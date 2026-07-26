import Foundation
import AppKit

private final class OperationProcessOutputCapture: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var value = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func drain(_ handle: FileHandle) {
        while true {
            let chunk = handle.readData(ofLength: 64 * 1_024)
            if chunk.isEmpty { break }
            lock.lock()
            let available = max(0, limit - value.count)
            if available > 0 { value.append(chunk.prefix(available)) }
            lock.unlock()
        }
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

class OperationMonitor: ObservableObject {
    @Published var records: [OperationRecord] = []
    @Published var isMonitoring: Bool = false
    @Published var aiSelfLearningEnabled: Bool = false
    @Published var curatedRecords: [CuratedRecord] = []
    @Published var isCurating: Bool = false
    @Published var lastCurationTime: Date?
    @Published var autoCurationInterval: Int = 3
    @Published var curationMessage: String = ""
    @Published var curationRawResponse: String = ""

    weak var localizer: Localizer?
    weak var guardFeature: AgentGuardFeature?

    private var streamRef: FSEventStreamRef?
    private var isFSEventStreamRunning = false
    private var fileSnapshots: [String: FileSnapshot] = [:]
    private var accessTimes: [String: Date] = [:]
    private var hasBuiltInitialSnapshot = false
    @Published var recordRetentionHours: Int = {
        let saved = UserDefaults.standard.integer(forKey: "operationRecordRetentionHours")
        return saved > 0 ? min(saved, 360) : 72
    }() {
        didSet {
            let clamped = min(max(recordRetentionHours, 1), 360)
            if clamped != recordRetentionHours {
                recordRetentionHours = clamped
                return
            }
            UserDefaults.standard.set(recordRetentionHours, forKey: "operationRecordRetentionHours")
            pruneRecordsToRetention()
            saveRecords()
        }
    }
    private let maxSnapshots = 10000
    private let maxStoredRecords = 3000
    private var recordsPath: String { SandboxPaths.shared.operationsPath }
    private var curatedPath: String { SandboxPaths.shared.curatedPath }
    private var snapshotsPath: String { SandboxPaths.shared.snapshotsPath }
    private var hasRestoredBookmarks: Bool = false
    @Published var needsReauthorization: Bool = false
    private var stalePaths: [String] = []
    private var authorizedWatchPaths: Set<String> = []
    private var lastCleanupTime: Date = .distantPast
    private var recordFingerprints: Set<String> = []
    private let processInfoPollInterval: TimeInterval = 15
    private let fsHealthPollInterval: TimeInterval = 30
    private let snapshotFallbackPollInterval: TimeInterval = 45
    private let lsofRefreshInterval: TimeInterval = 30

    private var allPidOpenFiles: [pid_t: Set<String>] = [:]
    private(set) var allPidCommMap: [pid_t: String] = [:]
    private(set) var allPidArgsMap: [pid_t: String] = [:]
    private(set) var ppidMap: [pid_t: pid_t] = [:]
    private var agentComms: Set<String> = []
    private var lastLsofRefresh: Date = .distantPast
    private var lastProcessInfoPoll: Date = .distantPast
    private var lastFSHealthPoll: Date = .distantPast
    private var lastSnapshotFallbackPoll: Date = .distantPast
    private var fileAgentCache: [String: (agentName: String, processName: String, toolInfo: String?, cachedAt: Date, pid: pid_t)] = [:]
    private let cacheMaxSize = 5000
    private let maxProcessArgumentLength = 2000
    private let cacheTTL: TimeInterval = 120.0

    @Published var activeAgentNames: Set<String> = []
    private(set) var agentSelfDirs: Set<String> = []
    private var selfDirDiscoveryTime: Date = .distantPast
    @Published var processSnapshots: [ProcessSnapshot] = []
    private var lastCurationRecordIndex: Int = 0
    private var observedCommandPids: Set<pid_t> = []

    let agentKeywords: [(String, [String])] = [
        ("Trae", ["trae", "trae-cn", "trae cn", "traecn", "trae-cn.app", "trae.app", "com.trae"]),
        ("Claude", ["claude", "claude code", "claude-code", "anthropic"]),
        ("Cursor", ["cursor"]),
        ("Windsurf", ["windsurf", "codeium"]),
        ("CodeBuddy", ["codebuddy", "codebuddy-cn", "codebuddy cn", "codebuddycn", "com.tencent.codebuddy"]),
        ("Doubao", ["doubao"]),
        ("Kimi", ["kimi"]),
        ("DeepSeek", ["deepseek"]),
        ("ChatGPT", ["chatgpt"]),
        ("Gemini", ["gemini"]),
        ("Copilot", ["copilot"]),
        ("Cline", ["cline"]),
        ("OpenClaw", ["openclaw", "open-claw", "open claw"]),
        ("QClaw", ["qclaw", "q-claw", "q claw"]),
        ("Hermes", ["hermes", "hermes.app", ".hermes"]),
        ("Codex", ["codex"]),
        ("Augment", ["augment"]),
        ("CodeArts", ["codearts", "huawei"]),
        ("Continue", ["continue"]),
        ("Aider", ["aider"]),
        ("Roo Code", ["roo code", "roo-code", "roocode"]),
        ("Tabby", ["tabby"]),
        ("Cody", ["cody"]),
        ("OpenHands", ["openhands", "open-hands", "open hands"]),
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
        "bash": "Shell", "zsh": "Shell", "sh": "Shell", "fish": "Shell",
        "sed": "sed", "awk": "awk", "rg": "ripgrep", "grep": "grep",
        "find": "find", "curl": "curl", "wget": "wget", "chmod": "chmod",
        "chown": "chown", "sudo": "sudo", "kill": "kill", "killall": "killall",
    ]

    private func isKnownAgentName(_ name: String) -> Bool {
        guard !name.isEmpty, name != "—", name != (localizer?.systemProcess ?? "System Process") else { return false }
        return agentKeywords.contains { displayName, _ in displayName == name }
    }

    private func isAgentProcess(comm: String, args: String) -> Bool {
        let combined = (comm + " " + args).lowercased()
        return agentKeywords.contains { _, keywords in
            keywords.contains { combined.contains($0) }
        }
    }

    private func resolvedAgentForProcess(pid: pid_t, comm: String, args: String, ppidMap: [pid_t: pid_t], argsMap: [pid_t: String], commMap: [pid_t: String]) -> String? {
        if isSystemProcess(comm) { return nil }

        let combined = (comm + " " + args).lowercased()
        for (displayName, keywords) in agentKeywords {
            if keywords.contains(where: { combined.contains($0) }) {
                return displayName
            }
        }

        var current = pid
        var depth = 0
        while depth < 10, let ppid = ppidMap[current], ppid > 0 {
            current = ppid
            depth += 1
            guard let parentComm = commMap[current] else { continue }
            let parentCombined = (parentComm + " " + (argsMap[current] ?? "")).lowercased()
            for (displayName, keywords) in agentKeywords {
                if keywords.contains(where: { parentCombined.contains($0) }) {
                    return displayName
                }
            }
        }

        return nil
    }

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
        let home = SandboxPaths.realHomeDirectory.lowercased()

