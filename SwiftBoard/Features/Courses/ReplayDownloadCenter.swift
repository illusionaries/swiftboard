import Foundation
import Observation
import CommonCrypto
import AVFoundation
import SwiftBoardKit
#if os(iOS)
import BackgroundTasks
#endif

struct ReplayDownload: Identifiable, Codable, Hashable, Sendable {
    let videoID: String
    let courseTitle: String
    let title: String
    let teacher: String
    let time: String
    let directoryName: String
    let segmentDurations: [Double]
    let totalBytes: Int64
    let createdAt: Date

    var id: String { videoID }
    var duration: Double { segmentDurations.reduce(0, +) }
    var segmentCount: Int { segmentDurations.count }

    func segmentFileName(_ index: Int) -> String {
        String(format: "segment_%05d.ts", index)
    }

    var playlistText: String {
        let target = max(1, Int(ceil((segmentDurations.max() ?? 1).rounded(.up))))
        var lines = [
            "#EXTM3U",
            "#EXT-X-VERSION:3",
            "#EXT-X-TARGETDURATION:\(target)",
            "#EXT-X-MEDIA-SEQUENCE:0"
        ]
        for (index, duration) in segmentDurations.enumerated() {
            lines.append(String(format: "#EXTINF:%.3f,", duration))
            lines.append(segmentFileName(index))
        }
        lines.append("#EXT-X-ENDLIST")
        return lines.joined(separator: "\n")
    }
}

@MainActor
@Observable
final class ReplayDownloadCenter {
    enum DownloadState: Equatable, Sendable {
        case downloading(completed: Int, total: Int)
        case failed(String)
        case completed

        var isActive: Bool {
            if case .downloading = self { return true }
            return false
        }

        var progress: Double {
            guard case .downloading(let completed, let total) = self, total > 0 else { return 0 }
            return min(1, max(0, Double(completed) / Double(total)))
        }
    }

    private(set) var items: [ReplayDownload] = []
    private(set) var states: [String: DownloadState] = [:]

    private let root: URL
    private let indexURL: URL
    private var tasks: [String: Task<Void, Never>] = [:]
    private let fileManager = FileManager.default

