import Foundation
import SQLite3

struct AgentDataSource {
    let agentName: String
    let searchPaths: [String]
    let filePattern: String
    let isCustom: Bool
    let parser: (URL, String) -> [AgentOpRecord]
    let isVSCodeType: Bool

    init(agentName: String, searchPaths: [String], filePattern: String = ".jsonl", isCustom: Bool = false, isVSCodeType: Bool = false, parser: @escaping (URL, String) -> [AgentOpRecord]) {
        self.agentName = agentName
        self.searchPaths = searchPaths
        self.filePattern = filePattern
        self.isCustom = isCustom
        self.isVSCodeType = isVSCodeType
        self.parser = parser
    }
}

class AgentSessionScanner: ObservableObject {
    @Published var discoveredAgents: [DiscoveredAgent] = []
    @Published var opRecords: [AgentOpRecord] = []
    @Published var isScanning: Bool = false
    @Published var scanError: String = ""

    weak var localizer: Localizer?

    private let fileManager = FileManager.default
    private var dataSources: [AgentDataSource] = []
    private var isScanningAgents = false
    private var isScanningOps = false
    private let codexRolloutMetadataReadLimit = 256 * 1024
    private let codexRolloutMetadataLineLimit = 250
    private let operationFilesPerSourceLimit = 80
    private let codexOperationTailReadLimit = 512 * 1024
    private let codexOperationLineLimit = 900
    private let genericOperationTailReadLimit = 4 * 1024 * 1024
    private let structuredSessionReadLimit = 8 * 1024 * 1024

    init() {
        registerBuiltInSources()
    }

    func searchJSONLDirs(forAgentName name: String, bundlePath: String?) -> [String] {
        let home = SandboxPaths.realHomeDirectory
        let lower = name.lowercased().replacingOccurrences(of: " ", with: "")
        let displayName = name
        let candidates = [
            home + "/.\(lower)",
            home + "/.\(lower)/sessions",
            home + "/.\(lower)/projects",
            home + "/Library/Application Support/\(displayName)",
            home + "/Library/Application Support/\(displayName)/User",
            home + "/Library/Application Support/\(displayName)/User/globalStorage",
            home + "/Library/Application Support/\(displayName)/User/workspaceStorage",
            home + "/Library/Application Support/\(displayName) CN",
            home + "/Library/Application Support/\(displayName) CN/User",
            home + "/Library/Application Support/\(displayName) CN/User/globalStorage",
            home + "/Library/Application Support/\(displayName) CN/User/workspaceStorage",
            home + "/.config/\(lower)",
            home + "/.config/\(lower)/sessions",
            home + "/.local/share/\(lower)",
            home + "/Library/Application Support/\(displayName)/User/globalStorage/\(lower)",
        ]

        var searchDirs = candidates
        if let bp = bundlePath {
            searchDirs.append(bp)
            searchDirs.append(bp + "/Contents/Resources")
            if bp.hasSuffix(".app") {
                searchDirs.append(bp.replacingOccurrences(of: ".app", with: ""))
            }
        }

        var foundDirs: [String] = []
        for dir in searchDirs {
            guard fileManager.fileExists(atPath: dir) else { continue }
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: dir, isDirectory: &isDir)
            guard isDir.boolValue else { continue }
            if hasSessionFiles(in: dir, depth: 5) {
                foundDirs.append(dir)
            }
        }

        if foundDirs.isEmpty {
            let broadPaths = [
                home + "/Library/Application Support",
                home,
            ]
            for broad in broadPaths {
                guard let contents = try? fileManager.contentsOfDirectory(atPath: broad) else { continue }
                for item in contents {
                    if item.lowercased().contains(lower) {
                        let fullPath = broad + "/" + item
                        var isDir: ObjCBool = false
                        fileManager.fileExists(atPath: fullPath, isDirectory: &isDir)
                        guard isDir.boolValue else { continue }
                        if hasSessionFiles(in: fullPath, depth: 5) {
                            foundDirs.append(fullPath)
                        }
                    }
                }
            }
        }

        if foundDirs.isEmpty {
            let deepPaths = [
                home + "/Library/Application Support",
            ]
            for deep in deepPaths {
                guard let contents = try? fileManager.contentsOfDirectory(atPath: deep) else { continue }
                for item in contents {
                    let fullPath = deep + "/" + item
                    var isDir: ObjCBool = false
                    fileManager.fileExists(atPath: fullPath, isDirectory: &isDir)
                    guard isDir.boolValue else { continue }
                    if hasSessionFiles(in: fullPath, depth: 6) {
                        let itemName = item.lowercased()
                        if itemName.contains(lower) || lower.contains(itemName) {
                            foundDirs.append(fullPath)
                        }
                    }
                }
            }
        }

