import CryptoKit
import Darwin
import Foundation

enum StorageCleanupItemKind: String, Codable, Sendable {
    case historicalBuild
    case installerArtifact
}

struct StorageCleanupItem: Hashable, Codable, Sendable {
    let kind: StorageCleanupItemKind
    let name: String
    let path: String
    let size: Int64
    let fileCount: Int
    let isDirectory: Bool
    let modifiedDate: Date?
    let detail: String
}

struct AgentStorageBreakdown: Hashable, Codable, Sendable {
    let agentName: String
    let sessionBytes: Int64
    let sessionFileCount: Int
    let embeddedMediaBytes: Int64
    let duplicateMediaBytes: Int64
}

struct StorageOptimizationSummary: Hashable, Codable, Sendable {
    let agentSessionBytes: Int64
    let agentSessionFileCount: Int
    let embeddedMediaBytes: Int64
    let uniqueMediaBytes: Int64
    let duplicateMediaBytes: Int64
    let withinSessionDuplicateBytes: Int64
    let crossSessionDuplicateBytes: Int64
    let embeddedMediaOccurrences: Int
    let uniqueMediaCount: Int
    let cacheHitCount: Int
    let hashedFileCount: Int
    let fingerprintedBytes: Int64
    let historicalBuildCount: Int
    let historicalBuildBytes: Int64
    let retainedBuildCount: Int
    let installerArtifactCount: Int
    let installerArtifactBytes: Int64
    let scanDuration: TimeInterval
    let completedAt: Date
    let agentBreakdown: [AgentStorageBreakdown]
}

struct StorageOptimizationScanResult: Sendable {
    let summary: StorageOptimizationSummary
    let cleanupItems: [StorageCleanupItem]
}

enum SystemDataStorageKind: String, Codable, Sendable {
    case caches
    case temporary
    case developer
    case applicationSupport
    case appContainers
    case systemDiagnostics
    case virtualMemory
}

enum SystemDataStorageDisposition: String, Codable, Sendable {
    /// Regenerable data already covered by the cleanup safety pipeline.
    case cleanable
    /// Large user/application data: show it, but require item-level review elsewhere.
    case reviewRequired
    /// macOS-owned data such as swap or diagnostic databases; never delete directly.
    case systemManaged
}

struct SystemDataStorageBucket: Hashable, Codable, Sendable {
    let kind: SystemDataStorageKind
    let path: String
    let allocatedBytes: Int64
    let visitedEntryCount: Int
    let unreadableEntryCount: Int
    let disposition: SystemDataStorageDisposition
    let wasTruncated: Bool
}

struct SystemDataStorageSummary: Hashable, Codable, Sendable {
    let buckets: [SystemDataStorageBucket]
    let measuredBytes: Int64
    let visitedEntryCount: Int
    let unreadableEntryCount: Int
    let wasTruncated: Bool
    let scanDuration: TimeInterval
    let completedAt: Date
}

/// Bounded, read-only explanation of the major locations macOS may group under "System Data".
///
/// The Storage Settings number is not a deletable directory and can include APFS/purgeable and
/// system-managed data. This scanner therefore reports physical allocation by source and labels
/// what may enter the normal cleanup pipeline. It retains no path list and never deletes.
enum SystemDataStorageInspectionCore {
    private static let maximumVisitedEntries = 180_000
    private static let maximumVisitedEntriesPerRoot = 25_000
    private static let maximumScanDuration: TimeInterval = 12
    private static let maximumScanDurationPerRoot: TimeInterval = 1.5

    private struct RootDefinition {
        let kind: SystemDataStorageKind
        let url: URL
        let disposition: SystemDataStorageDisposition
    }

    static func scan(homeDirectory: String, now: Date = Date()) -> SystemDataStorageSummary {
        let startedAt = Date()
        let deadline = startedAt.addingTimeInterval(maximumScanDuration)
        let roots = definitions(homeDirectory: homeDirectory)
        var buckets: [SystemDataStorageBucket] = []
        var totalVisited = 0
        var totalUnreadable = 0
        var didTruncate = false

        for root in roots {
            guard totalVisited < maximumVisitedEntries else {
                didTruncate = true
                break
            }
            let rootDeadline = min(
                deadline,
                Date().addingTimeInterval(maximumScanDurationPerRoot)
            )
            let result = allocatedSize(
                of: root.url,
                remainingEntries: min(
                    maximumVisitedEntriesPerRoot,
                    maximumVisitedEntries - totalVisited
                ),
                deadline: rootDeadline
            )
            totalVisited += result.visited
            totalUnreadable += result.unreadable
            didTruncate = didTruncate || result.truncated
            buckets.append(SystemDataStorageBucket(
                kind: root.kind,
                path: root.url.path,
                allocatedBytes: result.bytes,
                visitedEntryCount: result.visited,
                unreadableEntryCount: result.unreadable,
                disposition: root.disposition,
                wasTruncated: result.truncated
            ))
        }

        let completedAt = Date()
        return SystemDataStorageSummary(
            buckets: buckets,
            measuredBytes: buckets.reduce(Int64(0)) { $0 + max($1.allocatedBytes, 0) },
            visitedEntryCount: totalVisited,
            unreadableEntryCount: totalUnreadable,
            wasTruncated: didTruncate,
            scanDuration: completedAt.timeIntervalSince(startedAt),
            completedAt: completedAt
        )
    }

    private static func definitions(homeDirectory: String) -> [RootDefinition] {
        let home = URL(fileURLWithPath: homeDirectory, isDirectory: true).standardizedFileURL
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let temporary = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .resolvingSymlinksInPath()
        let perUserTemporaryRoot = temporary.deletingLastPathComponent()

        return [
            RootDefinition(
                kind: .caches,
                url: library.appendingPathComponent("Caches", isDirectory: true),
                disposition: .cleanable
            ),
            RootDefinition(
                kind: .temporary,
                url: perUserTemporaryRoot,
                disposition: .reviewRequired
            ),
            RootDefinition(
                kind: .developer,
                url: library.appendingPathComponent("Developer", isDirectory: true),
                disposition: .reviewRequired
            ),
            RootDefinition(
                kind: .applicationSupport,
                url: library.appendingPathComponent("Application Support", isDirectory: true),
                disposition: .reviewRequired
            ),
            RootDefinition(
                kind: .appContainers,
                url: library.appendingPathComponent("Containers", isDirectory: true),
                disposition: .reviewRequired
            ),
            RootDefinition(
                kind: .systemDiagnostics,
                url: URL(fileURLWithPath: "/private/var/db/diagnostics", isDirectory: true),
                disposition: .systemManaged
            ),
            RootDefinition(
                kind: .virtualMemory,
                url: URL(fileURLWithPath: "/private/var/vm", isDirectory: true),
                disposition: .systemManaged
            )
        ]
    }

