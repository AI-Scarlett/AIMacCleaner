import Foundation
import Darwin
import SwiftUI

struct ProviderQuotaWindow: Identifiable, Codable {
    enum Kind: String, Codable {
        case fiveHour
        case weekly
        case monthly
        case extra
    }

    let id: String
    let kind: Kind
    let title: String
    let usedPercent: Double
    let resetsAt: Date?
    let windowMinutes: Int?

    var remainingPercent: Double {
        max(0, min(100, 100 - usedPercent))
    }
}

struct ProviderQuotaSnapshot: Identifiable, Codable {
    let id: String
    let providerName: String
    let planName: String?
    let accountLabel: String?
    let credits: Double?
    let windows: [ProviderQuotaWindow]
    let resetCredits: ProviderQuotaResetCredits?
    let updatedAt: Date
    let source: String
    let errorMessage: String?
    let setupHint: String?
    let isSetupNotice: Bool

    var tightestWindow: ProviderQuotaWindow? {
        windows.min { lhs, rhs in
            lhs.remainingPercent < rhs.remainingPercent
        }
    }
}

struct ProviderQuotaResetCredits: Codable {
    let availableCount: Int
    let credits: [ProviderQuotaResetCredit]
    let updatedAt: Date

    var nextExpiringAvailableCredit: ProviderQuotaResetCredit? {
        credits
            .filter { $0.status == .available && ($0.expiresAt ?? .distantPast) > updatedAt }
            .min { lhs, rhs in
                guard let lhsDate = lhs.expiresAt else { return false }
                guard let rhsDate = rhs.expiresAt else { return true }
                return lhsDate < rhsDate
            }
    }
}

struct ProviderQuotaResetCredit: Identifiable, Codable {
    enum Status: String, Codable {
        case available
        case redeeming
        case redeemed
        case expired
        case unknown

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    let id: String
    let resetType: String
    let status: Status
    let grantedAt: Date?
    let expiresAt: Date?
    let redeemStartedAt: Date?
    let redeemedAt: Date?
    let title: String?
    let description: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case resetType = "reset_type"
        case status
        case grantedAt = "granted_at"
        case expiresAt = "expires_at"
        case redeemStartedAt = "redeem_started_at"
        case redeemedAt = "redeemed_at"
        case title
        case description
    }
}

final class ProviderQuotaService: ObservableObject {
    @Published private(set) var snapshots: [ProviderQuotaSnapshot] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshDate: Date?

    private let provider = CodexBarQuotaProvider()
    private var timer: Timer?

    var menuBarSummary: String? {
        snapshots
            .flatMap(\.windows)
            .filter(\.isPrimaryAllowanceWindow)
            .min { lhs, rhs in lhs.remainingPercent < rhs.remainingPercent }
            .map { window in
                "\(window.shortTitle) \(Int(window.remainingPercent.rounded()))%"
            }
    }

    func start() {
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 120, repeats: true) { [weak self] _ in
                self?.refresh()
            }
        }
        if snapshots.isEmpty, !isRefreshing {
            refresh()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true

        DispatchQueue.global(qos: .utility).async { [provider] in
            let result = provider.fetch()
            DispatchQueue.main.async {
                self.snapshots = result
                self.lastRefreshDate = Date()
                self.isRefreshing = false
            }
        }
    }
}

private extension ProviderQuotaWindow {
    var isPrimaryAllowanceWindow: Bool {
        id == "primary" || id == "secondary" || id == "tertiary"
    }

    var shortTitle: String {
        switch kind {
        case .fiveHour: return "5h"
        case .weekly: return "7d"
        case .monthly: return "30d"
        case .extra: return title
        }
    }
}

