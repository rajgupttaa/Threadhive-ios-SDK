import Foundation

/// Who authored a message. Unknown values decode to `.unknown`.
public enum AuthorKind: String, Codable, Sendable {
    case visitor, bot, agent, system, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AuthorKind(rawValue: raw) ?? .unknown
    }
}

/// Conversation lifecycle. Unknown values decode to `.unknown`.
public enum ConversationStatus: String, Codable, Sendable {
    case open, snoozed, closed, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ConversationStatus(rawValue: raw) ?? .unknown
    }
}

/// An image/PDF attached to a message.
public struct MessageAttachment: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let mimeType: String
    public let sizeBytes: Int
    /// Relative, `/api`-prefixed download path. Resolve against the API base
    /// origin via `WidgetEndpoints.resolveAttachmentURL`.
    public let url: String

    enum CodingKeys: String, CodingKey {
        case id, name
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case url
    }

    public var isImage: Bool { mimeType.hasPrefix("image/") }
}

/// Visitor-facing message returned by `/poll`.
public struct WidgetMessage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let authorKind: AuthorKind
    public let authorName: String
    public let authorAvatarURL: String?
    public let body: String
    public let sources: [JSONValue]?
    public let createdAt: String
    public let attachments: [MessageAttachment]
    public let deliveredAt: String?
    public let readAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case authorKind = "author_kind"
        case authorName = "author_name"
        case authorAvatarURL = "author_avatar_url"
        case body, sources
        case createdAt = "created_at"
        case attachments
        case deliveredAt = "delivered_at"
        case readAt = "read_at"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        authorKind = try c.decodeIfPresent(AuthorKind.self, forKey: .authorKind) ?? .unknown
        authorName = try c.decodeIfPresent(String.self, forKey: .authorName) ?? ""
        authorAvatarURL = try c.decodeIfPresent(String.self, forKey: .authorAvatarURL)
        body = try c.decodeIfPresent(String.self, forKey: .body) ?? ""
        sources = try c.decodeIfPresent([JSONValue].self, forKey: .sources)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        attachments = try c.decodeIfPresent([MessageAttachment].self, forKey: .attachments) ?? []
        deliveredAt = try c.decodeIfPresent(String.self, forKey: .deliveredAt)
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt)
    }

    public init(
        id: String, authorKind: AuthorKind, authorName: String, authorAvatarURL: String? = nil,
        body: String, sources: [JSONValue]? = nil, createdAt: String,
        attachments: [MessageAttachment] = [], deliveredAt: String? = nil, readAt: String? = nil
    ) {
        self.id = id; self.authorKind = authorKind; self.authorName = authorName
        self.authorAvatarURL = authorAvatarURL; self.body = body; self.sources = sources
        self.createdAt = createdAt; self.attachments = attachments
        self.deliveredAt = deliveredAt; self.readAt = readAt
    }
}

/// Live "is someone typing" presence embedded in the poll response.
public struct TypingState: Codable, Equatable, Sendable {
    public let visitor: Bool
    public let agent: Bool

    public init(visitor: Bool = false, agent: Bool = false) {
        self.visitor = visitor
        self.agent = agent
    }
}

/// `GET /v1/widget/{key}/conversations/{id}/poll` response.
public struct ConversationPoll: Codable, Equatable, Sendable {
    public let conversationID: String
    public let status: ConversationStatus
    public let messages: [WidgetMessage]
    /// ISO of the newest message returned — echo back as `since` next poll.
    public let cursor: String?
    public let typing: TypingState
    /// The human teammate handling the thread, once assigned.
    public let assignedAgent: WidgetTeamMember?
    /// The visitor's submitted CSAT rating (1–5), else nil.
    public let csatScore: Int?

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case status, messages, cursor, typing
        case assignedAgent = "assigned_agent"
        case csatScore = "csat_score"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        conversationID = try c.decode(String.self, forKey: .conversationID)
        status = try c.decodeIfPresent(ConversationStatus.self, forKey: .status) ?? .unknown
        messages = try c.decodeIfPresent([WidgetMessage].self, forKey: .messages) ?? []
        cursor = try c.decodeIfPresent(String.self, forKey: .cursor)
        typing = try c.decodeIfPresent(TypingState.self, forKey: .typing) ?? TypingState()
        assignedAgent = try c.decodeIfPresent(WidgetTeamMember.self, forKey: .assignedAgent)
        csatScore = try c.decodeIfPresent(Int.self, forKey: .csatScore)
    }
}

/// One row in the "Messages" tab (`GET /v1/widget/{key}/conversations`).
public struct ConversationSummary: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let status: ConversationStatus
    public let subject: String
    public let lastMessagePreview: String
    public let lastMessageAuthor: AuthorKind?
    public let lastMessageAt: String?
    public let aiHandled: Bool
    public let unread: Bool

    enum CodingKeys: String, CodingKey {
        case id, status, subject
        case lastMessagePreview = "last_message_preview"
        case lastMessageAuthor = "last_message_author"
        case lastMessageAt = "last_message_at"
        case aiHandled = "ai_handled"
        case unread
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        status = try c.decodeIfPresent(ConversationStatus.self, forKey: .status) ?? .unknown
        subject = try c.decodeIfPresent(String.self, forKey: .subject) ?? "Conversation"
        lastMessagePreview = try c.decodeIfPresent(String.self, forKey: .lastMessagePreview) ?? ""
        lastMessageAuthor = try c.decodeIfPresent(AuthorKind.self, forKey: .lastMessageAuthor)
        lastMessageAt = try c.decodeIfPresent(String.self, forKey: .lastMessageAt)
        aiHandled = try c.decodeIfPresent(Bool.self, forKey: .aiHandled) ?? true
        unread = try c.decodeIfPresent(Bool.self, forKey: .unread) ?? false
    }
}

/// Envelope for the conversations list.
public struct ConversationList: Codable, Equatable, Sendable {
    public let items: [ConversationSummary]
}

/// `POST /v1/widget/{key}/conversations/{id}/messages` response.
public struct SendMessageResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let conversationID: String
    public let messageID: String
    public let handoff: Bool
    public let botReply: BotReply?

    public struct BotReply: Codable, Equatable, Sendable {
        public let id: String
        public let body: String
    }

    enum CodingKeys: String, CodingKey {
        case ok
        case conversationID = "conversation_id"
        case messageID = "message_id"
        case handoff
        case botReply = "bot_reply"
    }
}
