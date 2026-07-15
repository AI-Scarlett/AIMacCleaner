import SwiftUI

fileprivate enum AgentCenterApprovalScope {
    case pending
    case history
}

private enum AgentCenterColumns {
    static let agentName: CGFloat = 220
    static let hookStatus: CGFloat = 220
    static let action: CGFloat = 128
    static let approvalType: CGFloat = 160
    static let approvalAgent: CGFloat = 120
    static let approvalTime: CGFloat = 90
    static let chevron: CGFloat = 14
}

private enum AgentProjectLane: String, CaseIterable {
    case live
    case scheduled
    case blocked
    case completed

    func title(_ localizer: Localizer) -> String {
        switch self {
        case .live:
            return localizer.t("实时项目", en: "Live Projects", zhHant: "即時專案", ja: "ライブプロジェクト", ko: "실시간 프로젝트", mt: "Live Projects")
        case .scheduled:
            return localizer.t("定时项目", en: "Scheduled Projects", zhHant: "排程專案", ja: "スケジュール済み", ko: "예약 프로젝트", mt: "Scheduled Projects")
        case .blocked:
            return localizer.t("阻塞关注", en: "Blocked", zhHant: "阻塞關注", ja: "ブロック中", ko: "차단됨", mt: "Blocked")
        case .completed:
            return localizer.t("最近完成", en: "Recently Done", zhHant: "最近完成", ja: "最近完了", ko: "최근 완료", mt: "Recently Done")
        }
    }

    func subtitle(_ count: Int, _ localizer: Localizer) -> String {
        switch self {
        case .live:
            return localizer.t("\(count) 个正在推进", en: "\(count) in progress", zhHant: "\(count) 個正在推進", ja: "\(count) 件進行中", ko: "\(count)개 진행 중", mt: "\(count) in progress")
        case .scheduled:
            return localizer.t("\(count) 个等待触发", en: "\(count) queued or scheduled", zhHant: "\(count) 個等待觸發", ja: "\(count) 件待機中", ko: "\(count)개 대기 중", mt: "\(count) queued or scheduled")
        case .blocked:
            return localizer.t("\(count) 个需要处理", en: "\(count) need attention", zhHant: "\(count) 個需要處理", ja: "\(count) 件要対応", ko: "\(count)개 처리 필요", mt: "\(count) need attention")
        case .completed:
            return localizer.t("\(count) 个可回看", en: "\(count) for review", zhHant: "\(count) 個可回看", ja: "\(count) 件確認可能", ko: "\(count)개 검토 가능", mt: "\(count) for review")
        }
    }

    var icon: String {
        switch self {
        case .live: return "dot.radiowaves.left.and.right"
        case .scheduled: return "calendar.badge.clock"
        case .blocked: return "exclamationmark.triangle.fill"
        case .completed: return "checkmark.seal.fill"
        }
    }

    var color: Color {
        switch self {
        case .live: return Theme.Colors.success
        case .scheduled: return Theme.Colors.info
        case .blocked: return Theme.Colors.warning
        case .completed: return Theme.Colors.purple
        }
    }
}

private struct AgentProjectSnapshot: Identifiable {
    let id: String
    let title: String
    let path: String
    let lane: AgentProjectLane
    let agents: [String]
    let sessions: [SessionState]
    let operations: [OperationRecord]
    let startedAt: Date
    let lastActivityAt: Date
    let progress: Double
    let completedTaskCount: Int
    let totalTaskCount: Int
    let pendingApprovalCount: Int
    let activeToolNames: [String]
    let subagentCount: Int
    let summary: String
    let blocker: String?
    let scheduleHint: String?

    var sessionCount: Int { sessions.count }
    var operationCount: Int { operations.count }
}

private struct AgentAutomationConfig {
    let id: String
    let name: String
    let status: String
    let model: String
    let kind: String
    let schedule: String
    let description: String
    let cwds: [String]
    let directoryPath: String
    let updatedAt: Date
}

struct AgentCenterView: View {
    @EnvironmentObject var agentRegistry: AgentRegistry
    @EnvironmentObject var sessionsViewModel: SessionsViewModel
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @State private var selectedAgentId: String?
    @State private var selectedProjectId: String?
    @State private var projectSearchText: String = ""
    @State private var searchText: String = ""
    @State private var filterStatus: AdapterStatus?
    @State private var selectedSection: AgentCenterSection = .projects
    @State private var selectedApprovalScope: AgentCenterApprovalScope = .pending
    @State private var automationProjectSnapshots: [AgentProjectSnapshot] = []

