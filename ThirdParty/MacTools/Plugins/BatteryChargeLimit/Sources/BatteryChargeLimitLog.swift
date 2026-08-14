import OSLog

enum BatteryChargeLimitLog {
    static let plugin = Logger(subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools", category: "BatteryChargeLimitPlugin")
    static let reader = Logger(subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools", category: "BatteryChargeLimitReader")
    static let writer = Logger(subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools", category: "BatteryChargeLimitWriter")
}
