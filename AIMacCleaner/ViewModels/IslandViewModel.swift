import SwiftUI
import Combine

enum IslandDisplayLevel: Int, Comparable {
    case compact = 0
    case hover = 1
    case expanded = 2
    case detail = 3

    static func < (lhs: IslandDisplayLevel, rhs: IslandDisplayLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var islandWidth: CGFloat {
        switch self {
        case .compact: return 380
        case .hover: return 420
        case .expanded: return 620
        case .detail: return 620
        }
    }

    var islandHeight: CGFloat {
        switch self {
        case .compact: return 56
        case .hover: return 64
        case .expanded: return 440
        case .detail: return 440
        }
    }

    var cornerRadius: CGFloat {
        switch self {
        case .compact: return 28
        case .hover: return 32
        case .expanded: return 20
        case .detail: return 16
        }
    }
}

enum IslandPosition {
    case topCenter
    case topRight
    case center

    var origin: CGPoint {
        guard let screen = NSScreen.main else { return .zero }
        let frame = screen.visibleFrame
        switch self {
        case .topCenter:
            return CGPoint(x: frame.midX - 100, y: frame.maxY - 60)
        case .topRight:
            return CGPoint(x: frame.maxX - 220, y: frame.maxY - 60)
        case .center:
            return CGPoint(x: frame.midX - 100, y: frame.midY - 24)
        }
    }
}

enum IslandApprovalKind: String, Codable, Sendable {
    case permission
    case question
    case plan

    var priority: Int {
        switch self {
        case .permission: return 100
        case .plan: return 90
        case .question: return 80
        }
    }
}

struct IslandApprovalOverlay: Identifiable, Equatable, Sendable {
    var id: String
    var sessionId: String
    var kind: IslandApprovalKind
    var title: String
    var createdAt: Date
}

@MainActor
class IslandViewModel: ObservableObject {
    @Published var displayLevel: IslandDisplayLevel = .compact
    @Published var position: IslandPosition = .topCenter
    @Published var isVisible: Bool = false
    @Published var isPinned: Bool = false
    @Published var currentSession: SessionState?
    @Published var allSessions: [SessionState] = []
    @Published var activeSessions: [SessionState] = []
    @Published var recentEvents: [AgentHookEvent] = []
    @Published var lastStatusText: String = ""
    @Published var lastAgentIcon: String = ""
    @Published var blinking: Bool = false
    @Published var showPermissionSheet: Bool = false
    @Published var showQuestionSheet: Bool = false
    @Published var showPlanApprovalSheet: Bool = false
    @Published var sessionToDetail: SessionState?
    @Published var approvalQueue: [IslandApprovalOverlay] = []
    @Published var activeApprovalOverlay: IslandApprovalOverlay?
    @Published var showsApprovalList: Bool = false

    private let maxRecentEvents = 20
    private let maxApprovalQueue = 50
    private var eventStream: AsyncStream<AgentHookEvent>?
    private var streamTask: Task<Void, Never>?
    private var autoHideTask: Task<Void, Never>?
    private let autoHideDelay: TimeInterval = 5
    private var autoPresentedApprovalIds: Set<String> = []
    private var overviewSessions: [SessionState] = []
    private var observedSessions: [SessionState] = []
    private var staysVisibleUntilClosed = false

    weak var hookServer: HookServer?
    weak var sessionStore: SessionStore?
    private var observerId: UUID?

    func setup(hookServer: HookServer, sessionStore: SessionStore) {
        self.hookServer = hookServer
        self.sessionStore = sessionStore
    }

    func startObserving() {
        guard let hookServer = hookServer else { return }
        streamTask = Task { [weak self, hookServer] in
            let stream = await hookServer.observeEvents()
            for await event in stream {
                await self?.handleEvent(event)
            }
        }

        Task { [weak self] in
            guard let self = self, let store = self.sessionStore else { return }
            self.observerId = await store.observe { [weak self] sessions in
                self?.observedSessions = sessions
                self?.refreshCombinedSessions()
                self?.syncApprovalQueue(from: sessions)
                if self?.allSessions.isEmpty == true {
                    self?.isVisible = false
                }
            }
        }
    }

