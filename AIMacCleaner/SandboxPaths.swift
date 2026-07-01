import Foundation

class SandboxPaths {
    static let shared = SandboxPaths()
    static let directDistributionBundleID = "com.tracefence.app"

    static var isDirectDistribution: Bool {
        Bundle.main.bundleIdentifier == directDistributionBundleID
    }

    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

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
            appSupportDir = containerURL.appendingPathComponent("TraceFence").path
        } else {
            appSupportDir = SandboxPaths.realHomeDirectory + "/Library/Application Support/TraceFence"
        }

        if !fm.fileExists(atPath: appSupportDir) {
            do {
                try fm.createDirectory(atPath: appSupportDir, withIntermediateDirectories: true)
            } catch {
                print("[TraceFence] Failed to create data directory: \(error)")
            }
        }

        SandboxPaths.copyLegacySupportDirectories(to: appSupportDir)

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
            (home + "/.tracefence_ignore.json", shared.ignoreListPath),
            (home + "/.tracefence_ai.json", shared.aiConfigPath),
            (home + "/.tracefence_operations_v2.json", shared.operationsPath),
            (home + "/.tracefence_curated.json", shared.curatedPath),
            (home + "/.tracefence_monitor.json", shared.monitorPath),
            (home + "/.tracefence_bookmarks.json", shared.bookmarksPath),
            (home + "/.tracefence_scan_bookmarks.json", shared.scanBookmarksPath),
            (home + "/.tracefence_tokenscope_bookmarks.json", shared.tokenScopeBookmarksPath),
            (home + "/.tracefence_scanner_cache_v1.json", shared.scannerCachePath),
            (home + "/.tracefence_tokenscope_cache_v1.json", shared.tokenScopeCachePath),
            (home + "/.tracefence_agent_monitor_cache_v1.json", shared.agentMonitorCachePath),
            (home + "/.tracefence_last_response.txt", shared.lastResponsePath),
            (home + "/.tracefence_alerts.json", shared.alertsPath),
            (home + "/.tracefence_alert_rule.json", shared.alertRulePath),
            (home + "/.tracefence_protected_dirs.json", shared.protectedDirsPath),
            (home + "/.tracefence_protected_trash_items.json", shared.protectedTrashItemsPath),
            (home + "/.tracefence_lifecycle.json", shared.lifecyclePath),
            (home + "/.tracefence_hourly_stats.json", shared.hourlyStatsPath),
            (home + "/.tracefence_cmd_rules.json", shared.cmdRulesPath),
            (home + "/.tracefence_custom_agents.json", shared.customAgentSourcesPath),
            (home + "/.tracefence_snapshots.json", shared.snapshotsPath),
        ]

        for (legacyPath, newPath) in migrations {
            guard fm.fileExists(atPath: legacyPath) else { continue }
            if bookmarkFileNames.contains((newPath as NSString).lastPathComponent) {
                mergeBookmarkFile(from: legacyPath, into: newPath)
            } else if !fm.fileExists(atPath: newPath) {
                try? fm.copyItem(atPath: legacyPath, toPath: newPath)
            }
        }
    }

    private static let managedFileNames = [
        "ignore.json",
        "ai.json",
        "operations_v2.json",
        "curated.json",
        "monitor.json",
        "bookmarks.json",
        "scan_bookmarks.json",
        "tokenscope_bookmarks.json",
        "scanner_cache_v1.json",
        "tokenscope_cache_v1.json",
        "agent_monitor_cache_v1.json",
        "last_response.txt",
        "alerts.json",
        "alert_rule.json",
        "protected_dirs.json",
        "protected_trash_items.json",
        "lifecycle.json",
        "hourly_stats.json",
        "cmd_rules.json",
        "custom_agents.json",
        "snapshots.json"
    ]

    private static let bookmarkFileNames: Set<String> = [
        "bookmarks.json",
        "scan_bookmarks.json",
        "tokenscope_bookmarks.json"
    ]

    private static func copyLegacySupportDirectories(to targetDirectory: String) {
        let fm = FileManager.default
        let home = realHomeDirectory
        let legacyDirectories = [
            home + "/Library/Application Support/AIMacCleaner",
            home + "/Library/Application Support/AgentGuard",
            home + "/Library/Containers/com.aimaccleaner.app/Data/Library/Application Support/AIMacCleaner",
            home + "/Library/Containers/com.aimaccleaner.app/Data/Library/Application Support/AgentGuard",
            home + "/Library/Containers/com.tracefence.app/Data/Library/Application Support/TraceFence"
        ]

        for legacyDirectory in legacyDirectories {
            guard legacyDirectory != targetDirectory,
                  fm.fileExists(atPath: legacyDirectory) else {
                continue
            }
            for fileName in managedFileNames {
                let oldPath = (legacyDirectory as NSString).appendingPathComponent(fileName)
                let newPath = (targetDirectory as NSString).appendingPathComponent(fileName)
                guard fm.fileExists(atPath: oldPath) else { continue }
                if bookmarkFileNames.contains(fileName) {
                    mergeBookmarkFile(from: oldPath, into: newPath)
                } else if !fm.fileExists(atPath: newPath) {
                    try? fm.copyItem(atPath: oldPath, toPath: newPath)
                }
            }
        }
    }

    private static func mergeBookmarkFile(from oldPath: String, into newPath: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: oldPath),
              let oldData = try? Data(contentsOf: URL(fileURLWithPath: oldPath)),
              let oldBookmarks = try? JSONDecoder().decode([String: Data].self, from: oldData) else {
            return
        }

        var merged: [String: Data] = [:]
        if let newData = try? Data(contentsOf: URL(fileURLWithPath: newPath)),
           let newBookmarks = try? JSONDecoder().decode([String: Data].self, from: newData) {
            merged = newBookmarks
        }

        var changed = false
        for (path, data) in oldBookmarks where merged[path] == nil {
            merged[path] = data
            changed = true
        }

        guard changed || !fm.fileExists(atPath: newPath),
              let encoded = try? JSONEncoder().encode(merged) else {
            return
        }
        try? encoded.write(to: URL(fileURLWithPath: newPath), options: .atomic)
    }
}
