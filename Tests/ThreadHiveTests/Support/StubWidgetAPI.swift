import Foundation
@testable import ThreadHive

/// A fully-overridable `WidgetAPI` for session/UI tests. Each method delegates
/// to a closure; unset closures throw `notConfigured`.
final class StubWidgetAPI: WidgetAPI {
    var onConfig: () async throws -> WidgetPublicConfig = { throw APIError.notConfigured }
    var onAsk: (AskRequest) async throws -> AskResponse = { _ in throw APIError.notConfigured }
    var onConfirm: (String, ConfirmActionRequest) async throws -> ConfirmActionResponse = { _, _ in throw APIError.notConfigured }
    var onPoll: (String, String?, String?) async throws -> ConversationPoll = { _, _, _ in throw APIError.notConfigured }
    var onListConversations: (String, Int) async throws -> [ConversationSummary] = { _, _ in [] }
    var onSendMessage: (String, String, String?, [String]) async throws -> SendMessageResponse = { _, _, _, _ in throw APIError.notConfigured }
    var onIdentify: (IdentifyRequest) async throws -> IdentifyResponse = { _ in IdentifyResponse(ok: true, contactID: "c", verified: false) }
    var onTrack: (TrackRequest) async throws -> TrackResponse = { _ in TrackResponse(ok: true, contactID: "c") }
    var onCSAT: (CSATRequest) async throws -> CSATResponse = { _ in CSATResponse(ok: true, submissionID: "s", conversationID: "c") }

    func fetchConfig() async throws -> WidgetPublicConfig { try await onConfig() }
    func ask(_ request: AskRequest) async throws -> AskResponse { try await onAsk(request) }
    func confirmAction(runID: String, request: ConfirmActionRequest) async throws -> ConfirmActionResponse { try await onConfirm(runID, request) }
    func poll(conversationID: String, since cursor: String?, visitorID: String?) async throws -> ConversationPoll { try await onPoll(conversationID, cursor, visitorID) }
    func listConversations(visitorID: String, limit: Int) async throws -> [ConversationSummary] { try await onListConversations(visitorID, limit) }
    func sendMessage(conversationID: String, body: String, visitorID: String?, attachmentIDs: [String]) async throws -> SendMessageResponse { try await onSendMessage(conversationID, body, visitorID, attachmentIDs) }
    func uploadAttachment(conversationID: String, fileURL: URL, fileName: String?, mimeType: String?, visitorID: String) async throws -> MessageAttachment { throw APIError.notConfigured }
    func uploadAttachment(conversationID: String, data: Data, fileName: String, mimeType: String, visitorID: String) async throws -> MessageAttachment { throw APIError.notConfigured }
    func sendTyping(conversationID: String, isTyping: Bool, visitorID: String?) async throws -> TypingState { TypingState() }
    func identify(_ request: IdentifyRequest) async throws -> IdentifyResponse { try await onIdentify(request) }
    func track(_ request: TrackRequest) async throws -> TrackResponse { try await onTrack(request) }
    func submitCSAT(_ request: CSATRequest) async throws -> CSATResponse { try await onCSAT(request) }
    func markSeen(messageID: String, visitorID: String) async throws -> SeenResponse { SeenResponse(ok: true, readAt: nil) }
}

extension ConversationSummary {
    /// Test factory (the production type only has a decoding initializer).
    static func make(
        id: String, status: ConversationStatus = .open, subject: String = "S",
        lastMessagePreview: String = "p", lastMessageAuthor: AuthorKind? = .agent,
        lastMessageAt: String? = "2026-06-19T10:00:00+00:00", aiHandled: Bool = false, unread: Bool = false
    ) throws -> ConversationSummary {
        let dict: [String: Any] = [
            "id": id, "status": status.rawValue, "subject": subject,
            "last_message_preview": lastMessagePreview,
            "last_message_author": lastMessageAuthor?.rawValue as Any,
            "last_message_at": lastMessageAt as Any,
            "ai_handled": aiHandled, "unread": unread,
        ]
        let data = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(ConversationSummary.self, from: data)
    }
}
