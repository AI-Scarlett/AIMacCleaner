import Foundation

struct RemoteHost: Codable, Identifiable, Sendable {
    var id: String
    var host: String
    var port: Int = 22
    var username: String
    var identityFile: String?
    var nickname: String?
    var fingerprint: String?
    var lastConnected: Date?
    var isOnline: Bool = false
    var sessionCount: Int = 0
}

struct RemoteSessionState: Codable, Identifiable, Sendable {
    var id: String
    var remoteHostId: String
    var localSessionId: String
    var connectedAt: Date
    var disconnectedAt: Date?
    var bridgePid: Int32?
    var tunnelActive: Bool = false
    var eventsForwarded: Int = 0

    var isActive: Bool { disconnectedAt == nil }
}

enum SecurityVerdict: String, Codable, Sendable {
    case safe = "safe"
    case suspicious = "suspicious"
    case dangerous = "dangerous"
    case unknown = "unknown"
}

struct AgentGuardAlert: Codable, Identifiable, Sendable {
    var id: String
    var remoteHostId: String
    var timestamp: Date
    var verdict: SecurityVerdict
    var message: String
    var detail: String?
    var dismissed: Bool = false
}

struct RemoteConfig: Codable, Sendable {
    var bridgePort: Int = 17894
    var bridgePath: String = "~/.agentguard/bin/agentguard-bridge"
    var autoConnectEnabled: Bool = false
    var keepAliveSeconds: Int = 30
    var maxReconnectAttempts: Int = 5
    var reconnectDelayMs: UInt64 = 2000
    var securityLevel: SecurityLevel = .standard
    var trustedHosts: [String] = []

    enum SecurityLevel: String, Codable, Sendable {
        case permissive = "permissive"
        case standard = "standard"
        case strict = "strict"
    }
}