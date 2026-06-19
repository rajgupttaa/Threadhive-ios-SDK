import XCTest
@testable import ThreadHive

/// Async variant of `XCTAssertThrowsError`.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error to be thrown", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

final class WidgetAPIClientTests: XCTestCase {
    private let base = URL(string: "https://app.example.com/api")!
    private let fastRetry = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2, maxDelay: 0.05)

    private func makeClient(retry: RetryPolicy? = nil) -> WidgetAPIClient {
        WidgetAPIClient(
            apiBaseURL: base,
            widgetKey: "wk_1",
            session: StubURLProtocol.makeSession(),
            retryPolicy: retry ?? fastRetry
        )
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
    }

    override func tearDown() {
        StubURLProtocol.reset()
        super.tearDown()
    }

    func testAskDecodesResponse() async throws {
        StubURLProtocol.handler = { _ in
            .json(#"{"answer":"Hello","sources":[],"used_rag":true,"conversation_id":"c1","handoff":false}"#)
        }
        let ask = try await makeClient().ask(AskRequest(question: "hi", visitorID: "v123456789"))
        XCTAssertEqual(ask.answer, "Hello")
        XCTAssertEqual(ask.conversationID, "c1")
        XCTAssertTrue(ask.usedRAG)

        // Hit the documented path.
        XCTAssertEqual(StubURLProtocol.requests.last?.url?.path, "/api/v1/widget/wk_1/ask")
        XCTAssertEqual(StubURLProtocol.requests.last?.httpMethod, "POST")
    }

    func testConfirmAction() async throws {
        StubURLProtocol.handler = { _ in .json(#"{"status":"ok","message":"All set"}"#) }
        let result = try await makeClient().confirmAction(runID: "r1", request: ConfirmActionRequest(confirmToken: "tok", confirm: true))
        XCTAssertEqual(result.outcome, .ok)
        XCTAssertEqual(result.message, "All set")
        XCTAssertEqual(StubURLProtocol.requests.last?.url?.path, "/api/v1/widget/wk_1/actions/r1/confirm")
    }

    func testConfigBlockedSentinelThrows() async {
        StubURLProtocol.handler = { _ in .json(#"{"blocked":true,"detail":"domain_not_allowed"}"#) }
        await XCTAssertThrowsErrorAsync(try await self.makeClient().fetchConfig()) { error in
            XCTAssertEqual(error as? APIError, .blocked("domain_not_allowed"))
        }
    }

    func testWidgetNotFoundMapping() async {
        StubURLProtocol.handler = { _ in .json(#"{"detail":"widget_not_found"}"#, status: 404) }
        await XCTAssertThrowsErrorAsync(try await self.makeClient().fetchConfig()) { error in
            XCTAssertEqual(error as? APIError, .widgetNotFound)
        }
    }

    func testForbiddenMapping() async {
        StubURLProtocol.handler = { _ in .json(#"{"detail":"forbidden"}"#, status: 403) }
        await XCTAssertThrowsErrorAsync(
            try await self.makeClient().poll(conversationID: "c1", since: nil, visitorID: "v")
        ) { error in
            XCTAssertEqual(error as? APIError, .forbidden)
        }
    }

    func testRateLimitedMappingWithRetryAfter() async {
        // confirm uses retry:false, so 429 surfaces immediately.
        StubURLProtocol.handler = { _ in .json(#"{"detail":"rate_limited"}"#, status: 429, headers: ["Retry-After": "7"]) }
        await XCTAssertThrowsErrorAsync(
            try await self.makeClient().confirmAction(runID: "r", request: ConfirmActionRequest(confirmToken: "t", confirm: true))
        ) { error in
            XCTAssertEqual(error as? APIError, .rateLimited(retryAfter: 7))
        }
    }

    func testAskRetriesOnServerErrorThenSucceeds() async throws {
        let counter = Counter()
        StubURLProtocol.handler = { _ in
            let n = counter.increment()
            if n < 3 { return .json(#"{"detail":"boom"}"#, status: 500) }
            return .json(#"{"answer":"recovered","sources":[],"used_rag":false}"#)
        }
        let ask = try await makeClient().ask(AskRequest(question: "hi", visitorID: "v123456789"))
        XCTAssertEqual(ask.answer, "recovered")
        XCTAssertEqual(counter.value, 3, "two failures + one success")
    }

    func testAskGivesUpAfterMaxAttempts() async {
        let counter = Counter()
        StubURLProtocol.handler = { _ in _ = counter.increment(); return .json(#"{"detail":"boom"}"#, status: 500) }
        await XCTAssertThrowsErrorAsync(
            try await self.makeClient().ask(AskRequest(question: "hi", visitorID: "v123456789"))
        ) { error in
            XCTAssertEqual(error as? APIError, .http(status: 500, detail: "boom"))
        }
        XCTAssertEqual(counter.value, 3, "exactly maxAttempts tries")
    }

    func testSendMessageBuildsCorrectPath() async throws {
        StubURLProtocol.handler = { _ in
            .json(#"{"ok":true,"conversation_id":"c1","message_id":"m1","handoff":false,"bot_reply":{"id":"b1","body":"hi"}}"#)
        }
        let response = try await makeClient().sendMessage(conversationID: "c1", body: "hello", visitorID: "v1", attachmentIDs: ["a1"])
        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.botReply?.body, "hi")
        XCTAssertEqual(StubURLProtocol.requests.last?.url?.path, "/api/v1/widget/wk_1/conversations/c1/messages")
    }

    func testTypingReturnsState() async throws {
        StubURLProtocol.handler = { _ in .json(#"{"typing":{"agent":true,"visitor":false}}"#) }
        let state = try await makeClient().sendTyping(conversationID: "c1", isTyping: true, visitorID: "v1")
        XCTAssertTrue(state.agent)
        XCTAssertFalse(state.visitor)
    }

    func testMultipartBodyShape() {
        let data = WidgetAPIClient.multipartBody(
            boundary: "B", fieldName: "file", fileName: "shot.png", mimeType: "image/png", fileData: Data([0x1, 0x2])
        )
        let prefix = String(decoding: data.prefix(120), as: UTF8.self)
        XCTAssertTrue(prefix.contains("--B\r\n"))
        XCTAssertTrue(prefix.contains(#"Content-Disposition: form-data; name="file"; filename="shot.png""#))
        XCTAssertTrue(prefix.contains("Content-Type: image/png"))
        XCTAssertTrue(String(decoding: data.suffix(8), as: UTF8.self).contains("--B--"))
    }
}

/// Thread-safe counter for stub handlers.
final class Counter {
    private var count = 0
    private let lock = NSLock()
    @discardableResult func increment() -> Int { lock.lock(); defer { lock.unlock() }; count += 1; return count }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
