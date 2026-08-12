import CoreServices
import Foundation

enum DiskFileCategory: String, Codable, CaseIterable, Sendable {
    case image
    case video
    case audio
    case document
    case archive
    case installer
    case code
    case other
}

enum DiskFileActivityMarker: String, Codable, CaseIterable, Sendable {
    case recent
    case days7
    case days30
    case days90
    case unknown

    static func classify(lastActivityDate: Date?, now: Date = Date()) -> DiskFileActivityMarker {
        guard let lastActivityDate else { return .unknown }
        let days = max(now.timeIntervalSince(lastActivityDate), 0) / 86_400
        if days >= 90 { return .days90 }
        if days >= 30 { return .days30 }
        if days >= 7 { return .days7 }
        return .recent
    }
}

struct DiskFileRecord: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let path: String
    let fileExtension: String
    let category: DiskFileCategory
    let size: Int64
    let logicalSize: Int64
    let creationDate: Date?
    let modifiedDate: Date?
    let accessedDate: Date?
    let lastOpenedDate: Date?

    var lastActivityDate: Date? {
        [lastOpenedDate, accessedDate, modifiedDate].compactMap { $0 }.max()
    }

    func activityMarker(at date: Date = Date()) -> DiskFileActivityMarker {
        DiskFileActivityMarker.classify(lastActivityDate: lastActivityDate, now: date)
    }
}

struct DiskFileCategoryBreakdown: Hashable, Codable, Sendable {
    let category: DiskFileCategory
    let fileCount: Int
    let totalBytes: Int64
}

struct DiskFileInventorySummary: Hashable, Codable, Sendable {
    let eligibleFileCount: Int
    let eligibleBytes: Int64
    let returnedFileCount: Int
    let returnedBytes: Int64
    let visitedEntryCount: Int
    let cacheHitCount: Int
    let metadataReadCount: Int
    let unreadableEntryCount: Int
    let wasTruncated: Bool
    let minimumFileSize: Int64
    let scanDuration: TimeInterval
    let completedAt: Date
    let categoryBreakdown: [DiskFileCategoryBreakdown]
}

struct DiskFileInventoryScanResult: Sendable {
    let files: [DiskFileRecord]
    let summary: DiskFileInventorySummary
}

/// Bounded, metadata-only inventory for user files.
///
/// The scanner never reads file contents. It stores only paths, sizes, dates,
/// formats, and file identity metadata in its cache. Hidden/system/Agent state
/// and generated dependency trees are excluded from file-level cleanup rows.
enum DiskFileInventoryCore {
    private static let cacheVersion = 1
    private static let minimumFileSize: Int64 = 64 * 1_024
    private static let maxVisitedEntries = 200_000
    // The UI initially renders 300 rows and can page forward. Keeping tens of
    // thousands of path-rich records plus dictionary/filter copies offered no
    // practical benefit and amplified a scan into hundreds of MB of live state.
    private static let maxReturnedFiles = 8_000
    private static let maxCachedFiles = 16_000
    private static let maximumCacheBytes = 16 * 1_024 * 1_024
    private static let maximumScanDuration: TimeInterval = 30
    private static let spotlightRefreshInterval: TimeInterval = 24 * 60 * 60
    private static let cacheTouchInterval: TimeInterval = 24 * 60 * 60

    private struct CachedFile: Codable {
        let logicalSize: Int64
        let allocatedSize: Int64
        let modifiedAt: TimeInterval
        let accessedAt: TimeInterval
        let record: DiskFileRecord
        let spotlightCheckedAt: TimeInterval
        var lastSeenAt: TimeInterval
    }

    private struct InventoryCache: Codable {
        var version: Int
        var files: [String: CachedFile]
    }

    private struct MutableCategoryStats {
        var count = 0
        var bytes: Int64 = 0
    }

    /// Metadata collected from the filesystem enumerator before the optional
    /// Spotlight lookup. Keeping only the largest candidates avoids retaining
    /// every eligible file when a large home directory reaches the visit cap.
    private struct InventoryCandidate {
        let url: URL
        let path: String
        let name: String
        let fileExtension: String
        let category: DiskFileCategory
        let logicalSize: Int64
        let allocatedSize: Int64
        let creationDate: Date?
        let modifiedDate: Date?
        let accessedDate: Date?

