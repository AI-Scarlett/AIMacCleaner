import Foundation

struct ScanItem: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let category: String
    let app: String
    let risk: String
    let riskDesc: String
    let path: String
    let realPath: String?
    let size: Int64
    let fileCount: Int
    var ignored: Bool
    var reason: String?
    var source: String?

    var riskLevel: RiskLevel { RiskLevel(rawValue: risk) ?? .caution }
    var sourceType: SourceType { SourceType(rawValue: source ?? "local") ?? .local }

    enum RiskLevel: String, Codable {
        case safe, caution, dangerous
        var label: String { ["safe": "安全", "caution": "注意", "dangerous": "危险"][rawValue] ?? "未知" }
        var systemImage: String { ["safe": "checkmark.circle.fill", "caution": "exclamationmark.triangle.fill", "dangerous": "xmark.circle.fill"][rawValue] ?? "questionmark.circle" }
        var color: String { ["safe": "green", "caution": "orange", "dangerous": "red"][rawValue] ?? "gray" }
    }

    enum SourceType: String, Codable {
        case local, ai
        var label: String { self == .ai ? "AI" : "本地" }
    }
}

struct DiskInfo: Codable {
    let total: Int64
    let used: Int64
    let free: Int64
    let totalGb: Double
    let usedGb: Double
    let freeGb: Double
    let usedPct: Double
}

struct AIConfig: Codable {
    let apiBase: String?
    let apiKey: String?
    let model: String?
    let hasKey: Bool?

    enum CodingKeys: String, CodingKey {
        case apiBase = "api_base", apiKey = "api_key", model, hasKey = "has_key"
    }
}

struct DeleteResult: Codable {
    let success: Bool
    let results: [DeleteItemResult]?
    let deleted: Int?
    let failed: Int?
}

struct DeleteItemResult: Codable {
    let id: String?
    let path: String?
    let success: Bool?
    let message: String?
}

struct AIStatus: Codable {
    let running: Bool
    let message: String?
}

struct IgnoreResult: Codable {
    let success: Bool
    let ignored: [String]?
}

struct AppInfo: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let desc: String
    let bundleId: String
    let appPath: String
    let iconPath: String?
    let version: String?
    let appSize: Int64
    let cacheSize: Int64
    let dataSize: Int64
    let totalSize: Int64
    let appType: AppType
    let risk: String
    let riskDesc: String
    let canUninstall: Bool
    let canClean: Bool
    let canReset: Bool

    enum AppType: String, Codable, CaseIterable {
        case app = "app"
        case dependency = "dependency"
        case other = "other"

        var label: String {
            switch self {
            case .app: "应用"
            case .dependency: "依赖"
            case .other: "其它"
            }
        }

        var tabLabel: String {
            switch self {
            case .app: "APP 管理"
            case .dependency: "依赖管理"
            case .other: "其它工具"
            }
        }

        var tabIcon: String {
            switch self {
            case .app: "app.badge"
            case .dependency: "cube.box"
            case .other: "terminal"
            }
        }
    }

    var relatedPaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Caches/\(bundleId)",
            "\(home)/Library/Application Support/\(bundleId)",
            "\(home)/Library/Preferences/\(bundleId).plist",
            "\(home)/Library/Saved Application State/\(bundleId).savedState",
            "\(home)/Library/Containers/\(bundleId)",
            "\(home)/Library/Logs/\(bundleId)",
            "\(home)/Library/HTTPStorages/\(bundleId)",
            "\(home)/Library/WebKit/\(bundleId)",
            "\(home)/Library/Cookies/\(bundleId).binarycookies",
            "\(home)/Library/Group Containers/\(bundleId)",
        ]
    }

    var cachePaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Caches/\(bundleId)",
            "\(home)/Library/HTTPStorages/\(bundleId)",
            "\(home)/Library/WebKit/\(bundleId)",
        ]
    }

    var dataPaths: [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Application Support/\(bundleId)",
            "\(home)/Library/Preferences/\(bundleId).plist",
            "\(home)/Library/Saved Application State/\(bundleId).savedState",
            "\(home)/Library/Containers/\(bundleId)",
            "\(home)/Library/Logs/\(bundleId)",
            "\(home)/Library/Cookies/\(bundleId).binarycookies",
            "\(home)/Library/Group Containers/\(bundleId)",
        ]
    }
}
