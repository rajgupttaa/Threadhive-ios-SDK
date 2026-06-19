import Foundation

/// Briefly caches the published widget config (non-secret) so re-opening the
/// chat doesn't re-fetch on every launch. TTL mirrors the backend's own short
/// cache window (`Cache-Control: max-age=15`).
final class ConfigCache {
    private let defaults: UserDefaults
    private let key: String
    private let ttl: TimeInterval
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults, widgetKey: String, ttl: TimeInterval = 30) {
        self.defaults = defaults
        self.key = "threadhive_config_\(widgetKey)"
        self.ttl = ttl
    }

    private struct Entry: Codable {
        let storedAt: Date
        let config: WidgetPublicConfig
    }

    func load() -> WidgetPublicConfig? {
        guard let data = defaults.data(forKey: key),
              let entry = try? decoder.decode(Entry.self, from: data) else { return nil }
        guard Date().timeIntervalSince(entry.storedAt) < ttl else { return nil }
        return entry.config
    }

    func store(_ config: WidgetPublicConfig) {
        let entry = Entry(storedAt: Date(), config: config)
        guard let data = try? encoder.encode(entry) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}
