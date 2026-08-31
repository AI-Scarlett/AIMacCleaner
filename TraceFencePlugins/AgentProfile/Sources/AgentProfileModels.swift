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
    var accuracyMeters: Double
    var locationOverrideEnabled: Bool
    var timezoneOverrideEnabled: Bool
    var languageOverrideEnabled: Bool
    var acceptLanguageOverrideEnabled: Bool
    var cliWrappersEnabled: Bool
    var desktopLaunchersEnabled: Bool
    var browserExtensionEnabled: Bool

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
        longitude: -122.4194,
        accuracyMeters: 80,
        locationOverrideEnabled: true,
        timezoneOverrideEnabled: true,
        languageOverrideEnabled: true,
        acceptLanguageOverrideEnabled: true,
        cliWrappersEnabled: true,
        desktopLaunchersEnabled: true,
        browserExtensionEnabled: true
    )
}

extension AgentProfileConfiguration {
    private enum CodingKeys: String, CodingKey {
        case enabled, name, proxyURL, noProxy, routeTrafficThroughProxy
        case countryCode, region, city, timezoneIdentifier, localeIdentifier
        case languages, acceptLanguage, latitude, longitude, accuracyMeters
        case locationOverrideEnabled, timezoneOverrideEnabled, languageOverrideEnabled
        case acceptLanguageOverrideEnabled, cliWrappersEnabled, desktopLaunchersEnabled
        case browserExtensionEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Self.defaultValue
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? fallback.enabled
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? fallback.name
        proxyURL = try container.decodeIfPresent(String.self, forKey: .proxyURL) ?? fallback.proxyURL
        noProxy = try container.decodeIfPresent(String.self, forKey: .noProxy) ?? fallback.noProxy
        routeTrafficThroughProxy = try container.decodeIfPresent(Bool.self, forKey: .routeTrafficThroughProxy) ?? fallback.routeTrafficThroughProxy
        countryCode = try container.decodeIfPresent(String.self, forKey: .countryCode) ?? fallback.countryCode
        region = try container.decodeIfPresent(String.self, forKey: .region) ?? fallback.region
        city = try container.decodeIfPresent(String.self, forKey: .city) ?? fallback.city
        timezoneIdentifier = try container.decodeIfPresent(String.self, forKey: .timezoneIdentifier) ?? fallback.timezoneIdentifier
        localeIdentifier = try container.decodeIfPresent(String.self, forKey: .localeIdentifier) ?? fallback.localeIdentifier
        languages = try container.decodeIfPresent(String.self, forKey: .languages) ?? fallback.languages
        acceptLanguage = try container.decodeIfPresent(String.self, forKey: .acceptLanguage) ?? fallback.acceptLanguage
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude) ?? fallback.latitude
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude) ?? fallback.longitude
        accuracyMeters = try container.decodeIfPresent(Double.self, forKey: .accuracyMeters) ?? fallback.accuracyMeters
        locationOverrideEnabled = try container.decodeIfPresent(Bool.self, forKey: .locationOverrideEnabled) ?? fallback.locationOverrideEnabled
        timezoneOverrideEnabled = try container.decodeIfPresent(Bool.self, forKey: .timezoneOverrideEnabled) ?? fallback.timezoneOverrideEnabled
        languageOverrideEnabled = try container.decodeIfPresent(Bool.self, forKey: .languageOverrideEnabled) ?? fallback.languageOverrideEnabled
        acceptLanguageOverrideEnabled = try container.decodeIfPresent(Bool.self, forKey: .acceptLanguageOverrideEnabled) ?? fallback.acceptLanguageOverrideEnabled
        cliWrappersEnabled = try container.decodeIfPresent(Bool.self, forKey: .cliWrappersEnabled) ?? fallback.cliWrappersEnabled
        desktopLaunchersEnabled = try container.decodeIfPresent(Bool.self, forKey: .desktopLaunchersEnabled) ?? fallback.desktopLaunchersEnabled
        browserExtensionEnabled = try container.decodeIfPresent(Bool.self, forKey: .browserExtensionEnabled) ?? fallback.browserExtensionEnabled
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(name, forKey: .name)
        try container.encode(proxyURL, forKey: .proxyURL)
        try container.encode(noProxy, forKey: .noProxy)
        try container.encode(routeTrafficThroughProxy, forKey: .routeTrafficThroughProxy)
        try container.encode(countryCode, forKey: .countryCode)
        try container.encode(region, forKey: .region)
        try container.encode(city, forKey: .city)
        try container.encode(timezoneIdentifier, forKey: .timezoneIdentifier)
        try container.encode(localeIdentifier, forKey: .localeIdentifier)
        try container.encode(languages, forKey: .languages)
        try container.encode(acceptLanguage, forKey: .acceptLanguage)
        try container.encode(latitude, forKey: .latitude)
        try container.encode(longitude, forKey: .longitude)
        try container.encode(accuracyMeters, forKey: .accuracyMeters)
        try container.encode(locationOverrideEnabled, forKey: .locationOverrideEnabled)
        try container.encode(timezoneOverrideEnabled, forKey: .timezoneOverrideEnabled)
        try container.encode(languageOverrideEnabled, forKey: .languageOverrideEnabled)
        try container.encode(acceptLanguageOverrideEnabled, forKey: .acceptLanguageOverrideEnabled)
        try container.encode(cliWrappersEnabled, forKey: .cliWrappersEnabled)
        try container.encode(desktopLaunchersEnabled, forKey: .desktopLaunchersEnabled)
        try container.encode(browserExtensionEnabled, forKey: .browserExtensionEnabled)
    }
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
    var localTunnelDetected: Bool? = nil

    static let empty = AgentProfileDiagnosticSnapshot(
        checkedAt: .distantPast,
        status: .notTested,
        directGoogleIP: nil,
        proxyGoogleIP: nil,
        detectedCountryCode: nil,
        detectedRegion: nil,
        detectedCity: nil,
        detectedTimezone: nil,
        details: nil,
        localTunnelDetected: nil
    )
}

struct AgentProfileGeneratedAssets: Sendable {
    let rootURL: URL
    let profileURL: URL
    let contextURL: URL
    let environmentURL: URL
    let binURL: URL
    let launchersURL: URL
    let browserExtensionURL: URL
    let shellLauncherURL: URL
    let antigravityLauncherURL: URL
    let antigravityCLILauncherURL: URL
    let readmeURL: URL
}

enum AgentProfilePolicy {
    static func classifyEgress(
        routeTrafficThroughProxy: Bool,
        proxyURLIsValid: Bool,
        directIP: String?,
        proxyIP: String?,
        localTunnelDetected: Bool = false
    ) -> AgentProfileEgressStatus {
        guard routeTrafficThroughProxy else { return .proxyDisabled }
        guard proxyURLIsValid else { return .proxyInvalid }
        guard let directIP, !directIP.isEmpty, let proxyIP, !proxyIP.isEmpty else {
            return .proxyUnavailable
        }
        if directIP == proxyIP {
            // A URLSession with proxy settings disabled still traverses a
            // packet-tunnel/TUN route. Equal egress in that state means the
            // default path is already tunneled, not that the physical egress
            // leaked around the explicit proxy.
            return localTunnelDetected ? .routed : .sameAsDirect
        }
        return .routed
    }

    static func mayClaimProviderEligibility(from status: AgentProfileEgressStatus) -> Bool {
        // A provider can use account country, age, plan, organization policy,
        // payment profile, and server-side history. Local egress is never
        // sufficient evidence of eligibility.
        false
    }
}
