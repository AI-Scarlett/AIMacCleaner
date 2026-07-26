import SwiftUI
import Foundation

struct ScanItem: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: String
    let app: String
    let risk: String
    let riskDesc: String
    let path: String
    let realPath: String?
    let size: Int64
    let fileCount: Int
    var ignored: Bool
    var reason: String?
    var source: String?

    var riskLevel: RiskLevel { RiskLevel(rawValue: risk) ?? .caution }
    var sourceType: SourceType { SourceType(rawValue: source ?? "local") ?? .local }

    enum RiskLevel: String, Codable {
        case safe, caution, dangerous
        var label: String { ["safe": "Safe", "caution": "Caution", "dangerous": "Danger"][rawValue] ?? "Unknown" }
        func localizedLabel(_ localizer: Localizer) -> String {
            switch self {
            case .safe: return localizer.riskSafe
            case .caution: return localizer.riskCaution
            case .dangerous: return localizer.riskDangerous
            }
        }
        var systemImage: String { ["safe": "checkmark.circle.fill", "caution": "exclamationmark.triangle.fill", "dangerous": "xmark.circle.fill"][rawValue] ?? "questionmark.circle" }
        var color: String { ["safe": "green", "caution": "orange", "dangerous": "red"][rawValue] ?? "gray" }

        init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            switch rawValue {
            case "safe", "安全": self = .safe
            case "caution", "注意", "警告": self = .caution
            case "dangerous", "危险": self = .dangerous
            default: self = .caution
            }
        }
    }

    enum SourceType: String, Codable {
        case local, ai
        var label: String { self == .ai ? "AI" : "Local" }
        func localizedLabel(_ localizer: Localizer) -> String {
            self == .ai ? localizer.sourceAI : localizer.sourceLocal
        }

        init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            switch rawValue {
            case "local", "本地": self = .local
            case "ai", "AI", "智能": self = .ai
            default: self = .local
            }
        }
    }
}

struct DiskInfo: Codable {
    let total: Int64
    let used: Int64
    let free: Int64
    let totalGb: Double
    let usedGb: Double
    let freeGb: Double
    let usedPct: Double
}

enum AIProviderMode: String, Codable, CaseIterable {
    case automatic
    case apple
    case external
}

struct BrowserExtensionTarget: Identifiable {
    let id: String
    let displayName: String
    let appName: String
    let appNames: [String]
    let executableName: String
    let extensionPage: String
    let icon: String

    init(
        id: String,
        displayName: String,
        appName: String,
        appNames: [String]? = nil,
        executableName: String,
        extensionPage: String,
        icon: String
    ) {
        self.id = id
        self.displayName = displayName
        self.appName = appName
        self.appNames = appNames ?? [appName]
        self.executableName = executableName
        self.extensionPage = extensionPage
        self.icon = icon
    }

    static let supported: [BrowserExtensionTarget] = [
        BrowserExtensionTarget(id: "chrome", displayName: "Google Chrome", appName: "Google Chrome", executableName: "Google Chrome", extensionPage: "chrome://extensions/", icon: "globe"),
        BrowserExtensionTarget(id: "edge", displayName: "Microsoft Edge", appName: "Microsoft Edge", executableName: "Microsoft Edge", extensionPage: "edge://extensions/", icon: "globe"),
        BrowserExtensionTarget(id: "brave", displayName: "Brave", appName: "Brave Browser", executableName: "Brave Browser", extensionPage: "brave://extensions/", icon: "globe"),
        BrowserExtensionTarget(id: "arc", displayName: "Arc", appName: "Arc", executableName: "Arc", extensionPage: "arc://extensions/", icon: "globe"),
        BrowserExtensionTarget(id: "vivaldi", displayName: "Vivaldi", appName: "Vivaldi", executableName: "Vivaldi", extensionPage: "vivaldi://extensions/", icon: "globe")
    ]
}

struct DesktopAgentLaunchTarget: Identifiable {
    let id: String
    let displayName: String
    let appName: String
    let appNames: [String]
    let executableName: String
    let launcherFileName: String
    let icon: String
    let isPrimary: Bool

    init(
        id: String,
        displayName: String,
        appName: String,
        appNames: [String]? = nil,
        executableName: String? = nil,
        launcherFileName: String,
        icon: String,
        isPrimary: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.appName = appName
        self.appNames = appNames ?? [appName]
        self.executableName = executableName ?? appName
        self.launcherFileName = launcherFileName
        self.icon = icon
        self.isPrimary = isPrimary
    }

