import Foundation

/// Exponential-backoff policy for retryable requests (`/ask`, `/config.json`).
public struct RetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var baseDelay: TimeInterval
    public var multiplier: Double
    public var maxDelay: TimeInterval

    public init(maxAttempts: Int, baseDelay: TimeInterval, multiplier: Double, maxDelay: TimeInterval) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.multiplier = multiplier
        self.maxDelay = maxDelay
    }

    /// 3 attempts, 0.5s → 1s → 2s (+jitter), capped at 8s.
    public static let `default` = RetryPolicy(maxAttempts: 3, baseDelay: 0.5, multiplier: 2, maxDelay: 8)

    /// No retry — a single attempt (used for polling/typing fire-and-forget).
    public static let none = RetryPolicy(maxAttempts: 1, baseDelay: 0, multiplier: 1, maxDelay: 0)
}
