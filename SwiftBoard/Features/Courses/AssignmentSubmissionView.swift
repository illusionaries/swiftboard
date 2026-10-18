import SwiftUI
import SwiftBoardKit
import UniformTypeIdentifiers
import QuickLook
#if os(macOS)
import QuickLookUI
#endif
#if os(iOS)
import VisionKit
#endif

struct AssignmentSubmissionView: View {
    let course: Course
    let content: CourseContent
    var onSubmitted: () -> Void = {}

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var form: AssignmentUploadForm?
    @State private var isLoadingForm = true
    @State private var loadError: String?
    @State private var selectedFile: SelectedUploadFile?
    @State private var showFileImporter = false
    @State private var comment = ""
    @State private var isSubmitting = false
    @State private var showConfirmation = false
    @State private var receipt: AssignmentSubmissionReceipt?
    @State private var submissionError: String?
    @State private var importError: String?
    @State private var showScanner = false
    @State private var pendingScanURL: URL?
    @State private var scanFileName = "扫描文稿.pdf"
    @State private var showScanNamePrompt = false
    @State private var attempts: [AssignmentAttempt] = []
    @State private var attemptsChecked = false
    @State private var isCheckingAttempts = false
    @State private var showHistory = false
    @State private var previewURL: URL?

    private struct SelectedUploadFile: Identifiable {
        let id = UUID()
        let name: String
        let url: URL
        let size: Int64
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    if let receipt {
                        resultCard(receipt)
                    } else if isCheckingAttempts {
                        checkingAttemptsCard
                    } else if hasReachedAttemptLimit {
                        attemptLimitReachedCard
                    } else {
                        formContent
                    }
                }
                .padding(20)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.canvas)
            .navigationTitle("提交作业")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(isSubmitting)
                }
            }
        }
        .task { await loadForm() }
        .task { await checkAttempts() }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false,
            onCompletion: handleImport
        )
        #if os(iOS)
        .sheet(isPresented: $showScanNamePrompt) {
            ScanNameSheet(
                name: $scanFileName,
                onSave: finalizeScannedPDF,
                onCancel: cancelPendingScan
            )
        }
        .fullScreenCover(isPresented: $showScanner) {
            DocumentScannerView(
                onFinish: handleScan,
                onCancel: { showScanner = false },
                onError: { error in
                    showScanner = false
                    importError = "扫描失败：\(error.localizedDescription)"
                }
            )
            .ignoresSafeArea()
        }
        #endif
        .alert("确认提交作业？", isPresented: $showConfirmation) {
            Button("提交") {
                submit()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(submissionConfirmationMessage)
        }
        .quickLookPreview($previewURL)
        .interactiveDismissDisabled(isSubmitting)
        .onDisappear(perform: cleanup)
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 640)
        #endif
    }

    // MARK: - Content

    @ViewBuilder
    private var formContent: some View {
        if finiteAttemptLimit != nil {
            attemptLimitNotice
        }

        if let instructions {
            VStack(alignment: .leading, spacing: 7) {
                Text("作业说明")
                    .font(.subheadline.weight(.semibold))
                Text(instructions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(10)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 16, radius: 16)
        }

        fileSection
        commentSection

        if let form, !form.attachments.isEmpty {
            AssignmentAttachmentsView(attachments: form.attachments, course: course)
        }

        if let importError {
            inlineError(importError)
        }

        if let submissionError {
            ErrorBanner(message: submissionError)
        }

        if let loadError {
            ErrorBanner(message: loadError) {
                Task { await loadForm() }
            }
        }

        submitButton

        Text("提交会直接写入教学网。若页面提示失败或长时间没有响应，请先在教学网确认，避免重复提交。")
            .font(.caption2)
            .foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
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
                        Chip(text: SBDate.dueDescription(due), tint: dueTint(due))
                    }
                    if let points = content.possiblePoints, points > 0 {
                        Chip(text: "\(formatScore(points)) 分", tint: Theme.accent)
                    }
                    if let limit = finiteAttemptLimit {
                        Chip(text: limit == 1 ? "仅一次提交" : "最多 \(limit) 次", tint: Theme.accent)
                    }
                    if let form, form.existingFileCount > 0 {
                        Chip(text: "已有 \(form.existingFileCount) 个文件", tint: Theme.muted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var finiteAttemptLimit: Int? {
        guard let limit = content.attemptLimit, limit > 0 else { return nil }
        return limit
    }

    private var hasReachedAttemptLimit: Bool {
        guard attemptsChecked, let limit = finiteAttemptLimit else { return false }
        return attempts.count >= limit
    }

    private var remainingAttempts: Int? {
        guard let limit = finiteAttemptLimit else { return nil }
        return max(0, limit - attempts.count)
    }

    private var submissionConfirmationMessage: String {
        let base = "将把「\(selectedFile?.name ?? "")」上传到「\(course.title)」。"
        guard let limit = finiteAttemptLimit else {
            return base + "提交后请在教学网核对提交记录。"
        }
        if limit == 1 {
            return base + "该作业只允许一次提交，提交后无法修改，请确认文件无误。"
        }
        if attemptsChecked {
            let afterSubmit = max(0, limit - attempts.count - 1)
            return base + "该作业最多可提交 \(limit) 次，你已提交 \(attempts.count) 次；本次提交后还剩 \(afterSubmit) 次。"
        }
        return base + "该作业最多可提交 \(limit) 次。"
    }

    private var checkingAttemptsCard: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("正在检查提交次数…")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16, radius: 16)
    }

    private var attemptLimitNotice: some View {
        let limit = finiteAttemptLimit ?? 1
        let title = limit == 1 ? "该作业只允许提交一次" : "该作业最多可提交 \(limit) 次"
        let detail: String
        if !attemptsChecked {
            detail = "请在教学网确认已提交次数，避免超过上限。"
        } else if limit == 1 {
            detail = "提交后不能修改或重新提交，请确认文件、文件名和留言无误。"
        } else if attempts.isEmpty {
            detail = "你目前还没有提交记录。"
        } else {
            detail = "你已提交 \(attempts.count) 次，还剩 \(remainingAttempts ?? 0) 次。"
        }

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: 0xA06A24))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 14, radius: 14)
    }

    private var attemptLimitReachedCard: some View {
        let limit = finiteAttemptLimit ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                Text(limit == 1 ? "该作业只允许一次提交" : "已达到提交次数上限")
                    .font(.headline)
            }

            if limit > 1 {
                Text("该作业最多可提交 \(limit) 次，你已提交 \(attempts.count) 次。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let latest = attempts.last, let submittedAt = latest.submittedAt {
                Text("你已于 \(submittedAt.formatted(date: .abbreviated, time: .shortened)) 提交。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if !attempts.isEmpty {
                Text("你已有 \(attempts.count) 次提交记录。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(limit == 1
                 ? "为避免覆盖已提交内容，本 App 不会再次上传。如需修改，请联系任课老师。"
                 : "已达到本次作业的提交上限，本 App 不会再次上传。如需额外机会，请联系任课老师。")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button("查看提交记录") {
                    showHistory = true
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)

                Button("在教学网查看") {
                    openURL(model.client.blackboard.contentPageURL(course: course, content: content))
                }
                .buttonStyle(.bordered)
            }
            .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 18, radius: 16)
        .sheet(isPresented: $showHistory) {
            AssignmentHistoryView(course: course, content: content)
                .environment(model)
        }
    }

    private func checkAttempts() async {
        guard finiteAttemptLimit != nil, let columnID = content.gradeColumnID else { return }
        isCheckingAttempts = true
        defer { isCheckingAttempts = false }
        do {
            attempts = try await model.client.blackboard.assignments.history(
                courseID: content.courseID,
                contentID: content.id,
                columnID: columnID
            )
            attemptsChecked = true
        } catch {
            // A failed history read should not prevent an otherwise valid submission.
            attemptsChecked = false
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("提交文件")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isLoadingForm {
                    ProgressView().controlSize(.mini)
                }
            }

            if let selectedFile {
                HStack(spacing: 12) {
                    let info = fileSymbol(for: selectedFile.name)
                    IconTile(symbol: info.0, tint: info.1, size: 38)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedFile.name)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(2)
                        Text(byteCount(selectedFile.size))
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    Button {
                        previewURL = selectedFile.url
                    } label: {
                        Image(systemName: "eye")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("预览文件")
                    Button {
                        cleanupSelectedFile()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("移除文件")
                }
                .padding(12)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                HStack(spacing: 18) {
                    Button("重新选择文件") { showFileImporter = true }
                    #if os(iOS)
                    if VNDocumentCameraViewController.isSupported {
                        Button("扫描文稿") { showScanner = true }
                    }
                    #endif
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Theme.accent)
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            } else {
                Button {
                    showFileImporter = true
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(Theme.accent)
                        Text("选择要提交的文件")
                            .font(.subheadline.weight(.medium))
                        Text("PDF、Word、PPT、压缩包等格式均可")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
                    .background(Theme.field.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)

                #if os(iOS)
                if VNDocumentCameraViewController.isSupported {
                    Button {
                        showScanner = true
                    } label: {
                        Label("扫描文稿", systemImage: "doc.viewfinder")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .disabled(isSubmitting)
                }
                #endif
            }

            Text("只会上传你选择的这个文件。大文件提交前请确认网络稳定。")
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardSurface(padding: 16, radius: 16)
    }

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("给老师留言")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(comment.count)/1000")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .monospacedDigit()
            }
            ZStack(alignment: .topLeading) {
                if comment.isEmpty {
                    Text("可选，例如：这是第三次作业的最终版本。")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $comment)
                    .font(.subheadline)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 76)
                    .padding(4)
                    .disabled(isSubmitting)
            }
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: comment) { _, value in
                if value.count > 1000 {
                    comment = String(value.prefix(1000))
                }
            }
        }
        .cardSurface(padding: 16, radius: 16)
    }

    private var submitButton: some View {
        Button {
            showConfirmation = true
        } label: {
            HStack(spacing: 8) {
                if isSubmitting {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 13, weight: .semibold))
                }
                Text(isSubmitting ? "正在提交…" : "提交作业")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
            .background(
                LinearGradient(
                    colors: [Theme.accentBright, Theme.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .opacity(canSubmit ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
    }

    private func resultCard(_ receipt: AssignmentSubmissionReceipt) -> some View {
        let success = receipt.outcome == .submitted
        let tint = success ? Color(hex: 0x3F7A5C) : Color(hex: 0xA06A24)
        return VStack(spacing: 12) {
            Image(systemName: success ? "checkmark.circle.fill" : "info.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(tint)
            Text(success ? "作业已提交" : "提交请求已发送")
                .font(.title3.weight(.semibold))
            Text(receipt.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("文件：\(receipt.fileName)")
                .font(.caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(2)

            HStack(spacing: 10) {
                Button {
                    openURL(model.client.blackboard.contentPageURL(course: course, content: content))
                } label: {
                    Label("在教学网查看", systemImage: "safari")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.field, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Button {
                    dismiss()
                } label: {
                    Text("完成")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.8)
        )
    }

    private func inlineError(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(Color.red.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Data

    private var instructions: String? {
        let text = content.bodyHTML.htmlToPlainText
        if !text.isEmpty {
            return text.count > 700 ? String(text.prefix(700)) + "…" : text
        }
        let description = content.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? nil : description
    }

    private var canSubmit: Bool {
        selectedFile != nil && form != nil && !isSubmitting && loadError == nil
    }

    private func dueTint(_ date: Date) -> Color {
        if date < Date() { return Theme.muted }
        if date.timeIntervalSinceNow < 48 * 3600 { return Color(hex: 0xB3263B) }
        return Color(hex: 0xA06A24)
    }

    private func formatScore(_ value: Double) -> String {
        abs(value.rounded() - value) < 0.001 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }

    private func byteCount(_ size: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func loadForm() async {
        guard form == nil else { return }
        isLoadingForm = true
        loadError = nil
        defer { isLoadingForm = false }
        do {
            form = try await model.client.blackboard.assignments.uploadForm(
                courseID: content.courseID,
                contentID: content.id
            )
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importFile(url)
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                importError = "无法选择文件：\(error.localizedDescription)"
            }
        }
    }

    private func importFile(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            guard values.isDirectory != true else {
                importError = "请选择文件，而不是文件夹。"
                return
            }
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftBoardUploads", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            cleanupSelectedFile()
            let destination = directory.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.copyItem(at: url, to: destination)
            let copied = try destination.resourceValues(forKeys: [.fileSizeKey])
            let size = Int64(copied.fileSize ?? values.fileSize ?? 0)
            selectedFile = SelectedUploadFile(name: url.lastPathComponent, url: destination, size: size)
            importError = nil
        } catch {
            importError = "无法读取所选文件：\(error.localizedDescription)"
        }
    }

    private func submit() {
        guard let selectedFile, !isSubmitting else { return }
        isSubmitting = true
        submissionError = nil
        Task {
            do {
                let result = try await model.client.blackboard.assignments.submit(
                    courseID: content.courseID,
                    contentID: content.id,
                    fileURL: selectedFile.url,
                    fileName: selectedFile.name,
                    comment: comment
                )
                receipt = result
                onSubmitted()
            } catch let api as APIError where api.isCancellation {
                // Leave the sheet as-is so the student can retry.
            } catch {
                if let api = error as? APIError, case .notAuthenticated = api {
                    model.expireSession()
                }
                submissionError = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    #if os(iOS)
    private func handleScan(_ scan: VNDocumentCameraScan) {
        showScanner = false
        do {
            let url = try ScannedDocumentPDF.make(from: scan)
            pendingScanURL = url
            scanFileName = "扫描文稿.pdf"
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(320))
                showScanNamePrompt = true
            }
        } catch {
            importError = "扫描文件生成失败：\(error.localizedDescription)"
        }
    }
    #endif

    private func finalizeScannedPDF() {
        guard let pending = pendingScanURL else { return }
        let name = normalizedScannedFileName()
        do {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SwiftBoardUploads", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let destination = directory.appendingPathComponent(name)
            try FileManager.default.copyItem(at: pending, to: destination)
            let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            cleanupSelectedFile()
            selectedFile = SelectedUploadFile(name: name, url: destination, size: Int64(size))
            importError = nil
        } catch {
            importError = "保存扫描文件失败：\(error.localizedDescription)"
        }
        try? FileManager.default.removeItem(at: pending.deletingLastPathComponent())
        pendingScanURL = nil
        showScanNamePrompt = false
    }

    private func cancelPendingScan() {
        if let pending = pendingScanURL {
            try? FileManager.default.removeItem(at: pending.deletingLastPathComponent())
        }
        pendingScanURL = nil
        showScanNamePrompt = false
    }

    private func normalizedScannedFileName() -> String {
        var base = scanFileName.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.lowercased().hasSuffix(".pdf") {
            base = String(base.dropLast(4))
        }
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        base = base.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if base.isEmpty {
            base = "扫描文稿"
        }
        return String(base.prefix(110)) + ".pdf"
    }

    private func cleanup() {
        guard !isSubmitting else { return }
        cleanupSelectedFile()
    }

    private func cleanupSelectedFile() {
        if let pendingScanURL {
            try? FileManager.default.removeItem(at: pendingScanURL.deletingLastPathComponent())
            self.pendingScanURL = nil
        }
        if let selectedFile {
            try? FileManager.default.removeItem(at: selectedFile.url.deletingLastPathComponent())
        }
        selectedFile = nil
    }
}
