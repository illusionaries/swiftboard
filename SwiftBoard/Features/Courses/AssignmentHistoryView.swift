import SwiftUI
import SwiftBoardKit
import QuickLook
#if os(macOS)
import QuickLookUI
#endif

struct AssignmentHistoryView: View {
    let course: Course
    let content: CourseContent

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var attempts: [AssignmentAttempt]?
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var downloadingFileID: String?
    @State private var previewURL: URL?
    @State private var downloadError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if isLoading && attempts == nil {
                        HStack(spacing: 9) {
                            ProgressView().controlSize(.small)
                            Text("正在读取提交记录…")
                                .font(.subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 24)
                    } else if let loadError {
                        ErrorBanner(message: loadError) {
                            Task { await load(force: true) }
                        }
                    } else if let attempts, attempts.isEmpty {
                        EmptyStateView(
                            symbol: "tray",
                            title: "还没有提交记录",
                            message: "提交作业后，上传的文件和老师的反馈会显示在这里。通过外部工具提交的作业可能不显示。"
                        )
                    } else if let attempts {
                        ForEach(Array(attempts.reversed().enumerated()), id: \.element.id) { index, attempt in
                            attemptCard(attempt, number: attempts.count - index)
                        }
                        Text("共 \(attempts.count) 次提交 · 数据来自教学网")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 2)
                    }

                    if let downloadError {
                        ErrorBanner(message: downloadError)
                    }
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas)
            .navigationTitle("提交记录")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await load(force: true) }
                    } label: {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                    .help("刷新提交记录")
                }
            }
        }
        .task { await load() }
        .refreshable { await load(force: true) }
        .quickLookPreview($previewURL)
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 600)
        #endif
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            CourseGlyph(course: course, size: 40)
            VStack(alignment: .leading, spacing: 5) {
                Text(content.title)
                    .font(.system(size: 20, weight: .semibold))
                    .lineLimit(3)
                Text(course.title)
                    .font(.caption)
                    .foregroundStyle(Theme.courseColor(course.colorIndex))
                    .lineLimit(1)
                HStack(spacing: 7) {
                    if let due = content.dueDate {
                        Chip(text: SBDate.dueDescription(due), tint: due < Date() ? Theme.muted : Color(hex: 0xA06A24))
                    }
                    if let points = content.possiblePoints, points > 0 {
                        Chip(text: "\(formatScore(points)) 分", tint: Theme.accent)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func attemptCard(_ attempt: AssignmentAttempt, number: Int) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("第 \(number) 次提交")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                statusChip(attempt)
            }

            HStack(spacing: 9) {
                if let submittedAt = attempt.submittedAt {
                    Label("\(SBDate.fullDate(submittedAt)) \(SBDate.time(submittedAt))", systemImage: "clock")
                } else {
                    Label("提交时间未知", systemImage: "clock")
                }
                if let size = attempt.submissionSize, size > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                }
                Spacer(minLength: 4)
                if let score = attempt.score {
                    Text("\(formatScore(score)) / \(formatScore(content.possiblePoints ?? 0))")
                        .foregroundStyle(.primary)
                        .monospacedDigit()
                }
            }
            .font(.caption2)
            .foregroundStyle(Theme.muted)

            if attempt.files.isEmpty {
                Text("没有找到提交文件，可能通过其他方式提交。")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            } else {
                VStack(spacing: 8) {
                    ForEach(attempt.files) { file in
                        fileRow(file)
                    }
                }
            }

            if attempt.hasFeedback, let feedback = attempt.feedbackHTML {
                DisclosureGroup {
                    Text(feedback.htmlToPlainText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 5)
                        .textSelection(.enabled)
                } label: {
                    Label("教师反馈", systemImage: "text.bubble")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
                .tint(Theme.accent)
            }
        }
        .cardSurface(padding: 16, radius: 18)
    }

    private func fileRow(_ file: AssignmentSubmittedFile) -> some View {
        let info = fileSymbol(for: file.name)
        return HStack(spacing: 10) {
            IconTile(symbol: info.0, tint: info.1, size: 30)
            Text(file.name)
                .font(.caption)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 6)
            if downloadingFileID == file.id {
                ProgressView().controlSize(.mini)
            } else {
                Button {
                    preview(file)
                } label: {
                    Label("预览", systemImage: "eye")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .disabled(downloadingFileID != nil)
            }
        }
        .padding(10)
        .background(Theme.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusChip(_ attempt: AssignmentAttempt) -> some View {
        let text: String
        let tint: Color
        switch attempt.status {
        case "Completed":
            text = "已评分"; tint = Color(hex: 0x3F7A5C)
        case "NeedsGrading":
            text = "待评分"; tint = Color(hex: 0xA06A24)
        case "NotAttempted":
            text = "未提交"; tint = Theme.muted
        default:
            text = attempt.status?.isEmpty == false ? attempt.status! : "已提交"
            tint = Theme.muted
        }
        return Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.11), in: Capsule())
    }

    private func preview(_ file: AssignmentSubmittedFile) {
        guard downloadingFileID == nil else { return }
        downloadingFileID = file.id
        downloadError = nil
        Task {
            do {
                let directory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("SwiftBoardSubmitted", isDirectory: true)
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let destination = directory.appendingPathComponent(sanitize(file.name))
                try await model.client.blackboard.downloadFile(from: file.url, to: destination)
                previewURL = destination
            } catch {
                if let api = error as? APIError, case .notAuthenticated = api {
                    model.expireSession()
                }
                downloadError = error.localizedDescription
            }
            downloadingFileID = nil
        }
    }

    private func load(force: Bool = false) async {
        if !force, attempts != nil { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        do {
            var columnID = content.gradeColumnID
            if columnID == nil {
                let columns = try await model.client.blackboard.gradeColumns(courseID: content.courseID)
                columnID = columns.first(where: { $0.contentID == content.id })?.id
            }
            guard let columnID else {
                loadError = "无法定位这项作业的成绩项，暂时不能读取提交记录。"
                return
            }
            attempts = try await model.client.blackboard.assignments.history(
                courseID: content.courseID,
                contentID: content.id,
                columnID: columnID
            )
            #if DEBUG
            if ProcessInfo.processInfo.environment["SWIFTBOARD_HISTORY_PREVIEW"] == "1",
               previewURL == nil,
               let firstFile = attempts?.first?.files.first {
                preview(firstFile)
            }
            #endif
        } catch {
            if let api = error as? APIError, case .notAuthenticated = api {
                model.expireSession()
            }
            loadError = error.localizedDescription
        }
    }

    private func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "submission" : String(cleaned.prefix(160))
    }

    private func formatScore(_ value: Double) -> String {
        abs(value.rounded() - value) < 0.001 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
