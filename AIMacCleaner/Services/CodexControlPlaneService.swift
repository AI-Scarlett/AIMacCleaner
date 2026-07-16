import Foundation
import Darwin

private struct RolloutSummary: Sendable {
    var phase = "idle"
    var activeTurnId: String?
    var lastResponse = ""
    var lastUserMessage = ""
}

/// Keeps rollout file I/O and JSON parsing off the main actor. The file
/// signature makes repeated session refreshes cheap while a rollout is idle.
private actor RolloutSummaryCache {
    private struct FileSignature: Equatable, Sendable {
        let size: UInt64
        let modificationTime: TimeInterval
        let fileNumber: UInt64
    }

    private struct Entry: Sendable {
        let signature: FileSignature
        let summary: RolloutSummary
        let accessOrder: UInt64
    }

    private let maxEntries = 120
    private var entries: [String: Entry] = [:]
    private var accessOrder: UInt64 = 0

    func summaries(for paths: [String]) -> [String: RolloutSummary] {
        var result: [String: RolloutSummary] = [:]
        var seen = Set<String>()

        for path in paths where !path.isEmpty {
            guard seen.insert(path).inserted else { continue }
            guard seen.count <= maxEntries else { break }
            result[path] = summary(for: path)
        }
        return result
    }

    func summary(for path: String) -> RolloutSummary {
        guard !path.isEmpty, let signature = fileSignature(path: path) else {
            if !path.isEmpty {
                entries.removeValue(forKey: path)
            }
            return RolloutSummary()
        }

        accessOrder &+= 1
        if let cached = entries[path], cached.signature == signature {
            entries[path] = Entry(
                signature: cached.signature,
                summary: cached.summary,
                accessOrder: accessOrder
            )
            return cached.summary
        }

        let parsed = Self.readRolloutSummary(path: path)
        entries[path] = Entry(
            signature: signature,
            summary: parsed,
            accessOrder: accessOrder
        )
        pruneIfNeeded()
        return parsed
    }

    private func fileSignature(path: String) -> FileSignature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modificationDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        return FileSignature(
            size: size,
            modificationTime: modificationDate.timeIntervalSinceReferenceDate,
            fileNumber: (attributes[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        )
    }

    private func pruneIfNeeded() {
        guard entries.count > maxEntries else { return }
        let overflow = entries.count - maxEntries
        let oldestPaths = entries
            .sorted { $0.value.accessOrder < $1.value.accessOrder }
            .prefix(overflow)
            .map(\.key)
        for path in oldestPaths {
            entries.removeValue(forKey: path)
        }
    }

    private static func readRolloutSummary(path: String) -> RolloutSummary {
        guard let handle = FileHandle(forReadingAtPath: path) else { return RolloutSummary() }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 96 * 1_024
        let offset = end > maxBytes ? end - maxBytes : 0
        try? handle.seek(toOffset: offset)
        guard var data = try? handle.readToEnd(), !data.isEmpty else {
            return RolloutSummary()
        }
        if offset > 0 {
            guard let newline = data.firstIndex(of: 0x0A) else { return RolloutSummary() }
            let next = data.index(after: newline)
            data = next < data.endIndex ? Data(data[next...]) : Data()
        }
        let text = String(decoding: data, as: UTF8.self)

        var summary = RolloutSummary()
        var lastLifecycleIndex = -1
        for (index, rawLine) in text.split(separator: "\n").enumerated() {
            guard let data = rawLine.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = object["type"] as? String,
                  let payload = object["payload"] as? [String: Any]
            else {
                continue
            }

            if type == "event_msg", let eventType = payload["type"] as? String {
                switch eventType {
                case "task_started":
                    if index >= lastLifecycleIndex {
                        summary.phase = "processing"
                        summary.activeTurnId = payload["turn_id"] as? String
                        lastLifecycleIndex = index
                    }
                case "task_complete":
                    if index >= lastLifecycleIndex {
                        summary.phase = "idle"
                        summary.activeTurnId = nil
                        lastLifecycleIndex = index
                    }
                case "turn_aborted", "task_interrupted":
                    if index >= lastLifecycleIndex {
                        summary.phase = "interrupted"
                        summary.activeTurnId = nil
                        lastLifecycleIndex = index
                    }
                case "agent_message":
                    if let message = payload["message"] as? String, !message.isEmpty {
                        summary.lastResponse = String(message.suffix(1_200))
                    }
                case "user_message":
                    if let message = payload["message"] as? String, !message.isEmpty {
                        summary.lastUserMessage = String(message.suffix(1_200))
                    }
                default:
                    break
                }
            }

            if type == "response_item", payload["type"] as? String == "message",
               let role = payload["role"] as? String {
                let content = payload["content"] as? [[String: Any]] ?? []
                let message = content.compactMap { item in
                    item["text"] as? String ?? item["input_text"] as? String ?? item["output_text"] as? String
                }.joined(separator: "\n")
                if role == "assistant", !message.isEmpty {
                    summary.lastResponse = String(message.suffix(1_200))
                } else if role == "user", !message.isEmpty, !message.hasPrefix("<environment_context>") {
                    summary.lastUserMessage = String(message.suffix(1_200))
                }
            }
        }
        return summary
    }
}

struct CodexSessionSnapshot: Identifiable {
    let id: String
    let preview: String
    let cwd: String
    let sourcePath: String
    let createdAt: Date
    let updatedAt: Date
    var phase: String
    var activeTurnId: String?
    let lastResponse: String
    let lastUserMessage: String
    let model: String
    let source: String
}

struct CodexArtifactMessageSnapshot: Sendable {
    let text: String
    let order: Int
    let isFinalAnswer: Bool
}

struct CodexApprovalSnapshot: Identifiable {
    let id: String
    let threadId: String
    let turnId: String
    let kind: String
    let title: String
    let detail: String
    let options: [String]
    let descriptions: [String]
    let permissions: [String]
    let requestedAt: Date
    let requiresTextAnswer: Bool
    let source: String
    let requestId: String
    let method: String
    let requestedPermissions: [String: Any]
    let questionIds: [String]
    let questionDefaults: [String: String]
}

struct CodexControlResult {
    let ok: Bool
    let command: String
    let message: String
    let controlMode: String
}

@MainActor
final class CodexControlPlaneService {
    static let shared = CodexControlPlaneService()

    private struct PendingRequest {
        let completion: CheckedContinuation<[String: Any], Error>
        let method: String
    }

    private struct PendingApproval {
        let snapshot: CodexApprovalSnapshot
        let requestId: Any
        let method: String
        let requestedPermissions: [String: Any]
        let questionIds: [String]
        let questionDefaults: [String: String]
    }

    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = Data()
    private var outputSearchOffset = 0
    private var errorTail = ""
    private var nextRequestId = 0
    private var pendingRequests: [Int: PendingRequest] = [:]
    private var initialized = false
    private var activeTurns: [String: String] = [:]
    private var pendingApprovals: [String: PendingApproval] = [:]
    private var cachedSessions: [CodexSessionSnapshot] = []
    private var desktopSessions: [String: CodexSessionSnapshot] = [:]
    private var desktopRolloutSummaries: [String: RolloutSummary] = [:]
    private var latestDesktopStates: [String: [String: Any]] = [:]
    private var desktopRolloutRefreshTasks: [String: Task<Void, Never>] = [:]
    private var desktopRolloutRefreshTokens: [String: UUID] = [:]
    private var desktopRolloutRefreshVersions: [String: UInt64] = [:]
    private var lastSessionRefresh: Date?
    private let maxCachedSessions = 120
    private let rolloutSummaryCache = RolloutSummaryCache()

    private init() {
        DesktopCodexIPC.startObserver { [weak self] message in
            Task { @MainActor in
                self?.consumeDesktopBroadcast(message)
            }
        }
    }

    var isAvailable: Bool {
        Self.codexExecutableURL() != nil
    }

    func sessionSnapshots() async -> [CodexSessionSnapshot] {
        if let lastSessionRefresh,
           Date().timeIntervalSince(lastSessionRefresh) < 3,
           !cachedSessions.isEmpty {
            return cachedSessions
        }

        var coreSnapshots: [CodexSessionSnapshot] = []
        if let coreRows = await TraceFenceAgentCoreClient.shared.listSessions() {
            let rolloutSummaries = await rolloutSummaryCache.summaries(
                for: coreRows.map(Self.sourcePath(from:))
            )
            coreSnapshots = coreRows.compactMap { row in
                let sourcePath = Self.sourcePath(from: row)
                return sessionSnapshot(
                    from: row,
                    rollout: rolloutSummaries[sourcePath] ?? RolloutSummary()
                )
            }
            for row in coreRows {
                if let threadId = row["id"] as? String {
                    captureDesktopApprovals(from: row, threadId: threadId)
                }
            }
        }

        do {
            try await ensureStarted()
            var rows: [[String: Any]] = []
            var cursor: String?
            var pageCount = 0

            repeat {
                var params: [String: Any] = [
                    "limit": 80,
                    "sortKey": "recency_at",
                    "sortDirection": "desc",
                    "useStateDbOnly": true
                ]
                if let cursor {
                    params["cursor"] = cursor
                }
                let result = try await request(method: "thread/list", params: params, timeout: 12)
                rows.append(contentsOf: result["data"] as? [[String: Any]] ?? [])
                cursor = result["nextCursor"] as? String
                pageCount += 1
            } while cursor != nil && pageCount < 2 && rows.count < maxCachedSessions

            let limitedRows = Array(rows.prefix(maxCachedSessions))
            let rolloutSummaries = await rolloutSummaryCache.summaries(
                for: limitedRows.map(Self.sourcePath(from:))
            )
            let snapshots = limitedRows.compactMap { row in
                let sourcePath = Self.sourcePath(from: row)
                return sessionSnapshot(
                    from: row,
                    rollout: rolloutSummaries[sourcePath] ?? RolloutSummary()
                )
            }
            let merged = mergeDesktopSessions(with: mergeCoreSessions(coreSnapshots, native: snapshots))
            cachedSessions = Array(merged.prefix(maxCachedSessions))
            lastSessionRefresh = Date()
            return cachedSessions
        } catch {
            if !coreSnapshots.isEmpty {
                cachedSessions = Array(mergeDesktopSessions(with: coreSnapshots).prefix(maxCachedSessions))
                lastSessionRefresh = Date()
            }
            return cachedSessions
        }
    }

    func latestSessionSnapshots() -> [CodexSessionSnapshot] {
        cachedSessions
    }

    /// Returns the complete assistant-message history that Codex itself uses
    /// to render file cards for a task. Callers decide which message phases
    /// qualify as user-facing deliveries.
    func artifactMessageSnapshots(threadId: String) async -> [CodexArtifactMessageSnapshot] {
        do {
            let thread = try await readThread(threadId: threadId)
            let turns = thread["turns"] as? [[String: Any]] ?? []
            var messages: [CodexArtifactMessageSnapshot] = []
            var order = 0
            for turn in turns {
                let items = turn["items"] as? [[String: Any]] ?? []
                for item in items {
                    let type = (item["type"] as? String ?? "").lowercased()
                    guard type == "agentmessage" || type == "assistantmessage" else { continue }
                    guard let text = (item["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !text.isEmpty else { continue }
                    let phase = (item["phase"] as? String ?? "").lowercased()
                    messages.append(CodexArtifactMessageSnapshot(
                        text: text,
                        order: order,
                        isFinalAnswer: phase == "final_answer" || phase == "finalanswer"
                    ))
                    order += 1
                }
            }
            return messages
        } catch {
            return []
        }
    }

    private func mergeDesktopSessions(with snapshots: [CodexSessionSnapshot]) -> [CodexSessionSnapshot] {
        var merged = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        for (id, snapshot) in desktopSessions {
            merged[id] = snapshot
        }
        return merged.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func mergeCoreSessions(
        _ core: [CodexSessionSnapshot],
        native: [CodexSessionSnapshot]
    ) -> [CodexSessionSnapshot] {
        var merged = Dictionary(uniqueKeysWithValues: core.map { ($0.id, $0) })
        for nativeSession in native {
            guard let coreSession = merged[nativeSession.id] else {
                merged[nativeSession.id] = nativeSession
                continue
            }
            merged[nativeSession.id] = CodexSessionSnapshot(
                id: nativeSession.id,
                preview: nativeSession.preview,
                cwd: nativeSession.cwd.isEmpty ? coreSession.cwd : nativeSession.cwd,
                sourcePath: nativeSession.sourcePath.isEmpty ? coreSession.sourcePath : nativeSession.sourcePath,
                createdAt: min(nativeSession.createdAt, coreSession.createdAt),
                updatedAt: max(nativeSession.updatedAt, coreSession.updatedAt),
                phase: coreSession.phase,
                activeTurnId: coreSession.activeTurnId ?? nativeSession.activeTurnId,
                lastResponse: nativeSession.lastResponse.isEmpty ? coreSession.lastResponse : nativeSession.lastResponse,
                lastUserMessage: nativeSession.lastUserMessage.isEmpty ? coreSession.lastUserMessage : nativeSession.lastUserMessage,
                model: nativeSession.model.isEmpty ? coreSession.model : nativeSession.model,
                source: "native+\(coreSession.source)"
            )
        }
        return merged.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    private func consumeDesktopBroadcast(_ message: [String: Any]) {
        guard message["method"] as? String == "thread-stream-state-changed",
              let params = message["params"] as? [String: Any],
              let change = params["change"] as? [String: Any],
              change["type"] as? String == "snapshot",
              let state = change["conversationState"] as? [String: Any],
              let threadId = state["id"] as? String else {
            return
        }

        let sourcePath = state["rolloutPath"] as? String ?? ""
        let rollout = desktopRolloutSummaries[sourcePath] ?? RolloutSummary()
        guard let snapshot = desktopSessionSnapshot(from: state, rollout: rollout) else { return }

        desktopSessions[snapshot.id] = snapshot
        latestDesktopStates[threadId] = state
        desktopRolloutRefreshVersions[threadId, default: 0] &+= 1
        pruneDesktopSessions()
        cachedSessions = Array(mergeDesktopSessions(with: cachedSessions).prefix(maxCachedSessions))
        captureDesktopApprovals(from: state, threadId: snapshot.id)
        lastSessionRefresh = Date()
        scheduleDesktopRolloutRefresh(threadId: threadId)
    }

    /// Desktop broadcasts can arrive several times per second while a turn is
    /// streaming. Update their in-memory state immediately, then coalesce the
    /// rollout refresh so no broadcast performs synchronous disk work.
    private func scheduleDesktopRolloutRefresh(threadId: String) {
        guard desktopRolloutRefreshTasks[threadId] == nil else { return }

        let token = UUID()
        desktopRolloutRefreshTokens[threadId] = token
        desktopRolloutRefreshTasks[threadId] = Task { @MainActor [weak self] in
            guard let self else { return }
            var shouldReschedule = false
            defer {
                if self.desktopRolloutRefreshTokens[threadId] == token {
                    self.desktopRolloutRefreshTasks[threadId] = nil
                    self.desktopRolloutRefreshTokens[threadId] = nil
                    if shouldReschedule {
                        self.scheduleDesktopRolloutRefresh(threadId: threadId)
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled,
                  let state = self.latestDesktopStates[threadId] else { return }

            let refreshVersion = self.desktopRolloutRefreshVersions[threadId] ?? 0
            let sourcePath = state["rolloutPath"] as? String ?? ""
            let rollout = await self.rolloutSummaryCache.summary(for: sourcePath)
            guard !Task.isCancelled else { return }

            self.desktopRolloutSummaries[sourcePath] = rollout
            if let latestState = self.latestDesktopStates[threadId],
               let snapshot = self.desktopSessionSnapshot(from: latestState, rollout: rollout) {
                self.desktopSessions[snapshot.id] = snapshot
                self.pruneDesktopSessions()
                self.cachedSessions = Array(
                    self.mergeDesktopSessions(with: self.cachedSessions).prefix(self.maxCachedSessions)
                )
                self.lastSessionRefresh = Date()
            }
            shouldReschedule = self.desktopRolloutRefreshVersions[threadId] != refreshVersion
        }
    }

    private func pruneDesktopSessions() {
        guard desktopSessions.count > maxCachedSessions else { return }
        let retained = desktopSessions.values
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(maxCachedSessions)
        desktopSessions = Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })

        let retainedIDs = Set(desktopSessions.keys)
        let removedIDs = latestDesktopStates.keys.filter { !retainedIDs.contains($0) }
        for threadId in removedIDs {
            latestDesktopStates.removeValue(forKey: threadId)
            desktopRolloutRefreshTasks.removeValue(forKey: threadId)?.cancel()
            desktopRolloutRefreshTokens.removeValue(forKey: threadId)
            desktopRolloutRefreshVersions.removeValue(forKey: threadId)
        }
        let retainedPaths = Set(latestDesktopStates.values.compactMap { $0["rolloutPath"] as? String })
        desktopRolloutSummaries = desktopRolloutSummaries.filter { retainedPaths.contains($0.key) }
    }

    private func desktopSessionSnapshot(
        from state: [String: Any],
        rollout: RolloutSummary
    ) -> CodexSessionSnapshot? {
        guard let id = state["id"] as? String else { return nil }
        let cwd = state["cwd"] as? String ?? ""
        let sourcePath = state["rolloutPath"] as? String ?? ""
        let created = Self.date(from: state["createdAt"]) ?? Date()
        let updated = Self.date(from: state["updatedAt"] ?? state["recencyAt"]) ?? created
        let requests = state["requests"] as? [[String: Any]] ?? []
        let requestMethods = requests.compactMap { $0["method"] as? String }
        let runtimeType = (state["threadRuntimeStatus"] as? [String: Any])?["type"] as? String
        let phase: String
        if requestMethods.contains("item/tool/requestUserInput") {
            phase = "waitingInput"
        } else if requestMethods.contains(where: { $0.hasPrefix("item/") }) {
            phase = "waitingApproval"
        } else if runtimeType == "active" || rollout.phase == "processing" {
            phase = "processing"
        } else if rollout.phase == "interrupted" {
            phase = "interrupted"
        } else {
            phase = "idle"
        }
        let activeTurnId = (state["threadRuntimeStatus"] as? [String: Any])?["activeTurnId"] as? String
            ?? rollout.activeTurnId

        return CodexSessionSnapshot(
            id: id,
            preview: (state["title"] as? String)?.nonEmpty ?? "Codex 会话",
            cwd: cwd,
            sourcePath: sourcePath,
            createdAt: created,
            updatedAt: updated,
            phase: phase,
            activeTurnId: activeTurnId,
            lastResponse: rollout.lastResponse,
            lastUserMessage: rollout.lastUserMessage,
            model: state["latestModel"] as? String ?? "Codex",
            source: state["source"] as? String ?? "desktop"
        )
    }

    private func captureDesktopApprovals(from state: [String: Any], threadId: String) {
        let requests = state["requests"] as? [[String: Any]] ?? []
        let requestIDs: Set<String> = Set(requests.compactMap { request in
            guard let method = request["method"] as? String, method.hasPrefix("item/") else { return nil }
            return "codex|\(threadId)|\(Self.requestKey(request["id"] as Any))"
        })
        pendingApprovals = pendingApprovals.filter { key, value in
            if value.snapshot.source == "desktop", value.snapshot.threadId == threadId {
                return requestIDs.contains(key)
            }
            return true
        }
        for request in requests {
            guard let method = request["method"] as? String,
                  method.hasPrefix("item/"),
                  let requestID = request["id"] else { continue }
            let params = request["params"] as? [String: Any] ?? [:]
            captureApproval(
                method: method,
                requestId: requestID,
                params: params,
                source: "desktop"
            )
        }
    }

    func approvalSnapshots() -> [CodexApprovalSnapshot] {
        pendingApprovals.values
            .map(\.snapshot)
            .sorted { $0.requestedAt > $1.requestedAt }
    }

    func sendInstruction(threadId: String, instruction: String) async -> CodexControlResult {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return CodexControlResult(
                ok: false,
                command: "codex_instruction",
                message: "请输入要发送给 Agent 的指令。",
                controlMode: "codex_native"
            )
        }

        let desktopActive = desktopSessions[threadId]?.phase == "processing"
            || cachedSessions.first(where: { $0.id == threadId })?.phase == "processing"
        if let coreResult = await TraceFenceAgentCoreClient.shared.control([
            "action": desktopActive ? "steer" : "start",
            "threadId": threadId,
            "instruction": text
        ]) {
            return CodexControlResult(
                ok: true,
                command: coreResult["command"] as? String ?? (desktopActive ? "codex_core_steer" : "codex_core_start"),
                message: coreResult["message"] as? String ?? "指令已交给 TraceFence Agent Core。",
                controlMode: coreResult["controlMode"] as? String ?? "tracefence_agent_core"
            )
        }

        let desktopInstruction = await DesktopCodexIPC.send(
            method: desktopActive ? "thread-follower-steer-turn" : "thread-follower-start-turn",
            version: 1,
            params: desktopActive
                ? [
                    "conversationId": threadId,
                    "input": [["type": "text", "text": text, "text_elements": []]]
                ]
                : [
                    "conversationId": threadId,
                    "turnStartParams": ["input": [["type": "text", "text": text, "text_elements": []]]]
                ]
        )
        switch desktopInstruction {
        case .accepted, .acceptedWithoutReply:
            return CodexControlResult(
                ok: true,
                command: desktopActive ? "codex_desktop_steer" : "codex_desktop_start",
                message: desktopActive
                    ? "新指令已插入 Mac 上当前打开的 Codex 任务。"
                    : "指令已交给 Mac 上当前打开的 Codex 会话。",
                controlMode: "codex_desktop_owner"
            )
        case .rejected(let message) where !Self.isNoClientIPCError(message):
            return CodexControlResult(
                ok: false,
                command: "codex_instruction",
                message: "Mac 上的 Codex 桌面会话没有接受指令：\(message)",
                controlMode: "codex_desktop_owner"
            )
        case .rejected:
            break
        }

        do {
            try await ensureStarted()
            let before = try? await readThread(threadId: threadId)
            var currentTurnId = activeTurnId(in: before) ?? activeTurns[threadId]
            let resumed = try await request(
                method: "thread/resume",
                params: [
                    "threadId": threadId,
                    "approvalPolicy": "on-request",
                    "approvalsReviewer": "user"
                ],
                timeout: 25
            )
            if currentTurnId == nil {
                currentTurnId = activeTurnId(in: resumed["thread"] as? [String: Any])
            }

            let input: [[String: Any]] = [[
                "type": "text",
                "text": text,
                "text_elements": []
            ]]

            if let currentTurnId {
                _ = try await request(
                    method: "turn/steer",
                    params: [
                        "threadId": threadId,
                        "expectedTurnId": currentTurnId,
                        "input": input
                    ],
                    timeout: 12
                )
                return CodexControlResult(
                    ok: true,
                    command: "codex_steer",
                    message: "新指令已插入 Mac 上正在执行的 Codex 任务。",
                    controlMode: "codex_native"
                )
            }

            let result = try await request(
                method: "turn/start",
                params: [
                    "threadId": threadId,
                    "input": input,
                    "approvalPolicy": "on-request",
                    "approvalsReviewer": "user"
                ],
                timeout: 15
            )
            if let turn = result["turn"] as? [String: Any], let turnId = turn["id"] as? String {
                activeTurns[threadId] = turnId
            }
            return CodexControlResult(
                ok: true,
                command: "codex_start",
                message: "指令已发送，Mac 上的 Codex 会话已经开始执行。",
                controlMode: "codex_native"
            )
        } catch {
            return await sendInstructionThroughDesktopIPC(
                threadId: threadId,
                instruction: text,
                active: activeTurns[threadId] != nil,
                originalError: error
            )
        }
    }

    func interrupt(threadId: String) async -> CodexControlResult {
        if let coreResult = await TraceFenceAgentCoreClient.shared.control([
            "action": "interrupt",
            "threadId": threadId
        ]) {
            activeTurns.removeValue(forKey: threadId)
            removeApprovals(threadId: threadId)
            return CodexControlResult(
                ok: true,
                command: coreResult["command"] as? String ?? "codex_core_interrupt",
                message: coreResult["message"] as? String ?? "中断请求已发送给 TraceFence Agent Core。",
                controlMode: coreResult["controlMode"] as? String ?? "tracefence_agent_core"
            )
        }

        let desktopResult = await DesktopCodexIPC.send(
            method: "thread-follower-interrupt-turn",
            version: 2,
            params: ["conversationId": threadId]
        )
        switch desktopResult {
        case .accepted, .acceptedWithoutReply:
            activeTurns.removeValue(forKey: threadId)
            removeApprovals(threadId: threadId)
            return CodexControlResult(
                ok: true,
                command: "codex_interrupt",
                message: "中断请求已发送给 Mac 上当前打开的 Codex 任务。",
                controlMode: "codex_desktop_owner"
            )
        case .rejected(let message) where !Self.isNoClientIPCError(message):
            return CodexControlResult(
                ok: false,
                command: "codex_interrupt",
                message: "Codex 桌面会话没有接受中断请求：\(message)",
                controlMode: "codex_desktop_owner"
            )
        case .rejected:
            break
        }

        do {
            try await ensureStarted()
            let read = try? await readThread(threadId: threadId)
            var turnId = activeTurnId(in: read) ?? activeTurns[threadId]
            let resumed = try await request(
                method: "thread/resume",
                params: [
                    "threadId": threadId,
                    "approvalPolicy": "on-request",
                    "approvalsReviewer": "user"
                ],
                timeout: 25
            )
            if turnId == nil {
                turnId = activeTurnId(in: resumed["thread"] as? [String: Any])
            }
            if let turnId {
                _ = try await request(
                    method: "turn/interrupt",
                    params: ["threadId": threadId, "turnId": turnId],
                    timeout: 12
                )
                activeTurns.removeValue(forKey: threadId)
                removeApprovals(threadId: threadId)
                return CodexControlResult(
                    ok: true,
                    command: "codex_interrupt",
                    message: "Mac 上的 Codex 任务已中断。",
                    controlMode: "codex_native"
                )
            }
        } catch {
            // The desktop renderer may still own an active turn; try its owner IPC below.
        }

        let ipcResult = await DesktopCodexIPC.send(
            method: "thread-follower-interrupt-turn",
            version: 2,
            params: ["conversationId": threadId]
        )
        switch ipcResult {
        case .accepted, .acceptedWithoutReply:
            activeTurns.removeValue(forKey: threadId)
            removeApprovals(threadId: threadId)
            return CodexControlResult(
                ok: true,
                command: "codex_interrupt",
                message: "中断请求已发送给 Mac 上当前打开的 Codex 任务。",
                controlMode: "codex_desktop_owner"
            )
        case .rejected(let message):
            return CodexControlResult(
                ok: false,
                command: "codex_interrupt",
                message: message.contains("no-client-found")
                    ? "这个会话当前没有正在执行的任务。"
                    : "Codex 没有接受中断请求：\(message)",
                controlMode: "codex_native"
            )
        }
    }

    func resolveApproval(id: String, allow: Bool, answer: String?) async -> CodexControlResult {
        guard let approval = pendingApprovals[id] else {
            return CodexControlResult(
                ok: false,
                command: allow ? "codex_approval_approve" : "codex_approval_deny",
                message: "该 Codex 权限请求已经处理或失效。",
                controlMode: "codex_native"
            )
        }

        if approval.snapshot.source == "desktop" {
            if let coreResult = await TraceFenceAgentCoreClient.shared.control([
                "action": "approval",
                "threadId": approval.snapshot.threadId,
                "requestId": approval.snapshot.requestId,
                "approvalMethod": approval.snapshot.method,
                "allow": allow,
                "answer": answer ?? "",
                "requestedPermissions": approval.snapshot.requestedPermissions,
                "questionIds": approval.snapshot.questionIds,
                "questionDefaults": approval.snapshot.questionDefaults
            ]) {
                pendingApprovals.removeValue(forKey: id)
                return CodexControlResult(
                    ok: true,
                    command: coreResult["command"] as? String ?? "codex_core_approval",
                    message: coreResult["message"] as? String ?? (allow ? "已确认 Mac 上的 Codex 请求，任务会继续执行。" : "已拒绝 Mac 上的 Codex 请求。"),
                    controlMode: coreResult["controlMode"] as? String ?? "tracefence_agent_core"
                )
            }
            let result = await resolveDesktopApproval(approval, allow: allow, answer: answer)
            if result.ok {
                pendingApprovals.removeValue(forKey: id)
            }
            return result
        }

        let response: [String: Any]
        switch approval.method {
        case "item/commandExecution/requestApproval":
            response = ["decision": allow ? "accept" : "decline"]
        case "item/fileChange/requestApproval":
            response = ["decision": allow ? "accept" : "decline"]
        case "item/permissions/requestApproval":
            response = [
                "permissions": allow ? approval.requestedPermissions : [:],
                "scope": "turn"
            ]
        case "item/tool/requestUserInput":
            let trimmed = answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var answers: [String: Any] = [:]
            for questionId in approval.questionIds {
                let value = trimmed.isEmpty ? (approval.questionDefaults[questionId] ?? "") : trimmed
                answers[questionId] = ["answers": [value]]
            }
            response = ["answers": answers]
        default:
            return CodexControlResult(
                ok: false,
                command: "codex_approval",
                message: "暂不支持这种 Codex 请求。",
                controlMode: "codex_native"
            )
        }

        do {
            try sendResponse(id: approval.requestId, result: response)
            pendingApprovals.removeValue(forKey: id)

            let replacement = answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !allow, !replacement.isEmpty, approval.method != "item/tool/requestUserInput" {
                return await sendInstruction(threadId: approval.snapshot.threadId, instruction: replacement)
            }
            return CodexControlResult(
                ok: true,
                command: allow ? "codex_approval_approve" : "codex_approval_deny",
                message: allow
                    ? "已在 iPhone 上批准 Codex 请求，Mac 任务会继续执行。"
                    : "已拒绝 Codex 请求。",
                controlMode: "codex_native"
            )
        } catch {
            return CodexControlResult(
                ok: false,
                command: "codex_approval",
                message: "审批回传失败：\(error.localizedDescription)",
                controlMode: "codex_native"
            )
        }
    }

    private func resolveDesktopApproval(
        _ approval: PendingApproval,
        allow: Bool,
        answer: String?
    ) async -> CodexControlResult {
        let snapshot = approval.snapshot
        let params: [String: Any]
        let method: String
        switch snapshot.method {
        case "item/commandExecution/requestApproval":
            method = "thread-follower-command-approval-decision"
            params = [
                "conversationId": snapshot.threadId,
                "requestId": snapshot.requestId,
                "decision": allow ? "accept" : "decline"
            ]
        case "item/fileChange/requestApproval":
            method = "thread-follower-file-approval-decision"
            params = [
                "conversationId": snapshot.threadId,
                "requestId": snapshot.requestId,
                "decision": allow ? "accept" : "decline"
            ]
        case "item/permissions/requestApproval":
            method = "thread-follower-permissions-request-approval-response"
            params = [
                "conversationId": snapshot.threadId,
                "requestId": snapshot.requestId,
                "response": [
                    "permissions": allow ? snapshot.requestedPermissions : [:],
                    "scope": "turn"
                ]
            ]
        case "item/tool/requestUserInput":
            method = "thread-follower-submit-user-input"
            let text = answer?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var answers: [String: Any] = [:]
            for questionId in snapshot.questionIds {
                let value = text.isEmpty ? (snapshot.questionDefaults[questionId] ?? "") : text
                answers[questionId] = ["answers": [value]]
            }
            params = [
                "conversationId": snapshot.threadId,
                "requestId": snapshot.requestId,
                "response": ["answers": answers]
            ]
        default:
            return CodexControlResult(
                ok: false,
                command: "codex_approval",
                message: "暂不支持这种 Codex 桌面请求。",
                controlMode: "codex_desktop_owner"
            )
        }

        switch await DesktopCodexIPC.send(method: method, version: 1, params: params) {
        case .accepted, .acceptedWithoutReply:
            return CodexControlResult(
                ok: true,
                command: allow ? "codex_approval_approve" : "codex_approval_deny",
                message: allow ? "已确认 Mac 上的 Codex 请求，任务会继续执行。" : "已拒绝 Mac 上的 Codex 请求。",
                controlMode: "codex_desktop_owner"
            )
        case .rejected(let message):
            return CodexControlResult(
                ok: false,
                command: "codex_approval",
                message: "Codex 桌面请求没有接受审批：\(message)",
                controlMode: "codex_desktop_owner"
            )
        }
    }

    private func sendInstructionThroughDesktopIPC(
        threadId: String,
        instruction: String,
        active: Bool,
        originalError: Error
    ) async -> CodexControlResult {
        let input: [[String: Any]] = [[
            "type": "text",
            "text": instruction,
            "text_elements": []
        ]]
        let method = active ? "thread-follower-steer-turn" : "thread-follower-start-turn"
        let params: [String: Any] = active
            ? ["conversationId": threadId, "input": input]
            : ["conversationId": threadId, "turnStartParams": ["input": input]]
        let result = await DesktopCodexIPC.send(method: method, version: 1, params: params)

        switch result {
        case .accepted, .acceptedWithoutReply:
            return CodexControlResult(
                ok: true,
                command: active ? "codex_desktop_steer" : "codex_desktop_start",
                message: active
                    ? "新指令已插入 Mac 上当前打开的 Codex 任务。"
                    : "指令已交给 Mac 上当前打开的 Codex 会话。",
                controlMode: "codex_desktop_owner"
            )
        case .rejected(let message):
            let detail = message.contains("no-client-found") ? originalError.localizedDescription : message
            return CodexControlResult(
                ok: false,
                command: "codex_instruction",
                message: "Mac 上的 Codex 会话没有接受指令：\(detail)",
                controlMode: "codex_native"
            )
        }
    }

    private static func isNoClientIPCError(_ message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("no-client-found")
            || normalized.contains("no client")
            || normalized.contains("owner") && normalized.contains("unavailable")
    }

    private func readThread(threadId: String) async throws -> [String: Any] {
        let result = try await request(
            method: "thread/read",
            params: ["threadId": threadId, "includeTurns": true],
            timeout: 12
        )
        guard let thread = result["thread"] as? [String: Any] else {
            throw CodexControlPlaneError.invalidResponse("thread/read")
        }
        return thread
    }

    private func activeTurnId(in thread: [String: Any]?) -> String? {
        guard let thread else { return nil }
        if let status = thread["status"] as? [String: Any], status["type"] as? String == "active",
           let turnId = status["activeTurnId"] as? String {
            return turnId
        }
        let turns = thread["turns"] as? [[String: Any]] ?? []
        return turns.reversed().first(where: {
            let status = ($0["status"] as? String ?? "").lowercased()
            return status == "inprogress" || status == "in_progress" || status == "active"
        })?["id"] as? String
    }

    private func sessionSnapshot(
        from row: [String: Any],
        rollout: RolloutSummary
    ) -> CodexSessionSnapshot? {
        guard
            let id = row["id"] as? String,
            let cwd = row["cwd"] as? String
        else {
            return nil
        }
        let sourcePath = Self.sourcePath(from: row)
        let preview = (row["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? (row["preview"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
            ?? "Codex 会话"
        let created = Self.date(from: row["createdAt"]) ?? Date()
        let updated = Self.date(from: row["recencyAt"] ?? row["updatedAt"]) ?? created
        let statusType = (row["status"] as? [String: Any])?["type"] as? String
        let knownActiveTurn = activeTurns[id]
        let source = row["source"] as? String ?? "app-server"
        let corePhase = row["phase"] as? String
        let phase: String
        if source == "agent-core", let corePhase {
            phase = corePhase
        } else if knownActiveTurn != nil || statusType == "active" || rollout.phase == "processing" {
            phase = "processing"
        } else if rollout.phase == "interrupted" {
            phase = "interrupted"
        } else {
            phase = "idle"
        }

        return CodexSessionSnapshot(
            id: id,
            preview: preview,
            cwd: cwd,
            sourcePath: sourcePath,
            createdAt: created,
            updatedAt: updated,
            phase: phase,
            activeTurnId: knownActiveTurn ?? rollout.activeTurnId,
            lastResponse: rollout.lastResponse,
            lastUserMessage: rollout.lastUserMessage,
            model: row["model"] as? String ?? "Codex",
            source: source
        )
    }

    private func ensureStarted() async throws {
        if initialized, process?.isRunning == true {
            return
        }
        guard let executableURL = Self.codexExecutableURL() else {
            throw CodexControlPlaneError.executableMissing
        }

        stopProcess()
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.consumeOutput(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return }
            Task { @MainActor in
                guard let self else { return }
                self.errorTail = String((self.errorTail + text).suffix(4_000))
            }
        }
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                self?.handleProcessTermination()
            }
        }

        try process.run()
        self.process = process
        inputHandle = inputPipe.fileHandleForWriting
        outputBuffer.removeAll(keepingCapacity: true)
        outputSearchOffset = 0
        initialized = false

        _ = try await requestWithoutStartup(
            method: "initialize",
            params: [
                "clientInfo": ["name": "TraceFence", "version": Self.appVersion],
                "capabilities": ["experimentalApi": true]
            ],
            timeout: 10
        )
        try sendNotification(method: "initialized", params: [:])
        initialized = true
    }

    private func request(method: String, params: [String: Any], timeout: TimeInterval) async throws -> [String: Any] {
        try await ensureStarted()
        return try await requestWithoutStartup(method: method, params: params, timeout: timeout)
    }

    private func requestWithoutStartup(
        method: String,
        params: [String: Any],
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        nextRequestId += 1
        let id = nextRequestId
        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = PendingRequest(completion: continuation, method: method)
            do {
                try writeJSON([
                    "jsonrpc": "2.0",
                    "id": id,
                    "method": method,
                    "params": params
                ])
            } catch {
                pendingRequests.removeValue(forKey: id)
                continuation.resume(throwing: error)
                return
            }

            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard let self, let pending = self.pendingRequests.removeValue(forKey: id) else { return }
                pending.completion.resume(throwing: CodexControlPlaneError.timeout(pending.method))
            }
        }
    }

    private func consumeOutput(_ data: Data) {
        outputBuffer.append(data)
        var lineStart = outputBuffer.startIndex
        var searchStart = outputBuffer.index(
            outputBuffer.startIndex,
            offsetBy: min(outputSearchOffset, outputBuffer.count)
        )
        while searchStart < outputBuffer.endIndex,
              let newlineIndex = outputBuffer[searchStart...].firstIndex(of: 0x0A) {
            let line = outputBuffer[lineStart..<newlineIndex]
            lineStart = outputBuffer.index(after: newlineIndex)
            searchStart = lineStart
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: line),
                  let message = object as? [String: Any]
            else {
                continue
            }
            handleMessage(message)
        }
        if lineStart > outputBuffer.startIndex {
            outputBuffer = lineStart < outputBuffer.endIndex
                ? Data(outputBuffer[lineStart..<outputBuffer.endIndex])
                : Data()
        }
        // Bytes left in the buffer have already been checked. Starting the
        // next search at the old end avoids rescanning a growing giant JSON
        // response on every pipe callback.
        outputSearchOffset = outputBuffer.count
    }

    private func handleMessage(_ message: [String: Any]) {
        if let id = Self.intId(message["id"]), message["method"] == nil,
           let pending = pendingRequests.removeValue(forKey: id) {
            if let error = message["error"] as? [String: Any] {
                let detail = error["message"] as? String ?? String(describing: error)
                pending.completion.resume(throwing: CodexControlPlaneError.server(detail))
            } else if let result = message["result"] as? [String: Any] {
                pending.completion.resume(returning: result)
            } else {
                pending.completion.resume(returning: [:])
            }
            return
        }

        guard let method = message["method"] as? String else { return }
        let params = message["params"] as? [String: Any] ?? [:]
        if message["id"] != nil, method.hasPrefix("item/") {
            captureApproval(method: method, requestId: message["id"] as Any, params: params)
            return
        }

        switch method {
        case "turn/started":
            if let threadId = params["threadId"] as? String,
               let turn = params["turn"] as? [String: Any],
               let turnId = turn["id"] as? String {
                activeTurns[threadId] = turnId
            }
        case "turn/completed":
            if let threadId = params["threadId"] as? String {
                activeTurns.removeValue(forKey: threadId)
                removeApprovals(threadId: threadId)
            }
        case "thread/status/changed":
            if let threadId = params["threadId"] as? String,
               let status = params["status"] as? [String: Any],
               status["type"] as? String == "idle" {
                activeTurns.removeValue(forKey: threadId)
            }
        default:
            break
        }
    }

    private func captureApproval(
        method: String,
        requestId: Any,
        params: [String: Any],
        source: String = "app-server"
    ) {
        guard
            let threadId = params["threadId"] as? String,
            let turnId = params["turnId"] as? String
        else {
            return
        }
        let requestKey = Self.requestKey(requestId)
        let id = "codex|\(threadId)|\(requestKey)"
        let startedAtMs = (params["startedAtMs"] as? NSNumber)?.doubleValue
        let requestedAt = startedAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) } ?? Date()
        var title = "Codex 请求确认"
        var detail = params["reason"] as? String ?? ""
        var kind = "permission"
        var options: [String] = []
        var descriptions: [String] = []
        var permissions: [String] = []
        var requiresTextAnswer = false
        var requestedPermissions: [String: Any] = [:]
        var questionIds: [String] = []
        var questionDefaults: [String: String] = [:]

        switch method {
        case "item/commandExecution/requestApproval":
            title = "执行命令"
            let command = params["command"] as? String ?? "未知命令"
            let cwd = params["cwd"] as? String ?? ""
            detail = [command, detail, cwd].filter { !$0.isEmpty }.joined(separator: "\n")
            options = Self.stringDecisions(params["availableDecisions"])
            if options.isEmpty { options = ["允许一次", "拒绝"] }
            permissions = Self.permissionLabels(params["additionalPermissions"])
        case "item/fileChange/requestApproval":
            title = "修改文件"
            let root = params["grantRoot"] as? String ?? ""
            detail = [detail, root].filter { !$0.isEmpty }.joined(separator: "\n")
        case "item/permissions/requestApproval":
            title = "提升任务权限"
            requestedPermissions = params["permissions"] as? [String: Any] ?? [:]
            permissions = Self.permissionLabels(requestedPermissions)
            if detail.isEmpty {
                detail = permissions.isEmpty ? "Codex 请求额外系统权限。" : permissions.joined(separator: "\n")
            }
        case "item/tool/requestUserInput":
            kind = "question"
            requiresTextAnswer = true
            let questions = params["questions"] as? [[String: Any]] ?? []
            title = questions.first?["header"] as? String ?? "Codex 提问"
            detail = questions.map { $0["question"] as? String ?? "" }.filter { !$0.isEmpty }.joined(separator: "\n")
            for question in questions {
                guard let questionId = question["id"] as? String else { continue }
                questionIds.append(questionId)
                let questionOptions = question["options"] as? [[String: Any]] ?? []
                if options.isEmpty {
                    options = questionOptions.compactMap { $0["label"] as? String }
                    descriptions = questionOptions.compactMap { $0["description"] as? String }
                }
                if let first = questionOptions.first?["label"] as? String {
                    questionDefaults[questionId] = first
                }
            }
        default:
            return
        }

        let snapshot = CodexApprovalSnapshot(
            id: id,
            threadId: threadId,
            turnId: turnId,
            kind: kind,
            title: title,
            detail: detail,
            options: options,
            descriptions: descriptions,
            permissions: permissions,
            requestedAt: requestedAt,
            requiresTextAnswer: requiresTextAnswer,
            source: source,
            requestId: requestKey,
            method: method,
            requestedPermissions: requestedPermissions,
            questionIds: questionIds,
            questionDefaults: questionDefaults
        )
        pendingApprovals[id] = PendingApproval(
            snapshot: snapshot,
            requestId: requestId,
            method: method,
            requestedPermissions: requestedPermissions,
            questionIds: questionIds,
            questionDefaults: questionDefaults
        )
    }

    private func removeApprovals(threadId: String) {
        pendingApprovals = pendingApprovals.filter { $0.value.snapshot.threadId != threadId }
    }

    private func sendResponse(id: Any, result: [String: Any]) throws {
        try writeJSON(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func sendNotification(method: String, params: [String: Any]) throws {
        try writeJSON(["jsonrpc": "2.0", "method": method, "params": params])
    }

    private func writeJSON(_ object: [String: Any]) throws {
        guard let inputHandle, process?.isRunning == true else {
            throw CodexControlPlaneError.notRunning
        }
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(0x0A)
        try inputHandle.write(contentsOf: data)
    }

    private func stopProcess() {
        process?.terminationHandler = nil
        if process?.isRunning == true {
            process?.terminate()
        }
        process = nil
        inputHandle = nil
        outputBuffer.removeAll(keepingCapacity: true)
        outputSearchOffset = 0
        initialized = false
    }

    private func handleProcessTermination() {
        let detail = errorTail.trimmingCharacters(in: .whitespacesAndNewlines)
        let error = CodexControlPlaneError.server(detail.isEmpty ? "Codex app-server 已退出。" : detail)
        let requests = pendingRequests.values
        pendingRequests.removeAll()
        for request in requests {
            request.completion.resume(throwing: error)
        }
        process = nil
        inputHandle = nil
        initialized = false
        activeTurns.removeAll()
        pendingApprovals.removeAll()
    }

    private static func codexExecutableURL() -> URL? {
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static func intId(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func requestKey(_ value: Any) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return String(describing: value)
    }

    private static func sourcePath(from row: [String: Any]) -> String {
        (row["path"] as? String) ?? (row["sourcePath"] as? String) ?? ""
    }

    private static func date(from value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        return Date(timeIntervalSince1970: raw > 9_999_999_999 ? raw / 1_000 : raw)
    }

    private static func stringDecisions(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap { item in
            if let text = item as? String {
                switch text {
                case "accept": return "允许一次"
                case "acceptForSession": return "本次会话始终允许"
                case "decline": return "拒绝"
                case "cancel": return "拒绝并中断"
                default: return text
                }
            }
            return nil
        }
    }

    private static func permissionLabels(_ value: Any?) -> [String] {
        guard let dictionary = value as? [String: Any], !dictionary.isEmpty else { return [] }
        var labels: [String] = []
        if let network = dictionary["network"] as? [String: Any], network["enabled"] as? Bool == true {
            labels.append("访问网络")
        }
        if dictionary["fileSystem"] != nil || dictionary["filesystem"] != nil {
            labels.append("访问工作区外文件")
        }
        if labels.isEmpty,
           let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) {
            labels.append(text)
        }
        return labels
    }

}

private enum CodexControlPlaneError: LocalizedError {
    case executableMissing
    case notRunning
    case invalidResponse(String)
    case timeout(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .executableMissing:
            return "Mac 上未找到 Codex/ChatGPT 控制运行时。"
        case .notRunning:
            return "Codex 控制服务未运行。"
        case .invalidResponse(let method):
            return "Codex 返回了无法识别的 \(method) 响应。"
        case .timeout(let method):
            return "Codex 处理 \(method) 超时。"
        case .server(let detail):
            return detail
        }
    }
}

