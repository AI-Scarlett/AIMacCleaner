import Foundation

class SandboxPaths {
    static let shared = SandboxPaths()

    static let realHomeDirectory: String = {
        let directPath = FileManager.default.homeDirectoryForCurrentUser.path
        if directPath.hasPrefix("/Users/") && !directPath.contains("/Library/Containers/") {
            return directPath
        }
        if let containersRange = directPath.range(of: "/Library/Containers/") {
            let home = String(directPath[..<containersRange.lowerBound])
            if home.hasPrefix("/Users/") { return home }
        }
        let sandboxHome = NSHomeDirectory()
        if let containersRange = sandboxHome.range(of: "/Library/Containers/") {
            let home = String(sandboxHome[..<containersRange.lowerBound])
            if home.hasPrefix("/Users/") { return home }
        }
        return "/Users/" + NSUserName()
    }()

    let dataDirectory: String

    private init() {
        let fm = FileManager.default
        let appSupportDir: String

        if let containerURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            appSupportDir = containerURL.appendingPathComponent("AIMacCleaner").path
        } else {
            appSupportDir = SandboxPaths.realHomeDirectory + "/Library/Application Support/AIMacCleaner"
        }

        if !fm.fileExists(atPath: appSupportDir) {
            do {
                try fm.createDirectory(atPath: appSupportDir, withIntermediateDirectories: true)
            } catch {
                print("[AIMacCleaner] Failed to create data directory: \(error)")
            }
        }

        dataDirectory = appSupportDir
    }

    var ignoreListPath: String { dataDirectory + "/ignore.json" }
    var aiConfigPath: String { dataDirectory + "/ai.json" }
    var operationsPath: String { dataDirectory + "/operations_v2.json" }
    var curatedPath: String { dataDirectory + "/curated.json" }
    var monitorPath: String { dataDirectory + "/monitor.json" }
    var bookmarksPath: String { dataDirectory + "/bookmarks.json" }
    var scanBookmarksPath: String { dataDirectory + "/scan_bookmarks.json" }
    var tokenScopeBookmarksPath: String { dataDirectory + "/tokenscope_bookmarks.json" }
    var scannerCachePath: String { dataDirectory + "/scanner_cache_v1.json" }
    var tokenScopeCachePath: String { dataDirectory + "/tokenscope_cache_v1.json" }
    var agentMonitorCachePath: String { dataDirectory + "/agent_monitor_cache_v1.json" }
    var lastResponsePath: String { dataDirectory + "/last_response.txt" }
    var alertsPath: String { dataDirectory + "/alerts.json" }
    var alertRulePath: String { dataDirectory + "/alert_rule.json" }
    var protectedDirsPath: String { dataDirectory + "/protected_dirs.json" }
    var protectedTrashItemsPath: String { dataDirectory + "/protected_trash_items.json" }
    var lifecyclePath: String { dataDirectory + "/lifecycle.json" }
    var hourlyStatsPath: String { dataDirectory + "/hourly_stats.json" }
    var cmdRulesPath: String { dataDirectory + "/cmd_rules.json" }
    var customAgentSourcesPath: String { dataDirectory + "/custom_agents.json" }
    var snapshotsPath: String { dataDirectory + "/snapshots.json" }
    var captureShelfHistoryPath: String { dataDirectory + "/capture_shelf_history.json" }

    static func migrateFromLegacyPaths() {
        let fm = FileManager.default
        let home = SandboxPaths.realHomeDirectory

        let migrations: [(String, String)] = [
            (home + "/.aimaccleaner_ignore.json", shared.ignoreListPath),
            (home + "/.aimaccleaner_ai.json", shared.aiConfigPath),
            (home + "/.aimaccleaner_operations_v2.json", shared.operationsPath),
            (home + "/.aimaccleaner_curated.json", shared.curatedPath),
            (home + "/.aimaccleaner_monitor.json", shared.monitorPath),
            (home + "/.aimaccleaner_bookmarks.json", shared.bookmarksPath),
            (home + "/.aimaccleaner_scan_bookmarks.json", shared.scanBookmarksPath),
            (home + "/.aimaccleaner_tokenscope_bookmarks.json", shared.tokenScopeBookmarksPath),
            (home + "/.aimaccleaner_scanner_cache_v1.json", shared.scannerCachePath),
            (home + "/.aimaccleaner_tokenscope_cache_v1.json", shared.tokenScopeCachePath),
            (home + "/.aimaccleaner_agent_monitor_cache_v1.json", shared.agentMonitorCachePath),
            (home + "/.aimaccleaner_last_response.txt", shared.lastResponsePath),
            (home + "/.aimaccleaner_alerts.json", shared.alertsPath),
            (home + "/.aimaccleaner_alert_rule.json", shared.alertRulePath),
            (home + "/.aimaccleaner_protected_dirs.json", shared.protectedDirsPath),
            (home + "/.aimaccleaner_protected_trash_items.json", shared.protectedTrashItemsPath),
            (home + "/.aimaccleaner_lifecycle.json", shared.lifecyclePath),
            (home + "/.aimaccleaner_hourly_stats.json", shared.hourlyStatsPath),
            (home + "/.aimaccleaner_cmd_rules.json", shared.cmdRulesPath),
            (home + "/.aimaccleaner_custom_agents.json", shared.customAgentSourcesPath),
            (home + "/.aimaccleaner_snapshots.json", shared.snapshotsPath),
        ]

        for (legacyPath, newPath) in migrations {
            if fm.fileExists(atPath: legacyPath) && !fm.fileExists(atPath: newPath) {
                try? fm.moveItem(atPath: legacyPath, toPath: newPath)
            } else if fm.fileExists(atPath: legacyPath) && fm.fileExists(atPath: newPath) {
                try? fm.removeItem(atPath: legacyPath)
            }
        }
    }
}