    func stopObserving() {
        streamTask?.cancel()
        streamTask = nil
        eventStream = nil
        if let id = observerId, let store = sessionStore {
            Task { await store.removeObserver(id) }
            observerId = nil
        }
    }

    private func handleEvent(_ event: AgentHookEvent) async {
        recentEvents.append(event)
        if recentEvents.count > maxRecentEvents {
            recentEvents.removeFirst()
        }

        if !isVisible, !isPinned {
            show(level: .compact)
        }

        if let store = sessionStore {
            currentSession = await store.getSession(event.sessionId)
        }

        switch event {
        case .sessionStart(_, _, _, _, let agentType):
            lastStatusText = "\(agentType) started"
            lastAgentIcon = agentIcon(for: agentType)
            playHaptic()
        case .processing(_, let desc):
            lastStatusText = desc
        case .toolUse(_, let toolName, _, let toolTarget, let status):
            let target = toolTarget.map { " → \($0)" } ?? ""
            lastStatusText = "\(status == "running" ? "" : "✓ ")\(toolName)\(target)"
            blinking = status == "running"
            if status != "running" { playHaptic() }
        case .permissionRequest(_, let toolName, _, _):
            lastStatusText = "Permission: \(toolName)"
            pushApprovalOverlay(sessionId: event.sessionId, kind: .permission, title: toolName)
        case .askQuestion(_, _, _, _, _, _, _):
            lastStatusText = "Question pending..."
            pushApprovalOverlay(sessionId: event.sessionId, kind: .question, title: "Question")
        case .planApproval(_, let title, _, _):
            lastStatusText = "Plan: \(title)"
            pushApprovalOverlay(sessionId: event.sessionId, kind: .plan, title: title)
        case .taskComplete(_, let summary):
            lastStatusText = "✓ \(summary.prefix(40))"
            playHaptic()
        case .agentError(_, let message):
            lastStatusText = "✗ \(message.prefix(40))"
            playErrorHaptic()
        case .tokenUsage(let id, let input, let output, _, _):
            if let session = await sessionStore?.getSession(id) {
                lastStatusText = "Tokens: \(input.formatted())↑ \(output.formatted())↓"
                currentSession = session
            }
        case .rateLimitUpdate(_, let fiveHourUsage, _, _, _, _, _, _, _, _, _, _):
            lastStatusText = "API: \(Int(fiveHourUsage))% used"
        case .subagentStart(_, _, let name, _, _, _):
            if let n = name { lastStatusText = "Sub: \(n)" }
        case .subagentStop(_, _, let status, let name, _, _, _, _):
            let n = name ?? "subagent"
            lastStatusText = "Sub: \(n) \(status)"
        case .shellExecutionStart(_, let command, _):
            lastStatusText = "$ \(command.prefix(40))"
        case .sessionEnd:
            lastStatusText = "Session ended"
            scheduleAutoHide()
        default:
            break
        }
    }

    func show(level: IslandDisplayLevel) {
        if level != .expanded {
            showsApprovalList = false
        }
        isVisible = true
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            displayLevel = level
        }
        DisplayController.shared.updateIslandFrame(level: level)
        DisplayController.shared.showIsland()
        cancelAutoHide()
    }

    func dismiss() {
        guard !isPinned else { return }
        withAnimation(.easeOut(duration: 0.25)) {
            displayLevel = .compact
        }
        if !staysVisibleUntilClosed {
            scheduleAutoHide()
        }
    }

    func togglePin() {
        isPinned.toggle()
        if isPinned {
            cancelAutoHide()
        } else {
            scheduleAutoHide()
        }
    }

    func syncOverviewSessions(_ sessions: [SessionState], selectedID: String?) {
        overviewSessions = sessions
        staysVisibleUntilClosed = true
        refreshCombinedSessions(selectedID: selectedID)
    }

