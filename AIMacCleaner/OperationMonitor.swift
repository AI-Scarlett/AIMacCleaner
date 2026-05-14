import Foundation
import AppKit

class OperationMonitor: ObservableObject {
    @Published var records: [OperationRecord] = []
    @Published var isMonitoring: Bool = false

    private var streamRef: FSEventStreamRef?
    private var fileSnapshots: [String: FileSnapshot] = [:]
    private var accessTimes: [String: Date] = [:]
    private let maxRecords = 2000
    private let maxSnapshots = 10000
    private let recordsPath = NSHomeDirectory() + "/.aimaccleaner_operations_v2.json"
    private var cachedActiveAgents: [String] = []
    private var lastAgentDetectTime: Date = .distantPast
    private var hasRestoredBookmarks: Bool = false
    private var lastCleanupTime: Date = .distantPast

    struct FileSnapshot: Codable {
        let path: String
        let modDate: TimeInterval
        let size: Int64
        let isDir: Bool
        let agentName: String?
    }

    private let watchPaths: [String] = {
        let home = NSHomeDirectory()
        return [
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Library/Caches",
            "\(home)/Library/Application Support",
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }()

    private let bookmarksPath: String = NSHomeDirectory() + "/.aimaccleaner_bookmarks.json"

    init() {
        restoreAccessFromBookmarks()
    }

    private let agentProcessNames = [
        "claude", "claude-code", "codebuddy", "cline", "codex", "hermes", "trae", "trae-agent",
        "cursor", "windsurf", "codearts", "kimi", "deepseek", "qwen", "doubao",
        "minimax", "copilot", "aider", "cody", "tabby", "warp",
        "chatgpt", "gemini", "augment", "node", "python", "python3",
        "bun", "deno", "npm", "yarn", "pnpm", "cargo", "go", "rustc",
        "swift", "ruby", "php", "java", "gradle", "mvn",
        "vim", "nvim", "emacs", "code", "subl", "atom",
        "git", "hg", "svn", "rsync", "scp", "curl", "wget",
        "tar", "gzip", "zip", "unzip", "docker", "podman",
        "make", "cmake", "xcodebuild", "swiftc", "gcc", "clang",
    ]

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        loadRecords()
        if !hasRestoredBookmarks {
            restoreAccessFromBookmarks()
        }
        buildInitialSnapshot()
        cachedActiveAgents = detectActiveAgents()
        startFSEventStream()
        startProcessPoller()
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.saveBookmarks()
        }
    }

    func stop() {
        stopFSEventStream()
        processPoller?.invalidate()
        isMonitoring = false
    }

    // MARK: - FSEvents

    private func startFSEventStream() {
        guard !watchPaths.isEmpty else { return }

        let weakRef = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let monitor = Unmanaged<OperationMonitor>.fromOpaque(info).takeUnretainedValue()
            let cPaths = eventPaths.bindMemory(to: UnsafePointer<Int8>.self, capacity: Int(numEvents))
            var pathList: [String] = []
            for i in 0..<Int(numEvents) {
                let cStr = cPaths[i]
                pathList.append(String(cString: cStr))
            }
            guard !pathList.isEmpty else { return }
            DispatchQueue.global(qos: .utility).async { [weak monitor] in
                guard let monitor = monitor else { return }
                do {
                    try monitor.processEvents(paths: pathList)
                } catch {
                    print("[OperationMonitor] Error processing events: \(error.localizedDescription)")
                }
            }
        }

        var context = FSEventStreamContext(
            version: 0,
            info: weakRef,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        streamRef = FSEventStreamCreate(
            nil,
            callback,
            &context,
            watchPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            5.0,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )

        if let stream = streamRef {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
        }
    }

    private func stopFSEventStream() {
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
        }
    }

    private func processEvents(paths: [String]) throws {
        let fm = FileManager.default
        let now = Date()
        
        if now.timeIntervalSince(lastAgentDetectTime) > 5.0 {
            cachedActiveAgents = detectActiveAgents()
            lastAgentDetectTime = now
        }
        
        if now.timeIntervalSince(lastCleanupTime) > 60.0 {
            cleanupOldSnapshots()
            lastCleanupTime = now
        }
        
        let activeAgents = cachedActiveAgents
        let primaryAgent = activeAgents.first ?? "System"

        for eventPath in paths {
            guard !eventPath.isEmpty else { continue }
            
            let fileName = (eventPath as NSString).lastPathComponent
            if fileName.hasPrefix(".") || fileName.hasPrefix("._") { continue }

            let expanded = NSString(string: eventPath).expandingTildeInPath

            guard fm.fileExists(atPath: expanded) else {
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: primaryAgent,
                    operationType: .delete,
                    targetPath: eventPath,
                    detail: formatDeleteDetail(eventPath),
                    fileSize: 0
                )
                addRecord(record)
                fileSnapshots.removeValue(forKey: eventPath)
                accessTimes.removeValue(forKey: eventPath)
                continue
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue else { continue }

            let attrs = try? fm.attributesOfItem(atPath: expanded)
            
            guard let fileAttrs = attrs else { continue }
            
            let size = (fileAttrs[.size] as? NSNumber)?.int64Value ?? 0
            let modDate = (fileAttrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

            if let existing = fileSnapshots[eventPath] {
                guard abs(modDate - existing.modDate) > 1.0 || size != existing.size else {
                    if let lastAccess = accessTimes[eventPath] {
                        if now.timeIntervalSince(lastAccess) > 30.0 {
                            accessTimes[eventPath] = now
                            let record = OperationRecord(
                                id: UUID().uuidString,
                                timestamp: Date(),
                                agentName: primaryAgent,
                                operationType: .read,
                                targetPath: eventPath,
                                detail: formatReadDetail(eventPath, size: size),
                                fileSize: size
                            )
                            addRecord(record)
                        }
                    } else {
                        accessTimes[eventPath] = now
                        let record = OperationRecord(
                            id: UUID().uuidString,
                            timestamp: Date(),
                            agentName: primaryAgent,
                            operationType: .read,
                            targetPath: eventPath,
                            detail: formatReadDetail(eventPath, size: size),
                            fileSize: size
                        )
                        addRecord(record)
                    }
                    continue
                }
                let agentName = activeAgents.first ?? existing.agentName ?? primaryAgent
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentName,
                    operationType: .modify,
                    targetPath: eventPath,
                    detail: formatModifyDetail(eventPath, oldSize: existing.size, newSize: size),
                    fileSize: size
                )
                addRecord(record)
            } else {
                let agentName = primaryAgent
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentName,
                    operationType: .create,
                    targetPath: eventPath,
                    detail: formatCreateDetail(eventPath, size: size),
                    fileSize: size
                )
                addRecord(record)
            }

            fileSnapshots[eventPath] = FileSnapshot(
                path: eventPath,
                modDate: modDate,
                size: size,
                isDir: false,
                agentName: activeAgents.first
            )
            accessTimes[eventPath] = now
        }
    }
    
    private func cleanupOldSnapshots() {
        if fileSnapshots.count > maxSnapshots {
            let excess = fileSnapshots.count - maxSnapshots
            let keysToRemove = Array(fileSnapshots.keys.prefix(excess))
            for key in keysToRemove {
                fileSnapshots.removeValue(forKey: key)
                accessTimes.removeValue(forKey: key)
            }
        }
        
        if accessTimes.count > maxSnapshots * 2 {
            let cutoff = Date().addingTimeInterval(-300)
            accessTimes = accessTimes.filter { $0.value > cutoff }
        }
    }

    // MARK: - Process Detection

    private func detectActiveAgents() -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ps")
        task.arguments = ["-eo", "pid,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }

        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else { return [] }

        var activeAgents: [String] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: " ", maxSplits: 1)
            let processName = parts.count > 1 ? String(parts[1]).lowercased() : String(parts[0]).lowercased()
            guard !processName.isEmpty else { continue }

            for agent in agentProcessNames {
                if processName == agent || processName.hasSuffix("/\(agent)") || processName.contains(agent) {
                    let displayName = agent.capitalized
                    if !activeAgents.contains(displayName) {
                        activeAgents.append(displayName)
                    }
                }
            }
        }

        return activeAgents
    }

    private var processPoller: Timer?
    private var lastPolledAgents: [String] = []
    private func startProcessPoller() {
        processPoller?.invalidate()
        processPoller = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                let agents = self.detectActiveAgents()
                DispatchQueue.main.async {
                    self.cachedActiveAgents = agents
                    self.lastAgentDetectTime = Date()
                    let newAgents = agents.filter { !self.lastPolledAgents.contains($0) }
                    if !newAgents.isEmpty {
                        let agentList = newAgents.joined(separator: ", ")
                        let record = OperationRecord(
                            id: UUID().uuidString,
                            timestamp: Date(),
                            agentName: newAgents.first ?? "System",
                            operationType: .modify,
                            targetPath: "System Process",
                            detail: "🤖 New AI Agent Started: \(agentList)",
                            fileSize: 0
                        )
                        self.addRecord(record)
                    }
                    self.lastPolledAgents = agents
                }
            }
        }
    }

    // MARK: - Snapshot

    private func buildInitialSnapshot() {
        let fm = FileManager.default
        var totalCount = 0
        for dirPath in watchPaths {
            guard totalCount < maxSnapshots else { break }
            let enumerator = fm.enumerator(atPath: dirPath)
            while let file = enumerator?.nextObject() as? String, totalCount < maxSnapshots {
                let fullPath = "\(dirPath)/\(file)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    let attrs = try? fm.attributesOfItem(atPath: fullPath)
                    let size = (attrs?[.size] as? Int64) ?? 0
                    let modDate = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                    fileSnapshots[fullPath] = FileSnapshot(
                        path: fullPath, modDate: modDate, size: size, isDir: isDir.boolValue, agentName: nil
                    )
                    totalCount += 1
                }
            }
        }
        print("[OperationMonitor] Initial snapshot built with \(totalCount) files")
    }

    // MARK: - Detail Formatting

    private func formatCreateDetail(_ path: String, size: Int64) -> String {
        let fileName = (path as NSString).lastPathComponent
        let dirName = dirName(from: path)
        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "📄 创建文件: \(fileName) (\(sizeStr))\n📁 位置: \(dirName)"
    }

    private func formatReadDetail(_ path: String, size: Int64) -> String {
        let fileName = (path as NSString).lastPathComponent
        let dirName = dirName(from: path)
        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "👁️ 读取文件: \(fileName) (\(sizeStr))\n📁 位置: \(dirName)"
    }

    private func formatModifyDetail(_ path: String, oldSize: Int64, newSize: Int64) -> String {
        let fileName = (path as NSString).lastPathComponent
        let dirName = dirName(from: path)
        let diff = newSize - oldSize
        let diffStr: String
        if diff > 0 {
            diffStr = "+\(ByteCountFormatter.string(fromByteCount: diff, countStyle: .file))"
        } else if diff < 0 {
            diffStr = ByteCountFormatter.string(fromByteCount: abs(diff), countStyle: .file)
        } else {
            diffStr = "内容变更"
        }
        return "✏️ 修改文件: \(fileName)\n📊 大小变化: \(diffStr)\n📁 位置: \(dirName)"
    }

    private func formatDeleteDetail(_ path: String) -> String {
        let fileName = (path as NSString).lastPathComponent
        let dirName = dirName(from: path)
        return "🗑️ 删除文件: \(fileName)\n📁 原位置: \(dirName)"
    }

    private func dirName(from path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        if dir.hasPrefix(NSHomeDirectory()) {
            return "~" + String(dir.dropFirst(NSHomeDirectory().count))
        }
        return dir
    }

    // MARK: - Record Management

    func addRecord(_ record: OperationRecord) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.records.insert(record, at: 0)
            if self.records.count > self.maxRecords {
                self.records = Array(self.records.prefix(self.maxRecords))
            }
            if self.records.count % 50 == 0 {
                self.saveRecords()
            }
        }
    }

    func clearRecords() {
        records.removeAll()
        saveRecords()
    }

    private func loadRecords() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: recordsPath)),
              let decoded = try? JSONDecoder().decode([OperationRecord].self, from: data) else { return }
        records = decoded
    }

    func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: URL(fileURLWithPath: recordsPath))
    }

    private func saveBookmarks() {
        var bookmarksData: [String: Data] = [:]
        var savedCount = 0
        for path in watchPaths {
            let url = URL(fileURLWithPath: path)
            do {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                bookmarksData[path] = bookmark
                let success = url.startAccessingSecurityScopedResource()
                if success {
                    savedCount += 1
                }
            } catch {
                continue
            }
        }
        if !bookmarksData.isEmpty, let data = try? JSONEncoder().encode(bookmarksData) {
            try? data.write(to: URL(fileURLWithPath: bookmarksPath))
            print("[OperationMonitor] Saved bookmarks for \(savedCount) paths")
        }
    }

    private func restoreAccessFromBookmarks() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: bookmarksPath)),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
            hasRestoredBookmarks = true
            return
        }
        var restoredCount = 0
        for (path, bookmark) in bookmarks {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if !isStale {
                    let success = url.startAccessingSecurityScopedResource()
                    if success {
                        restoredCount += 1
                    }
                }
            } catch {
                continue
            }
        }
        hasRestoredBookmarks = true
        if restoredCount > 0 {
            print("[OperationMonitor] Restored access for \(restoredCount) paths from bookmarks")
        }
    }

    deinit {
        stopFSEventStream()
        processPoller?.invalidate()
    }
}
