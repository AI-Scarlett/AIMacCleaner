import Foundation
import AppKit

struct ProcessInfo {
    let pid: pid_t
    let comm: String
    let args: String
    let agentName: String?
}

class OperationMonitor: ObservableObject {
    @Published var records: [OperationRecord] = []
    @Published var isMonitoring: Bool = false

    private var streamRef: FSEventStreamRef?
    private var fileSnapshots: [String: FileSnapshot] = [:]
    private var accessTimes: [String: Date] = [:]
    private let maxRecords = 2000
    private let maxSnapshots = 10000
    private let recordsPath = NSHomeDirectory() + "/.aimaccleaner_operations_v2.json"
    private var hasRestoredBookmarks: Bool = false
    private var lastCleanupTime: Date = .distantPast

    private var agentPIDMap: [String: pid_t] = [:]
    private var pidAgentMap: [pid_t: String] = [:]
    private var pidOpenFiles: [pid_t: Set<String>] = [:]
    private var pidCommMap: [pid_t: String] = [:]
    private var pidArgsMap: [pid_t: String] = [:]
    private var ppidMap: [pid_t: pid_t] = [:]
    private var lastLsofRefresh: Date = .distantPast

    private let agentKeywords: [(String, [String])] = [
        ("Trae", ["trae-cn", "trae cn", "traecn", "trae-cn.app"]), ("Claude", ["claude"]),
        ("Cursor", ["cursor"]), ("Windsurf", ["windsurf", "codeium"]),
        ("CodeBuddy", ["codebuddy-cn", "codebuddy cn", "codebuddycn"]),
        ("Doubao", ["doubao"]), ("Kimi", ["kimi"]), ("DeepSeek", ["deepseek"]),
        ("ChatGPT", ["chatgpt"]), ("Gemini", ["gemini"]), ("Copilot", ["copilot"]),
        ("Cline", ["cline"]), ("Hermes", ["hermes"]), ("Codex", ["codex"]),
        ("Augment", ["augment"]), ("CodeArts", ["codearts", "huawei"]),
    ]

    private let cliToolNames: [String: String] = [
        "node": "Node.js", "python3": "Python", "python": "Python",
        "npm": "npm", "npx": "npx", "yarn": "Yarn", "pnpm": "pnpm",
        "cargo": "Cargo", "rustc": "Rust", "deno": "Deno", "bun": "Bun",
        "go": "Go", "swift": "Swift", "swiftc": "Swift",
        "java": "Java", "gradle": "Gradle", "mvn": "Maven",
        "make": "Make", "cmake": "CMake", "xcodebuild": "Xcode",
        "git": "Git", "docker": "Docker", "pip": "pip", "pip3": "pip3",
        "esbuild": "esbuild", "tsx": "tsx", "tsc": "tsc",
        "swift-frontend": "Swift", "clang": "Clang",
    ]

    struct FileSnapshot: Codable {
        let path: String
        let modDate: TimeInterval
        let size: Int64
        let isDir: Bool
        let agentName: String?
        let processName: String?
        let toolInfo: String?
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
        refreshAllProcessInfo()
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

    // MARK: - Batch Process Info Refresh

    private func refreshAllProcessInfo() {
        detectActiveAgents()
        refreshLsofData()
    }

    private func detectActiveAgents() {
        var newAgentPIDMap: [String: pid_t] = [:]
        var newPidCommMap: [pid_t: String] = [:]
        var newPidArgsMap: [pid_t: String] = [:]
        var newPpidMap: [pid_t: pid_t] = [:]

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "pid=,ppid=,comm=,args="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            task.waitUntilExit()
            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else { return }

            for line in output.components(separatedBy: .newlines) {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 3,
                      let pid = pid_t(parts[0]),
                      let ppid = pid_t(parts[1]) else { continue }

                let comm = String(parts[2])
                let args = parts.count >= 4 ? String(parts[3...].joined(separator: " ")) : ""
                let lowerAll = (comm + " " + args).lowercased()

                if lowerAll.contains("findersyncextension") || lowerAll.hasSuffix(".appex") ||
                   lowerAll.contains("/plugins/") { continue }

                newPidCommMap[pid] = comm
                newPidArgsMap[pid] = args
                newPpidMap[pid] = ppid

                let resolved = resolveAgentNameFromComm(comm: comm, args: args)
                if let name = resolved {
                    newAgentPIDMap[name] = pid
                }
            }
        } catch {}

