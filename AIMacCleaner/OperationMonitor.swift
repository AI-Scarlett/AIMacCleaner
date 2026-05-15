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
    private var agentPIDMap: [String: pid_t] = [:]
    private var agentOpenFiles: [String: Set<String>] = [:]
    private var lastAgentDetectTime: Date = .distantPast
    private var lastOpenFilesRefresh: Date = .distantPast
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
            "\(home)/Projects",
            NSHomeDirectory(),
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }()

    private let bookmarksPath: String = NSHomeDirectory() + "/.aimaccleaner_bookmarks.json"
    
    private let stateLock = NSLock()
    private let processQueue = DispatchQueue(label: "com.aimacleaner.monitor.process", qos: .userInitiated)

    init() {
        restoreAccessFromBookmarks()
    }

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

    private func detectAgentForPath(_ path: String, agents: [String]) -> String? {
        guard !agents.isEmpty else { return nil }

        let expanded = NSString(string: path).expandingTildeInPath
        for agent in agents {
            if let files = agentOpenFiles[agent], files.contains(expanded) {
                return agent
            }
        }

        let pathLower = expanded.lowercased()
        for agent in agents {
            if pathLower.contains("/\(agent.lowercased())/") || pathLower.contains(".\(agent.lowercased())/") {
                return agent
            }
        }

        return nil
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
            
            monitor.processQueue.async { [weak monitor] in
                guard let monitor = monitor else { return }
                monitor.processEvents(paths: pathList)
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

    private func processEvents(paths: [String]) {
        let fm = FileManager.default
        let now = Date()

        if now.timeIntervalSince(lastAgentDetectTime) > 10.0 {
            let agents = detectActiveAgents()
            stateLock.lock()
            cachedActiveAgents = agents
            lastAgentDetectTime = Date()
            stateLock.unlock()
        }

        if now.timeIntervalSince(lastCleanupTime) > 60.0 {
            cleanupOldSnapshots()
            lastCleanupTime = now
        }

        stateLock.lock()
        let agents = cachedActiveAgents
        stateLock.unlock()

        for eventPath in paths {
            guard !eventPath.isEmpty else { continue }

            let fileName = (eventPath as NSString).lastPathComponent
            if fileName.hasPrefix(".") || fileName.hasPrefix("._") { continue }

            let expanded = NSString(string: eventPath).expandingTildeInPath

            let exists: Bool
            do {
                exists = fm.fileExists(atPath: expanded)
            } catch {
                continue
            }

            guard exists else {
                let agentName = detectAgentForPath(eventPath, agents: agents) ?? "System"
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentName,
                    operationType: .delete,
                    targetPath: eventPath,
                    detail: formatDeleteDetail(eventPath),
                    fileSize: 0
                )
                addRecord(record)
                stateLock.lock()
                fileSnapshots.removeValue(forKey: eventPath)
                accessTimes.removeValue(forKey: eventPath)
                stateLock.unlock()
                continue
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir), !isDir.boolValue else { continue }

            let attrs: [FileAttributeKey: Any]?
            do {
                attrs = try fm.attributesOfItem(atPath: expanded)
            } catch {
                continue
            }
            guard let fileAttrs = attrs else { continue }

            let size = (fileAttrs[.size] as? NSNumber)?.int64Value ?? 0
            let modDate = (fileAttrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

            stateLock.lock()
            let existing = fileSnapshots[eventPath]
            stateLock.unlock()

            if let existing = existing {
                guard abs(modDate - existing.modDate) > 1.0 || size != existing.size else {
                    stateLock.lock()
                    let shouldRecordRead: Bool
                    if let lastAccess = accessTimes[eventPath] {
                        shouldRecordRead = now.timeIntervalSince(lastAccess) > 30.0
                    } else {
                        shouldRecordRead = true
                    }
                    if shouldRecordRead {
                        accessTimes[eventPath] = now
                    }
                    stateLock.unlock()
                    
                    if shouldRecordRead {
                        let agentName = detectAgentForPath(eventPath, agents: agents) ?? existing.agentName ?? "System"
                        let record = OperationRecord(
                            id: UUID().uuidString,
                            timestamp: Date(),
                            agentName: agentName,
                            operationType: .read,
                            targetPath: eventPath,
                            detail: formatReadDetail(eventPath, size: size),
                            fileSize: size
                        )
                        addRecord(record)
                    }
                    continue
                }

                let agentName = detectAgentForPath(eventPath, agents: agents) ?? existing.agentName ?? "System"
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
                let agentName = detectAgentForPath(eventPath, agents: agents) ?? "System"
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

            stateLock.lock()
            fileSnapshots[eventPath] = FileSnapshot(
                path: eventPath,
                modDate: modDate,
                size: size,
                isDir: false,
                agentName: detectAgentForPath(eventPath, agents: agents)
            )
            accessTimes[eventPath] = now
            stateLock.unlock()
        }
    }

    private func cleanupOldSnapshots() {
        stateLock.lock()
        defer { stateLock.unlock() }
        
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
        var activeAgents: [String] = []
        var seenApps: Set<String> = []
        var newPIDMap: [String: pid_t] = [:]

        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications
        for app in runningApps {
            let name = app.localizedName ?? ""
            let bundleId = app.bundleIdentifier ?? ""
            let execURL = app.executableURL?.path ?? ""
            let lowerName = name.lowercased()
            let lowerExec = execURL.lowercased()
            let lowerBundle = bundleId.lowercased()

            if lowerBundle.contains("findersyncextension") || lowerExec.contains("/plugins/") ||
               lowerBundle.hasSuffix(".appex") || lowerExec.contains(".appex/") {
                continue
            }

            let appsMap: [(String, [String])] = [
                ("Trae", ["trae"]), ("Claude", ["claude"]), ("Cursor", ["cursor"]),
                ("Windsurf", ["windsurf", "codeium"]), ("CodeBuddy", ["codebuddy"]),
                ("Doubao", ["doubao"]), ("Kimi", ["kimi"]), ("DeepSeek", ["deepseek"]),
                ("ChatGPT", ["chatgpt"]), ("Gemini", ["gemini"]), ("Copilot", ["copilot"]),
                ("Cline", ["cline"]), ("Hermes", ["hermes"]), ("Codex", ["codex"]),
                ("Augment", ["augment"]), ("CodeArts", ["codearts", "huawei"]),
            ]

            for (displayName, keywords) in appsMap where !seenApps.contains(displayName) {
                for kw in keywords {
                    if lowerName.contains(kw) || lowerExec.contains(kw) || lowerBundle.contains(kw) {
                        activeAgents.append(displayName)
                        seenApps.insert(displayName)
                        newPIDMap[displayName] = app.processIdentifier
                        break
                    }
                }
            }
        }

        if activeAgents.isEmpty {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ps")
            task.arguments = ["-eo", "pid=,command="]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = FileHandle.nullDevice
            do { try task.run(); task.waitUntilExit() } catch { return [] }
            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else { return [] }

            let psAgents: [(String, [String])] = [
                ("Trae", ["trae"]), ("Claude", ["claude"]), ("Cursor", ["cursor"]),
                ("Windsurf", ["windsurf", "codeium"]), ("CodeBuddy", ["codebuddy"]),
                ("Doubao", ["doubao"]), ("Kimi", ["kimi"]), ("DeepSeek", ["deepseek"]),
                ("ChatGPT", ["chatgpt"]), ("Gemini", ["gemini"]), ("Copilot", ["copilot"]),
                ("Cline", ["cline"]), ("Hermes", ["hermes"]), ("Codex", ["codex"]),
                ("Augment", ["augment"]), ("CodeArts", ["codearts", "huawei"]),
            ]

            for line in output.components(separatedBy: .newlines) {
                let ll = line.lowercased()
                if ll.contains("/plugins/") || ll.contains(".appex/") { continue }
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
                guard parts.count >= 2, let pid = pid_t(parts[0]) else { continue }
                for (displayName, keywords) in psAgents where !seenApps.contains(displayName) {
                    for kw in keywords where ll.contains(kw) {
                        activeAgents.append(displayName)
                        seenApps.insert(displayName)
                        newPIDMap[displayName] = pid
                        break
                    }
                    if seenApps.contains(displayName) { break }
                }
            }
        }

        let cliNames: [String: String] = [
            "node": "Node.js", "python3": "Python", "python": "Python",
            "npm": "npm", "yarn": "Yarn", "pnpm": "pnpm", "cargo": "Cargo",
            "deno": "Deno", "bun": "Bun", "go": "Go", "swift": "Swift",
            "java": "Java", "gradle": "Gradle", "mvn": "Maven",
            "make": "Make", "cmake": "CMake", "xcodebuild": "Xcode", "git": "Git",
        ]

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ps")
        task.arguments = ["-eo", "pid=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run(); task.waitUntilExit() } catch { return activeAgents }
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else { return activeAgents }

        for line in output.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1)
            guard parts.count >= 2, let pid = pid_t(parts[0]) else { continue }
            let comm = String(parts[1]).lowercased()
            if let displayName = cliNames[comm], !activeAgents.contains(displayName) {
                activeAgents.append(displayName)
                newPIDMap[displayName] = pid
            }
        }

        agentPIDMap = newPIDMap
        return activeAgents
    }

    private func refreshAgentOpenFiles() {
        let pids = agentPIDMap.values
        guard !pids.isEmpty else { return }
        let pidList = pids.map(String.init).joined(separator: ",")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-w", "-Fn", "-p", pidList]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let deadline = DispatchTime.now() + .seconds(3)
            DispatchQueue.global().asyncAfter(deadline: deadline) { task.terminate() }
            task.waitUntilExit()

            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else { return }

            var filePaths: Set<String> = []
            for line in output.components(separatedBy: .newlines) {
                guard line.hasPrefix("n") else { continue }
                let path = String(line.dropFirst())
                guard path.hasPrefix("/"), !path.hasPrefix("/dev/"), !path.hasPrefix("/private/var/folders"),
                      !path.contains(".app/Contents/"), path != "/" else { continue }
                filePaths.insert(path)
            }

            var newOpenFiles: [String: Set<String>] = [:]
            for agent in agentPIDMap.keys {
                newOpenFiles[agent] = filePaths
            }
            agentOpenFiles = newOpenFiles
            lastOpenFilesRefresh = Date()
        } catch {}
    }

    private var processPoller: Timer?
    private var lastPolledAgents: [String] = []
    private func startProcessPoller() {
        processPoller?.invalidate()
        processPoller = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                let agents = self.detectActiveAgents()
                self.refreshAgentOpenFiles()
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
                            detail: "🤖 New Agent: \(agentList)",
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
                    let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                    let modDate = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                    stateLock.lock()
                    fileSnapshots[fullPath] = FileSnapshot(
                        path: fullPath, modDate: modDate, size: size, isDir: isDir.boolValue, agentName: nil
                    )
                    stateLock.unlock()
                    totalCount += 1
                }
            }
        }
    }

    // MARK: - Detail Formatting

    private func formatCreateDetail(_ path: String, size: Int64) -> String {
        let fileName = (path as NSString).lastPathComponent
        let dirName = dirName(from: path)
        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "📄 Create: \(fileName) (\(sizeStr))\n📁 \(dirName)"
    }

    private func formatReadDetail(_ path: String, size: Int64) -> String {
        let fileName = (path as NSString).lastPathComponent
        let dirName = dirName(from: path)
        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "👁 Read: \(fileName) (\(sizeStr))\n📁 \(dirName)"
    }

    private func formatModifyDetail(_ path: String, oldSize: Int64, newSize: Int64) -> String {
        let fileName = (path as NSString).lastPathComponent
        let dirName = dirName(from: path)
        let diff = newSize - oldSize
        let diffStr: String
        if diff > 0 {
            diffStr = "+\(ByteCountFormatter.string(fromByteCount: diff, countStyle: .file))"
        } else if diff < 0 {
            diffStr = "-\(ByteCountFormatter.string(fromByteCount: abs(diff), countStyle: .file))"
        } else {
            diffStr = "content changed"
        }
        return "✏️ Modify: \(fileName)\n📊 \(diffStr)\n📁 \(dirName)"
    }

    private func formatDeleteDetail(_ path: String) -> String {
        let fileName = (path as NSString).lastPathComponent
        let dirName = dirName(from: path)
        return "🗑 Delete: \(fileName)\n📁 \(dirName)"
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
        stateLock.lock()
        let currentRecords = records
        stateLock.unlock()
        guard let data = try? JSONEncoder().encode(currentRecords) else { return }
        try? data.write(to: URL(fileURLWithPath: recordsPath))
    }

    private func saveBookmarks() {
        var bookmarksData: [String: Data] = [:]
        for path in watchPaths {
            let url = URL(fileURLWithPath: path)
            do {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                bookmarksData[path] = bookmark
                _ = url.startAccessingSecurityScopedResource()
            } catch {
                continue
            }
        }
        if !bookmarksData.isEmpty, let data = try? JSONEncoder().encode(bookmarksData) {
            try? data.write(to: URL(fileURLWithPath: bookmarksPath))
        }
    }

    private func restoreAccessFromBookmarks() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: bookmarksPath)),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
            hasRestoredBookmarks = true
            return
        }
        for (_, bookmark) in bookmarks {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if !isStale {
                    _ = url.startAccessingSecurityScopedResource()
                }
            } catch {
                continue
            }
        }
        hasRestoredBookmarks = true
    }

    deinit {
        stopFSEventStream()
        processPoller?.invalidate()
    }
}
