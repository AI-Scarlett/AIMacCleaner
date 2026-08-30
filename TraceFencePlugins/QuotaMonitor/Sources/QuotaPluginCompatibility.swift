import Foundation

/// The quota engine source is shared with the App Store host so provider
/// parsing and continuity rules have one implementation. The independently
/// delivered website plugin always runs outside the App Sandbox and therefore
/// supplies the small distribution/path contract that source expects.
struct SandboxPaths {
    static let isDirectDistribution = true
    static let isSandboxed = false
    static let directDistributionBundleID = "com.tracefence.app"
    static let realHomeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
    static let shared = SandboxPaths()

    private init() {}

    var bookmarksPath: String { "/dev/null/tracefence-quota-bookmarks" }
    var scanBookmarksPath: String { "/dev/null/tracefence-quota-scan-bookmarks" }
    var tokenScopeBookmarksPath: String { "/dev/null/tracefence-quota-token-bookmarks" }
}

enum TraceFenceDistributionPolicy {
    struct Channel {
        let isDirect = true
    }

    static let currentChannel = Channel()
}

enum AgentIntegrationCatalog {
    static func isProviderLikelyInstalled(_ provider: String) -> Bool {
        switch provider.lowercased() {
        case "codex":
            return appExists("Codex") || commandExists("codex") || pathExists("~/.codex")
        case "claude":
            return appExists("Claude") || commandExists("claude") || pathExists("~/.claude")
        case "cursor":
            return appExists("Cursor") || commandExists("cursor-agent") || pathExists("~/.cursor")
        case "grok":
            return commandExists("grok") || pathExists("~/.grok")
        case "opencode", "opencodego":
            return commandExists("opencode") || pathExists("~/.config/opencode")
        case "gemini":
            return commandExists("gemini")
        case "antigravity":
            return appExists("Antigravity")
                || appExists("Google Antigravity")
                || pathExists("~/.gemini/antigravity")
                || pathExists("~/.gemini/antigravity-ide")
        case "amp":
            return commandExists("amp") || pathExists("~/.config/amp")
        case "qwen":
            return commandExists("qwen") || pathExists("~/.qwen")
        case "goose":
            return commandExists("goose") || pathExists("~/.config/goose")
        case "aider":
            return commandExists("aider") || pathExists("~/.aider") || pathExists("~/.aider.conf.yml")
        case "openrouter":
            return ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"]?.isEmpty == false
        default:
            return false
        }
    }

    private static func appExists(_ name: String) -> Bool {
        let home = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
        return [
            URL(fileURLWithPath: "/Applications/\(name).app", isDirectory: true),
            home.appendingPathComponent("Applications/\(name).app", isDirectory: true)
        ].contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    private static func commandExists(_ command: String) -> Bool {
        let home = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
        let directories = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".grok/bin").path,
            home.appendingPathComponent(".mavis/bin").path,
            home.appendingPathComponent("bin").path
        ]
        return directories.contains {
            FileManager.default.isExecutableFile(atPath: URL(fileURLWithPath: $0).appendingPathComponent(command).path)
        }
    }

    private static func pathExists(_ rawPath: String) -> Bool {
        let path: String
        if rawPath == "~" {
            path = SandboxPaths.realHomeDirectory
        } else if rawPath.hasPrefix("~/") {
            path = SandboxPaths.realHomeDirectory + String(rawPath.dropFirst())
        } else {
            path = rawPath
        }
        return FileManager.default.fileExists(atPath: path)
    }
}
