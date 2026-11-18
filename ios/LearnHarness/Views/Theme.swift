import SwiftUI

/// De kleuren van het actieve LearnHarness-thema (Settings → Appearance), gelezen uit de
/// CSS-variabelen van de pagina (bridge.js). Zo volgen de native lijst en balken het thema.
struct LHTheme: Equatable, Sendable {
    var background: Color
    var foreground: Color
    var card: Color
    var muted: Color
    var border: Color
    var accent: Color
    var primary: Color
    var isDark: Bool

    /// Standaard donker thema uit upstream app/globals.css.
    static let `default` = LHTheme(
        background: Color(red: 0x14 / 255, green: 0x14 / 255, blue: 0x14 / 255),
        foreground: Color(red: 0xe6 / 255, green: 0xe6 / 255, blue: 0xe6 / 255),
        card: Color(red: 0x1c / 255, green: 0x1c / 255, blue: 0x1c / 255),
        muted: Color(red: 0x8d / 255, green: 0x8d / 255, blue: 0x8d / 255),
        border: Color(red: 0x43 / 255, green: 0x43 / 255, blue: 0x43 / 255),
        accent: Color(red: 0x2a / 255, green: 0x2a / 255, blue: 0x2a / 255),
        primary: Color(red: 0xe6 / 255, green: 0xe6 / 255, blue: 0xe6 / 255),
        isDark: true)

    /// `vars`: naam → "r,g,b" (0–255), zoals bridge.js ze aanlevert na getComputedStyle.
    init(cssVars vars: [String: String]) {
        let d = LHTheme.default
        func color(_ key: String, _ fallback: Color) -> Color {
            guard let parts = vars[key]?.split(separator: ",").compactMap({ Double($0.trimmingCharacters(in: .whitespaces)) }),
                  parts.count >= 3 else { return fallback }
            return Color(red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255)
        }
        background = color("background", d.background)
        foreground = color("foreground", d.foreground)
        card = color("card", d.card)
        muted = color("muted-foreground", d.muted)
        border = color("border", d.border)
        accent = color("accent", d.accent)
        primary = color("primary", d.primary)
        if let bg = vars["background"]?.split(separator: ",").compactMap({ Double($0.trimmingCharacters(in: .whitespaces)) }), bg.count >= 3 {
            isDark = (0.2126 * bg[0] + 0.7152 * bg[1] + 0.0722 * bg[2]) / 255 < 0.5
        } else {
            isDark = true
        }
    }

    init(background: Color, foreground: Color, card: Color, muted: Color, border: Color, accent: Color, primary: Color, isDark: Bool) {
        self.background = background; self.foreground = foreground; self.card = card; self.muted = muted
        self.border = border; self.accent = accent; self.primary = primary; self.isDark = isDark
    }
}

extension Font {
    /// Upstream gebruikt JetBrains Mono voor de UI en een serif (lh-cmu) voor titels.
    static func lhUI(_ style: Font.TextStyle) -> Font { .system(style, design: .monospaced) }
    static func lhTitle(_ style: Font.TextStyle) -> Font { .system(style, design: .serif) }
}

extension ISO8601DateFormatter {
    nonisolated(unsafe) static let lh: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}