    #if os(iOS)
    private static let backgroundTaskIdentifier = "blog.illusion.swiftboard.replay-download"
    private static var didRegisterContinuedProcessing = false
    private var activeDownloadTask: Task<Void, Never>?
    private var activeDownloadVideoID: String?
    private var backgroundProgress: Progress?
    #endif

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        root = base
            .appendingPathComponent("SwiftBoard", isDirectory: true)
            .appendingPathComponent("Replays", isDirectory: true)
        indexURL = root.appendingPathComponent("index.json")
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = root
        try? mutableRoot.setResourceValues(values)
        loadIndex()
        #if os(iOS)
        if #available(iOS 26.0, *) {
            registerContinuedProcessing()
        }
        #endif
    }

    // MARK: - Queries

    func item(for videoID: String) -> ReplayDownload? {
        items.first { $0.videoID == videoID }
    }

    func state(for videoID: String) -> DownloadState? {
        if let state = states[videoID] { return state }
        return item(for: videoID) == nil ? nil : .completed
    }

    func directory(for download: ReplayDownload) -> URL {
        root.appendingPathComponent(download.directoryName, isDirectory: true)
    }

    func segmentsDirectory(for download: ReplayDownload) -> URL {
        directory(for: download).appendingPathComponent("segments", isDirectory: true)
    }

    func exportedFileURL(for download: ReplayDownload) -> URL {
        #if os(macOS)
        return directory(for: download).appendingPathComponent("export.mp4")
        #else
        return directory(for: download).appendingPathComponent("export.ts")
        #endif
    }

    /// macOS exports a real MP4 via AVFoundation. iOS's AVFoundation cannot
    /// open MPEG-TS directly, so it exports the merged TS file instead.
    func exportVideo(_ download: ReplayDownload) async throws -> URL {
        let finalURL = exportedFileURL(for: download)
        if fileManager.fileExists(atPath: finalURL.path) {
            let existingSize = (try? finalURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if existingSize > 0 {
                return finalURL
            }
        }

        let temporaryTS = fileManager.temporaryDirectory
            .appendingPathComponent("swiftboard-\(UUID().uuidString).ts")
        try? fileManager.removeItem(at: temporaryTS)
        do {
            try mergeSegments(download, to: temporaryTS)
        } catch {
            try? fileManager.removeItem(at: temporaryTS)
            throw error
        }

        #if os(macOS)
        defer { try? fileManager.removeItem(at: temporaryTS) }
        let asset = AVURLAsset(url: temporaryTS)
        let temporaryMP4 = fileManager.temporaryDirectory
            .appendingPathComponent("swiftboard-\(UUID().uuidString).mp4")
        defer { try? fileManager.removeItem(at: temporaryMP4) }

        var lastError: Error?
        for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality] {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            guard session.supportedFileTypes.contains(.mp4) else { continue }
            session.shouldOptimizeForNetworkUse = true
            do {
                try await session.export(to: temporaryMP4, as: .mp4)
                let size = (try? temporaryMP4.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                guard size > 0 else { throw ReplayDownloadError.exportFailed }
                try? fileManager.removeItem(at: finalURL)
                try fileManager.moveItem(at: temporaryMP4, to: finalURL)
                return finalURL
            } catch {
                lastError = error
                try? fileManager.removeItem(at: temporaryMP4)
            }
        }
        throw lastError ?? ReplayDownloadError.exportFailed
        #else
        try? fileManager.removeItem(at: finalURL)
        try fileManager.moveItem(at: temporaryTS, to: finalURL)
        #if os(iOS)
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: finalURL.path
        )
        #endif
        return finalURL
        #endif
    }

    private func mergeSegments(_ download: ReplayDownload, to url: URL) throws {
        let directory = segmentsDirectory(for: download)
        guard fileManager.createFile(atPath: url.path, contents: nil) else {
            throw ReplayDownloadError.exportFailed
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        for index in 0..<download.segmentCount {
            try Task.checkCancellation()
            let segmentURL = directory.appendingPathComponent(download.segmentFileName(index))
            guard fileManager.fileExists(atPath: segmentURL.path) else {
                throw ReplayDownloadError.noSegments
            }
            let data = try Data(contentsOf: segmentURL, options: .mappedIfSafe)
            try handle.write(contentsOf: data)
        }
    }

    // MARK: - Download

    func startDownload(video: CourseVideo, course: Course, service: CourseVideoService) {
        guard item(for: video.id) == nil, state(for: video.id)?.isActive != true else { return }
        states[video.id] = .downloading(completed: 0, total: 0)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performDownload(video: video, course: course, service: service)
        }
        tasks[video.id] = task

        #if os(iOS)
        if activeDownloadTask == nil {
            activeDownloadTask = task
            activeDownloadVideoID = video.id
            if #available(iOS 26.0, *) {
                submitContinuedProcessing(for: video)
            }
        }
        #endif
    }

    func cancel(videoID: String) {
        tasks[videoID]?.cancel()
        tasks[videoID] = nil
        states[videoID] = nil
        try? fileManager.removeItem(at: root.appendingPathComponent(stableName(videoID)))
    }

    func delete(_ download: ReplayDownload) {
        tasks[download.videoID]?.cancel()
        tasks[download.videoID] = nil
        try? fileManager.removeItem(at: directory(for: download))
        items.removeAll { $0.videoID == download.videoID }
        states[download.videoID] = nil
        saveIndex()
    }

    func deleteAll() {
        for task in tasks.values { task.cancel() }
        tasks.removeAll()
        states.removeAll()
        items.removeAll()
        try? fileManager.removeItem(at: root)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        saveIndex()
    }

    private func performDownload(video: CourseVideo, course: Course, service: CourseVideoService) async {
        let videoID = video.id
        defer {
            tasks[videoID] = nil
            #if os(iOS)
            if activeDownloadVideoID == videoID {
                activeDownloadTask = nil
                activeDownloadVideoID = nil
                backgroundProgress = nil
            }
            #endif
        }

        do {
            let prepared = try await service.prepare(video: video)
            var plan = try DownloadPlan(prepared: prepared)
            #if DEBUG
            if let raw = ProcessInfo.processInfo.environment["SWIFTBOARD_DOWNLOAD_LIMIT"],
               let limit = Int(raw), limit > 0, limit < plan.segments.count {
                plan = DownloadPlan(segments: Array(plan.segments.prefix(limit)))
            }
            #endif
            guard !plan.segments.isEmpty else { throw ReplayDownloadError.noSegments }
            try Task.checkCancellation()

            let directory = root.appendingPathComponent(stableName(video.id), isDirectory: true)
            let segmentsDirectory = directory.appendingPathComponent("segments", isDirectory: true)
            try fileManager.createDirectory(at: segmentsDirectory, withIntermediateDirectories: true)
            #if os(iOS)
            try? fileManager.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: segmentsDirectory.path
            )
            #endif

            var completed = 0
            for index in plan.segments.indices {
                let path = segmentsDirectory.appendingPathComponent(String(format: "segment_%05d.ts", index))
                if fileManager.fileExists(atPath: path.path) {
                    completed += 1
                }
            }
            let total = plan.segments.count
            states[videoID] = .downloading(completed: completed, total: total)
            #if os(iOS)
            backgroundProgress?.totalUnitCount = Int64(total)
            backgroundProgress?.completedUnitCount = Int64(completed)
            #endif

            let batchSize = 4
            var start = 0
            while start < plan.segments.count {
                try Task.checkCancellation()
                let end = min(plan.segments.count, start + batchSize)
                let batch = Array(start..<end)
                try await withThrowingTaskGroup(of: Int.self) { group in
                    for index in batch {
                        let path = segmentsDirectory.appendingPathComponent(String(format: "segment_%05d.ts", index))
                        guard !fileManager.fileExists(atPath: path.path) else { continue }
                        let segment = plan.segments[index]
                        group.addTask {
                            try await Self.downloadSegment(segment, index: index, destination: path)
                            return index
                        }
                    }
                    for try await _ in group {
                        completed += 1
                        states[videoID] = .downloading(completed: completed, total: total)
                        #if os(iOS)
                        backgroundProgress?.completedUnitCount = Int64(completed)
                        #endif
                    }
                }
                start = end
            }

            try Task.checkCancellation()
            let durations = plan.segments.map(\.duration)
            let totalBytes = plan.segments.indices.reduce(Int64(0)) { partial, index in
                let path = segmentsDirectory.appendingPathComponent(String(format: "segment_%05d.ts", index))
                let attributes = try? fileManager.attributesOfItem(atPath: path.path)
                let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                return partial + size
            }
            let download = ReplayDownload(
                videoID: video.id,
                courseTitle: course.title,
                title: prepared.title,
                teacher: prepared.teacher ?? video.teacher,
                time: video.time,
                directoryName: stableName(video.id),
                segmentDurations: durations,
                totalBytes: totalBytes,
                createdAt: Date()
            )
            items.removeAll { $0.videoID == video.id }
            items.insert(download, at: 0)
            states[videoID] = .completed
            saveIndex()
        } catch is CancellationError {
            states[videoID] = nil
        } catch {
            states[videoID] = .failed(error.localizedDescription)
        }
    }

    nonisolated private static func downloadSegment(
        _ segment: DownloadSegment,
        index: Int,
        destination: URL
    ) async throws -> Int {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                var request = URLRequest(url: segment.url)
                request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse,
                   http.statusCode != 200, http.statusCode != 206 {
                    throw ReplayDownloadError.server("HTTP \(http.statusCode)")
                }
                var output = data
                if let key = segment.key, !key.isEmpty {
                    output = try AES128CBC.decrypt(data, key: key, iv: segment.iv ?? Data(count: 16))
                }
                try output.write(to: destination, options: .atomic)
                return output.count
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(600))
                }
            }
        }
        throw lastError ?? ReplayDownloadError.downloadFailed
    }

    // MARK: - Background continuation

    #if os(iOS)
    @available(iOS 26.0, *)
    private func registerContinuedProcessing() {
        guard !Self.didRegisterContinuedProcessing else { return }
        Self.didRegisterContinuedProcessing = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskIdentifier, using: nil) { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor [weak self] in
                await self?.handleContinuedProcessing(task)
            }
        }
    }

    @available(iOS 26.0, *)
    private func submitContinuedProcessing(for video: CourseVideo) {
        let request = BGContinuedProcessingTaskRequest(
            identifier: Self.backgroundTaskIdentifier,
            title: "正在下载课程回放",
            subtitle: video.title
        )
        request.strategy = .queue
        do {
            try BGTaskScheduler.shared.submit(request)
            #if DEBUG
            print("[background] submitted continued processing")
            #endif
        } catch {
            #if DEBUG
            print("[background] submit failed: \(error)")
            #endif
        }
    }

    @available(iOS 26.0, *)
    private func handleContinuedProcessing(_ task: BGContinuedProcessingTask) async {
        guard let videoID = activeDownloadVideoID, let downloadTask = activeDownloadTask else {
            task.setTaskCompleted(success: false)
            return
        }
        backgroundProgress = task.progress
        if let state = states[videoID], case .downloading(let completed, let total) = state, total > 0 {
            task.progress.totalUnitCount = Int64(total)
            task.progress.completedUnitCount = Int64(completed)
        }
        task.expirationHandler = {
            downloadTask.cancel()
        }
        await downloadTask.value
        let success = item(for: videoID) != nil
        backgroundProgress = nil
        task.setTaskCompleted(success: success)
    }
    #endif

    // MARK: - Persistence

    private func loadIndex() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([ReplayDownload].self, from: data) else {
            return
        }
        items = decoded
            .filter { fileManager.fileExists(atPath: segmentsDirectory(for: $0).path) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func saveIndex() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private func stableName(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(format: "replay-%016llx", hash)
    }
}

