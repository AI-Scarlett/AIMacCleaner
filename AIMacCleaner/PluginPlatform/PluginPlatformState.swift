import Foundation

/// The package lifecycle is independent from commerce and runtime state.
enum TraceFencePluginInstallationState: Equatable {
    case notInstalled
    case downloading(targetVersion: String)
    case installing(targetVersion: String)
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
