import Foundation

public extension String {
    /// Very small HTML-to-text converter used for list previews. It is not a
    /// full parser; the detail screens render the original markup in WebKit.
    var htmlToPlainText: String {
        var text = self
        text = text.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "</(p|div|li|tr|h[1-6])>", with: "\n", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<li[^>]*>", with: "• ", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.decodingHTMLEntities()
        text = text.replacingOccurrences(of: "[ \\t\\u{00A0}]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n[ \\t]*\\n[ \\t]*\\n+", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trims a plain-text body down to a readable snippet.
    func snippet(limit: Int = 180) -> String {
        let plain = htmlToPlainText
        guard plain.count > limit else { return plain }
        let end = plain.index(plain.startIndex, offsetBy: limit)
        return plain[..<end].trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    func decodingHTMLEntities() -> String {
        var result = self
        let named: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&hellip;": "…",
            "&mdash;": "—", "&ndash;": "–", "&ldquo;": "“", "&rdquo;": "”",
            "&lsquo;": "‘", "&rsquo;": "’", "&middot;": "·"
        ]
        for (entity, replacement) in named {
            result = result.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        // Numeric entities, e.g. &#160; or &#x00A0;
        guard result.contains("&#") else { return result }
        let pattern = "&#(x?[0-9a-fA-F]+);"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let range = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = regex.matches(in: result, range: range)
        for match in matches.reversed() {
            guard let full = Range(match.range, in: result),
                  let valueRange = Range(match.range(at: 1), in: result) else { continue }
            let raw = String(result[valueRange])
            let scalarValue: UInt32?
            if raw.hasPrefix("x") || raw.hasPrefix("X") {
                scalarValue = UInt32(raw.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(raw, radix: 10)
            }
            if let scalarValue, let scalar = Unicode.Scalar(scalarValue) {
                result.replaceSubrange(full, with: String(Character(scalar)))
            }
        }
        return result
    }
}

/// Escapes user content for the small HTML documents rendered in-app.
public extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
