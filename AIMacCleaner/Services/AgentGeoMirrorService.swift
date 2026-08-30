import Foundation
import Network

struct AgentGeoMirrorProfile: Codable {
    var name: String
    var enabled: Bool
    var proxyURL: String
    var noProxy: String
    var routeTrafficThroughProxy: Bool
    var countryCode: String
    var region: String
    var city: String
    var timezoneIdentifier: String
    var localeIdentifier: String
    var languages: [String]
    var acceptLanguage: String
    var latitude: Double
    var longitude: Double
    var accuracyMeters: Double
    var locationOverrideEnabled: Bool
    var timezoneOverrideEnabled: Bool
    var languageOverrideEnabled: Bool
    var acceptLanguageOverrideEnabled: Bool
    var browserExtensionEnabled: Bool
    var cliWrappersEnabled: Bool
    var desktopLaunchersEnabled: Bool
    var updatedAt: Date

    static let defaultProfile = AgentGeoMirrorProfile(
        name: "default",
        enabled: false,
        proxyURL: "http://127.0.0.1:7890",
        noProxy: "localhost,127.0.0.1,::1",
        routeTrafficThroughProxy: false,
        countryCode: "US",
        region: "California",
        city: "San Francisco",
        timezoneIdentifier: "America/Los_Angeles",
        localeIdentifier: "en-US",
        languages: ["en-US", "en"],
        acceptLanguage: "en-US,en;q=0.9",
        latitude: 37.7749,
        longitude: -122.4194,
        accuracyMeters: 80,
        locationOverrideEnabled: true,
        timezoneOverrideEnabled: true,
        languageOverrideEnabled: true,
        acceptLanguageOverrideEnabled: true,
        browserExtensionEnabled: true,
        cliWrappersEnabled: true,
        desktopLaunchersEnabled: true,
        updatedAt: Date()
    )
}

struct AgentGeoMirrorDetectedProfile {
    let countryCode: String
    let region: String
    let city: String
    let timezoneIdentifier: String
    let localeIdentifier: String
    let languages: [String]
    let acceptLanguage: String
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
}

struct AgentGeoMirrorGeneratedAssets {
    let rootURL: URL
    let rawProfileURL: URL
    let portableProfileURL: URL
    let profileContextURL: URL
    let profileLinksURL: URL
    let envScriptURL: URL
    let binURL: URL
    let launchersURL: URL
    let browserExtensionURL: URL
    let readmeURL: URL
}

enum AgentGeoMirrorProfileAccess {
    static let host = "127.0.0.1"
    static let port: UInt16 = 17777
    static var origin: String { "http://\(host):\(port)" }

    static func profileID(_ rawName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return name.isEmpty ? "default" : name
    }

    static func profileURL(profileName: String) -> String {
        "\(origin)/profiles/\(profileID(profileName))/agent-profile.json"
    }

    static func contextURL(profileName: String) -> String {
        "\(origin)/profiles/\(profileID(profileName))/agent-profile.md"
    }

    static func rawProfileURL(profileName: String) -> String {
        "\(origin)/profiles/\(profileID(profileName))/raw-profile.json"
    }
}

private struct AgentGeoMirrorCLITool {
    let wrapperName: String
    let commandName: String
    let displayName: String
}

private struct AgentGeoMirrorPortableProfile: Codable {
    struct Location: Codable {
        let countryCode: String
        let region: String
        let city: String
        let latitude: Double
        let longitude: Double
        let accuracyMeters: Double
    }

    struct Proxy: Codable {
        let url: String
        let noProxy: String
        let routesAgentTraffic: Bool
    }

    let schema: String
    let generatedAt: Date
    let enabled: Bool
    let profileName: String
    let profileURL: String
    let contextURL: String
    let rawProfileURL: String
    let timezoneIdentifier: String
    let localeIdentifier: String
    let posixLocale: String
    let languages: [String]
    let acceptLanguage: String
    let location: Location
    let proxy: Proxy
    let environment: [String: String]
    let instructions: [String]
}

enum AgentGeoMirrorServiceError: LocalizedError {
    case directOnly
    case invalidProxyURL
    case proxyEgressMatchesDirect
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .directOnly:
            return "Agent Geo Mirror is only available in the direct TraceFence build."
        case .invalidProxyURL:
            return "Proxy URL must include a host and port, for example http://127.0.0.1:7890."
        case .proxyEgressMatchesDirect:
            return "The configured proxy exposes the same public IP to Google as a direct connection. Change the proxy route or Clash mode before enabling Agent traffic routing."
        case .refreshFailed:
            return "Unable to detect the proxy exit profile from the configured proxy."
        }
    }
}

final class AgentGeoMirrorService {
    static let shared = AgentGeoMirrorService()

    private let coreOverridesMigrationKey = "agentGeoMirrorCoreOverridesMigrated20260708"
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private init() {}

    func profileFromDefaults(enabledOverride: Bool? = nil) -> AgentGeoMirrorProfile {
        let defaults = UserDefaults.standard
        let fallback = AgentGeoMirrorProfile.defaultProfile
        let effectiveEnabled = enabledOverride ?? defaultsBool("agentGeoMirrorEnabled", fallback: fallback.enabled)
        if effectiveEnabled && defaults.object(forKey: coreOverridesMigrationKey) == nil {
            forceCoreOverridesInDefaults(defaults)
            defaults.set(true, forKey: coreOverridesMigrationKey)
        }
        let languages = defaults.string(forKey: "agentGeoMirrorLanguages")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? fallback.languages

        return AgentGeoMirrorProfile(
            name: defaults.string(forKey: "agentGeoMirrorProfileName") ?? fallback.name,
            enabled: effectiveEnabled,
            proxyURL: defaults.string(forKey: "agentGeoMirrorProxyURL") ?? fallback.proxyURL,
            noProxy: defaults.string(forKey: "agentGeoMirrorNoProxy") ?? fallback.noProxy,
            routeTrafficThroughProxy: defaultsBool(
                "agentGeoMirrorRouteTrafficThroughProxy",
                fallback: fallback.routeTrafficThroughProxy
            ),
            countryCode: defaults.string(forKey: "agentGeoMirrorCountryCode") ?? fallback.countryCode,
            region: defaults.string(forKey: "agentGeoMirrorRegion") ?? fallback.region,
            city: defaults.string(forKey: "agentGeoMirrorCity") ?? fallback.city,
            timezoneIdentifier: defaults.string(forKey: "agentGeoMirrorTimezone") ?? fallback.timezoneIdentifier,
            localeIdentifier: defaults.string(forKey: "agentGeoMirrorLocale") ?? fallback.localeIdentifier,
            languages: languages.isEmpty ? fallback.languages : languages,
            acceptLanguage: defaults.string(forKey: "agentGeoMirrorAcceptLanguage") ?? fallback.acceptLanguage,
            latitude: defaultsDouble("agentGeoMirrorLatitude", fallback: fallback.latitude),
            longitude: defaultsDouble("agentGeoMirrorLongitude", fallback: fallback.longitude),
            accuracyMeters: defaultsDouble("agentGeoMirrorAccuracy", fallback: fallback.accuracyMeters),
            locationOverrideEnabled: defaultsBool("agentGeoMirrorLocationOverride", fallback: fallback.locationOverrideEnabled),
            timezoneOverrideEnabled: defaultsBool("agentGeoMirrorTimezoneOverride", fallback: fallback.timezoneOverrideEnabled),
            languageOverrideEnabled: defaultsBool("agentGeoMirrorLanguageOverride", fallback: fallback.languageOverrideEnabled),
            acceptLanguageOverrideEnabled: defaultsBool("agentGeoMirrorAcceptLanguageOverride", fallback: fallback.acceptLanguageOverrideEnabled),
            browserExtensionEnabled: defaultsBool("agentGeoMirrorBrowserExtension", fallback: fallback.browserExtensionEnabled),
            cliWrappersEnabled: defaultsBool("agentGeoMirrorCLIWrappers", fallback: fallback.cliWrappersEnabled),
            desktopLaunchersEnabled: defaultsBool("agentGeoMirrorDesktopLaunchers", fallback: fallback.desktopLaunchersEnabled),
            updatedAt: Date()
        )
    }

    func setEnabledFromDefaults(_ isEnabled: Bool) throws -> AgentGeoMirrorGeneratedAssets {
        let defaults = UserDefaults.standard
        defaults.set(isEnabled, forKey: "agentGeoMirrorEnabled")
        if isEnabled {
            forceCoreOverridesInDefaults(defaults)
            defaults.set(true, forKey: coreOverridesMigrationKey)
        }
        return try generateAssets(for: profileFromDefaults(enabledOverride: isEnabled))
    }

    func refreshEnabledProfileInBackground() {
        guard SandboxPaths.isDirectDistribution else {
            return
        }

        let defaults = UserDefaults.standard
        let isEnabled = defaultsBool("agentGeoMirrorEnabled", fallback: AgentGeoMirrorProfile.defaultProfile.enabled)
        let profileName = defaults.string(forKey: "agentGeoMirrorProfileName") ?? AgentGeoMirrorProfile.defaultProfile.name
        let assets = generatedAssets(forProfileName: profileName)
        guard isEnabled || fileManager.fileExists(atPath: assets.rootURL.path) else {
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            do {
                _ = try self.generateAssets(for: self.profileFromDefaults(enabledOverride: isEnabled))
            } catch {
                print("[TraceFence] Failed to refresh Agent Geo Mirror profile: \(error)")
            }
        }
    }

    func generatedAssets(forProfileName profileName: String) -> AgentGeoMirrorGeneratedAssets {
        let rootURL = URL(fileURLWithPath: SandboxPaths.shared.dataDirectory)
            .appendingPathComponent("AgentGeoMirror", isDirectory: true)
            .appendingPathComponent(safeFileName(profileName), isDirectory: true)
        return AgentGeoMirrorGeneratedAssets(
            rootURL: rootURL,
            rawProfileURL: rootURL.appendingPathComponent("profile.json"),
            portableProfileURL: rootURL.appendingPathComponent("agent-profile.json"),
            profileContextURL: rootURL.appendingPathComponent("agent-profile.md"),
            profileLinksURL: rootURL.appendingPathComponent("profile-url.txt"),
            envScriptURL: rootURL.appendingPathComponent("agent-env.sh"),
            binURL: rootURL.appendingPathComponent("bin", isDirectory: true),
            launchersURL: rootURL.appendingPathComponent("Launchers", isDirectory: true),
            browserExtensionURL: rootURL.appendingPathComponent("BrowserExtension", isDirectory: true),
            readmeURL: rootURL.appendingPathComponent("README.md")
        )
    }

