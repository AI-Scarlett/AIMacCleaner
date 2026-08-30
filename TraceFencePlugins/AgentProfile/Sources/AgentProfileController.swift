import AppKit
import Combine
import Foundation
import MacToolsPluginKit

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

private actor AgentProfileDiagnosticEngine {
    func run(configuration: AgentProfileConfiguration) async -> AgentProfileDiagnosticSnapshot {
        let directConfiguration = URLSessionConfiguration.ephemeral
        directConfiguration.connectionProxyDictionary = [
            "HTTPEnable": 0,
            "HTTPSEnable": 0
        ]
        let directSession = URLSession(configuration: directConfiguration)
        let directIP = try? await googleEgressIP(session: directSession)

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
                details: nil
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
                details: "invalid-proxy-url"
            )
        }

        async let proxyIPValue = optionalGoogleEgressIP(session: proxySession)
        async let geoValue = optionalGeo(session: proxySession)
        let (proxyIP, geo) = await (proxyIPValue, geoValue)
        let status = AgentProfilePolicy.classifyEgress(
            routeTrafficThroughProxy: true,
            proxyURLIsValid: true,
            directIP: directIP,
            proxyIP: proxyIP
        )
        return AgentProfileDiagnosticSnapshot(
            checkedAt: Date(),
            status: status,
            directGoogleIP: directIP,
            proxyGoogleIP: proxyIP,
            detectedCountryCode: geo?.countryCode?.uppercased(),
            detectedRegion: geo?.region,
            detectedCity: geo?.city,
            detectedTimezone: geo?.timezone,
            details: status == .sameAsDirect ? "google-egress-matches-direct" : nil
        )
    }

    private func optionalGoogleEgressIP(session: URLSession) async -> String? {
        try? await googleEgressIP(session: session)
    }

    private func optionalGeo(session: URLSession) async -> AgentProfileIPAPIResponse? {
        try? await geo(session: session)
    }

    private func googleEgressIP(session: URLSession) async throws -> String {
        let url = URL(string: "https://domains.google.com/checkip")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let value = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.count <= 128 else {
            throw URLError(.badServerResponse)
        }
        return value
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
        self.configuration = Self.loadConfiguration(from: context.storage)
        self.diagnostic = Self.loadDiagnostic(from: self.supportDirectory) ?? .empty
        self.lastGeneratedAssets = Self.existingAssets(
            supportDirectory: self.supportDirectory,
            profileName: self.configuration.name
        )
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
        let launchers = root.appendingPathComponent("Launchers", isDirectory: true)
        return AgentProfileGeneratedAssets(
            rootURL: root,
            profileURL: root.appendingPathComponent("agent-profile.json"),
            environmentURL: root.appendingPathComponent("agent-env.sh"),
            launchersURL: launchers,
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
        try FileManager.default.createDirectory(at: assets.launchersURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(configuration).write(to: assets.profileURL, options: .atomic)
        try environmentScript(configuration).write(to: assets.environmentURL, atomically: true, encoding: .utf8)
        try antigravityLauncher(configuration, profileRoot: assets.rootURL)
            .write(to: assets.antigravityLauncherURL, atomically: true, encoding: .utf8)
        try antigravityCLILauncher(profileRoot: assets.rootURL)
            .write(to: assets.antigravityCLILauncherURL, atomically: true, encoding: .utf8)
        try readme(configuration).write(to: assets.readmeURL, atomically: true, encoding: .utf8)
        for url in [assets.environmentURL, assets.antigravityLauncherURL, assets.antigravityCLILauncherURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        for url in [assets.profileURL, assets.readmeURL] {
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return assets
    }

    private static func environmentScript(_ value: AgentProfileConfiguration) -> String {
        let localeUnderscore = value.localeIdentifier.replacingOccurrences(of: "-", with: "_")
        var lines = [
            "#!/bin/zsh",
            "# Generated by the TraceFence Agent Profile plugin.",
            "export TRACEFENCE_AGENT_PROFILE=1",
            "export TRACEFENCE_COUNTRY=\(shellQuote(value.countryCode.uppercased()))",
            "export TRACEFENCE_REGION=\(shellQuote(value.region))",
            "export TRACEFENCE_CITY=\(shellQuote(value.city))",
            "export TRACEFENCE_TIMEZONE=\(shellQuote(value.timezoneIdentifier))",
            "export TRACEFENCE_LOCALE=\(shellQuote(value.localeIdentifier))",
            "export TRACEFENCE_LANGUAGES=\(shellQuote(value.languages))",
            "export TRACEFENCE_ACCEPT_LANGUAGE=\(shellQuote(value.acceptLanguage))",
            "export TZ=\(shellQuote(value.timezoneIdentifier))",
            "export LANG=\(shellQuote(localeUnderscore + ".UTF-8"))",
            "export LC_ALL=\(shellQuote(localeUnderscore + ".UTF-8"))"
        ]
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
        """
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

        The generated launchers align the process environment and, when proxy
        routing is enabled, disable QUIC and non-proxied WebRTC UDP for the
        Antigravity Chromium process.

        This is not proof of Google Antigravity eligibility. Google can evaluate
        the account country, age, plan, organization, payment profile, and other
        server-side signals. See https://antigravity.google/docs/faq.
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
        Direct Google IP: \(diagnostic.directGoogleIP ?? "unavailable")
        Proxy Google IP: \(diagnostic.proxyGoogleIP ?? "unavailable")
        Proxy geography: \([diagnostic.detectedCity, diagnostic.detectedRegion, diagnostic.detectedCountryCode].compactMap { $0 }.joined(separator: ", "))
        Proxy timezone: \(diagnostic.detectedTimezone ?? "unavailable")
        Profile locale: \(configuration.localeIdentifier)
        Profile timezone: \(configuration.timezoneIdentifier)
        Provider eligibility: not inferred; Google remains authoritative
        """
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
