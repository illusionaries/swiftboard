import Foundation

/// JSON client for `course.pku.edu.cn` (Blackboard Learn 3900).
///
/// The endpoints under `/learn/api/v1` are the ones used by Blackboard's own
/// web front-end and work with the regular session cookies, no OAuth app
/// registration required. The `/learn/api/public/v2` gradebook endpoint gives
/// the signed-in student's own grades in a single request.
public struct BlackboardClient: Sendable {
    public static let baseURL = URL(string: "https://course.pku.edu.cn")!

    let http: HTTPClient

    public init(http: HTTPClient) {
        self.http = http
    }

    // MARK: - Requests

    private func makeURL(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        components.path = path.hasPrefix("/") ? path : "/" + path
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    private func fetchPage<Item: Decodable>(_ target: String, query: [URLQueryItem] = []) async throws -> PagedDTO<Item> {
        let url = target.hasPrefix("http") ? URL(string: target)! : makeURL(target, query: query)
        var request = HTTPRequest(url: url)
        request.headers["Accept"] = "application/json"
        let response = try await http.send(request)
        try Self.validate(response)
        do {
            return try JSONDecoder.pku().decode(PagedDTO<Item>.self, from: response.data)
        } catch {
            throw APIError.decoding(Self.describe(error))
        }
    }

    private func getAll<Item: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        maxPages: Int = 30
    ) async throws -> [Item] {
        var items: [Item] = []
        var nextPage: String?
        var first = true
        for _ in 0..<maxPages {
            let target = first ? path : (nextPage ?? path)
            let page: PagedDTO<Item> = try await fetchPage(target, query: first ? query : [])
            items.append(contentsOf: page.results)
            first = false
            guard let next = page.paging?.nextPage, !next.isEmpty else { break }
            nextPage = next
        }
        return items
    }

    private func getJSON<Value: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Value {
        var request = HTTPRequest(url: makeURL(path, query: query))
        request.headers["Accept"] = "application/json"
        let response = try await http.send(request)
        try Self.validate(response)
        do {
            return try JSONDecoder.pku().decode(Value.self, from: response.data)
        } catch {
            throw APIError.decoding(Self.describe(error))
        }
    }