        func record(lastOpenedDate: Date?) -> DiskFileRecord {
            DiskFileRecord(
                id: path,
                name: name,
                path: path,
                fileExtension: fileExtension,
                category: category,
                size: allocatedSize,
                logicalSize: logicalSize,
                creationDate: creationDate,
                modifiedDate: modifiedDate,
                accessedDate: accessedDate,
                lastOpenedDate: lastOpenedDate
            )
        }
    }

    /// A worst-first heap that retains only the largest files needed by the UI.
    /// Category totals and eligible-byte totals are still calculated for every
    /// visited file, so bounding the visible inventory does not hide coverage.
    private struct BoundedInventoryCandidates {
        let limit: Int
        private(set) var values: [InventoryCandidate] = []

        mutating func insert(_ candidate: InventoryCandidate) {
            guard limit > 0 else { return }
            if values.count < limit {
                values.append(candidate)
                siftUp(from: values.count - 1)
                return
            }
            guard let worst = values.first, Self.isPreferred(candidate, over: worst) else { return }
            values[0] = candidate
            siftDown(from: 0)
        }

        func sortedBestFirst() -> [InventoryCandidate] {
            values.sorted(by: Self.isPreferred)
        }

        private mutating func siftUp(from start: Int) {
            var child = start
            while child > 0 {
                let parent = (child - 1) / 2
                guard Self.isWorse(values[child], than: values[parent]) else { break }
                values.swapAt(child, parent)
                child = parent
            }
        }

        private mutating func siftDown(from start: Int) {
            var parent = start
            while true {
                let left = parent * 2 + 1
                guard left < values.count else { return }
                let right = left + 1
                var worseChild = left
                if right < values.count, Self.isWorse(values[right], than: values[left]) {
                    worseChild = right
                }
                guard Self.isWorse(values[worseChild], than: values[parent]) else { return }
                values.swapAt(parent, worseChild)
                parent = worseChild
            }
        }

        private static func isPreferred(_ lhs: InventoryCandidate, over rhs: InventoryCandidate) -> Bool {
            if lhs.allocatedSize != rhs.allocatedSize { return lhs.allocatedSize > rhs.allocatedSize }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }

        private static func isWorse(_ lhs: InventoryCandidate, than rhs: InventoryCandidate) -> Bool {
            if lhs.allocatedSize != rhs.allocatedSize { return lhs.allocatedSize < rhs.allocatedSize }
            return lhs.path.localizedStandardCompare(rhs.path) == .orderedDescending
        }
    }