    static let codex = DesktopAgentLaunchTarget(
        id: "codex",
        displayName: "Codex",
        appName: "Codex",
        launcherFileName: "Launch Codex.command",
        icon: "terminal",
        isPrimary: true
    )

    static let claude = DesktopAgentLaunchTarget(
        id: "claude",
        displayName: "Claude",
        appName: "Claude",
        launcherFileName: "Launch Claude.command",
        icon: "bubble.left.and.text.bubble.right",
        isPrimary: true
    )

    static let supported: [DesktopAgentLaunchTarget] = [
        codex,
        claude,
        DesktopAgentLaunchTarget(id: "cursor", displayName: "Cursor", appName: "Cursor", launcherFileName: "Launch Cursor.command", icon: "cursorarrow"),
        DesktopAgentLaunchTarget(id: "windsurf", displayName: "Windsurf", appName: "Windsurf", launcherFileName: "Launch Windsurf.command", icon: "wind"),
        DesktopAgentLaunchTarget(id: "vscode", displayName: "Visual Studio Code", appName: "Visual Studio Code", executableName: "Electron", launcherFileName: "Launch Visual Studio Code.command", icon: "chevron.left.forwardslash.chevron.right"),
        DesktopAgentLaunchTarget(id: "chatgpt", displayName: "ChatGPT", appName: "ChatGPT", launcherFileName: "Launch ChatGPT.command", icon: "sparkles"),
        DesktopAgentLaunchTarget(id: "warp", displayName: "Warp", appName: "Warp", launcherFileName: "Launch Warp.command", icon: "terminal"),
        DesktopAgentLaunchTarget(id: "zed", displayName: "Zed", appName: "Zed", launcherFileName: "Launch Zed.command", icon: "chevron.left.forwardslash.chevron.right"),
        DesktopAgentLaunchTarget(id: "antigravity", displayName: "Google Antigravity", appName: "Google Antigravity", launcherFileName: "Launch Google Antigravity.command", icon: "sparkles"),
        DesktopAgentLaunchTarget(id: "trae", displayName: "Trae", appName: "Trae", appNames: ["Trae", "Trae CN"], launcherFileName: "Launch Trae.command", icon: "terminal")
    ]
}

struct CLIAgentLaunchTarget: Identifiable {
    let id: String
    let displayName: String
    let commandName: String
    let launcherFileName: String
    let icon: String

    static let grok = CLIAgentLaunchTarget(
        id: "grok",
        displayName: "Grok CLI",
        commandName: "grok",
        launcherFileName: "Launch Grok CLI.command",
        icon: "terminal"
    )

    static let shell = CLIAgentLaunchTarget(
        id: "shell",
        displayName: "CLI Shell",
        commandName: "zsh",
        launcherFileName: "Open TraceFence CLI Shell.command",
        icon: "chevron.left.forwardslash.chevron.right"
    )

    static let supported: [CLIAgentLaunchTarget] = [
        grok,
        CLIAgentLaunchTarget(id: "codex", displayName: "Codex CLI", commandName: "codex", launcherFileName: "Launch Codex CLI.command", icon: "terminal"),
        CLIAgentLaunchTarget(id: "claude", displayName: "Claude Code", commandName: "claude", launcherFileName: "Launch Claude Code.command", icon: "bubble.left.and.text.bubble.right"),
        CLIAgentLaunchTarget(id: "gemini", displayName: "Gemini CLI", commandName: "gemini", launcherFileName: "Launch Gemini CLI.command", icon: "sparkles"),
        CLIAgentLaunchTarget(id: "cursor-agent", displayName: "Cursor Agent", commandName: "cursor-agent", launcherFileName: "Launch Cursor Agent.command", icon: "cursorarrow"),
        CLIAgentLaunchTarget(id: "opencode", displayName: "OpenCode", commandName: "opencode", launcherFileName: "Launch OpenCode.command", icon: "terminal"),
        CLIAgentLaunchTarget(id: "aider", displayName: "Aider", commandName: "aider", launcherFileName: "Launch Aider.command", icon: "wand.and.stars"),
        CLIAgentLaunchTarget(id: "amp", displayName: "Amp", commandName: "amp", launcherFileName: "Launch Amp.command", icon: "bolt"),
        CLIAgentLaunchTarget(id: "goose", displayName: "Goose", commandName: "goose", launcherFileName: "Launch Goose.command", icon: "terminal"),
        CLIAgentLaunchTarget(id: "qwen", displayName: "Qwen", commandName: "qwen", launcherFileName: "Launch Qwen.command", icon: "terminal"),
        CLIAgentLaunchTarget(id: "openclaw", displayName: "OpenClaw", commandName: "openclaw", launcherFileName: "Launch OpenClaw.command", icon: "terminal"),
        CLIAgentLaunchTarget(id: "hermes", displayName: "Hermes", commandName: "hermes", launcherFileName: "Launch Hermes.command", icon: "terminal"),
        CLIAgentLaunchTarget(id: "minimax", displayName: "MiniMax Code", commandName: "minimax", launcherFileName: "Launch MiniMax Code.command", icon: "terminal"),
        CLIAgentLaunchTarget(id: "kiro", displayName: "Kiro CLI", commandName: "kiro-cli", launcherFileName: "Launch Kiro CLI.command", icon: "terminal"),
        CLIAgentLaunchTarget(id: "copilot", displayName: "GitHub Copilot CLI", commandName: "copilot", launcherFileName: "Launch Copilot CLI.command", icon: "terminal"),
        CLIAgentLaunchTarget(id: "droid", displayName: "Factory Droid", commandName: "droid", launcherFileName: "Launch Droid.command", icon: "terminal")
    ]
}

