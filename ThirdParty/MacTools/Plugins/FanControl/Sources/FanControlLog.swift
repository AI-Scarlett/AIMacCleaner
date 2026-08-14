import OSLog

enum FanControlLog {
    static let plugin = Logger(subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools", category: "FanControlPlugin")
    static let smc = Logger(subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools", category: "FanControlSMC")
    static let writer = Logger(subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools", category: "FanControlWriter")
}
