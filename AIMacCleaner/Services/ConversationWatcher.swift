import Foundation

struct ConversationFile: Codable, Identifiable {
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
    private var watchedPaths: Set<String> = []
    private let maxConversations = 500
    private let externalApprovalWindow: TimeInterval = 15 * 60
    private let initialApprovalTailBytes: UInt64 = 4 * 1_024 * 1_024
    private let maxApprovalDeltaBytes: UInt64 = 8 * 1_024 * 1_024
    private let maxApprovalPartialLineBytes = 512 * 1_024
    private var processedExternalApprovalIds: Set<String> = []
    private var pendingExternalApprovalIds: [String: String] = [:]
    private var externalApprovalCursors: [String: ExternalApprovalCursor] = [:]
    private weak var sessionStore: SessionStore?
    private let jsonTimestampFormatter = ISO8601DateFormatter()
    private let fractionalJSONTimestampFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated private static let sessionIdRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "session[-_]([a-f0-9-]{20,})", options: []),
        try! NSRegularExpression(pattern: "([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})", options: [])
    ]
    nonisolated private static let approvalMarker = Data("require_escalated".utf8)
    nonisolated private static let functionOutputMarker = Data("function_call_output".utf8)

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
        pendingExternalApprovalIds.removeAll()
        externalApprovalCursors.removeAll()
    }

    func scanDirectories() {
        mergeDiscoveredConversations(Self.scanDirectoriesSnapshot(watchedDirectories))
    }

    func scanExternalApprovals() {
        guard let codexDir = watchedDirectories.first(where: { $0.agentId == "codex" }),
              let sessionStore else { return }

        let root = URL(fileURLWithPath: NSString(string: codexDir.path).expandingTildeInPath)
        let sessionsRoot = root.lastPathComponent == "sessions" ? root : root.appendingPathComponent("sessions")
        guard FileManager.default.fileExists(atPath: sessionsRoot.path) else { return }

        let cutoff = Date().addingTimeInterval(-externalApprovalWindow)
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var activePaths = Set<String>()
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  (values.contentModificationDate ?? .distantPast) >= cutoff,
                  let fileSize = values.fileSize,
                  fileSize >= 0 else { continue }
            activePaths.insert(url.path)
            scanCodexRolloutForExternalApprovals(
                url: url,
                fileSize: UInt64(fileSize),
                cutoff: cutoff,
                sessionStore: sessionStore
            )
        }
        externalApprovalCursors = externalApprovalCursors.filter { activePaths.contains($0.key) }
    }

    private func scanCodexRolloutForExternalApprovals(
        url: URL,
        fileSize: UInt64,
        cutoff: Date,
        sessionStore: SessionStore
    ) {
        let prior = externalApprovalCursors[url.path]
        let cursorIsValid = prior.map { $0.offset <= fileSize } ?? false
        var startOffset = cursorIsValid
            ? (prior?.offset ?? 0)
            : fileSize > initialApprovalTailBytes ? fileSize - initialApprovalTailBytes : 0
        var partialLine = cursorIsValid ? (prior?.partialLine ?? Data()) : Data()
        var dropsLeadingPartialLine = !cursorIsValid && startOffset > 0

        if fileSize > startOffset, fileSize - startOffset > maxApprovalDeltaBytes {
            startOffset = fileSize - maxApprovalDeltaBytes
            partialLine.removeAll(keepingCapacity: false)
            dropsLeadingPartialLine = true
        }

        guard fileSize > startOffset,
              let handle = try? FileHandle(forReadingFrom: url) else {
            externalApprovalCursors[url.path] = ExternalApprovalCursor(
                offset: fileSize,
                partialLine: partialLine
            )
            return
        }

        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: startOffset)
            let byteCount = Int(min(fileSize - startOffset, maxApprovalDeltaBytes))
            guard let newData = try handle.read(upToCount: byteCount), !newData.isEmpty else { return }

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
            } else if let tail = lines.popLast(), tail.count <= maxApprovalPartialLineBytes {
                nextPartialLine = Data(tail)
            }
            if dropsLeadingPartialLine, !lines.isEmpty {
                lines.removeFirst()
            }

            for line in lines where !line.isEmpty {
                autoreleasepool {
                    let data = Data(line)
                    guard data.range(of: Self.approvalMarker) != nil
                            || data.range(of: Self.functionOutputMarker) != nil,
                          let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let timestamp = parseJSONLTimestamp(raw["timestamp"] as? String),
                          timestamp >= cutoff,
                          let payload = raw["payload"] as? [String: Any] else { return }

                    if let request = parseCodexExternalApproval(
                        payload: payload,
                        timestamp: timestamp,
                        rolloutURL: url
                    ) {
                        publishExternalApproval(request, sessionStore: sessionStore)
                        return
                    }

                    if let callId = payload["call_id"] as? String,
                       payload["type"] as? String == "function_call_output",
                       let sessionId = pendingExternalApprovalIds.removeValue(forKey: callId) {
                        Task { await sessionStore.setPendingPermission(sessionId, nil) }
                    }
                }
            }

            externalApprovalCursors[url.path] = ExternalApprovalCursor(
                offset: startOffset + UInt64(newData.count),
                partialLine: nextPartialLine
            )
        } catch {
            externalApprovalCursors.removeValue(forKey: url.path)
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

    private func parseCodexExternalApproval(
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
            project: projectName(from: cwd, fallback: rolloutURL.deletingPathExtension().lastPathComponent),
            actionHint: "Open Codex to approve or reject this permission request.",
            timestamp: timestamp
        )
    }

    private func parseJSONString(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func parseJSONLTimestamp(_ value: String?) -> Date? {
        guard let value else { return nil }
        return fractionalJSONTimestampFormatter.date(from: value)
            ?? jsonTimestampFormatter.date(from: value)
    }

    private func projectName(from cwd: String, fallback: String) -> String {
        guard !cwd.isEmpty else { return fallback }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    nonisolated private static func scanDirectoriesSnapshot(_ directories: [ConversationDirectory]) -> [ConversationFile] {
        directories.flatMap { scanDirectory($0) }
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

            guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                  let modDate = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? Int64 else { continue }

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
        }

        return found
    }

    private func mergeDiscoveredConversations(_ found: [ConversationFile]) {
        let existingIds = Set(discoveredConversations.map { $0.id })
        for conv in found {
            if !existingIds.contains(conv.id) {
                discoveredConversations.insert(conv, at: 0)
            }
        }

        if discoveredConversations.count > maxConversations {
            discoveredConversations = Array(discoveredConversations.prefix(maxConversations))
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

private struct ExternalApprovalCursor {
    var offset: UInt64
    var partialLine: Data
}

private struct ExternalApprovalRequest {
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
