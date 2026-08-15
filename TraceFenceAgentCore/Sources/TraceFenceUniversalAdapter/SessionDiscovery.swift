import Foundation
import Darwin
import SQLite3

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class SessionDiscovery {
    private let profile: UniversalAdapterProfile
    private let store: AdapterStateStore
    private let fileManager = FileManager.default

    init(profile: UniversalAdapterProfile, store: AdapterStateStore) {
        self.profile = profile
        self.store = store
    }

    func health() -> [String: Any] {
        let commandInstalled = profile.commandURL != nil
        let dataPresent = profile.dataPresent
        let appPresent = profile.applicationPresent
        let installed = commandInstalled || dataPresent || appPresent
        let providerFailure = recentProviderFailure()
        let canControl = profile.supportsDirectControl && providerFailure == nil
        let nativeApprovalAvailable = profile.id == "opencode" && canControl
            || profile.id == "minimax" && miniMaxSessions().contains { ($0["controlAvailable"] as? Bool) == true }
        let approvalAvailable = (profile.supportsApprovalHook && commandInstalled && providerFailure == nil)
            || nativeApprovalAvailable
        var capabilities = ["independent_update", "capability_negotiation"]
        if installed { capabilities += ["session_discovery", "session_context"] }
        if canControl { capabilities += ["instruction", "interrupt"] }
        if approvalAvailable { capabilities.append("approval") }
        let tier: String
        if canControl {
            tier = profile.id == "opencode" || profile.id == "minimax" ? "native_control_plane" : "managed_headless"
        } else if installed {
            tier = "monitor_only"
        } else {
            tier = "unavailable"
        }
        var result: [String: Any] = [
            "installed": installed,
            "commandInstalled": commandInstalled,
            "applicationInstalled": appPresent,
            "dataPresent": dataPresent,
            "operational": installed,
            "controlAvailable": canControl,
            "approvalAvailable": approvalAvailable,
            "integrationTier": tier,
            "capabilities": Array(Set(capabilities)).sorted(),
            "documentationURL": profile.documentationURL,
            "message": providerFailure ?? healthMessage(installed: installed, canControl: canControl)
        ]
        if providerFailure != nil { result["authenticated"] = false }
        return result
    }

    func sessions() -> [[String: Any]] {
        var values: [[String: Any]]
        switch profile.id {
        case "grok": values = grokSessions()
        case "qwen": values = qwenSessions()
        case "cursor": values = cursorSessions()
        case "trae": values = traeSessions()
        case "codebuddy": values = codeBuddySessions()
        case "openclaw": values = openClawSessions()
        case "hermes": values = hermesSessions()
        case "minimax": values = miniMaxSessions()
        case "gemini": values = genericJSONSessions(roots: ["~/.gemini/tmp", "~/.gemini/sessions"], agentType: "Gemini CLI")
        case "opencode": values = genericJSONSessions(roots: ["~/.local/share/opencode/storage/session", "~/.local/share/opencode"], agentType: "OpenCode")
        case "kiro": values = genericJSONSessions(roots: ["~/.kiro/sessions"], agentType: "Kiro CLI")
        case "aider": values = aiderSessions()
        case "deepseek-harness": values = deepSeekHarnessSessions()
        default: values = []
        }

        var merged = Dictionary(uniqueKeysWithValues: values.compactMap { value -> (String, [String: Any])? in
            guard let id = value["id"] as? String, !id.isEmpty else { return nil }
            return (id, value)
        })

        for job in store.jobs(adapterId: profile.id) {
            let id = job.nativeSessionId.isEmpty ? job.id : job.nativeSessionId
            var value = merged[id] ?? baseSession(
                id: id,
                title: job.title,
                cwd: job.cwd,
                createdAt: job.createdAt,
                updatedAt: job.updatedAt,
                model: profile.displayName,
                sourcePath: job.outputPath
            )
            let alive = processIsAlive(job.pid)
            let output = store.outputTail(path: job.outputPath)
            let providerFailure = providerFailure(in: output)
            let inactivePhase = job.phase == "processing" ? "done" : job.phase
            value["phase"] = alive ? "processing" : (providerFailure == nil ? inactivePhase : "error")
            value["updatedAt"] = max(job.updatedAt, fileModifiedAt(job.outputPath))
            value["controlAvailable"] = providerFailure == nil
            value["controlReason"] = providerFailure == nil ? "managed_agent_process" : "provider_authentication_failed"
            value["controlMode"] = providerFailure == nil ? "tracefence_agent_core" : "display_only"
            value["pid"] = Int(job.pid)
            value["lastResponse"] = output
            if let providerFailure { value["controlError"] = providerFailure }
            if (value["sourcePath"] as? String)?.isEmpty != false { value["sourcePath"] = job.outputPath }
            merged[id] = value
        }

        attachHookApprovals(to: &merged)
        return merged.values.sorted {
            let leftWaiting = ($0["phase"] as? String)?.hasPrefix("waiting") == true
            let rightWaiting = ($1["phase"] as? String)?.hasPrefix("waiting") == true
            if leftWaiting != rightWaiting { return leftWaiting }
            return unixTime($0["updatedAt"]) > unixTime($1["updatedAt"])
        }.prefix(100).map { $0 }
    }

    func context(sessionId: String, cursor: String?, limit: Int, turnLimit: Int? = nil) -> [String: Any] {
        let all = sessions()
        let row = all.first { $0["id"] as? String == sessionId }
        let sourcePath = row?["sourcePath"] as? String ?? ""
        var records: [[String: Any]]
        switch profile.id {
        case "grok": records = parseGrokContext(path: sourcePath)
        case "qwen": records = parseQwenContext(path: sourcePath)
        case "codebuddy": records = parseCodeBuddyContext(path: sourcePath, sessionId: sessionId)
        case "hermes": records = hermesContext(sessionId: sessionId, sourcePath: sourcePath)
        case "minimax": records = miniMaxContext(sessionId: sessionId)
        default: records = parseGenericContext(path: sourcePath)
        }
        if profile.id == "qwen",
           let job = store.job(adapterId: profile.id, sessionId: sessionId),
           job.outputPath != sourcePath {
            records.append(contentsOf: parseQwenContext(path: job.outputPath))
        }
        records = assignTurnIdentifiers(records)
        let requested = min(max(limit, 20), 120)
        let requestedEnd = cursor.flatMap(Int.init) ?? records.count
        let end = min(max(requestedEnd, 0), records.count)
        let start: Int
        if let turnLimit {
            start = semanticPageStart(
                records: records,
                end: end,
                turnLimit: min(max(turnLimit, 1), 10)
            )
        } else {
            start = max(0, end - requested)
        }
        let selectedRecords = turnLimit == nil
            ? Array(records[start..<end])
            : compactSemanticTurns(Array(records[start..<end]), maxRecordsPerTurn: 64)
        var result: [String: Any] = [
            "messages": selectedRecords,
            "totalCount": records.count,
            "hasMore": start > 0,
            "truncated": false
        ]
        if start > 0 { result["nextCursor"] = String(start) }
        if records.isEmpty {
            result["warning"] = contextWarning()
        }
        return result
    }

    private func assignTurnIdentifiers(_ records: [[String: Any]]) -> [[String: Any]] {
        var result = records
        var currentTurnId: String?
        var currentTurnHasUserMessage = false

        for index in result.indices {
            let explicitTurnId = (result[index]["turnId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let explicitTurnId, !explicitTurnId.isEmpty {
                if explicitTurnId != currentTurnId {
                    currentTurnId = explicitTurnId
                    currentTurnHasUserMessage = false
                }
            } else {
                let role = result[index]["role"] as? String ?? "assistant"
                let kind = result[index]["kind"] as? String ?? "message"
                let text = result[index]["text"] as? String ?? ""
                let startsTask = kind == "event" && text == "task_started"
                let startsUserTurn = role == "user" && currentTurnHasUserMessage
                if currentTurnId == nil || startsTask || startsUserTurn {
                    let recordId = result[index]["id"] as? String ?? String(index)
                    currentTurnId = "derived:\(recordId)"
                    currentTurnHasUserMessage = false
                }
                result[index]["turnId"] = currentTurnId
            }
            if result[index]["role"] as? String == "user" {
                currentTurnHasUserMessage = true
            }
        }
        return result
    }

    private func semanticPageStart(
        records: [[String: Any]],
        end: Int,
        turnLimit: Int
    ) -> Int {
        guard end > 0 else { return 0 }
        var start = end
        var mostRecentTurnId: String?
        var turnCount = 0

        for index in stride(from: end - 1, through: 0, by: -1) {
            let recordId = records[index]["id"] as? String ?? String(index)
            let currentTurnId = records[index]["turnId"] as? String ?? "derived:\(recordId)"
            if currentTurnId != mostRecentTurnId {
                guard turnCount < turnLimit else { break }
                turnCount += 1
                mostRecentTurnId = currentTurnId
            }
            start = index
        }
        return start
    }

    private func compactSemanticTurns(_ records: [[String: Any]], maxRecordsPerTurn: Int) -> [[String: Any]] {
        guard !records.isEmpty else { return [] }
        var result: [[String: Any]] = []
        var groupStart = 0

        while groupStart < records.count {
            let firstRecordId = records[groupStart]["id"] as? String ?? String(groupStart)
            let turnId = records[groupStart]["turnId"] as? String ?? "derived:\(firstRecordId)"
            var groupEnd = groupStart + 1
            while groupEnd < records.count {
                let recordId = records[groupEnd]["id"] as? String ?? String(groupEnd)
                let recordTurnId = records[groupEnd]["turnId"] as? String ?? "derived:\(recordId)"
                guard recordTurnId == turnId else { break }
                groupEnd += 1
            }

            let group = Array(records[groupStart..<groupEnd])
            if group.count <= maxRecordsPerTurn {
                result.append(contentsOf: group)
            } else {
                let recordBudget = maxRecordsPerTurn - 1
                let important = group.indices.filter {
                    let role = group[$0]["role"] as? String
                    return role == "user" || role == "assistant" || group[$0]["kind"] as? String == "event"
                }
                var selected = balancedIndices(important, limit: recordBudget)
                if selected.count < recordBudget {
                    let selectedSet = Set(selected)
                    let remaining = group.indices.filter { !selectedSet.contains($0) }
                    selected.append(contentsOf: balancedIndices(remaining, limit: recordBudget - selected.count))
                }
                selected.sort()

                var marker: [String: Any] = [
                    "id": "tracefence-context-compacted-\(firstRecordId)",
                    "role": "system",
                    "kind": "event",
                    "text": "context_compacted",
                    "status": "\(group.count - selected.count)_records_omitted",
                    "turnId": turnId
                ]
                if let timestamp = group.last?["timestamp"] { marker["timestamp"] = timestamp }

                var insertedMarker = false
                var previousIndex: Int?
                for index in selected {
                    if !insertedMarker, let previousIndex, index - previousIndex > 1 {
                        result.append(marker)
                        insertedMarker = true
                    }
                    result.append(group[index])
                    previousIndex = index
                }
                if !insertedMarker { result.append(marker) }
            }
            groupStart = groupEnd
        }
        return result
    }

    private func balancedIndices(_ indices: [Int], limit: Int) -> [Int] {
        guard limit > 0, indices.count > limit else { return limit > 0 ? indices : [] }
        let leadingCount = limit / 3
        let trailingCount = limit - leadingCount
        return Array(indices.prefix(leadingCount)) + Array(indices.suffix(trailingCount))
    }

    private func grokSessions() -> [[String: Any]] {
        let root = URL(fileURLWithPath: expandPath("~/.grok/sessions"), isDirectory: true)
        return recentFiles(root: root, matching: { $0.lastPathComponent == "summary.json" }, maxDepth: 4, limit: 100).compactMap { url in
            guard let data = boundedData(contentsOf: url), let object = jsonObject(data) else { return nil }
            let info = object["info"] as? [String: Any] ?? [:]
            let id = info["id"] as? String ?? url.deletingLastPathComponent().lastPathComponent
            let cwd = info["cwd"] as? String ?? ""
            let title = object["generated_title"] as? String
                ?? object["session_summary"] as? String
                ?? "Grok session"
            let created = unixTime(object["created_at"])
            let updated = max(unixTime(object["updated_at"]), unixTime(object["last_active_at"]))
            let transcript = url.deletingLastPathComponent().appendingPathComponent("updates.jsonl")
            return baseSession(
                id: id,
                title: title,
                cwd: cwd,
                createdAt: created,
                updatedAt: updated,
                model: object["current_model_id"] as? String ?? "Grok",
                sourcePath: fileManager.fileExists(atPath: transcript.path) ? transcript.path : ""
            )
        }
    }

    private func qwenSessions() -> [[String: Any]] {
        let root = URL(fileURLWithPath: expandPath("~/.qwen/projects"), isDirectory: true)
        return recentFiles(root: root, matching: { $0.pathExtension == "jsonl" }, maxDepth: 5, limit: 100).map { url in
            let sample = firstJSONLines(url: url, limit: 40)
            let first = sample.first ?? [:]
            let id = first["sessionId"] as? String ?? url.deletingPathExtension().lastPathComponent
            let cwd = first["cwd"] as? String ?? ""
            let user = sample.first { ($0["type"] as? String) == "user" }
            let title = extractedText((user?["message"] as? [String: Any])?["parts"])
            let created = sample.compactMap { unixTime($0["timestamp"]) }.filter { $0 > 0 }.min() ?? fileCreatedAt(url.path)
            return baseSession(
                id: id,
                title: title.isEmpty ? "Qwen session" : String(title.prefix(180)),
                cwd: cwd,
                createdAt: created,
                updatedAt: fileModifiedAt(url.path),
                model: "Qwen Code",
                sourcePath: url.path
            )
        }
    }

    private func cursorSessions() -> [[String: Any]] {
        let databasePath = expandPath("~/Library/Application Support/Cursor/User/globalStorage/state.vscdb")
        if let database = SQLiteReadOnlyDatabase(path: databasePath),
           let raw = database.rows(
            sql: "SELECT value FROM ItemTable WHERE key = ? LIMIT 1",
            bindings: ["composer.composerHeaders"]
           ).first?["value"] as? String,
           let data = raw.data(using: .utf8),
           let object = jsonObject(data),
           let headers = object["allComposers"] as? [[String: Any]] {
            let modifiedAt = fileModifiedAt(databasePath)
            let rows = headers.compactMap { header -> [String: Any]? in
                guard let id = header["composerId"] as? String, !id.isEmpty,
                      (header["unifiedMode"] as? String ?? "agent") == "agent" else { return nil }
                let workspaceId = (header["workspaceIdentifier"] as? [String: Any])?["id"] as? String ?? ""
                let cwd = cursorWorkspacePath(id: workspaceId)
                let detailRaw = database.rows(
                    sql: "SELECT value FROM cursorDiskKV WHERE key = ? LIMIT 1",
                    bindings: ["composerData:\(id)"]
                ).first?["value"] as? String
                let detail = detailRaw?.data(using: .utf8).flatMap(jsonObject) ?? [:]
                let draft = (detail["text"] as? String ?? detail["richText"] as? String ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let title = header["name"] as? String
                    ?? detail["name"] as? String
                    ?? (draft.isEmpty ? "Cursor Agent session" : String(draft.prefix(180)))
                let createdAt = unixTime(header["createdAt"] ?? detail["createdAt"])
                let status = (detail["status"] as? String ?? "").lowercased()
                let generating = !(detail["generatingBubbleIds"] as? [Any] ?? []).isEmpty
                var session = baseSession(
                    id: id,
                    title: title,
                    cwd: cwd,
                    createdAt: createdAt,
                    updatedAt: max(createdAt, modifiedAt),
                    model: (detail["modelConfig"] as? [String: Any])?["modelName"] as? String ?? "Cursor",
                    sourcePath: "",
                    forceControlAvailable: false
                )
                session["phase"] = generating || ["running", "generating", "processing"].contains(status) ? "processing" : "idle"
                session["controlReason"] = "cursor_desktop_has_no_supported_local_control_api_install_cli"
                return session
            }
            if !rows.isEmpty { return rows }
        }

        let root = URL(fileURLWithPath: expandPath("~/Library/Application Support/Cursor/User/workspaceStorage"), isDirectory: true)
        guard let directories = try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return directories.compactMap { directory -> [String: Any]? in
            let workspace = directory.appendingPathComponent("workspace.json")
            guard let data = boundedData(contentsOf: workspace), let object = jsonObject(data) else { return nil }
            let folder = object["folder"] as? String ?? ""
            let cwd: String
            if let url = URL(string: folder), url.isFileURL { cwd = url.path } else { cwd = folder }
            let state = directory.appendingPathComponent("state.vscdb")
            return baseSession(
                id: "workspace-\(directory.lastPathComponent)",
                title: cwd.isEmpty ? "Cursor workspace" : URL(fileURLWithPath: cwd).lastPathComponent,
                cwd: cwd,
                createdAt: fileCreatedAt(workspace.path),
                updatedAt: max(fileModifiedAt(workspace.path), fileModifiedAt(state.path)),
                model: "Cursor",
                sourcePath: "",
                forceControlAvailable: profile.commandURL != nil
            )
        }
    }

    private func cursorWorkspacePath(id: String) -> String {
        guard !id.isEmpty else { return "" }
        let workspace = URL(fileURLWithPath: expandPath("~/Library/Application Support/Cursor/User/workspaceStorage"), isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
            .appendingPathComponent("workspace.json")
        guard let data = boundedData(contentsOf: workspace), let object = jsonObject(data),
              let folder = object["folder"] as? String else { return "" }
        if let url = URL(string: folder), url.isFileURL { return url.path }
        return folder.removingPercentEncoding ?? folder
    }

    private func traeSessions() -> [[String: Any]] {
        let roots = [
            expandPath("~/Library/Application Support/Trae CN"),
            expandPath("~/Library/Application Support/Trae")
        ]
        var sessions: [String: [String: Any]] = [:]
        for root in roots where fileManager.fileExists(atPath: root) {
            let storage = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("User/workspaceStorage", isDirectory: true)
            var databases: [(URL, String)] = []
            let global = URL(fileURLWithPath: root, isDirectory: true).appendingPathComponent("User/globalStorage/state.vscdb")
            if fileManager.fileExists(atPath: global.path) { databases.append((global, "")) }
            if let directories = try? fileManager.contentsOfDirectory(at: storage, includingPropertiesForKeys: [.contentModificationDateKey]) {
                for directory in directories {
                    let database = directory.appendingPathComponent("state.vscdb")
                    guard fileManager.fileExists(atPath: database.path) else { continue }
                    databases.append((database, vscodeWorkspacePath(directory: directory)))
                }
            }
            for (databaseURL, cwd) in databases.sorted(by: { fileModifiedAt($0.0.path) > fileModifiedAt($1.0.path) }).prefix(30) {
                for row in traeSessions(databasePath: databaseURL.path, cwd: cwd) {
                    guard let id = row["id"] as? String else { continue }
                    if unixTime(row["updatedAt"]) > unixTime(sessions[id]?["updatedAt"]) { sessions[id] = row }
                }
            }
        }
        return Array(sessions.values)
    }

    private func traeSessions(databasePath: String, cwd: String) -> [[String: Any]] {
        guard let database = SQLiteReadOnlyDatabase(path: databasePath) else { return [] }
        let rows = database.rows(sql: """
        SELECT key, value FROM ItemTable
        WHERE key LIKE '%ChatStore' OR key LIKE '%sessionRelation:modelMap'
           OR key = 'icube_session_agent_map' OR key = 'memento/icube-ai-agent-storage'
        LIMIT 300
        """)
        var models: [String: String] = [:]
        for row in rows where (row["key"] as? String ?? "").contains("sessionRelation:modelMap") {
            guard let raw = row["value"] as? String, let data = raw.data(using: .utf8), let object = jsonObject(data) else { continue }
            for (id, value) in object { models[id] = jsonString(value, limit: 200) }
        }
        let modifiedAt = fileModifiedAt(databasePath)
        var sessions: [String: [String: Any]] = [:]
        for row in rows {
            let key = row["key"] as? String ?? ""
            guard let raw = row["value"] as? String, let data = raw.data(using: .utf8) else { continue }
            if key.hasSuffix("ChatStore"), let object = jsonObject(data), let entries = object["entries"] as? [String: Any] {
                for (id, rawEntry) in entries {
                    let entry = rawEntry as? [String: Any] ?? [:]
                    let title = entry["title"] as? String ?? entry["lastMessage"] as? String ?? "Trae session"
                    let createdAt = unixTime(entry["createdAt"] ?? entry["lastMessageDate"])
                    sessions[id] = baseSession(
                        id: id,
                        title: title,
                        cwd: cwd,
                        createdAt: createdAt,
                        updatedAt: max(createdAt, modifiedAt),
                        model: models[id] ?? "Trae",
                        sourcePath: "",
                        forceControlAvailable: false
                    )
                }
            } else if key == "memento/icube-ai-agent-storage", let object = jsonObject(data), let list = object["list"] as? [[String: Any]] {
                for item in list {
                    guard let id = item["sessionId"] as? String, !id.isEmpty else { continue }
                    let createdAt = dateFromObjectIdentifier(id) ?? modifiedAt
                    var session = sessions[id] ?? baseSession(
                        id: id,
                        title: item["title"] as? String ?? "Trae session",
                        cwd: cwd,
                        createdAt: createdAt,
                        updatedAt: modifiedAt,
                        model: models[id] ?? "Trae",
                        sourcePath: "",
                        forceControlAvailable: false
                    )
                    if item["isCurrent"] as? Bool == true, Date().timeIntervalSince1970 - modifiedAt < 300 {
                        session["phase"] = "processing"
                    }
                    sessions[id] = session
                }
            } else if key == "icube_session_agent_map", let object = jsonObject(data) {
                for id in object.keys where sessions[id] == nil {
                    let createdAt = dateFromObjectIdentifier(id) ?? modifiedAt
                    sessions[id] = baseSession(
                        id: id,
                        title: "Trae Agent session",
                        cwd: cwd,
                        createdAt: createdAt,
                        updatedAt: modifiedAt,
                        model: models[id] ?? "Trae",
                        sourcePath: "",
                        forceControlAvailable: false
                    )
                }
            }
        }
        return Array(sessions.values)
    }

    private func codeBuddySessions() -> [[String: Any]] {
        let roots = [
            expandPath("~/Library/Application Support/CodeBuddy CN/User/globalStorage/tencent-cloud.coding-copilot/message-queue"),
            expandPath("~/Library/Application Support/CodeBuddy/User/globalStorage/tencent-cloud.coding-copilot/message-queue")
        ]
        var sessions: [String: [String: Any]] = [:]
        for rootPath in roots {
            let root = URL(fileURLWithPath: rootPath, isDirectory: true)
            for url in recentFiles(root: root, matching: { $0.pathExtension == "json" }, maxDepth: 1, limit: 40) {
                guard let data = boundedData(contentsOf: url), let object = jsonObject(data),
                      let conversations = object["conversations"] as? [String: Any] else { continue }
                for (key, rawConversation) in conversations {
                    let conversation = rawConversation as? [String: Any] ?? [:]
                    let id = conversation["conversationId"] as? String ?? key
                    let items = conversation["items"] as? [[String: Any]] ?? []
                    let lastItem = items.max { unixTime($0["updatedAt"]) < unixTime($1["updatedAt"]) }
                    let title = lastItem?["previewText"] as? String
                        ?? extractedText(lastItem?["contentBlocks"])
                    let updatedAt = max(unixTime(conversation["updatedAt"]), fileModifiedAt(url.path))
                    let createdAt = items.compactMap { value -> Double? in
                        let timestamp = unixTime(value["createdAt"])
                        return timestamp > 0 ? timestamp : nil
                    }.min() ?? updatedAt
                    let runtime = conversation["runtime"] as? [String: Any] ?? [:]
                    let active = boolValue(runtime["activated"])
                        && !boolValue(runtime["paused"])
                        && Date().timeIntervalSince1970 - updatedAt < 300
                    var session = baseSession(
                        id: id,
                        title: title.isEmpty ? "CodeBuddy session" : title,
                        cwd: "",
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        model: lastItem?["modelId"] as? String ?? "CodeBuddy",
                        sourcePath: url.path,
                        forceControlAvailable: false
                    )
                    session["phase"] = active ? "processing" : (runtime["pauseReason"] as? String == "error" ? "error" : "idle")
                    session["lastUserMessage"] = title
                    session["contextAvailable"] = !items.isEmpty
                    if unixTime(session["updatedAt"]) > unixTime(sessions[id]?["updatedAt"]) { sessions[id] = session }
                }
            }
        }
        return Array(sessions.values)
    }

    private func vscodeWorkspacePath(directory: URL) -> String {
        let workspace = directory.appendingPathComponent("workspace.json")
        guard let data = boundedData(contentsOf: workspace), let object = jsonObject(data),
              let folder = object["folder"] as? String else { return "" }
        if let url = URL(string: folder), url.isFileURL { return url.path }
        return folder.removingPercentEncoding ?? folder
    }

    private func dateFromObjectIdentifier(_ value: String) -> Double? {
        guard value.count >= 8, let seconds = UInt64(value.prefix(8), radix: 16), seconds > 0 else { return nil }
        return Double(seconds)
    }

    private func openClawSessions() -> [[String: Any]] {
        let root = URL(fileURLWithPath: expandPath("~/.openclaw/agents"), isDirectory: true)
        let stores = recentFiles(root: root, matching: { $0.lastPathComponent == "sessions.json" }, maxDepth: 4, limit: 30)
        var rows: [[String: Any]] = []
        for storeURL in stores {
            guard let data = boundedData(contentsOf: storeURL), let raw = try? JSONSerialization.jsonObject(with: data) else { continue }
            let agentId = storeURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent
            let entries: [[String: Any]]
            if let object = raw as? [String: Any], let sessions = object["sessions"] as? [[String: Any]] {
                entries = sessions
            } else if let object = raw as? [String: [String: Any]] {
                entries = object.map { key, value in var row = value; row["key"] = row["key"] ?? key; return row }
            } else if let array = raw as? [[String: Any]] {
                entries = array
            } else {
                entries = []
            }
            for entry in entries.prefix(100) {
                guard let id = entry["key"] as? String ?? entry["sessionKey"] as? String ?? entry["id"] as? String else { continue }
                let cwd = entry["cwd"] as? String ?? entry["workspace"] as? String ?? ""
                let transcript = openClawTranscript(entry: entry, storeURL: storeURL)
                rows.append(baseSession(
                    id: id,
                    title: entry["title"] as? String ?? entry["displayName"] as? String ?? "OpenClaw \(agentId)",
                    cwd: cwd,
                    createdAt: unixTime(entry["createdAt"] ?? entry["created_at"]),
                    updatedAt: unixTime(entry["updatedAt"] ?? entry["updated_at"] ?? entry["lastActivityAt"]),
                    model: entry["model"] as? String ?? "OpenClaw",
                    sourcePath: transcript
                ))
            }
        }
        return rows
    }

    private func hermesSessions() -> [[String: Any]] {
        let databasePath = expandPath("~/.hermes/state.db")
        if let database = SQLiteReadOnlyDatabase(path: databasePath) {
            let rows = database.rows(sql: "SELECT * FROM sessions ORDER BY started_at DESC LIMIT 100")
            if !rows.isEmpty {
                return rows.compactMap { row in
                    guard let id = row["session_id"] as? String, !id.isEmpty else { return nil }
                    let createdAt = unixTime(row["started_at"] ?? row["created_at"])
                    let updatedAt = max(unixTime(row["ended_at"] ?? row["updated_at"]), createdAt)
                    return baseSession(
                        id: id,
                        title: row["title"] as? String ?? "Hermes session",
                        cwd: row["cwd"] as? String ?? row["working_directory"] as? String ?? "",
                        createdAt: createdAt,
                        updatedAt: updatedAt,
                        model: row["model"] as? String ?? "Hermes",
                        sourcePath: databasePath
                    )
                }
            }
        }
        let root = URL(fileURLWithPath: expandPath("~/.hermes/sessions"), isDirectory: true)
        return recentFiles(root: root, matching: { ["json", "jsonl"].contains($0.pathExtension.lowercased()) }, maxDepth: 5, limit: 100).map { url in
            let first = firstJSONLines(url: url, limit: 4).first ?? [:]
            let id = first["session_id"] as? String ?? first["id"] as? String ?? url.deletingPathExtension().lastPathComponent
            let cwd = first["cwd"] as? String ?? first["workspace_dir"] as? String ?? ""
            let title = first["title"] as? String ?? first["summary"] as? String ?? "Hermes session"
            return baseSession(
                id: id,
                title: title,
                cwd: cwd,
                createdAt: unixTime(first["created_at"] ?? first["session_start"]),
                updatedAt: fileModifiedAt(url.path),
                model: first["model"] as? String ?? "Hermes",
                sourcePath: url.path
            )
        }
    }

    private func miniMaxSessions() -> [[String: Any]] {
        guard let database = SQLiteReadOnlyDatabase(path: expandPath("~/.minimax/sqlite.db")) else { return [] }
        let sql = """
        SELECT session_id, agent_name, title, workspace_dir, status, pid, port, process_alive,
               last_active_at, framework_type, session_data_dir, framework_session_id,
               effective_model, created_at, updated_at
        FROM sessions ORDER BY updated_at DESC LIMIT 100
        """
        let pending = miniMaxPendingApprovals(database: database)
        return database.rows(sql: sql).compactMap { row in
            guard let id = row["session_id"] as? String, !id.isEmpty else { return nil }
            let frameworkId = row["framework_session_id"] as? String ?? ""
            let alive = boolValue(row["process_alive"]) && processIsAlive(Int32(numberValue(row["pid"])))
            let status = (row["status"] as? String ?? "").lowercased()
            var session = baseSession(
                id: id,
                title: row["title"] as? String ?? "MiniMax session",
                cwd: row["workspace_dir"] as? String ?? "",
                createdAt: unixTime(row["created_at"]),
                updatedAt: max(unixTime(row["updated_at"]), unixTime(row["last_active_at"])),
                model: row["effective_model"] as? String ?? "MiniMax",
                sourcePath: "",
                forceControlAvailable: alive && numberValue(row["port"]) > 0
            )
            session["phase"] = alive || ["running", "processing", "active"].contains(status) ? "processing" : "done"
            session["frameworkSessionId"] = frameworkId
            session["port"] = numberValue(row["port"])
            session["pid"] = numberValue(row["pid"])
            session["agentType"] = "MiniMax Code"
            let requests = pending.filter { approval in
                let approvalSession = approval["sessionKey"] as? String ?? ""
                return approvalSession == id || approvalSession == frameworkId
            }.map { $0["request"] as? [String: Any] ?? [:] }
            if !requests.isEmpty {
                session["requests"] = requests
                session["phase"] = "waitingApproval"
            }
            return session
        }
    }

    private func genericJSONSessions(roots: [String], agentType: String) -> [[String: Any]] {
        var rows: [[String: Any]] = []
        for rawRoot in roots {
            let root = URL(fileURLWithPath: expandPath(rawRoot), isDirectory: true)
            let files = recentFiles(root: root, matching: { ["json", "jsonl"].contains($0.pathExtension.lowercased()) }, maxDepth: 6, limit: 60)
            for url in files {
                let first = firstJSONLines(url: url, limit: 5).first ?? [:]
                let id = first["sessionId"] as? String
                    ?? first["session_id"] as? String
                    ?? first["id"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
                let cwd = first["cwd"] as? String ?? first["workspace_dir"] as? String ?? ""
                rows.append(baseSession(
                    id: id,
                    title: first["title"] as? String ?? first["summary"] as? String ?? "\(agentType) session",
                    cwd: cwd,
                    createdAt: unixTime(first["createdAt"] ?? first["created_at"] ?? first["timestamp"]),
                    updatedAt: fileModifiedAt(url.path),
                    model: first["model"] as? String ?? agentType,
                    sourcePath: url.path
                ))
            }
        }
        return rows
    }

    private func aiderSessions() -> [[String: Any]] {
        let roots = [expandPath("~/.aider.chat.history.md"), expandPath("~/.aider.input.history")]
        return roots.compactMap { path in
            guard fileManager.fileExists(atPath: path) else { return nil }
            return baseSession(
                id: "aider-history-\(URL(fileURLWithPath: path).lastPathComponent)",
                title: "Aider history",
                cwd: NSHomeDirectory(),
                createdAt: fileCreatedAt(path),
                updatedAt: fileModifiedAt(path),
                model: "Aider",
                sourcePath: "",
                forceControlAvailable: false
            )
        }
    }

    private func deepSeekHarnessSessions() -> [[String: Any]] {
        let workspaceURL = URL(fileURLWithPath: expandPath("~/.dsh/storages/workspace.json"))
        let projectionURL = URL(fileURLWithPath: expandPath("~/.dsh/storages/session_projcache.json"))
        guard let workspaceData = boundedData(contentsOf: workspaceURL, limit: 8 * 1_024 * 1_024),
              let workspaceObject = jsonObject(workspaceData) else { return [] }

        let projectionObject = boundedData(contentsOf: projectionURL, limit: 32 * 1_024 * 1_024)
            .flatMap(jsonObject) ?? [:]
        let workspaces = ((workspaceObject["tables"] as? [String: Any])?["workspaces"] as? [String: Any]) ?? [:]
        let projections = ((projectionObject["tables"] as? [String: Any])?["sessions"] as? [String: Any]) ?? [:]
        let archives = deepSeekHarnessArchives()
        let projectionModifiedAt = fileModifiedAt(projectionURL.path)

        var workspaceBySession: [String: [String: Any]] = [:]
        for rawWorkspace in workspaces.values {
            guard let workspace = rawWorkspace as? [String: Any] else { continue }
            for sessionId in workspace["sessionIds"] as? [String] ?? [] {
                workspaceBySession[sessionId] = workspace
            }
        }

        let allSessionIds = Set(projections.keys).union(workspaceBySession.keys)
        return allSessionIds.compactMap { sessionId -> [String: Any]? in
            let projection = projections[sessionId] as? [String: Any] ?? [:]
            let identity = projection["identity"] as? [String: Any] ?? [:]
            let rows = projection["rows"] as? [String: Any] ?? [:]
            let workspace = workspaceBySession[sessionId] ?? [:]
            let titleRow = deepSeekHarnessRow(rows, key: "title")
            let metadata = deepSeekHarnessRow(rows, key: "sessionListMetadata")
            let stats = deepSeekHarnessRow(rows, key: "sessionStats")
            let usage = deepSeekHarnessRow(rows, key: "tokenUsage")
            let totals = usage["totals"] as? [String: Any] ?? [:]

            let cwd = (identity["cwd"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? (workspace["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? ""
            let workspaceTitle = (workspace["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let rawProjectedTitle = titleRow["title"] as? String
                ?? titleRow["text"] as? String
                ?? titleRow["value"] as? String
            let projectedTitle = rawProjectedTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let directTitle = (rows["title"] as? [String: Any])?["val"] as? String ?? ""
            let title = [projectedTitle, directTitle, workspaceTitle, "DeepSeek Harness session"]
                .first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? "DeepSeek Harness session"

            let archivePath = archives[sessionId] ?? ""
            let createdAt = unixTime(identity["createdAt"] ?? workspace["createdAt"])
            let observedUpdatedAt = max(
                unixTime(metadata["lastPromptAt"] ?? workspace["updatedAt"]),
                archivePath.isEmpty ? 0 : fileModifiedAt(archivePath)
            )
            let updatedAt = observedUpdatedAt > 0 ? observedUpdatedAt : projectionModifiedAt
            let openStep = stats["openStep"]
            let hasOpenStep = openStep != nil && !(openStep is NSNull)
            let pendingCalls = stats["pendingCalls"]
            let hasPendingCalls: Bool
            if let calls = pendingCalls as? [Any] {
                hasPendingCalls = !calls.isEmpty
            } else if let calls = pendingCalls as? [String: Any] {
                hasPendingCalls = !calls.isEmpty
            } else {
                hasPendingCalls = false
            }

            var session = baseSession(
                id: sessionId,
                title: title,
                cwd: cwd,
                createdAt: createdAt,
                updatedAt: updatedAt,
                model: "DeepSeek Harness",
                sourcePath: archivePath
            )
            session["project"] = workspaceTitle.isEmpty
                ? (cwd.isEmpty ? "DeepSeek Harness" : URL(fileURLWithPath: cwd).lastPathComponent)
                : workspaceTitle
            session["phase"] = hasOpenStep || hasPendingCalls ? "processing" : "idle"
            session["controlReason"] = profile.supportsDirectControl
                ? "new_headless_task_adapter"
                : unavailableControlReason()
            session["contextAvailable"] = false
            session["resumeRequiresInstruction"] = true
            session["resumeNote"] = "DeepSeek Harness headless mode starts a new persisted task in this workspace; it does not mutate the archived session."
            session["tokens"] = [
                "input": numberValue(totals["uncachedInputTokens"]),
                "output": numberValue(totals["outputTokens"]),
                "cacheRead": numberValue(totals["cacheReadTokens"]),
                "cacheCreate": numberValue(totals["cacheWriteTokens"])
            ]
            return session
        }
    }

    private func deepSeekHarnessRow(_ rows: [String: Any], key: String) -> [String: Any] {
        guard let wrapper = rows[key] as? [String: Any] else { return [:] }
        if let value = wrapper["val"] as? [String: Any] { return value }
        return wrapper
    }

    private func deepSeekHarnessArchives() -> [String: String] {
        let root = URL(fileURLWithPath: expandPath("~/.dsh/sessions"), isDirectory: true)
        let files = recentFiles(
            root: root,
            matching: { $0.lastPathComponent == "session.jsonl.zstd" },
            maxDepth: 4,
            limit: 240
        )
        return Dictionary(uniqueKeysWithValues: files.map { ($0.deletingLastPathComponent().lastPathComponent, $0.path) })
    }

    private func baseSession(
        id: String,
        title: String,
        cwd: String,
        createdAt: Double,
        updatedAt: Double,
        model: String,
        sourcePath: String,
        forceControlAvailable: Bool? = nil
    ) -> [String: Any] {
        let canControl = forceControlAvailable ?? profile.supportsDirectControl
        let now = Date().timeIntervalSince1970
        return [
            "id": id,
            "preview": title.isEmpty ? "\(profile.displayName) session" : String(title.prefix(320)),
            "cwd": cwd,
            "project": cwd.isEmpty ? profile.displayName : URL(fileURLWithPath: cwd).lastPathComponent,
            "phase": "idle",
            "createdAt": createdAt > 0 ? createdAt : updatedAt,
            "updatedAt": updatedAt > 0 ? updatedAt : now,
            "model": model,
            "agentType": profile.displayName,
            "controlAvailable": canControl,
            "controlReason": canControl
                ? (profile.controlKind == .newTaskCLI ? "new_headless_task_adapter" : "resumable_agent_adapter")
                : unavailableControlReason(),
            "controlMode": canControl ? "tracefence_agent_core" : "display_only",
            "sourcePath": sourcePath,
            "contextAvailable": profile.id == "minimax" || (profile.id != "deepseek-harness" && !sourcePath.isEmpty)
        ]
    }

    private func attachHookApprovals(to sessions: inout [String: [String: Any]]) {
        for approval in store.pendingApprovals(adapterId: profile.id) {
            let request: [String: Any] = [
                "method": "item/permissions/requestApproval",
                "requestId": approval.requestId,
                "source": "universal-hook",
                "params": [
                    "title": "\(profile.displayName) requests \(approval.toolName)",
                    "reason": "The Agent is waiting for approval before using \(approval.toolName).",
                    "toolName": approval.toolName,
                    "toolInput": approval.toolInput,
                    "command": approval.command,
                    "cwd": approval.cwd,
                    "startedAtMs": approval.createdAt * 1_000
                ]
            ]
            var session = sessions[approval.sessionId] ?? baseSession(
                id: approval.sessionId,
                title: "\(profile.displayName) approval",
                cwd: approval.cwd,
                createdAt: approval.createdAt,
                updatedAt: approval.createdAt,
                model: profile.displayName,
                sourcePath: ""
            )
            var requests = session["requests"] as? [[String: Any]] ?? []
            requests.removeAll { ($0["requestId"] as? String) == approval.requestId }
            requests.append(request)
            session["requests"] = requests
            session["phase"] = "waitingApproval"
            session["updatedAt"] = approval.createdAt
            sessions[approval.sessionId] = session
        }
    }

    private func miniMaxPendingApprovals(database: SQLiteReadOnlyDatabase) -> [[String: Any]] {
        let cutoff = (Date().timeIntervalSince1970 - 24 * 60 * 60) * 1_000
        let rows = database.rows(sql: """
        SELECT request_id, session_id, tool_name, tool_input, reason, execution_path, created_at
        FROM permission_requests WHERE status = 'pending' AND created_at >= ? ORDER BY created_at DESC LIMIT 50
        """, bindings: [cutoff])
        return rows.compactMap { row in
            guard let requestId = row["request_id"] as? String, let sessionId = row["session_id"] as? String else { return nil }
            let toolName = row["tool_name"] as? String ?? "tool"
            let toolInput = row["tool_input"] as? String ?? ""
            let reason = row["reason"] as? String ?? "MiniMax Code requests permission."
            let command = commandFromJSONString(toolInput)
            let request: [String: Any] = [
                "method": "item/permissions/requestApproval",
                "requestId": requestId,
                "source": "minimax-opencode",
                "params": [
                    "title": "MiniMax Code requests \(toolName)",
                    "reason": reason,
                    "toolName": toolName,
                    "toolInput": toolInput,
                    "command": command,
                    "cwd": row["execution_path"] as? String ?? "",
                    "startedAtMs": numberValue(row["created_at"])
                ]
            ]
            return ["sessionKey": sessionId, "request": request]
        }
    }

    private func miniMaxContext(sessionId: String) -> [[String: Any]] {
        guard let database = SQLiteReadOnlyDatabase(path: expandPath("~/.minimax/sqlite.db")) else { return [] }
        let rows = database.rows(sql: """
        SELECT id, role, data, timestamp FROM session_messages
        WHERE session_id = ? ORDER BY id DESC LIMIT 800
        """, bindings: [sessionId]).reversed()
        var result: [[String: Any]] = []
        for row in rows {
            guard let raw = row["data"] as? String,
                  let data = raw.data(using: .utf8),
                  let object = jsonObject(data) else { continue }
            let role = object["role"] as? String ?? row["role"] as? String ?? "assistant"
            let timestamp = unixTime(object["timestamp"] ?? row["timestamp"])
            let content = object["msg_content"] as? String ?? ""
            if !content.isEmpty {
                result.append(message(
                    id: "minimax-\(numberValue(row["id"]))-message",
                    role: role,
                    kind: "message",
                    text: content,
                    timestamp: timestamp
                ))
            }
            for (index, tool) in (object["tool_calls"] as? [[String: Any]] ?? []).enumerated() {
                let function = tool["function"] as? [String: Any] ?? tool
                let name = function["name"] as? String ?? "tool"
                result.append(message(
                    id: "minimax-\(numberValue(row["id"]))-tool-\(index)",
                    role: "tool",
                    kind: "toolCall",
                    text: jsonString(function["arguments"] ?? function["input"] ?? [:]),
                    timestamp: timestamp,
                    toolName: name
                ))
            }
        }
        return result
    }

    private func parseCodeBuddyContext(path: String, sessionId: String) -> [[String: Any]] {
        guard !path.isEmpty, let data = boundedData(contentsOf: URL(fileURLWithPath: path)),
              let object = jsonObject(data),
              let conversations = object["conversations"] as? [String: Any],
              let conversation = conversations[sessionId] as? [String: Any] else { return [] }
        let items = (conversation["items"] as? [[String: Any]] ?? []).sorted {
            unixTime($0["createdAt"]) < unixTime($1["createdAt"])
        }
        return items.compactMap { item in
            let text = item["previewText"] as? String ?? extractedText(item["contentBlocks"])
            guard !text.isEmpty else { return nil }
            return message(
                id: item["id"] as? String ?? "codebuddy-\(UUID().uuidString)",
                role: "user",
                kind: "message",
                text: text,
                timestamp: unixTime(item["createdAt"])
            )
        }
    }

    private func hermesContext(sessionId: String, sourcePath: String) -> [[String: Any]] {
        guard sourcePath.hasSuffix("state.db"), let database = SQLiteReadOnlyDatabase(path: sourcePath) else {
            return parseGenericContext(path: sourcePath)
        }
        let rows = database.rows(
            sql: "SELECT * FROM messages WHERE session_id = ? ORDER BY timestamp ASC LIMIT 1200",
            bindings: [sessionId]
        )
        var records: [[String: Any]] = []
        for (index, row) in rows.enumerated() {
            let role = row["role"] as? String ?? "assistant"
            let timestamp = unixTime(row["timestamp"] ?? row["created_at"])
            let raw = row["content"] as? String ?? row["message"] as? String ?? ""
            let text: String
            if let data = raw.data(using: .utf8),
               let value = try? JSONSerialization.jsonObject(with: data) {
                text = extractedText(value)
            } else {
                text = raw
            }
            if !text.isEmpty {
                records.append(message(
                    id: row["id"] as? String ?? "hermes-\(index)-message",
                    role: role,
                    kind: "message",
                    text: text,
                    timestamp: timestamp
                ))
            }
            if let rawTools = row["tool_calls"] as? String,
               let data = rawTools.data(using: .utf8),
               let tools = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                for (toolIndex, tool) in tools.enumerated() {
                    let function = tool["function"] as? [String: Any] ?? tool
                    records.append(message(
                        id: "hermes-\(index)-tool-\(toolIndex)",
                        role: "tool",
                        kind: "toolCall",
                        text: jsonString(function["arguments"] ?? function["input"] ?? [:]),
                        timestamp: timestamp,
                        toolName: function["name"] as? String ?? "tool"
                    ))
                }
            }
        }
        return records
    }

    private func parseGrokContext(path: String) -> [[String: Any]] {
        guard !path.isEmpty else { return [] }
        var result: [[String: Any]] = []
        enumerateJSONLines(path: path, maxLines: 5_000) { lineNumber, object in
            guard let params = object["params"] as? [String: Any],
                  let update = params["update"] as? [String: Any] else { return }
            let type = update["sessionUpdate"] as? String ?? ""
            let timestamp = unixTime(object["timestamp"])
            switch type {
            case "user_message_chunk", "agent_message_chunk", "agent_thought_chunk":
                let text = extractedText(update["content"])
                guard !text.isEmpty else { return }
                let role = type == "user_message_chunk" ? "user" : "assistant"
                let kind = type == "agent_thought_chunk" ? "thought" : "message"
                if let last = result.indices.last,
                   result[last]["role"] as? String == role,
                   result[last]["kind"] as? String == kind {
                    result[last]["text"] = (result[last]["text"] as? String ?? "") + text
                } else {
                    result.append(message(id: "grok-\(lineNumber)", role: role, kind: kind, text: text, timestamp: timestamp))
                }
            case "tool_call", "tool_call_update":
                let title = update["title"] as? String ?? "tool"
                let text = jsonString(update["rawInput"] ?? update["content"] ?? update["rawOutput"] ?? [:])
                result.append(message(
                    id: "grok-\(lineNumber)-tool",
                    role: "tool",
                    kind: type == "tool_call" ? "toolCall" : "toolResult",
                    text: text,
                    timestamp: timestamp,
                    toolName: title,
                    status: update["status"] as? String
                ))
            default:
                break
            }
        }
        return result
    }

    private func parseQwenContext(path: String) -> [[String: Any]] {
        guard !path.isEmpty else { return [] }
        var result: [[String: Any]] = []
        enumerateJSONLines(path: path, maxLines: 5_000) { lineNumber, object in
            let timestamp = unixTime(object["timestamp"])
            if let messageObject = object["message"] as? [String: Any] {
                let role = messageObject["role"] as? String ?? object["type"] as? String ?? "assistant"
                let text = extractedText(messageObject["parts"] ?? messageObject["content"])
                guard !text.isEmpty else { return }
                result.append(message(id: "qwen-\(lineNumber)", role: role, kind: "message", text: text, timestamp: timestamp))
                return
            }
            if let tool = object["toolCall"] as? [String: Any] ?? object["tool_call"] as? [String: Any] {
                let name = tool["name"] as? String ?? "tool"
                result.append(message(
                    id: "qwen-\(lineNumber)-tool",
                    role: "tool",
                    kind: "toolCall",
                    text: jsonString(tool["args"] ?? tool["input"] ?? [:]),
                    timestamp: timestamp,
                    toolName: name
                ))
            }
        }
        return result
    }

    private func parseGenericContext(path: String) -> [[String: Any]] {
        guard !path.isEmpty, fileManager.fileExists(atPath: path) else { return [] }
        var result: [[String: Any]] = []
        enumerateJSONLines(path: path, maxLines: 5_000) { lineNumber, object in
            let timestamp = unixTime(object["timestamp"] ?? object["createdAt"])
            let role = object["role"] as? String ?? (object["type"] as? String == "user" ? "user" : "assistant")
            var text = object["text"] as? String ?? object["result"] as? String ?? ""
            if text.isEmpty, let value = object["message"] { text = extractedText(value) }
            if text.isEmpty, let value = object["content"] { text = extractedText(value) }
            if !text.isEmpty {
                result.append(message(id: "generic-\(lineNumber)", role: role, kind: "message", text: text, timestamp: timestamp))
            }
        }
        return result
    }

    private func message(
        id: String,
        role: String,
        kind: String,
        text: String,
        timestamp: Double,
        toolName: String? = nil,
        status: String? = nil
    ) -> [String: Any] {
        var value: [String: Any] = [
            "id": id,
            "role": role,
            "kind": kind,
            "text": String(text.prefix(24_000))
        ]
        if timestamp > 0 { value["timestamp"] = ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp)) }
        if let toolName, !toolName.isEmpty { value["toolName"] = toolName }
        if let status, !status.isEmpty { value["status"] = status }
        return value
    }

    private func contextWarning() -> String {
        switch profile.id {
        case "cursor": return "Cursor Desktop does not expose a supported local transcript API. Install Cursor Agent CLI for resumable sessions."
        case "trae": return "Trae Desktop session metadata is visible, but Trae does not expose a supported local transcript or control API."
        case "codebuddy": return "CodeBuddy exposes queued user instructions locally; assistant output and live control are not available through a supported local API."
        case "minimax": return "No readable MiniMax Code messages were found for this session."
        case "deepseek-harness": return "DeepSeek Harness stores this transcript as a compressed archive. TraceFence currently shows its project, status, and token totals without expanding the archive."
        default: return "This Agent session has not written a readable local transcript yet."
        }
    }

    private func unavailableControlReason() -> String {
        if profile.commandURL == nil && profile.applicationPresent {
            return "desktop_app_has_no_public_control_api"
        }
        if profile.dataPresent { return "agent_runtime_not_installed" }
        return "agent_not_installed"
    }

    private func healthMessage(installed: Bool, canControl: Bool) -> String {
        if !installed { return "\(profile.displayName) is not installed; its public integration profile is ready." }
        if canControl { return "\(profile.displayName) sessions can be monitored and controlled through TraceFence Agent Core." }
        if profile.id == "cursor" && profile.applicationPresent {
            return "Cursor Desktop was found. Install the official Cursor Agent CLI to enable remote instructions; desktop sessions remain monitor-only."
        }
        return "\(profile.displayName) data was found, but no supported controllable runtime is currently available."
    }

    private func recentProviderFailure() -> String? {
        let cutoff = Date().timeIntervalSince1970 - 7 * 24 * 60 * 60
        for job in store.jobs(adapterId: profile.id) where job.updatedAt >= cutoff {
            let output = store.outputTail(path: job.outputPath)
            guard !output.isEmpty else { continue }
            return providerFailure(in: output)
        }
        return nil
    }

    private func providerFailure(in output: String) -> String? {
        let normalized = output.lowercased()
        if normalized.contains("401 invalid access token") || normalized.contains("token expired") {
            return "\(profile.displayName) authentication failed: the access token is invalid or expired. Sign in again on the Mac."
        }
        if normalized.contains("authentication_failed") || normalized.contains("not logged in") {
            return "\(profile.displayName) is not authenticated. Sign in again on the Mac."
        }
        if normalized.contains("[api error:") || normalized.contains("provider request failed") {
            return "\(profile.displayName) provider request failed. Check its account and provider configuration on the Mac."
        }
        return nil
    }

    private func openClawTranscript(entry: [String: Any], storeURL: URL) -> String {
        for key in ["transcriptPath", "transcript_path", "path"] {
            if let path = entry[key] as? String, fileManager.fileExists(atPath: path) { return path }
        }
        if let id = entry["sessionId"] as? String ?? entry["id"] as? String {
            let candidate = storeURL.deletingLastPathComponent().appendingPathComponent("\(id).jsonl")
            if fileManager.fileExists(atPath: candidate.path) { return candidate.path }
        }
        return ""
    }

    private func commandFromJSONString(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8), let object = jsonObject(data) else { return "" }
        return object["command"] as? String ?? object["cmd"] as? String ?? ""
    }

    private func firstJSONLines(url: URL, limit: Int) -> [[String: Any]] {
        var result: [[String: Any]] = []
        guard let handle = try? FileHandle(forReadingFrom: url) else { return result }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 512 * 1_024)) ?? Data()
        for line in data.split(separator: 0x0A).prefix(limit) {
            if let object = jsonObject(Data(line)) { result.append(object) }
        }
        return result
    }

    private func enumerateJSONLines(path: String, maxLines: Int, body: (Int, [String: Any]) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return }
        defer { try? handle.close() }
        let maxBytes = 32 * 1_024 * 1_024
        let size = (try? handle.seekToEnd()) ?? 0
        if size > UInt64(maxBytes) { try? handle.seek(toOffset: size - UInt64(maxBytes)) } else { try? handle.seek(toOffset: 0) }
        let data = (try? handle.readToEnd()) ?? Data()
        var lineNumber = 0
        for line in data.split(separator: 0x0A).suffix(maxLines) {
            lineNumber += 1
            if let object = jsonObject(Data(line)) { body(lineNumber, object) }
        }
    }

    private func recentFiles(root: URL, matching: (URL) -> Bool, maxDepth: Int, limit: Int) -> [URL] {
        guard fileManager.fileExists(atPath: root.path),
              let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        var values: [(URL, Double)] = []
        for case let url as URL in enumerator {
            let relative = String(url.path.dropFirst(min(root.path.count + 1, url.path.count)))
            let depth = relative.split(separator: "/").count
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            guard matching(url) else { continue }
            values.append((url, fileModifiedAt(url.path)))
            if values.count > limit * 5 {
                values.sort { $0.1 > $1.1 }
                values.removeLast(values.count - limit * 2)
            }
        }
        return values.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }

    private func fileModifiedAt(_ path: String) -> Double {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path), let date = attributes[.modificationDate] as? Date else { return 0 }
        return date.timeIntervalSince1970
    }

    private func fileCreatedAt(_ path: String) -> Double {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path), let date = attributes[.creationDate] as? Date else { return fileModifiedAt(path) }
        return date.timeIntervalSince1970
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        return numberValue(value) != 0
    }

    private func numberValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? Double { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    private func boundedData(contentsOf url: URL, limit: Int = 16 * 1_024 * 1_024) -> Data? {
        guard limit > 0 else { return nil }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > limit {
            return nil
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: limit + 1),
              data.count <= limit else {
            return nil
        }
        return data
    }
}

final class SQLiteReadOnlyDatabase {
    private var database: OpaquePointer?
    private let path: String
    private var usingImmutable = false

    init?(path: String) {
        self.path = path
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        if sqlite3_open_v2(path, &database, flags, nil) != SQLITE_OK {
            guard reopenImmutable() else { return nil }
        }
        sqlite3_busy_timeout(database, 750)
    }

    deinit {
        if let database { sqlite3_close(database) }
    }

    func rows(sql: String, bindings: [Any] = []) -> [[String: Any]] {
        guard let database else { return [] }
        var statement: OpaquePointer?
        if sqlite3_prepare_v2(database, sql, -1, &statement, nil) != SQLITE_OK, !usingImmutable {
            guard reopenImmutable(), let reopenedDatabase = self.database,
                  sqlite3_prepare_v2(reopenedDatabase, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        }
        guard let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case let value as String:
                sqlite3_bind_text(statement, position, value, -1, sqliteTransient)
            case let value as Double:
                sqlite3_bind_double(statement, position, value)
            case let value as Int:
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            case let value as Int64:
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            default:
                sqlite3_bind_null(statement, position)
            }
        }
        var result: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                guard let name = sqlite3_column_name(statement, index) else { continue }
                let key = String(cString: name)
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[key] = Int64(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    row[key] = sqlite3_column_double(statement, index)
                case SQLITE_TEXT:
                    if let value = sqlite3_column_text(statement, index) { row[key] = String(cString: value) }
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(statement, index) {
                        row[key] = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, index)))
                    }
                default:
                    row[key] = NSNull()
                }
            }
            result.append(row)
        }
        return result
    }

    private func reopenImmutable() -> Bool {
        if let database { sqlite3_close(database) }
        database = nil
        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let immutableURI = "file:\(encodedPath)?immutable=1"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX | SQLITE_OPEN_URI
        guard sqlite3_open_v2(immutableURI, &database, flags, nil) == SQLITE_OK else {
            if let database { sqlite3_close(database) }
            database = nil
            return false
        }
        usingImmutable = true
        sqlite3_busy_timeout(database, 750)
        return true
    }
}