    enum AgentCenterSection: String, CaseIterable {
        case projects
        case approvals
        case audit
        case integrations
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().opacity(0.6)
            if selectedSection == .projects {
                projectBoardContent
            } else if selectedSection == .approvals {
                approvalsContent
            } else if selectedSection == .audit {
                auditContent
            } else {
                agentListContent
            }
        }
        .background(Theme.Colors.background)
        .onAppear {
            refreshAgentCenterData()
        }
    }

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            PageHeader(
                icon: "house.fill",
                title: localizer.navAgentCenter,
                subtitle: localizer.t("按项目聚合实时会话、定时任务、阻塞审批与本机审计活动", en: "Project board for live sessions, scheduled work, blockers, and local audit activity", zhHant: "按專案彙整即時會話、排程任務、阻塞審批與本機審計活動", ja: "ライブセッション、予定タスク、ブロッカー、ローカル監査をプロジェクト別に表示", ko: "실시간 세션, 예약 작업, 차단 항목, 로컬 감사 활동을 프로젝트별로 표시", mt: "Project board for live sessions, scheduled work, blockers, and local audit activity"),
                color: Theme.Colors.warning
            ) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button(action: {
                        refreshAgentCenterData()
                    }) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text(localizer.agentCenterRefresh)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Theme.Colors.info)

                    Button(action: { agentRegistry.installAllAvailableHooks() }) {
                        HStack(spacing: Theme.Spacing.xs) {
                            if !agentRegistry.installingAgentIds.isEmpty {
                                ProgressView()
                                    .controlSize(.small)
                                    .scaleEffect(0.65)
                            } else {
                                Image(systemName: "point.3.connected.trianglepath.dotted")
                            }
                            Text(localizer.agentCenterConnect)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Theme.Colors.success)
                    .disabled(connectableAdapterCount == 0 || !agentRegistry.installingAgentIds.isEmpty)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 136), spacing: Theme.Spacing.sm)],
                alignment: .leading,
                spacing: Theme.Spacing.sm
            ) {
                StatCardView(
                    icon: "dot.radiowaves.left.and.right",
                    iconColor: Theme.Colors.success,
                    title: localizer.t("实时项目", en: "Live Projects", zhHant: "即時專案", ja: "ライブプロジェクト", ko: "실시간 프로젝트", mt: "Live Projects"),
                    value: "\(liveProjects.count)",
                    subtitle: localizer.t("正在推进", en: "in progress", zhHant: "正在推進", ja: "進行中", ko: "진행 중", mt: "in progress")
                )
                StatCardView(
                    icon: "calendar.badge.clock",
                    iconColor: Theme.Colors.info,
                    title: localizer.t("定时项目", en: "Scheduled", zhHant: "排程專案", ja: "予定タスク", ko: "예약 작업", mt: "Scheduled"),
                    value: "\(scheduledProjects.count)",
                    subtitle: localizer.t("等待触发", en: "queued", zhHant: "等待觸發", ja: "待機中", ko: "대기 중", mt: "queued")
                )
                StatCardView(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: blockedProjects.isEmpty ? Theme.Colors.success : Theme.Colors.warning,
                    title: localizer.t("阻塞事项", en: "Blockers", zhHant: "阻塞事項", ja: "ブロッカー", ko: "차단 항목", mt: "Blockers"),
                    value: "\(blockedProjects.count)",
                    subtitle: pendingApprovalSessions.isEmpty ? localizer.t("暂无待处理", en: "clear", zhHant: "暫無待處理", ja: "対応不要", ko: "처리할 항목 없음", mt: "clear") : "\(pendingApprovalSessions.count) \(localizer.agentCenterPending)"
                )
                StatCardView(
                    icon: "clock.arrow.circlepath",
                    iconColor: Theme.Colors.teal,
                    title: localizer.t("今日活动", en: "Today", zhHant: "今日活動", ja: "今日の活動", ko: "오늘 활동", mt: "Today"),
                    value: "\(todayOperationCount)",
                    subtitle: localizer.agentOpAudit
                )
                StatCardView(
                    icon: "puzzlepiece.extension.fill",
                    iconColor: Theme.Colors.purple,
                    title: localizer.agentCenterIntegrations,
                    value: "\(agentRegistry.activeCount)/\(agentRegistry.allAdapters.count)",
                    subtitle: localizer.agentCenterActiveSummary
                )
            }
            .padding(.horizontal, Theme.Spacing.xl)

            statusStrip

            HStack(spacing: Theme.Spacing.lg) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        AgentCenterSegmentButton(
                            title: localizer.t("项目", en: "Projects", zhHant: "專案", ja: "プロジェクト", ko: "프로젝트", mt: "Projects"),
                            icon: "rectangle.3.group.fill",
                            section: .projects,
                            selectedSection: $selectedSection
                        )
                        AgentCenterSegmentButton(
                            title: localizer.agentCenterApprovals,
                            icon: "hand.raised.fill",
                            section: .approvals,
                            selectedSection: $selectedSection
                        )
                        AgentCenterSegmentButton(
                            title: localizer.audit,
                            icon: "doc.text.magnifyingglass",
                            section: .audit,
                            selectedSection: $selectedSection
                        )
                        AgentCenterSegmentButton(
                            title: localizer.agentCenterIntegrations,
                            icon: "point.3.connected.trianglepath.dotted",
                            section: .integrations,
                            selectedSection: $selectedSection
                        )
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(Theme.Colors.cardBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.md)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                            )
                    )
                }

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.xl)

            if selectedSection == .projects {
                HStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        TextField(localizer.t("搜索项目、Agent、路径或当前工具", en: "Search projects, agents, paths, or tools", zhHant: "搜尋專案、Agent、路徑或目前工具", ja: "プロジェクト、Agent、パス、ツールを検索", ko: "프로젝트, Agent, 경로 또는 도구 검색", mt: "Search projects, agents, paths, or tools"), text: $projectSearchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )

                    Spacer()

                    Text(localizer.t("按项目归并会话、工具调用、审批和文件审计", en: "Sessions, tool calls, approvals, and file audit are grouped by project.", zhHant: "按專案合併會話、工具呼叫、審批和檔案審計", ja: "セッション、ツール呼び出し、承認、ファイル監査をプロジェクト別に集約します。", ko: "세션, 도구 호출, 승인, 파일 감사를 프로젝트별로 묶습니다.", mt: "Sessions, tool calls, approvals, and file audit are grouped by project."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.horizontal, Theme.Spacing.xl)
            } else if selectedSection == .integrations {
                HStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        TextField(localizer.agentCenterSearch, text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )

                    HStack(spacing: 0) {
                        AgentCenterStatusFilterButton(
                            title: localizer.agentCenterAll,
                            status: nil,
                            selectedStatus: $filterStatus
                        )
                        ForEach(AdapterStatus.allCases, id: \.self) { status in
                            AgentCenterStatusFilterButton(
                                title: statusLabel(status),
                                status: status,
                                selectedStatus: $filterStatus
                            )
                        }
                    }
                    .padding(3)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(Theme.Colors.cardBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.md)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                            )
                    )
                }
                .padding(.horizontal, Theme.Spacing.xl)
            }
        }
        .padding(.bottom, Theme.Spacing.md)
    }

    private var statusStrip: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Circle()
                .fill(agentRegistry.installingAgentIds.isEmpty ? Theme.Colors.success : Theme.Colors.warning)
                .frame(width: 6, height: 6)
            Text(agentRegistry.installingAgentIds.isEmpty ? localizer.agentCenterActiveSummary : localizer.agentCenterConnecting)
                .font(Theme.Font.caption)
                .foregroundStyle(agentRegistry.installingAgentIds.isEmpty ? Theme.Colors.success : Theme.Colors.warning)
            Text("·")
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("\(connectableAdapterCount) \(localizer.agentCenterInstalledSummary)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Spacer()
            if let message = agentRegistry.lastActionMessage {
                Text(message)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xs + 1)
        .background(Theme.Colors.success.opacity(0.05))
    }

    private var projectBoardContent: some View {
        Group {
            if filteredProjectSnapshots.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Theme.Colors.info.opacity(0.78))
                    Text(localizer.t("暂无可展示项目", en: "No projects to show", zhHant: "暫無可展示專案", ja: "表示できるプロジェクトはありません", ko: "표시할 프로젝트가 없습니다", mt: "No projects to show"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t("接入 Agent Hook 或授权 Agent 数据目录后，这里会按项目展示实时进度、定时任务和阻塞事项。", en: "Connect agent hooks or authorize agent data folders to see live progress, scheduled work, and blockers by project.", zhHant: "接入 Agent Hook 或授權 Agent 資料目錄後，這裡會按專案展示即時進度、排程任務和阻塞事項。", ja: "Agent Hookを接続するかデータフォルダを許可すると、プロジェクト別の進捗、予定タスク、ブロッカーが表示されます。", ko: "Agent Hook을 연결하거나 데이터 폴더를 승인하면 프로젝트별 실시간 진행률, 예약 작업, 차단 항목이 표시됩니다.", mt: "Connect agent hooks or authorize agent data folders to see live progress, scheduled work, and blockers by project."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            ForEach(AgentProjectLane.allCases, id: \.self) { lane in
                                let laneProjects = filteredProjectSnapshots.filter { $0.lane == lane }
                                AgentProjectLaneView(
                                    lane: lane,
                                    projects: laneProjects,
                                    selectedProjectId: selectedProjectSnapshot?.id,
                                    localizer: localizer
                                ) { project in
                                    selectedProjectId = project.id
                                }
                            }
                        }

                        AgentProjectDetailPanel(
                            project: selectedProjectSnapshot,
                            localizer: localizer,
                            phaseLabel: phaseLabel,
                            relativeTime: relativeTimeText,
                            copyPath: copyToPasteboard
                        )
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
        }
    }

    private var agentListContent: some View {
        VStack(spacing: 0) {
            agentListHeader
            ScrollView {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(filteredAdapters, id: \.agentId) { profile in
                        AgentRowView(
                            profile: profile,
                            status: agentRegistry.status(for: profile.agentId),
                            isSelected: selectedAgentId == profile.agentId,
                            isWorking: agentRegistry.installingAgentIds.contains(profile.agentId),
                            supportsHooks: agentRegistry.canInstallHooks(for: profile.agentId),
                            localizer: localizer,
                            onSelect: { selectedAgentId = profile.agentId },
                            onInstall: { agentRegistry.installHooks(for: profile.agentId) },
                            onUninstall: { agentRegistry.uninstallHooks(for: profile.agentId) }
                        )
                    }
                }
                .padding(Theme.Spacing.lg)
            }
        }
    }

    private var agentListHeader: some View {
        HStack(spacing: 12) {
            Text(localizer.nameCol)
                .frame(width: AgentCenterColumns.agentName, alignment: .center)
            Text(localizer.pathCol)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(localizer.agentCenterHookStatus)
                .frame(width: AgentCenterColumns.hookStatus, alignment: .center)
            Text(localizer.actionCol)
                .frame(width: AgentCenterColumns.action, alignment: .center)
        }
        .font(Theme.Font.captionMedium)
        .foregroundStyle(Theme.Colors.textTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.sidebarBg.opacity(0.35))
    }

    private var connectableAdapterCount: Int {
        agentRegistry.allAdapters.filter {
            let status = agentRegistry.status(for: $0.name)
            return agentRegistry.canInstallHooks(for: $0.name) && (status == .installed || status == .available)
        }.count
    }

    private var filteredAdapters: [AgentIntegrationProfile] {
        var result = AgentIntegrationProfile.allProfiles

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.agentId.lowercased().contains(query) ||
                $0.displayName.lowercased().contains(query) ||
                $0.executable.lowercased().contains(query)
            }
        }

        if let status = filterStatus {
            result = result.filter { agentRegistry.status(for: $0.agentId) == status }
        }

        return result
    }

    private var filteredProjectSnapshots: [AgentProjectSnapshot] {
        let snapshots = projectSnapshots
        let query = projectSearchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return snapshots }

        return snapshots.filter { snapshot in
            snapshot.title.lowercased().contains(query) ||
            snapshot.path.lowercased().contains(query) ||
            snapshot.agents.contains { $0.lowercased().contains(query) } ||
            snapshot.activeToolNames.contains { $0.lowercased().contains(query) } ||
            snapshot.summary.lowercased().contains(query) ||
            (snapshot.blocker?.lowercased().contains(query) ?? false)
        }
    }

    private var selectedProjectSnapshot: AgentProjectSnapshot? {
        let snapshots = filteredProjectSnapshots
        if let selectedProjectId,
           let match = snapshots.first(where: { $0.id == selectedProjectId }) {
            return match
        }
        return snapshots.first
    }

    private var liveProjects: [AgentProjectSnapshot] {
        projectSnapshots.filter { $0.lane == .live }
    }

    private var scheduledProjects: [AgentProjectSnapshot] {
        projectSnapshots.filter { $0.lane == .scheduled }
    }

    private var blockedProjects: [AgentProjectSnapshot] {
        projectSnapshots.filter { $0.lane == .blocked }
    }

    private var todayOperationCount: Int {
        auditRecords.filter { Calendar.current.isDateInToday($0.timestamp) }.count
    }

    private var projectSnapshots: [AgentProjectSnapshot] {
        let groupedSessions = Dictionary(grouping: sessionsViewModel.sessions) { session in
            projectKey(for: session)
        }

        var snapshots: [AgentProjectSnapshot] = groupedSessions.compactMap { key, sessions in
            makeSessionBackedProjectSnapshot(key: key, sessions: sessions)
        }

        let knownSessionRoots = Set(snapshots.map(\.id))
        snapshots.append(contentsOf: operationBackedProjectSnapshots(excluding: knownSessionRoots))
        snapshots.append(contentsOf: automationProjectSnapshots)

        return snapshots.sorted { lhs, rhs in
            if lanePriority(lhs.lane) != lanePriority(rhs.lane) {
                return lanePriority(lhs.lane) < lanePriority(rhs.lane)
            }
            return lhs.lastActivityAt > rhs.lastActivityAt
        }
    }

    private var pendingApprovalSessions: [SessionState] {
        sessionsViewModel.sessions.filter {
            $0.pendingPermission != nil || $0.pendingQuestion != nil || $0.pendingPlan != nil || $0.phase.needsAttention
        }
    }

    private var auditRecords: [OperationRecord] {
        service.operationRecords
            .filter { !$0.agentName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.timestamp > $1.timestamp }
    }

    private func refreshAgentCenterData() {
        NotificationCenter.default.post(name: .agentCenterShouldInitialize, object: nil)
        agentRegistry.refreshAllStatuses()
        service.ensureAgentGuardDataPipeline()
        service.refreshOperationRecordsSnapshot()
        automationProjectSnapshots = readAutomationProjectSnapshots()
    }

    private var historyApprovalSessions: [SessionState] {
        sessionsViewModel.sessions
            .filter { session in
                !pendingApprovalSessions.contains(where: { $0.id == session.id }) &&
                !session.approvalHistory.isEmpty
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var approvalsContent: some View {
        VStack(spacing: 0) {
            approvalScopeBar

            if selectedApprovalScope == .pending {
                approvalSessionList(
                    sessions: pendingApprovalSessions,
                    emptyIcon: "checkmark.seal",
                    emptyTitle: localizer.agentCenterNoApprovals,
                    emptyHint: localizer.agentCenterPendingApprovalsHint,
                    isHistory: false
                )
            } else {
                approvalSessionList(
                    sessions: historyApprovalSessions,
                    emptyIcon: "clock.badge.questionmark",
                    emptyTitle: localizer.agentCenterNoApprovalHistory,
                    emptyHint: localizer.agentCenterApprovalHistoryHint,
                    isHistory: true
                )
            }
        }
    }

    private var approvalScopeBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(localizer.agentCenterApprovalHistoryHint)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)

            Spacer()

            HStack(spacing: 0) {
                AgentCenterApprovalScopeButton(
                    title: "\(localizer.agentCenterPending) \(pendingApprovalSessions.count)",
                    icon: "hand.raised.fill",
                    scope: .pending,
                    selectedScope: $selectedApprovalScope
                )
                AgentCenterApprovalScopeButton(
                    title: "\(localizer.agentCenterHistory) \(historyApprovalSessions.count)",
                    icon: "clock.arrow.circlepath",
                    scope: .history,
                    selectedScope: $selectedApprovalScope
                    )
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Colors.cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
            )
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.sidebarBg.opacity(0.3))
    }

    private func approvalSessionList(
        sessions: [SessionState],
        emptyIcon: String,
        emptyTitle: String,
        emptyHint: String,
        isHistory: Bool
    ) -> some View {
        Group {
            if sessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: emptyIcon)
                        .font(.system(size: 34))
                        .foregroundStyle((isHistory ? Theme.Colors.info : Theme.Colors.success).opacity(0.75))
                    Text(emptyTitle)
                        .font(.system(size: 14, weight: .semibold))
                    Text(emptyHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    approvalListHeader
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(sessions) { session in
                                ApprovalSessionRow(session: session, localizer: localizer, isHistory: isHistory) {
                                    selectedApprovalScope = isHistory ? .history : .pending
                                }
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
    }

    private var auditContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Text(localizer.agentOpAudit)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                Spacer()
                Text("\(auditRecords.count) \(localizer.recordsCount)")
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.purple)
                Button {
                    service.importKnownAgentHistory(force: true)
                    service.refreshOperationRecordsSnapshot()
                } label: {
                    Label(localizer.agentCenterRefresh, systemImage: "arrow.triangle.2.circlepath")
                        .font(Theme.Font.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(Theme.Colors.purple)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.xs)
            .background(Theme.Colors.sidebarBg.opacity(0.3))

            if auditRecords.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.Colors.purple.opacity(0.75))
                    Text(localizer.noOpRecordsLabel)
                        .font(.system(size: 14, weight: .semibold))
                    Text(localizer.agentCenterPendingApprovalsHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    auditListHeader
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(auditRecords.prefix(500))) { record in
                                AgentCenterAuditRow(record: record, localizer: localizer)
                            }
                        }
                        .padding(14)
                    }
                }
            }
        }
    }

    private var auditListHeader: some View {
        HStack(spacing: 12) {
            Text(localizer.timeCol)
                .frame(width: 90, alignment: .center)
            Text(localizer.agentCol)
                .frame(width: 120, alignment: .center)
            Text(localizer.opTypeLabel)
                .frame(width: 90, alignment: .center)
            Text(localizer.targetPathCol)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(localizer.detailCol)
                .frame(width: 180, alignment: .center)
        }
        .font(Theme.Font.captionMedium)
        .foregroundStyle(Theme.Colors.textTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.sidebarBg.opacity(0.35))
    }

    private var approvalListHeader: some View {
        HStack(spacing: 12) {
            Text(localizer.opTypeLabel)
                .frame(width: AgentCenterColumns.approvalType, alignment: .center)
            Text(localizer.agentCol)
                .frame(width: AgentCenterColumns.approvalAgent, alignment: .center)
            Text(localizer.detailCol)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(localizer.timeCol)
                .frame(width: AgentCenterColumns.approvalTime, alignment: .center)
            Color.clear
                .frame(width: AgentCenterColumns.chevron)
        }
        .font(Theme.Font.captionMedium)
        .foregroundStyle(Theme.Colors.textTertiary)
        .padding(.horizontal, 16)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.sidebarBg.opacity(0.35))
    }

    private func makeSessionBackedProjectSnapshot(key: String, sessions: [SessionState]) -> AgentProjectSnapshot? {
        guard !sessions.isEmpty else { return nil }

        let sortedSessions = sessions.sorted { lastActivityDate(for: $0) > lastActivityDate(for: $1) }
        let latest = sortedSessions[0]
        let projectOperations = operationsForProject(key: key, sessions: sortedSessions)
        let tasks = sortedSessions.flatMap(\.tasks)
        let completedTaskCount = tasks.filter { taskIsDone($0) }.count
        let totalTaskCount = tasks.count
        let pendingSessions = sortedSessions.filter { hasPendingAttention($0) }
        let activeSessions = sortedSessions.filter { $0.phase.isActive && !hasPendingAttention($0) }
        let scheduled = sortedSessions.contains { isScheduledSession($0) }
        let lane: AgentProjectLane

        if !pendingSessions.isEmpty {
            lane = .blocked
        } else if !activeSessions.isEmpty {
            lane = .live
        } else if scheduled {
            lane = .scheduled
        } else {
            lane = .completed
        }

        let agents = uniqueStrings(sortedSessions.map(\.agentType) + projectOperations.map(\.agentName))
        let activeTools = uniqueStrings(
            sortedSessions.flatMap { session in
                session.activeTools.map(\.toolName) + [session.lastToolName].compactMap { $0 }
            }
        )
        let subagentCount = sortedSessions.reduce(0) { $0 + $1.subagents.count }
        let latestOperationDate = projectOperations.map(\.timestamp).max()
        let lastActivity = max(latestOperationDate ?? .distantPast, sortedSessions.map { lastActivityDate(for: $0) }.max() ?? latest.startedAt)
        let startedAt = sortedSessions.map(\.startedAt).min() ?? latest.startedAt

        return AgentProjectSnapshot(
            id: key,
            title: projectTitle(for: sortedSessions, fallbackKey: key),
            path: key,
            lane: lane,
            agents: agents,
            sessions: sortedSessions,
            operations: projectOperations,
            startedAt: startedAt,
            lastActivityAt: lastActivity,
            progress: progressForProject(sessions: sortedSessions, totalTasks: totalTaskCount, completedTasks: completedTaskCount),
            completedTaskCount: completedTaskCount,
            totalTaskCount: totalTaskCount,
            pendingApprovalCount: pendingSessions.count,
            activeToolNames: activeTools,
            subagentCount: subagentCount,
            summary: projectSummary(for: sortedSessions, operations: projectOperations),
            blocker: blockerText(for: pendingSessions.first),
            scheduleHint: scheduled ? scheduleHint(for: sortedSessions) : nil
        )
    }

    private func operationBackedProjectSnapshots(excluding knownSessionRoots: Set<String>) -> [AgentProjectSnapshot] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let recentOperations = auditRecords.filter { $0.timestamp >= cutoff }
        let grouped = Dictionary(grouping: recentOperations) { operationProjectRoot(for: $0) }

        return grouped.compactMap { key, operations in
            guard !key.isEmpty, !knownSessionRoots.contains(key) else { return nil }
            let sortedOperations = operations.sorted { $0.timestamp > $1.timestamp }
            guard let latest = sortedOperations.first else { return nil }
            let agents = uniqueStrings(sortedOperations.map(\.agentName))
            let activeAgentNames = service.operationMonitor.activeAgentNames
            let hasLiveAgent = agents.contains { activeAgentNames.contains($0) }
            let lane: AgentProjectLane = hasLiveAgent && Date().timeIntervalSince(latest.timestamp) < 15 * 60 ? .live : .completed
            let title = URL(fileURLWithPath: key).lastPathComponent.isEmpty ? latest.agentName : URL(fileURLWithPath: key).lastPathComponent

            return AgentProjectSnapshot(
                id: key,
                title: title,
                path: key,
                lane: lane,
                agents: agents,
                sessions: [],
                operations: Array(sortedOperations.prefix(12)),
                startedAt: sortedOperations.map(\.timestamp).min() ?? latest.timestamp,
                lastActivityAt: latest.timestamp,
                progress: lane == .live ? 0.42 : 0.92,
                completedTaskCount: 0,
                totalTaskCount: 0,
                pendingApprovalCount: 0,
                activeToolNames: uniqueStrings(sortedOperations.compactMap(\.toolInfo)),
                subagentCount: 0,
                summary: latest.detail.isEmpty ? latest.targetPath : latest.detail,
                blocker: nil,
                scheduleHint: nil
            )
        }
        .sorted { $0.lastActivityAt > $1.lastActivityAt }
        .prefix(8)
        .map { $0 }
    }

    private func readAutomationProjectSnapshots() -> [AgentProjectSnapshot] {
        let root = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
            .appendingPathComponent(".codex/automations", isDirectory: true)
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return directories.compactMap { directory -> AgentProjectSnapshot? in
            let file = directory.appendingPathComponent("automation.toml")
            guard let config = parseAutomationConfig(file: file, directory: directory) else { return nil }

            let status = config.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isPaused = ["disabled", "paused", "inactive", "stopped", "off"].contains(status)
            let path = config.cwds.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? config.directoryPath
            let scheduleText = [config.kind, config.schedule]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            let hint = scheduleText.isEmpty
                ? localizer.t("等待下一次触发", en: "Waiting for next trigger", zhHant: "等待下一次觸發", ja: "次回トリガー待ち", ko: "다음 트리거 대기 중", mt: "Waiting for next trigger")
                : scheduleText
            let description = config.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = description.isEmpty
                ? localizer.t("Codex 定时项目会在触发后出现在实时项目中。", en: "This Codex automation will move into live projects after it starts.", zhHant: "Codex 排程專案觸發後會出現在即時專案中。", ja: "このCodex自動化は開始後にライブプロジェクトへ移動します。", ko: "이 Codex 자동화는 시작 후 실시간 프로젝트에 표시됩니다.", mt: "This Codex automation will move into live projects after it starts.")
                : shortText(description, limit: 180)

            return AgentProjectSnapshot(
                id: "codex-automation:\(config.id)",
                title: config.name,
                path: path,
                lane: isPaused ? .blocked : .scheduled,
                agents: uniqueStrings(["Codex", config.model.isEmpty ? "" : config.model]),
                sessions: [],
                operations: [],
                startedAt: config.updatedAt,
                lastActivityAt: config.updatedAt,
                progress: isPaused ? 0.08 : 0.18,
                completedTaskCount: 0,
                totalTaskCount: 1,
                pendingApprovalCount: isPaused ? 1 : 0,
                activeToolNames: [],
                subagentCount: 0,
                summary: summary,
                blocker: isPaused ? localizer.t("定时项目当前处于暂停或禁用状态", en: "This scheduled project is paused or disabled.", zhHant: "此排程專案目前暫停或停用", ja: "この予定プロジェクトは一時停止または無効です。", ko: "이 예약 프로젝트는 일시 중지되었거나 비활성화되었습니다.", mt: "This scheduled project is paused or disabled.") : nil,
                scheduleHint: hint
            )
        }
        .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    private func parseAutomationConfig(file: URL, directory: URL) -> AgentAutomationConfig? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }

        var name = directory.lastPathComponent
        var status = "active"
        var model = ""
        var kind = ""
        var schedule = ""
        var description = ""
        var cwds: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if let value = tomlStringValue(line, key: "name") {
                name = value
            } else if let value = tomlStringValue(line, key: "status") {
                status = value
            } else if let value = tomlStringValue(line, key: "model") {
                model = value
            } else if let value = tomlStringValue(line, key: "kind") {
                kind = value
            } else if let value = tomlStringValue(line, key: "rrule") {
                schedule = value
            } else if let value = tomlStringValue(line, key: "cron") {
                schedule = value
            } else if let value = tomlStringValue(line, key: "schedule") {
                schedule = value
            } else if let value = tomlStringValue(line, key: "description") {
                description = value
            } else if let value = tomlStringValue(line, key: "objective") {
                description = description.isEmpty ? value : description
            } else if let value = tomlStringValue(line, key: "prompt") {
                description = description.isEmpty ? value : description
            } else if let value = tomlStringValue(line, key: "cwd") {
                cwds.append(value)
            } else if let values = tomlArrayValue(line, key: "cwds") {
                cwds.append(contentsOf: values)
            }
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        let modified = attrs?[.modificationDate] as? Date ?? Date.distantPast
        return AgentAutomationConfig(
            id: directory.lastPathComponent,
            name: name,
            status: status,
            model: model,
            kind: kind,
            schedule: schedule,
            description: description,
            cwds: uniqueStrings(cwds),
            directoryPath: directory.path,
            updatedAt: modified
        )
    }

    private func tomlStringValue(_ line: String, key: String) -> String? {
        guard line.hasPrefix("\(key) =") || line.hasPrefix("\(key)="),
              let first = line.firstIndex(of: "\""),
              let last = line.lastIndex(of: "\""),
              first < last else {
            return nil
        }
        return String(line[line.index(after: first)..<last])
    }

    private func tomlArrayValue(_ line: String, key: String) -> [String]? {
        guard line.hasPrefix("\(key) =") || line.hasPrefix("\(key)="),
              let open = line.firstIndex(of: "["),
              let close = line.lastIndex(of: "]"),
              open < close else {
            return nil
        }
        let body = line[line.index(after: open)..<close]
        return body
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"")) }
            .filter { !$0.isEmpty }
    }

    private func operationsForProject(key: String, sessions: [SessionState]) -> [OperationRecord] {
        let sessionRoots = Set(sessions.map { projectKey(for: $0) })
        let sessionCwds = sessions.map(\.cwd).filter { !$0.isEmpty }
        return auditRecords
            .filter { record in
                let root = operationProjectRoot(for: record)
                if !root.isEmpty && (root == key || sessionRoots.contains(root)) { return true }
                return sessionCwds.contains { cwd in
                    record.targetPath.hasPrefix(cwd + "/") || record.targetPath == cwd
                }
            }
            .prefix(20)
            .map { $0 }
    }

    private func hasPendingAttention(_ session: SessionState) -> Bool {
        session.pendingPermission != nil ||
            session.pendingQuestion != nil ||
            session.pendingPlan != nil ||
            session.phase == .waitingApproval ||
            session.phase == .waitingInput ||
            session.phase == .error ||
            session.phase == .interrupted
    }

    private func isScheduledSession(_ session: SessionState) -> Bool {
        if (session.phase == .ready || session.phase == .idle) && session.hasUnfinishedTasks {
            return true
        }

        let haystack = [
            session.sessionTitle,
            session.description,
            session.statusLineText,
            session.lastUserMessage,
            session.lastResponse
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()

        return ["定时", "排程", "计划任务", "scheduled", "recurring", "cron", "automation", "monitor"].contains { haystack.contains($0) }
    }

    private func scheduleHint(for sessions: [SessionState]) -> String? {
        if let task = sessions.flatMap(\.tasks).first(where: { !taskIsDone($0) }) {
            return task.name
        }
        if let title = sessions.compactMap(\.sessionTitle).first(where: { !$0.isEmpty }) {
            return title
        }
        return localizer.t("等待下一次触发", en: "Waiting for next trigger", zhHant: "等待下一次觸發", ja: "次回トリガー待ち", ko: "다음 트리거 대기 중", mt: "Waiting for next trigger")
    }

    private func blockerText(for session: SessionState?) -> String? {
        guard let session else { return nil }
        if let permission = session.pendingPermission {
            return localizer.t("等待权限审批: \(permission.toolName)", en: "Waiting for permission: \(permission.toolName)", zhHant: "等待權限審批: \(permission.toolName)", ja: "権限承認待ち: \(permission.toolName)", ko: "권한 승인 대기: \(permission.toolName)", mt: "Waiting for permission: \(permission.toolName)")
        }
        if let question = session.pendingQuestion {
            return localizer.t("等待回复: \(shortText(question.question, limit: 80))", en: "Waiting for reply: \(shortText(question.question, limit: 80))", zhHant: "等待回覆: \(shortText(question.question, limit: 80))", ja: "返信待ち: \(shortText(question.question, limit: 80))", ko: "응답 대기: \(shortText(question.question, limit: 80))", mt: "Waiting for reply: \(shortText(question.question, limit: 80))")
        }
        if let plan = session.pendingPlan {
            return localizer.t("等待计划确认: \(plan.title)", en: "Waiting for plan approval: \(plan.title)", zhHant: "等待計劃確認: \(plan.title)", ja: "計画承認待ち: \(plan.title)", ko: "계획 승인 대기: \(plan.title)", mt: "Waiting for plan approval: \(plan.title)")
        }
        if session.phase == .error {
            return localizer.agentCenterPhaseError
        }
        if session.phase == .interrupted {
            return localizer.agentCenterPhaseInterrupted
        }
        return phaseLabel(session.phase)
    }

    private func progressForProject(sessions: [SessionState], totalTasks: Int, completedTasks: Int) -> Double {
        if totalTasks > 0 {
            return min(max(Double(completedTasks) / Double(totalTasks), 0.05), 1.0)
        }

        let values = sessions.map { phaseProgress($0.phase) }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func phaseProgress(_ phase: SessionPhase) -> Double {
        switch phase {
        case .ready: return 0.12
        case .idle: return 0.18
        case .processing: return 0.55
        case .waitingApproval, .waitingInput: return 0.48
        case .compacting: return 0.72
        case .done: return 1.0
        case .error: return 0.35
        case .interrupted: return 0.25
        }
    }

    private func projectSummary(for sessions: [SessionState], operations: [OperationRecord]) -> String {
        let sorted = sessions.sorted { lastActivityDate(for: $0) > lastActivityDate(for: $1) }
        let candidates = sorted.flatMap { session in
            [
                session.statusLineText,
                session.description,
                session.lastResponse,
                session.lastThought,
                session.lastUserMessage,
                session.lastToolName
            ]
        }
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        if let text = candidates.first(where: { !$0.isEmpty }) {
            return shortText(text, limit: 180)
        }

        if let operation = operations.first {
            let text = operation.detail.isEmpty ? operation.targetPath : operation.detail
            return shortText(text, limit: 180)
        }

        return localizer.t("等待更多实时事件", en: "Waiting for more live events", zhHant: "等待更多即時事件", ja: "ライブイベント待ち", ko: "추가 실시간 이벤트 대기 중", mt: "Waiting for more live events")
    }

    private func projectTitle(for sessions: [SessionState], fallbackKey: String) -> String {
        let sorted = sessions.sorted { lastActivityDate(for: $0) > lastActivityDate(for: $1) }
        if let title = sorted.compactMap(\.sessionTitle).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return shortProjectName(title)
        }
        if let project = sorted.map(\.project).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return shortProjectName(project)
        }
        return shortProjectName(fallbackKey)
    }

    private func projectKey(for session: SessionState) -> String {
        let cwd = session.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cwd.isEmpty {
            return projectRoot(from: cwd, allowFilePath: false)
        }

        let project = session.project.trimmingCharacters(in: .whitespacesAndNewlines)
        if !project.isEmpty {
            let root = projectRoot(from: project, allowFilePath: false)
            return root.isEmpty ? project : root
        }

        return session.id
    }

    private func operationProjectRoot(for record: OperationRecord) -> String {
        let targetRoot = projectRoot(from: record.targetPath, allowFilePath: true)
        if !targetRoot.isEmpty { return targetRoot }
        return projectRoot(from: record.detail, allowFilePath: true)
    }

    private func projectRoot(from rawPath: String, allowFilePath: Bool) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~") else { return "" }

        let expanded = NSString(string: trimmed).expandingTildeInPath
        let lower = expanded.lowercased()
        if lower.contains("/library/") || lower.contains("/.trash/") {
            return ""
        }

        let url = URL(fileURLWithPath: expanded)
        let components = url.pathComponents
        let anchors = ["Downloads", "Documents", "Desktop", "Developer", "Projects", "Code", "Workspace", "Work"]
        if let index = components.firstIndex(where: { anchors.contains($0) }),
           components.count > index + 1 {
            let rootComponents = Array(components.prefix(index + 2))
            return NSString.path(withComponents: rootComponents)
        }

        if allowFilePath && !url.pathExtension.isEmpty {
            return url.deletingLastPathComponent().path
        }

        return expanded
    }

    private func taskIsDone(_ task: TaskInfo) -> Bool {
        let status = task.status.lowercased()
        return status == "completed" || status == "done" || status == "success" || status == "finished"
    }

    private func lastActivityDate(for session: SessionState) -> Date {
        if let lastMainAgentAt = session.lastMainAgentAt, lastMainAgentAt > 0 {
            let value = Double(lastMainAgentAt)
            if value > 10_000_000_000 {
                return Date(timeIntervalSince1970: value / 1000)
            }
            return Date(timeIntervalSince1970: value)
        }
        return session.endedAt ?? session.startedAt
    }

    private func lanePriority(_ lane: AgentProjectLane) -> Int {
        switch lane {
        case .blocked: return 0
        case .live: return 1
        case .scheduled: return 2
        case .completed: return 3
        }
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed.lowercased()) else { continue }
            seen.insert(trimmed.lowercased())
            result.append(trimmed)
        }
        return result
    }

    private func shortProjectName(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return localizer.overviewNoProject }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath).lastPathComponent
        }
        return shortText(trimmed, limit: 48)
    }

    private func shortText(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit - 1)) + "…"
    }

    private func phaseLabel(_ phase: SessionPhase) -> String {
        switch phase {
        case .ready: return localizer.agentCenterPhaseReady
        case .idle: return localizer.agentCenterPhaseIdle
        case .processing: return localizer.agentCenterPhaseRunning
        case .waitingApproval: return localizer.agentCenterPending
        case .waitingInput: return localizer.agentCenterQuestion
        case .compacting: return localizer.agentCenterPhaseCompacting
        case .done: return localizer.agentCenterPhaseDone
        case .error: return localizer.agentCenterPhaseError
        case .interrupted: return localizer.agentCenterPhaseInterrupted
        }
    }

    private func relativeTimeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func statusLabel(_ status: AdapterStatus) -> String {
        switch status {
        case .active: return localizer.agentCenterActive
        case .installed: return localizer.agentCenterInstalled
        case .available: return localizer.agentCenterAvailableSummary
        case .unavailable: return localizer.agentCenterUnavailable
        }
    }
}