private struct CodexBarQuotaProvider {
    func fetch() -> [ProviderQuotaSnapshot] {
        guard let executable = findExecutable() else {
            return [ProviderQuotaSnapshot(
                id: "provider-engine-missing",
                providerName: "TraceFence",
                planName: nil,
                accountLabel: nil,
                credits: nil,
                windows: [],
                resetCredits: nil,
                updatedAt: Date(),
                source: "bundle",
                errorMessage: "Quota monitor engine was not found. Please reinstall TraceFence.",
                setupHint: nil,
                isSetupNotice: false)]
        }

        do {
            let authorizedAccess = restoreAuthorizedAgentFolderAccess()
            defer {
                authorizedAccess.forEach { $0.stopAccessingSecurityScopedResource() }
            }

            let configs = readProviderConfigs(from: executable)
            let data = try runCodexBar(at: executable)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom(Self.decodeDate)
            let autoPayloads = try decoder.decode([CodexBarProviderPayload].self, from: data)
            let payloads = payloadsByReplacingCodexAuto(
                autoPayloads,
                with: readCodexOAuthPayloads(from: executable, decoder: decoder)
            )
            var hiddenCount = 0
            let snapshots = payloads.compactMap { payload -> ProviderQuotaSnapshot? in
                if let snapshot = makeSnapshot(from: payload, configs: configs) {
                    return snapshot
                }
                if payload.error != nil {
                    hiddenCount += 1
                }
                return nil
            }
            var visibleSnapshots = snapshots
            if hiddenCount > 0 {
                visibleSnapshots.append(setupNotice(count: hiddenCount))
            }
            if visibleSnapshots.isEmpty {
                return [ProviderQuotaSnapshot(
                    id: "provider-engine-empty",
                    providerName: "TraceFence",
                    planName: nil,
                    accountLabel: nil,
                    credits: nil,
                    windows: [],
                    resetCredits: nil,
                    updatedAt: Date(),
                    source: "cli",
                    errorMessage: "No quota data is available yet. Log in or enable the Agent you want to monitor.",
                    setupHint: "Installed Agents such as Codex, Claude, and Cursor will show actionable diagnostics here.",
                    isSetupNotice: false)]
            }
            return visibleSnapshots
        } catch {
            return [ProviderQuotaSnapshot(
                id: "provider-engine-error",
                providerName: "TraceFence",
                planName: nil,
                accountLabel: nil,
                credits: nil,
                windows: [],
                resetCredits: nil,
                updatedAt: Date(),
                source: "cli",
                errorMessage: sanitizedMessage(error.localizedDescription),
                setupHint: nil,
                isSetupNotice: false)]
        }
    }

