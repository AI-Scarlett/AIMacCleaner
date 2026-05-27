import Foundation

struct TraeAdapter: AgentAdapter {
    let name = "trae"
    let displayName = "Trae"
    let icon = "t.square"
    var configRoot: URL { userHome.appendingPathComponent(".trae") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("config.yaml")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { FileManager.default.homeDirectoryForCurrentUser }
    func detectInstallation() -> Bool { detectCLI("trae") || detectApp(named: "Trae") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectYAMLHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.trae.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeYAMLHooks(at: hookConfigPaths[0]) }
}

struct TraeCliAdapter: AgentAdapter {
    let name = "traecli"
    let displayName = "Trae CLI"
    let icon = "t.square.fill"
    var configRoot: URL { userHome.appendingPathComponent(".trae") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("traecli.yaml")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { FileManager.default.homeDirectoryForCurrentUser }
    func detectInstallation() -> Bool { detectAnyCLI(["trae", "trae-cli", "traecli"]) || detectApp(named: "Trae") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectYAMLHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.traeCli.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeYAMLHooks(at: hookConfigPaths[0]) }
}

struct TraeCNAdapter: AgentAdapter {
    let name = "traecn"
    let displayName = "Trae CN"
    let icon = "t.square"
    var configRoot: URL { userHome.appendingPathComponent(".trae-cn") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("config.yaml")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { FileManager.default.homeDirectoryForCurrentUser }
    func detectInstallation() -> Bool { detectCLI("trae-cn") || detectApp(named: "Trae CN") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectYAMLHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.traeCN.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeYAMLHooks(at: hookConfigPaths[0]) }
}

struct QoderAdapter: AgentAdapter {
    let name = "qoder"
    let displayName = "Qoder"
    let icon = "q.square"
    var configRoot: URL { userHome.appendingPathComponent(".qoder") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { FileManager.default.homeDirectoryForCurrentUser }
    func detectInstallation() -> Bool { detectCLI("qoder") || detectApp(named: "Qoder") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.qoder.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct QoderCliAdapter: AgentAdapter {
    let name = "qoder-cli"
    let displayName = "Qoder CLI"
    let icon = "q.square.fill"
    var configRoot: URL { userHome.appendingPathComponent(".qoder") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { FileManager.default.homeDirectoryForCurrentUser }
    func detectInstallation() -> Bool { detectCLI("qoder") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.qoderCli.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct CodeBuddyAdapter: AgentAdapter {
    let name = "codebuddy"
    let displayName = "CodeBuddy"
    let icon = "b.square"
    var configRoot: URL { userHome.appendingPathComponent(".codebuddy") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { FileManager.default.homeDirectoryForCurrentUser }
    func detectInstallation() -> Bool { detectCLI("codebuddy") || detectApp(named: "CodeBuddy") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.codebuddy.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct CodeBuddyCNAdapter: AgentAdapter {
    let name = "codebuddycn"
    let displayName = "CodeBuddy CN"
    let icon = "b.square.fill"
    var configRoot: URL { userHome.appendingPathComponent(".codybuddycn") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { FileManager.default.homeDirectoryForCurrentUser }
    func detectInstallation() -> Bool { detectAnyCLI(["codybuddycn", "codebuddy-cn"]) || detectAnyApp(["CodeBuddy CN", "CodyBuddyCN"]) }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.codebuddyCN.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}