private struct AgentCenterSegmentButton: View {
    let title: String
    let icon: String
    let section: AgentCenterView.AgentCenterSection
    @Binding var selectedSection: AgentCenterView.AgentCenterSection

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.24)) {
                selectedSection = section
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: selectedSection == section ? .semibold : .medium))
                Text(title)
                    .font(Theme.Font.captionMedium)
            }
            .foregroundStyle(selectedSection == section ? Theme.Colors.teal : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm - 2)
            .background {
                if selectedSection == section {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.Colors.teal.opacity(0.16))
                }
            }
            .overlay {
                if selectedSection == section {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.Colors.teal.opacity(0.28), lineWidth: 0.8)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct AgentProjectLaneView: View {
    let lane: AgentProjectLane
    let projects: [AgentProjectSnapshot]
    let selectedProjectId: String?
    let localizer: Localizer
    let onSelect: (AgentProjectSnapshot) -> Void

    private var gridColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 238, maximum: 340), spacing: Theme.Spacing.md, alignment: .top)
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: lane.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(lane.color)
                    .frame(width: 26, height: 26)
                    .background(lane.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                VStack(alignment: .leading, spacing: 2) {
                    Text(lane.title(localizer))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(lane.subtitle(projects.count, localizer))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(projects.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(lane.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(lane.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            .padding(.horizontal, Theme.Spacing.xs)

            if projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(0.7))
                    Text(localizer.t("暂无项目", en: "No projects", zhHant: "暫無專案", ja: "プロジェクトなし", ko: "프로젝트 없음", mt: "No projects"))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 82)
                .background(Theme.Colors.cardBg.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
            } else {
                LazyVGrid(columns: gridColumns, alignment: .leading, spacing: Theme.Spacing.md) {
                    ForEach(projects) { project in
                        AgentProjectCard(
                            project: project,
                            isSelected: selectedProjectId == project.id,
                            localizer: localizer,
                            onSelect: { onSelect(project) }
                        )
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.Colors.elevatedCardBg.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        )
    }
}

private struct AgentProjectCard: View {
    let project: AgentProjectSnapshot
    let isSelected: Bool
    let localizer: Localizer
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: project.lane.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(project.lane.color)
                        .frame(width: 30, height: 30)
                        .background(project.lane.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(2)
                            .help(project.title)

                        Text(project.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(project.path)
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(localizer.t("进度", en: "Progress", zhHant: "進度", ja: "進捗", ko: "진행률", mt: "Progress"))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Spacer()
                        Text("\(Int((project.progress * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(project.lane.color)
                    }
                    ProgressView(value: min(max(project.progress, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(project.lane.color)
                }

                if let blocker = project.blocker, !blocker.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 10))
                        Text(blocker)
                            .font(Theme.Font.caption)
                            .lineLimit(2)
                    }
                    .foregroundStyle(Theme.Colors.warning)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.warning.opacity(0.09))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                } else if let scheduleHint = project.scheduleHint {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                        Text(scheduleHint)
                            .font(Theme.Font.caption)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Theme.Colors.info)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Colors.info.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }

                HStack(spacing: 5) {
                    ForEach(project.agents.prefix(3), id: \.self) { agent in
                        AgentProjectTinyBadge(text: agent, color: Theme.Colors.accent)
                    }
                    if project.agents.count > 3 {
                        AgentProjectTinyBadge(text: "+\(project.agents.count - 3)", color: Theme.Colors.textSecondary)
                    }
                }

                Text(project.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .frame(minHeight: 30, alignment: .topLeading)

                HStack(spacing: Theme.Spacing.sm) {
                    AgentProjectMetricPill(icon: "terminal", value: "\(project.sessionCount)", color: Theme.Colors.info, help: localizer.t("会话", en: "Sessions", zhHant: "會話", ja: "セッション", ko: "세션", mt: "Sessions"))
                    AgentProjectMetricPill(icon: "doc.text.magnifyingglass", value: "\(project.operationCount)", color: Theme.Colors.purple, help: localizer.audit)
                    if project.totalTaskCount > 0 {
                        AgentProjectMetricPill(icon: "checklist", value: "\(project.completedTaskCount)/\(project.totalTaskCount)", color: Theme.Colors.success, help: localizer.t("任务", en: "Tasks", zhHant: "任務", ja: "タスク", ko: "작업", mt: "Tasks"))
                    }
                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .background(isSelected ? project.lane.color.opacity(0.11) : Theme.Colors.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(isSelected ? project.lane.color.opacity(0.38) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AgentProjectDetailPanel: View {
    let project: AgentProjectSnapshot?
    let localizer: Localizer
    let phaseLabel: (SessionPhase) -> String
    let relativeTime: (Date) -> String
    let copyPath: (String) -> Void

    private var statColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 132), spacing: Theme.Spacing.sm, alignment: .top)]
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "list.bullet.rectangle.portrait.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text(localizer.t("项目详情", en: "Project Detail", zhHant: "專案詳情", ja: "プロジェクト詳細", ko: "프로젝트 상세", mt: "Project Detail"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.sidebarBg.opacity(0.32))

            Divider()

            if let project {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Image(systemName: project.lane.icon)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(project.lane.color)
                                .frame(width: 34, height: 34)
                                .background(project.lane.color.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(project.title)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(3)
                                Text(project.lane.title(localizer))
                                    .font(Theme.Font.captionMedium)
                                    .foregroundStyle(project.lane.color)
                            }
                            Spacer()
                        }

                        HStack(spacing: 6) {
                            Text(project.path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(project.path)
                            Button {
                                copyPath(project.path)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 10))
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.Colors.accent)
                            .help(localizer.copyPath)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(localizer.t("整体进度", en: "Overall Progress", zhHant: "整體進度", ja: "全体進捗", ko: "전체 진행률", mt: "Overall Progress"))
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Spacer()
                            Text("\(Int((project.progress * 100).rounded()))%")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(project.lane.color)
                        }
                        ProgressView(value: min(max(project.progress, 0), 1))
                            .progressViewStyle(.linear)
                            .tint(project.lane.color)
                    }

                    LazyVGrid(columns: statColumns, alignment: .leading, spacing: Theme.Spacing.sm) {
                        AgentProjectDetailStat(title: localizer.t("会话", en: "Sessions", zhHant: "會話", ja: "セッション", ko: "세션", mt: "Sessions"), value: "\(project.sessionCount)", icon: "terminal", color: Theme.Colors.info)
                        AgentProjectDetailStat(title: localizer.audit, value: "\(project.operationCount)", icon: "doc.text.magnifyingglass", color: Theme.Colors.purple)
                        AgentProjectDetailStat(title: localizer.t("子 Agent", en: "Subagents", zhHant: "子 Agent", ja: "サブAgent", ko: "하위 Agent", mt: "Subagents"), value: "\(project.subagentCount)", icon: "person.2.fill", color: Theme.Colors.teal)
                        AgentProjectDetailStat(title: localizer.t("待处理", en: "Pending", zhHant: "待處理", ja: "保留中", ko: "대기", mt: "Pending"), value: "\(project.pendingApprovalCount)", icon: "hand.raised.fill", color: project.pendingApprovalCount > 0 ? Theme.Colors.warning : Theme.Colors.success)
                    }

                    if let blocker = project.blocker {
                        detailSection(title: localizer.t("当前阻塞", en: "Current Blocker", zhHant: "目前阻塞", ja: "現在のブロッカー", ko: "현재 차단 항목", mt: "Current Blocker"), icon: "exclamationmark.triangle.fill", color: Theme.Colors.warning) {
                            Text(blocker)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(4)
                        }
                    }

                    if !project.activeToolNames.isEmpty {
                        detailSection(title: localizer.t("当前工具", en: "Active Tools", zhHant: "目前工具", ja: "アクティブツール", ko: "활성 도구", mt: "Active Tools"), icon: "hammer.fill", color: Theme.Colors.info) {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(project.activeToolNames.prefix(6), id: \.self) { tool in
                                    AgentProjectToolRow(name: tool)
                                }
                            }
                        }
                    }

                    detailSection(title: localizer.t("项目摘要", en: "Project Summary", zhHant: "專案摘要", ja: "プロジェクト概要", ko: "프로젝트 요약", mt: "Project Summary"), icon: "text.alignleft", color: Theme.Colors.accent) {
                        Text(project.summary)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(6)
                    }

                    if !project.sessions.isEmpty {
                        detailSection(title: localizer.t("会话流", en: "Session Flow", zhHant: "會話流", ja: "セッションフロー", ko: "세션 흐름", mt: "Session Flow"), icon: "point.3.connected.trianglepath.dotted", color: Theme.Colors.teal) {
                            VStack(spacing: 8) {
                                ForEach(project.sessions.prefix(5)) { session in
                                    AgentProjectSessionRow(session: session, localizer: localizer, phaseLabel: phaseLabel, relativeTime: relativeTime)
                                }
                            }
                        }
                    }

                    if !project.operations.isEmpty {
                        detailSection(title: localizer.t("最近审计", en: "Recent Audit", zhHant: "最近審計", ja: "最近の監査", ko: "최근 감사", mt: "Recent Audit"), icon: "clock.arrow.circlepath", color: Theme.Colors.purple) {
                            VStack(spacing: 8) {
                                ForEach(project.operations.prefix(6)) { operation in
                                    AgentProjectOperationRow(operation: operation, localizer: localizer, relativeTime: relativeTime)
                                }
                            }
                        }
                    }
                }
                .padding(Theme.Spacing.md)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(localizer.t("选择一个项目查看详情", en: "Select a project", zhHant: "選擇一個專案", ja: "プロジェクトを選択", ko: "프로젝트 선택", mt: "Select a project"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.Colors.elevatedCardBg.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func detailSection<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }
            content()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct AgentProjectTinyBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

private struct AgentProjectMetricPill: View {
    let icon: String
    let value: String
    let color: Color
    let help: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .help(help)
    }
}

