import AppKit
import Foundation
import MacToolsPluginKit

@MainActor
final class CodexMediaCleanupController: ObservableObject {
    @Published private(set) var snapshot: CodexMediaCleanupSnapshot
    var onStateChange: (() -> Void)?

    private let codexHome: URL
    private let supportDirectory: URL
    private let localization: PluginLocalization
    private let scanEngine: CodexMediaScanEngine
    private let repairEngine: CodexMediaRepairEngine
    private var task: Task<Void, Never>?

    init(
        codexHome: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true),
        supportDirectory: URL,
        localization: PluginLocalization,
        scanEngine: CodexMediaScanEngine = CodexMediaScanEngine(),
        repairEngine: CodexMediaRepairEngine = CodexMediaRepairEngine()
    ) {
        self.codexHome = codexHome
        self.supportDirectory = supportDirectory
        self.localization = localization
        self.scanEngine = scanEngine
        self.repairEngine = repairEngine
        self.snapshot = CodexMediaCleanupSnapshot()
    }

    var canScan: Bool { !snapshot.isBusy }
    var canCleanup: Bool { canRun(.cleanup) }
    var canRepair: Bool { canRun(.repair) }
    var canCleanupAndRepair: Bool { canRun(.cleanupAndRepair) }

    func setIncludeArchivedSessions(_ value: Bool) {
        guard !snapshot.isBusy, snapshot.includeArchivedSessions != value else { return }
        snapshot.includeArchivedSessions = value
        snapshot.phase = .idle
        snapshot.scanReport = nil
        snapshot.errorMessage = nil
        appendLog(.info, t("log.scopeChanged", "扫描范围已变更，请重新扫描。"))
        publish()
    }

    func scan() {
        guard canScan else { return }
        task?.cancel()
        snapshot.phase = .scanning
        snapshot.activeOperation = nil
        snapshot.errorMessage = nil
        snapshot.completedFiles = 0
        snapshot.totalFiles = 0
        snapshot.currentFile = ""
        appendLog(.info, t("log.scanStarted", "开始只读扫描 Codex 会话；不会修改任何文件。"))
        publish()

        let configuration = configuration
        let engine = scanEngine
        let progress: @Sendable (CodexMediaProgress) -> Void = { [weak self] value in
            Task { @MainActor [weak self] in self?.applyScanProgress(value) }
        }
        task = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                try engine.scan(configuration: configuration, progress: progress)
            }
            do {
                let report = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, let self else { return }
                self.snapshot.scanReport = report
                self.snapshot.phase = .scanned
                self.snapshot.completedFiles = report.scannedFiles
                self.snapshot.totalFiles = report.scannedFiles
                self.snapshot.currentFile = ""
                self.appendLog(.success, self.localization.format(
                    "log.scanCompletedFormat",
                    defaultValue: "扫描完成：%lld 个会话文件，%lld 个可清理副本，%lld 个无效 image_url，预计释放 %@。",
                    Int64(report.scannedFiles),
                    Int64(report.reclaimableOccurrences),
                    Int64(report.invalidEffectiveFileURLs),
                    Self.bytes(report.estimatedReclaimableBytes)
                ))
                if report.malformedFiles > 0 || report.missingMediaObjects > 0 {
                    self.appendLog(.warning, self.localization.format(
                        "log.scanSkippedFormat",
                        defaultValue: "安全跳过：%lld 个损坏 JSONL，%lld 个缺失或未通过校验的媒体对象。",
                        Int64(report.malformedFiles),
                        Int64(report.missingMediaObjects)
                    ))
                }
                self.publish()
            } catch {
                guard let self else { return }
                self.snapshot.phase = self.snapshot.scanReport == nil ? .idle : .scanned
                let message = self.localizedDescription(for: error)
                self.snapshot.errorMessage = message
                self.appendLog(.error, message)
                self.publish()
            }
        }
    }

    func run(_ operation: CodexMediaOperation) {
        guard canRun(operation) else { return }
        task?.cancel()
        let codexIsRunning = repairEngine.processMonitor.isCodexRunning()
        snapshot.phase = codexIsRunning ? .waitingForCodex : operation.phase
        snapshot.activeOperation = operation
        snapshot.lastOperation = nil
        snapshot.errorMessage = nil
        snapshot.repairReport = nil
        snapshot.completedFiles = 0
        snapshot.totalFiles = snapshot.scanReport?.scannedFiles ?? 0
        snapshot.currentFile = ""
        snapshot.requiresRestartValidation = false
        snapshot.codexRestarted = false
        snapshot.historyConversationValidated = false
        appendLog(.info, localization.format(
            "log.operationRequestedFormat",
            defaultValue: "已请求“%@”。写入前将确认 Codex 完全退出并检查会话文件句柄。",
            operationName(operation)
        ))
        if codexIsRunning {
            appendLog(.warning, t(
                "log.waitingForCodex",
                "检测到 Codex/ChatGPT 仍在运行。请暂停所有任务并完全退出客户端；TraceFence 会继续等待，不会强制结束进程。"
            ))
        } else {
            appendLog(.success, t("log.codexStopped", "未检测到 Codex 进程，开始逐文件安全处理。"))
        }
        publish()

        let configuration = configuration
        let engine = repairEngine
        let progress: @Sendable (CodexMediaProgress) -> Void = { [weak self] value in
            Task { @MainActor [weak self] in self?.applyOperationProgress(value, operation: operation) }
        }
        task = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                try await engine.perform(operation, configuration: configuration, progress: progress)
            }
            do {
                let report = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, let self else { return }
                self.snapshot.phase = .completed
                self.snapshot.activeOperation = nil
                self.snapshot.lastOperation = operation
                self.snapshot.repairReport = report
                self.snapshot.completedFiles = self.snapshot.totalFiles
                self.snapshot.currentFile = ""
                self.snapshot.requiresRestartValidation = true
                self.appendLog(.success, self.localization.format(
                    "log.operationCompletedFormat",
                    defaultValue: "%@完成：处理 %lld 个会话，清理 %lld 个重复媒体副本，修复 %lld 个无效 image_url，释放约 %@。",
                    self.operationName(operation),
                    Int64(report.repairedFileCount),
                    Int64(report.replacementCount),
                    Int64(report.restorationCount),
                    Self.bytes(report.reclaimedBytes)
                ))
                if !report.skippedFiles.isEmpty {
                    self.appendLog(.warning, self.localization.format(
                        "log.operationSkippedFormat",
                        defaultValue: "%lld 个文件因占用、损坏或安全校验失败而跳过，详情见报告。",
                        Int64(report.skippedFiles.count)
                    ))
                }
                self.appendLog(.warning, t(
                    "log.restartRequired",
                    "必须完全重新启动 Codex，再打开一个包含图片的历史对话，确认图片可见并能继续发送消息。"
                ))
                self.publish()
            } catch {
                guard let self else { return }
                self.snapshot.phase = .scanned
                self.snapshot.activeOperation = nil
                let message = self.localizedDescription(for: error)
                self.snapshot.errorMessage = message
                self.appendLog(.error, message)
                self.publish()
            }
        }
    }

    func restartCodexClient() {
        guard snapshot.requiresRestartValidation, !snapshot.isBusy else { return }
        let candidates = [
            URL(fileURLWithPath: "/Applications/ChatGPT.app", isDirectory: true),
            URL(fileURLWithPath: "/Applications/Codex.app", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/ChatGPT.app", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications/Codex.app", isDirectory: true)
        ]
        guard let applicationURL = candidates.first(where: {
            FileManager.default.fileExists(atPath: $0.path)
        }) else {
            let message = t("error.codexAppMissing", "未找到 Codex/ChatGPT 客户端，请手动启动后再完成历史对话验证。")
            snapshot.errorMessage = message
            appendLog(.error, message)
            publish()
            return
        }

        appendLog(.info, t("log.restartingCodex", "正在启动全新的 Codex 客户端进程…"))
        publish()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: applicationURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let error {
                    self.snapshot.errorMessage = error.localizedDescription
                    self.appendLog(.error, error.localizedDescription)
                } else {
                    self.snapshot.codexRestarted = true
                    self.appendLog(.success, self.t(
                        "log.codexRestarted",
                        "Codex 已重新启动。请打开一个包含图片的历史对话并验证。"
                    ))
                }
                self.publish()
            }
        }
    }

    func markHistoryConversationValidated() {
        guard snapshot.requiresRestartValidation, snapshot.codexRestarted else { return }
        snapshot.historyConversationValidated = true
        appendLog(.success, t(
            "log.historyValidated",
            "已记录：重启后的历史对话图片显示正常，并已完成继续对话验证。"
        ))
        publish()
    }

    func cancelCurrentOperation() {
        guard snapshot.isBusy else { return }
        task?.cancel()
        task = nil
        snapshot.phase = snapshot.scanReport == nil ? .idle : .scanned
        snapshot.activeOperation = nil
        snapshot.currentFile = ""
        let message = CodexMediaCleanupError.cancelled.message(using: localization)
        snapshot.errorMessage = message
        appendLog(.warning, message)
        publish()
    }

    private func canRun(_ operation: CodexMediaOperation) -> Bool {
        guard !snapshot.isBusy, let report = snapshot.scanReport else { return false }
        return switch operation {
        case .cleanup: report.needsCleanup
        case .repair: report.needsRepair
        case .cleanupAndRepair: report.needsWork
        }
    }

    private var configuration: CodexMediaCleanupConfiguration {
        CodexMediaCleanupConfiguration(
            codexHome: codexHome,
            supportDirectory: supportDirectory,
            includeArchivedSessions: snapshot.includeArchivedSessions
        )
    }

    private func publish() {
        onStateChange?()
        objectWillChange.send()
    }

    private func localizedDescription(for error: Error) -> String {
        if let cleanupError = error as? CodexMediaCleanupError {
            return cleanupError.message(using: localization)
        }
        return error.localizedDescription
    }

    private func applyScanProgress(_ progress: CodexMediaProgress) {
        guard snapshot.phase == .scanning else { return }
        snapshot.completedFiles = progress.completed
        snapshot.totalFiles = progress.total
        snapshot.currentFile = progress.currentPath
        if !progress.currentPath.isEmpty {
            appendLog(.info, localization.format(
                "log.scanFileFormat",
                defaultValue: "扫描 [%lld/%lld] %@",
                Int64(min(progress.completed + 1, progress.total)),
                Int64(progress.total),
                relativeDisplayPath(progress.currentPath)
            ))
        }
        publish()
    }

    private func applyOperationProgress(_ progress: CodexMediaProgress, operation: CodexMediaOperation) {
        guard snapshot.isBusy else { return }
        if snapshot.phase == .waitingForCodex {
            appendLog(.success, t("log.codexStopped", "Codex 已完全退出，开始逐文件备份、校验和原子处理。"))
        }
        snapshot.phase = operation.phase
        snapshot.completedFiles = progress.completed
        snapshot.totalFiles = progress.total
        snapshot.currentFile = progress.currentPath
        if !progress.currentPath.isEmpty {
            appendLog(.info, localization.format(
                "log.processFileFormat",
                defaultValue: "%@ [%lld/%lld] %@",
                operationName(operation),
                Int64(min(progress.completed + 1, progress.total)),
                Int64(progress.total),
                relativeDisplayPath(progress.currentPath)
            ))
        }
        publish()
    }

    private func appendLog(_ level: CodexMediaLogLevel, _ message: String) {
        snapshot.logs.append(.init(id: UUID(), timestamp: Date(), level: level, message: message))
        if snapshot.logs.count > 500 {
            snapshot.logs.removeFirst(snapshot.logs.count - 500)
        }
    }

    private func relativeDisplayPath(_ path: String) -> String {
        let root = codexHome.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return path }
        return "~/.codex/" + String(path.dropFirst(root.count + 1))
    }

    private func operationName(_ operation: CodexMediaOperation) -> String {
        switch operation {
        case .cleanup: t("operation.cleanup", "清理")
        case .repair: t("operation.repair", "修复")
        case .cleanupAndRepair: t("operation.cleanupAndRepair", "清理并修复")
        }
    }

    private func t(_ key: String, _ defaultValue: String) -> String {
        localization.string(key, defaultValue: defaultValue)
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
