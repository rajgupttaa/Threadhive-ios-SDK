import Foundation

/// `POST /v1/widget/{key}/identify` request body.
///
/// `userHash = HMAC-SHA256(identitySecret, userID)` is computed by the host's
/// **backend** and forwarded here. The SDK never sees the identity secret.
public struct IdentifyRequest: Codable, Equatable, Sendable {
    public var visitorID: String
    public var userID: String
    public var email: String?
    public var name: String?
    public var phone: String?
    public var avatarURL: String?
    public var role: String?
    public var company: String?
    public var plan: String?
    public var mrr: Double?
    public var traits: [String: JSONValue]?
    public var userHash: String?

    enum CodingKeys: String, CodingKey {
        case visitorID = "visitor_id"
        case userID = "user_id"
        case email, name, phone
        case avatarURL = "avatar_url"
        case role, company, plan, mrr, traits
        case userHash = "user_hash"
    }

    public init(
        visitorID: String, userID: String, email: String? = nil, name: String? = nil,
        phone: String? = nil, avatarURL: String? = nil, role: String? = nil,
        company: String? = nil, plan: String? = nil, mrr: Double? = nil,
        traits: [String: JSONValue]? = nil, userHash: String? = nil
    ) {
        self.visitorID = visitorID; self.userID = userID; self.email = email
        self.name = name; self.phone = phone; self.avatarURL = avatarURL
        self.role = role; self.company = company; self.plan = plan; self.mrr = mrr
        self.traits = traits; self.userHash = userHash
    }
}

public struct IdentifyResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let contactID: String
    /// True when the HMAC verified server-side.
    public let verified: Bool

    enum CodingKeys: String, CodingKey {
        case ok
        case contactID = "contact_id"
        case verified
    }

    public init(ok: Bool, contactID: String, verified: Bool) {
        self.ok = ok; self.contactID = contactID; self.verified = verified
    }
}

/// `POST /v1/widget/{key}/track` request body.
public struct TrackRequest: Codable, Equatable, Sendable {
    public enum EventType: String, Codable, Sendable { case pageview, custom }

    public var visitorID: String
    public var type: EventType
    public var name: String?
    public var url: String?
    public var referrer: String?
    public var properties: [String: JSONValue]?
    public var tz: String?
    public var utmSource: String?
    public var utmMedium: String?
    public var utmCampaign: String?

    enum CodingKeys: String, CodingKey {
        case visitorID = "visitor_id"
        case type, name, url, referrer, properties, tz
        case utmSource = "utm_source"
        case utmMedium = "utm_medium"
        case utmCampaign = "utm_campaign"
    }

    public init(
        visitorID: String, type: EventType = .pageview, name: String? = nil,
        url: String? = nil, referrer: String? = nil, properties: [String: JSONValue]? = nil,
        tz: String? = nil, utmSource: String? = nil, utmMedium: String? = nil, utmCampaign: String? = nil
    ) {
        self.visitorID = visitorID; self.type = type; self.name = name; self.url = url
        self.referrer = referrer; self.properties = properties; self.tz = tz
        self.utmSource = utmSource; self.utmMedium = utmMedium; self.utmCampaign = utmCampaign
    }
}

public struct TrackResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let contactID: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case contactID = "contact_id"
    }

    public init(ok: Bool, contactID: String?) {
        self.ok = ok; self.contactID = contactID
    }
}

/// `POST /v1/widget/{key}/csat` request body.
public struct CSATRequest: Codable, Equatable, Sendable {
    public var conversationID: String
    public var visitorID: String?
    /// 1–5.
    public var score: Int
    public var comment: String?

    enum CodingKeys: String, CodingKey {
        case conversationID = "conversation_id"
        case visitorID = "visitor_id"
        case score, comment
    }

    public init(conversationID: String, score: Int, visitorID: String? = nil, comment: String? = nil) {
        self.conversationID = conversationID; self.score = score
        self.visitorID = visitorID; self.comment = comment
    }
}

public struct CSATResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let submissionID: String?
    public let conversationID: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case submissionID = "submission_id"
        case conversationID = "conversation_id"
    }

    public init(ok: Bool, submissionID: String?, conversationID: String?) {
        self.ok = ok; self.submissionID = submissionID; self.conversationID = conversationID
    }
}

/// `POST /v1/widget/messages/{messageID}/seen` response.
public struct SeenResponse: Codable, Equatable, Sendable {
    public let ok: Bool
    public let readAt: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case readAt = "read_at"
    }

    public init(ok: Bool, readAt: String?) {
        self.ok = ok; self.readAt = readAt
    }
}