    private static func validate(_ response: HTTPResponse) throws {
        if response.url.path.contains("/webapps/login") { throw APIError.notAuthenticated }
        if response.isHTML { throw APIError.notAuthenticated }
        guard response.isSuccess else {
            var message: String?
            if let object = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] {
                message = object["message"] as? String
            }
            throw APIError.http(status: response.status, message: message)
        }
    }

    private static func describe(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .keyNotFound(let key, _): return "缺少字段 \(key.stringValue)"
            case .typeMismatch(_, let context): return context.debugDescription
            case .valueNotFound(_, let context): return context.debugDescription
            case .dataCorrupted(let context): return context.debugDescription
            @unknown default: return error.localizedDescription
            }
        }
        return error.localizedDescription
    }

    // MARK: - Session

    /// Completes the campus login handshake with the IAAA token.
    public func campusLogin(token: String) async throws {
        var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("/webapps/bb-sso-BBLEARN/execute/authValidate/campusLogin"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "rand", value: String(format: "%.16f", Double.random(in: 0...1))),
            URLQueryItem(name: "token", value: token)
        ]
        let response = try await http.send(HTTPRequest(url: components.url!))
        guard response.isSuccess else {
            throw APIError.login(message: "教学网会话建立失败（HTTP \(response.status)）", code: nil)
        }
        // Warming the portal session makes Blackboard issue the path-scoped
        // session cookie used by the REST endpoints.
        _ = try? await http.send(HTTPRequest(url: Self.baseURL.appendingPathComponent("/webapps/portal/frameset.jsp")))
    }

    public func profile() async throws -> UserProfile {
        let dto: ProfileDTO = try await getJSON("/learn/api/v1/users/me")
        let avatar = dto.avatar?.permanentUrl.flatMap { URL(string: $0, relativeTo: Self.baseURL)?.absoluteURL }
        return UserProfile(
            id: dto.id,
            userName: dto.userName,
            givenName: dto.givenName ?? "",
            familyName: dto.familyName ?? "",
            email: dto.emailAddress ?? "",
            department: dto.department,
            avatarURL: avatar,
            systemRole: dto.systemRole
        )
    }

    // MARK: - Courses

    public func terms() async throws -> [AcademicTerm] {
        let items: [TermDTO] = try await getAll("/learn/api/v1/terms", query: [URLQueryItem(name: "limit", value: "100")])
        let unique = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return unique.values
            .map { AcademicTerm(id: $0.id, name: $0.name) }
            .sorted { $0.sortKey > $1.sortKey }
    }

    public func enrollments() async throws -> [Course] {
        let memberships: [MembershipDTO] = try await getAll(
            "/learn/api/v1/users/me/memberships",
            query: [
                URLQueryItem(name: "expand", value: "course"),
                URLQueryItem(name: "limit", value: "200")
            ]
        )
        var seen = Set<String>()
        var courses: [Course] = []
        for membership in memberships {
            guard let course = Self.course(from: membership), !seen.contains(course.id) else { continue }
            seen.insert(course.id)
            courses.append(course)
        }
        return courses.sorted {
            if $0.resolvedTermKey != $1.resolvedTermKey { return $0.resolvedTermKey > $1.resolvedTermKey }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    /// Fetches term information for courses whose membership payload did not
    /// embed a term object.
    public func courseTerm(courseID: String) async throws -> (id: String?, name: String?) {
        struct DetailDTO: Decodable {
            let termId: String?
            let term: TermDTO?
        }
        let detail: DetailDTO = try await getJSON(
            "/learn/api/v1/courses/\(courseID)",
            query: [URLQueryItem(name: "expand", value: "term")]
        )
        return (detail.termId, detail.term?.name)
    }

    private static func course(from membership: MembershipDTO) -> Course? {
        guard let dto = membership.course else { return nil }
        let display = dto.displayName ?? dto.name ?? "未命名课程"
        let name = dto.name ?? display
        let termName = dto.term?.name ?? TermName.embeddedInCourseName(name)
        let homeURL = dto.homePageUrl.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        return Course(
            id: dto.id,
            externalID: dto.courseId ?? dto.id,
            name: name,
            displayName: display,
            description: dto.description ?? "",
            termID: dto.termId,
            termName: termName,
            role: CourseRole(apiValue: membership.role),
            lastAccess: membership.lastAccessDate,
            enrolledAt: membership.enrollmentDate,
            colorIndex: membership.courseCardColorIndex ?? stableColorIndex(dto.id),
            isAvailable: membership.isAvailable ?? dto.isAvailable ?? true,
            homePageURL: homeURL,
            ultraStatus: dto.ultraStatus
        )
    }

    public static func stableColorIndex(_ value: String) -> Int {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return Int(hash % 10)
    }

    // MARK: - Announcements

    public func announcements(courseID: String) async throws -> [Announcement] {
        let items: [AnnouncementDTO] = try await getAll(
            "/learn/api/v1/courses/\(courseID)/announcements",
            query: [URLQueryItem(name: "limit", value: "100")]
        )
        return items
            .filter { $0.isDraft != true }
            .compactMap { dto in
                guard let created = dto.createdDate ?? dto.modifiedDate else { return nil }
                return Announcement(
                    id: dto.id,
                    courseID: dto.courseId ?? courseID,
                    title: dto.title ?? "无标题通知",
                    bodyHTML: dto.body?.displayText ?? dto.body?.rawText ?? "",
                    creatorID: dto.creatorUserId,
                    created: created,
                    modified: dto.modifiedDate,
                    position: dto.position ?? 0
                )
            }
            .sorted { $0.created > $1.created }
    }

    // MARK: - Content

    public func contents(courseID: String, parentID: String? = nil) async throws -> [CourseContent] {
        let path: String
        if let parentID {
            path = "/learn/api/v1/courses/\(courseID)/contents/\(parentID)/children"
        } else {
            path = "/learn/api/v1/courses/\(courseID)/contents"
        }
        let items: [ContentDTO] = try await getAll(path, query: [URLQueryItem(name: "limit", value: "200")])
        return items
            .map { Self.content(from: $0, courseID: courseID) }
            .sorted { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    private static func content(from dto: ContentDTO, courseID: String) -> CourseContent {
        let handler = dto.contentHandler ?? "unknown"
        let payload = dto.contentDetail?[handler] ?? dto.contentDetail?.values.first
        let fileDTO = payload?.file
        let fileURL = fileDTO?.permanentUrl.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
        let file = fileDTO.map { ContentFile(name: $0.fileName ?? "未命名文件", mimeType: $0.mimeType, url: fileURL) }
        let external = payload?.url.flatMap { URL(string: $0, relativeTo: baseURL)?.absoluteURL }
            ?? dto.body?.webLocation.flatMap { URL(string: $0) }
        return CourseContent(
            id: dto.id,
            courseID: dto.courseId ?? courseID,
            parentID: dto.parentId,
            title: dto.title ?? "未命名内容",
            handler: handler,
            kind: kind(for: handler, payload: payload),
            description: dto.description ?? "",
            bodyHTML: dto.body?.displayText ?? dto.body?.rawText ?? "",
            position: dto.position ?? 0,
            dueDate: payload?.gradingColumn?.dueDate,
            possiblePoints: payload?.gradingColumn?.possible,
            gradeColumnID: payload?.gradingColumn?.id,
            file: file,
            externalURL: external,
            isAvailable: dto.isAvailable ?? true
        )
    }

    private static func kind(for handler: String, payload: ContentDetailPayloadDTO?) -> ContentKind {
        let value = handler.lowercased()
        if payload?.isFolder == true { return .folder }
        if value.contains("folder") { return .folder }
        if value.contains("lesson") || value.contains("learningmodule") { return .lesson }
        if value.contains("assignment") { return .assignment }
        if value.contains("test") || value.contains("assessment") { return .test }
        if value.contains("externallink") || value.hasSuffix("link") { return .link }
        if value.contains("document") || value.contains("page") { return .document }
        if value.contains("file") { return .file }
        if value.contains("discussion") || value.contains("forum") { return .discussion }
        return .other
    }

    /// Fetches a single content item. Used when navigating from a gradebook
    /// row, where only the content ID is known.
    public func content(courseID: String, contentID: String) async throws -> CourseContent {
        var request = HTTPRequest(url: makeURL("/learn/api/v1/courses/\(courseID)/contents/\(contentID)"))
        request.headers["Accept"] = "application/json"
        let response = try await http.send(request)
        try Self.validate(response)
        do {
            let dto = try JSONDecoder.pku().decode(ContentDTO.self, from: response.data)
            return Self.content(from: dto, courseID: courseID)
        } catch {
            throw APIError.decoding(Self.describe(error))
        }
    }

    // MARK: - Grades

    public func gradeColumns(courseID: String) async throws -> [GradeColumn] {
        let items: [GradeColumnDTO] = try await getAll(
            "/learn/api/v1/courses/\(courseID)/gradebook/columns",
            query: [URLQueryItem(name: "limit", value: "200")]
        )
        return items
            .filter { $0.deleted != true }
            .map {
                GradeColumn(
                    id: $0.id,
                    name: $0.columnName ?? "未命名项目",
                    possible: $0.possible ?? 0,
                    dueDate: $0.dueDate,
                    isVisible: $0.visible ?? true,
                    calculationType: $0.calculationType,
                    contentID: $0.contentId,
                    gradesReleased: $0.gradesReleased ?? false
                )
            }
    }

    public func myGrades(courseID: String) async throws -> [UserGrade] {
        let dto: UserGradesDTO = try await getJSON(
            "/learn/api/public/v2/courses/\(courseID)/gradebook/users/me"
        )
        return dto.results.map {
            UserGrade(
                columnID: $0.columnId,
                score: $0.displayGrade?.score,
                text: $0.displayGrade?.text,
                status: $0.status,
                exempt: $0.exempt ?? false
            )
        }
    }

    public func courseGrade(courseID: String) async throws -> CourseGrade {
        async let columnsTask = gradeColumns(courseID: courseID)
        async let gradesTask = myGrades(courseID: courseID)
        let columns = try await columnsTask
        let grades = try await gradesTask

        var byColumn: [String: UserGrade] = [:]
        for grade in grades { byColumn[grade.columnID] = grade }

        let all = columns.map { column -> GradeItem in
            let grade = byColumn[column.id]
            return GradeItem(
                column: column,
                score: grade?.score,
                text: grade?.text,
                status: grade?.status,
                exempt: grade?.exempt ?? false
            )
        }
        let total = all.first { $0.column.isTotal && !$0.column.isWeightedTotal }
        let weighted = all.first { $0.column.isWeightedTotal }
        let items = all
            .filter { !$0.column.isTotal }
            .sorted { lhs, rhs in
                switch (lhs.column.dueDate, rhs.column.dueDate) {
                case let (l?, r?) where l != r: return l < r
                case (.some, .none): return true
                case (.none, .some): return false
                default: return lhs.column.name.localizedStandardCompare(rhs.column.name) == .orderedAscending
                }
            }
        return CourseGrade(courseID: courseID, items: items, total: total, weightedTotal: weighted, fetchedAt: Date())
    }

    // MARK: - Links & downloads

    public func coursePageURL(for course: Course) -> URL {
        course.homePageURL ?? makeURL(
            "/webapps/blackboard/execute/courseMain",
            query: [URLQueryItem(name: "course_id", value: course.id)]
        )
    }

    public func contentPageURL(course: Course, content: CourseContent) -> URL {
        makeURL(
            "/webapps/blackboard/execute/displayIndividualContent",
            query: [
                URLQueryItem(name: "course_id", value: course.id),
                URLQueryItem(name: "content_id", value: content.id)
            ]
        )
    }

    /// Downloads a content file into `root/<course>/<file name>`.
    public func download(
        content: CourseContent,
        course: Course,
        to root: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        guard let file = content.file, let url = file.url else {
            throw APIError.invalidResponse("该内容没有可下载的文件")
        }
        return try await download(url: url, name: file.name, course: course, to: root, progress: progress)
    }

    /// Downloads an arbitrary attachment link (for example a teacher-provided
    /// assignment attachment) into `root/<course>/<file name>`.
    public func download(
        url: URL,
        name: String,
        course: Course,
        to root: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let destination = root
            .appendingPathComponent(Self.sanitize(course.title), isDirectory: true)
            .appendingPathComponent(Self.sanitize(name))
        try await http.download(url, to: destination, progress: progress)
        return destination
    }

    static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "未命名" : String(cleaned.prefix(120))
    }
}
