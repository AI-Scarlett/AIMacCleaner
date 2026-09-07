import CryptoKit
import Darwin
import Foundation

/// Content-based duplicate detection built on the candidates collected by the
/// file-inventory walk. It first groups by logical size, then compares a small
/// head/tail fingerprint, and only streams the full file for real collisions.
/// No file is ever loaded into memory in full.
enum DiskCleanDuplicateScanner {
    private static let cacheVersion = 2
    private static let chunkBytes = 1 * 1_024 * 1_024
    private static let quickChunkBytes = 64 * 1_024
    private static let maximumCacheEntries = 6_000
    private static let maximumCacheBytes = 8 * 1_024 * 1_024

    private struct CacheEntry: Codable, Sendable {
        let logicalSize: Int64
        let modifiedAt: TimeInterval
        let changedAt: TimeInterval
        let fileIdentity: String
        let quickHash: String
        let fullHash: String
        let lastSeenAt: TimeInterval
    }

    private struct Cache: Codable, Sendable {
        var version: Int
        var entries: [String: CacheEntry]
    }

    private struct FingerprintedFile: Sendable {
        let file: DiskFileRecord
        let identity: String
        let modifiedAt: TimeInterval
        let changedAt: TimeInterval
        let quickHash: String
        var fullHash: String?
    }

    private struct FileSnapshot: Equatable, Sendable {
        let identity: String
        let logicalSize: Int64
        let modifiedAt: TimeInterval
        let changedAt: TimeInterval
    }

    static func scan(
        candidates: [DiskFileRecord],
        cacheURL: URL,
        candidateWasTruncated: Bool,
        now: Date = Date(),
        maximumDuration: TimeInterval = 25
    ) -> DiskDuplicateFileScanResult {
        let startedAt = Date()
        let deadline = ProcessInfo.processInfo.systemUptime + max(0, maximumDuration)
        func canContinue() -> Bool {
            !Task.isCancelled && ProcessInfo.processInfo.systemUptime < deadline
        }
        var cache = loadCache(from: cacheURL)
        var unreadableFileCount = 0
        var hashedFileCount = 0
        var wasTruncated = candidateWasTruncated
        var quickGroups: [String: [FingerprintedFile]] = [:]
        var seenIdentities = Set<String>()

        let sizeGroups = Dictionary(grouping: candidates) { $0.logicalSize }
            .filter { $0.key > 0 && $0.value.count > 1 }
            .sorted { $0.key > $1.key }

        quickLoop: for (logicalSize, files) in sizeGroups {
            for file in files.sorted(by: { $0.path < $1.path }) {
                guard canContinue() else {
                    wasTruncated = true
                    break quickLoop
                }
                guard let snapshot = fileSnapshot(path: file.path),
                      snapshot.logicalSize == logicalSize else {
                    unreadableFileCount += 1
                    continue
                }
                // Multiple directory entries can point to the same inode. Hash it once.
                guard seenIdentities.insert(snapshot.identity).inserted else { continue }

                let cached = cache.entries[file.path]
                let cacheMatches = cached?.logicalSize == logicalSize
                    && cached?.modifiedAt == snapshot.modifiedAt
                    && cached?.changedAt == snapshot.changedAt
                    && cached?.fileIdentity == snapshot.identity
                let quickHash: String
                let fullHash: String?
                if let cached, cacheMatches {
                    quickHash = cached.quickHash
                    fullHash = cached.fullHash
                } else {
                    guard let hash = quickFingerprint(path: file.path, logicalSize: logicalSize) else {
                        unreadableFileCount += 1
                        continue
                    }
                    quickHash = hash
                    fullHash = nil
                }
                quickGroups["\(logicalSize):\(quickHash)", default: []].append(
                    FingerprintedFile(
                        file: file,
                        identity: snapshot.identity,
                        modifiedAt: snapshot.modifiedAt,
                        changedAt: snapshot.changedAt,
                        quickHash: quickHash,
                        fullHash: fullHash
                    )
                )
            }
        }

        var fullGroups: [String: [FingerprintedFile]] = [:]
        fullLoop: for files in quickGroups.values where files.count > 1 {
            for var value in files {
                guard canContinue() else {
                    wasTruncated = true
                    break fullLoop
                }
                if value.fullHash == nil {
                    guard let hash = fullFingerprint(path: value.file.path, shouldContinue: canContinue) else {
                        if !canContinue() {
                            wasTruncated = true
                            break fullLoop
                        }
                        unreadableFileCount += 1
                        continue
                    }
                    value.fullHash = hash
                    hashedFileCount += 1
                }
                // Validate cached hashes too: a file can change between the two passes.
                guard matchesSnapshot(value) else {
                    unreadableFileCount += 1
                    continue
                }
                guard let fullHash = value.fullHash else { continue }
                cache.entries[value.file.path] = CacheEntry(
                    logicalSize: value.file.logicalSize,
                    modifiedAt: value.modifiedAt,
                    changedAt: value.changedAt,
                    fileIdentity: value.identity,
                    quickHash: value.quickHash,
                    fullHash: fullHash,
                    lastSeenAt: now.timeIntervalSince1970
                )
                fullGroups["\(value.file.logicalSize):\(fullHash)", default: []].append(value)
            }
        }

        let groups = fullGroups.compactMap { key, rawFiles -> DiskDuplicateFileGroup? in
            let files = rawFiles
                .filter { value in
                    guard matchesSnapshot(value) else {
                        unreadableFileCount += 1
                        return false
                    }
                    return true
                }
                .map(\.file)
                .sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            guard files.count > 1, let first = files.first else { return nil }
            let allocatedSizes = files.map { max($0.size, 0) }.sorted()
            let reclaimableBytes = allocatedSizes.dropFirst().reduce(Int64(0), +)
            return DiskDuplicateFileGroup(
                id: key,
                logicalSize: first.logicalSize,
                reclaimableBytes: reclaimableBytes,
                files: files
            )
        }
        .sorted {
            if $0.reclaimableBytes != $1.reclaimableBytes {
                return $0.reclaimableBytes > $1.reclaimableBytes
            }
            return $0.id < $1.id
        }

        trimAndSave(&cache, to: cacheURL)
        let completedAt = Date()
        return DiskDuplicateFileScanResult(
            groups: groups,
            summary: DiskDuplicateFileSummary(
                candidateFileCount: candidates.count,
                hashedFileCount: hashedFileCount,
                duplicateFileCount: groups.reduce(0) { $0 + $1.files.count },
                duplicateGroupCount: groups.count,
                duplicateBytes: groups.reduce(Int64(0)) { total, group in
                    total + group.files.reduce(Int64(0)) { $0 + max($1.size, 0) }
                },
                reclaimableBytes: groups.reduce(Int64(0)) { $0 + $1.reclaimableBytes },
                unreadableFileCount: unreadableFileCount,
                wasTruncated: wasTruncated,
                scanDuration: completedAt.timeIntervalSince(startedAt),
                completedAt: completedAt
            )
        )
    }

