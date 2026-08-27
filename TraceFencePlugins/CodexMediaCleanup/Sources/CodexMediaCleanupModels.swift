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

enum CodexMediaBackupReportStatus: String, Equatable, Sendable {
    case completed
    case interrupted
    case unavailable
}

/// One rollback batch created by a cleanup or repair run.
///
/// Backup management is intentionally batch-based. A user can remove a whole rollback point,
/// but never individual JSONL files that could leave the batch internally inconsistent.
struct CodexMediaBackupBatch: Identifiable, Equatable, Sendable {
    let id: String
    let path: String
    let createdAt: Date
    let allocatedBytes: Int64
    let fileCount: Int
    let reportStatus: CodexMediaBackupReportStatus
    let reportPath: String?
    let resourceIdentifier: String?
}

struct CodexMediaBackupCleanupResult: Equatable, Sendable {
    let removedBatchCount: Int
    let removedFileCount: Int
    let removedAllocatedBytes: Int64
    /// APFS may update free capacity asynchronously. This value is a best-effort immediate
    /// observation, while `removedAllocatedBytes` remains the stable amount selected by the user.
    let immediatelyReclaimedBytes: Int64
}

enum CodexMediaBackupStoreError: LocalizedError, Equatable {
    case invalidBatch(String)
    case batchChanged(String)

    var errorDescription: String? {
        switch self {
        case let .invalidBatch(id):
            "拒绝删除不属于 Codex 媒体整理插件的备份批次：\(id)"
        case let .batchChanged(id):
            "备份批次已发生变化，请刷新后重新选择：\(id)"
        }
    }

#if !TRACEFENCE_CODEX_MEDIA_WORKER
    func message(using localization: PluginLocalization) -> String {
        switch self {
        case let .invalidBatch(id):
            localization.format(
                "error.backup.invalidBatch",
                defaultValue: "拒绝删除不属于 Codex 媒体整理插件的备份批次：%@",
                id
            )
        case let .batchChanged(id):
            localization.format(
                "error.backup.batchChanged",
                defaultValue: "备份批次已发生变化，请刷新后重新选择：%@",
                id
            )
        }
    }
#endif
}

/// Enumerates and permanently removes only direct children of this plugin's `Backups` folder.
/// Symlinks are never followed, which keeps deletion inside the plugin-owned support directory.
struct CodexMediaBackupStore: Sendable {
    func scan(configuration: CodexMediaCleanupConfiguration) throws -> [CodexMediaBackupBatch] {
        let fileManager = FileManager.default
        let backupRoot = configuration.backupRoot.standardizedFileURL
        guard fileManager.fileExists(atPath: backupRoot.path) else { return [] }

        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .creationDateKey,
            .contentModificationDateKey,
            .fileResourceIdentifierKey
        ]
        let children = try fileManager.contentsOfDirectory(
            at: backupRoot,
            includingPropertiesForKeys: Array(keys),
            options: []
        )

