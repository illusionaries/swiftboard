import SwiftUI
import SwiftBoardKit

struct ContentDetailView: View {
    let course: Course
    let content: CourseContent

    @Environment(AppModel.self) private var model
    @Environment(DownloadCenter.self) private var downloads
    @Environment(\.openURL) private var openURL
    @State private var activeSheet: ActiveSheet?
    @State private var assignmentAttachments: [AssignmentAttachment]?
    @State private var contentFiles: [ContentFile] = []

    private enum ActiveSheet: String, Identifiable {
        case submit
        case history

        var id: String { rawValue }
    }

    var body: some View {
        Group {
            if content.isContainer {
                containerBody
            } else if content.hasBody {
                documentBody
            } else {
                plainBody
            }
        }
        .background(Theme.canvas)
        .navigationTitle(content.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: content.id) {
            await loadAssignmentAttachments()
        }
        .task(id: content.id) {
            await loadContentFiles()
        }
        #if DEBUG
        .onAppear {
            if ProcessInfo.processInfo.environment["SWIFTBOARD_HISTORY"] == "1", activeSheet == nil {
                activeSheet = .history
            }
            if ProcessInfo.processInfo.environment["SWIFTBOARD_SUBMIT"] == "1", activeSheet == nil {
                activeSheet = .submit
            }
        }
        #endif
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .submit:
                AssignmentSubmissionView(course: course, content: content) {
                    model.assignmentSubmitted(courseID: course.id)
                }
                .environment(model)
                .environment(downloads)
            case .history:
                AssignmentHistoryView(course: course, content: content)
                    .environment(model)
                    .environment(downloads)
            }
        }
    }

    // MARK: - Layouts

    private var documentBody: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                headerCard
                actions
                if let assignmentAttachments, !assignmentAttachments.isEmpty {
                    AssignmentAttachmentsView(attachments: assignmentAttachments, course: course)
                }
                contentFilesSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 14)

            Divider()

            HTMLView(html: content.bodyHTML)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var plainBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                actions
                if let assignmentAttachments, !assignmentAttachments.isEmpty {
                    AssignmentAttachmentsView(attachments: assignmentAttachments, course: course)
                }
                contentFilesSection
                metadataCard
                if content.file != nil {
                    hintCard
                }
                Button {
                    openURL(pageURL)
                } label: {
                    Label("在教学网中打开", systemImage: "arrow.up.right.square")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var containerBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                headerCard
                if content.hasBody {
                    HTMLView(html: content.bodyHTML)
                        .frame(height: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                ContentChildrenList(course: course, parentID: content.id)
            }
            .padding(20)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var contentFileAttachments: [AssignmentAttachment] {
        contentFiles.compactMap { file in
            guard let url = file.url else { return nil }
            return AssignmentAttachment(name: file.name, url: url)
        }
    }

    @ViewBuilder
    private var contentFilesSection: some View {
        if !contentFileAttachments.isEmpty {
            AssignmentAttachmentsView(
                attachments: contentFileAttachments,
                course: course,
                title: "课件 / 附件"
            )
        }
    }

    private func loadContentFiles() async {
        guard content.kind == .document, let folderID = content.parentID else { return }
        contentFiles = []
        guard let attachments = try? await model.client.blackboard.contentAttachments(
            courseID: content.courseID,
            folderID: folderID
        ) else { return }
        contentFiles = attachments[content.id] ?? []
    }

    private func loadAssignmentAttachments() async {
        guard content.kind == .assignment else { return }
        guard let form = try? await model.client.blackboard.assignments.uploadForm(
            courseID: content.courseID,
            contentID: content.id
        ) else { return }
        assignmentAttachments = form.attachments
        #if DEBUG
        if ProcessInfo.processInfo.environment["SWIFTBOARD_ATTACHMENT_PREVIEW"] == "1",
           let first = form.attachments.first {
            downloads.preview(first, course: course, api: model.client.blackboard)
        }
        #endif
    }

    // MARK: - Header

    private var headerCard: some View {
        HStack(alignment: .top, spacing: 14) {
            IconTile(symbol: symbol, tint: tint, size: 48)

            VStack(alignment: .leading, spacing: 6) {
                Text(content.title)
                    .font(.system(size: 21, weight: .semibold))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 8) {
                    Text(course.title)
                        .font(.caption)
                        .foregroundStyle(Theme.courseColor(course.colorIndex))
                        .lineLimit(1)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Text(kindLabel)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }

                HStack(spacing: 8) {
                    if let due = content.dueDate {
                        Chip(text: SBDate.dueDescription(due), tint: dueTint(due))
                    }
                    if let points = content.possiblePoints, points > 0 {
                        Chip(text: "\(formatScore(points)) 分", tint: Theme.accent)
                    }
                    if content.kind == .assignment, let limit = content.attemptLimit {
                        if limit == 0 {
                            Chip(text: "不限次数", tint: Theme.muted)
                        } else {
                            Chip(text: limit == 1 ? "仅一次提交" : "最多 \(limit) 次", tint: Theme.accent)
                        }
                    }
                    if let file = content.file {
                        Chip(text: fileExtension(file.name), tint: Theme.muted)
                    }
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 0)
        }
        .cardSurface(padding: 16, radius: 18)
    }

    // MARK: - Actions

    @ViewBuilder
    private var actions: some View {
        if let file = content.file {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        downloads.preview(content, course: course, api: model.client.blackboard)
                    } label: {
                        Label("预览文件", systemImage: "eye")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)

                    if let url = file.url {
                        Button {
                            openURL(url)
                        } label: {
                            Label("浏览器", systemImage: "safari")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .background(Theme.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.primary)
                    }
                }

                if let state = downloads.state(for: content), state.isDownloading {
                    VStack(spacing: 5) {
                        ProgressView(value: state.progress)
                            .tint(Theme.accent)
                        HStack {
                            Text("正在下载 \(file.name)")
                                .lineLimit(1)
                            Spacer()
                            Text("\(Int(state.progress * 100))%")
                                .monospacedDigit()
                        }
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                    }
                    .padding(.top, 2)
                } else if let state = downloads.state(for: content), let error = state.error {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red.opacity(0.85))
                } else if let url = downloads.existingFile(for: content, course: course) {
                    HStack(spacing: 10) {
                        ShareLink(item: url) {
                            Label("分享 / 保存", systemImage: "square.and.arrow.up")
                                .font(.caption.weight(.medium))
                        }
                        .foregroundStyle(Theme.accent)
                        Spacer()
                        Text("已下载")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
        } else if content.kind == .assignment {
            VStack(spacing: 9) {
                Button {
                    activeSheet = .submit
                } label: {
                    Label("提交作业", systemImage: "paperplane.fill")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Button {
                        activeSheet = .history
                    } label: {
                        Label("提交记录", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)

                    Button {
                        openURL(pageURL)
                    } label: {
                        Label("教学网", systemImage: "safari")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }
            }
        } else if let url = content.externalURL, content.kind == .link {
            Button {
                openURL(url)
            } label: {
                Label("打开链接", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
    }

    private var hintCard: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: "arrow.down.circle", tint: Theme.accent, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text("下载后可离线查看")
                    .font(.subheadline.weight(.medium))
                Text("文件保存在本机，可用系统预览打开，或通过分享面板存到「文件」App。")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Theme.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.10), lineWidth: 0.8)
        )
    }

    private var metadataCard: some View {
        VStack(spacing: 0) {
            metaRow("类型", kindLabel)
            if let file = content.file {
                Divider().padding(.leading, 16)
                metaRow("文件名", file.name)
                Divider().padding(.leading, 16)
                metaRow("格式", fileExtension(file.name).uppercased())
            }
            if let due = content.dueDate {
                Divider().padding(.leading, 16)
                metaRow("截止时间", "\(SBDate.fullDate(due)) \(SBDate.time(due))")
            }
            if let points = content.possiblePoints, points > 0 {
                Divider().padding(.leading, 16)
                metaRow("分值", "\(formatScore(points)) 分")
            }
            if let external = content.externalURL, content.kind == .link {
                Divider().padding(.leading, 16)
                metaRow("链接", external.absoluteString)
            }
        }
        .cardSurface(padding: 0, radius: 16)
    }

    private func metaRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Helpers

    private var pageURL: URL {
        if content.kind == .link, let url = content.externalURL { return url }
        return model.client.blackboard.contentPageURL(course: course, content: content)
    }

    private var symbolAndTint: (String, Color) {
        if content.kind == .file, let name = content.file?.name {
            return fileSymbol(for: name)
        }
        return (content.kind.symbol, content.kind.tint)
    }

    private var symbol: String { symbolAndTint.0 }
    private var tint: Color { symbolAndTint.1 }

    private var kindLabel: String {
        switch content.kind {
        case .folder: "文件夹"
        case .file: "文件"
        case .document: "课程页面"
        case .assignment: "作业"
        case .test: "在线测试"
        case .link: "外部链接"
        case .lesson: "课程单元"
        case .discussion: "讨论板"
        case .other: "内容"
        }
    }

    private func dueTint(_ date: Date) -> Color {
        if date < Date() { return Theme.muted }
        if date.timeIntervalSinceNow < 48 * 3600 { return Color(hex: 0xB3263B) }
        return Color(hex: 0xA06A24)
    }

    private func fileExtension(_ name: String) -> String {
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "文件" : ext.uppercased()
    }

    private func formatScore(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }
}

struct ContentChildrenList: View {
    let course: Course
    let parentID: String

    @Environment(AppModel.self) private var model
    @State private var items: [CourseContent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("文件夹内容")
                    .font(.system(size: 16, weight: .semibold))
                if !items.isEmpty {
                    Text("\(items.count) 项")
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                Button {
                    Task { await load(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.muted)
            }

            if isLoading && items.isEmpty {
                LoadingRows(count: 3)
            } else if let errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await load(force: true) }
                }
            } else if items.isEmpty {
                EmptyStateView(
                    symbol: "folder",
                    title: "文件夹是空的",
                    message: "老师还没有在这里放入内容。"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: AppRoute.content(item)) {
                            ContentRow(content: item)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        if index < items.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                .cardSurface(padding: 0, radius: 18)
            }
        }
        .task(id: parentID) { await load() }
    }

    private func load(force: Bool = false) async {
        if !force, !items.isEmpty { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await model.contents(courseID: course.id, parentID: parentID, force: force)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}


struct ContentByIDView: View {
    let courseID: String
    let contentID: String

    @Environment(AppModel.self) private var model
    @State private var content: CourseContent?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let content, let course = model.course(id: courseID) {
                ContentDetailView(course: course, content: content)
            } else if let errorMessage {
                VStack(spacing: 14) {
                    EmptyStateView(
                        symbol: "exclamationmark.triangle",
                        title: "无法加载这项内容",
                        message: errorMessage
                    )
                    Button("重试") {
                        Task { await load(force: true) }
                    }
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                }
                .padding(24)
            } else {
                ProgressView("正在加载…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
        .navigationTitle(content?.title ?? "作业")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private func load(force: Bool = false) async {
        if !force, content != nil { return }
        errorMessage = nil
        do {
            content = try await model.client.blackboard.content(courseID: courseID, contentID: contentID)
        } catch {
            if let api = error as? APIError, case .notAuthenticated = api {
                model.expireSession()
            }
            errorMessage = error.localizedDescription
        }
    }
}
