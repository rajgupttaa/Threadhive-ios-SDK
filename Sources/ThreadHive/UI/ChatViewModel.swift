import Foundation
import Combine

/// Drives the chat experience: sending (ask / reply), optimistic rendering with
/// server-id reconciliation, agent-reply polling, typing, products, bot action
/// confirmations, attachments, and CSAT. Pure logic + Combine (no UIKit), so it
/// is unit-testable and reusable behind a custom UI.
@MainActor
public final class ChatViewModel: ObservableObject {
    // Presentation state
    @Published public private(set) var messages: [ChatMessage] = []
    @Published public private(set) var resolved: ResolvedConfig
    @Published public private(set) var workspaceName: String
    @Published public private(set) var team: [WidgetTeamMember] = []
    @Published public private(set) var teamOverflow: Int = 0
    @Published public private(set) var replyTimeLabel: String?
    @Published public private(set) var aiAvailable: Bool = true
    @Published public private(set) var isOnline: Bool = true
    @Published public private(set) var status: ConversationStatus = .open
    @Published public private(set) var assignedAgent: WidgetTeamMember?
    @Published public private(set) var agentTyping: Bool = false
    @Published public private(set) var botThinking: Bool = false
    @Published public private(set) var conversationID: String?
    @Published public private(set) var pendingUploads: [MessageAttachment] = []
    @Published public private(set) var isUploading: Bool = false
    @Published public private(set) var banner: String?
    @Published public private(set) var csatScore: Int?
    @Published public private(set) var pastConversations: [ConversationSummary] = []
    @Published public var inputText: String = ""

    // Hooks wired by the host (UIKit interop lives outside this MainActor logic).
    public var onOpenURL: ((URL) -> Void)?
    public var onConversationIDChanged: ((String) -> Void)?
    public var onUnreadSeen: ((String, String) -> Void)?

    // Dependencies
    private let api: WidgetAPI
    private let visitorID: String
    public let endpoints: WidgetEndpoints?
    private let overrides: ThemeOverrides
    private let pollInterval: TimeInterval
    private let typingPingInterval: TimeInterval
    private let logger: ThreadHiveLogger?

    // Reconciliation state
    private var seenServerIDs = Set<String>()
    private var cursor: String?
    private var pollTask: Task<Void, Never>?
    private var lastTypingPingAt = Date.distantPast
    private var greetingShown = false

    public init(
        api: WidgetAPI,
        visitorID: String,
        config: WidgetPublicConfig? = nil,
        overrides: ThemeOverrides = ThemeOverrides(),
        endpoints: WidgetEndpoints? = nil,
        initialConversationID: String? = nil,
        pollInterval: TimeInterval = 4,
        typingPingInterval: TimeInterval = 2,
        logger: ThreadHiveLogger? = nil
    ) {
        self.api = api
        self.visitorID = visitorID
        self.overrides = overrides
        self.endpoints = endpoints
        self.conversationID = initialConversationID
        self.pollInterval = max(1, pollInterval)
        self.typingPingInterval = max(1, typingPingInterval)
        self.logger = logger
        self.workspaceName = config?.workspaceName ?? ""
        self.resolved = ResolvedConfig(config: config, overrides: overrides, workspaceName: config?.workspaceName ?? "")
        if let config { applyConfig(config) }
    }

    deinit { pollTask?.cancel() }

    // MARK: - Lifecycle

    /// Call when the chat becomes visible. Refreshes config, loads/starts the
    /// thread, and begins polling.
    public func onAppear() {
        Task {
            await refreshConfig()
            if let cid = conversationID {
                await loadThread(cid)
            } else {
                showGreetingIfNeeded()
            }
            startPolling()
        }
    }

    /// Call when the chat is dismissed/backgrounded — stops the poll loop.
    public func onDisappear() {
        stopPolling()
    }

    public func dismissBanner() { banner = nil }

    // MARK: - Config

    public func refreshConfig() async {
        do {
            let config = try await api.fetchConfig()
            applyConfig(config)
        } catch {
            logger?.log(.debug, "config refresh failed: \(error.localizedDescription)")
        }
    }

    private func applyConfig(_ config: WidgetPublicConfig) {
        workspaceName = config.workspaceName
        resolved = ResolvedConfig(config: config, overrides: overrides, workspaceName: config.workspaceName)
        team = config.team
        teamOverflow = config.teamOverflow
        replyTimeLabel = config.replyTimeLabel
        aiAvailable = config.aiAvailable
        isOnline = config.isOpen
    }

    private func showGreetingIfNeeded() {
        guard !greetingShown, messages.isEmpty else { return }
        greetingShown = true
        messages.append(ChatMessage(
            id: "greeting",
            author: .bot,
            authorName: resolved.botName,
            text: resolved.greeting
        ))
    }

    // MARK: - Messages tab (history)

    /// Load the visitor's past conversations for the Messages tab.
    public func loadConversations() async {
        do {
            pastConversations = try await api.listConversations(visitorID: visitorID)
        } catch {
            logger?.log(.debug, "list conversations failed: \(error.localizedDescription)")
        }
    }

