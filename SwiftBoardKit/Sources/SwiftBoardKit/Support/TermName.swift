import Foundation

/// The academic term names used by PKU Blackboard look like
/// `26-27学年第一学期` (and occasionally `26-27学年第1学期`).
public enum TermName {
    /// Converts arabic digits used for the semester ordinal into Chinese
    /// numerals so that names coming from different endpoints compare equal.
    public static func normalized(_ name: String) -> String {
        var result = name
        let map: [(String, String)] = [
            ("学年第1学期", "学年第一学期"),
            ("学年第2学期", "学年第二学期"),
            ("学年第3学期", "学年第三学期"),
            ("学年第4学期", "学年第四学期"),
            ("学年1学期", "学年第一学期"),
            ("学年2学期", "学年第二学期"),
            ("学年3学期", "学年第三学期"),
            ("学年4学期", "学年第四学期")
        ]
        for (from, to) in map {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    /// A monotonically increasing key for sorting terms chronologically.
    /// `26-27学年第一学期` -> 20261, `25-26学年第二学期` -> 20252.
    public static func sortKey(_ name: String) -> Int {
        let normalized = normalized(name)
        guard let regex = try? NSRegularExpression(pattern: "(\\d{2})-(\\d{2})学年(?:第)?([一二三四1234])学期") else {
            return 0
        }
        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        guard let match = regex.firstMatch(in: normalized, range: range),
              let yearRange = Range(match.range(at: 1), in: normalized),
              let semesterRange = Range(match.range(at: 3), in: normalized),
              let year = Int(normalized[yearRange]) else {
            return 0
        }
        let ordinal: Int
        switch String(normalized[semesterRange]) {
        case "一", "1": ordinal = 1
        case "二", "2": ordinal = 2
        case "三", "3": ordinal = 3
        case "四", "4": ordinal = 4
        default: ordinal = 0
        }
        return (2000 + year) * 10 + ordinal
    }

    /// Extracts the term suffix from a course name, e.g.
    /// `数字集成电路与系统(26-27学年第1学期)` -> `26-27学年第1学期`.
    public static func embeddedInCourseName(_ name: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "\\(([^()]*学年[^()]*学期)\\)") else { return nil }
        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        guard let match = regex.firstMatch(in: name, range: range),
              let termRange = Range(match.range(at: 1), in: name) else { return nil }
        return String(name[termRange])
    }

    /// Removes the trailing term suffix from a course display name.
    public static func strippingTermSuffix(_ name: String) -> String {
        guard let embedded = embeddedInCourseName(name), !embedded.isEmpty else { return name }
        return name.replacingOccurrences(of: "(\(embedded))", with: "")
            .replacingOccurrences(of: "（\(embedded)）", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
