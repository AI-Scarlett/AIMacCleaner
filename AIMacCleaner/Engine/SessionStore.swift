import Foundation

actor SessionStore {
    private var sessions: [String: SessionState] = [:]
    private var onChangeCallbacks: [(UUID, @MainActor ([SessionState]) -> Void)] = []
    private let sessionEndCleanupSeconds: TimeInterval = 5
    private let doneSessionCleanupSeconds: TimeInterval = 7200
    private let notifyThrottleNanos: UInt64 = 250_000_000
    private var notifyTask: Task<Void, Never>?

    func getOrCreateSession(sessionId: String, agentType: String, project: String, cwd: String, terminal: String) -> SessionState {
        if let existing = sessions[sessionId] {
            return existing
        }
        let session = SessionState(
            id: sessionId,
            agentType: agentType,
            project: project,
            cwd: cwd,
            terminal: terminal,
            startedAt: Date()
        )
        sessions[sessionId] = session
        return session
    }

    private func ensureSessionForPendingRequest(
        sessionId: String,
        agentType: String = "Agent Center",
        project: String = "Approval Request",
        cwd: String = "",
        terminal: String = ""
    ) {
        guard !sessionId.isEmpty, sessions[sessionId] == nil else { return }
        sessions[sessionId] = SessionState(
            id: sessionId,
            agentType: agentType,
            project: project,
            cwd: cwd,
            terminal: terminal,
            startedAt: Date()
        )
    }

    func seedPendingSession(
        sessionId: String,
        agentType: String,
        project: String,
        cwd: String,
        terminal: String = ""
    ) {
        ensureSessionForPendingRequest(
            sessionId: sessionId,
            agentType: agentType,
            project: project,
            cwd: cwd,
            terminal: terminal
        )
        sessions[sessionId]?.agentType = agentType
        if !project.isEmpty { sessions[sessionId]?.project = project }
        if !cwd.isEmpty { sessions[sessionId]?.cwd = cwd }
        if !terminal.isEmpty { sessions[sessionId]?.terminal = terminal }
        Task { await notifyChange() }
    }

    func handleEvent(_ event: AgentHookEvent) async {
        let sessionId = event.sessionId
        if !sessionId.isEmpty, sessions[sessionId] == nil {
            sessions[sessionId] = SessionState(
                id: sessionId,
                agentType: "Agent Center",
                project: "Agent Session",
                cwd: "",
                terminal: "",
                startedAt: Date()
            )
        }

        switch event {
        case .sessionStart(let id, let project, let cwd, let terminal, let agentType):
            let session = getOrCreateSession(sessionId: id, agentType: agentType, project: project, cwd: cwd, terminal: terminal)
            sessions[id] = session
            sessions[id]?.phase = .ready

        case .sessionEnd(let id):
            sessions[id]?.phase = .done
            sessions[id]?.endedAt = Date()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(doneSessionCleanupSeconds * 1_000_000_000))
                cleanupDoneSession(id)
            }

        case .toolUse(let id, let toolName, let toolInput, let toolTarget, let status):
            sessions[id]?.lastToolName = toolName
            sessions[id]?.lastToolTarget = toolTarget
            sessions[id]?.lastToolStatus = status
            if status == "running" {
                sessions[id]?.phase = .processing
            } else if sessions[id]?.phase == .processing {
                sessions[id]?.phase = .idle
            }

            let toolResult = ToolResult(
                toolUseId: UUID().uuidString,
                toolName: toolName,
                status: status,
                startedAt: Date(),
                toolInput: toolInput
            )
            sessions[id]?.activeTools.append(toolResult)
            if sessions[id]?.activeTools.count ?? 0 > 50 {
                sessions[id]?.activeTools.removeFirst()
            }

        case .permissionRequest(let id, let toolName, let diff, let options):
            sessions[id]?.pendingPermission = PendingPermission(toolName: toolName, toolInput: "", diff: diff, options: options)
            sessions[id]?.phase = .waitingApproval
            addApprovalHistory(
                id,
                kind: "permission",
                title: toolName,
                detail: diff ?? ""
            )

        case .askQuestion(let id, let question, let options, let descriptions, let header, let multiSelect, let questions):
            sessions[id]?.pendingQuestion = PendingQuestion(
                question: question, options: options, descriptions: descriptions,
                header: header, multiSelect: multiSelect, questions: questions
            )
            sessions[id]?.phase = .waitingInput
            addApprovalHistory(
                id,
                kind: "question",
                title: header ?? question,
                detail: question
            )

        case .planApproval(let id, let title, let content, let permissions):
            sessions[id]?.pendingPlan = PendingPlan(title: title, content: content, permissions: permissions)
            sessions[id]?.phase = .waitingApproval
            addApprovalHistory(
                id,
                kind: "plan",
                title: title,
                detail: content
            )

        case .tokenUsage(let id, let input, let output, let cacheRead, let cacheCreate):
            sessions[id]?.tokens.input += input
            sessions[id]?.tokens.output += output
            sessions[id]?.tokens.cacheRead += cacheRead
            sessions[id]?.tokens.cacheCreate += cacheCreate

        case .rateLimitUpdate(let id, let fiveHourUsage, let fiveHourRemaining, let sevenDayUsage, let sevenDayRemaining, let statusLineText, let totalInput, let totalOutput, let ctxSize, let ctxPct, let lastMainAt, let cacheTtl):
            sessions[id]?.rateLimits = RateLimitInfo(
                fiveHourUsage: fiveHourUsage, fiveHourRemaining: fiveHourRemaining,
                sevenDayUsage: sevenDayUsage, sevenDayRemaining: sevenDayRemaining
            )
            sessions[id]?.statusLineText = statusLineText
            if let totalInput = totalInput, let totalOutput = totalOutput, let ctxSize = ctxSize {
                sessions[id]?.contextWindow = ContextWindowInfo(
                    totalInputTokens: totalInput,
                    totalOutputTokens: totalOutput,
                    contextWindowSize: ctxSize,
                    usedPercentage: ctxPct
                )
            }
            sessions[id]?.lastMainAgentAt = lastMainAt
            sessions[id]?.cacheTtlMs = cacheTtl

        case .subagentStart(let id, let agentId, let name, let description, let agentType, let transcriptPath):
            let sub = SubagentInfo(
                agentId: agentId, name: name, agentType: agentType,
                description: description, transcriptPath: transcriptPath,
                startedAt: Date(), status: "running"
            )
            sessions[id]?.subagents.append(sub)

        case .subagentStop(let id, let agentId, let status, let name, let agentType, _, let agentTranscriptPath, let lastMsg):
            if let idx = sessions[id]?.subagents.firstIndex(where: { $0.agentId == agentId }) {
                sessions[id]?.subagents[idx].status = status
                sessions[id]?.subagents[idx].completedAt = Date()
                sessions[id]?.subagents[idx].name = name ?? sessions[id]?.subagents[idx].name
                sessions[id]?.subagents[idx].agentType = agentType ?? sessions[id]?.subagents[idx].agentType
                sessions[id]?.subagents[idx].agentTranscriptPath = agentTranscriptPath
                sessions[id]?.subagents[idx].lastAssistantMessage = lastMsg
            }

        case .shellExecutionStart(let id, let command, _):
            sessions[id]?.lastToolName = "Shell: \(command.prefix(60))"
            sessions[id]?.phase = .processing

        case .shellExecutionEnd(_, _, let exitCode, _, _, _):
            if exitCode != 0 {
                sessions[sessionId]?.lastToolStatus = "error"
            }

        case .agentError(let id, let message):
            sessions[id]?.phase = .error
            sessions[id]?.description = message

        case .taskComplete(let id, let summary):
            sessions[id]?.description = summary

        case .agentResponse(_, let content, _):
            sessions[sessionId]?.lastResponse = content

        case .agentThought(_, let thought):
            sessions[sessionId]?.lastThought = thought

        case .notification(_, let message, _):
            sessions[sessionId]?.description = message

        default: break
        }

        await notifyChange()
    }

    func getAllSessions() -> [SessionState] {
        sessions.values.sorted { $0.startedAt > $1.startedAt }
    }

    func getActiveSessions() -> [SessionState] {
        sessions.values.filter { $0.phase.isActive || $0.phase.needsAttention }
    }

    func getSession(_ id: String) -> SessionState? {
        sessions[id]
    }

    func setPendingPermission(_ sessionId: String, _ permission: PendingPermission?) {
        ensureSessionForPendingRequest(sessionId: sessionId)
        if let perm = permission {
            sessions[sessionId]?.pendingPermission = perm
            sessions[sessionId]?.phase = .waitingApproval
            addApprovalHistory(
                sessionId,
                kind: "permission",
                title: perm.toolName,
                detail: perm.diff ?? perm.toolInput
            )
        } else {
            sessions[sessionId]?.pendingPermission = nil
            resolveLatestApprovalHistory(sessionId, kind: "permission")
            if sessions[sessionId]?.phase == .waitingApproval {
                sessions[sessionId]?.phase = .idle
            }
        }
        Task { await notifyChange() }
    }

    func setPendingQuestion(_ sessionId: String, _ question: PendingQuestion?) {
        ensureSessionForPendingRequest(sessionId: sessionId)
        if let q = question {
            sessions[sessionId]?.pendingQuestion = q
            sessions[sessionId]?.phase = .waitingInput
            addApprovalHistory(
                sessionId,
                kind: "question",
                title: q.header ?? q.question,
                detail: q.question
            )
        } else {
            sessions[sessionId]?.pendingQuestion = nil
            resolveLatestApprovalHistory(sessionId, kind: "question")
            if sessions[sessionId]?.phase == .waitingInput {
                sessions[sessionId]?.phase = .idle
            }
        }
        Task { await notifyChange() }
    }

    func setPendingPlan(_ sessionId: String, _ plan: PendingPlan?) {
        ensureSessionForPendingRequest(sessionId: sessionId)
        if let p = plan {
            sessions[sessionId]?.pendingPlan = p
            sessions[sessionId]?.phase = .waitingApproval
            addApprovalHistory(
                sessionId,
                kind: "plan",
                title: p.title,
                detail: p.content
            )
        } else {
            sessions[sessionId]?.pendingPlan = nil
            resolveLatestApprovalHistory(sessionId, kind: "plan")
            if sessions[sessionId]?.phase == .waitingApproval {
                sessions[sessionId]?.phase = .idle
            }
        }
        Task { await notifyChange() }
    }

    func updatePhase(_ sessionId: String, phase: SessionPhase) {
        sessions[sessionId]?.phase = phase
        Task { await notifyChange() }
    }

    func updateSession(_ sessionId: String, updater: (inout SessionState) -> Void) {
        if var session = sessions[sessionId] {
            updater(&session)
            sessions[sessionId] = session
            Task { await notifyChange() }
        }
    }

    func observe(onChange: @escaping @MainActor ([SessionState]) -> Void) -> UUID {
        let id = UUID()
        onChangeCallbacks.append((id, onChange))
        let snapshot = getAllSessions()
        Task { @MainActor in
            onChange(snapshot)
        }
        return id
    }

    func removeObserver(_ id: UUID) {
        onChangeCallbacks.removeAll { $0.0 == id }
    }

    private func cleanupDoneSession(_ id: String) {
        sessions.removeValue(forKey: id)
        Task { await notifyChange() }
    }

    private func addApprovalHistory(_ sessionId: String, kind: String, title: String, detail: String) {
        guard var session = sessions[sessionId] else { return }
        if let latest = session.approvalHistory.last,
           latest.isPending,
           latest.kind == kind,
           latest.title == title,
           latest.detail == detail {
            return
        }

        session.approvalHistory.append(
            ApprovalHistoryRecord(
                kind: kind,
                title: title,
                detail: detail
            )
        )
        if session.approvalHistory.count > 100 {
            session.approvalHistory.removeFirst(session.approvalHistory.count - 100)
        }
        sessions[sessionId] = session
    }

    private func resolveLatestApprovalHistory(_ sessionId: String, kind: String) {
        guard var session = sessions[sessionId],
              let index = session.approvalHistory.lastIndex(where: { $0.kind == kind && $0.isPending })
        else { return }

        session.approvalHistory[index].resolvedAt = Date()
        sessions[sessionId] = session
    }

    private func notifyChange() async {
        guard notifyTask == nil else { return }
        notifyTask = Task { [weak self] in
            let delay = self?.notifyThrottleNanos ?? 250_000_000
            try? await Task.sleep(nanoseconds: delay)
            await self?.deliverChange()
        }
    }

    private func deliverChange() async {
        let snapshot = getAllSessions()
        notifyTask = nil
        for (_, callback) in onChangeCallbacks {
            await callback(snapshot)
        }
    }
}
