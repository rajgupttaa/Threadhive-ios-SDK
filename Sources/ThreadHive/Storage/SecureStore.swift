import Foundation
import Security

/// Abstraction over secret persistence so the visitor id can be Keychain-backed
/// in production and swapped for an in-memory store in tests/previews.
public protocol SecureStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String) throws
    func removeValue(forKey key: String)
}

public enum KeychainError: Error, Equatable {
    case unhandled(OSStatus)
}

/// Keychain-backed `SecureStore` (`kSecClassGenericPassword`). Items use
/// `kSecAttrAccessibleAfterFirstUnlock` so the visitor id survives reboots and
/// is readable in the background (for poll/notification handling) but not before
/// first unlock.
public final class KeychainSecureStore: SecureStore {
    private let service: String
    private let accessGroup: String?
    private let lock = NSLock()

    public init(service: String = "io.threadhive.sdk", accessGroup: String? = nil) {
        self.service = service
        self.accessGroup = accessGroup
    }

    public func string(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else { return nil }
        return string
    }

    public func set(_ value: String, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        let data = Data(value.utf8)
        var query = baseQuery(key)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
        default:
            throw KeychainError.unhandled(status)
        }
    }

    public func removeValue(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        SecItemDelete(baseQuery(key) as CFDictionary)
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }
}

/// Volatile `SecureStore` — for unit tests, SwiftUI previews, and hosts that
/// explicitly want no persistence.
public final class InMemorySecureStore: SecureStore {
    private var storage: [String: String] = [:]
    private let lock = NSLock()

    public init() {}

    public func string(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }

    public func set(_ value: String, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = value
    }

    public func removeValue(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}
