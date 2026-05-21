import SwiftUI

struct MenuBarMonitor: View {
    @ObservedObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @State private var selectedTab: MonitorTab = .operations
    @AppStorage("networkMode") private var networkMode = "internet"
    @State private var alertThreshold: Double = 10.0
    @State private var monitoringEnabled: Bool = true
    @State private var operationMonitorEnabled: Bool = false
    @State private var trashInsteadOfDelete: Bool = true
    @State private var preventAutoEmptyTrash: Bool = true

    enum MonitorTab: String, CaseIterable {
        case operations = "operations"
        case overview = "overview"

        func label(_ localizer: Localizer) -> String {
            switch self {
            case .operations: return localizer.agentMonitorTitle
            case .overview: return localizer.systemMonitorTitle
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()

            switch selectedTab {
            case .overview:
                overviewContent
            case .operations:
                operationsContent
            }

            Divider()
            popoverFooter
        }
        .frame(width: 360)
        .onAppear {
            loadSettings()
            if monitoringEnabled { service.startMonitoring() }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MonitorTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.spring(duration: 0.3)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab == .operations ? "chart.bar" : "gauge.open.with.lines.needle.84percent")
                            .font(Theme.Font.caption)
                        Text(tab.label(localizer))
                            .font(Theme.Font.captionMedium)
                    }
                    .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 1)
                    .background {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .fill(Theme.Gradients.accent)
                        } else {
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .fill(Color.clear)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.Colors.cardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
    }

