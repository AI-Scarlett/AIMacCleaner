import Foundation
import OSLog

enum MenuBarHiddenLog {
    static let plugin = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools",
        category: "MenuBarHiddenPlugin"
    )
}