private enum DesktopCodexIPCResult {
    case accepted
    case acceptedWithoutReply
    case rejected(String)
}

private enum DesktopCodexIPC {
    static func send(method: String, version: Int, params: [String: Any]) async -> DesktopCodexIPCResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: sendSync(method: method, version: version, params: params))
            }
        }
    }

    static func startObserver(_ handler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            while true {
                guard let socketPath = socketPath(),
                      let fd = connect(socketPath: socketPath) else {
                    Thread.sleep(forTimeInterval: 3)
                    continue
                }
                defer { close(fd) }

                let initialize: [String: Any] = [
                    "type": "request",
                    "requestId": UUID().uuidString,
                    "sourceClientId": "initializing-client",
                    "version": 0,
                    "method": "initialize",
                    "params": ["clientType": "tracefence-observer"],
                    "timeoutMs": 3_000
                ]
                guard writeFrame(initialize, fd: fd), readFrame(fd: fd) != nil else {
                    Thread.sleep(forTimeInterval: 1)
                    continue
                }

                while true {
                    let decoded: (didRead: Bool, message: [String: Any]?) = autoreleasepool {
                        guard let message = readFrame(fd: fd) else { return (false, nil) }
                        return (true, compactObserverMessage(message))
                    }
                    guard decoded.didRead else { break }
                    if let message = decoded.message {
                        handler(message)
                    }
                }
            }
        }
    }

    private static func compactObserverMessage(_ message: [String: Any]) -> [String: Any]? {
        guard message["type"] as? String == "broadcast",
              message["method"] as? String == "thread-stream-state-changed",
              let params = message["params"] as? [String: Any],
              let change = params["change"] as? [String: Any],
              change["type"] as? String == "snapshot",
              let state = change["conversationState"] as? [String: Any] else {
            return nil
        }

        var compactState: [String: Any] = [:]
        for key in [
            "id", "cwd", "rolloutPath", "createdAt", "updatedAt", "recencyAt",
            "title", "latestModel", "source"
        ] {
            if let value = state[key] { compactState[key] = value }
        }
        if let status = state["threadRuntimeStatus"] as? [String: Any] {
            var compactStatus: [String: Any] = [:]
            for key in ["type", "activeTurnId"] {
                if let value = status[key] { compactStatus[key] = value }
            }
            compactState["threadRuntimeStatus"] = compactStatus
        }
        if let requests = state["requests"] as? [[String: Any]] {
            compactState["requests"] = requests.compactMap { request -> [String: Any]? in
                guard let method = request["method"] as? String, method.hasPrefix("item/") else { return nil }
                var compactRequest: [String: Any] = ["method": method]
                if let id = request["id"] { compactRequest["id"] = id }
                if let requestParams = request["params"] as? [String: Any] {
                    var compactParams: [String: Any] = [:]
                    for key in [
                        "threadId", "turnId", "startedAtMs", "reason", "command", "cwd",
                        "availableDecisions", "additionalPermissions", "grantRoot", "permissions", "questions"
                    ] {
                        if let value = requestParams[key] { compactParams[key] = value }
                    }
                    compactRequest["params"] = compactParams
                }
                return compactRequest
            }
        }

        return [
            "type": "broadcast",
            "method": "thread-stream-state-changed",
            "params": [
                "change": [
                    "type": "snapshot",
                    "conversationState": compactState
                ]
            ]
        ]
    }

    private static func sendSync(method: String, version: Int, params: [String: Any]) -> DesktopCodexIPCResult {
        guard let socketPath = socketPath() else {
            return .rejected("no-client-found: Codex Desktop IPC socket is unavailable")
        }
        guard let fd = connect(socketPath: socketPath) else {
            return .rejected(lastPOSIXError())
        }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let initializeId = UUID().uuidString
        let initialize: [String: Any] = [
            "type": "request",
            "requestId": initializeId,
            "sourceClientId": "initializing-client",
            "version": 0,
            "method": "initialize",
            "params": ["clientType": "tracefence"],
            "timeoutMs": 3_000
        ]
        guard writeFrame(initialize, fd: fd) else { return .rejected(lastPOSIXError()) }
        guard let initialized = readFrame(fd: fd),
              initialized["resultType"] as? String == "success",
              let result = initialized["result"] as? [String: Any],
              let clientId = result["clientId"] as? String else {
            return .rejected((readableError(initialized: nil)) ?? lastPOSIXError())
        }

        let request: [String: Any] = [
            "type": "request",
            "requestId": UUID().uuidString,
            "sourceClientId": clientId,
            "version": version,
            "method": method,
            "params": params,
            "timeoutMs": 5_000
        ]
        guard writeFrame(request, fd: fd) else { return .rejected(lastPOSIXError()) }
        guard let response = readFrame(fd: fd) else {
            return errno == EAGAIN || errno == EWOULDBLOCK ? .acceptedWithoutReply : .rejected(lastPOSIXError())
        }
        if response["resultType"] as? String == "success" {
            return .accepted
        }
        return .rejected(readableError(initialized: response) ?? String(describing: response))
    }

    private static func socketPath() -> String? {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("codex-ipc", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        let uid = getuid()
        return entries.first(where: { $0.lastPathComponent == "ipc-\(uid).sock" })?.path
            ?? entries.first(where: { $0.pathExtension == "sock" })?.path
    }

    private static func connect(socketPath: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            close(fd)
            return nil
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { destination in
                _ = pathBytes.withUnsafeBufferPointer { source in
                    memcpy(destination, source.baseAddress, pathBytes.count)
                }
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            close(fd)
            return nil
        }
        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    private static func writeFrame(_ object: [String: Any], fd: Int32) -> Bool {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else { return false }
        var length = UInt32(body.count).littleEndian
        let header = Data(bytes: &length, count: MemoryLayout<UInt32>.size)
        return writeAll(header, fd: fd) && writeAll(body, fd: fd)
    }

    private static func readFrame(fd: Int32) -> [String: Any]? {
        guard let header = readExact(count: 4, fd: fd) else { return nil }
        let length = header.withUnsafeBytes { raw -> UInt32 in
            raw.load(as: UInt32.self).littleEndian
        }
        guard length > 0, length < 16 * 1_024 * 1_024,
              let body = readExact(count: Int(length), fd: fd),
              let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func writeAll(_ data: Data, fd: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.baseAddress else { return false }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                guard written > 0 else { return false }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }

    private static func readExact(count: Int, fd: Int32) -> Data? {
        var data = Data(count: count)
        let success = data.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard var pointer = rawBuffer.baseAddress else { return false }
            var remaining = count
            while remaining > 0 {
                let received = Darwin.read(fd, pointer, remaining)
                guard received > 0 else { return false }
                remaining -= received
                pointer = pointer.advanced(by: received)
            }
            return true
        }
        return success ? data : nil
    }

    private static func readableError(initialized response: [String: Any]?) -> String? {
        if let error = response?["error"] as? String { return error }
        if let error = response?["error"] as? [String: Any] {
            return error["message"] as? String ?? String(describing: error)
        }
        return nil
    }

    private static func lastPOSIXError() -> String {
        String(cString: strerror(errno))
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
