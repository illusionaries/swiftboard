import Foundation
import SwiftBoardKit

/// Small command line harness used during development to exercise the real
/// endpoints against the live PKU servers.
@main
struct Probe {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "summary"
        let environment = ProcessInfo.processInfo.environment

        guard let account = credential(named: "BB_USERNAME", file: ".bb_account", environment: environment),
              let password = credential(named: "BB_PASSWORD", file: ".bb_password", environment: environment) else {
            fail("缺少凭据：请设置 BB_USERNAME/BB_PASSWORD 或在工作目录提供 .bb_account/.bb_password")
        }

        let client = PKUClient(persistCookies: false)
        do {
            let profile = try await client.signIn(username: account, password: password)
            log("登录成功：\(profile.displayName) (\(profile.userName))")

            switch command {
            case "login":
                print(try encode(profile))

            case "courses":
                let courses = try await client.blackboard.enrollments()
                for course in courses {
                    print("\(course.id)\t\(course.termName ?? "-")\t\(course.title)")
                }

            case "terms":
                for term in try await client.blackboard.terms() {
                    print("\(term.id)\t\(term.name)\t\(term.sortKey)")
                }

            case "summary":
                let courses = try await client.blackboard.enrollments()
                let current = courses.filter { $0.resolvedTermKey == courses.map(\.resolvedTermKey).max() }
                log("课程 \(courses.count) 门，当前学期 \(current.count) 门")
                var announcementCount = 0
                await withTaskGroup(of: Int.self) { group in
                    for course in current {
                        group.addTask {
                            let items = (try? await client.blackboard.announcements(courseID: course.id)) ?? []
                            if !items.isEmpty {
                                log("通知 \(course.title)：\(items.count) 条")
                            }
                            return items.count
                        }
                    }
                    for await count in group { announcementCount += count }
                }
                log("通知合计 \(announcementCount) 条")

                for course in current.prefix(4) {
                    if let grade = try? await client.blackboard.courseGrade(courseID: course.id) {
                        let score = grade.displayScore.map { String(format: "%.1f", $0) } ?? "—"
                        log("成绩 \(course.title)：\(score)/\(String(format: "%.0f", grade.displayPossible))，\(grade.items.count) 项")
                    }
                }

            case "content":
                guard arguments.count > 1 else { fail("用法：content <courseID>") }
                let courseID = arguments[1]
                let items = try await client.blackboard.contents(courseID: courseID)
                for item in items {
                    print("\(item.position)\t\(item.kind.rawValue)\t\(item.title)")
                    if item.isContainer {
                        let children = (try? await client.blackboard.contents(courseID: courseID, parentID: item.id)) ?? []
                        for child in children {
                            print("    \(child.kind.rawValue)\t\(child.title)\t\(child.file?.name ?? "")")
                        }
                    }
                }

            case "grades":
                let courses = try await client.blackboard.enrollments()
                for course in courses {
                    guard let grade = try? await client.blackboard.courseGrade(courseID: course.id) else { continue }
                    print("\(course.title)\t\(grade.displayScore ?? -1)\t\(grade.displayPossible)")
                }

            case "download":
                guard arguments.count > 3 else { fail("用法：download <courseID> <contentID> <destination>") }
                let courseID = arguments[1]
                let contentID = arguments[2]
                let destination = URL(fileURLWithPath: arguments[3])
                guard let course = try await client.blackboard.enrollments().first(where: { $0.id == courseID }) else {
                    fail("找不到课程")
                }
                guard let content = try await findContent(client, courseID: courseID, contentID: contentID) else {
                    fail("找不到内容")
                }
                log("下载 \(content.title)…")
                let url = try await client.blackboard.download(content: content, course: course, to: destination) { progress in
                    if Int(progress * 100) % 25 == 0 { log("  \(Int(progress * 100))%") }
                }
                log("已保存到 \(url.path)")

            default:
                fail("未知命令：\(command)")
            }
        } catch {
            fail("失败：\(error.localizedDescription)")
        }
    }

    static func findContent(_ client: PKUClient, courseID: String, contentID: String, parentID: String? = nil, depth: Int = 0) async throws -> CourseContent? {
        guard depth < 5 else { return nil }
        let items = try await client.blackboard.contents(courseID: courseID, parentID: parentID)
        if let match = items.first(where: { $0.id == contentID }) { return match }
        for item in items where item.isContainer {
            if let found = try await findContent(client, courseID: courseID, contentID: contentID, parentID: item.id, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    static func credential(named name: String, file: String, environment: [String: String]) -> String? {
        if let value = environment[name], !value.isEmpty { return value }
        let path = FileManager.default.currentDirectoryPath + "/" + file
        guard let value = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return String(data: try encoder.encode(value), encoding: .utf8) ?? ""
    }

    static func log(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }

    static func fail(_ message: String) -> Never {
        log(message)
        exit(1)
    }
}
