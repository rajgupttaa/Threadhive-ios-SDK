import Foundation

/// The full surface the chat UI talks to. Backed by `WidgetAPIClient` against a
/// live ThreadHive backend; stub it in tests / previews. Every "to confirm"
/// endpoint from the build brief is resolved here against the real routes (see
/// `mobile-sdks/API_CONTRACT.md`).
public protocol WidgetAPI: AnyObject {
    /// `GET /config.json` — theming + presence.
    func fetchConfig() async throws -> WidgetPublicConfig

    /// `POST /ask` — send a visitor message, get the bot reply.
    func ask(_ request: AskRequest) async throws -> AskResponse

    /// `POST /actions/{runID}/confirm` — confirm/decline a bot-prepared action.
    func confirmAction(runID: String, request: ConfirmActionRequest) async throws -> ConfirmActionResponse

    /// `GET /conversations/{id}/poll` — new messages + typing since `cursor`.
    func poll(conversationID: String, since cursor: String?, visitorID: String?) async throws -> ConversationPoll

    /// `GET /conversations` — the visitor's past threads (Messages tab).
    func listConversations(visitorID: String, limit: Int) async throws -> [ConversationSummary]

    /// `POST /conversations/{id}/messages` — visitor reply on an existing thread.
    func sendMessage(conversationID: String, body: String, visitorID: String?, attachmentIDs: [String]) async throws -> SendMessageResponse

    /// `POST /conversations/{id}/attachments` — multipart upload.
    func uploadAttachment(conversationID: String, fileURL: URL, fileName: String?, mimeType: String?, visitorID: String) async throws -> MessageAttachment

    /// `POST /conversations/{id}/attachments` — multipart upload from in-memory data.
    func uploadAttachment(conversationID: String, data: Data, fileName: String, mimeType: String, visitorID: String) async throws -> MessageAttachment

    /// `POST /conversations/{id}/typing` — ping that the visitor is typing.
    @discardableResult
    func sendTyping(conversationID: String, isTyping: Bool, visitorID: String?) async throws -> TypingState

    /// `POST /identify` — link a logged-in user (HMAC computed server-side by the host).
    @discardableResult
    func identify(_ request: IdentifyRequest) async throws -> IdentifyResponse

    /// `POST /track` — pageview / custom event.
    @discardableResult
    func track(_ request: TrackRequest) async throws -> TrackResponse

    /// `POST /csat` — 1–5 satisfaction rating tied to a conversation.
    @discardableResult
    func submitCSAT(_ request: CSATRequest) async throws -> CSATResponse

    /// `POST /messages/{id}/seen` — mark an outbound message read.
    @discardableResult
    func markSeen(messageID: String, visitorID: String) async throws -> SeenResponse
}

public extension WidgetAPI {
    /// Convenience: first poll (no cursor).
    func poll(conversationID: String, visitorID: String?) async throws -> ConversationPoll {
        try await poll(conversationID: conversationID, since: nil, visitorID: visitorID)
    }

    func listConversations(visitorID: String) async throws -> [ConversationSummary] {
        try await listConversations(visitorID: visitorID, limit: 20)
    }
}
