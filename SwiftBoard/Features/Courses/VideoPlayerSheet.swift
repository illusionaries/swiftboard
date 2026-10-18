import SwiftUI
import AVKit
import AVFoundation
import Combine
import SwiftBoardKit
#if os(iOS)
import AVFAudio
#endif
#if os(macOS)
import AppKit
#endif

struct VideoPlayerSheet: View {
    private let video: CourseVideo?
    private let course: Course?
    private let offline: ReplayDownload?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var controller = VideoPlayerController()
    @State private var isFullscreen = false

    init(video: CourseVideo, course: Course) {
        self.video = video
        self.course = course
        self.offline = nil
    }

    init(download: ReplayDownload) {
        self.video = nil
        self.course = nil
        self.offline = download
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                playerArea
                infoArea
                Spacer(minLength: 0)
            }
            .background(Theme.canvas)
            .navigationTitle("回放")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if let video, let course, offline == nil {
                    ToolbarItem(placement: .primaryAction) {
                        downloadButton(video: video, course: course)
                    }
                }
                #if os(macOS)
                if controller.state == .ready {
                    ToolbarItem(placement: .primaryAction) {
                        Button("全屏") {
                            NSApp.keyWindow?.toggleFullScreen(nil)
                        }
                    }
                }
                #endif
            }
        }
        .task { await load() }
        #if os(iOS)
        .fullScreenCover(isPresented: $isFullscreen) {
            if let player = controller.player {
                FullscreenVideoPlayer(player: player)
            }
        }
        #endif
        .onDisappear {
            controller.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                controller.pause()
            }
        }
        #if DEBUG
        .onChange(of: controller.state) { _, state in
            if state == .ready,
               ProcessInfo.processInfo.environment["SWIFTBOARD_FULLSCREEN"] == "1" {
                isFullscreen = true
            }
        }
        #endif
        #if os(macOS)
        .frame(minWidth: 900, minHeight: 640)
        #endif
    }

    private var playerArea: some View {
        ZStack {
            Color.black
            switch controller.state {
            case .loading:
                VStack(spacing: 10) {
                    ProgressView().tint(.white)
                    Text("正在准备回放…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 30, weight: .light))
                    Text(message)
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("重试") {
                        Task { await load() }
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .foregroundStyle(.white)
                .padding(24)
                .frame(maxWidth: 420)
            case .ready:
                if let player = controller.player {
                    #if os(macOS)
                    MacVideoPlayer(player: player)
                    #else
                    VideoPlayer(player: player)
                        .overlay(alignment: .bottomTrailing) {
                            Button {
                                isFullscreen = true
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .padding(8)
                                    .background(.black.opacity(0.55), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .padding(12)
                            .accessibilityLabel("全屏播放")
                        }
                    #endif
                }
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .background(Color.black)
    }

    private var infoArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let courseTitle, !courseTitle.isEmpty {
                Text(courseTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }
            Text(displayTitle)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 14) {
                if !displayTeacher.isEmpty {
                    Label(displayTeacher, systemImage: "person")
                }
                if !displayTime.isEmpty {
                    Label(displayTime, systemImage: "clock")
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .lineLimit(1)

            Text(offline == nil
                 ? "回放由北大在线课堂提供，仅对已选课同学开放，请勿传播。"
                 : "已下载到本机，仅限个人学习使用，请勿传播。")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayTitle: String {
        offline?.title ?? video?.title ?? "课程回放"
    }

    private var displayTeacher: String {
        offline?.teacher ?? video?.teacher ?? ""
    }

    private var displayTime: String {
        offline?.time ?? video?.time ?? ""
    }

    private var courseTitle: String? {
        offline?.courseTitle ?? course?.title
    }

    @ViewBuilder
    private func downloadButton(video: CourseVideo, course: Course) -> some View {
        if model.replayDownloads.item(for: video.id) != nil {
            Label("已下载", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Theme.accent)
        } else if let state = model.replayDownloads.state(for: video.id) {
            switch state {
            case .downloading(let completed, let total):
                Button {
                    model.replayDownloads.cancel(videoID: video.id)
                } label: {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini)
                        Text(total > 0 ? "\(Int(Double(completed) / Double(total) * 100))%" : "下载中")
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                .accessibilityLabel("取消下载")
            case .failed:
                Button {
                    startDownload(video: video, course: course)
                } label: {
                    Label("重试下载", systemImage: "arrow.clockwise")
                }
            case .completed:
                Label("已下载", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        } else {
            Button {
                startDownload(video: video, course: course)
            } label: {
                Label("下载", systemImage: "arrow.down.circle")
            }
            .accessibilityHint("下载后在「我的 → 离线回放」中观看")
        }
    }

    private func startDownload(video: CourseVideo, course: Course) {
        model.replayDownloads.startDownload(
            video: video,
            course: course,
            service: model.client.blackboard.videos
        )
    }

    private func load() async {
        if let offline {
            await controller.loadLocal(
                playlist: offline.playlistText,
                segmentsDirectory: model.replayDownloads.segmentsDirectory(for: offline)
            )
        } else if let video {
            if let downloaded = model.replayDownloads.item(for: video.id) {
                await controller.loadLocal(
                    playlist: downloaded.playlistText,
                    segmentsDirectory: model.replayDownloads.segmentsDirectory(for: downloaded)
                )
            } else {
                await controller.load(video: video, service: model.client.blackboard.videos)
                #if DEBUG
                if ProcessInfo.processInfo.environment["SWIFTBOARD_DOWNLOAD"] == "1",
                   let course,
                   ProcessInfo.processInfo.environment["SWIFTBOARD_VIDEO"] == "1" {
                    startDownload(video: video, course: course)
                }
                #endif
            }
        }
        if scenePhase != .active {
            controller.pause()
        }
    }
}

@MainActor
@Observable
final class VideoPlayerController {
    enum State: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var state: State = .loading
    private(set) var player: AVPlayer?
    private var item: AVPlayerItem?
    private var videoServer: LocalVideoServer?
    private var statusCancellable: AnyCancellable?
    private var shouldAutoplay = true

    func load(video: CourseVideo, service: CourseVideoService) async {
        stop()
        shouldAutoplay = true
        state = .loading

        do {
            let prepared = try await service.prepare(video: video)
            try await start(playlist: prepared.playlist, segmentsDirectory: nil, keys: prepared.keys)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func loadLocal(playlist: String, segmentsDirectory: URL) async {
        stop()
        shouldAutoplay = true
        state = .loading

        do {
            try await start(playlist: playlist, segmentsDirectory: segmentsDirectory, keys: [])
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private func start(playlist: String, segmentsDirectory: URL?, keys: [Data]) async throws {
        let server = LocalVideoServer(keys: keys, segmentsDirectory: segmentsDirectory)
        let port = try await server.start()
        self.videoServer = server

        var text = playlist
        if !keys.isEmpty {
            text = text.replacingOccurrences(
                of: "swiftboard-key://key/",
                with: "http://127.0.0.1:\(port)/key/"
            )
        }
        server.setPlaylist(text)

        guard let url = URL(string: "http://127.0.0.1:\(port)/playlist.m3u8") else {
            throw VideoError.invalidPlaylist
        }
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        player.automaticallyWaitsToMinimizeStalling = true

        self.item = item
        self.player = player

        #if os(iOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif

        statusCancellable = item.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.state = .ready
                    if self.shouldAutoplay {
                        self.player?.play()
                    }
                case .failed:
                    self.state = .failed(item.error?.localizedDescription ?? "回放加载失败")
                default:
                    break
                }
            }
        if shouldAutoplay {
            player.play()
        }
    }

    func pause() {
        shouldAutoplay = false
        player?.pause()
    }

    func stop() {
        player?.pause()
        statusCancellable?.cancel()
        statusCancellable = nil
        player = nil
        item = nil
        videoServer?.stop()
        videoServer = nil
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

#if os(macOS)
private struct MacVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}
#endif


#if os(iOS)
private struct FullscreenVideoPlayer: View {
    let player: AVPlayer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(18)
            .accessibilityLabel("退出全屏")
        }
        .statusBarHidden()
    }
}
#endif
