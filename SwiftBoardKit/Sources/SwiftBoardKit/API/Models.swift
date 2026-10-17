import Foundation

// MARK: - User

public struct UserProfile: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let userName: String
    public let givenName: String
    public let familyName: String
    public let email: String
    public let department: String?
    public let avatarURL: URL?
    public let systemRole: String?

    public init(
        id: String,
        userName: String,
        givenName: String,
        familyName: String,
        email: String,
        department: String? = nil,
        avatarURL: URL? = nil,
        systemRole: String? = nil
    ) {
        self.id = id
        self.userName = userName
        self.givenName = givenName
        self.familyName = familyName
        self.email = email
        self.department = department
        self.avatarURL = avatarURL
        self.systemRole = systemRole
    }

    public var displayName: String {
        givenName.isEmpty ? userName : givenName
    }

    public var initials: String {
        String(displayName.prefix(1))
    }
}

// MARK: - Terms & courses

public struct AcademicTerm: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    public var sortKey: Int { TermName.sortKey(name) }
}

public enum CourseRole: String, Codable, Hashable, Sendable {
    case student
    case instructor
    case teachingAssistant
    case other

    public init(apiValue: String?) {
        switch apiValue {
        case "S", "Student": self = .student
        case "P", "Instructor": self = .instructor
        case "T", "TeachingAssistant": self = .teachingAssistant
        default: self = .other
        }
    }

    public var displayName: String {
        switch self {
        case .student: "学生"
        case .instructor: "教师"
        case .teachingAssistant: "助教"
        case .other: "成员"
        }
    }
}

public struct Course: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let externalID: String
    public let name: String
    public let displayName: String
    public let description: String
    public let termID: String?
    public let termName: String?
    public let role: CourseRole
    public let lastAccess: Date?
    public let enrolledAt: Date?
    public let colorIndex: Int
    public let isAvailable: Bool
    public let homePageURL: URL?
    public let ultraStatus: String?

    public init(
        id: String,
        externalID: String,
        name: String,
        displayName: String,
        description: String,
        termID: String?,
        termName: String?,
        role: CourseRole,
        lastAccess: Date?,
        enrolledAt: Date?,
        colorIndex: Int,
        isAvailable: Bool,
        homePageURL: URL?,
        ultraStatus: String?
    ) {
        self.id = id
        self.externalID = externalID
        self.name = name
        self.displayName = displayName
        self.description = description
        self.termID = termID
        self.termName = termName
        self.role = role
        self.lastAccess = lastAccess
        self.enrolledAt = enrolledAt
        self.colorIndex = colorIndex
        self.isAvailable = isAvailable
        self.homePageURL = homePageURL
        self.ultraStatus = ultraStatus
    }

    /// Course title without the trailing `(26-27学年第1学期)` suffix.
    public var title: String {
        let source = displayName.isEmpty ? name : displayName
        return TermName.strippingTermSuffix(source)
    }

    /// Best-known term name, even for courses whose membership lacks a term.
    public var resolvedTermName: String? {
        if let termName, !termName.isEmpty { return termName }
        if let embedded = TermName.embeddedInCourseName(name) { return embedded }
        return nil
    }

    public var resolvedTermKey: Int {
        guard let resolvedTermName else { return 0 }
        return TermName.sortKey(resolvedTermName)
    }

    public var isUltra: Bool {
        ultraStatus?.caseInsensitiveCompare("Ultra") == .orderedSame
    }
}

// MARK: - Announcements

public struct Announcement: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let courseID: String
    public let title: String
    public let bodyHTML: String
    public let creatorID: String?
    public let created: Date
    public let modified: Date?
    public let position: Int

    public init(
        id: String,
        courseID: String,
        title: String,
        bodyHTML: String,
        creatorID: String?,
        created: Date,
        modified: Date?,
        position: Int
    ) {
        self.id = id
        self.courseID = courseID
        self.title = title
        self.bodyHTML = bodyHTML
        self.creatorID = creatorID
        self.created = created
        self.modified = modified
        self.position = position
    }

    public var preview: String { bodyHTML.snippet() }
}

// MARK: - Course content

public enum ContentKind: String, Codable, Hashable, Sendable {
    case folder
    case file
    case document
    case assignment
    case test
    case link
    case lesson
    case discussion
    case other

    public var isContainer: Bool {
        self == .folder || self == .lesson
    }
}

public struct ContentFile: Codable, Hashable, Sendable {
    public let name: String
    public let mimeType: String?
    public let url: URL?

    public init(name: String, mimeType: String?, url: URL?) {
        self.name = name
        self.mimeType = mimeType
        self.url = url
    }
}

public struct CourseContent: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let courseID: String
    public let parentID: String?
    public let title: String
    public let handler: String
    public let kind: ContentKind
    public let description: String
    public let bodyHTML: String
    public let position: Int
    public let dueDate: Date?
    public let possiblePoints: Double?
    public let gradeColumnID: String?
    public let file: ContentFile?
    public let externalURL: URL?
    public let isAvailable: Bool

    public init(
        id: String,
        courseID: String,
        parentID: String?,
        title: String,
        handler: String,
        kind: ContentKind,
        description: String,
        bodyHTML: String,
        position: Int,
        dueDate: Date?,
        possiblePoints: Double?,
        gradeColumnID: String? = nil,
        file: ContentFile?,
        externalURL: URL?,
        isAvailable: Bool
    ) {
        self.id = id
        self.courseID = courseID
        self.parentID = parentID
        self.title = title
        self.handler = handler
        self.kind = kind
        self.description = description
        self.bodyHTML = bodyHTML
        self.position = position
        self.dueDate = dueDate
        self.possiblePoints = possiblePoints
        self.gradeColumnID = gradeColumnID
        self.file = file
        self.externalURL = externalURL
        self.isAvailable = isAvailable
    }

    public var isContainer: Bool { kind.isContainer }

    public var hasBody: Bool {
        !bodyHTML.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var subtitle: String {
        switch kind {
        case .file:
            if let file { return file.name }
            return "文件"
        case .document: return "页面"
        case .assignment:
            if let dueDate {
                return "作业 · 截止 \(dueDate.formatted(date: .abbreviated, time: .shortened))"
            }
            return "作业"
        case .test: return "在线测试"
        case .link: return externalURL?.host() ?? "外部链接"
        case .folder: return "文件夹"
        case .lesson: return "课程单元"
        case .discussion: return "讨论板"
        case .other: return handler.replacingOccurrences(of: "resource/x-bb-", with: "")
        }
    }
}

