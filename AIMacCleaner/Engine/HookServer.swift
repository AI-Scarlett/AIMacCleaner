import Foundation
import Network

actor HookServer {
    private let socketPath = "/tmp/agentguard.sock"
    private let tcpPort: NWEndpoint.Port = 17893
    private let maxRawEventsPerSession = 200
    private let maxRawEventSessions = 200

    private var tcpListener: NWListener?
    private var unixListener: NWListener?

    private var pendingPermissions: [String: [PendingPermissionEntry]] = [:]
    private var pendingQuestions: [String: PendingQuestionEntry] = [:]
    private var pendingPlans: [String: PendingPlanEntry] = [:]

    private var rawEvents: [String: [RawHookEvent]] = [:]
    private var nextSeq: UInt64 = 0

    weak var sessionStore: SessionStore?
    weak var soundEngine: SoundEngine?
    weak var guardFeature: AgentGuardFeature?

    private var eventObservers: [(UUID, AsyncStream<AgentHookEvent>.Continuation)] = []

    func setup(sessionStore: SessionStore, soundEngine: SoundEngine, guardFeature: AgentGuardFeature) {
        self.sessionStore = sessionStore
        self.soundEngine = soundEngine
        self.guardFeature = guardFeature
    }

    func start() throws {
        unlink(socketPath)

        let tcpParams = NWParameters.tcp
        tcpListener = try NWListener(using: tcpParams, on: tcpPort)
        tcpListener?.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection, label: "tcp") }
        }
        tcpListener?.start(queue: .global())

        let unixParams = NWParameters.tcp
        unixParams.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
        unixListener = try NWListener(using: unixParams)
        unixListener?.newConnectionHandler = { [weak self] connection in
            Task { await self?.handleConnection(connection, label: "unix") }
        }
        unixListener?.start(queue: .global())

        print("[AgentGuard] HookServer started on \(socketPath) and port \(tcpPort)")
    }

    func stop() {
        tcpListener?.cancel()
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

                if isComplete {
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

        let eventName = raw["event"] as? String ?? ""
        let sessionId = raw["session_id"] as? String ?? ""

        storeRawEvent(sessionId: sessionId, eventName: eventName, raw: line)

        if eventName == "PermissionRequest" || eventName == "permission_request" {
            let response = await waitForPermissionResponse(from: raw)
            await sendJSON(response, to: connection)
            return
        }

        if eventName == "AskQuestion" || eventName == "ask_question" {
            let response = await waitForQuestionResponse(from: raw)
            await sendJSON(response, to: connection)
            return
        }

        if eventName == "PlanApproval" || eventName == "plan_approval" {
            let response = await waitForPlanResponse(from: raw)
            await sendJSON(response, to: connection)
            return
        }

        guard let event = AgentHookEvent.parse(from: raw) else { return }

        await sessionStore?.handleEvent(event)
        await guardFeature?.checkAgentEvent(event)
        await soundEngine?.play(for: event)

        for (_, continuation) in eventObservers {
            continuation.yield(event)
        }
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
                entry.continuation.resume(returning: PermissionResponse(decision: "deny", reason: "AgentGuard stopped"))
            }
        }
        pendingPermissions.removeAll()

        for entry in pendingQuestions.values {
            entry.continuation.resume(returning: QuestionResponse(answer: ""))
        }
        pendingQuestions.removeAll()

        for entry in pendingPlans.values {
            entry.continuation.resume(returning: PlanResponse(mode: "cancel", message: "AgentGuard stopped"))
        }
        pendingPlans.removeAll()
    }

    private func waitForPermissionResponse(from raw: [String: Any]) async -> PermissionResponse {
        let sessionId = raw["session_id"] as? String ?? ""
        let toolName = raw["tool"] as? String ?? raw["tool_name"] as? String ?? ""
        let key = "\(sessionId):\(toolName)"

        return await withCheckedContinuation { continuation in
            let entry = PendingPermissionEntry(
                sessionId: sessionId,
                toolName: toolName,
                toolInput: (raw["tool_input"] as? String) ?? "",
                continuation: continuation
            )
            var entries = pendingPermissions[key] ?? []
            entries.append(entry)
            pendingPermissions[key] = entries

            Task { @MainActor in
                await self.sessionStore?.seedPendingSession(
                    sessionId: sessionId,
                    agentType: raw["agent"] as? String ?? raw["source_label"] as? String ?? "Agent Center",
                    project: self.projectName(from: raw["cwd"] as? String ?? "", fallback: "Approval Request"),
                    cwd: raw["cwd"] as? String ?? "",
                    terminal: raw["tty"] as? String ?? ""
                )
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

    private func waitForQuestionResponse(from raw: [String: Any]) async -> QuestionResponse {
        let sessionId = raw["session_id"] as? String ?? ""

        return await withCheckedContinuation { continuation in
            pendingQuestions[sessionId] = PendingQuestionEntry(continuation: continuation)

            Task { @MainActor in
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
        let sessionId = raw["session_id"] as? String ?? ""

        return await withCheckedContinuation { continuation in
            pendingPlans[sessionId] = PendingPlanEntry(continuation: continuation)

            Task { @MainActor in
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
                entry.continuation.resume(returning: PermissionResponse(
                    decision: decision.decision,
                    reason: decision.reason,
                    always: decision.always
                ))
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
}

struct PendingPermissionEntry {
    let sessionId: String
    let toolName: String
    let toolInput: String
    let continuation: CheckedContinuation<PermissionResponse, Never>
}

struct PendingQuestionEntry {
    let continuation: CheckedContinuation<QuestionResponse, Never>
}

struct PendingPlanEntry {
    let continuation: CheckedContinuation<PlanResponse, Never>
}