enum AgentIntegrationCatalog {
    static var installedBrowserTargets: [BrowserExtensionTarget] {
        BrowserExtensionTarget.supported.filter { applicationURL(appNames: $0.appNames) != nil }
    }

    static var primaryDesktopAgents: [DesktopAgentLaunchTarget] {
        DesktopAgentLaunchTarget.supported.filter(\.isPrimary)
    }

    static var installedPrimaryDesktopAgents: [DesktopAgentLaunchTarget] {
        primaryDesktopAgents.filter(isDesktopAgentInstalled)
    }

    static var installedSecondaryDesktopAgents: [DesktopAgentLaunchTarget] {
        DesktopAgentLaunchTarget.supported
            .filter { !$0.isPrimary }
            .filter(isDesktopAgentInstalled)
    }

    static var installedCLIAgents: [CLIAgentLaunchTarget] {
        CLIAgentLaunchTarget.supported.filter(isCLIAgentInstalled)
    }

    static func isDesktopAgentInstalled(_ target: DesktopAgentLaunchTarget) -> Bool {
        applicationURL(appNames: target.appNames) != nil
    }

    static func isCLIAgentInstalled(_ target: CLIAgentLaunchTarget) -> Bool {
        commandURL(target.commandName) != nil || knownConfigExists(for: target.id)
    }

