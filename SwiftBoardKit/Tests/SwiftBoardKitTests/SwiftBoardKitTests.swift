import Foundation
import Security
import Testing
@testable import SwiftBoardKit

@Suite("Term names")
struct TermNameTests {
    @Test func parsesAndSorts() {
        #expect(TermName.sortKey("26-27学年第一学期") == 20261)
        #expect(TermName.sortKey("25-26学年第二学期") == 20252)
        #expect(TermName.sortKey("26-27学年第1学期") == 20261)
        #expect(TermName.sortKey("20-21学年第三学期") == 20203)
        #expect(TermName.sortKey("未知") == 0)
        #expect(TermName.sortKey("26-27学年第一学期") > TermName.sortKey("25-26学年第二学期"))
    }

    @Test func normalizesOrdinals() {
        #expect(TermName.normalized("26-27学年第1学期") == "26-27学年第一学期")
        #expect(TermName.normalized("26-27学年1学期") == "26-27学年第一学期")
    }

    @Test func extractsSuffix() {
        let name = "示例课程(26-27学年第1学期)"
        #expect(TermName.embeddedInCourseName(name) == "26-27学年第1学期")
        #expect(TermName.strippingTermSuffix(name) == "示例课程")
        #expect(TermName.embeddedInCourseName("大学英语") == nil)
    }
}

@Suite("HTML previews")
struct HTMLTests {
    @Test func stripsTagsAndEntities() {
        let html = "<div class=\"vtbegenerated\"><p>同学们好！&nbsp;第一章</p><p>作业 &amp; 讲义&hellip;</p></div>"
        let text = html.htmlToPlainText
        #expect(text.contains("同学们好！"))
        #expect(text.contains("作业 & 讲义…"))
        #expect(!text.contains("<p>"))
    }

    @Test func truncatesSnippet() {
        let html = String(repeating: "一", count: 400)
        let snippet = html.snippet(limit: 50)
        #expect(snippet.count == 51)
        #expect(snippet.hasSuffix("…"))
    }
}

@Suite("Dates and JSON")
struct DateTests {
    @Test func parsesFractionalSeconds() {
        #expect(APIDate.parse("2026-10-17T10:11:34.000Z") != nil)
        #expect(APIDate.parse("2026-09-23T15:59:00.000Z") != nil)
        #expect(APIDate.parse(nil) == nil)
    }

    @Test func decodesContentDTO() throws {
        let json = """
        {"id":"_1_1","title":"课件","position":0,"contentHandler":"resource/x-bb-file",
         "contentDetail":{"resource/x-bb-file":{"file":{"fileName":"a.pdf","mimeType":"application/pdf","permanentUrl":"/bbcswebdav/x"}}}}
        """
        let dto = try JSONDecoder.pku().decode(ContentDTO.self, from: Data(json.utf8))
        #expect(dto.contentHandler == "resource/x-bb-file")
        #expect(dto.contentDetail?["resource/x-bb-file"]?.file?.fileName == "a.pdf")
    }
}

@Suite("RSA")
struct RSATests {
    let publicKey = """
    -----BEGIN PUBLIC KEY-----
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwdLSGNuuGH5YCPq3uezF
    P7zWW74gYpHTmJ/ktq5RHOphiD6p8Pbih+T3lWvLjXPgB4TrEh5OzIOPn5ywIlQ8
    Tii4eJ0auStf5FcaB/gUt4xDDYOlxY9Wcti9gv2wByiTTlcABLNgfhM7LeIUOiDh
    8NJYEmTLLrk/U1PZMmulGGyi+HDRxnfeRnDlj6/cD1PpDOsZ/3J5CK1ZSBgvS/In
    Cvkr0FWYyElR1xG64GBsnTPSMakEZM+HlbR91Cjr0ia51M7yYWQZ0P7nh9+yGluU
    BjCEV+dh6lTqstrbY3pWZIN8aABhNE/00bYTtHWFkVMtPvZ3xw6QBR9Py2+1UPBk
    OwIDAQAB
    -----END PUBLIC KEY-----
    """

    @Test func extractsPKCS1Key() throws {
        let key = try RSA.pkcs1Key(fromPEM: publicKey)
        #expect(key.first == 0x30)
        #expect(key.count > 250)
    }

    @Test func encryptsWithPKCS1() throws {
        let encrypted = try RSA.encrypt("测试密码-test-123", publicKeyPEM: publicKey)
        let data = Data(base64Encoded: encrypted)
        #expect(data?.count == 256)
    }
}

@Suite("Course model")
struct CourseTests {
    @Test func stripsTermFromTitle() {
        let course = Course(
            id: "_1_1", externalID: "x", name: "高等数学(25-26学年第2学期)",
            displayName: "高等数学(25-26学年第2学期)", description: "必修",
            termID: "_2_1", termName: nil, role: .student, lastAccess: nil,
            enrolledAt: nil, colorIndex: 1, isAvailable: true, homePageURL: nil, ultraStatus: "CLASSIC"
        )
        #expect(course.title == "高等数学")
        #expect(course.resolvedTermName == "25-26学年第2学期")
    }
}

@Suite("Grades")
struct GradeTests {
    private func column(_ id: String, _ name: String, possible: Double, due: Date? = nil, type: String = "NON_CALCULATED") -> GradeColumn {
        GradeColumn(id: id, name: name, possible: possible, dueDate: due, isVisible: true, calculationType: type, contentID: nil, gradesReleased: true)
    }

    @Test func aggregatesScores() {
        let items = [
            GradeItem(column: column("a", "作业一", possible: 10), score: 8.5, text: nil, status: "Graded", exempt: false),
            GradeItem(column: column("b", "作业二", possible: 10), score: nil, text: nil, status: "NeedsGrading", exempt: false)
        ]
        let grade = CourseGrade(
            courseID: "c",
            items: items,
            total: GradeItem(column: column("t", "总计", possible: 20, type: "TOTAL"), score: nil, text: nil, status: nil, exempt: false),
            weightedTotal: nil,
            fetchedAt: Date()
        )
        #expect(grade.gradedItems.count == 1)
        #expect(grade.earnedPoints == 8.5)
        #expect(grade.gradedPossible == 10)
        #expect(grade.displayScore == 8.5)
        #expect(grade.displayPossible == 20)
        #expect(grade.progress == 0.425)
        #expect(grade.hasReleasedTotal == false)
        #expect(items[1].isPending)
    }

    @Test func prefersReleasedTotal() {
        let total = GradeItem(column: column("t", "总计", possible: 100, type: "TOTAL"), score: 91, text: nil, status: "Graded", exempt: false)
        let grade = CourseGrade(
            courseID: "c",
            items: [GradeItem(column: column("a", "作业", possible: 10), score: 10, text: nil, status: "Graded", exempt: false)],
            total: total,
            weightedTotal: nil,
            fetchedAt: Date()
        )
        #expect(grade.displayScore == 91)
        #expect(grade.displayPossible == 100)
        #expect(grade.progress == 0.91)
        #expect(grade.hasReleasedTotal)
    }
}

@Suite("Content")
struct ContentTests {
    @Test func kindAndContainerFlags() {
        #expect(ContentKind.folder.isContainer)
        #expect(ContentKind.lesson.isContainer)
        #expect(!ContentKind.file.isContainer)
        #expect(!ContentKind.assignment.isContainer)
    }

    @Test func plainTextHandlesLists() {
        let html = "<ul><li>一</li><li>二</li></ul><p>结束</p>"
        let text = html.htmlToPlainText
        #expect(text.contains("• 一"))
        #expect(text.contains("结束"))
    }
}
