import SwiftUI
import SwiftBoardKit
import QuickLook
#if os(macOS)
import QuickLookUI
#endif

struct MainShell: View {
    @Environment(DownloadCenter.self) private var downloads

    var body: some View {
        @Bindable var downloads = downloads
        shellContent
            .quickLookPreview($downloads.previewURL)
            #if os(macOS)
            .frame(minWidth: 980, minHeight: 620)
            #endif
    }

    @ViewBuilder
    private var shellContent: some View {
        #if os(macOS)
        SplitShell()
        #else
        if horizontalSizeClass == .regular {
            SplitShell()
        } else {
            CompactShell()
        }
        #endif
    }

    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
}

struct SplitShell: View {
    @Environment(AppRouter.self) private var router
    @State private var visibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 232, ideal: 258, max: 300)
        } detail: {
            SectionDetail(section: router.section)
        }
        .navigationSplitViewStyle(.balanced)
    }
}

struct CompactShell: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.section) {
            SectionStack(section: .home, path: $router.homePath)
                .tabItem { Label("首页", systemImage: router.section == .home ? "house.fill" : "house") }
                .tag(AppSection.home)

            SectionStack(section: .courses, path: $router.coursesPath)
                .tabItem { Label("课程", systemImage: router.section == .courses ? "books.vertical.fill" : "books.vertical") }
                .tag(AppSection.courses)

            SectionStack(section: .announcements, path: $router.announcementsPath)
                .tabItem { Label("通知", systemImage: router.section == .announcements ? "megaphone.fill" : "megaphone") }
                .tag(AppSection.announcements)

            SectionStack(section: .grades, path: $router.gradesPath)
                .tabItem { Label("成绩", systemImage: router.section == .grades ? "chart.bar.doc.horizontal.fill" : "chart.bar.doc.horizontal") }
                .tag(AppSection.grades)

            SectionStack(section: .settings, path: $router.settingsPath)
                .tabItem { Label("我的", systemImage: router.section == .settings ? "person.crop.circle.fill" : "person.crop.circle") }
                .tag(AppSection.settings)
        }
    }
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            Section {
                row(.home)
                row(.courses)
                row(.announcements)
                row(.grades)
            }

            Section {
                row(.settings)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(
            LinearGradient(
                colors: [Theme.canvas, Theme.canvas.opacity(0.94)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationTitle("SwiftBoard")
        .safeAreaInset(edge: .bottom) {
            SidebarProfile()
        }
    }

    private func row(_ section: AppSection) -> some View {
        let selected = router.section == section
        return Button {
            router.section = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? section.selectedIcon : section.icon)
                    .frame(width: 20)
                    .foregroundStyle(selected ? Theme.accent : .secondary)
                Text(section.sidebarTitle)
                    .foregroundStyle(.primary)
                Spacer(minLength: 4)
                if section == .announcements, !model.announcements.isEmpty {
                    Text("\(model.announcements.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if section == .grades, !model.currentCourses.isEmpty {
                    Text("\(model.currentCourses.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 7)
            .background(
                selected ? Theme.accent.opacity(0.11) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
        .listRowBackground(Color.clear)
    }
}

struct SidebarProfile: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        Group {
            if let profile = model.profile {
                Button {
                    router.section = .settings
                } label: {
                    HStack(spacing: 10) {
                        AvatarView(initials: profile.initials, size: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(profile.displayName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(profile.userName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(9)
                    .background(Theme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 0.8)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
    }
}

struct SectionDetail: View {
    let section: AppSection
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        switch section {
        case .home:
            SectionStack(section: .home, path: $router.homePath)
        case .courses:
            SectionStack(section: .courses, path: $router.coursesPath)
        case .announcements:
            SectionStack(section: .announcements, path: $router.announcementsPath)
        case .grades:
            SectionStack(section: .grades, path: $router.gradesPath)
        case .settings:
            SectionStack(section: .settings, path: $router.settingsPath)
        }
    }
}

struct SectionStack: View {
    let section: AppSection
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
            content
                .navigationDestination(for: AppRoute.self) { route in
                    RouteDestination(route: route)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section {
        case .home:
            HomeView()
        case .courses:
            CoursesView()
        case .announcements:
            AnnouncementsView()
        case .grades:
            GradesView()
        case .settings:
            SettingsView()
        }
    }
}

struct RouteDestination: View {
    let route: AppRoute
    @Environment(AppModel.self) private var model

    var body: some View {
        switch route {
        case .course(let id, let tab):
            if let course = model.course(id: id) {
                CourseDetailView(course: course, initialTab: tab)
            } else {
                EmptyStateView(symbol: "questionmark.folder", title: "找不到这门课程", message: "它可能已从教学网移除。")
            }
        case .content(let content):
            if let course = model.course(id: content.courseID) {
                ContentDetailView(course: course, content: content)
            } else {
                EmptyStateView(symbol: "questionmark.folder", title: "找不到该内容")
            }
        case .gradeContent(let courseID, let contentID):
            ContentByIDView(courseID: courseID, contentID: contentID)
        case .announcement(let announcement):
            AnnouncementDetailView(announcement: announcement, course: model.course(id: announcement.courseID))
        case .downloads:
            ReplayDownloadsView()
        }
    }
}
