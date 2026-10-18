import Foundation

// MARK: - Shared envelopes

struct PagedDTO<Item: Decodable>: Decodable {
    let results: [Item]
    let paging: PagingDTO?
}

struct PagingDTO: Decodable {
    let nextPage: String?
}

struct BodyDTO: Decodable {
    let rawText: String?
    let displayText: String?
    let webLocation: String?
}

// MARK: - User

struct ProfileDTO: Decodable {
    let id: String
    let userName: String
    let givenName: String?
    let familyName: String?
    let emailAddress: String?
    let department: String?
    let systemRole: String?
    let avatar: AvatarDTO?
}

struct AvatarDTO: Decodable {
    let permanentUrl: String?
}

// MARK: - Courses

struct TermDTO: Decodable {
    let id: String
    let name: String
}

struct CourseDTO: Decodable {
    let id: String
    let courseId: String?
    let name: String?
    let displayName: String?
    let description: String?
    let termId: String?
    let term: TermDTO?
    let homePageUrl: String?
    let isAvailable: Bool?
    let ultraStatus: String?
}

struct MembershipDTO: Decodable {
    let courseId: String
    let role: String?
    let courseCardColorIndex: Int?
    let isAvailable: Bool?
    let lastAccessDate: Date?
    let enrollmentDate: Date?
    let course: CourseDTO?
}

// MARK: - Announcements

struct AnnouncementDTO: Decodable {
    let id: String
    let courseId: String?
    let title: String?
    let body: BodyDTO?
    let creatorUserId: String?
    let createdDate: Date?
    let modifiedDate: Date?
    let position: Int?
    let isDraft: Bool?
}

// MARK: - Content

struct FileDTO: Decodable {
    let fileName: String?
    let mimeType: String?
    let permanentUrl: String?
    let size: Int?
}

struct GradingColumnDTO: Decodable {
    let id: String?
    let dueDate: Date?
    let possible: Double?
    let contentId: String?
    /// Blackboard uses 0 for unlimited attempts and 1 for a single attempt.
    let multipleAttempts: Int?
}

struct ContentDetailPayloadDTO: Decodable {
    let isFolder: Bool?
    let isBbPage: Bool?
    let file: FileDTO?
    let gradingColumn: GradingColumnDTO?
    let url: String?
    let fileName: String?
}

struct ContentDTO: Decodable {
    let id: String
    let courseId: String?
    let parentId: String?
    let title: String?
    let contentHandler: String?
    let description: String?
    let body: BodyDTO?
    let position: Int?
    let isAvailable: Bool?
    let contentDetail: [String: ContentDetailPayloadDTO]?
}

// MARK: - Grades

struct GradeColumnDTO: Decodable {
    let id: String
    let columnName: String?
    let possible: Double?
    let dueDate: Date?
    let visible: Bool?
    let deleted: Bool?
    let calculationType: String?
    let contentId: String?
    let gradesReleased: Bool?
    let scorable: Bool?
}

struct DisplayGradeDTO: Decodable {
    let scaleType: String?
    let score: Double?
    let text: String?
}

struct UserGradeDTO: Decodable {
    let userId: String?
    let columnId: String
    let status: String?
    let displayGrade: DisplayGradeDTO?
    let exempt: Bool?
}

struct UserGradesDTO: Decodable {
    let results: [UserGradeDTO]
}

// MARK: - Login

struct IAAAPublicKeyDTO: Decodable {
    let success: Bool
    let key: String
}

struct IAAALoginDTO: Decodable {
    let success: Bool
    let token: String?
    let errors: IAAAErrorDTO?
    let showCode: Bool?
}

struct IAAAErrorDTO: Decodable {
    let code: String?
    let msg: String?
}
