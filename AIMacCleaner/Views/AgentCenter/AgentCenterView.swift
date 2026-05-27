import SwiftUI

struct AgentCenterView: View {
    @EnvironmentObject var agentRegistry: AgentRegistry
    @EnvironmentObject var sessionsViewModel: SessionsViewModel
    @EnvironmentObject var islandViewModel: IslandViewModel
    @EnvironmentObject var localizer: Localizer
    @State private var selectedAgentId: String?
    @State private var searchText: String = ""
    @State private var filterStatus: AdapterStatus?
    @State private var selectedSection: AgentCenterSection = .integrations

    private enum AgentCenterSection: String, CaseIterable {
        case integrations
        case approvals
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Divider()
            if selectedSection == .integrations {
                agentListContent
            } else {
                approvalsContent
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.navAgentCenter)
                        .font(.system(size: 18, weight: .bold))
                    Text("\(agentRegistry.activeCount) \(localizer.agentCenterActiveSummary) · \(agentRegistry.installedCount) \(localizer.agentCenterInstalledSummary) · \(agentRegistry.allAdapters.count - agentRegistry.unavailableCount) \(localizer.agentCenterAvailableSummary)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: { agentRegistry.refreshAllStatuses() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 11))
                            Text(localizer.agentCenterRefresh)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)

                    Button(action: { agentRegistry.installAllAvailableHooks() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 11))
                            Text(localizer.agentCenterInstallAll)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.green)
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker("", selection: $selectedSection) {
                Text(localizer.agentCenterIntegrations).tag(AgentCenterSection.integrations)
                Text(localizer.agentCenterApprovals).tag(AgentCenterSection.approvals)
            }
            .pickerStyle(.segmented)
            .controlSize(.small)

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField(localizer.agentCenterSearch, text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.primary.opacity(0.06))
                .cornerRadius(8)

                Picker("Filter", selection: $filterStatus) {
                    Text(localizer.agentCenterAll).tag(nil as AdapterStatus?)
                    ForEach(AdapterStatus.allCases, id: \.self) { status in
                        Text(statusLabel(status)).tag(status as AdapterStatus?)
                    }
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
            }
        }
        .padding(16)
    }

    private var agentListContent: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(filteredAdapters, id: \.agentId) { profile in
                    AgentRowView(
                        profile: profile,
                        status: agentRegistry.status(for: profile.agentId),
                        isSelected: selectedAgentId == profile.agentId,
                        localizer: localizer,
                        onSelect: { selectedAgentId = profile.agentId },
                        onInstall: { agentRegistry.installHooks(for: profile.agentId) },
                        onUninstall: { agentRegistry.uninstallHooks(for: profile.agentId) }
                    )
                }
            }
        }
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

    private var approvalsContent: some View {
        Group {
            if pendingApprovalSessions.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 34))
                        .foregroundStyle(.green.opacity(0.75))
                    Text(localizer.agentCenterNoApprovals)
                        .font(.system(size: 14, weight: .semibold))
                    Text(localizer.agentCenterPendingApprovalsHint)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(pendingApprovalSessions) { session in
                            ApprovalSessionRow(session: session, localizer: localizer) {
                                islandViewModel.currentSession = session
                                islandViewModel.show(level: .expanded)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
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

struct AgentRowView: View {
    let profile: AgentIntegrationProfile
    let status: AdapterStatus
    let isSelected: Bool
    let localizer: Localizer
    let onSelect: () -> Void
    let onInstall: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: profile.systemImage)
                .font(.system(size: 16))
                .foregroundStyle(statusColor)
                .frame(width: 32, height: 32)
                .background(statusColor.opacity(0.1))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 2) {
                Text(profile.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(profile.executable)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)

                if status == .active || status == .installed {
                    Text(profile.configRoot)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            statusBadge

            HStack(spacing: 4) {
                if status == .installed {
                    Button(action: onInstall) {
                        Text(localizer.agentCenterInstallHook)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                } else if status == .active || status == .installed {
                    Button(action: onUninstall) {
                        Text(localizer.agentCenterRemoveHook)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.red.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(localizer.agentCenterUnavailable)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isSelected ? .blue.opacity(0.06) : .clear)
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
        .cornerRadius(4)
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
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)
                    .frame(width: 34, height: 34)
                    .background(color.opacity(0.12))
                    .cornerRadius(7)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(session.agentType)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.primary.opacity(0.04))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }

    private var title: String {
        if session.pendingPermission != nil { return localizer.agentCenterPermission }
        if session.pendingQuestion != nil { return localizer.agentCenterQuestion }
        if session.pendingPlan != nil { return localizer.agentCenterPlan }
        return session.phase.rawValue
    }

    private var detail: String {
        if let permission = session.pendingPermission { return permission.toolName }
        if let question = session.pendingQuestion { return question.question }
        if let plan = session.pendingPlan { return plan.title }
        return session.description ?? session.project
    }

    private var icon: String {
        if session.pendingPermission != nil { return "hand.raised.fill" }
        if session.pendingQuestion != nil { return "questionmark.bubble.fill" }
        if session.pendingPlan != nil { return "list.clipboard.fill" }
        return "exclamationmark.triangle.fill"
    }

    private var color: Color {
        if session.pendingPermission != nil { return .orange }
        if session.pendingQuestion != nil { return .purple }
        if session.pendingPlan != nil { return .cyan }
        return .red
    }
}
