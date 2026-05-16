import Foundation
import AppKit

class OperationMonitor: ObservableObject {
    @Published var records: [OperationRecord] = []
    @Published var isMonitoring: Bool = false
    @Published var aiSelfLearningEnabled: Bool = false
    @Published var curatedRecords: [CuratedRecord] = []
    @Published var isCurating: Bool = false
    @Published var lastCurationTime: Date?
    @Published var autoCurationInterval: Int = 3

    private var streamRef: FSEventStreamRef?
    private var fileSnapshots: [String: FileSnapshot] = [:]
    private var accessTimes: [String: Date] = [:]
    private let maxRecords = 2000
    private let maxSnapshots = 10000
    private let recordsPath = NSHomeDirectory() + "/.aimaccleaner_operations_v2.json"
    private let curatedPath = NSHomeDirectory() + "/.aimaccleaner_curated.json"
    private let snapshotsPath = NSHomeDirectory() + "/.aimaccleaner_snapshots.json"
    private var hasRestoredBookmarks: Bool = false
    private var lastCleanupTime: Date = .distantPast

    private var allPidOpenFiles: [pid_t: Set<String>] = [:]
    private var allPidCommMap: [pid_t: String] = [:]
    private var allPidArgsMap: [pid_t: String] = [:]
    private var ppidMap: [pid_t: pid_t] = [:]
    private var agentComms: Set<String> = []
    private var lastLsofRefresh: Date = .distantPast
    private var fileAgentCache: [String: (agentName: String, processName: String, toolInfo: String?, cachedAt: Date, pid: pid_t)] = [:]
    private let cacheMaxSize = 5000
    private let cacheTTL: TimeInterval = 15.0

    private var activeAgentNames: Set<String> = []
    private var agentSelfDirs: Set<String> = []
    private var selfDirDiscoveryTime: Date = .distantPast
    private var processSnapshots: [ProcessSnapshot] = []
    private var lastCurationRecordIndex: Int = 0

    let agentKeywords: [(String, [String])] = [
        ("Trae", ["trae-cn", "trae cn", "traecn", "trae-cn.app"]),
        ("Claude", ["claude"]),
        ("Cursor", ["cursor"]),
        ("Windsurf", ["windsurf", "codeium"]),
        ("CodeBuddy", ["codebuddy-cn", "codebuddy cn", "codebuddycn"]),
        ("Doubao", ["doubao"]),
        ("Kimi", ["kimi"]),
        ("DeepSeek", ["deepseek"]),
        ("ChatGPT", ["chatgpt"]),
        ("Gemini", ["gemini"]),
        ("Copilot", ["copilot"]),
        ("Cline", ["cline"]),
        ("Hermes", ["hermes"]),
        ("Codex", ["codex"]),
        ("Augment", ["augment"]),
        ("CodeArts", ["codearts", "huawei"]),
    ]

    private let systemProcessBlacklist: Set<String> = [
        "cfprefsd", "ContextStoreAgent", "coreservicesd", "coreauthd",
        "mds", "mds_stores", "fseventsd", "spotlight", "mdworker",
        "mdworker_shared", "mdwrite", "mdimporter",
        "launchd", "kernel_task", "syslogd", "distnoted", "notifyd",
        "WindowServer", "Finder", "Dock", "SystemUIServer",
        "usermanagerd", "secinitd", "trustd", "syspolicyd",
        "sandboxd", "containermanagerd", "cfprefsd.xpc",
        "filecoordinationd", "bird", "cloudd", "cloudpaird",
        "nsurlsessiond", "nsurlstoraged", "photolibraryd",
        "assetsd", "mediaserverd", "coreaudiod",
        "com.apple.", "diagnostics_agent",
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
        "rsync": "rsync", "cp": "cp", "mv": "mv", "rm": "rm",
        "zip": "zip", "tar": "tar", "mkdir": "mkdir",
    ]

    private func isSystemProcess(_ comm: String) -> Bool {
        let lower = comm.lowercased()
        for prefix in systemProcessBlacklist {
            if prefix.hasSuffix(".") {
                if lower.hasPrefix(prefix) { return true }
            } else {
                if lower == prefix || lower.hasPrefix(prefix + ".") || lower == (prefix as NSString).lastPathComponent.lowercased() { return true }
            }
        }
        return false
    }

    private func shouldSkipPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        let expanded = NSString(string: path).expandingTildeInPath.lowercased()
        let home = NSHomeDirectory().lowercased()

        if lower.contains("/.trash/") || lower.contains("/.trash/") { return true }
        if lower.hasSuffix(".ds_store") { return true }
        if lower.hasSuffix("-journal") || lower.hasSuffix("-wal") || lower.hasSuffix("-shm") { return true }

