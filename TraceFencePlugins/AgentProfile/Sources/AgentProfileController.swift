import AppKit
import Combine
import Foundation
import MacToolsPluginKit
import Network

private struct AgentProfileIPAPIResponse: Decodable, Sendable {
    let countryCode: String?
    let region: String?
    let city: String?
    let timezone: String?

    private enum CodingKeys: String, CodingKey {
        case countryCode = "country_code"
        case region
        case city
        case timezone
    }
}

struct AgentProfileCLIIntegration: Identifiable, Sendable {
    let id: String
    let displayName: String
    let commandName: String
    let launcherFileName: String

    static let supported: [Self] = [
        .init(id: "codex", displayName: "Codex CLI", commandName: "codex", launcherFileName: "Launch Codex CLI.command"),
        .init(id: "claude", displayName: "Claude Code", commandName: "claude", launcherFileName: "Launch Claude Code.command"),
        .init(id: "grok", displayName: "Grok CLI", commandName: "grok", launcherFileName: "Launch Grok CLI.command"),
        .init(id: "gemini", displayName: "Gemini CLI", commandName: "gemini", launcherFileName: "Launch Gemini CLI.command"),
        .init(id: "antigravity", displayName: "Antigravity CLI", commandName: "agy", launcherFileName: "Launch Antigravity CLI with Agent Profile.command"),
        .init(id: "cursor-agent", displayName: "Cursor Agent", commandName: "cursor-agent", launcherFileName: "Launch Cursor Agent.command"),
        .init(id: "opencode", displayName: "OpenCode", commandName: "opencode", launcherFileName: "Launch OpenCode.command"),
        .init(id: "aider", displayName: "Aider", commandName: "aider", launcherFileName: "Launch Aider.command"),
        .init(id: "amp", displayName: "Amp", commandName: "amp", launcherFileName: "Launch Amp.command"),
        .init(id: "goose", displayName: "Goose", commandName: "goose", launcherFileName: "Launch Goose.command"),
        .init(id: "qwen", displayName: "Qwen", commandName: "qwen", launcherFileName: "Launch Qwen.command"),
        .init(id: "openclaw", displayName: "OpenClaw", commandName: "openclaw", launcherFileName: "Launch OpenClaw.command"),
        .init(id: "hermes", displayName: "Hermes", commandName: "hermes", launcherFileName: "Launch Hermes.command"),
        .init(id: "minimax", displayName: "MiniMax Code", commandName: "minimax", launcherFileName: "Launch MiniMax Code.command"),
        .init(id: "kiro", displayName: "Kiro CLI", commandName: "kiro-cli", launcherFileName: "Launch Kiro CLI.command"),
        .init(id: "copilot", displayName: "GitHub Copilot CLI", commandName: "copilot", launcherFileName: "Launch Copilot CLI.command"),
        .init(id: "droid", displayName: "Factory Droid", commandName: "droid", launcherFileName: "Launch Droid.command"),
        .init(id: "dsh", displayName: "DeepSeek Harness", commandName: "dsh", launcherFileName: "Launch DeepSeek Harness.command")
    ]
}

struct AgentProfileDesktopIntegration: Identifiable, Sendable {
    let id: String
    let displayName: String
    let appNames: [String]
    let executableName: String
    let launcherFileName: String
    let usesChromiumNetworkArguments: Bool

    static let supported: [Self] = [
        .init(id: "codex", displayName: "Codex", appNames: ["Codex"], executableName: "Codex", launcherFileName: "Launch Codex.command", usesChromiumNetworkArguments: false),
        .init(id: "claude", displayName: "Claude", appNames: ["Claude"], executableName: "Claude", launcherFileName: "Launch Claude.command", usesChromiumNetworkArguments: false),
        .init(id: "cursor", displayName: "Cursor", appNames: ["Cursor"], executableName: "Cursor", launcherFileName: "Launch Cursor.command", usesChromiumNetworkArguments: false),
        .init(id: "windsurf", displayName: "Windsurf", appNames: ["Windsurf"], executableName: "Windsurf", launcherFileName: "Launch Windsurf.command", usesChromiumNetworkArguments: false),
        .init(id: "vscode", displayName: "Visual Studio Code", appNames: ["Visual Studio Code"], executableName: "Electron", launcherFileName: "Launch Visual Studio Code.command", usesChromiumNetworkArguments: false),
        .init(id: "chatgpt", displayName: "ChatGPT", appNames: ["ChatGPT"], executableName: "ChatGPT", launcherFileName: "Launch ChatGPT.command", usesChromiumNetworkArguments: false),
        .init(id: "warp", displayName: "Warp", appNames: ["Warp"], executableName: "Warp", launcherFileName: "Launch Warp.command", usesChromiumNetworkArguments: false),
        .init(id: "zed", displayName: "Zed", appNames: ["Zed"], executableName: "Zed", launcherFileName: "Launch Zed.command", usesChromiumNetworkArguments: false),
        .init(id: "antigravity", displayName: "Google Antigravity", appNames: ["Antigravity", "Google Antigravity"], executableName: "Antigravity", launcherFileName: "Launch Antigravity with Agent Profile.command", usesChromiumNetworkArguments: true),
        .init(id: "trae", displayName: "Trae", appNames: ["Trae", "Trae CN"], executableName: "Trae", launcherFileName: "Launch Trae.command", usesChromiumNetworkArguments: false)
    ]
}

