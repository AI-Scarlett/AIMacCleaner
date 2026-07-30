import CryptoKit
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

/// A local-only scanner for Agent session payloads and historical build output.
///
/// Agent files are never rewritten or returned as deletion candidates. The cache
/// stores only paths, file identity, sizes, and content digests; it never stores
/// conversation prose or media bytes.
enum StorageOptimizationCore {
    private static let cacheVersion = 3
    private static let minimumInstallerSize: Int64 = 1 * 1024 * 1024
    private static let recentlyModifiedProtection: TimeInterval = 30 * 60
    private static let maxAgentFiles = 20_000
    private static let maxArtifactEntries = 100_000
    private static let maxCleanupItems = 800

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

        for root in roots where FileManager.default.fileExists(atPath: root.url.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root.url,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in enumerator {
                visited += 1
                if visited > maxAgentFiles { break }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
                let ext = url.pathExtension.lowercased()
                guard ext == "jsonl" || ext == "ndjson" else { continue }

                let path = url.standardizedFileURL.path
                guard discoveredPaths.insert(path).inserted,
                      let identity = fileIdentity(at: url) else { continue }

                let payloads: [PayloadFingerprint]
                if var cached = cache.files[path],
                   cached.deviceID == identity.deviceID,
                   cached.inode == identity.inode,
                   cached.size == identity.size,
                   abs(cached.modifiedAt - identity.modifiedAt) < 0.001 {
                    payloads = cached.payloads
                    cached.lastAccessedAt = now.timeIntervalSince1970
                    cache.files[path] = cached
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
            if visited > maxAgentFiles { break }
        }

        trimAndSave(&cache, to: cacheURL, now: now)

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
            ("Claude", ".claude/projects"),
            ("Grok", ".grok/sessions"),
            ("Grok", ".grok/projects"),
            ("Gemini", ".gemini/tmp"),
            ("Gemini", ".gemini/history"),
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
            agentName: "Trae",
            url: support.appendingPathComponent("Trae/User/workspaceStorage", isDirectory: true)
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
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !data.isEmpty else {
            return EmbeddedPayloadScan(
                payloads: [],
                endedWithNewline: false,
                processedBytes: 0,
                tailDigest: "",
                tailByteCount: 0
            )
        }

        let payloads = data.withUnsafeBytes { rawBuffer -> [PayloadFingerprint] in
            guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return [] }
            let count = rawBuffer.count
            var index = max(0, min(Int(requestedOffset), count))
            var records: [String: PayloadFingerprint] = [:]

            while index + 12 < count {
                guard matchesASCII("data:", at: index, bytes: base, count: count) else {
                    index += 1
                    continue
                }

                let typeStart = index + 5
                let kind: EmbeddedMediaKind
                if matchesASCII("image/", at: typeStart, bytes: base, count: count) {
                    kind = .image
                } else if matchesASCII("audio/", at: typeStart, bytes: base, count: count) {
                    kind = .audio
                } else if matchesASCII("video/", at: typeStart, bytes: base, count: count) {
                    kind = .video
                } else if matchesASCII("application/", at: typeStart, bytes: base, count: count) {
                    kind = .attachment
                } else {
                    index += 5
                    continue
                }

                guard let marker = findASCII(
                    ";base64,",
                    from: typeStart,
                    through: min(typeStart + 160, count),
                    bytes: base,
                    count: count
                ) else {
                    index += 5
                    continue
                }

                let payloadStart = marker + 8
                var payloadEnd = payloadStart
                while payloadEnd < count, isBase64Byte(base[payloadEnd]) {
                    payloadEnd += 1
                }
                let length = payloadEnd - payloadStart
                guard length >= 16 else {
                    index = max(payloadEnd, index + 5)
                    continue
                }

                let payload = Data(
                    bytesNoCopy: UnsafeMutableRawPointer(mutating: base.advanced(by: payloadStart)),
                    count: length,
                    deallocator: .none
                )
                let digest = Data(SHA256.hash(data: payload)).base64EncodedString()
                let key = "\(kind.rawValue):\(digest)"
                if var existing = records[key] {
                    existing.occurrences += 1
                    records[key] = existing
                } else {
                    records[key] = PayloadFingerprint(
                        digest: digest,
                        kind: kind,
                        encodedBytes: Int64(length),
                        occurrences: 1
                    )
                }
                index = payloadEnd
            }
            return Array(records.values)
        }
        let tailByteCount = min(data.count, 4_096)
        let tail = data.suffix(tailByteCount)
        let tailDigest = Data(SHA256.hash(data: tail)).base64EncodedString()
        return EmbeddedPayloadScan(
            payloads: payloads,
            endedWithNewline: data.last == 10,
            processedBytes: Int64(data.count),
            tailDigest: tailDigest,
            tailByteCount: tailByteCount
        )
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

    private static func matchesASCII(
        _ value: StaticString,
        at index: Int,
        bytes: UnsafePointer<UInt8>,
        count: Int
    ) -> Bool {
        let length = value.utf8CodeUnitCount
        guard index >= 0, index + length <= count else { return false }
        return value.withUTF8Buffer { expected in
            for offset in 0..<expected.count where bytes[index + offset] != expected[offset] {
                return false
            }
            return true
        }
    }

    private static func findASCII(
        _ value: StaticString,
        from start: Int,
        through end: Int,
        bytes: UnsafePointer<UInt8>,
        count: Int
    ) -> Int? {
        guard start < end else { return nil }
        var index = start
        while index < end {
            if matchesASCII(value, at: index, bytes: bytes, count: count) { return index }
            index += 1
        }
        return nil
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
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(FingerprintCache.self, from: data),
              cache.version == cacheVersion else {
            return FingerprintCache(version: cacheVersion, files: [:])
        }
        return cache
    }

    private static func trimAndSave(_ cache: inout FingerprintCache, to url: URL, now: Date) {
        let cutoff = now.addingTimeInterval(-90 * 24 * 60 * 60).timeIntervalSince1970
        cache.files = cache.files.filter { path, entry in
            entry.lastAccessedAt >= cutoff && FileManager.default.fileExists(atPath: path)
        }
        if cache.files.count > 5_000 {
            let keep = cache.files
                .sorted { $0.value.lastAccessedAt > $1.value.lastAccessedAt }
                .prefix(5_000)
            cache.files = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        cache.version = cacheVersion
        guard let data = try? JSONEncoder().encode(cache) else { return }
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
                guard isDirectory(project), !isSymbolicLink(project) else { continue }
                let projectFamily = normalizedDerivedDataName(project.lastPathComponent)
                let modified = modificationDate(of: project) ?? .distantPast
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
                    if isSymbolicLink(url) {
                        enumerator.skipDescendants()
                        continue
                    }
                    let ext = url.pathExtension.lowercased()
                    let date = modificationDate(of: url) ?? .distantPast
                    if ext == "xcresult" {
                        records.append(BuildRecord(
                            kind: .xcodeResult,
                            url: url,
                            groupKey: "xcresult:\(projectFamily)",
                            modifiedDate: date
                        ))
                        enumerator.skipDescendants()
                    } else if ext == "xcactivitylog", isRegularFile(url) {
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
            if isSymbolicLink(url) {
                enumerator.skipDescendants()
                continue
            }
            guard url.pathExtension.lowercased() == pathExtension else { continue }
            let group = xcodeArchiveFamily(at: url)
            records.append(BuildRecord(
                kind: kind,
                url: url,
                groupKey: "archive:\(group)",
                modifiedDate: modificationDate(of: url) ?? .distantPast
            ))
            enumerator.skipDescendants()
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
                    isDirectory: isDirectory(record.url),
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
            roots = (authorizedRoots ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
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
                let depth = url.pathComponents.count - rootDepth
                if depth > 10 {
                    enumerator.skipDescendants()
                    continue
                }
                if isSymbolicLink(url) {
                    enumerator.skipDescendants()
                    continue
                }

                if isDirectory(url) {
                    let lower = url.lastPathComponent.lowercased()
                    if shouldSkipArtifactDirectory(lower) || isOpaquePackage(url) {
                        enumerator.skipDescendants()
                        continue
                    }
                    let parent = url.deletingLastPathComponent().lastPathComponent.lowercased()
                    if versionContainerNames.contains(parent), isVersionedOutputName(lower) {
                        result.versionedBuilds.append(BuildRecord(
                            kind: .versionedOutput,
                            url: url,
                            groupKey: "versioned:\(url.deletingLastPathComponent().standardizedFileURL.path)",
                            modifiedDate: modificationDate(of: url) ?? .distantPast
                        ))
                    }
                    continue
                }

                guard isRegularFile(url), isInstallerArtifact(url) else { continue }
                let path = url.standardizedFileURL.path
                guard seen.insert(path).inserted else { continue }
                let values = try? url.resourceValues(forKeys: [
                    .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey,
                    .contentModificationDateKey
                ])
                let bytes = allocatedFileSize(values)
                guard bytes >= minimumInstallerSize else { continue }
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
            if visited > maxArtifactEntries { break }
        }
        return result
    }

    private static let versionContainerNames: Set<String> = [
        "builds", "releases", "artifacts", "outputs", "packages"
    ]

    private static let installerExtensions: Set<String> = [
        "dmg", "pkg", "ipa", "apk", "aab", "exe", "msi", "msix",
        "appx", "appxbundle", "deb", "rpm", "snap"
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

    private static func allocatedSizeAndCount(of url: URL) -> (bytes: Int64, files: Int) {
        if isRegularFile(url) {
            let values = try? url.resourceValues(forKeys: [
                .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
            ])
            return (allocatedFileSize(values), 1)
        }
        guard isDirectory(url),
              let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [
                    .isRegularFileKey, .isSymbolicLinkKey,
                    .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
                ],
                options: []
              ) else { return (0, 0) }
        var bytes: Int64 = 0
        var files = 0
        for case let child as URL in enumerator {
            if isSymbolicLink(child) {
                enumerator.skipDescendants()
                continue
            }
            guard isRegularFile(child) else { continue }
            let values = try? child.resourceValues(forKeys: [
                .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey
            ])
            bytes += allocatedFileSize(values)
            files += 1
        }
        return (bytes, files)
    }
}
