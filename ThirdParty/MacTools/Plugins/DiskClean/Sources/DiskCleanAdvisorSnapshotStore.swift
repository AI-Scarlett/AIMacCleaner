import Foundation

/// Small, bounded presentation snapshot for reopening the plugin without another disk walk.
/// Scanner caches and this snapshot have different jobs: scanner caches accelerate the next
/// analysis; this file restores the last visible result immediately. It contains metadata only,
/// never conversation text or media bytes.
struct DiskCleanAdvisorSnapshot: Codable, Sendable {
    static let currentVersion = 3

    let version: Int
    let savedAt: Date
    let storageSummary: StorageOptimizationSummary
    let storageCleanupItems: [StorageCleanupItem]
    let systemDataSummary: SystemDataStorageSummary
    let inventorySummary: DiskFileInventorySummary
    let files: [DiskFileRecord]
    let duplicateSummary: DiskDuplicateFileSummary
    let duplicateGroups: [DiskDuplicateFileGroup]

    init(
        savedAt: Date = Date(),
        storageSummary: StorageOptimizationSummary,
        storageCleanupItems: [StorageCleanupItem],
        systemDataSummary: SystemDataStorageSummary,
        inventorySummary: DiskFileInventorySummary,
        files: [DiskFileRecord],
        duplicateSummary: DiskDuplicateFileSummary,
        duplicateGroups: [DiskDuplicateFileGroup]
    ) {
        self.version = Self.currentVersion
        self.savedAt = savedAt
        self.storageSummary = storageSummary
        self.storageCleanupItems = Array(storageCleanupItems.prefix(800))
        self.systemDataSummary = systemDataSummary
        self.inventorySummary = inventorySummary
        self.files = Array(files.prefix(2_000))
        self.duplicateSummary = duplicateSummary
        self.duplicateGroups = Array(duplicateGroups.prefix(500)).map { group in
            DiskDuplicateFileGroup(
                id: group.id,
                logicalSize: group.logicalSize,
                reclaimableBytes: group.reclaimableBytes,
                files: Array(group.files.prefix(100))
            )
        }
    }
}

struct DiskCleanAdvisorSnapshotStore: Sendable {
    static let maximumFileBytes = 32 * 1_024 * 1_024
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    let fileURL: URL

    func load(now: Date = Date()) -> DiskCleanAdvisorSnapshot? {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values?.isRegularFile == true,
              let fileSize = values?.fileSize,
              fileSize > 0,
              fileSize <= Self.maximumFileBytes,
              let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe),
              let snapshot = try? JSONDecoder().decode(DiskCleanAdvisorSnapshot.self, from: data),
              snapshot.version == DiskCleanAdvisorSnapshot.currentVersion,
              snapshot.storageCleanupItems.count <= 800,
              snapshot.files.count <= 2_000,
              snapshot.duplicateGroups.count <= 500,
              snapshot.duplicateGroups.allSatisfy({ $0.files.count <= 100 }),
              now.timeIntervalSince(snapshot.savedAt) >= 0,
              now.timeIntervalSince(snapshot.savedAt) <= Self.maximumAge else {
            return nil
        }
        return snapshot
    }

    @discardableResult
    func save(_ snapshot: DiskCleanAdvisorSnapshot) -> Bool {
        do {
            let data = try JSONEncoder().encode(snapshot)
            guard data.count <= Self.maximumFileBytes else { return false }
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
