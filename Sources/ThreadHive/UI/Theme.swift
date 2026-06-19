#if canImport(SwiftUI)
import SwiftUI

extension Color {
    /// Build a Color from a `#RRGGBB` / `#RGB` hex string (falls back to indigo).
    init(threadHiveHex hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let r, g, b: UInt64
        switch cleaned.count {
        case 3: (r, g, b) = ((value >> 8 & 0xF) * 17, (value >> 4 & 0xF) * 17, (value & 0xF) * 17)
        case 6: (r, g, b) = (value >> 16 & 0xFF, value >> 8 & 0xFF, value & 0xFF)
        default: (r, g, b) = (79, 70, 229)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: 1)
    }
}

/// SwiftUI theme derived from `ResolvedConfig`. Cross-platform colors only (no
/// UIKit/AppKit), so the views compile on iOS and macOS alike.
public struct ThreadHiveTheme {
    public var brand: Color
    public var accent: Color
    /// Forced color scheme from the published config / overrides; nil = system.
    public var preferredColorScheme: ColorScheme?

    public init(resolved: ResolvedConfig) {
        brand = Color(threadHiveHex: resolved.brandColorHex)
        accent = Color(threadHiveHex: resolved.accentColorHex)
        switch resolved.themeMode {
        case "light": preferredColorScheme = .light
        case "dark": preferredColorScheme = .dark
        default: preferredColorScheme = nil
        }
    }

    public var userBubble: Color { brand }
    public var userBubbleText: Color { .white }
    public var botBubble: Color { Color.primary.opacity(0.07) }
    public var botBubbleText: Color { .primary }
    public var systemText: Color { .secondary }
    public var chatBackground: Color { Color.primary.opacity(0.03) }
    public var divider: Color { Color.primary.opacity(0.1) }
}
#endif
