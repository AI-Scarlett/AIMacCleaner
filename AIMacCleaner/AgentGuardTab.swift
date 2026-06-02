import SwiftUI
import Charts
import AppKit
import UserNotifications

struct AgentGuardTab: View {

    struct HourlyStatPoint: Identifiable {
        let id = UUID()
        let hour: Date
        let count: Int
        let type: String
    }

    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var service: ScannerService
    @State private var selectedSegment = 0
    @State private var alertFilter: GuardAlert.AlertSeverity?
    @State private var reportPeriod = 0
    @State private var showReportSheet = false
    @State private var generatedReport: AuditReport?
    @State private var newBlacklistPattern = ""
    @State private var showCreateOps = true
    @State private var showModifyOps = true
    @State private var showDeleteOps = true
    @State private var showReadOps = true
    @State private var showExecuteOps = true
    @State private var chartTimeRange = 0
    @State private var chartHoverDate: Date?
    @State private var toastMessage: String = ""
    @State private var showToast = false
    @State private var toastTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "shield.fill",
                title: localizer.navAgentGuard,
                subtitle: localizer.subAgentGuard,
                color: Theme.Colors.warning
            )

            segmentPicker

            ScrollView {
                switch selectedSegment {
                case 0: dashboardView
                case 1: alertCenterView
                case 2: alertRulesView
                case 3: commandRulesView
                case 4: protectedDirsView
                default: dashboardView
                }
            }
        }
        .overlay(alignment: .top) {
            if showToast {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text(toastMessage)
                        .font(Theme.Font.captionMedium)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Theme.Colors.success)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showToast)
        .onAppear {
            service.ensureAgentGuardDataPipeline()
        }
    }

    private var segmentPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                SegmentButton(title: localizer.guardDashboard, icon: "gauge", index: 0, tint: Theme.Colors.warning, selected: $selectedSegment)
                SegmentButton(title: localizer.alertCenter, icon: "bell.badge", index: 1, tint: Theme.Colors.warning, selected: $selectedSegment)
                SegmentButton(title: localizer.alertRules, icon: "slider.horizontal.3", index: 2, tint: Theme.Colors.warning, selected: $selectedSegment)
                SegmentButton(title: localizer.commandRules, icon: "terminal", index: 3, tint: Theme.Colors.warning, selected: $selectedSegment)
                SegmentButton(title: localizer.protectedDirs, icon: "folder.badge.eye", index: 4, tint: Theme.Colors.warning, selected: $selectedSegment)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.background)
    }

    // MARK: - Dashboard

    private var dashboardView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if service.operationMonitor.needsReauthorization {
                reauthorizationBanner
            }

            HStack(spacing: Theme.Spacing.lg) {
                StatCard(
                    title: localizer.unreadAlerts,
                    value: "\(service.guardFeature.unreadAlertCount)",
                    icon: "bell.badge.fill",
                    color: service.guardFeature.unreadAlertCount > 0 ? Theme.Colors.danger : Theme.Colors.success
                )
                StatCard(
                    title: localizer.criticalAlerts,
                    value: "\(service.guardFeature.criticalAlertCount)",
                    icon: "exclamationmark.octagon.fill",
                    color: Theme.Colors.danger
                )
                StatCard(
                    title: localizer.totalAlerts,
                    value: "\(service.guardFeature.alerts.count)",
                    icon: "bell.fill",
                    color: Theme.Colors.info
                )
                StatCard(
                    title: localizer.totalOpsLabel,
                    value: "\(service.operationRecords.count)",
                    icon: "doc.fill",
                    color: Theme.Colors.accent
                )
            }

            dashboardTrendChart

            recentAlertsPreview

            quickActionsCard
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var reauthorizationBanner: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(Theme.Colors.warning)
            Text(localizer.permissionExpired)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Button {
                service.operationMonitor.requestAccessForStalePaths()
                service.importKnownAgentHistory()
            } label: {
                Text(localizer.reauthorize)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.Colors.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.warning.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var recentAlertsPreview: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(localizer.alertCenter)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if !service.guardFeature.alerts.isEmpty {
                    Button {
                        selectedSegment = 1
                    } label: {
                        Text(localizer.viewFullLogLabel)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if service.guardFeature.alerts.isEmpty {
                emptyStateView(icon: "checkmark.circle.fill", message: localizer.noAlerts, hint: localizer.noAlertsHint, color: Theme.Colors.success)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(service.guardFeature.alerts.prefix(5)) { alert in
                        alertRow(alert)
                    }
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var quickActionsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(localizer.exportData)
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.sm) {
                actionButton(title: localizer.exportCSV, icon: "doc.text") {
                    let csv = service.guardFeature.exportRecordsAsCSV(records: service.operationRecords)
                    _ = service.guardFeature.saveExport(content: csv, filename: "agent_operations.csv")
                }
                actionButton(title: localizer.exportJSON, icon: "doc.richtext") {
                    let json = service.guardFeature.exportRecordsAsJSON(records: service.operationRecords)
                    _ = service.guardFeature.saveExport(content: json, filename: "agent_operations.json")
                }
                actionButton(title: localizer.exportAlertsCSV, icon: "bell.and.text") {
                    let csv = service.guardFeature.exportAlertsAsCSV()
                    _ = service.guardFeature.saveExport(content: csv, filename: "agent_alerts.csv")
                }
                actionButton(title: localizer.generateReport, icon: "doc.text.magnifyingglass") {
                    generateReport()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    // MARK: - Alert Center

    private var alertCenterView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.sm) {
                severityFilterChip(label: localizer.filterAll, severity: nil)
                severityFilterChip(label: localizer.filterCritical, severity: .critical)
                severityFilterChip(label: localizer.filterWarning, severity: .warning)
                severityFilterChip(label: localizer.filterInfo, severity: .info)
                Spacer()
                Button { service.guardFeature.markAllAlertsRead() } label: {
                    Text(localizer.markAllRead)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
                Button {
                    service.guardFeature.clearAlerts()
                } label: {
                    Text(localizer.clearAllAlerts)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.danger)
                }
                .buttonStyle(.plain)
            }

            let filtered = alertFilter == nil ? service.guardFeature.alerts : service.guardFeature.alerts.filter { $0.severity == alertFilter }
            if filtered.isEmpty {
                emptyStateView(icon: "checkmark.circle.fill", message: localizer.noAlerts, hint: localizer.noAlertsHint, color: Theme.Colors.success)
            } else {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(filtered) { alert in
                        alertDetailRow(alert)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Alert Rules

    private var alertRulesView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ruleSection(title: localizer.batchDeleteThreshold, description: localizer.batchDeleteDesc) {
                HStack {
                    Slider(value: Binding(
                        get: { Double(service.guardFeature.alertRule.batchDeleteThreshold) },
                        set: { service.guardFeature.alertRule.batchDeleteThreshold = Int($0); service.guardFeature.scheduleSaveAlertRule() }
                    ), in: 2...50, step: 1)
                    Text("\(service.guardFeature.alertRule.batchDeleteThreshold)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 30)
                }
            }

            ruleSection(title: localizer.batchModifyThreshold, description: localizer.batchModifyDesc) {
                HStack {
                    Slider(value: Binding(
                        get: { Double(service.guardFeature.alertRule.batchModifyThreshold) },
                        set: { service.guardFeature.alertRule.batchModifyThreshold = Int($0); service.guardFeature.scheduleSaveAlertRule() }
                    ), in: 2...100, step: 1)
                    Text("\(service.guardFeature.alertRule.batchModifyThreshold)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 30)
                }
            }

            ruleSection(title: localizer.timeWindowSeconds, description: localizer.timeWindowDesc) {
                HStack {
                    Slider(value: Binding(
                        get: { service.guardFeature.alertRule.batchTimeWindowSeconds },
                        set: { service.guardFeature.alertRule.batchTimeWindowSeconds = $0; service.guardFeature.scheduleSaveAlertRule() }
                    ), in: 5...300, step: 5)
                    Text("\(Int(service.guardFeature.alertRule.batchTimeWindowSeconds))s")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 40)
                }
            }

            ruleSection(title: localizer.alertCooldown, description: localizer.alertCooldownDesc) {
                HStack {
                    Slider(value: Binding(
                        get: { service.guardFeature.alertRule.alertCooldownSeconds },
                        set: { service.guardFeature.alertRule.alertCooldownSeconds = $0; service.guardFeature.scheduleSaveAlertRule() }
                    ), in: 10...600, step: 10)
                    Text("\(Int(service.guardFeature.alertRule.alertCooldownSeconds))s")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 40)
                }
            }

            Divider()

            toggleRule(title: localizer.enableSensitiveFile, description: localizer.sensitiveFileDesc, isOn: Binding(
                get: { service.guardFeature.alertRule.sensitiveFileDetectionEnabled },
                set: { service.guardFeature.alertRule.sensitiveFileDetectionEnabled = $0; service.guardFeature.scheduleSaveAlertRule() }
            ))

            toggleRule(title: localizer.enableSensitiveContent, description: localizer.sensitiveContentDesc, isOn: Binding(
                get: { service.guardFeature.alertRule.sensitiveContentDetectionEnabled },
                set: { service.guardFeature.alertRule.sensitiveContentDetectionEnabled = $0; service.guardFeature.scheduleSaveAlertRule() }
            ))

            toggleRule(title: localizer.enableProcessAlert, description: localizer.processAlertDesc, isOn: Binding(
                get: { service.guardFeature.alertRule.processLaunchAlertEnabled },
                set: { service.guardFeature.alertRule.processLaunchAlertEnabled = $0; service.guardFeature.scheduleSaveAlertRule() }
            ))

            toggleRule(title: localizer.enableProtectedDir, description: localizer.protectedDirDesc, isOn: Binding(
                get: { service.guardFeature.alertRule.protectedDirAlertEnabled },
                set: { service.guardFeature.alertRule.protectedDirAlertEnabled = $0; service.guardFeature.scheduleSaveAlertRule() }
            ))

            toggleRule(title: localizer.enableNotification, description: localizer.notificationDesc, isOn: Binding(
                get: { service.guardFeature.alertRule.notificationEnabled },
                set: { service.guardFeature.alertRule.notificationEnabled = $0; service.guardFeature.scheduleSaveAlertRule() }
            ))

            Divider()

            toggleRule(title: localizer.doNotDisturb, description: localizer.doNotDisturbDesc, isOn: Binding(
                get: { service.guardFeature.alertRule.doNotDisturbEnabled },
                set: { service.guardFeature.alertRule.doNotDisturbEnabled = $0; service.guardFeature.scheduleSaveAlertRule() }
            ))

            if service.guardFeature.alertRule.doNotDisturbEnabled {
                HStack {
                    Text(localizer.dndTimeRange)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { service.guardFeature.alertRule.doNotDisturbStartHour },
                        set: { service.guardFeature.alertRule.doNotDisturbStartHour = $0; service.guardFeature.scheduleSaveAlertRule() }
                    )) {
                        ForEach(0..<24, id: \.self) { (h: Int) in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }
                    .frame(width: 80)
                    Text("—")
                    Picker("", selection: Binding(
                        get: { service.guardFeature.alertRule.doNotDisturbEndHour },
                        set: { service.guardFeature.alertRule.doNotDisturbEndHour = $0; service.guardFeature.scheduleSaveAlertRule() }
                    )) {
                        ForEach(0..<24, id: \.self) { (h: Int) in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }
                    .frame(width: 80)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Command Rules

    private var commandRulesView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            toggleRule(title: localizer.enableCommandGuard, isOn: Binding(
                get: { service.guardFeature.alertRule.commandGuardEnabled },
                set: { service.guardFeature.alertRule.commandGuardEnabled = $0; service.guardFeature.scheduleSaveAlertRule() }
            ))

            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.info)
                Text(localizer.commandRulesDesc)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.md)

            if service.guardFeature.alertRule.commandGuardEnabled {
                commandSectionHeader(
                    icon: "xmark.octagon.fill",
                    title: localizer.commandBlacklist,
                    count: service.guardFeature.blacklistRules.count,
                    color: Theme.Colors.danger
                )

                ForEach(service.guardFeature.blacklistRules) { rule in
                    commandRuleCard(rule: rule)
                }

                commandSectionHeader(
                    icon: "checkmark.circle.fill",
                    title: localizer.commandWhitelist,
                    count: service.guardFeature.whitelistRules.count,
                    color: Theme.Colors.success
                )

                ForEach(service.guardFeature.whitelistRules) { rule in
                    commandRuleCard(rule: rule)
                }

                commandSectionHeader(
                    icon: "exclamationmark.triangle.fill",
                    title: localizer.commandUnclassified,
                    count: service.guardFeature.unclassifiedRules.count,
                    color: Theme.Colors.warning
                )

                if service.guardFeature.unclassifiedRules.isEmpty {
                    Text(localizer.noUnclassifiedRules)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(Theme.Spacing.md)
                        .frame(maxWidth: .infinity)
                        .background(Theme.Colors.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                } else {
                    ForEach(service.guardFeature.unclassifiedRules) { rule in
                        commandRuleCard(rule: rule)
                    }
                }

                Divider()

                addCommandForm
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private func commandSectionHeader(icon: String, title: String, count: Int, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(title)
                .font(Theme.Font.subheadlineMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("(\(count))")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Spacer()
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private func commandRuleCard(rule: CommandRule) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                listTypeBadge(rule.listType)

                Text(rule.pattern)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                sourceBadge(rule.source)

                Button {
                    service.guardFeature.removeCommandRule(id: rule.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.danger.opacity(0.7))
                }
                .buttonStyle(.plain)
            }

            if !rule.commandDesc.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(service.guardFeature.localizeCommandDesc(rule.commandDesc, localizer: localizer))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }

            if !rule.consequence.isEmpty {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9))
                        .foregroundStyle(rule.listType == .blacklist ? Theme.Colors.danger.opacity(0.7) : Theme.Colors.warning.opacity(0.7))
                    Text(service.guardFeature.localizeCommandDesc(rule.consequence, localizer: localizer))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                HStack(spacing: Theme.Spacing.sm) {
                    if rule.listType != .blacklist {
                        Button {
                            service.guardFeature.moveCommandToBlacklist(id: rule.id)
                            showCommandToast(localizer.moveToBlacklist)
                        } label: {
                            Label(localizer.moveToBlacklist, systemImage: "xmark.octagon")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.Colors.danger)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if rule.listType != .whitelist {
                        Button {
                            service.guardFeature.moveCommandToWhitelist(id: rule.id)
                            showCommandToast(localizer.moveToWhitelist)
                        } label: {
                            Label(localizer.moveToWhitelist, systemImage: "checkmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.Colors.success)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    if rule.listType != .unclassified {
                        Button {
                            service.guardFeature.moveCommandToUnclassified(id: rule.id)
                            showCommandToast(localizer.moveToUnclassified)
                        } label: {
                            Label(localizer.moveToUnclassified, systemImage: "questionmark.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(.black.opacity(0.82))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.Colors.warning)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                HStack(spacing: Theme.Spacing.lg) {
                    VStack(alignment: .center, spacing: 2) {
                        Text("\(rule.totalCallCount)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.totalCount)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    VStack(alignment: .center, spacing: 2) {
                        Text("\(rule.todayCallCount)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.Colors.accent)
                        Text(localizer.todayCount)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    if !rule.lastCalledBy.isEmpty {
                        let agentName = String(rule.lastCalledBy.split(separator: "|").last ?? "")
                        if !agentName.isEmpty {
                            VStack(alignment: .center, spacing: 2) {
                                Text(agentName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(Theme.Colors.info)
                                    .lineLimit(1)
                                Text(localizer.lastCalledBy)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(listTypeColor(rule.listType).opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(listTypeColor(rule.listType).opacity(0.12), lineWidth: 1)
        )
    }

    private var addCommandForm: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(localizer.addCustomCommand)
                .font(Theme.Font.subheadlineMedium)
                .foregroundStyle(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.sm) {
                TextField(localizer.newCommandPattern, text: $newBlacklistPattern)
                    .textFieldStyle(.roundedBorder)
                    .font(Theme.Font.caption)
                Button {
                    if !newBlacklistPattern.isEmpty {
                        service.guardFeature.addCommandRule(pattern: newBlacklistPattern, listType: .unclassified)
                        newBlacklistPattern = ""
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func listTypeBadge(_ type: CommandRule.ListType) -> some View {
        let (icon, text, color) = switch type {
        case .blacklist: ("xmark.octagon.fill", localizer.blacklistLabel, Theme.Colors.danger)
        case .whitelist: ("checkmark.circle.fill", localizer.whitelistLabel, Theme.Colors.success)
        case .unclassified: ("exclamationmark.triangle.fill", localizer.unclassifiedLabel, Theme.Colors.warning)
        }
        return HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }

    private func sourceBadge(_ source: CommandRule.Source) -> some View {
        let text = switch source {
        case .default: localizer.sourceDefault
        case .discovered: localizer.sourceDiscovered
        case .custom: localizer.sourceCustom
        }
        return Text(text)
            .font(.system(size: 9))
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Theme.Colors.cardHover)
            .clipShape(Capsule())
    }

    private func listTypeColor(_ type: CommandRule.ListType) -> Color {
        switch type {
        case .blacklist: return Theme.Colors.danger
        case .whitelist: return Theme.Colors.success
        case .unclassified: return Theme.Colors.warning
        }
    }

    // MARK: - Protected Dirs

    private var protectedDirsView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack {
                Text(localizer.protectedDirs)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    panel.prompt = localizer.selectDirectory
                    if panel.runModal() == .OK, let url = panel.urls.first {
                        service.guardFeature.addProtectedDir(url.path)
                    }
                } label: {
                    Label(localizer.addProtectedDir, systemImage: "plus.circle.fill")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.plain)
            }

            if service.guardFeature.protectedDirs.isEmpty {
                emptyStateView(icon: "folder.badge.eye", message: localizer.noProtectedDirs, hint: localizer.noProtectedDirsHint, color: Theme.Colors.info)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(service.guardFeature.protectedDirs, id: \.self) { dir in
                        protectedDirRow(dir)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Dashboard Trend Chart

    private var dashboardTrendChart: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(localizer.hourlyTrend)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                HStack(spacing: 2) {
                    chartRangeButton(title: localizer.rangeRealtime, index: 0)
                    chartRangeButton(title: localizer.rangeToday, index: 1)
                    chartRangeButton(title: localizer.rangeAll, index: 2)
                }
                Divider().frame(height: 14)
                HStack(spacing: Theme.Spacing.sm) {
                    Button { showCreateOps.toggle() } label: {
                        HStack(spacing: 3) {
                            Circle().fill(showCreateOps ? Color.green : Color.gray.opacity(0.4)).frame(width: 7, height: 7)
                            Text(localizer.createOps).font(.system(size: 10)).foregroundStyle(showCreateOps ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Button { showModifyOps.toggle() } label: {
                        HStack(spacing: 3) {
                            Circle().fill(showModifyOps ? Color.orange : Color.gray.opacity(0.4)).frame(width: 7, height: 7)
                            Text(localizer.modifyOps).font(.system(size: 10)).foregroundStyle(showModifyOps ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Button { showDeleteOps.toggle() } label: {
                        HStack(spacing: 3) {
                            Circle().fill(showDeleteOps ? Color.red : Color.gray.opacity(0.4)).frame(width: 7, height: 7)
                            Text(localizer.deleteOps).font(.system(size: 10)).foregroundStyle(showDeleteOps ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Button { showReadOps.toggle() } label: {
                        HStack(spacing: 3) {
                            Circle().fill(showReadOps ? Color.blue : Color.gray.opacity(0.4)).frame(width: 7, height: 7)
                            Text(localizer.readOps).font(.system(size: 10)).foregroundStyle(showReadOps ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                    Button { showExecuteOps.toggle() } label: {
                        HStack(spacing: 3) {
                            Circle().fill(showExecuteOps ? Color.purple : Color.gray.opacity(0.4)).frame(width: 7, height: 7)
                            Text(localizer.executeOps).font(.system(size: 10)).foregroundStyle(showExecuteOps ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if filteredStats.isEmpty {
                emptyStateView(icon: "chart.line.uptrend.xyaxis", message: localizer.noData, hint: localizer.startMonitorHint2, color: Theme.Colors.textTertiary)
            } else {
                dashboardChartContent
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func chartRangeButton(title: String, index: Int) -> some View {
        Button { chartTimeRange = index } label: {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(chartTimeRange == index ? Theme.Colors.success : Theme.Colors.textTertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(chartTimeRange == index ? Theme.Colors.success.opacity(0.14) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    private var filteredStats: [HourlyStats] {
        let now = Date()
        if chartTimeRange == 0 {
            return realtimeStats
        }
        let all = service.guardFeature.hourlyStats
        switch chartTimeRange {
        case 1:
            let startOfToday = Calendar.current.startOfDay(for: now)
            return all.filter { $0.hour >= startOfToday }
        default:
            return all
        }
    }

    private var realtimeStats: [HourlyStats] {
        let calendar = Calendar.current
        let endMinute = calendar.dateInterval(of: .minute, for: Date())?.start ?? Date()
        let startMinute = endMinute.addingTimeInterval(-3600)
        let records = service.operationRecords.filter { $0.timestamp >= startMinute && $0.timestamp <= endMinute.addingTimeInterval(60) }
        var buckets: [Date: HourlyStats] = [:]

        for offset in 0...60 {
            guard let minute = calendar.date(byAdding: .minute, value: offset, to: startMinute) else { continue }
            buckets[minute] = HourlyStats(id: ISO8601DateFormatter().string(from: minute), hour: minute)
        }

        for record in records {
            let minute = calendar.dateInterval(of: .minute, for: record.timestamp)?.start ?? record.timestamp
            let id = ISO8601DateFormatter().string(from: minute)
            var stats = buckets[minute] ?? HourlyStats(id: id, hour: minute)
            switch record.operationType {
            case .create: stats.createCount += 1
            case .modify: stats.modifyCount += 1
            case .delete: stats.deleteCount += 1
            case .read: stats.readCount += 1
            case .move: stats.moveCount += 1
            case .rename: stats.renameCount += 1
            case .execute: stats.executeCount += 1
            }
            buckets[minute] = stats
        }

        return buckets.values.sorted { $0.hour < $1.hour }
    }

    private var chartXDomain: ClosedRange<Date> {
        let calendar = Calendar.current
        let now = Date()
        switch chartTimeRange {
        case 0:
            let endMinute = calendar.dateInterval(of: .minute, for: now)?.start ?? now
            return endMinute.addingTimeInterval(-3600)...endMinute
        case 1:
            return calendar.startOfDay(for: now)...now
        default:
            let stats = filteredStats
            guard let first = stats.first?.hour else {
                let end = calendar.dateInterval(of: .hour, for: now)?.start ?? now
                return end.addingTimeInterval(-3600)...end
            }
            let last = max(stats.last?.hour ?? first, now)
            return first...last
        }
    }

    @ViewBuilder
    private var dashboardChartContent: some View {
        let stats = filteredStats
        let yMax = max(1, stats.flatMap { [$0.createCount, $0.modifyCount, $0.deleteCount, $0.readCount, $0.executeCount] }.max() ?? 1) + 1
        let allPoints = stats.flatMap { stat -> [HourlyStatPoint] in
            var pts: [HourlyStatPoint] = []
            if showCreateOps { pts.append(HourlyStatPoint(hour: stat.hour, count: stat.createCount, type: "Create")) }
            if showModifyOps { pts.append(HourlyStatPoint(hour: stat.hour, count: stat.modifyCount, type: "Modify")) }
            if showDeleteOps { pts.append(HourlyStatPoint(hour: stat.hour, count: stat.deleteCount, type: "Delete")) }
            if showReadOps { pts.append(HourlyStatPoint(hour: stat.hour, count: stat.readCount, type: "Read")) }
            if showExecuteOps { pts.append(HourlyStatPoint(hour: stat.hour, count: stat.executeCount, type: "Execute")) }
            return pts
        }
        let activeDomain = allPoints.map(\.type).reduce(into: Set<String>()) { $0.insert($1) }.sorted()
        let colorMap: [String: Color] = ["Create": .green, "Modify": .orange, "Delete": .red, "Read": .blue, "Execute": .purple]
        let activeRange = activeDomain.compactMap { colorMap[$0] }
        let hoverPoints = nearestChartPoints(in: allPoints, to: chartHoverDate)

        let strideCount: Int = {
            switch chartTimeRange {
            case 2: return stats.count > 48 ? 12 : (stats.count > 24 ? 6 : 3)
            case 1: return stats.count > 12 ? 3 : 1
            case 0: return 1
            default: return 3
            }
        }()

        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            chartHoverSummaryBar(points: hoverPoints)

            Chart {
                ForEach(allPoints) { point in
                    LineMark(
                        x: .value(localizer.hour, point.hour),
                        y: .value(localizer.opsCount, point.count)
                    )
                    .foregroundStyle(by: .value("Type", point.type))
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    if hoverPoints.contains(where: { $0.id == point.id }) {
                        PointMark(
                            x: .value(localizer.hour, point.hour),
                            y: .value(localizer.opsCount, point.count)
                        )
                        .foregroundStyle(by: .value("Type", point.type))
                        .symbolSize(42)
                    }
                }

                if let firstHoverPoint = hoverPoints.first {
                    RuleMark(x: .value(localizer.hour, firstHoverPoint.hour))
                        .foregroundStyle(Theme.Colors.textSecondary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartForegroundStyleScale(domain: activeDomain, range: activeRange)
            .chartXScale(domain: chartXDomain)
            .chartYScale(domain: 0...yMax)
            .chartLegend(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.15))
                    AxisValueLabel().font(.system(size: 9))
                }
            }
            .chartXAxis {
                if chartTimeRange == 0 {
                    AxisMarks(values: .stride(by: .minute, count: 10)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.15))
                        AxisValueLabel(anchor: .top) {
                            if let date = value.as(Date.self) {
                                Text(chartAxisTimeLabel(date))
                                    .font(.system(size: 9))
                            }
                        }
                    }
                } else {
                    AxisMarks(values: .stride(by: .hour, count: strideCount)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.15))
                        AxisValueLabel(anchor: .top) {
                            if let date = value.as(Date.self) {
                                Text(chartAxisTimeLabel(date))
                                    .font(.system(size: chartTimeRange == 2 ? 8 : 9))
                            }
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                let plotFrame = geometry[proxy.plotAreaFrame]
                                let x = location.x - plotFrame.origin.x
                                guard x >= 0, x <= plotFrame.width,
                                      let date: Date = proxy.value(atX: x) else {
                                    chartHoverDate = nil
                                    return
                                }
                                chartHoverDate = nearestChartDate(in: allPoints, to: date)
                            case .ended:
                                chartHoverDate = nil
                            }
                        }
                }
            }
            .frame(minHeight: 190, maxHeight: 240)
        }
        .padding(.bottom, 8)
    }

    private func nearestChartDate(in points: [HourlyStatPoint], to date: Date) -> Date? {
        points.min { lhs, rhs in
            abs(lhs.hour.timeIntervalSince(date)) < abs(rhs.hour.timeIntervalSince(date))
        }?.hour
    }

    private func nearestChartPoints(in points: [HourlyStatPoint], to date: Date?) -> [HourlyStatPoint] {
        guard let date = date else { return [] }
        let sameTime = points.filter { abs($0.hour.timeIntervalSince(date)) < 0.5 }
        return sameTime.sorted { chartTypeSortIndex($0.type) < chartTypeSortIndex($1.type) }
    }

    private func chartHoverSummaryBar(points: [HourlyStatPoint]) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let date = points.first?.hour {
                Text(chartHoverTimeLabel(date))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(minWidth: 72, alignment: .leading)
            } else {
                Text(" ")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(minWidth: 72, alignment: .leading)
            }

            ForEach(points) { point in
                HStack(spacing: 4) {
                    Circle()
                        .fill(chartColor(for: point.type))
                        .frame(width: 6, height: 6)
                    Text(chartLabel(for: point.type))
                        .font(.system(size: 9))
                    Text("\(point.count)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(Theme.Colors.textPrimary)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 28)
        .padding(.horizontal, 10)
        .background(points.isEmpty ? Theme.Colors.cardHover.opacity(0.5) : Theme.Colors.cardHover)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private func chartTypeSortIndex(_ type: String) -> Int {
        switch type {
        case "Create": return 0
        case "Modify": return 1
        case "Delete": return 2
        case "Read": return 3
        case "Execute": return 4
        default: return 99
        }
    }

    private func chartColor(for type: String) -> Color {
        switch type {
        case "Create": return .green
        case "Modify": return .orange
        case "Delete": return .red
        case "Read": return .blue
        case "Execute": return .purple
        default: return .secondary
        }
    }

    private func chartLabel(for type: String) -> String {
        switch type {
        case "Create": return localizer.createOps
        case "Modify": return localizer.modifyOps
        case "Delete": return localizer.deleteOps
        case "Read": return localizer.readOps
        case "Execute": return localizer.executeOps
        default: return type
        }
    }

    private func chartHoverTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = chartTimeRange == 2 ? .short : .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func chartAxisTimeLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.calendar = Calendar.current
        formatter.timeZone = .current
        formatter.dateFormat = chartTimeRange == 2 ? "MM-dd HH:mm" : "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Audit Report Sheet

    private func showCommandToast(_ action: String) {
        toastTask?.cancel()
        toastMessage = "\(action) ✓"
        withAnimation { showToast = true }
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { showToast = false }
        }
    }

    private func generateReport() {
        let now = Date()
        let startTime: Date
        switch reportPeriod {
        case 0: startTime = now.addingTimeInterval(-86400)
        case 1: startTime = now.addingTimeInterval(-604800)
        case 2: startTime = now.addingTimeInterval(-2592000)
        default: startTime = .distantPast
        }
        generatedReport = service.guardFeature.generateAuditReport(
            records: service.operationRecords,
            startTime: startTime,
            endTime: now
        )
        showReportSheet = true
    }

    // MARK: - Helper Views

    private func alertRow(_ alert: GuardAlert) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: alert.severity.icon)
                .font(.system(size: 12))
                .foregroundStyle(severityColor(alert.severity))
            Text(alert.title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(alert.timestamp, style: .time)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            if !alert.isRead {
                Circle()
                    .fill(Theme.Colors.danger)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(alert.isRead ? Color.clear : severityColor(alert.severity).opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .onTapGesture {
            service.guardFeature.markAlertRead(alert.id)
        }
    }

    private func alertDetailRow(_ alert: GuardAlert) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: alert.severity.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(severityColor(alert.severity))
                Text(alert.title)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text(alert.timestamp, style: .time)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .monospacedDigit()
                if !alert.isRead {
                    Circle()
                        .fill(Theme.Colors.danger)
                        .frame(width: 6, height: 6)
                }
            }
            Text(alert.message)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !alert.detail.isEmpty {
                Text(alert.detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "person.fill")
                    .font(.system(size: 9))
                Text(alert.agentName)
                    .font(Theme.Font.caption)
                    .lineLimit(1)
                if !alert.targetPath.isEmpty {
                    Text("·")
                    Image(systemName: "doc.fill")
                        .font(.system(size: 9))
                    Text((alert.targetPath as NSString).lastPathComponent)
                        .font(Theme.Font.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background(alert.isRead ? Theme.Colors.cardBg : severityColor(alert.severity).opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .onTapGesture {
            service.guardFeature.markAlertRead(alert.id)
        }
    }

    private func severityColor(_ severity: GuardAlert.AlertSeverity) -> Color {
        switch severity {
        case .info: return Theme.Colors.info
        case .warning: return Theme.Colors.warning
        case .critical: return Theme.Colors.danger
        }
    }

    private func severityFilterChip(label: String, severity: GuardAlert.AlertSeverity?) -> some View {
        Button {
            alertFilter = severity
        } label: {
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(alertFilter == severity ? .white : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(alertFilter == severity ? (severity == nil ? Theme.Colors.success : severityColor(severity!)) : Theme.Colors.cardBg)
                )
        }
        .buttonStyle(.plain)
    }

    private func emptyStateView(icon: String, message: String, hint: String, color: Color) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(color.opacity(0.5))
            Text(message)
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(hint)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }

    private func ruleSection<Content: View>(title: String, description: String = "", @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            if !description.isEmpty {
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func toggleRule(title: String, description: String = "", isOn: Binding<Bool>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: isOn)
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            if !description.isEmpty {
                Text(description)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Theme.Colors.success)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Color.white.opacity(0.24), lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func protectedDirRow(_ dir: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "folder.fill.badge.eye")
                .font(.system(size: 12))
                .foregroundStyle(Theme.Colors.warning)
            Text(dir)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button {
                service.guardFeature.removeProtectedDir(dir)
            } label: {
                Text(localizer.removeDir)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

// MARK: - Supporting Views

struct SegmentButton: View {
    let title: String
    let icon: String
    let index: Int
    let tint: Color
    @Binding var selected: Int

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                selected = index
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: selected == index ? .semibold : .medium))
                Text(title)
                    .font(.system(size: 11, weight: selected == index ? .semibold : .regular))
            }
            .foregroundStyle(selected == index ? .white : Theme.Colors.textTertiary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(selected == index ? tint : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 100)
        .padding(.vertical, Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.Colors.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(color.opacity(0.15), lineWidth: 1)
        )
    }
}
