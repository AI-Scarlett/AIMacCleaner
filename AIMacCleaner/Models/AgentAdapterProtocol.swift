import Foundation

protocol AgentAdapter: Sendable, Identifiable {
    var name: String { get }
    var displayName: String { get }
    var icon: String { get }
    var configRoot: URL { get }
    var hookConfigPaths: [URL] { get }
    var status: AdapterStatus { get }

    func detectInstallation() -> Bool
    func installHooks(installer: HookInstaller) async throws
    func removeHooks(installer: HookInstaller) async throws
    func parseEvent(raw: [String: Any]) throws -> AgentHookEvent
    var hooksInstalled: Bool { get }
}

extension AgentAdapter {
    var id: String { name }

    func parseEvent(raw: [String: Any]) throws -> AgentHookEvent {
        if let event = AgentHookEvent.parse(from: raw) {
            return event
        }
        throw AgentError.unhandledEvent(raw["event"] as? String ?? "unknown")
    }
}