    static func scan(
        homeDirectory: String,
        authorizedRoots: Set<String>? = nil,
        isSandboxed: Bool,
        cacheURL: URL,
        now: Date = Date(),
        maximumReturnedFiles: Int = maxReturnedFiles,
        lastOpenedDateProvider: ((URL) -> Date?)? = nil
    ) -> DiskFileInventoryScanResult {
        let startedAt = Date()
        let roots = scanRoots(
            homeDirectory: homeDirectory,
            authorizedRoots: authorizedRoots,
            isSandboxed: isSandboxed
        )
        let openedDateProvider = lastOpenedDateProvider ?? spotlightLastOpenedDate
        var cache = loadCache(from: cacheURL)
        let returnLimit = min(max(maximumReturnedFiles, 1), maxReturnedFiles)
        var candidates = BoundedInventoryCandidates(limit: returnLimit)
        var categoryStats: [DiskFileCategory: MutableCategoryStats] = [:]
        var discoveredPaths = Set<String>()
        var visitedEntryCount = 0
        var eligibleFileCount = 0
        var eligibleBytes: Int64 = 0
        var cacheHitCount = 0
        var metadataReadCount = 0
        var unreadableEntryCount = 0
        var hitVisitLimit = false
        var hitTimeLimit = false
        var cacheChanged = false

        rootLoop: for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in
                    unreadableEntryCount += 1
                    return true
                }
            ) else {
                unreadableEntryCount += 1
                continue
            }

            for case let url as URL in enumerator {
                visitedEntryCount += 1
                if visitedEntryCount > maxVisitedEntries {
                    hitVisitLimit = true
                    break rootLoop
                }
                if visitedEntryCount.isMultiple(of: 512),
                   Date().timeIntervalSince(startedAt) >= maximumScanDuration {
                    hitTimeLimit = true
                    break rootLoop
                }

                // URL resource values and Foundation enumerator entries can
                // accumulate autoreleased objects for the entire detached task.
                // Drain them per entry while retaining only compact candidates.
                autoreleasepool {
                    guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
                        unreadableEntryCount += 1
                        return
                    }
                    if values.isSymbolicLink == true {
                        enumerator.skipDescendants()
                        return
                    }
                    if values.isDirectory == true {
                        if shouldSkipDirectory(url.lastPathComponent.lowercased()) {
                            enumerator.skipDescendants()
                        }
                        return
                    }
                    guard values.isRegularFile == true else { return }

                    let logicalSize = Int64(values.fileSize ?? 0)
                    let allocatedSize = allocatedFileSize(values)
                    guard max(logicalSize, allocatedSize) >= minimumFileSize else { return }

                    let path = url.standardizedFileURL.path
                    guard discoveredPaths.insert(path).inserted else { return }
                    eligibleFileCount += 1
                    eligibleBytes += allocatedSize

                    let ext = url.pathExtension.lowercased()
                    let category = category(forExtension: ext)
                    candidates.insert(InventoryCandidate(
                        url: url,
                        path: path,
                        name: url.lastPathComponent,
                        fileExtension: ext,
                        category: category,
                        logicalSize: logicalSize,
                        allocatedSize: allocatedSize,
                        creationDate: values.creationDate,
                        modifiedDate: values.contentModificationDate,
                        accessedDate: values.contentAccessDate
                    ))
                    var stats = categoryStats[category] ?? MutableCategoryStats()
                    stats.count += 1
                    stats.bytes += allocatedSize
                    categoryStats[category] = stats
                }
            }
        }

        var returned: [DiskFileRecord] = []
        returned.reserveCapacity(candidates.values.count)
        for candidate in candidates.sortedBestFirst() {
            autoreleasepool {
                let modifiedAt = candidate.modifiedDate?.timeIntervalSince1970 ?? 0
                let accessedAt = candidate.accessedDate?.timeIntervalSince1970 ?? 0
                let cached = cache.files[candidate.path]
                let cacheMatches = cached?.logicalSize == candidate.logicalSize
                    && cached?.allocatedSize == candidate.allocatedSize
                    && approximatelyEqual(cached?.modifiedAt, modifiedAt)
                    && approximatelyEqual(cached?.accessedAt, accessedAt)
                let spotlightIsFresh = now.timeIntervalSince1970 - (cached?.spotlightCheckedAt ?? 0)
                    < spotlightRefreshInterval

                let record: DiskFileRecord
                if let cached, cacheMatches, spotlightIsFresh {
                    record = cached.record
                    cacheHitCount += 1
                    if now.timeIntervalSince1970 - cached.lastSeenAt >= cacheTouchInterval {
                        cache.files[candidate.path] = CachedFile(
                            logicalSize: cached.logicalSize,
                            allocatedSize: cached.allocatedSize,
                            modifiedAt: cached.modifiedAt,
                            accessedAt: cached.accessedAt,
                            record: cached.record,
                            spotlightCheckedAt: cached.spotlightCheckedAt,
                            lastSeenAt: now.timeIntervalSince1970
                        )
                        cacheChanged = true
                    }
                } else {
                    record = candidate.record(lastOpenedDate: openedDateProvider(candidate.url))
                    metadataReadCount += 1
                    cache.files[candidate.path] = CachedFile(
                        logicalSize: candidate.logicalSize,
                        allocatedSize: candidate.allocatedSize,
                        modifiedAt: modifiedAt,
                        accessedAt: accessedAt,
                        record: record,
                        spotlightCheckedAt: now.timeIntervalSince1970,
                        lastSeenAt: now.timeIntervalSince1970
                    )
                    cacheChanged = true
                }
                returned.append(record)
            }
        }
        let returnedBytes = returned.reduce(Int64(0)) { $0 + $1.size }
        trimAndSave(&cache, to: cacheURL, now: now, cacheChanged: cacheChanged)

        let completedAt = Date()
        let breakdown = DiskFileCategory.allCases.compactMap { category -> DiskFileCategoryBreakdown? in
            guard let stats = categoryStats[category], stats.count > 0 else { return nil }
            return DiskFileCategoryBreakdown(
                category: category,
                fileCount: stats.count,
                totalBytes: stats.bytes
            )
        }.sorted {
            if $0.totalBytes != $1.totalBytes { return $0.totalBytes > $1.totalBytes }
            return $0.category.rawValue < $1.category.rawValue
        }

        return DiskFileInventoryScanResult(
            files: returned,
            summary: DiskFileInventorySummary(
                eligibleFileCount: eligibleFileCount,
                eligibleBytes: eligibleBytes,
                returnedFileCount: returned.count,
                returnedBytes: returnedBytes,
                visitedEntryCount: visitedEntryCount,
                cacheHitCount: cacheHitCount,
                metadataReadCount: metadataReadCount,
                unreadableEntryCount: unreadableEntryCount,
                wasTruncated: hitVisitLimit || hitTimeLimit || eligibleFileCount > returned.count,
                minimumFileSize: minimumFileSize,
                scanDuration: completedAt.timeIntervalSince(startedAt),
                completedAt: completedAt,
                categoryBreakdown: breakdown
            )
        )
    }

    private static let resourceKeys: Set<URLResourceKey> = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
        .fileAllocatedSizeKey,
        .totalFileAllocatedSizeKey,
        .creationDateKey,
        .contentModificationDateKey,
        .contentAccessDateKey
    ]

    private static func scanRoots(
        homeDirectory: String,
        authorizedRoots: Set<String>?,
        isSandboxed: Bool
    ) -> [URL] {
        let home = URL(fileURLWithPath: homeDirectory, isDirectory: true).standardizedFileURL
        let candidates: [URL]
        if isSandboxed {
            candidates = (authorizedRoots ?? []).map {
                URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL
            }
        } else {
            candidates = ["Downloads", "Desktop", "Documents", "Movies", "Pictures", "Music"].map {
                home.appendingPathComponent($0, isDirectory: true).standardizedFileURL
            }
        }

        let existing = candidates
            .filter { candidate in
                var isDirectory: ObjCBool = false
                return FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
                    && !isProtectedInventoryRoot(candidate, home: home)
            }
            .sorted { $0.path.count < $1.path.count }
        var roots: [URL] = []
        for candidate in existing where !roots.contains(where: {
            candidate.path == $0.path || candidate.path.hasPrefix($0.path + "/")
        }) {
            roots.append(candidate)
        }
        return roots
    }

    private static func isProtectedInventoryRoot(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        if AgentDataProtection.containsProtectedData(path: path, homeDirectory: homePath) {
            return true
        }
        guard path != homePath, path.hasPrefix(homePath + "/") else { return false }
        let relative = String(path.dropFirst(homePath.count + 1))
        let components = relative.split(separator: "/").map { $0.lowercased() }
        return components.contains { protectedInventoryComponents.contains($0) }
    }

    private static let protectedInventoryComponents: Set<String> = [
        ".trash", ".ssh", ".gnupg", "library", "applications", "keychains",
        "wallet", "wallets", "credentials"
    ]

    private static func shouldSkipDirectory(_ lowercasedName: String) -> Bool {
        skippedDirectoryNames.contains(lowercasedName)
    }

    private static let skippedDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg", ".trash", ".codex", ".claude", ".grok",
        ".gemini", ".cursor", ".ssh", ".gnupg", "node_modules", "pods",
        "deriveddata", ".gradle", ".swiftpm", ".build", ".cache", "__pycache__",
        ".venv", "venv", "library", "applications", "keychains", "wallets",
        "credentials", "system", "private", "dev"
    ]

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff",
        "bmp", "svg", "avif", "dng", "raw", "ico"
    ]
    private static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm", "flv", "wmv", "mpg",
        "mpeg", "mts", "m2ts", "3gp"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "wav", "aac", "flac", "ogg", "opus", "aiff", "aif", "wma"
    ]
    private static let documentExtensions: Set<String> = [
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers",
        "key", "keynote", "txt", "rtf", "md", "markdown", "csv", "tsv", "json",
        "xml", "yaml", "yml", "epub", "mobi"
    ]
    private static let archiveExtensions: Set<String> = [
        "zip", "zipx", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz", "zst",
        "lzh", "cab", "iso"
    ]
    private static let installerExtensions: Set<String> = [
        "dmg", "pkg", "ipa", "apk", "aab", "exe", "msi", "msix", "appx",
        "appxbundle", "deb", "rpm", "snap"
    ]
    private static let codeExtensions: Set<String> = [
        "swift", "m", "mm", "h", "c", "cc", "cpp", "hpp", "rs", "go", "py",
        "js", "jsx", "ts", "tsx", "java", "kt", "kts", "cs", "php", "rb",
        "sh", "bash", "zsh", "fish", "sql", "html", "css", "scss", "vue",
        "svelte", "dart", "lua", "ex", "exs", "erl", "hrl", "scala", "clj",
        "gradle"
    ]

    private static func category(forExtension ext: String) -> DiskFileCategory {
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if installerExtensions.contains(ext) { return .installer }
        if archiveExtensions.contains(ext) { return .archive }
        if documentExtensions.contains(ext) { return .document }
        if codeExtensions.contains(ext) { return .code }
        return .other
    }

    private static func allocatedFileSize(_ values: URLResourceValues) -> Int64 {
        if let size = values.totalFileAllocatedSize { return Int64(size) }
        if let size = values.fileAllocatedSize { return Int64(size) }
        return Int64(values.fileSize ?? 0)
    }

    private static func spotlightLastOpenedDate(for url: URL) -> Date? {
        guard let item = MDItemCreate(kCFAllocatorDefault, url.path as CFString),
              let value = MDItemCopyAttribute(item, kMDItemLastUsedDate) else {
            return nil
        }
        return value as? Date
    }

    private static func approximatelyEqual(_ lhs: TimeInterval?, _ rhs: TimeInterval) -> Bool {
        guard let lhs else { return false }
        return abs(lhs - rhs) < 0.001
    }

    private static func loadCache(from url: URL) -> InventoryCache {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size >= 0,
              size <= maximumCacheBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let cache = try? JSONDecoder().decode(InventoryCache.self, from: data),
              cache.version == cacheVersion else {
            return InventoryCache(version: cacheVersion, files: [:])
        }
        return cache
    }

    private static func trimAndSave(
        _ cache: inout InventoryCache,
        to url: URL,
        now: Date,
        cacheChanged: Bool
    ) {
        var needsSave = cacheChanged
        let cutoff = now.addingTimeInterval(-90 * 24 * 60 * 60).timeIntervalSince1970
        let originalCount = cache.files.count
        cache.files = cache.files.filter { $0.value.lastSeenAt >= cutoff }
        if cache.files.count != originalCount { needsSave = true }
        if cache.files.count > maxCachedFiles {
            let newest = cache.files
                .sorted { $0.value.lastSeenAt > $1.value.lastSeenAt }
                .prefix(maxCachedFiles)
            cache.files = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
            needsSave = true
        }
        cache.version = cacheVersion
        guard needsSave else { return }
        let encoder = JSONEncoder()
        guard var data = try? encoder.encode(cache) else { return }
        if data.count > maximumCacheBytes {
            let orderedPaths = cache.files.sorted { lhs, rhs in
                if lhs.value.lastSeenAt != rhs.value.lastSeenAt {
                    return lhs.value.lastSeenAt > rhs.value.lastSeenAt
                }
                return lhs.key < rhs.key
            }.map(\.key)
            var keepCount = orderedPaths.count
            while data.count > maximumCacheBytes, keepCount > 1 {
                keepCount = max(1, keepCount * 3 / 4)
                let keep = Set(orderedPaths.prefix(keepCount))
                cache.files = cache.files.filter { keep.contains($0.key) }
                guard let reduced = try? encoder.encode(cache) else { return }
                data = reduced
            }
        }
        guard data.count <= maximumCacheBytes else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: [.atomic])
    }
}
