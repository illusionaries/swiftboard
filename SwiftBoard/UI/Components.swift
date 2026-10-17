import SwiftUI
import SwiftBoardKit

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var showsChevron: Bool = true
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        if showsChevron {
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Chips & badges

struct Chip: View {
    let text: String
    var tint: Color = Theme.accent
    var filled: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(filled ? Color.white : tint)
            .background(filled ? tint : tint.opacity(0.11), in: Capsule())
    }
}

struct CountBadge: View {
    let count: Int
    var tint: Color = Theme.accent

    var body: some View {
        Text("\(count)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Icons & avatars

struct IconTile: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 38

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: size * 0.32, style: .continuous))
    }
}

struct AvatarView: View {
    let initials: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xB32236), Color(hex: 0x6E0A18)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.8))
    }
}

struct AcademicMark: View {
    var size: CGFloat = 56
    var monochrome: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(
                    monochrome
                        ? LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.10)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color(hex: 0xB32236), Color(hex: 0x7A0C1B)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            Image(systemName: "graduationcap.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
                .offset(y: -size * 0.01)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 0.8)
        )
    }
}

// MARK: - Course cover

struct CourseCard: View {
    let course: Course
    var height: CGFloat = 154

    private var watermark: String {
        String(course.title.prefix(1))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Theme.courseGradient(course.colorIndex)
            Text(watermark)
                .font(.system(size: 132, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.10))
                .offset(x: 18, y: 34)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    if !course.description.isEmpty {
                        Text(course.description)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.18), in: Capsule())
                    }
                    Spacer(minLength: 0)
                    if !course.isAvailable {
                        Text("已结束")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.18), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
                Text(course.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                Text(course.resolvedTermName ?? "课程")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.8)
        }
        .shadow(color: Theme.courseColors(course.colorIndex).1.opacity(0.22), radius: 14, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Empty & error states

struct EmptyStateView: View {
    let symbol: String
    let title: String
    var message: String?
    var actionTitle: String?
    var showsChevron: Bool = true
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.muted)
                .frame(width: 64, height: 64)
                .background(Theme.subtleFill, in: Circle())
            Text(title)
                .font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .tint(Theme.accent)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry {
                Button("重试", action: retry)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.8)
        )
    }
}

struct LoadingRows: View {
    var count: Int = 3

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<count, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.subtleFill)
                        .frame(width: 38, height: 38)
                    VStack(alignment: .leading, spacing: 7) {
                        RoundedRectangle(cornerRadius: 4).fill(Theme.subtleFill).frame(height: 11)
                        RoundedRectangle(cornerRadius: 4).fill(Theme.subtleFill.opacity(0.7)).frame(width: 150, height: 9)
                    }
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
    }
}

// MARK: - Dates

enum SBDate {
    static let chinese = Locale(identifier: "zh_CN")

    static func relative(_ date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(Int(seconds / 60)) 分钟前" }

        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "今天 " + time(date)
        }
        if calendar.isDateInYesterday(date) {
            return "昨天 " + time(date)
        }
        if seconds < 7 * 24 * 3600 {
            return weekday(date) + " " + time(date)
        }
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return monthDay(date)
        }
        return fullDate(date)
    }

    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = chinese
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func monthDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = chinese
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }

    static func fullDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = chinese
        formatter.dateFormat = "yyyy年M月d日"
        return formatter.string(from: date)
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = chinese
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    static func dayNumber(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = chinese
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    static func month(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = chinese
        formatter.dateFormat = "M月"
        return formatter.string(from: date)
    }

    static func dueDescription(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: now)
        let startOfDueDay = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: startOfToday, to: startOfDueDay).day ?? 0

        if date < now {
            let overdue = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            return overdue <= 0 ? "刚刚截止" : "已截止 \(overdue) 天"
        }
        if calendar.isDateInToday(date) { return "今天 \(time(date)) 截止" }
        if days == 1 { return "明天 \(time(date)) 截止" }
        if days <= 30 { return "\(days) 天后截止" }
        return monthDay(date) + " 截止"
    }

    static func headerDate(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = chinese
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: date)
    }

    static func greeting(_ date: Date = Date()) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<9: return "早上好"
        case 9..<12: return "上午好"
        case 12..<14: return "中午好"
        case 14..<18: return "下午好"
        default: return "晚上好"
        }
    }
}

struct CourseGlyph: View {
    let course: Course
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(Theme.courseGradient(course.colorIndex))
            Text(String(course.title.prefix(1)))
                .font(.system(size: size * 0.42, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.8)
        )
    }
}

struct SearchField: View {
    @Binding var text: String
    var placeholder = "搜索"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.muted)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .submitLabel(.search)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(Theme.field, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 0.8)
        )
    }
}