    private static func quickFingerprint(path: String, logicalSize: Int64) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        do {
            var hasher = SHA256()
            hasher.update(data: Data("\(logicalSize):".utf8))
            if let head = try handle.read(upToCount: quickChunkBytes) {
                hasher.update(data: head)
            }
            if logicalSize > Int64(quickChunkBytes) {
                try handle.seek(toOffset: UInt64(max(logicalSize - Int64(quickChunkBytes), 0)))
                if let tail = try handle.read(upToCount: quickChunkBytes) {
                    hasher.update(data: tail)
                }
            }
            return hex(hasher.finalize())
        } catch {
            return nil
        }
    }

    static func fullFingerprint(path: String, shouldContinue: () -> Bool) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return nil }
        defer { try? handle.close() }
        do {
            var hasher = SHA256()
            while true {
                guard !Task.isCancelled, shouldContinue() else { return nil }
                guard let data = try handle.read(upToCount: chunkBytes), !data.isEmpty else { break }
                hasher.update(data: data)
            }
            return hex(hasher.finalize())
        } catch {
            return nil
        }
    }

    private static func fileSnapshot(path: String) -> FileSnapshot? {
        var info = stat()
        guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return FileSnapshot(
            identity: "\(info.st_dev):\(info.st_ino)",
            logicalSize: Int64(info.st_size),
            modifiedAt: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000,
            changedAt: TimeInterval(info.st_ctimespec.tv_sec) + TimeInterval(info.st_ctimespec.tv_nsec) / 1_000_000_000
        )
    }

    private static func matchesSnapshot(_ value: FingerprintedFile) -> Bool {
        fileSnapshot(path: value.file.path) == FileSnapshot(
            identity: value.identity,
            logicalSize: value.file.logicalSize,
            modifiedAt: value.modifiedAt,
            changedAt: value.changedAt
        )
    }

    private static func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
        digest.map { String(format: "%02x", $0) }.joined()
    }

    private static func loadCache(from url: URL) -> Cache {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size > 0,
              size <= maximumCacheBytes,
              let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let cache = try? JSONDecoder().decode(Cache.self, from: data),
              cache.version == cacheVersion else {
            return Cache(version: cacheVersion, entries: [:])
        }
        return cache
    }

    private static func trimAndSave(_ cache: inout Cache, to url: URL) {
        if cache.entries.count > maximumCacheEntries {
            let retained = cache.entries
                .sorted { $0.value.lastSeenAt > $1.value.lastSeenAt }
                .prefix(maximumCacheEntries)
            cache.entries = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
        }
        guard let data = try? JSONEncoder().encode(cache), data.count <= maximumCacheBytes else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }
}
