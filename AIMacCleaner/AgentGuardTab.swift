import SwiftUI
import Charts
import AppKit
import UserNotifications

struct AgentGuardTab: View {
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var service: ScannerService
    @State private var selectedSegment = 0
    @State private var alertFilter: GuardAlert.AlertSeverity?
    @State private var reportPeriod = 0
    @State private var showReportSheet = false
    @State private var generatedReport: AuditReport?
    @State private var newBlacklistPattern = ""
    @State private var newWhitelistPattern = ""

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "eye.circle.fill",
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
                case 5: trendChartView
                default: dashboardView
                }
            }
        }
    }

    private var segmentPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                SegmentButton(title: localizer.guardDashboard, icon: "gauge", index: 0, selected: $selectedSegment)
                SegmentButton(title: localizer.alertCenter, icon: "bell.badge", index: 1, selected: $selectedSegment)
                SegmentButton(title: localizer.alertRules, icon: "slider.horizontal.3", index: 2, selected: $selectedSegment)
                SegmentButton(title: localizer.commandRules, icon: "terminal", index: 3, selected: $selectedSegment)
                SegmentButton(title: localizer.protectedDirs, icon: "folder.badge.eye", index: 4, selected: $selectedSegment)
                SegmentButton(title: localizer.trendChart, icon: "chart.line.uptrend.xyaxis", index: 5, selected: $selectedSegment)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.background)
    }

    // MARK: - Dashboard

    private var dashboardView: some View {
        VStack(spacing: Theme.Spacing.lg) {
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

            recentAlertsPreview

            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                quickActionsCard
                processLifecycleCard
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
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

            VStack(spacing: Theme.Spacing.sm) {
                actionButton(title: localizer.exportCSV, icon: "doc.text") {
                    let csv = service.guardFeature.exportRecordsAsCSV(records: service.operationRecords)
                    service.guardFeature.saveExport(content: csv, filename: "agent_operations.csv")
                }
                actionButton(title: localizer.exportJSON, icon: "doc.richtext") {
                    let json = service.guardFeature.exportRecordsAsJSON(records: service.operationRecords)
                    service.guardFeature.saveExport(content: json, filename: "agent_operations.json")
                }
                actionButton(title: localizer.exportAlertsCSV, icon: "bell.and.text") {
                    let csv = service.guardFeature.exportAlertsAsCSV()
                    service.guardFeature.saveExport(content: csv, filename: "agent_alerts.csv")
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

    private var processLifecycleCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(localizer.processLifecycle)
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)

            if service.guardFeature.processLifecycleEvents.isEmpty {
                Text(localizer.noData)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(service.guardFeature.processLifecycleEvents.prefix(8)) { event in
                        lifecycleRow(event)
                    }
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
            ruleSection(title: localizer.batchDeleteThreshold) {
                HStack {
                    Slider(value: Binding(
                        get: { Double(service.guardFeature.alertRule.batchDeleteThreshold) },
                        set: { service.guardFeature.alertRule.batchDeleteThreshold = Int($0); service.guardFeature.saveAlertRule() }
                    ), in: 2...50, step: 1)
                    Text("\(service.guardFeature.alertRule.batchDeleteThreshold)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 30)
                }
            }

            ruleSection(title: localizer.batchModifyThreshold) {
                HStack {
                    Slider(value: Binding(
                        get: { Double(service.guardFeature.alertRule.batchModifyThreshold) },
                        set: { service.guardFeature.alertRule.batchModifyThreshold = Int($0); service.guardFeature.saveAlertRule() }
                    ), in: 2...100, step: 1)
                    Text("\(service.guardFeature.alertRule.batchModifyThreshold)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 30)
                }
            }

            ruleSection(title: localizer.timeWindowSeconds) {
                HStack {
                    Slider(value: Binding(
                        get: { service.guardFeature.alertRule.batchTimeWindowSeconds },
                        set: { service.guardFeature.alertRule.batchTimeWindowSeconds = $0; service.guardFeature.saveAlertRule() }
                    ), in: 5...300, step: 5)
                    Text("\(Int(service.guardFeature.alertRule.batchTimeWindowSeconds))s")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 40)
                }
            }

            ruleSection(title: localizer.alertCooldown) {
                HStack {
                    Slider(value: Binding(
                        get: { service.guardFeature.alertRule.alertCooldownSeconds },
                        set: { service.guardFeature.alertRule.alertCooldownSeconds = $0; service.guardFeature.saveAlertRule() }
                    ), in: 10...600, step: 10)
                    Text("\(Int(service.guardFeature.alertRule.alertCooldownSeconds))s")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 40)
                }
            }

            Divider()

            toggleRule(title: localizer.enableSensitiveFile, isOn: Binding(
                get: { service.guardFeature.alertRule.sensitiveFileDetectionEnabled },
                set: { service.guardFeature.alertRule.sensitiveFileDetectionEnabled = $0; service.guardFeature.saveAlertRule() }
            ))

            toggleRule(title: localizer.enableSensitiveContent, isOn: Binding(
                get: { service.guardFeature.alertRule.sensitiveContentDetectionEnabled },
                set: { service.guardFeature.alertRule.sensitiveContentDetectionEnabled = $0; service.guardFeature.saveAlertRule() }
            ))

            toggleRule(title: localizer.enableProcessAlert, isOn: Binding(
                get: { service.guardFeature.alertRule.processLaunchAlertEnabled },
                set: { service.guardFeature.alertRule.processLaunchAlertEnabled = $0; service.guardFeature.saveAlertRule() }
            ))

            toggleRule(title: localizer.enableProtectedDir, isOn: Binding(
                get: { service.guardFeature.alertRule.protectedDirAlertEnabled },
                set: { service.guardFeature.alertRule.protectedDirAlertEnabled = $0; service.guardFeature.saveAlertRule() }
            ))

            toggleRule(title: localizer.enableNotification, isOn: Binding(
                get: { service.guardFeature.alertRule.notificationEnabled },
                set: { service.guardFeature.alertRule.notificationEnabled = $0; service.guardFeature.saveAlertRule() }
            ))

            Divider()

            toggleRule(title: localizer.doNotDisturb, isOn: Binding(
                get: { service.guardFeature.alertRule.doNotDisturbEnabled },
                set: { service.guardFeature.alertRule.doNotDisturbEnabled = $0; service.guardFeature.saveAlertRule() }
            ))

            if service.guardFeature.alertRule.doNotDisturbEnabled {
                HStack {
                    Text(localizer.dndTimeRange)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { service.guardFeature.alertRule.doNotDisturbStartHour },
                        set: { service.guardFeature.alertRule.doNotDisturbStartHour = $0; service.guardFeature.saveAlertRule() }
                    )) {
                        ForEach(0..<24, id: \.self) { (h: Int) in
                            Text(String(format: "%02d:00", h)).tag(h)
                        }
                    }
                    .frame(width: 80)
                    Text("—")
                    Picker("", selection: Binding(
                        get: { service.guardFeature.alertRule.doNotDisturbEndHour },
                        set: { service.guardFeature.alertRule.doNotDisturbEndHour = $0; service.guardFeature.saveAlertRule() }
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
            toggleRule(title: localizer.enableCommandBlacklist, isOn: Binding(
                get: { service.guardFeature.alertRule.commandBlacklistEnabled },
                set: { service.guardFeature.alertRule.commandBlacklistEnabled = $0; service.guardFeature.saveAlertRule() }
            ))

            if service.guardFeature.alertRule.commandBlacklistEnabled {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Text(localizer.commandBlacklist)
                            .font(Theme.Font.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("(\(service.guardFeature.commandBlacklist.count))")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Spacer()
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        TextField(localizer.newCommandPattern, text: $newBlacklistPattern)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.Font.caption)
                            .onSubmit {
                                if !newBlacklistPattern.isEmpty {
                                    service.guardFeature.addBlacklistRule(pattern: newBlacklistPattern, severity: .warning)
                                    newBlacklistPattern = ""
                                }
                            }
                        Button {
                            if !newBlacklistPattern.isEmpty {
                                service.guardFeature.addBlacklistRule(pattern: newBlacklistPattern, severity: .warning)
                                newBlacklistPattern = ""
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(service.guardFeature.commandBlacklist) { rule in
                        commandRuleRow(rule: rule, isBlacklist: true)
                    }
                }
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }

            Divider()

            toggleRule(title: localizer.enableCommandWhitelist, isOn: Binding(
                get: { service.guardFeature.alertRule.commandWhitelistEnabled },
                set: { service.guardFeature.alertRule.commandWhitelistEnabled = $0; service.guardFeature.saveAlertRule() }
            ))

            if service.guardFeature.alertRule.commandWhitelistEnabled {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack {
                        Text(localizer.commandWhitelist)
                            .font(Theme.Font.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text("(\(service.guardFeature.commandWhitelist.count))")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Spacer()
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        TextField(localizer.newCommandPattern, text: $newWhitelistPattern)
                            .textFieldStyle(.roundedBorder)
                            .font(Theme.Font.caption)
                            .onSubmit {
                                if !newWhitelistPattern.isEmpty {
                                    service.guardFeature.addWhitelistRule(pattern: newWhitelistPattern)
                                    newWhitelistPattern = ""
                                }
                            }
                        Button {
                            if !newWhitelistPattern.isEmpty {
                                service.guardFeature.addWhitelistRule(pattern: newWhitelistPattern)
                                newWhitelistPattern = ""
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.Colors.success)
                        }
                        .buttonStyle(.plain)
                    }

                    if service.guardFeature.commandWhitelist.isEmpty {
                        Text(localizer.noWhitelistRules)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    } else {
                        ForEach(service.guardFeature.commandWhitelist) { rule in
                            commandRuleRow(rule: rule, isBlacklist: false)
                        }
                    }
                }
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private func commandRuleRow(rule: CommandRule, isBlacklist: Bool) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: isBlacklist ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(isBlacklist ? severityColor(rule.severity) : Theme.Colors.success)
            Text(rule.pattern)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
            if !rule.note.isEmpty {
                Text("— \(rule.note)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer()
            if isBlacklist {
                Image(systemName: rule.severity.icon)
                    .font(.system(size: 10))
                    .foregroundStyle(severityColor(rule.severity))
            }
            Button {
                if isBlacklist {
                    service.guardFeature.removeBlacklistRule(id: rule.id)
                } else {
                    service.guardFeature.removeWhitelistRule(id: rule.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.danger)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(isBlacklist ? severityColor(rule.severity).opacity(0.04) : Theme.Colors.success.opacity(0.04))
        )
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
                    ForEach(Array(service.guardFeature.protectedDirs.enumerated()), id: \.offset) { index, dir in
                        protectedDirRow(dir)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Trend Chart

    private var trendChartView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Text(localizer.hourlyTrend)
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if service.guardFeature.hourlyStats.isEmpty {
                emptyStateView(icon: "chart.line.uptrend.xyaxis", message: localizer.noData, hint: localizer.startMonitorHint2, color: Theme.Colors.textTertiary)
            } else {
                let recentStats = Array(service.guardFeature.hourlyStats.suffix(48))
                Chart {
                    ForEach(recentStats) { stat in
                        BarMark(
                            x: .value("Hour", stat.hour, unit: .hour),
                            y: .value(localizer.createOps, stat.createCount)
                        )
                        .foregroundStyle(Color.green.opacity(0.6))

                        BarMark(
                            x: .value("Hour", stat.hour, unit: .hour),
                            y: .value(localizer.modifyOps, stat.modifyCount)
                        )
                        .foregroundStyle(Color.orange.opacity(0.6))

                        BarMark(
                            x: .value("Hour", stat.hour, unit: .hour),
                            y: .value(localizer.deleteOps, stat.deleteCount)
                        )
                        .foregroundStyle(Color.red.opacity(0.6))
                    }
                }
                .chartForegroundStyleScale([
                    localizer.createOps: Color.green.opacity(0.6),
                    localizer.modifyOps: Color.orange.opacity(0.6),
                    localizer.deleteOps: Color.red.opacity(0.6)
                ])
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisValueLabel()
                            .font(.system(size: 9))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.hour())
                            .font(.system(size: 9))
                    }
                }
                .frame(minHeight: 200, maxHeight: 280)
                .padding(Theme.Spacing.lg)
                .background(Theme.Colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                HStack(spacing: Theme.Spacing.lg) {
                    legendItem(color: .green, label: localizer.createOps)
                    legendItem(color: .orange, label: localizer.modifyOps)
                    legendItem(color: .red, label: localizer.deleteOps)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    // MARK: - Audit Report Sheet

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
                        .fill(alertFilter == severity ? (severity == nil ? Theme.Colors.accent : severityColor(severity!)) : Theme.Colors.cardBg)
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

    private func ruleSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            content()
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func toggleRule(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title)
                    .font(Theme.Font.caption)
            }
            .foregroundStyle(Theme.Colors.accent)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Theme.Colors.accent.opacity(0.08))
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

    private func lifecycleRow(_ event: ProcessLifecycleEvent) -> some View {
        let isLaunch = event.eventType == .launch
        return HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: isLaunch ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(isLaunch ? Theme.Colors.success : Theme.Colors.textTertiary)
            Text(event.agentName)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Spacer()
            Text(event.comm)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
            Text(event.timestamp, style: .time)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
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
            .foregroundStyle(selected == index ? Theme.Colors.warning : Theme.Colors.textTertiary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(selected == index ? Theme.Colors.warning.opacity(0.1) : Color.clear)
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
