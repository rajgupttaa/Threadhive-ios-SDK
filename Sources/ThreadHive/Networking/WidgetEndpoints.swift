import Foundation

/// Builds request URLs for the widget API under `{apiBaseURL}/v1/widget/...`,
/// and resolves relative attachment URLs against the API base origin.
public struct WidgetEndpoints: Sendable {
    public let apiBaseURL: URL
    public let widgetKey: String

    public init(apiBaseURL: URL, widgetKey: String) {
        self.apiBaseURL = apiBaseURL
        self.widgetKey = widgetKey
    }

    /// `{apiBaseURL}/v1/widget/{key}/{suffix}` with query items.
    func url(_ suffix: String, query: [URLQueryItem] = []) -> URL? {
        widgetURL(path: "/v1/widget/\(widgetKey)/\(suffix)", query: query)
    }

    /// A widget path NOT scoped by key (e.g. `/v1/widget/messages/{id}/seen`).
    func unscopedURL(_ suffix: String, query: [URLQueryItem] = []) -> URL? {
        widgetURL(path: "/v1/widget/\(suffix)", query: query)
    }

    private func widgetURL(path: String, query: [URLQueryItem]) -> URL? {
        // Append `path` after the base's own path (e.g. `/api`). We build the
        // string explicitly so a base of `https://host/api` yields
        // `https://host/api/v1/widget/...` rather than dropping `/api`.
        var components = URLComponents(url: apiBaseURL, resolvingAgainstBaseURL: false)
        let basePath = (components?.path ?? "").trimmingTrailingSlash
        components?.path = basePath + path
        if !query.isEmpty { components?.queryItems = query }
        return components?.url
    }

    /// Resolve a `/poll` attachment URL (a `/api`-prefixed absolute path, or a
    /// fully-qualified URL) against the API base origin.
    ///
    /// An absolute-path reference (`/api/v1/...`) replaces the whole path of the
    /// base, so this correctly produces `origin + /api/v1/...`.
    public func resolveAttachmentURL(_ raw: String) -> URL? {
        if let absolute = URL(string: raw), absolute.scheme != nil { return absolute }
        return URL(string: raw, relativeTo: apiBaseURL)?.absoluteURL
    }
}

private extension String {
    var trimmingTrailingSlash: String {
        hasSuffix("/") ? String(dropLast()) : self
    }
}