        stateLock.lock()
        agentPIDMap = newAgentPIDMap
        pidCommMap = newPidCommMap
        pidArgsMap = newPidArgsMap
        ppidMap = newPpidMap
        pidAgentMap = [:]
        for (name, pid) in agentPIDMap {
            pidAgentMap[pid] = name
        }
        stateLock.unlock()
    }

    private func resolveAgentNameFromComm(comm: String, args: String) -> String? {
        let combined = (comm + " " + args).lowercased()
        for (displayName, keywords) in agentKeywords {
            for kw in keywords {
                if combined.contains(kw) {
                    return displayName
                }
            }
        }
        let commBase = (comm as NSString).lastPathComponent.lowercased()
        return cliToolNames[commBase]
    }

    private func refreshLsofData() {
        let pids = agentPIDMap.values
        guard !pids.isEmpty else {
            stateLock.lock()
            pidOpenFiles = [:]
            stateLock.unlock()
            return
        }
        let pidList = pids.map(String.init).joined(separator: ",")

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["+c", "0", "-w", "-FpcRn", "-p", pidList]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let deadline = DispatchTime.now() + .seconds(5)
            DispatchQueue.global().asyncAfter(deadline: deadline) { task.terminate() }
            task.waitUntilExit()

            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else { return }

            var newPidOpenFiles: [pid_t: Set<String>] = [:]
            var currentPid: pid_t = 0

            for line in output.components(separatedBy: .newlines) {
                if line.hasPrefix("p") {
                    if let pid = pid_t(String(line.dropFirst())) {
                        currentPid = pid
                    }
                } else if line.hasPrefix("n") && currentPid != 0 {
                    let path = String(line.dropFirst())
                    guard path.hasPrefix("/"), !path.hasPrefix("/dev/"),
                          !path.hasPrefix("/private/var/folders/"),
                          !path.contains(".app/Contents/MacOS/") else { continue }
                    newPidOpenFiles[currentPid, default: []].insert(path)
                }
            }

            stateLock.lock()
            pidOpenFiles = newPidOpenFiles
            lastLsofRefresh = Date()
            stateLock.unlock()
        } catch {}
    }

    // MARK: - Cached Agent Lookup (NO lsof per event!)

    private func lookupAgentForPath(_ eventPath: String) -> (agentName: String, processName: String?, toolInfo: String?) {
        let expanded = NSString(string: eventPath).expandingTildeInPath

        stateLock.lock()
        let localPidOpenFiles = pidOpenFiles
        let localPidAgentMap = pidAgentMap
        let localPidCommMap = pidCommMap
        let localPidArgsMap = pidArgsMap
        let localPpidMap = ppidMap
        let localAgentPIDMap = agentPIDMap
        stateLock.unlock()

        for (pid, files) in localPidOpenFiles {
            if files.contains(expanded) {
                let agentName = localPidAgentMap[pid] ?? resolveFromTree(pid: pid, ppidMap: localPpidMap, pidAgentMap: localPidAgentMap, pidCommMap: localPidCommMap)
                let procName = localPidCommMap[pid]
                let args = localPidArgsMap[pid] ?? ""
                let tool = extractToolInfo(comm: procName ?? "", args: args)
                return (agentName ?? procName ?? "PID:\(pid)", procName, tool)
            }
        }

        for (pid, files) in localPidOpenFiles {
            for file in files {
                if expanded.hasPrefix(file) {
                    let agentName = localPidAgentMap[pid] ?? resolveFromTree(pid: pid, ppidMap: localPpidMap, pidAgentMap: localPidAgentMap, pidCommMap: localPidCommMap)
                    let procName = localPidCommMap[pid]
                    let args = localPidArgsMap[pid] ?? ""
                    let tool = extractToolInfo(comm: procName ?? "", args: args)
                    return (agentName ?? procName ?? "PID:\(pid)", procName, tool)
                }
            }
        }

        let pathLower = expanded.lowercased()
        for (name, _) in localAgentPIDMap {
            let kw = name.lowercased()
            if pathLower.contains("/\(kw)/") || pathLower.contains(".\(kw)/") {
                return (name, "path-match", nil)
            }
        }

        return ("—", nil, nil)
    }

    private func resolveFromTree(pid: pid_t, ppidMap: [pid_t: pid_t], pidAgentMap: [pid_t: String], pidCommMap: [pid_t: String]) -> String? {
        var current = pid
        var depth = 0
        while depth < 10 {
            if let name = pidAgentMap[current] {
                return name
            }
            if let ppid = ppidMap[current], ppid > 0 {
                current = ppid
                depth += 1
            } else {
                break
            }
        }
        if let comm = pidCommMap[current] {
            let commBase = (comm as NSString).lastPathComponent.lowercased()
            return cliToolNames[commBase]
        }
        return nil
    }

    private func extractToolInfo(comm: String, args: String) -> String? {
        let commBase = (comm as NSString).lastPathComponent
        guard !commBase.isEmpty else { return nil }
        if args.isEmpty { return commBase }
        let maxLen = 80
        if args.count > maxLen {
            return commBase + " " + String(args.prefix(maxLen)) + "…"
        }
        return commBase + " " + args
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

        if now.timeIntervalSince(lastCleanupTime) > 60.0 {
            cleanupOldSnapshots()
            lastCleanupTime = now
        }

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

            let agentInfo = lookupAgentForPath(eventPath)

            guard exists else {
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentInfo.agentName,
                    operationType: .delete,
                    targetPath: eventPath,
                    detail: formatDeleteDetail(eventPath),
                    fileSize: 0,
                    processName: agentInfo.processName,
                    toolInfo: agentInfo.toolInfo
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
                        let readAgent = agentInfo.agentName == "—" ? (existing.agentName ?? "—") : agentInfo.agentName
                        let readProc = agentInfo.processName ?? existing.processName
                        let readTool = agentInfo.toolInfo ?? existing.toolInfo
                        let record = OperationRecord(
                            id: UUID().uuidString,
                            timestamp: Date(),
                            agentName: readAgent,
                            operationType: .read,
                            targetPath: eventPath,
                            detail: formatReadDetail(eventPath, size: size),
                            fileSize: size,
                            processName: readProc,
                            toolInfo: readTool
                        )
                        addRecord(record)
                    }
                    continue
                }

                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentInfo.agentName == "—" ? (existing.agentName ?? "—") : agentInfo.agentName,
                    operationType: .modify,
                    targetPath: eventPath,
                    detail: formatModifyDetail(eventPath, oldSize: existing.size, newSize: size),
                    fileSize: size,
                    processName: agentInfo.processName ?? existing.processName,
                    toolInfo: agentInfo.toolInfo ?? existing.toolInfo
                )
                addRecord(record)
            } else {
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentInfo.agentName,
                    operationType: .create,
                    targetPath: eventPath,
                    detail: formatCreateDetail(eventPath, size: size),
                    fileSize: size,
                    processName: agentInfo.processName,
                    toolInfo: agentInfo.toolInfo
                )
                addRecord(record)
            }

            stateLock.lock()
            fileSnapshots[eventPath] = FileSnapshot(
                path: eventPath,
                modDate: modDate,
                size: size,
                isDir: false,
                agentName: agentInfo.agentName,
                processName: agentInfo.processName,
                toolInfo: agentInfo.toolInfo
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

    // MARK: - Process Poller

    private var processPoller: Timer?
    private var lastPolledAgents: Set<String> = []

    private func startProcessPoller() {
        processPoller?.invalidate()
        processPoller = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                guard let self = self else { return }
                self.detectActiveAgents()
                self.refreshLsofData()
                DispatchQueue.main.async {
                    let currentAgents = Set(self.agentPIDMap.keys)
                    let newAgents = currentAgents.subtracting(self.lastPolledAgents)
                    if !newAgents.isEmpty {
                        let agentList = newAgents.sorted().joined(separator: ", ")
                        let record = OperationRecord(
                            id: UUID().uuidString,
                            timestamp: Date(),
                            agentName: newAgents.first ?? "Unknown",
                            operationType: .modify,
                            targetPath: "System Process",
                            detail: "🤖 Agent detected: \(agentList)",
                            fileSize: 0,
                            processName: "monitor",
                            toolInfo: "agent detection"
                        )
                        self.addRecord(record)
                    }
                    self.lastPolledAgents = currentAgents
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
                        path: fullPath, modDate: modDate, size: size, isDir: isDir.boolValue,
                        agentName: nil, processName: nil, toolInfo: nil
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