        return try children.compactMap { child in
            let values = try child.resourceValues(forKeys: keys)
            guard values.isDirectory == true, values.isSymbolicLink != true else { return nil }
            let report = reportMetadata(runID: child.lastPathComponent, configuration: configuration)
            let allocation = try allocatedSize(of: child)
            return CodexMediaBackupBatch(
                id: child.lastPathComponent,
                path: child.path,
                createdAt: values.creationDate ?? values.contentModificationDate ?? .distantPast,
                allocatedBytes: allocation.bytes,
                fileCount: allocation.files,
                reportStatus: report.status,
                reportPath: report.path,
                resourceIdentifier: values.fileResourceIdentifier.map { String(describing: $0) }
            )
        }
        .sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id > rhs.id
        }
    }

    func remove(
        _ batches: [CodexMediaBackupBatch],
        configuration: CodexMediaCleanupConfiguration
    ) throws -> CodexMediaBackupCleanupResult {
        guard !batches.isEmpty else {
            return .init(
                removedBatchCount: 0,
                removedFileCount: 0,
                removedAllocatedBytes: 0,
                immediatelyReclaimedBytes: 0
            )
        }

        let fileManager = FileManager.default
        let backupRoot = configuration.backupRoot.standardizedFileURL.resolvingSymlinksInPath()
        let capacityBefore = availableCapacity(at: backupRoot)
        var removedFiles = 0
        var removedBytes: Int64 = 0

        for batch in batches {
            guard Self.isValidRunID(batch.id) else {
                throw CodexMediaBackupStoreError.invalidBatch(batch.id)
            }
            let candidate = configuration.backupRoot
                .appendingPathComponent(batch.id, isDirectory: true)
                .standardizedFileURL
            let parent = candidate.deletingLastPathComponent().resolvingSymlinksInPath()
            guard parent == backupRoot else {
                throw CodexMediaBackupStoreError.invalidBatch(batch.id)
            }

            let values = try candidate.resourceValues(forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
                .fileResourceIdentifierKey
            ])
            guard values.isDirectory == true, values.isSymbolicLink != true else {
                throw CodexMediaBackupStoreError.invalidBatch(batch.id)
            }
            let currentIdentifier = values.fileResourceIdentifier.map { String(describing: $0) }
            if let expected = batch.resourceIdentifier, currentIdentifier != expected {
                throw CodexMediaBackupStoreError.batchChanged(batch.id)
            }

            try fileManager.removeItem(at: candidate)
            removedFiles += batch.fileCount
            removedBytes += max(batch.allocatedBytes, 0)
        }

        let capacityAfter = availableCapacity(at: backupRoot)
        let immediate = max((capacityAfter ?? 0) - (capacityBefore ?? 0), 0)
        return .init(
            removedBatchCount: batches.count,
            removedFileCount: removedFiles,
            removedAllocatedBytes: removedBytes,
            immediatelyReclaimedBytes: immediate
        )
    }

    private func allocatedSize(of root: URL) throws -> (bytes: Int64, files: Int) {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey,
            .fileSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        ) else { return (0, 0) }

        var bytes: Int64 = 0
        var files = 0
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                continue
            }
            guard values.isRegularFile == true else { continue }
            let allocated = values.totalFileAllocatedSize
                ?? values.fileAllocatedSize
                ?? values.fileSize
                ?? 0
            bytes += Int64(max(allocated, 0))
            files += 1
        }
        return (bytes, files)
    }

    private func reportMetadata(
        runID: String,
        configuration: CodexMediaCleanupConfiguration
    ) -> (status: CodexMediaBackupReportStatus, path: String?) {
        let reportRoot = configuration.reportRoot.appendingPathComponent(runID, isDirectory: true)
        guard let reports = try? FileManager.default.contentsOfDirectory(
            at: reportRoot,
            includingPropertiesForKeys: nil,
            options: []
        ) else { return (.unavailable, nil) }

        if let completed = reports.first(where: { $0.lastPathComponent.hasSuffix("-report.json") }) {
            return (.completed, completed.path)
        }
        if let progress = reports.first(where: { $0.lastPathComponent.hasSuffix("-progress.json") }) {
            return (.interrupted, progress.path)
        }
        return (.unavailable, nil)
    }

    private func availableCapacity(at url: URL) -> Int64? {
        try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
    }

    private static func isValidRunID(_ value: String) -> Bool {
        guard !value.isEmpty, value != ".", value != ".." else { return false }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || $0 == "-" || $0 == "_" || $0 == "."
        }
    }
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
    var backupBatches: [CodexMediaBackupBatch] = []
    var isScanningBackups = false
    var isDeletingBackups = false
    var lastBackupCleanupResult: CodexMediaBackupCleanupResult?

    var backupAllocatedBytes: Int64 {
        backupBatches.reduce(0) { $0 + max($1.allocatedBytes, 0) }
    }

    var isManagingBackups: Bool { isScanningBackups || isDeletingBackups }

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