    private static func allocatedSize(
        of root: URL,
        remainingEntries: Int,
        deadline: Date
    ) -> (bytes: Int64, visited: Int, unreadable: Int, truncated: Bool) {
        let keys: [URLResourceKey] = [
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileAllocatedSizeKey
        ]
        guard FileManager.default.fileExists(atPath: root.path) else {
            return (0, 0, 0, false)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return (0, 0, 1, false)
        }

        var bytes: Int64 = 0
        var visited = 0
        var unreadable = 0
        var truncated = false

        for case let url as URL in enumerator {
            if visited >= remainingEntries || Date() >= deadline || Task.isCancelled {
                truncated = true
                break
            }
            visited += 1
            autoreleasepool {
                do {
                    let values = try url.resourceValues(forKeys: Set(keys))
                    guard values.isSymbolicLink != true, values.isRegularFile == true else { return }
                    bytes += Int64(max(values.fileAllocatedSize ?? 0, 0))
                } catch {
                    unreadable += 1
                }
            }
        }
        return (max(bytes, 0), visited, unreadable, truncated)
    }
}

/// A local-only scanner for Agent session payloads and historical build output.
///
/// Agent files are never rewritten or returned as deletion candidates. The cache
/// stores only paths, file identity, sizes, and content digests; it never stores
/// conversation prose or media bytes.
enum StorageOptimizationCore {
    private static let cacheVersion = 3
    private static let minimumInstallerSize: Int64 = 1 * 1024 * 1024
    private static let recentlyModifiedProtection: TimeInterval = 30 * 60
    private static let maxAgentFiles = 8_000
    private static let maxArtifactEntries = 100_000
    private static let maxCleanupItems = 800
    private static let cacheTouchInterval: TimeInterval = 24 * 60 * 60
    private static let maximumCacheBytes = 64 * 1_024 * 1_024
    private static let maximumAgentScanDuration: TimeInterval = 35
    // Very large Codex JSONL files can be gigabytes. Fingerprint only a bounded
    // prefix per file and persist a newline-aligned offset so later scans resume
    // instead of monopolizing CPU and allocator pages in one UI action.
    private static let maximumFingerprintBytesPerFilePass: Int64 = 64 * 1_024 * 1_024
    private static let allocatorReliefIntervalBytes: Int64 = 16 * 1_024 * 1_024

    private struct AgentRoot {
        let agentName: String
        let url: URL
    }

    private enum EmbeddedMediaKind: String, Codable {
        case image
        case audio
        case video
        case attachment
    }

    private struct PayloadFingerprint: Hashable, Codable {
        let digest: String
        let kind: EmbeddedMediaKind
        let encodedBytes: Int64
        var occurrences: Int

        var key: String { "\(kind.rawValue):\(digest)" }
    }

    private struct CachedAgentFile: Codable {
        let size: Int64
        let modifiedAt: TimeInterval
        let deviceID: UInt64
        let inode: UInt64
        let payloads: [PayloadFingerprint]
        let endedWithNewline: Bool
        let tailDigest: String
        let tailByteCount: Int
        var lastAccessedAt: TimeInterval
    }

    private struct EmbeddedPayloadScan {
        let payloads: [PayloadFingerprint]
        let endedWithNewline: Bool
        let processedBytes: Int64
        let tailDigest: String
        let tailByteCount: Int
    }

    private struct FingerprintCache: Codable {
        var version: Int
        var files: [String: CachedAgentFile]
    }

    private struct AgentFileScan {
        let agentName: String
        let path: String
        let size: Int64
        let payloads: [PayloadFingerprint]
    }

    private struct BuildRecord {
        enum Kind {
            case xcodeArchive
            case xcodeResult
            case xcodeBuildLog
            case xcodeDerivedData
            case versionedOutput
        }

        let kind: Kind
        let url: URL
        let groupKey: String
        let modifiedDate: Date
    }

    private struct BuildScanResult {
        let items: [StorageCleanupItem]
        let retainedCount: Int
    }

    private struct ArtifactDiscovery {
        var installers: [StorageCleanupItem] = []
        var versionedBuilds: [BuildRecord] = []
    }

    private struct MutableAgentStats {
        var sessionBytes: Int64 = 0
        var sessionFileCount = 0
        var embeddedMediaBytes: Int64 = 0
        var perFileUniqueMediaBytes: Int64 = 0
        var payloads: [String: PayloadFingerprint] = [:]
    }

    static func scan(
        homeDirectory: String,
        authorizedRoots: Set<String>? = nil,
        isSandboxed: Bool,
        cacheURL: URL,
        retainBuildCount: Int = 3,
        now: Date = Date()
    ) -> StorageOptimizationScanResult {
        let startedAt = Date()
        let home = URL(fileURLWithPath: homeDirectory, isDirectory: true).standardizedFileURL
        let normalizedRoots = authorizedRoots.map {
            Set($0.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path })
        }

        let agentResult = scanAgentStorage(
            home: home,
            authorizedRoots: normalizedRoots,
            isSandboxed: isSandboxed,
            cacheURL: cacheURL,
            now: now
        )

        var artifactDiscovery = discoverArtifacts(
            home: home,
            authorizedRoots: normalizedRoots,
            isSandboxed: isSandboxed
        )
        var buildRecords = scanXcodeBuildHistory(
            home: home,
            authorizedRoots: normalizedRoots,
            isSandboxed: isSandboxed
        )
        buildRecords.append(contentsOf: artifactDiscovery.versionedBuilds)
        let buildResult = buildCleanupItems(
            from: buildRecords,
            retaining: max(retainBuildCount, 1),
            now: now
        )

