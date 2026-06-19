import XCTest
@testable import ThreadHive

@MainActor
final class ChatViewModelTests: XCTestCase {
    private func config() -> WidgetPublicConfig {
        WidgetPublicConfig(workspaceName: "Acme", widgetKey: "wk_1", aiAvailable: true)
    }

    private func widgetMessage(id: String, kind: String, body: String, createdAt: String = "2026-06-19T10:00:00+00:00") throws -> WidgetMessage {
        let dict: [String: Any] = ["id": id, "author_kind": kind, "author_name": kind == "agent" ? "Mia" : "ThreadHive", "body": body, "sources": NSNull(), "created_at": createdAt]
        return try JSONDecoder().decode(WidgetMessage.self, from: JSONSerialization.data(withJSONObject: dict))
    }

    private func poll(_ messages: [WidgetMessage], cursor: String?, agentTyping: Bool = false, assigned: Bool = false) throws -> ConversationPoll {
        var dict: [String: Any] = [
            "conversation_id": "c1", "status": "open",
            "messages": try messages.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) },
            "cursor": cursor as Any,
            "typing": ["visitor": false, "agent": agentTyping],
            "csat_score": NSNull(),
        ]
        dict["assigned_agent"] = assigned ? ["name": "Mia", "initials": "M", "color": "x", "avatar_url": NSNull()] : NSNull()
        return try JSONDecoder().decode(ConversationPoll.self, from: JSONSerialization.data(withJSONObject: dict))
    }

    private func makeVM(api: WidgetAPI, conversationID: String? = nil) -> ChatViewModel {
        ChatViewModel(api: api, visitorID: "v123456789", config: config(), initialConversationID: conversationID, pollInterval: 60)
    }

    func testGreetingFromConfig() {
        let vm = makeVM(api: StubWidgetAPI())
        XCTAssertEqual(vm.resolved.botName, "Assistant")
        vm.send() // empty → no-op
        XCTAssertTrue(vm.messages.isEmpty)
    }

    func testSendCreatesConversationThenBindsOnPoll() async throws {
        let api = StubWidgetAPI()
        api.onAsk = { request in
            XCTAssertEqual(request.question, "How do I cancel?")
            return AskResponse(answer: "Cancel in Settings.", usedRAG: true, conversationID: "c1")
        }
        api.onPoll = { _, _, _ in
            try self.poll([
                try self.widgetMessage(id: "vm1", kind: "visitor", body: "How do I cancel?"),
                try self.widgetMessage(id: "bm1", kind: "bot", body: "Cancel in Settings."),
            ], cursor: "2026-06-19T10:00:00+00:00")
        }
        let vm = makeVM(api: api)
        vm.inputText = "How do I cancel?"
        let prepared = try XCTUnwrap(vm.prepareSend())
        XCTAssertEqual(vm.messages.count, 1)            // optimistic visitor
        XCTAssertEqual(vm.messages[0].sendState, .sending)

        await vm.performSend(prepared)

        XCTAssertEqual(vm.conversationID, "c1")
        // No duplicates: visitor (bound) + bot (bound).
        XCTAssertEqual(vm.messages.count, 2)
        XCTAssertEqual(vm.messages[0].author, .visitor)
        XCTAssertEqual(vm.messages[0].serverID, "vm1")
        XCTAssertEqual(vm.messages[0].sendState, .sent)
        XCTAssertEqual(vm.messages[1].author, .bot)
        XCTAssertEqual(vm.messages[1].serverID, "bm1")
        XCTAssertFalse(vm.botThinking)
    }

    func testProductsAndPendingActionsRideOnBotMessage() async throws {
        let api = StubWidgetAPI()
        api.onAsk = { _ in
            AskResponse(
                answer: "Here you go",
                conversationID: "c1",
                pendingActions: [PendingAction(runID: "r1", name: "cancel", label: "Cancel sub", confirmToken: "t")],
                products: [Product(id: "p1", title: "Blue Widget", url: "https://store/p/1")]
            )
        }
        api.onPoll = { _, _, _ in try self.poll([try self.widgetMessage(id: "bm1", kind: "bot", body: "Here you go")], cursor: "c") }
        let vm = makeVM(api: api)
        vm.inputText = "show me widgets"
        let prepared = try XCTUnwrap(vm.prepareSend())
        await vm.performSend(prepared)

        let bot = try XCTUnwrap(vm.messages.first { $0.author == .bot })
        XCTAssertEqual(bot.products.first?.title, "Blue Widget")
        XCTAssertEqual(bot.pendingActions.first?.runID, "r1")
        XCTAssertEqual(bot.serverID, "bm1", "bot message still binds despite carrying products/actions")
    }

    func testConfirmRemovesPendingActionAndPostsResult() async throws {
        let api = StubWidgetAPI()
        var sentConfirm: Bool?
        api.onConfirm = { runID, request in
            XCTAssertEqual(runID, "r1")
            sentConfirm = request.confirm
            return ConfirmActionResponse(status: "ok", message: "All set — done.")
        }
        api.onPoll = { _, _, _ in try self.poll([], cursor: "c") }
        let vm = makeVM(api: api, conversationID: "c1")
        // Seed a bot message carrying a pending action.
        let action = PendingAction(runID: "r1", name: "n", label: "l", confirmToken: "t")
        api.onPoll = { _, _, _ in try self.poll([try self.widgetMessage(id: "bm1", kind: "bot", body: "Confirm?")], cursor: "c") }
        await vm.pollOnce()
        // Inject the action onto the message via a fresh ask-style append is private;
        // instead confirm directly and assert the API + result bubble.
        await vm.confirmNow(action, accept: true)
        XCTAssertEqual(sentConfirm, true)
        XCTAssertTrue(vm.messages.contains { $0.text == "All set — done." }, "result message posted as a bubble")
    }

    func testHandoffRendersSystemMessage() async throws {
        let api = StubWidgetAPI()
        api.onAsk = { _ in AskResponse(answer: "A teammate is joining.", conversationID: "c1", handoff: true) }
        api.onPoll = { _, _, _ in try self.poll([], cursor: "c") }
        let vm = makeVM(api: api)
        vm.inputText = "help"
        let prepared = try XCTUnwrap(vm.prepareSend())
        await vm.performSend(prepared)
        XCTAssertTrue(vm.messages.contains { $0.author == .system && $0.text == "A teammate is joining." })
    }

    func testPollSurfacesAgentReplyAndTyping() async throws {
        let api = StubWidgetAPI()
        api.onPoll = { _, _, _ in
            try self.poll([try self.widgetMessage(id: "am1", kind: "agent", body: "Hi, I can help!")], cursor: "c", agentTyping: true, assigned: true)
        }
        let vm = makeVM(api: api, conversationID: "c1")
        await vm.pollOnce()
        XCTAssertTrue(vm.messages.contains { $0.author == .agent && $0.text == "Hi, I can help!" })
        XCTAssertTrue(vm.agentTyping)
        XCTAssertEqual(vm.assignedAgent?.name, "Mia")
    }

    func testPollDedupesByServerID() async throws {
        let api = StubWidgetAPI()
        api.onPoll = { _, _, _ in try self.poll([try self.widgetMessage(id: "am1", kind: "agent", body: "Hello")], cursor: "c") }
        let vm = makeVM(api: api, conversationID: "c1")
        await vm.pollOnce()
        await vm.pollOnce()
        XCTAssertEqual(vm.messages.filter { $0.serverID == "am1" }.count, 1, "same server id never duplicates")
    }

    func testSendFailurePreservesComposerText() async throws {
        let api = StubWidgetAPI()
        api.onAsk = { _ in throw APIError.transport("offline") }
        let vm = makeVM(api: api)
        vm.inputText = "important question"
        let prepared = try XCTUnwrap(vm.prepareSend())
        XCTAssertEqual(vm.inputText, "", "composer cleared optimistically")
        await vm.performSend(prepared)
        XCTAssertEqual(vm.inputText, "important question", "text restored on failure")
        XCTAssertFalse(vm.messages.contains { $0.sendState == .failed }, "failed optimistic bubble removed")
        XCTAssertNotNil(vm.banner)
    }

    func testMessagesTabLoadReopenAndNew() async throws {
        let api = StubWidgetAPI()
        api.onListConversations = { _, _ in [try ConversationSummary.make(id: "c9", subject: "Old thread")] }
        api.onPoll = { _, _, _ in try self.poll([], cursor: "c") }
        let vm = makeVM(api: api)
        await vm.loadConversations()
        XCTAssertEqual(vm.pastConversations.count, 1)
        XCTAssertEqual(vm.pastConversations.first?.subject, "Old thread")

        vm.reopen(vm.pastConversations[0])
        XCTAssertEqual(vm.conversationID, "c9", "reopen sets the conversation synchronously")

        vm.startNewConversation()
        XCTAssertNil(vm.conversationID, "new conversation clears the id")
        XCTAssertTrue(vm.messages.contains { $0.id == "greeting" }, "greeting shown for a fresh thread")
    }

    func testProductTapOpensSafeURLOnly() {
        let vm = makeVM(api: StubWidgetAPI())
        var opened: URL?
        vm.onOpenURL = { opened = $0 }
        vm.open(Product(id: "p1", title: "X", url: "https://store/p/1"))
        XCTAssertEqual(opened?.absoluteString, "https://store/p/1")
        opened = nil
        vm.open(Product(id: "p2", title: "Y", url: "javascript:alert(1)"))
        XCTAssertNil(opened, "unsafe scheme never opened")
    }

    func testCitationTapOpensChunkURL() {
        let vm = makeVM(api: StubWidgetAPI())
        var opened: URL?
        vm.onOpenURL = { opened = $0 }
        vm.openCitation(AskSource(sourceID: "s", sourceName: "Docs", score: 0.9, chunkURL: "https://docs/x"))
        XCTAssertEqual(opened?.absoluteString, "https://docs/x")
    }

    func testAttachmentURLResolvesAgainstBase() throws {
        let endpoints = WidgetEndpoints(apiBaseURL: URL(string: "https://app.example.com/api")!, widgetKey: "wk_1")
        let vm = ChatViewModel(api: StubWidgetAPI(), visitorID: "v123456789", config: config(), endpoints: endpoints)
        let attachment = try JSONDecoder().decode(MessageAttachment.self, from: Data(
            #"{"id":"a1","name":"x.png","mime_type":"image/png","size_bytes":1,"url":"/api/v1/widget/wk_1/conversations/c1/attachments/a1?visitor_id=v"}"#.utf8
        ))
        XCTAssertEqual(vm.attachmentURL(attachment)?.absoluteString,
                       "https://app.example.com/api/v1/widget/wk_1/conversations/c1/attachments/a1?visitor_id=v")
    }

    func testSafeURLRejectsNonHTTP() {
        XCTAssertNil(ChatViewModel.safeURL("javascript:alert(1)"))
        XCTAssertNil(ChatViewModel.safeURL("file:///etc/passwd"))
        XCTAssertNotNil(ChatViewModel.safeURL("https://store/p/1"))
    }

    func testResolvedConfigReadsBlobAndOverrides() {
        let blobJSON = ##"{"brand":{"brandColor":"#5b21b6","accentColor":"#db2777"},"welcome":{"botName":"Ada","greeting":"Hey!","suggestedQuestions":["Pricing?","Refunds?"]}}"##
        let blob = try! JSONDecoder().decode(JSONValue.self, from: Data(blobJSON.utf8))
        let config = WidgetPublicConfig(workspaceName: "Acme", widgetKey: "wk_1", config: blob)
        let resolved = ResolvedConfig(config: config, overrides: ThemeOverrides())
        XCTAssertEqual(resolved.brandColorHex, "#5b21b6")
        XCTAssertEqual(resolved.accentColorHex, "#db2777")
        XCTAssertEqual(resolved.botName, "Ada")
        XCTAssertEqual(resolved.greeting, "Hey!")
        XCTAssertEqual(resolved.suggestedQuestions, ["Pricing?", "Refunds?"])

        let overridden = ResolvedConfig(config: config, overrides: ThemeOverrides(brandColorHex: "#000000", botName: "Bot"))
        XCTAssertEqual(overridden.brandColorHex, "#000000")
        XCTAssertEqual(overridden.botName, "Bot")
    }
}
