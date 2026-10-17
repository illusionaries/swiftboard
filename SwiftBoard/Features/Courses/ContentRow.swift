import SwiftUI
import SwiftBoardKit

extension ContentKind {
    var symbol: String {
        switch self {
        case .folder: "folder.fill"
        case .file: "doc.fill"
        case .document: "doc.richtext.fill"
        case .assignment: "square.and.pencil"
        case .test: "checklist"
        case .link: "link"
        case .lesson: "rectangle.stack.fill"
        case .discussion: "bubble.left.and.bubble.right.fill"
        case .other: "square.grid.2x2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .folder: Color(hex: 0xB07B2A)
        case .file: Color(hex: 0x3E6FA3)
        case .document: Color(hex: 0x3F7A5C)
        case .assignment: Theme.accent
        case .test: Color(hex: 0x7A5AA6)
        case .link: Color(hex: 0x2F7C82)
        case .lesson: Color(hex: 0x50639B)
        case .discussion: Color(hex: 0x3E6FA3)
        case .other: Theme.muted
        }
    }
}

func fileSymbol(for name: String) -> (String, Color) {
    let ext = (name as NSString).pathExtension.lowercased()
    switch ext {
    case "pdf": return ("doc.richtext", Color(hex: 0xB3383E))
    case "ppt", "pptx", "key": return ("rectangle.on.rectangle", Color(hex: 0xB2642A))
    case "doc", "docx", "pages", "rtf": return ("doc.text", Color(hex: 0x3E6FA3))
    case "xls", "xlsx", "csv", "numbers": return ("tablecells", Color(hex: 0x3F7A5C))
    case "zip", "rar", "7z", "tar", "gz": return ("archivebox", Color(hex: 0x7A6A55))
    case "png", "jpg", "jpeg", "gif", "heic", "webp", "svg": return ("photo", Color(hex: 0x7A5AA6))
    case "mp4", "mov", "m4v", "avi", "mkv": return ("play.rectangle", Color(hex: 0x2F7C82))
    case "mp3", "wav", "m4a": return ("waveform", Color(hex: 0x2F7C82))
    case "md", "txt": return ("doc.plaintext", Color(hex: 0x5A6472))
    default: return ("doc.fill", Color(hex: 0x3E6FA3))
    }
}

struct ContentRow: View {
    let content: CourseContent

    private var symbolAndTint: (String, Color) {
        if content.kind == .file, let name = content.file?.name {
            return fileSymbol(for: name)
        }
        return (content.kind.symbol, content.kind.tint)
    }

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: symbolAndTint.0, tint: symbolAndTint.1, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(content.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 7) {
                    Text(content.subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                    if let due = content.dueDate {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(Theme.muted)
                        Text(SBDate.dueDescription(due))
                            .font(.caption2)
                            .foregroundStyle(dueUrgency(due))
                    }
                }
            }

            Spacer(minLength: 6)

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func dueUrgency(_ date: Date) -> Color {
        if date < Date() { return Theme.muted }
        if date.timeIntervalSinceNow < 48 * 3600 { return Color(hex: 0xB3263B) }
        return Theme.muted
    }
}
