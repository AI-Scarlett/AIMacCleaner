import Foundation

@MainActor
final class AgentRegistry: ObservableObject {
    @Published var adapters: [any AgentAdapter] = []
    @Published var detectedTools: [DetectedTool] = []
    @Published var adapterStatuses: [String: AdapterStatus] = [:]

    var hookInstaller = HookInstaller()

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
        return adapter.detectInstallation() ? .installed : .unavailable
    }

    func status(for agentId: String) -> AdapterStatus {
        adapterStatuses[agentId] ?? .unavailable
    }

    func refreshAllStatuses() {
        Task {
            for adapter in adapters {
                let installed = adapter.detectInstallation()
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
        Task {
            guard let adapter = adapters.first(where: { $0.name == agentId }) else { return }
            do {
                try await adapter.installHooks(installer: hookInstaller)
                adapterStatuses[agentId] = .active
            } catch {
                adapterStatuses[agentId] = localStatus(for: adapter)
            }
        }
    }

    func uninstallHooks(for agentId: String) {
        Task {
            guard let adapter = adapters.first(where: { $0.name == agentId }) else { return }
            do {
                try await adapter.removeHooks(installer: hookInstaller)
                adapterStatuses[agentId] = adapter.detectInstallation() ? .installed : .unavailable
            } catch {
                adapterStatuses[agentId] = localStatus(for: adapter)
            }
        }
    }

    func installAllAvailableHooks() {
        Task {
            for adapter in adapters where adapter.detectInstallation() {
                do {
                    try await adapter.installHooks(installer: hookInstaller)
                    adapterStatuses[adapter.name] = .active
                } catch {
                    adapterStatuses[adapter.name] = localStatus(for: adapter)
                }
            }
        }
    }

    func detectInstalledTools() async {
        var detected: [DetectedTool] = []

        await withTaskGroup(of: DetectedTool?.self) { group in
            for adapter in adapters {
                group.addTask {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
                    process.arguments = [adapter.name]
                    let pipe = Pipe()
                    process.standardOutput = pipe
                    process.standardError = FileHandle.nullDevice

                    do {
                        try process.run()
                        process.waitUntilExit()
                        if process.terminationStatus == 0,
                           let path = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                           !path.isEmpty {
                            return DetectedTool(agentId: adapter.name, binary: adapter.name, path: path, displayName: adapter.displayName)
                        }
                    } catch {}

                    return nil
                }
            }

            for await result in group {
                if let tool = result {
                    detected.append(tool)
                }
            }
        }

        self.detectedTools = detected.sorted { $0.displayName < $1.displayName }
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
