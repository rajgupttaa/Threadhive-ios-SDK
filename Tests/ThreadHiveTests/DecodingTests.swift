import XCTest
@testable import ThreadHive

/// Decodes the exact wire shapes the backend emits (see mobile-sdks/API_CONTRACT.md).
final class DecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testDecodeAskResponseFull() throws {
        let json = """
        {
          "answer": "You can cancel anytime in Settings.",
          "sources": [
            { "source_id": "s1", "source_name": "Docs / Billing", "score": 0.92, "chunk_url": "https://docs/x" },
            { "source_id": "s2", "source_name": "FAQ", "score": 0.5, "chunk_url": null }
          ],
          "used_rag": true,
          "conversation_id": "11111111-1111-1111-1111-111111111111",
          "handoff": false,
          "pending_actions": [
            { "run_id": "r1", "name": "cancel_sub", "label": "Cancel subscription", "confirm_token": "tok_abc" }
          ],
          "products": [
            { "id": "p1", "title": "Blue Widget", "price": "29.99", "currency": "USD",
              "image_url": "https://img", "url": "https://store/p/1", "in_stock": true,
              "source": "shopify", "add_to_cart_id": "v1" }
          ]
        }
        """
        let ask = try decoder.decode(AskResponse.self, from: Data(json.utf8))
        XCTAssertEqual(ask.answer, "You can cancel anytime in Settings.")
        XCTAssertEqual(ask.sources.count, 2)
        XCTAssertEqual(ask.sources[0].sourceName, "Docs / Billing")
        XCTAssertEqual(ask.sources[0].chunkURL, "https://docs/x")
        XCTAssertNil(ask.sources[1].chunkURL)
        XCTAssertTrue(ask.usedRAG)
        XCTAssertEqual(ask.conversationID, "11111111-1111-1111-1111-111111111111")
        XCTAssertFalse(ask.handoff)
        XCTAssertEqual(ask.pendingActions.first?.confirmToken, "tok_abc")
        XCTAssertEqual(ask.pendingActions.first?.id, ask.pendingActions.first?.runID)
        XCTAssertEqual(ask.products.first?.title, "Blue Widget")
        XCTAssertEqual(ask.products.first?.addToCartID, "v1")
        XCTAssertTrue(ask.products.first?.inStock == true)
    }

    func testDecodeAskResponseMinimal() throws {
        // Attachment-only / human-owned: empty answer, missing arrays default to [].
        let json = #"{ "answer": "", "sources": [], "used_rag": false, "conversation_id": "c1", "handoff": false }"#
        let ask = try decoder.decode(AskResponse.self, from: Data(json.utf8))
        XCTAssertEqual(ask.answer, "")
        XCTAssertTrue(ask.pendingActions.isEmpty)
        XCTAssertTrue(ask.products.isEmpty)
        XCTAssertEqual(ask.conversationID, "c1")
    }

    func testProductInStockDefaultsTrue() throws {
        let json = #"{ "id": "p1", "title": "X" }"#
        let product = try decoder.decode(Product.self, from: Data(json.utf8))
        XCTAssertTrue(product.inStock)
        XCTAssertNil(product.url)
    }

    func testDecodeConfirmOutcomeUnknownFallsBack() throws {
        let known = try decoder.decode(ConfirmActionResponse.self, from: Data(#"{"status":"ok","message":"Done"}"#.utf8))
        XCTAssertEqual(known.outcome, .ok)
        XCTAssertTrue(known.outcome.isSuccess)

        let novel = try decoder.decode(ConfirmActionResponse.self, from: Data(#"{"status":"warp_speed","message":"?"}"#.utf8))
        XCTAssertEqual(novel.outcome, .unknown)
        XCTAssertFalse(novel.outcome.isSuccess)
    }

    func testDecodeConfig() throws {
        let json = """
        {
          "workspace_name": "Acme",
          "workspace_subdomain": "acme",
          "widget_key": "wk_1",
          "config": { "brand_color": "#5b21b6", "bot": { "name": "Ada" } },
          "published_version": "v3",
          "published_at": "2026-01-02T03:04:05+00:00",
          "ai_available": true,
          "availability": null,
          "is_open": false,
          "team": [{ "name": "Mia", "initials": "M", "color": "from-orange-400 to-pink-500", "avatar_url": null }],
          "team_overflow": 2,
          "reply_time_label": "under 2 minutes"
        }
        """
        let config = try decoder.decode(WidgetPublicConfig.self, from: Data(json.utf8))
        XCTAssertEqual(config.workspaceName, "Acme")
        XCTAssertTrue(config.aiAvailable)
        XCTAssertFalse(config.isOpen)
        XCTAssertEqual(config.team.first?.name, "Mia")
        XCTAssertEqual(config.teamOverflow, 2)
        XCTAssertEqual(config.replyTimeLabel, "under 2 minutes")
        // Opaque config blob keeps raw snake_case keys.
        XCTAssertEqual(config.config?["brand_color"]?.stringValue, "#5b21b6")
        XCTAssertEqual(config.config?["bot"]?["name"]?.stringValue, "Ada")
    }

    func testDecodeConfigToleratesMissingDefaults() throws {
        // ai_available/is_open/team/team_overflow absent → safe defaults.
        let json = #"{ "workspace_name": "Acme", "widget_key": "wk_1", "config": null, "published_version": null, "published_at": null }"#
        let config = try decoder.decode(WidgetPublicConfig.self, from: Data(json.utf8))
        XCTAssertFalse(config.aiAvailable)
        XCTAssertTrue(config.isOpen)
        XCTAssertTrue(config.team.isEmpty)
        XCTAssertEqual(config.teamOverflow, 0)
    }

    func testDecodePoll() throws {
        let json = """
        {
          "conversation_id": "c1",
          "status": "open",
          "messages": [
            { "id": "m1", "author_kind": "agent", "author_name": "Mia", "author_avatar_url": "https://a",
              "body": "Hi there!", "sources": null, "created_at": "2026-06-19T10:00:00+00:00",
              "attachments": [{ "id": "a1", "name": "shot.png", "mime_type": "image/png", "size_bytes": 1024, "url": "/api/v1/widget/wk_1/conversations/c1/attachments/a1?visitor_id=v" }],
              "delivered_at": "2026-06-19T10:00:01+00:00", "read_at": null }
          ],
          "cursor": "2026-06-19T10:00:00+00:00",
          "typing": { "visitor": false, "agent": true },
          "assigned_agent": { "name": "Mia", "initials": "M", "color": "x", "avatar_url": null },
          "csat_score": null
        }
        """
        let poll = try decoder.decode(ConversationPoll.self, from: Data(json.utf8))
        XCTAssertEqual(poll.status, .open)
        XCTAssertEqual(poll.messages.count, 1)
        let message = poll.messages[0]
        XCTAssertEqual(message.authorKind, .agent)
        XCTAssertEqual(message.attachments.first?.mimeType, "image/png")
        XCTAssertTrue(message.attachments.first?.isImage == true)
        XCTAssertTrue(poll.typing.agent)
        XCTAssertEqual(poll.assignedAgent?.name, "Mia")
        XCTAssertEqual(poll.cursor, "2026-06-19T10:00:00+00:00")
    }

    func testUnknownAuthorKindDecodesToUnknown() throws {
        let json = #"{ "id": "m1", "author_kind": "martian", "author_name": "?", "body": "hi", "sources": null, "created_at": "t" }"#
        let message = try decoder.decode(WidgetMessage.self, from: Data(json.utf8))
        XCTAssertEqual(message.authorKind, .unknown)
        XCTAssertTrue(message.attachments.isEmpty)
    }

    func testDecodeConversationList() throws {
        let json = """
        { "items": [
          { "id": "c1", "status": "closed", "subject": "Billing", "last_message_preview": "Thanks!",
            "last_message_author": "agent", "last_message_at": "2026-06-18T09:00:00+00:00", "ai_handled": false, "unread": false }
        ] }
        """
        let list = try decoder.decode(ConversationList.self, from: Data(json.utf8))
        XCTAssertEqual(list.items.count, 1)
        XCTAssertEqual(list.items[0].status, .closed)
        XCTAssertEqual(list.items[0].lastMessageAuthor, .agent)
    }

    func testEncodeAskRequestOmitsNilsAndUsesSnakeCase() throws {
        let request = AskRequest(question: "hi", visitorID: "v123456789", attachmentIDs: nil)
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["question"] as? String, "hi")
        XCTAssertEqual(object?["visitor_id"] as? String, "v123456789")
        XCTAssertNil(object?["attachment_ids"], "nil attachment_ids must be omitted")
    }

    func testEncodeIdentifyRequestSnakeCase() throws {
        let request = IdentifyRequest(visitorID: "v123456789", userID: "u1", email: "a@b.com", userHash: "h")
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(object?["visitor_id"] as? String, "v123456789")
        XCTAssertEqual(object?["user_id"] as? String, "u1")
        XCTAssertEqual(object?["user_hash"] as? String, "h")
        XCTAssertNil(object?["phone"], "nil optionals omitted")
    }
}
