import Foundation

/// APNs delivery environment for a registered device token. Debug builds get
/// sandbox-issued tokens that fail against the production APNs host, so the
/// default resolves from the build configuration.
public enum APNSEnvironment: String, Sendable {
    case production
    case sandbox

    /// `.sandbox` for Debug builds, `.production` otherwise.
    public static var automatic: APNSEnvironment {
        #if DEBUG
        return .sandbox
        #else
        return .production
        #endif
    }
}

/// `POST /devices` — register an APNs token so backgrounded agent replies reach
/// this install. `platform` is always `"ios"` here.
public struct DeviceRegisterRequest: Codable, Equatable, Sendable {
    public var visitorID: String
    public var platform: String
    public var token: String
    public var appBundleID: String?
    public var environment: String?

    enum CodingKeys: String, CodingKey {
        case visitorID = "visitor_id"
        case platform, token, environment
        case appBundleID = "app_bundle_id"
    }

    public init(
        visitorID: String,
        platform: String = "ios",
        token: String,
        appBundleID: String? = nil,
        environment: String? = nil
    ) {
        self.visitorID = visitorID
        self.platform = platform
        self.token = token
        self.appBundleID = appBundleID
        self.environment = environment
    }
}

/// `DELETE /devices` — drop this install's token (logout / invalidation). With
/// no `token`, the server drops every device for the visitor.
public struct DeviceUnregisterRequest: Codable, Equatable, Sendable {
    public var visitorID: String
    public var token: String?

    enum CodingKeys: String, CodingKey {
        case visitorID = "visitor_id"
        case token
    }

    public init(visitorID: String, token: String? = nil) {
        self.visitorID = visitorID
        self.token = token
    }
}

public struct DeviceResponse: Codable, Equatable, Sendable {
    public let ok: Bool
}

extension Data {
    /// Lowercase hex — the wire form of an APNs device token.
    var threadHiveHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
