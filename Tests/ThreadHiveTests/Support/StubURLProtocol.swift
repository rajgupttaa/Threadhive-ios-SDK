import Foundation

/// In-process HTTP stub. Register a handler that maps each request to a canned
/// response; install it on an ephemeral `URLSession` so client tests never touch
/// the network.
final class StubURLProtocol: URLProtocol {
    struct Response {
        var status: Int = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        var body: Data = Data()

        static func json(_ string: String, status: Int = 200, headers: [String: String] = [:]) -> Response {
            var h = ["Content-Type": "application/json"]
            headers.forEach { h[$0.key] = $0.value }
            return Response(status: status, headers: h, body: Data(string.utf8))
        }
    }

    static var handler: ((URLRequest) -> Response)?
    static private(set) var requests: [URLRequest] = []

    static func reset() {
        handler = nil
        requests = []
    }

    /// An ephemeral session that routes through this stub.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let stub = handler(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