    static func applicationURL(appNames: [String]) -> URL? {
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true).appendingPathComponent("Applications", isDirectory: true)
        ]
        for root in roots {
            for name in appNames {
                let candidate = root.appendingPathComponent("\(name).app", isDirectory: true)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    static func commandExists(_ command: String) -> Bool {
        commandURL(command) != nil
    }

    static func commandURL(_ command: String) -> URL? {
        commandSearchDirectories()
            .map { $0.appendingPathComponent(command) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func isProviderLikelyInstalled(_ provider: String) -> Bool {
        switch provider.lowercased() {
        case "codex":
            return isDesktopAgentInstalled(.codex) || commandExists("codex") || pathExists("~/.codex")
        case "claude":
            return isDesktopAgentInstalled(.claude) || commandExists("claude") || pathExists("~/.claude")
        case "cursor":
            return hasDesktopAgent(id: "cursor") || commandExists("cursor-agent") || pathExists("~/.cursor")
        case "grok":
            return commandExists("grok") || pathExists("~/.grok")
        case "opencode", "opencodego":
            return commandExists("opencode") || pathExists("~/.config/opencode")
        case "gemini":
            return commandExists("gemini") || pathExists("~/.gemini")
        case "amp":
            return commandExists("amp") || pathExists("~/.config/amp")
        case "warp":
            return hasDesktopAgent(id: "warp") || commandExists("warp")
        case "zed":
            return hasDesktopAgent(id: "zed") || commandExists("zed")
        case "windsurf":
            return hasDesktopAgent(id: "windsurf") || commandExists("windsurf")
        case "copilot":
            return commandExists("gh") && pathExists("~/.config/gh")
        case "factory":
            return pathExists("/Applications/Droid.app")
        case "antigravity":
            return hasDesktopAgent(id: "antigravity")
        default:
            return false
        }
    }

    private static func hasDesktopAgent(id: String) -> Bool {
        DesktopAgentLaunchTarget.supported
            .first { $0.id == id }
            .map(isDesktopAgentInstalled) ?? false
    }

    private static func knownConfigExists(for id: String) -> Bool {
        switch id {
        case "grok": return pathExists("~/.grok")
        case "gemini": return pathExists("~/.gemini")
        case "opencode": return pathExists("~/.config/opencode")
        case "amp": return pathExists("~/.config/amp")
        case "goose": return pathExists("~/.config/goose")
        case "aider": return pathExists("~/.aider.conf.yml") || pathExists("~/.aider")
        case "qwen": return pathExists("~/.qwen")
        default: return false
        }
    }

    private static func commandSearchDirectories() -> [URL] {
        let home = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
        let rawPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".cargo/bin").path,
            home.appendingPathComponent(".grok/bin").path,
            home.appendingPathComponent(".mavis/bin").path,
            home.appendingPathComponent("bin").path
        ]
        return rawPaths.map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private static func pathExists(_ rawPath: String) -> Bool {
        FileManager.default.fileExists(atPath: expandedPath(rawPath))
    }

    private static func expandedPath(_ rawPath: String) -> String {
        if rawPath == "~" {
            return SandboxPaths.realHomeDirectory
        }
        if rawPath.hasPrefix("~/") {
            return SandboxPaths.realHomeDirectory + String(rawPath.dropFirst())
        }
        return NSString(string: rawPath).expandingTildeInPath
    }
}

struct AIConfig: Codable {
    let apiBase: String?
    let apiKey: String?
    let model: String?
    let hasKey: Bool?
    let mode: String?

    static let appleIntelligenceModel = "apple-intelligence"

    enum CodingKeys: String, CodingKey {
        case apiBase = "api_base", apiKey = "api_key", model, hasKey = "has_key", mode
    }

    var providerMode: AIProviderMode {
        AIProviderMode(rawValue: mode ?? "") ?? .automatic
    }

    var usesExternalProvider: Bool {
        let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let modelName = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty && !modelName.isEmpty && modelName != Self.appleIntelligenceModel
    }

    var chatCompletionsURL: URL? {
        Self.chatCompletionsURL(from: apiBase)
    }

    static func chatCompletionsURL(from apiBase: String?) -> URL? {
        let raw = (apiBase ?? "https://api.deepseek.com")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !raw.isEmpty else { return nil }
        if raw.hasSuffix("/chat/completions") {
            return URL(string: raw)
        }
        if raw.hasSuffix("/v1") {
            return URL(string: raw + "/chat/completions")
        }
        return URL(string: raw + "/v1/chat/completions")
    }
}

struct DeleteResult: Codable {
    let success: Bool
    let results: [DeleteItemResult]?
    let deleted: Int?
    let failed: Int?
}

struct DeleteItemResult: Codable {
    let id: String?
    let path: String?
    let success: Bool?
    let message: String?
}

struct AIStatus: Codable {
    let running: Bool
    let message: String?
}

struct IgnoreResult: Codable {
    let success: Bool
    let ignored: [String]?
}

struct AppInfo: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let desc: String
    let bundleId: String
    let appPath: String
    let iconPath: String?
    let version: String?
    let appSize: Int64
    let cacheSize: Int64
    let dataSize: Int64
    let totalSize: Int64
    let appType: AppType
    let subCategory: String
    let risk: String
    let riskDesc: String
    let canUninstall: Bool
    let canClean: Bool
    let canReset: Bool

    enum AppType: String, Codable, CaseIterable {
        case app = "app"
        case dependency = "dependency"
        case other = "other"

        init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            switch rawValue {
            case "app", "应用", "应用程序": self = .app
            case "dependency", "依赖": self = .dependency
            case "other", "其它", "其他": self = .other
            default: self = .other
            }
        }

        var label: String {
            switch self {
            case .app: "App"
            case .dependency: "Dependency"
            case .other: "Other"
            }
        }

        func localizedLabel(_ localizer: Localizer) -> String {
            switch self {
            case .app: return localizer.typeApp
            case .dependency: return localizer.typeDependency
            case .other: return localizer.typeOther
            }
        }

        var tabLabel: String {
            switch self {
            case .app: "App Management"
            case .dependency: "Dependencies"
            case .other: "Other Tools"
            }
        }

        func localizedTabLabel(_ localizer: Localizer) -> String {
            switch self {
            case .app: return localizer.appManagerTitle
            case .dependency: return localizer.dependencyTitle
            case .other: return localizer.otherToolsTitle
            }
        }

        var tabIcon: String {
            switch self {
            case .app: "app.badge"
            case .dependency: "cube.box"
            case .other: "terminal"
            }
        }

        var tabColor: Color {
            switch self {
            case .app: .cyan
            case .dependency: .orange
            case .other: .gray
            }
        }
    }

    var relatedPaths: [String] {
        let home = SandboxPaths.realHomeDirectory
        var paths: [String] = []
        if !appPath.hasSuffix(".app") && appPath.hasPrefix(home) {
            paths.append(appPath)
        }
        paths += [
            "\(home)/Library/Caches/\(bundleId)",
            "\(home)/Library/Application Support/\(bundleId)",
            "\(home)/Library/Preferences/\(bundleId).plist",
            "\(home)/Library/Saved Application State/\(bundleId).savedState",
            "\(home)/Library/Containers/\(bundleId)",
            "\(home)/Library/Logs/\(bundleId)",
            "\(home)/Library/HTTPStorages/\(bundleId)",
            "\(home)/Library/WebKit/\(bundleId)",
            "\(home)/Library/Cookies/\(bundleId).binarycookies",
            "\(home)/Library/Group Containers/\(bundleId)",
        ]
        return paths
    }

    var cachePaths: [String] {
        let home = SandboxPaths.realHomeDirectory
        return [
            "\(home)/Library/Caches/\(bundleId)",
            "\(home)/Library/HTTPStorages/\(bundleId)",
            "\(home)/Library/WebKit/\(bundleId)",
        ]
    }

    var dataPaths: [String] {
        let home = SandboxPaths.realHomeDirectory
        var paths: [String] = []
        if !appPath.hasSuffix(".app") && appPath.hasPrefix(home) {
            paths.append(appPath)
        }
        paths += [
            "\(home)/Library/Application Support/\(bundleId)",
            "\(home)/Library/Preferences/\(bundleId).plist",
            "\(home)/Library/Saved Application State/\(bundleId).savedState",
            "\(home)/Library/Containers/\(bundleId)",
            "\(home)/Library/Logs/\(bundleId)",
            "\(home)/Library/Cookies/\(bundleId).binarycookies",
            "\(home)/Library/Group Containers/\(bundleId)",
        ]
        return paths
    }
}

