import Foundation

/// `POST /v1/widget/{key}/actions/{runID}/confirm` request body.
public struct ConfirmActionRequest: Codable, Equatable, Sendable {
    public let confirmToken: String
    /// `false` = the visitor declined.
    public let confirm: Bool

    enum CodingKeys: String, CodingKey {
        case confirmToken = "confirm_token"
        case confirm
    }

    public init(confirmToken: String, confirm: Bool) {
        self.confirmToken = confirmToken
        self.confirm = confirm
    }
}

/// Outcome of a confirm/decline. Unknown server values map to `.unknown` rather
/// than failing to decode, so a new backend status never breaks the SDK.
public enum ConfirmOutcome: String, Sendable {
    case ok, rejected, error
    case notFound = "not_found"
    case alreadyDone = "already_done"
    case unknown

    public var isSuccess: Bool { self == .ok }
}

/// `POST /v1/widget/{key}/actions/{runID}/confirm` response (`ConfirmActionOut`).
public struct ConfirmActionResponse: Codable, Equatable, Sendable {
    /// Raw status string as sent by the server.
    public let status: String
    /// Visitor-facing line to render as a bot bubble.
    public let message: String

    public var outcome: ConfirmOutcome { ConfirmOutcome(rawValue: status) ?? .unknown }

    public init(status: String, message: String) {
        self.status = status
        self.message = message
    }
}