    private func findExecutable() -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            Bundle.main.bundleURL
                .appendingPathComponent("Contents/Helpers/CodexBarHelper.app/Contents/MacOS/codexbar"),
            Bundle.main.url(forResource: "codexbar", withExtension: nil),
            Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("codexbar")
        ].compactMap(\.self)

        return candidates.first { url in
            fileManager.isExecutableFile(atPath: url.path)
        }
    }

    private func restoreAuthorizedAgentFolderAccess() -> [URL] {
        let bookmarkPaths = [
            SandboxPaths.shared.bookmarksPath,
            SandboxPaths.shared.scanBookmarksPath,
            SandboxPaths.shared.tokenScopeBookmarksPath
        ]

        let bookmarks = bookmarkPaths.reduce(into: [String: Data]()) { merged, path in
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let values = try? JSONDecoder().decode([String: Data].self, from: data) else {
                return
            }
            for (key, value) in values where merged[key] == nil {
                merged[key] = value
            }
        }

        var accessed: [URL] = []
        for (_, data) in bookmarks {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if url.startAccessingSecurityScopedResource() {
                    accessed.append(url)
                }
            } catch {
                continue
            }
        }
        return accessed
    }

    private func runCodexBar(at executable: URL) throws -> Data {
        try runCodexBarCommand(
            at: executable,
            arguments: [
                "usage",
                "--provider", "all",
                "--format", "json",
                "--source", "auto"
            ],
            timeout: 35
        )
    }

    private func readCodexOAuthPayloads(
        from executable: URL,
        decoder: JSONDecoder
    ) -> [CodexBarProviderPayload] {
        do {
            let data = try runCodexBarCommand(
                at: executable,
                arguments: [
                    "usage",
                    "--provider", "codex",
                    "--format", "json",
                    "--source", "oauth",
                    "--all-accounts"
                ],
                timeout: 20
            )
            return try decoder.decode([CodexBarProviderPayload].self, from: data)
        } catch {
            return []
        }
    }

    private func payloadsByReplacingCodexAuto(
        _ autoPayloads: [CodexBarProviderPayload],
        with oauthPayloads: [CodexBarProviderPayload]
    ) -> [CodexBarProviderPayload] {
        let codexOAuthPayloads = oauthPayloads.filter { payload in
            payload.provider.lowercased() == "codex"
                && (payload.usage != nil || payload.credits != nil || payload.error != nil)
        }
        guard codexOAuthPayloads.contains(where: { $0.usage != nil || $0.credits != nil }) else {
            return autoPayloads
        }

        return codexOAuthPayloads + autoPayloads.filter { $0.provider.lowercased() != "codex" }
    }

    private func readProviderConfigs(from executable: URL) -> [String: CodexBarProviderConfigPayload] {
        do {
            let data = try runCodexBarCommand(
                at: executable,
                arguments: ["config", "providers", "--format", "json"],
                timeout: 8
            )
            let configs = try JSONDecoder().decode([CodexBarProviderConfigPayload].self, from: data)
            return Dictionary(uniqueKeysWithValues: configs.map { ($0.provider, $0) })
        } catch {
            return [:]
        }
    }

    private func runCodexBarCommand(
        at executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> Data {
        let process = Process()
        let output = Pipe()
        let error = Pipe()

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        process.environment = processEnvironment()

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        var didTimeOut = false
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            didTimeOut = true
            process.terminate()
            let terminateDeadline = Date().addingTimeInterval(1.5)
            while process.isRunning, Date() < terminateDeadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let message = String(data: errorData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if didTimeOut {
            throw CodexBarQuotaError.commandFailed("Quota monitor engine timed out. TraceFence stopped this read automatically.")
        }
        if !data.isEmpty {
            return data
        }
        if process.terminationReason != .exit || process.terminationStatus != 0 {
            let fallback = "Quota monitor engine stopped before returning data. Please update or reinstall TraceFence."
            let value = (message?.isEmpty == false) ? message! : fallback
            throw CodexBarQuotaError.commandFailed(sanitizedMessage(value))
        }

        let value = (message?.isEmpty == false) ? message! : "Quota monitor engine produced no output."
        throw CodexBarQuotaError.commandFailed(sanitizedMessage(value))
    }

    private func makeSnapshot(
        from payload: CodexBarProviderPayload,
        configs: [String: CodexBarProviderConfigPayload]
    ) -> ProviderQuotaSnapshot? {
        let now = Date()
        let usage = payload.usage
        let windows = makeWindows(from: usage)
        let resetCredits = usage?.codexResetCredits
        let errorMessage = displayErrorMessage(for: payload)
        let config = configs[payload.provider]

        guard !windows.isEmpty || payload.credits != nil || resetCredits != nil || shouldShowDiagnostic(for: payload, config: config) else {
            return nil
        }

        return ProviderQuotaSnapshot(
            id: snapshotID(from: payload),
            providerName: displayName(for: payload.provider),
            planName: planName(from: payload),
            accountLabel: accountLabel(from: payload),
            credits: payload.credits?.remaining,
            windows: windows,
            resetCredits: resetCredits,
            updatedAt: usage?.updatedAt ?? payload.credits?.updatedAt ?? resetCredits?.updatedAt ?? now,
            source: payload.source,
            errorMessage: windows.isEmpty && resetCredits == nil ? errorMessage : nil,
            setupHint: windows.isEmpty && resetCredits == nil ? setupHint(for: payload) : nil,
            isSetupNotice: false)
    }

    private func setupNotice(count: Int) -> ProviderQuotaSnapshot {
        ProviderQuotaSnapshot(
            id: "provider-setup-notice",
            providerName: "Other Providers",
            planName: nil,
            accountLabel: "Optional setup",
            credits: nil,
            windows: [],
            resetCredits: nil,
            updatedAt: Date(),
            source: "setup",
            errorMessage: "\(count) inactive providers are collapsed.",
            setupHint: "Install or log in to the matching Agent, or enable its provider to show detailed diagnostics.",
            isSetupNotice: true)
    }

    private func shouldShowDiagnostic(
        for payload: CodexBarProviderPayload,
        config: CodexBarProviderConfigPayload?
    ) -> Bool {
        guard payload.error != nil else { return false }
        if config?.enabled == true || config?.defaultEnabled == true { return true }
        return isProviderLikelyInstalled(payload.provider)
    }

    private func setupHint(for payload: CodexBarProviderPayload) -> String? {
        let provider = payload.provider.lowercased()
        let message = payload.error?.message.lowercased() ?? ""
        if message.contains("api key") {
            return "Configure the \(displayName(for: provider)) API key or account credentials, then refresh the TraceFence provider monitor."
        }
        if message.contains("cli is not installed") || message.contains("not on path") {
            if isProviderLikelyInstalled(provider) {
                return "\(displayName(for: provider)) appears to be installed, but the quota reader cannot run its CLI. Reinstall or repair the \(displayName(for: provider)) CLI so it works directly in Terminal."
            }
            return "This provider is enabled, but its CLI was not found. Install the \(displayName(for: provider)) CLI and make sure it is on PATH."
        }
        if message.contains("session") || message.contains("log in") || message.contains("cookies") {
            return "The related Agent was detected, but no readable login session was found. Log in to \(displayName(for: provider)), authorize its data folder in TraceFence, then refresh the quota monitor."
        }
        if provider == "cursor" {
            return "Cursor was detected, but no usable session was found. Log in to Cursor, authorize the matching data folder in TraceFence, then refresh the quota monitor."
        }
        if provider == "claude" {
            return "Claude was detected. Make sure the Claude CLI runs, then finish signing in to Claude."
        }
        return "\(displayName(for: provider)) may be installed, but login, API key, or dependency setup is still missing."
    }

    private func displayErrorMessage(for payload: CodexBarProviderPayload) -> String? {
        guard let rawMessage = payload.error?.message else { return nil }
        let provider = payload.provider.lowercased()
        let message = rawMessage.lowercased()
        if message.contains("api key") {
            return "\(displayName(for: provider)) API key is not configured"
        }
        if message.contains("cli is not installed") || message.contains("not on path") {
            return isProviderLikelyInstalled(provider)
                ? "\(displayName(for: provider)) CLI is temporarily unavailable"
                : "\(displayName(for: provider)) CLI is not installed"
        }
        if provider == "cursor", message.contains("session") {
            return "No Cursor login session found"
        }
        if message.contains("cookies") || message.contains("log in") || message.contains("session") {
            return "No usable \(displayName(for: provider)) login session found"
        }
        if message.contains("no available fetch strategy") {
            return "No available fetch strategy for \(displayName(for: provider))"
        }
        return sanitizedMessage(rawMessage)
    }

    private func isProviderLikelyInstalled(_ provider: String) -> Bool {
        switch provider.lowercased() {
        case "codex":
            return commandExists("codex") || pathExists("~/.codex")
        case "claude":
            return commandExists("claude") || pathExists("/Applications/Claude.app") || pathExists("~/.claude")
        case "cursor":
            return pathExists("/Applications/Cursor.app") || pathExists("~/.cursor")
        case "opencode", "opencodego":
            return commandExists("opencode") || pathExists("~/.config/opencode")
        case "gemini":
            return commandExists("gemini") || pathExists("~/.gemini")
        case "amp":
            return commandExists("amp") || pathExists("~/.config/amp")
        case "warp":
            return commandExists("warp") || pathExists("/Applications/Warp.app")
        case "zed":
            return commandExists("zed") || pathExists("/Applications/Zed.app")
        case "windsurf":
            return commandExists("windsurf") || pathExists("/Applications/Windsurf.app")
        case "copilot":
            return commandExists("gh") && pathExists("~/.config/gh")
        case "factory":
            return pathExists("/Applications/Droid.app")
        case "antigravity":
            return pathExists("/Applications/Google Antigravity.app")
        default:
            return false
        }
    }

    private func commandExists(_ command: String) -> Bool {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        return paths.contains { path in
            FileManager.default.isExecutableFile(atPath: "\(path)/\(command)")
        }
    }

    private func pathExists(_ rawPath: String) -> Bool {
        let expanded = expandedPath(rawPath)
        return FileManager.default.fileExists(atPath: expanded)
    }

    private func expandedPath(_ rawPath: String) -> String {
        if rawPath == "~" {
            return SandboxPaths.realHomeDirectory
        }
        if rawPath.hasPrefix("~/") {
            return SandboxPaths.realHomeDirectory + String(rawPath.dropFirst())
        }
        return NSString(string: rawPath).expandingTildeInPath
    }

    private func processEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["HOME"] = SandboxPaths.realHomeDirectory
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(fallbackPath):\(path)"
        } else {
            environment["PATH"] = fallbackPath
        }
        return environment
    }

    private func makeWindows(from usage: CodexBarUsagePayload?) -> [ProviderQuotaWindow] {
        guard let usage else { return [] }

        var windows: [ProviderQuotaWindow] = []
        if let primary = usage.primary {
            windows.append(makeWindow(id: "primary", title: title(for: primary, fallback: "Current window"), payload: primary))
        }
        if let secondary = usage.secondary {
            windows.append(makeWindow(id: "secondary", title: title(for: secondary, fallback: "Long-term window"), payload: secondary))
        }
        if let tertiary = usage.tertiary {
            windows.append(makeWindow(id: "tertiary", title: title(for: tertiary, fallback: "Additional window"), payload: tertiary))
        }
        for extra in usage.extraRateWindows ?? [] where extra.usageKnown {
            windows.append(makeWindow(id: extra.id, title: extra.title, payload: extra.window))
        }
        return windows
    }

    private func makeWindow(id: String, title: String, payload: CodexBarRateWindowPayload) -> ProviderQuotaWindow {
        ProviderQuotaWindow(
            id: id,
            kind: kind(for: payload.windowMinutes),
            title: title,
            usedPercent: max(0, min(100, payload.usedPercent)),
            resetsAt: payload.resetsAt,
            windowMinutes: payload.windowMinutes)
    }

    private func kind(for minutes: Int?) -> ProviderQuotaWindow.Kind {
        guard let minutes else { return .extra }
        if minutes <= 300 { return .fiveHour }
        if minutes <= 10_080 { return .weekly }
        if minutes <= 45_000 { return .monthly }
        return .extra
    }

    private func title(for window: CodexBarRateWindowPayload, fallback: String) -> String {
        guard let minutes = window.windowMinutes else { return fallback }
        if minutes <= 300 { return "5-hour quota" }
        if minutes <= 10_080 { return "Weekly quota" }
        if minutes <= 45_000 { return "Monthly quota" }
        return fallback
    }

    private func displayName(for provider: String) -> String {
        let names = [
            "codex": "Codex",
            "openai": "OpenAI",
            "claude": "Claude",
            "cursor": "Cursor",
            "gemini": "Gemini",
            "grok": "Grok",
            "perplexity": "Perplexity",
            "openrouter": "OpenRouter",
            "poe": "Poe",
            "mistral": "Mistral",
            "deepseek": "DeepSeek",
            "manus": "Manus",
            "amp": "Amp",
            "factory": "Factory",
            "kiro": "Kiro",
            "bedrock": "Bedrock",
            "vertexai": "Vertex AI"
        ]
        if let name = names[provider.lowercased()] {
            return name
        }
        return provider
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func planName(from payload: CodexBarProviderPayload) -> String? {
        payload.usage?.identity?.loginMethod ?? payload.usage?.loginMethod ?? payload.version
    }

    private func accountLabel(from payload: CodexBarProviderPayload) -> String? {
        payload.usage?.identity?.accountEmail
            ?? payload.usage?.accountEmail
            ?? payload.account
            ?? payload.source
    }

    private func snapshotID(from payload: CodexBarProviderPayload) -> String {
        let account = accountLabel(from: payload) ?? "unknown-account"
        let plan = planName(from: payload) ?? "unknown-plan"
        return [
            payload.provider,
            payload.source,
            account,
            plan
        ]
        .map(normalizedSnapshotIDPart)
        .filter { !$0.isEmpty }
        .joined(separator: "-")
    }

    private func normalizedSnapshotIDPart(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        return value.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar).lowercased() : "-"
        }
        .joined()
        .split(separator: "-")
        .joined(separator: "-")
    }

    private static func decodeDate(from decoder: Decoder) throws -> Date {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) {
            return date
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(value)")
    }
}