private actor AgentProfileDiagnosticEngine {
    func run(configuration: AgentProfileConfiguration) async -> AgentProfileDiagnosticSnapshot {
        let localTunnelDetected = AgentProfileLocalProxyDiscovery.clashTUNIsEnabled()
        let directConfiguration = URLSessionConfiguration.ephemeral
        directConfiguration.connectionProxyDictionary = [
            "HTTPEnable": 0,
            "HTTPSEnable": 0
        ]
        let directSession = URLSession(configuration: directConfiguration)
        let directIP = try? await egressIP(session: directSession)

        guard configuration.routeTrafficThroughProxy else {
            return AgentProfileDiagnosticSnapshot(
                checkedAt: Date(),
                status: .proxyDisabled,
                directGoogleIP: directIP,
                proxyGoogleIP: nil,
                detectedCountryCode: nil,
                detectedRegion: nil,
                detectedCity: nil,
                detectedTimezone: nil,
                details: nil,
                localTunnelDetected: localTunnelDetected
            )
        }

        guard let proxySession = proxySession(rawURL: configuration.proxyURL) else {
            return AgentProfileDiagnosticSnapshot(
                checkedAt: Date(),
                status: .proxyInvalid,
                directGoogleIP: directIP,
                proxyGoogleIP: nil,
                detectedCountryCode: nil,
                detectedRegion: nil,
                detectedCity: nil,
                detectedTimezone: nil,
                details: "invalid-proxy-url",
                localTunnelDetected: localTunnelDetected
            )
        }

        async let proxyIPValue = optionalEgressIP(session: proxySession)
        async let geoValue = optionalGeo(session: proxySession)
        let (proxyIP, geo) = await (proxyIPValue, geoValue)
        let status = AgentProfilePolicy.classifyEgress(
            routeTrafficThroughProxy: true,
            proxyURLIsValid: true,
            directIP: directIP,
            proxyIP: proxyIP,
            localTunnelDetected: localTunnelDetected
        )
        let matchingEgressWithTunnel = directIP.flatMap { direct in
            proxyIP.map { $0 == direct }
        } == true && localTunnelDetected
        return AgentProfileDiagnosticSnapshot(
            checkedAt: Date(),
            status: status,
            directGoogleIP: directIP,
            proxyGoogleIP: proxyIP,
            detectedCountryCode: geo?.countryCode?.uppercased(),
            detectedRegion: geo?.region,
            detectedCity: geo?.city,
            detectedTimezone: geo?.timezone,
            details: matchingEgressWithTunnel
                ? "default-egress-matches-explicit-proxy-tun-active"
                : (status == .sameAsDirect ? "default-egress-matches-explicit-proxy" : nil),
            localTunnelDetected: localTunnelDetected
        )
    }

    private func optionalEgressIP(session: URLSession) async -> String? {
        try? await egressIP(session: session)
    }

    private func optionalGeo(session: URLSession) async -> AgentProfileIPAPIResponse? {
        try? await geo(session: session)
    }

    private func egressIP(session: URLSession) async throws -> String {
        let endpoints = [
            "https://api.ipify.org",
            "https://domains.google.com/checkip",
            "https://ifconfig.me/ip"
        ]
        for rawURL in endpoints {
            guard let url = URL(string: rawURL) else { continue }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let value = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  value.count <= 128 else { continue }
            return value
        }
        throw URLError(.cannotConnectToHost)
    }

    private func geo(session: URLSession) async throws -> AgentProfileIPAPIResponse {
        let url = URL(string: "https://ipapi.co/json/")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(AgentProfileIPAPIResponse.self, from: data)
    }

    private func proxySession(rawURL: String) -> URLSession? {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              !host.isEmpty,
              let port = url.port else {
            return nil
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return nil }
        configuration.proxyConfigurations = [
            ProxyConfiguration(
                httpCONNECTProxy: .hostPort(
                    host: NWEndpoint.Host(host),
                    port: nwPort
                )
            )
        ]
        // Retain the CFNetwork dictionary for macOS builds where an older
        // Foundation implementation still consults it. The Network.framework
        // proxy configuration above is authoritative on supported hosts.
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 1,
            "HTTPProxy": host,
            "HTTPPort": port,
            "HTTPSEnable": 1,
            "HTTPSProxy": host,
            "HTTPSPort": port
        ]
        return URLSession(configuration: configuration)
    }
}

private enum AgentProfileLocalProxyDiscovery {
    static func detectedProxyURL() -> String? {
        for url in clashConfigurationURLs() {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let port = firstIntegerValue(named: "mixed-port", in: text),
                  (1...65_535).contains(port) else { continue }
            return "http://127.0.0.1:\(port)"
        }
        return nil
    }

    static func clashTUNIsEnabled() -> Bool {
        for url in clashConfigurationURLs() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            var insideTUN = false
            for rawLine in text.split(whereSeparator: \.isNewline) {
                let line = String(rawLine)
                if !line.first.map({ $0 == " " || $0 == "\t" })! {
                    insideTUN = line.trimmingCharacters(in: .whitespaces) == "tun:"
                    continue
                }
                guard insideTUN else { continue }
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed == "enable: true" { return true }
            }
        }
        return false
    }

    private static func clashConfigurationURLs() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent("Library/Application Support/io.github.clash-verge-rev.clash-verge-rev/clash-verge.yaml"),
            home.appendingPathComponent("Library/Application Support/com.follow.clash/config.yaml")
        ]
    }

    private static func firstIntegerValue(named key: String, in text: String) -> Int? {
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("\(key):") else { continue }
            return Int(line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }
}

@MainActor
final class AgentProfileController: ObservableObject {
    @Published var configuration: AgentProfileConfiguration {
        didSet { saveConfiguration() }
    }
    @Published private(set) var diagnostic = AgentProfileDiagnosticSnapshot.empty
    @Published private(set) var isDiagnosing = false
    @Published private(set) var isGenerating = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastGeneratedAssets: AgentProfileGeneratedAssets?

    private let storage: any PluginStorage
    private let supportDirectory: URL
    private let diagnosticEngine = AgentProfileDiagnosticEngine()
    private var diagnosticTask: Task<Void, Never>?

    init(context: PluginRuntimeContext) {
        self.storage = context.storage
        self.supportDirectory = context.supportDirectory
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/TraceFence/Plugins/Data/tracefence.tools.agent-profile", isDirectory: true)
        Self.copyLegacySettingsIfNeeded(to: context.storage)
        var loadedConfiguration = Self.loadConfiguration(from: context.storage)
        if loadedConfiguration.proxyURL == AgentProfileConfiguration.defaultValue.proxyURL,
           let detectedProxyURL = AgentProfileLocalProxyDiscovery.detectedProxyURL(),
           detectedProxyURL != loadedConfiguration.proxyURL {
            loadedConfiguration.proxyURL = detectedProxyURL
        }
        self.configuration = loadedConfiguration
        self.diagnostic = Self.loadDiagnostic(from: self.supportDirectory) ?? .empty
        self.lastGeneratedAssets = Self.existingAssets(
            supportDirectory: self.supportDirectory,
            profileName: self.configuration.name
        )
        if let data = try? JSONEncoder().encode(loadedConfiguration) {
            context.storage.set(data, forKey: "configuration-v1")
        }
    }