        let historicalPaths = buildResult.items
            .filter(\.isDirectory)
            .map { URL(fileURLWithPath: $0.path, isDirectory: true).standardizedFileURL.path }
        artifactDiscovery.installers.removeAll { installer in
            historicalPaths.contains { installer.path.hasPrefix($0 + "/") }
        }

        let cleanupItems = Array(
            (buildResult.items + artifactDiscovery.installers)
                .sorted { lhs, rhs in
                    if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
                    if lhs.size != rhs.size { return lhs.size > rhs.size }
                    return lhs.path < rhs.path
                }
                .prefix(maxCleanupItems)
        )

        let historicalItems = cleanupItems.filter { $0.kind == .historicalBuild }
        let installerItems = cleanupItems.filter { $0.kind == .installerArtifact }
        let completedAt = Date()
        let summary = StorageOptimizationSummary(
            agentSessionBytes: agentResult.sessionBytes,
            agentSessionFileCount: agentResult.sessionFileCount,
            embeddedMediaBytes: agentResult.embeddedMediaBytes,
            uniqueMediaBytes: agentResult.uniqueMediaBytes,
            duplicateMediaBytes: agentResult.duplicateMediaBytes,
            withinSessionDuplicateBytes: agentResult.withinSessionDuplicateBytes,
            crossSessionDuplicateBytes: agentResult.crossSessionDuplicateBytes,
            embeddedMediaOccurrences: agentResult.mediaOccurrences,
            uniqueMediaCount: agentResult.uniqueMediaCount,
            cacheHitCount: agentResult.cacheHits,
            hashedFileCount: agentResult.hashedFiles,
            fingerprintedBytes: agentResult.fingerprintedBytes,
            historicalBuildCount: historicalItems.count,
            historicalBuildBytes: historicalItems.reduce(Int64(0)) { $0 + $1.size },
            retainedBuildCount: buildResult.retainedCount,
            installerArtifactCount: installerItems.count,
            installerArtifactBytes: installerItems.reduce(Int64(0)) { $0 + $1.size },
            scanDuration: completedAt.timeIntervalSince(startedAt),
            completedAt: completedAt,
            agentBreakdown: agentResult.breakdown
        )
        return StorageOptimizationScanResult(summary: summary, cleanupItems: cleanupItems)
    }

    // MARK: - Agent session analysis

    private static func scanAgentStorage(
        home: URL,
        authorizedRoots: Set<String>?,
        isSandboxed: Bool,
        cacheURL: URL,
        now: Date
    ) -> (
        sessionBytes: Int64,
        sessionFileCount: Int,
        embeddedMediaBytes: Int64,
        uniqueMediaBytes: Int64,
        duplicateMediaBytes: Int64,
        withinSessionDuplicateBytes: Int64,
        crossSessionDuplicateBytes: Int64,
        mediaOccurrences: Int,
        uniqueMediaCount: Int,
        cacheHits: Int,
        hashedFiles: Int,
        fingerprintedBytes: Int64,
        breakdown: [AgentStorageBreakdown]
    ) {
        let startedAt = Date()
        let roots = agentRoots(home: home).filter {
            isAllowed($0.url, authorizedRoots: authorizedRoots, isSandboxed: isSandboxed)
        }
        var cache = loadCache(from: cacheURL)
        var discoveredPaths = Set<String>()
        var scans: [AgentFileScan] = []
        var cacheHits = 0
        var hashedFiles = 0
        var fingerprintedBytes: Int64 = 0
        var visited = 0
        var cacheChanged = false
        var deadlineReached = false

        for root in roots where FileManager.default.fileExists(atPath: root.url.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root.url,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                visited += 1
                if visited > maxAgentFiles { break }
                if visited.isMultiple(of: 64),
                   Date().timeIntervalSince(startedAt) >= maximumAgentScanDuration {
                    deadlineReached = true
                    break
                }
                autoreleasepool {
                    let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values?.isRegularFile == true, values?.isSymbolicLink != true else { return }
                    let ext = url.pathExtension.lowercased()
                    guard ext == "jsonl" || ext == "ndjson" else { return }

                    let path = url.standardizedFileURL.path
                    guard discoveredPaths.insert(path).inserted,
                          let identity = fileIdentity(at: url) else { return }

                    let payloads: [PayloadFingerprint]
                    if var cached = cache.files[path],
                       cached.deviceID == identity.deviceID,
                       cached.inode == identity.inode,
                       cached.size == identity.size,
                       abs(cached.modifiedAt - identity.modifiedAt) < 0.001 {
                        payloads = cached.payloads
                        if now.timeIntervalSince1970 - cached.lastAccessedAt >= cacheTouchInterval {
                            cached.lastAccessedAt = now.timeIntervalSince1970
                            cache.files[path] = cached
                            cacheChanged = true
                        }
                        cacheHits += 1
                    } else if let cached = cache.files[path],
                              cached.deviceID == identity.deviceID,
                              cached.inode == identity.inode,
                              cached.endedWithNewline,
                              identity.size > cached.size,
                              verifyCachedTail(cached, in: url),
                              let appended = try? scanEmbeddedPayloads(in: url, startingAt: cached.size),
                              appended.processedBytes >= cached.size {
                        payloads = mergePayloads(cached.payloads, with: appended.payloads)
                        let finalIdentity = fileIdentity(at: url)
                        cache.files[path] = CachedAgentFile(
                            size: appended.processedBytes,
                            modifiedAt: finalIdentity?.size == appended.processedBytes
                                ? (finalIdentity?.modifiedAt ?? identity.modifiedAt)
                                : identity.modifiedAt,
                            deviceID: identity.deviceID,
                            inode: identity.inode,
                            payloads: payloads,
                            endedWithNewline: appended.endedWithNewline,
                            tailDigest: appended.tailDigest,
                            tailByteCount: appended.tailByteCount,
                            lastAccessedAt: now.timeIntervalSince1970
                        )
                        cacheChanged = true
                        fingerprintedBytes += appended.processedBytes - cached.size
                        hashedFiles += 1
                    } else {
                        let full = try? scanEmbeddedPayloads(in: url)
                        payloads = full?.payloads ?? []
                        let processedBytes = full?.processedBytes ?? identity.size
                        let finalIdentity = fileIdentity(at: url)
                        cache.files[path] = CachedAgentFile(
                            size: processedBytes,
                            modifiedAt: finalIdentity?.size == processedBytes
                                ? (finalIdentity?.modifiedAt ?? identity.modifiedAt)
                                : identity.modifiedAt,
                            deviceID: identity.deviceID,
                            inode: identity.inode,
                            payloads: payloads,
                            endedWithNewline: full?.endedWithNewline ?? false,
                            tailDigest: full?.tailDigest ?? "",
                            tailByteCount: full?.tailByteCount ?? 0,
                            lastAccessedAt: now.timeIntervalSince1970
                        )
                        cacheChanged = true
                        fingerprintedBytes += processedBytes
                        hashedFiles += 1
                    }
                    scans.append(AgentFileScan(
                        agentName: root.agentName,
                        path: path,
                        size: identity.size,
                        payloads: payloads
                    ))
                }
            }
            if visited > maxAgentFiles || deadlineReached { break }
        }

        trimAndSave(&cache, to: cacheURL, now: now, cacheChanged: cacheChanged)

        var globalPayloads: [String: PayloadFingerprint] = [:]
        var statsByAgent: [String: MutableAgentStats] = [:]
        var sessionBytes: Int64 = 0
        var embeddedMediaBytes: Int64 = 0
        var perFileUniqueMediaBytes: Int64 = 0
        var mediaOccurrences = 0

        for scan in scans {
            sessionBytes += scan.size
            var agentStats = statsByAgent[scan.agentName] ?? MutableAgentStats()
            agentStats.sessionBytes += scan.size
            agentStats.sessionFileCount += 1

            var localUniqueBytes: Int64 = 0
            for payload in scan.payloads {
                let payloadBytes = payload.encodedBytes * Int64(payload.occurrences)
                embeddedMediaBytes += payloadBytes
                mediaOccurrences += payload.occurrences
                localUniqueBytes += payload.encodedBytes
                agentStats.embeddedMediaBytes += payloadBytes
                agentStats.perFileUniqueMediaBytes += payload.encodedBytes
                agentStats.payloads[payload.key] = payload
                if globalPayloads[payload.key] == nil {
                    globalPayloads[payload.key] = payload
                }
            }
            perFileUniqueMediaBytes += localUniqueBytes
            statsByAgent[scan.agentName] = agentStats
        }

        let uniqueMediaBytes = globalPayloads.values.reduce(Int64(0)) { $0 + $1.encodedBytes }
        let duplicateMediaBytes = max(embeddedMediaBytes - uniqueMediaBytes, 0)
        let withinSessionDuplicateBytes = max(embeddedMediaBytes - perFileUniqueMediaBytes, 0)
        let crossSessionDuplicateBytes = max(perFileUniqueMediaBytes - uniqueMediaBytes, 0)

        let breakdown = statsByAgent.map { name, stats -> AgentStorageBreakdown in
            let unique = stats.payloads.values.reduce(Int64(0)) { $0 + $1.encodedBytes }
            return AgentStorageBreakdown(
                agentName: name,
                sessionBytes: stats.sessionBytes,
                sessionFileCount: stats.sessionFileCount,
                embeddedMediaBytes: stats.embeddedMediaBytes,
                duplicateMediaBytes: max(stats.embeddedMediaBytes - unique, 0)
            )
        }.sorted { $0.sessionBytes > $1.sessionBytes }

        return (
            sessionBytes,
            scans.count,
            embeddedMediaBytes,
            uniqueMediaBytes,
            duplicateMediaBytes,
            withinSessionDuplicateBytes,
            crossSessionDuplicateBytes,
            mediaOccurrences,
            globalPayloads.count,
            cacheHits,
            hashedFiles,
            fingerprintedBytes,
            breakdown
        )
    }

    private static func agentRoots(home: URL) -> [AgentRoot] {
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let definitions: [(String, String)] = [
            ("Codex", ".codex/sessions"),
            ("Codex", ".codex/archived_sessions"),
            ("MiniMax", ".minimax/sessions"),
            ("MiniMax", ".minimax/agents"),
            ("DeepSeek Harness", ".dsh/sessions"),
            ("DeepSeek Harness", "deepseek-harness/sessions"),
            ("Claude", ".claude/projects"),
            ("Grok", ".grok/sessions"),
            ("Grok", ".grok/projects"),
            ("Gemini", ".gemini/tmp"),
            ("Gemini", ".gemini/history"),
            ("Antigravity", ".gemini/antigravity-cli/brain"),
            ("Cursor", ".cursor/projects")
        ]
        var roots = definitions.map {
            AgentRoot(agentName: $0.0, url: home.appendingPathComponent($0.1, isDirectory: true))
        }
        roots.append(AgentRoot(
            agentName: "Cursor",
            url: support.appendingPathComponent("Cursor/User/workspaceStorage", isDirectory: true)
        ))
        roots.append(AgentRoot(
            agentName: "Cursor",
            url: support.appendingPathComponent("Cursor/snapshots", isDirectory: true)
        ))
        roots.append(AgentRoot(
            agentName: "Trae",
            url: support.appendingPathComponent("Trae/User/workspaceStorage", isDirectory: true)
        ))
        roots.append(AgentRoot(
            agentName: "Trae",
            url: support.appendingPathComponent("Trae CN/User/workspaceStorage", isDirectory: true)
        ))
        roots.append(AgentRoot(
            agentName: "CodeBuddy",
            url: support.appendingPathComponent("CodeBuddy CN/User/workspaceStorage", isDirectory: true)
        ))
        return roots
    }

    private static func scanEmbeddedPayloads(
        in url: URL,
        startingAt requestedOffset: Int64 = 0
    ) throws -> EmbeddedPayloadScan {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let fileSize = try handle.seekToEnd()
        let startOffset = min(UInt64(max(requestedOffset, 0)), fileSize)

        guard fileSize > 0 else {
            return EmbeddedPayloadScan(
                payloads: [],
                endedWithNewline: false,
                processedBytes: 0,
                tailDigest: "",
                tailByteCount: 0
            )
        }

        var parser = EmbeddedPayloadStreamParser()
        var processedBytes = Int64(startOffset)
        var tail = Data()
        if startOffset > 0 {
            let tailStart = startOffset > 4_096 ? startOffset - 4_096 : 0
            try handle.seek(toOffset: tailStart)
            tail = try handle.read(upToCount: Int(startOffset - tailStart)) ?? Data()
        }
        try handle.seek(toOffset: startOffset)
        var lastByte: UInt8? = tail.last
        var processedThisPass: Int64 = 0
        var bytesSinceAllocatorRelief: Int64 = 0
        var isSkippingOversizedRecord = false
        var stoppedAtRecordBoundary = false

        func updateTail(with data: Data) {
            guard !data.isEmpty else { return }
            if data.count >= 4_096 {
                tail = Data(data.suffix(4_096))
            } else {
                tail.append(data)
                if tail.count > 4_096 {
                    tail.removeFirst(tail.count - 4_096)
                }
            }
        }

        func relieveAllocatorIfNeeded(consumedBytes: Int) {
            bytesSinceAllocatorRelief += Int64(consumedBytes)
            guard bytesSinceAllocatorRelief >= allocatorReliefIntervalBytes else { return }
            _ = malloc_zone_pressure_relief(nil, 0)
            bytesSinceAllocatorRelief = 0
        }

        while let chunk = try handle.read(upToCount: 1_024 * 1_024), !chunk.isEmpty {
            if isSkippingOversizedRecord {
                if let newline = chunk.firstIndex(of: 10) {
                    let length = chunk.distance(from: chunk.startIndex, to: newline) + 1
                    let consumed = Data(chunk.prefix(length))
                    parser.discardInProgressRecord()
                    processedBytes += Int64(length)
                    updateTail(with: consumed)
                    lastByte = 10
                    relieveAllocatorIfNeeded(consumedBytes: length)
                    stoppedAtRecordBoundary = true
                    break
                }
                processedBytes += Int64(chunk.count)
                updateTail(with: chunk)
                lastByte = chunk.last
                relieveAllocatorIfNeeded(consumedBytes: chunk.count)
                continue
            }

            let remainingBudget = maximumFingerprintBytesPerFilePass - processedThisPass
            if remainingBudget > 0, Int64(chunk.count) <= remainingBudget {
                parser.consume(chunk)
                processedBytes += Int64(chunk.count)
                processedThisPass += Int64(chunk.count)
                updateTail(with: chunk)
                lastByte = chunk.last
                relieveAllocatorIfNeeded(consumedBytes: chunk.count)
                continue
            }

            let searchOffset = max(min(Int(remainingBudget), chunk.count), 0)
            let searchStart = chunk.index(chunk.startIndex, offsetBy: searchOffset)
            if let newline = chunk[searchStart...].firstIndex(of: 10) {
                let length = chunk.distance(from: chunk.startIndex, to: newline) + 1
                let consumed = Data(chunk.prefix(length))
                parser.consume(consumed)
                processedBytes += Int64(length)
                processedThisPass += Int64(length)
                updateTail(with: consumed)
                lastByte = 10
                relieveAllocatorIfNeeded(consumedBytes: length)
                stoppedAtRecordBoundary = true
                break
            } else {
                // The current JSONL record itself crosses the per-pass budget.
                // Parse this chunk, then find its terminating newline using the
                // fast Data search path without hashing an unbounded payload.
                parser.consume(chunk)
                processedBytes += Int64(chunk.count)
                processedThisPass += Int64(chunk.count)
                updateTail(with: chunk)
                lastByte = chunk.last
                relieveAllocatorIfNeeded(consumedBytes: chunk.count)
                isSkippingOversizedRecord = true
            }
        }
        if !stoppedAtRecordBoundary {
            if isSkippingOversizedRecord {
                parser.discardInProgressRecord()
            } else {
                parser.finishAtEndOfFile()
            }
        }
        _ = malloc_zone_pressure_relief(nil, 0)
        let tailByteCount = tail.count
        let tailDigest = Data(SHA256.hash(data: tail)).base64EncodedString()
        return EmbeddedPayloadScan(
            payloads: parser.payloads,
            endedWithNewline: lastByte == 10,
            processedBytes: processedBytes,
            tailDigest: tailDigest,
            tailByteCount: tailByteCount
        )
    }

    /// Incrementally recognizes data-URL payloads across arbitrary chunk
    /// boundaries and hashes the base64 bytes without retaining the payload.
    private struct EmbeddedPayloadStreamParser {
        private static let dataPrefix = Array("data:".utf8)
        private static let base64Marker = Array(";base64,".utf8)
        private static let imagePrefix = Array("image/".utf8)
        private static let audioPrefix = Array("audio/".utf8)
        private static let videoPrefix = Array("video/".utf8)
        private static let applicationPrefix = Array("application/".utf8)
        private static let maximumHeaderBytes = 160

        private var records: [String: PayloadFingerprint] = [:]
        private var prefixMatchCount = 0
        private var isReadingHeader = false
        private var header: [UInt8] = []
        private var payloadKind: EmbeddedMediaKind?
        private var payloadHasher = SHA256()
        private var payloadLength: Int64 = 0

        var payloads: [PayloadFingerprint] { Array(records.values) }

        mutating func consume(_ data: Data) {
            data.withUnsafeBytes { rawBuffer in
                let buffer = rawBuffer.bindMemory(to: UInt8.self)
                guard let base = buffer.baseAddress else { return }
                var index = 0
                while index < buffer.count {
                    if payloadKind != nil {
                        let start = index
                        while index < buffer.count, StorageOptimizationCore.isBase64Byte(base[index]) {
                            index += 1
                        }
                        if index > start {
                            payloadHasher.update(bufferPointer: UnsafeRawBufferPointer(
                                start: base.advanced(by: start),
                                count: index - start
                            ))
                            payloadLength += Int64(index - start)
                        }
                        if index == buffer.count { break }
                        finishPayload()
                        continue
                    }

                    consumeMetadataByte(base[index])
                    index += 1
                }
            }
        }

        mutating func finishAtEndOfFile() {
            if payloadKind != nil { finishPayload() }
        }

        mutating func discardInProgressRecord() {
            prefixMatchCount = 0
            isReadingHeader = false
            header.removeAll(keepingCapacity: true)
            payloadKind = nil
            payloadHasher = SHA256()
            payloadLength = 0
        }

        private mutating func consumeMetadataByte(_ byte: UInt8) {
            if isReadingHeader {
                header.append(byte)
                if header.count >= Self.base64Marker.count,
                   header.suffix(Self.base64Marker.count).elementsEqual(Self.base64Marker) {
                    let mediaType = header.dropLast(Self.base64Marker.count)
                    if mediaType.starts(with: Self.imagePrefix) {
                        beginPayload(.image)
                    } else if mediaType.starts(with: Self.audioPrefix) {
                        beginPayload(.audio)
                    } else if mediaType.starts(with: Self.videoPrefix) {
                        beginPayload(.video)
                    } else if mediaType.starts(with: Self.applicationPrefix) {
                        beginPayload(.attachment)
                    } else {
                        resetHeader(lastByte: byte)
                    }
                } else if header.count > Self.maximumHeaderBytes {
                    resetHeader(lastByte: byte)
                }
                return
            }

            if byte == Self.dataPrefix[prefixMatchCount] {
                prefixMatchCount += 1
                if prefixMatchCount == Self.dataPrefix.count {
                    prefixMatchCount = 0
                    isReadingHeader = true
                    header.removeAll(keepingCapacity: true)
                }
            } else {
                prefixMatchCount = byte == Self.dataPrefix[0] ? 1 : 0
            }
        }

        private mutating func beginPayload(_ kind: EmbeddedMediaKind) {
            payloadKind = kind
            payloadHasher = SHA256()
            payloadLength = 0
            isReadingHeader = false
            header.removeAll(keepingCapacity: true)
        }

        private mutating func finishPayload() {
            guard let kind = payloadKind else { return }
            if payloadLength >= 16 {
                let digest = Data(payloadHasher.finalize()).base64EncodedString()
                let key = "\(kind.rawValue):\(digest)"
                if var existing = records[key] {
                    existing.occurrences += 1
                    records[key] = existing
                } else {
                    records[key] = PayloadFingerprint(
                        digest: digest,
                        kind: kind,
                        encodedBytes: payloadLength,
                        occurrences: 1
                    )
                }
            }
            payloadKind = nil
            payloadHasher = SHA256()
            payloadLength = 0
        }

        private mutating func resetHeader(lastByte: UInt8) {
            isReadingHeader = false
            header.removeAll(keepingCapacity: true)
            prefixMatchCount = lastByte == Self.dataPrefix[0] ? 1 : 0
        }
    }

    private static func mergePayloads(
        _ existing: [PayloadFingerprint],
        with appended: [PayloadFingerprint]
    ) -> [PayloadFingerprint] {
        var merged = Dictionary(uniqueKeysWithValues: existing.map { ($0.key, $0) })
        for payload in appended {
            if var current = merged[payload.key] {
                current.occurrences += payload.occurrences
                merged[payload.key] = current
            } else {
                merged[payload.key] = payload
            }
        }
        return Array(merged.values)
    }

    private static func verifyCachedTail(_ cached: CachedAgentFile, in url: URL) -> Bool {
        guard cached.tailByteCount > 0,
              cached.size >= Int64(cached.tailByteCount),
              !cached.tailDigest.isEmpty,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(cached.size - Int64(cached.tailByteCount)))
            guard let data = try handle.read(upToCount: cached.tailByteCount),
                  data.count == cached.tailByteCount else { return false }
            return Data(SHA256.hash(data: data)).base64EncodedString() == cached.tailDigest
        } catch {
            return false
        }
    }

    private static func isBase64Byte(_ byte: UInt8) -> Bool {
        (byte >= 65 && byte <= 90)
            || (byte >= 97 && byte <= 122)
            || (byte >= 48 && byte <= 57)
            || byte == 43
            || byte == 47
            || byte == 61
    }

    private static func fileIdentity(at url: URL) -> (
        size: Int64,
        modifiedAt: TimeInterval,
        deviceID: UInt64,
        inode: UInt64
    )? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let deviceID = (attrs[.systemNumber] as? NSNumber)?.uint64Value ?? 0
        let inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        return (size, modifiedAt, deviceID, inode)
    }

    private static func loadCache(from url: URL) -> FingerprintCache {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size >= 0,
              size <= maximumCacheBytes,
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe]),
              let cache = try? JSONDecoder().decode(FingerprintCache.self, from: data),
              cache.version == cacheVersion else {
            return FingerprintCache(version: cacheVersion, files: [:])
        }
        return cache
    }

    private static func trimAndSave(
        _ cache: inout FingerprintCache,
        to url: URL,
        now: Date,
        cacheChanged: Bool
    ) {
        var needsSave = cacheChanged
        let cutoff = now.addingTimeInterval(-90 * 24 * 60 * 60).timeIntervalSince1970
        let originalCount = cache.files.count
        cache.files = cache.files.filter { $0.value.lastAccessedAt >= cutoff }
        if cache.files.count != originalCount { needsSave = true }
        if cache.files.count > 5_000 {
            let keep = cache.files
                .sorted { $0.value.lastAccessedAt > $1.value.lastAccessedAt }
                .prefix(5_000)
            cache.files = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
            needsSave = true
        }
        cache.version = cacheVersion
        guard needsSave else { return }
        let encoder = JSONEncoder()
        guard var data = try? encoder.encode(cache) else { return }
        if data.count > maximumCacheBytes {
            let orderedPaths = cache.files.sorted { lhs, rhs in
                if lhs.value.lastAccessedAt != rhs.value.lastAccessedAt {
                    return lhs.value.lastAccessedAt > rhs.value.lastAccessedAt
                }
                if lhs.value.size != rhs.value.size { return lhs.value.size > rhs.value.size }
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

    // MARK: - Build history

    private static func scanXcodeBuildHistory(
        home: URL,
        authorizedRoots: Set<String>?,
        isSandboxed: Bool
    ) -> [BuildRecord] {
        let developer = home.appendingPathComponent("Library/Developer/Xcode", isDirectory: true)
        var records: [BuildRecord] = []
        let archives = developer.appendingPathComponent("Archives", isDirectory: true)
        if isAllowed(archives, authorizedRoots: authorizedRoots, isSandboxed: isSandboxed) {
            records.append(contentsOf: collectPackages(
                under: archives,
                pathExtension: "xcarchive",
                kind: .xcodeArchive
            ))
        }

        let derivedData = developer.appendingPathComponent("DerivedData", isDirectory: true)
        if isAllowed(derivedData, authorizedRoots: authorizedRoots, isSandboxed: isSandboxed),
           let projects = try? FileManager.default.contentsOfDirectory(
                at: derivedData,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) {
            for project in projects {
                let projectValues = try? project.resourceValues(forKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey
                ])
                guard projectValues?.isDirectory == true,
                      projectValues?.isSymbolicLink != true else { continue }
                let projectFamily = normalizedDerivedDataName(project.lastPathComponent)
                let modified = projectValues?.contentModificationDate
                    ?? modificationDate(of: project)
                    ?? .distantPast
                records.append(BuildRecord(
                    kind: .xcodeDerivedData,
                    url: project,
                    groupKey: "derived:\(projectFamily)",
                    modifiedDate: modified
                ))

                let logs = project.appendingPathComponent("Logs", isDirectory: true)
                guard let enumerator = FileManager.default.enumerator(
                    at: logs,
                    includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                ) else { continue }
                var visited = 0
                for case let url as URL in enumerator {
                    visited += 1
                    if visited > 10_000 { break }
                    autoreleasepool {
                        let values = try? url.resourceValues(forKeys: [
                            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                            .contentModificationDateKey
                        ])
                        if values?.isSymbolicLink == true {
                            enumerator.skipDescendants()
                            return
                        }
                        let ext = url.pathExtension.lowercased()
                        let date = values?.contentModificationDate
                            ?? modificationDate(of: url)
                            ?? .distantPast
                        if ext == "xcresult" {
                            records.append(BuildRecord(
                                kind: .xcodeResult,
                                url: url,
                                groupKey: "xcresult:\(projectFamily)",
                                modifiedDate: date
                            ))
                            enumerator.skipDescendants()
                        } else if ext == "xcactivitylog", values?.isRegularFile == true {
                            records.append(BuildRecord(
                                kind: .xcodeBuildLog,
                                url: url,
                                groupKey: "activity:\(projectFamily):\(url.deletingLastPathComponent().lastPathComponent.lowercased())",
                                modifiedDate: date
                            ))
                        }
                    }
                }
            }
        }
        return records
    }

    private static func collectPackages(
        under root: URL,
        pathExtension: String,
        kind: BuildRecord.Kind
    ) -> [BuildRecord] {
        guard FileManager.default.fileExists(atPath: root.path),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        var records: [BuildRecord] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 25_000 { break }
            autoreleasepool {
                let values = try? url.resourceValues(forKeys: [
                    .isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey
                ])
                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    return
                }
                guard url.pathExtension.lowercased() == pathExtension else { return }
                let group = xcodeArchiveFamily(at: url)
                records.append(BuildRecord(
                    kind: kind,
                    url: url,
                    groupKey: "archive:\(group)",
                    modifiedDate: values?.contentModificationDate
                        ?? modificationDate(of: url)
                        ?? .distantPast
                ))
                enumerator.skipDescendants()
            }
        }
        return records
    }

    private static func xcodeArchiveFamily(at url: URL) -> String {
        let infoURL = url.appendingPathComponent("Info.plist")
        if let data = try? Data(contentsOf: infoURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let properties = plist["ApplicationProperties"] as? [String: Any],
           let bundleID = properties["CFBundleIdentifier"] as? String,
           !bundleID.isEmpty {
            return bundleID.lowercased()
        }
        let stem = url.deletingPathExtension().lastPathComponent
        return stem
            .replacingOccurrences(
                of: #"\s+\d{1,4}[-./]\d{1,2}[-./]\d{1,4}.*$"#,
                with: "",
                options: .regularExpression
            )
            .lowercased()
    }

    private static func normalizedDerivedDataName(_ value: String) -> String {
        value.replacingOccurrences(
            of: #"-[a-z]{20,}$"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        ).lowercased()
    }

    private static func buildCleanupItems(
        from records: [BuildRecord],
        retaining retainCount: Int,
        now: Date
    ) -> BuildScanResult {
        let groups = Dictionary(grouping: records) { $0.groupKey }
        var items: [StorageCleanupItem] = []
        var retainedCount = 0
        var seen = Set<String>()

        for (_, group) in groups {
            let sorted = group.sorted { $0.modifiedDate > $1.modifiedDate }
            retainedCount += min(retainCount, sorted.count)
            for record in sorted.dropFirst(retainCount) {
                guard now.timeIntervalSince(record.modifiedDate) >= recentlyModifiedProtection else {
                    retainedCount += 1
                    continue
                }
                let path = record.url.standardizedFileURL.path
                guard seen.insert(path).inserted,
                      FileManager.default.fileExists(atPath: path) else { continue }
                let size = allocatedSizeAndCount(of: record.url)
                guard size.bytes > 0 else { continue }
                let detail: String
                switch record.kind {
                case .xcodeArchive:
                    detail = "Xcode archive; the newest \(retainCount) archives for this app are protected."
                case .xcodeResult:
                    detail = "Xcode test result; the newest \(retainCount) results for this project are protected."
                case .xcodeBuildLog:
                    detail = "Xcode build activity log; the newest \(retainCount) logs for this project are protected."
                case .xcodeDerivedData:
                    detail = "Older Xcode DerivedData generation; the newest \(retainCount) project generations are protected."
                case .versionedOutput:
                    detail = "Older versioned build output; the newest \(retainCount) versions in this output folder are protected."
                }
                items.append(StorageCleanupItem(
                    kind: .historicalBuild,
                    name: record.url.lastPathComponent,
                    path: path,
                    size: size.bytes,
                    fileCount: size.files,
                    isDirectory: size.isDirectory,
                    modifiedDate: record.modifiedDate,
                    detail: detail
                ))
            }
        }
        let parentDirectories = items
            .filter(\.isDirectory)
            .map(\.path)
            .sorted { $0.count < $1.count }
        let nonOverlapping = items.filter { item in
            !parentDirectories.contains { parent in
                parent != item.path && item.path.hasPrefix(parent + "/")
            }
        }
        return BuildScanResult(items: nonOverlapping, retainedCount: retainedCount)
    }

    // MARK: - Installer and versioned output discovery

    private static func discoverArtifacts(
        home: URL,
        authorizedRoots: Set<String>?,
        isSandboxed: Bool
    ) -> ArtifactDiscovery {
        let roots: [URL]
        if isSandboxed {
            roots = nonOverlappingRoots((authorizedRoots ?? []).map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }, home: home)
        } else {
            roots = ["Downloads", "Desktop", "Documents"].map {
                home.appendingPathComponent($0, isDirectory: true)
            }
        }

        var result = ArtifactDiscovery()
        var seen = Set<String>()
        var visited = 0
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                    .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles]
            ) else { continue }
            let rootDepth = root.standardizedFileURL.pathComponents.count

            for case let url as URL in enumerator {
                visited += 1
                if visited > maxArtifactEntries { break }
                autoreleasepool {
                    let depth = url.pathComponents.count - rootDepth
                    if depth > 10 {
                        enumerator.skipDescendants()
                        return
                    }
                    let values = try? url.resourceValues(forKeys: [
                        .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
                        .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
                        .contentModificationDateKey
                    ])
                    if values?.isSymbolicLink == true {
                        enumerator.skipDescendants()
                        return
                    }

                    if values?.isDirectory == true {
                        let lower = url.lastPathComponent.lowercased()
                        if shouldSkipArtifactDirectory(lower) || isOpaquePackage(url) {
                            enumerator.skipDescendants()
                            return
                        }
                        let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
                        if versionContainerNames.contains(parent), isVersionedOutputName(lower) {
                            result.versionedBuilds.append(BuildRecord(
                                kind: .versionedOutput,
                                url: url,
                                groupKey: "versioned:\(url.deletingLastPathComponent().standardizedFileURL.path)",
                                modifiedDate: values?.contentModificationDate
                                    ?? modificationDate(of: url)
                                    ?? .distantPast
                            ))
                        }
                        return
                    }

                    guard values?.isRegularFile == true, isInstallerArtifact(url) else { return }
                    let path = url.standardizedFileURL.path
                    guard seen.insert(path).inserted else { return }
                    let bytes = allocatedFileSize(values)
                    guard bytes >= minimumInstallerSize else { return }
                    result.installers.append(StorageCleanupItem(
                        kind: .installerArtifact,
                        name: url.lastPathComponent,
                        path: path,
                        size: bytes,
                        fileCount: 1,
                        isDirectory: false,
                        modifiedDate: values?.contentModificationDate,
                        detail: "Installable or distributable build output. Remove only after confirming it is uploaded, backed up, or reproducible."
                    ))
                }
            }
            if visited > maxArtifactEntries { break }
        }
        return result
    }

    private static let versionContainerNames: Set<String> = [
        "builds", "releases", "artifacts", "outputs", "packages"
    ]

    private static let installerExtensions: Set<String> = [
        "dmg", "pkg", "xip", "iso", "ipa", "apk", "aab", "exe", "msi",
        "msix", "appx", "appxbundle", "deb", "rpm", "snap"
    ]

    private static func isInstallerArtifact(_ url: URL) -> Bool {
        installerExtensions.contains(url.pathExtension.lowercased())
    }

    private static func isVersionedOutputName(_ value: String) -> Bool {
        value.range(
            of: #"^v?\d+(?:\.\d+){1,4}(?:[-_ ].*)?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil || value.range(
            of: #"^\d{4}[-_.]\d{1,2}[-_.]\d{1,2}(?:[-_ ].*)?$"#,
            options: .regularExpression
        ) != nil || value.range(
            of: #"^build[-_ ]?\d+(?:[-_ ].*)?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func shouldSkipArtifactDirectory(_ value: String) -> Bool {
        [
            ".git", ".svn", ".hg", ".trash", "node_modules", "pods",
            ".gradle", ".swiftpm", ".cache", ".codex", ".claude", ".grok",
            "library", "applications", "pictures", "photos library.photoslibrary",
            "movies", "music"
        ].contains(value)
    }

    private static func isOpaquePackage(_ url: URL) -> Bool {
        ["app", "framework", "bundle", "xcarchive", "xcresult", "photoslibrary"]
            .contains(url.pathExtension.lowercased())
    }

    // MARK: - Shared filesystem helpers

    private static func isAllowed(
        _ url: URL,
        authorizedRoots: Set<String>?,
        isSandboxed: Bool
    ) -> Bool {
        guard isSandboxed else { return true }
        let path = url.standardizedFileURL.path
        return (authorizedRoots ?? []).contains { root in
            path == root || path.hasPrefix(root + "/")
        }
    }

    private static func nonOverlappingRoots(_ candidates: [URL], home: URL) -> [URL] {
        let existing = candidates
            .map(\.standardizedFileURL)
            .filter {
                FileManager.default.fileExists(atPath: $0.path)
                    && !AgentDataProtection.containsProtectedData(
                        path: $0.path,
                        homeDirectory: home.path
                    )
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

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ??
            ((try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date)
    }

    private static func allocatedFileSize(_ values: URLResourceValues?) -> Int64 {
        if let size = values?.totalFileAllocatedSize { return Int64(size) }
        if let size = values?.fileAllocatedSize { return Int64(size) }
        return Int64(values?.fileSize ?? 0)
    }

    private static func allocatedSizeAndCount(
        of url: URL
    ) -> (bytes: Int64, files: Int, isDirectory: Bool) {
        let rootValues = try? url.resourceValues(forKeys: [
            .isRegularFileKey, .isDirectoryKey,
            .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
        ])
        if rootValues?.isRegularFile == true {
            return (allocatedFileSize(rootValues), 1, false)
        }
        guard rootValues?.isDirectory == true,
              let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey,
                    .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
                ],
                options: []
              ) else { return (0, 0, false) }
        var bytes: Int64 = 0
        var files = 0
        var visited = 0
        for case let child as URL in enumerator {
            visited += 1
            if visited > 100_000 { break }
            autoreleasepool {
                let values = try? child.resourceValues(forKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey,
                    .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
                ])
                if values?.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    return
                }
                guard values?.isRegularFile == true else { return }
                bytes += allocatedFileSize(values)
                files += 1
            }
        }
        return (bytes, files, true)
    }
}
