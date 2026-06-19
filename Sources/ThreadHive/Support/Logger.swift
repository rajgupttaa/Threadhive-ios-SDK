import Foundation

public enum ThreadHiveLogLevel: Int, Sendable, Comparable {
    case debug = 0, info, warning, error
    public static func < (lhs: ThreadHiveLogLevel, rhs: ThreadHiveLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Inject your own to route SDK diagnostics into your logging stack.
public protocol ThreadHiveLogger: AnyObject {
    func log(_ level: ThreadHiveLogLevel, _ message: String)
}

/// Default logger — prints at or above `minimumLevel`. Off by default (the SDK
/// passes `nil` unless the host opts in).
public final class ConsoleLogger: ThreadHiveLogger {
    public let minimumLevel: ThreadHiveLogLevel

    public init(minimumLevel: ThreadHiveLogLevel = .info) {
        self.minimumLevel = minimumLevel
    }

    public func log(_ level: ThreadHiveLogLevel, _ message: String) {
        guard level >= minimumLevel else { return }
        print("[ThreadHive] \(message)")
    }
}
