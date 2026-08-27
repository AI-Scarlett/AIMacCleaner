import Foundation

enum NetworkTrafficCaptureMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case safeSockets
    case rawPackets

    var id: String { rawValue }
}

enum NetworkTrafficProtocol: String, CaseIterable, Codable, Sendable, Identifiable {
    case all = "ALL"
    case tcp = "TCP"
    case udp = "UDP"
    case icmp = "ICMP"
    case arp = "ARP"
    case other = "OTHER"

    var id: String { rawValue }
}

enum NetworkTrafficCaptureState: Equatable, Sendable {
    case idle
    case starting
    case running
    case importing
    case failed(String)

    var isActive: Bool {
        switch self {
        case .starting, .running, .importing:
            true
        case .idle, .failed:
            false
        }
    }
}

struct NetworkTrafficInterface: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let name: String
    let description: String?
    let isLoopback: Bool
    let isUp: Bool
}

struct NetworkTrafficEndpoint: Codable, Hashable, Sendable {
    let host: String
    let port: UInt16?

    var displayText: String {
        guard let port else { return host }
        if host.contains(":") && !host.hasPrefix("[") {
            return "[\(host)]:\(port)"
        }
        return "\(host):\(port)"
    }
}

struct NetworkTrafficConnection: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var protocolKind: NetworkTrafficProtocol
    var local: NetworkTrafficEndpoint
    var remote: NetworkTrafficEndpoint
    var interfaceName: String?
    var processName: String?
    var serviceName: String?
    var state: String?
    var receivedBytes: UInt64
    var sentBytes: UInt64
    var packetCount: UInt64
    var firstSeen: Date
    var lastSeen: Date
    var isFavorite: Bool
    var isBlacklisted: Bool

    var totalBytes: UInt64 { receivedBytes + sentBytes }
}

struct NetworkTrafficRatePoint: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let receivedBytesPerSecond: UInt64
    let sentBytesPerSecond: UInt64

    init(
        id: UUID = UUID(),
        date: Date,
        receivedBytesPerSecond: UInt64,
        sentBytesPerSecond: UInt64
    ) {
        self.id = id
        self.date = date
        self.receivedBytesPerSecond = receivedBytesPerSecond
        self.sentBytesPerSecond = sentBytesPerSecond
    }
}

struct NetworkTrafficAlert: Identifiable, Equatable, Sendable {
    let id: UUID
    let date: Date
    let host: String
    let message: String

    init(id: UUID = UUID(), date: Date = Date(), host: String, message: String) {
        self.id = id
        self.date = date
        self.host = host
        self.message = message
    }
}

struct NetworkTrafficRawFrame: Equatable, Sendable {
    let timestampSeconds: Int64
    let timestampMicroseconds: Int32
    let originalLength: UInt32
    let data: Data
    let linkType: Int32
}

struct NetworkTrafficDecodedPacket: Equatable, Sendable {
    let protocolKind: NetworkTrafficProtocol
    let source: NetworkTrafficEndpoint
    let destination: NetworkTrafficEndpoint
    let serviceName: String?
    let capturedLength: UInt32
}

struct NetworkTrafficSocketSample: Equatable, Sendable {
    let protocolKind: NetworkTrafficProtocol
    let local: NetworkTrafficEndpoint
    let remote: NetworkTrafficEndpoint
    let interfaceName: String?
    let processName: String?
    let state: String?
    let receivedBytes: UInt64
    let sentBytes: UInt64
}

enum NetworkTrafficFormatter {
    static func bytes(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    static func speed(_ bytesPerSecond: UInt64) -> String {
        "\(bytes(bytesPerSecond))/s"
    }
}

enum NetworkTrafficLimits {
    static let maximumConnections = 500
    static let maximumHistoryPoints = 120
    static let maximumAlerts = 100
    static let maximumRawFrames = 10_000
    static let maximumRawBytes = 32 * 1_024 * 1_024
    static let maximumBlacklistEntries = 10_000
}

enum NetworkTrafficServiceCatalog {
    private static let services: [UInt16: String] = [
        20: "FTP data", 21: "FTP", 22: "SSH", 23: "Telnet", 25: "SMTP",
        53: "DNS", 67: "DHCP", 68: "DHCP", 80: "HTTP", 110: "POP3",
        123: "NTP", 143: "IMAP", 161: "SNMP", 389: "LDAP", 443: "HTTPS",
        445: "SMB", 465: "SMTPS", 514: "Syslog", 587: "SMTP submission",
        631: "IPP", 853: "DNS over TLS", 993: "IMAPS", 995: "POP3S",
        1900: "SSDP", 3306: "MySQL", 3389: "RDP", 5432: "PostgreSQL",
        5353: "mDNS", 6379: "Redis", 8080: "HTTP alternate", 8443: "HTTPS alternate"
    ]

    static func name(sourcePort: UInt16?, destinationPort: UInt16?) -> String? {
        if let destinationPort, let value = services[destinationPort] { return value }
        if let sourcePort, let value = services[sourcePort] { return value }
        return nil
    }
}

enum NetworkTrafficHostClassifier {
    static func isLocal(_ host: String) -> Bool {
        let lowercased = host.lowercased()
        if lowercased == "localhost" || lowercased == "::1" || lowercased.hasPrefix("127.") {
            return true
        }
        if lowercased.hasPrefix("10.") || lowercased.hasPrefix("192.168.") || lowercased.hasPrefix("169.254.") {
            return true
        }
        if lowercased.hasPrefix("172."),
           let second = Int(lowercased.split(separator: ".").dropFirst().first ?? ""),
           (16...31).contains(second) {
            return true
        }
        return lowercased.hasPrefix("fc") || lowercased.hasPrefix("fd") || lowercased.hasPrefix("fe80:")
    }
}
