import XCTest
@testable import ThreadHive

final class StorageTests: XCTestCase {
    func testVisitorIDMintsPersistsAndReuses() {
        let store = InMemorySecureStore()
        let a = VisitorStore(store: store, widgetKey: "wk_1")
        let first = a.currentVisitorID()
        XCTAssertGreaterThanOrEqual(first.count, 8)
        XCTAssertEqual(a.currentVisitorID(), first, "stable within an instance")

        // A second store over the same backing reads the persisted id.
        let b = VisitorStore(store: store, widgetKey: "wk_1")
        XCTAssertEqual(b.currentVisitorID(), first, "persisted across instances")
    }

    func testVisitorIDIsScopedPerWidgetKey() {
        let store = InMemorySecureStore()
        let a = VisitorStore(store: store, widgetKey: "wk_1").currentVisitorID()
        let b = VisitorStore(store: store, widgetKey: "wk_2").currentVisitorID()
        XCTAssertNotEqual(a, b)
    }

    func testClearMintsFreshID() {
        let store = InMemorySecureStore()
        let visitor = VisitorStore(store: store, widgetKey: "wk_1")
        let first = visitor.currentVisitorID()
        visitor.clear()
        let second = visitor.currentVisitorID()
        XCTAssertNotEqual(first, second)
    }

    func testConfigCacheStoreAndLoadWithinTTL() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let cache = ConfigCache(defaults: defaults, widgetKey: "wk_1", ttl: 100)
        XCTAssertNil(cache.load())
        let config = WidgetPublicConfig(workspaceName: "Acme", widgetKey: "wk_1", aiAvailable: true)
        cache.store(config)
        XCTAssertEqual(cache.load()?.workspaceName, "Acme")
        XCTAssertEqual(cache.load()?.aiAvailable, true)
        cache.clear()
        XCTAssertNil(cache.load())
    }

    func testConfigCacheExpires() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let cache = ConfigCache(defaults: defaults, widgetKey: "wk_1", ttl: 0)
        cache.store(WidgetPublicConfig(workspaceName: "Acme", widgetKey: "wk_1"))
        XCTAssertNil(cache.load(), "ttl 0 means immediately stale")
    }

    func testUnreadTrackerCountsInboundAndRespectsSeen() throws {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let tracker = UnreadTracker(defaults: defaults, widgetKey: "wk_1")

        let unreadAgent = try ConversationSummary.make(id: "c1", lastMessageAuthor: .agent, lastMessageAt: "2026-06-19T10:00:00+00:00")
        let ownMessage = try ConversationSummary.make(id: "c2", lastMessageAuthor: .visitor, lastMessageAt: "2026-06-19T10:00:00+00:00")
        let botMessage = try ConversationSummary.make(id: "c3", lastMessageAuthor: .bot, lastMessageAt: "2026-06-19T10:00:00+00:00")

        XCTAssertEqual(tracker.unreadCount(from: [unreadAgent, ownMessage, botMessage]), 2, "agent + bot count; our own does not")

        tracker.markSeen(conversationID: "c1", at: "2026-06-19T10:00:00+00:00")
        XCTAssertEqual(tracker.unreadCount(from: [unreadAgent, ownMessage, botMessage]), 1, "c1 now seen")

        // Older seen marker does not clear newer activity.
        tracker.markSeen(conversationID: "c3", at: "2026-06-19T09:00:00+00:00")
        XCTAssertEqual(tracker.unreadCount(from: [unreadAgent, botMessage]), 1, "c3 has newer activity than the seen marker")
    }
}
