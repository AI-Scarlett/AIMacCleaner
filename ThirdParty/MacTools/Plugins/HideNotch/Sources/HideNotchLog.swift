import Foundation
import OSLog

enum HideNotchLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools"

    static let controller = Logger(subsystem: subsystem, category: "HideNotchController")
    static let overlayManager = Logger(subsystem: subsystem, category: "HideNotchOverlayManager")

    static var isVerboseLoggingEnabled: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["MACTOOLS_VERBOSE_LOGS"] == "1"
        #else
        false
        #endif
    }
}