// MARK: - Grades

public struct GradeColumn: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let possible: Double
    public let dueDate: Date?
    public let isVisible: Bool
    public let calculationType: String?
    public let contentID: String?
    public let gradesReleased: Bool

    public init(
        id: String,
        name: String,
        possible: Double,
        dueDate: Date?,
        isVisible: Bool,
        calculationType: String?,
        contentID: String?,
        gradesReleased: Bool
    ) {
        self.id = id
        self.name = name
        self.possible = possible
        self.dueDate = dueDate
        self.isVisible = isVisible
        self.calculationType = calculationType
        self.contentID = contentID
        self.gradesReleased = gradesReleased
    }

    public var isTotal: Bool {
        let type = calculationType?.uppercased() ?? ""
        return type.contains("TOTAL") || name.contains("总计")
    }

    public var isWeightedTotal: Bool {
        (calculationType?.uppercased() ?? "").contains("WEIGHTED") || name.contains("加权")
    }
}

public struct UserGrade: Codable, Hashable, Sendable {
    public let columnID: String
    public let score: Double?
    public let text: String?
    public let status: String?
    public let exempt: Bool

    public init(columnID: String, score: Double?, text: String?, status: String?, exempt: Bool) {
        self.columnID = columnID
        self.score = score
        self.text = text
        self.status = status
        self.exempt = exempt
    }
}

public struct GradeItem: Codable, Hashable, Sendable, Identifiable {
    public let column: GradeColumn
    public let score: Double?
    public let text: String?
    public let status: String?
    public let exempt: Bool

    public init(column: GradeColumn, score: Double?, text: String?, status: String?, exempt: Bool) {
        self.column = column
        self.score = score
        self.text = text
        self.status = status
        self.exempt = exempt
    }

    public var id: String { column.id }
    public var name: String { column.name }
    public var possible: Double { column.possible }
    public var isGraded: Bool { score != nil || (text?.isEmpty == false) }
    public var isPending: Bool {
        status?.caseInsensitiveCompare("NeedsGrading") == .orderedSame
            || status?.caseInsensitiveCompare("NeedsGradingMultipleAttempts") == .orderedSame
    }
    public var isExempt: Bool { exempt || status?.caseInsensitiveCompare("Exempt") == .orderedSame }
}

public struct CourseGrade: Codable, Hashable, Sendable, Identifiable {
    public let courseID: String
    public let items: [GradeItem]
    public let total: GradeItem?
    public let weightedTotal: GradeItem?
    public let fetchedAt: Date

    public init(
        courseID: String,
        items: [GradeItem],
        total: GradeItem?,
        weightedTotal: GradeItem?,
        fetchedAt: Date
    ) {
        self.courseID = courseID
        self.items = items
        self.total = total
        self.weightedTotal = weightedTotal
        self.fetchedAt = fetchedAt
    }

    public var id: String { courseID }

    public var gradedItems: [GradeItem] { items.filter { $0.isGraded && !$0.isExempt } }

    public var earnedPoints: Double {
        gradedItems.compactMap(\.score).reduce(0, +)
    }

    public var gradedPossible: Double {
        gradedItems.filter { $0.score != nil }.map(\.possible).reduce(0, +)
    }

    public var totalPossible: Double {
        items.map(\.possible).filter { $0 > 0 }.reduce(0, +)
    }

    public var releasedScore: Double? {
        total?.score ?? weightedTotal?.score
    }

    public var releasedPossible: Double? {
        if let total, total.possible > 0 { return total.possible }
        if let weightedTotal, weightedTotal.possible > 0 { return weightedTotal.possible }
        return nil
    }

    public var displayScore: Double? { releasedScore ?? (gradedItems.isEmpty ? nil : earnedPoints) }

    public var displayPossible: Double {
        releasedPossible ?? (totalPossible > 0 ? totalPossible : gradedPossible)
    }

    public var hasReleasedTotal: Bool { releasedScore != nil }

    public var progress: Double? {
        if let score = releasedScore, let possible = releasedPossible, possible > 0 {
            return min(1, max(0, score / possible))
        }
        guard totalPossible > 0 else { return nil }
        return min(1, max(0, earnedPoints / totalPossible))
    }
}

// MARK: - Deadlines

public struct Deadline: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let courseID: String
    public let courseName: String
    public let title: String
    public let dueDate: Date
    public let possible: Double?
    public let colorIndex: Int

    public init(courseID: String, courseName: String, title: String, dueDate: Date, possible: Double?, colorIndex: Int) {
        self.id = "\(courseID)-\(title)-\(dueDate.timeIntervalSince1970)"
        self.courseID = courseID
        self.courseName = courseName
        self.title = title
        self.dueDate = dueDate
        self.possible = possible
        self.colorIndex = colorIndex
    }
}
