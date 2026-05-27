import Foundation

enum InstallationKind {
    case jsonHooks(entry: JsonHookEntry, nested: Bool)
    case yamlHooks
    case cursorSettings
    case pluginDirectory
    case unknown
}

enum JsonHookEntry {
    case commandOnly
    case typedCommand
}

struct HookEventDescriptor: Sendable {
    var name: String
    var matcher: String?
    var timeout: UInt64?

    static func plain(_ name: String) -> HookEventDescriptor {
        HookEventDescriptor(name: name, matcher: nil, timeout: nil)
    }

    static func matcher(_ name: String, _ matcher: String, timeout: UInt64? = nil) -> HookEventDescriptor {
        HookEventDescriptor(name: name, matcher: matcher, timeout: timeout)
    }

    static func timed(_ name: String, _ timeout: UInt64) -> HookEventDescriptor {
        HookEventDescriptor(name: name, matcher: nil, timeout: timeout)
    }
}

struct AgentIntegrationProfile: Sendable {
    var id: String
    var displayLabel: String
    var installationKind: InstallationKind
    var configurationPath: String
    var events: [HookEventDescriptor]
    var extraArgs: [String]

    var agentId: String { id }
    var displayName: String { displayLabel }
    var configRoot: String { configurationPath }

    var executable: String {
        switch id {
        case "claude-code": return "claude"
        case "codex": return "codex"
        case "gemini": return "gemini"
        case "cursor": return "cursor"
        case "cursor-cli": return "cursor-agent"
        case "copilot": return "github-copilot-cli"
        case "trae": return "trae"
        case "traecli": return "trae-cli"
        case "traecn": return "trae-cn"
        case "qoder": return "qoder"
        case "qoder-cli": return "qoder-cli"
        case "codebuddy": return "codebuddy"
        case "codebuddycn": return "codebuddy-cn"
        case "qwen": return "qwen"
        case "kimi": return "kimi"
        case "deepseek": return "deepseek"
        case "opencode": return "opencode"
        case "droid": return "droid"
        case "stepfun": return "stepfun"
        case "antigravity": return "antigravity"
        case "workbuddy": return "workbuddy"
        case "hermes": return "hermes"
        case "pi": return "pi"
        case "kiro": return "kiro"
        case "openclaw": return "openclaw"
        case "qclaw": return "qclaw"
        case "easyclaw": return "easyclaw"
        case "autoclaw": return "autoclaw"
        default: return id
        }
    }

    var systemImage: String {
        switch id {
        case "claude-code": return "c.circle.fill"
        case "codex": return "o.circle.fill"
        case "gemini": return "sparkles"
        case "cursor": return "cursorarrow.rays"
        case "cursor-cli": return "cursorarrow.rays"
        case "copilot": return "laptopcomputer"
        case "trae", "traecli", "traecn": return "hammer.fill"
        case "qoder", "qoder-cli": return "q.circle.fill"
        case "codebuddy", "codebuddycn": return "b.circle.fill"
        case "qwen": return "brain.head.profile"
        case "kimi": return "k.circle.fill"
        case "deepseek": return "d.circle.fill"
        case "opencode": return "lock.open.fill"
        case "droid": return "cpu.fill"
        case "stepfun": return "figure.walk"
        case "antigravity": return "arrow.up.to.line.compact"
        case "workbuddy": return "briefcase.fill"
        case "hermes": return "bird.fill"
        case "pi": return "circle.dashed"
        case "kiro": return "bolt.fill"
        case "openclaw", "qclaw", "easyclaw", "autoclaw": return "terminal.fill"
        default: return "terminal.fill"
        }
    }

    var userHome: URL {
        FileManager.default.homeDirectoryForCurrentUser
    }

    var fullConfigPath: URL {
        userHome.appendingPathComponent(configurationPath)
    }
}

extension AgentIntegrationProfile {
    static let claudeCode = AgentIntegrationProfile(
        id: "claude-code", displayLabel: "Claude Code",
        installationKind: .jsonHooks(entry: .typedCommand, nested: true),
        configurationPath: ".claude/settings.json",
        events: [
            .plain("UserPromptSubmit"), .matcher("PreToolUse", "*"), .matcher("PostToolUse", "*"),
            .matcher("PermissionRequest", "*", timeout: 21600), .matcher("Notification", "*"),
            .plain("Stop"), .plain("SubagentStop"), .plain("SessionStart"), .plain("SessionEnd"), .plain("PreCompact"),
        ], extraArgs: [])

    static let codex = AgentIntegrationProfile(
        id: "codex", displayLabel: "Codex",
        installationKind: .jsonHooks(entry: .typedCommand, nested: true),
        configurationPath: ".codex/hooks.json",
        events: [
            .timed("SessionStart", 5), .timed("UserPromptSubmit", 5), .timed("PreToolUse", 5),
            .timed("PostToolUse", 5), .timed("PermissionRequest", 21600), .timed("Stop", 5),
        ], extraArgs: [])