struct OperationRecord: Identifiable, Codable, Equatable {
    let id: String
    let timestamp: Date
    let agentName: String
    let operationType: OperationType
    let targetPath: String
    let detail: String
    let fileSize: Int64
    let processName: String?
    let toolInfo: String?

    enum OperationType: String, Codable, CaseIterable {
        case create = "Create"
        case modify = "Modify"
        case delete = "Delete"
        case move = "Move"
        case rename = "Rename"
        case read = "Read"
        case execute = "Execute"

        var icon: String {
            switch self {
            case .create: "plus.circle.fill"
            case .modify: "pencil.circle.fill"
            case .delete: "trash.circle.fill"
            case .move: "arrow.right.circle.fill"
            case .rename: "text.cursor.input"
            case .read: "eye.circle.fill"
            case .execute: "terminal.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .create: "green"
            case .modify: "blue"
            case .delete: "red"
            case .move: "orange"
            case .rename: "purple"
            case .read: "teal"
            case .execute: "purple"
            }
        }

        func localizedLabel(_ localizer: Localizer) -> String {
            switch self {
            case .create: return localizer.opCreate
            case .modify: return localizer.opModify
            case .delete: return localizer.opDelete
            case .move: return localizer.opMove
            case .rename: return localizer.opRename
            case .read: return localizer.opRead
            case .execute: return localizer.opExec
            }
        }
    }
}

struct ProcessSnapshot: Codable {
    let timestamp: Date
    let pid: pid_t
    let ppid: pid_t
    let comm: String
    let args: String
}

