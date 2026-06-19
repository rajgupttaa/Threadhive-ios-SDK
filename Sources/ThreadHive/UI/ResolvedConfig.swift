import Foundation

/// Theming + copy resolved from the opaque published `config` blob (keys mirror
/// the web `WidgetConfig`: `brand.brandColor`, `welcome.botName`, …) with host
/// `ThemeOverrides` layered on top. Pure value type — no SwiftUI — so it can be
/// unit-tested and reused by a custom UI.
public struct ResolvedConfig: Equatable, Sendable {
    public var brandColorHex: String
    public var accentColorHex: String
    public var botName: String
    public var agentRole: String
    public var greeting: String
    public var greetingSubtitle: String
    public var suggestedQuestions: [String]
    public var showPoweredBy: Bool
    public var showAvailability: Bool
    public var logoURL: String?
    public var launcherLabel: String?
    /// "light" | "dark" | "auto" from the published config (host override wins).
    public var themeMode: String

    public static let defaultBrandColor = "#4F46E5"

    public init(config: WidgetPublicConfig?, overrides: ThemeOverrides = ThemeOverrides(), workspaceName: String = "") {
        let blob = config?.config
        let brand = blob?["brand"]
        let welcome = blob?["welcome"]
        let launcher = blob?["launcher"]

        func string(_ value: JSONValue?) -> String? {
            guard let s = value?.stringValue, !s.isEmpty else { return nil }
            return s
        }

        let name = workspaceName.isEmpty ? (config?.workspaceName ?? "") : workspaceName

        brandColorHex = overrides.brandColorHex ?? string(brand?["brandColor"]) ?? Self.defaultBrandColor
        accentColorHex = string(brand?["accentColor"]) ?? brandColorHex
        botName = overrides.botName ?? string(welcome?["botName"]) ?? "Assistant"
        agentRole = string(welcome?["agentRole"]) ?? "Support"
        greeting = string(welcome?["greeting"]) ?? (name.isEmpty ? "Hi there 👋" : "Hi from \(name) 👋")
        greetingSubtitle = string(welcome?["greetingSubtitle"]) ?? "Ask us anything, or search for an answer."
        suggestedQuestions = welcome?["suggestedQuestions"]?.arrayValue?.compactMap { $0.stringValue } ?? []
        showPoweredBy = brand?["showPoweredBy"]?.boolValue ?? true
        showAvailability = welcome?["showAvailability"]?.boolValue ?? true
        logoURL = string(brand?["logoUrl"])
        launcherLabel = string(launcher?["label"])

        switch overrides.colorScheme {
        case .light: themeMode = "light"
        case .dark: themeMode = "dark"
        case .system: themeMode = string(brand?["theme"]) ?? "auto"
        }
    }
}