    deinit {
        diagnosticTask?.cancel()
    }

    var antigravityInstallationSummary: String {
        let appExists = FileManager.default.fileExists(atPath: "/Applications/Antigravity.app")
            || FileManager.default.fileExists(
                atPath: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Applications/Antigravity.app").path
            )
        let cliExists = FileManager.default.isExecutableFile(
            atPath: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/agy").path
        )
        switch (appExists, cliExists) {
        case (true, true): return "app+cli"
        case (true, false): return "app"
        case (false, true): return "cli"
        case (false, false): return "missing"
        }
    }

    var installedDesktopIntegrations: [AgentProfileDesktopIntegration] {
        AgentProfileDesktopIntegration.supported.filter { Self.applicationURL(for: $0) != nil }
    }

    var installedCLIIntegrations: [AgentProfileCLIIntegration] {
        AgentProfileCLIIntegration.supported.filter { Self.commandURL(named: $0.commandName) != nil }
    }

    var integrationSummary: String {
        "desktop:\(installedDesktopIntegrations.count),cli:\(installedCLIIntegrations.count)"
    }

    func setEnabled(_ enabled: Bool) {
        configuration.enabled = enabled
        if enabled {
            generateAssets()
        }
    }

    func runDiagnostics() {
        diagnosticTask?.cancel()
        isDiagnosing = true
        statusMessage = nil
        let current = configuration
        diagnosticTask = Task { [weak self] in
            guard let self else { return }
            let result = await diagnosticEngine.run(configuration: current)
            guard !Task.isCancelled else { return }
            diagnostic = result
            isDiagnosing = false
            persistDiagnostic(result)
            objectWillChange.send()
        }
    }

    func cancelDiagnostics() {
        diagnosticTask?.cancel()
        diagnosticTask = nil
        isDiagnosing = false
    }

    func applyDetectedLocation() {
        guard diagnostic.status == .routed else { return }
        if let value = diagnostic.detectedCountryCode, !value.isEmpty {
            configuration.countryCode = value
        }
        if let value = diagnostic.detectedRegion, !value.isEmpty {
            configuration.region = value
        }
        if let value = diagnostic.detectedCity, !value.isEmpty {
            configuration.city = value
        }
        if let value = diagnostic.detectedTimezone, TimeZone(identifier: value) != nil {
            configuration.timezoneIdentifier = value
        }
        generateAssets()
    }

    func generateAssets() {
        isGenerating = true
        defer { isGenerating = false }
        do {
            lastGeneratedAssets = try Self.writeAssets(
                configuration: configuration,
                supportDirectory: supportDirectory
            )
            statusMessage = "generated"
        } catch {
            statusMessage = "generation-failed:\(error.localizedDescription)"
        }
    }

    func openGeneratedFolder() {
        if lastGeneratedAssets == nil { generateAssets() }
        guard let rootURL = lastGeneratedAssets?.rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([rootURL])
    }

    func launchAntigravity() {
        if lastGeneratedAssets == nil { generateAssets() }
        guard let launcher = lastGeneratedAssets?.antigravityLauncherURL else { return }
        NSWorkspace.shared.open(launcher)
    }

    func launchAntigravityCLI() {
        if lastGeneratedAssets == nil { generateAssets() }
        guard let launcher = lastGeneratedAssets?.antigravityCLILauncherURL else { return }
        NSWorkspace.shared.open(launcher)
    }

    func launchDesktop(_ integration: AgentProfileDesktopIntegration) {
        if lastGeneratedAssets == nil { generateAssets() }
        guard let root = lastGeneratedAssets?.launchersURL else { return }
        NSWorkspace.shared.open(root.appendingPathComponent(integration.launcherFileName))
    }

    func launchCLI(_ integration: AgentProfileCLIIntegration) {
        if lastGeneratedAssets == nil { generateAssets() }
        guard let root = lastGeneratedAssets?.launchersURL else { return }
        NSWorkspace.shared.open(root.appendingPathComponent(integration.launcherFileName))
    }

    func launchProfileShell() {
        if lastGeneratedAssets == nil { generateAssets() }
        guard let launcher = lastGeneratedAssets?.shellLauncherURL else { return }
        NSWorkspace.shared.open(launcher)
    }

    func openBrowserExtensionFolder() {
        if lastGeneratedAssets == nil { generateAssets() }
        guard let url = lastGeneratedAssets?.browserExtensionURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func openProfileContext() {
        if lastGeneratedAssets == nil { generateAssets() }
        guard let url = lastGeneratedAssets?.contextURL else { return }
        NSWorkspace.shared.open(url)
    }

    func copyProfilePath() {
        if lastGeneratedAssets == nil { generateAssets() }
        guard let assets = lastGeneratedAssets else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(assets.profileURL.path, forType: .string)
        statusMessage = "profile-path-copied"
    }

    func openOfficialAvailability() {
        guard let url = URL(string: "https://antigravity.google/docs/faq") else { return }
        NSWorkspace.shared.open(url)
    }

    func openOfficialCLIAuthentication() {
        guard let url = URL(string: "https://antigravity.google/docs/cli/install/#using-a-gemini-api-key") else { return }
        NSWorkspace.shared.open(url)
    }

    func copyDiagnosticReport() {
        let report = Self.diagnosticReport(configuration: configuration, diagnostic: diagnostic)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        statusMessage = "copied"
    }

    private func saveConfiguration() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        storage.set(data, forKey: "configuration-v1")
    }

    private func persistDiagnostic(_ snapshot: AgentProfileDiagnosticSnapshot) {
        do {
            try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(
                to: supportDirectory.appendingPathComponent("diagnostic-v1.json"),
                options: .atomic
            )
        } catch {
            statusMessage = "diagnostic-cache-failed"
        }
    }

    private static func loadConfiguration(from storage: any PluginStorage) -> AgentProfileConfiguration {
        guard let data = storage.data(forKey: "configuration-v1"),
              let value = try? JSONDecoder().decode(AgentProfileConfiguration.self, from: data) else {
            return .defaultValue
        }
        return value
    }

