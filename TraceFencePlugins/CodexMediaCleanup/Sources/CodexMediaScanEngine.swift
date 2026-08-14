import Foundation

struct CodexMediaScanEngine: Sendable {
    private struct FileStats {
        var inlineOccurrences = 0
        var reclaimableOccurrences = 0
        var retainedEffectiveOccurrences = 0
        var invalidEffectiveFileURLs = 0
        var missingMediaObjects = 0
        var estimatedReclaimableBytes: Int64 = 0
        var hashes = Set<String>()

        var isAffected: Bool {
            reclaimableOccurrences > 0 || invalidEffectiveFileURLs > 0 || missingMediaObjects > 0
        }
    }

    func scan(
        configuration: CodexMediaCleanupConfiguration,
        progress: @Sendable (CodexMediaProgress) -> Void = { _ in }
    ) throws -> CodexMediaScanReport {
        let home = configuration.codexHome.standardizedFileURL
        guard FileManager.default.fileExists(atPath: home.path) else {
            throw CodexMediaCleanupError.invalidCodexHome(home.path)
        }

        let files = try CodexSessionDiscovery.sessionFiles(configuration: configuration)
        var report = CodexMediaScanReport()
        var globalHashes = Set<String>()
        for (index, file) in files.enumerated() {
            if Task.isCancelled { throw CodexMediaCleanupError.cancelled }
            progress(.init(completed: index, total: files.count, currentPath: file.path))
            report.scannedFiles += 1
            report.scannedBytes += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)

            do {
                let stats = try inspect(file: file, mediaRoot: configuration.mediaRoot)
                if stats.isAffected { report.affectedFiles += 1 }
                report.inlineImageOccurrences += stats.inlineOccurrences
                report.reclaimableOccurrences += stats.reclaimableOccurrences
                report.retainedEffectiveOccurrences += stats.retainedEffectiveOccurrences
                report.invalidEffectiveFileURLs += stats.invalidEffectiveFileURLs
                report.missingMediaObjects += stats.missingMediaObjects
                report.estimatedReclaimableBytes += stats.estimatedReclaimableBytes
                globalHashes.formUnion(stats.hashes)
            } catch {
                report.malformedFiles += 1
            }
        }
        report.uniqueImageCount = globalHashes.count
        report.completedAt = Date()
        progress(.init(completed: files.count, total: files.count, currentPath: ""))
        return report
    }

    private func inspect(file: URL, mediaRoot: URL) throws -> FileStats {
        let layout = try CodexJSONL.layout(of: file)
        var stats = FileStats()
        try CodexJSONL.forEachLine(at: file) { lineNumber, data in
            let record = try CodexJSONL.decodeRecord(data, path: file.path, line: lineNumber)
            if let effectiveRoot = CodexJSONL.effectiveRoot(
                in: record,
                lineNumber: lineNumber,
                layout: layout
            ) {
                try inspectValue(effectiveRoot, isEffective: true, mediaRoot: mediaRoot, stats: &stats)
                try inspectStaleParts(
                    record,
                    excluding: effectiveRoot,
                    lineNumber: lineNumber,
                    layout: layout,
                    mediaRoot: mediaRoot,
                    stats: &stats
                )
            } else {
                try inspectValue(record, isEffective: false, mediaRoot: mediaRoot, stats: &stats)
            }
        }
        return stats
    }

    private func inspectStaleParts(
        _ record: [String: Any],
        excluding effectiveRoot: Any,
        lineNumber: Int,
        layout: CodexJSONL.Layout,
        mediaRoot: URL,
        stats: inout FileStats
    ) throws {
        let type = record["type"] as? String
        if lineNumber == layout.lastCompactionLine, type == "compacted" {
            var stale = record
            if var payload = stale["payload"] as? [String: Any] {
                payload.removeValue(forKey: "replacement_history")
                stale["payload"] = payload
            }
            try inspectValue(stale, isEffective: false, mediaRoot: mediaRoot, stats: &stats)
        } else if type == "response_item" {
            var stale = record
            stale.removeValue(forKey: "payload")
            try inspectValue(stale, isEffective: false, mediaRoot: mediaRoot, stats: &stats)
        }
    }

    private func inspectValue(
        _ value: Any,
        isEffective: Bool,
        mediaRoot: URL,
        stats: inout FileStats
    ) throws {
        if let string = value as? String {
            if let image = try CodexDataImage.parse(string) {
                stats.inlineOccurrences += 1
                stats.hashes.insert(image.sha256)
                if isEffective {
                    stats.retainedEffectiveOccurrences += 1
                } else {
                    stats.reclaimableOccurrences += 1
                    let referenceLength = CodexMediaObjectStore
                        .canonicalURL(for: image, mediaRoot: mediaRoot)
                        .absoluteString.utf8.count
                    stats.estimatedReclaimableBytes += Int64(max(0, image.originalCharacterCount - referenceLength))
                }
            }
            return
        }
        if let array = value as? [Any] {
            for item in array {
                try inspectValue(item, isEffective: isEffective, mediaRoot: mediaRoot, stats: &stats)
            }
            return
        }
        guard let dictionary = value as? [String: Any] else { return }

        if isEffective,
           dictionary["type"] as? String == "input_image",
           let imageURL = dictionary["image_url"] as? String,
           imageURL.hasPrefix("file://") {
            stats.invalidEffectiveFileURLs += 1
            do {
                guard let url = URL(string: imageURL) else {
                    throw CodexMediaCleanupError.unsafeMediaReference(imageURL)
                }
                let image = try CodexDataImage.fromCanonicalFile(url, mediaRoot: mediaRoot)
                stats.hashes.insert(image.sha256)
            } catch {
                stats.missingMediaObjects += 1
            }
        }
        for item in dictionary.values {
            try inspectValue(item, isEffective: isEffective, mediaRoot: mediaRoot, stats: &stats)
        }
    }
}
