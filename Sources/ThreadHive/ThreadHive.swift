import Foundation

/// ThreadHive native in-app chat. Configure once at launch, then present the
/// chat from anywhere.
///
/// ```swift
/// ThreadHive.configure(widgetKey: "wk_…", apiBaseURL: URL(string: "https://app.example.com/api")!)
/// ThreadHive.identify(userID: "u_123", email: "a@b.com", userHash: "…")   // optional
/// ThreadHive.presentChat(from: viewController)                              // UIKit host
/// ```
///
/// Thread-safe; all members may be called from any thread.
public enum ThreadHive {
    /// SemVer of the SDK (sent as `X-ThreadHive-SDK` and surfaced in docs).
    public static let sdkVersion = "1.1.0"

    private static let lock = NSLock()
    private static var _session: WidgetSession?

    // MARK: - Configuration

    /// Configure with the common defaults. `apiBaseURL` is your API origin,
    /// e.g. `https://app.example.com/api`.
    public static func configure(widgetKey: String, apiBaseURL: URL) {
        configure(ThreadHiveConfiguration(widgetKey: widgetKey, apiBaseURL: apiBaseURL))
    }

    /// Configure with full control (custom session for pinning, logger, polling
    /// cadence, injected secure store).
    public static func configure(_ configuration: ThreadHiveConfiguration) {
        lock.lock(); defer { lock.unlock() }
        _session = WidgetSession(configuration: configuration)
    }

    public static var isConfigured: Bool {
        lock.lock(); defer { lock.unlock() }
        return _session != nil
    }

    /// The current anonymous (or linked) visitor id, or nil if not configured.
    public static var visitorID: String? { sessionOrNil?.visitorID }

    /// The low-level API client, for power users / custom UIs. Nil until configured.
    public static var api: WidgetAPI? { sessionOrNil?.api }

    // MARK: - Identity

    /// Link a logged-in user. `userHash = HMAC-SHA256(identitySecret, userID)`
    /// must be computed by **your backend** and passed here — never embed the
    /// identity secret in the app. Fire-and-forget; pass `completion` to observe.
    public static func identify(
        userID: String,
        email: String? = nil,
        name: String? = nil,
        userHash: String? = nil,
        traits: [String: JSONValue]? = nil,
        completion: ((Result<IdentifyResponse, Error>) -> Void)? = nil
    ) {
        guard let session = sessionOrNil else {
            completion?(.failure(APIError.notConfigured))
            return
        }
        Task {
            do {
                let response = try await session.identify(userID: userID, email: email, name: name, userHash: userHash, traits: traits)
                completion?(.success(response))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    /// `async` variant of `identify`.
    @discardableResult
    public static func identify(
        userID: String,
        email: String? = nil,
        name: String? = nil,
        userHash: String? = nil,
        traits: [String: JSONValue]? = nil
    ) async throws -> IdentifyResponse {
        try await session().identify(userID: userID, email: email, name: name, userHash: userHash, traits: traits)
    }

    /// Clear the linked identity + visitor link and reset to a fresh anonymous
    /// visitor. Call on sign-out.
    public static func logout() {
        sessionOrNil?.logout()
    }

    // MARK: - Analytics

    /// Record a custom event for the current visitor (fire-and-forget).
    public static func track(_ event: String, properties: [String: JSONValue]? = nil) {
        guard let session = sessionOrNil else { return }
        Task { _ = try? await session.track(event, properties: properties) }
    }

    // MARK: - Push notifications

    /// Register the APNs device token (from
    /// `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`) so
    /// the backend can deliver agent replies while the app is backgrounded.
    /// Fire-and-forget; pass `completion` to observe. Re-call after `identify`
    /// or a fresh login so the token links to the right visitor.
    public static func registerPushToken(
        _ deviceToken: Data,
        environment: APNSEnvironment = .automatic,
        completion: ((Result<DeviceResponse, Error>) -> Void)? = nil
    ) {
        guard let session = sessionOrNil else {
            completion?(.failure(APIError.notConfigured))
            return
        }
        Task {
            do {
                let response = try await session.registerPushToken(deviceToken.threadHiveHexString, environment: environment)
                completion?(.success(response))
            } catch {
                completion?(.failure(error))
            }
        }
    }

    /// `async` variant of `registerPushToken`.
    @discardableResult
    public static func registerPushToken(
        _ deviceToken: Data,
        environment: APNSEnvironment = .automatic
    ) async throws -> DeviceResponse {
        try await session().registerPushToken(deviceToken.threadHiveHexString, environment: environment)
    }

    /// Stop delivering push to this device (also called automatically by `logout`).
    public static func unregisterPushToken() {
        sessionOrNil?.unregisterPushToken()
    }

    /// The conversation id carried by a ThreadHive push payload, or nil if the
    /// notification isn't one of ours.
    public static func conversationID(fromNotification userInfo: [AnyHashable: Any]) -> String? {
        userInfo["conversation_id"] as? String
    }

    /// Handle a notification tap. If it's a ThreadHive push, remember its
    /// conversation so the next `presentChat` / `ThreadHiveChatView` opens that
    /// thread, and return `true`. Call from your notification-tap handler, then
    /// present the chat when it returns `true`.
    @discardableResult
    public static func handleNotification(userInfo: [AnyHashable: Any]) -> Bool {
        guard let cid = conversationID(fromNotification: userInfo), let session = sessionOrNil else {
            return false
        }
        session.resumeConversationID = cid
        return true
    }

    // MARK: - Unread badge

    /// Best-effort count of conversations with unseen agent/bot replies.
    public static func unreadCount(_ completion: @escaping (Int) -> Void) {
        guard let session = sessionOrNil else { completion(0); return }
        Task {
            let count = await session.refreshUnreadCount()
            await MainActor.run { completion(count) }
        }
    }

    /// `async` variant of `unreadCount`.
    public static func unreadCount() async -> Int {
        guard let session = sessionOrNil else { return 0 }
        return await session.refreshUnreadCount()
    }

    // MARK: - Internal

    static func session() throws -> WidgetSession {
        lock.lock(); defer { lock.unlock() }
        guard let session = _session else { throw APIError.notConfigured }
        return session
    }

    static var sessionOrNil: WidgetSession? {
        lock.lock(); defer { lock.unlock() }
        return _session
    }

    /// Build a chat view model wired to the configured session (conversation
    /// resume, unread tracking). Nil until configured. Used by the SwiftUI view
    /// and the UIKit presenters.
    @MainActor
    static func makeChatViewModel() -> ChatViewModel? {
        guard let session = sessionOrNil else { return nil }
        let model = ChatViewModel(
            api: session.api,
            visitorID: session.visitorID,
            config: nil,
            overrides: session.configuration.theme,
            endpoints: session.endpoints,
            initialConversationID: session.resumeConversationID,
            pollInterval: session.configuration.pollInterval,
            typingPingInterval: session.configuration.typingPingInterval,
            logger: session.configuration.logger
        )
        model.onConversationIDChanged = { [weak session] cid in session?.resumeConversationID = cid }
        model.onUnreadSeen = { [weak session] cid, iso in session?.markConversationSeen(cid, at: iso) }
        return model
    }

    /// Test seam — install a session backed by a stub API.
    static func _installForTesting(_ session: WidgetSession?) {
        lock.lock(); defer { lock.unlock() }
        _session = session
    }
}
