import SwiftUI
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
    let subCategory: String
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

        var tabColor: Color {
            switch self {
            case .app: .cyan
            case .dependency: .orange
            case .other: .gray
            }
        }
    }

    var relatedPaths: [String] {
        let home = NSHomeDirectory()
        var paths: [String] = []
        if !appPath.hasSuffix(".app") && appPath.hasPrefix(home) {
            paths.append(appPath)
        }
        paths += [
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
        return paths
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
        var paths: [String] = []
        if !appPath.hasSuffix(".app") && appPath.hasPrefix(home) {
            paths.append(appPath)
        }
        paths += [
            "\(home)/Library/Application Support/\(bundleId)",
            "\(home)/Library/Preferences/\(bundleId).plist",
            "\(home)/Library/Saved Application State/\(bundleId).savedState",
            "\(home)/Library/Containers/\(bundleId)",
            "\(home)/Library/Logs/\(bundleId)",
            "\(home)/Library/Cookies/\(bundleId).binarycookies",
            "\(home)/Library/Group Containers/\(bundleId)",
        ]
        return paths
    }
}

struct OperationRecord: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let agentName: String
    let operationType: OperationType
    let targetPath: String
    let detail: String
    let fileSize: Int64

    enum OperationType: String, Codable, CaseIterable {
        case create = "创建"
        case modify = "修改"
        case delete = "删除"
        case move = "移动"
        case rename = "重命名"
        case read = "读取"

        var icon: String {
            switch self {
            case .create: "plus.circle.fill"
            case .modify: "pencil.circle.fill"
            case .delete: "trash.circle.fill"
            case .move: "arrow.right.circle.fill"
            case .rename: "text.cursor.input"
            case .read: "eye.circle.fill"
            }
        }

        var color: String {
            switch self {
            case .create: "green"
            case .modify: "blue"
            case .delete: "red"
            case .move: "orange"
            case .rename: "purple"
            case .read: "teal"
            }
        }
    }
}

struct HardwareInfo {
    var cpuUsage: Double
    var cpuCoreCount: Int
    var cpuTemperature: Double?
    var memoryTotal: Int64
    var memoryUsed: Int64
    var memoryFree: Int64
    var memoryPressure: Double
    var swapUsed: Int64
    var batteryPercent: Double?
    var batteryCharging: Bool
    var batteryTimeRemaining: Int?
    var processCount: Int
    var threadCount: Int
    var uptimeSeconds: Int64
    var networkInRate: Double
    var networkOutRate: Double

    var memoryTotalGb: Double { Double(memoryTotal) / 1073741824.0 }
    var memoryUsedGb: Double { Double(memoryUsed) / 1073741824.0 }
    var memoryFreeGb: Double { Double(memoryFree) / 1073741824.0 }
    var swapUsedGb: Double { Double(swapUsed) / 1073741824.0 }
    var memoryPressurePct: Double { memoryTotal > 0 ? Double(memoryUsed) / Double(memoryTotal) * 100.0 : 0 }
    var uptimeFormatted: String {
        let days = uptimeSeconds / 86400
        let hours = (uptimeSeconds % 86400) / 3600
        let mins = (uptimeSeconds % 3600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }
    var networkInFormatted: String { formatRate(networkInRate) }
    var networkOutFormatted: String { formatRate(networkOutRate) }

    private func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec < 1024 { return String(format: "%.0f B/s", bytesPerSec) }
        if bytesPerSec < 1048576 { return String(format: "%.1f KB/s", bytesPerSec / 1024) }
        return String(format: "%.1f MB/s", bytesPerSec / 1048576)
    }
}

struct SensorEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let sensorType: SensorType
    let processName: String
    let pid: Int32
    let bundleId: String?

    enum SensorType: String, CaseIterable {
        case camera = "摄像头"
        case microphone = "麦克风"

        var icon: String {
            switch self {
            case .camera: "video.fill"
            case .microphone: "mic.fill"
            }
        }

        var color: Color {
            switch self {
            case .camera: .red
            case .microphone: .blue
            }
        }
    }
}

struct StorageCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let size: Int64
    let path: String
    var files: [StorageFile]

    var sizeFormatted: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
}

struct StorageFile: Identifiable {
    let id: String
    let name: String
    let path: String
    let size: Int64
    let createdDate: Date?
    let modifiedDate: Date?
    let isDirectory: Bool
    var aiAnalysis: String?
    var riskLevel: FileRiskLevel = .unknown

    var sizeFormatted: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

    enum SortField: String, CaseIterable {
        case size = "大小"
        case created = "添加日期"
        case modified = "修改日期"
        case name = "名称"

        var icon: String {
            switch self {
            case .size: "arrow.up.arrow.down.circle"
            case .created: "calendar.badge.plus"
            case .modified: "calendar.badge.clock"
            case .name: "textformat"
            }
        }
    }
}
