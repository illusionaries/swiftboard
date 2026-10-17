import SwiftUI
import SwiftBoardKit

struct CourseGradesSection: View {
    let course: Course
    @Environment(AppModel.self) private var model

    @State private var grade: CourseGrade?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "成绩",
                subtitle: grade.map { "\($0.items.count) 项成绩" },
                actionTitle: "刷新",
                showsChevron: false,
                action: { Task { await load(force: true) } }
            )

            if isLoading && grade == nil {
                LoadingRows(count: 3)
            } else if let errorMessage {
                ErrorBanner(message: errorMessage) {
                    Task { await load(force: true) }
                }
            } else if let grade, !grade.items.isEmpty {
                summary(grade)
                itemsList(grade)
                Text("成绩以教学网为准。部分项目可能尚未发布。")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
                    .padding(.top, 2)
            } else {
                EmptyStateView(
                    symbol: "chart.bar.doc.horizontal",
                    title: "暂无成绩",
                    message: "老师还没有发布这门课程的成绩。"
                )
            }
        }
        .task(id: course.id) { await load() }
    }

    private func summary(_ grade: CourseGrade) -> some View {
        HStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Theme.subtleFill, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: grade.progress ?? 0)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(percentText(grade.progress))
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("完成度")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(width: 82, height: 82)

            VStack(alignment: .leading, spacing: 4) {
                Text(grade.hasReleasedTotal ? "已发布成绩" : "已获得分数")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(grade.displayScore.map(formatScore) ?? "—")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/ \(formatScore(grade.displayPossible))")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted)
                }
                Text("已评分 \(grade.gradedItems.count) 项 · 共 \(grade.items.count) 项")
                    .font(.caption2)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
        }
        .cardSurface(padding: 18, radius: 20)
    }

    private func itemsList(_ grade: CourseGrade) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(grade.items.enumerated()), id: \.element.id) { index, item in
                VStack(spacing: 0) {
                    if let contentID = item.column.contentID {
                        NavigationLink(value: AppRoute.gradeContent(courseID: course.id, contentID: contentID)) {
                            gradeItemRow(item)
                        }
                        .buttonStyle(.plain)
                    } else {
                        gradeItemRow(item)
                    }

                    if index < grade.items.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .cardSurface(padding: 0, radius: 18)
    }

    private func gradeItemRow(_ item: GradeItem) -> some View {
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let due = item.column.dueDate {
                        Text("截止 \(SBDate.monthDay(due)) \(SBDate.time(due))")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 6)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(item.isGraded ? (item.score.map(formatScore) ?? item.text ?? "—") : "—")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(item.isGraded ? .primary : Theme.muted)
                    Text("/ \(formatScore(item.possible))")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
                .frame(minWidth: 52, alignment: .trailing)
                statusChip(item)
                if item.column.contentID != nil {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            if item.possible > 0 {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.subtleFill)
                        Capsule()
                            .fill(item.isGraded ? Theme.accent.opacity(0.75) : Theme.subtleFill)
                            .frame(width: proxy.size.width * ratio(item))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .contentShape(Rectangle())
    }

    private func statusChip(_ item: GradeItem) -> some View {
        let text: String
        let tint: Color
        if item.isExempt {
            text = "免修"; tint = Theme.muted
        } else if item.isPending {
            text = "待评分"; tint = Color(hex: 0xA06A24)
        } else if item.isGraded {
            text = "已评分"; tint = Color(hex: 0x3F7A5C)
        } else if item.column.gradesReleased {
            text = "未提交"; tint = Theme.muted
        } else {
            text = "未发布"; tint = Theme.muted
        }
        return Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(tint.opacity(0.11), in: Capsule())
    }

    private func ratio(_ item: GradeItem) -> Double {
        guard item.possible > 0 else { return 0 }
        return min(1, max(0, (item.score ?? 0) / item.possible))
    }

    private func percentText(_ progress: Double?) -> String {
        guard let progress else { return "—" }
        return "\(Int((progress * 100).rounded()))%"
    }

    private func formatScore(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 {
            return String(format: "%.0f", value)
        }
        return String(format: "%.1f", value)
    }

    private func load(force: Bool = false) async {
        if !force, grade != nil { return }
        isLoading = true
        defer { isLoading = false }
        grade = await model.grade(for: course, force: force)
    }
}
