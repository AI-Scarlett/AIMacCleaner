import Foundation
import OSLog

enum DisplayBrightnessLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools"

    static let plugin = Logger(subsystem: subsystem, category: "DisplayBrightnessPlugin")
    static let controller = Logger(subsystem: subsystem, category: "DisplayBrightnessController")
    static let backend = Logger(subsystem: subsystem, category: "DisplayBrightnessBackend")
}
