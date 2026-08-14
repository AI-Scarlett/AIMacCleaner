import Foundation
import MacToolsPluginKit

/// Persists user-controlled state for the battery charge-limit plugin:
/// whether it's enabled, the charge ceiling, and the last mode.
@MainActor
final class BatteryChargeLimitStore: ObservableObject {
    private enum Key {
        static let isEnabled = "is-enabled"
        static let limitPercent = "limit-percent"
        static let mode = "mode"
    }

    private let storage: PluginStorage

    @Published private(set) var isEnabled: Bool
    @Published private(set) var limitPercent: Int
    @Published private(set) var mode: BatteryChargeMode

    init(storage: PluginStorage) {
        self.storage = storage

        // isEnabled — default off; user must opt in. We store the inverse of
        // "explicitly disabled" so the first launch is a clean disabled state.
        let storedIsEnabled = storage.object(forKey: Key.isEnabled) as? Bool
        self.isEnabled = storedIsEnabled ?? false

        // limitPercent — clamp to the supported range.
        let storedLimit = storage.object(forKey: Key.limitPercent) as? Int
        let initial = storedLimit ?? BatteryChargeLimits.defaultPercent
        self.limitPercent = max(
            BatteryChargeLimits.minimumPercent,
            min(BatteryChargeLimits.maximumPercent, initial)
        )

        // mode — default to .holdAtLimit (the plugin's main mode).
        if let raw = storage.string(forKey: Key.mode),
           let parsed = BatteryChargeMode(rawValue: raw) {
            self.mode = parsed
        } else {
            self.mode = .holdAtLimit
        }
    }

    // MARK: - Mutators

    func setEnabled(_ value: Bool) {
        guard isEnabled != value else { return }
        isEnabled = value
        storage.set(value, forKey: Key.isEnabled)
    }

    func setLimitPercent(_ value: Int) {
        let clamped = max(
            BatteryChargeLimits.minimumPercent,
            min(BatteryChargeLimits.maximumPercent, value)
        )
        guard limitPercent != clamped else { return }
        limitPercent = clamped
        storage.set(clamped, forKey: Key.limitPercent)
    }

    func setMode(_ value: BatteryChargeMode) {
        guard mode != value else { return }
        mode = value
        storage.set(value.rawValue, forKey: Key.mode)
    }
}
