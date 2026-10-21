import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

public struct AssignmentAttachment: Identifiable, Hashable, Sendable {
    public let name: String
    public let url: URL

    public var id: String { url.absoluteString }

    public init(name: String, url: URL) {
        self.name = name
        self.url = url
    }
}

/// Hidden fields and metadata scraped from Blackboard's legacy assignment
/// upload page. Blackboard protects submissions with a per-page nonce, so the
/// form has to be fetched immediately before posting.
public struct AssignmentUploadForm: Sendable {
    public let fields: [String: String]
    public let attachments: [AssignmentAttachment]
    public let existingFileCount: Int

    public init(fields: [String: String], attachments: [AssignmentAttachment], existingFileCount: Int) {
        self.fields = fields
        self.attachments = attachments
        self.existingFileCount = existingFileCount
    }
}

public struct AssignmentSubmittedFile: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let url: URL

    public init(id: String, name: String, url: URL) {
        self.id = id
        self.name = name
        self.url = url
    }
}

public struct AssignmentAttempt: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let status: String?
    public let score: Double?
    public let submittedAt: Date?
    public let submissionSize: Int?
    public let feedbackHTML: String?
    public let files: [AssignmentSubmittedFile]

    public init(
        id: String,
        label: String,
        status: String?,
        score: Double?,
        submittedAt: Date?,
        submissionSize: Int?,
        feedbackHTML: String?,
        files: [AssignmentSubmittedFile]
    ) {
        self.id = id
        self.label = label
        self.status = status
        self.score = score
        self.submittedAt = submittedAt
        self.submissionSize = submissionSize
        self.feedbackHTML = feedbackHTML
        self.files = files
    }

    public var hasFiles: Bool { !files.isEmpty }
    public var hasFeedback: Bool {
        !(feedbackHTML ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

public enum AssignmentSubmissionOutcome: String, Equatable, Sendable {
    /// The server's response clearly indicated success.
    case submitted
    /// The request was accepted but the response did not carry a success
    /// marker; the student should confirm on the website.
    case needsConfirmation
}

public struct AssignmentSubmissionReceipt: Sendable {
    public let outcome: AssignmentSubmissionOutcome
    public let message: String
    public let fileName: String
    public let submittedAt: Date

    public init(outcome: AssignmentSubmissionOutcome, message: String, fileName: String, submittedAt: Date = Date()) {
        self.outcome = outcome
        self.message = message
        self.fileName = fileName
        self.submittedAt = submittedAt
    }
}

public enum AssignmentSubmissionError: Error, LocalizedError, Sendable {
    case notAnAssignment
    case formUnavailable
    case missingField(String)
    case rejected(String)
    case server(String)
    case fileUnreadable(String)

    public var errorDescription: String? {
        switch self {
        case .notAnAssignment: "该内容不是作业"
        case .formUnavailable: "无法读取作业提交页面，请稍后重试"
        case .missingField(let field): "作业提交表单缺少字段：\(field)"
        case .rejected(let message): message
        case .server(let message): message
        case .fileUnreadable(let name): "无法读取文件：\(name)"
        }
    }
}

/// Handles the Original-Experience assignment upload form:
/// GET `uploadAssignment?action=newAttempt`, scrape the hidden fields, then
/// POST a multipart body to `uploadAssignment?action=submit`.
public struct AssignmentService: Sendable {
    private let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    private static let uploadPath = "/webapps/assignment/uploadAssignment"

    public func uploadForm(courseID: String, contentID: String) async throws -> AssignmentUploadForm {
        let url = makeURL([
            URLQueryItem(name: "action", value: "newAttempt"),
            URLQueryItem(name: "content_id", value: contentID),
            URLQueryItem(name: "course_id", value: courseID)
        ])
        var request = HTTPRequest(url: url)
        request.headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        let response = try await http.send(request)

        if response.url.path.contains("/webapps/login") {
            throw APIError.notAuthenticated
        }
        guard response.isSuccess else {
            throw AssignmentSubmissionError.server("无法读取作业提交页面（HTTP \(response.status)）")
        }
        guard let html = String(data: response.data, encoding: .utf8) else {
            throw AssignmentSubmissionError.formUnavailable
        }
        if html.contains("uploadAssignmentFormId") == false {
            if html.contains("loginForm") || html.contains("统一身份认证") {
                throw APIError.notAuthenticated
            }
            throw AssignmentSubmissionError.formUnavailable
        }

        try Self.assertAssignmentPage(html)

        guard let form = Self.parseForm(html) else {
            throw AssignmentSubmissionError.formUnavailable
        }
        return AssignmentUploadForm(
            fields: form,
            attachments: Self.parseAttachments(html),
            existingFileCount: Self.parseAttemptFileCount(html)
        )
    }

    public func submit(
        courseID: String,
        contentID: String,
        fileURL: URL,
        fileName: String? = nil,
        comment: String = ""
    ) async throws -> AssignmentSubmissionReceipt {
        let form = try await uploadForm(courseID: courseID, contentID: contentID)

        let resolvedName = Self.sanitizeFileName(fileName ?? fileURL.lastPathComponent)
        guard !resolvedName.isEmpty else {
            throw AssignmentSubmissionError.fileUnreadable(fileURL.lastPathComponent)
        }
        let fileData: Data
        do {
            fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        } catch {
            throw AssignmentSubmissionError.fileUnreadable(resolvedName)
        }
        guard !fileData.isEmpty else {
            throw AssignmentSubmissionError.fileUnreadable(resolvedName)
        }

        let fields = form.fields
        let nonce = try required("blackboard.platform.security.NonceUtil.nonce", in: fields)
        let ajaxNonce = try required("blackboard.platform.security.NonceUtil.nonce.ajax", in: fields)
        let formCourseID = try required("course_id", in: fields)
        let formContentID = try required("content_id", in: fields)
        let attemptID = fields["attempt_id"] ?? ""
        let isAjax = fields["isAjaxSubmit"] ?? "true"
        let studentTextType = fields["studentSubmission.type"] ?? "H"
        let studentTextEncoded = fields["studentSubmission.text_f"] ?? ""
        let studentTextWeb = fields["studentSubmission.text_w"] ?? ""
        let studentTextPrefix = fields["textbox_prefix"] ?? "studentSubmission.text"
        let commentType = fields["student_commentstype"] ?? "H"
        let commentEncoded = fields["student_commentstext_f"] ?? ""
        let commentWeb = fields["student_commentstext_w"] ?? ""
        let recallURL = fields["recallUrl"]
            ?? "/webapps/blackboard/content/listContent.jsp?content_id=\(contentID)&course_id=\(courseID)"
        let luLinkID = fields["lu_link_id"] ?? ""
        let mode = fields["mode"] ?? ""
        let removeFileID = fields["remove_file_id"] ?? ""

        var builder = MultipartBuilder()
        builder.field("attempt_id", attemptID)
        builder.field("blackboard.platform.security.NonceUtil.nonce", nonce)
        builder.field("blackboard.platform.security.NonceUtil.nonce.ajax", ajaxNonce)
        builder.field("content_id", formContentID)
        builder.field("course_id", formCourseID)
        builder.field("isAjaxSubmit", isAjax)
        builder.field("lu_link_id", luLinkID)
        builder.field("mode", mode)
        builder.field("recallUrl", recallURL)
        builder.field("remove_file_id", removeFileID)
        builder.field("studentSubmission.text_f", studentTextEncoded)
        builder.field("studentSubmission.text_w", studentTextWeb)
        builder.field("studentSubmission.type", studentTextType)
        builder.field("student_commentstext_f", commentEncoded)
        builder.field("student_commentstext_w", commentWeb)
        builder.field("student_commentstype", commentType)
        builder.field("textbox_prefix", studentTextPrefix)
        builder.field("studentSubmission.text", "")
        builder.field("student_commentstext", Self.limitedComment(comment))
        builder.field("dispatch", "submit")
        builder.field("newFile_artifactFileId", "undefined")
        builder.field("newFile_artifactType", "undefined")
        builder.field("newFile_artifactTypeResourceKey", "undefined")
        builder.field("newFile_attachmentType", "L")
        builder.field("newFile_fileId", "new")
        builder.field("newFile_linkTitle", resolvedName)
        builder.field("newFilefilePickerLastInput", "dummyValue")
        builder.file(
            name: "newFile_LocalFile0",
            fileName: resolvedName,
            mimeType: Self.mimeType(for: fileURL),
            data: fileData
        )
        builder.field("useless", "")

        let boundary = builder.boundary
        let body = builder.finalize()

        let request = HTTPRequest(
            url: makeURL([URLQueryItem(name: "action", value: "submit")]),
            method: .post,
            headers: [
                "Origin": "https://course.pku.edu.cn",
                "Accept": "*/*",
                "Referer": makeURL([
                    URLQueryItem(name: "action", value: "newAttempt"),
                    URLQueryItem(name: "content_id", value: contentID),
                    URLQueryItem(name: "course_id", value: courseID)
                ]).absoluteString
            ],
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)",
            timeout: 180
        )
        let response = try await http.send(request)
        if response.url.path.contains("/webapps/login") {
            throw APIError.notAuthenticated
        }
        guard response.isSuccess else {
            throw AssignmentSubmissionError.server(
                "提交失败（HTTP \(response.status)）\(Self.responseSnippet(response.text))"
            )
        }

        let text = response.text
        let lower = text.lowercased()

        if text.contains("uploadAssignmentFormId") {
            throw AssignmentSubmissionError.rejected(
                "服务器没有接受这次提交，请检查文件大小、截止时间或允许的提交次数。"
            )
        }

        if let json = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] {
            if let success = json["success"] as? Bool {
                if success {
                    return AssignmentSubmissionReceipt(
                        outcome: .submitted,
                        message: "作业已成功提交。",
                        fileName: resolvedName
                    )
                }
                let message = (json["message"] as? String)
                    ?? (json["error"] as? String)
                    ?? (json["errors"] as? String)
                    ?? "服务器拒绝了这次提交。"
                throw AssignmentSubmissionError.rejected(message)
            }
            if let error = json["error"] as? String, !error.isEmpty {
                throw AssignmentSubmissionError.rejected(error)
            }
        }

        let successMarkers = ["提交成功", "已成功提交", "successfully submitted", "\"success\":true", "\"success\": true", "\"status\":\"success\""]
        if successMarkers.contains(where: { lower.contains($0) }) {
            return AssignmentSubmissionReceipt(
                outcome: .submitted,
                message: "作业已成功提交。",
                fileName: resolvedName
            )
        }

        let failureMarkers = ["提交失败", "上传失败", "invalid nonce", "not permitted", "access denied", "截止日期已过"]
        if failureMarkers.contains(where: { lower.contains($0) }) {
            throw AssignmentSubmissionError.rejected("提交被服务器拒绝，请在教学网检查作业状态。")
        }

        return AssignmentSubmissionReceipt(
            outcome: .needsConfirmation,
            message: "提交请求已发送。服务器未返回明确结果，请在教学网核对提交记录。",
            fileName: resolvedName
        )
    }

    // MARK: - History

    /// Returns all attempts for an assignment, including the files uploaded in
    /// each attempt and any teacher feedback.
    public func history(courseID: String, contentID: String, columnID: String) async throws -> [AssignmentAttempt] {
        let attempts = try await attemptRecords(courseID: courseID, columnID: columnID)
        guard !attempts.isEmpty else { return [] }

        var results: [AssignmentAttempt] = []
        for (index, record) in attempts.enumerated() {
            var label: String?
            var files: [AssignmentSubmittedFile] = []
            do {
                let detail = try await submissionFiles(
                    courseID: courseID,
                    contentID: contentID,
                    attemptID: record.id
                )
                label = detail.label
                files = detail.files
            } catch let api as APIError where api.isCancellation {
                throw api
            } catch let api as APIError {
                if case .notAuthenticated = api { throw api }
            } catch {
                // The attempt summary is still useful if a file page fails.
            }

            results.append(
                AssignmentAttempt(
                    id: record.id,
                    label: (label?.isEmpty == false ? label! : "第 \(index + 1) 次提交"),
                    status: record.status,
                    score: record.displayGrade?.score,
                    submittedAt: record.attemptReceipt?.submissionDate ?? record.created,
                    submissionSize: record.attemptReceipt?.submissionTotalSize,
                    feedbackHTML: record.feedback,
                    files: files
                )
            )
        }
        return results.sorted {
            ($0.submittedAt ?? .distantPast) < ($1.submittedAt ?? .distantPast)
        }
    }

    private func attemptRecords(courseID: String, columnID: String) async throws -> [AttemptDTO] {
        let url = apiURL(
            "/learn/api/public/v2/courses/\(courseID)/gradebook/columns/\(columnID)/attempts"
        )
        var request = HTTPRequest(url: url)
        request.headers["Accept"] = "application/json"
        let response = try await http.send(request)
        if response.url.path.contains("/webapps/login") {
            throw APIError.notAuthenticated
        }
        if response.status == 404 {
            return []
        }
        guard response.isSuccess else {
            throw AssignmentSubmissionError.server("无法读取提交记录（HTTP \(response.status)）")
        }
        guard !response.data.isEmpty else { return [] }
        do {
            return try JSONDecoder.pku().decode(AttemptsDTO.self, from: response.data).results
        } catch {
            throw APIError.decoding("提交记录")
        }
    }

    private func submissionFiles(
        courseID: String,
        contentID: String,
        attemptID: String
    ) async throws -> (label: String?, files: [AssignmentSubmittedFile]) {
        let url = makeURL([
            URLQueryItem(name: "mode", value: "view"),
            URLQueryItem(name: "content_id", value: contentID),
            URLQueryItem(name: "course_id", value: courseID),
            URLQueryItem(name: "attempt_id", value: attemptID)
        ])
        var request = HTTPRequest(url: url)
        request.headers["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        let response = try await http.send(request)
        if response.url.path.contains("/webapps/login") {
            throw APIError.notAuthenticated
        }
        if response.status == 400 {
            return (nil, [])
        }
        guard response.isSuccess else {
            throw AssignmentSubmissionError.server("无法读取提交详情（HTTP \(response.status)）")
        }
        let html = response.text
        return (Self.parseAttemptLabel(html), Self.parseSubmittedFiles(html))
    }

    private func apiURL(_ path: String) -> URL {
        var components = URLComponents(url: BlackboardClient.baseURL, resolvingAgainstBaseURL: false)!
        components.path = path
        return components.url!
    }

    private static func parseAttemptLabel(_ html: String) -> String? {
        guard let match = html.firstRegexMatch(
            #"<h3[^>]*id\s*=\s*["']currentAttempt_label["'][^>]*>(.*?)</h3>"#
        ), match.count > 1 else { return nil }
        let label = match[1].htmlToPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? nil : label
    }

    private static func parseSubmittedFiles(_ html: String) -> [AssignmentSubmittedFile] {
        var seen = Set<String>()
        var files: [AssignmentSubmittedFile] = []
        for match in html.allRegexMatches(
            #"<a\b[^>]*href\s*=\s*["']([^"']*/webapps/assignment/download\?[^"']*)["'][^>]*>(.*?)</a>"#
        ) {
            guard match.count >= 3 else { continue }
            let href = match[1].decodingHTMLEntities()
            guard let url = URL(string: href, relativeTo: BlackboardClient.baseURL)?.absoluteURL else { continue }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let query = Dictionary(
                uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
                    item.value.map { (item.name, $0) }
                }
            )
            let fileName = query["fileName"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let linkText = match[2].htmlToPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = (fileName?.isEmpty == false ? fileName! : (linkText.isEmpty ? "提交文件" : linkText))
            let fileID = query["file_id"] ?? url.absoluteString
            guard seen.insert(url.absoluteString).inserted else { continue }
            files.append(AssignmentSubmittedFile(id: fileID, name: name, url: url))
        }
        return files
    }

    // MARK: - Helpers

    private func makeURL(_ query: [URLQueryItem]) -> URL {
        var components = URLComponents(url: BlackboardClient.baseURL, resolvingAgainstBaseURL: false)!
        components.path = Self.uploadPath
        components.queryItems = query
        return components.url!
    }

    private func required(_ key: String, in fields: [String: String]) throws -> String {
        guard let value = fields[key], !value.isEmpty else {
            throw AssignmentSubmissionError.missingField(key)
        }
        return value
    }

    private static func assertAssignmentPage(_ html: String) throws {
        let markers = ["上载作业", "提交作业", "作业提交", "Upload Assignment", "Assignment Submission"]
        if markers.contains(where: html.contains) {
            return
        }
        throw AssignmentSubmissionError.notAnAssignment
    }

    private static func parseForm(_ html: String) -> [String: String]? {
        guard let formMatch = html.firstRegexMatch(
            #"<form[^>]*id\s*=\s*["']uploadAssignmentFormId["'][^>]*>(.*?)</form>"#
        ), formMatch.count > 1 else {
            return nil
        }
        let inner = formMatch[1]
        var fields: [String: String] = [:]
        for tag in inner.allRegexMatches(#"<input\b[^>]*>"#) {
            guard let raw = tag.first else { continue }
            var name: String?
            var value = ""
            for attribute in raw.allRegexMatches(#"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)')"#) {
                guard attribute.count >= 4 else { continue }
                let key = attribute[1].lowercased()
                let doubleQuoted = attribute[2]
                let singleQuoted = attribute[3]
                let attrValue = doubleQuoted.isEmpty ? singleQuoted : doubleQuoted
                if key == "name" { name = attrValue }
                if key == "value" { value = attrValue }
            }
            if let name, !name.isEmpty {
                fields[name] = value.decodingHTMLEntities()
            }
        }
        return fields.isEmpty ? nil : fields
    }

    private static func parseAttemptFileCount(_ html: String) -> Int {
        guard let match = html.firstRegexMatch(#"var\s+sAttempt\s*=\s*(\d+)"#), match.count > 1 else {
            return 0
        }
        return Int(match[1]) ?? 0
    }

    private static func parseAttachments(_ html: String) -> [AssignmentAttachment] {
        var seen = Set<String>()
        var attachments: [AssignmentAttachment] = []
        for match in html.allRegexMatches(
            #"<a\b[^>]*href\s*=\s*["']([^"']*bbcswebdav[^"']*)["'][^>]*>(.*?)</a>"#
        ) {
            guard match.count >= 3 else { continue }
            let href = match[1].decodingHTMLEntities()
            guard let url = URL(string: href, relativeTo: BlackboardClient.baseURL)?.absoluteURL,
                  seen.insert(url.absoluteString).inserted else { continue }
            let name = match[2].htmlToPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
            attachments.append(AssignmentAttachment(name: name.isEmpty ? "附件" : name, url: url))
        }
        return attachments
    }

    private static func sanitizeFileName(_ name: String) -> String {
        var cleaned = name
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = "submission" }
        return String(cleaned.prefix(180))
    }

    private static func limitedComment(_ comment: String) -> String {
        String(comment.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
    }

    private static func mimeType(for url: URL) -> String {
        #if canImport(UniformTypeIdentifiers)
        if let type = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType {
            return type
        }
        #endif
        return "application/octet-stream"
    }

    private static func responseSnippet(_ html: String) -> String {
        let text = html.htmlToPlainText.trimmingCharacters(in: .whitespacesAndNewlines)
        let snippet = String(text.prefix(240))
        return snippet.isEmpty ? "" : "：\(snippet)"
    }
}

private struct AttemptsDTO: Decodable {
    let results: [AttemptDTO]
}

private struct AttemptDTO: Decodable {
    let id: String
    let status: String?
    let created: Date?
    let displayGrade: DisplayGradeDTO?
    let feedback: String?
    let attemptReceipt: AttemptReceiptDTO?
}

private struct AttemptReceiptDTO: Decodable {
    let submissionDate: Date?
    let submissionTotalSize: Int?
}

extension BlackboardClient {
    public var assignments: AssignmentService { AssignmentService(http: http) }

    /// Downloads a submitted assignment file with the current session cookies.
    public func downloadFile(
        from url: URL,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws {
        try await http.download(url, to: destination, progress: progress)
    }
}

// MARK: - Multipart

private struct MultipartBuilder {
    let boundary = "----SwiftBoardBoundary" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    private var data = Data()

    mutating func field(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append(value)
        append("\r\n")
    }

    mutating func file(name: String, fileName: String, mimeType: String, data fileData: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(fileName.replacingOccurrences(of: "\"", with: "%22"))\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(fileData)
        append("\r\n")
    }

    mutating func finalize() -> Data {
        append("--\(boundary)--\r\n")
        return data
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}

// MARK: - Regex helpers

extension String {
    func firstRegexMatch(_ pattern: String) -> [String]? {
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

    func allRegexMatches(_ pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(startIndex..<endIndex, in: self)
        return regex.matches(in: self, range: range).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: self) else { return "" }
                return String(self[range])
            }
        }
    }
}