    private func refreshCombinedSessions(selectedID: String? = nil) {
        var seen = Set<String>()
        allSessions = (overviewSessions + observedSessions).filter { seen.insert($0.id).inserted }
        activeSessions = allSessions.filter {
            $0.phase.isActive ||
            $0.phase.needsAttention ||
            $0.pendingPermission != nil ||
            $0.pendingQuestion != nil ||
            $0.pendingPlan != nil
        }
        if let selectedID, let selected = allSessions.first(where: { $0.id == selectedID }) {
            currentSession = selected
        } else if !allSessions.contains(where: { $0.id == currentSession?.id }) {
            currentSession = activeSessions.first ?? allSessions.first
        }
        sessionToDetail = currentSession
        if let currentSession {
            lastStatusText = currentSession.description ?? currentSession.sessionTitle ?? currentSession.project
            lastAgentIcon = agentIcon(for: currentSession.agentType)
            blinking = currentSession.phase == .processing
        }
    }

    func selectAdjacentSession(_ offset: Int) {
        guard !activeSessions.isEmpty else { return }
        let currentIndex = currentSession.flatMap { current in
            activeSessions.firstIndex(where: { $0.id == current.id })
        } ?? 0
        let nextIndex = (currentIndex + offset + activeSessions.count) % activeSessions.count
        currentSession = activeSessions[nextIndex]
        sessionToDetail = currentSession
        if let currentSession {
            lastStatusText = currentSession.description ?? currentSession.sessionTitle ?? currentSession.project
            lastAgentIcon = agentIcon(for: currentSession.agentType)
            blinking = currentSession.phase == .processing
        }
    }

    func closeIsland() {
        isPinned = false
        staysVisibleUntilClosed = false
        displayLevel = .compact
        isVisible = false
        cancelAutoHide()
    }

    func showDetail(for session: SessionState) {
        sessionToDetail = session
        show(level: .detail)
    }

    func dismissSheets() {
        showPermissionSheet = false
        showQuestionSheet = false
        showPlanApprovalSheet = false
        showsApprovalList = false
        dismiss()
    }

    var activeApprovalSession: SessionState? {
        guard let overlay = activeApprovalOverlay else { return nil }
        return allSessions.first { $0.id == overlay.sessionId } ??
            activeSessions.first { $0.id == overlay.sessionId } ??
            currentSession
    }

    var approvalQueueCount: Int {
        approvalQueue.count + (activeApprovalOverlay == nil ? 0 : 1)
    }

    var nextApprovalTitle: String? {
        approvalQueue.first?.title
    }

    var visibleApprovalOverlays: [IslandApprovalOverlay] {
        if let activeApprovalOverlay {
            return [activeApprovalOverlay] + approvalQueue
        }
        return approvalQueue
    }

    private func pushApprovalOverlay(sessionId: String, kind: IslandApprovalKind, title: String) {
        let overlay = IslandApprovalOverlay(
            id: "\(kind.rawValue)-\(sessionId)",
            sessionId: sessionId,
            kind: kind,
            title: title,
            createdAt: Date()
        )

        if activeApprovalOverlay?.id == overlay.id || approvalQueue.contains(where: { $0.id == overlay.id }) {
            show(level: .expanded)
            return
        }

        if activeApprovalOverlay == nil {
            activeApprovalOverlay = overlay
        } else {
            approvalQueue.append(overlay)
            approvalQueue = sortedApprovalQueue(approvalQueue)
            if approvalQueue.count > maxApprovalQueue {
                approvalQueue.removeLast(approvalQueue.count - maxApprovalQueue)
            }
        }

        updateLegacySheetFlags(for: activeApprovalOverlay)
        show(level: .expanded)
    }

