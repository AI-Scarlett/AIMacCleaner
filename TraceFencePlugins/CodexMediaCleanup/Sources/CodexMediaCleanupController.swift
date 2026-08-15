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
    var canRepair: Bool { !snapshot.isBusy && snapshot.scanReport?.needsRepair == true }

    func setIncludeArchivedSessions(_ value: Bool) {
        guard !snapshot.isBusy, snapshot.includeArchivedSessions != value else { return }
        snapshot.includeArchivedSessions = value
        snapshot.phase = .idle
        snapshot.scanReport = nil
        snapshot.repairReport = nil
        publish()
    }

    func scan() {
        guard canScan else { return }
        task?.cancel()
        snapshot.phase = .scanning
        snapshot.errorMessage = nil
        snapshot.repairReport = nil
        snapshot.completedFiles = 0
        snapshot.totalFiles = 0
        publish()

        let configuration = configuration
        let engine = scanEngine
        let progress: @Sendable (CodexMediaProgress) -> Void = { [weak self] value in
            Task { @MainActor [weak self] in self?.applyProgress(value, phase: .scanning) }
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
                self.publish()
            } catch {
                guard let self else { return }
                self.snapshot.phase = .idle
                self.snapshot.errorMessage = self.localizedDescription(for: error)
                self.publish()
            }
        }
    }

    func repairWhenCodexStops() {
        guard canRepair else { return }
        task?.cancel()
        snapshot.phase = repairEngine.processMonitor.isCodexRunning() ? .waitingForCodex : .repairing
        snapshot.errorMessage = nil
        snapshot.completedFiles = 0
        snapshot.totalFiles = snapshot.scanReport?.scannedFiles ?? 0
        publish()

        let configuration = configuration
        let engine = repairEngine
        let progress: @Sendable (CodexMediaProgress) -> Void = { [weak self] value in
            Task { @MainActor [weak self] in self?.applyProgress(value, phase: .repairing) }
        }
        task = Task { [weak self] in
            let worker = Task.detached(priority: .utility) {
                try await engine.repair(configuration: configuration, progress: progress)
            }
            do {
                let report = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                guard !Task.isCancelled, let self else { return }
                self.snapshot.phase = .completed
                self.snapshot.repairReport = report
                self.publish()
                self.refreshScanAfterRepair()
            } catch {
                guard let self else { return }
                self.snapshot.phase = .scanned
                self.snapshot.errorMessage = self.localizedDescription(for: error)
                self.publish()
            }
        }
    }

    func cancelCurrentOperation() {
        task?.cancel()
        task = nil
        snapshot.phase = snapshot.scanReport == nil ? .idle : .scanned
        snapshot.currentFile = ""
        snapshot.errorMessage = CodexMediaCleanupError.cancelled.message(using: localization)
        publish()
    }

    private func refreshScanAfterRepair() {
        let previousReport = snapshot.repairReport
        scan()
        snapshot.repairReport = previousReport
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

    private func applyProgress(_ progress: CodexMediaProgress, phase: CodexMediaCleanupPhase) {
        guard snapshot.isBusy else { return }
        snapshot.phase = phase
        snapshot.completedFiles = progress.completed
        snapshot.totalFiles = progress.total
        snapshot.currentFile = progress.currentPath
        publish()
    }
}
