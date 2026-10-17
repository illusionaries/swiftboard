import SwiftUI
import SwiftBoardKit

struct GradesView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if model.currentCourses.isEmpty {
                    EmptyStateView(
                        symbol: "chart.bar.doc.horizontal",
                        title: "本学期还没有课程",
                        message: "选课数据同步后，这里会显示每门课程的成绩概览。"
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(model.currentCourses) { course in
                            NavigationLink(value: AppRoute.course(id: course.id, tab: .grades)) {
                                GradeOverviewCard(course: course)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Text("成绩数据来自教学网，仅供参考，最终成绩以教务系统为准。")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .padding(.top, 4)
                }

                if let error = model.loadError {
                    ErrorBanner(message: error) {
                        Task { await model.refreshAll() }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 44)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.canvas)
        .refreshable {
            await model.refreshAll()
            await model.loadAllGrades(force: true)
        }
        .navigationTitle("")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await model.loadAllGrades()
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await model.loadAllGrades(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("刷新成绩")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("成绩")
                .font(.system(size: 32, weight: .bold))
            Text("\(model.currentTermName ?? "本学期") · \(model.currentCourses.count) 门课程")
                .font(.subheadline)
                .foregroundStyle(Theme.muted)
        }
    }
}

struct GradeOverviewCard: View {
    let course: Course
    @Environment(AppModel.self) private var model

    private var grade: CourseGrade? { model.grades[course.id] }
    private var isLoading: Bool { model.gradesLoading.contains(course.id) }

    var body: some View {
        HStack(spacing: 13) {
            CourseGlyph(course: course, size: 44)

            VStack(alignment: .leading, spacing: 6) {
                Text(course.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let grade, !grade.items.isEmpty {
                    HStack(spacing: 9) {
                        ProgressView(value: grade.progress ?? 0)
                            .tint(Theme.accent)
                            .frame(width: 72)
                        Text("\(grade.gradedItems.count)/\(grade.items.count) 项")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                            .lineLimit(1)
                            .fixedSize()
                    }
                } else if isLoading {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text("正在同步成绩…")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                } else {
                    Text(grade == nil ? "暂无成绩数据" : "老师尚未发布成绩")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text(grade?.displayScore.map(formatScore) ?? "—")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(grade?.displayScore == nil ? Theme.muted : .primary)
                if let grade, let score = grade.displayScore {
                    Text("/ \(formatScore(grade.displayPossible))")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .opacity(score.isNaN ? 0 : 1)
                }
            }
            .frame(minWidth: 56, alignment: .trailing)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func formatScore(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 { return String(format: "%.0f", value) }
        return String(format: "%.1f", value)
    }
}
