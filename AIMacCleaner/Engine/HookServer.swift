import Foundation
import Network

actor HookServer {
    private let socketPath = "/tmp/agentguard.sock"
    private let maxRawEventsPerSession = 200
    private let maxRawEventSessions = 200

    private var unixListener: NWListener?

    private var pendingPermissions: [String: [PendingPermissionEntry]] = [:]
    private var pendingQuestions: [String: PendingQuestionEntry] = [:]
    private var pendingPlans: [String: PendingPlanEntry] = [:]

    private var rawEvents: [String: [RawHookEvent]] = [:]
    private var nextSeq: UInt64 = 0

    weak var sessionStore: SessionStore?
    weak var soundEngine: SoundEngine?
    weak var guardFeature: AgentGuardFeature?
    weak var scannerService: ScannerService?

    private var eventObservers: [(UUID, AsyncStream<AgentHookEvent>.Continuation)] = []

    func setup(
        sessionStore: SessionStore,
        soundEngine: SoundEngine,
        guardFeature: AgentGuardFeature?,
        scannerService: ScannerService?
    ) {
        self.sessionStore = sessionStore
        self.soundEngine = soundEngine
        self.guardFeature = guardFeature
        self.scannerService = scannerService
    }

    func start() throws {
        unlink(socketPath)

        let unixParams = NWParameters.tcp
        unixParams.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
        unixListener = try NWListener(using: unixParams)
        unixListener?.stateUpdateHandler = { [socketPath] state in
            if case .failed(let error) = state {
                print("[AgentGuard] Unix listener failed on \(socketPath): \(error)")
            }
        }
        unixListener?.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection, label: "unix") }
        }
        unixListener?.start(queue: .global())

        print("[AgentGuard] HookServer started on \(socketPath)")
    }

    func stop() {
        unixListener?.cancel()
        resumePendingRequestsForShutdown()
        eventObservers.removeAll()
        unlink(socketPath)
    }

    func observeEvents() -> AsyncStream<AgentHookEvent> {
        AsyncStream { continuation in
            let id = UUID()
            eventObservers.append((id, continuation))
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id) }
            }
        }
    }

    private func removeObserver(_ id: UUID) {
        eventObservers.removeAll { $0.0 == id }
    }

    private func handleConnection(_ connection: NWConnection, label: String) {
        connection.start(queue: .global())

        var buffer = ""
        func receiveNext() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
                guard let self = self else { return }

                if let error = error {
                    print("[AgentGuard] Connection error (\(label)): \(error)")
                    connection.cancel()
                    return
                }

                if let data = data, let chunk = String(data: data, encoding: .utf8) {
                    buffer += chunk
                    let lines = buffer.components(separatedBy: "\n")
                    buffer = lines.last ?? ""

                    for i in 0..<(lines.count - 1) {
                        let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !line.isEmpty else { continue }
                        Task { await self.processLine(line, connection: connection) }
                    }
                }

                if isComplete {
                    let line = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !line.isEmpty {
                        Task { await self.processLine(line, connection: connection) }
                    }
                    connection.cancel()
                    return
                }

                receiveNext()
            }
        }

        receiveNext()
    }

    private func processLine(_ line: String, connection: NWConnection) async {
        guard let data = line.data(using: .utf8),
              var raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if raw["event"] == nil, let merged = mergeMultilineEvent(line) {
            raw = merged
        }

        if raw["event"] == nil, let hookEventName = raw["hook_event_name"] as? String ?? raw["hookEventName"] as? String {
            raw["event"] = hookEventName
        }

        let eventName = raw["event"] as? String ?? ""
        let sessionId = rawString(raw, keys: ["session_id", "sessionId", "conversation_id", "conversationId", "id"])

        storeRawEvent(sessionId: sessionId, eventName: eventName, raw: line)

        if eventName == "PermissionRequest" || eventName == "permission_request" {
            await seedPendingSession(from: raw, fallbackProject: "Approval Request")
            await publishRealtimeEvent(from: raw, updateSessionStore: true)
            let response = await waitForPermissionResponse(from: raw)
            await sendJSON(response, to: connection)
            return
        }

        if eventName == "AskQuestion" || eventName == "ask_question" {
            await seedPendingSession(from: raw, fallbackProject: "Question Request")
            await publishRealtimeEvent(from: raw, updateSessionStore: true)
            let response = await waitForQuestionResponse(from: raw)
            await sendJSON(response, to: connection)
            return
        }

        if eventName == "PlanApproval" || eventName == "plan_approval" {
            await seedPendingSession(from: raw, fallbackProject: "Plan Approval")
            await publishRealtimeEvent(from: raw, updateSessionStore: true)
            let response = await waitForPlanResponse(from: raw)
            await sendJSON(response, to: connection)
            return
        }

        await publishRealtimeEvent(from: raw, updateSessionStore: true)
    }

    private func publishRealtimeEvent(from raw: [String: Any], updateSessionStore: Bool) async {
        var normalized = raw
        if normalized["event"] == nil, let hookEventName = normalized["hook_event_name"] as? String ?? normalized["hookEventName"] as? String {
            normalized["event"] = hookEventName
        }

        guard let event = AgentHookEvent.parse(from: normalized) else { return }

        if updateSessionStore {
            await sessionStore?.handleEvent(event)
        }
        if let record = auditRecord(from: normalized, event: event) {
            await MainActor.run { [weak scannerService] in
                scannerService?.ingestHookAuditRecord(record)
            }
        }
        await guardFeature?.checkAgentEvent(event)
        await soundEngine?.play(for: event)

        for (_, continuation) in eventObservers {
            continuation.yield(event)
        }
    }

    private func seedPendingSession(from raw: [String: Any], fallbackProject: String) async {
        let sessionId = rawString(raw, keys: ["session_id", "sessionId", "conversation_id", "conversationId", "id"])
        guard !sessionId.isEmpty else { return }
        let cwd = rawString(raw, keys: ["cwd", "working_directory", "workingDirectory", "project_path", "projectPath"])
        await sessionStore?.seedPendingSession(
            sessionId: sessionId,
            agentType: rawString(raw, keys: ["agent", "source_label", "sourceLabel", "provider"], fallback: "Agent Center"),
            project: projectName(from: cwd, fallback: fallbackProject),
            cwd: cwd,
            terminal: rawString(raw, keys: ["tty", "terminal"])
        )
    }

    private func sendJSON<T: Encodable>(_ value: T, to connection: NWConnection) async {
        guard let data = try? JSONEncoder().encode(value),
              var str = String(data: data, encoding: .utf8) else { return }
        str += "\n"
        guard let sendData = str.data(using: .utf8) else { return }
        connection.send(content: sendData, completion: .contentProcessed({ _ in }))
    }

    private func resumePendingRequestsForShutdown() {
        for entries in pendingPermissions.values {
            for entry in entries {
                entry.continuation.resume(returning: permissionResponse(decision: .deny(reason: "TraceFence stopped"), raw: [:]))
            }
        }
        pendingPermissions.removeAll()

        for entry in pendingQuestions.values {
            entry.continuation.resume(returning: QuestionResponse(answer: ""))
        }
        pendingQuestions.removeAll()

        for entry in pendingPlans.values {
            entry.continuation.resume(returning: PlanResponse(mode: "cancel", message: "TraceFence stopped"))
        }
        pendingPlans.removeAll()
    }

    private func waitForPermissionResponse(from raw: [String: Any]) async -> PermissionResponse {
        let sessionId = rawString(raw, keys: ["session_id", "sessionId", "conversation_id", "conversationId", "id"])
        let toolName = rawString(raw, keys: ["tool", "tool_name", "toolName", "name"])
        let key = "\(sessionId):\(toolName)"

        return await withCheckedContinuation { continuation in
            let entry = PendingPermissionEntry(
                sessionId: sessionId,
                toolName: toolName,
                toolInput: rawString(raw, keys: ["tool_input", "toolInput", "input", "arguments", "args"]),
                raw: raw,
                continuation: continuation
            )
            var entries = pendingPermissions[key] ?? []
            entries.append(entry)
            pendingPermissions[key] = entries

            Task { @MainActor in
                await self.seedPendingSession(from: raw, fallbackProject: "Approval Request")
                await self.sessionStore?.setPendingPermission(sessionId, PendingPermission(
                    toolName: toolName,
                    toolInput: entry.toolInput,
                    diff: raw["diff"] as? String,
                    options: raw["options"] as? [String],
                    attachments: self.extractAttachments(from: raw),
                    source: raw["source"] as? String,
                    sourceLabel: raw["source_label"] as? String ?? raw["sourceLabel"] as? String,
                    requiresExternalHandling: raw["requires_external_handling"] as? Bool ?? raw["requiresExternalHandling"] as? Bool ?? false,
                    externalActionBundleId: raw["external_action_bundle_id"] as? String ?? raw["externalActionBundleId"] as? String,
                    externalActionHint: raw["external_action_hint"] as? String ?? raw["externalActionHint"] as? String
                ))
            }
        }
    }

    private nonisolated func projectName(from cwd: String, fallback: String) -> String {
        guard !cwd.isEmpty else { return fallback }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    private nonisolated func rawString(_ raw: [String: Any], keys: [String], fallback: String = "") -> String {
        for key in keys {
            if let value = raw[key] as? String, !value.isEmpty { return value }
            if let value = raw[key],
               JSONSerialization.isValidJSONObject(value),
               let data = try? JSONSerialization.data(withJSONObject: value),
               let string = String(data: data, encoding: .utf8),
               !string.isEmpty {
                return string
            }
        }
        return fallback
    }

    private func waitForQuestionResponse(from raw: [String: Any]) async -> QuestionResponse {
        let sessionId = rawString(raw, keys: ["session_id", "sessionId", "conversation_id", "conversationId", "id"])

        return await withCheckedContinuation { continuation in
            pendingQuestions[sessionId] = PendingQuestionEntry(continuation: continuation)

            Task { @MainActor in
                await self.seedPendingSession(from: raw, fallbackProject: "Question Request")
                await self.sessionStore?.setPendingQuestion(sessionId, PendingQuestion(
                    question: raw["question"] as? String ?? "",
                    options: raw["options"] as? [String] ?? [],
                    descriptions: raw["descriptions"] as? [String] ?? [],
                    header: raw["header"] as? String,
                    multiSelect: raw["multi_select"] as? Bool ?? false,
                    questions: AgentHookEvent.parseQuestions(from: raw),
                    responseMode: raw["response_mode"] as? String ?? raw["responseMode"] as? String,
                    attachments: self.extractAttachments(from: raw)
                ))
            }
        }
    }

    private func waitForPlanResponse(from raw: [String: Any]) async -> PlanResponse {
        let sessionId = rawString(raw, keys: ["session_id", "sessionId", "conversation_id", "conversationId", "id"])

        return await withCheckedContinuation { continuation in
            pendingPlans[sessionId] = PendingPlanEntry(continuation: continuation)

            Task { @MainActor in
                await self.seedPendingSession(from: raw, fallbackProject: "Plan Approval")
                await self.sessionStore?.setPendingPlan(sessionId, PendingPlan(
                    title: raw["plan_title"] as? String ?? "Plan",
                    content: raw["plan_content"] as? String ?? "",
                    permissions: raw["requested_permissions"] as? [String] ?? [],
                    attachments: self.extractAttachments(from: raw)
                ))
            }
        }
    }

    private nonisolated func extractAttachments(from raw: [String: Any]) -> [ApprovalAttachment] {
        var attachments: [ApprovalAttachment] = []
        var seen: Set<String> = []

        func addPath(_ value: String?, title: String? = nil, mimeType: String? = nil) {
            guard let value else { return }
            let path = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !path.isEmpty, !seen.contains(path) else { return }
            let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
            let looksLikeImage = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp"].contains(ext)
            let typedAsImage = mimeType?.lowercased().hasPrefix("image/") == true
            guard looksLikeImage || typedAsImage else { return }
            seen.insert(path)
            attachments.append(ApprovalAttachment(path: path, title: title, mimeType: mimeType))
        }

        func scanObject(_ object: Any, title: String? = nil) {
            if let text = object as? String {
                addPath(text, title: title)
                if let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) {
                    scanObject(json, title: title)
                }
                return
            }

            if let array = object as? [Any] {
                for item in array { scanObject(item, title: title) }
                return
            }

            guard let dict = object as? [String: Any] else { return }
            let title = (dict["title"] as? String) ?? (dict["name"] as? String) ?? title
            let mimeType = (dict["mime_type"] as? String) ?? (dict["mimeType"] as? String) ?? (dict["type"] as? String)

            for key in ["path", "file_path", "filePath", "image_path", "imagePath", "url"] {
                addPath(dict[key] as? String, title: title, mimeType: mimeType)
            }

            for key in ["image", "images", "attachment", "attachments", "files", "artifacts"] {
                if let nested = dict[key] {
                    scanObject(nested, title: title)
                }
            }
        }

        for key in ["image_path", "imagePath", "file_path", "filePath", "path", "images", "attachments", "artifact", "artifacts", "tool_input", "toolInput"] {
            if let value = raw[key] {
                scanObject(value)
            }
        }

        return attachments
    }

    func respondToPermission(sessionId: String, toolName: String, decision: PermissionDecision) {
        let key = "\(sessionId):\(toolName)"
        if let entries = pendingPermissions.removeValue(forKey: key) {
            for entry in entries {
                entry.continuation.resume(returning: permissionResponse(decision: decision, raw: entry.raw))
            }
        }
    }

    func respondToQuestion(sessionId: String, answer: String) {
        if let entry = pendingQuestions.removeValue(forKey: sessionId) {
            entry.continuation.resume(returning: QuestionResponse(answer: answer))
        }
    }

    func respondToPlan(sessionId: String, mode: String, message: String?) {
        if let entry = pendingPlans.removeValue(forKey: sessionId) {
            entry.continuation.resume(returning: PlanResponse(mode: mode, message: message))
        }
    }

    private func storeRawEvent(sessionId: String, eventName: String, raw: String) {
        let event = RawHookEvent(
            seq: nextSeq,
            timestampMs: UInt64(Date().timeIntervalSince1970 * 1000),
            sessionId: sessionId,
            agent: nil,
            eventName: eventName,
            raw: raw
        )
        nextSeq += 1

        var events = rawEvents[sessionId] ?? []
        if events.count >= maxRawEventsPerSession {
            events.removeFirst()
        }
        events.append(event)
        rawEvents[sessionId] = events
        if rawEvents.count > maxRawEventSessions,
           let oldest = rawEvents.min(by: {
               ($0.value.last?.timestampMs ?? 0) < ($1.value.last?.timestampMs ?? 0)
           })?.key {
            rawEvents.removeValue(forKey: oldest)
        }
    }

    func getRawEvents(for sessionId: String) -> [RawHookEvent] {
        rawEvents[sessionId] ?? []
    }

    private func mergeMultilineEvent(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func auditRecord(from raw: [String: Any], event: AgentHookEvent) -> OperationRecord? {
        let eventName = rawString(raw, keys: ["event", "hook_event_name", "hookEventName"])
        guard shouldRecordAuditEvent(eventName: eventName) else { return nil }

        let sessionId = rawString(raw, keys: ["session_id", "sessionId", "conversation_id", "conversationId", "id"])
        let agent = rawString(raw, keys: ["agent", "source_label", "sourceLabel", "provider"], fallback: "Agent Center")
        let toolName = rawString(raw, keys: ["tool", "tool_name", "toolName", "name"], fallback: eventName)
        let toolInput = rawString(raw, keys: ["tool_input", "toolInput", "input", "arguments", "args"])
        let cwd = rawString(raw, keys: ["cwd", "working_directory", "workingDirectory", "project_path", "projectPath"])
        let status = rawString(raw, keys: ["status"])
        let target = auditTarget(raw: raw, toolInput: toolInput, cwd: cwd, toolName: toolName)
        let detail = auditDetail(eventName: eventName, toolName: toolName, toolInput: toolInput, target: target, status: status)

        guard !target.isEmpty || !detail.isEmpty else { return nil }

        return OperationRecord(
            id: "hook_\(sessionId)_\(eventName)_\(toolName)_\(nextSeq)_\(UUID().uuidString)",
            timestamp: Date(),
            agentName: agent.isEmpty ? "Agent Center" : agent,
            operationType: auditOperationType(eventName: eventName, toolName: toolName, target: target, detail: detail),
            targetPath: target.isEmpty ? detail : target,
            detail: detail.isEmpty ? target : detail,
            fileSize: 0,
            processName: toolName,
            toolInfo: sessionId.isEmpty ? event.sessionId : sessionId
        )
    }

    private func shouldRecordAuditEvent(eventName: String) -> Bool {
        switch eventName {
        case "PreToolUse", "pre_tool_use",
             "PostToolUse", "post_tool_use",
             "PostToolUseFailure", "post_tool_use_failure",
             "PermissionDenied", "permission_denied",
             "PermissionRequest", "permission_request",
             "ShellExecutionStart", "shell_execution_start",
             "ShellExecutionEnd", "shell_execution_end",
             "MCPExecutionStart", "mcp_execution_start",
             "MCPExecutionEnd", "mcp_execution_end":
            return true
        default:
            return false
        }
    }

    private func auditTarget(raw: [String: Any], toolInput: String, cwd: String, toolName: String) -> String {
        for key in ["target_path", "targetPath", "file_path", "filePath", "path", "command"] {
            let value = rawString(raw, keys: [key])
            if !value.isEmpty { return value }
        }

        if let parsed = parseJSONString(toolInput) {
            for key in ["file_path", "filePath", "path", "target_path", "targetPath", "command"] {
                let value = rawString(parsed, keys: [key])
                if !value.isEmpty { return value }
            }
        }

        let lowerTool = toolName.lowercased()
        if lowerTool.contains("shell") || lowerTool.contains("bash") || lowerTool.contains("exec") || lowerTool.contains("command") {
            return toolInput
        }
        return cwd
    }

    private func auditDetail(eventName: String, toolName: String, toolInput: String, target: String, status: String) -> String {
        var parts = [eventName, toolName].filter { !$0.isEmpty }
        if !status.isEmpty { parts.append(status) }
        if !toolInput.isEmpty && toolInput != target {
            parts.append(String(toolInput.prefix(240)))
        }
        return parts.joined(separator: " · ")
    }

    private func auditOperationType(eventName: String, toolName: String, target: String, detail: String) -> OperationRecord.OperationType {
        let combined = "\(eventName) \(toolName) \(target) \(detail)".lowercased()
        if combined.contains("delete") || combined.contains("remove") || combined.contains("trash") || combined.contains(" rm ") {
            return .delete
        }
        if combined.contains("read") || combined.contains("view") || combined.contains("open") || combined.contains("grep") || combined.contains("rg ") || combined.contains("cat ") || combined.contains("ls ") {
            return .read
        }
        if combined.contains("shell") || combined.contains("bash") || combined.contains("exec") || combined.contains("command") || combined.contains("mcp") {
            return .execute
        }
        if combined.contains("write") || combined.contains("create") || combined.contains("new file") {
            return .create
        }
        if combined.contains("move") {
            return .move
        }
        if combined.contains("rename") {
            return .rename
        }
        return .modify
    }

    private func parseJSONString(_ value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func permissionResponse(decision: PermissionDecision, raw: [String: Any]) -> PermissionResponse {
        let behavior = decision.decision == "deny" ? "deny" : "allow"
        let updatedPermissions = decision.always == true
            ? codablePermissionSuggestions(from: raw)
            : decision.updatedPermissions
        let hookDecision = HookPermissionDecision(
            behavior: behavior,
            message: behavior == "deny" ? decision.reason : nil,
            updatedPermissions: updatedPermissions
        )
        let hookOutput = HookSpecificPermissionOutput(
            hookEventName: "PermissionRequest",
            decision: hookDecision
        )
        return PermissionResponse(
            decision: decision.decision,
            reason: decision.reason,
            always: decision.always,
            hookSpecificOutput: hookOutput,
            permissionDecision: behavior,
            permissionDecisionReason: decision.reason
        )
    }

    private func codablePermissionSuggestions(from raw: [String: Any]) -> [[String: AnyCodable]]? {
        guard let suggestions = raw["permission_suggestions"] as? [[String: Any]],
              !suggestions.isEmpty else { return nil }
        return suggestions.map { suggestion in
            suggestion.mapValues { AnyCodable($0) }
        }
    }
}

struct PendingPermissionEntry {
    let sessionId: String
    let toolName: String
    let toolInput: String
    let raw: [String: Any]
    let continuation: CheckedContinuation<PermissionResponse, Never>
}

struct PendingQuestionEntry {
    let continuation: CheckedContinuation<QuestionResponse, Never>
}

struct PendingPlanEntry {
    let continuation: CheckedContinuation<PlanResponse, Never>
}