    func generateAssets(for profile: AgentGeoMirrorProfile) throws -> AgentGeoMirrorGeneratedAssets {
        guard SandboxPaths.isDirectDistribution else {
            throw AgentGeoMirrorServiceError.directOnly
        }

        let assets = generatedAssets(forProfileName: profile.name)
        let rootURL = assets.rootURL
        let binURL = assets.binURL
        let launchersURL = assets.launchersURL
        let extensionURL = assets.browserExtensionURL
        let shellURL = rootURL.appendingPathComponent("ShellProfile", isDirectory: true)

        try createDirectory(rootURL)
        try createDirectory(binURL)
        try createDirectory(launchersURL)
        try createDirectory(extensionURL)
        try createDirectory(shellURL)

        let refreshedProfile = profile.withUpdatedTimestamp()
        try writeProfileJSON(refreshedProfile, to: assets.rawProfileURL)
        try writePortableProfileFiles(refreshedProfile, rootURL: rootURL, assets: assets)

        try writeExecutable(envScript(for: refreshedProfile, rootURL: rootURL, binURL: binURL, shellURL: shellURL), to: assets.envScriptURL)
        try writeLocalProbeShims(to: binURL)
        try writeShellStartupFiles(rootURL: rootURL, shellURL: shellURL)

        if refreshedProfile.cliWrappersEnabled {
            try writeCLIWrappers(rootURL: rootURL, binURL: binURL, launchersURL: launchersURL)
        }
        try syncManagedCommandShims(rootURL: rootURL, enabled: refreshedProfile.enabled && refreshedProfile.cliWrappersEnabled)
        if refreshedProfile.desktopLaunchersEnabled {
            try writeDesktopLaunchers(for: refreshedProfile, rootURL: rootURL, launchersURL: launchersURL)
        }
        if refreshedProfile.browserExtensionEnabled {
            try writeBrowserExtension(for: refreshedProfile, extensionURL: extensionURL)
        }

        try readme(for: refreshedProfile).write(to: assets.readmeURL, atomically: true, encoding: .utf8)
        AgentGeoMirrorProfileServer.shared.setProfile(profileName: refreshedProfile.name, enabled: refreshedProfile.enabled)

        return AgentGeoMirrorGeneratedAssets(
            rootURL: rootURL,
            rawProfileURL: assets.rawProfileURL,
            portableProfileURL: assets.portableProfileURL,
            profileContextURL: assets.profileContextURL,
            profileLinksURL: assets.profileLinksURL,
            envScriptURL: assets.envScriptURL,
            binURL: binURL,
            launchersURL: launchersURL,
            browserExtensionURL: extensionURL,
            readmeURL: assets.readmeURL
        )
    }

    func refreshProfileThroughProxy(_ profile: AgentGeoMirrorProfile) async throws -> AgentGeoMirrorDetectedProfile {
        guard SandboxPaths.isDirectDistribution else {
            throw AgentGeoMirrorServiceError.directOnly
        }
        guard let session = makeSession(proxyURLString: profile.proxyURL) else {
            throw AgentGeoMirrorServiceError.invalidProxyURL
        }

        try await verifyGoogleEgressIsProxied(proxySession: session)

        let endpoints = [
            URL(string: "https://ipapi.co/json/")!,
            URL(string: "https://ipwho.is/")!
        ]

        for endpoint in endpoints {
            do {
                let (data, response) = try await session.data(from: endpoint)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    continue
                }
                if endpoint.host?.contains("ipapi.co") == true,
                   let detected = try decodeIPAPI(data) {
                    return detected
                }
                if endpoint.host?.contains("ipwho.is") == true,
                   let detected = try decodeIPWhoIs(data) {
                    return detected
                }
            } catch {
                continue
            }
        }

