import XCTest
@testable import ThreadHive

final class EndpointTests: XCTestCase {
    private func endpoints(_ base: String) -> WidgetEndpoints {
        WidgetEndpoints(apiBaseURL: URL(string: base)!, widgetKey: "wk_1")
    }

    func testKeyScopedURL() {
        let url = endpoints("https://app.example.com/api").url("ask")
        XCTAssertEqual(url?.absoluteString, "https://app.example.com/api/v1/widget/wk_1/ask")
    }

    func testURLWithQuery() {
        let url = endpoints("https://app.example.com/api").url(
            "conversations/c1/poll",
            query: [URLQueryItem(name: "since", value: "2026-06-19T10:00:00+00:00"), URLQueryItem(name: "visitor_id", value: "v1")]
        )
        let string = url!.absoluteString
        XCTAssertTrue(string.hasPrefix("https://app.example.com/api/v1/widget/wk_1/conversations/c1/poll?"))
        XCTAssertTrue(string.contains("visitor_id=v1"))
        XCTAssertTrue(string.contains("since="))
    }

    func testUnscopedURL() {
        let url = endpoints("https://app.example.com/api").unscopedURL("messages/m1/seen")
        XCTAssertEqual(url?.absoluteString, "https://app.example.com/api/v1/widget/messages/m1/seen")
    }

    func testTrailingSlashOnBaseIsNormalized() {
        let url = endpoints("https://app.example.com/api/").url("ask")
        XCTAssertEqual(url?.absoluteString, "https://app.example.com/api/v1/widget/wk_1/ask")
    }

    func testRootMountedBase() {
        let url = WidgetEndpoints(apiBaseURL: URL(string: "https://api.example.com")!, widgetKey: "wk_1").url("ask")
        XCTAssertEqual(url?.absoluteString, "https://api.example.com/v1/widget/wk_1/ask")
    }

    func testResolveRelativeAttachmentURL() {
        let resolved = endpoints("https://app.example.com/api")
            .resolveAttachmentURL("/api/v1/widget/wk_1/conversations/c1/attachments/a1?visitor_id=v")
        XCTAssertEqual(resolved?.absoluteString, "https://app.example.com/api/v1/widget/wk_1/conversations/c1/attachments/a1?visitor_id=v")
    }

    func testResolveAbsoluteAttachmentURLPassesThrough() {
        let resolved = endpoints("https://app.example.com/api").resolveAttachmentURL("https://cdn.example.com/x.png")
        XCTAssertEqual(resolved?.absoluteString, "https://cdn.example.com/x.png")
    }

    func testDevicesURL() {
        let url = endpoints("https://app.example.com/api").url("devices")
        XCTAssertEqual(url?.absoluteString, "https://app.example.com/api/v1/widget/wk_1/devices")
    }
}