        if lower.contains("/.trash/") || lower.contains("/.trash/") { return true }
        if lower.contains("/.git/") || lower.hasSuffix("/.git") { return true }
        if lower.contains("/node_modules/") || lower.hasSuffix("/node_modules") { return true }
        if lower.contains("/.build/") || lower.hasSuffix("/.build") { return true }
        if lower.contains("/deriveddata/") { return true }
        if lower.contains("/typeshed-fallback/") { return true }
        if lower.contains("/extensions/") && (
            lower.contains("/.trae-cn/") ||
            lower.contains("/.trae/") ||
            lower.contains("/.cursor/") ||
            lower.contains("/.vscode/") ||
            lower.contains("/library/application support/trae") ||
            lower.contains("/library/application support/cursor") ||
            lower.contains("/library/application support/code/")
        ) { return true }
        if lower.hasSuffix(".ds_store") { return true }
        if lower.hasSuffix("-journal") || lower.hasSuffix("-wal") || lower.hasSuffix("-shm") { return true }

        // Never let an automatically monitored parent directory (for example, an
        // authorized Home folder) recurse into TCC-protected media libraries.
        // A user can still select media files for a one-off local scan, but Agent
        // Guard does not need their Music, Movies, or Photos libraries.
        if Self.isProtectedMediaLibraryPath(expanded, home: home) { return true }
        if expanded.hasPrefix(home + "/library/") { return true }
        if expanded.hasPrefix(home + "/.sogouinput/") { return true }
        if expanded.hasPrefix(home + "/.local/share/trash/") { return true }

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

    private static func isProtectedMediaLibraryPath(_ path: String, home: String? = nil) -> Bool {
        let expanded = NSString(string: path).expandingTildeInPath.lowercased()
        let rawHome = home ?? SandboxPaths.realHomeDirectory.lowercased()
        let normalizedHome = rawHome.hasSuffix("/") ? String(rawHome.dropLast()) : rawHome

        for root in [normalizedHome + "/music", normalizedHome + "/movies"] {
            if expanded == root || expanded.hasPrefix(root + "/") {
                return true
            }
        }

        let picturesRoot = normalizedHome + "/pictures/"
        if expanded.hasPrefix(picturesRoot),
           expanded.split(separator: "/").contains(where: { $0.hasSuffix(".photoslibrary") }) {
            return true
        }
        return false
    }

    private func isLowConfidenceFallback(_ record: OperationRecord) -> Bool {
        guard let tool = record.toolInfo?.lowercased() else { return false }
        return tool.contains("active codex") ||
            tool.contains("active agent") ||
            tool.contains("process-snapshot") ||
            tool.contains("running application") ||
            tool.contains("file event observed without process attribution")
    }

    func discoverAgentSelfDirs() {
        let fm = FileManager.default
        let home = SandboxPaths.realHomeDirectory
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
        let agents = activeAgentNames
        for name in agents {
            agentNamesLower.append(name.lowercased())
        }

        for (_, keywords) in agentKeywords {
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
        let pidOpenFiles = allPidOpenFiles
        let pidArgs = allPidArgsMap
        stateLock.unlock()

        var samples: [(comm: String, args: String, paths: [String], pid: pid_t)] = []

        for (pid, files) in pidOpenFiles {
            guard let comm = allPidCommMap[pid] else { continue }
            if isSystemProcess(comm) { continue }

            let agentName = resolveAgentNameForPid(pid)
            let isKnown = agentName != nil

            if !isKnown && files.count >= 3 {
                let userFiles = files.filter { f in
                    let fl = f.lowercased()
                    return !fl.contains("/library/") && !fl.hasPrefix("/system/") && !fl.hasPrefix("/private/")
                }
                if userFiles.count >= 2 {
                    let args = pidArgs[pid] ?? ""
                    samples.append((comm, args, Array(userFiles.prefix(10)), pid))
                }
            }
        }

        return Array(samples.prefix(20))
    }

    func learnAgentKeyword(displayName: String, keywords: [String], dirs: [String]) {
        guard !displayName.isEmpty, !keywords.isEmpty else { return }
        stateLock.lock()
        for dir in dirs where !dir.isEmpty {
            agentSelfDirs.insert(dir)
        }
        selfDirDiscoveryTime = Date()
        stateLock.unlock()
        DispatchQueue.main.async { [weak self] in
            self?.activeAgentNames.insert(displayName)
        }
        print("[AIMacCleaner] AI learned new agent: \(displayName) keywords: \(keywords) dirs: \(dirs)")
    }

    func getRawDataForCuration() -> (events: [OperationRecord], snapshots: [ProcessSnapshot]) {
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

    private static func defaultWatchPaths() -> [String] {
        let home = SandboxPaths.realHomeDirectory
        var paths: [String] = [
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
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
    }

    private static func isMediaLibraryPath(_ path: String) -> Bool {
        let home = SandboxPaths.realHomeDirectory
        let mediaRoots = ["\(home)/Music", "\(home)/Movies"]
        return mediaRoots.contains { path == $0 || path.hasPrefix($0 + "/") }
    }

    private var watchPaths: [String] {
        stateLock.lock()
        let authorized = authorizedWatchPaths
        stateLock.unlock()
        let defaults = Self.defaultWatchPaths()
        return Array(Set(defaults).union(authorized))
            .filter { !Self.isMediaLibraryPath($0) }
            .sorted()
            .filter { FileManager.default.fileExists(atPath: $0) }
    }

    private var bookmarksPath: String { SandboxPaths.shared.bookmarksPath }
    private let stateLock = NSRecursiveLock()
    private let processQueue = DispatchQueue(label: "com.aimacleaner.monitor.process", qos: .utility)

    init() {
        restoreAccessFromBookmarks()
    }

    private func runCapturedProcess(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        outputLimit: Int = 8 * 1_024 * 1_024
    ) -> (status: Int32, output: Data)? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        let reader = DispatchGroup()
        let capture = OperationProcessOutputCapture(limit: outputLimit)
        task.terminationHandler = { _ in finished.signal() }

        do {
            try task.run()
            reader.enter()
            DispatchQueue.global(qos: .utility).async {
                capture.drain(pipe.fileHandleForReading)
                reader.leave()
            }
        } catch {
            return nil
        }

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            task.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                _ = kill(task.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            _ = reader.wait(timeout: .now() + 2)
            return nil
        }

        _ = reader.wait(timeout: .now() + 2)
        return (task.terminationStatus, capture.snapshot())
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
        let paths = watchPaths
        if paths.isEmpty {
            needsReauthorization = true
            return
        }
        hasBuiltInitialSnapshot = false
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.buildInitialSnapshot()
        }
        startFSEventStream()
        startProcessPoller()
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.refreshAllProcessInfo()
        }
    }