    private func syncApprovalQueue(from sessions: [SessionState]) {
        let pending = sessions.flatMap { session -> [IslandApprovalOverlay] in
            var overlays: [IslandApprovalOverlay] = []
            if let permission = session.pendingPermission {
                overlays.append(IslandApprovalOverlay(id: "permission-\(session.id)", sessionId: session.id, kind: .permission, title: permission.toolName, createdAt: session.startedAt))
            }
            if let plan = session.pendingPlan {
                overlays.append(IslandApprovalOverlay(id: "plan-\(session.id)", sessionId: session.id, kind: .plan, title: plan.title, createdAt: session.startedAt))
            }
            if session.pendingQuestion != nil {
                overlays.append(IslandApprovalOverlay(id: "question-\(session.id)", sessionId: session.id, kind: .question, title: "Question", createdAt: session.startedAt))
            }
            return overlays
        }
        let pendingIds = Set(pending.map(\.id))
        let newPending = pending.filter { !autoPresentedApprovalIds.contains($0.id) }

        if let active = activeApprovalOverlay, !pendingIds.contains(active.id) {
            activeApprovalOverlay = nil
        }
        approvalQueue.removeAll { !pendingIds.contains($0.id) }
        autoPresentedApprovalIds.formIntersection(pendingIds)

        for overlay in pending where activeApprovalOverlay?.id != overlay.id && !approvalQueue.contains(where: { $0.id == overlay.id }) {
            approvalQueue.append(overlay)
        }

        approvalQueue = sortedApprovalQueue(approvalQueue)
        if activeApprovalOverlay == nil {
            activeApprovalOverlay = approvalQueue.first
            if activeApprovalOverlay != nil {
                approvalQueue.removeFirst()
            }
        }
        updateLegacySheetFlags(for: activeApprovalOverlay)

        if !newPending.isEmpty, activeApprovalOverlay != nil {
            autoPresentedApprovalIds.formUnion(newPending.map(\.id))
            show(level: .expanded)
        }
    }

    private func sortedApprovalQueue(_ overlays: [IslandApprovalOverlay]) -> [IslandApprovalOverlay] {
        overlays.sorted {
            if $0.kind.priority == $1.kind.priority {
                return $0.createdAt < $1.createdAt
            }
            return $0.kind.priority > $1.kind.priority
        }
    }

    private func updateLegacySheetFlags(for overlay: IslandApprovalOverlay?) {
        showPermissionSheet = overlay?.kind == .permission
        showQuestionSheet = overlay?.kind == .question
        showPlanApprovalSheet = overlay?.kind == .plan
    }

    private func advanceApprovalQueue() {
        showsApprovalList = false
        if approvalQueue.isEmpty {
            activeApprovalOverlay = nil
        } else {
            activeApprovalOverlay = approvalQueue.removeFirst()
        }
        updateLegacySheetFlags(for: activeApprovalOverlay)
    }

    func showApprovalSessionList() {
        showsApprovalList.toggle()
        show(level: .expanded)
    }

    func selectApprovalOverlay(_ overlay: IslandApprovalOverlay) {
        guard activeApprovalOverlay?.id != overlay.id else {
            showsApprovalList = false
            updateLegacySheetFlags(for: activeApprovalOverlay)
            return
        }

        var overlays = visibleApprovalOverlays
        overlays.removeAll { $0.id == overlay.id }
        activeApprovalOverlay = overlay
        approvalQueue = sortedApprovalQueue(overlays)
        showsApprovalList = false
        updateLegacySheetFlags(for: activeApprovalOverlay)
        if let session = allSessions.first(where: { $0.id == overlay.sessionId }) {
            currentSession = session
        }
    }

    func respondToPermission(_ decision: PermissionDecision) {
        guard let session = activeApprovalSession ?? currentSession,
              let perm = session.pendingPermission else { return }

        if perm.requiresExternalHandling {
            handleExternalPermissionDecision(decision, session: session, permission: perm)
            return
        }

        Task { [weak self] in
            await self?.hookServer?.respondToPermission(
                sessionId: session.id,
                toolName: perm.toolName,
                decision: decision
            )
            await MainActor.run {
                self?.activeApprovalOverlay = nil
                self?.showPermissionSheet = false
                self?.advanceApprovalQueue()
                if self?.activeApprovalOverlay == nil {
                    self?.dismiss()
                } else {
                    self?.show(level: .expanded)
                }
            }
            await self?.sessionStore?.setPendingPermission(session.id, nil)
        }
    }

