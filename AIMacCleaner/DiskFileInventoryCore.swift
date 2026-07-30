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
    private static let maxReturnedFiles = 50_000
    private static let maxCachedFiles = 100_000
    private static let spotlightRefreshInterval: TimeInterval = 24 * 60 * 60

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

    static func scan(
        homeDirectory: String,
        authorizedRoots: Set<String>? = nil,
        isSandboxed: Bool,
        cacheURL: URL,
        now: Date = Date(),
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
        var records: [DiskFileRecord] = []
        var categoryStats: [DiskFileCategory: MutableCategoryStats] = [:]
        var discoveredPaths = Set<String>()
        var visitedEntryCount = 0
        var eligibleFileCount = 0
        var eligibleBytes: Int64 = 0
        var cacheHitCount = 0
        var metadataReadCount = 0
        var unreadableEntryCount = 0
        var hitVisitLimit = false

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

                guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
                    unreadableEntryCount += 1
                    continue
                }
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    continue
                }
                if values.isDirectory == true {
                    if shouldSkipDirectory(url.lastPathComponent.lowercased()) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard values.isRegularFile == true else { continue }

                let logicalSize = Int64(values.fileSize ?? 0)
                let allocatedSize = allocatedFileSize(values)
                guard max(logicalSize, allocatedSize) >= minimumFileSize else { continue }

                let path = url.standardizedFileURL.path
                guard discoveredPaths.insert(path).inserted else { continue }
                eligibleFileCount += 1
                eligibleBytes += allocatedSize

                let modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
                let accessedAt = values.contentAccessDate?.timeIntervalSince1970 ?? 0
                let cached = cache.files[path]
                let cacheMatches = cached?.logicalSize == logicalSize
                    && cached?.allocatedSize == allocatedSize
                    && approximatelyEqual(cached?.modifiedAt, modifiedAt)
                    && approximatelyEqual(cached?.accessedAt, accessedAt)
                let spotlightIsFresh = now.timeIntervalSince1970 - (cached?.spotlightCheckedAt ?? 0)
                    < spotlightRefreshInterval

                let record: DiskFileRecord
                if let cached, cacheMatches, spotlightIsFresh {
                    record = cached.record
                    cacheHitCount += 1
                    cache.files[path] = CachedFile(
                        logicalSize: cached.logicalSize,
                        allocatedSize: cached.allocatedSize,
                        modifiedAt: cached.modifiedAt,
                        accessedAt: cached.accessedAt,
                        record: cached.record,
                        spotlightCheckedAt: cached.spotlightCheckedAt,
                        lastSeenAt: now.timeIntervalSince1970
                    )
                } else {
                    let ext = url.pathExtension.lowercased()
                    record = DiskFileRecord(
                        id: path,
                        name: url.lastPathComponent,
                        path: path,
                        fileExtension: ext,
                        category: category(forExtension: ext),
                        size: allocatedSize,
                        logicalSize: logicalSize,
                        creationDate: values.creationDate,
                        modifiedDate: values.contentModificationDate,
                        accessedDate: values.contentAccessDate,
                        lastOpenedDate: openedDateProvider(url)
                    )
                    metadataReadCount += 1
                    cache.files[path] = CachedFile(
                        logicalSize: logicalSize,
                        allocatedSize: allocatedSize,
                        modifiedAt: modifiedAt,
                        accessedAt: accessedAt,
                        record: record,
                        spotlightCheckedAt: now.timeIntervalSince1970,
                        lastSeenAt: now.timeIntervalSince1970
                    )
                }

                records.append(record)
                var stats = categoryStats[record.category] ?? MutableCategoryStats()
                stats.count += 1
                stats.bytes += record.size
                categoryStats[record.category] = stats
            }
        }

        records.sort {
            if $0.size != $1.size { return $0.size > $1.size }
            return $0.path.localizedStandardCompare($1.path) == .orderedAscending
        }
        let returned = Array(records.prefix(maxReturnedFiles))
        let returnedBytes = returned.reduce(Int64(0)) { $0 + $1.size }
        trimAndSave(&cache, to: cacheURL, now: now)

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
                wasTruncated: hitVisitLimit || records.count > returned.count,
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
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .sorted { $0.path.count < $1.path.count }
        var roots: [URL] = []
        for candidate in existing where !roots.contains(where: {
            candidate.path == $0.path || candidate.path.hasPrefix($0.path + "/")
        }) {
            roots.append(candidate)
        }
        return roots
    }

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
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(InventoryCache.self, from: data),
              cache.version == cacheVersion else {
            return InventoryCache(version: cacheVersion, files: [:])
        }
        return cache
    }

    private static func trimAndSave(_ cache: inout InventoryCache, to url: URL, now: Date) {
        let cutoff = now.addingTimeInterval(-90 * 24 * 60 * 60).timeIntervalSince1970
        cache.files = cache.files.filter { $0.value.lastSeenAt >= cutoff }
        if cache.files.count > maxCachedFiles {
            let newest = cache.files
                .sorted { $0.value.lastSeenAt > $1.value.lastSeenAt }
                .prefix(maxCachedFiles)
            cache.files = Dictionary(uniqueKeysWithValues: newest.map { ($0.key, $0.value) })
        }
        cache.version = cacheVersion
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: [.atomic])
    }
}
