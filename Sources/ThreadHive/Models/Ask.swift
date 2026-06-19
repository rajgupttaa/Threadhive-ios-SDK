import Foundation

/// `POST /v1/widget/{key}/ask` request body.
public struct AskRequest: Codable, Equatable, Sendable {
    /// May be empty ONLY when `attachmentIds` is non-empty (attachment-only send).
    public var question: String
    public var visitorID: String?
    public var attachmentIDs: [String]?

    enum CodingKeys: String, CodingKey {
        case question
        case visitorID = "visitor_id"
        case attachmentIDs = "attachment_ids"
    }

    public init(question: String, visitorID: String?, attachmentIDs: [String]? = nil) {
        self.question = question
        self.visitorID = visitorID
        self.attachmentIDs = (attachmentIDs?.isEmpty == true) ? nil : attachmentIDs
    }
}

/// A retrieval citation under a bot bubble.
public struct AskSource: Codable, Equatable, Sendable {
    public let sourceID: String
    public let sourceName: String
    /// Cosine similarity in [-1, 1] (1.0 = identical).
    public let score: Double
    /// Set for web crawls — link the chip here; else fall back to `sourceName`.
    public let chunkURL: String?

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case sourceName = "source_name"
        case score
        case chunkURL = "chunk_url"
    }

    public init(sourceID: String, sourceName: String, score: Double, chunkURL: String?) {
        self.sourceID = sourceID
        self.sourceName = sourceName
        self.score = score
        self.chunkURL = chunkURL
    }
}

/// A bot-prepared write action awaiting the visitor's explicit confirmation.
public struct PendingAction: Codable, Equatable, Identifiable, Sendable {
    public var id: String { runID }
    public let runID: String
    public let name: String
    /// Human-readable description of what the action does.
    public let label: String
    /// Capability token — pass it back to `/actions/{runID}/confirm`.
    public let confirmToken: String

    enum CodingKeys: String, CodingKey {
        case runID = "run_id"
        case name, label
        case confirmToken = "confirm_token"
    }
}

/// A product the bot surfaced via `search_products`, rendered as a card.
public struct Product: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let price: String?
    public let currency: String?
    public let imageURL: String?
    /// Product / checkout URL. On mobile, "Add" opens this in an in-app browser
    /// (there is no host merchant page to add to a cart session).
    public let url: String?
    public let inStock: Bool
    public let source: String?
    public let addToCartID: String?

    enum CodingKeys: String, CodingKey {
        case id, title, price, currency
        case imageURL = "image_url"
        case url
        case inStock = "in_stock"
        case source
        case addToCartID = "add_to_cart_id"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        price = try c.decodeIfPresent(String.self, forKey: .price)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        inStock = try c.decodeIfPresent(Bool.self, forKey: .inStock) ?? true
        source = try c.decodeIfPresent(String.self, forKey: .source)
        addToCartID = try c.decodeIfPresent(String.self, forKey: .addToCartID)
    }

    public init(
        id: String, title: String, price: String? = nil, currency: String? = nil,
        imageURL: String? = nil, url: String? = nil, inStock: Bool = true,
        source: String? = nil, addToCartID: String? = nil
    ) {
        self.id = id; self.title = title; self.price = price; self.currency = currency
        self.imageURL = imageURL; self.url = url; self.inStock = inStock
        self.source = source; self.addToCartID = addToCartID
    }
}

/// `POST /v1/widget/{key}/ask` response (`AskOut`).
public struct AskResponse: Codable, Equatable, Sendable {
    /// Empty answer → render nothing (attachment-only send, or a human owns the thread).
    public let answer: String
    public let sources: [AskSource]
    public let usedRAG: Bool
    /// Store this and poll it for later agent/bot messages.
    public let conversationID: String?
    /// True → render `answer` as a system notice ("a teammate is joining") and poll.
    public let handoff: Bool
    public let pendingActions: [PendingAction]
    public let products: [Product]

    enum CodingKeys: String, CodingKey {
        case answer, sources
        case usedRAG = "used_rag"
        case conversationID = "conversation_id"
        case handoff
        case pendingActions = "pending_actions"
        case products
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answer = try c.decodeIfPresent(String.self, forKey: .answer) ?? ""
        sources = try c.decodeIfPresent([AskSource].self, forKey: .sources) ?? []
        usedRAG = try c.decodeIfPresent(Bool.self, forKey: .usedRAG) ?? false
        conversationID = try c.decodeIfPresent(String.self, forKey: .conversationID)
        handoff = try c.decodeIfPresent(Bool.self, forKey: .handoff) ?? false
        pendingActions = try c.decodeIfPresent([PendingAction].self, forKey: .pendingActions) ?? []
        products = try c.decodeIfPresent([Product].self, forKey: .products) ?? []
    }

    public init(
        answer: String, sources: [AskSource] = [], usedRAG: Bool = false,
        conversationID: String? = nil, handoff: Bool = false,
        pendingActions: [PendingAction] = [], products: [Product] = []
    ) {
        self.answer = answer; self.sources = sources; self.usedRAG = usedRAG
        self.conversationID = conversationID; self.handoff = handoff
        self.pendingActions = pendingActions; self.products = products
    }
}