    private func handleExternalPermissionDecision(
        _ decision: PermissionDecision,
        session: SessionState,
        permission: PendingPermission
    ) {
        if decision.decision == PermissionDecision.openExternal.decision {
            openExternalApprovalSource(permission)
            show(level: .expanded)
            return
        }

        guard decision.decision == PermissionDecision.externalHandled.decision else { return }

        Task { [weak self] in
            await MainActor.run {
                self?.activeApprovalOverlay = nil
                self?.showPermissionSheet = false
                self?.advanceApprovalQueue()
                if self?.activeApprovalOverlay == nil {
                    self?.dismiss()
                } else {
                    self?.show(level: .expanded)
                }
            }
            await self?.sessionStore?.setPendingPermission(session.id, nil)
        }
    }

    private func openExternalApprovalSource(_ permission: PendingPermission) {
        if let bundleId = permission.externalActionBundleId,
           NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == bundleId }) {
            NSWorkspace.shared.runningApplications
                .first(where: { $0.bundleIdentifier == bundleId })?
                .activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            return
        }

        if let bundleId = permission.externalActionBundleId,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }

    func respondToQuestion(_ answer: String) {
        guard let session = activeApprovalSession ?? currentSession else { return }
        Task { [weak self] in
            await self?.hookServer?.respondToQuestion(
                sessionId: session.id,
                answer: answer
            )
            await MainActor.run {
                self?.activeApprovalOverlay = nil
                self?.showQuestionSheet = false
                self?.advanceApprovalQueue()
                if self?.activeApprovalOverlay == nil {
                    self?.dismiss()
                } else {
                    self?.show(level: .expanded)
                }
            }
            await self?.sessionStore?.setPendingQuestion(session.id, nil)
        }
    }

    func respondToPlan(mode: String, message: String?) {
        guard let session = activeApprovalSession ?? currentSession else { return }
        Task { [weak self] in
            await self?.hookServer?.respondToPlan(
                sessionId: session.id,
                mode: mode,
                message: message
            )
            await MainActor.run {
                self?.activeApprovalOverlay = nil
                self?.showPlanApprovalSheet = false
                self?.advanceApprovalQueue()
                if self?.activeApprovalOverlay == nil {
                    self?.dismiss()
                } else {
                    self?.show(level: .expanded)
                }
            }
            await self?.sessionStore?.setPendingPlan(session.id, nil)
        }
    }

    func moveToPosition(_ pos: IslandPosition) {
        position = pos
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: UInt64(self.autoHideDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.isVisible = false
                }
            }
        }
    }

    private func cancelAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    private func playHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
    }

    private func playErrorHaptic() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    private func agentIcon(for agentType: String) -> String {
        switch agentType.lowercased() {
        case "claude", "claude-code", "claude_code": return "c.circle.fill"
        case "codex": return "o.circle.fill"
        case "gemini": return "g.circle.fill"
        case "cursor": return "cursorarrow.rays"
        case "copilot": return "laptopcomputer"
        case "trae", "trae-cn": return "t.circle.fill"
        case "qoder", "qwen": return "q.circle.fill"
        case "codebuddy": return "b.circle.fill"
        case "kimi": return "k.circle.fill"
        case "deepseek": return "d.circle.fill"
        default: return "terminal.fill"
        }
    }
}

extension UInt64 {
    func formatted() -> String {
        if self >= 1_000_000 { return String(format: "%.1fM", Double(self) / 1_000_000) }
        if self >= 1_000 { return String(format: "%.1fK", Double(self) / 1_000) }
        return "\(self)"
    }
}