private func sanitizedMessage(_ message: String) -> String {
    let value = message
        .replacingOccurrences(of: "CodexBar", with: "TraceFence")
        .replacingOccurrences(of: "codexbar", with: "TraceFence")
    return value
}

private enum CodexBarQuotaError: LocalizedError {
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message):
            return message
        }
    }
}

private struct CodexBarProviderPayload: Decodable {
    let provider: String
    let account: String?
    let version: String?
    let source: String
    let usage: CodexBarUsagePayload?
    let credits: CodexBarCreditsPayload?
    let error: CodexBarErrorPayload?
}

private struct CodexBarProviderConfigPayload: Decodable {
    let provider: String
    let displayName: String
    let enabled: Bool
    let defaultEnabled: Bool
}

private struct CodexBarUsagePayload: Decodable {
    let primary: CodexBarRateWindowPayload?
    let secondary: CodexBarRateWindowPayload?
    let tertiary: CodexBarRateWindowPayload?
    let extraRateWindows: [CodexBarNamedRateWindowPayload]?
    let codexResetCredits: ProviderQuotaResetCredits?
    let updatedAt: Date
    let identity: CodexBarIdentityPayload?
    let accountEmail: String?
    let loginMethod: String?
}

private struct CodexBarRateWindowPayload: Decodable {
    let usedPercent: Double
    let windowMinutes: Int?
    let resetsAt: Date?
    let resetDescription: String?
}

private struct CodexBarNamedRateWindowPayload: Decodable {
    let id: String
    let title: String
    let window: CodexBarRateWindowPayload
    let usageKnown: Bool

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case window
        case usageKnown
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        window = try container.decode(CodexBarRateWindowPayload.self, forKey: .window)
        usageKnown = try container.decodeIfPresent(Bool.self, forKey: .usageKnown) ?? true
    }
}

private struct CodexBarIdentityPayload: Decodable {
    let accountEmail: String?
    let loginMethod: String?
}

private struct CodexBarCreditsPayload: Decodable {
    let remaining: Double
    let updatedAt: Date
}

private struct CodexBarErrorPayload: Decodable {
    let message: String
}