        throw AgentGeoMirrorServiceError.refreshFailed
    }

    private func makeSession(proxyURLString: String) -> URLSession? {
        guard let proxyURL = URL(string: proxyURLString),
              let host = proxyURL.host,
              let port = proxyURL.port else {
            return nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15

        switch proxyURL.scheme?.lowercased() {
        case "http", "https":
            configuration.connectionProxyDictionary = [
                "HTTPEnable": 1,
                "HTTPProxy": host,
                "HTTPPort": port,
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": port
            ]
        default:
            return nil
        }

        return URLSession(configuration: configuration)
    }

    private func verifyGoogleEgressIsProxied(proxySession: URLSession) async throws {
        guard let checkURL = URL(string: "https://domains.google.com/checkip") else { return }
        let directConfiguration = URLSessionConfiguration.ephemeral
        directConfiguration.timeoutIntervalForRequest = 8
        directConfiguration.timeoutIntervalForResource = 10
        let directSession = URLSession(configuration: directConfiguration)

        async let directValue = publicIPText(from: checkURL, session: directSession)
        async let proxiedValue = publicIPText(from: checkURL, session: proxySession)
        let (directIP, proxiedIP) = try await (directValue, proxiedValue)
        guard !directIP.isEmpty, !proxiedIP.isEmpty else {
            throw AgentGeoMirrorServiceError.refreshFailed
        }
        guard directIP != proxiedIP else {
            throw AgentGeoMirrorServiceError.proxyEgressMatchesDirect
        }
    }

    private func publicIPText(from url: URL, session: URLSession) async throws -> String {
        let (data, response) = try await session.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw AgentGeoMirrorServiceError.refreshFailed
        }
        return value
    }

    private func decodeIPAPI(_ data: Data) throws -> AgentGeoMirrorDetectedProfile? {
        let response = try JSONDecoder().decode(IPAPIResponse.self, from: data)
        guard let countryCode = response.countryCode,
              let timezone = response.timezone,
              let latitude = response.latitude,
              let longitude = response.longitude else {
            return nil
        }
        let locale = localeBundle(countryCode: countryCode, timezone: timezone)
        return AgentGeoMirrorDetectedProfile(
            countryCode: countryCode.uppercased(),
            region: response.region ?? "",
            city: response.city ?? "",
            timezoneIdentifier: timezone,
            localeIdentifier: locale.localeIdentifier,
            languages: locale.languages,
            acceptLanguage: locale.acceptLanguage,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: 80
        )
    }

    private func decodeIPWhoIs(_ data: Data) throws -> AgentGeoMirrorDetectedProfile? {
        let response = try JSONDecoder().decode(IPWhoIsResponse.self, from: data)
        guard response.success != false,
              let countryCode = response.countryCode,
              let timezone = response.timezone?.id,
              let latitude = response.latitude,
              let longitude = response.longitude else {
            return nil
        }
        let locale = localeBundle(countryCode: countryCode, timezone: timezone)
        return AgentGeoMirrorDetectedProfile(
            countryCode: countryCode.uppercased(),
            region: response.region ?? "",
            city: response.city ?? "",
            timezoneIdentifier: timezone,
            localeIdentifier: locale.localeIdentifier,
            languages: locale.languages,
            acceptLanguage: locale.acceptLanguage,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: 80
        )
    }

    private func writeProfileJSON(_ profile: AgentGeoMirrorProfile, to url: URL) throws {
        let data = try encoder.encode(profile)
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func writePortableProfileFiles(_ profile: AgentGeoMirrorProfile, rootURL: URL, assets: AgentGeoMirrorGeneratedAssets) throws {
        let profileURL = AgentGeoMirrorProfileAccess.profileURL(profileName: profile.name)
        let contextURL = AgentGeoMirrorProfileAccess.contextURL(profileName: profile.name)
        let rawProfileURL = AgentGeoMirrorProfileAccess.rawProfileURL(profileName: profile.name)
        let portable = portableProfile(for: profile, rootURL: rootURL, profileURL: profileURL, contextURL: contextURL, rawProfileURL: rawProfileURL)
        let portableData = try encoder.encode(portable)
        try portableData.write(to: assets.portableProfileURL, options: .atomic)
        try profileContextMarkdown(for: profile, profileURL: profileURL, contextURL: contextURL)
            .write(to: assets.profileContextURL, atomically: true, encoding: .utf8)
        try """
        TRACEFENCE_PROFILE_URL=\(profileURL)
        TRACEFENCE_PROFILE_CONTEXT_URL=\(contextURL)
        TRACEFENCE_RAW_PROFILE_URL=\(rawProfileURL)
        TRACEFENCE_PROFILE_PATH=\(assets.portableProfileURL.path)
        TRACEFENCE_PROFILE_CONTEXT_PATH=\(assets.profileContextURL.path)
        TRACEFENCE_RAW_PROFILE_PATH=\(assets.rawProfileURL.path)
        """.write(to: assets.profileLinksURL, atomically: true, encoding: .utf8)
        for url in [assets.portableProfileURL, assets.profileContextURL, assets.profileLinksURL] {
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    private func portableProfile(
        for profile: AgentGeoMirrorProfile,
        rootURL: URL,
        profileURL: String,
        contextURL: String,
        rawProfileURL: String
    ) -> AgentGeoMirrorPortableProfile {
        let localeIdentifier = profile.localeIdentifier.isEmpty ? "en-US" : profile.localeIdentifier
        let localeUnderscore = localeIdentifier.replacingOccurrences(of: "-", with: "_")
        let posixLocale = localeUnderscore + ".UTF-8"
        let normalizedLanguages = profile.languages.isEmpty ? [localeIdentifier] : profile.languages
        let noProxy = normalizedNoProxy(profile.noProxy)

        return AgentGeoMirrorPortableProfile(
            schema: "tracefence.agent-profile.v1",
            generatedAt: profile.updatedAt,
            enabled: profile.enabled,
            profileName: profile.name,
            profileURL: profileURL,
            contextURL: contextURL,
            rawProfileURL: rawProfileURL,
            timezoneIdentifier: profile.timezoneIdentifier,
            localeIdentifier: localeIdentifier,
            posixLocale: posixLocale,
            languages: normalizedLanguages,
            acceptLanguage: profile.acceptLanguage,
            location: AgentGeoMirrorPortableProfile.Location(
                countryCode: profile.countryCode.uppercased(),
                region: profile.region,
                city: profile.city,
                latitude: profile.latitude,
                longitude: profile.longitude,
                accuracyMeters: profile.accuracyMeters
            ),
            proxy: AgentGeoMirrorPortableProfile.Proxy(
                url: redactedProxyURL(profile.proxyURL),
                noProxy: noProxy,
                routesAgentTraffic: profile.routeTrafficThroughProxy
            ),
            environment: [
                "TRACEFENCE": profile.enabled ? "1" : "0",
                "TRACEFENCE_PROFILE_URL": profileURL,
                "TRACEFENCE_PROFILE_CONTEXT_URL": contextURL,
                "TRACEFENCE_PROFILE_PATH": rootURL.appendingPathComponent("agent-profile.json").path,
                "TRACEFENCE_PROFILE_CONTEXT_PATH": rootURL.appendingPathComponent("agent-profile.md").path,
                "TRACEFENCE_TIMEZONE": profile.timezoneIdentifier,
                "TRACEFENCE_LOCALE": localeIdentifier,
                "TRACEFENCE_POSIX_LOCALE": posixLocale,
                "TRACEFENCE_LANGUAGES": normalizedLanguages.joined(separator: ","),
                "TRACEFENCE_ACCEPT_LANGUAGE": profile.acceptLanguage
            ],
            instructions: [
                "This profile is generated by TraceFence on the local Mac.",
                "When TRACEFENCE=1, prefer these timezone, locale, language, Accept-Language, location, and proxy values over macOS global settings for agent-facing behavior.",
                "Use TRACEFENCE_PROFILE_URL or TRACEFENCE_PROFILE_CONTEXT_URL when a new agent supports reading a profile from a local URL.",
                "Use TRACEFENCE_PROFILE_PATH or TRACEFENCE_PROFILE_CONTEXT_PATH when a new agent supports reading a local profile file.",
                "Do not treat this profile as proof that macOS global language, region, or timezone changed."
            ]
        )
    }

    private func profileContextMarkdown(for profile: AgentGeoMirrorProfile, profileURL: String, contextURL: String) -> String {
        let localeIdentifier = profile.localeIdentifier.isEmpty ? "en-US" : profile.localeIdentifier
        let normalizedLanguages = profile.languages.isEmpty ? [localeIdentifier] : profile.languages
        let state = profile.enabled ? "enabled" : "disabled"
        return """
        # TraceFence Agent Profile

        TraceFence generated this local profile for agent-facing environment alignment. The current profile is **\(state)**.

        ## Active values

        - Profile name: \(profile.name)
        - Timezone: \(profile.timezoneIdentifier)
        - Locale: \(localeIdentifier)
        - Languages: \(normalizedLanguages.joined(separator: ", "))
        - Accept-Language: \(profile.acceptLanguage)
        - Country: \(profile.countryCode.uppercased())
        - Region: \(profile.region)
        - City: \(profile.city)
        - Location: \(profile.latitude), \(profile.longitude) (+/- \(profile.accuracyMeters)m)
        - Proxy: \(redactedProxyURL(profile.proxyURL))
        - NO_PROXY: \(normalizedNoProxy(profile.noProxy))
        - Route Agent traffic: \(profile.routeTrafficThroughProxy ? "enabled" : "disabled")

        ## How agents should use this

        When `TRACEFENCE=1`, prefer the values in this file for agent-facing language, timezone, region, coarse location, Accept-Language, and proxy behavior. This is a local app profile, not a macOS global settings change.

        Local profile JSON: \(profileURL)
        Local context file: \(contextURL)

        If an agent cannot read the local URL, read `TRACEFENCE_PROFILE_PATH` or `TRACEFENCE_PROFILE_CONTEXT_PATH` from the environment instead.
        """
    }

    private func redactedProxyURL(_ rawValue: String) -> String {
        guard var components = URLComponents(string: rawValue) else { return "" }
        components.user = nil
        components.password = nil
        return components.string ?? ""
    }

    private func defaultsBool(_ key: String, fallback: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func defaultsDouble(_ key: String, fallback: Double) -> Double {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.double(forKey: key)
    }

    private func normalizedNoProxy(_ rawValue: String) -> String {
        var values = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for required in ["localhost", "127.0.0.1", "::1"] where !values.contains(required) {
            values.append(required)
        }
        return values.joined(separator: ",")
    }

    private func forceCoreOverridesInDefaults(_ defaults: UserDefaults) {
        defaults.set(true, forKey: "agentGeoMirrorLocationOverride")
        defaults.set(true, forKey: "agentGeoMirrorTimezoneOverride")
        defaults.set(true, forKey: "agentGeoMirrorLanguageOverride")
        defaults.set(true, forKey: "agentGeoMirrorAcceptLanguageOverride")
    }

    private func writeCLIWrappers(rootURL: URL, binURL: URL, launchersURL: URL) throws {
        let tools: [AgentGeoMirrorCLITool] = [
            AgentGeoMirrorCLITool(wrapperName: "tf-claude", commandName: "claude", displayName: "Claude Code"),
            AgentGeoMirrorCLITool(wrapperName: "tf-codex", commandName: "codex", displayName: "Codex"),
            AgentGeoMirrorCLITool(wrapperName: "tf-grok", commandName: "grok", displayName: "Grok"),
            AgentGeoMirrorCLITool(wrapperName: "tf-gemini", commandName: "gemini", displayName: "Gemini"),
            AgentGeoMirrorCLITool(wrapperName: "tf-cursor-agent", commandName: "cursor-agent", displayName: "Cursor Agent"),
            AgentGeoMirrorCLITool(wrapperName: "tf-opencode", commandName: "opencode", displayName: "OpenCode"),
            AgentGeoMirrorCLITool(wrapperName: "tf-aider", commandName: "aider", displayName: "Aider"),
            AgentGeoMirrorCLITool(wrapperName: "tf-amp", commandName: "amp", displayName: "Amp"),
            AgentGeoMirrorCLITool(wrapperName: "tf-qwen", commandName: "qwen", displayName: "Qwen"),
            AgentGeoMirrorCLITool(wrapperName: "tf-goose", commandName: "goose", displayName: "Goose")
        ]

        for tool in tools {
            let script = cliWrapperScript(rootURL: rootURL, commandName: tool.commandName)
            try writeExecutable(script, to: binURL.appendingPathComponent(tool.wrapperName))
            try writeExecutable(script, to: binURL.appendingPathComponent(tool.commandName))
        }

        let genericScript = """
        #!/bin/zsh
        set -e
        if [[ $# -lt 1 ]]; then
          echo "Usage: tf-agent <command> [args...]" >&2
          exit 64
        fi
        PROFILE_DIR=\(shellQuote(rootURL.path))
        source "$PROFILE_DIR/agent-env.sh"
        exec "$@"
        """
        try writeExecutable(genericScript, to: binURL.appendingPathComponent("tf-agent"))
        try writeExecutable(profileShellLauncher(rootURL: rootURL), to: launchersURL.appendingPathComponent("Open TraceFence CLI Shell.command"))
        for target in CLIAgentLaunchTarget.supported {
            let tool = AgentGeoMirrorCLITool(
                wrapperName: "tf-\(target.commandName)",
                commandName: target.commandName,
                displayName: target.displayName
            )
            try writeExecutable(cliLauncherScript(rootURL: rootURL, tool: tool), to: launchersURL.appendingPathComponent(target.launcherFileName))
        }
    }

    private func syncManagedCommandShims(rootURL: URL, enabled: Bool) throws {
        try syncGrokUserCommandShim(rootURL: rootURL, enabled: enabled)
    }

    private func syncGrokUserCommandShim(rootURL: URL, enabled: Bool) throws {
        let homeURL = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
        let grokBinURL = homeURL.appendingPathComponent(".grok/bin", isDirectory: true)
        let commandURL = grokBinURL.appendingPathComponent("grok")
        let metadataURL = grokBinURL.appendingPathComponent(".tracefence-grok-original")
        let backupURL = grokBinURL.appendingPathComponent("grok.tracefence-original")
        let defaultBinaryURL = homeURL.appendingPathComponent(".grok/downloads/grok-macos-aarch64")

        guard enabled else {
            try restoreManagedCommandShim(commandURL: commandURL, metadataURL: metadataURL, backupURL: backupURL)
            return
        }

        guard fileManager.fileExists(atPath: grokBinURL.path) || fileManager.fileExists(atPath: defaultBinaryURL.path) else {
            return
        }
        try createDirectory(grokBinURL)

        let original = try preserveOriginalCommand(
            commandURL: commandURL,
            metadataURL: metadataURL,
            backupURL: backupURL,
            fallbackURL: defaultBinaryURL
        )
        guard !original.resolvedPath.isEmpty else { return }

        try writeExecutable(
            managedGrokCommandShim(rootURL: rootURL, originalPath: original.resolvedPath),
            to: commandURL
        )
    }

    private func preserveOriginalCommand(
        commandURL: URL,
        metadataURL: URL,
        backupURL: URL,
        fallbackURL: URL
    ) throws -> (resolvedPath: String, metadata: String) {
        if isTraceFenceManagedCommand(commandURL),
           let metadata = try? String(contentsOf: metadataURL, encoding: .utf8),
           let restored = restoredCommandPath(from: metadata, commandURL: commandURL) {
            return (restored, metadata)
        }

        if let symlinkDestination = try? fileManager.destinationOfSymbolicLink(atPath: commandURL.path) {
            let resolvedURL = URL(fileURLWithPath: symlinkDestination, relativeTo: commandURL.deletingLastPathComponent()).standardizedFileURL
            let metadata = "symlink\t\(symlinkDestination)\n"
            try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
            try? fileManager.removeItem(at: commandURL)
            return (resolvedURL.path, metadata)
        }

        if fileManager.fileExists(atPath: commandURL.path) {
            if !fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.moveItem(at: commandURL, to: backupURL)
            } else {
                try? fileManager.removeItem(at: commandURL)
            }
            let metadata = "file\t\(backupURL.path)\n"
            try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
            return (backupURL.path, metadata)
        }

        guard fileManager.fileExists(atPath: fallbackURL.path) else {
            return ("", "")
        }
        let metadata = "file\t\(fallbackURL.path)\n"
        try metadata.write(to: metadataURL, atomically: true, encoding: .utf8)
        return (fallbackURL.path, metadata)
    }

    private func restoreManagedCommandShim(commandURL: URL, metadataURL: URL, backupURL: URL) throws {
        guard isTraceFenceManagedCommand(commandURL) else {
            return
        }

        let metadata = (try? String(contentsOf: metadataURL, encoding: .utf8)) ?? ""
        try? fileManager.removeItem(at: commandURL)

        if metadata.hasPrefix("symlink\t") {
            let destination = metadata
                .dropFirst("symlink\t".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !destination.isEmpty {
                try fileManager.createSymbolicLink(atPath: commandURL.path, withDestinationPath: destination)
            }
        } else if metadata.hasPrefix("file\t") {
            let originalPath = metadata
                .dropFirst("file\t".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if fileManager.fileExists(atPath: originalPath) {
                try fileManager.moveItem(atPath: originalPath, toPath: commandURL.path)
            }
        } else if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.moveItem(at: backupURL, to: commandURL)
        }

        try? fileManager.removeItem(at: metadataURL)
    }

    private func restoredCommandPath(from metadata: String, commandURL: URL) -> String? {
        if metadata.hasPrefix("symlink\t") {
            let destination = metadata
                .dropFirst("symlink\t".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !destination.isEmpty else { return nil }
            return URL(fileURLWithPath: destination, relativeTo: commandURL.deletingLastPathComponent()).standardizedFileURL.path
        }
        if metadata.hasPrefix("file\t") {
            let path = metadata
                .dropFirst("file\t".count)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        }
        return nil
    }

    private func isTraceFenceManagedCommand(_ url: URL) -> Bool {
        guard fileManager.fileExists(atPath: url.path),
              let handle = try? FileHandle(forReadingFrom: url) else {
            return false
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 512),
              let prefix = String(data: data, encoding: .utf8) else {
            return false
        }
        return prefix.contains("TraceFence managed Grok CLI shim")
    }

    private func managedGrokCommandShim(rootURL: URL, originalPath: String) -> String {
        """
        #!/bin/zsh
        # TraceFence managed Grok CLI shim. Do not edit by hand; toggle Agent Environment Profile in TraceFence.
        set -e
        PROFILE_DIR=\(shellQuote(rootURL.path))
        ORIGINAL_GROK=\(shellQuote(originalPath))
        if [[ -f "$PROFILE_DIR/agent-env.sh" ]]; then
          source "$PROFILE_DIR/agent-env.sh"
        fi
        export TRACEFENCE_GROK_MANAGED_SHIM=1
        export GROK_TRACEFENCE_PROFILE_URL="${TRACEFENCE_PROFILE_URL:-}"
        export GROK_TRACEFENCE_PROFILE_CONTEXT_URL="${TRACEFENCE_PROFILE_CONTEXT_URL:-}"
        if [[ ! -x "$ORIGINAL_GROK" ]]; then
          echo "TraceFence: original Grok command was not found at $ORIGINAL_GROK." >&2
          echo "TraceFence: turn Agent Environment Profile off and on again after reinstalling Grok." >&2
          exit 127
        fi
        exec "$ORIGINAL_GROK" "$@"
        """
    }

    private func cliWrapperScript(rootURL: URL, commandName: String) -> String {
        """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(rootURL.path))
        source "$PROFILE_DIR/agent-env.sh"
        WRAPPER_DIR="${TRACEFENCE_GEO_BIN_DIR:-$PROFILE_DIR/bin}"
        path_parts=("${(@s/:/)PATH}")
        clean_parts=()
        for entry in "${path_parts[@]}"; do
          if [[ -n "$entry" && "$entry" != "$WRAPPER_DIR" ]]; then
            clean_parts+=("$entry")
          fi
        done
        SEARCH_PATH="${(j/:/)clean_parts}"
        REAL_COMMAND="$(PATH="$SEARCH_PATH" command -v \(commandName) || true)"
        if [[ -z "$REAL_COMMAND" || "$REAL_COMMAND" == "$WRAPPER_DIR/\(commandName)" ]]; then
          echo "TraceFence: command '\(commandName)' was not found outside the generated Profile bin directory." >&2
          exit 127
        fi
        exec "$REAL_COMMAND" "$@"
        """
    }

    private func cliLauncherScript(rootURL: URL, tool: AgentGeoMirrorCLITool) -> String {
        """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(rootURL.path))
        source "$PROFILE_DIR/agent-env.sh"
        clear
        echo "TraceFence Agent Environment Profile is active."
        echo "Launching \(tool.displayName) with timezone $TRACEFENCE_TIMEZONE and locale $TRACEFENCE_LOCALE."
        echo "Profile: $TRACEFENCE_PROFILE_URL"
        echo ""
        exec \(tool.commandName) "$@"
        """
    }

    private func profileShellLauncher(rootURL: URL) -> String {
        """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(rootURL.path))
        source "$PROFILE_DIR/agent-env.sh"
        cd "$HOME"
        clear
        echo "TraceFence Agent Environment Profile is active."
        echo "Timezone: $TRACEFENCE_TIMEZONE"
        echo "Locale:   $TRACEFENCE_LOCALE"
        echo "Profile:  $TRACEFENCE_PROFILE_URL"
        echo "Use normal commands such as grok, codex, or claude in this shell."
        echo ""
        exec /bin/zsh -l
        """
    }

    private func writeDesktopLaunchers(for profile: AgentGeoMirrorProfile, rootURL: URL, launchersURL: URL) throws {
        for app in DesktopAgentLaunchTarget.supported {
            let script = desktopLauncherScript(
                rootURL: rootURL,
                appNames: app.appNames,
                executable: app.executableName,
                usesChromiumProxyArguments: app.id == "antigravity"
            )
            try writeExecutable(script, to: launchersURL.appendingPathComponent(app.launcherFileName))
        }

        let browserScript = browserLauncherScript(
            rootURL: rootURL,
            browserAppName: "Google Chrome",
            executable: "Google Chrome"
        )
        try writeExecutable(browserScript, to: launchersURL.appendingPathComponent("Launch Chrome with TraceFence Profile.command"))

        let edgeScript = browserLauncherScript(
            rootURL: rootURL,
            browserAppName: "Microsoft Edge",
            executable: "Microsoft Edge"
        )
        try writeExecutable(edgeScript, to: launchersURL.appendingPathComponent("Launch Edge with TraceFence Profile.command"))

        let braveScript = browserLauncherScript(
            rootURL: rootURL,
            browserAppName: "Brave Browser",
            executable: "Brave Browser"
        )
        try writeExecutable(braveScript, to: launchersURL.appendingPathComponent("Launch Brave with TraceFence Profile.command"))

        let arcScript = browserLauncherScript(
            rootURL: rootURL,
            browserAppName: "Arc",
            executable: "Arc"
        )
        try writeExecutable(arcScript, to: launchersURL.appendingPathComponent("Launch Arc with TraceFence Profile.command"))

        let vivaldiScript = browserLauncherScript(
            rootURL: rootURL,
            browserAppName: "Vivaldi",
            executable: "Vivaldi"
        )
        try writeExecutable(vivaldiScript, to: launchersURL.appendingPathComponent("Launch Vivaldi with TraceFence Profile.command"))
    }

    private func writeBrowserExtension(for profile: AgentGeoMirrorProfile, extensionURL: URL) throws {
        try manifestJSON().write(to: extensionURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try profileJS(profile).write(to: extensionURL.appendingPathComponent("profile.js"), atomically: true, encoding: .utf8)
        try backgroundJS(profile).write(to: extensionURL.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)
        try contentBridgeJS().write(to: extensionURL.appendingPathComponent("content_bridge.js"), atomically: true, encoding: .utf8)
        try mainInjectorJS().write(to: extensionURL.appendingPathComponent("main_injector.js"), atomically: true, encoding: .utf8)
        try popupHTML().write(to: extensionURL.appendingPathComponent("popup.html"), atomically: true, encoding: .utf8)
        try popupJS().write(to: extensionURL.appendingPathComponent("popup.js"), atomically: true, encoding: .utf8)
    }

    private func createDirectory(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func writeExecutable(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func writeLocalProbeShims(to binURL: URL) throws {
        let rewriteCommands: [(name: String, path: String)] = [
            ("readlink", "/usr/bin/readlink"),
            ("realpath", "/usr/bin/realpath"),
            ("ls", "/bin/ls"),
            ("stat", "/usr/bin/stat"),
            ("cat", "/bin/cat"),
            ("file", "/usr/bin/file"),
            ("strings", "/usr/bin/strings"),
            ("md5", "/sbin/md5"),
            ("shasum", "/usr/bin/shasum"),
            ("cksum", "/usr/bin/cksum"),
            ("zdump", "/usr/sbin/zdump")
        ]

        for command in rewriteCommands {
            try writeExecutable(
                localtimeRewriteExecShim(commandName: command.name, realPath: command.path),
                to: binURL.appendingPathComponent(command.name)
            )
        }

        try writeExecutable(systemsetupShim(), to: binURL.appendingPathComponent("systemsetup"))
        try writeExecutable(localeShim(), to: binURL.appendingPathComponent("locale"))
        try writeExecutable(defaultsShim(), to: binURL.appendingPathComponent("defaults"))
    }

    private func writeShellStartupFiles(rootURL: URL, shellURL: URL) throws {
        let envPath = rootURL.appendingPathComponent("agent-env.sh").path
        let zshSource = """
        # TraceFence generated shell profile.
        if [[ -f \(shellQuote(envPath)) ]]; then
          source \(shellQuote(envPath))
        fi
        """
        let shSource = """
        # TraceFence generated shell profile.
        if [ -f \(shellQuote(envPath)) ]; then
          . \(shellQuote(envPath))
        fi
        """

        try writeExecutable(zshSource, to: shellURL.appendingPathComponent(".zshenv"))
        try writeExecutable(zshSource, to: shellURL.appendingPathComponent(".zprofile"))
        try writeExecutable(zshSource, to: shellURL.appendingPathComponent(".zshrc"))
        try writeExecutable(shSource, to: shellURL.appendingPathComponent("bash_env"))
        try writeExecutable(shSource, to: shellURL.appendingPathComponent("sh_env"))
    }

    private func localtimeRewriteExecShim(commandName: String, realPath: String) -> String {
        """
        #!/bin/zsh
        REAL_COMMAND=\(shellQuote(realPath))
        if [[ ! -x "$REAL_COMMAND" ]]; then
          REAL_COMMAND="$(PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v \(commandName) || true)"
        fi
        if [[ -z "$REAL_COMMAND" || ! -x "$REAL_COMMAND" ]]; then
          echo "TraceFence: unable to find real \(commandName)." >&2
          exit 127
        fi
        TRACEFENCE_LOCALTIME_FILE="${TRACEFENCE_LOCALTIME_FILE:-/var/db/timezone/zoneinfo/${TRACEFENCE_TIMEZONE:-UTC}}"
        if [[ "\(commandName)" == "readlink" && $# -eq 1 && "${1:-}" == "/etc/localtime" ]]; then
          echo "$TRACEFENCE_LOCALTIME_FILE"
          exit 0
        fi
        ARGS=()
        for arg in "$@"; do
          if [[ "$arg" == "/etc/localtime" ]]; then
            ARGS+=("$TRACEFENCE_LOCALTIME_FILE")
          else
            ARGS+=("$arg")
          fi
        done
        exec "$REAL_COMMAND" "${ARGS[@]}"
        """
    }

    private func systemsetupShim() -> String {
        """
        #!/bin/zsh
        if [[ "${1:-}" == "-gettimezone" || "${1:-}" == "-getTimeZone" ]]; then
          echo "Time Zone: ${TRACEFENCE_TIMEZONE:-UTC}"
          exit 0
        fi
        exec /usr/sbin/systemsetup "$@"
        """
    }

    private func localeShim() -> String {
        """
        #!/bin/zsh
        POSIX_LOCALE="${TRACEFENCE_POSIX_LOCALE:-en_US.UTF-8}"
        if [[ $# -eq 0 ]]; then
          echo "LANG=\\"$POSIX_LOCALE\\""
          echo "LC_COLLATE=\\"$POSIX_LOCALE\\""
          echo "LC_CTYPE=\\"$POSIX_LOCALE\\""
          echo "LC_MESSAGES=\\"$POSIX_LOCALE\\""
          echo "LC_MONETARY=\\"$POSIX_LOCALE\\""
          echo "LC_NUMERIC=\\"$POSIX_LOCALE\\""
          echo "LC_TIME=\\"$POSIX_LOCALE\\""
          echo "LC_ALL=\\"$POSIX_LOCALE\\""
          exit 0
        fi
        if [[ $# -eq 1 && ( "$1" == "LANG" || "$1" == LC_* ) ]]; then
          echo "$POSIX_LOCALE"
          exit 0
        fi
        exec /usr/bin/locale "$@"
        """
    }

    private func defaultsShim() -> String {
        """
        #!/bin/zsh
        joined=" $* "
        if [[ "$joined" == *"AppleLanguages"* ]]; then
          langs=("${(@s:,:)TRACEFENCE_LANGUAGES}")
          if [[ ${#langs[@]} -eq 0 ]]; then
            langs=("${TRACEFENCE_LOCALE:-en-US}")
          fi
          echo "("
          for lang in "${langs[@]}"; do
            echo "    \\"$lang\\""
          done
          echo ")"
          exit 0
        fi
        if [[ "$joined" == *"AppleLocale"* ]]; then
          echo "${TRACEFENCE_LOCALE_UNDERSCORE:-en_US}"
          exit 0
        fi
        exec /usr/bin/defaults "$@"
        """
    }

    private func envScript(for profile: AgentGeoMirrorProfile, rootURL: URL, binURL: URL, shellURL: URL) -> String {
        let normalizedLanguages = profile.languages.isEmpty ? [profile.localeIdentifier] : profile.languages
        let localeIdentifier = profile.localeIdentifier.isEmpty ? "en-US" : profile.localeIdentifier
        let localeUnderscore = localeIdentifier.replacingOccurrences(of: "-", with: "_")
        let posixLocale = localeUnderscore + ".UTF-8"
        let localtimeFile = "/var/db/timezone/zoneinfo/\(profile.timezoneIdentifier)"
        let profileURL = AgentGeoMirrorProfileAccess.profileURL(profileName: profile.name)
        let contextURL = AgentGeoMirrorProfileAccess.contextURL(profileName: profile.name)
        let rawProfileURL = AgentGeoMirrorProfileAccess.rawProfileURL(profileName: profile.name)
        let portableProfilePath = rootURL.appendingPathComponent("agent-profile.json").path
        let profileContextPath = rootURL.appendingPathComponent("agent-profile.md").path
        let rawProfilePath = rootURL.appendingPathComponent("profile.json").path
        let noProxy = normalizedNoProxy(profile.noProxy)
        let chromiumBypassList = noProxy
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ";")
        var lines = [
            "#!/bin/zsh",
            "# Generated by TraceFence Agent Geo Mirror. Edit from TraceFence settings instead of hand editing this file.",
            "export TRACEFENCE=\(shellQuote(profile.enabled ? "1" : "0"))",
            "export TRACEFENCE_GEO_PROFILE_ENABLED=\(shellQuote(profile.enabled ? "1" : "0"))",
            "export TRACEFENCE_GEO_PROFILE_NAME=\(shellQuote(profile.name))",
            "export TRACEFENCE_GEO_PROFILE_DIR=\(shellQuote(rootURL.path))",
            "export TRACEFENCE_GEO_BIN_DIR=\(shellQuote(binURL.path))",
            "export TRACEFENCE_GEO_SHELL_DIR=\(shellQuote(shellURL.path))",
            "export TRACEFENCE_PROFILE_SERVICE_ORIGIN=\(shellQuote(AgentGeoMirrorProfileAccess.origin))",
            "export TRACEFENCE_PROFILE_URL=\(shellQuote(profileURL))",
            "export TRACEFENCE_PROFILE_CONTEXT_URL=\(shellQuote(contextURL))",
            "export TRACEFENCE_RAW_PROFILE_URL=\(shellQuote(rawProfileURL))",
            "export TRACEFENCE_PROFILE_PATH=\(shellQuote(portableProfilePath))",
            "export TRACEFENCE_PROFILE_CONTEXT_PATH=\(shellQuote(profileContextPath))",
            "export TRACEFENCE_RAW_PROFILE_PATH=\(shellQuote(rawProfilePath))",
            "export AGENT_PROFILE_URL=\"$TRACEFENCE_PROFILE_URL\"",
            "export AGENT_PROFILE_CONTEXT_URL=\"$TRACEFENCE_PROFILE_CONTEXT_URL\"",
            "export AGENT_PROFILE_PATH=\"$TRACEFENCE_PROFILE_PATH\"",
            "export AGENT_PROFILE_CONTEXT_PATH=\"$TRACEFENCE_PROFILE_CONTEXT_PATH\"",
            "export TRACEFENCE_PROFILE_HINT=\(shellQuote("Read TRACEFENCE_PROFILE_URL or TRACEFENCE_PROFILE_CONTEXT_URL for the local TraceFence agent profile."))",
            "export TRACEFENCE_COUNTRY=\(shellQuote(profile.countryCode.uppercased()))",
            "export TRACEFENCE_REGION=\(shellQuote(profile.region))",
            "export TRACEFENCE_CITY=\(shellQuote(profile.city))",
            "export TRACEFENCE_TIMEZONE=\(shellQuote(profile.timezoneIdentifier))",
            "export TRACEFENCE_LOCALTIME_FILE=\(shellQuote(localtimeFile))",
            "export TRACEFENCE_LOCALE=\(shellQuote(localeIdentifier))",
            "export TRACEFENCE_LOCALE_UNDERSCORE=\(shellQuote(localeUnderscore))",
            "export TRACEFENCE_POSIX_LOCALE=\(shellQuote(posixLocale))",
            "export TRACEFENCE_LANGUAGES=\(shellQuote(normalizedLanguages.joined(separator: ",")))",
            "export TRACEFENCE_LANGUAGES_COLON=\(shellQuote(normalizedLanguages.joined(separator: ":")))"
        ]

        if profile.enabled {
            lines.append("export PATH=\"$TRACEFENCE_GEO_BIN_DIR:$PATH\"")
            lines.append("export ZDOTDIR=\"$TRACEFENCE_GEO_SHELL_DIR\"")
            lines.append("export BASH_ENV=\"$TRACEFENCE_GEO_SHELL_DIR/bash_env\"")
            lines.append("export ENV=\"$TRACEFENCE_GEO_SHELL_DIR/sh_env\"")
            lines.append("export TRACEFENCE_PROFILE_PROXY_URL=\(shellQuote(profile.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines)))")
            lines.append("export TRACEFENCE_PROFILE_NO_PROXY=\(shellQuote(noProxy.trimmingCharacters(in: .whitespacesAndNewlines)))")
            lines.append("export TRACEFENCE_CHROMIUM_PROXY_BYPASS_LIST=\(shellQuote(chromiumBypassList))")
            lines.append("export TRACEFENCE_ROUTE_TRAFFIC_THROUGH_PROXY=\(shellQuote(profile.routeTrafficThroughProxy ? "1" : "0"))")
            if profile.routeTrafficThroughProxy {
                lines.append("if [[ \"${TRACEFENCE_SKIP_PROXY:-0}\" != \"1\" ]]; then")
                lines.append("  export HTTP_PROXY=\"$TRACEFENCE_PROFILE_PROXY_URL\"")
                lines.append("  export HTTPS_PROXY=\"$TRACEFENCE_PROFILE_PROXY_URL\"")
                lines.append("  export ALL_PROXY=\"$TRACEFENCE_PROFILE_PROXY_URL\"")
                lines.append("  export http_proxy=\"$HTTP_PROXY\"")
                lines.append("  export https_proxy=\"$HTTPS_PROXY\"")
                lines.append("  export all_proxy=\"$ALL_PROXY\"")
                lines.append("  export NO_PROXY=\"$TRACEFENCE_PROFILE_NO_PROXY\"")
                lines.append("  export no_proxy=\"$NO_PROXY\"")
                lines.append("fi")
            } else {
                lines.append("unset HTTP_PROXY HTTPS_PROXY ALL_PROXY http_proxy https_proxy all_proxy NO_PROXY no_proxy")
            }
            if profile.timezoneOverrideEnabled {
                lines.append("export TZ=\(shellQuote(profile.timezoneIdentifier))")
            }
            if profile.languageOverrideEnabled {
                lines.append("export LANG=\(shellQuote(posixLocale))")
                lines.append("export LC_ALL=\(shellQuote(posixLocale))")
                lines.append("export LC_CTYPE=\(shellQuote(posixLocale))")
                lines.append("export LC_MESSAGES=\(shellQuote(posixLocale))")
                lines.append("export LANGUAGE=\"$TRACEFENCE_LANGUAGES_COLON\"")
                lines.append("export AppleLocale=\"$TRACEFENCE_LOCALE_UNDERSCORE\"")
                lines.append("export AppleLanguages=\"$TRACEFENCE_LANGUAGES\"")
            }
            if profile.acceptLanguageOverrideEnabled {
                lines.append("export ACCEPT_LANGUAGE=\(shellQuote(profile.acceptLanguage))")
                lines.append("export TRACEFENCE_ACCEPT_LANGUAGE=\"$ACCEPT_LANGUAGE\"")
            }
            if profile.locationOverrideEnabled {
                lines.append("export TRACEFENCE_LATITUDE=\(shellQuote(String(profile.latitude)))")
                lines.append("export TRACEFENCE_LONGITUDE=\(shellQuote(String(profile.longitude)))")
                lines.append("export TRACEFENCE_ACCURACY_METERS=\(shellQuote(String(profile.accuracyMeters)))")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func desktopLauncherScript(
        rootURL: URL,
        appNames: [String],
        executable: String,
        usesChromiumProxyArguments: Bool
    ) -> String {
        let appNameLines = appNames.map { "  \(shellQuote($0))" }.joined(separator: "\n")
        let fallbackAppName = appNames.first ?? ""
        let chromiumProxySetup = usesChromiumProxyArguments ? """
        if [[ "${TRACEFENCE_ROUTE_TRAFFIC_THROUGH_PROXY:-0}" == "1" ]]; then
          APP_NETWORK_ARGS=(
            --proxy-server="$TRACEFENCE_PROFILE_PROXY_URL"
            --proxy-bypass-list="$TRACEFENCE_CHROMIUM_PROXY_BYPASS_LIST"
            --disable-quic
            --force-webrtc-ip-handling-policy=disable_non_proxied_udp
          )
        fi
        """ : ""
        return """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(rootURL.path))
        source "$PROFILE_DIR/agent-env.sh"
        APP_LOCALE_ARGS=()
        APP_NETWORK_ARGS=()
        \(chromiumProxySetup)
        if [[ "${TRACEFENCE_GEO_PROFILE_ENABLED:-0}" == "1" && -n "${TRACEFENCE_LOCALE_UNDERSCORE:-}" ]]; then
          APP_LOCALE_ARGS=(-AppleLocale "$TRACEFENCE_LOCALE_UNDERSCORE" -AppleLanguages "($TRACEFENCE_LANGUAGES)")
        fi
        if [[ "${TRACEFENCE_GEO_PROFILE_ENABLED:-0}" == "1" && -n "${TRACEFENCE_LOCALE:-}" ]]; then
          APP_LOCALE_ARGS+=(--lang="$TRACEFENCE_LOCALE")
        fi
        APP_NAMES=(
        \(appNameLines)
        )
        for app_name in "${APP_NAMES[@]}"; do
          CANDIDATES=(
            "/Applications/$app_name.app/Contents/MacOS/\(executable)"
            "$HOME/Applications/$app_name.app/Contents/MacOS/\(executable)"
          )
          for candidate in "${CANDIDATES[@]}"; do
            if [[ -x "$candidate" ]]; then
              exec "$candidate" "${APP_LOCALE_ARGS[@]}" "${APP_NETWORK_ARGS[@]}" "$@"
            fi
          done
          if [[ -d "/Applications/$app_name.app" || -d "$HOME/Applications/$app_name.app" ]]; then
            exec open -na "$app_name" --args "${APP_LOCALE_ARGS[@]}" "${APP_NETWORK_ARGS[@]}" "$@"
          fi
        done
        echo "TraceFence: \(fallbackAppName).app was not found in /Applications or ~/Applications." >&2
        echo "TraceFence: falling back to macOS open; some environment variables may not be inherited by the app." >&2
        exec open -na \(shellQuote(fallbackAppName)) --args "${APP_LOCALE_ARGS[@]}" "${APP_NETWORK_ARGS[@]}" "$@"
        """
    }

    private func browserLauncherScript(rootURL: URL, browserAppName: String, executable: String) -> String {
        """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(rootURL.path))
        source "$PROFILE_DIR/agent-env.sh"
        EXTENSION_DIR="$PROFILE_DIR/BrowserExtension"
        USER_DATA_DIR="$PROFILE_DIR/\(safeFileName(browserAppName))-Profile"
        mkdir -p "$USER_DATA_DIR"
        BROWSER_LANG_ARGS=()
        if [[ -n "${TRACEFENCE_LOCALE:-}" ]]; then
          BROWSER_LANG_ARGS=(--lang="$TRACEFENCE_LOCALE")
        fi
        if [[ -n "${TRACEFENCE_ACCEPT_LANGUAGE:-}" ]]; then
          BROWSER_LANG_ARGS+=("--accept-lang=$TRACEFENCE_ACCEPT_LANGUAGE")
        fi
        BROWSER_PROXY_ARGS=()
        if [[ "${TRACEFENCE_ROUTE_TRAFFIC_THROUGH_PROXY:-0}" == "1" ]]; then
          BROWSER_PROXY_ARGS=(
            --proxy-server="$TRACEFENCE_PROFILE_PROXY_URL"
            --proxy-bypass-list="$TRACEFENCE_CHROMIUM_PROXY_BYPASS_LIST"
            --disable-quic
            --force-webrtc-ip-handling-policy=disable_non_proxied_udp
          )
        fi
        CANDIDATES=(
          "/Applications/\(browserAppName).app/Contents/MacOS/\(executable)"
          "$HOME/Applications/\(browserAppName).app/Contents/MacOS/\(executable)"
        )
        for candidate in "${CANDIDATES[@]}"; do
          if [[ -x "$candidate" ]]; then
            exec "$candidate" --user-data-dir="$USER_DATA_DIR" --load-extension="$EXTENSION_DIR" "${BROWSER_LANG_ARGS[@]}" "${BROWSER_PROXY_ARGS[@]}" "$@"
          fi
        done
        echo "TraceFence: \(browserAppName).app was not found in /Applications or ~/Applications." >&2
        exit 66
        """
    }

    private func manifestJSON() -> String {
        """
        {
          "manifest_version": 3,
          "name": "TraceFence Agent Geo Mirror",
          "description": "Local browser environment profile generated by TraceFence.",
          "version": "1.0.0",
          "permissions": ["declarativeNetRequest", "storage"],
          "host_permissions": ["<all_urls>"],
          "background": {
            "service_worker": "background.js"
          },
          "content_scripts": [
            {
              "matches": ["<all_urls>"],
              "js": ["profile.js", "content_bridge.js"],
              "run_at": "document_start",
              "all_frames": true
            }
          ],
          "web_accessible_resources": [
            {
              "resources": ["main_injector.js"],
              "matches": ["<all_urls>"]
            }
          ],
          "action": {
            "default_title": "TraceFence Agent Geo Mirror",
            "default_popup": "popup.html"
          }
        }
        """
    }

    private func profileJS(_ profile: AgentGeoMirrorProfile) throws -> String {
        let json = try browserProfileJSON(profile)
        return "globalThis.TRACEFENCE_GEO_PROFILE = \(json);\n"
    }

    private func backgroundJS(_ profile: AgentGeoMirrorProfile) throws -> String {
        let acceptLanguage = javascriptString(profile.acceptLanguage)
        return """
        importScripts("profile.js");

        const APPLY_ACCEPT_LANGUAGE = \(profile.enabled && profile.acceptLanguageOverrideEnabled ? "true" : "false");
        const ACCEPT_LANGUAGE = \(acceptLanguage);
        const RULE_ID = 270801;

        async function syncHeaderRule() {
          if (!chrome.declarativeNetRequest) return;
          const addRules = APPLY_ACCEPT_LANGUAGE ? [{
            id: RULE_ID,
            priority: 1,
            action: {
              type: "modifyHeaders",
              requestHeaders: [
                { header: "Accept-Language", operation: "set", value: ACCEPT_LANGUAGE }
              ]
            },
            condition: {
              urlFilter: "|http",
              resourceTypes: [
                "main_frame", "sub_frame", "stylesheet", "script", "image", "font",
                "object", "xmlhttprequest", "ping", "csp_report", "media",
                "websocket", "other"
              ]
            }
          }] : [];
          await chrome.declarativeNetRequest.updateDynamicRules({
            removeRuleIds: [RULE_ID],
            addRules
          });
        }

        chrome.runtime.onInstalled.addListener(syncHeaderRule);
        chrome.runtime.onStartup.addListener(syncHeaderRule);
        syncHeaderRule();
        """
    }

    private func contentBridgeJS() -> String {
        """
        (() => {
          const profile = globalThis.TRACEFENCE_GEO_PROFILE;
          if (!profile || !profile.enabled) return;
          const script = document.createElement("script");
          script.src = chrome.runtime.getURL("main_injector.js");
          script.dataset.traceFenceProfile = JSON.stringify(profile);
          script.onload = () => script.remove();
          script.onerror = () => script.remove();
          (document.documentElement || document.head || document).prepend(script);
        })();
        """
    }

    private func mainInjectorJS() -> String {
        """
        (() => {
          const currentScript = document.currentScript;
          const rawProfile = currentScript?.dataset?.traceFenceProfile;
          if (!rawProfile) return;

          let profile;
          try {
            profile = JSON.parse(rawProfile);
          } catch (_) {
            return;
          }
          if (!profile.enabled) return;

          const NativeDateTimeFormat = Intl.DateTimeFormat;
          const NativeNumberFormat = Intl.NumberFormat;
          const NativeCollator = Intl.Collator;
          const nativeGetTimezoneOffset = Date.prototype.getTimezoneOffset;

          const defineGetter = (target, key, getter) => {
            try {
              Object.defineProperty(target, key, {
                configurable: true,
                enumerable: true,
                get: getter
              });
            } catch (_) {}
          };

          const timezoneOffsetFor = (date, timezone) => {
            try {
              const parts = new NativeDateTimeFormat("en-US", {
                timeZone: timezone,
                hourCycle: "h23",
                year: "numeric",
                month: "2-digit",
                day: "2-digit",
                hour: "2-digit",
                minute: "2-digit",
                second: "2-digit"
              }).formatToParts(date).reduce((acc, part) => {
                acc[part.type] = part.value;
                return acc;
              }, {});
              const asUTC = Date.UTC(
                Number(parts.year),
                Number(parts.month) - 1,
                Number(parts.day),
                Number(parts.hour),
                Number(parts.minute),
                Number(parts.second)
              );
              return Math.round((date.getTime() - asUTC) / 60000);
            } catch (_) {
              return nativeGetTimezoneOffset.call(date);
            }
          };

          if (profile.languageOverrideEnabled) {
            defineGetter(Navigator.prototype, "language", () => profile.localeIdentifier);
            defineGetter(Navigator.prototype, "languages", () => profile.languages.slice());
          }

          if (profile.locationOverrideEnabled && navigator.geolocation) {
            let nextWatchId = 7000;
            const watches = new Map();
            const makePosition = () => ({
              coords: {
                latitude: Number(profile.latitude),
                longitude: Number(profile.longitude),
                accuracy: Number(profile.accuracyMeters),
                altitude: null,
                altitudeAccuracy: null,
                heading: null,
                speed: null
              },
              timestamp: Date.now()
            });
            navigator.geolocation.getCurrentPosition = (success, error, options) => {
              if (typeof success === "function") {
                setTimeout(() => success(makePosition()), 0);
              }
            };
            navigator.geolocation.watchPosition = (success, error, options) => {
              const watchId = nextWatchId++;
              if (typeof success === "function") {
                const tick = () => success(makePosition());
                tick();
                watches.set(watchId, setInterval(tick, Math.max(1000, Number(options?.maximumAge || 10000))));
              }
              return watchId;
            };
            navigator.geolocation.clearWatch = (watchId) => {
              const timer = watches.get(watchId);
              if (timer) clearInterval(timer);
              watches.delete(watchId);
            };
          }

          if (profile.locationOverrideEnabled && navigator.permissions?.query) {
            const nativeQuery = navigator.permissions.query.bind(navigator.permissions);
            navigator.permissions.query = (descriptor) => {
              if (descriptor && descriptor.name === "geolocation") {
                return Promise.resolve({ state: "granted", onchange: null });
              }
              return nativeQuery(descriptor);
            };
          }

          if (profile.timezoneOverrideEnabled) {
            Date.prototype.getTimezoneOffset = function() {
              return timezoneOffsetFor(this, profile.timezoneIdentifier);
            };
          }

          if (profile.languageOverrideEnabled || profile.timezoneOverrideEnabled) {
            Intl.DateTimeFormat = function(locales, options) {
              const nextLocales = profile.languageOverrideEnabled && (locales === undefined || locales === null)
                ? profile.localeIdentifier
                : locales;
              const nextOptions = Object.assign({}, options || {});
              if (profile.timezoneOverrideEnabled && nextOptions.timeZone === undefined) {
                nextOptions.timeZone = profile.timezoneIdentifier;
              }
              return new NativeDateTimeFormat(nextLocales, nextOptions);
            };
            Intl.DateTimeFormat.prototype = NativeDateTimeFormat.prototype;
            Object.setPrototypeOf(Intl.DateTimeFormat, NativeDateTimeFormat);

            Intl.NumberFormat = function(locales, options) {
              const nextLocales = profile.languageOverrideEnabled && (locales === undefined || locales === null)
                ? profile.localeIdentifier
                : locales;
              return new NativeNumberFormat(nextLocales, options);
            };
            Intl.NumberFormat.prototype = NativeNumberFormat.prototype;
            Object.setPrototypeOf(Intl.NumberFormat, NativeNumberFormat);

            Intl.Collator = function(locales, options) {
              const nextLocales = profile.languageOverrideEnabled && (locales === undefined || locales === null)
                ? profile.localeIdentifier
                : locales;
              return new NativeCollator(nextLocales, options);
            };
            Intl.Collator.prototype = NativeCollator.prototype;
            Object.setPrototypeOf(Intl.Collator, NativeCollator);
          }
        })();
        """
    }

    private func popupHTML() -> String {
        """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
              body { width: 300px; margin: 0; padding: 14px; font: 13px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #0f172a; }
              h1 { font-size: 15px; margin: 0 0 10px; }
              .row { display: flex; justify-content: space-between; gap: 12px; padding: 6px 0; border-top: 1px solid #e5e7eb; }
              .key { color: #64748b; }
              .value { text-align: right; font-weight: 600; }
              .ok { color: #2563eb; }
            </style>
          </head>
          <body>
            <h1>TraceFence Agent Geo Mirror</h1>
            <div id="status"></div>
            <script src="profile.js"></script>
            <script src="popup.js"></script>
          </body>
        </html>
        """
    }

    private func popupJS() -> String {
        """
        const profile = globalThis.TRACEFENCE_GEO_PROFILE || {};
        const status = document.getElementById("status");
        const rows = [
          ["Enabled", profile.enabled ? "On" : "Off"],
          ["Country", profile.countryCode || "-"],
          ["City", profile.city || "-"],
          ["Timezone", profile.timezoneIdentifier || "-"],
          ["Locale", profile.localeIdentifier || "-"],
          ["Accept-Language", profile.acceptLanguage || "-"],
          ["Location", `${profile.latitude}, ${profile.longitude}`]
        ];
        status.innerHTML = rows.map(([key, value]) =>
          `<div class="row"><span class="key">${key}</span><span class="value">${value}</span></div>`
        ).join("");
        """
    }

    private func readme(for profile: AgentGeoMirrorProfile) -> String {
        """
        # TraceFence Agent Geo Mirror

        This profile is generated locally by TraceFence direct build. It does not modify macOS global language or timezone settings.

        ## What is generated

        - `agent-env.sh`: sourceable environment profile for proxy, timezone, locale, and coarse location metadata.
        - `agent-profile.json`: stable agent-facing profile for new CLIs or desktop agents that can read a local profile file.
        - `agent-profile.md`: compact human and agent readable context for tools that accept a profile/context document.
        - `profile-url.txt`: local URL and file path shortcuts for support and troubleshooting.
        - `bin/tf-*`: CLI wrappers such as `tf-grok`, `tf-claude`, `tf-codex`, and `tf-agent`.
        - `bin/grok`, `bin/claude`, `bin/codex`, and other command-name shims: when this profile's `bin` directory is first in `PATH`, normal CLI commands are routed through TraceFence automatically.
        - `bin/systemsetup`, `bin/locale`, `bin/defaults`, and localtime file shims: common local probes are answered from this profile when the generated `bin` directory is first in `PATH`.
        - `ShellProfile`: generated zsh/bash/sh startup files that keep the profile active when an agent opens a nested login shell.
        - `Launchers/*.command`: desktop launchers for Codex, Claude, Cursor, Windsurf, Trae, VS Code, ChatGPT, Chrome, Edge, Brave, Arc, and Vivaldi.
        - `BrowserExtension`: unpacked Chromium extension that mirrors geolocation, timezone, locale, and Accept-Language in browser-visible APIs.

        ## Usage

        Add this to your shell when you want the profile for arbitrary commands:

        ```sh
        source \(shellQuote("agent-env.sh"))
        ```

        Or prepend the generated `bin` directory to your PATH:

        ```sh
        export PATH=\(shellQuote("bin")):$PATH
        tf-grok
        tf-claude
        tf-codex
        tf-agent your-command --with --args
        ```

        The generated `Launch Grok CLI.command` starts Grok in a new Terminal window with this profile already active. `Open TraceFence CLI Shell.command` opens a general shell where normal commands such as `grok`, `codex`, and `claude` are routed through the generated shims.

        TraceFence also starts a local read-only profile service while the switch is on:

        - JSON profile: \(AgentGeoMirrorProfileAccess.profileURL(profileName: profile.name))
        - Context profile: \(AgentGeoMirrorProfileAccess.contextURL(profileName: profile.name))

        New agents that support profile discovery can read `TRACEFENCE_PROFILE_URL`, `TRACEFENCE_PROFILE_CONTEXT_URL`, `TRACEFENCE_PROFILE_PATH`, or `TRACEFENCE_PROFILE_CONTEXT_PATH` from the environment instead of needing a TraceFence-specific wrapper.

        For desktop apps, launch them through the generated `.command` files so the app process inherits the language, timezone, local-probe profile, and—when explicitly enabled—the configured proxy. Antigravity and generated Chromium launchers also disable QUIC and non-proxied WebRTC UDP while traffic routing is enabled.

        For Chromium browsers, use the generated Chrome, Edge, Brave, Arc, or Vivaldi launcher, or load the `BrowserExtension` folder from the browser extension page with Developer Mode enabled.

        ## Limits

        - CLI coverage depends on launching the tool through `tf-*`, `tf-agent`, or a shell that has sourced `agent-env.sh`. The generated shell startup files keep the profile active for common nested `zsh -lc`, `bash -lc`, and `sh` command execution.
        - The local profile service is a convenience channel for agents that can read a local URL. It does not intercept HTTPS traffic or force third-party tools to obey the profile.
        - Common local probes such as `systemsetup -gettimezone`, `locale`, `defaults read AppleLocale`, `defaults read AppleLanguages`, and `readlink /etc/localtime` are covered only when the command is resolved through the generated `PATH` shim. A tool that calls absolute system paths such as `/usr/bin/defaults` or reads system files with custom code can still bypass this profile.
        - Electron/AppKit desktop coverage is strongest when the generated launcher starts the real app binary. The fallback `open` path may not propagate all environment variables.
        - Browser API coverage applies to pages where the unpacked extension is enabled. Native apps do not use the browser extension.
        - Existing running agents are not changed retroactively. Quit and relaunch them through the generated wrapper or launcher after changing this profile.

        ## Current profile

        - Name: \(profile.name)
        - Proxy: \(profile.proxyURL)
        - Route Agent traffic: \(profile.routeTrafficThroughProxy ? "enabled" : "disabled")
        - Country: \(profile.countryCode.uppercased())
        - City: \(profile.city)
        - Timezone: \(profile.timezoneIdentifier)
        - Locale: \(profile.localeIdentifier)
        - Accept-Language: \(profile.acceptLanguage)
        """
    }

    private func browserProfileJSON(_ profile: AgentGeoMirrorProfile) throws -> String {
        let dictionary: [String: Any] = [
            "enabled": profile.enabled,
            "countryCode": profile.countryCode.uppercased(),
            "region": profile.region,
            "city": profile.city,
            "timezoneIdentifier": profile.timezoneIdentifier,
            "localeIdentifier": profile.localeIdentifier,
            "languages": profile.languages,
            "acceptLanguage": profile.acceptLanguage,
            "latitude": profile.latitude,
            "longitude": profile.longitude,
            "accuracyMeters": profile.accuracyMeters,
            "locationOverrideEnabled": profile.locationOverrideEnabled,
            "timezoneOverrideEnabled": profile.timezoneOverrideEnabled,
            "languageOverrideEnabled": profile.languageOverrideEnabled,
            "acceptLanguageOverrideEnabled": profile.acceptLanguageOverrideEnabled
        ]
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func javascriptString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return "\"\""
        }
        return String(json.dropFirst().dropLast())
    }

    private func safeFileName(_ rawName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return name.isEmpty ? "default" : name
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func localeBundle(countryCode: String, timezone: String) -> (localeIdentifier: String, languages: [String], acceptLanguage: String) {
        let country = countryCode.uppercased()
        let locale: String
        switch country {
        case "US": locale = "en-US"
        case "GB": locale = "en-GB"
        case "CA": locale = timezone.hasPrefix("America/") ? "en-CA" : "fr-CA"
        case "AU": locale = "en-AU"
        case "NZ": locale = "en-NZ"
        case "SG": locale = "en-SG"
        case "JP": locale = "ja-JP"
        case "KR": locale = "ko-KR"
        case "TW": locale = "zh-TW"
        case "HK": locale = "zh-HK"
        case "CN": locale = "zh-CN"
        case "DE": locale = "de-DE"
        case "FR": locale = "fr-FR"
        case "NL": locale = "nl-NL"
        case "ES": locale = "es-ES"
        case "IT": locale = "it-IT"
        case "BR": locale = "pt-BR"
        case "IN": locale = "en-IN"
        default: locale = "en-US"
        }
        let language = locale.split(separator: "-").first.map(String.init) ?? locale
        let languages = language == locale ? [locale] : [locale, language]
        let acceptLanguage = languages.enumerated().map { index, item -> String in
            index == 0 ? item : "\(item);q=\(String(format: "%.1f", max(0.1, 1.0 - Double(index) * 0.1)))"
        }.joined(separator: ",")
        return (locale, languages, acceptLanguage)
    }
}

final class AgentGeoMirrorProfileServer {
    static let shared = AgentGeoMirrorProfileServer()

    private let queue = DispatchQueue(label: "com.tracefence.agent-profile-server", qos: .utility)
    private let fileManager = FileManager.default
    private var listener: NWListener?
    private var activeProfileName = AgentGeoMirrorProfile.defaultProfile.name

    private init() {}

    func syncWithDefaults() {
        guard SandboxPaths.isDirectDistribution else {
            stop()
            return
        }

        let defaults = UserDefaults.standard
        let enabled: Bool
        if defaults.object(forKey: "agentGeoMirrorEnabled") == nil {
            enabled = AgentGeoMirrorProfile.defaultProfile.enabled
        } else {
            enabled = defaults.bool(forKey: "agentGeoMirrorEnabled")
        }
        let profileName = defaults.string(forKey: "agentGeoMirrorProfileName") ?? AgentGeoMirrorProfile.defaultProfile.name
        setProfile(profileName: profileName, enabled: enabled)
    }

    func setProfile(profileName: String, enabled: Bool) {
        queue.async {
            self.activeProfileName = profileName
            if enabled {
                self.startLocked()
            } else {
                self.stopLocked()
            }
        }
    }

    func stop() {
        queue.async {
            self.stopLocked()
        }
    }

    private func startLocked() {
        guard listener == nil else {
            return
        }

        do {
            guard let port = NWEndpoint.Port(rawValue: AgentGeoMirrorProfileAccess.port) else {
                return
            }
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(
                host: NWEndpoint.Host(AgentGeoMirrorProfileAccess.host),
                port: port
            )
            let listener = try NWListener(using: parameters)
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    print("[TraceFence] Agent profile server failed: \(error)")
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            print("[TraceFence] Unable to start Agent profile server: \(error)")
        }
    }

    private func stopLocked() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.stateUpdateHandler = { state in
            if case .failed = state {
                connection.cancel()
            }
        }
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else {
                connection.cancel()
                return
            }
            guard let data,
                  let request = String(data: data, encoding: .utf8) else {
                self.send(status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Bad Request\n".utf8), on: connection)
                return
            }
            self.respond(to: request, on: connection)
        }
    }

    private func respond(to request: String, on connection: NWConnection) {
        guard let firstLine = request.split(separator: "\n", maxSplits: 1).first else {
            send(status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Bad Request\n".utf8), on: connection)
            return
        }

        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else {
            send(status: "400 Bad Request", contentType: "text/plain; charset=utf-8", body: Data("Bad Request\n".utf8), on: connection)
            return
        }

        let method = parts[0].uppercased()
        guard method == "GET" || method == "HEAD" else {
            send(status: "405 Method Not Allowed", contentType: "text/plain; charset=utf-8", body: Data("Method Not Allowed\n".utf8), on: connection)
            return
        }

        let path = normalizedRequestPath(String(parts[1]))
        if path == "/health" {
            let body = Data("""
            {"status":"ok","service":"tracefence-agent-profile","profile":"\(AgentGeoMirrorProfileAccess.profileID(activeProfileName))"}
            """.utf8)
            send(status: "200 OK", contentType: "application/json; charset=utf-8", body: method == "HEAD" ? Data() : body, on: connection)
            return
        }

        guard let route = route(for: path) else {
            send(status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Not Found\n".utf8), on: connection)
            return
        }

        guard fileManager.fileExists(atPath: route.url.path),
              let data = try? Data(contentsOf: route.url) else {
            send(status: "404 Not Found", contentType: "text/plain; charset=utf-8", body: Data("Profile Not Generated\n".utf8), on: connection)
            return
        }

        send(status: "200 OK", contentType: route.contentType, body: method == "HEAD" ? Data() : data, on: connection)
    }

    private func normalizedRequestPath(_ target: String) -> String {
        if let url = URL(string: target),
           let scheme = url.scheme,
           scheme.hasPrefix("http") {
            return url.path.isEmpty ? "/" : url.path
        }
        guard let questionMark = target.firstIndex(of: "?") else {
            return target.isEmpty ? "/" : target
        }
        let path = String(target[..<questionMark])
        return path.isEmpty ? "/" : path
    }

    private func route(for path: String) -> (url: URL, contentType: String)? {
        let parts = path.split(separator: "/").map(String.init)
        let activeProfileID = AgentGeoMirrorProfileAccess.profileID(activeProfileName)
        let resource: String

        if parts.count == 3, parts[0] == "profiles" {
            guard parts[1] == activeProfileID,
                  AgentGeoMirrorProfileAccess.profileID(parts[1]) == parts[1] else {
                return nil
            }
            resource = parts[2]
        } else if parts == [".well-known", "tracefence-profile.json"] {
            resource = "agent-profile.json"
        } else if parts.isEmpty {
            resource = "agent-profile.md"
        } else {
            return nil
        }

        let rootURL = URL(fileURLWithPath: SandboxPaths.shared.dataDirectory)
            .appendingPathComponent("AgentGeoMirror", isDirectory: true)
            .appendingPathComponent(activeProfileID, isDirectory: true)

        switch resource {
        case "agent-profile.json", "profile":
            return (rootURL.appendingPathComponent("agent-profile.json"), "application/json; charset=utf-8")
        case "agent-profile.md", "context.md", "context":
            return (rootURL.appendingPathComponent("agent-profile.md"), "text/markdown; charset=utf-8")
        default:
            return nil
        }
    }

    private func send(status: String, contentType: String, body: Data, on connection: NWConnection) {
        let header = """
        HTTP/1.1 \(status)\r
        Content-Type: \(contentType)\r
        Content-Length: \(body.count)\r
        Cache-Control: no-store\r
        X-Content-Type-Options: nosniff\r
        Connection: close\r
        \r

        """
        var response = Data(header.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private extension AgentGeoMirrorProfile {
    func withUpdatedTimestamp() -> AgentGeoMirrorProfile {
        var copy = self
        copy.updatedAt = Date()
        return copy
    }
}

private struct IPAPIResponse: Decodable {
    let city: String?
    let region: String?
    let countryCode: String?
    let latitude: Double?
    let longitude: Double?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case city
        case region
        case countryCode = "country_code"
        case latitude
        case longitude
        case timezone
    }
}

private struct IPWhoIsResponse: Decodable {
    let success: Bool?
    let city: String?
    let region: String?
    let countryCode: String?
    let latitude: Double?
    let longitude: Double?
    let timezone: Timezone?

    struct Timezone: Decodable {
        let id: String?
    }

    enum CodingKeys: String, CodingKey {
        case success
        case city
        case region
        case countryCode = "country_code"
        case latitude
        case longitude
        case timezone
    }
}
