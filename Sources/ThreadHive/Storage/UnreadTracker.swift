import Foundation

/// Local, per-conversation "last seen" bookkeeping that powers the host's
/// unread badge. A conversation is unread when its newest message is from the
/// other side (bot/agent/system) and is newer than what the visitor last saw.
///
/// Timestamps are compared as the backend's ISO strings — same producer, same
/// UTC offset, so lexicographic order matches chronological order.
final class UnreadTracker {
    private let defaults: UserDefaults
    private let key: String
    private let lock = NSLock()

    init(defaults: UserDefaults, widgetKey: String) {
        self.defaults = defaults
        self.key = "threadhive_seen_\(widgetKey)"
    }

    private func seenMap() -> [String: String] {
        (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
    }

    private func setSeenMap(_ map: [String: String]) {
        defaults.set(map, forKey: key)
    }

    /// Mark a conversation seen up to `iso` (no-op if already at/after it).
    func markSeen(conversationID: String, at iso: String) {
        lock.lock(); defer { lock.unlock() }
        var map = seenMap()
        if let existing = map[conversationID], existing >= iso { return }
        map[conversationID] = iso
        setSeenMap(map)
    }

    /// Count of conversations with unseen inbound activity.
    func unreadCount(from summaries: [ConversationSummary]) -> Int {
        lock.lock(); defer { lock.unlock() }
        let map = seenMap()
        return summaries.reduce(into: 0) { total, summary in
            guard let last = summary.lastMessageAt else { return }
            // Skip our own last message (and unknown authors) — not "unread".
            let author = summary.lastMessageAuthor
            if author == nil || author == .visitor { return }
            if let seen = map[summary.id], seen >= last { return }
            total += 1
        }
    }

    func clear() {
        lock.lock(); defer { lock.unlock() }
        defaults.removeObject(forKey: key)
    }
}
