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

    func startWatching(directories: [ConversationDirectory]) {
        stopWatching()
        watchedDirectories = directories
        watchedPaths = Set(directories.map { $0.path })
        isWatching = true

        monitorTask = Task { [weak self] in
            while !Task.isCancelled, self?.isWatching == true {
                self?.scanDirectories()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stopWatching() {
        isWatching = false
        monitorTask?.cancel()
        monitorTask = nil
    }

    func scanDirectories() {
        for dir in watchedDirectories {
            scanDirectory(dir)
        }
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
            let expanded = NSString(string: profile.configRoot).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: expanded) else { return nil }

            let conversationDirs = findConversationDirs(in: expanded, profile: profile)
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