    static let gemini = AgentIntegrationProfile(
        id: "gemini", displayLabel: "Gemini CLI",
        installationKind: .jsonHooks(entry: .commandOnly, nested: false),
        configurationPath: ".gemini/settings.json",
        events: [.plain("PreToolUse"), .plain("PostToolUse"), .plain("Stop")], extraArgs: [])

    static let cursor = AgentIntegrationProfile(
        id: "cursor", displayLabel: "Cursor",
        installationKind: .cursorSettings,
        configurationPath: ".cursor/settings.json",
        events: [], extraArgs: [])

    static let cursorCli = AgentIntegrationProfile(
        id: "cursor-cli", displayLabel: "Cursor CLI",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".cursor/settings.json",
        events: [.plain("PreToolUse"), .plain("PostToolUse"), .plain("Notification"), .plain("Stop")], extraArgs: [])

    static let copilot = AgentIntegrationProfile(
        id: "copilot", displayLabel: "GitHub Copilot",
        installationKind: .jsonHooks(entry: .commandOnly, nested: false),
        configurationPath: ".config/github-copilot/hooks.json",
        events: [.plain("pre_tool_use"), .plain("post_tool_use"), .plain("session_start"), .plain("session_end")], extraArgs: [])

    static let trae = AgentIntegrationProfile(
        id: "trae", displayLabel: "Trae",
        installationKind: .yamlHooks,
        configurationPath: ".trae/config.yaml",
        events: [.plain("pre_tool_use"), .plain("post_tool_use"), .plain("session_start")], extraArgs: [])

    static let traeCli = AgentIntegrationProfile(
        id: "traecli", displayLabel: "Trae CLI",
        installationKind: .yamlHooks,
        configurationPath: ".trae/traecli.yaml",
        events: [.plain("UserPromptSubmit"), .plain("PreToolUse"), .plain("PostToolUse"), .plain("PermissionRequest"), .plain("Stop"), .plain("SessionStart"), .plain("SessionEnd")], extraArgs: [])

    static let traeCN = AgentIntegrationProfile(
        id: "traecn", displayLabel: "Trae CN",
        installationKind: .yamlHooks,
        configurationPath: ".trae-cn/config.yaml",
        events: [.plain("pre_tool_use"), .plain("post_tool_use"), .plain("session_start")], extraArgs: [])

    static let qoder = AgentIntegrationProfile(
        id: "qoder", displayLabel: "Qoder",
        installationKind: .jsonHooks(entry: .typedCommand, nested: true),
        configurationPath: ".qoder/settings.json",
        events: [.plain("UserPromptSubmit"), .matcher("PreToolUse", "*"), .matcher("PostToolUse", "*"),
                 .matcher("PostToolUseFailure", "*"), .matcher("PermissionRequest", "*"), .matcher("Notification", "*"),
                 .plain("Stop"), .plain("SessionStart"), .plain("SessionEnd"), .plain("PreCompact"),
                 .plain("SubagentStart"), .plain("SubagentStop")], extraArgs: [])

    static let qoderCli = AgentIntegrationProfile(
        id: "qoder-cli", displayLabel: "Qoder CLI",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".qoder/settings.json",
        events: [.plain("PreToolUse"), .plain("PostToolUse"), .plain("Notification"), .plain("Stop")], extraArgs: [])

    static let codebuddy = AgentIntegrationProfile(
        id: "codebuddy", displayLabel: "CodeBuddy",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".codebuddy/settings.json",
        events: [.plain("PreToolUse"), .plain("PostToolUse"), .plain("SessionStart"), .plain("SessionEnd")], extraArgs: [])

    static let codebuddyCN = AgentIntegrationProfile(
        id: "codebuddycn", displayLabel: "CodeBuddy CN",
        installationKind: .jsonHooks(entry: .commandOnly, nested: false),
        configurationPath: ".codybuddycn/settings.json",
        events: [.plain("PreToolUse"), .plain("PostToolUse"), .plain("Notification"), .plain("Stop")], extraArgs: [])

    static let qwen = AgentIntegrationProfile(
        id: "qwen", displayLabel: "Qwen",
        installationKind: .jsonHooks(entry: .commandOnly, nested: false),
        configurationPath: ".qwen/settings.json",
        events: [.plain("pre_tool_use"), .plain("post_tool_use"), .plain("session_start"), .plain("session_end")], extraArgs: [])

    static let kimi = AgentIntegrationProfile(
        id: "kimi", displayLabel: "Kimi",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".kimi/settings.json",
        events: [.plain("UserPromptSubmit"), .matcher("PreToolUse", "*"), .matcher("PostToolUse", "*"),
                 .matcher("Notification", "*"), .plain("Stop"), .plain("SessionStart"), .plain("SessionEnd"),
                 .matcher("PermissionRequest", "*", timeout: 86400)], extraArgs: [])

