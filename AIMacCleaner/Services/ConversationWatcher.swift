import Foundation

struct ConversationFile: Codable, Identifiable, Equatable {
    var id: String
    var path: String
    var agentId: String
    var agentName: String
    var projectName: String?
    var timestamp: Date
    var size: Int64
    var sessionId: String?
    var snippet: String?
}

struct ConversationDirectory: Codable, Identifiable {
    var id: String { path }
    var path: String
    var agentId: String
    var agentName: String
    var lastModified: Date
}

@MainActor
class ConversationWatcher: ObservableObject {
    @Published var discoveredConversations: [ConversationFile] = []
    @Published var watchedDirectories: [ConversationDirectory] = []
    @Published var isWatching: Bool = false

    private var monitorTask: Task<Void, Never>?
    private var externalApprovalScanTask: Task<Void, Never>?
    private var watchedPaths: Set<String> = []
    private let maxConversations = 500
    private let externalApprovalWindow: TimeInterval = 15 * 60
    private var processedExternalApprovalIds: Set<String> = []
    private var pendingExternalApprovalIds: [String: String] = [:]
    private weak var sessionStore: SessionStore?
    private let externalApprovalScanner = ExternalApprovalScanner()
    nonisolated private static let sessionIdRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "session[-_]([a-f0-9-]{20,})", options: []),
        try! NSRegularExpression(pattern: "([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})", options: [])
    ]
    nonisolated private static let scanResultLimit = 500
    nonisolated private static let scanPruneThreshold = 1_000

    func setupExternalApprovalBridge(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    func startWatching(directories: [ConversationDirectory]) {
        stopWatching()
        watchedDirectories = directories
        watchedPaths = Set(directories.map { $0.path })
        isWatching = true

        monitorTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let watcher = self,
                      let directories = await watcher.activeWatchedDirectories() else {
                    break
                }
                let found = autoreleasepool {
                    Self.scanDirectoriesSnapshot(directories)
                }
                await watcher.applyScanResult(found)
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    private func activeWatchedDirectories() -> [ConversationDirectory]? {
        isWatching ? watchedDirectories : nil
    }

    private func applyScanResult(_ found: [ConversationFile]) {
        mergeDiscoveredConversations(found)
        scanExternalApprovals()
    }

    func stopWatching() {
        isWatching = false
        monitorTask?.cancel()
        monitorTask = nil
        externalApprovalScanTask?.cancel()
        externalApprovalScanTask = nil
        pendingExternalApprovalIds.removeAll()
    }

    func scanDirectories() {
        let directories = watchedDirectories
        Task.detached(priority: .utility) { [weak self] in
            let found = autoreleasepool {
                Self.scanDirectoriesSnapshot(directories)
            }
            await self?.applyScanResult(found)
        }
    }

    func scanExternalApprovals() {
        guard let codexDir = watchedDirectories.first(where: { $0.agentId == "codex" }),
              sessionStore != nil,
              externalApprovalScanTask == nil else { return }

        let root = URL(fileURLWithPath: NSString(string: codexDir.path).expandingTildeInPath)
        let sessionsRoot = root.lastPathComponent == "sessions" ? root : root.appendingPathComponent("sessions")
        guard FileManager.default.fileExists(atPath: sessionsRoot.path) else { return }

        let cutoff = Date().addingTimeInterval(-externalApprovalWindow)
        externalApprovalScanTask = Task { [weak self, externalApprovalScanner] in
            let events = await externalApprovalScanner.scan(sessionsRoot: sessionsRoot, cutoff: cutoff)
            guard !Task.isCancelled, let self else { return }
            self.externalApprovalScanTask = nil
            self.applyExternalApprovalEvents(events)
        }
    }

    private func applyExternalApprovalEvents(_ events: [ExternalApprovalEvent]) {
        guard let sessionStore else { return }
        for event in events {
            switch event {
            case .request(let request):
                publishExternalApproval(request, sessionStore: sessionStore)
            case .completed(let callId):
                guard let sessionId = pendingExternalApprovalIds.removeValue(forKey: callId) else { continue }
                Task { await sessionStore.setPendingPermission(sessionId, nil) }
            }
        }
    }

    private func publishExternalApproval(_ request: ExternalApprovalRequest, sessionStore: SessionStore) {
        guard !processedExternalApprovalIds.contains(request.id) else { return }
        if processedExternalApprovalIds.count >= 4_096 {
            processedExternalApprovalIds.removeAll(keepingCapacity: true)
        }
        processedExternalApprovalIds.insert(request.id)
        pendingExternalApprovalIds[request.callId] = request.id

        Task {
            await sessionStore.seedPendingSession(
                sessionId: request.id,
                agentType: request.agentName,
                project: request.project,
                cwd: request.cwd
            )
            await sessionStore.setPendingPermission(request.id, PendingPermission(
                toolUseId: request.callId,
                toolName: request.toolName,
                toolInput: request.command,
                diff: request.detail,
                options: ["open-source-app"],
                source: "codex_external_approval",
                sourceLabel: request.agentName,
                requiresExternalHandling: true,
                externalActionBundleId: "com.openai.codex",
                externalActionHint: request.actionHint
            ))
        }
    }

    nonisolated private static func scanDirectoriesSnapshot(_ directories: [ConversationDirectory]) -> [ConversationFile] {
        var found: [ConversationFile] = []
        for directory in directories {
            found.append(contentsOf: scanDirectory(directory))
            if found.count >= scanPruneThreshold {
                found.sort { $0.timestamp > $1.timestamp }
                found.removeSubrange(scanResultLimit..<found.count)
            }
        }
        found.sort { $0.timestamp > $1.timestamp }
        return Array(found.prefix(scanResultLimit))
    }

    nonisolated private static func scanDirectory(_ dir: ConversationDirectory) -> [ConversationFile] {
        let fm = FileManager.default
        let dirPath = NSString(string: dir.path).expandingTildeInPath

        guard fm.fileExists(atPath: dirPath) else { return [] }

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: dirPath),
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [ConversationFile] = []

        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            guard ext == "json" || ext == "jsonl" || ext == "md" || ext == "txt" else { continue }

            guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                  let modDate = values.contentModificationDate,
                  let sizeValue = values.fileSize else { continue }
            let size = Int64(sizeValue)

            let fileName = url.deletingPathExtension().lastPathComponent
            let sessionId = extractSessionId(from: fileName, path: url.path)

            let conv = ConversationFile(
                id: url.path,
                path: url.path,
                agentId: dir.agentId,
                agentName: dir.agentName,
                projectName: extractProjectName(from: url.path),
                timestamp: modDate,
                size: size,
                sessionId: sessionId,
                snippet: nil
            )

            found.append(conv)
            if found.count >= scanPruneThreshold {
                found.sort { $0.timestamp > $1.timestamp }
                found.removeSubrange(scanResultLimit..<found.count)
            }
        }

        found.sort { $0.timestamp > $1.timestamp }
        return Array(found.prefix(scanResultLimit))
    }

    private func mergeDiscoveredConversations(_ found: [ConversationFile]) {
        // A scan is also a reconciliation pass: never keep rows whose source
        // file has already been removed or rotated by the Agent.
        let existingFiles = discoveredConversations.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
        var mergedByID = Dictionary(uniqueKeysWithValues: existingFiles.map { ($0.id, $0) })
        for conv in found {
            if let existing = mergedByID[conv.id], existing.timestamp > conv.timestamp {
                continue
            }
            mergedByID[conv.id] = conv
        }

        let merged = Array(mergedByID.values)
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(maxConversations)
        let next = Array(merged)
        if next != discoveredConversations {
            discoveredConversations = next
        }
    }

    func readSnippet(for conversation: ConversationFile) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: conversation.path)) else {
            return nil
        }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4_096),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return String(text.prefix(500))
    }

    func getConversationsForAgent(_ agentId: String) -> [ConversationFile] {
        discoveredConversations.filter { $0.agentId == agentId }
    }

    func getConversationsForSession(_ sessionId: String) -> [ConversationFile] {
        discoveredConversations.filter { $0.sessionId == sessionId }
    }

    nonisolated private static func extractSessionId(from fileName: String, path: String) -> String? {
        for regex in sessionIdRegexes {
            if let match = firstCapture(in: fileName, regex: regex) {
                return match
            }
            if let match = firstCapture(in: path, regex: regex) {
                return match
            }
        }
        return nil
    }

    nonisolated private static func firstCapture(in text: String, regex: NSRegularExpression) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    nonisolated private static func extractProjectName(from path: String) -> String? {
        let components = (path as NSString).pathComponents
        for (i, comp) in components.enumerated() {
            if comp == "projects" || comp == "sessions", i + 1 < components.count {
                return components[i + 1]
            }
        }
        return nil
    }

    static func buildConversationDirectories(from profiles: [AgentIntegrationProfile]) -> [ConversationDirectory] {
        var seenPaths = Set<String>()
        return profiles.compactMap { profile in
            let configPath = profile.fullConfigPath
            let expanded = configPath.path
            var isDir: ObjCBool = false
            let root: String
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) {
                root = isDir.boolValue ? expanded : configPath.deletingLastPathComponent().path
            } else {
                let parent = configPath.deletingLastPathComponent().path
                guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDir),
                      isDir.boolValue else { return nil }
                root = parent
            }

            let conversationDirs = findConversationDirs(in: root, profile: profile)
            guard let directory = conversationDirs.first,
                  seenPaths.insert(directory.path).inserted else { return nil }
            return directory
        }
    }

    private static func findConversationDirs(in root: String, profile: AgentIntegrationProfile) -> [ConversationDirectory] {
        var dirs: [ConversationDirectory] = []
        let fm = FileManager.default

        let knownNames = ["projects", "sessions", "conversations", "transcripts", "history", "chat_history", ".sessions"]

        for name in knownNames {
            let candidate = (root as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: candidate, isDirectory: &isDir), isDir.boolValue {
                let dir = ConversationDirectory(
                    path: candidate,
                    agentId: profile.agentId,
                    agentName: profile.displayName,
                    lastModified: (try? fm.attributesOfItem(atPath: candidate)[.modificationDate] as? Date) ?? Date()
                )
                dirs.append(dir)
            }
        }

        return dirs
    }
}