struct CuratedRecord: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let agentName: String
    let operationType: String
    let targetPath: String
    let detail: String
    let fileSize: Int64
    let confidence: Double
    let evidence: String

    var confidenceLabel: String {
        if confidence >= 0.8 { return "high" }
        if confidence >= 0.5 { return "medium" }
        return "low"
    }

    func localizedConfidenceLabel(_ localizer: Localizer) -> String {
        if confidence >= 0.8 { return localizer.highConf }
        if confidence >= 0.5 { return localizer.medConf }
        return localizer.lowConf
    }

    var confidenceColor: String {
        if confidence >= 0.8 { return "green" }
        if confidence >= 0.5 { return "orange" }
        return "red"
    }
}

struct DiscoveredProcess: Identifiable, Hashable {
    let id: String
    let comm: String
    let pids: [pid_t]
    let agentName: String?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: DiscoveredProcess, rhs: DiscoveredProcess) -> Bool { lhs.id == rhs.id }
}

struct CustomAgentSource: Codable, Identifiable {
    var id: String { name }
    let name: String
    let searchPaths: [String]
    let addedAt: Date
}

struct DiscoveredAgent: Identifiable, Codable {
    let id: String
    let name: String
    let sessionCount: Int
    let latestActivity: Date?
    let projectDirs: [String]
    let dataPath: String
}

struct AgentOpRecord: Identifiable, Codable {
    let id: String
    let agentName: String
    let sessionId: String
    let projectDir: String
    let timestamp: Date
    let toolName: String
    let targetPath: String
    let opType: String
    let detail: String
}

struct TargetedFileOp: Identifiable {
    let id: String
    let timestamp: Date
    let processComm: String
    let processPid: pid_t
    let targetPath: String
    let opType: String
    let fileSize: Int64
}

struct HardwareInfo: Codable {
    var cpuUsage: Double
    var cpuCoreCount: Int
    var cpuTemperature: Double?
    var memoryTotal: Int64
    var memoryUsed: Int64
    var memoryFree: Int64
    var memoryPressure: Double
    var swapUsed: Int64
    var batteryPercent: Double?
    var batteryCharging: Bool
    var batteryTimeRemaining: Int?
    var processCount: Int
    var threadCount: Int
    var uptimeSeconds: Int64
    var networkInRate: Double
    var networkOutRate: Double

    var memoryTotalGb: Double { Double(memoryTotal) / 1073741824.0 }
    var memoryUsedGb: Double { Double(memoryUsed) / 1073741824.0 }
    var memoryFreeGb: Double { Double(memoryFree) / 1073741824.0 }
    var swapUsedGb: Double { Double(swapUsed) / 1073741824.0 }
    var memoryPressurePct: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) * 100.0 : 0 }
    var uptimeFormatted: String {
        let days = uptimeSeconds / 86400
        let hours = (uptimeSeconds % 86400) / 3600
        let mins = (uptimeSeconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
    var networkInFormatted: String { formatRate(networkInRate) }
    var networkOutFormatted: String { formatRate(networkOutRate) }

    private func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        if bytesPerSec < 1048576 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
        return String(format: "%.1f MB/s", bytesPerSec / 1048576)
    }
}

struct SensorEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let sensorType: SensorType
    let processName: String
    let pid: Int32
    let bundleId: String?

    enum SensorType: String, Codable, CaseIterable {
        case camera = "Camera"
        case microphone = "Microphone"

        init(from decoder: Decoder) throws {
            let rawValue = try decoder.singleValueContainer().decode(String.self)
            switch rawValue {
            case "Camera", "摄像头": self = .camera
            case "Microphone", "麦克风": self = .microphone
            default: self = .camera
            }
        }

        var icon: String {
            switch self {
            case .camera: "video.fill"
            case .microphone: "mic.fill"
            }
        }

        func localizedLabel(_ localizer: Localizer) -> String {
            switch self {
            case .camera: return localizer.camera
            case .microphone: return localizer.microphone
            }
        }

        var color: Color {
            switch self {
            case .camera: .red
            case .microphone: .blue
            }
        }
    }
}

struct StorageCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let size: Int64
    let path: String
    var files: [StorageFile]

    var sizeFormatted: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

struct StorageFile: Identifiable {
    let id: String
    let name: String
    let path: String
    let size: Int64
    let createdDate: Date?
    let modifiedDate: Date?
    let isDirectory: Bool
    var aiAnalysis: String?
    var riskLevel: FileRiskLevel = .unknown

    var sizeFormatted: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

    enum SortField: String, CaseIterable {
        case size = "Size"
        case created = "Date Added"
        case modified = "Date Modified"
        case name = "Name"

