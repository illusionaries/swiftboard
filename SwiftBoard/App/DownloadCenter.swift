import Foundation
import Observation
import SwiftUI
import SwiftBoardKit

/// Owns background downloads and the Quick Look preview state.
@MainActor
@Observable
final class DownloadCenter {
    struct State: Equatable {
        var progress: Double = 0
        var isDownloading = false
        var localURL: URL?
        var error: String?
    }

    private(set) var states: [String: State] = [:]
    var previewURL: URL?
    let root: URL

    private var tasks: [String: Task<Void, Never>] = [:]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        root = base.appendingPathComponent("SwiftBoard/Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func state(for content: CourseContent) -> State? {
        states[content.id]
    }

    func existingFile(for content: CourseContent, course: Course) -> URL? {
        guard let destination = destination(for: content, course: course) else { return nil }
        return FileManager.default.fileExists(atPath: destination.path) ? destination : nil
    }

    func download(content: CourseContent, course: Course, api: BlackboardClient) {
        guard content.file != nil, tasks[content.id] == nil else { return }
        states[content.id] = State(progress: 0, isDownloading: true)

        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let url = try await api.download(content: content, course: course, to: self.root) { progress in
                    Task { @MainActor in
                        guard var state = self.states[content.id] else { return }
                        state.progress = progress
                        self.states[content.id] = state
                    }
                }
                var state = self.states[content.id] ?? State()
                state.isDownloading = false
                state.progress = 1
                state.localURL = url
                state.error = nil
                self.states[content.id] = state
                self.previewURL = url
            } catch {
                var state = self.states[content.id] ?? State()
                state.isDownloading = false
                state.error = error.localizedDescription
                self.states[content.id] = state
            }
            self.tasks[content.id] = nil
        }
        tasks[content.id] = task
    }

    func preview(_ content: CourseContent, course: Course, api: BlackboardClient) {
        if let existing = existingFile(for: content, course: course) {
            previewURL = existing
            return
        }
        states[content.id] = states[content.id] ?? State()
        download(content: content, course: course, api: api)
    }

    func cancel(_ content: CourseContent) {
        tasks[content.id]?.cancel()
        tasks[content.id] = nil
        if var state = states[content.id] {
            state.isDownloading = false
            state.error = "已取消"
            states[content.id] = state
        }
    }

    func destination(for content: CourseContent, course: Course) -> URL? {
        guard let file = content.file else { return nil }
        return root
            .appendingPathComponent(sanitize(course.title), isDirectory: true)
            .appendingPathComponent(sanitize(file.name))
    }

    private func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "未命名" : String(cleaned.prefix(120))
    }
}
