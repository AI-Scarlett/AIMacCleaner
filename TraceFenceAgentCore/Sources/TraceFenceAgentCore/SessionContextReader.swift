import Foundation

struct SessionContextPage {
    let messages: [[String: Any]]
    let totalCount: Int
    let nextCursor: String?
    let hasMore: Bool
    let truncated: Bool
}

final class SessionContextReader {
    enum ReaderError: LocalizedError {
        case unavailable
        case disallowedPath
        case unreadable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "This Agent session does not expose a local context transcript."
            case .disallowedPath:
                return "The session transcript is outside TraceFence's trusted Agent directories."
            case .unreadable:
                return "The session transcript could not be read."
            }
        }
    }

    private struct MessageRecord {
        var id: String
        var role: String
        var kind: String
        var text: String
        var timestamp: String?
        var toolName: String?
        var status: String?
        var turnId: String?

        var payload: [String: Any] {
            var value: [String: Any] = [
                "id": id,
                "role": role,
                "kind": kind,
                "text": text
            ]
            if let timestamp, !timestamp.isEmpty { value["timestamp"] = timestamp }
            if let toolName, !toolName.isEmpty { value["toolName"] = toolName }
            if let status, !status.isEmpty { value["status"] = status }
            if let turnId, !turnId.isEmpty { value["turnId"] = turnId }
            return value
        }
    }

    private struct CacheEntry {
        var fileSize: Int
        var modifiedAt: TimeInterval
        var messages: [MessageRecord]
        var truncated: Bool
        var lastAccessedAt: Date
    }

    private let lock = NSLock()
    private var cache: [String: CacheEntry] = [:]
    private let maxCachedFiles = 8
    private let maxRetainedMessages = 5_000
    private let retainedMessageTrimBatch = 500
    private let maxLineBytes = 4 * 1_024 * 1_024
    private let readChunkBytes = 128 * 1_024

    func contextAvailable(sourcePath: String) -> Bool {
        securedTranscriptURL(sourcePath) != nil
    }

    func page(
        sourcePath: String,
        adapterId: String,
        cursor: String?,
        requestedLimit: Int,
        requestedTurnLimit: Int? = nil
    ) throws -> SessionContextPage {
        guard !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReaderError.unavailable
        }
        guard let url = securedTranscriptURL(sourcePath) else {
            throw ReaderError.disallowedPath
        }
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              let modifiedAt = values.contentModificationDate else {
            throw ReaderError.unreadable
        }

        let cacheKey = url.path
        let records: [MessageRecord]
        let wasTruncated: Bool
        lock.lock()
        if var cached = cache[cacheKey],
           cached.fileSize == fileSize,
           cached.modifiedAt == modifiedAt.timeIntervalSince1970 {
            cached.lastAccessedAt = Date()
            cache[cacheKey] = cached
            records = cached.messages
            wasTruncated = cached.truncated
            lock.unlock()
        } else {
            lock.unlock()
            let parsed = try parse(url: url, adapterId: adapterId)
            lock.lock()
            cache[cacheKey] = CacheEntry(
                fileSize: fileSize,
                modifiedAt: modifiedAt.timeIntervalSince1970,
                messages: parsed.messages,
                truncated: parsed.truncated,
                lastAccessedAt: Date()
            )
            trimCacheLocked()
            lock.unlock()
            records = parsed.messages
            wasTruncated = parsed.truncated
        }

        let limit = min(max(requestedLimit, 20), 120)
        let requestedEnd = cursor.flatMap(Int.init) ?? records.count
        let end = min(max(requestedEnd, 0), records.count)
        let start: Int
        if let requestedTurnLimit {
            start = semanticPageStart(
                records: records,
                end: end,
                turnLimit: min(max(requestedTurnLimit, 1), 10)
            )
        } else {
            start = max(0, end - limit)
        }
        let selectedRecords = requestedTurnLimit == nil
            ? Array(records[start..<end])
            : compactSemanticTurns(Array(records[start..<end]), maxRecordsPerTurn: 64)
        let messages = selectedRecords.map(\.payload)
        return SessionContextPage(
            messages: messages,
            totalCount: records.count,
            nextCursor: start > 0 ? String(start) : nil,
            hasMore: start > 0,
            truncated: wasTruncated
        )
    }

    private func parse(url: URL, adapterId: String) throws -> (messages: [MessageRecord], truncated: Bool) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { throw ReaderError.unreadable }
        defer { try? handle.close() }

        var messages: [MessageRecord] = []
        var truncated = false
        var buffer = Data()
        var lineNumber = 0

        func retain(_ newRecords: [MessageRecord]) {
            guard !newRecords.isEmpty else { return }
            messages.append(contentsOf: newRecords)
            if messages.count > maxRetainedMessages {
                let removeCount = min(
                    messages.count - maxRetainedMessages + retainedMessageTrimBatch,
                    messages.count
                )
                messages.removeFirst(removeCount)
                truncated = true
            }
        }

        do {
            while let chunk = try handle.read(upToCount: readChunkBytes), !chunk.isEmpty {
                buffer.append(chunk)
                while let newline = buffer.firstIndex(of: 0x0A) {
                    let line = Data(buffer[..<newline])
                    buffer.removeSubrange(...newline)
                    lineNumber += 1
                    if line.count <= maxLineBytes {
                        retain(parseLine(line, adapterId: adapterId, lineNumber: lineNumber))
                    } else {
                        truncated = true
                    }
                }
                if buffer.count > maxLineBytes {
                    buffer.removeAll(keepingCapacity: true)
                    truncated = true
                }
            }
        } catch {
            throw ReaderError.unreadable
        }

        if !buffer.isEmpty, buffer.count <= maxLineBytes {
            lineNumber += 1
            retain(parseLine(buffer, adapterId: adapterId, lineNumber: lineNumber))
        }
        return (assignTurnIdentifiers(messages), truncated)
    }

    private func assignTurnIdentifiers(_ records: [MessageRecord]) -> [MessageRecord] {
        var result = records
        var currentTurnId: String?
        var currentTurnHasUserMessage = false

        for index in result.indices {
            let explicitTurnId = result[index].turnId?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let explicitTurnId, !explicitTurnId.isEmpty {
                if explicitTurnId != currentTurnId {
                    currentTurnId = explicitTurnId
                    currentTurnHasUserMessage = false
                }
            } else {
                let startsTask = result[index].kind == "event" && result[index].text == "task_started"
                let startsUserTurn = result[index].role == "user" && currentTurnHasUserMessage
                if currentTurnId == nil || startsTask || startsUserTurn {
                    currentTurnId = "derived:\(result[index].id)"
                    currentTurnHasUserMessage = false
                }
                result[index].turnId = currentTurnId
            }

            if result[index].role == "user" {
                currentTurnHasUserMessage = true
            }
        }
        return result
    }

    private func semanticPageStart(
        records: [MessageRecord],
        end: Int,
        turnLimit: Int
    ) -> Int {
        guard end > 0 else { return 0 }
        var start = end
        var mostRecentTurnId: String?
        var turnCount = 0

        for index in stride(from: end - 1, through: 0, by: -1) {
            let turnId = records[index].turnId ?? "derived:\(records[index].id)"
            if turnId != mostRecentTurnId {
                guard turnCount < turnLimit else { break }
                turnCount += 1
                mostRecentTurnId = turnId
            }
            start = index
        }
        return start
    }

    private func compactSemanticTurns(_ records: [MessageRecord], maxRecordsPerTurn: Int) -> [MessageRecord] {
        guard !records.isEmpty else { return [] }
        var result: [MessageRecord] = []
        var groupStart = 0

        while groupStart < records.count {
            let turnId = records[groupStart].turnId ?? "derived:\(records[groupStart].id)"
            var groupEnd = groupStart + 1
            while groupEnd < records.count,
                  (records[groupEnd].turnId ?? "derived:\(records[groupEnd].id)") == turnId {
                groupEnd += 1
            }

            let group = Array(records[groupStart..<groupEnd])
            if group.count <= maxRecordsPerTurn {
                result.append(contentsOf: group)
            } else {
                let recordBudget = maxRecordsPerTurn - 1
                let important = group.indices.filter {
                    group[$0].role == "user" || group[$0].role == "assistant" || group[$0].kind == "event"
                }
                var selected = balancedIndices(important, limit: recordBudget)
                if selected.count < recordBudget {
                    let selectedSet = Set(selected)
                    let remaining = group.indices.filter { !selectedSet.contains($0) }
                    selected.append(contentsOf: balancedIndices(remaining, limit: recordBudget - selected.count))
                }
                selected.sort()

                let marker = MessageRecord(
                    id: "tracefence-context-compacted-\(group[0].id)",
                    role: "system",
                    kind: "event",
                    text: "context_compacted",
                    timestamp: group.last?.timestamp,
                    status: "\(group.count - selected.count)_records_omitted",
                    turnId: turnId
                )
                var insertedMarker = false
                var previousIndex: Int?
                for index in selected {
                    if !insertedMarker, let previousIndex, index - previousIndex > 1 {
                        result.append(marker)
                        insertedMarker = true
                    }
                    result.append(group[index])
                    previousIndex = index
                }
                if !insertedMarker { result.append(marker) }
            }
            groupStart = groupEnd
        }
        return result
    }

    private func balancedIndices(_ indices: [Int], limit: Int) -> [Int] {
        guard limit > 0, indices.count > limit else { return limit > 0 ? indices : [] }
        let leadingCount = limit / 3
        let trailingCount = limit - leadingCount
        return Array(indices.prefix(leadingCount)) + Array(indices.suffix(trailingCount))
    }

    private func parseLine(_ data: Data, adapterId: String, lineNumber: Int) -> [MessageRecord] {
        autoreleasepool {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
            if adapterId == "claude" || object["message"] is [String: Any] {
                return parseClaudeLine(object, lineNumber: lineNumber)
            }
            return parseCodexLine(object, lineNumber: lineNumber)
        }
    }

    private func parseCodexLine(_ object: [String: Any], lineNumber: Int) -> [MessageRecord] {
        guard let type = object["type"] as? String,
              let payload = object["payload"] as? [String: Any] else { return [] }
        let timestamp = object["timestamp"] as? String
        let turnId = payload["turn_id"] as? String ?? payload["turnId"] as? String

        if type == "response_item" {
            let itemType = payload["type"] as? String ?? "message"
            if let role = payload["role"] as? String,
               role == "user" || role == "assistant" {
                let text = limitedText(extractText(payload["content"]), limit: 24_000)
                guard !text.isEmpty else { return [] }
                return [MessageRecord(
                    id: "codex-\(lineNumber)-message",
                    role: role,
                    kind: "message",
                    text: text,
                    timestamp: timestamp,
                    turnId: turnId
                )]
            }

            if ["function_call", "custom_tool_call", "local_shell_call", "web_search_call"].contains(itemType) {
                let name = payload["name"] as? String
                    ?? payload["tool_name"] as? String
                    ?? payload["toolName"] as? String
                    ?? itemType
                let input = payload["arguments"] ?? payload["input"] ?? payload["action"] ?? [:]
                return [MessageRecord(
                    id: "codex-\(lineNumber)-tool",
                    role: "tool",
                    kind: "toolCall",
                    text: limitedText(stringify(input), limit: 8_000),
                    timestamp: timestamp,
                    toolName: name,
                    status: payload["status"] as? String,
                    turnId: turnId
                )]
            }

            if ["function_call_output", "custom_tool_call_output", "local_shell_call_output"].contains(itemType) {
                let output = payload["output"] ?? payload["content"] ?? ""
                return [MessageRecord(
                    id: "codex-\(lineNumber)-tool-result",
                    role: "tool",
                    kind: "toolResult",
                    text: limitedText(extractText(output), limit: 8_000),
                    timestamp: timestamp,
                    toolName: payload["name"] as? String,
                    status: payload["status"] as? String,
                    turnId: turnId
                )]
            }
            return []
        }

        guard type == "event_msg", let eventType = payload["type"] as? String else { return [] }
        guard ["task_started", "task_complete", "turn_aborted", "context_compacted"].contains(eventType) else {
            return []
        }
        return [MessageRecord(
            id: "codex-\(lineNumber)-event",
            role: "system",
            kind: "event",
            text: eventType,
            timestamp: timestamp,
            status: eventType,
            turnId: turnId
        )]
    }

    private func parseClaudeLine(_ object: [String: Any], lineNumber: Int) -> [MessageRecord] {
        guard let message = object["message"] as? [String: Any],
              let role = message["role"] as? String,
              role == "user" || role == "assistant" else { return [] }
        let timestamp = object["timestamp"] as? String
        let content = message["content"]
        if let text = content as? String {
            let value = limitedText(text, limit: 24_000)
            guard !value.isEmpty else { return [] }
            return [MessageRecord(
                id: "claude-\(lineNumber)-message",
                role: role,
                kind: "message",
                text: value,
                timestamp: timestamp
            )]
        }

        guard let blocks = content as? [[String: Any]] else { return [] }
        var result: [MessageRecord] = []
        var textParts: [String] = []
        var ordinal = 0

        func flushText() {
            let text = limitedText(textParts.joined(separator: "\n"), limit: 24_000)
            textParts.removeAll(keepingCapacity: true)
            guard !text.isEmpty else { return }
            ordinal += 1
            result.append(MessageRecord(
                id: "claude-\(lineNumber)-message-\(ordinal)",
                role: role,
                kind: "message",
                text: text,
                timestamp: timestamp
            ))
        }

        for block in blocks {
            let blockType = block["type"] as? String ?? "text"
            switch blockType {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty { textParts.append(text) }
            case "tool_use":
                flushText()
                ordinal += 1
                result.append(MessageRecord(
                    id: "claude-\(lineNumber)-tool-\(ordinal)",
                    role: "tool",
                    kind: "toolCall",
                    text: limitedText(stringify(block["input"] ?? [:]), limit: 8_000),
                    timestamp: timestamp,
                    toolName: block["name"] as? String
                ))
            case "tool_result":
                flushText()
                ordinal += 1
                result.append(MessageRecord(
                    id: "claude-\(lineNumber)-result-\(ordinal)",
                    role: "tool",
                    kind: "toolResult",
                    text: limitedText(extractText(block["content"]), limit: 8_000),
                    timestamp: timestamp,
                    toolName: block["name"] as? String,
                    status: (block["is_error"] as? Bool) == true ? "error" : "completed"
                ))
            default:
                break
            }
        }
        flushText()
        return result
    }

    private func extractText(_ value: Any?) -> String {
        if let text = value as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let array = value as? [Any] {
            return array.map(extractText).filter { !$0.isEmpty }.joined(separator: "\n")
        }
        if let dictionary = value as? [String: Any] {
            for key in ["text", "input_text", "output_text", "content", "output"] {
                let text = extractText(dictionary[key])
                if !text.isEmpty { return text }
            }
        }
        return ""
    }

    private func stringify(_ value: Any) -> String {
        if let text = value as? String { return text }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return String(describing: value)
        }
        return text
    }

    private func limitedText(_ value: String, limit: Int) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "\n[content truncated by TraceFence]"
    }

    private func securedTranscriptURL(_ sourcePath: String) -> URL? {
        let candidate = URL(fileURLWithPath: sourcePath)
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard candidate.pathExtension.lowercased() == "jsonl" else { return nil }

        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let roots = [
            home.appendingPathComponent(".codex/sessions", isDirectory: true),
            home.appendingPathComponent(".claude/projects", isDirectory: true)
        ].map { $0.resolvingSymlinksInPath().standardizedFileURL.path + "/" }
        let path = candidate.path
        guard roots.contains(where: { path.hasPrefix($0) }) else { return nil }
        return FileManager.default.isReadableFile(atPath: path) ? candidate : nil
    }

    private func trimCacheLocked() {
        guard cache.count > maxCachedFiles else { return }
        let retainedKeys = Set(
            cache.sorted { $0.value.lastAccessedAt > $1.value.lastAccessedAt }
                .prefix(maxCachedFiles)
                .map(\.key)
        )
        cache = cache.filter { retainedKeys.contains($0.key) }
    }
}
