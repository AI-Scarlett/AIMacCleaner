import Foundation
import OSLog

enum PhysicalCleanModeLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools"

    static let plugin = Logger(subsystem: subsystem, category: "PhysicalCleanModePlugin")
    static let session = Logger(subsystem: subsystem, category: "PhysicalCleanModeSession")

    static var isVerboseLoggingEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MACTOOLS_VERBOSE_LOGS"] == "1"
        #else
        false
        #endif
    }
}