    private var popoverFooter: some View {
        VStack(spacing: 0) {
            if service.isDownloadingUpdate {
                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundStyle(Theme.Colors.info)
                            .font(Theme.Font.caption)
                        Text(String(format: "\(localizer.downloadingUpdateFmt) %.0f%%", service.updateDownloadProgress * 100))
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Spacer()
                        Button {
                            service.cancelUpdateDownload()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .font(Theme.Font.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    ProgressView(value: service.updateDownloadProgress)
                        .progressViewStyle(.linear)
                        .tint(Theme.Colors.info)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.info.opacity(0.05))
            } else if service.isInstallingUpdate {
                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                        Text(localizer.installingUpdate)
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.warning)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.warning.opacity(0.05))
            } else if service.updateReadyToInstall {
                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.Colors.success)
                        Text(localizer.updateDownloaded)
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                    Button {
                        service.installUpdate()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundStyle(.white)
                            Text("\(localizer.quitAndInstall) v\(service.latestVersion)")
                                .foregroundStyle(.white)
                                .font(Theme.Font.captionMedium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Gradients.success)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
                .background(Theme.Colors.success.opacity(0.05))
            } else if !service.updateErrorMessage.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.warning)
                        Text(service.updateErrorMessage)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.warning)
                        Spacer()
                        Button {
                            service.updateErrorMessage = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .font(Theme.Font.caption)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        service.downloadUpdate()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text(localizer.retryDownload)
                        }
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
            } else if service.updateAvailable {
                Button {
                    service.downloadUpdate()
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("\(localizer.updateToVersion) v\(service.latestVersion)")
                    }
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Gradients.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.sm)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.title.contains("AgentGuard") || $0.title.contains("Agent卫士") || (!$0.title.isEmpty && $0.className.contains("Window")) }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let menuWindow = NSApp.windows.first(where: { $0.isFloatingPanel || $0.level == .floating }) {
                            menuWindow.orderOut(nil)
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "arrow.down.doc.fill")
                        Text(localizer.openAIMacCleaner)
                    }
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xs + 1)
                    .background(Theme.Colors.accent.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await service.checkForUpdates() }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text(localizer.checkForUpdate)
                    }
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.xs + 1)
                    .background(Theme.Colors.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(service.isCheckingUpdate || service.isDownloadingUpdate)
                .opacity(service.isCheckingUpdate || service.isDownloadingUpdate ? 0.5 : 1)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.sm)

            HStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.xs) {
                    Circle()
                        .fill(networkMode == "internet" ? Theme.Colors.success : Theme.Colors.warning)
                        .frame(width: 5, height: 5)
                    Text(networkMode == "internet" ? localizer.internetStatus : localizer.offlineStatus)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                Text("v\(service.currentVersion)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)

                Spacer()

                Button {
                    withAnimation(.none) {
                        localizer.language = localizer.language == .simplifiedChinese ? .english : .simplifiedChinese
                    }
                } label: {
                    Text(localizer.langToggleText)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Theme.Colors.accent.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)

                Button {
                    let behavior = UserDefaults.standard.string(forKey: "quitBehavior") ?? "quitAll"
                    if behavior == "quitAppKeepMenu" {
                        for window in NSApp.windows where !window.isFloatingPanel && window.level != .floating {
                            window.orderOut(nil)
                        }
                        NSApp.setActivationPolicy(.accessory)
                    } else {
                        for window in NSApp.windows {
                            window.orderOut(nil)
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            NSApp.terminate(nil)
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "power")
                        Text(localizer.quitApp)
                    }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 2)
                    .background(Theme.Colors.danger.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private var overviewContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                hardwareOverview
                Divider()
                diskOverview
                Divider()
                monitoringSettings
                Divider()
                safetySettings
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var operationsContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                operationStatsHeader
                Divider()
                operationAgentStats
                Divider()
                operationTypeStats
                Divider()
                recentOperations
                Divider()
                operationControlBar
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var hardwareOverview: some View {
        VStack(spacing: Theme.Spacing.md) {
            SectionHeader(title: localizer.hardwareMonitor, icon: "gauge.open.with.lines.needle.84percent")

            if let hw = service.hardwareInfo {
                DashboardGrid(columns: 2, spacing: Theme.Spacing.sm) {
                    VStack(spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "cpu")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.statusColor(for: hw.cpuUsage / 100.0))
                            Text(localizer.cpuLabel)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text(String(format: "%.0f%%", hw.cpuUsage))
                            .font(Theme.Font.title2Bold)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.statusColor(for: hw.cpuUsage / 100.0))
                        Text("\(hw.cpuCoreCount) " + localizer.coresLabel)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .cardStyle(padding: Theme.Spacing.md)

                    VStack(spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "memorychip")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.statusColor(for: hw.memoryPressurePct / 100.0))
                            Text(localizer.memoryLabel)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text(String(format: "%.0f%%", hw.memoryPressurePct))
                            .font(Theme.Font.title2Bold)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.statusColor(for: hw.memoryPressurePct / 100.0))
                        Text(String(format: "%.1f/%.0fG", hw.memoryUsedGb, hw.memoryTotalGb))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .cardStyle(padding: Theme.Spacing.md)

                    if let temp = hw.cpuTemperature {
                        VStack(spacing: Theme.Spacing.xs) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "thermometer.medium")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Colors.statusColor(for: min(temp / 100.0, 1.0)))
                                Text(localizer.cpuTempLabel)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Text(String(format: "%.0f°C", temp))
                                .font(Theme.Font.title2Bold)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.statusColor(for: min(temp / 100.0, 1.0)))
                            Text(temp > 80 ? localizer.overheating : temp > 60 ? localizer.high : localizer.normal)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .cardStyle(padding: Theme.Spacing.md)
                    }

                    if let battery = hw.batteryPercent {
                        VStack(spacing: Theme.Spacing.xs) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: hw.batteryCharging ? "battery.100.bolt" : "battery.75")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Colors.statusColor(for: 1.0 - battery / 100.0))
                                Text(localizer.batteryLabel)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Text(String(format: "%.0f%%", battery))
                                .font(Theme.Font.title2Bold)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.statusColor(for: 1.0 - battery / 100.0))
                            Text(hw.batteryCharging ? localizer.charging : (hw.batteryTimeRemaining.map { "\($0)\(localizer.minuteUnit)" } ?? localizer.inUse))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .cardStyle(padding: Theme.Spacing.md)
                    }

                    VStack(spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.teal)
                            Text(localizer.networkLabel)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text("↓\(hw.networkInFormatted)")
                            .font(Theme.Font.title2Bold)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.teal)
                        Text("↑\(hw.networkOutFormatted)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .cardStyle(padding: Theme.Spacing.md)
                }

                HStack(spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "app.badge")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text("\(hw.processCount) \(localizer.processesLabel)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "arrow.up.arrow.down.circle")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text("\(hw.threadCount) \(localizer.threadsLabel)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "clock")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text("\(localizer.runtimeLabel) \(hw.uptimeFormatted)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            } else {
                Text(localizer.gettingHardwareInfo)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.lg)
    }

    private var diskOverview: some View {
        VStack(spacing: Theme.Spacing.md) {
            SectionHeader(title: localizer.diskSpaceLabel, icon: "internaldrive")

            if let disk = service.diskInfo {
                HStack(spacing: Theme.Spacing.lg) {
                    ProgressRing(
                        progress: disk.usedPct / 100.0,
                        lineWidth: 6,
                        size: 56,
                        color: diskColor(pct: disk.usedPct)
                    )

                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizer.usedLabel)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(String(format: "%.0f GB / %.0f GB", disk.usedGb, disk.totalGb))
                                .font(Theme.Font.subheadlineMedium)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.textPrimary)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizer.available)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(String(format: "%.0f GB", disk.freeGb))
                                .font(Theme.Font.subheadlineMedium)
                                .monospacedDigit()
                                .foregroundStyle(disk.freeGb < 20 ? Theme.Colors.danger : Theme.Colors.success)
                        }
                    }
                }
                .cardStyle(padding: Theme.Spacing.md)

                if disk.freeGb < Double(100 * Int(alertThreshold) / 100) || disk.usedPct > (100 - alertThreshold) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.Colors.warning)
                        Text(localizer.storageWarning)
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.warning)
                    }
                    .padding(Theme.Spacing.sm)
                    .frame(maxWidth: .infinity)
                    .background(Theme.Colors.warning.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            } else {
                Text(localizer.scanning)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.lg)
    }

    private var monitoringSettings: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: "bell.badge")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.warning)
                Text(localizer.storageAlert)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $monitoringEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: monitoringEnabled) { newValue in
                        if newValue {
                            service.startMonitoring()
                        } else {
                            service.stopMonitoring()
                        }
                        saveSettings()
                    }
            }

            if monitoringEnabled {
                HStack {
                    Text(localizer.alertThresholdLabel)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Text("\(localizer.remainingLabel) \(Int(alertThreshold))%")
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.warning)
                }

                Slider(value: $alertThreshold, in: 5...30, step: 5) {
                    Text(localizer.thresholdLabel)
                }
                .controlSize(.small)
                .tint(Theme.Colors.warning)
                .onChange(of: alertThreshold) { _ in
                    service.alertThreshold = alertThreshold
                    saveSettings()
                }
            }
        }
        .cardStyle(padding: Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private var safetySettings: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: "eye.fill")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.purple)
                Text(localizer.opMonitorLabel)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $operationMonitorEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: operationMonitorEnabled) { _ in saveSettings() }
            }

            HStack {
                Image(systemName: "trash")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.info)
                Text(localizer.moveToTrash)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $trashInsteadOfDelete)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: trashInsteadOfDelete) { _ in
                        service.trashInsteadOfDelete = trashInsteadOfDelete
                        saveSettings()
                    }
            }

            HStack {
                Image(systemName: "trash.slash")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.danger)
                Text(localizer.preventAutoEmptyTrash)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Toggle("", isOn: $preventAutoEmptyTrash)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: preventAutoEmptyTrash) { _ in
                        service.preventAutoEmptyTrash = preventAutoEmptyTrash
                        saveSettings()
                    }
            }
        }
        .cardStyle(padding: Theme.Spacing.md)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.bottom, Theme.Spacing.lg)
    }

    // MARK: - Operation Monitor Tab

    private var operationStatsHeader: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack {
                SectionHeader(title: localizer.opStatsLabel, icon: "chart.bar")
                if operationMonitorEnabled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Theme.Colors.success)
                            .frame(width: 5, height: 5)
                        Text(localizer.monitoringLabel)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.success)
                    }
                } else {
                    Text(localizer.notEnabledLabel)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            HStack(spacing: Theme.Spacing.xs) {
                compactStatCard(
                    icon: "list.bullet",
                    iconColor: Theme.Colors.info,
                    title: localizer.totalOpsLabel,
                    value: "\(service.operationRecords.count)"
                )
                compactStatCard(
                    icon: "clock",
                    iconColor: Theme.Colors.success,
                    title: localizer.todayLabel,
                    value: "\(todayOperationCount)"
                )
                compactStatCard(
                    icon: "flame.fill",
                    iconColor: Theme.Colors.warning,
                    title: localizer.hourLabel,
                    value: "\(hourOperationCount)"
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    private func compactStatCard(icon: String, iconColor: Color, title: String, value: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(Theme.Font.caption)
                .foregroundStyle(iconColor)
            Text(value)
                .font(Theme.Font.subheadlineMedium)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.sm)
        .background(iconColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var operationAgentStats: some View {
        VStack(spacing: Theme.Spacing.xs) {
            SectionHeader(title: localizer.agentActivityLabel, icon: "cpu")

            if agentStats.isEmpty {
                Text(localizer.noOpRecordsLabel)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.vertical, Theme.Spacing.xs)
            } else {
                agentStatsList
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var agentStatsList: some View {
        let stats = topAgentStats
        return VStack(spacing: Theme.Spacing.xs) {
            ForEach(stats.map { $0.name }, id: \.self) { name in
                if let stat = stats.first(where: { $0.name == name }) {
                    agentStatRow(stat)
                }
            }
        }
    }

    private func agentStatRow(_ stat: AgentStat) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(stat.name)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 90, alignment: .leading)

            GeometryReader { geo in
                let maxCount = agentStats.first?.count ?? 1
                let ratio = CGFloat(stat.count) / CGFloat(max(maxCount, 1))
                RoundedRectangle(cornerRadius: 3)
                    .fill(agentStatColor(index: stat.index).opacity(0.7))
                    .frame(width: max(geo.size.width * ratio, 4), height: 10)
            }
            .frame(height: 10)

            Text("\(stat.count)")
                .font(Theme.Font.captionMedium)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 28, alignment: .trailing)
        }
    }

    private var operationTypeStats: some View {
        VStack(spacing: Theme.Spacing.xs) {
            SectionHeader(title: localizer.opTypeDistLabel, icon: "chart.pie")

            if service.operationRecords.isEmpty {
                Text(localizer.noData)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.vertical, Theme.Spacing.xs)
            } else {
                FlowLayout(spacing: Theme.Spacing.xs) {
                    ForEach(Array(typeStats.enumerated()), id: \.offset) { _, stat in
                        HStack(spacing: 3) {
                            Image(systemName: stat.icon)
                                .font(.system(size: 9))
                            Text("\(stat.count) \(stat.label)")
                                .font(.system(size: 10))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .foregroundStyle(stat.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(stat.color.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var recentOperations: some View {
        VStack(spacing: Theme.Spacing.xs) {
            SectionHeader(title: localizer.recentOpsLabel, icon: "clock.arrow.circlepath") {
                if !service.operationRecords.isEmpty {
                    Text("\(service.operationRecords.count) \(localizer.recordsUnit)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            if service.operationRecords.isEmpty {
                VStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "tray")
                        .font(.title3)
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(0.4))
                    Text(localizer.noOpRecordsLabel)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(localizer.startMonitorHint2)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.vertical, Theme.Spacing.sm)
            } else {
                VStack(spacing: 3) {
                    ForEach(recentRecords, id: \.id) { record in
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: record.operationType.icon)
                                .font(.system(size: 10))
                                .foregroundStyle(opTypeColor(record.operationType))
                                .frame(width: 14)

                            Text(record.agentName)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(width: 58, alignment: .leading)
                                .help(record.processName ?? record.agentName)

                            PillBadge(text: record.operationType.localizedLabel(localizer), color: opTypeColor(record.operationType), size: .small)
                                .fixedSize()

                            Text(record.targetPath)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(minWidth: 40)

                            Spacer(minLength: 4)

                            Text(record.timestamp, style: .time)
                                .font(.system(size: 10))
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 4)
                        .background(Theme.Colors.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var operationControlBar: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Button {
                    operationMonitorEnabled.toggle()
                    saveSettings()
                    if operationMonitorEnabled {
                        service.startOperationMonitor()
                    } else {
                        service.stopOperationMonitor()
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: operationMonitorEnabled ? "pause.circle" : "play.circle")
                        Text(operationMonitorEnabled ? localizer.pauseMonitorLabel : localizer.startMonitorLabel)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(operationMonitorEnabled ? Theme.Colors.warning.opacity(0.85) : Theme.Colors.success.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)

                if operationMonitorEnabled {
                    Button {
                        if service.operationMonitor.aiSelfLearningEnabled {
                            service.stopAISelfLearning()
                        } else {
                            service.startAISelfLearning()
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: service.operationMonitor.aiSelfLearningEnabled ? "sparkles" : "brain.head.profile")
                            Text(service.operationMonitor.aiSelfLearningEnabled ? localizer.closeAILabel : localizer.aiAnalysisLabel)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(service.operationMonitor.aiSelfLearningEnabled ? .white : Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(service.operationMonitor.aiSelfLearningEnabled ? Theme.Colors.purple.opacity(0.85) : Theme.Colors.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .stroke(service.operationMonitor.aiSelfLearningEnabled ? Color.clear : Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if !service.operationRecords.isEmpty {
                    Button {
                        service.clearOperationRecords()
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "trash")
                            Text(localizer.clear)
                        }
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.danger.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }

            if operationMonitorEnabled && service.operationMonitor.aiSelfLearningEnabled {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "brain.head.profile")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.purple)
                    Text(localizer.aiSelfLearningStatus)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.purple)
                    Spacer()
                }
            }

            HStack {
                Button {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.title.contains("AgentGuard") || $0.title.contains("Agent卫士") || (!$0.title.isEmpty && $0.className.contains("Window")) }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        if let menuWindow = NSApp.windows.first(where: { $0.isFloatingPanel || $0.level == .floating }) {
                            menuWindow.orderOut(nil)
                        }
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "arrow.up.right.and.arrow.down.left")
                        Text(localizer.viewFullLogLabel)
                    }
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Computed Properties

    private var todayOperationCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return service.operationRecords.filter { $0.timestamp >= start }.count
    }

    private var hourOperationCount: Int {
        service.operationRecords.filter { Date().timeIntervalSince($0.timestamp) < 3600 }.count
    }

    private struct AgentStat: Identifiable {
        let name: String
        let count: Int
        let index: Int
        var id: String { name }
    }

    private var agentStats: [AgentStat] {
        var counts: [String: Int] = [:]
        for record in service.operationRecords {
            counts[record.agentName, default: 0] += 1
        }
        return counts.sorted { $0.value > $1.value }.enumerated().map { index, entry in
            AgentStat(name: entry.key, count: entry.value, index: index)
        }
    }

    private struct TypeStat {
        let label: String
        let icon: String
        let color: Color
        let count: Int
    }

    private var typeStats: [TypeStat] {
        var counts: [OperationRecord.OperationType: Int] = [:]
        for record in service.operationRecords {
            counts[record.operationType, default: 0] += 1
        }
        return OperationRecord.OperationType.allCases.compactMap { type in
            let count = counts[type] ?? 0
            if count > 0 {
                return TypeStat(label: type.localizedLabel(localizer), icon: type.icon, color: opTypeColor(type), count: count)
            }
            return nil
        }
    }

    private var recentRecords: [OperationRecord] {
        Array(service.operationRecords.prefix(5))
    }

    private var topAgentStats: [AgentStat] {
        let stats = agentStats
        return Array(stats.prefix(min(5, stats.count)))
    }

    // MARK: - Helper Functions

    private func diskColor(pct: Double) -> Color {
        if pct > 90 { return .red }
        if pct > 80 { return .orange }
        return .green
    }

    private func opTypeColor(_ type: OperationRecord.OperationType) -> Color {
        switch type {
        case .create: .green
        case .modify: .blue
        case .delete: .red
        case .move: .orange
        case .rename: .purple
        case .read: .cyan
        }
    }

    private func agentStatColor(index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .cyan, .pink, .indigo, .teal]
        return colors[index % colors.count]
    }

    private func settingsPath() -> String {
        NSHomeDirectory() + "/.aimaccleaner_monitor.json"
    }

    private func loadSettings() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath())),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        monitoringEnabled = obj["enabled"] as? Bool ?? true
        alertThreshold = obj["threshold"] as? Double ?? 10.0
        operationMonitorEnabled = obj["operationMonitor"] as? Bool ?? false
        trashInsteadOfDelete = obj["trashInsteadOfDelete"] as? Bool ?? true
        preventAutoEmptyTrash = obj["preventAutoEmptyTrash"] as? Bool ?? true
        service.alertThreshold = alertThreshold
        service.trashInsteadOfDelete = trashInsteadOfDelete
        service.preventAutoEmptyTrash = preventAutoEmptyTrash
        if operationMonitorEnabled {
            service.startOperationMonitor()
        }
    }

    private func saveSettings() {
        let obj: [String: Any] = [
            "enabled": monitoringEnabled,
            "threshold": alertThreshold,
            "operationMonitor": operationMonitorEnabled,
            "trashInsteadOfDelete": trashInsteadOfDelete,
            "preventAutoEmptyTrash": preventAutoEmptyTrash,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted) else { return }
        try? data.write(to: URL(fileURLWithPath: settingsPath()))
    }
}

