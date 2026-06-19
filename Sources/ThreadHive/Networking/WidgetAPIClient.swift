import Foundation

/// `URLSession`-backed `WidgetAPI` implementation. Thread-safe (stateless aside
/// from injected dependencies), cancellation-aware, no third-party deps.
public final class WidgetAPIClient: WidgetAPI {
    public let endpoints: WidgetEndpoints
    private let session: URLSession
    private let logger: ThreadHiveLogger?
    private let retryPolicy: RetryPolicy

    /// Plain coders — no key-conversion strategy, so the opaque snake_case keys
    /// inside `config`/`traits` blobs survive. DTOs map names via CodingKeys.
    static let decoder = JSONDecoder()
    static let encoder = JSONEncoder()

    public init(
        apiBaseURL: URL,
        widgetKey: String,
        session: URLSession = .shared,
        logger: ThreadHiveLogger? = nil,
        retryPolicy: RetryPolicy = .default
    ) {
        self.endpoints = WidgetEndpoints(apiBaseURL: apiBaseURL, widgetKey: widgetKey)
        self.session = session
        self.logger = logger
        self.retryPolicy = retryPolicy
    }

    // MARK: - Endpoints

    public func fetchConfig() async throws -> WidgetPublicConfig {
        guard let url = endpoints.url("config.json") else { throw APIError.invalidURL }
        let data = try await sendRaw(request(url, method: "GET"), retry: true)
        // Defensive: catch the domain-blocked sentinel before decoding the config.
        if let sentinel = try? Self.decoder.decode(BlockedSentinel.self, from: data), sentinel.blocked == true {
            throw APIError.blocked(sentinel.detail)
        }
        return try decode(WidgetPublicConfig.self, from: data)
    }

    public func ask(_ body: AskRequest) async throws -> AskResponse {
        guard let url = endpoints.url("ask") else { throw APIError.invalidURL }
        return try await send(request(url, method: "POST", json: try encode(body)), as: AskResponse.self, retry: true)
    }

    public func confirmAction(runID: String, request body: ConfirmActionRequest) async throws -> ConfirmActionResponse {
        guard let url = endpoints.url("actions/\(runID)/confirm") else { throw APIError.invalidURL }
        return try await send(request(url, method: "POST", json: try encode(body)), as: ConfirmActionResponse.self, retry: false)
    }

    public func poll(conversationID: String, since cursor: String?, visitorID: String?) async throws -> ConversationPoll {
        var query: [URLQueryItem] = []
        if let cursor { query.append(URLQueryItem(name: "since", value: cursor)) }
        if let visitorID { query.append(URLQueryItem(name: "visitor_id", value: visitorID)) }
        guard let url = endpoints.url("conversations/\(conversationID)/poll", query: query) else { throw APIError.invalidURL }
        // No retry: the poll loop re-fires on the next tick, so a transient
        // failure should be skipped rather than retried within the tick.
        return try await send(request(url, method: "GET"), as: ConversationPoll.self, retry: false)
    }

