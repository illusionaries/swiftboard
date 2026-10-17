import SwiftUI
import SwiftBoardKit

struct CourseDetailView: View {
    let course: Course

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var tab: CourseTab

    init(course: Course, initialTab: CourseTab = .content) {
        self.course = course
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero
                tabSelector
                tabContent
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 44)
            .frame(maxWidth: 1020, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .navigationTitle(course.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openURL(model.client.blackboard.coursePageURL(for: course))
                } label: {
                    Image(systemName: "safari")
                }
                .help("在浏览器中打开课程")
                .accessibilityLabel("在浏览器中打开课程")
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.courseGradient(course.colorIndex))

            Text(String(course.title.prefix(1)))
                .font(.system(size: 190, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.08))
                .offset(x: 26, y: 54)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if let term = course.resolvedTermName {
                        chip(term, icon: "calendar")
                    }
                    if !course.description.isEmpty {
                        chip(course.description, icon: nil)
                    }
                    if course.role != .student {
                        chip(course.role.displayName, icon: "person.badge.key")
                    }
                    Spacer()
                }

                Spacer(minLength: 20)

                Text(course.title)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(3)
                    .minimumScaleFactor(0.7)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)

                Text(course.isAvailable ? "课程进行中" : "课程已结束")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
                    .padding(.top, 8)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Button {
                openURL(model.client.blackboard.coursePageURL(for: course))
            } label: {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(18)
            .help("在浏览器中打开")
        }
        .frame(height: 212)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.8)
        }
        .shadow(color: Theme.courseColors(course.colorIndex).1.opacity(0.22), radius: 18, y: 10)
    }

    private func chip(_ text: String, icon: String?) -> some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
            }
            Text(text)
        }
        .font(.caption2.weight(.medium))
        .foregroundStyle(.white.opacity(0.92))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.white.opacity(0.16), in: Capsule())
    }

    // MARK: - Tabs

    private var tabSelector: some View {
        HStack(spacing: 4) {
            ForEach(CourseTab.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) { tab = item }
                } label: {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tab == item ? Theme.accent : Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if tab == item {
                                Capsule().fill(Theme.card)
                                    .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Theme.subtleFill, in: Capsule())
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .content:
            CourseContentSection(course: course)
        case .videos:
            CourseVideosSection(course: course)
        case .announcements:
            CourseAnnouncementsSection(course: course)
        case .grades:
            CourseGradesSection(course: course)
        case .info:
            CourseInfoSection(course: course)
        }
    }
}

// MARK: - Content

struct CourseContentSection: View {
    let course: Course
    @Environment(AppModel.self) private var model

    @State private var items: [CourseContent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "课程内容",
                subtitle: items.isEmpty ? nil : "\(items.count) 个项目",
                actionTitle: "刷新",
                showsChevron: false,
                action: { Task { await load(force: true) } }
            )

            if isLoading && items.isEmpty {
                LoadingRows(count: 4)
            } else if let errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await load(force: true) }
                }
            } else if items.isEmpty {
                EmptyStateView(
                    symbol: "folder",
                    title: "暂无课程内容",
                    message: "老师还没有在这门课程中发布内容。"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: AppRoute.content(item)) {
                            ContentRow(content: item)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        if index < items.count - 1 {
                            Divider().padding(.leading, 66)
                        }
                    }
                }
                .cardSurface(padding: 0, radius: 18)
            }
        }
        .task(id: course.id) { await load() }
    }

    private func load(force: Bool = false) async {
        if !force, !items.isEmpty { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await model.contents(courseID: course.id, force: force)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Announcements

struct CourseAnnouncementsSection: View {
    let course: Course
    @Environment(AppModel.self) private var model

    @State private var items: [Announcement] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "课程通知",
                subtitle: items.isEmpty ? nil : "\(items.count) 条",
                actionTitle: "刷新",
                showsChevron: false,
                action: { Task { await load(force: true) } }
            )

            if isLoading && items.isEmpty {
                LoadingRows(count: 3)
            } else if let errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await load(force: true) }
                }
            } else if items.isEmpty {
                EmptyStateView(
                    symbol: "megaphone",
                    title: "暂无课程通知",
                    message: "老师还没有发布通知。"
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: AppRoute.announcement(item)) {
                            AnnouncementRow(announcement: item, course: course, showsCourse: false)
                                .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        if index < items.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .cardSurface(padding: 0, radius: 18)
            }
        }
        .task(id: course.id) { await load() }
    }

    private func load(force: Bool = false) async {
        if !force, !items.isEmpty { return }
        isLoading = true
        defer { isLoading = false }
        do {
            items = try await model.announcements(for: course, force: force)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Info

struct CourseInfoSection: View {
    let course: Course
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "课程信息", subtitle: nil, actionTitle: nil, action: nil)

            VStack(spacing: 0) {
                infoRow("课程名称", course.displayName)
                Divider().padding(.leading, 16)
                infoRow("课程编号", course.externalID)
                Divider().padding(.leading, 16)
                infoRow("学期", course.resolvedTermName ?? "—")
                Divider().padding(.leading, 16)
                infoRow("课程类型", course.description.isEmpty ? "—" : course.description)
                Divider().padding(.leading, 16)
                infoRow("我的身份", course.role.displayName)
                Divider().padding(.leading, 16)
                infoRow("课程 ID", course.id)
                Divider().padding(.leading, 16)
                infoRow("状态", course.isAvailable ? "可访问" : "已结束")
                Divider().padding(.leading, 16)

                Button {
                    openURL(model.client.blackboard.coursePageURL(for: course))
                } label: {
                    HStack {
                        Text("在教学网中打开")
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
            .cardSurface(padding: 0, radius: 18)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
    }
}
