import Foundation

@MainActor
final class AgentRegistry: ObservableObject {
    @Published var adapters: [any AgentAdapter] = []
    @Published var detectedTools: [DetectedTool] = []
    @Published var adapterStatuses: [String: AdapterStatus] = [:]
    @Published var installingAgentIds: Set<String> = []
    @Published var lastActionMessage: String?

    var hookInstaller = HookInstaller()
    private let unsupportedHookAgentIds: Set<String> = ["cursor"]

    var allAdapters: [any AgentAdapter] { adapters }

    var activeCount: Int {
        adapterStatuses.values.filter { $0 == .active }.count
    }

    var installedCount: Int {
        adapterStatuses.values.filter { $0 == .active || $0 == .installed }.count
    }

    var unavailableCount: Int {
        adapterStatuses.values.filter { $0 == .unavailable }.count
    }

    init() {
        registerAllAdapters()
    }

    func setHookInstaller(_ installer: HookInstaller) {
        self.hookInstaller = installer
    }

    private func registerAllAdapters() {
        adapters = [
            ClaudeCodeAdapter(),
            CodexAdapter(),
            GeminiAdapter(),
            CursorAdapter(),
            CursorCliAdapter(),
            CopilotAdapter(),
            TraeAdapter(),
            TraeCliAdapter(),
            TraeCNAdapter(),
            QoderAdapter(),
            QoderCliAdapter(),
            CodeBuddyAdapter(),
            CodeBuddyCNAdapter(),
            QwenAdapter(),
            KimiAdapter(),
            DeepSeekAdapter(),
            OpenCodeAdapter(),
            DroidAdapter(),
            StepFunAdapter(),
            AntiGravityAdapter(),
            WorkBuddyAdapter(),
            HermesAdapter(),
            PiAdapter(),
            KiroAdapter(),
            OpenClawAdapter(),
            QClawAdapter(),
            EasyClawAdapter(),
            AutoClawAdapter(),
        ]

        for adapter in adapters {
            adapterStatuses[adapter.name] = localStatus(for: adapter)
        }
    }

    private func localStatus(for adapter: any AgentAdapter) -> AdapterStatus {
        if adapter.hooksInstalled {
            return .active
        }
        return isLocallyInstalled(adapter) ? .installed : .unavailable
    }

    func status(for agentId: String) -> AdapterStatus {
        adapterStatuses[agentId] ?? .unavailable
    }

    func canInstallHooks(for agentId: String) -> Bool {
        !unsupportedHookAgentIds.contains(agentId)
    }

    func refreshAllStatuses() {
        Task {
            for adapter in adapters {
                let installed = isLocallyInstalled(adapter)
                if installed {
                    var hooksOk = true
                    for path in adapter.hookConfigPaths {
                        let health = await hookInstaller.checkHealth(at: path)
                        if health != .healthy {
                            hooksOk = false
                            break
                        }
                    }
                    adapterStatuses[adapter.name] = hooksOk ? .active : .installed
                } else {
                    adapterStatuses[adapter.name] = .unavailable
                }
            }

            await detectInstalledTools()
        }
    }

    func installHooks(for agentId: String) {
        guard !installingAgentIds.contains(agentId) else { return }
        guard canInstallHooks(for: agentId) else {
            lastActionMessage = "This agent does not support AgentGuard hooks yet."
            return
        }
        installingAgentIds.insert(agentId)
        lastActionMessage = nil
        Task {
            guard let adapter = adapters.first(where: { $0.name == agentId }) else {
                installingAgentIds.remove(agentId)
                lastActionMessage = "Unknown agent: \(agentId)"
                return
            }
            do {
                try await adapter.installHooks(installer: hookInstaller)
                adapterStatuses[agentId] = .active
                lastActionMessage = "\(adapter.displayName) connected"
            } catch {
                adapterStatuses[agentId] = localStatus(for: adapter)
                lastActionMessage = "\(adapter.displayName): \(error.localizedDescription)"
            }
            installingAgentIds.remove(agentId)
        }
    }

