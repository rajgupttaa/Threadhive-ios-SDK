import Foundation

/// Errors surfaced by the `WidgetAPI`.
public enum APIError: Error, Equatable {
    /// The SDK has not been configured (`ThreadHive.configure(...)`).
    case notConfigured
    /// A URL could not be constructed from the base + path.
    case invalidURL
    /// Transport-level failure (no connectivity, TLS, timeout). Retryable.
    case transport(String)
    /// The request was cancelled (e.g. the view was dismissed).
    case cancelled
    /// Non-2xx response carrying an optional `{ "detail": "<code>" }`.
    case http(status: Int, detail: String?)
    /// 404 `widget_not_found`.
    case widgetNotFound
    /// 403 — the supplied `visitor_id` doesn't own this conversation.
    case forbidden
    /// 429 — back off and retry after `retryAfter` seconds when present.
    case rateLimited(retryAfter: TimeInterval?)
    /// The origin was blocked by the workspace domain allowlist (web only).
    case blocked(String?)
    /// Response body could not be decoded into the expected model.
    case decoding(String)

    /// Whether a retry with backoff is worthwhile.
    public var isRetryable: Bool {
        switch self {
        case .transport:
            return true
        case .rateLimited:
            return true
        case .http(let status, _):
            return status >= 500
        default:
            return false
        }
    }

    /// Server-suggested delay before the next attempt, if any.
    public var retryAfter: TimeInterval? {
        if case .rateLimited(let delay) = self { return delay }
        return nil
    }
}

extension APIError {
    public var localizedDescription: String {
        switch self {
        case .notConfigured: return "ThreadHive is not configured. Call ThreadHive.configure(...) first."
        case .invalidURL: return "Could not build a valid request URL."
        case .transport(let m): return "Network error: \(m)"
        case .cancelled: return "The request was cancelled."
        case .http(let status, let detail): return "HTTP \(status)\(detail.map { ": \($0)" } ?? "")"
        case .widgetNotFound: return "Widget not found — check the widget key."
        case .forbidden: return "Forbidden — this visitor doesn't own the conversation."
        case .rateLimited: return "Rate limited — please retry shortly."
        case .blocked(let d): return "Blocked: \(d ?? "domain not allowed")"
        case .decoding(let m): return "Could not decode the response: \(m)"
        }
    }
}