    func stop() {
        stopFSEventStream()
        processPoller?.invalidate()
        processPoller = nil
        isMonitoring = false
        saveRecords()
    }

    // MARK: - Process Info Refresh

    private func refreshAllProcessInfo() {
        guard !isRefreshingProcessInfo else { return }
        isRefreshingProcessInfo = true
        defer { isRefreshingProcessInfo = false }

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

        guard let result = runCapturedProcess(
            executable: "/bin/ps",
            arguments: ["-eo", "pid=,ppid=,comm=,args="],
            timeout: 3
        ), result.status == 0 || result.status == 1,
           let output = String(data: result.output, encoding: .utf8) else { return }

        for line in output.components(separatedBy: .newlines) {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 3,
                      let pid = pid_t(parts[0]),
                      let ppid = pid_t(parts[1]) else { continue }

                let comm = String(parts[2].prefix(500))
                let joinedArguments = parts.count >= 4 ? parts[3...].joined(separator: " ") : ""
                let args = String(joinedArguments.prefix(maxProcessArgumentLength))
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

        stateLock.lock()
        allPidCommMap = newPidCommMap
        allPidArgsMap = newPidArgsMap
        ppidMap = newPpidMap
        agentComms = newAgentComms
        stateLock.unlock()

        stateLock.lock()
        let previousActiveAgents = activeAgentNames
        stateLock.unlock()
        let agentsChanged = previousActiveAgents != newActiveAgents

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.activeAgentNames = newActiveAgents
        }

        let now = Date()
        recordNewCommandExecutions(
            currentPidCommMap: newPidCommMap,
            currentPidArgsMap: newPidArgsMap,
            currentPpidMap: newPpidMap
        )
        stateLock.lock()
        let lastLsofRefreshSnapshot = lastLsofRefresh
        stateLock.unlock()
        if agentsChanged || now.timeIntervalSince(lastLsofRefreshSnapshot) >= lsofRefreshInterval {
            refreshLsofData(pidCommMap: newPidCommMap, pidArgsMap: newPidArgsMap, ppidMap: newPpidMap)
        }

        let snapshot = newPidCommMap.map { (pid, comm) in
            ProcessSnapshot(timestamp: now, pid: pid, ppid: newPpidMap[pid] ?? 0, comm: comm, args: newPidArgsMap[pid] ?? "")
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.processSnapshots.append(contentsOf: snapshot)
            if self.processSnapshots.count > 4000 { self.processSnapshots = Array(self.processSnapshots.suffix(3200)) }
        }

        if agentsChanged || Date().timeIntervalSince(selfDirDiscoveryTime) > 30.0 {
            discoverAgentSelfDirs()
        }

        let newPids = Set(newPidCommMap.keys).subtracting(Set(currentPidComms.keys))
        if !newPids.isEmpty {
            print("[AIMacCleaner] New PIDs detected: \(newPids.count), total: \(newPidCommMap.count)")
        }
    }

