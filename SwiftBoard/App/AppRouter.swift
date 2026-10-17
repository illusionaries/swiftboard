import Foundation
import Observation
import SwiftUI
import SwiftBoardKit

enum AppSection: String, CaseIterable, Identifiable, Hashable {
    case home
    case courses
    case announcements
    case grades
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .courses: "课程"
        case .announcements: "通知"
        case .grades: "成绩"
        case .settings: "我的"
        }
    }

    var sidebarTitle: String {
        switch self {
        case .home: "首页"
        case .courses: "我的课程"
        case .announcements: "课程通知"
        case .grades: "成绩"
        case .settings: "设置"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .courses: "books.vertical"
        case .announcements: "megaphone"
        case .grades: "chart.bar.doc.horizontal"
        case .settings: "person.crop.circle"
        }
    }

    var selectedIcon: String {
        switch self {
        case .home: "house.fill"
        case .courses: "books.vertical.fill"
        case .announcements: "megaphone.fill"
        case .grades: "chart.bar.doc.horizontal.fill"
        case .settings: "person.crop.circle.fill"
        }
    }
}

enum CourseTab: String, CaseIterable, Identifiable, Hashable {
    case content
    case videos
    case announcements
    case grades
    case info

    var id: String { rawValue }

    var title: String {
        switch self {
        case .content: "内容"
        case .videos: "回放"
        case .announcements: "通知"
        case .grades: "成绩"
        case .info: "信息"
        }
    }
}

enum AppRoute: Hashable {
    case course(id: String, tab: CourseTab)
    case content(CourseContent)
    case gradeContent(courseID: String, contentID: String)
    case announcement(Announcement)
}

@MainActor
@Observable
final class AppRouter {
    var section: AppSection = .home
    var homePath = NavigationPath()
    var coursesPath = NavigationPath()
    var announcementsPath = NavigationPath()
    var gradesPath = NavigationPath()
    var settingsPath = NavigationPath()

    func openCourse(_ course: Course, tab: CourseTab = .content) {
        section = .courses
        coursesPath = NavigationPath()
        coursesPath.append(AppRoute.course(id: course.id, tab: tab))
    }

    func show(_ section: AppSection) {
        self.section = section
    }

    #if DEBUG
    func openDebugContent(courseID: String, contentID: String, model: AppModel) async {
        guard let item = await model.debugFindContent(courseID: courseID, contentID: contentID) else { return }
        section = .courses
        coursesPath = NavigationPath()
        coursesPath.append(AppRoute.content(item))
    }

    func apply(debugRoute route: String, model: AppModel) {
        let parts = route.split(separator: ":").map(String.init)
        switch parts.first {
        case "course":
            guard parts.count >= 2, let course = model.course(id: parts[1]) else { return }
            let tab = parts.count >= 3 ? (CourseTab(rawValue: parts[2]) ?? .content) : .content
            openCourse(course, tab: tab)
        case "gradecontent":
            guard parts.count >= 3 else { return }
            section = .courses
            coursesPath = NavigationPath()
            coursesPath.append(AppRoute.gradeContent(courseID: parts[1], contentID: parts[2]))
        case "announcement":
            guard parts.count >= 2, let item = model.announcements.first(where: { $0.id == parts[1] }) else { return }
            section = .announcements
            announcementsPath = NavigationPath()
            announcementsPath.append(AppRoute.announcement(item))
        case "tab":
            if let raw = parts.dropFirst().first, let target = AppSection(rawValue: raw) {
                show(target)
            }
        default:
            break
        }
    }
    #endif

    func handle(_ url: URL, model: AppModel) {
        guard url.scheme == "swiftboard" else { return }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let host = components?.host ?? ""
        let segments = url.pathComponents.filter { $0 != "/" }
        let query = Dictionary(uniqueKeysWithValues: (components?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })

        switch host {
        case "course":
            guard let id = segments.first, let course = model.course(id: id) else { return }
            let tab = query["tab"].flatMap(CourseTab.init(rawValue:)) ?? .content
            openCourse(course, tab: tab)
        case "tab":
            if let raw = segments.first, let target = AppSection(rawValue: raw) {
                show(target)
            }
        case "announcement":
            guard let id = segments.first else { return }
            let pool = model.announcements + model.currentCourses.flatMap { course in
                model.announcements.filter { $0.courseID == course.id }
            }
            if let item = pool.first(where: { $0.id == id }) {
                section = .announcements
                announcementsPath = NavigationPath()
                announcementsPath.append(AppRoute.announcement(item))
            }
        default:
            break
        }
    }
}