    static let deepseek = AgentIntegrationProfile(
        id: "deepseek", displayLabel: "DeepSeek",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".deepseek/settings.json",
        events: [.plain("PreToolUse"), .plain("PostToolUse"), .plain("Notification"), .plain("Stop")], extraArgs: [])

    static let opencode = AgentIntegrationProfile(
        id: "opencode", displayLabel: "OpenCode",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".opencode/settings.json",
        events: [.plain("SessionStart"), .plain("SessionEnd"), .plain("UserPromptSubmit"),
                 .plain("PreToolUse"), .plain("PostToolUse"), .plain("PermissionRequest"), .plain("Stop")], extraArgs: [])

    static let droid = AgentIntegrationProfile(
        id: "droid", displayLabel: "Factory / Droid",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".factory/settings.json",
        events: [.plain("PreToolUse"), .plain("PostToolUse"), .plain("Notification"), .plain("Stop")], extraArgs: [])

    static let stepfun = AgentIntegrationProfile(
        id: "stepfun", displayLabel: "StepFun",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".stepfun/settings.json",
        events: [.plain("PreToolUse"), .plain("PostToolUse"), .plain("Notification"), .plain("Stop")], extraArgs: [])

    static let antigravity = AgentIntegrationProfile(
        id: "antigravity", displayLabel: "AntiGravity",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".antigravity/settings.json",
        events: [.plain("PreToolUse"), .plain("PostToolUse"), .plain("Notification"), .plain("Stop")], extraArgs: [])

    static let workbuddy = AgentIntegrationProfile(
        id: "workbuddy", displayLabel: "WorkBuddy",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".workbuddy/hooks.json",
        events: [.plain("PreToolUse"), .plain("PostToolUse"), .plain("Notification"), .plain("Stop")], extraArgs: [])

    static let hermes = AgentIntegrationProfile(
        id: "hermes", displayLabel: "Hermes",
        installationKind: .pluginDirectory,
        configurationPath: ".hermes/plugins/agentguard",
        events: [.plain("SessionStart"), .plain("SessionEnd"), .plain("UserPromptSubmit"),
                 .plain("PreToolUse"), .plain("PostToolUse"), .plain("PostToolUseFailure"),
                 .plain("Notification"), .plain("Stop")], extraArgs: [])

    static let pi = AgentIntegrationProfile(
        id: "pi", displayLabel: "Pi",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".pi/hooks.json",
        events: [.plain("PreToolUse"), .plain("PostToolUse"), .plain("Notification"), .plain("Stop")], extraArgs: [])

    static let kiro = AgentIntegrationProfile(
        id: "kiro", displayLabel: "Kiro",
        installationKind: .unknown,
        configurationPath: ".kiro/agents/agentguard.json",
        events: [.timed("PreToolUse", 10000), .timed("PostToolUse", 10000), .timed("Notification", 10000),
                 .timed("Stop", 10000), .timed("SubagentStart", 10000), .timed("SubagentEnd", 10000)], extraArgs: [])

    static let openClaw = AgentIntegrationProfile(
        id: "openclaw", displayLabel: "OpenClaw",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".openclaw/settings.json",
        events: [.plain("SessionStart"), .plain("SessionEnd"), .plain("UserPromptSubmit"),
                 .plain("PreToolUse"), .plain("PostToolUse"), .plain("PermissionRequest"),
                 .plain("Notification"), .plain("Stop")], extraArgs: [])

    static let qClaw = AgentIntegrationProfile(
        id: "qclaw", displayLabel: "QClaw",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".qclaw/settings.json",
        events: AgentIntegrationProfile.openClaw.events, extraArgs: [])

    static let easyClaw = AgentIntegrationProfile(
        id: "easyclaw", displayLabel: "EasyClaw",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".easyclaw/settings.json",
        events: AgentIntegrationProfile.openClaw.events, extraArgs: [])

    static let autoClaw = AgentIntegrationProfile(
        id: "autoclaw", displayLabel: "AutoClaw",
        installationKind: .jsonHooks(entry: .typedCommand, nested: false),
        configurationPath: ".openclaw-autoclaw/settings.json",
        events: AgentIntegrationProfile.openClaw.events, extraArgs: [])

    static let allProfiles: [AgentIntegrationProfile] = [
        .claudeCode, .codex, .gemini, .cursor, .cursorCli, .copilot,
        .trae, .traeCli, .traeCN, .qoder, .qoderCli, .codebuddy, .codebuddyCN,
        .qwen, .kimi, .deepseek, .opencode, .droid, .stepfun, .antigravity,
        .workbuddy, .hermes, .pi, .kiro, .openClaw, .qClaw, .easyClaw, .autoClaw,
    ]
}
