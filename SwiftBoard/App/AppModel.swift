import Foundation
import Observation
import SwiftBoardKit

@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case booting
        case login
        case ready
    }

    struct CourseGroup: Identifiable, Hashable {
        let id: String
        let title: String
        let sortKey: Int
        let courses: [Course]
    }

    // MARK: - Published state

    private(set) var phase: Phase = .booting
    private(set) var profile: UserProfile?
    private(set) var courses: [Course] = []
    private(set) var terms: [AcademicTerm] = []
    private(set) var announcements: [Announcement] = []
    private(set) var deadlines: [Deadline] = []
    private(set) var grades: [String: CourseGrade] = [:]
    private(set) var gradesLoading: Set<String> = []
    private(set) var lastUpdated: Date?
    private(set) var isRefreshing = false
    private(set) var feedLoading = false
    private(set) var hasCachedData = false

    var loadError: String?
    var sessionMessage: String?
    var preferredTermKey: Int?

    // MARK: - Dependencies

    let client = PKUClient()
    let replayDownloads = ReplayDownloadCenter()
    let deadlineNotifications = DeadlineNotificationCenter()
    private let cacheURL: URL
    private var announcementsCache: [String: [Announcement]] = [:]
    private var contentCache: [String: [CourseContent]] = [:]
    private var didBootstrap = false

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("SwiftBoard", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        cacheURL = folder.appendingPathComponent("snapshot.json")
    }

    // MARK: - Derived

    var currentTermKey: Int {
        courses.map(\.resolvedTermKey).max() ?? 0
    }

    var currentTermName: String? {
        let key = currentTermKey
        if let term = terms.first(where: { $0.sortKey == key }) { return term.name }
        return currentCourses.first?.resolvedTermName
    }

    var currentCourses: [Course] {
        let key = currentTermKey
        let filtered = courses.filter { $0.resolvedTermKey == key && (key != 0 || $0.isAvailable) }
        return filtered.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    var upcomingDeadlines: [Deadline] {
        let now = Date()
        return deadlines.filter {
            $0.dueDate >= now.addingTimeInterval(-6 * 3600)
                && $0.dueDate <= now.addingTimeInterval(30 * 24 * 3600)
        }
    }

    var courseGroups: [CourseGroup] {
        let grouped = Dictionary(grouping: courses, by: \.resolvedTermKey)
        let groups: [CourseGroup] = grouped.map { key, value in
            let termName = terms.first(where: { $0.sortKey == key })?.name
                ?? value.first?.resolvedTermName
                ?? "其他课程"
            return CourseGroup(
                id: "\(key)",
                title: key == 0 ? "其他课程" : termName,
                sortKey: key,
                courses: value.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            )
        }
        return groups.sorted { $0.sortKey > $1.sortKey }
    }

    func course(id: String) -> Course? {
        courses.first { $0.id == id }
    }

    func announcementCount(for courseID: String) -> Int {
        announcementsCache[courseID]?.count ?? 0
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        phase = .booting

        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if let username = environment["SWIFTBOARD_ACCOUNT"], let password = environment["SWIFTBOARD_PASSWORD"],
           !username.isEmpty, !password.isEmpty {
            do {
                try await signIn(username: username, password: password, remember: false)
                return
            } catch {
                loadError = error.localizedDescription
            }
        }
        #endif

        if let cached = await client.restoreSession() {
            profile = maskedProfile(cached)
            phase = .ready
            loadSnapshot()
            await deadlineNotifications.sync(deadlines: deadlines)
            await refreshAll()
            debugLog("restored session for \(cached.userName), \(courses.count) courses")
            return
        }

        if let credentials = client.credentials.load() {
            do {
                try await signIn(username: credentials.username, password: credentials.password, remember: true)
                return
            } catch {
                sessionMessage = error.localizedDescription
            }
        }

        phase = .login
    }

    func signIn(username: String, password: String, otp: String = "", remember: Bool, randCode: String = "") async throws {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = try await client.signIn(username: trimmed, password: password, otpCode: otp, randCode: randCode)
        self.profile = maskedProfile(profile)
        self.sessionMessage = nil
        self.loadError = nil
        self.phase = .ready
        if remember {
            client.saveCredentials(username: trimmed, password: password)
        } else {
            client.credentials.clear()
        }
        UserDefaults.standard.set(trimmed, forKey: "lastUsername")
        await refreshAll()
    }

    func signOut() async {
        await client.signOut()
        client.credentials.clear()
        replayDownloads.deleteAll()
        await deadlineNotifications.clear()
        clearMemory()
        try? FileManager.default.removeItem(at: cacheURL)
        phase = .login
        sessionMessage = nil
    }

    func expireSession() {
        profile = nil
        phase = .login
        sessionMessage = "登录状态已过期，请重新登录"
        loadError = nil
    }

    func clearMemory() {
        profile = nil
        courses = []
        terms = []
        announcements = []
        deadlines = []
        grades = [:]
        announcementsCache = [:]
        contentCache = [:]
        hasCachedData = false
        lastUpdated = nil
    }

    // MARK: - Refresh

    func refreshAll() async {
        guard profile != nil, !isRefreshing else { return }
        isRefreshing = true
        loadError = nil
        defer { isRefreshing = false }

        do {
            let fetchedCourses = try await client.blackboard.enrollments()
            courses = fetchedCourses
            if let fetchedTerms = try? await client.blackboard.terms() {
                terms = fetchedTerms
            }
            lastUpdated = Date()
            saveSnapshot()
            debugLog("loaded \(courses.count) courses")
            await refreshFeeds()
            debugLog("feeds: \(announcements.count) announcements, \(deadlines.count) deadlines")
            saveSnapshot()
        } catch {
            present(error: error)
        }
    }

    private func refreshFeeds() async {
        let targets = currentCourses
        guard !targets.isEmpty else {
            announcements = []
            deadlines = []
            await deadlineNotifications.sync(deadlines: deadlines)
            return
        }

        feedLoading = true
        defer { feedLoading = false }

        let client = client
        let results = await withTaskGroup(of: (String, [Announcement], [GradeColumn]).self) { group in
            for course in targets {
                group.addTask {
                    let announcements = (try? await client.blackboard.announcements(courseID: course.id)) ?? []
                    let columns = (try? await client.blackboard.gradeColumns(courseID: course.id)) ?? []
                    return (course.id, announcements, columns)
                }
            }
            var collected: [(String, [Announcement], [GradeColumn])] = []
            for await result in group { collected.append(result) }
            return collected
        }

        var allAnnouncements: [Announcement] = []
        var allDeadlines: [Deadline] = []
        for (courseID, items, columns) in results {
            announcementsCache[courseID] = items
            allAnnouncements.append(contentsOf: items)
            guard let course = course(id: courseID) else { continue }
            for column in columns {
                guard let due = column.dueDate else { continue }
                allDeadlines.append(
                    Deadline(
                        courseID: course.id,
                        courseName: course.title,
                        title: column.name,
                        dueDate: due,
                        possible: column.possible > 0 ? column.possible : nil,
                        colorIndex: course.colorIndex
                    )
                )
            }
        }

        var seen = Set<String>()
        announcements = allAnnouncements
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.created > $1.created }
        deadlines = allDeadlines
            .filter { $0.dueDate > Date().addingTimeInterval(-14 * 24 * 3600) }
            .sorted { $0.dueDate < $1.dueDate }
        await deadlineNotifications.sync(deadlines: deadlines)
        lastUpdated = Date()
    }

    // MARK: - Per-course data

    func announcements(for course: Course, force: Bool = false) async throws -> [Announcement] {
        if !force, let cached = announcementsCache[course.id] { return cached }
        let items = try await client.blackboard.announcements(courseID: course.id)
        announcementsCache[course.id] = items
        return items
    }

    func contents(courseID: String, parentID: String? = nil, force: Bool = false) async throws -> [CourseContent] {
        let key = cacheKey(courseID: courseID, parentID: parentID)
        if !force, let cached = contentCache[key] { return cached }
        let items = try await client.blackboard.contents(courseID: courseID, parentID: parentID)
        contentCache[key] = items
        return items
    }

    func grade(for course: Course, force: Bool = false) async -> CourseGrade? {
        if !force, let cached = grades[course.id], Date().timeIntervalSince(cached.fetchedAt) < 600 {
            return cached
        }
        if gradesLoading.contains(course.id) { return grades[course.id] }
        gradesLoading.insert(course.id)
        defer { gradesLoading.remove(course.id) }
        do {
            let grade = try await client.blackboard.courseGrade(courseID: course.id)
            grades[course.id] = grade
            return grade
        } catch {
            present(error: error)
            return grades[course.id]
        }
    }

    func loadAllGrades(force: Bool = false) async {
        let targets = currentCourses.filter { force || grades[$0.id] == nil }
        guard !targets.isEmpty else { return }
        for course in targets { gradesLoading.insert(course.id) }
        let client = client
        await withTaskGroup(of: (String, CourseGrade?).self) { group in
            for course in targets {
                group.addTask {
                    (course.id, try? await client.blackboard.courseGrade(courseID: course.id))
                }
            }
            for await (courseID, grade) in group {
                if let grade { grades[courseID] = grade }
                gradesLoading.remove(courseID)
            }
        }
    }

    private func cacheKey(courseID: String, parentID: String?) -> String {
        "\(courseID)|\(parentID ?? "root")"
    }

    /// Called after an assignment upload so the content tree and grades are
    /// refetched on the next navigation.
    func assignmentSubmitted(courseID: String) {
        contentCache = contentCache.filter { !$0.key.hasPrefix("\(courseID)|") }
        grades[courseID] = nil
        Task { await refreshAll() }
    }

    // MARK: - Cache

    private struct Snapshot: Codable {
        let profile: UserProfile
        let courses: [Course]
        let terms: [AcademicTerm]
        let announcements: [Announcement]
        let deadlines: [Deadline]
        let savedAt: Date
    }

    private func loadSnapshot() {
        guard let profile,
              let data = try? Data(contentsOf: cacheURL),
              let snapshot = try? JSONDecoder.pku().decode(Snapshot.self, from: data),
              snapshot.profile.id == profile.id else {
            return
        }
        courses = snapshot.courses
        terms = snapshot.terms
        announcements = snapshot.announcements
        deadlines = snapshot.deadlines
        lastUpdated = snapshot.savedAt
        hasCachedData = true
        for item in snapshot.announcements {
            announcementsCache[item.courseID, default: []].append(item)
        }
    }

    private func saveSnapshot() {
        guard let profile else { return }
        let snapshot = Snapshot(
            profile: profile,
            courses: courses,
            terms: terms,
            announcements: announcements,
            deadlines: deadlines,
            savedAt: lastUpdated ?? Date()
        )
        guard let data = try? JSONEncoder.pku().encode(snapshot) else { return }
        try? data.write(to: cacheURL, options: .atomic)
        hasCachedData = true
    }

    func clearCache() {
        try? FileManager.default.removeItem(at: cacheURL)
        Task { await deadlineNotifications.sync(deadlines: []) }
        courses = []
        terms = []
        announcements = []
        deadlines = []
        grades = [:]
        announcementsCache = [:]
        contentCache = [:]
        hasCachedData = false
        lastUpdated = nil
    }

    #if DEBUG
    func debugFindContent(courseID: String, contentID: String) async -> CourseContent? {
        func search(parentID: String?, depth: Int) async -> CourseContent? {
            guard depth < 5 else { return nil }
            guard let items = try? await contents(courseID: courseID, parentID: parentID) else { return nil }
            if let match = items.first(where: { $0.id == contentID }) { return match }
            for item in items where item.isContainer {
                if let found = await search(parentID: item.id, depth: depth + 1) { return found }
            }
            return nil
        }
        return await search(parentID: nil, depth: 0)
    }
    #endif

    /// Screenshots and demos should never expose the signed-in student's name
    /// or student number.
    private func maskedProfile(_ profile: UserProfile) -> UserProfile {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["SWIFTBOARD_DEMO"] == "1" else { return profile }
        return UserProfile(
            id: profile.id,
            userName: "0000000000",
            givenName: "同学",
            familyName: "",
            email: "student@pku.edu.cn",
            department: profile.department,
            avatarURL: nil,
            systemRole: profile.systemRole
        )
        #else
        return profile
        #endif
    }

    #if DEBUG
    private func debugLog(_ message: String) {
        FileHandle.standardError.write(Data(("[app] " + message + "\n").utf8))
    }
    #else
    private func debugLog(_ message: String) {}
    #endif

    // MARK: - Errors

    func present(error: Error) {
        if let api = error as? APIError {
            switch api {
            case .notAuthenticated:
                expireSession()
            case .cancelled:
                break
            default:
                loadError = api.localizedDescription
            }
        } else if error is CancellationError {
            return
        } else {
            loadError = error.localizedDescription
        }
    }
}

extension JSONEncoder {
    static func pku() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