    /// Reopen a past thread: reset state and load it from the server.
    public func reopen(_ summary: ConversationSummary) {
        resetThreadState()
        conversationID = summary.id
        onConversationIDChanged?(summary.id)
        Task {
            await loadThread(summary.id)
            startPolling()
        }
    }

    /// Start a fresh conversation (next send creates it server-side).
    public func startNewConversation() {
        resetThreadState()
        conversationID = nil
        showGreetingIfNeeded()
    }

    private func resetThreadState() {
        stopPolling()
        messages.removeAll()
        seenServerIDs.removeAll()
        cursor = nil
        greetingShown = false
        csatScore = nil
        assignedAgent = nil
        agentTyping = false
        botThinking = false
    }

    // MARK: - Sending

    /// Tap a suggested question.
    public func sendSuggestion(_ text: String) {
        inputText = text
        send()
    }

    struct PreparedSend { let text: String; let attachmentIDs: [String]; let tempID: String }

    public func send() {
        guard let prepared = prepareSend() else { return }
        Task { await performSend(prepared) }
    }

    /// Synchronously stage the optimistic visitor bubble + clear the composer.
    /// Returns the work for `performSend`, or nil when there's nothing to send.
    /// Split out so tests can drive send deterministically.
    func prepareSend() -> PreparedSend? {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachmentIDs = pendingUploads.map { $0.id }
        guard !text.isEmpty || !attachmentIDs.isEmpty else { return nil }

        inputText = ""
        let staged = pendingUploads
        pendingUploads = []
        banner = nil

        let tempID = "temp:\(UUID().uuidString)"
        messages.append(ChatMessage(
            id: tempID, author: .visitor, authorName: "You", text: text,
            attachments: staged, sendState: .sending, awaitingEcho: true
        ))
        botThinking = !text.isEmpty
        return PreparedSend(text: text, attachmentIDs: attachmentIDs, tempID: tempID)
    }

    func performSend(_ prepared: PreparedSend) async {
        let text = prepared.text, attachmentIDs = prepared.attachmentIDs, tempID = prepared.tempID
        do {
            if let cid = conversationID {
                let response = try await api.sendMessage(conversationID: cid, body: text, visitorID: visitorID, attachmentIDs: attachmentIDs)
                handleSendResponse(response)
            } else {
                let response = try await api.ask(AskRequest(question: text, visitorID: visitorID, attachmentIDs: attachmentIDs))
                handleAskResponse(response)
            }
            markSendState(tempID, .sent)
            await pollOnce()
            startPolling()
        } catch {
            // Never lose the composer text — restore it and drop the failed bubble.
            messages.removeAll { $0.id == tempID }
            if inputText.isEmpty { inputText = text }
            botThinking = false
            banner = "Couldn’t send your message. Check your connection and try again."
            logger?.log(.warning, "send failed: \(error.localizedDescription)")
        }
    }

    private func handleAskResponse(_ response: AskResponse) {
        botThinking = false
        if let cid = response.conversationID { setConversationID(cid) }
        guard !response.answer.isEmpty else { return } // attachment-only / human-owned
        let author: ChatAuthor = response.handoff ? .system : .bot
        messages.append(ChatMessage(
            id: "temp:\(UUID().uuidString)",
            author: author,
            authorName: response.handoff ? "" : resolved.botName,
            text: response.answer,
            citations: response.sources,
            products: response.products,
            pendingActions: response.pendingActions,
            awaitingEcho: true
        ))
    }

    private func handleSendResponse(_ response: SendMessageResponse) {
        botThinking = false
        setConversationID(response.conversationID)
        // The bot/system reply arrives via /poll (kept as the single render path).
    }

    private func setConversationID(_ cid: String) {
        guard conversationID != cid else { return }
        conversationID = cid
        onConversationIDChanged?(cid)
    }

    private func markSendState(_ id: String, _ state: SendState) {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[idx].sendState = state
    }

    // MARK: - Polling + reconciliation

    private func loadThread(_ cid: String) async {
        do {
            let poll = try await api.poll(conversationID: cid, since: nil, visitorID: visitorID)
            apply(poll)
        } catch {
            logger?.log(.debug, "load thread failed: \(error.localizedDescription)")
            showGreetingIfNeeded()
        }
    }

