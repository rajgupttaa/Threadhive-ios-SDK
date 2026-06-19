import Foundation
import ThreadHive

// A dependency-free smoke runner exercising the SDK's PUBLIC surface so it can
// be verified without a full Xcode install. The internal units (VisitorStore,
// UnreadTracker, ConfigCache, WidgetSession) are covered indirectly here via the
// public facade/client, and directly by the XCTest suite (which uses @testable).
// Exit code is non-zero on failure.

final class Box { var failures = 0 }
let box = Box()
func check(_ condition: Bool, _ message: String) {
    if condition { return }
    box.failures += 1
    print("  ✗ FAIL: \(message)")
}
func checkEqual<T: Equatable>(_ a: T, _ b: T, _ message: String) {
    check(a == b, "\(message) — got \(a), expected \(b)")
}
func section(_ name: String) { print("• \(name)") }

let decoder = JSONDecoder()

// MARK: Decoding

section("Decoding")
do {
    let askJSON = """
    {"answer":"Hi","sources":[{"source_id":"s","source_name":"Docs","score":0.9,"chunk_url":"https://x"}],
     "used_rag":true,"conversation_id":"c1","handoff":false,
     "pending_actions":[{"run_id":"r","name":"n","label":"l","confirm_token":"t"}],
     "products":[{"id":"p","title":"T","price":"9.99","currency":"USD","in_stock":true,"add_to_cart_id":"v1"}]}
    """
    let ask = try decoder.decode(AskResponse.self, from: Data(askJSON.utf8))
    checkEqual(ask.answer, "Hi", "ask.answer")
    checkEqual(ask.sources.first?.sourceName ?? "", "Docs", "ask.sources[0].sourceName")
    checkEqual(ask.pendingActions.first?.confirmToken ?? "", "t", "ask.pendingActions[0].confirmToken")
    checkEqual(ask.products.first?.addToCartID ?? "", "v1", "ask.products[0].addToCartID")
    check(ask.products.first?.inStock == true, "product.inStock")

    let minimal = try decoder.decode(AskResponse.self, from: Data(#"{"answer":"","sources":[],"used_rag":false}"#.utf8))
    check(minimal.pendingActions.isEmpty && minimal.products.isEmpty, "missing arrays default to empty")

    let confirm = try decoder.decode(ConfirmActionResponse.self, from: Data(#"{"status":"warp","message":"?"}"#.utf8))
    checkEqual(confirm.outcome, .unknown, "unknown confirm status → .unknown")
    let okConfirm = try decoder.decode(ConfirmActionResponse.self, from: Data(#"{"status":"ok","message":"x"}"#.utf8))
    check(okConfirm.outcome.isSuccess, "ok confirm isSuccess")

    let configJSON = """
    {"workspace_name":"Acme","workspace_subdomain":"acme","widget_key":"wk_1",
     "config":{"brand_color":"#5b21b6"},"published_version":null,"published_at":null,
     "ai_available":true,"is_open":false,
     "team":[{"name":"Mia","initials":"M","color":"x","avatar_url":null}],"team_overflow":2,"reply_time_label":"fast"}
    """
    let config = try decoder.decode(WidgetPublicConfig.self, from: Data(configJSON.utf8))
    check(config.aiAvailable && !config.isOpen, "config flags")
    checkEqual(config.config?["brand_color"]?.stringValue ?? "", "#5b21b6", "opaque config snake_case key preserved")
    checkEqual(config.teamOverflow, 2, "team_overflow")

    let pollJSON = """
    {"conversation_id":"c1","status":"open",
     "messages":[{"id":"m1","author_kind":"agent","author_name":"Mia","author_avatar_url":null,
       "body":"hi","sources":null,"created_at":"t",
       "attachments":[{"id":"a","name":"x.png","mime_type":"image/png","size_bytes":1,"url":"/api/v1/x"}]}],
     "cursor":"t","typing":{"visitor":false,"agent":true},"assigned_agent":null,"csat_score":null}
    """
    let poll = try decoder.decode(ConversationPoll.self, from: Data(pollJSON.utf8))
    checkEqual(poll.status, .open, "poll.status")
    check(poll.typing.agent, "poll.typing.agent")
    check(poll.messages.first?.attachments.first?.isImage == true, "attachment.isImage")

    let unknownKind = try decoder.decode(WidgetMessage.self, from: Data(#"{"id":"m","author_kind":"alien","author_name":"?","body":"b","sources":null,"created_at":"t"}"#.utf8))
    checkEqual(unknownKind.authorKind, .unknown, "unknown author_kind → .unknown")

    let req = AskRequest(question: "hi", visitorID: "v123456789", attachmentIDs: nil)
    let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any]
    checkEqual(obj?["visitor_id"] as? String ?? "", "v123456789", "encode visitor_id snake_case")
    check(obj?["attachment_ids"] == nil, "nil attachment_ids omitted")
} catch {
    box.failures += 1
    print("  ✗ decoding threw: \(error)")
}

// MARK: Attachment URL resolution (public)

section("Attachment URLs")
do {
    let ep = WidgetEndpoints(apiBaseURL: URL(string: "https://app.example.com/api")!, widgetKey: "wk_1")
    checkEqual(
        ep.resolveAttachmentURL("/api/v1/widget/wk_1/conversations/c1/attachments/a1?visitor_id=v")?.absoluteString ?? "",
        "https://app.example.com/api/v1/widget/wk_1/conversations/c1/attachments/a1?visitor_id=v",
        "resolve relative attachment url against base origin"
    )
    checkEqual(ep.resolveAttachmentURL("https://cdn/x.png")?.absoluteString ?? "", "https://cdn/x.png", "absolute attachment url passes through")
}

// MARK: ChatViewModel (pure logic)

section("ChatViewModel logic")
do {
    check(ChatViewModel.safeURL("javascript:alert(1)") == nil, "safeURL rejects javascript:")
    check(ChatViewModel.safeURL("file:///etc/passwd") == nil, "safeURL rejects file:")
    check(ChatViewModel.safeURL("https://store/p/1") != nil, "safeURL allows https")

    let blob = try decoder.decode(JSONValue.self, from: Data(##"{"brand":{"brandColor":"#5b21b6"},"welcome":{"botName":"Ada","greeting":"Hey!","suggestedQuestions":["A","B"]}}"##.utf8))
    let config = WidgetPublicConfig(workspaceName: "Acme", widgetKey: "wk_1", config: blob)
    let resolved = ResolvedConfig(config: config, overrides: ThemeOverrides(botName: "Override"))
    checkEqual(resolved.brandColorHex, "#5b21b6", "resolved brand color from blob")
    checkEqual(resolved.botName, "Override", "override beats blob botName")
    checkEqual(resolved.suggestedQuestions, ["A", "B"], "suggested questions parsed")
} catch {
    box.failures += 1
    print("  ✗ ChatViewModel logic threw: \(error)")
}

// MARK: Stub HTTP

final class SmokeStub: URLProtocol {
    static var handler: ((URLRequest) -> (Int, [String: String], Data))?
    static var requests: [URLRequest] = []
    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [SmokeStub.self]
        return URLSession(configuration: c)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests.append(request)
        let (status, headers, body) = Self.handler?(request) ?? (500, [:], Data())
        var h = ["Content-Type": "application/json"]; headers.forEach { h[$0.key] = $0.value }
        let resp = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: h)!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class AtomicInt {
    private var n = 0; private let lock = NSLock()
    @discardableResult func inc() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

@MainActor
func runAsyncChecks() async {
    section("Networking client")
    let fast = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2, maxDelay: 0.05)
    let client = WidgetAPIClient(apiBaseURL: URL(string: "https://app.example.com/api")!, widgetKey: "wk_1", session: SmokeStub.session(), retryPolicy: fast)

    SmokeStub.requests = []
    SmokeStub.handler = { _ in (200, [:], Data(#"{"answer":"Hello","sources":[],"used_rag":true,"conversation_id":"c1","handoff":false}"#.utf8)) }
    do {
        let ask = try await client.ask(AskRequest(question: "hi", visitorID: "v123456789"))
        checkEqual(ask.answer, "Hello", "ask via client decodes")
        checkEqual(SmokeStub.requests.last?.url?.path ?? "", "/api/v1/widget/wk_1/ask", "ask hits the documented path (verifies internal URL building)")
        checkEqual(SmokeStub.requests.last?.httpMethod ?? "", "POST", "ask is a POST")
    } catch { box.failures += 1; print("  ✗ ask threw: \(error)") }

    SmokeStub.handler = { _ in (404, [:], Data(#"{"detail":"widget_not_found"}"#.utf8)) }
    do { _ = try await client.fetchConfig(); box.failures += 1; print("  ✗ expected widgetNotFound") }
    catch { checkEqual(error as? APIError, APIError.widgetNotFound, "404 → widgetNotFound") }

    SmokeStub.handler = { _ in (429, ["Retry-After": "7"], Data(#"{"detail":"rate_limited"}"#.utf8)) }
    do { _ = try await client.confirmAction(runID: "r", request: ConfirmActionRequest(confirmToken: "t", confirm: true)); box.failures += 1; print("  ✗ expected rateLimited") }
    catch { checkEqual(error as? APIError, APIError.rateLimited(retryAfter: 7), "429 → rateLimited(7)") }

    let counter = AtomicInt()
    SmokeStub.handler = { _ in
        counter.inc() < 3 ? (500, [:], Data(#"{"detail":"boom"}"#.utf8)) : (200, [:], Data(#"{"answer":"recovered","sources":[],"used_rag":false}"#.utf8))
    }
    do {
        let ask = try await client.ask(AskRequest(question: "hi", visitorID: "v123456789"))
        checkEqual(ask.answer, "recovered", "ask retries then succeeds")
        checkEqual(counter.value, 3, "retried twice before success")
    } catch { box.failures += 1; print("  ✗ retry threw: \(error)") }

    // MARK: ChatViewModel polling (end-to-end via the real client + stub HTTP)
    section("ChatViewModel polling")
    let vmClient = WidgetAPIClient(apiBaseURL: URL(string: "https://app.example.com/api")!, widgetKey: "wk_1", session: SmokeStub.session(), retryPolicy: fast)
    SmokeStub.handler = { req in
        if req.url?.path.hasSuffix("/poll") == true {
            return (200, [:], Data("""
            {"conversation_id":"c1","status":"open",
             "messages":[{"id":"am1","author_kind":"agent","author_name":"Mia","author_avatar_url":null,"body":"Hi, I can help!","sources":null,"created_at":"2026-06-19T10:00:00+00:00","attachments":[]}],
             "cursor":"2026-06-19T10:00:00+00:00","typing":{"visitor":false,"agent":true},"assigned_agent":{"name":"Mia","initials":"M","color":"x","avatar_url":null},"csat_score":null}
            """.utf8))
        }
        return (200, [:], Data("{}".utf8))
    }
    let vm = ChatViewModel(api: vmClient, visitorID: "v123456789", config: WidgetPublicConfig(workspaceName: "Acme", widgetKey: "wk_1"), initialConversationID: "c1", pollInterval: 60)
    await vm.pollOnce()
    checkEqual(vm.messages.count, 1, "poll surfaces the agent message")
    check(vm.messages.first?.author == .agent, "message author is agent")
    check(vm.agentTyping, "agent typing reflected from poll")
    checkEqual(vm.assignedAgent?.name ?? "", "Mia", "assigned agent surfaced")
    await vm.pollOnce()
    checkEqual(vm.messages.count, 1, "duplicate server id not re-appended")

    // MARK: Facade (visitor persistence + unread, with a stubbed session)
    section("Facade")
    ThreadHive.configure(ThreadHiveConfiguration(
        widgetKey: "wk_1",
        apiBaseURL: URL(string: "https://app.example.com/api")!,
        urlSession: SmokeStub.session(),
        secureStore: InMemorySecureStore()
    ))
    check(ThreadHive.isConfigured, "configured")
    let v1 = ThreadHive.visitorID
    check(v1 != nil, "visitor id minted")
    checkEqual(ThreadHive.visitorID, v1, "visitor id stable")

    SmokeStub.handler = { _ in
        (200, [:], Data("""
        {"items":[
          {"id":"c1","status":"open","subject":"s","last_message_preview":"p","last_message_author":"agent","last_message_at":"2026-06-19T10:00:00+00:00","ai_handled":false,"unread":false},
          {"id":"c2","status":"open","subject":"s","last_message_preview":"p","last_message_author":"visitor","last_message_at":"2026-06-19T10:00:00+00:00","ai_handled":false,"unread":false}
        ]}
        """.utf8))
    }
    let unread = await ThreadHive.unreadCount()
    checkEqual(unread, 1, "unreadCount = 1 (agent thread, not our own) — exercises UnreadTracker via the facade")

    ThreadHive.logout()
    check(ThreadHive.visitorID != v1, "logout mints a fresh visitor")
}

await runAsyncChecks()

print("")
if box.failures == 0 {
    print("✅ ALL SMOKE CHECKS PASSED")
    exit(0)
} else {
    print("❌ \(box.failures) SMOKE CHECK(S) FAILED")
    exit(1)
}