    private static func copyLegacySettingsIfNeeded(to storage: any PluginStorage) {
        guard storage.object(forKey: "configuration-v1") == nil else { return }
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: "agentGeoMirrorEnabled") != nil else { return }
        var value = AgentProfileConfiguration.defaultValue
        value.enabled = defaults.bool(forKey: "agentGeoMirrorEnabled")
        value.name = defaults.string(forKey: "agentGeoMirrorProfileName") ?? value.name
        value.proxyURL = defaults.string(forKey: "agentGeoMirrorProxyURL") ?? value.proxyURL
        value.noProxy = defaults.string(forKey: "agentGeoMirrorNoProxy") ?? value.noProxy
        value.routeTrafficThroughProxy = defaults.bool(forKey: "agentGeoMirrorRouteTrafficThroughProxy")
        value.countryCode = defaults.string(forKey: "agentGeoMirrorCountryCode") ?? value.countryCode
        value.region = defaults.string(forKey: "agentGeoMirrorRegion") ?? value.region
        value.city = defaults.string(forKey: "agentGeoMirrorCity") ?? value.city
        value.timezoneIdentifier = defaults.string(forKey: "agentGeoMirrorTimezone") ?? value.timezoneIdentifier
        value.localeIdentifier = defaults.string(forKey: "agentGeoMirrorLocale") ?? value.localeIdentifier
        value.languages = defaults.string(forKey: "agentGeoMirrorLanguages") ?? value.languages
        value.acceptLanguage = defaults.string(forKey: "agentGeoMirrorAcceptLanguage") ?? value.acceptLanguage
        if defaults.object(forKey: "agentGeoMirrorLatitude") != nil {
            value.latitude = defaults.double(forKey: "agentGeoMirrorLatitude")
        }
        if defaults.object(forKey: "agentGeoMirrorLongitude") != nil {
            value.longitude = defaults.double(forKey: "agentGeoMirrorLongitude")
        }
        if defaults.object(forKey: "agentGeoMirrorAccuracy") != nil {
            value.accuracyMeters = defaults.double(forKey: "agentGeoMirrorAccuracy")
        }
        if defaults.object(forKey: "agentGeoMirrorLocationOverride") != nil {
            value.locationOverrideEnabled = defaults.bool(forKey: "agentGeoMirrorLocationOverride")
        }
        if defaults.object(forKey: "agentGeoMirrorTimezoneOverride") != nil {
            value.timezoneOverrideEnabled = defaults.bool(forKey: "agentGeoMirrorTimezoneOverride")
        }
        if defaults.object(forKey: "agentGeoMirrorLanguageOverride") != nil {
            value.languageOverrideEnabled = defaults.bool(forKey: "agentGeoMirrorLanguageOverride")
        }
        if defaults.object(forKey: "agentGeoMirrorAcceptLanguageOverride") != nil {
            value.acceptLanguageOverrideEnabled = defaults.bool(forKey: "agentGeoMirrorAcceptLanguageOverride")
        }
        if defaults.object(forKey: "agentGeoMirrorCLIWrappers") != nil {
            value.cliWrappersEnabled = defaults.bool(forKey: "agentGeoMirrorCLIWrappers")
        }
        if defaults.object(forKey: "agentGeoMirrorDesktopLaunchers") != nil {
            value.desktopLaunchersEnabled = defaults.bool(forKey: "agentGeoMirrorDesktopLaunchers")
        }
        if defaults.object(forKey: "agentGeoMirrorBrowserExtension") != nil {
            value.browserExtensionEnabled = defaults.bool(forKey: "agentGeoMirrorBrowserExtension")
        }
        if let data = try? JSONEncoder().encode(value) {
            storage.set(data, forKey: "configuration-v1")
        }
    }

    private static func loadDiagnostic(from directory: URL) -> AgentProfileDiagnosticSnapshot? {
        let url = directory.appendingPathComponent("diagnostic-v1.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AgentProfileDiagnosticSnapshot.self, from: data)
    }

    private static func existingAssets(
        supportDirectory: URL,
        profileName: String
    ) -> AgentProfileGeneratedAssets? {
        let assets = assetURLs(supportDirectory: supportDirectory, profileName: profileName)
        return FileManager.default.fileExists(atPath: assets.profileURL.path) ? assets : nil
    }

    private static func assetURLs(
        supportDirectory: URL,
        profileName: String
    ) -> AgentProfileGeneratedAssets {
        let safeName = profileName
            .unicodeScalars
            .map { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0) ? Character($0) : "-" }
        let normalized = String(safeName).trimmingCharacters(in: CharacterSet(charactersIn: "-_")).isEmpty
            ? "default"
            : String(safeName).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        let root = supportDirectory.appendingPathComponent("Profiles/\(normalized)", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let launchers = root.appendingPathComponent("Launchers", isDirectory: true)
        let extensionRoot = root.appendingPathComponent("BrowserExtension", isDirectory: true)
        return AgentProfileGeneratedAssets(
            rootURL: root,
            profileURL: root.appendingPathComponent("agent-profile.json"),
            contextURL: root.appendingPathComponent("agent-profile.md"),
            environmentURL: root.appendingPathComponent("agent-env.sh"),
            binURL: bin,
            launchersURL: launchers,
            browserExtensionURL: extensionRoot,
            shellLauncherURL: launchers.appendingPathComponent("Open TraceFence Agent Profile Shell.command"),
            antigravityLauncherURL: launchers.appendingPathComponent("Launch Antigravity with Agent Profile.command"),
            antigravityCLILauncherURL: launchers.appendingPathComponent("Launch Antigravity CLI with Agent Profile.command"),
            readmeURL: root.appendingPathComponent("README.md")
        )
    }

    private static func writeAssets(
        configuration: AgentProfileConfiguration,
        supportDirectory: URL
    ) throws -> AgentProfileGeneratedAssets {
        let assets = assetURLs(supportDirectory: supportDirectory, profileName: configuration.name)
        try FileManager.default.createDirectory(at: assets.rootURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assets.binURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assets.launchersURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: assets.browserExtensionURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: assets.profileURL, options: .atomic)
        try profileContext(configuration).write(to: assets.contextURL, atomically: true, encoding: .utf8)
        try environmentScript(configuration, assets: assets).write(to: assets.environmentURL, atomically: true, encoding: .utf8)
        if configuration.cliWrappersEnabled {
            try writeCLIIntegrations(assets: assets)
        }
        if configuration.desktopLaunchersEnabled {
            try writeDesktopIntegrations(configuration: configuration, assets: assets)
        }
        if configuration.browserExtensionEnabled {
            try writeBrowserExtension(configuration: configuration, assets: assets)
        }
        try readme(configuration).write(to: assets.readmeURL, atomically: true, encoding: .utf8)
        for url in [assets.environmentURL] {
            try setExecutable(url)
        }
        for url in [assets.profileURL, assets.contextURL, assets.readmeURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return assets
    }

    private static func environmentScript(
        _ value: AgentProfileConfiguration,
        assets: AgentProfileGeneratedAssets
    ) -> String {
        let localeUnderscore = value.localeIdentifier.replacingOccurrences(of: "-", with: "_")
        var lines = [
            "#!/bin/zsh",
            "# Generated by the TraceFence Agent Profile plugin.",
            "export TRACEFENCE_AGENT_PROFILE=1",
            "export TRACEFENCE_PROFILE_PATH=\(shellQuote(assets.profileURL.path))",
            "export TRACEFENCE_PROFILE_CONTEXT_PATH=\(shellQuote(assets.contextURL.path))",
            "export AGENT_PROFILE_PATH=\"$TRACEFENCE_PROFILE_PATH\"",
            "export AGENT_PROFILE_CONTEXT_PATH=\"$TRACEFENCE_PROFILE_CONTEXT_PATH\"",
            "export TRACEFENCE_PROFILE_BIN=\(shellQuote(assets.binURL.path))",
            "export TRACEFENCE_COUNTRY=\(shellQuote(value.countryCode.uppercased()))",
            "export TRACEFENCE_REGION=\(shellQuote(value.region))",
            "export TRACEFENCE_CITY=\(shellQuote(value.city))",
            "export TRACEFENCE_TIMEZONE=\(shellQuote(value.timezoneIdentifier))",
            "export TRACEFENCE_LOCALE=\(shellQuote(value.localeIdentifier))",
            "export TRACEFENCE_LANGUAGES=\(shellQuote(value.languages))",
            "export TRACEFENCE_ACCEPT_LANGUAGE=\(shellQuote(value.acceptLanguage))",
            "export TRACEFENCE_ROUTE_TRAFFIC_THROUGH_PROXY=\(shellQuote(value.enabled && value.routeTrafficThroughProxy ? "1" : "0"))",
            "export TRACEFENCE_LATITUDE=\(shellQuote(String(value.latitude)))",
            "export TRACEFENCE_LONGITUDE=\(shellQuote(String(value.longitude)))",
            "export TRACEFENCE_ACCURACY_METERS=\(shellQuote(String(value.accuracyMeters)))"
        ]
        if value.enabled && value.cliWrappersEnabled {
            lines.append("export PATH=\"$TRACEFENCE_PROFILE_BIN:$PATH\"")
        }
        if value.enabled && value.timezoneOverrideEnabled {
            lines.append("export TZ=\(shellQuote(value.timezoneIdentifier))")
        }
        if value.enabled && value.languageOverrideEnabled {
            lines.append("export LANG=\(shellQuote(localeUnderscore + ".UTF-8"))")
            lines.append("export LC_ALL=\(shellQuote(localeUnderscore + ".UTF-8"))")
            lines.append("export LANGUAGE=\(shellQuote(value.languages.replacingOccurrences(of: ",", with: ":")))")
            lines.append("export AppleLocale=\(shellQuote(localeUnderscore))")
            lines.append("export AppleLanguages=\(shellQuote(value.languages))")
        }
        if value.enabled && value.acceptLanguageOverrideEnabled {
            lines.append("export ACCEPT_LANGUAGE=\(shellQuote(value.acceptLanguage))")
        }
        if value.enabled && value.routeTrafficThroughProxy {
            let noProxy = normalizedNoProxy(value.noProxy)
            lines += [
                "export TRACEFENCE_PROFILE_PROXY_URL=\(shellQuote(value.proxyURL))",
                "export TRACEFENCE_PROFILE_NO_PROXY=\(shellQuote(noProxy))",
                "export HTTP_PROXY=\"$TRACEFENCE_PROFILE_PROXY_URL\"",
                "export HTTPS_PROXY=\"$TRACEFENCE_PROFILE_PROXY_URL\"",
                "export ALL_PROXY=\"$TRACEFENCE_PROFILE_PROXY_URL\"",
                "export http_proxy=\"$HTTP_PROXY\"",
                "export https_proxy=\"$HTTPS_PROXY\"",
                "export all_proxy=\"$ALL_PROXY\"",
                "export NO_PROXY=\"$TRACEFENCE_PROFILE_NO_PROXY\"",
                "export no_proxy=\"$NO_PROXY\""
            ]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func writeCLIIntegrations(assets: AgentProfileGeneratedAssets) throws {
        for integration in AgentProfileCLIIntegration.supported {
            let wrapper = cliWrapperScript(commandName: integration.commandName, profileRoot: assets.rootURL)
            let launcher = cliLauncherScript(integration: integration, profileRoot: assets.rootURL)
            let commandShim = assets.binURL.appendingPathComponent(integration.commandName)
            let namedWrapper = assets.binURL.appendingPathComponent("tf-\(integration.commandName)")
            try wrapper.write(to: commandShim, atomically: true, encoding: .utf8)
            try wrapper.write(to: namedWrapper, atomically: true, encoding: .utf8)
            try launcher.write(
                to: assets.launchersURL.appendingPathComponent(integration.launcherFileName),
                atomically: true,
                encoding: .utf8
            )
            try setExecutable(commandShim)
            try setExecutable(namedWrapper)
            try setExecutable(assets.launchersURL.appendingPathComponent(integration.launcherFileName))
        }

        let genericWrapper = """
        #!/bin/zsh
        set -e
        if [[ $# -lt 1 ]]; then
          echo "Usage: tf-agent <command> [args...]" >&2
          exit 64
        fi
        PROFILE_DIR=\(shellQuote(assets.rootURL.path))
        source "$PROFILE_DIR/agent-env.sh"
        exec "$@"
        """
        let genericURL = assets.binURL.appendingPathComponent("tf-agent")
        try genericWrapper.write(to: genericURL, atomically: true, encoding: .utf8)
        try setExecutable(genericURL)

        let shellLauncher = """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(assets.rootURL.path))
        source "$PROFILE_DIR/agent-env.sh"
        cd "$HOME"
        clear
        echo "TraceFence Agent Profile is active."
        echo "Profile: $TRACEFENCE_PROFILE_PATH"
        echo "Locale:  $TRACEFENCE_LOCALE"
        echo "Timezone: $TRACEFENCE_TIMEZONE"
        echo "Use codex, claude, grok, gemini, dsh, or another installed CLI normally."
        echo ""
        exec /bin/zsh
        """
        try shellLauncher.write(to: assets.shellLauncherURL, atomically: true, encoding: .utf8)
        try setExecutable(assets.shellLauncherURL)
    }

    private static func cliWrapperScript(commandName: String, profileRoot: URL) -> String {
        """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(profileRoot.path))
        source "$PROFILE_DIR/agent-env.sh"
        WRAPPER_DIR="$PROFILE_DIR/bin"
        path_parts=("${(@s/:/)PATH}")
        clean_parts=()
        for entry in "${path_parts[@]}"; do
          if [[ -n "$entry" && "$entry" != "$WRAPPER_DIR" ]]; then
            clean_parts+=("$entry")
          fi
        done
        SEARCH_PATH="${(j/:/)clean_parts}"
        REAL_COMMAND="$(PATH="$SEARCH_PATH" command -v \(commandName) || true)"
        if [[ -z "$REAL_COMMAND" && "\(commandName)" == "dsh" && -x "$HOME/deepseek-harness/apps/cli/lib/bin.js" ]]; then
          REAL_COMMAND="$HOME/deepseek-harness/apps/cli/lib/bin.js"
        fi
        if [[ -z "$REAL_COMMAND" || "$REAL_COMMAND" == "$WRAPPER_DIR/\(commandName)" ]]; then
          echo "TraceFence: command '\(commandName)' was not found outside the generated Agent Profile bin directory." >&2
          exit 127
        fi
        exec "$REAL_COMMAND" "$@"
        """
    }

    private static func cliLauncherScript(
        integration: AgentProfileCLIIntegration,
        profileRoot: URL
    ) -> String {
        """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(profileRoot.path))
        source "$PROFILE_DIR/agent-env.sh"
        clear
        echo "TraceFence Agent Profile is active."
        echo "Launching \(integration.displayName) with the configured locale, timezone, location metadata, and proxy policy."
        echo ""
        exec "$PROFILE_DIR/bin/tf-\(integration.commandName)" "$@"
        """
    }

    private static func writeDesktopIntegrations(
        configuration: AgentProfileConfiguration,
        assets: AgentProfileGeneratedAssets
    ) throws {
        for integration in AgentProfileDesktopIntegration.supported {
            let script = desktopLauncherScript(
                configuration: configuration,
                integration: integration,
                profileRoot: assets.rootURL
            )
            let url = assets.launchersURL.appendingPathComponent(integration.launcherFileName)
            try script.write(to: url, atomically: true, encoding: .utf8)
            try setExecutable(url)
        }
        let browsers = [
            ("Google Chrome", "Google Chrome"),
            ("Microsoft Edge", "Microsoft Edge"),
            ("Brave Browser", "Brave Browser"),
            ("Arc", "Arc"),
            ("Vivaldi", "Vivaldi")
        ]
        for (appName, executable) in browsers {
            let url = assets.launchersURL.appendingPathComponent("Launch \(appName) with Agent Profile.command")
            try browserLauncherScript(
                appName: appName,
                executable: executable,
                profileRoot: assets.rootURL
            ).write(to: url, atomically: true, encoding: .utf8)
            try setExecutable(url)
        }
    }

    private static func desktopLauncherScript(
        configuration: AgentProfileConfiguration,
        integration: AgentProfileDesktopIntegration,
        profileRoot: URL
    ) -> String {
        let appNames = integration.appNames.map { "  \(shellQuote($0))" }.joined(separator: "\n")
        let bypass = normalizedNoProxy(configuration.noProxy)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: ";")
        let networkSetup = integration.usesChromiumNetworkArguments ? """
        if [[ "${TRACEFENCE_ROUTE_TRAFFIC_THROUGH_PROXY:-0}" == "1" ]]; then
          APP_NETWORK_ARGS=(
            --proxy-server="$TRACEFENCE_PROFILE_PROXY_URL"
            --proxy-bypass-list=\(shellQuote(bypass))
            --disable-quic
            --force-webrtc-ip-handling-policy=disable_non_proxied_udp
          )
        fi
        """ : ""
        return """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(profileRoot.path))
        source "$PROFILE_DIR/agent-env.sh"
        APP_LOCALE_ARGS=()
        APP_NETWORK_ARGS=()
        \(networkSetup)
        if [[ -n "${TRACEFENCE_LOCALE:-}" ]]; then
          APP_LOCALE_ARGS=(--lang="$TRACEFENCE_LOCALE")
        fi
        APP_NAMES=(
        \(appNames)
        )
        for app_name in "${APP_NAMES[@]}"; do
          CANDIDATES=(
            "/Applications/$app_name.app/Contents/MacOS/\(integration.executableName)"
            "$HOME/Applications/$app_name.app/Contents/MacOS/\(integration.executableName)"
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
        echo "TraceFence: \(integration.displayName) is not installed." >&2
        exit 66
        """
    }

    private static func browserLauncherScript(
        appName: String,
        executable: String,
        profileRoot: URL
    ) -> String {
        """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(profileRoot.path))
        source "$PROFILE_DIR/agent-env.sh"
        EXTENSION_DIR="$PROFILE_DIR/BrowserExtension"
        USER_DATA_DIR="$PROFILE_DIR/BrowserProfiles/\(appName.replacingOccurrences(of: " ", with: "-"))"
        mkdir -p "$USER_DATA_DIR"
        PROXY_ARGS=()
        if [[ -n "${TRACEFENCE_PROFILE_PROXY_URL:-}" ]]; then
          PROXY_ARGS=(--proxy-server="$TRACEFENCE_PROFILE_PROXY_URL" --disable-quic --force-webrtc-ip-handling-policy=disable_non_proxied_udp)
        fi
        CANDIDATES=(
          "/Applications/\(appName).app/Contents/MacOS/\(executable)"
          "$HOME/Applications/\(appName).app/Contents/MacOS/\(executable)"
        )
        for candidate in "${CANDIDATES[@]}"; do
          if [[ -x "$candidate" ]]; then
            exec "$candidate" --user-data-dir="$USER_DATA_DIR" --load-extension="$EXTENSION_DIR" --lang="$TRACEFENCE_LOCALE" --accept-lang="$TRACEFENCE_ACCEPT_LANGUAGE" "${PROXY_ARGS[@]}" "$@"
          fi
        done
        echo "TraceFence: \(appName) is not installed." >&2
        exit 66
        """
    }

    private static func writeBrowserExtension(
        configuration: AgentProfileConfiguration,
        assets: AgentProfileGeneratedAssets
    ) throws {
        let manifest = """
        {
          "manifest_version": 3,
          "name": "TraceFence Agent Profile",
          "description": "Local language, timezone, and coarse-location profile generated by TraceFence.",
          "version": "1.1.1",
          "permissions": ["declarativeNetRequest"],
          "host_permissions": ["<all_urls>"],
          "background": { "service_worker": "background.js" },
          "content_scripts": [{
            "matches": ["<all_urls>"],
            "js": ["profile.js", "content_bridge.js"],
            "run_at": "document_start",
            "all_frames": true
          }],
          "web_accessible_resources": [{
            "resources": ["main_injector.js"],
            "matches": ["<all_urls>"]
          }],
          "action": { "default_title": "TraceFence Agent Profile" }
        }
        """
        let profileJSON = try browserProfileJSON(configuration)
        let profileJS = "globalThis.TRACEFENCE_AGENT_PROFILE = \(profileJSON);\n"
        let acceptLanguage = javascriptString(configuration.acceptLanguage)
        let background = """
        importScripts("profile.js");
        const RULE_ID = 270801;
        async function syncHeaders() {
          const profile = globalThis.TRACEFENCE_AGENT_PROFILE || {};
          const addRules = profile.enabled && profile.acceptLanguageOverrideEnabled ? [{
            id: RULE_ID,
            priority: 1,
            action: { type: "modifyHeaders", requestHeaders: [{ header: "Accept-Language", operation: "set", value: \(acceptLanguage) }] },
            condition: { urlFilter: "|http", resourceTypes: ["main_frame", "sub_frame", "xmlhttprequest", "script", "other"] }
          }] : [];
          await chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds: [RULE_ID], addRules });
        }
        chrome.runtime.onInstalled.addListener(syncHeaders);
        chrome.runtime.onStartup.addListener(syncHeaders);
        syncHeaders();
        """
        let bridge = """
        (() => {
          const profile = globalThis.TRACEFENCE_AGENT_PROFILE;
          if (!profile || !profile.enabled) return;
          const script = document.createElement("script");
          script.src = chrome.runtime.getURL("main_injector.js");
          script.dataset.traceFenceProfile = JSON.stringify(profile);
          script.onload = () => script.remove();
          (document.documentElement || document.head || document).prepend(script);
        })();
        """
        try manifest.write(to: assets.browserExtensionURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try profileJS.write(to: assets.browserExtensionURL.appendingPathComponent("profile.js"), atomically: true, encoding: .utf8)
        try background.write(to: assets.browserExtensionURL.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)
        try bridge.write(to: assets.browserExtensionURL.appendingPathComponent("content_bridge.js"), atomically: true, encoding: .utf8)
        try browserMainInjector().write(to: assets.browserExtensionURL.appendingPathComponent("main_injector.js"), atomically: true, encoding: .utf8)
    }

    private static func browserMainInjector() -> String {
        """
        (() => {
          const raw = document.currentScript?.dataset?.traceFenceProfile;
          if (!raw) return;
          let profile;
          try { profile = JSON.parse(raw); } catch (_) { return; }
          if (!profile.enabled) return;
          const defineGetter = (target, key, getter) => {
            try { Object.defineProperty(target, key, { configurable: true, get: getter }); } catch (_) {}
          };
          if (profile.languageOverrideEnabled) {
            defineGetter(Navigator.prototype, "language", () => profile.localeIdentifier);
            defineGetter(Navigator.prototype, "languages", () => profile.languages.slice());
          }
          if (profile.locationOverrideEnabled && navigator.geolocation) {
            const position = () => ({ coords: {
              latitude: Number(profile.latitude), longitude: Number(profile.longitude), accuracy: Number(profile.accuracyMeters),
              altitude: null, altitudeAccuracy: null, heading: null, speed: null
            }, timestamp: Date.now() });
            navigator.geolocation.getCurrentPosition = success => setTimeout(() => success(position()), 0);
            navigator.geolocation.watchPosition = success => { success(position()); return 1; };
            navigator.geolocation.clearWatch = () => {};
          }
          if (profile.timezoneOverrideEnabled) {
            const NativeDateTimeFormat = Intl.DateTimeFormat;
            Intl.DateTimeFormat = function(locales, options) {
              const resolvedLocales = locales ?? (profile.languageOverrideEnabled ? profile.localeIdentifier : locales);
              const resolvedOptions = Object.assign({}, options || {});
              if (!resolvedOptions.timeZone) resolvedOptions.timeZone = profile.timezoneIdentifier;
              return new NativeDateTimeFormat(resolvedLocales, resolvedOptions);
            };
            Intl.DateTimeFormat.prototype = NativeDateTimeFormat.prototype;
            Object.setPrototypeOf(Intl.DateTimeFormat, NativeDateTimeFormat);
          }
        })();
        """
    }

    private static func browserProfileJSON(_ value: AgentProfileConfiguration) throws -> String {
        let dictionary: [String: Any] = [
            "enabled": value.enabled,
            "countryCode": value.countryCode.uppercased(),
            "region": value.region,
            "city": value.city,
            "timezoneIdentifier": value.timezoneIdentifier,
            "localeIdentifier": value.localeIdentifier,
            "languages": value.languages.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) },
            "acceptLanguage": value.acceptLanguage,
            "latitude": value.latitude,
            "longitude": value.longitude,
            "accuracyMeters": value.accuracyMeters,
            "locationOverrideEnabled": value.locationOverrideEnabled,
            "timezoneOverrideEnabled": value.timezoneOverrideEnabled,
            "languageOverrideEnabled": value.languageOverrideEnabled,
            "acceptLanguageOverrideEnabled": value.acceptLanguageOverrideEnabled
        ]
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func javascriptString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else { return "\"\"" }
        return String(json.dropFirst().dropLast())
    }

    private static func profileContext(_ value: AgentProfileConfiguration) -> String {
        """
        # TraceFence Agent Profile

        This is a provider-neutral local profile for Agent processes.

        - Profile: \(value.name)
        - Country: \(value.countryCode.uppercased())
        - Region: \(value.region)
        - City: \(value.city)
        - Timezone: \(value.timezoneIdentifier)
        - Locale: \(value.localeIdentifier)
        - Languages: \(value.languages)
        - Accept-Language: \(value.acceptLanguage)
        - Coarse location: \(value.latitude), \(value.longitude) (+/- \(value.accuracyMeters)m)
        - Proxy routing: \(value.routeTrafficThroughProxy ? "enabled" : "disabled")

        Supported launchers include Codex, Claude, Grok, Gemini, Antigravity, Cursor, OpenCode, DeepSeek Harness, and other detected Agents. Provider account eligibility is separate from this local process profile.
        """
    }

    private static func setExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func antigravityLauncher(
        _ value: AgentProfileConfiguration,
        profileRoot: URL
    ) -> String {
        let bypass = normalizedNoProxy(value.noProxy)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: ";")
        let networkArguments = value.enabled && value.routeTrafficThroughProxy ? """
        NETWORK_ARGS=(
          --proxy-server="$TRACEFENCE_PROFILE_PROXY_URL"
          --proxy-bypass-list=\(shellQuote(bypass))
          --disable-quic
          --force-webrtc-ip-handling-policy=disable_non_proxied_udp
        )
        """ : "NETWORK_ARGS=()"
        return """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(profileRoot.path))
        source "$PROFILE_DIR/agent-env.sh"
        \(networkArguments)
        CANDIDATES=(
          "/Applications/Antigravity.app/Contents/MacOS/Antigravity"
          "$HOME/Applications/Antigravity.app/Contents/MacOS/Antigravity"
        )
        for candidate in "${CANDIDATES[@]}"; do
          if [[ -x "$candidate" ]]; then
            exec "$candidate" --lang="$TRACEFENCE_LOCALE" "${NETWORK_ARGS[@]}" "$@"
          fi
        done
        echo "TraceFence: Antigravity.app was not found." >&2
        exit 66
        """
    }

    private static func antigravityCLILauncher(profileRoot: URL) -> String {
        return """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(profileRoot.path))
        source "$PROFILE_DIR/agent-env.sh"
        AGY="$HOME/.local/bin/agy"
        if [[ ! -x "$AGY" ]]; then
          AGY="$(command -v agy || true)"
        fi
        if [[ -z "$AGY" || ! -x "$AGY" ]]; then
          echo "TraceFence: Antigravity CLI (agy) was not found." >&2
          exit 127
        fi
        echo "TraceFence Agent Profile: network and locale profile loaded."
        echo "Google remains authoritative for account and region eligibility."
        exec "$AGY" "$@"
        """
    }

    private static func readme(_ value: AgentProfileConfiguration) -> String {
        """
        # TraceFence Agent Profile

        Profile: \(value.name)
        Locale: \(value.localeIdentifier)
        Timezone: \(value.timezoneIdentifier)
        Configured country: \(value.countryCode.uppercased())
        Proxy routing: \(value.routeTrafficThroughProxy ? "enabled" : "disabled")

        This is a provider-neutral Agent profile. It generates:

        - CLI wrappers for Codex, Claude, Grok, Gemini, Antigravity, Cursor Agent,
          OpenCode, Aider, Amp, Goose, Qwen, OpenClaw, Hermes, MiniMax, Kiro,
          Copilot, Factory Droid, and DeepSeek Harness.
        - Desktop launchers for Codex, Claude, Cursor, Windsurf, VS Code, ChatGPT,
          Warp, Zed, Antigravity, and Trae.
        - Chromium launchers and an unpacked extension for language, timezone,
          coarse location, Accept-Language, and optional proxy routing.
        - `agent-profile.json`, `agent-profile.md`, and `agent-env.sh` for new
          Agents that can consume a local profile without a dedicated launcher.

        Provider-specific checks, such as Google Antigravity account eligibility,
        are diagnostic modules inside this general profile and do not replace the
        common Agent integrations.
        """
    }

    private static func diagnosticReport(
        configuration: AgentProfileConfiguration,
        diagnostic: AgentProfileDiagnosticSnapshot
    ) -> String {
        """
        TraceFence Agent Profile diagnostic
        Checked: \(diagnostic.checkedAt.formatted(.iso8601))
        Egress status: \(diagnostic.status.rawValue)
        Default-path Google IP: \(diagnostic.directGoogleIP ?? "unavailable")
        Proxy Google IP: \(diagnostic.proxyGoogleIP ?? "unavailable")
        Local TUN detected: \(diagnostic.localTunnelDetected == true ? "yes" : "no")
        Proxy geography: \([diagnostic.detectedCity, diagnostic.detectedRegion, diagnostic.detectedCountryCode].compactMap { $0 }.joined(separator: ", "))
        Proxy timezone: \(diagnostic.detectedTimezone ?? "unavailable")
        Profile locale: \(configuration.localeIdentifier)
        Profile timezone: \(configuration.timezoneIdentifier)
        Provider eligibility: not inferred; each Provider remains authoritative
        """
    }

    private static func applicationURL(for integration: AgentProfileDesktopIntegration) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in roots {
            for name in integration.appNames {
                let candidate = root.appendingPathComponent("\(name).app", isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }

    private static func commandURL(named command: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if command == "dsh" {
            let harness = home.appendingPathComponent("deepseek-harness/apps/cli/lib/bin.js")
            if FileManager.default.isExecutableFile(atPath: harness.path) { return harness }
        }
        var directories = [
            home.appendingPathComponent(".local/bin", isDirectory: true),
            home.appendingPathComponent(".grok/bin", isDirectory: true),
            home.appendingPathComponent(".npm-global/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/bin", isDirectory: true),
            URL(fileURLWithPath: "/bin", isDirectory: true)
        ]
        directories += ProcessInfo.processInfo.environment["PATH", default: ""]
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
        return directories
            .map { $0.appendingPathComponent(command) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    private static func normalizedNoProxy(_ rawValue: String) -> String {
        var values = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for required in ["localhost", "127.0.0.1", "::1"] where !values.contains(required) {
            values.append(required)
        }
        return values.joined(separator: ",")
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