    private func startPolling() {
        guard conversationID != nil, pollTask == nil else { return }
        let interval = pollInterval
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.pollOnce()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// One poll tick (also reachable from tests).
    public func pollOnce() async {
        guard let cid = conversationID else { return }
        do {
            let poll = try await api.poll(conversationID: cid, since: cursor, visitorID: visitorID)
            apply(poll)
        } catch {
            logger?.log(.debug, "poll failed: \(error.localizedDescription)")
        }
    }

    private func apply(_ poll: ConversationPoll) {
        reconcile(poll.messages)
        cursor = poll.cursor ?? cursor
        status = poll.status
        assignedAgent = poll.assignedAgent
        agentTyping = poll.typing.agent
        if let score = poll.csatScore { csatScore = score }

        // Mark the newest inbound message seen (unread badge + read receipt).
        if let cid = conversationID,
           let newest = poll.messages.last(where: { $0.authorKind != .visitor }) {
            onUnreadSeen?(cid, newest.createdAt)
            let messageID = newest.id
            Task { _ = try? await api.markSeen(messageID: messageID, visitorID: visitorID) }
        }
    }

    /// Merge polled messages: bind to optimistic locals by (author, body), dedupe
    /// by server id, append the genuinely new.
    private func reconcile(_ incoming: [WidgetMessage]) {
        for message in incoming {
            if seenServerIDs.contains(message.id) {
                if let idx = messages.firstIndex(where: { $0.serverID == message.id }) {
                    messages[idx].attachments = message.attachments.isEmpty ? messages[idx].attachments : message.attachments
                    messages[idx].avatarURL = message.authorAvatarURL ?? messages[idx].avatarURL
                }
                continue
            }
            let author = ChatAuthor(message.authorKind)
            if let idx = messages.firstIndex(where: {
                $0.awaitingEcho && $0.serverID == nil && $0.author == author && $0.text == message.body
            }) {
                messages[idx].serverID = message.id
                messages[idx].awaitingEcho = false
                messages[idx].createdAt = message.createdAt
                messages[idx].sendState = (author == .visitor) ? .sent : nil
                if messages[idx].attachments.isEmpty { messages[idx].attachments = message.attachments }
                messages[idx].avatarURL = message.authorAvatarURL ?? messages[idx].avatarURL
            } else {
                messages.append(ChatMessage(message))
            }
            seenServerIDs.insert(message.id)
        }
    }

    // MARK: - Typing

    /// Call from the composer's text change. Throttled to `typingPingInterval`.
    public func userIsTyping() {
        guard let cid = conversationID else { return }
        let now = Date()
        guard now.timeIntervalSince(lastTypingPingAt) >= typingPingInterval else { return }
        lastTypingPingAt = now
        Task { _ = try? await api.sendTyping(conversationID: cid, isTyping: true, visitorID: visitorID) }
    }

    // MARK: - Bot action confirmation

    public func confirm(_ action: PendingAction, accept: Bool) {
        Task { await confirmNow(action, accept: accept) }
    }

    func confirmNow(_ action: PendingAction, accept: Bool) async {
        do {
                let result = try await api.confirmAction(
                    runID: action.runID,
                    request: ConfirmActionRequest(confirmToken: action.confirmToken, confirm: accept)
                )
                removePendingAction(action)
                if !result.message.isEmpty {
                    messages.append(ChatMessage(
                        id: "temp:\(UUID().uuidString)", author: .bot,
                        authorName: resolved.botName, text: result.message, awaitingEcho: true
                    ))
                }
                await pollOnce()
            } catch {
                banner = "Couldn’t complete that action. Please try again."
                logger?.log(.warning, "confirm failed: \(error.localizedDescription)")
            }
    }

    private func removePendingAction(_ action: PendingAction) {
        for idx in messages.indices {
            messages[idx].pendingActions.removeAll { $0.runID == action.runID }
        }
    }

    // MARK: - Commerce + citations (open in in-app browser)

    public func open(_ product: Product) {
        guard let raw = product.url, let url = Self.safeURL(raw) else { return }
        onOpenURL?(url)
    }

    public func openCitation(_ source: AskSource) {
        guard let raw = source.chunkURL, let url = Self.safeURL(raw) else { return }
        onOpenURL?(url)
    }

    /// Only http(s) URLs are opened (validate before handing to a browser).
    public static func safeURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    /// Resolve a message attachment's relative URL for display.
    public func attachmentURL(_ attachment: MessageAttachment) -> URL? {
        endpoints?.resolveAttachmentURL(attachment.url) ?? URL(string: attachment.url)
    }

    // MARK: - Attachments

    public func upload(data: Data, fileName: String, mimeType: String) {
        guard let cid = conversationID else {
            banner = "Send a message first — then you can attach files to the conversation."
            return
        }
        isUploading = true
        Task {
            defer { isUploading = false }
            do {
                let attachment = try await api.uploadAttachment(conversationID: cid, data: data, fileName: fileName, mimeType: mimeType, visitorID: visitorID)
                pendingUploads.append(attachment)
            } catch {
                banner = "Couldn’t upload that file."
                logger?.log(.warning, "upload failed: \(error.localizedDescription)")
            }
        }
    }

    public func removeUpload(_ attachment: MessageAttachment) {
        pendingUploads.removeAll { $0.id == attachment.id }
    }

    public var canAttach: Bool { conversationID != nil }

    // MARK: - CSAT

    public func submitCSAT(score: Int, comment: String? = nil) {
        guard let cid = conversationID else { return }
        csatScore = score
        Task { _ = try? await api.submitCSAT(CSATRequest(conversationID: cid, score: score, visitorID: visitorID, comment: comment)) }
    }
}
