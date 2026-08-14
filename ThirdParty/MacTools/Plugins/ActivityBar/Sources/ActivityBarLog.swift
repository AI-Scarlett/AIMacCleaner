import Foundation
import OSLog

enum ActivityBarLog {
    static let input = logger(category: "ActivityBarInput")
    static let socket = logger(category: "ActivityBarSocket")
    static let hooks = logger(category: "ActivityBarHooks")

    private static func logger(category: String) -> Logger {
        Logger(
            subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools",
            category: category
        )
    }
}