private struct AgentProjectDetailStat: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct AgentProjectToolRow: View {
    let name: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "hammer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.info)
                .frame(width: 20, height: 20)
                .background(Theme.Colors.info.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            Text(name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }
}

private struct AgentProjectSessionRow: View {
    let session: SessionState
    let localizer: Localizer
    let phaseLabel: (SessionPhase) -> String
    let relativeTime: (Date) -> String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(phaseColor)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.agentType)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(phaseLabel(session.phase))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(phaseColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(phaseColor.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    Spacer(minLength: 0)
                }

                Text(session.lastToolName ?? session.description ?? session.cwd)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(relativeTime(session.endedAt ?? session.startedAt))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var phaseColor: Color {
        switch session.phase {
        case .processing, .compacting: return Theme.Colors.info
        case .waitingApproval, .waitingInput: return Theme.Colors.warning
        case .done, .idle, .ready: return Theme.Colors.success
        case .error, .interrupted: return Theme.Colors.danger
        }
    }
}

private struct AgentProjectOperationRow: View {
    let operation: OperationRecord
    let localizer: Localizer
    let relativeTime: (Date) -> String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: operation.operationType.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(operationColor)
                .frame(width: 22, height: 22)
                .background(operationColor.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(operation.operationType.localizedLabel(localizer))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("·")
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(operation.agentName)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(operation.targetPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(operation.targetPath)

                Text(relativeTime(operation.timestamp))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var operationColor: Color {
        switch operation.operationType {
        case .create: return Theme.Colors.success
        case .modify: return Theme.Colors.info
        case .delete: return Theme.Colors.danger
        case .move: return Theme.Colors.warning
        case .rename: return Theme.Colors.purple
        case .read: return Theme.Colors.teal
        case .execute: return Theme.Colors.purple
        }
    }
}

private struct AgentCenterStatusFilterButton: View {
    let title: String
    let status: AdapterStatus?
    @Binding var selectedStatus: AdapterStatus?

    private var isSelected: Bool { selectedStatus == status }

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.22)) {
                selectedStatus = status
            }
        } label: {
            Text(title)
                .font(Theme.Font.captionMedium)
                .lineLimit(1)
                .foregroundStyle(isSelected ? Theme.Colors.teal : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs + 1)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(Theme.Colors.teal.opacity(0.16))
                    }
                }
                .overlay {
                    if isSelected {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Theme.Colors.teal.opacity(0.28), lineWidth: 0.8)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct AgentCenterAuditRow: View {
    let record: OperationRecord
    let localizer: Localizer

    var body: some View {
        HStack(spacing: 12) {
            Text(timeText)
                .font(.system(size: 10, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)

            Text(record.agentName)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(record.agentName)
                .frame(width: 120, alignment: .leading)

            Label(record.operationType.localizedLabel(localizer), systemImage: record.operationType.icon)
                .font(.system(size: 10, weight: .semibold))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(operationColor)
                .lineLimit(1)
                .frame(width: 90, alignment: .leading)

            HStack(spacing: Theme.Spacing.xs) {
                Text(record.targetPath)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(record.targetPath)
                if !record.targetPath.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(record.targetPath, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                            .foregroundColor(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                    .help(localizer.copyPath)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(record.detail)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(record.detail)
                .frame(width: 180, alignment: .leading)
        }
        .padding(12)
        .background(.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: record.timestamp)
    }

    private var operationColor: Color {
        switch record.operationType {
        case .create: return .green
        case .modify: return .blue
        case .delete: return .red
        case .move: return .orange
        case .rename: return .purple
        case .read: return .teal
        case .execute: return .purple
        }
    }
}

private struct AgentCenterApprovalScopeButton: View {
    let title: String
    let icon: String
    let scope: AgentCenterApprovalScope
    @Binding var selectedScope: AgentCenterApprovalScope

    private var isSelected: Bool { selectedScope == scope }

    var body: some View {
        Button {
            withAnimation(.spring(duration: 0.22)) {
                selectedScope = scope
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Theme.Colors.teal : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm - 2)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(Theme.Colors.teal.opacity(0.16))
                }
            }
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.Colors.teal.opacity(0.28), lineWidth: 0.8)
                }
            }
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

struct AgentRowView: View {
    let profile: AgentIntegrationProfile
    let status: AdapterStatus
    let isSelected: Bool
    let isWorking: Bool
    let supportsHooks: Bool
    let localizer: Localizer
    let onSelect: () -> Void
    let onInstall: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: profile.systemImage)
                    .font(.system(size: 16))
                    .foregroundStyle(statusColor)
                    .frame(width: 32, height: 32)
                    .background(statusColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                VStack(alignment: .leading, spacing: 2) {
                    Text(profile.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .help(profile.displayName)
                    Text(profile.executable)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .help(profile.executable)
                }
            }
            .frame(width: AgentCenterColumns.agentName, alignment: .leading)

            Text(profile.configRoot)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(status == .unavailable ? Theme.Colors.textTertiary : Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(profile.configRoot)
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                statusBadge
                Text(supportsHooks ? localizer.agentCenterHookHint : localizer.agentCenterHookUnsupported)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(2)
            }
            .frame(width: AgentCenterColumns.hookStatus, alignment: .leading)

            HStack(spacing: 4) {
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.7)
                        .frame(width: 88, alignment: .trailing)
                } else if supportsHooks && (status == .installed || status == .available) {
                    Button(action: onInstall) {
                        Label(localizer.agentCenterConnect, systemImage: "point.3.connected.trianglepath.dotted")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Theme.Colors.success)
                } else if supportsHooks && status == .active {
                    Button(action: onUninstall) {
                        Label(localizer.agentCenterDisconnect, systemImage: "xmark.circle")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(Theme.Colors.danger)
                } else {
                    Text(supportsHooks ? localizer.agentCenterUnavailable : localizer.agentCenterUnsupported)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
            }
            .frame(width: AgentCenterColumns.action, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isSelected ? Theme.Colors.info.opacity(0.08) : Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(isSelected ? Theme.Colors.info.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }

    private var statusBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var statusText: String {
        switch status {
        case .active: return localizer.agentCenterActive
        case .installed: return localizer.agentCenterInstalled
        case .available: return localizer.agentCenterAvailableSummary
        case .unavailable: return localizer.agentCenterUnavailable
        }
    }

    private var statusColor: Color {
        switch status {
        case .active: return .green
        case .installed: return .blue
        case .available: return .orange
        case .unavailable: return .secondary
        }
    }
}

private struct ApprovalSessionRow: View {
    let session: SessionState
    let localizer: Localizer
    let isHistory: Bool
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundStyle(color)
                        .frame(width: 34, height: 34)
                        .background(color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .help(title)
                        if isHistory {
                            Text(phaseLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(phaseColor)
                                .lineLimit(1)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(phaseColor.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                .help(phaseLabel)
                        }
                    }
                }
                .frame(width: AgentCenterColumns.approvalType, alignment: .leading)

                Text(session.agentType)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(session.agentType)
                    .frame(width: AgentCenterColumns.approvalAgent, alignment: .leading)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(detail)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(timeText)
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: AgentCenterColumns.approvalTime, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: AgentCenterColumns.chevron, alignment: .trailing)
            }
            .padding(12)
            .background(.primary.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if session.pendingPermission != nil { return localizer.agentCenterPermission }
        if let question = session.pendingQuestion { return question.isTextReply ? localizer.agentCenterTextReply : localizer.agentCenterQuestion }
        if session.pendingPlan != nil { return localizer.agentCenterPlan }
        if let approval = latestApproval { return approvalTitle(for: approval) }
        return phaseLabel
    }

    private var detail: String {
        if let permission = session.pendingPermission { return permission.toolName }
        if let question = session.pendingQuestion { return question.question }
        if let plan = session.pendingPlan { return plan.title }
        if let approval = latestApproval {
            return approval.detail.isEmpty ? approval.title : approval.detail
        }
        if let tool = session.lastToolName, !tool.isEmpty { return tool }
        if let description = session.description, !description.isEmpty { return description }
        return session.project
    }

    private var icon: String {
        if session.pendingPermission != nil { return "hand.raised.fill" }
        if let question = session.pendingQuestion { return question.isTextReply ? "text.bubble.fill" : "questionmark.bubble.fill" }
        if session.pendingPlan != nil { return "list.clipboard.fill" }
        if let approval = latestApproval {
            switch approval.kind {
            case "permission": return "hand.raised.fill"
            case "question": return "questionmark.bubble.fill"
            case "plan": return "list.clipboard.fill"
            default: return "checkmark.seal.fill"
            }
        }
        return "exclamationmark.triangle.fill"
    }

    private var color: Color {
        if session.pendingPermission != nil { return .orange }
        if session.pendingQuestion != nil { return .purple }
        if session.pendingPlan != nil { return .cyan }
        return isHistory ? .blue : .red
    }

    private var phaseLabel: String {
        if let approval = latestApproval {
            return approval.isPending ? localizer.agentCenterPending : localizer.agentCenterPhaseDone
        }

        switch session.phase {
        case .ready: return localizer.agentCenterPhaseReady
        case .idle: return localizer.agentCenterPhaseIdle
        case .processing: return localizer.agentCenterPhaseRunning
        case .waitingApproval: return localizer.agentCenterPending
        case .waitingInput: return localizer.agentCenterQuestion
        case .compacting: return localizer.agentCenterPhaseCompacting
        case .done: return localizer.agentCenterPhaseDone
        case .error: return localizer.agentCenterPhaseError
        case .interrupted: return localizer.agentCenterPhaseInterrupted
        }
    }

    private var phaseColor: Color {
        if let approval = latestApproval {
            return approval.isPending ? .orange : .green
        }

        switch session.phase {
        case .waitingApproval, .waitingInput: return .orange
        case .processing, .compacting: return .blue
        case .done, .idle, .ready: return .green
        case .error, .interrupted: return .red
        }
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        if let approval = latestApproval {
            return formatter.string(from: approval.resolvedAt ?? approval.requestedAt)
        }
        return formatter.string(from: session.endedAt ?? session.startedAt)
    }

    private var latestApproval: ApprovalHistoryRecord? {
        session.approvalHistory.last
    }

    private func approvalTitle(for approval: ApprovalHistoryRecord) -> String {
        switch approval.kind {
        case "permission": return localizer.agentCenterPermission
        case "question": return localizer.agentCenterQuestion
        case "plan": return localizer.agentCenterPlan
        default: return approval.title
        }
    }
}