    func uninstallHooks(for agentId: String) {
        guard !installingAgentIds.contains(agentId) else { return }
        guard canInstallHooks(for: agentId) else {
            lastActionMessage = "This agent does not support AgentGuard hooks yet."
            return
        }
        installingAgentIds.insert(agentId)
        lastActionMessage = nil
        Task {
            guard let adapter = adapters.first(where: { $0.name == agentId }) else {
                installingAgentIds.remove(agentId)
                lastActionMessage = "Unknown agent: \(agentId)"
                return
            }
            do {
                try await adapter.removeHooks(installer: hookInstaller)
                adapterStatuses[agentId] = adapter.detectInstallation() ? .installed : .unavailable
                lastActionMessage = "\(adapter.displayName) disconnected"
            } catch {
                adapterStatuses[agentId] = localStatus(for: adapter)
                lastActionMessage = "\(adapter.displayName): \(error.localizedDescription)"
            }
            installingAgentIds.remove(agentId)
        }
    }

    func installAllAvailableHooks() {
        let candidates = adapters.filter { canInstallHooks(for: $0.name) && isLocallyInstalled($0) && adapterStatuses[$0.name] != .active }
        guard !candidates.isEmpty else { return }
        installingAgentIds.formUnion(candidates.map(\.name))
        lastActionMessage = nil
        Task {
            for adapter in candidates {
                do {
                    try await adapter.installHooks(installer: hookInstaller)
                    adapterStatuses[adapter.name] = .active
                } catch {
                    adapterStatuses[adapter.name] = localStatus(for: adapter)
                }
                installingAgentIds.remove(adapter.name)
            }
            lastActionMessage = "Agent connections updated"
        }
    }

    func detectInstalledTools() async {
        var detected: [DetectedTool] = []

        for adapter in adapters {
            let binary = profile(for: adapter.name)?.executable ?? adapter.name
            if let path = cliPath(for: binary) {
                detected.append(DetectedTool(agentId: adapter.name, binary: binary, path: path, displayName: adapter.displayName))
            } else if isLocallyInstalled(adapter) {
                detected.append(DetectedTool(agentId: adapter.name, binary: binary, path: displayPath(adapter.configRoot.path), displayName: adapter.displayName))
            }
        }

        self.detectedTools = detected.sorted { $0.displayName < $1.displayName }
    }

    private func profile(for agentId: String) -> AgentIntegrationProfile? {
        AgentIntegrationProfile.allProfiles.first { $0.agentId == agentId }
    }

    private func cliPath(for binary: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0,
               let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}

        let home = SandboxPaths.realHomeDirectory
        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
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
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    private func displayPath(_ path: String) -> String {
        let home = SandboxPaths.realHomeDirectory
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + String(path.dropFirst(home.count))
        }
        return path
    }

    private func isLocallyInstalled(_ adapter: any AgentAdapter) -> Bool {
        if adapter.detectInstallation() {
            return true
        }
        let configPath = adapter.configRoot.path
        if FileManager.default.fileExists(atPath: configPath) {
            return true
        }
        return adapter.hookConfigPaths.contains { FileManager.default.fileExists(atPath: $0.deletingLastPathComponent().path) }
    }

    func installHook(for agentId: String) async throws {
        guard let adapter = adapters.first(where: { $0.name == agentId }) else {
            throw AgentError.unknownAgent(agentId)
        }
        try await adapter.installHooks(installer: hookInstaller)
    }

    func uninstallHook(for agentId: String) async throws {
        guard let adapter = adapters.first(where: { $0.name == agentId }) else {
            throw AgentError.unknownAgent(agentId)
        }
        try await adapter.removeHooks(installer: hookInstaller)
    }

    func installAllHooks() async {
        for adapter in adapters where adapter.detectInstallation() {
            try? await adapter.installHooks(installer: hookInstaller)
        }
    }

    func healthCheck(for agentId: String) async -> HookInstallHealth {
        guard let adapter = adapters.first(where: { $0.name == agentId }) else {
            return .error
        }
        for path in adapter.hookConfigPaths {
            return await hookInstaller.checkHealth(at: path)
        }
        return .notInstalled
    }
}
