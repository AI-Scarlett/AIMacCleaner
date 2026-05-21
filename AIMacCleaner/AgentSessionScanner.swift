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

    init() {
        registerBuiltInSources()
    }

    func searchJSONLDirs(forAgentName name: String, bundlePath: String?) -> [String] {
        let home = NSHomeDirectory()
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
            if lastComponent == ".git" { return true }
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
        registerKimi()
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
        dataSources.append(source)
    }

    func removeDataSource(forAgentName name: String) {
        dataSources.removeAll { $0.agentName == name && $0.isCustom }
    }

    func scanAllAgents() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async { self.scanError = "" }

            var merged: [String: DiscoveredAgent] = [:]

            for source in self.dataSources {
                let home = NSHomeDirectory()
                let expandedPaths = source.searchPaths.map { $0.replacingOccurrences(of: "~", with: home) }

                var sourceHasResults = false

                for basePath in expandedPaths {
                    guard self.fileManager.fileExists(atPath: basePath) else { continue }
                    var isDir: ObjCBool = false
                    self.fileManager.fileExists(atPath: basePath, isDirectory: &isDir)
                    guard isDir.boolValue else { continue }

                    let depthLimit = 10
                    var sessionCount = 0
                    var latestDate: Date?
                    var projectDirs = Set<String>()

                    guard let enumerator = self.fileManager.enumerator(at: URL(fileURLWithPath: basePath), includingPropertiesForKeys: nil) else { continue }

                    for case let itemURL as URL in enumerator {
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

                        if path.hasSuffix(".jsonl") || path.hasSuffix(source.filePattern) || path.hasSuffix(".sqlite") || path.hasSuffix(".vscdb") || path.hasSuffix(".db") || path.hasSuffix(".md") || (itemURL.pathExtension == "json" && (path.contains("file-changes") || path.contains("session") || path.contains("events") || path.contains("conversation") || path.contains("trajectory") || itemURL.lastPathComponent == "entries.json")) {
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
                            sessionCount: (existing?.sessionCount ?? 0) + sessionCount,
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
                self.isScanning = false
                print("[AgentSessionScanner] Found \(results.count) agents with sessions")
            }
        }
    }

    func scanAgentOps(agentName: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            DispatchQueue.main.async { self.scanError = "" }

            var allRecords: [AgentOpRecord] = []
            let home = NSHomeDirectory()

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
                        print("[AgentSessionScanner] found \(urls.count) session files in \(basePath)")
                        for url in urls {
                            let records = source.parser(url, agentName)
                            allRecords.append(contentsOf: records)
                        }
                    } else {
                        let url = URL(fileURLWithPath: basePath)
                        let records = source.parser(url, agentName)
                        allRecords.append(contentsOf: records)
                    }
                }
            }

            allRecords.sort { $0.timestamp > $1.timestamp }
            if allRecords.count > 10000 { allRecords = Array(allRecords.prefix(10000)) }

            DispatchQueue.main.async {
                self.opRecords = allRecords
                self.isScanning = false
                print("[AgentSessionScanner] Found \(allRecords.count) op records for \(agentName)")
            }
        }
    }

    private func findSessionFiles(in dir: String, pattern: String) -> [URL] {
        var results: [URL] = []
        guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: nil) else { return results }
        for case let url as URL in enumerator {
            let relPath = String(url.path.dropFirst(dir.count + 1))
            let depth = relPath.components(separatedBy: "/").count
            if depth > 10 {
                enumerator.skipDescendants()
                continue
            }
            let lastComponent = url.lastPathComponent
            if lastComponent == ".git" {
                results.append(url)
                enumerator.skipDescendants()
                continue
            }
            if lastComponent.hasPrefix(".") && lastComponent != ".jsonl" {
                enumerator.skipDescendants()
                continue
            }
            let ext = url.pathExtension
            if ext == "jsonl" || url.path.hasSuffix(pattern) || ext == "sqlite" || ext == "md" || ext == "db" {
                results.append(url)
            } else if ext == "json" && (url.path.contains("file-changes") || url.path.contains("session") || url.path.contains("events") || url.path.contains("conversation") || url.path.contains("trajectory") || url.lastPathComponent == "entries.json") {
                results.append(url)
            } else if ext == "vscdb" {
                results.append(url)
            }
        }
        return results
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
        let home = NSHomeDirectory()
        let paths = [
            home + "/.claude/projects",
            home + "/.config/claude/projects"
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
        let home = NSHomeDirectory()
        let paths = [
            home + "/.codex/sessions"
        ]
        let source = AgentDataSource(
            agentName: "Codex",
            searchPaths: paths,
            filePattern: ".jsonl",
            parser: { [weak self] url, name in
                self?.parseCodexJSONL(url: url, agentName: name) ?? []
            }
        )
        dataSources.append(source)
    }

    private func registerKimi() {
        let home = NSHomeDirectory()
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

    private func registerAider() {
        let home = NSHomeDirectory()
        let source = AgentDataSource(
            agentName: "Aider",
            searchPaths: [home + "/.aider"],
            filePattern: ".md",
            parser: { url, name in
                guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
                var records: [AgentOpRecord] = []
                let lines = content.components(separatedBy: "\n")
                for (i, line) in lines.enumerated() {
                    if line.hasPrefix("##### ") || line.contains("ADDED:") || line.contains("EDITED:") || line.contains("DELETED:") {
                        let opType: String
                        if line.contains("ADDED") { opType = "新增" }
                        else if line.contains("EDITED") { opType = "编辑" }
                        else if line.contains("DELETED") { opType = "删除" }
                        else { opType = "操作" }
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
        let paths = [
            home + "/.opencode"
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
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
        let home = NSHomeDirectory()
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
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
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

        guard let data = try? Data(contentsOf: url),
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
                opType: "对话",
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
                        opType: "对话",
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
                        opType: "操作",
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
            if lower.contains("session") || lower.contains("message") || lower.contains("conversation") || lower.contains("workflow") {
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
                            opType: "对话",
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
        guard let data = try? Data(contentsOf: url),
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
                opType: "对话",
                detail: ""
            ))
        }

        return records
    }

    private func registerTrae() {
        let home = NSHomeDirectory()
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
            opType: "写入",
            detail: "\(fileCount)\(localizer?.fileChangeCount ?? "files changed")"
        ))

        return records
    }

    private func parseTraeSandbox(url: URL, agentName: String) -> [AgentOpRecord] {
        guard let data = try? Data(contentsOf: url),
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
            opType: "操作",
            detail: "\(localizer?.allowedPaths ?? "Allowed access"): \(allowedPaths.count)\(localizer?.pathsCount ?? "paths")"
        )]
    }

    private func parseTraeHistory(url: URL, agentName: String) -> [AgentOpRecord] {
        let filename = url.lastPathComponent
        guard filename == "entries.json" else { return [] }

        guard let data = try? Data(contentsOf: url),
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
            if source.contains("编辑") || source.contains("edit") || source.contains("Edit") {
                opType = "编辑"
            } else if source.contains("保存") || source.contains("save") || source.contains("Save") {
                opType = "写入"
            } else if source.contains("删除") || source.contains("delete") {
                opType = "删除"
            } else {
                opType = "编辑"
            }

            records.append(AgentOpRecord(
                id: "trae_history_\(dirName)_\(entryId)",
                agentName: agentName,
                sessionId: dirName,
                projectDir: "",
                timestamp: date,
                toolName: "file_edit",
                targetPath: resourcePath,
                opType: opType,
                detail: source
            ))
        }

        return records
    }

    private func registerGenericAutoDiscovery() {
        let home = NSHomeDirectory()
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

            let parser: (URL, String) -> [AgentOpRecord]
            if isVSCode {
                parser = { [weak self] url, agentName in
                    guard let self = self else { return [] }
                    let ext = url.pathExtension
                    if ext == "vscdb" {
                        return self.parseVscdbSQLite(url: url, agentName: agentName)
                    } else if ext == "json" && url.path.contains("file-changes") {
                        return self.parseFileChangesJSON(url: url, agentName: agentName)
                    } else {
                        return self.parseGenericJSONL(url: url, agentName: agentName)
                    }
                }
            } else {
                parser = { [weak self] url, agentName in
                    guard let self = self else { return [] }
                    let ext = url.pathExtension
                    if ext == "vscdb" {
                        return self.parseVscdbSQLite(url: url, agentName: agentName)
                    } else if ext == "json" && url.path.contains("file-changes") {
                        return self.parseFileChangesJSON(url: url, agentName: agentName)
                    } else if ext == "db" || ext == "sqlite" {
                        return self.parseGenericJSONL(url: url, agentName: agentName)
                    } else {
                        return self.parseGenericJSONL(url: url, agentName: agentName)
                    }
                }
            }

            let source = AgentDataSource(
                agentName: name,
                searchPaths: paths,
                isVSCodeType: isVSCode,
                parser: parser
            )
            dataSources.append(source)
        }
    }

    private func parseClaudeCodeJSONL(url: URL, agentName: String) -> [AgentOpRecord] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
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
                    opType = "写入"
                    targetPath = input["file_path"] as? String ?? input["path"] as? String ?? cwd
                    detail = (input["content"] as? String ?? "").prefix(200).description
                case "Edit", "MultiEdit":
                    opType = "编辑"
                    targetPath = input["file_path"] as? String ?? input["path"] as? String ?? cwd
                    detail = input["old_string"] as? String ?? ""
                case "Read":
                    opType = "读取"
                    targetPath = input["file_path"] as? String ?? input["path"] as? String ?? cwd
                    detail = ""
                case "Bash":
                    opType = "执行命令"
                    targetPath = cwd
                    detail = input["command"] as? String ?? ""
                case "Glob", "Grep":
                    opType = "搜索"
                    targetPath = input["pattern"] as? String ?? input["file_path"] as? String ?? input["path"] as? String ?? cwd
                    detail = ""
                default:
                    opType = "操作"
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
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var records: [AgentOpRecord] = []
        let sessionId = url.deletingPathExtension().lastPathComponent
        var cwd = ""

        for line in content.components(separatedBy: "\n") {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

            let type = json["type"] as? String ?? ""

            if type == "turn_context" {
                if let payload = json["payload"] as? [String: Any] {
                    cwd = payload["cwd"] as? String ?? cwd
                }
            }

            if type == "response_item" {
                guard let payload = json["payload"] as? [String: Any] else { continue }
                let payloadType = payload["type"] as? String ?? ""

                if payloadType == "message" {
                    let role = payload["role"] as? String ?? ""
                    guard role == "assistant" else { continue }
                    let contentBlocks = payload["content"] as? [[String: Any]] ?? []
                    let ts = parseTimestamp(json["timestamp"] as? String) ?? Date()

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

    private func extractOpsFromText(_ text: String, agentName: String, sessionId: String, cwd: String, ts: Date) -> [AgentOpRecord] {
        var records: [AgentOpRecord] = []
        let patterns: [(String, [String], String)] = [
            ("写入", ["write", "created", "wrote", "saved"], #"(?:to|at|in|→)\s+[`\"']?(/[^\s`\"']+)[`\"']?"#),
            ("编辑", ["edit", "modified", "updated", "changed"], #"(?:file|at|in|→)\s+[`\"']?(/[^\s`\"']+)[`\"']?"#),
            ("读取", ["read", "viewed", "opened", "checked"], #"(?:file|at|in|→)\s+[`\"']?(/[^\s`\"']+)[`\"']?"#),
            ("删除", ["delete", "removed", "deleted"], #"(?:file|at|in|→)\s+[`\"']?(/[^\s`\"']+)[`\"']?"#),
            ("执行命令", ["ran ", "executed", "command", "shell", "bash"], #"(?:ran|executed|command|bash|shell)[:\s]+[`\"']?([^`\"'\n]+)[`\"']?"#),
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
        if lower.contains("write") || lower.contains("create") { return "写入" }
        if lower.contains("edit") || lower.contains("update") { return "编辑" }
        if lower.contains("read") || lower.contains("view") || lower.contains("get") { return "读取" }
        if lower.contains("delete") || lower.contains("remove") { return "删除" }
        if lower.contains("bash") || lower.contains("shell") || lower.contains("exec") || lower.contains("command") { return "执行命令" }
        if lower.contains("search") || lower.contains("glob") || lower.contains("grep") || lower.contains("find") { return "搜索" }
        return "操作"
    }

    static func localizedOpType(_ opType: String, localizer: Localizer) -> String {
        switch opType {
        case "写入": return localizer.opWrite
        case "编辑": return localizer.opEdit
        case "读取": return localizer.opRead
        case "删除": return localizer.opDelete2
        case "执行命令": return localizer.opExec
        case "搜索": return localizer.opSearch
        case "操作": return localizer.opAction
        case "对话": return localizer.opDialogue
        case "新增": return localizer.opNew
        case "保存": return localizer.opSave
        case "打开": return localizer.opOpen
        case "关闭": return localizer.opClose
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
        if let wsData = try? Data(contentsOf: URL(fileURLWithPath: wsPath)),
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
                            opType: "对话",
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
                                    opType: "对话",
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
                        opType: "对话",
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
                        opType: "操作",
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
                        opType: "操作",
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
                    opType: "操作",
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
                        opType: "操作",
                        detail: "status=\(status) parent_session=\(badgeSessionId)"
                    ))
                }
            }
        }

        return records
    }

    func parseFileChangesJSON(url: URL, agentName: String) -> [AgentOpRecord] {
        guard let data = try? Data(contentsOf: url),
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
        case "create": opType = "写入"
        case "edit", "modify", "update": opType = "编辑"
        case "delete", "remove": opType = "删除"
        default:
            if addedLines > 0 && removedLines == 0 { opType = "写入" }
            else if addedLines > 0 && removedLines > 0 { opType = "编辑" }
            else if removedLines > 0 && addedLines == 0 { opType = "删除" }
            else { opType = "编辑" }
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

    func parseGenericJSONL(url: URL, agentName: String) -> [AgentOpRecord] {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
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

            if type == "turn_context" {
                if let payload = json["payload"] as? [String: Any] {
                    cwd = payload["cwd"] as? String ?? cwd
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

        return records
    }

    private func parseTimestamp(_ str: String?) -> Date? {
        guard let str = str else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: str) ?? ISO8601DateFormatter().date(from: str)
    }
}