    private func refreshLsofData(pidCommMap: [pid_t: String], pidArgsMap: [pid_t: String], ppidMap: [pid_t: pid_t]) {
        let processCount = pidCommMap.count
        guard processCount > 0 else { return }

        var agentProcessInfo: [pid_t: (agentName: String, comm: String, tool: String?)] = [:]
        for (pid, comm) in pidCommMap {
            if isSystemProcess(comm) { continue }
            let args = pidArgsMap[pid] ?? ""
            guard let agentName = resolvedAgentForProcess(
                pid: pid,
                comm: comm,
                args: args,
                ppidMap: ppidMap,
                argsMap: pidArgsMap,
                commMap: pidCommMap
            ) else { continue }
            agentProcessInfo[pid] = (agentName, comm, extractToolInfo(comm: comm, args: args))
        }
        if agentProcessInfo.isEmpty {
            stateLock.lock()
            allPidOpenFiles.removeAll(keepingCapacity: true)
            lastLsofRefresh = Date()
            stateLock.unlock()
            return
        }

        let pidList = agentProcessInfo.keys
            .sorted()
            .prefix(512)
            .map(String.init)
            .joined(separator: ",")
        guard let result = runCapturedProcess(
            executable: "/usr/sbin/lsof",
            arguments: ["+c", "0", "-w", "-FpcRn", "-p", pidList],
            timeout: 3,
            outputLimit: 16 * 1_024 * 1_024
        ), result.status == 0 || result.status == 1,
           let output = String(data: result.output, encoding: .utf8) else { return }

        var newPidOpenFiles: [pid_t: Set<String>] = [:]
        var currentPid: pid_t = 0

        for line in output.components(separatedBy: .newlines) {
                if line.hasPrefix("p") {
                    if let pid = pid_t(String(line.dropFirst())) {
                        currentPid = pid
                    }
                } else if line.hasPrefix("n") && currentPid != 0 {
                    guard agentProcessInfo[currentPid] != nil else { continue }
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
        stateLock.unlock()

        let now = Date()
        var newCacheEntries = 0
        for (pid, files) in newPidOpenFiles {
            guard let processInfo = agentProcessInfo[pid] else { continue }
            let procName = processInfo.comm
            let agentName = processInfo.agentName
            let tool = processInfo.tool

                for file in files {
                    if shouldSkipPath(file) { continue }
                    let key = file
                    stateLock.lock()
                    if fileAgentCache[key] == nil || fileAgentCache[key]?.pid != pid {
                        fileAgentCache[key] = (agentName, procName, tool, now, pid)
                        newCacheEntries += 1
                    }
                    stateLock.unlock()
                }
        }

        stateLock.lock()
        fileAgentCache = fileAgentCache.filter { now.timeIntervalSince($0.value.cachedAt) < cacheTTL }
        if fileAgentCache.count > cacheMaxSize {
            let sorted = fileAgentCache.sorted { $0.value.cachedAt > $1.value.cachedAt }
            fileAgentCache = Dictionary(uniqueKeysWithValues: sorted.prefix(cacheMaxSize).map { ($0.key, $0.value) })
        }
        stateLock.unlock()

        print("[AIMacCleaner] lsof: \(newPidOpenFiles.count) PIDs, \(newPidOpenFiles.values.map{$0.count}.reduce(0,+)) files, cache: \(fileAgentCache.count) entries, new: \(newCacheEntries)")
    }

    private func recordNewCommandExecutions(currentPidCommMap: [pid_t: String], currentPidArgsMap: [pid_t: String], currentPpidMap: [pid_t: pid_t]) {
        stateLock.lock()
        let alreadyObserved = observedCommandPids
        stateLock.unlock()

        let livePids = Set(currentPidCommMap.keys)
        let candidates = livePids.subtracting(alreadyObserved)
        guard !candidates.isEmpty else { return }

        var newRecords: [OperationRecord] = []
        var pidsToMark: Set<pid_t> = []

        for pid in candidates {
            guard let comm = currentPidCommMap[pid] else { continue }
            if isSystemProcess(comm) { continue }
            let args = currentPidArgsMap[pid] ?? ""
            guard let agentName = resolvedAgentForProcess(
                pid: pid,
                comm: comm,
                args: args,
                ppidMap: currentPpidMap,
                argsMap: currentPidArgsMap,
                commMap: currentPidCommMap
            ) else { continue }
            guard shouldRecordCommandExecution(pid: pid, comm: comm, args: args, ppidMap: currentPpidMap, commMap: currentPidCommMap, argsMap: currentPidArgsMap) else { continue }

            pidsToMark.insert(pid)
            let command = normalizedObservedCommand(comm: comm, args: args)
            guard !command.isEmpty else { continue }
            newRecords.append(OperationRecord(
                id: UUID().uuidString,
                timestamp: Date(),
                agentName: agentName,
                operationType: .execute,
                targetPath: command,
                detail: command,
                fileSize: 0,
                processName: (comm as NSString).lastPathComponent,
                toolInfo: extractToolInfo(comm: comm, args: args)
            ))
        }

        stateLock.lock()
        observedCommandPids.formUnion(pidsToMark)
        observedCommandPids.formIntersection(livePids)
        stateLock.unlock()

        for record in newRecords {
            addRecord(record)
        }
    }

    private func shouldRecordCommandExecution(pid: pid_t, comm: String, args: String, ppidMap: [pid_t: pid_t], commMap: [pid_t: String], argsMap: [pid_t: String]) -> Bool {
        if isAgentProcess(comm: comm, args: args) { return false }
        let base = (comm as NSString).lastPathComponent.lowercased()
        if cliToolNames[base] != nil { return true }

        var current = pid
        var depth = 0
        while depth < 10, let ppid = ppidMap[current], ppid > 0 {
            current = ppid
            depth += 1
            let parentComm = commMap[current] ?? ""
            let parentArgs = argsMap[current] ?? ""
            if isAgentProcess(comm: parentComm, args: parentArgs) {
                return true
            }
        }
        return false
    }

    private func normalizedObservedCommand(comm: String, args: String) -> String {
        let trimmedArgs = args.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedArgs.isEmpty {
            return String(trimmedArgs.prefix(500))
        }
        return (comm as NSString).lastPathComponent
    }

    // MARK: - Agent Resolution

    private func resolveAgentNameForPid(_ pid: pid_t) -> String? {
        stateLock.lock()
        let args = allPidArgsMap[pid] ?? ""
        let localPpidMap = ppidMap
        let localArgsMap = allPidArgsMap
        let localComms = allPidCommMap
        stateLock.unlock()

        guard let comm = localComms[pid] else { return nil }

        return resolvedAgentForProcess(pid: pid, comm: comm, args: args, ppidMap: localPpidMap, argsMap: localArgsMap, commMap: localComms)
    }

    private func lookupAgentForPath(_ eventPath: String) -> (agentName: String?, processName: String?, toolInfo: String?) {
        let expanded = NSString(string: eventPath).expandingTildeInPath
        let now = Date()

        stateLock.lock()
        if let cached = fileAgentCache[expanded], now.timeIntervalSince(cached.cachedAt) < cacheTTL {
            if isKnownAgentName(cached.agentName), !isSystemProcess(cached.processName) {
                stateLock.unlock()
                return (cached.agentName, cached.processName, cached.toolInfo)
            }
        }
        if let cached = fileAgentCache[eventPath], now.timeIntervalSince(cached.cachedAt) < cacheTTL {
            if isKnownAgentName(cached.agentName), !isSystemProcess(cached.processName) {
                stateLock.unlock()
                return (cached.agentName, cached.processName, cached.toolInfo)
            }
        }

        stateLock.unlock()

        return (nil, nil, nil)
    }

    private func fallbackAgentInfoForEvent(_ eventPath: String) -> (agentName: String?, processName: String?, toolInfo: String?) {
        return (nil, nil, nil)
    }

    private func workspaceActiveAgentApplications() -> [(agentName: String, processName: String)] {
        var matches: [(agentName: String, processName: String)] = []
        for app in NSWorkspace.shared.runningApplications {
            let name = app.localizedName ?? ""
            let bundleID = app.bundleIdentifier ?? ""
            let bundlePath = app.bundleURL?.path ?? ""
            let combined = "\(name) \(bundleID) \(bundlePath)".lowercased()

            for (displayName, keywords) in agentKeywords {
                if keywords.contains(where: { combined.contains($0) }) {
                    matches.append((displayName, name.isEmpty ? displayName : name))
                    break
                }
            }
        }
        return matches
    }

    private func liveActiveAgentProcesses() -> [(agentName: String, processName: String)] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["ax", "-o", "comm=,args="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let deadline = DispatchTime.now() + .seconds(2)
            DispatchQueue.global().asyncAfter(deadline: deadline) {
                if task.isRunning { task.terminate() }
            }
            task.waitUntilExit()
            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else { return [] }

            var matches: [(agentName: String, processName: String)] = []
            for line in output.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                let lower = trimmed.lowercased()
                for (displayName, keywords) in agentKeywords {
                    if keywords.contains(where: { lower.contains($0) }) {
                        let processName = trimmed.components(separatedBy: .whitespaces).first ?? displayName
                        matches.append((displayName, processName))
                        break
                    }
                }
            }
            return matches
        } catch {
            return []
        }
    }

    private func inferredActiveAgents(pidComms: [pid_t: String], pidArgs: [pid_t: String]) -> Set<String> {
        var inferred = Set<String>()
        for (pid, comm) in pidComms {
            let combined = (comm + " " + (pidArgs[pid] ?? "")).lowercased()
            for (displayName, keywords) in agentKeywords {
                if keywords.contains(where: { combined.contains($0) }) {
                    inferred.insert(displayName)
                    break
                }
            }
        }
        return inferred
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

    // MARK: - Targeted Process Monitor

    @Published var targetedFileOps: [TargetedFileOp] = []
    @Published var isTargetedMonitoring: Bool = false
    @Published var targetedAgentName: String = ""
    @Published var targetedPids: Set<pid_t> = []
    @Published var targetedErrorMessage: String = ""

    private var targetedAgentNames: [String] = []
    private var targetedMonitorTimer: Timer?
    private var targetedLsofCache: [pid_t: (comm: String, files: Set<String>, sizes: [String: Int64])] = [:]
    private let targetedMaxOps = 2000

    func startTargetedMonitoring(agentNames: [String]) {
        stopTargetedMonitoring()
        targetedAgentNames = agentNames
        let displayNames = agentNames.joined(separator: " + ")
        targetedAgentName = displayNames
        targetedErrorMessage = ""
        print("[AIMacCleaner] startTargetedMonitoring called with agentNames=\(agentNames)")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var allPids = Set<pid_t>()
            for name in agentNames {
                let pids = self.discoverPidsForAgent(name)
                allPids.formUnion(pids)
            }
            DispatchQueue.main.async {
                self.targetedPids = allPids
                self.targetedLsofCache.removeAll()
                if allPids.isEmpty {
                    self.targetedErrorMessage = self.localizer?.processNotFound ?? "No running process found, please confirm the program is running"
                    self.isTargetedMonitoring = false
                    print("[AIMacCleaner] No PIDs found for \(displayNames)")
                } else {
                    self.isTargetedMonitoring = true
                    self.targetedErrorMessage = ""
                    print("[AIMacCleaner] Targeted monitoring started for \(displayNames), found \(allPids.count) PIDs")

                    self.targetedMonitorTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                        DispatchQueue.global(qos: .userInitiated).async {
                            self?.pollTargetedProcesses()
                        }
                    }
                    DispatchQueue.global(qos: .userInitiated).async {
                        self.pollTargetedProcesses()
                    }
                }
            }
        }
    }

