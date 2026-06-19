import Foundation

/// Owns the anonymous `visitor_id` — minted once, persisted in the secure store,
/// keyed per widget key (so two widgets in one app don't share a visitor).
final class VisitorStore {
    private let store: SecureStore
    private let widgetKey: String
    private let lock = NSLock()
    private var cached: String?

    init(store: SecureStore, widgetKey: String) {
        self.store = store
        self.widgetKey = widgetKey
    }

    private var key: String { "visitor_id_\(widgetKey)" }

    /// The current visitor id, minting + persisting one on first access.
    func currentVisitorID() -> String {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        if let existing = store.string(forKey: key), existing.count >= 8 {
            cached = existing
            return existing
        }
        let fresh = UUID().uuidString
        try? store.set(fresh, forKey: key)
        cached = fresh
        return fresh
    }

    /// Drop the stored id (e.g. on logout). The next `currentVisitorID()` mints
    /// a fresh anonymous identity.
    func clear() {
        lock.lock(); defer { lock.unlock() }
        store.removeValue(forKey: key)
        cached = nil
    }
}
