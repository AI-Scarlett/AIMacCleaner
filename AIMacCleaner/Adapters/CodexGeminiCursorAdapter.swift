import Foundation

struct CodexAdapter: AgentAdapter {
    let name = "codex"
    let displayName = "Codex"
    let icon = "terminal"
    var configRoot: URL { userHome.appendingPathComponent(".codex") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("hooks.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("codex") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.codex.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct GeminiAdapter: AgentAdapter {
    let name = "gemini"
    let displayName = "Gemini CLI"
    let icon = "sparkles"
    var configRoot: URL { userHome.appendingPathComponent(".gemini") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("gemini") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.gemini.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct CursorAdapter: AgentAdapter {
    let name = "cursor"
    let displayName = "Cursor"
    let icon = "cursorarrow"
    var configRoot: URL { userHome.appendingPathComponent(".cursor") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("cursor") || detectApp(named: "Cursor") }
    var hooksInstalled: Bool { checkCursorYolo() }
    func installHooks(installer: HookInstaller) async throws {
        throw AgentError.hookInstallFailed("Cursor desktop does not expose compatible TraceFence hooks yet. Use Cursor CLI when available.")
    }
    func removeHooks(installer: HookInstaller) async throws {
        throw AgentError.hookUninstallFailed("Cursor desktop has no TraceFence hook to remove.")
    }

    private func checkCursorYolo() -> Bool {
        let path = userHome.appendingPathComponent("Library/Application Support/Cursor/User/settings.json")
        guard let data = try? Data(contentsOf: path),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return json["cursor.general.yoloMode"] as? Bool ?? false
    }
}

struct CursorCliAdapter: AgentAdapter {
    let name = "cursor-cli"
    let displayName = "Cursor CLI"
    let icon = "cursorarrow"
    var configRoot: URL { userHome.appendingPathComponent(".cursor") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("cursor") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.cursorCli.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}

struct CopilotAdapter: AgentAdapter {
    let name = "copilot"
    let displayName = "GitHub Copilot"
    let icon = "circle.dotted"
    var configRoot: URL { userHome.appendingPathComponent(".config/github-copilot") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("hooks.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }
    func detectInstallation() -> Bool { detectCLI("code") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }
    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.copilot.events, hookCommand: cmd)
    }
    func removeHooks(installer: HookInstaller) async throws { try await installer.removeJSONHooks(at: hookConfigPaths[0]) }
}
