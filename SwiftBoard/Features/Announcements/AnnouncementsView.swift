import SwiftUI
import SwiftBoardKit

struct AnnouncementsView: View {
    @Environment(AppModel.self) private var model

    @State private var selectedCourseID: String?
    @State private var search = ""

    private var currentCoursesWithAnnouncements: [Course] {
        let ids = Set(model.announcements.map(\.courseID))
        return model.currentCourses.filter { ids.contains($0.id) }
    }

    private var filtered: [Announcement] {
        model.announcements.filter { item in
            if let selectedCourseID, item.courseID != selectedCourseID { return false }
            guard !search.isEmpty else { return true }
            return item.title.localizedStandardContains(search) || item.preview.localizedStandardContains(search)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                SearchField(text: $search, placeholder: "搜索通知")

                if !currentCoursesWithAnnouncements.isEmpty {
                    courseFilter
                }

                if filtered.isEmpty {
                    EmptyStateView(
                        symbol: "megaphone",
                        title: search.isEmpty ? "还没有通知" : "没有找到相关通知",
                        message: search.isEmpty ? "本学期暂时没有新的课程通知。" : "换一个关键词试试。"
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: AppRoute.announcement(item)) {
                                AnnouncementRow(
                                    announcement: item,
                                    course: model.course(id: item.courseID)
                                )
                                .padding(.horizontal, 16)
                            }
                            .buttonStyle(.plain)

                            if index < filtered.count - 1 {
                                Divider().padding(.leading, 30)
                            }
                        }
                    }
                    .cardSurface(padding: 0, radius: 18)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 44)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .refreshable { await model.refreshAll() }
        .navigationTitle("")
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("课程通知")
                .font(.system(size: 32, weight: .bold))
            Text("\(model.announcements.count) 条通知 · 来自 \(currentCoursesWithAnnouncements.count) 门课程")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
    }

    private var courseFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                filterChip(title: "全部", course: nil)
                ForEach(currentCoursesWithAnnouncements) { course in
                    filterChip(title: course.title, course: course)
                }
            }
            .padding(.vertical, 2)
            .padding(.trailing, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(title: String, course: Course?) -> some View {
        let selected = selectedCourseID == course?.id
        let tint = course.map { Theme.courseColor($0.colorIndex) } ?? Theme.accent
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedCourseID = course?.id
            }
        } label: {
            HStack(spacing: 5) {
                if course != nil {
                    Circle()
                        .fill(tint)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(selected ? .white : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(selected ? tint : Theme.subtleFill))
        }
        .buttonStyle(.plain)
    }
}

struct AnnouncementDetailView: View {
    let announcement: Announcement
    var course: Course?

    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    if let course {
                        Circle()
                            .fill(Theme.courseColor(course.colorIndex))
                            .frame(width: 7, height: 7)
                        Text(course.title)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.courseColor(course.colorIndex))
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(Theme.muted)
                    }
                    Text(SBDate.fullDate(announcement.created))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Text(SBDate.time(announcement.created))
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                    Spacer()
                }

                Text(announcement.title)
                    .font(.system(size: 23, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                if let course {
                    NavigationLink(value: AppRoute.course(id: course.id, tab: .announcements)) {
                        Label("查看课程通知", systemImage: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 14)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)

            Divider()

            if announcement.bodyHTML.isEmpty {
                EmptyStateView(symbol: "text.alignleft", title: "这条通知没有正文")
                    .frame(maxHeight: .infinity)
            } else {
                HTMLView(html: announcement.bodyHTML)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.canvas)
        .navigationTitle("通知")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