        return foundDirs
    }

    private func hasSessionFiles(in dir: String, depth: Int) -> Bool {
        guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil) else { return false }
        for case let url as URL in enumerator {
            let relPath = String(url.path.dropFirst(dir.count + 1))
            let components = relPath.components(separatedBy: "/")
            if components.count > depth {
                enumerator.skipDescendants()
                continue
            }
            let lastComponent = url.lastPathComponent
            if lastComponent == ".git" {
                enumerator.skipDescendants()
                continue
            }
            if lastComponent.hasPrefix(".") && lastComponent != ".jsonl" {
                enumerator.skipDescendants()
                continue
            }
            let ext = url.pathExtension
            if ext == "jsonl" || ext == "sqlite" || ext == "md" || ext == "vscdb" || ext == "db" {
                return true
            }
            if ext == "json" && (url.path.contains("file-changes") || url.path.contains("session") || url.path.contains("events") || url.path.contains("conversation") || url.path.contains("trajectory") || url.lastPathComponent == "entries.json") {
                return true
            }
        }
        return false
    }

    func registerBuiltInSources() {
        registerClaudeCode()
        registerCodex()
        registerGrok()
        registerQwenCode()
        registerCursorWorkspaces()
        registerKimi()
        registerMiniMax()
        registerAider()
        registerCline()
        registerGeminiCLI()
        registerOpenCode()
        registerOpenClaw()
        registerHermes()
        registerCrewAI()
        registerAutoGen()
        registerOpenHands()
        registerDify()
        registerMetaGPT()
        registerCAMEL()
        registerDeerFlow()
        registerHuginn()
        registerBrowserUse()
        registerTrae()
        registerGenericAutoDiscovery()
    }

    func registerSource(_ source: AgentDataSource) {
        dataSources.removeAll { $0.agentName == source.agentName && $0.isCustom == source.isCustom }
        dataSources.append(source)
    }

    func removeDataSource(forAgentName name: String) {
        dataSources.removeAll { $0.agentName == name && $0.isCustom }
    }

    func scanAllAgents() {
        guard !isScanningAgents else {
            print("[AgentSessionScanner] scanAllAgents already in progress, skipping")
            return
        }

        isScanningAgents = true
        isScanning = true
        scanError = ""

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            defer {
                DispatchQueue.main.async {
                    self.isScanningAgents = false
                    self.isScanning = false
                }
            }

            var merged: [String: DiscoveredAgent] = [:]

            for source in self.dataSources {
                if source.agentName == "Codex" {
                    if let codexAgent = self.discoverCodexAgent() {
                        merged[codexAgent.name] = codexAgent
                    }
                    continue
                }

                let home = SandboxPaths.realHomeDirectory
                let expandedPaths = source.searchPaths.map { $0.replacingOccurrences(of: "~", with: home) }

                var sourceHasResults = false

                for basePath in expandedPaths {
                    guard self.fileManager.fileExists(atPath: basePath) else { continue }
                    var isDir: ObjCBool = false
                    self.fileManager.fileExists(atPath: basePath, isDirectory: &isDir)
                    if !isDir.boolValue {
                        sourceHasResults = true
                        let modifiedAt = (try? self.fileManager.attributesOfItem(atPath: basePath)[.modificationDate]) as? Date
                        let existing = merged[source.agentName]
                        merged[source.agentName] = DiscoveredAgent(
                            id: source.agentName + "_" + basePath,
                            name: source.agentName,
                            sessionCount: 1 + (existing?.sessionCount ?? 0),
                            latestActivity: [modifiedAt, existing?.latestActivity].compactMap { $0 }.max(),
                            projectDirs: existing?.projectDirs ?? [],
                            dataPath: basePath
                        )
                        continue
                    }

                    let depthLimit = 8
                    var sessionCount = 0
                    var latestDate: Date?
                    var projectDirs = Set<String>()
                    var fileCount = 0

                    guard let enumerator = self.fileManager.enumerator(at: URL(fileURLWithPath: basePath), includingPropertiesForKeys: nil) else { continue }

                    for case let itemURL as URL in enumerator {
                        fileCount += 1
                        if fileCount > 5000 { break }

                        let path = itemURL.path
                        let relPath = String(path.dropFirst(basePath.count + 1))
                        let components = relPath.components(separatedBy: "/")

                        if components.count > depthLimit {
                            enumerator.skipDescendants()
                            continue
                        }

                        let lastComponent = itemURL.lastPathComponent
                        if lastComponent == ".git" {
                            sessionCount += 1
                            if let attrs = try? self.fileManager.attributesOfItem(atPath: path),
                               let modDate = attrs[.modificationDate] as? Date {
                                if latestDate == nil || modDate > latestDate! { latestDate = modDate }
                            }
                            enumerator.skipDescendants()
                            continue
                        }
                        if lastComponent.hasPrefix(".") && lastComponent != ".jsonl" {
                            enumerator.skipDescendants()
                            continue
                        }

                        if self.isSessionCandidate(itemURL, pattern: source.filePattern) {
                            sessionCount += 1
                            if let attrs = try? self.fileManager.attributesOfItem(atPath: path),
                               let modDate = attrs[.modificationDate] as? Date {
                                if latestDate == nil || modDate > latestDate! { latestDate = modDate }
                            }
                            let dirPart = components.first ?? ""
                            if dirPart.hasPrefix("-") || dirPart.contains("project") {
                                let realPath = dirPart.replacingOccurrences(of: "-", with: "/").dropFirst()
                                projectDirs.insert("/" + realPath)
                            }
                        }
                    }

                    if sessionCount > 0 {
                        sourceHasResults = true
                        let existing = merged[source.agentName]
                        let combined = DiscoveredAgent(
                            id: source.agentName + "_" + basePath,
                            name: source.agentName,
                            sessionCount: sessionCount + (existing?.sessionCount ?? 0),
                            latestActivity: [latestDate, existing?.latestActivity].compactMap { $0 }.max(),
                            projectDirs: projectDirs.union(Set(existing?.projectDirs ?? [])).sorted(),
                            dataPath: basePath
                        )
                        merged[source.agentName] = combined
                    }
                }

                if !sourceHasResults && source.isCustom {
                    let existingPaths = expandedPaths.filter { self.fileManager.fileExists(atPath: $0) }
                    let dataPath = existingPaths.first ?? expandedPaths.first ?? ""
                    let existing = merged[source.agentName]
                    merged[source.agentName] = DiscoveredAgent(
                        id: source.agentName + "_custom",
                        name: source.agentName,
                        sessionCount: existing?.sessionCount ?? 0,
                        latestActivity: existing?.latestActivity,
                        projectDirs: existing?.projectDirs ?? [],
                        dataPath: dataPath
                    )
                }
            }

            let results = Array(merged.values).sorted { ($0.latestActivity ?? .distantPast) > ($1.latestActivity ?? .distantPast) }

            DispatchQueue.main.async {
                self.discoveredAgents = results
                print("[AgentSessionScanner] Found \(results.count) agents with sessions")
            }
        }
    }

    func scanAgentOps(agentName: String) {
        DispatchQueue.main.async {
            self.opRecords = []
            self.scanError = ""
            self.isScanning = true
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard !self.isScanningOps else {
                print("[AgentSessionScanner] scanAgentOps already in progress, skipping")
                DispatchQueue.main.async {
                    self.scanError = self.localizer?.t(
                        "另一个 Agent 审计仍在解析，请稍后重试。",
                        en: "Another agent audit is still parsing. Try again in a moment."
                    ) ?? "Another agent audit is still parsing. Try again in a moment."
                    self.isScanning = false
                }
                return
            }
            self.isScanningOps = true
            defer {
                self.isScanningOps = false
                DispatchQueue.main.async { self.isScanning = false }
            }

            DispatchQueue.main.async { self.scanError = "" }

            var allRecords: [AgentOpRecord] = []
            let home = SandboxPaths.realHomeDirectory
            var candidateCount = 0
            var parsedFileCount = 0

            let matchingSources = self.dataSources.filter { $0.agentName == agentName }
            print("[AgentSessionScanner] scanAgentOps: \(agentName), found \(matchingSources.count) data sources")

            for source in matchingSources {
                let expandedPaths = source.searchPaths.map { $0.replacingOccurrences(of: "~", with: home) }
                print("[AgentSessionScanner] source paths: \(expandedPaths)")

                for basePath in expandedPaths {
                    guard self.fileManager.fileExists(atPath: basePath) else {
                        print("[AgentSessionScanner] path not found: \(basePath)")
                        continue
                    }
                    var isDir: ObjCBool = false
                    self.fileManager.fileExists(atPath: basePath, isDirectory: &isDir)
                    if isDir.boolValue {
                        let urls = self.findSessionFiles(in: basePath, pattern: source.filePattern)
                        candidateCount += urls.count
                        print("[AgentSessionScanner] found \(urls.count) session files in \(basePath)")
                        for url in urls {
                            let records = source.parser(url, agentName)
                            if !records.isEmpty { parsedFileCount += 1 }
                            allRecords.append(contentsOf: records)
                        }
                    } else {
                        candidateCount += 1
                        let url = URL(fileURLWithPath: basePath)
                        let records = source.parser(url, agentName)
                        if !records.isEmpty { parsedFileCount += 1 }
                        allRecords.append(contentsOf: records)
                    }
                }
            }

            allRecords.sort { $0.timestamp > $1.timestamp }
            var seenRecordIds = Set<String>()
            allRecords = allRecords.filter { seenRecordIds.insert($0.id).inserted }
            if allRecords.count > 10000 { allRecords = Array(allRecords.prefix(10000)) }

            if allRecords.isEmpty, agentName == "Codex" {
                allRecords.append(AgentOpRecord(
                    id: "codex_authorization_required",
                    agentName: "Codex",
                    sessionId: "sandbox",
                    projectDir: home + "/.codex",
                    timestamp: Date(),
                    toolName: "authorization",
                    targetPath: home + "/.codex",
                    opType: "Action",
                    detail: "Codex data exists, but the App Store sandbox requires user authorization before reading ~/.codex session logs."
                ))
            }

            DispatchQueue.main.async {
                self.opRecords = allRecords
                if allRecords.isEmpty {
                    if matchingSources.isEmpty {
                        self.scanError = self.localizer?.t(
                            "未找到 \(agentName) 的审计数据源。请重新扫描或手动添加数据目录。",
                            en: "No audit data source is registered for \(agentName). Rescan or add its data folder manually."
                        ) ?? "No audit data source is registered for \(agentName)."
                    } else if candidateCount == 0 {
                        self.scanError = self.localizer?.t(
                            "已找到 \(agentName)，但数据目录中没有受支持的会话文件。",
                            en: "\(agentName) was found, but its data folders contain no supported session files."
                        ) ?? "No supported session files found."
                    } else {
                        self.scanError = self.localizer?.t(
                            "检查了 \(candidateCount) 个会话文件，但没有解析到可审计操作。可能是数据格式尚未支持或目录权限不足。",
                            en: "Checked \(candidateCount) session files but parsed no auditable operations. The format may be unsupported or folder access may be restricted."
                        ) ?? "No auditable operations parsed."
                    }
                } else {
                    self.scanError = self.localizer?.t(
                        "已从 \(parsedFileCount)/\(candidateCount) 个会话文件解析 \(allRecords.count) 条审计记录。",
                        en: "Parsed \(allRecords.count) audit records from \(parsedFileCount)/\(candidateCount) session files."
                    ) ?? "Parsed \(allRecords.count) audit records."
                }
                print("[AgentSessionScanner] Found \(allRecords.count) op records for \(agentName)")
            }
        }
    }

    func collectAllAgentOps(limit: Int = 10000, filesPerSourceLimit: Int? = nil) -> [AgentOpRecord] {
        var allRecords: [AgentOpRecord] = []
        let fileLimit = max(1, filesPerSourceLimit ?? operationFilesPerSourceLimit)
        let sourceRecordLimit = max(100, min(limit, (limit / max(1, min(dataSources.count, 8))) * 2))
        for source in dataSources {
            allRecords.append(contentsOf: collectAgentOps(
                for: source,
                fileLimit: fileLimit,
                recordLimit: sourceRecordLimit
            ))
            if allRecords.count > limit * 2 {
                allRecords.sort { $0.timestamp > $1.timestamp }
                allRecords = Array(allRecords.prefix(limit))
            }
        }
        allRecords.sort { $0.timestamp > $1.timestamp }
        if allRecords.count > limit {
            allRecords = Array(allRecords.prefix(limit))
        }
        return allRecords
    }

    private func collectAgentOps(for source: AgentDataSource, fileLimit: Int, recordLimit: Int) -> [AgentOpRecord] {
        let home = SandboxPaths.realHomeDirectory
        let expandedPaths = source.searchPaths.map { $0.replacingOccurrences(of: "~", with: home) }
        var records: [AgentOpRecord] = []

        for basePath in expandedPaths {
            guard fileManager.fileExists(atPath: basePath) else { continue }
            var isDir: ObjCBool = false
            fileManager.fileExists(atPath: basePath, isDirectory: &isDir)
            if isDir.boolValue {
                let urls = recentSessionFiles(in: basePath, pattern: source.filePattern, limit: fileLimit)
                for url in urls {
                    records.append(contentsOf: autoreleasepool {
                        source.parser(url, source.agentName)
                    })
                    if records.count > recordLimit * 2 {
                        records.sort { $0.timestamp > $1.timestamp }
                        records = Array(records.prefix(recordLimit))
                    }
                }
            } else {
                records.append(contentsOf: autoreleasepool {
                    source.parser(URL(fileURLWithPath: basePath), source.agentName)
                })
            }
        }

        records.sort { $0.timestamp > $1.timestamp }
        return Array(records.prefix(recordLimit))
    }

    private func recentSessionFiles(in dir: String, pattern: String, limit: Int) -> [URL] {
        let urls = findSessionFiles(in: dir, pattern: pattern)
        let dated = urls.map { (url: $0, modifiedAt: modificationDate(for: $0)) }
        let sorted = dated.sorted { $0.modifiedAt > $1.modifiedAt }.map(\.url)
        guard sorted.count > limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    private func modificationDate(for url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private func findSessionFiles(in dir: String, pattern: String) -> [URL] {
        var results: [URL] = []
        guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil) else { return results }
        for case let url as URL in enumerator {
            let relPath = String(url.path.dropFirst(dir.count + 1))
            let depth = relPath.components(separatedBy: "/").count
            if depth > 8 {
                enumerator.skipDescendants()
                continue
            }
            let lastComponent = url.lastPathComponent
            if lastComponent == ".git" {
                if pattern == ".git" { results.append(url) }
                enumerator.skipDescendants()
                continue
            }
            if lastComponent.hasPrefix(".") && lastComponent != ".jsonl" {
                enumerator.skipDescendants()
                continue
            }
            if isSessionCandidate(url, pattern: pattern) {
                results.append(url)
            }
        }
        return results
    }

    private func isSessionCandidate(_ url: URL, pattern: String) -> Bool {
        let ext = url.pathExtension.lowercased()
        let normalizedPattern = pattern.lowercased()
        if normalizedPattern == ".git" {
            return url.lastPathComponent == ".git"
        }
        if normalizedPattern == "*" {
            if ["jsonl", "vscdb", "sqlite", "db", "md"].contains(ext) { return true }
            return ext == "json" && isLikelySessionJSON(url)
        }
        if normalizedPattern.hasPrefix(".") {
            return ext == String(normalizedPattern.dropFirst())
        }
        return url.path.lowercased().hasSuffix(normalizedPattern)
    }

    private func isLikelySessionJSON(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let name = url.lastPathComponent.lowercased()
        return path.contains("file-changes")
            || path.contains("session")
            || path.contains("events")
            || path.contains("conversation")
            || path.contains("trajectory")
            || path.contains("history")
            || name == "entries.json"
    }

    private func discoverCodexAgent() -> DiscoveredAgent? {
        let home = SandboxPaths.realHomeDirectory
        let codexDir = home + "/.codex"
        let sessionsDir = codexDir + "/sessions"
        guard fileManager.fileExists(atPath: codexDir) else { return nil }

        let rolloutFiles = fileManager.fileExists(atPath: sessionsDir) ? findSessionFiles(in: sessionsDir, pattern: ".jsonl") : []
        var activityCount = 0
        var latestActivity: Date?
        var projectDirs = Set<String>()

        for url in rolloutFiles {
            let summary = summarizeCodexRollout(url: url)
            activityCount += max(summary.activityCount, 1)
            if let latest = summary.latestActivity, latestActivity == nil || latest > latestActivity! {
                latestActivity = latest
            }
            projectDirs.formUnion(summary.projectDirs)
        }

        let stateSummary = summarizeCodexStateDB(path: codexDir + "/state_5.sqlite")
        activityCount = max(activityCount, stateSummary.threadCount)
        if let latest = stateSummary.latestActivity, latestActivity == nil || latest > latestActivity! {
            latestActivity = latest
        }
        projectDirs.formUnion(stateSummary.projectDirs)

        let logsSummary = summarizeCodexLogsDB(path: codexDir + "/logs_2.sqlite")
        activityCount = max(activityCount, logsSummary.activityCount)
        if let latest = logsSummary.latestActivity, latestActivity == nil || latest > latestActivity! {
            latestActivity = latest
        }

        return DiscoveredAgent(
            id: "Codex_\(codexDir)",
            name: "Codex",
            sessionCount: max(activityCount, rolloutFiles.count, 1),
            latestActivity: latestActivity,
            projectDirs: Array(projectDirs).sorted(),
            dataPath: codexDir
        )
    }

    private func summarizeCodexRollout(url: URL) -> (activityCount: Int, latestActivity: Date?, projectDirs: Set<String>) {
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
        var activityCount = fileSize > 0 ? 1 : 0
        var latestActivity = attrs?[.modificationDate] as? Date
        var projectDirs = Set<String>()

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return (activityCount, latestActivity, projectDirs)
        }
        defer { try? handle.close() }

        let data = (try? handle.read(upToCount: codexRolloutMetadataReadLimit)) ?? Data()
        let content = String(decoding: data, as: UTF8.self)

        for line in content.split(separator: "\n", omittingEmptySubsequences: true).prefix(codexRolloutMetadataLineLimit) {
            guard let data = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let ts = parseTimestamp(json["timestamp"] as? String), latestActivity == nil || ts > latestActivity! {
                latestActivity = ts
            }

            let type = json["type"] as? String ?? ""
            if type == "session_meta", let payload = json["payload"] as? [String: Any], let cwd = payload["cwd"] as? String, !cwd.isEmpty {
                projectDirs.insert(cwd)
            } else if type == "turn_context", let payload = json["payload"] as? [String: Any], let cwd = payload["cwd"] as? String, !cwd.isEmpty {
                projectDirs.insert(cwd)
            }

            if type == "response_item", let payload = json["payload"] as? [String: Any] {
                let payloadType = payload["type"] as? String ?? ""
                let role = payload["role"] as? String ?? ""
                if payloadType == "function_call" || role == "user" || role == "assistant" {
                    activityCount = max(activityCount, 1)
                }
            } else if type == "event_msg", let payload = json["payload"] as? [String: Any] {
                let eventType = payload["type"] as? String ?? ""
                if eventType == "user_message" || eventType == "agent_message" {
                    activityCount = max(activityCount, 1)
                }
            }
        }

        return (activityCount, latestActivity, projectDirs)
    }

    private func summarizeCodexStateDB(path: String) -> (threadCount: Int, latestActivity: Date?, projectDirs: Set<String>) {
        guard fileManager.fileExists(atPath: path), fileManager.isReadableFile(atPath: path) else { return (0, nil, []) }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return (0, nil, []) }
        defer { sqlite3_close(db) }

        var threadCount = 0
        var latestActivity: Date?
        var projectDirs = Set<String>()
        let sql = "SELECT cwd, updated_at, updated_at_ms FROM threads ORDER BY updated_at DESC"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return (0, nil, []) }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            threadCount += 1
            if let cwdPtr = sqlite3_column_text(stmt, 0) {
                let cwd = String(cString: cwdPtr)
                if !cwd.isEmpty { projectDirs.insert(cwd) }
            }

            let updatedAt = sqlite3_column_int64(stmt, 1)
            let updatedAtMs = sqlite3_column_int64(stmt, 2)
            let interval = updatedAtMs > 0 ? TimeInterval(updatedAtMs) / 1000.0 : TimeInterval(updatedAt)
            if interval > 0 {
                let date = Date(timeIntervalSince1970: interval)
                if latestActivity == nil || date > latestActivity! { latestActivity = date }
            }
        }

        return (threadCount, latestActivity, projectDirs)
    }

    private func summarizeCodexLogsDB(path: String) -> (activityCount: Int, latestActivity: Date?) {
        guard fileManager.fileExists(atPath: path), fileManager.isReadableFile(atPath: path) else { return (0, nil) }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return (0, nil) }
        defer { sqlite3_close(db) }

        let count = sqliteInt(db, "SELECT COUNT(DISTINCT thread_id) FROM logs WHERE thread_id IS NOT NULL")
        let latest = sqliteInt(db, "SELECT ts FROM logs ORDER BY ts DESC, ts_nanos DESC, id DESC LIMIT 1")
        let latestDate = latest > 0 ? Date(timeIntervalSince1970: TimeInterval(latest)) : nil
        return (count, latestDate)
    }

    private func sqliteInt(_ db: OpaquePointer?, _ sql: String) -> Int {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    private func findJSONLFiles(in dir: String) -> [URL] {
        var results: [URL] = []
        guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil) else { return results }
        for case let url as URL in enumerator {
            let relPath = String(url.path.dropFirst(dir.count + 1))
            let depth = relPath.components(separatedBy: "/").count
            if depth > 10 {
                enumerator.skipDescendants()
                continue
            }
            if url.pathExtension == "jsonl" {
                results.append(url)
            }
        }
        return results
    }

    private func registerClaudeCode() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.claude/projects",
            home + "/.config/claude/projects",
            home + "/.claude/tasks"
        ]
        let source = AgentDataSource(
            agentName: "Claude Code",
            searchPaths: paths,
            filePattern: ".jsonl",
            parser: { [weak self] url, name in
                self?.parseClaudeCodeJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerCodex() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.codex/sessions",
            home + "/.codex/state_5.sqlite",
            home + "/.codex/logs_2.sqlite"
        ]
        let source = AgentDataSource(
            agentName: "Codex",
            searchPaths: paths,
            filePattern: ".jsonl",
            parser: { [weak self] url, name in
                self?.parseCodexDataSource(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerGrok() {
        let home = SandboxPaths.realHomeDirectory
        dataSources.append(AgentDataSource(
            agentName: "Grok CLI",
            searchPaths: [home + "/.grok/sessions"],
            filePattern: ".jsonl",
            parser: { [weak self] url, name in
                self?.parseGrokUpdates(url: url, agentName: name) ?? []
            }
        ))
    }

    private func registerQwenCode() {
        let home = SandboxPaths.realHomeDirectory
        dataSources.append(AgentDataSource(
            agentName: "Qwen Code",
            searchPaths: [home + "/.qwen/projects"],
            filePattern: ".jsonl",
            parser: { [weak self] url, name in
                self?.parseGenericJSONL(url: url, agentName: name) ?? []
            }
        ))
    }

    private func registerCursorWorkspaces() {
        let home = SandboxPaths.realHomeDirectory
        dataSources.append(AgentDataSource(
            agentName: "Cursor",
            searchPaths: [home + "/Library/Application Support/Cursor/User/workspaceStorage"],
            filePattern: ".vscdb",
            isVSCodeType: true,
            parser: { [weak self] url, name in
                self?.parseVscdbSQLite(url: url, agentName: name) ?? []
            }
        ))
    }

    private func registerKimi() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.kimi/sessions",
            home + "/.kimi/user-history",
        ]
        let source = AgentDataSource(
            agentName: "Kimi",
            searchPaths: paths,
            parser: { [weak self] url, name in
                self?.parseGenericJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerMiniMax() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.minimax/sqlite.db",
            home + "/.minimax/nexus/nexus.db"
        ]
        let source = AgentDataSource(
            agentName: "MiniMax Code",
            searchPaths: paths,
            filePattern: ".db",
            parser: { [weak self] url, name in
                self?.parseMiniMaxSQLite(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerAider() {
        let home = SandboxPaths.realHomeDirectory
        let source = AgentDataSource(
            agentName: "Aider",
            searchPaths: [home + "/.aider"],
            filePattern: ".md",
            parser: { [weak self] url, name in
                guard let self,
                      let content = self.readOperationTail(url: url, maxBytes: self.genericOperationTailReadLimit) else { return [] }
                var records: [AgentOpRecord] = []
                let lines = content.components(separatedBy: "\n")
                for (i, line) in lines.enumerated() {
                    if line.hasPrefix("##### ") || line.contains("ADDED:") || line.contains("EDITED:") || line.contains("DELETED:") {
                        let opType: String
                        if line.contains("ADDED") { opType = "Create" }
                        else if line.contains("EDITED") { opType = "Edit" }
                        else if line.contains("DELETED") { opType = "Delete" }
                        else { opType = "Action" }
                        records.append(AgentOpRecord(
                            id: "\(url.path)_\(i)",
                            agentName: name,
                            sessionId: url.deletingPathExtension().lastPathComponent,
                            projectDir: "",
                            timestamp: Date(),
                            toolName: "aider",
                            targetPath: line.replacingOccurrences(of: "##### ", with: "").trimmingCharacters(in: .whitespaces),
                            opType: opType,
                            detail: String(line.prefix(200))
                        ))
                    }
                }
                return records
            }
        )
        dataSources.append(source)
    }

    private func registerCline() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.cline/tasks"
        ]
        let source = AgentDataSource(
            agentName: "Cline",
            searchPaths: paths,
            filePattern: ".jsonl",
            parser: { [weak self] url, name in
                self?.parseGenericJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerGeminiCLI() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.gemini"
        ]
        let source = AgentDataSource(
            agentName: "Gemini CLI",
            searchPaths: paths,
            filePattern: ".jsonl",
            parser: { [weak self] url, name in
                self?.parseGenericJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerOpenCode() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.opencode",
            home + "/.local/share/opencode"
        ]
        let source = AgentDataSource(
            agentName: "OpenCode",
            searchPaths: paths,
            filePattern: ".jsonl",
            parser: { [weak self] url, name in
                self?.parseGenericJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerOpenClaw() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.openclaw/agents",
            home + "/.openclaw/workspace",
        ]
        let source = AgentDataSource(
            agentName: "OpenClaw",
            searchPaths: paths,
            filePattern: ".jsonl",
            parser: { [weak self] url, name in
                self?.parseOpenClawJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerHermes() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.hermes/sessions",
            home + "/.hermes/memories",
        ]
        let source = AgentDataSource(
            agentName: "Hermes",
            searchPaths: paths,
            filePattern: ".json",
            parser: { [weak self] url, name in
                self?.parseHermesSessionJSON(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)

        let dbSource = AgentDataSource(
            agentName: "Hermes",
            searchPaths: [home + "/.hermes"],
            filePattern: ".db",
            isVSCodeType: false,
            parser: { [weak self] url, name in
                self?.parseHermesStateDB(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(dbSource)
    }

    private func registerCrewAI() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/Library/Application Support/CrewAI",
            home + "/.crewai",
        ]
        let source = AgentDataSource(
            agentName: "CrewAI",
            searchPaths: paths,
            filePattern: ".db",
            parser: { [weak self] url, name in
                self?.parseCrewAISQLite(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerAutoGen() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.autogenstudio",
        ]
        let source = AgentDataSource(
            agentName: "AutoGen",
            searchPaths: paths,
            filePattern: ".sqlite",
            parser: { [weak self] url, name in
                self?.parseAutoGenSQLite(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerOpenHands() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.openhands",
            home + "/.conversations",
        ]
        let source = AgentDataSource(
            agentName: "OpenHands",
            searchPaths: paths,
            filePattern: ".json",
            parser: { [weak self] url, name in
                self?.parseOpenHandsJSON(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerDify() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.dify",
            home + "/.dify/sandbox",
        ]
        let source = AgentDataSource(
            agentName: "Dify",
            searchPaths: paths,
            parser: { [weak self] url, name in
                self?.parseGenericJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerMetaGPT() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.metagpt",
            home + "/.metagpt/workspace",
        ]
        let source = AgentDataSource(
            agentName: "MetaGPT",
            searchPaths: paths,
            parser: { [weak self] url, name in
                self?.parseGenericJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerCAMEL() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.camel",
            home + "/.camel/sessions",
        ]
        let source = AgentDataSource(
            agentName: "CAMEL",
            searchPaths: paths,
            parser: { [weak self] url, name in
                self?.parseGenericJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerDeerFlow() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.deer-flow",
            home + "/.deerflow",
        ]
        let source = AgentDataSource(
            agentName: "DeerFlow",
            searchPaths: paths,
            parser: { [weak self] url, name in
                self?.parseGenericJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerHuginn() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.huginn",
            home + "/huginn",
        ]
        let source = AgentDataSource(
            agentName: "Huginn",
            searchPaths: paths,
            filePattern: ".db",
            parser: { [weak self] url, name in
                self?.parseGenericJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerBrowserUse() {
        let home = SandboxPaths.realHomeDirectory
        let paths = [
            home + "/.browser-use",
        ]
        let source = AgentDataSource(
            agentName: "BrowserUse",
            searchPaths: paths,
            parser: { [weak self] url, name in
                self?.parseGenericJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func parseOpenClawJSONL(url: URL, agentName: String) -> [AgentOpRecord] {
        guard let content = readOperationTail(url: url, maxBytes: genericOperationTailReadLimit) else { return [] }
        var records: [AgentOpRecord] = []
        let sessionId = url.deletingPathExtension().lastPathComponent

        for line in content.components(separatedBy: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let ts = parseTimestamp(json["timestamp"] as? String) ?? Date()

            if let contentBlocks = json["content"] as? [[String: Any]] {
                for block in contentBlocks {
                    let blockType = block["type"] as? String ?? ""
                    if blockType == "tool_use" || blockType == "tool_call" {
                        let toolName = block["name"] as? String ?? ""
                        let input = block["input"] as? [String: Any] ?? [:]
                        let targetPath = input["file_path"] as? String
                            ?? input["path"] as? String
                            ?? ""
                        let opType = classifyOpType(toolName)
                        var detail = ""
                        if toolName.lowercased().contains("bash") || toolName.lowercased().contains("shell") || toolName.lowercased().contains("command") {
                            detail = input["command"] as? String ?? ""
                        }
                        records.append(AgentOpRecord(
                            id: UUID().uuidString,
                            agentName: agentName,
                            sessionId: sessionId,
                            projectDir: "",
                            timestamp: ts,
                            toolName: toolName,
                            targetPath: targetPath,
                            opType: opType,
                            detail: detail
                        ))
                    } else if blockType == "text" {
                        let text = block["text"] as? String ?? ""
                        let ops = extractOpsFromText(text, agentName: agentName, sessionId: sessionId, cwd: "", ts: ts)
                        records.append(contentsOf: ops)
                    }
                }
            }

            if let toolCalls = json["tool_calls"] as? [[String: Any]] {
                for tc in toolCalls {
                    let fn = tc["function"] as? [String: Any] ?? [:]
                    let toolName = fn["name"] as? String ?? ""
                    let argsStr = fn["arguments"] as? String ?? ""
                    var targetPath = ""
                    if let argsData = argsStr.data(using: .utf8),
                       let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                        targetPath = args["file_path"] as? String
                            ?? args["path"] as? String
                            ?? ""
                    }
                    let opType = classifyOpType(toolName)
                    records.append(AgentOpRecord(
                        id: UUID().uuidString,
                        agentName: agentName,
                        sessionId: sessionId,
                        projectDir: "",
                        timestamp: ts,
                        toolName: toolName,
                        targetPath: targetPath,
                        opType: opType,
                        detail: String(argsStr.prefix(200))
                    ))
                }
            }
        }

        return records
    }

    private func parseHermesSessionJSON(url: URL, agentName: String) -> [AgentOpRecord] {
        let filename = url.lastPathComponent
        if filename.hasPrefix("request_dump_") { return [] }

        guard let data = boundedStructuredData(url: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        var records: [AgentOpRecord] = []
        let sessionId = json["session_id"] as? String ?? url.deletingPathExtension().lastPathComponent
        let model = json["model"] as? String ?? ""
        let platform = json["platform"] as? String ?? ""
        let sessionStart = json["session_start"] as? String ?? ""
        let ts = parseTimestamp(sessionStart) ?? Date()

        if let messages = json["messages"] as? [[String: Any]] {
            for msg in messages {
                let role = msg["role"] as? String ?? ""
                guard role == "assistant" else { continue }

                if let toolCalls = msg["tool_calls"] as? [[String: Any]] {
                    for tc in toolCalls {
                        let fn = tc["function"] as? [String: Any] ?? [:]
                        let toolName = fn["name"] as? String ?? ""
                        let argsStr = fn["arguments"] as? String ?? ""
                        var targetPath = ""
                        if let argsData = argsStr.data(using: .utf8),
                           let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any] {
                            targetPath = args["file_path"] as? String
                                ?? args["path"] as? String
                                ?? args["command"] as? String
                                ?? args["directory"] as? String
                                ?? ""
                        }
                        let opType = classifyOpType(toolName)
                        records.append(AgentOpRecord(
                            id: UUID().uuidString,
                            agentName: agentName,
                            sessionId: sessionId,
                            projectDir: "",
                            timestamp: ts,
                            toolName: toolName,
                            targetPath: targetPath,
                            opType: opType,
                            detail: String(argsStr.prefix(200))
                        ))
                    }
                }

                if let content = msg["content"] as? String, !content.isEmpty {
                    let ops = extractOpsFromText(content, agentName: agentName, sessionId: sessionId, cwd: "", ts: ts)
                    records.append(contentsOf: ops)
                }
            }
        }

        if records.isEmpty {
            records.append(AgentOpRecord(
                id: "\(url.path)_session",
                agentName: agentName,
                sessionId: sessionId,
                projectDir: "",
                timestamp: ts,
                toolName: "session",
                targetPath: "",
                opType: "Chat",
                detail: "model=\(model) platform=\(platform)"
            ))
        }

        return records
    }

    private func parseHermesStateDB(url: URL, agentName: String) -> [AgentOpRecord] {
        guard url.pathExtension == "db" else { return [] }
        var records: [AgentOpRecord] = []
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let dbRef = db else { return records }
        defer { sqlite3_close(dbRef) }

        let query = "SELECT name FROM sqlite_master WHERE type='table' LIMIT 50;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(dbRef, query, -1, &stmt, nil) == SQLITE_OK else { return records }

        var tables: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 0) {
                tables.append(String(cString: name))
            }
        }
        sqlite3_finalize(stmt)

        if tables.contains("sessions") {
            var stmt2: OpaquePointer?
            let q2 = "SELECT session_id, title, model, platform, started_at, ended_at FROM sessions ORDER BY started_at DESC LIMIT 200;"
            if sqlite3_prepare_v2(dbRef, q2, -1, &stmt2, nil) == SQLITE_OK {
                while sqlite3_step(stmt2) == SQLITE_ROW {
                    let sid = sqlite3_column_text(stmt2, 0).map { String(cString: $0) } ?? ""
                    let title = sqlite3_column_text(stmt2, 1).map { String(cString: $0) } ?? ""
                    let model = sqlite3_column_text(stmt2, 2).map { String(cString: $0) } ?? ""
                    let platform = sqlite3_column_text(stmt2, 3).map { String(cString: $0) } ?? ""
                    let startedAt = sqlite3_column_double(stmt2, 4)
                    let date = startedAt > 1_000_000_000_000 ? Date(timeIntervalSince1970: startedAt / 1000) : (startedAt > 0 ? Date(timeIntervalSince1970: startedAt) : Date())

                    records.append(AgentOpRecord(
                        id: "\(url.path)_\(sid)",
                        agentName: agentName,
                        sessionId: sid,
                        projectDir: "",
                        timestamp: date,
                        toolName: "session",
                        targetPath: title,
                        opType: "Chat",
                        detail: "model=\(model) platform=\(platform)"
                    ))
                }
                sqlite3_finalize(stmt2)
            }
        }

        return records
    }

    private func parseCrewAISQLite(url: URL, agentName: String) -> [AgentOpRecord] {
        var records: [AgentOpRecord] = []
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let dbRef = db else { return records }
        defer { sqlite3_close(dbRef) }

        let query = "SELECT name FROM sqlite_master WHERE type='table';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(dbRef, query, -1, &stmt, nil) == SQLITE_OK else { return records }

        var tables: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 0) {
                tables.append(String(cString: name))
            }
        }
        sqlite3_finalize(stmt)

        for table in tables {
            let q = "SELECT * FROM \"\(table)\" LIMIT 100;"
            var stmt2: OpaquePointer?
            if sqlite3_prepare_v2(dbRef, q, -1, &stmt2, nil) == SQLITE_OK {
                let colCount = sqlite3_column_count(stmt2)
                while sqlite3_step(stmt2) == SQLITE_ROW {
                    var detail = ""
                    for i in 0..<colCount {
                        if let val = sqlite3_column_text(stmt2, i) {
                            let colName = sqlite3_column_name(stmt2, i).map { String(cString: $0) } ?? ""
                            let valStr = String(cString: val)
                            if !valStr.isEmpty {
                                if !detail.isEmpty { detail += "; " }
                                detail += "\(colName)=\(valStr.prefix(50))"
                            }
                        }
                    }
                    records.append(AgentOpRecord(
                        id: UUID().uuidString,
                        agentName: agentName,
                        sessionId: table,
                        projectDir: "",
                        timestamp: Date(),
                        toolName: table,
                        targetPath: "",
                        opType: "Action",
                        detail: String(detail.prefix(200))
                    ))
                }
                sqlite3_finalize(stmt2)
            }
        }

        return records
    }

    private func parseAutoGenSQLite(url: URL, agentName: String) -> [AgentOpRecord] {
        var records: [AgentOpRecord] = []
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let dbRef = db else { return records }
        defer { sqlite3_close(dbRef) }

        let query = "SELECT name FROM sqlite_master WHERE type='table';"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(dbRef, query, -1, &stmt, nil) == SQLITE_OK else { return records }

        var tables: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let name = sqlite3_column_text(stmt, 0) {
                tables.append(String(cString: name))
            }
        }
        sqlite3_finalize(stmt)

        for table in tables {
            let lower = table.lowercased()
            if lower.contains("session") || lower.contains("message") || lower.contains("conversation")
                || lower.contains("workflow") || lower.contains("history") || lower.contains("event")
                || lower.contains("log") || lower.contains("trace") || lower.contains("action")
                || lower.contains("tool") || lower.contains("task") {
                let q = "SELECT * FROM \"\(table)\" ORDER BY rowid DESC LIMIT 100;"
                var stmt2: OpaquePointer?
                if sqlite3_prepare_v2(dbRef, q, -1, &stmt2, nil) == SQLITE_OK {
                    let colCount = sqlite3_column_count(stmt2)
                    while sqlite3_step(stmt2) == SQLITE_ROW {
                        var detail = ""
                        var ts: Date = Date()
                        for i in 0..<colCount {
                            let colName = sqlite3_column_name(stmt2, i).map { String(cString: $0) } ?? ""
                            if let val = sqlite3_column_text(stmt2, i) {
                                let valStr = String(cString: val)
                                if !valStr.isEmpty {
                                    if !detail.isEmpty { detail += "; " }
                                    detail += "\(colName)=\(valStr.prefix(50))"
                                }
                                if colName.contains("timestamp") || colName.contains("created") || colName.contains("time") {
                                    if let d = parseTimestamp(valStr) { ts = d }
                                    else if let d = Double(valStr), d > 0 {
                                        ts = d > 1_000_000_000_000 ? Date(timeIntervalSince1970: d / 1000) : Date(timeIntervalSince1970: d)
                                    }
                                }
                            }
                        }
                        records.append(AgentOpRecord(
                            id: UUID().uuidString,
                            agentName: agentName,
                            sessionId: table,
                            projectDir: "",
                            timestamp: ts,
                            toolName: table,
                            targetPath: "",
                            opType: "Chat",
                            detail: String(detail.prefix(200))
                        ))
                    }
                    sqlite3_finalize(stmt2)
                }
            }
        }

        return records
    }

    private func parseOpenHandsJSON(url: URL, agentName: String) -> [AgentOpRecord] {
        guard let data = boundedStructuredData(url: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        var records: [AgentOpRecord] = []
        let sessionId = json["conversation_id"] as? String ?? url.deletingPathExtension().lastPathComponent

        if let events = json["events"] as? [[String: Any]] {
            for event in events {
                let eventType = event["type"] as? String ?? ""
                let ts = parseTimestamp(event["timestamp"] as? String) ?? Date()

                if eventType.contains("action") || eventType.contains("tool") {
                    let action = event["action"] as? String ?? eventType
                    let args = event["args"] as? [String: Any] ?? [:]
                    let targetPath = args["path"] as? String
                        ?? args["file_path"] as? String
                        ?? args["command"] as? String
                        ?? args["content"] as? String ?? ""
                    let opType = classifyOpType(action)
                    records.append(AgentOpRecord(
                        id: UUID().uuidString,
                        agentName: agentName,
                        sessionId: sessionId,
                        projectDir: "",
                        timestamp: ts,
                        toolName: action,
                        targetPath: String(targetPath.prefix(200)),
                        opType: opType,
                        detail: ""
                    ))
                }
            }
        }

        if records.isEmpty {
            let ts = parseTimestamp(json["timestamp"] as? String) ?? Date()
            records.append(AgentOpRecord(
                id: "\(url.path)_session",
                agentName: agentName,
                sessionId: sessionId,
                projectDir: "",
                timestamp: ts,
                toolName: "session",
                targetPath: "",
                opType: "Chat",
                detail: ""
            ))
        }

        return records
    }

    private func registerTrae() {
        let home = SandboxPaths.realHomeDirectory
        let traePaths = [
            "Trae CN": home + "/Library/Application Support/Trae CN",
            "Trae": home + "/Library/Application Support/Trae",
        ]

        for (_, basePath) in traePaths {
            guard fileManager.fileExists(atPath: basePath) else { continue }

            let globalStorage = basePath + "/User/globalStorage"
            let workspaceStorage = basePath + "/User/workspaceStorage"
            let snapshotDir = basePath + "/ModularData/ai-agent/snapshot"
            let sandboxDir = basePath + "/ModularData/ai-agent/sandbox"
            let historyDir = basePath + "/User/History"

            var searchPaths = [globalStorage]
            if fileManager.fileExists(atPath: workspaceStorage) {
                if let contents = try? fileManager.contentsOfDirectory(atPath: workspaceStorage) {
                    for item in contents {
                        let wsPath = workspaceStorage + "/" + item
                        var isDir: ObjCBool = false
                        fileManager.fileExists(atPath: wsPath, isDirectory: &isDir)
                        guard isDir.boolValue else { continue }
                        let vscdbPath = wsPath + "/state.vscdb"
                        if fileManager.fileExists(atPath: vscdbPath) {
                            searchPaths.append(wsPath)
                        }
                    }
                }
            }

            let vscdbParser: (URL, String) -> [AgentOpRecord] = { [weak self] url, agentName in
                guard let self = self else { return [] }
                return self.parseVscdbSQLite(url: url, agentName: agentName)
            }

            let source = AgentDataSource(
                agentName: "Trae",
                searchPaths: searchPaths,
                filePattern: ".vscdb",
                isVSCodeType: true,
                parser: vscdbParser
            )
            dataSources.append(source)

            if fileManager.fileExists(atPath: snapshotDir) {
                let snapshotParser: (URL, String) -> [AgentOpRecord] = { [weak self] url, agentName in
                    guard let self = self else { return [] }
                    return self.parseTraeSnapshot(url: url, agentName: agentName)
                }
                let snapshotSource = AgentDataSource(
                    agentName: "Trae",
                    searchPaths: [snapshotDir],
                    filePattern: ".git",
                    isVSCodeType: false,
                    parser: snapshotParser
                )
                dataSources.append(snapshotSource)
            }

            if fileManager.fileExists(atPath: sandboxDir) {
                let sandboxParser: (URL, String) -> [AgentOpRecord] = { [weak self] url, agentName in
                    guard let self = self else { return [] }
                    return self.parseTraeSandbox(url: url, agentName: agentName)
                }
                let sandboxSource = AgentDataSource(
                    agentName: "Trae",
                    searchPaths: [sandboxDir],
                    filePattern: ".json",
                    isVSCodeType: false,
                    parser: sandboxParser
                )
                dataSources.append(sandboxSource)
            }

            if fileManager.fileExists(atPath: historyDir) {
                let historyParser: (URL, String) -> [AgentOpRecord] = { [weak self] url, agentName in
                    guard let self = self else { return [] }
                    return self.parseTraeHistory(url: url, agentName: agentName)
                }
                let historySource = AgentDataSource(
                    agentName: "Trae",
                    searchPaths: [historyDir],
                    filePattern: ".json",
                    isVSCodeType: false,
                    parser: historyParser
                )
                dataSources.append(historySource)
            }
        }
    }

    private func parseTraeSnapshot(url: URL, agentName: String) -> [AgentOpRecord] {
        var records: [AgentOpRecord] = []
        let dirName = url.deletingLastPathComponent().lastPathComponent
        guard dirName.count >= 24 else { return records }

        let sessionId: String
        if dirName == "v2" {
            sessionId = url.deletingPathExtension().deletingLastPathComponent().lastPathComponent
        } else {
            sessionId = dirName
        }

        let date = dateFromObjectID(sessionId) ?? Date()

        let snapshotDir = url.deletingLastPathComponent().deletingLastPathComponent()
        var fileCount = 0
        if let enumerator = fileManager.enumerator(at: snapshotDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let fileURL as URL in enumerator {
                let relPath = String(fileURL.path.dropFirst(snapshotDir.path.count + 1))
                if relPath.contains(".git/") || relPath.contains(".git\\") {
                    enumerator.skipDescendants()
                    continue
                }
                var isDir: ObjCBool = false
                fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDir)
                guard !isDir.boolValue else { continue }
                fileCount += 1
                if fileCount > 50 { break }
            }
        }

        records.append(AgentOpRecord(
            id: "trae_snapshot_\(sessionId)",
            agentName: agentName,
            sessionId: sessionId,
            projectDir: snapshotDir.path,
            timestamp: date,
            toolName: "snapshot",
            targetPath: snapshotDir.path,
            opType: "Write",
            detail: "\(fileCount)\(localizer?.fileChangeCount ?? "files changed")"
        ))

        return records
    }

    private func parseTraeSandbox(url: URL, agentName: String) -> [AgentOpRecord] {
        guard let data = boundedStructuredData(url: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let sessionId = json["name"] as? String ?? url.deletingPathExtension().lastPathComponent
        let date = dateFromObjectID(sessionId) ?? Date()

        var allowedPaths: [String] = []
        if let permissions = json["permission"] as? [[String: String]] {
            for perm in permissions {
                for (_, path) in perm {
                    allowedPaths.append(path)
                }
            }
        }

        return [AgentOpRecord(
            id: "trae_sandbox_\(sessionId)",
            agentName: agentName,
            sessionId: sessionId,
            projectDir: allowedPaths.first ?? "",
            timestamp: date,
            toolName: "sandbox",
            targetPath: allowedPaths.first ?? "",
            opType: "Action",
            detail: "\(localizer?.allowedPaths ?? "Allowed access"): \(allowedPaths.count)\(localizer?.pathsCount ?? "paths")"
        )]
    }

    private func parseTraeHistory(url: URL, agentName: String) -> [AgentOpRecord] {
        let filename = url.lastPathComponent
        guard filename == "entries.json" else { return [] }

        guard let data = boundedStructuredData(url: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let resource = json["resource"] as? String ?? ""
        let resourcePath = resource
            .replacingOccurrences(of: "file://", with: "")
            .removingPercentEncoding ?? resource

        guard let entries = json["entries"] as? [[String: Any]] else { return [] }

        var records: [AgentOpRecord] = []
        let dirName = url.deletingLastPathComponent().lastPathComponent

        for entry in entries {
            let entryId = entry["id"] as? String ?? ""
            let source = entry["source"] as? String ?? ""
            let timestamp = entry["timestamp"] as? Double ?? 0

            let date: Date
            if timestamp > 1_000_000_000_000 {
                date = Date(timeIntervalSince1970: timestamp / 1000)
            } else if timestamp > 1_000_000_000 {
                date = Date(timeIntervalSince1970: timestamp)
            } else {
                date = Date()
            }

            let opType: String
            if source.contains("Edit") || source.contains("edit") {
                opType = "Edit"
            } else if source.contains("Save") || source.contains("save") {
                opType = "Write"
            } else if source.contains("Delete") || source.contains("delete") {
                opType = "Delete"
            } else {
                opType = "Edit"
            }

            let displayDetail = source.isEmpty ? opType : source

            records.append(AgentOpRecord(
                id: "trae_history_\(dirName)_\(entryId)",
                agentName: agentName,
                sessionId: dirName,
                projectDir: "",
                timestamp: date,
                toolName: "file_edit",
                targetPath: resourcePath.isEmpty ? dirName : resourcePath,
                opType: opType,
                detail: displayDetail
            ))
        }

        return records
    }

    private func registerGenericAutoDiscovery() {
        let home = SandboxPaths.realHomeDirectory
        let vscodeAgents: Set<String> = ["Trae", "Cursor", "CodeBuddy", "Windsurf", "Kimi", "Lingma", "Augment", "Continue", "Cody", "Amazon Q", "Roo Code", "Tabnine"]

        let knownDirs: [(String, String)] = [
            ("Cursor", home + "/.cursor"),
            ("Windsurf", home + "/.codeium/windsurf"),
            ("CodeBuddy", home + "/.codebuddy"),
            ("CodeBuddy", home + "/Library/Application Support/CodeBuddy CN"),
            ("DeepSeek", home + "/.deepseek"),
            ("Kimi", home + "/.kimi"),
            ("Lingma", home + "/.lingma"),
            ("Augment", home + "/.augment"),
            ("Cursor Agent", home + "/.cursor-agent"),
            ("Windsurf Agent", home + "/.windsurf-agent"),
            ("CodeBuddy Agent", home + "/.codebuddy-agent"),
            ("Amp", home + "/.amp"),
            ("pi-agent", home + "/.pi-agent"),
            ("GLM", home + "/.glm"),
            ("Doubao", home + "/.doubao"),
            ("Roo Code", home + "/.roo"),
            ("Continue", home + "/.continue"),
            ("Tabnine", home + "/.tabnine"),
            ("Cody", home + "/.cody"),
            ("Amazon Q", home + "/.amazon-q"),
            ("Aider", home + "/.aider"),
            ("Cline", home + "/.cline"),
            ("OpenCode", home + "/.opencode"),
            ("Gemini CLI", home + "/.gemini"),
            ("Codex", home + "/.codex"),
            ("Claude Code", home + "/.claude"),
            ("OpenClaw", home + "/.openclaw"),
            ("Hermes", home + "/.hermes"),
            ("CrewAI", home + "/.crewai"),
            ("AutoGen", home + "/.autogenstudio"),
            ("OpenHands", home + "/.openhands"),
            ("Dify", home + "/.dify"),
            ("MetaGPT", home + "/.metagpt"),
            ("CAMEL", home + "/.camel"),
            ("DeerFlow", home + "/.deer-flow"),
            ("DeerFlow", home + "/.deerflow"),
            ("Huginn", home + "/.huginn"),
            ("BrowserUse", home + "/.browser-use"),
            ("AgentGPT", home + "/.agentgpt"),
            ("LobeHub", home + "/.lobehub"),
            ("LangGraph", home + "/.langgraph"),
            ("Swarm", home + "/.swarm"),
            ("AgentScope", home + "/.agentscope"),
            ("UI-TARS", home + "/.ui-tars"),
        ]

        var grouped: [String: [String]] = [:]
        for (name, path) in knownDirs {
            grouped[name, default: []].append(path)
        }

        for (name, paths) in grouped {
            let isVSCode = vscodeAgents.contains(name)
            let existingSources = dataSources.filter { $0.agentName == name }
            if !existingSources.isEmpty { continue }

            let parser: (URL, String) -> [AgentOpRecord] = { [weak self] url, agentName in
                self?.parseAutoDetectedSource(url: url, agentName: agentName) ?? []
            }

            let source = AgentDataSource(
                agentName: name,
                searchPaths: paths,
                filePattern: "*",
                isVSCodeType: isVSCode,
                parser: parser
            )
            dataSources.append(source)
        }
    }

    private func parseClaudeCodeJSONL(url: URL, agentName: String) -> [AgentOpRecord] {
        guard let content = readOperationTail(url: url, maxBytes: genericOperationTailReadLimit) else { return [] }
        var records: [AgentOpRecord] = []
        var cwd = ""
        var sessionId = url.deletingPathExtension().lastPathComponent
        let fileOpTools: Set<String> = ["Write", "Edit", "MultiEdit", "Read", "Bash", "Glob", "Grep"]

        for line in content.components(separatedBy: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            if let c = json["cwd"] as? String { cwd = c }
            if let sid = json["sessionId"] as? String { sessionId = sid }

            guard json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let contentBlocks = message["content"] as? [[String: Any]] else { continue }

            let ts = parseTimestamp(json["timestamp"] as? String) ?? Date()

            for block in contentBlocks {
                guard block["type"] as? String == "tool_use",
                      let toolName = block["name"] as? String,
                      fileOpTools.contains(toolName),
                      let input = block["input"] as? [String: Any] else { continue }

                let targetPath: String
                let opType: String
                let detail: String
                switch toolName {
                case "Write":
                    opType = "Write"
                    targetPath = input["file_path"] as? String ?? input["path"] as? String ?? cwd
                    detail = (input["content"] as? String ?? "").prefix(200).description
                case "Edit", "MultiEdit":
                    opType = "Edit"
                    targetPath = input["file_path"] as? String ?? input["path"] as? String ?? cwd
                    detail = input["old_string"] as? String ?? ""
                case "Read":
                    opType = "Read"
                    targetPath = input["file_path"] as? String ?? input["path"] as? String ?? cwd
                    detail = ""
                case "Bash":
                    opType = "Execute"
                    targetPath = cwd
                    detail = input["command"] as? String ?? ""
                case "Glob", "Grep":
                    opType = "Search"
                    targetPath = input["pattern"] as? String ?? input["file_path"] as? String ?? input["path"] as? String ?? cwd
                    detail = ""
                default:
                    opType = "Action"
                    targetPath = input["file_path"] as? String ?? input["path"] as? String ?? cwd
                    detail = ""
                }

                records.append(AgentOpRecord(
                    id: UUID().uuidString,
                    agentName: agentName,
                    sessionId: sessionId,
                    projectDir: cwd,
                    timestamp: ts,
                    toolName: toolName,
                    targetPath: targetPath,
                    opType: opType,
                    detail: String(detail.prefix(200))
                ))
            }
        }

        return records
    }

    private func parseCodexJSONL(url: URL, agentName: String) -> [AgentOpRecord] {
        guard let content = readCodexOperationWindow(url: url) else { return [] }
        var records: [AgentOpRecord] = []
        let sessionId = url.deletingPathExtension().lastPathComponent
        var cwd = ""

        for line in content.split(separator: "\n", omittingEmptySubsequences: true).suffix(codexOperationLineLimit) {
            guard let data = String(line).data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let type = json["type"] as? String ?? ""

            if type == "session_meta" || type == "turn_context" {
                if let payload = json["payload"] as? [String: Any] {
                    cwd = payload["cwd"] as? String ?? cwd
                }
            }

            if type == "response_item" {
                guard let payload = json["payload"] as? [String: Any] else { continue }
                let payloadType = payload["type"] as? String ?? ""
                let ts = parseTimestamp(json["timestamp"] as? String) ?? Date()

                if payloadType == "function_call" || payloadType == "custom_tool_call" {
                    if let record = codexFunctionCallRecord(payload: payload, agentName: agentName, sessionId: sessionId, cwd: cwd, ts: ts) {
                        records.append(record)
                    }
                } else if payloadType == "message" {
                    let role = payload["role"] as? String ?? ""
                    guard role == "assistant" else { continue }
                    let contentBlocks = payload["content"] as? [[String: Any]] ?? []

                    for block in contentBlocks {
                        let blockType = block["type"] as? String ?? ""

                        if blockType == "tool_use" {
                            guard let toolName = block["name"] as? String,
                                  let input = block["input"] as? [String: Any] else { continue }
                            let targetPath = input["file_path"] as? String
                                ?? input["path"] as? String
                                ?? cwd
                            let opType = classifyOpType(toolName)
                            var detail = ""
                            if toolName.lowercased().contains("bash") || toolName.lowercased().contains("shell") {
                                detail = input["command"] as? String ?? ""
                            }
                            records.append(AgentOpRecord(
                                id: UUID().uuidString,
                                agentName: agentName,
                                sessionId: sessionId,
                                projectDir: cwd,
                                timestamp: ts,
                                toolName: toolName,
                                targetPath: targetPath,
                                opType: opType,
                                detail: detail
                            ))
                        } else if blockType == "input_text" || blockType == "text" {
                            let text = block["text"] as? String ?? ""
                            let ops = extractOpsFromText(text, agentName: agentName, sessionId: sessionId, cwd: cwd, ts: ts)
                            records.append(contentsOf: ops)
                        }
                    }
                }
            }

            if type == "event_msg" {
                guard let payload = json["payload"] as? [String: Any] else { continue }
                let eventType = payload["type"] as? String ?? ""
                if eventType == "task_complete" {
                    if let lastMsg = payload["last_agent_message"] as? String, !lastMsg.isEmpty {
                        let ts = parseTimestamp(json["timestamp"] as? String) ?? Date()
                        let ops = extractOpsFromText(lastMsg, agentName: agentName, sessionId: sessionId, cwd: cwd, ts: ts)
                        records.append(contentsOf: ops)
                    }
                }
            }
        }

        return records
    }

    private func readCodexOperationWindow(url: URL) -> String? {
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attrs?[.size] as? NSNumber)?.uint64Value ?? 0
        guard fileSize > 0 else { return nil }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let maxBytes = UInt64(codexOperationTailReadLimit)
        let startOffset = fileSize > maxBytes ? fileSize - maxBytes : 0
        do {
            try handle.seek(toOffset: startOffset)
            guard let data = try handle.readToEnd() else { return nil }
            var content = String(decoding: data, as: UTF8.self)
            if startOffset > 0, let firstBreak = content.firstIndex(of: "\n") {
                content = String(content[content.index(after: firstBreak)...])
            }
            return content
        } catch {
            return nil
        }
    }

    private func parseCodexDataSource(url: URL, agentName: String) -> [AgentOpRecord] {
        let fileName = url.lastPathComponent
        if fileName == "state_5.sqlite" {
            return parseCodexStateDBRecords(url: url, agentName: agentName)
        }
        if fileName == "logs_2.sqlite" {
            return parseCodexLogDBRecords(url: url, agentName: agentName)
        }
        return parseCodexJSONL(url: url, agentName: agentName)
    }

    private func parseCodexStateDBRecords(url: URL, agentName: String) -> [AgentOpRecord] {
        guard fileManager.fileExists(atPath: url.path), fileManager.isReadableFile(atPath: url.path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, rollout_path, cwd, title, updated_at, updated_at_ms, model, reasoning_effort, preview
        FROM threads
        ORDER BY updated_at DESC
        LIMIT 1000;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var records: [AgentOpRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let threadId = sqliteText(stmt, 0)
            let rolloutPath = sqliteText(stmt, 1)
            let cwd = sqliteText(stmt, 2)
            let title = sqliteText(stmt, 3)
            let updatedAt = sqlite3_column_int64(stmt, 4)
            let updatedAtMs = sqlite3_column_int64(stmt, 5)
            let model = sqliteText(stmt, 6)
            let effort = sqliteText(stmt, 7)
            let preview = sqliteText(stmt, 8)
            let interval = updatedAtMs > 0 ? TimeInterval(updatedAtMs) / 1000.0 : TimeInterval(updatedAt)
            let ts = interval > 0 ? Date(timeIntervalSince1970: interval) : Date()
            let detail = [title, preview, model, effort].filter { !$0.isEmpty }.joined(separator: " | ")

            records.append(AgentOpRecord(
                id: "codex_thread_\(threadId)",
                agentName: agentName,
                sessionId: threadId,
                projectDir: cwd,
                timestamp: ts,
                toolName: "thread",
                targetPath: rolloutPath.isEmpty ? cwd : rolloutPath,
                opType: "Session",
                detail: detail.isEmpty ? "Codex thread activity" : String(detail.prefix(300))
            ))
        }
        return records
    }

    private func parseCodexLogDBRecords(url: URL, agentName: String) -> [AgentOpRecord] {
        guard fileManager.fileExists(atPath: url.path), fileManager.isReadableFile(atPath: url.path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, ts, thread_id, target, feedback_log_body
        FROM logs
        WHERE feedback_log_body LIKE '%function_call%'
           OR feedback_log_body LIKE '%tool_call%'
           OR feedback_log_body LIKE '%codex.op=%'
           OR feedback_log_body LIKE '%exec_command%'
           OR feedback_log_body LIKE '%apply_patch%'
           OR feedback_log_body LIKE '%response.function_call_arguments.done%'
        ORDER BY ts DESC
        LIMIT 2000;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var records: [AgentOpRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(stmt, 0)
            let tsRaw = sqlite3_column_int64(stmt, 1)
            let threadId = sqliteText(stmt, 2)
            let target = sqliteText(stmt, 3)
            let body = sqliteText(stmt, 4)
            let ts = tsRaw > 0 ? Date(timeIntervalSince1970: TimeInterval(tsRaw)) : Date()
            let argumentsText = codexArgumentsTextFromLog(body)
            let parsedArgs = parseJSONString(argumentsText) ?? [:]
            let tool = codexToolNameFromLog(body: body, parsedArgs: parsedArgs, rawArguments: argumentsText)
            let fallbackTarget = codexTargetFromLog(body: body, fallback: target)
            records.append(AgentOpRecord(
                id: "codex_log_\(rowId)",
                agentName: agentName,
                sessionId: threadId.isEmpty ? "logs_2" : threadId,
                projectDir: "",
                timestamp: ts,
                toolName: tool,
                targetPath: codexTargetPath(toolName: tool, args: parsedArgs, rawArguments: argumentsText, cwd: fallbackTarget),
                opType: classifyOpType(tool),
                detail: String(codexDetail(toolName: tool, args: parsedArgs, rawArguments: argumentsText.isEmpty ? body : argumentsText).prefix(300))
            ))
        }
        return records
    }

    private func sqliteText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }

    private func codexToolNameFromLog(body: String, parsedArgs: [String: Any] = [:], rawArguments: String = "") -> String {
        let lower = body.lowercased()
        if parsedArgs["cmd"] != nil || parsedArgs["command"] != nil { return "exec_command" }
        if rawArguments.contains("*** Begin Patch") { return "apply_patch" }
        if lower.contains("apply_patch") { return "apply_patch" }
        if lower.contains("exec_command") { return "exec_command" }
        if lower.contains("function_call") { return "function_call" }
        if lower.contains("tool_call") { return "tool_call" }
        return "codex"
    }

    private func codexTargetFromLog(body: String, fallback: String) -> String {
        if let path = firstPathLikeToken(in: body) {
            return path
        }
        return fallback
    }

    private func firstPathLikeToken(in text: String) -> String? {
        let pattern = #"(/Users/[^"'\s,;]+|~\/[^"'\s,;]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[range])
    }

    private func codexArgumentsTextFromLog(_ body: String) -> String {
        let prefix = "SSE event: "
        let jsonText = body.hasPrefix(prefix) ? String(body.dropFirst(prefix.count)) : body
        if let data = jsonText.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let args = json["arguments"] as? String {
            return args
        }
        return ""
    }

    private func parseJSONString(_ text: String) -> [String: Any]? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func codexFunctionCallRecord(payload: [String: Any], agentName: String, sessionId: String, cwd: String, ts: Date) -> AgentOpRecord? {
        let rawName = payload["name"] as? String ?? ""
        guard !rawName.isEmpty else { return nil }

        let argumentsText = payload["arguments"] as? String ?? payload["input"] as? String ?? ""
        let parsedArgs: [String: Any]
        if let data = argumentsText.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            parsedArgs = json
        } else {
            parsedArgs = [:]
        }

        let displayName = rawName.replacingOccurrences(of: "functions.", with: "")
        let targetPath = codexTargetPath(toolName: displayName, args: parsedArgs, rawArguments: argumentsText, cwd: cwd)
        let detail = codexDetail(toolName: displayName, args: parsedArgs, rawArguments: argumentsText)

        return AgentOpRecord(
            id: UUID().uuidString,
            agentName: agentName,
            sessionId: sessionId,
            projectDir: stringArg(parsedArgs, ["workdir", "cwd"]) ?? cwd,
            timestamp: ts,
            toolName: displayName,
            targetPath: targetPath,
            opType: classifyOpType(displayName),
            detail: String(detail.prefix(300))
        )
    }

    private func codexTargetPath(toolName: String, args: [String: Any], rawArguments: String, cwd: String) -> String {
        if let path = stringArg(args, ["file", "path", "filepath", "file_path"]), !path.isEmpty {
            return path
        }
        if let workdir = stringArg(args, ["workdir", "cwd"]), !workdir.isEmpty {
            return workdir
        }
        if toolName.contains("apply_patch"),
           let patchedFile = firstPatchedFile(in: rawArguments) {
            return patchedFile.hasPrefix("/") ? patchedFile : (cwd.isEmpty ? patchedFile : "\(cwd)/\(patchedFile)")
        }
        return cwd
    }

    private func codexDetail(toolName: String, args: [String: Any], rawArguments: String) -> String {
        if let command = stringArg(args, ["cmd", "command"]), !command.isEmpty { return command }
        if let chars = stringArg(args, ["chars"]), !chars.isEmpty { return chars }
        if let query = stringArg(args, ["query", "pattern"]), !query.isEmpty { return query }
        if toolName.contains("apply_patch") { return firstPatchSummary(in: rawArguments) ?? "apply_patch" }
        return rawArguments
    }

    private func stringArg(_ args: [String: Any], _ keys: [String]) -> String? {
        for key in keys {
            if let value = args[key] as? String { return value }
            if let value = args[key] { return "\(value)" }
        }
        return nil
    }

    private func firstPatchedFile(in text: String) -> String? {
        for line in text.components(separatedBy: "\n") {
            let prefixes = ["*** Update File: ", "*** Add File: ", "*** Delete File: "]
            for prefix in prefixes where line.hasPrefix(prefix) {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }

    private func firstPatchSummary(in text: String) -> String? {
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("*** Update File: ") || line.hasPrefix("*** Add File: ") || line.hasPrefix("*** Delete File: ") {
                return line
            }
        }
        return nil
    }

    private func extractOpsFromText(_ text: String, agentName: String, sessionId: String, cwd: String, ts: Date) -> [AgentOpRecord] {
        var records: [AgentOpRecord] = []
        let patterns: [(String, [String], String)] = [
            ("Write", ["write", "created", "wrote", "saved"], #"(?:to|at|in|→)\s+[`\"']?(/[^\s`\"']+)[`\"']?"#),
            ("Edit", ["edit", "modified", "updated", "changed"], #"(?:file|at|in|→)\s+[`\"']?(/[^\s`\"']+)[`\"']?"#),
            ("Read", ["read", "viewed", "opened", "checked"], #"(?:file|at|in|→)\s+[`\"']?(/[^\s`\"']+)[`\"']?"#),
            ("Delete", ["delete", "removed", "deleted"], #"(?:file|at|in|→)\s+[`\"']?(/[^\s`\"']+)[`\"']?"#),
            ("Execute", ["ran ", "executed", "command", "shell", "bash"], #"(?:ran|executed|command|bash|shell)[:\s]+[`\"']?([^`\"'\n]+)[`\"']?"#),
        ]

        let lines = text.components(separatedBy: "\n")
        for line in lines {
            let lower = line.lowercased()
            for (opType, keywords, pathPattern) in patterns {
                let matched = keywords.contains { lower.contains($0) }
                if matched {
                    if let regex = try? NSRegularExpression(pattern: pathPattern, options: .caseInsensitive),
                       let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                       let range = Range(match.range(at: 1), in: line) {
                        let extracted = String(line[range]).trimmingCharacters(in: .whitespaces)
                        let path = extracted.hasPrefix("/") ? extracted : extracted
                        let instruction = String(line.prefix(150)).trimmingCharacters(in: .whitespaces)
                        records.append(AgentOpRecord(
                            id: UUID().uuidString,
                            agentName: agentName,
                            sessionId: sessionId,
                            projectDir: cwd,
                            timestamp: ts,
                            toolName: "text_action",
                            targetPath: path,
                            opType: opType,
                            detail: instruction
                        ))
                    }
                    break
                }
            }
        }

        return records
    }

    private func classifyOpType(_ toolName: String) -> String {
        let lower = toolName.lowercased()
        if lower.contains("write") || lower.contains("create") { return "Write" }
        if lower.contains("edit") || lower.contains("update") || lower.contains("apply_patch") { return "Edit" }
        if lower.contains("read") || lower.contains("view") || lower.contains("get") { return "Read" }
        if lower.contains("delete") || lower.contains("remove") { return "Delete" }
        if lower.contains("bash") || lower.contains("shell") || lower.contains("exec") || lower.contains("command") || lower == "js" { return "Execute" }
        if lower.contains("search") || lower.contains("glob") || lower.contains("grep") || lower.contains("find") { return "Search" }
        return "Action"
    }

    static func localizedOpType(_ opType: String, localizer: Localizer) -> String {
        switch opType {
        case "Write": return localizer.opWrite
        case "Edit": return localizer.opEdit
        case "Read": return localizer.opRead
        case "Delete": return localizer.opDelete2
        case "Execute": return localizer.opExec
        case "Search": return localizer.opSearch
        case "Action": return localizer.opAction
        case "Chat": return localizer.opDialogue
        case "Create": return localizer.opNew
        case "Save": return localizer.opSave
        case "Open": return localizer.opOpen
        case "Close": return localizer.opClose
        default: return opType
        }
    }

    private func dateFromObjectID(_ oid: String) -> Date? {
        guard oid.count >= 8 else { return nil }
        let hex = String(oid.prefix(8))
        guard let ts = UInt64(hex, radix: 16), ts > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    func parseVscdbSQLite(url: URL, agentName: String) -> [AgentOpRecord] {
        var records: [AgentOpRecord] = []
        let dbPath = url.path

        var db: OpaquePointer?
        guard sqlite3_open(dbPath, &db) == SQLITE_OK, let dbRef = db else {
            return records
        }
        defer { sqlite3_close(dbRef) }

        var workspaceFolder = ""
        let wsPath = url.deletingLastPathComponent().appendingPathComponent("workspace.json").path
        if let wsData = boundedStructuredData(url: URL(fileURLWithPath: wsPath)),
           let wsJson = try? JSONSerialization.jsonObject(with: wsData) as? [String: Any],
           let folder = wsJson["folder"] as? String {
            workspaceFolder = folder
                .replacingOccurrences(of: "file://", with: "")
                .removingPercentEncoding ?? folder
        }

        var dbModDate: Date? = nil
        if let attrs = try? fileManager.attributesOfItem(atPath: dbPath),
           let modDate = attrs[.modificationDate] as? Date {
            dbModDate = modDate
        }

        let query = "SELECT key, value FROM ItemTable;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(dbRef, query, -1, &stmt, nil) == SQLITE_OK else { return records }
        defer { sqlite3_finalize(stmt) }

        var sessionModelMap: [String: String] = [:]
        var sessionModeMap: [String: String] = [:]

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let keyPtr = sqlite3_column_text(stmt, 0),
                  let valuePtr = sqlite3_column_text(stmt, 1) else { continue }
            let key = String(cString: keyPtr)
            let value = String(cString: valuePtr)

            if key.contains("ai-chat:sessionRelation:modelMap") {
                guard let data = value.data(using: .utf8),
                      let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                for (sessionId, modelInfo) in map {
                    if let m = modelInfo as? [String: String] {
                        sessionModelMap[sessionId] = m.values.joined(separator: " ")
                    } else {
                        sessionModelMap[sessionId] = String(describing: modelInfo)
                    }
                }
            }

            if key.contains("ai-chat:sessionRelation:modeMap") || key.contains("ai-chat:sessionRelation:planModeMap") || key.contains("ai-chat:sessionRelation:specModeMap") {
                guard let data = value.data(using: .utf8),
                      let map = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                for (sessionId, modeInfo) in map {
                    if let m = modeInfo as? [String: String] {
                        sessionModeMap[sessionId] = m.values.joined(separator: " ")
                    }
                }
            }

            if key.hasSuffix("ChatStore") || key.hasSuffix("chat.ChatSessionStore.index") {
                guard let data = value.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                if let entries = json["entries"] as? [String: Any] {
                    for (sessionId, entry) in entries {
                        guard let entryDict = entry as? [String: Any] else { continue }
                        let title = entryDict["title"] as? String ?? ""
                        let lastMessage = entryDict["lastMessage"] as? String ?? ""
                        let ts = entryDict["createdAt"] as? Double ?? entryDict["lastMessageDate"] as? Double ?? 0
                        let date: Date
                        if ts > 1_000_000_000_000 {
                            date = Date(timeIntervalSince1970: ts / 1000)
                        } else if ts > 0 {
                            date = Date(timeIntervalSince1970: ts)
                        } else {
                            date = dateFromObjectID(sessionId) ?? dbModDate ?? Date()
                        }

                        records.append(AgentOpRecord(
                            id: "\(url.path)_\(sessionId)",
                            agentName: agentName,
                            sessionId: sessionId,
                            projectDir: workspaceFolder,
                            timestamp: date,
                            toolName: "chat_session",
                            targetPath: title.isEmpty ? lastMessage.prefix(100).description : title,
                            opType: "Chat",
                            detail: workspaceFolder
                        ))
                    }
                }

                if let state = json["state"] as? [String: Any] {
                    if let turnsHeight = state["turnsHeight"] as? [String: Any] {
                        for (sessionId, _) in turnsHeight {
                            let existing = records.contains { $0.id == "\(url.path)_\(sessionId)" }
                            if !existing {
                                let date = dateFromObjectID(sessionId) ?? dbModDate ?? Date()
                                records.append(AgentOpRecord(
                                    id: "\(url.path)_turns_\(sessionId)",
                                    agentName: agentName,
                                    sessionId: sessionId,
                                    projectDir: workspaceFolder,
                                    timestamp: date,
                                    toolName: "chat_session",
                                    targetPath: workspaceFolder,
                                    opType: "Chat",
                                    detail: ""
                                ))
                            }
                        }
                    }
                }
            }

            if (key.contains("icube-ai-agent-storage-input-history") || key.contains("agent-storage-input-history")) && !key.contains("query") {
                guard let data = value.data(using: .utf8),
                      let historyList = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { continue }
                let totalCount = historyList.count
                let endDate = dbModDate ?? Date()
                var startDate = endDate
                if let earliestSession = sessionModelMap.keys.sorted().first, let oidDate = dateFromObjectID(earliestSession) {
                    startDate = oidDate
                } else {
                    startDate = endDate.addingTimeInterval(-Double(totalCount) * 600)
                }
                let timeRange = endDate.timeIntervalSince(startDate)
                let step = totalCount > 1 ? timeRange / Double(totalCount - 1) : 0
                for (idx, item) in historyList.enumerated() {
                    let inputText = item["inputText"] as? String ?? ""
                    guard !inputText.isEmpty else { continue }
                    let date: Date
                    if let ts = item["timestamp"] as? Double, ts > 0 {
                        date = ts > 1_000_000_000_000 ? Date(timeIntervalSince1970: ts / 1000) : Date(timeIntervalSince1970: ts)
                    } else if let tsStr = item["timestamp"] as? String, let ts = parseTimestamp(tsStr) {
                        date = ts
                    } else {
                        date = startDate.addingTimeInterval(Double(idx) * step)
                    }
                    records.append(AgentOpRecord(
                        id: "\(url.path)_history_\(idx)",
                        agentName: agentName,
                        sessionId: "input_history",
                        projectDir: workspaceFolder,
                        timestamp: date,
                        toolName: "user_input",
                        targetPath: workspaceFolder,
                        opType: "Chat",
                        detail: String(inputText.prefix(200))
                    ))
                }
            }

            if key == "icube_session_agent_map" {
                guard let data = value.data(using: .utf8),
                      let map = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { continue }
                for (sessionId, agentType) in map {
                    let date = dateFromObjectID(sessionId) ?? dbModDate ?? Date()
                    let modelInfo = sessionModelMap[sessionId] ?? ""
                    let modeInfo = sessionModeMap[sessionId] ?? ""
                    records.append(AgentOpRecord(
                        id: "\(url.path)_agentmap_\(sessionId)",
                        agentName: agentName,
                        sessionId: sessionId,
                        projectDir: workspaceFolder,
                        timestamp: date,
                        toolName: "agent_session",
                        targetPath: workspaceFolder,
                        opType: "Action",
                        detail: "agent_type=\(agentType) model=\(modelInfo) mode=\(modeInfo)"
                    ))
                }
            }

            if key == "memento/icube-ai-agent-storage" {
                guard let data = value.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let list = json["list"] as? [[String: Any]] else { continue }
                for item in list {
                    let sessionId = item["sessionId"] as? String ?? ""
                    let isCurrent = item["isCurrent"] as? Bool ?? false
                    let date = dateFromObjectID(sessionId) ?? dbModDate ?? Date()
                    let modelInfo = sessionModelMap[sessionId] ?? ""
                    var detail = isCurrent ? (localizer?.currentSession ?? "Active session") : (localizer?.historySession ?? "History session")
                    if !modelInfo.isEmpty { detail += " model=\(modelInfo)" }
                    records.append(AgentOpRecord(
                        id: "\(url.path)_icube_\(sessionId)",
                        agentName: agentName,
                        sessionId: sessionId,
                        projectDir: workspaceFolder,
                        timestamp: date,
                        toolName: isCurrent ? "current_session" : "session",
                        targetPath: workspaceFolder,
                        opType: "Action",
                        detail: detail
                    ))
                }
            }

            if key.contains("currentAgentData") {
                guard let data = value.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                let agentId = json["agent_id"] as? String ?? ""
                let agentName2 = json["name"] as? String ?? ""
                let desc = json["description"] as? String ?? ""
                let tools = json["built_in_tool_list"] as? [[String: String]] ?? []
                let toolNames = tools.compactMap { $0["value"] }.joined(separator: ", ")
                let createdAt = json["created_at"] as? Double ?? 0
                let updatedAt = json["updated_at"] as? Double ?? 0
                let date: Date
                if updatedAt > 0 {
                    date = updatedAt > 1_000_000_000_000 ? Date(timeIntervalSince1970: updatedAt / 1000) : Date(timeIntervalSince1970: updatedAt)
                } else if createdAt > 0 {
                    date = createdAt > 1_000_000_000_000 ? Date(timeIntervalSince1970: createdAt / 1000) : Date(timeIntervalSince1970: createdAt)
                } else {
                    date = dbModDate ?? Date()
                }
                records.append(AgentOpRecord(
                    id: "\(url.path)_agent_config_\(agentId)",
                    agentName: agentName,
                    sessionId: agentId,
                    projectDir: workspaceFolder,
                    timestamp: date,
                    toolName: "agent_config",
                    targetPath: workspaceFolder,
                    opType: "Action",
                    detail: "agent=\(agentName2) tools=[\(toolNames)] \(desc)"
                ))
            }

            if key.contains("all_session_badges_") {
                let badgeSessionId = key.replacingOccurrences(of: "all_session_badges_", with: "")
                guard let data = value.data(using: .utf8),
                      let badgeMap = try? JSONSerialization.jsonObject(with: data) as? [String: String] else { continue }
                let sessionDate = dateFromObjectID(badgeSessionId) ?? dbModDate ?? Date()
                for (subSessionId, status) in badgeMap {
                    let subDate = dateFromObjectID(subSessionId) ?? sessionDate
                    records.append(AgentOpRecord(
                        id: "\(url.path)_badge_\(subSessionId)",
                        agentName: agentName,
                        sessionId: subSessionId,
                        projectDir: workspaceFolder,
                        timestamp: subDate,
                        toolName: "session_badge",
                        targetPath: workspaceFolder,
                        opType: "Action",
                        detail: "status=\(status) parent_session=\(badgeSessionId)"
                    ))
                }
            }
        }

        return records
    }

    func parseFileChangesJSON(url: URL, agentName: String) -> [AgentOpRecord] {
        guard let data = boundedStructuredData(url: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }

        let filePath = json["filePath"] as? String ?? ""
        let _ = json["fileName"] as? String ?? ""
        let changeType = json["changeType"] as? String ?? ""
        let addedLines = json["addedLines"] as? Int ?? 0
        let removedLines = json["removedLines"] as? Int ?? 0
        let status = json["status"] as? String ?? ""
        let timestamp = json["timestamp"] as? Double ?? 0

        let opType: String
        switch changeType.lowercased() {
        case "create": opType = "Write"
        case "edit", "modify", "update": opType = "Edit"
        case "delete", "remove": opType = "Delete"
        default:
            if addedLines > 0 && removedLines == 0 { opType = "Write" }
            else if addedLines > 0 && removedLines > 0 { opType = "Edit" }
            else if removedLines > 0 && addedLines == 0 { opType = "Delete" }
            else { opType = "Edit" }
        }

        let date: Date
        if timestamp > 1_000_000_000_000 {
            date = Date(timeIntervalSince1970: timestamp / 1000)
        } else if timestamp > 1_000_000_000 {
            date = Date(timeIntervalSince1970: timestamp)
        } else {
            date = Date()
        }

        let sessionId: String
        if let pathComponents = url.pathComponents.first(where: { $0.count == 32 && $0.allSatisfy { $0.isHexDigit } }) {
            sessionId = pathComponents
        } else {
            let parts = url.path.components(separatedBy: "/")
            sessionId = parts.first(where: { $0.count >= 20 && $0.contains("-") }) ?? url.deletingPathExtension().lastPathComponent
        }

        let detail = "+\(addedLines) -\(removedLines) [\(status)]"

        return [AgentOpRecord(
            id: url.path,
            agentName: agentName,
            sessionId: sessionId,
            projectDir: "",
            timestamp: date,
            toolName: "file_change",
            targetPath: filePath,
            opType: opType,
            detail: detail
        )]
    }

    func parseAutoDetectedSource(url: URL, agentName: String) -> [AgentOpRecord] {
        let ext = url.pathExtension.lowercased()
        if ext == "vscdb" {
            return parseVscdbSQLite(url: url, agentName: agentName)
        }
        if ext == "db" || ext == "sqlite" {
            return parseAutoGenSQLite(url: url, agentName: agentName)
        }
        if ext == "json" && url.path.lowercased().contains("file-changes") {
            return parseFileChangesJSON(url: url, agentName: agentName)
        }
        return parseGenericJSONL(url: url, agentName: agentName)
    }

    private func parseGrokUpdates(url: URL, agentName: String) -> [AgentOpRecord] {
        guard url.lastPathComponent == "updates.jsonl",
              let content = readOperationTail(url: url, maxBytes: 2 * 1024 * 1024) else { return [] }
        let sessionId = url.deletingLastPathComponent().lastPathComponent
        let encodedCWD = url.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
        let cwd = encodedCWD.removingPercentEncoding ?? ""
        var records: [AgentOpRecord] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let params = event["params"] as? [String: Any],
                  let update = params["update"] as? [String: Any],
                  update["sessionUpdate"] as? String == "tool_call" else { continue }

            let toolName = (update["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? update["kind"] as? String
                ?? "tool"
            let input = update["rawInput"] as? [String: Any] ?? [:]
            let target = stringArg(input, ["file_path", "path", "cwd", "workdir", "pattern"]) ?? cwd
            let detail = stringArg(input, ["command", "cmd", "query", "content"])
                ?? jsonText(input)
            let rawTimestamp = (event["timestamp"] as? NSNumber)?.doubleValue ?? 0
            let timestamp = rawTimestamp > 0
                ? Date(timeIntervalSince1970: rawTimestamp > 9_999_999_999 ? rawTimestamp / 1_000 : rawTimestamp)
                : (fileModificationDate(url) ?? Date())
            records.append(AgentOpRecord(
                id: update["toolCallId"] as? String ?? UUID().uuidString,
                agentName: agentName,
                sessionId: params["sessionId"] as? String ?? sessionId,
                projectDir: cwd,
                timestamp: timestamp,
                toolName: toolName,
                targetPath: target,
                opType: classifyOpType(toolName),
                detail: String(detail.prefix(300))
            ))
        }
        return records
    }

    private func parseMiniMaxSQLite(url: URL, agentName: String) -> [AgentOpRecord] {
        guard fileManager.fileExists(atPath: url.path), fileManager.isReadableFile(atPath: url.path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT m.id, m.session_id, m.timestamp, m.data, COALESCE(s.workspace_dir, '')
        FROM session_messages m
        LEFT JOIN sessions s ON s.session_id = m.session_id
        WHERE m.data LIKE '%"tool_calls"%'
        ORDER BY m.timestamp DESC
        LIMIT 2000;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return parseAutoGenSQLite(url: url, agentName: agentName)
        }
        defer { sqlite3_finalize(stmt) }

        var records: [AgentOpRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowId = sqlite3_column_int64(stmt, 0)
            let sessionId = sqliteText(stmt, 1)
            let rawTimestamp = sqlite3_column_int64(stmt, 2)
            let rawData = sqliteText(stmt, 3)
            let cwd = sqliteText(stmt, 4)
            guard let data = rawData.data(using: .utf8),
                  let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let calls = message["tool_calls"] as? [[String: Any]] else { continue }
            let timestampValue = TimeInterval(rawTimestamp)
            let timestamp = Date(timeIntervalSince1970: timestampValue > 9_999_999_999 ? timestampValue / 1_000 : timestampValue)
            for (index, call) in calls.enumerated() {
                guard let record = genericToolCallRecord(
                    call,
                    agentName: agentName,
                    sessionId: sessionId,
                    cwd: cwd,
                    ts: timestamp
                ) else { continue }
                records.append(AgentOpRecord(
                    id: "minimax_\(rowId)_\(index)",
                    agentName: record.agentName,
                    sessionId: record.sessionId,
                    projectDir: record.projectDir,
                    timestamp: record.timestamp,
                    toolName: record.toolName,
                    targetPath: record.targetPath,
                    opType: record.opType,
                    detail: record.detail
                ))
            }
        }
        return records
    }

    private func readOperationTail(url: URL, maxBytes: Int) -> String? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              size > 0,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let start = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        do {
            try handle.seek(toOffset: start)
            guard let data = try handle.readToEnd() else { return nil }
            var content = String(decoding: data, as: UTF8.self)
            if start > 0, let newline = content.firstIndex(of: "\n") {
                content = String(content[content.index(after: newline)...])
            }
            return content
        } catch {
            return nil
        }
    }

    private func boundedStructuredData(url: URL) -> Data? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size >= 0,
              size <= structuredSessionReadLimit else { return nil }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }

    private func jsonText(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return String(describing: value) }
        return text
    }

    func parseGenericJSONL(url: URL, agentName: String) -> [AgentOpRecord] {
        guard let content = readOperationTail(url: url, maxBytes: genericOperationTailReadLimit) else { return [] }
        var records: [AgentOpRecord] = []
        let sessionId = url.deletingPathExtension().lastPathComponent
        var cwd = ""

        for line in content.components(separatedBy: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let type = json["type"] as? String ?? ""
            let ts = parseTimestamp(json["timestamp"] as? String)
                ?? parseTimestamp(json["createdAt"] as? String)
                ?? Date()

            if type == "session_meta" || type == "turn_context" {
                if let payload = json["payload"] as? [String: Any] {
                    cwd = payload["cwd"] as? String ?? cwd
                }
            }

            if type == "function_call" || type == "custom_tool_call" || type == "tool_call" {
                if let record = genericToolCallRecord(json, agentName: agentName, sessionId: sessionId, cwd: cwd, ts: ts) {
                    records.append(record)
                }
            } else if let payload = json["payload"] as? [String: Any] {
                let payloadType = payload["type"] as? String ?? ""
                if payloadType == "function_call" || payloadType == "custom_tool_call" || payloadType == "tool_call",
                   let record = genericToolCallRecord(payload, agentName: agentName, sessionId: sessionId, cwd: cwd, ts: ts) {
                    records.append(record)
                }
            }

            if let toolCalls = json["tool_calls"] as? [[String: Any]] {
                for call in toolCalls {
                    if let function = call["function"] as? [String: Any],
                       let record = genericToolCallRecord(function, agentName: agentName, sessionId: sessionId, cwd: cwd, ts: ts) {
                        records.append(record)
                    } else if let record = genericToolCallRecord(call, agentName: agentName, sessionId: sessionId, cwd: cwd, ts: ts) {
                        records.append(record)
                    }
                }
            }

            var contentBlocks: [[String: Any]] = []

            if let message = json["message"] as? [String: Any],
               let cb = message["content"] as? [[String: Any]] {
                contentBlocks = cb
                cwd = json["cwd"] as? String ?? cwd
            } else if let cb = json["content"] as? [[String: Any]] {
                contentBlocks = cb
            } else if let payload = json["payload"] as? [String: Any],
                      payload["type"] as? String == "message",
                      let cb = payload["content"] as? [[String: Any]] {
                contentBlocks = cb
                if let pCwd = payload["cwd"] as? String { cwd = pCwd }
            }

            for block in contentBlocks {
                let blockType = block["type"] as? String ?? ""

                if blockType == "tool_use" {
                    guard let toolName = block["name"] as? String else { continue }
                    let input = block["input"] as? [String: Any] ?? [:]
                    let targetPath = input["file_path"] as? String
                        ?? input["path"] as? String
                        ?? input["pattern"] as? String
                        ?? cwd
                    let opType = classifyOpType(toolName)
                    var detail = ""
                    let lower = toolName.lowercased()
                    if lower.contains("bash") || lower.contains("shell") || lower.contains("command") {
                        detail = input["command"] as? String ?? ""
                    }
                    records.append(AgentOpRecord(
                        id: UUID().uuidString,
                        agentName: agentName,
                        sessionId: sessionId,
                        projectDir: cwd,
                        timestamp: ts,
                        toolName: toolName,
                        targetPath: targetPath,
                        opType: opType,
                        detail: detail
                    ))
                } else if blockType == "input_text" || blockType == "text" {
                    let text = block["text"] as? String ?? ""
                    let ops = extractOpsFromText(text, agentName: agentName, sessionId: sessionId, cwd: cwd, ts: ts)
                    records.append(contentsOf: ops)
                }
            }

            if type == "event_msg" {
                if let payload = json["payload"] as? [String: Any],
                   payload["type"] as? String == "task_complete",
                   let lastMsg = payload["last_agent_message"] as? String, !lastMsg.isEmpty {
                    let ops = extractOpsFromText(lastMsg, agentName: agentName, sessionId: sessionId, cwd: cwd, ts: ts)
                    records.append(contentsOf: ops)
                }
            }
        }

        if records.isEmpty,
           let data = content.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) {
            records.append(contentsOf: recordsFromGenericJSONObject(
                object,
                agentName: agentName,
                sessionId: sessionId,
                cwd: cwd,
                timestamp: Date(),
                depth: 0
            ))
        }

        if records.isEmpty {
            records.append(contentsOf: extractOpsFromText(
                content,
                agentName: agentName,
                sessionId: sessionId,
                cwd: cwd,
                ts: fileModificationDate(url) ?? Date()
            ))
        }

        if records.isEmpty, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let summary = content
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            records.append(AgentOpRecord(
                id: "\(url.path)_session",
                agentName: agentName,
                sessionId: sessionId,
                projectDir: cwd,
                timestamp: fileModificationDate(url) ?? Date(),
                toolName: "session",
                targetPath: cwd,
                opType: "Chat",
                detail: String(summary.prefix(240))
            ))
        }

        return records
    }

    private func fileModificationDate(_ url: URL) -> Date? {
        (try? fileManager.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
    }

    private func genericToolCallRecord(
        _ value: [String: Any],
        agentName: String,
        sessionId: String,
        cwd: String,
        ts: Date
    ) -> AgentOpRecord? {
        let toolName = value["name"] as? String
            ?? value["tool_name"] as? String
            ?? value["tool"] as? String
            ?? value["action"] as? String
            ?? ""
        guard !toolName.isEmpty else { return nil }

        var input = value["input"] as? [String: Any]
            ?? value["arguments"] as? [String: Any]
            ?? value["args"] as? [String: Any]
            ?? [:]
        let argumentsText = value["arguments"] as? String
            ?? value["input"] as? String
            ?? value["args"] as? String
            ?? value["tool_call_args"] as? String
            ?? ""
        if input.isEmpty, let parsed = parseJSONString(argumentsText) {
            input = parsed
        }

        let target = stringArg(input, ["file_path", "path", "file", "target", "cwd", "workdir"])
            ?? firstPathLikeToken(in: argumentsText)
            ?? cwd
        let detail = stringArg(input, ["command", "cmd", "query", "pattern", "content"])
            ?? argumentsText

        return AgentOpRecord(
            id: UUID().uuidString,
            agentName: agentName,
            sessionId: sessionId,
            projectDir: stringArg(input, ["cwd", "workdir"]) ?? cwd,
            timestamp: ts,
            toolName: toolName,
            targetPath: target,
            opType: classifyOpType(toolName),
            detail: String(detail.prefix(300))
        )
    }

    private func recordsFromGenericJSONObject(
        _ object: Any,
        agentName: String,
        sessionId: String,
        cwd: String,
        timestamp: Date,
        depth: Int
    ) -> [AgentOpRecord] {
        guard depth < 8 else { return [] }
        if let array = object as? [Any] {
            return array.prefix(500).flatMap {
                recordsFromGenericJSONObject(
                    $0,
                    agentName: agentName,
                    sessionId: sessionId,
                    cwd: cwd,
                    timestamp: timestamp,
                    depth: depth + 1
                )
            }
        }
        guard let dict = object as? [String: Any] else { return [] }

        let nextSessionId = dict["session_id"] as? String
            ?? dict["sessionId"] as? String
            ?? dict["conversation_id"] as? String
            ?? sessionId
        let nextCwd = dict["cwd"] as? String
            ?? dict["projectDir"] as? String
            ?? dict["workspace"] as? String
            ?? cwd
        let nextTimestamp = parseTimestamp(dict["timestamp"] as? String)
            ?? parseTimestamp(dict["createdAt"] as? String)
            ?? timestamp

        var records: [AgentOpRecord] = []
        let type = (dict["type"] as? String ?? "").lowercased()
        if type.contains("tool") || type.contains("function") || dict["tool_name"] != nil || dict["action"] != nil {
            if let record = genericToolCallRecord(
                dict,
                agentName: agentName,
                sessionId: nextSessionId,
                cwd: nextCwd,
                ts: nextTimestamp
            ) {
                records.append(record)
            }
        }

        for value in dict.values {
            records.append(contentsOf: recordsFromGenericJSONObject(
                value,
                agentName: agentName,
                sessionId: nextSessionId,
                cwd: nextCwd,
                timestamp: nextTimestamp,
                depth: depth + 1
            ))
            if records.count >= 1000 { break }
        }
        return records
    }

    private func parseTimestamp(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str)
    }
}
