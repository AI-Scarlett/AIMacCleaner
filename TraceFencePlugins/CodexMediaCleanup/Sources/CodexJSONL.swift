import Darwin
import Foundation

enum CodexJSONL {
    /// A single Codex JSONL record can legitimately contain several inline
    /// images. Above this bound Foundation's tree decoder can multiply the
    /// allocation into hundreds of megabytes. The file is left untouched and
    /// reported instead of risking memory-pressure termination.
    static let maximumRecordBytes = 64 * 1_024 * 1_024
    private static let allocatorReliefInterval = 32 * 1_024 * 1_024
    private static let compactedMarker = Data("\"compacted\"".utf8)

    struct Layout: Equatable, Sendable {
        let lastCompactionLine: Int?
        let lineCount: Int
    }

    static func layout(of url: URL) throws -> Layout {
        var lastCompactionLine: Int?
        var lineCount = 0
        try forEachLine(at: url) { lineNumber, data in
            lineCount = lineNumber
            guard data.range(of: compactedMarker) != nil else { return }
            let record = try decodeRecord(data, path: url.path, line: lineNumber)
            if record["type"] as? String == "compacted" {
                lastCompactionLine = lineNumber
            }
        }
        return Layout(lastCompactionLine: lastCompactionLine, lineCount: lineCount)
    }

    static func forEachLine(
        at url: URL,
        _ body: (_ lineNumber: Int, _ data: Data) throws -> Void
    ) throws {
        guard let file = fopen(url.path, "rb") else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { fclose(file) }

        var buffer: UnsafeMutablePointer<CChar>?
        var capacity = 0
        defer { free(buffer) }

        var lineNumber = 0
        var bytesSinceAllocatorRelief = 0
        while true {
            let count = getline(&buffer, &capacity, file)
            if count < 0 { break }
            guard let buffer else { throw POSIXError(.EIO) }
            lineNumber += 1
            try validateRecordByteCount(count, path: url.path, line: lineNumber)
            try autoreleasepool {
                try body(lineNumber, Data(bytes: buffer, count: count))
            }
            bytesSinceAllocatorRelief += count
            if bytesSinceAllocatorRelief >= allocatorReliefInterval {
                _ = malloc_zone_pressure_relief(nil, 0)
                bytesSinceAllocatorRelief = 0
            }
        }
        _ = malloc_zone_pressure_relief(nil, 0)
        if ferror(file) != 0 {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    static func validateRecordByteCount(_ count: Int, path: String, line: Int) throws {
        guard count <= maximumRecordBytes else {
            throw CodexMediaCleanupError.recordTooLarge(
                path: path,
                line: line,
                bytes: count,
                limit: maximumRecordBytes
            )
        }
    }

    static func decodeRecord(_ data: Data, path: String, line: Int) throws -> [String: Any] {
        do {
            guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CodexMediaCleanupError.malformedJSON(path: path, line: line)
            }
            return value
        } catch let error as CodexMediaCleanupError {
            throw error
        } catch {
            throw CodexMediaCleanupError.malformedJSON(path: path, line: line)
        }
    }

    static func encodeRecord(_ record: [String: Any]) throws -> Data {
        var data = try JSONSerialization.data(withJSONObject: record, options: [.withoutEscapingSlashes])
        data.append(0x0A)
        return data
    }

    static func effectiveRoot(
        in record: [String: Any],
        lineNumber: Int,
        layout: Layout
    ) -> Any? {
        let type = record["type"] as? String
        if lineNumber == layout.lastCompactionLine,
           type == "compacted",
           let payload = record["payload"] as? [String: Any] {
            return payload["replacement_history"]
        }
        if type == "response_item",
           layout.lastCompactionLine == nil || lineNumber > layout.lastCompactionLine!,
           let payload = record["payload"] {
            return payload
        }
        return nil
    }
}

enum CodexSessionDiscovery {
    static func sessionFiles(configuration: CodexMediaCleanupConfiguration) throws -> [URL] {
        let fileManager = FileManager.default
        var files: [URL] = []
        for root in configuration.sessionRoots where fileManager.fileExists(atPath: root.path) {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator {
                if files.count >= 10_000 { break }
                guard url.pathExtension.lowercased() == "jsonl" else { continue }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
                files.append(url.standardizedFileURL)
            }
        }
        return files.sorted { $0.path < $1.path }
    }
}