    public func listConversations(visitorID: String, limit: Int) async throws -> [ConversationSummary] {
        let query = [
            URLQueryItem(name: "visitor_id", value: visitorID),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = endpoints.url("conversations", query: query) else { throw APIError.invalidURL }
        let list = try await send(request(url, method: "GET"), as: ConversationList.self, retry: true)
        return list.items
    }

    public func sendMessage(conversationID: String, body: String, visitorID: String?, attachmentIDs: [String]) async throws -> SendMessageResponse {
        guard let url = endpoints.url("conversations/\(conversationID)/messages") else { throw APIError.invalidURL }
        var payload: [String: JSONValue] = ["body": .string(body)]
        if let visitorID { payload["visitor_id"] = .string(visitorID) }
        if !attachmentIDs.isEmpty { payload["attachment_ids"] = .array(attachmentIDs.map(JSONValue.string)) }
        return try await send(request(url, method: "POST", json: try encode(payload)), as: SendMessageResponse.self, retry: false)
    }

    public func uploadAttachment(conversationID: String, fileURL: URL, fileName: String?, mimeType: String?, visitorID: String) async throws -> MessageAttachment {
        let data: Data
        do { data = try Data(contentsOf: fileURL) }
        catch { throw APIError.transport("could not read file: \(error.localizedDescription)") }
        let name = fileName ?? fileURL.lastPathComponent
        let mime = mimeType ?? Self.mimeType(forExtension: fileURL.pathExtension)
        return try await uploadAttachment(conversationID: conversationID, data: data, fileName: name, mimeType: mime, visitorID: visitorID)
    }

    public func uploadAttachment(conversationID: String, data: Data, fileName: String, mimeType: String, visitorID: String) async throws -> MessageAttachment {
        let query = [URLQueryItem(name: "visitor_id", value: visitorID)]
        guard let url = endpoints.url("conversations/\(conversationID)/attachments", query: query) else { throw APIError.invalidURL }
        let boundary = "threadhive.\(UUID().uuidString)"
        var req = request(url, method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue(visitorID, forHTTPHeaderField: "x-threadhive-visitor-id")
        req.httpBody = Self.multipartBody(boundary: boundary, fieldName: "file", fileName: fileName, mimeType: mimeType, fileData: data)
        return try await send(req, as: MessageAttachment.self, retry: false)
    }

    @discardableResult
    public func sendTyping(conversationID: String, isTyping: Bool, visitorID: String?) async throws -> TypingState {
        guard let url = endpoints.url("conversations/\(conversationID)/typing") else { throw APIError.invalidURL }
        var payload: [String: JSONValue] = ["is_typing": .bool(isTyping)]
        if let visitorID { payload["visitor_id"] = .string(visitorID) }
        let env = try await send(request(url, method: "POST", json: try encode(payload)), as: TypingEnvelope.self, retry: false)
        return env.typing
    }

    @discardableResult
    public func identify(_ body: IdentifyRequest) async throws -> IdentifyResponse {
        guard let url = endpoints.url("identify") else { throw APIError.invalidURL }
        return try await send(request(url, method: "POST", json: try encode(body)), as: IdentifyResponse.self, retry: true)
    }

    @discardableResult
    public func track(_ body: TrackRequest) async throws -> TrackResponse {
        guard let url = endpoints.url("track") else { throw APIError.invalidURL }
        return try await send(request(url, method: "POST", json: try encode(body)), as: TrackResponse.self, retry: false)
    }

    @discardableResult
    public func submitCSAT(_ body: CSATRequest) async throws -> CSATResponse {
        guard let url = endpoints.url("csat") else { throw APIError.invalidURL }
        return try await send(request(url, method: "POST", json: try encode(body)), as: CSATResponse.self, retry: true)
    }

    @discardableResult
    public func markSeen(messageID: String, visitorID: String) async throws -> SeenResponse {
        guard let url = endpoints.unscopedURL("messages/\(messageID)/seen") else { throw APIError.invalidURL }
        var req = request(url, method: "POST", json: try encode(["visitor_id": JSONValue.string(visitorID)]))
        req.setValue(visitorID, forHTTPHeaderField: "x-threadhive-visitor-id")
        return try await send(req, as: SeenResponse.self, retry: false)
    }

    // MARK: - Request plumbing

    private func request(_ url: URL, method: String, json: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ThreadHive-iOS/\(ThreadHive.sdkVersion)", forHTTPHeaderField: "X-ThreadHive-SDK")
        if let json {
            req.httpBody = json
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return req
    }

    private func send<T: Decodable>(_ request: URLRequest, as type: T.Type, retry: Bool) async throws -> T {
        let data = try await sendRaw(request, retry: retry)
        return try decode(T.self, from: data)
    }

    private func sendRaw(_ request: URLRequest, retry: Bool) async throws -> Data {
        let policy = retry ? retryPolicy : .none
        var attempt = 0
        while true {
            attempt += 1
            try Task.checkCancellation()
            do {
                return try await performOnce(request)
            } catch let error as APIError {
                guard error.isRetryable, attempt < policy.maxAttempts else { throw error }
                let delay = backoffDelay(attempt: attempt, suggested: error.retryAfter, policy: policy)
                logger?.log(.debug, "retry \(attempt)/\(policy.maxAttempts) in \(String(format: "%.2f", delay))s — \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000))
            } catch is CancellationError {
                throw APIError.cancelled
            }
        }
    }

    private func performOnce(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            try Self.validate(response: response, data: data)
            return data
        } catch let error as APIError {
            throw error
        } catch let urlError as URLError {
            if urlError.code == .cancelled { throw APIError.cancelled }
            throw APIError.transport(urlError.localizedDescription)
        } catch is CancellationError {
            throw APIError.cancelled
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private func backoffDelay(attempt: Int, suggested: TimeInterval?, policy: RetryPolicy) -> TimeInterval {
        if let suggested { return min(suggested, policy.maxDelay) }
        let exp = policy.baseDelay * pow(policy.multiplier, Double(attempt - 1))
        let capped = min(exp, policy.maxDelay)
        return capped + Double.random(in: 0...(max(capped, 0.001) * 0.25))
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try Self.decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding(String(describing: error)) }
    }

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        do { return try Self.encoder.encode(value) }
        catch { throw APIError.decoding("encode failed: \(error)") }
    }

    static func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if (200..<300).contains(http.statusCode) { return }
        let detail = decodeDetail(data)
        switch http.statusCode {
        case 404 where detail == "widget_not_found":
            throw APIError.widgetNotFound
        case 403:
            throw APIError.forbidden
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
            throw APIError.rateLimited(retryAfter: retryAfter)
        default:
            throw APIError.http(status: http.statusCode, detail: detail)
        }
    }

    static func decodeDetail(_ data: Data) -> String? {
        struct Envelope: Decodable { let detail: String? }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.detail
    }

    static func multipartBody(boundary: String, fieldName: String, fileName: String, mimeType: String, fileData: Data) -> Data {
        var body = Data()
        func appendString(_ string: String) { body.append(Data(string.utf8)) }
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        body.append(fileData)
        appendString("\r\n--\(boundary)--\r\n")
        return body
    }

    static func mimeType(forExtension ext: String) -> String {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "pdf": return "application/pdf"
        default: return "application/octet-stream"
        }
    }
}

private struct BlockedSentinel: Decodable {
    let blocked: Bool?
    let detail: String?
}

private struct TypingEnvelope: Decodable {
    let typing: TypingState
}
