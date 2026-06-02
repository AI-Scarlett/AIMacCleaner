import Foundation

struct ClaudeCodeAdapter: AgentAdapter {
    let name = "claude-code"
    let displayName = "Claude Code"
    let icon = "cpu"
    var configRoot: URL { userHome.appendingPathComponent(".claude") }
    var hookConfigPaths: [URL] { [configRoot.appendingPathComponent("settings.json")] }
    var status: AdapterStatus { hooksInstalled ? .active : (detectInstallation() ? .installed : .unavailable) }
    private var userHome: URL { agentRealHomeURL() }

    func detectInstallation() -> Bool { detectCLI("claude") }
    var hooksInstalled: Bool { hookConfigPaths.contains { path in (try? String(contentsOf: path, encoding: .utf8))?.contains("agentguard-bridge") ?? false } }

    func installHooks(installer: HookInstaller) async throws {
        let bridgePath = try await installer.ensureBridgeBinary()
        let cmd = await installer.hookCommand(bridgePath: bridgePath, label: displayName, agentId: name)
        try await installer.injectJSONHooks(at: hookConfigPaths[0], events: AgentIntegrationProfile.claudeCode.events, hookCommand: cmd)
    }

    func removeHooks(installer: HookInstaller) async throws {
        try await installer.removeJSONHooks(at: hookConfigPaths[0])
    }
}

func detectCLI(_ binary: String) -> Bool {
    let fm = FileManager.default
    let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
        .split(separator: ":")
        .map(String.init)
    let home = SandboxPaths.realHomeDirectory
    let commonDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin",
        "\(home)/.local/bin",
        "\(home)/bin",
        "\(home)/.npm-global/bin",
        "\(home)/.bun/bin",
        "\(home)/.cargo/bin"
    ]
    for dir in Array(Set(pathEntries + commonDirs)) {
        let candidate = URL(fileURLWithPath: dir).appendingPathComponent(binary).path
        if fm.isExecutableFile(atPath: candidate) {
            return true
        }
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
    process.arguments = [binary]
    process.standardOutput = Pipe()
    process.standardError = FileHandle.nullDevice
    do { try process.run(); process.waitUntilExit(); return process.terminationStatus == 0 } catch { return false }
}

func detectAnyCLI(_ binaries: [String]) -> Bool {
    binaries.contains { detectCLI($0) }
}

func detectApp(named appName: String) -> Bool {
    let fm = FileManager.default
    let home = SandboxPaths.realHomeDirectory
    return [
        "/Applications/\(appName).app",
        "\(home)/Applications/\(appName).app",
    ].contains { fm.fileExists(atPath: $0) }
}

func detectAnyApp(_ appNames: [String]) -> Bool {
    appNames.contains { detectApp(named: $0) }
}

func agentRealHomeURL() -> URL {
    URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
}
