import Foundation
#if !TRACEFENCE_CODEX_MEDIA_WORKER
import MacToolsPluginKit
#endif

enum CodexMediaCleanupPhase: Equatable, Sendable {
    case idle
    case scanning
    case scanned
    case waitingForCodex
    case cleaning
    case repairing
    case cleaningAndRepairing
    case completed
}

enum CodexMediaOperation: String, CaseIterable, Codable, Equatable, Sendable {
    case cleanup
    case repair
    case cleanupAndRepair

    var performsCleanup: Bool {
        self == .cleanup || self == .cleanupAndRepair
    }

    var performsRepair: Bool {
        self == .repair || self == .cleanupAndRepair
    }

    var phase: CodexMediaCleanupPhase {
        switch self {
        case .cleanup: .cleaning
        case .repair: .repairing
        case .cleanupAndRepair: .cleaningAndRepairing
        }
    }
}

enum CodexMediaLogLevel: String, Equatable, Sendable {
    case info
    case success
    case warning
    case error
}

struct CodexMediaLogEntry: Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let level: CodexMediaLogLevel
    let message: String
}

struct CodexMediaScanReport: Equatable, Sendable {
    var scannedFiles = 0
    var affectedFiles = 0
    var malformedFiles = 0
    var resourceLimitedFiles = 0
    var inlineImageOccurrences = 0
    var uniqueImageCount = 0
    var reclaimableOccurrences = 0
    var retainedEffectiveOccurrences = 0
    var invalidEffectiveFileURLs = 0
    var missingMediaObjects = 0
    var estimatedReclaimableBytes: Int64 = 0
    var scannedBytes: Int64 = 0
    var completedAt = Date()

    var needsCleanup: Bool { reclaimableOccurrences > 0 }
    var needsRepair: Bool { invalidEffectiveFileURLs > 0 }
    var needsWork: Bool { needsCleanup || needsRepair }
}

struct CodexMediaRepairReport: Equatable, Codable, Sendable {
    struct FileResult: Equatable, Codable, Sendable {
        let path: String
        let backupPath: String
        let originalSHA256: String
        let repairedSHA256: String
        let replacedStaleDataURLs: Int
        let restoredEffectiveImageURLs: Int
        let createdMediaObjects: Int
        let reboundLocalPaths: Int
        let reclaimedBytes: Int64
    }

    let runID: String
    let operation: CodexMediaOperation
    let startedAt: Date
    let completedAt: Date
    let files: [FileResult]
    let skippedFiles: [String]
    let reportPath: String

    var repairedFileCount: Int { files.count }
    var replacementCount: Int { files.reduce(0) { $0 + $1.replacedStaleDataURLs } }
    var restorationCount: Int { files.reduce(0) { $0 + $1.restoredEffectiveImageURLs } }
    var reclaimedBytes: Int64 { files.reduce(0) { $0 + $1.reclaimedBytes } }
}

struct CodexMediaWorkerResponse: Codable, Sendable {
    let result: CodexMediaRepairReport.FileResult?
    let error: String?
}

struct CodexMediaCleanupSnapshot: Equatable, Sendable {
    var phase: CodexMediaCleanupPhase = .idle
    var scanReport: CodexMediaScanReport?
    var repairReport: CodexMediaRepairReport?
    var activeOperation: CodexMediaOperation?
    var lastOperation: CodexMediaOperation?
    var completedFiles = 0
    var totalFiles = 0
    var currentFile = ""
    var includeArchivedSessions = true
    var errorMessage: String?
    var logs: [CodexMediaLogEntry] = []
    var requiresRestartValidation = false
    var codexRestarted = false
    var historyConversationValidated = false

    var isBusy: Bool {
        switch phase {
        case .scanning, .waitingForCodex, .cleaning, .repairing, .cleaningAndRepairing: true
        default: false
        }
    }
}