    func startTargetedMonitoring(agentName: String) {
        startTargetedMonitoring(agentNames: [agentName])
    }

    private func discoverPidsForAgent(_ name: String) -> Set<pid_t> {
        var keywords: [String] = []
        for (displayName, kws) in agentKeywords {
            if displayName == name {
                keywords = kws
                break
            }
        }
        if keywords.isEmpty {
            keywords = [name.lowercased()]
        }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-eo", "pid=,ppid=,comm=,args="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        var pidCommMap: [pid_t: String] = [:]
        var pidPpidMap: [pid_t: pid_t] = [:]
        var pidArgsMap: [pid_t: String] = [:]
        var rootPids: Set<pid_t> = []

        do {
            try task.run()
            task.waitUntilExit()
            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else { return [] }

            for line in output.components(separatedBy: .newlines) {
                let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 3,
                      let pid = pid_t(parts[0]),
                      let ppid = pid_t(parts[1]) else { continue }

                let comm = String(parts[2])
                let args = parts.count >= 4 ? String(parts[3...].joined(separator: " ")) : ""
                let combined = (comm + " " + args).lowercased()

                pidCommMap[pid] = comm
                pidPpidMap[pid] = ppid
                pidArgsMap[pid] = args

                for kw in keywords {
                    if combined.contains(kw) {
                        rootPids.insert(pid)
                        break
                    }
                }
            }
        } catch {
            print("[AIMacCleaner] discoverPidsForAgent ps failed: \(error)")
            return []
        }

        var allPids = Set<pid_t>(rootPids)

        var changed = true
        while changed {
            changed = false
            for (pid, ppid) in pidPpidMap {
                if allPids.contains(pid) { continue }
                if allPids.contains(ppid) {
                    allPids.insert(pid)
                    changed = true
                }
            }
        }

        return allPids
    }

