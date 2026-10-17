import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// A colour that resolves differently in light and dark appearances.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
        #elseif canImport(AppKit)
        return Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
        #else
        return Color(hex: light)
        #endif
    }
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#elseif canImport(AppKit)
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
#endif

enum Theme {
    static let accent = Color.adaptive(light: 0x9E1B32, dark: 0xE05A6C)
    static let accentDeep = Color(hex: 0x7A0C1B)
    static let accentBright = Color(hex: 0xB32236)

    static let canvas = Color.adaptive(light: 0xF6F3EF, dark: 0x0E0E10)
    static let card = Color.adaptive(light: 0xFFFFFF, dark: 0x1A1A1D)
    static let cardElevated = Color.adaptive(light: 0xFFFFFF, dark: 0x222226)
    static let field = Color.adaptive(light: 0xF1EDE8, dark: 0x26262B)
    static let stroke = Color.adaptive(light: 0x000000, dark: 0xFFFFFF).opacity(0.07)
    static let muted = Color.adaptive(light: 0x6E6A66, dark: 0x9C9A98)
    static let subtleFill = Color.adaptive(light: 0x000000, dark: 0xFFFFFF).opacity(0.04)

    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x6E0A18), Color(hex: 0x9E1B32), Color(hex: 0xC03A4B)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Muted, editorial gradient palette used for course covers.
    static let coursePalette: [(Color, Color)] = [
        (Color(hex: 0x9E2B3E), Color(hex: 0x5C1523)),
        (Color(hex: 0x2F6F73), Color(hex: 0x173F42)),
        (Color(hex: 0x3E5C86), Color(hex: 0x22344F)),
        (Color(hex: 0x9B6B2E), Color(hex: 0x5F3F1A)),
        (Color(hex: 0x6C5A94), Color(hex: 0x3D3359)),
        (Color(hex: 0x4F6D4A), Color(hex: 0x2C3F29)),
        (Color(hex: 0xA4533F), Color(hex: 0x5F2C20)),
        (Color(hex: 0x496975), Color(hex: 0x283E46)),
        (Color(hex: 0x7C4266), Color(hex: 0x452437)),
        (Color(hex: 0x8A6B42), Color(hex: 0x503D23))
    ]

    static func courseColors(_ index: Int) -> (Color, Color) {
        let palette = coursePalette
        return palette[abs(index) % palette.count]
    }

    static func courseColor(_ index: Int) -> Color {
        courseColors(index).0
    }

    static func courseGradient(_ index: Int) -> LinearGradient {
        let (start, end) = courseColors(index)
        return LinearGradient(colors: [start, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func courseTint(_ index: Int) -> Color {
        courseColors(index).0.opacity(0.12)
    }
}

// MARK: - Card surface

struct CardSurface: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    var padding: CGFloat = 18
    var radius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 0.8)
            }
            .shadow(
                color: .black.opacity(colorScheme == .dark ? 0.28 : 0.05),
                radius: colorScheme == .dark ? 10 : 18,
                x: 0,
                y: colorScheme == .dark ? 4 : 8
            )
    }
}

extension View {
    func cardSurface(padding: CGFloat = 18, radius: CGFloat = 20) -> some View {
        modifier(CardSurface(padding: padding, radius: radius))
    }
}
