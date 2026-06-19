import Foundation

/// Light/dark preference for the chat UI.
public enum ColorSchemePreference: Sendable, Equatable {
    case system, light, dark
}

/// Optional host overrides on top of the theming the SDK derives from
/// `config.json`. Everything is opt-in — leave nil to use the workspace's
/// published config.
public struct ThemeOverrides: Sendable, Equatable {
    /// `#RRGGBB` brand color override (else taken from the published config).
    public var brandColorHex: String?
    /// Override the bot's display name.
    public var botName: String?
    public var colorScheme: ColorSchemePreference

    public init(brandColorHex: String? = nil, botName: String? = nil, colorScheme: ColorSchemePreference = .system) {
        self.brandColorHex = brandColorHex
        self.botName = botName
        self.colorScheme = colorScheme
    }
}

/// Full configuration for the SDK. Use `ThreadHive.configure(widgetKey:apiBaseURL:)`
/// for the common case, or build this for the advanced knobs (custom URLSession
/// for cert pinning, injected secure store, polling cadence, logger).
public struct ThreadHiveConfiguration {
    public var widgetKey: String
    /// API origin, e.g. `https://app.example.com/api`. Widget calls live under
    /// `{apiBaseURL}/v1/widget/...`.
    public var apiBaseURL: URL
    /// Seconds between conversation polls while the chat is open (3–5 typical).
    public var pollInterval: TimeInterval
    /// Seconds between "visitor is typing" pings while composing.
    public var typingPingInterval: TimeInterval
    public var theme: ThemeOverrides
    public var logger: ThreadHiveLogger?
    /// Inject a custom session (e.g. with certificate pinning).
    public var urlSession: URLSession
    public var retryPolicy: RetryPolicy
    /// Inject a custom secret store (defaults to Keychain).
    public var secureStore: SecureStore?

    public init(
        widgetKey: String,
        apiBaseURL: URL,
        pollInterval: TimeInterval = 4,
        typingPingInterval: TimeInterval = 2,
        theme: ThemeOverrides = ThemeOverrides(),
        logger: ThreadHiveLogger? = nil,
        urlSession: URLSession = .shared,
        retryPolicy: RetryPolicy = .default,
        secureStore: SecureStore? = nil
    ) {
        self.widgetKey = widgetKey
        self.apiBaseURL = apiBaseURL
        self.pollInterval = max(1, pollInterval)
        self.typingPingInterval = max(1, typingPingInterval)
        self.theme = theme
        self.logger = logger
        self.urlSession = urlSession
        self.retryPolicy = retryPolicy
        self.secureStore = secureStore
    }
}
