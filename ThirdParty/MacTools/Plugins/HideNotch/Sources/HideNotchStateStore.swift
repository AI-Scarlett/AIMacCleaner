import Foundation
import MacToolsPluginKit

@MainActor
final class HideNotchStateStore: HideNotchStateStoring {
    private enum StorageKey {
        static let desiredEnabled = "hide-notch.enabled"
    }

    private let storage: PluginStorage
    private let legacyUserDefaults: UserDefaults
    private let obsoleteKeys = [
        "feature.hideNotchManagedWallpapers",
        "feature.hideNotchEnabled",
        "hide-notch.original-wallpaper-states",
        "hide-notch.managed-space-states"
    ]

    init(
        context: PluginRuntimeContext = PluginRuntimeContext(pluginID: "hide-notch"),
        userDefaults: UserDefaults? = nil
    ) {
        self.legacyUserDefaults = userDefaults ?? .standard
        self.storage = userDefaults.map {
            UserDefaultsPluginStorage(pluginID: context.pluginID, userDefaults: $0)
        } ?? context.storage
        storage.migrateValueIfNeeded(
            fromLegacyKey: StorageKey.desiredEnabled,
            to: StorageKey.desiredEnabled
        )
        removeObsoleteStateIfNeeded()
    }

    var desiredEnabled: Bool {
        get { storage.bool(forKey: StorageKey.desiredEnabled) }
        set { storage.set(newValue, forKey: StorageKey.desiredEnabled) }
    }

    private func removeObsoleteStateIfNeeded() {
        obsoleteKeys.forEach { legacyUserDefaults.removeObject(forKey: $0) }
    }
}
