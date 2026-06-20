import Foundation

/// Internal engine wiring the API client, visitor identity, config cache, and
/// unread tracking together. The chat UI and the `ThreadHive` facade both drive
/// the session; it is the single owner of per-widget state.
final class WidgetSession {
    let configuration: ThreadHiveConfiguration
    let api: WidgetAPI
    let endpoints: WidgetEndpoints

    private let visitorStore: VisitorStore
    private let configCache: ConfigCache
    private let unreadTracker: UnreadTracker
    private let conversationDefaults: UserDefaults
    private let lock = NSLock()
    private var identity: Identity?
    private var lastPushToken: String?

    struct Identity: Equatable {
        let userID: String
        let email: String?
        let name: String?
    }

    init(configuration: ThreadHiveConfiguration) {
        self.configuration = configuration
        let store = configuration.secureStore ?? KeychainSecureStore()
        self.visitorStore = VisitorStore(store: store, widgetKey: configuration.widgetKey)
        self.configCache = ConfigCache(defaults: .standard, widgetKey: configuration.widgetKey)
        self.unreadTracker = UnreadTracker(defaults: .standard, widgetKey: configuration.widgetKey)
        self.conversationDefaults = .standard
        let client = WidgetAPIClient(
            apiBaseURL: configuration.apiBaseURL,
            widgetKey: configuration.widgetKey,
            session: configuration.urlSession,
            logger: configuration.logger,
            retryPolicy: configuration.retryPolicy
        )
        self.api = client
        self.endpoints = client.endpoints
    }

    /// Test/advanced seam: inject a stub `WidgetAPI`.
    init(configuration: ThreadHiveConfiguration, api: WidgetAPI, defaults: UserDefaults, secureStore: SecureStore) {
        self.configuration = configuration
        self.api = api
        self.endpoints = WidgetEndpoints(apiBaseURL: configuration.apiBaseURL, widgetKey: configuration.widgetKey)
        self.visitorStore = VisitorStore(store: secureStore, widgetKey: configuration.widgetKey)
        self.configCache = ConfigCache(defaults: defaults, widgetKey: configuration.widgetKey)
        self.unreadTracker = UnreadTracker(defaults: defaults, widgetKey: configuration.widgetKey)
        self.conversationDefaults = defaults
    }

    var visitorID: String { visitorStore.currentVisitorID() }

    var currentIdentity: Identity? {
        lock.lock(); defer { lock.unlock() }
        return identity
    }

    private func setIdentity(_ value: Identity?) {
        lock.lock(); defer { lock.unlock() }
        identity = value
    }

    private func setLastPushToken(_ value: String?) {
        lock.lock(); defer { lock.unlock() }
        lastPushToken = value
    }

    /// Read and clear the stored token in one locked step.
    private func takeLastPushToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        let token = lastPushToken
        lastPushToken = nil
        return token
    }

    /// Published config, served from the TTL cache when warm.
    func config(forceRefresh: Bool = false) async throws -> WidgetPublicConfig {
        if !forceRefresh, let cached = configCache.load() { return cached }
        let fresh = try await api.fetchConfig()
        configCache.store(fresh)
        return fresh
    }

    @discardableResult
    func identify(
        userID: String, email: String? = nil, name: String? = nil,
        phone: String? = nil, userHash: String? = nil, traits: [String: JSONValue]? = nil
    ) async throws -> IdentifyResponse {
        let request = IdentifyRequest(
            visitorID: visitorID, userID: userID, email: email, name: name,
            phone: phone, traits: traits, userHash: userHash
        )
        setIdentity(Identity(userID: userID, email: email, name: name))
        return try await api.identify(request)
    }

    @discardableResult
    func track(_ name: String, type: TrackRequest.EventType = .custom, properties: [String: JSONValue]? = nil, url: String? = nil) async throws -> TrackResponse {
        try await api.track(TrackRequest(visitorID: visitorID, type: type, name: name, url: url, properties: properties))
    }

    // MARK: - Push registration

    /// Register an APNs token for the current visitor. Stored so `logout()` can
    /// drop it server-side. `appBundleID` is the host app's bundle id (APNs topic).
    @discardableResult
    func registerPushToken(_ token: String, environment: APNSEnvironment) async throws -> DeviceResponse {
        setLastPushToken(token)
        let request = DeviceRegisterRequest(
            visitorID: visitorID,
            token: token,
            appBundleID: Bundle.main.bundleIdentifier,
            environment: environment.rawValue
        )
        return try await api.registerDevice(request)
    }

    /// Drop the last-registered token server-side (fire-and-forget).
    func unregisterPushToken() {
        let token = takeLastPushToken()
        let vid = visitorID
        let api = self.api
        Task { _ = try? await api.unregisterDevice(DeviceUnregisterRequest(visitorID: vid, token: token)) }
    }

    /// Clear the linked identity, drop the visitor id (a fresh anonymous one is
    /// minted on next use), and wipe local caches.
    func logout() {
        unregisterPushToken()
        lock.lock(); identity = nil; lock.unlock()
        visitorStore.clear()
        configCache.clear()
        unreadTracker.clear()
        resumeConversationID = nil
    }

    func markConversationSeen(_ conversationID: String, at iso: String) {
        unreadTracker.markSeen(conversationID: conversationID, at: iso)
    }

    /// The most recent conversation the visitor was in (persisted, non-secret) —
    /// so reopening the chat resumes the same thread, like the web widget's
    /// localStorage-stored conversation id.
    private var resumeKey: String { "threadhive_conversation_\(configuration.widgetKey)" }

    var resumeConversationID: String? {
        get { conversationDefaults.string(forKey: resumeKey) }
        set {
            if let newValue { conversationDefaults.set(newValue, forKey: resumeKey) }
            else { conversationDefaults.removeObject(forKey: resumeKey) }
        }
    }

    /// Best-effort unread count from the visitor's conversation list. Returns 0
    /// on any error so a transient failure never breaks a badge.
    func refreshUnreadCount() async -> Int {
        do {
            let summaries = try await api.listConversations(visitorID: visitorID)
            return unreadTracker.unreadCount(from: summaries)
        } catch {
            configuration.logger?.log(.debug, "unread refresh failed: \(error)")
            return 0
        }
    }
}