    func refreshTargetedPids() {
        guard isTargetedMonitoring, !targetedAgentNames.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var newPids = Set<pid_t>()
            for name in self.targetedAgentNames {
                newPids.formUnion(self.discoverPidsForAgent(name))
            }
            DispatchQueue.main.async {
                let added = newPids.subtracting(self.targetedPids)
                let removed = self.targetedPids.subtracting(newPids)
                if !added.isEmpty || !removed.isEmpty {
                    print("[AIMacCleaner] PID refresh for \(self.targetedAgentName): +\(added.count) -\(removed.count), total \(newPids.count)")
                }
                self.targetedPids = newPids
            }
        }
    }

    func stopTargetedMonitoring() {
        isTargetedMonitoring = false
        targetedMonitorTimer?.invalidate()
        targetedMonitorTimer = nil
        targetedLsofCache.removeAll()
    }

    func clearTargetedOps() {
        targetedFileOps.removeAll()
    }

    private var pidRefreshTimer: Timer?

    private func pollTargetedProcesses() {
        let pids = targetedPids
        guard !pids.isEmpty else { return }

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["+c", "0", "-w", "-FpcRn", "-u", "\(getuid())"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let deadline = DispatchTime.now() + .seconds(4)
            DispatchQueue.global().asyncAfter(deadline: deadline) { task.terminate() }
            task.waitUntilExit()

            guard let data = try? pipe.fileHandleForReading.readToEnd(),
                  let output = String(data: data, encoding: .utf8) else { return }

            var currentFiles: [pid_t: (comm: String, files: Set<String>, sizes: [String: Int64])] = [:]
            var currentPid: pid_t = 0
            var currentComm: String = ""

            for line in output.components(separatedBy: .newlines) {
                if line.hasPrefix("p") {
                    if let pid = pid_t(String(line.dropFirst())) {
                        currentPid = pid
                    }
                } else if line.hasPrefix("c") {
                    currentComm = String(line.dropFirst())
                } else if line.hasPrefix("n") && currentPid != 0 {
                    let path = String(line.dropFirst())
                    guard path.hasPrefix("/"),
                          !path.hasPrefix("/dev/"),
                          !path.hasPrefix("/System/"),
                          !path.hasPrefix("/private/var/folders/") else { continue }
                    if !pids.contains(currentPid) { continue }

                    var fileSize: Int64 = 0
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: path) {
                        fileSize = (attrs[.size] as? Int64) ?? 0
                    }

                    if var entry = currentFiles[currentPid] {
                        entry.files.insert(path)
                        entry.sizes[path] = fileSize
                        currentFiles[currentPid] = entry
                    } else {
                        currentFiles[currentPid] = (comm: currentComm, files: [path], sizes: [path: fileSize])
                    }
                }
            }

            let now = Date()
            var newOps: [TargetedFileOp] = []

            for (pid, current) in currentFiles {
                guard let prev = targetedLsofCache[pid] else {
                    for path in current.files {
                        let sz = current.sizes[path] ?? 0
                        newOps.append(TargetedFileOp(id: UUID().uuidString, timestamp: now, processComm: current.comm, processPid: pid, targetPath: path, opType: localizer?.opOpen ?? "Open", fileSize: sz))
                    }
                    continue
                }

                for path in current.files.subtracting(prev.files) {
                    let sz = current.sizes[path] ?? 0
                    newOps.append(TargetedFileOp(id: UUID().uuidString, timestamp: now, processComm: current.comm, processPid: pid, targetPath: path, opType: localizer?.opOpen ?? "Open", fileSize: sz))
                }

                for path in prev.files.subtracting(current.files) {
                    newOps.append(TargetedFileOp(id: UUID().uuidString, timestamp: now, processComm: current.comm, processPid: pid, targetPath: path, opType: localizer?.opClose ?? "Close", fileSize: 0))
                }

                for path in current.files.intersection(prev.files) {
                    let curSize = current.sizes[path] ?? 0
                    let prevSize = prev.sizes[path] ?? 0
                    if curSize != prevSize {
                        let op = curSize > prevSize ? (localizer?.opEdit ?? "Modify") : (localizer?.fileTruncated ?? "Truncated")
                        newOps.append(TargetedFileOp(id: UUID().uuidString, timestamp: now, processComm: current.comm, processPid: pid, targetPath: path, opType: op, fileSize: curSize))
                    }
                }
            }

            for (pid, prev) in targetedLsofCache where currentFiles[pid] == nil {
                for path in prev.files {
                    newOps.append(TargetedFileOp(id: UUID().uuidString, timestamp: now, processComm: prev.comm, processPid: pid, targetPath: path, opType: localizer?.opClose ?? "Close", fileSize: 0))
                }
            }

            targetedLsofCache = currentFiles

            if !newOps.isEmpty {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.targetedFileOps.insert(contentsOf: newOps.reversed(), at: 0)
                    if self.targetedFileOps.count > self.targetedMaxOps {
                        self.targetedFileOps = Array(self.targetedFileOps.prefix(self.targetedMaxOps))
                    }
                }
            }
        } catch {
            print("[AIMacCleaner] pollTargetedProcesses failed: \(error)")
        }
    }

    // MARK: - Process Poller

    private var processPoller: Timer?
    private let refreshLock = NSLock()
    private var _isRefreshingProcessInfo = false
    private var isRefreshingProcessInfo: Bool {
        get { refreshLock.lock(); defer { refreshLock.unlock() }; return _isRefreshingProcessInfo }
        set { refreshLock.lock(); _isRefreshingProcessInfo = newValue; refreshLock.unlock() }
    }

    private func startProcessPoller() {
        processPoller?.invalidate()
        let now = Date()
        lastProcessInfoPoll = now
        lastFSHealthPoll = now
        lastSnapshotFallbackPoll = now
        processPoller = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = Date()
            if now.timeIntervalSince(self.lastProcessInfoPoll) >= self.processInfoPollInterval {
                self.lastProcessInfoPoll = now
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    self?.refreshAllProcessInfo()
                }
            }
            if now.timeIntervalSince(self.lastFSHealthPoll) >= self.fsHealthPollInterval {
                self.lastFSHealthPoll = now
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    self?.checkFSEventStreamHealth()
                }
            }
            if !self.isFSEventStreamRunning,
               now.timeIntervalSince(self.lastSnapshotFallbackPoll) >= self.snapshotFallbackPollInterval {
                self.lastSnapshotFallbackPoll = now
                DispatchQueue.global(qos: .utility).async { [weak self] in
                    self?.pollSnapshotChanges()
                }
            }
        }
    }

    private func checkFSEventStreamHealth() {
        guard isMonitoring else { return }
        if streamRef == nil || !isFSEventStreamRunning {
            print("[AIMacCleaner] FSEventStream is nil, restarting on main queue...")
            DispatchQueue.main.async { [weak self] in
                self?.stopFSEventStream()
                self?.startFSEventStream()
            }
        }
    }

    // MARK: - FSEvents

    private func startFSEventStream() {
        guard !watchPaths.isEmpty else { return }

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

            monitor.processEvents(paths: pathList)
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        streamRef = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            watchPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            flags
        )

        if let stream = streamRef {
            FSEventStreamSetDispatchQueue(stream, processQueue)
            let started = FSEventStreamStart(stream)
            isFSEventStreamRunning = started
            print("[AIMacCleaner] FSEventStream started: \(started), paths: \(watchPaths.count)")
        } else {
            isFSEventStreamRunning = false
            print("[AIMacCleaner] FSEventStream creation FAILED!")
        }
    }

    private func stopFSEventStream() {
        isFSEventStreamRunning = false
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

            var agentInfo = lookupAgentForPath(eventPath)
            if agentInfo.agentName == nil {
                agentInfo = fallbackAgentInfoForEvent(eventPath)
            }

            guard exists else {
                guard let agentName = agentInfo.agentName else { continue }
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentName,
                    operationType: .delete,
                    targetPath: eventPath,
                    detail: localizer?.fileDeleted ?? "File deleted",
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
                        guard let readAgent = agentInfo.agentName ?? existing.agentName, isKnownAgentName(readAgent) else { continue }
                        let readProc = agentInfo.processName ?? existing.processName
                        let readTool = agentInfo.toolInfo ?? existing.toolInfo
                        let record = OperationRecord(
                            id: UUID().uuidString,
                            timestamp: Date(),
                            agentName: readAgent,
                            operationType: .read,
                            targetPath: eventPath,
                            detail: "\(localizer?.fileRead ?? "File read") (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))",
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
                    agentName: agentInfo.agentName ?? existing.agentName ?? "—",
                    operationType: .modify,
                    targetPath: eventPath,
                    detail: formatModifyDetail(eventPath, oldSize: existing.size, newSize: size),
                    fileSize: size,
                    processName: agentInfo.processName ?? existing.processName,
                    toolInfo: agentInfo.toolInfo ?? existing.toolInfo
                )
                if isKnownAgentName(record.agentName) || record.agentName == "Unattributed Agent" {
                    addRecord(record)
                }
            } else {
                guard let agentName = agentInfo.agentName else { continue }
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentName,
                    operationType: .create,
                    targetPath: eventPath,
                    detail: "\(localizer?.fileCreated ?? "File created") (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))",
                    fileSize: size,
                    processName: agentInfo.processName,
                    toolInfo: agentInfo.toolInfo
                )
                addRecord(record)
            }

            let bestAgent: String
            let bestProc: String?
            let bestTool: String?
            if let agentName = agentInfo.agentName, isKnownAgentName(agentName) {
                bestAgent = agentName
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
                if shouldSkipPath(fullPath) {
                    enumerator?.skipDescendants()
                    continue
                }
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
        hasBuiltInitialSnapshot = true
    }

    private func pollSnapshotChanges() {
        guard isMonitoring, hasBuiltInitialSnapshot else { return }
        let fm = FileManager.default
        var scanned = 0
        let maxScan = maxSnapshots

        for dirPath in watchPaths {
            guard scanned < maxScan else { break }
            guard let enumerator = fm.enumerator(atPath: dirPath) else { continue }
            while let file = enumerator.nextObject() as? String, scanned < maxScan {
                let fullPath = "\(dirPath)/\(file)"
                scanned += 1
                if shouldSkipPath(fullPath) {
                    enumerator.skipDescendants()
                    continue
                }

                let fileName = (fullPath as NSString).lastPathComponent
                if fileName.hasPrefix(".") || fileName.hasPrefix("._") { continue }

                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { continue }
                guard let attrs = try? fm.attributesOfItem(atPath: fullPath) else { continue }

                let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                let modDate = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

                stateLock.lock()
                let existing = fileSnapshots[fullPath]
                stateLock.unlock()

                let agentInfo = fallbackAgentInfoForEvent(fullPath)
                if let existing = existing {
                    let changed = abs(modDate - existing.modDate) > 1.0 || size != existing.size
                    guard changed else { continue }

                    let record = OperationRecord(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        agentName: agentInfo.agentName ?? existing.agentName ?? "Unattributed Agent",
                        operationType: .modify,
                        targetPath: fullPath,
                        detail: formatModifyDetail(fullPath, oldSize: existing.size, newSize: size),
                        fileSize: size,
                        processName: agentInfo.processName ?? existing.processName,
                        toolInfo: agentInfo.toolInfo ?? existing.toolInfo
                    )
                    addRecord(record)
                } else {
                    let record = OperationRecord(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        agentName: agentInfo.agentName ?? "Unattributed Agent",
                        operationType: .create,
                        targetPath: fullPath,
                        detail: "\(localizer?.fileCreated ?? "File created") (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))",
                        fileSize: size,
                        processName: agentInfo.processName,
                        toolInfo: agentInfo.toolInfo
                    )
                    addRecord(record)
                }

                let bestAgent: String?
                let bestProc: String?
                let bestTool: String?
                if let agentName = agentInfo.agentName, isKnownAgentName(agentName) {
                    bestAgent = agentName
                    bestProc = agentInfo.processName
                    bestTool = agentInfo.toolInfo
                } else {
                    bestAgent = existing?.agentName
                    bestProc = existing?.processName
                    bestTool = existing?.toolInfo
                }

                stateLock.lock()
                fileSnapshots[fullPath] = FileSnapshot(
                    path: fullPath,
                    modDate: modDate,
                    size: size,
                    isDir: false,
                    agentName: bestAgent,
                    processName: bestProc,
                    toolInfo: bestTool,
                    pid: existing?.pid ?? 0
                )
                accessTimes[fullPath] = Date()
                stateLock.unlock()
            }
        }
    }

    // MARK: - Detail Formatting

    private func formatModifyDetail(_ path: String, oldSize: Int64, newSize: Int64) -> String {
        let diff = newSize - oldSize
        let diffStr: String
        if diff > 0 {
            diffStr = "+\(ByteCountFormatter.string(fromByteCount: diff, countStyle: .file))"
        } else if diff < 0 {
            diffStr = "-\(ByteCountFormatter.string(fromByteCount: abs(diff), countStyle: .file))"
        } else {
            diffStr = localizer?.contentChanged ?? "Content changed"
        }
        return "\(localizer?.fileModified ?? "File modified") (\(diffStr))"
    }

    // MARK: - Record Management

    private var pendingRecords: [OperationRecord] = []
    private var flushWorkItem: DispatchWorkItem?
    private var saveRecordsWorkItem: DispatchWorkItem?

    private func recordFingerprint(_ record: OperationRecord) -> String {
        let bucket = Int(record.timestamp.timeIntervalSince1970 / 5.0)
        var parts = [
            record.agentName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            record.operationType.rawValue,
            record.targetPath.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "\(bucket)"
        ]
        if record.operationType == .execute {
            parts.append(record.detail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
        return parts.joined(separator: "|")
    }

    private func recordsWithinRetention(_ input: [OperationRecord]) -> [OperationRecord] {
        let cutoff = Date().addingTimeInterval(-Double(recordRetentionHours) * 3600)
        var seen: Set<String> = []
        var seenIDs: Set<String> = []
        let retained = input
            .filter { $0.timestamp >= cutoff }
            .sorted { $0.timestamp > $1.timestamp }
            .filter { record in
                guard !seenIDs.contains(record.id) else { return false }
                seenIDs.insert(record.id)
                let key = recordFingerprint(record)
                guard !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
        return Array(retained.prefix(maxStoredRecords))
    }

    private func rebuildRecordFingerprints() {
        stateLock.lock()
        defer { stateLock.unlock() }
        recordFingerprints = Set(records.map { recordFingerprint($0) })
    }

    private func pruneRecordsToRetention() {
        stateLock.lock()
        defer { stateLock.unlock() }
        records = recordsWithinRetention(records)
        rebuildRecordFingerprints()
    }

    func addRecord(_ record: OperationRecord) {
        if shouldSkipPath(record.targetPath) || isLowConfidenceFallback(record) {
            return
        }

        let agentName = record.agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if agentName.isEmpty ||
            agentName == "—" ||
            agentName == "Unattributed Agent" ||
            agentName == (localizer?.systemProcess ?? "System Process") ||
            agentName.localizedCaseInsensitiveContains("system process") {
            return
        }

        if let gf = guardFeature {
            let command = record.detail.isEmpty ? record.targetPath : record.detail
            let agentName = record.agentName
            DispatchQueue.main.async {
                if record.operationType == .execute {
                    let _ = gf.recordObservedCommand(command: command, agentName: agentName)
                }
            }
        }

        let key = recordFingerprint(record)
        stateLock.lock()
        if recordFingerprints.contains(key) || pendingRecords.contains(where: { recordFingerprint($0) == key }) {
            stateLock.unlock()
            return
        }
        recordFingerprints.insert(key)
        pendingRecords.append(record)
        stateLock.unlock()

        flushWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.flushRecords()
        }
        flushWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: item)
    }

    private func flushRecords() {
        stateLock.lock()
        let batch = pendingRecords
        pendingRecords = []
        guard !batch.isEmpty else {
            stateLock.unlock()
            return
        }
        records.insert(contentsOf: batch.reversed(), at: 0)
        pruneRecordsToRetention()
        stateLock.unlock()
        scheduleRecordsSave()
    }

    func clearRecords() {
        flushWorkItem?.cancel()
        flushWorkItem = nil
        saveRecordsWorkItem?.cancel()
        saveRecordsWorkItem = nil
        stateLock.lock()
        pendingRecords.removeAll()
        recordFingerprints.removeAll()
        stateLock.unlock()
        records.removeAll()
        saveRecords()
    }

    func normalizeHistoricalRecords(_ transform: (OperationRecord) -> OperationRecord) {
        stateLock.lock()
        var changed = false
        let normalized = records.map { record in
            let updated = transform(record)
            if updated != record {
                changed = true
            }
            return updated
        }
        guard changed else {
            stateLock.unlock()
            return
        }
        records = recordsWithinRetention(normalized)
        rebuildRecordFingerprints()
        stateLock.unlock()
        saveRecords()
    }

    @discardableResult
    func removeHistoricalRecords(where shouldRemove: (OperationRecord) -> Bool) -> Int {
        stateLock.lock()
        let previousCount = records.count
        records.removeAll(where: shouldRemove)
        let removedCount = previousCount - records.count
        if removedCount > 0 {
            rebuildRecordFingerprints()
        }
        stateLock.unlock()
        if removedCount > 0 {
            saveRecords()
        }
        return removedCount
    }

    func mergeHistoricalRecords(_ historicalRecords: [OperationRecord]) {
        guard !historicalRecords.isEmpty else { return }
        stateLock.lock()
        if recordFingerprints.isEmpty, !records.isEmpty {
            rebuildRecordFingerprints()
        }
        let recordIndexByID = Dictionary(uniqueKeysWithValues: records.enumerated().map { ($0.element.id, $0.offset) })
        var additions: [OperationRecord] = []
        var additionIndexByID: [String: Int] = [:]
        var replacedExistingRecord = false
        for record in historicalRecords {
            if let existingIndex = recordIndexByID[record.id] {
                if record.timestamp >= records[existingIndex].timestamp,
                   record != records[existingIndex] {
                    records[existingIndex] = record
                    replacedExistingRecord = true
                }
                continue
            }
            if let additionIndex = additionIndexByID[record.id] {
                if record.timestamp >= additions[additionIndex].timestamp {
                    additions[additionIndex] = record
                }
                continue
            }
            let key = recordFingerprint(record)
            guard !recordFingerprints.contains(key) else { continue }
            recordFingerprints.insert(key)
            additionIndexByID[record.id] = additions.count
            additions.append(record)
        }
        guard !additions.isEmpty || replacedExistingRecord else {
            stateLock.unlock()
            return
        }
        records.append(contentsOf: additions)
        records = recordsWithinRetention(records)
        rebuildRecordFingerprints()
        stateLock.unlock()
        scheduleRecordsSave(delay: 1.0)
    }

    private func loadRecords() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: recordsPath)),
              let decoded = try? JSONDecoder().decode([OperationRecord].self, from: data) else { return }
        let cleaned = decoded.filter { !shouldSkipPath($0.targetPath) && !isLowConfidenceFallback($0) }
        stateLock.lock()
        records = recordsWithinRetention(cleaned)
        rebuildRecordFingerprints()
        stateLock.unlock()
        if records.count != decoded.count {
            saveRecords()
        }
    }

    func saveRecords() {
        saveRecordsWorkItem?.cancel()
        saveRecordsWorkItem = nil
        writeRecordsToDisk()
    }

    private func scheduleRecordsSave(delay: TimeInterval = 2.0) {
        saveRecordsWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.writeRecordsToDisk()
        }
        saveRecordsWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func writeRecordsToDisk() {
        stateLock.lock()
        let currentRecords = records
        stateLock.unlock()
        guard let data = try? JSONEncoder().encode(currentRecords) else { return }
        try? data.write(to: URL(fileURLWithPath: recordsPath))
    }

    private func restoreAccessFromBookmarks() {
        if SandboxPaths.isDirectDistribution && !SandboxPaths.isSandboxed {
            stateLock.lock()
            authorizedWatchPaths = Set(Self.defaultWatchPaths())
            stalePaths = []
            stateLock.unlock()
            hasRestoredBookmarks = true
            needsReauthorization = false
            return
        }

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: bookmarksPath)),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
            hasRestoredBookmarks = true
            needsReauthorization = true
            return
        }
        var stale: [String] = []
        var restored: Set<String> = []
        var refreshedBookmarks = bookmarks
        for (path, bookmark) in bookmarks {
            do {
                var isStale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                guard url.startAccessingSecurityScopedResource() else {
                    stale.append(path)
                    continue
                }
                restored.insert(url.path)
                if isStale {
                    do {
                        let refreshed = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                        refreshedBookmarks.removeValue(forKey: path)
                        refreshedBookmarks[url.path] = refreshed
                    } catch {
                        stale.append(url.path)
                    }
                }
            } catch {
                stale.append(path)
            }
        }
        stateLock.lock()
        authorizedWatchPaths = restored
        stateLock.unlock()
        if refreshedBookmarks.keys.sorted() != bookmarks.keys.sorted(),
           let encoded = try? JSONEncoder().encode(refreshedBookmarks) {
            try? encoded.write(to: URL(fileURLWithPath: bookmarksPath))
        }
        if !stale.isEmpty {
            stateLock.lock()
            stalePaths = stale
            stateLock.unlock()
            print("[AIMacCleaner] Stale bookmarks detected for \(stale.count) paths: \(stale)")
            DispatchQueue.main.async {
                self.needsReauthorization = true
            }
        }
        hasRestoredBookmarks = true
        needsReauthorization = restored.isEmpty || !stale.isEmpty || hasExistingAgentDataOutsideAuthorizedPaths(restored)
    }

    private func hasExistingAgentDataOutsideAuthorizedPaths(_ roots: Set<String>) -> Bool {
        let home = SandboxPaths.realHomeDirectory
        let agentDataDirs = [
            "\(home)/.codex",
            "\(home)/.claude",
            "\(home)/.config/claude",
            "\(home)/.grok",
            "\(home)/.cursor",
            "\(home)/.continue",
            "\(home)/.aider",
            "\(home)/.gemini"
        ]
        return agentDataDirs.contains { dir in
            !roots.contains { root in
                let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
                let normalizedDir = URL(fileURLWithPath: dir).standardizedFileURL.path
                return normalizedDir == normalizedRoot || normalizedDir.hasPrefix(normalizedRoot + "/")
            }
        }
    }

    deinit {
        stopFSEventStream()
        processPoller?.invalidate()
        saveRecordsWorkItem?.cancel()
        writeRecordsToDisk()
    }

    func requestAccessForStalePaths() {
        let home = SandboxPaths.realHomeDirectory
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: home)
        panel.prompt = localizer?.reauthorize ?? "Re-authorize"
        panel.message = localizer?.selectMonitorDirs ?? "Choose directories to monitor. Hold ⌘ to select multiple folders such as Desktop, Documents, or Downloads."

        guard panel.runModal() == .OK, !panel.urls.isEmpty else { return }

        let selectedURLs = panel.urls
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.needsReauthorization = false
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var newBookmarks: [String: Data] = [:]
            for url in selectedURLs {
                let accessing = url.startAccessingSecurityScopedResource()
                print("[AIMacCleaner] startAccessingSecurityScopedResource for \(url.path): \(accessing)")
                do {
                    let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    newBookmarks[url.path] = bookmark
                } catch {
                    print("[AIMacCleaner] Failed to create bookmark for \(url.path): \(error)")
                }
            }

            if !newBookmarks.isEmpty {
                for (path, data) in newBookmarks {
                    self.mergeBookmark(path: path, data: data)
                }
                self.stateLock.lock()
                self.authorizedWatchPaths.formUnion(newBookmarks.keys)
                self.stalePaths = []
                self.stateLock.unlock()
            }

            DispatchQueue.main.async {
                self.needsReauthorization = newBookmarks.isEmpty
                self.stopFSEventStream()
                self.startFSEventStream()
                print("[AIMacCleaner] Reauthorization complete, FSEventStream restarted")
            }
        }
    }

    private func mergeBookmark(path: String, data: Data) {
        var allBookmarks: [String: Data] = [:]
        if let existingData = try? Data(contentsOf: URL(fileURLWithPath: bookmarksPath)),
           let existing = try? JSONDecoder().decode([String: Data].self, from: existingData) {
            allBookmarks = existing
        }
        allBookmarks[path] = data
        if let encoded = try? JSONEncoder().encode(allBookmarks) {
            try? encoded.write(to: URL(fileURLWithPath: bookmarksPath))
        }
    }
}
