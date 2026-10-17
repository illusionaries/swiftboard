import SwiftUI
import SwiftBoardKit

struct AnnouncementRow: View {
    let announcement: Announcement
    var course: Course?
    var showsCourse = true

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Theme.courseColor(course?.colorIndex ?? 0))
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    if showsCourse {
                        Text(course?.title ?? "课程通知")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(Theme.courseColor(course?.colorIndex ?? 0))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(SBDate.relative(announcement.created))
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
                Text(announcement.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                if !announcement.preview.isEmpty {
                    Text(announcement.preview)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if let error = model.loadError {
                    ErrorBanner(message: error) {
                        Task { await model.refreshAll() }
                    }
                }

                if model.currentCourses.isEmpty && model.isRefreshing {
                    LoadingRows(count: 4)
                } else if model.currentCourses.isEmpty {
                    EmptyStateView(
                        symbol: "books.vertical",
                        title: "还没有课程",
                        message: "下拉刷新，或者前往教学网确认本学期选课。",
                        actionTitle: "重新加载"
                    ) {
                        Task { await model.refreshAll() }
                    }
                } else {
                    if !model.upcomingDeadlines.isEmpty {
                        deadlineSection
                    }
                    announcementSection
                    courseSection
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 18)
            .padding(.bottom, 48)
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .refreshable { await model.refreshAll() }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.refreshAll() }
                } label: {
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help("刷新")
                .accessibilityLabel("刷新")
                .disabled(model.isRefreshing)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x741020), Color(hex: 0x9E1B32), Color(hex: 0xB93A4B)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            GeometryReader { proxy in
                Circle()
                    .fill(.white.opacity(0.06))
                    .frame(width: proxy.size.width * 0.55)
                    .offset(x: proxy.size.width * 0.06, y: -proxy.size.width * 0.28)
                Circle()
                    .stroke(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: proxy.size.width * 0.38)
                    .offset(x: proxy.size.width * 0.12, y: proxy.size.height * 0.55)
            }
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))

            Text("S")
                .font(.system(size: 180, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.055))
                .offset(x: 18, y: 46)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(SBDate.headerDate())
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer()
                    if model.isRefreshing {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                }

                Text("\(SBDate.greeting())，\(model.profile?.displayName ?? "同学")")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(model.currentTermName ?? "本学期") · \(model.currentCourses.count) 门课程")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .padding(.top, 4)

                Spacer(minLength: 18)

                HStack(spacing: 10) {
                    statPill(icon: "books.vertical", value: "\(model.currentCourses.count)", label: "课程")
                    statPill(icon: "clock", value: "\(model.upcomingDeadlines.count)", label: "待办")
                    statPill(icon: "megaphone", value: "\(model.announcements.count)", label: "通知")
                }
            }
            .padding(22)
        }
        .frame(height: 194)
        .shadow(color: Theme.accentDeep.opacity(0.22), radius: 18, x: 0, y: 10)
    }

    private func statPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.65))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.12), in: Capsule())
    }

    // MARK: - Deadlines

    private var deadlineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "即将截止",
                subtitle: "未来 30 天 · 按截止时间排序",
                actionTitle: nil,
                action: nil
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 258), spacing: 12)], spacing: 12) {
                ForEach(model.upcomingDeadlines.prefix(4)) { deadline in
                    NavigationLink(value: AppRoute.course(id: deadline.courseID, tab: .grades)) {
                        DeadlineCard(deadline: deadline)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Announcements

    private var announcementSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "最新通知",
                subtitle: model.feedLoading ? "正在同步…" : nil,
                actionTitle: model.announcements.isEmpty ? nil : "全部",
                action: { router.section = .announcements }
            )

            if model.announcements.isEmpty {
                Text(model.feedLoading ? "正在加载课程通知…" : "最近没有新的课程通知。")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(model.announcements.prefix(5).enumerated()), id: \.element.id) { index, announcement in
                        NavigationLink(value: AppRoute.announcement(announcement)) {
                            AnnouncementRow(
                                announcement: announcement,
                                course: model.course(id: announcement.courseID)
                            )
                            .padding(.horizontal, 16)
                        }
                        .buttonStyle(.plain)
                        if index < min(4, model.announcements.count - 1) {
                            Divider().padding(.leading, 30)
                        }
                    }
                }
                .cardSurface(padding: 0, radius: 18)
            }
        }
    }

    // MARK: - Courses

    private var courseSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "本学期课程",
                subtitle: model.currentTermName,
                actionTitle: "全部课程",
                action: { router.section = .courses }
            )
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 232, maximum: 360), spacing: 14)],
                spacing: 14
            ) {
                ForEach(model.currentCourses) { course in
                    NavigationLink(value: AppRoute.course(id: course.id, tab: .content)) {
                        CourseCard(course: course)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct DeadlineCard: View {
    let deadline: Deadline

    private var tint: Color {
        let interval = deadline.dueDate.timeIntervalSinceNow
        if interval < 36 * 3600 { return Color(hex: 0xB3263B) }
        if interval < 7 * 24 * 3600 { return Color(hex: 0xA06A24) }
        return Theme.courseColor(deadline.colorIndex)
    }

    var body: some View {
        HStack(spacing: 13) {
            VStack(spacing: 1) {
                Text(SBDate.dayNumber(deadline.dueDate))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(SBDate.month(deadline.dueDate))
                    .font(.caption2)
            }
            .foregroundStyle(tint)
            .frame(width: 52, height: 56)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(deadline.courseName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                Text(deadline.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(SBDate.dueDescription(deadline.dueDate))
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