        var icon: String {
            switch self {
            case .size: "arrow.up.arrow.down.circle"
            case .created: "calendar.badge.plus"
            case .modified: "calendar.badge.clock"
            case .name: "textformat"
            }
        }

        func localizedLabel(_ localizer: Localizer) -> String {
            switch self {
            case .size: return localizer.sortSize
            case .created: return localizer.sortCreated
            case .modified: return localizer.sortModified
            case .name: return localizer.sortName
            }
        }
    }
}

struct IntelAppInfo: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let path: String
    let architecture: BinaryArchitecture
    let appType: IntelAppType
    let size: Int64
    let version: String?
    let bundleId: String?
    var downloadURL: String?
    var homebrewARMName: String?
    var isSearching: Bool = false
    var searchError: String?
    var replaceState: ReplaceState = .idle
    var replaceProgress: Double = 0

    enum ReplaceState: Int {
        case idle = 0
        case searchingReplacement = 1
        case awaitingVerification = 2
        case completed = 3
        case failed = 4

        var label: String {
            switch self {
            case .idle: return ""
            case .searchingReplacement: return "正在查找替代版本..."
            case .awaitingVerification: return "等待安装并验证"
            case .completed: return "已完成"
            case .failed: return "失败"
            }
        }

        func localizedLabel(_ localizer: Localizer) -> String {
            switch self {
            case .idle: return ""
            case .searchingReplacement: return localizer.t("正在查找替代版本…", en: "Finding a replacement…")
            case .awaitingVerification: return localizer.t("等待安装并验证", en: "Awaiting installation and verification")
            case .completed: return localizer.completed
            case .failed: return localizer.failed
            }
        }

        var color: Color {
            switch self {
            case .idle: return .secondary
            case .searchingReplacement: return .orange
            case .awaitingVerification: return .blue
            case .completed: return .green
            case .failed: return .red
            }
        }
    }

    var sizeFormatted: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

    enum BinaryArchitecture: String, CaseIterable {
        case x86_64 = "Intel (x86_64)"
        case arm64 = "Apple Silicon (arm64)"
        case universal = "Universal"
        case unknown = "未知"
        case rosetta = "Rosetta 转译"

        var isIntel: Bool { self == .x86_64 || self == .rosetta }

        var icon: String {
            switch self {
            case .x86_64: "cpu"
            case .arm64: "cpu"
            case .universal: "arrow.triangle.2.circlepath"
            case .unknown: "questionmark.circle"
            case .rosetta: "arrow.right.arrow.left.circle"
            }
        }

        var color: Color {
            switch self {
            case .x86_64: .red
            case .arm64: .green
            case .universal: .blue
            case .unknown: .gray
            case .rosetta: .orange
            }
        }

        var badge: String {
            switch self {
            case .x86_64: "Intel"
            case .arm64: "ARM"
            case .universal: "通用"
            case .unknown: "?"
            case .rosetta: "转译"
            }
        }

        func localizedLabel(_ localizer: Localizer) -> String {
            switch self {
            case .x86_64: return "Intel (x86_64)"
            case .arm64: return "Apple Silicon (arm64)"
            case .universal: return "Universal"
            case .unknown: return localizer.unknownArch
            case .rosetta: return localizer.rosettaTrans
            }
        }

        func localizedBadge(_ localizer: Localizer) -> String {
            switch self {
            case .x86_64: return "Intel"
            case .arm64: return "ARM"
            case .universal: return localizer.universalBinary
            case .unknown: return "?"
            case .rosetta: return localizer.translated
            }
        }
    }

    enum IntelAppType: String, CaseIterable {
        case app = "应用程序"
        case cli = "命令行工具"
        case homebrew = "Homebrew 包"
        case framework = "框架/库"

        var icon: String {
            switch self {
            case .app: "app.badge"
            case .cli: "terminal"
            case .homebrew: "mug.is.full"
            case .framework: "building.columns"
            }
        }

        var color: Color {
            switch self {
            case .app: .cyan
            case .cli: .purple
            case .homebrew: .orange
            case .framework: .brown
            }
        }

        func localizedLabel(_ localizer: Localizer) -> String {
            switch self {
            case .app: return localizer.appTypeApp
            case .cli: return localizer.appTypeCLI
            case .homebrew: return localizer.appTypeHomebrew
            case .framework: return localizer.appTypeFramework
            }
        }
    }
}
