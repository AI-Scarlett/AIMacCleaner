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

struct AgentCenterView: View {
    @EnvironmentObject var agentRegistry: AgentRegistry
    @EnvironmentObject var sessionsViewModel: SessionsViewModel
    @EnvironmentObject var islandViewModel: IslandViewModel
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @State private var selectedAgentId: String?
    @State private var searchText: String = ""
    @State private var filterStatus: AdapterStatus?
    @State private var selectedSection: AgentCenterSection = .approvals
    @State private var selectedApprovalScope: AgentCenterApprovalScope = .pending

    enum AgentCenterSection: String, CaseIterable {
        case approvals
        case audit
        case integrations
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider().opacity(0.6)
            if selectedSection == .approvals {
                approvalsContent
            } else if selectedSection == .audit {
                auditContent
            } else {
                agentListContent
            }
        }
        .background(Theme.Colors.background)
        .onAppear {
            NotificationCenter.default.post(name: .agentCenterShouldInitialize, object: nil)
            agentRegistry.refreshAllStatuses()
            service.ensureAgentGuardDataPipeline()
            service.refreshOperationRecordsSnapshot()
        }
    }

    private var headerSection: some View {
        VStack(spacing: Theme.Spacing.md) {
            PageHeader(
                icon: "house.fill",
                title: localizer.navAgentCenter,
                subtitle: localizer.subAgentCenter,
                color: Theme.Colors.warning
            ) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button(action: { agentRegistry.refreshAllStatuses() }) {
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

            HStack(spacing: Theme.Spacing.sm) {
                StatCardView(
                    icon: "hand.raised.fill",
                    iconColor: pendingApprovalSessions.isEmpty ? Theme.Colors.success : Theme.Colors.warning,
                    title: localizer.agentCenterApprovals,
                    value: "\(pendingApprovalSessions.count)",
                    subtitle: localizer.agentCenterPendingApprovalsHint
                )
                StatCardView(
                    icon: "bolt.badge.checkmark",
                    iconColor: Theme.Colors.success,
                    title: localizer.agentCenterActive,
                    value: "\(agentRegistry.activeCount)",
                    subtitle: localizer.agentCenterActiveSummary
                )
                StatCardView(
                    icon: "puzzlepiece.extension.fill",
                    iconColor: Theme.Colors.info,
                    title: localizer.agentCenterInstalled,
                    value: "\(agentRegistry.installedCount)",
                    subtitle: localizer.agentCenterInstalledSummary
                )
                StatCardView(
                    icon: "tray.full.fill",
                    iconColor: Theme.Colors.teal,
                    title: localizer.agentCenterAll,
                    value: "\(agentRegistry.allAdapters.count)",
                    subtitle: localizer.agentCenterAvailableSummary
                )
                StatCardView(
                    icon: "doc.text.magnifyingglass",
                    iconColor: Theme.Colors.purple,
                    title: localizer.audit,
                    value: "\(auditRecords.count)",
                    subtitle: localizer.agentOpAudit
                )
            }
            .padding(.horizontal, Theme.Spacing.xl)

            statusStrip

            HStack(spacing: Theme.Spacing.lg) {
                HStack(spacing: 0) {
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

                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.xl)

            if selectedSection == .integrations {
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
                                    islandViewModel.currentSession = session
                                    if isHistory {
                                        islandViewModel.showDetail(for: session)
                                    } else {
                                        islandViewModel.show(level: .expanded)
                                    }
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
                    service.importKnownAgentHistory()
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
