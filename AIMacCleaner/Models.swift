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
    let processName: String?
    let toolInfo: String?

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

struct ProcessSnapshot: Codable {
    let timestamp: Date
    let pid: pid_t
    let ppid: pid_t
    let comm: String
    let args: String
}

struct CuratedRecord: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let agentName: String
    let operationType: String
    let targetPath: String
    let detail: String
    let fileSize: Int64
    let confidence: Double
    let evidence: String

    var confidenceLabel: String {
        if confidence >= 0.8 { return "高" }
        if confidence >= 0.5 { return "中" }
        return "低"
    }

    var confidenceColor: String {
        if confidence >= 0.8 { return "green" }
        if confidence >= 0.5 { return "orange" }
        return "red"
    }
}

struct DiscoveredProcess: Identifiable, Hashable {
    let id: String
    let comm: String
    let pids: [pid_t]
    let agentName: String?

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: DiscoveredProcess, rhs: DiscoveredProcess) -> Bool { lhs.id == rhs.id }
}

struct CustomAgentSource: Codable, Identifiable {
    var id: String { name }
    let name: String
    let searchPaths: [String]
    let addedAt: Date
}

struct DiscoveredAgent: Identifiable {
    let id: String
    let name: String
    let sessionCount: Int
    let latestActivity: Date?
    let projectDirs: [String]
    let dataPath: String
}

struct AgentOpRecord: Identifiable {
    let id: String
    let agentName: String
    let sessionId: String
    let projectDir: String
    let timestamp: Date
    let toolName: String
    let targetPath: String
    let opType: String
    let detail: String
}

struct TargetedFileOp: Identifiable {
    let id: String
    let timestamp: Date
    let processComm: String
    let processPid: pid_t
    let targetPath: String
    let opType: String
    let fileSize: Int64
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

struct IntelAppInfo: Identifiable {
    let id: String
    let name: String
    let displayName: String
    let path: String
    let architecture: BinaryArchitecture
    let appType: IntelAppType
    let size: Int64
    let version: String?
    let bundleId: String?
    var downloadURL: String?
    var homebrewARMName: String?
    var isSearching: Bool = false
    var searchError: String?
    var replaceState: ReplaceState = .idle
    var replaceProgress: Double = 0

    enum ReplaceState: Int {
        case idle = 0
        case uninstalling = 1
        case installing = 2
        case completed = 3
        case failed = 4

        var label: String {
            switch self {
            case .idle: return ""
            case .uninstalling: return "正在卸载..."
            case .installing: return "正在安装..."
            case .completed: return "已完成"
            case .failed: return "失败"
            }
        }

        var color: Color {
            switch self {
            case .idle: return .secondary
            case .uninstalling: return .orange
            case .installing: return .blue
            case .completed: return .green
            case .failed: return .red
            }
        }
    }

    var sizeFormatted: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }

    enum BinaryArchitecture: String, CaseIterable {
        case x86_64 = "Intel (x86_64)"
        case arm64 = "Apple Silicon (arm64)"
        case universal = "Universal"
        case unknown = "未知"
        case rosetta = "Rosetta 转译"

        var isIntel: Bool { self == .x86_64 || self == .rosetta }

        var icon: String {
            switch self {
            case .x86_64: "cpu"
            case .arm64: "cpu"
            case .universal: "arrow.triangle.2.circlepath"
            case .unknown: "questionmark.circle"
            case .rosetta: "arrow.right.arrow.left.circle"
            }
        }

        var color: Color {
            switch self {
            case .x86_64: .red
            case .arm64: .green
            case .universal: .blue
            case .unknown: .gray
            case .rosetta: .orange
            }
        }

        var badge: String {
            switch self {
            case .x86_64: "Intel"
            case .arm64: "ARM"
            case .universal: "通用"
            case .unknown: "?"
            case .rosetta: "转译"
            }
        }
    }

    enum IntelAppType: String, CaseIterable {
        case app = "应用程序"
        case cli = "命令行工具"
        case homebrew = "Homebrew 包"
        case framework = "框架/库"

        var icon: String {
            switch self {
            case .app: "app.badge"
            case .cli: "terminal"
            case .homebrew: "mug.is.full"
            case .framework: "building.columns"
            }
        }

        var color: Color {
            switch self {
            case .app: .cyan
            case .cli: .purple
            case .homebrew: .orange
            case .framework: .brown
            }
        }
    }
}
