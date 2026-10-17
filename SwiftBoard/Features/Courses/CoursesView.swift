import SwiftUI
import SwiftBoardKit

struct CoursesView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    @State private var search = ""
    @State private var scope: Scope = .current

    enum Scope: String, CaseIterable, Identifiable {
        case current = "本学期"
        case all = "全部学期"

        var id: String { rawValue }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                SearchField(text: $search, placeholder: "搜索课程")
                scopeBar

                if groups.isEmpty {
                    EmptyStateView(
                        symbol: search.isEmpty ? "books.vertical" : "magnifyingglass",
                        title: search.isEmpty ? "还没有课程" : "没有找到匹配的课程",
                        message: search.isEmpty ? "下拉刷新，或者前往教学网确认选课。" : "换一个关键词试试。"
                    )
                } else {
                    ForEach(groups) { group in
                        groupView(group)
                    }
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 16)
            .padding(.bottom, 44)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("我的课程")
                .font(.system(size: 32, weight: .bold))
            Text("共 \(model.courses.count) 门课程 · 本学期 \(model.currentCourses.count) 门")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
    }

    private var scopeBar: some View {
        HStack(spacing: 8) {
            ForEach(Scope.allCases) { item in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { scope = item }
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(scope == item ? .white : .secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            Capsule().fill(scope == item ? Theme.accent : Theme.subtleFill)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private func groupView(_ group: AppModel.CourseGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.title)
                    .font(.system(size: 18, weight: .semibold))
                Text("\(group.courses.count) 门")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                Spacer()
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 232, maximum: 360), spacing: 14)],
                spacing: 14
            ) {
                ForEach(group.courses) { course in
                    NavigationLink(value: AppRoute.course(id: course.id, tab: .content)) {
                        CourseCard(course: course)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var groups: [AppModel.CourseGroup] {
        let base: [AppModel.CourseGroup]
        switch scope {
        case .current:
            base = model.courseGroups.filter { $0.sortKey == model.currentTermKey }
        case .all:
            base = model.courseGroups
        }
        guard !search.isEmpty else { return base }
        return base.compactMap { group in
            let matches = group.courses.filter { course in
                course.title.localizedStandardContains(search)
                    || course.description.localizedStandardContains(search)
                    || (course.resolvedTermName?.localizedStandardContains(search) ?? false)
            }
            guard !matches.isEmpty else { return nil }
            return AppModel.CourseGroup(id: group.id, title: group.title, sortKey: group.sortKey, courses: matches)
        }
    }
}
