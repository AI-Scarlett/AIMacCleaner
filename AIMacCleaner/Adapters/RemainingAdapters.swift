import Foundation

struct QwenAdapter: AgentAdapter {
    let name = "qwen"
    let displayName = "Qwen"
    let icon = "brain"
    var configRoot: URL { userHome.appendingPathComponent(".qwen") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("qwen") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.qwen.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct KimiAdapter: AgentAdapter {
    let name = "kimi"
    let displayName = "Kimi"
    let icon = "k.circle"
    var configRoot: URL { userHome.appendingPathComponent(".kimi") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("kimi") || detectApp(named: "Kimi") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.kimi.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct DeepSeekAdapter: AgentAdapter {
    let name = "deepseek"
    let displayName = "DeepSeek"
    let icon = "d.square"
    var configRoot: URL { userHome.appendingPathComponent(".deepseek") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("deepseek") || detectApp(named: "DeepSeek") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.deepseek.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct OpenCodeAdapter: AgentAdapter {
    let name = "opencode"
    let displayName = "OpenCode"
    let icon = "o.circle"
    var configRoot: URL { userHome.appendingPathComponent(".opencode") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("opencode") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.opencode.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct DroidAdapter: AgentAdapter {
    let name = "droid"
    let displayName = "Factory / Droid"
    let icon = "f.circle"
    var configRoot: URL { userHome.appendingPathComponent(".factory") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("droid") || detectApp(named: "Factory") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.droid.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct StepFunAdapter: AgentAdapter {
    let name = "stepfun"
    let displayName = "StepFun"
    let icon = "s.square"
    var configRoot: URL { userHome.appendingPathComponent(".stepfun") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("stepfun") || detectApp(named: "StepFun") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.stepfun.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct AntiGravityAdapter: AgentAdapter {
    let name = "antigravity"
    let displayName = "AntiGravity"
    let icon = "a.circle"
    var configRoot: URL { userHome.appendingPathComponent(".antigravity") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("antigravity") || detectApp(named: "Antigravity") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.antigravity.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct WorkBuddyAdapter: AgentAdapter {
    let name = "workbuddy"
    let displayName = "WorkBuddy"
    let icon = "w.square"
    var configRoot: URL { userHome.appendingPathComponent(".workbuddy") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("hooks.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("workbuddy") || detectApp(named: "WorkBuddy") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.workbuddy.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct HermesAdapter: AgentAdapter {
    let name = "hermes"
    let displayName = "Hermes"
    let icon = "h.square"
    var configRoot: URL { userHome.appendingPathComponent(".hermes") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("plugins/agentguard")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("hermes") || detectApp(named: "Hermes") }
    var hooksInstalled: Bool {
        let dir = configRoot.appendingPathComponent("plugins/agentguard")
        let yamlPath = dir.appendingPathComponent("plugin.yaml")
        return (try? String(contentsOf: yamlPath, encoding: .utf8))?.contains("agentguard-bridge") ?? false
    }
    func installHooks(installer: HookInstaller) async throws {
        let dir = configRoot.appendingPathComponent("plugins/agentguard")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        var lines = ["# [AGENTGUARD-START]", "hooks:"]
        for event in AgentIntegrationProfile.hermes.events {
            lines.append("  \(event.name):")
            lines.append("    command: \"\(cmd)\"")
        }
        lines.append("# [AGENTGUARD-END]")
        try lines.joined(separator: "\n").write(to: dir.appendingPathComponent("plugin.yaml"), atomically: true, encoding: .utf8)
    }
    func removeHooks(installer: HookInstaller) async throws {
        let dir = configRoot.appendingPathComponent("plugins/agentguard")
        let yamlPath = dir.appendingPathComponent("plugin.yaml")
        if FileManager.default.fileExists(atPath: yamlPath.path) {
            try FileManager.default.removeItem(at: yamlPath)
        }
    }
}

struct PiAdapter: AgentAdapter {
    let name = "pi"
    let displayName = "Pi"
    let icon = "p.circle"
    var configRoot: URL { userHome.appendingPathComponent(".pi") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("hooks.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("pi") || detectApp(named: "Pi") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.pi.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct KiroAdapter: AgentAdapter {
    let name = "kiro"
    let displayName = "Kiro"
    let icon = "k.square"
    var configRoot: URL { userHome.appendingPathComponent(".kiro") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("agents/agentguard.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectAnyCLI(["kiro-cli", "kiro"]) || detectApp(named: "Kiro") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let dir = configRoot.appendingPathComponent("agents")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        let config: [String: Any] = ["name": "agentguard", "command": cmd]
        let data = try JSONSerialization.data(withJSONObject: config, options: .prettyPrinted)
        try data.write(to: hookConfigPaths[0])
    }
    func removeHooks(installer: HookInstaller) async throws {
        if FileManager.default.fileExists(atPath: hookConfigPaths[0].path) {
            try FileManager.default.removeItem(at: hookConfigPaths[0])
        }
    }
}

struct OpenClawAdapter: AgentAdapter {
    let name = "openclaw"
    let displayName = "OpenClaw"
    let icon = "o.square"
    var configRoot: URL { userHome.appendingPathComponent(".openclaw") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("openclaw") || detectApp(named: "OpenClaw") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.openClaw.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct QClawAdapter: AgentAdapter {
    let name = "qclaw"
    let displayName = "QClaw"
    let icon = "q.square"
    var configRoot: URL { userHome.appendingPathComponent(".qclaw") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("qclaw") || detectApp(named: "QClaw") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.qClaw.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct EasyClawAdapter: AgentAdapter {
    let name = "easyclaw"
    let displayName = "EasyClaw"
    let icon = "e.square"
    var configRoot: URL { userHome.appendingPathComponent(".easyclaw") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("easyclaw") || detectApp(named: "EasyClaw") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.easyClaw.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct AutoClawAdapter: AgentAdapter {
    let name = "autoclaw"
    let displayName = "AutoClaw"
    let icon = "a.square"
    var configRoot: URL { userHome.appendingPathComponent(".openclaw-autoclaw") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("autoclaw") || detectApp(named: "AutoClaw") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.autoClaw.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}