// MARK: - Plan

private struct DownloadSegment: Sendable {
    let url: URL
    let duration: Double
    let key: Data?
    let iv: Data?
}

private struct DownloadPlan {
    let segments: [DownloadSegment]

    init(segments: [DownloadSegment]) {
        self.segments = segments
    }

    init(prepared: PreparedVideo) throws {
        let playlist = prepared.playlist
        var mediaSequence = 0
        if let match = playlist.videoFirstMatch(#"(?i)#EXT-X-MEDIA-SEQUENCE:(\d+)"#),
           match.count > 1 {
            mediaSequence = Int(match[1]) ?? 0
        }

        var keyIndex: Int?
        var keyIV: Data?
        var pendingDuration = 0.0
        var result: [DownloadSegment] = []

        for rawLine in playlist.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("#EXT-X-KEY") {
                if line.uppercased().contains("METHOD=NONE") {
                    keyIndex = nil
                    keyIV = nil
                } else if let match = line.videoFirstMatch(#"(?i)URI="([^"]*)""#), match.count > 1,
                          let index = Int(URL(string: match[1])?.lastPathComponent ?? "") {
                    keyIndex = index
                }
                if let match = line.videoFirstMatch(#"(?i)IV=0x([0-9A-Fa-f]+)"#), match.count > 1 {
                    keyIV = Data(hexString: match[1])
                }
            } else if line.hasPrefix("#EXTINF") {
                if let match = line.videoFirstMatch(#"(?i)#EXTINF:([0-9.]+)"#), match.count > 1 {
                    pendingDuration = Double(match[1]) ?? 0
                }
            } else if !line.isEmpty, !line.hasPrefix("#") {
                guard let url = URL(string: line) else {
                    throw ReplayDownloadError.invalidPlaylist
                }
                let key: Data?
                if let keyIndex {
                    guard prepared.keys.indices.contains(keyIndex) else {
                        throw ReplayDownloadError.invalidPlaylist
                    }
                    key = prepared.keys[keyIndex]
                } else {
                    key = nil
                }
                let iv = key == nil ? nil : (keyIV ?? Self.sequenceIV(mediaSequence + result.count))
                result.append(
                    DownloadSegment(
                        url: url,
                        duration: pendingDuration,
                        key: key,
                        iv: iv
                    )
                )
                pendingDuration = 0
            }
        }
        guard !result.isEmpty else { throw ReplayDownloadError.noSegments }
        segments = result
    }

    private static func sequenceIV(_ value: Int) -> Data {
        var number = UInt64(max(0, value)).bigEndian
        var data = Data(count: 16)
        withUnsafeBytes(of: &number) { bytes in
            data.replaceSubrange(8..<16, with: bytes)
        }
        return data
    }

}

private enum ReplayDownloadError: Error, LocalizedError {
    case invalidPlaylist
    case noSegments
    case downloadFailed
    case decryptFailed
    case exportFailed
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidPlaylist: "回放下载信息不完整"
        case .noSegments: "没有可下载的分片"
        case .downloadFailed: "分片下载失败"
        case .decryptFailed: "回放解密失败"
        case .exportFailed: "MP4 导出失败"
        case .server(let message): "回放下载失败（\(message)）"
        }
    }
}

// MARK: - Crypto

private enum AES128CBC {
    static func decrypt(_ data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128 else {
            throw ReplayDownloadError.decryptFailed
        }
        let outputCapacity = data.count + kCCBlockSizeAES128
        let inputLength = data.count
        let keyLength = key.count
        var output = Data(count: outputCapacity)
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            keyLength,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            inputLength,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else {
            throw ReplayDownloadError.decryptFailed
        }
        output.removeSubrange(outputLength..<output.count)
        return output
    }
}

private extension String {
    func videoFirstMatch(_ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, range: range) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: self) else { return "" }
            return String(self[range])
        }
    }
}

private extension Data {
    init(hexString: String) {
        var value = hexString
        if value.count % 2 != 0 {
            value = "0" + value
        }
        var bytes: [UInt8] = []
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            if let byte = UInt8(value[index..<next], radix: 16) {
                bytes.append(byte)
            }
            index = next
        }
        if bytes.count < 16 {
            bytes = Array(repeating: 0, count: 16 - bytes.count) + bytes
        } else if bytes.count > 16 {
            bytes = Array(bytes.suffix(16))
        }
        self.init(bytes)
    }
}