enum CodexMediaCleanupError: LocalizedError, Equatable {
    case invalidCodexHome(String)
    case malformedJSON(path: String, line: Int)
    case recordTooLarge(path: String, line: Int, bytes: Int, limit: Int)
    case invalidDataImage
    case unsupportedImageType(String)
    case unsafeMediaReference(String)
    case missingMediaObject(String)
    case corruptMediaObject(String)
    case fileIsOpen(String)
    case backupVerificationFailed(String)
    case outputVerificationFailed(String)
    case atomicReplaceFailed(String)
    case workerUnavailable(String)
    case workerFailed(path: String, detail: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case let .invalidCodexHome(path): "Codex 数据目录不可用：\(path)"
        case let .malformedJSON(path, line): "会话 JSON 已损坏：\(path) 第 \(line) 行"
        case let .recordTooLarge(path, line, bytes, limit):
            "会话记录超过安全处理上限：\(path) 第 \(line) 行（\(bytes) 字节，上限 \(limit) 字节）"
        case .invalidDataImage: "发现无法解码的 data:image Base64 图片"
        case let .unsupportedImageType(type): "暂不支持的图片类型：\(type)"
        case let .unsafeMediaReference(path): "媒体引用超出 Codex 内容寻址目录：\(path)"
        case let .missingMediaObject(path): "原始媒体文件不存在：\(path)"
        case let .corruptMediaObject(path): "媒体文件 SHA-256 与文件名不一致：\(path)"
        case let .fileIsOpen(path): "会话仍被进程占用：\(path)"
        case let .backupVerificationFailed(path): "备份校验失败：\(path)"
        case let .outputVerificationFailed(path): "修复结果校验失败：\(path)"
        case let .atomicReplaceFailed(path): "无法原子替换会话文件：\(path)"
        case let .workerUnavailable(path): "隔离修复进程不可用：\(path)"
        case let .workerFailed(path, detail): "隔离修复进程未能处理：\(path)（\(detail)）"
        case .cancelled: "操作已取消"
        }
    }

#if !TRACEFENCE_CODEX_MEDIA_WORKER
    func message(using localization: PluginLocalization) -> String {
        switch self {
        case let .invalidCodexHome(path):
            localization.format("error.invalidCodexHome", defaultValue: "Codex 数据目录不可用：%@", path)
        case let .malformedJSON(path, line):
            localization.format("error.malformedJSON", defaultValue: "会话 JSON 已损坏：%@ 第 %lld 行", path, Int64(line))
        case let .recordTooLarge(path, line, bytes, limit):
            localization.format(
                "error.recordTooLarge",
                defaultValue: "会话记录超过安全处理上限：%@ 第 %lld 行（%lld 字节，上限 %lld 字节）",
                path,
                Int64(line),
                Int64(bytes),
                Int64(limit)
            )
        case .invalidDataImage:
            localization.string("error.invalidDataImage", defaultValue: "发现无法解码的 data:image Base64 图片")
        case let .unsupportedImageType(type):
            localization.format("error.unsupportedImageType", defaultValue: "暂不支持的图片类型：%@", type)
        case let .unsafeMediaReference(path):
            localization.format("error.unsafeMediaReference", defaultValue: "媒体引用超出 Codex 内容寻址目录：%@", path)
        case let .missingMediaObject(path):
            localization.format("error.missingMediaObject", defaultValue: "原始媒体文件不存在：%@", path)
        case let .corruptMediaObject(path):
            localization.format("error.corruptMediaObject", defaultValue: "媒体文件 SHA-256 与文件名不一致：%@", path)
        case let .fileIsOpen(path):
            localization.format("error.fileIsOpen", defaultValue: "会话仍被进程占用：%@", path)
        case let .backupVerificationFailed(path):
            localization.format("error.backupVerificationFailed", defaultValue: "备份校验失败：%@", path)
        case let .outputVerificationFailed(path):
            localization.format("error.outputVerificationFailed", defaultValue: "修复结果校验失败：%@", path)
        case let .atomicReplaceFailed(path):
            localization.format("error.atomicReplaceFailed", defaultValue: "无法原子替换会话文件：%@", path)
        case let .workerUnavailable(path):
            localization.format("error.workerUnavailable", defaultValue: "隔离修复进程不可用：%@", path)
        case let .workerFailed(path, detail):
            localization.format("error.workerFailed", defaultValue: "隔离修复进程未能处理：%@（%@）", path, detail)
        case .cancelled:
            localization.string("error.cancelled", defaultValue: "操作已取消")
        }
    }
#endif
}

struct CodexMediaCleanupConfiguration: Sendable {
    let codexHome: URL
    let supportDirectory: URL
    let includeArchivedSessions: Bool

    var mediaRoot: URL {
        codexHome.appendingPathComponent("media_objects/sha256", isDirectory: true)
    }

    var sessionRoots: [URL] {
        var roots = [codexHome.appendingPathComponent("sessions", isDirectory: true)]
        if includeArchivedSessions {
            roots.append(codexHome.appendingPathComponent("archived_sessions", isDirectory: true))
        }
        return roots
    }

    var backupRoot: URL {
        supportDirectory.appendingPathComponent("Backups", isDirectory: true)
    }

    var reportRoot: URL {
        supportDirectory.appendingPathComponent("Reports", isDirectory: true)
    }
}

struct CodexMediaProgress: Sendable {
    let completed: Int
    let total: Int
    let currentPath: String
}
