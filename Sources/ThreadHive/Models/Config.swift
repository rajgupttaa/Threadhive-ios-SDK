import Foundation

/// A workspace teammate rendered as an avatar in the chat header.
public struct WidgetTeamMember: Codable, Equatable, Sendable {
    public let name: String
    public let initials: String
    /// Tailwind gradient class on the web (e.g. `from-orange-400 to-pink-500`).
    /// The SDK maps it to a deterministic local color when there is no avatar.
    public let color: String
    public let avatarURL: String?

    enum CodingKeys: String, CodingKey {
        case name, initials, color
        case avatarURL = "avatar_url"
    }
}

/// `GET /v1/widget/{key}/config.json` — theming + presence state.
///
/// `config` / `availability` are opaque blobs the backend stores without a
/// fixed schema; the SDK reads known keys for theming via `JSONValue`.
public struct WidgetPublicConfig: Codable, Equatable, Sendable {
    public let workspaceName: String
    public let workspaceSubdomain: String
    public let widgetKey: String
    public let config: JSONValue?
    public let publishedVersion: String?
    public let publishedAt: String?
    /// True when an LLM provider is configured → show the "AI active" affordance.
    public let aiAvailable: Bool
    /// Business-hours schedule (opaque); null means "always open".
    public let availability: JSONValue?
    /// Server snapshot of open/closed at fetch time.
    public let isOpen: Bool
    public let team: [WidgetTeamMember]
    public let teamOverflow: Int
    /// Friendly median first-reply label ("under 2 minutes"), or null.
    public let replyTimeLabel: String?

    enum CodingKeys: String, CodingKey {
        case workspaceName = "workspace_name"
        case workspaceSubdomain = "workspace_subdomain"
        case widgetKey = "widget_key"
        case config
        case publishedVersion = "published_version"
        case publishedAt = "published_at"
        case aiAvailable = "ai_available"
        case availability
        case isOpen = "is_open"
        case team
        case teamOverflow = "team_overflow"
        case replyTimeLabel = "reply_time_label"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        workspaceName = try c.decode(String.self, forKey: .workspaceName)
        workspaceSubdomain = try c.decodeIfPresent(String.self, forKey: .workspaceSubdomain) ?? ""
        widgetKey = try c.decode(String.self, forKey: .widgetKey)
        config = try c.decodeIfPresent(JSONValue.self, forKey: .config)
        publishedVersion = try c.decodeIfPresent(String.self, forKey: .publishedVersion)
        publishedAt = try c.decodeIfPresent(String.self, forKey: .publishedAt)
        aiAvailable = try c.decodeIfPresent(Bool.self, forKey: .aiAvailable) ?? false
        availability = try c.decodeIfPresent(JSONValue.self, forKey: .availability)
        isOpen = try c.decodeIfPresent(Bool.self, forKey: .isOpen) ?? true
        team = try c.decodeIfPresent([WidgetTeamMember].self, forKey: .team) ?? []
        teamOverflow = try c.decodeIfPresent(Int.self, forKey: .teamOverflow) ?? 0
        replyTimeLabel = try c.decodeIfPresent(String.self, forKey: .replyTimeLabel)
    }

    public init(
        workspaceName: String,
        workspaceSubdomain: String = "",
        widgetKey: String,
        config: JSONValue? = nil,
        publishedVersion: String? = nil,
        publishedAt: String? = nil,
        aiAvailable: Bool = false,
        availability: JSONValue? = nil,
        isOpen: Bool = true,
        team: [WidgetTeamMember] = [],
        teamOverflow: Int = 0,
        replyTimeLabel: String? = nil
    ) {
        self.workspaceName = workspaceName
        self.workspaceSubdomain = workspaceSubdomain
        self.widgetKey = widgetKey
        self.config = config
        self.publishedVersion = publishedVersion
        self.publishedAt = publishedAt
        self.aiAvailable = aiAvailable
        self.availability = availability
        self.isOpen = isOpen
        self.team = team
        self.teamOverflow = teamOverflow
        self.replyTimeLabel = replyTimeLabel
    }
}