private enum ExternalApprovalEvent: Sendable {
    case request(ExternalApprovalRequest)
    case completed(callId: String)
}

private struct ExternalApprovalCursor: Sendable {
    var offset: UInt64
    var partialLine: Data
}

private struct ExternalApprovalRequest: Sendable {
    var id: String
    var callId: String
    var agentName: String
    var toolName: String
    var command: String
    var detail: String
    var cwd: String
    var project: String
    var actionHint: String
    var timestamp: Date
}

private actor ExternalApprovalScanner {
    private let initialTailBytes: UInt64 = 4 * 1_024 * 1_024
    private let maxDeltaBytes: UInt64 = 8 * 1_024 * 1_024
    private let maxPartialLineBytes = 512 * 1_024
    private let approvalMarker = Data("require_escalated".utf8)
    private let functionOutputMarker = Data("function_call_output".utf8)
    private var cursors: [String: ExternalApprovalCursor] = [:]
    private let timestampFormatter = ISO8601DateFormatter()
    private let fractionalTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    func scan(sessionsRoot: URL, cutoff: Date) -> [ExternalApprovalEvent] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var activePaths = Set<String>()
        var events: [ExternalApprovalEvent] = []
        for case let url as URL in enumerator {
            guard !Task.isCancelled else { break }
            guard url.pathExtension.lowercased() == "jsonl",
                  let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  (values.contentModificationDate ?? .distantPast) >= cutoff,
                  let fileSize = values.fileSize,
                  fileSize >= 0 else { continue }

            activePaths.insert(url.path)
            events.append(contentsOf: scanRollout(
                url: url,
                fileSize: UInt64(fileSize),
                cutoff: cutoff
            ))
        }
        cursors = cursors.filter { activePaths.contains($0.key) }
        return events
    }

    private func scanRollout(
        url: URL,
        fileSize: UInt64,
        cutoff: Date
    ) -> [ExternalApprovalEvent] {
        let prior = cursors[url.path]
        let cursorIsValid = prior.map { $0.offset <= fileSize } ?? false
        var startOffset = cursorIsValid
            ? (prior?.offset ?? 0)
            : fileSize > initialTailBytes ? fileSize - initialTailBytes : 0
        var partialLine = cursorIsValid ? (prior?.partialLine ?? Data()) : Data()
        var dropsLeadingPartialLine = !cursorIsValid && startOffset > 0

        if fileSize > startOffset, fileSize - startOffset > maxDeltaBytes {
            startOffset = fileSize - maxDeltaBytes
            partialLine.removeAll(keepingCapacity: false)
            dropsLeadingPartialLine = true
        }

        guard fileSize > startOffset,
              let handle = try? FileHandle(forReadingFrom: url) else {
            cursors[url.path] = ExternalApprovalCursor(offset: fileSize, partialLine: partialLine)
            return []
        }

        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: startOffset)
            let byteCount = Int(min(fileSize - startOffset, maxDeltaBytes))
            guard let newData = try handle.read(upToCount: byteCount), !newData.isEmpty else { return [] }

            var buffered = Data(capacity: partialLine.count + newData.count)
            buffered.append(partialLine)
            buffered.append(newData)

            var lines = buffered.split(separator: 0x0A, omittingEmptySubsequences: false)
            let endsWithNewline = buffered.last == 0x0A
            var nextPartialLine = Data()
            if endsWithNewline {
                if lines.last?.isEmpty == true {
                    lines.removeLast()
                }
            } else if let tail = lines.popLast(), tail.count <= maxPartialLineBytes {
                nextPartialLine = Data(tail)
            }
            if dropsLeadingPartialLine, !lines.isEmpty {
                lines.removeFirst()
            }

            var events: [ExternalApprovalEvent] = []
            for line in lines where !line.isEmpty {
                autoreleasepool {
                    let data = Data(line)
                    guard data.range(of: approvalMarker) != nil
                            || data.range(of: functionOutputMarker) != nil,
                          let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let timestamp = parseTimestamp(raw["timestamp"] as? String),
                          timestamp >= cutoff,
                          let payload = raw["payload"] as? [String: Any] else { return }

                    if let request = parseRequest(payload: payload, timestamp: timestamp, rolloutURL: url) {
                        events.append(.request(request))
                    } else if let callId = payload["call_id"] as? String,
                              payload["type"] as? String == "function_call_output" {
                        events.append(.completed(callId: callId))
                    }
                }
            }

            cursors[url.path] = ExternalApprovalCursor(
                offset: startOffset + UInt64(newData.count),
                partialLine: nextPartialLine
            )
            return events
        } catch {
            cursors.removeValue(forKey: url.path)
            return []
        }
    }

    private func parseRequest(
        payload: [String: Any],
        timestamp: Date,
        rolloutURL: URL
    ) -> ExternalApprovalRequest? {
        guard payload["type"] as? String == "function_call",
              payload["name"] as? String == "exec_command",
              let callId = payload["call_id"] as? String,
              let arguments = payload["arguments"] as? String,
              let args = parseJSONString(arguments),
              args["sandbox_permissions"] as? String == "require_escalated" else { return nil }

        let command = args["cmd"] as? String ?? "exec_command"
        let cwd = args["workdir"] as? String ?? ""
        let justification = args["justification"] as? String ?? ""
        let prefix = (args["prefix_rule"] as? [Any])?.compactMap { $0 as? String }.joined(separator: " ") ?? ""
        let detail = [
            justification.isEmpty ? nil : justification,
            command.isEmpty ? nil : "Command: \(command)",
            prefix.isEmpty ? nil : "Prefix: \(prefix)"
        ].compactMap { $0 }.joined(separator: "\n\n")

        return ExternalApprovalRequest(
            id: "codex-external-\(callId)",
            callId: callId,
            agentName: "Codex",
            toolName: "exec_command",
            command: command,
            detail: detail,
            cwd: cwd,
            project: cwd.isEmpty ? rolloutURL.deletingPathExtension().lastPathComponent : URL(fileURLWithPath: cwd).lastPathComponent,
            actionHint: "Open Codex to approve or reject this permission request.",
            timestamp: timestamp
        )
    }

    private func parseJSONString(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func parseTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalTimestampFormatter.date(from: value)
            ?? timestampFormatter.date(from: value)
    }
}
