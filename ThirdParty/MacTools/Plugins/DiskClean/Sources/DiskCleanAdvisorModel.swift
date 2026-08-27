import Combine
import Foundation

enum DiskCleanAdvisorStage: Equatable, Sendable {
    case idle
    case agentAndBuildStorage
    case systemData
    case fileInventory
    case completed
}

/// Shared state for the plugin's AI Disk Advisor migration.
///
/// Both scanners are the exact source files used by the native fallback. They are bounded and
/// cache-backed; work is deliberately serial so opening the plugin cannot start two competing
/// full-disk walks and reproduce the memory/IO pressure that prompted this migration.
@MainActor
final class DiskCleanAdvisorModel: ObservableObject {
    @Published private(set) var stage: DiskCleanAdvisorStage = .idle
    @Published private(set) var storageSummary: StorageOptimizationSummary?
    @Published private(set) var storageCleanupItems: [StorageCleanupItem] = []
    @Published private(set) var systemDataSummary: SystemDataStorageSummary?
    @Published private(set) var inventorySummary: DiskFileInventorySummary?
    @Published private(set) var files: [DiskFileRecord] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastAnalyzedAt: Date?
    @Published private(set) var isRestoredFromCache = false

    private let homeDirectory: String
    private let cacheDirectory: URL
    private let snapshotStore: DiskCleanAdvisorSnapshotStore
    private let isSandboxed: Bool
    private var scanTask: Task<Void, Never>?
    private var snapshotLoadTask: Task<Void, Never>?
    private var scanGeneration = UUID()

    init(
        cacheDirectory: URL?,
        homeDirectory: String = NSHomeDirectory(),
        isSandboxed: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    ) {
        self.homeDirectory = URL(fileURLWithPath: homeDirectory, isDirectory: true)
            .standardizedFileURL.path
        self.cacheDirectory = cacheDirectory ?? Self.fallbackCacheDirectory
        self.snapshotStore = DiskCleanAdvisorSnapshotStore(
            fileURL: self.cacheDirectory.appendingPathComponent(
                "advisor-visible-snapshot-v1.json",
                isDirectory: false
            )
        )
        self.isSandboxed = isSandboxed
        try? FileManager.default.createDirectory(
            at: self.cacheDirectory,
            withIntermediateDirectories: true
        )
        restoreVisibleSnapshot()
    }

    deinit {
        scanTask?.cancel()
        snapshotLoadTask?.cancel()
    }

    var isScanning: Bool {
        stage == .agentAndBuildStorage || stage == .systemData || stage == .fileInventory
    }

    var hasResult: Bool {
        storageSummary != nil || inventorySummary != nil
    }

    func scan() {
        guard !isScanning else { return }

        snapshotLoadTask?.cancel()
        errorMessage = nil
        isRestoredFromCache = false
        stage = .agentAndBuildStorage
        let generation = UUID()
        scanGeneration = generation

        let homeDirectory = homeDirectory
        let isSandboxed = isSandboxed
        let storageCacheURL = cacheDirectory.appendingPathComponent(
            "storage-optimizer-v3.json",
            isDirectory: false
        )
        let inventoryCacheURL = cacheDirectory.appendingPathComponent(
            "file-inventory-v1.json",
            isDirectory: false
        )
        let snapshotStore = snapshotStore

        scanTask = Task { [weak self] in
            let storageResult = await Task.detached(priority: .utility) {
                autoreleasepool {
                    StorageOptimizationCore.scan(
                        homeDirectory: homeDirectory,
                        authorizedRoots: nil,
                        isSandboxed: isSandboxed,
                        cacheURL: storageCacheURL,
                        retainBuildCount: 3
                    )
                }
            }.value

            guard let self, self.scanGeneration == generation, !Task.isCancelled else { return }
            self.storageSummary = storageResult.summary
            self.storageCleanupItems = storageResult.cleanupItems
            self.stage = .systemData

            let systemDataResult = await Task.detached(priority: .utility) {
                autoreleasepool {
                    SystemDataStorageInspectionCore.scan(homeDirectory: homeDirectory)
                }
            }.value

            guard self.scanGeneration == generation, !Task.isCancelled else { return }
            self.systemDataSummary = systemDataResult
            self.stage = .fileInventory

            let inventoryResult = await Task.detached(priority: .utility) {
                autoreleasepool {
                    DiskFileInventoryCore.scan(
                        homeDirectory: homeDirectory,
                        authorizedRoots: nil,
                        isSandboxed: isSandboxed,
                        cacheURL: inventoryCacheURL,
                        // The summary still covers every eligible file. Limiting retained rows
                        // keeps a large home folder from turning the plugin view into an in-memory
                        // path database.
                        maximumReturnedFiles: 2_000
                    )
                }
            }.value

            guard self.scanGeneration == generation, !Task.isCancelled else { return }
            self.files = inventoryResult.files
            self.inventorySummary = inventoryResult.summary

            let visibleSnapshot = DiskCleanAdvisorSnapshot(
                storageSummary: storageResult.summary,
                storageCleanupItems: storageResult.cleanupItems,
                inventorySummary: inventoryResult.summary,
                files: inventoryResult.files
            )
            _ = await Task.detached(priority: .utility) {
                snapshotStore.save(visibleSnapshot)
            }.value

            guard self.scanGeneration == generation, !Task.isCancelled else { return }
            self.lastAnalyzedAt = max(
                storageResult.summary.completedAt,
                inventoryResult.summary.completedAt
            )
            self.stage = .completed
            self.scanTask = nil
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func restoreVisibleSnapshot() {
        let store = snapshotStore
        snapshotLoadTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                store.load()
            }.value
            guard let self,
                  !Task.isCancelled,
                  self.stage == .idle,
                  !self.hasResult,
                  let snapshot else {
                return
            }
            self.storageSummary = snapshot.storageSummary
            self.storageCleanupItems = snapshot.storageCleanupItems
            self.inventorySummary = snapshot.inventorySummary
            self.files = snapshot.files
            self.lastAnalyzedAt = max(
                snapshot.storageSummary.completedAt,
                snapshot.inventorySummary.completedAt
            )
            self.isRestoredFromCache = true
            self.stage = .completed
            self.snapshotLoadTask = nil
        }
    }

    private static var fallbackCacheDirectory: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return root
            .appendingPathComponent("TraceFence", isDirectory: true)
            .appendingPathComponent("Plugins", isDirectory: true)
            .appendingPathComponent("disk-clean", isDirectory: true)
    }
}