        if expanded.hasPrefix(home + "/library/") { return true }

        stateLock.lock()
        let dirs = agentSelfDirs
        stateLock.unlock()
        for dir in dirs {
            if expanded.hasPrefix(dir.lowercased() + "/") || expanded == dir.lowercased() {
                return true
            }
        }

        return false
    }

    private func discoverAgentSelfDirs() {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        var discovered: Set<String> = []

        let searchBases: [(String, (String) -> Bool)] = [
            ("\(home)/Library/Application Support", { _ in true }),
            ("\(home)/Library/Caches", { _ in true }),
            ("\(home)/Library/Preferences", { path in path.hasSuffix(".plist") }),
            ("\(home)/Library/Logs", { _ in true }),
            ("\(home)/Library/Containers", { _ in true }),
            ("\(home)/Library/Group Containers", { _ in true }),
            ("\(home)/Library/Saved Application State", { path in path.hasSuffix(".savedState") }),
            (home, { path in
                let name = (path as NSString).lastPathComponent
                return name.hasPrefix(".")
            }),
        ]

        var agentNamesLower: [String] = []
        stateLock.lock()
        let agents = activeAgentNames
        stateLock.unlock()
        for name in agents {
            agentNamesLower.append(name.lowercased())
        }

        for (name, keywords) in agentKeywords {
            for kw in keywords {
                agentNamesLower.append(kw)
            }
        }

        let agentLowerSet = Set(agentNamesLower)

        for (basePath, filter) in searchBases {
            guard fm.fileExists(atPath: basePath) else { continue }
            guard let contents = try? fm.contentsOfDirectory(atPath: basePath) else { continue }

            for item in contents {
                let fullPath = "\(basePath)/\(item)"
                let itemLower = item.lowercased()

                var matched = false
                for agentLower in agentLowerSet {
                    if itemLower.contains(agentLower) {
                        matched = true
                        break
                    }
                }
                guard matched else { continue }
                guard filter(fullPath) else { continue }

                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    discovered.insert(fullPath)
                }
            }
        }

        stateLock.lock()
        agentSelfDirs = discovered
        selfDirDiscoveryTime = Date()
        stateLock.unlock()
        print("[AIMacCleaner] discoverAgentSelfDirs: found \(discovered.count) agent-owned dirs for \(Array(agents))")
    }

    func addDiscoveredAgentDir(_ dir: String) {
        stateLock.lock()
        agentSelfDirs.insert(dir)
        stateLock.unlock()
        print("[AIMacCleaner] AI learned agent dir: \(dir)")
    }

    func getUnknownAgentSamples() -> [(comm: String, args: String, paths: [String], pid: pid_t)] {
        stateLock.lock()
        defer { stateLock.unlock() }

        var samples: [(comm: String, args: String, paths: [String], pid: pid_t)] = []
        let knownNames = activeAgentNames.union(["systemd", "kernel_task"])

        for (pid, files) in allPidOpenFiles {
            guard let comm = allPidCommMap[pid] else { continue }
            if isSystemProcess(comm) { continue }

            let agentName = resolveAgentNameForPid(pid)
            let isKnown = activeAgentNames.contains(agentName) || agentName == comm || cliToolNames[(comm as NSString).lastPathComponent.lowercased()] != nil

            if !isKnown && files.count >= 3 {
                let userFiles = files.filter { f in
                    let fl = f.lowercased()
                    return !fl.contains("/library/") && !fl.hasPrefix("/system/") && !fl.hasPrefix("/private/")
                }
                if userFiles.count >= 2 {
                    let args = allPidArgsMap[pid] ?? ""
                    samples.append((comm, args, Array(userFiles.prefix(10)), pid))
                }
            }
        }

        return Array(samples.prefix(20))
    }

    func learnAgentKeyword(displayName: String, keywords: [String], dirs: [String]) {
        guard !displayName.isEmpty, !keywords.isEmpty else { return }
        stateLock.lock()
        activeAgentNames.insert(displayName)
        for dir in dirs where !dir.isEmpty {
            agentSelfDirs.insert(dir)
        }
        selfDirDiscoveryTime = Date()
        stateLock.unlock()
        print("[AIMacCleaner] AI learned new agent: \(displayName) keywords: \(keywords) dirs: \(dirs)")
    }

    func getRawDataForCuration() -> (events: [OperationRecord], snapshots: [ProcessSnapshot]) {
        stateLock.lock()
        defer { stateLock.unlock() }
        let startIndex = lastCurationRecordIndex
        lastCurationRecordIndex = records.count
        return (Array(records[startIndex..<records.count]), processSnapshots)
    }

    func saveCuratedRecords(_ newRecords: [CuratedRecord]) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.curatedRecords = newRecords + self.curatedRecords
            if self.curatedRecords.count > 1000 {
                self.curatedRecords = Array(self.curatedRecords.prefix(1000))
            }
            self.lastCurationTime = Date()
            self.isCurating = false
            self.saveCurated()
        }
    }

    func loadCurated() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: curatedPath)),
              let decoded = try? JSONDecoder().decode([CuratedRecord].self, from: data) else { return }
        curatedRecords = decoded
    }

    private func saveCurated() {
        stateLock.lock()
        let cr = curatedRecords
        stateLock.unlock()
        guard let data = try? JSONEncoder().encode(cr) else { return }
        try? data.write(to: URL(fileURLWithPath: curatedPath))
    }

    func clearCuratedRecords() {
        curatedRecords.removeAll()
        saveCurated()
    }

    struct FileSnapshot: Codable {
        let path: String
        let modDate: TimeInterval
        let size: Int64
        let isDir: Bool
        let agentName: String?
        let processName: String?
        let toolInfo: String?
        let pid: pid_t
    }

    private let watchPaths: [String] = {
        let home = NSHomeDirectory()
        var paths: [String] = [
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Movies",
            "\(home)/Music",
            "\(home)/Pictures",
        ]

        let fm = FileManager.default
        let commonDirs = ["Projects", "Dev", "Developer", "Code", "workspace", "src", "repo", "repos"]
        for dir in commonDirs {
            let p = "\(home)/\(dir)"
            if fm.fileExists(atPath: p) {
                paths.append(p)
            }
        }

        if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
            let parent = desktop.deletingLastPathComponent().path
            for item in (try? fm.contentsOfDirectory(atPath: parent)) ?? [] {
                if item.hasPrefix(".") || item == "Desktop" || item == "Documents" ||
                   item == "Downloads" || item == "Library" || item == "Movies" ||
                   item == "Music" || item == "Pictures" || item == "Public" ||
                   item == "Applications" { continue }
                let full = "\(parent)/\(item)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                    paths.append(full)
                }
            }
        }

        return Array(Set(paths)).filter { fm.fileExists(atPath: $0) }
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

        print("[AIMacCleaner] === OperationMonitor starting ===")
        print("[AIMacCleaner] Watch paths: \(watchPaths)")

        if !hasRestoredBookmarks {
            restoreAccessFromBookmarks()
        }
        buildInitialSnapshot()
        startFSEventStream()
        startProcessPoller()
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshAllProcessInfo()
        }
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.saveBookmarks()
        }
    }

    func stop() {
        stopFSEventStream()
        processPoller?.invalidate()
        processPoller = nil
        isMonitoring = false
    }

    // MARK: - Process Info Refresh

    private func refreshAllProcessInfo() {
        stateLock.lock()
        let currentPidComms = allPidCommMap
        stateLock.unlock()

        var newPidCommMap: [pid_t: String] = [:]
        var newPidArgsMap: [pid_t: String] = [:]
        var newPpidMap: [pid_t: pid_t] = [:]
        var newAgentComms: Set<String> = []
        var newActiveAgents: Set<String> = []

        for (_, keywords) in agentKeywords {
            for kw in keywords {
                newAgentComms.insert(kw)
            }
        }

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

                for (displayName, keywords) in agentKeywords {
                    for kw in keywords {
                        if lowerAll.contains(kw) {
                            newActiveAgents.insert(displayName)
                            break
                        }
                    }
                }
            }
        } catch {
            print("[AIMacCleaner] ps failed: \(error)")
        }

        stateLock.lock()
        allPidCommMap = newPidCommMap
        allPidArgsMap = newPidArgsMap
        ppidMap = newPpidMap
        agentComms = newAgentComms
        let agentsChanged = activeAgentNames != newActiveAgents
        activeAgentNames = newActiveAgents
        stateLock.unlock()

        refreshLsofData()

        let now = Date()
        let snapshot = newPidCommMap.map { (pid, comm) in
            ProcessSnapshot(timestamp: now, pid: pid, ppid: newPpidMap[pid] ?? 0, comm: comm, args: newPidArgsMap[pid] ?? "")
        }
        stateLock.lock()
        processSnapshots.append(contentsOf: snapshot)
        if processSnapshots.count > 10000 { processSnapshots = Array(processSnapshots.suffix(8000)) }
        stateLock.unlock()

        if agentsChanged || Date().timeIntervalSince(selfDirDiscoveryTime) > 30.0 {
            discoverAgentSelfDirs()
        }

        let newPids = Set(newPidCommMap.keys).subtracting(Set(currentPidComms.keys))
        if !newPids.isEmpty {
            print("[AIMacCleaner] New PIDs detected: \(newPids.count), total: \(newPidCommMap.count)")
        }
    }

    private func refreshLsofData() {
        stateLock.lock()
        let pidCommMap = allPidCommMap
        stateLock.unlock()

        let processCount = pidCommMap.count
        guard processCount > 0 else { return }

        let uid = getuid()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["+c", "0", "-w", "-FpcRn", "-u", "\(uid)"]
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
                    guard path.hasPrefix("/"),
                          !path.hasPrefix("/dev/"),
                          !path.hasPrefix("/private/var/folders/"),
                          !path.hasPrefix("/System/"),
                          !path.contains(".app/Contents/"),
                          !path.hasSuffix(".nib"),
                          !path.hasSuffix(".strings"),
                          !path.hasSuffix(".plist"),
                          !shouldSkipPath(path) else { continue }

                    newPidOpenFiles[currentPid, default: []].insert(path)
                    let expanded = NSString(string: path).expandingTildeInPath
                    if expanded != path {
                        newPidOpenFiles[currentPid, default: []].insert(expanded)
                    }
                }
            }

            stateLock.lock()
            allPidOpenFiles = newPidOpenFiles
            lastLsofRefresh = Date()

            let now = Date()
            var newCacheEntries = 0
            for (pid, files) in newPidOpenFiles {
                let procName = allPidCommMap[pid] ?? ""
                if isSystemProcess(procName) { continue }

                let agentName = resolveAgentNameForPid(pid)
                let args = allPidArgsMap[pid] ?? ""
                let tool = extractToolInfo(comm: procName, args: args)

                for file in files {
                    if shouldSkipPath(file) { continue }
                    let key = file
                    if fileAgentCache[key] == nil || fileAgentCache[key]?.pid != pid {
                        fileAgentCache[key] = (agentName, procName, tool, now, pid)
                        newCacheEntries += 1
                    }
                }
            }

            fileAgentCache = fileAgentCache.filter { now.timeIntervalSince($0.value.cachedAt) < cacheTTL }
            if fileAgentCache.count > cacheMaxSize {
                let sorted = fileAgentCache.sorted { $0.value.cachedAt > $1.value.cachedAt }
                fileAgentCache = Dictionary(uniqueKeysWithValues: sorted.prefix(cacheMaxSize).map { ($0.key, $0.value) })
            }

            stateLock.unlock()

            print("[AIMacCleaner] lsof: \(newPidOpenFiles.count) PIDs, \(newPidOpenFiles.values.map{$0.count}.reduce(0,+)) files, cache: \(fileAgentCache.count) entries, new: \(newCacheEntries)")
        } catch {
            print("[AIMacCleaner] lsof failed: \(error)")
        }
    }

    // MARK: - Agent Resolution

    private func resolveAgentNameForPid(_ pid: pid_t) -> String {
        stateLock.lock()
        let comm = allPidCommMap[pid]
        let args = allPidArgsMap[pid] ?? ""
        let localPpidMap = ppidMap
        let localComms = allPidCommMap
        stateLock.unlock()

        guard let comm = comm else { return "PID:\(pid)" }

        if isSystemProcess(comm) { return "系统进程" }

        let combined = (comm + " " + args).lowercased()
        for (displayName, keywords) in agentKeywords {
            for kw in keywords {
                if combined.contains(kw) {
                    return displayName
                }
            }
        }

        let commBase = (comm as NSString).lastPathComponent.lowercased()
        if let toolName = cliToolNames[commBase] {
            return toolName
        }

        var current = pid
        var depth = 0
        while depth < 10 {
            if let ppid = localPpidMap[current], ppid > 0 {
                current = ppid
                depth += 1
                if let parentComm = localComms[current] {
                    let parentCombined = (parentComm + " " + (allPidArgsMap[current] ?? "")).lowercased()
                    for (displayName, keywords) in agentKeywords {
                        for kw in keywords {
                            if parentCombined.contains(kw) {
                                return displayName
                            }
                        }
                    }
                }
            } else {
                break
            }
        }

        return (comm as NSString).lastPathComponent
    }

    private func lookupAgentForPath(_ eventPath: String) -> (agentName: String, processName: String?, toolInfo: String?) {
        let expanded = NSString(string: eventPath).expandingTildeInPath
        let now = Date()

        stateLock.lock()
        if let cached = fileAgentCache[expanded], now.timeIntervalSince(cached.cachedAt) < cacheTTL {
            if !isSystemProcess(cached.processName) {
                stateLock.unlock()
                return (cached.agentName, cached.processName, cached.toolInfo)
            }
        }
        if let cached = fileAgentCache[eventPath], now.timeIntervalSince(cached.cachedAt) < cacheTTL {
            if !isSystemProcess(cached.processName) {
                stateLock.unlock()
                return (cached.agentName, cached.processName, cached.toolInfo)
            }
        }
        stateLock.unlock()

        if abs(now.timeIntervalSince(lastLsofRefresh)) > 3.0 {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.refreshAllProcessInfo()
            }
        }

        return ("—", nil, nil)
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

    // MARK: - Process Poller

    private var processPoller: Timer?

    private func startProcessPoller() {
        processPoller?.invalidate()
        processPoller = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.refreshAllProcessInfo()
            }
        }
    }

    // MARK: - FSEvents

    private func startFSEventStream() {
        guard !watchPaths.isEmpty else { return }

        let weakRef = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let monitor = Unmanaged<OperationMonitor>.fromOpaque(info).takeUnretainedValue()

            var pathList: [String] = []
            let cfArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            for i in 0..<CFArrayGetCount(cfArray) {
                let raw = CFArrayGetValueAtIndex(cfArray, i)
                let cfStr = Unmanaged<CFString>.fromOpaque(raw!).takeUnretainedValue()
                pathList.append(cfStr as String)
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

        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            watchPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            flags
        )

        if let stream = streamRef {
            FSEventStreamSetDispatchQueue(stream, processQueue)
            let started = FSEventStreamStart(stream)
            print("[AIMacCleaner] FSEventStream started: \(started), paths: \(watchPaths.count)")
        } else {
            print("[AIMacCleaner] FSEventStream creation FAILED!")
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

            if shouldSkipPath(eventPath) { continue }

            let fileName = (eventPath as NSString).lastPathComponent
            if fileName.hasPrefix(".") || fileName.hasPrefix("._") { continue }

            let expanded = NSString(string: eventPath).expandingTildeInPath

            let exists = fm.fileExists(atPath: expanded)

            let agentInfo = lookupAgentForPath(eventPath)

            if agentInfo.agentName == "系统进程" { continue }

            guard exists else {
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentInfo.agentName,
                    operationType: .delete,
                    targetPath: eventPath,
                    detail: "删除: \((eventPath as NSString).lastPathComponent)",
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
                let changed = abs(modDate - existing.modDate) > 1.0 || size != existing.size

                if !changed {
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
                            detail: "读取: \((eventPath as NSString).lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))",
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
                    detail: "创建: \((eventPath as NSString).lastPathComponent) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))",
                    fileSize: size,
                    processName: agentInfo.processName,
                    toolInfo: agentInfo.toolInfo
                )
                addRecord(record)
            }

            let bestAgent: String
            let bestProc: String?
            let bestTool: String?
            if agentInfo.agentName != "—" {
                bestAgent = agentInfo.agentName
                bestProc = agentInfo.processName
                bestTool = agentInfo.toolInfo
            } else if let existingAgent = existing?.agentName, existingAgent != "—" {
                bestAgent = existingAgent
                bestProc = existing?.processName
                bestTool = existing?.toolInfo
            } else {
                bestAgent = "—"
                bestProc = nil
                bestTool = nil
            }

            stateLock.lock()
            fileSnapshots[eventPath] = FileSnapshot(
                path: eventPath,
                modDate: modDate,
                size: size,
                isDir: false,
                agentName: bestAgent,
                processName: bestProc,
                toolInfo: bestTool,
                pid: existing?.pid ?? 0
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
                        agentName: nil, processName: nil, toolInfo: nil, pid: 0
                    )
                    stateLock.unlock()
                    totalCount += 1
                }
            }
        }
        print("[AIMacCleaner] Initial snapshot: \(totalCount) files")
    }

    // MARK: - Detail Formatting

    private func formatModifyDetail(_ path: String, oldSize: Int64, newSize: Int64) -> String {
        let fileName = (path as NSString).lastPathComponent
        let diff = newSize - oldSize
        let diffStr: String
        if diff > 0 {
            diffStr = "+\(ByteCountFormatter.string(fromByteCount: diff, countStyle: .file))"
        } else if diff < 0 {
            diffStr = "-\(ByteCountFormatter.string(fromByteCount: abs(diff), countStyle: .file))"
        } else {
            diffStr = "内容已更改"
        }
        return "修改: \(fileName) (\(diffStr))"
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
