import Foundation

struct AgentProfileConfiguration: Codable, Equatable, Sendable {
    var enabled: Bool
    var name: String
    var proxyURL: String
    var noProxy: String
    var routeTrafficThroughProxy: Bool
    var countryCode: String
    var region: String
    var city: String
    var timezoneIdentifier: String
    var localeIdentifier: String
    var languages: String
    var acceptLanguage: String
    var latitude: Double
    var longitude: Double

    static let defaultValue = AgentProfileConfiguration(
        enabled: false,
        name: "default",
        proxyURL: "http://127.0.0.1:7890",
        noProxy: "localhost,127.0.0.1,::1",
        routeTrafficThroughProxy: false,
        countryCode: "US",
        region: "California",
        city: "San Francisco",
        timezoneIdentifier: "America/Los_Angeles",
        localeIdentifier: "en-US",
        languages: "en-US,en",
        acceptLanguage: "en-US,en;q=0.9",
        latitude: 37.7749,
        longitude: -122.4194
    )
}

enum AgentProfileEgressStatus: String, Codable, Sendable {
    case notTested
    case proxyDisabled
    case proxyInvalid
    case proxyUnavailable
    case sameAsDirect
    case routed
}

struct AgentProfileDiagnosticSnapshot: Codable, Equatable, Sendable {
    var checkedAt: Date
    var status: AgentProfileEgressStatus
    var directGoogleIP: String?
    var proxyGoogleIP: String?
    var detectedCountryCode: String?
    var detectedRegion: String?
    var detectedCity: String?
    var detectedTimezone: String?
    var details: String?

    static let empty = AgentProfileDiagnosticSnapshot(
        checkedAt: .distantPast,
        status: .notTested,
        directGoogleIP: nil,
        proxyGoogleIP: nil,
        detectedCountryCode: nil,
        detectedRegion: nil,
        detectedCity: nil,
        detectedTimezone: nil,
        details: nil
    )
}

struct AgentProfileGeneratedAssets: Sendable {
    let rootURL: URL
    let profileURL: URL
    let environmentURL: URL
    let launchersURL: URL
    let antigravityLauncherURL: URL
    let antigravityCLILauncherURL: URL
    let readmeURL: URL
}

enum AgentProfilePolicy {
    static func classifyEgress(
        routeTrafficThroughProxy: Bool,
        proxyURLIsValid: Bool,
        directIP: String?,
        proxyIP: String?
    ) -> AgentProfileEgressStatus {
        guard routeTrafficThroughProxy else { return .proxyDisabled }
        guard proxyURLIsValid else { return .proxyInvalid }
        guard let directIP, !directIP.isEmpty, let proxyIP, !proxyIP.isEmpty else {
            return .proxyUnavailable
        }
        return directIP == proxyIP ? .sameAsDirect : .routed
    }

    static func mayClaimProviderEligibility(from status: AgentProfileEgressStatus) -> Bool {
        // A provider can use account country, age, plan, organization policy,
        // payment profile, and server-side history. Local egress is never
        // sufficient evidence of eligibility.
        false
    }
}
