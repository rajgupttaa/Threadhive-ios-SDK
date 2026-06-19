import XCTest
@testable import ThreadHive

final class SessionTests: XCTestCase {
    private func makeSession(api: WidgetAPI) -> WidgetSession {
        let config = ThreadHiveConfiguration(widgetKey: "wk_\(UUID().uuidString)", apiBaseURL: URL(string: "https://app.example.com/api")!)
        return WidgetSession(
            configuration: config,
            api: api,
            defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!,
            secureStore: InMemorySecureStore()
        )
    }

    func testConfigIsCachedAfterFirstFetch() async throws {
        let api = StubWidgetAPI()
        let counter = Counter()
        api.onConfig = {
            counter.increment()
            return WidgetPublicConfig(workspaceName: "Acme", widgetKey: "wk_1", aiAvailable: true)
        }
        let session = makeSession(api: api)

        let first = try await session.config()
        let second = try await session.config()
        XCTAssertEqual(first.workspaceName, "Acme")
        XCTAssertEqual(second.workspaceName, "Acme")
        XCTAssertEqual(counter.value, 1, "second read served from cache")

        _ = try await session.config(forceRefresh: true)
        XCTAssertEqual(counter.value, 2, "forceRefresh bypasses cache")
    }

    func testIdentifyForwardsVisitorIDAndRecordsIdentity() async throws {
        let api = StubWidgetAPI()
        var sentVisitorID: String?
        var sentHash: String?
        api.onIdentify = { request in
            sentVisitorID = request.visitorID
            sentHash = request.userHash
            return IdentifyResponse(ok: true, contactID: "c1", verified: true)
        }
        let session = makeSession(api: api)
        let response = try await session.identify(userID: "u1", email: "a@b.com", userHash: "h")

        XCTAssertTrue(response.verified)
        XCTAssertEqual(sentVisitorID, session.visitorID)
        XCTAssertEqual(sentHash, "h")
        XCTAssertEqual(session.currentIdentity?.userID, "u1")
        XCTAssertEqual(session.currentIdentity?.email, "a@b.com")
    }

    func testRefreshUnreadCount() async throws {
        let api = StubWidgetAPI()
        api.onListConversations = { _, _ in
            [
                try ConversationSummary.make(id: "c1", lastMessageAuthor: .agent),
                try ConversationSummary.make(id: "c2", lastMessageAuthor: .visitor),
            ]
        }
        let session = makeSession(api: api)
        let count = await session.refreshUnreadCount()
        XCTAssertEqual(count, 1, "only the agent thread is unread")

        session.markConversationSeen("c1", at: "2026-06-19T10:00:00+00:00")
        let afterSeen = await session.refreshUnreadCount()
        XCTAssertEqual(afterSeen, 0)
    }

    func testRefreshUnreadCountSwallowsErrors() async {
        let api = StubWidgetAPI()
        api.onListConversations = { _, _ in throw APIError.transport("down") }
        let session = makeSession(api: api)
        let count = await session.refreshUnreadCount()
        XCTAssertEqual(count, 0)
    }

    func testLogoutResetsVisitorAndIdentity() async throws {
        let api = StubWidgetAPI()
        let session = makeSession(api: api)
        let original = session.visitorID
        _ = try await session.identify(userID: "u1")
        XCTAssertNotNil(session.currentIdentity)

        session.logout()
        XCTAssertNil(session.currentIdentity)
        XCTAssertNotEqual(session.visitorID, original, "a fresh anonymous visitor is minted")
    }
}

final class FacadeTests: XCTestCase {
    func testConfigureExposesStableVisitorAndLogoutResets() {
        ThreadHive.configure(ThreadHiveConfiguration(
            widgetKey: "wk_facade_\(UUID().uuidString)",
            apiBaseURL: URL(string: "https://app.example.com/api")!,
            secureStore: InMemorySecureStore()
        ))
        XCTAssertTrue(ThreadHive.isConfigured)
        XCTAssertNotNil(ThreadHive.api)

        let v1 = ThreadHive.visitorID
        XCTAssertNotNil(v1)
        XCTAssertEqual(ThreadHive.visitorID, v1, "stable across reads")

        ThreadHive.logout()
        XCTAssertNotEqual(ThreadHive.visitorID, v1, "logout mints a fresh visitor")
    }
}
