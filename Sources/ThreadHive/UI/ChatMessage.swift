import Foundation

public enum ChatAuthor: String, Equatable, Sendable {
    case visitor, bot, agent, system

    init(_ kind: AuthorKind) {
        switch kind {
        case .visitor: self = .visitor
        case .bot: self = .bot
        case .agent: self = .agent
        case .system, .unknown: self = .system
        }
    }
}

public enum SendState: Equatable, Sendable {
    case sending, sent, failed
}

/// A single rendered row in the chat. Built either optimistically (local send)
/// or from a polled `WidgetMessage`; products + pending actions ride on the bot
/// message they arrived with (they only come from `/ask`, not `/poll`).
public struct ChatMessage: Identifiable, Equatable, Sendable {
    public var id: String
    /// Server id once the message has been confirmed/echoed by `/poll`.
    public var serverID: String?
    public var author: ChatAuthor
    public var authorName: String
    public var avatarURL: String?
    public var text: String
    public var citations: [AskSource]
    public var attachments: [MessageAttachment]
    public var products: [Product]
    public var pendingActions: [PendingAction]
    public var createdAt: String?
    public var sendState: SendState?
    /// A local message awaiting its server echo so it can be bound by body match.
    public var awaitingEcho: Bool

    public init(
        id: String, serverID: String? = nil, author: ChatAuthor, authorName: String,
        avatarURL: String? = nil, text: String, citations: [AskSource] = [],
        attachments: [MessageAttachment] = [], products: [Product] = [],
        pendingActions: [PendingAction] = [], createdAt: String? = nil,
        sendState: SendState? = nil, awaitingEcho: Bool = false
    ) {
        self.id = id; self.serverID = serverID; self.author = author; self.authorName = authorName
        self.avatarURL = avatarURL; self.text = text; self.citations = citations
        self.attachments = attachments; self.products = products; self.pendingActions = pendingActions
        self.createdAt = createdAt; self.sendState = sendState; self.awaitingEcho = awaitingEcho
    }

    /// Build from an authoritative polled message.
    public init(_ message: WidgetMessage) {
        self.id = message.id
        self.serverID = message.id
        self.author = ChatAuthor(message.authorKind)
        self.authorName = message.authorName
        self.avatarURL = message.authorAvatarURL
        self.text = message.body
        self.citations = (message.sources ?? []).compactMap(AskSource.init(json:))
        self.attachments = message.attachments
        self.products = []
        self.pendingActions = []
        self.createdAt = message.createdAt
        self.sendState = nil
        self.awaitingEcho = false
    }

    public var isFromVisitor: Bool { author == .visitor }
    public var isSystem: Bool { author == .system }
}

extension AskSource {
    /// Parse a citation out of a polled message's loosely-typed `sources` entry.
    init?(json: JSONValue) {
        guard let object = json.objectValue else { return nil }
        guard let sourceID = object["source_id"]?.stringValue,
              let sourceName = object["source_name"]?.stringValue else { return nil }
        self.init(
            sourceID: sourceID,
            sourceName: sourceName,
            score: object["score"]?.doubleValue ?? 0,
            chunkURL: object["chunk_url"]?.stringValue
        )
    }
}
