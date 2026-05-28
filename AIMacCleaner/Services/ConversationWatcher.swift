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
    private var processedExternalApprovalIds: Set<String> = []
    private var pendingExternalApprovalIds: [String: String] = [:]
    private weak var sessionStore: SessionStore?

    func setupExternalApprovalBridge(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    func startWatching(directories: [ConversationDirectory]) {
        stopWatching()
        watchedDirectories = directories
        watchedPaths = Set(directories.map { $0.path })
        isWatching = true

        monitorTask = Task { [weak self] in
            while !Task.isCancelled, self?.isWatching == true {
                self?.scanDirectories()
                self?.scanExternalApprovals()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stopWatching() {
        isWatching = false
        monitorTask?.cancel()
        monitorTask = nil
        pendingExternalApprovalIds.removeAll()
    }

    func scanDirectories() {
        for dir in watchedDirectories {
            scanDirectory(dir)
        }
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
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
                  (values.contentModificationDate ?? .distantPast) >= cutoff else { continue }
            scanCodexRolloutForExternalApprovals(url: url, cutoff: cutoff, sessionStore: sessionStore)
        }
    }

    private func scanCodexRolloutForExternalApprovals(url: URL, cutoff: Date, sessionStore: SessionStore) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestamp = parseJSONLTimestamp(raw["timestamp"] as? String),
                  timestamp >= cutoff,
                  let payload = raw["payload"] as? [String: Any] else { continue }

            if let request = parseCodexExternalApproval(payload: payload, timestamp: timestamp, rolloutURL: url) {
                publishExternalApproval(request, sessionStore: sessionStore)
                continue
            }

            if let callId = payload["call_id"] as? String,
               payload["type"] as? String == "function_call_output",
               let sessionId = pendingExternalApprovalIds.removeValue(forKey: callId) {
                Task { await sessionStore.setPendingPermission(sessionId, nil) }
            }
        }
    }

    private func publishExternalApproval(_ request: ExternalApprovalRequest, sessionStore: SessionStore) {
        guard !processedExternalApprovalIds.contains(request.id) else { return }
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
        return ISO8601DateFormatter().date(from: value)
    }

    private func projectName(from cwd: String, fallback: String) -> String {
        guard !cwd.isEmpty else { return fallback }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    private func scanDirectory(_ dir: ConversationDirectory) {
        let fm = FileManager.default
        let dirPath = NSString(string: dir.path).expandingTildeInPath

        guard fm.fileExists(atPath: dirPath) else { return }

        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: dirPath),
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

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
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: conversation.path)),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return String(text.prefix(500))
    }

    func getConversationsForAgent(_ agentId: String) -> [ConversationFile] {
        discoveredConversations.filter { $0.agentId == agentId }
    }

    func getConversationsForSession(_ sessionId: String) -> [ConversationFile] {
        discoveredConversations.filter { $0.sessionId == sessionId }
    }

    private func extractSessionId(from fileName: String, path: String) -> String? {
        let patterns: [Regex<(Substring, Substring)>] = [
            try! Regex("session[-_]([a-f0-9-]{20,})"),
            try! Regex("([a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12})"),
        ]

        for pattern in patterns {
            if let match = fileName.firstMatch(of: pattern) {
                return String(match.1)
            }
            if let match = path.firstMatch(of: pattern) {
                return String(match.1)
            }
        }
        return nil
    }

    private func extractProjectName(from path: String) -> String? {
        let components = (path as NSString).pathComponents
        for (i, comp) in components.enumerated() {
            if comp == "projects" || comp == "sessions", i + 1 < components.count {
                return components[i + 1]
            }
        }
        return nil
    }

    static func buildConversationDirectories(from profiles: [AgentIntegrationProfile]) -> [ConversationDirectory] {
        profiles.compactMap { profile in
            let expanded = profile.fullConfigPath.path
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir) else { return nil }
            let root = isDir.boolValue ? expanded : URL(fileURLWithPath: expanded).deletingLastPathComponent().path

            let conversationDirs = findConversationDirs(in: root, profile: profile)
            return conversationDirs.first
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

        if dirs.isEmpty {
            let dir = ConversationDirectory(
                path: root,
                agentId: profile.agentId,
                agentName: profile.displayName,
                lastModified: Date()
            )
            dirs.append(dir)
        }

        return dirs
    }
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
