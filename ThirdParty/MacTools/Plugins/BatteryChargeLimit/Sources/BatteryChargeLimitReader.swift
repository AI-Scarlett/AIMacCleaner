import Foundation
import IOKit
import IOKit.ps

/// Reads the current battery snapshot from IOPS.
/// Mirrors the approach used by `SystemStatusSampler.collectBattery()` but is
/// scoped to only the fields this plugin cares about (level, charging state,
/// adapter presence), so it stays decoupled from the SystemStatus plugin.
@MainActor
final class BatteryChargeLimitReader: BatteryChargeLimitReading {

    init() {}

    func readSnapshot() -> BatterySnapshot {
        guard
            let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return .empty
        }

        var fallback: [String: Any]?
        var battery: [String: Any]?
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }
            fallback = fallback ?? desc
            if desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType {
                battery = desc
                break
            }
        }

        guard let description = battery ?? fallback else {
            return .empty
        }

        let maxCapacity = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
        let currentCapacity = min(max(description[kIOPSCurrentCapacityKey] as? Int ?? 0, 0), maxCapacity)
        let levelPercent = Int(round(Double(currentCapacity) / Double(maxCapacity) * 100.0))
        let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
        let isCharged = description[kIOPSIsChargedKey] as? Bool ?? false
        let powerSource = description[kIOPSPowerSourceStateKey] as? String ?? ""
        let isOnAdapter = powerSource == kIOPSACPowerValue

        let state: BatteryPowerState
        if isCharged || levelPercent >= 100 {
            state = .charged
        } else if isCharging {
            state = .charging
        } else if isOnAdapter {
            state = .acPower
        } else if powerSource == kIOPSBatteryPowerValue {
            state = .unplugged
        } else {
            state = .unknown
        }

        return BatterySnapshot(
            isAvailable: true,
            levelPercent: levelPercent,
            state: state,
            isOnAdapter: isOnAdapter
        )
    }
}
