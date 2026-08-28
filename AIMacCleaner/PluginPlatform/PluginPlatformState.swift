import Combine
import Foundation

/// The package lifecycle is independent from commerce and runtime state.
enum TraceFencePluginInstallationState: Equatable {
    case notInstalled
    case downloading(targetVersion: String)
    case installing(targetVersion: String)
    case updating(installedVersion: String, targetVersion: String)
    case installed(version: String, enabled: Bool, restartRequired: Bool)
    case updateAvailable(installedVersion: String, targetVersion: String, enabled: Bool)
    case failed(message: String, installedVersion: String?)

    var installedVersion: String? {
        switch self {
        case let .installed(version, _, _):
            return version
        case let .updateAvailable(version, _, _):
            return version
        case let .failed(_, version):
            return version
        case let .updating(installedVersion, _):
            return installedVersion
        case .notInstalled, .downloading, .installing:
            return nil
        }
    }
}
/// Runtime state is intentionally separate from installation. Installed code
/// has zero background cost until the user opens or enables it.
enum TraceFencePluginRuntimeState: Equatable {
    case unavailable
    case disabled
    case idle
    case loading
    case active
    case failed(String)
    case restartRequired
}

struct TraceFencePluginPlatformSnapshot: Equatable, Identifiable {
    let pluginID: String
    let catalogVersion: String
    let entitlement: TraceFencePluginAccessState
    let installation: TraceFencePluginInstallationState
    let runtime: TraceFencePluginRuntimeState

    var id: String { pluginID }

    var hasCompatibleUpdate: Bool {
        if case .updateAvailable = installation { return true }
        return false
    }
}

enum TraceFencePluginPlatformSection: String, CaseIterable, Identifiable {
    case discover
    case library
    case updates

    var id: String { rawValue }
}

/// A store never presents plugin UI itself. It sends a launch request to the
/// application shell, which chooses the appropriate workspace or menu-bar
/// surface and can dismiss Settings before showing it.
struct TraceFencePluginPresentationRequest: Identifiable, Equatable {
    let id = UUID()
    let pluginID: String?
}

@MainActor
final class TraceFencePluginPresentationCenter: ObservableObject {
    static let shared = TraceFencePluginPresentationCenter()

    @Published private(set) var request: TraceFencePluginPresentationRequest?
    @Published private(set) var storeRequestID: UUID?

    private init() {}

    func open(pluginID: String) {
        request = TraceFencePluginPresentationRequest(pluginID: pluginID)
    }

    func openPluginWorkspace() {
        request = TraceFencePluginPresentationRequest(pluginID: nil)
    }

    func openStore() {
        storeRequestID = UUID()
    }

    func consume(requestID: UUID) {
        guard request?.id == requestID else { return }
        request = nil
    }

    func consumeStoreRequest(requestID: UUID) {
        guard storeRequestID == requestID else { return }
        storeRequestID = nil
    }
}

enum TraceFencePluginDisplayPreferences {
    static let pinnedPluginIDsKey = "traceFence.plugins.pinnedIDs"
    static let defaultPinnedPluginIDs = ["tracefence.tools.fan-control"]
    static let defaultPinnedPluginIDsJSON = "[\"tracefence.tools.fan-control\"]"
    static let mainTabPluginIDsKey = "traceFence.plugins.mainTabIDs"
    static let defaultMainTabPluginIDsJSON = "[]"

    static func pinnedPluginIDs(from rawValue: String) -> [String] {
        guard let data = rawValue.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return defaultPinnedPluginIDs
        }
        return values
    }

    static func encodedPinnedPluginIDs(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    static func mainTabPluginIDs(from rawValue: String) -> [String] {
        guard let data = rawValue.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    static func encodedMainTabPluginIDs(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values),
              let string = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return string
    }

    static func remove(pluginID: String, userDefaults: UserDefaults = .standard) {
        let pinned = pinnedPluginIDs(
            from: userDefaults.string(forKey: pinnedPluginIDsKey) ?? defaultPinnedPluginIDsJSON
        ).filter { $0 != pluginID }
        userDefaults.set(encodedPinnedPluginIDs(pinned), forKey: pinnedPluginIDsKey)

        let mainTabs = mainTabPluginIDs(
            from: userDefaults.string(forKey: mainTabPluginIDsKey) ?? defaultMainTabPluginIDsJSON
        ).filter { $0 != pluginID }
        userDefaults.set(encodedMainTabPluginIDs(mainTabs), forKey: mainTabPluginIDsKey)
    }
}
