import SwiftUI

struct MenuBarMonitor: View {
    @ObservedObject var service: ScannerService
    @State private var selectedTab: MonitorTab = .overview
    @State private var alertThreshold: Double = 10.0
    @State private var monitoringEnabled: Bool = true
    @State private var operationMonitorEnabled: Bool = false
    @State private var trashInsteadOfDelete: Bool = true
    @State private var preventAutoEmptyTrash: Bool = true

    enum MonitorTab: String, CaseIterable {
        case overview = "硬件监控"
        case operations = "Agent监控"
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
        }
        .frame(width: 300)
        .onAppear {
            loadSettings()
            if monitoringEnabled { service.startMonitoring() }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(MonitorTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    VStack(spacing: 3) {
                        HStack(spacing: 4) {
                            Image(systemName: tab == .overview ? "gauge.open.with.lines.needle.84percent" : "chart.bar")
                                .font(.caption2)
                            Text(tab.rawValue)
                                .font(.caption)
                                .fontWeight(selectedTab == tab ? .semibold : .regular)
                        }
                        .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)

                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
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
                Divider()
                quickActions
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
        VStack(spacing: 10) {
            HStack {
                Text("硬件监控")
                    .font(.headline)
                Spacer()
                if let hw = service.hardwareInfo {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(hw.cpuUsage > 80 ? .red : hw.cpuUsage > 50 ? .orange : .green)
                            .frame(width: 6, height: 6)
                        Text("运行中")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if let hw = service.hardwareInfo {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        HardwareStatCard(
                            icon: "cpu",
                            label: "CPU",
                            value: String(format: "%.0f%%", hw.cpuUsage),
                            detail: "\(hw.cpuCoreCount) 核",
                            color: hw.cpuUsage > 80 ? .red : hw.cpuUsage > 50 ? .orange : .green,
                            progress: hw.cpuUsage / 100.0
                        )

                        HardwareStatCard(
                            icon: "memorychip",
                            label: "内存",
                            value: String(format: "%.0f%%", hw.memoryPressurePct),
                            detail: String(format: "%.1f/%.0fG", hw.memoryUsedGb, hw.memoryTotalGb),
                            color: hw.memoryPressurePct > 85 ? .red : hw.memoryPressurePct > 70 ? .orange : .blue,
                            progress: hw.memoryPressurePct / 100.0
                        )
                    }

                    if let temp = hw.cpuTemperature {
                        HStack(spacing: 8) {
                            HardwareStatCard(
                                icon: "thermometer.medium",
                                label: "CPU 温度",
                                value: String(format: "%.0f°C", temp),
                                detail: temp > 80 ? "过热" : temp > 60 ? "偏高" : "正常",
                                color: temp > 80 ? .red : temp > 60 ? .orange : .green,
                                progress: min(temp / 100.0, 1.0)
                            )

                            if let battery = hw.batteryPercent {
                                HardwareStatCard(
                                    icon: hw.batteryCharging ? "battery.100.bolt" : "battery.75",
                                    label: "电池",
                                    value: String(format: "%.0f%%", battery),
                                    detail: hw.batteryCharging ? "充电中" : (hw.batteryTimeRemaining.map { "\($0)分钟" } ?? "使用中"),
                                    color: battery < 20 ? .red : battery < 50 ? .orange : .green,
                                    progress: battery / 100.0
                                )
                            } else {
                                HardwareStatCard(
                                    icon: "arrow.up.arrow.down",
                                    label: "网络",
                                    value: "↓\(hw.networkInFormatted)",
                                    detail: "↑\(hw.networkOutFormatted)",
                                    color: .teal,
                                    progress: nil
                                )
                            }
                        }
                    } else {
                        HStack(spacing: 8) {
                            if let battery = hw.batteryPercent {
                                HardwareStatCard(
                                    icon: hw.batteryCharging ? "battery.100.bolt" : "battery.75",
                                    label: "电池",
                                    value: String(format: "%.0f%%", battery),
                                    detail: hw.batteryCharging ? "充电中" : (hw.batteryTimeRemaining.map { "\($0)分钟" } ?? "使用中"),
                                    color: battery < 20 ? .red : battery < 50 ? .orange : .green,
                                    progress: battery / 100.0
                                )
                            }

                            HardwareStatCard(
                                icon: "arrow.up.arrow.down",
                                label: "网络",
                                value: "↓\(hw.networkInFormatted)",
                                detail: "↑\(hw.networkOutFormatted)",
                                color: .teal,
                                progress: nil
                            )
                        }
                    }

                    HStack(spacing: 12) {
                        HStack(spacing: 4) {
                            Image(systemName: "app.badge")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("\(hw.processCount) 进程")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down.circle")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("\(hw.threadCount) 线程")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                            Text("运行 \(hw.uptimeFormatted)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
            } else {
                Text("正在获取硬件信息...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
    }

    private var diskOverview: some View {
        VStack(spacing: 10) {
            HStack {
                Text("磁盘空间")
                    .font(.headline)
                Spacer()
                if let disk = service.diskInfo {
                    Text(String(format: "%.0f%% 已用", disk.usedPct))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(diskColor(pct: disk.usedPct))
                }
            }

            if let disk = service.diskInfo {
                ProgressView(value: disk.usedPct / 100.0)
                    .progressViewStyle(.linear)
                    .tint(diskColor(pct: disk.usedPct))
                    .scaleEffect(y: 2)

                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("总容量").font(.caption2).foregroundColor(.secondary)
                        Text(String(format: "%.0f GB", disk.totalGb)).font(.caption).fontWeight(.medium)
                    }
                    Spacer()
                    VStack(alignment: .center, spacing: 2) {
                        Text("已使用").font(.caption2).foregroundColor(.secondary)
                        Text(String(format: "%.0f GB", disk.usedGb)).font(.caption).fontWeight(.medium)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("可用").font(.caption2).foregroundColor(.secondary)
                        Text(String(format: "%.0f GB", disk.freeGb))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(disk.freeGb < 20 ? .red : .green)
                    }
                }

                if disk.freeGb < Double(100 * Int(alertThreshold) / 100) || disk.usedPct > (100 - alertThreshold) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("存储空间不足！建议立即清理")
                            .font(.caption2)
                            .foregroundColor(.orange)
                            .fontWeight(.medium)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(6)
                }
            } else {
                Text("正在获取磁盘信息...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
    }

    private var monitoringSettings: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "bell.badge")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("存储警报")
                    .font(.caption)
                    .fontWeight(.medium)
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
                    Text("警报阈值")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("剩余 \(Int(alertThreshold))%")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                }

                Slider(value: $alertThreshold, in: 5...30, step: 5) {
                    Text("阈值")
                }
                .controlSize(.small)
                .onChange(of: alertThreshold) { _ in
                    service.alertThreshold = alertThreshold
                    saveSettings()
                }
            }
        }
        .padding(14)
    }

    private var safetySettings: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "eye.fill")
                    .font(.caption)
                    .foregroundColor(.purple)
                Text("操作监控")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                Toggle("", isOn: $operationMonitorEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .onChange(of: operationMonitorEnabled) { _ in saveSettings() }
            }

            HStack {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("删除移入回收站")
                    .font(.caption)
                    .fontWeight(.medium)
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
                    .font(.caption)
                    .foregroundColor(.red)
                Text("禁止自动清空回收站")
                    .font(.caption)
                    .fontWeight(.medium)
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
        .padding(14)
    }

    private var quickActions: some View {
        VStack(spacing: 0) {
            updateSection

            HStack(spacing: 8) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.isVisible }) {
                        window.makeKeyAndOrderFront(nil)
                    } else {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.doc.fill")
                        Text("打开 AIMacCleaner")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task { await service.checkForUpdates() }
                } label: {
                    HStack {
                        Image(systemName: service.isCheckingUpdate ? "arrow.clockwise" : "arrow.triangle.2.circlepath")
                        Text(service.isCheckingUpdate ? "检查中..." : "检查更新")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(service.isCheckingUpdate || service.isDownloadingUpdate)
            }
            .padding(.horizontal, 14)
            .padding(.top, service.updateAvailable || service.isDownloadingUpdate || service.updateReadyToInstall ? 6 : 10)

            Text("v\(service.currentVersion)")
                .font(.system(size: 9))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.vertical, 6)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Image(systemName: "power")
                    Text("退出 AIMacCleaner")
                }
                .frame(maxWidth: .infinity)
                .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
    }

    private var updateSection: some View {
        VStack(spacing: 0) {
            if service.isDownloadingUpdate {
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.blue)
                            .font(.caption)
                        Text(String(format: "正在下载更新 %.0f%%", service.updateDownloadProgress * 100))
                            .font(.caption)
                            .fontWeight(.medium)
                        Spacer()
                        Button {
                            service.cancelUpdateDownload()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                    }

                    ProgressView(value: service.updateDownloadProgress)
                        .progressViewStyle(.linear)
                        .tint(.blue)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.05))
            } else if service.updateReadyToInstall {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("更新已下载完成")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    Button {
                        Task {
                            let alert = NSAlert()
                            alert.messageText = "安装更新"
                            alert.informativeText = "应用将退出并安装新版本 v\(service.latestVersion)，安装完成后会自动重新启动。"
                            alert.addButton(withTitle: "退出并安装")
                            alert.addButton(withTitle: "稍后安装")
                            alert.alertStyle = .informational
                            let response = alert.runModal()
                            if response == .alertFirstButtonReturn {
                                await service.installUpdate()
                            }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.circle.fill")
                                .foregroundColor(.white)
                            Text("退出并安装 v\(service.latestVersion)")
                                .foregroundColor(.white)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.green.opacity(0.05))
            } else if !service.updateErrorMessage.isEmpty {
                VStack(spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(service.updateErrorMessage)
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Spacer()
                        Button {
                            service.updateErrorMessage = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        Task { await service.downloadUpdate() }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("重试下载")
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.05))
            } else if service.updateAvailable {
                Button {
                    Task { await service.downloadUpdate() }
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.green)
                        Text("更新到 v\(service.latestVersion)")
                            .foregroundColor(.green)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.green)
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }
        }
    }

    // MARK: - Operation Monitor Tab

    private var operationStatsHeader: some View {
        VStack(spacing: 10) {
            HStack {
                Text("操作统计")
                    .font(.headline)
                Spacer()
                if operationMonitorEnabled {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text("监控中")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }
                } else {
                    Text("未启用")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                StatCard(
                    icon: "list.bullet",
                    value: "\(service.operationRecords.count)",
                    label: "总操作",
                    color: .blue
                )
                StatCard(
                    icon: "clock",
                    value: "\(todayOperationCount)",
                    label: "今日",
                    color: .green
                )
                StatCard(
                    icon: "flame.fill",
                    value: "\(hourOperationCount)",
                    label: "1小时",
                    color: .orange
                )
            }
        }
        .padding(14)
    }

    private var operationAgentStats: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "cpu")
                    .font(.caption)
                    .foregroundColor(.purple)
                Text("Agent 活跃度")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            if agentStats.isEmpty {
                Text("暂无操作记录")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 4) {
                    ForEach(agentStats.prefix(5), id: \.name) { stat in
                        HStack(spacing: 6) {
                            Text(stat.name)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .frame(width: 80, alignment: .leading)

                            GeometryReader { geo in
                                let maxCount = agentStats.first?.count ?? 1
                                let ratio = CGFloat(stat.count) / CGFloat(max(maxCount, 1))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(agentStatColor(index: stat.index))
                                    .frame(width: geo.size.width * ratio, height: 10)
                            }
                            .frame(height: 10)

                            Text("\(stat.count)")
                                .font(.caption2)
                                .monospacedDigit()
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                                .frame(width: 30, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private var operationTypeStats: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "chart.pie")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("操作类型分布")
                    .font(.caption)
                    .fontWeight(.medium)
            }

            if service.operationRecords.isEmpty {
                Text("暂无数据")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
            } else {
                HStack(spacing: 6) {
                    ForEach(Array(typeStats.enumerated()), id: \.offset) { index, stat in
                        VStack(spacing: 3) {
                            Image(systemName: stat.icon)
                                .font(.caption2)
                                .foregroundColor(stat.color)
                            Text("\(stat.count)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .monospacedDigit()
                            Text(stat.label)
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(stat.color.opacity(0.06))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(14)
    }

    private var recentOperations: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("最近操作")
                    .font(.caption)
                    .fontWeight(.medium)
                Spacer()
                if !service.operationRecords.isEmpty {
                    Text("\(service.operationRecords.count) 条")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if service.operationRecords.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.title3)
                        .foregroundColor(.secondary.opacity(0.4))
                    Text("暂无操作记录")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("开启监控后将自动记录 Agent 操作")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .padding(.vertical, 12)
            } else {
                VStack(spacing: 4) {
                    ForEach(recentRecords, id: \.id) { record in
                        HStack(spacing: 6) {
                            Image(systemName: record.operationType.icon)
                                .font(.system(size: 9))
                                .foregroundColor(opTypeColor(record.operationType))
                                .frame(width: 14)

                            Text(record.agentName)
                                .font(.system(size: 10))
                                .fontWeight(.medium)
                                .lineLimit(1)
                                .frame(width: 60, alignment: .leading)

                            Text(record.operationType.rawValue)
                                .font(.system(size: 9))
                                .fontWeight(.medium)
                                .foregroundColor(opTypeColor(record.operationType))
                                .frame(width: 24, alignment: .center)

                            Text(record.targetPath)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Text(record.timestamp, style: .time)
                                .font(.system(size: 9))
                                .monospacedDigit()
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                        .cornerRadius(4)
                    }
                }
            }
        }
        .padding(14)
    }

    private var operationControlBar: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    operationMonitorEnabled.toggle()
                    saveSettings()
                    if operationMonitorEnabled {
                        service.startOperationMonitor()
                    } else {
                        service.stopOperationMonitor()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: operationMonitorEnabled ? "pause.circle" : "play.circle")
                        Text(operationMonitorEnabled ? "暂停监控" : "开始监控")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(operationMonitorEnabled ? .orange : .green)

                Spacer()

                if !service.operationRecords.isEmpty {
                    Button {
                        service.clearOperationRecords()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                            Text("清空")
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.red)
                }
            }

            HStack {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    if let window = NSApp.windows.first(where: { $0.isVisible }) {
                        window.makeKeyAndOrderFront(nil)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.right.and.arrow.down.left")
                        Text("查看完整记录")
                    }
                    .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Spacer()

                Button {
                    NSApp.terminate(nil)
                } label: {
                    HStack {
                        Image(systemName: "power")
                        Text("退出")
                    }
                    .font(.caption2)
                    .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Computed Properties

    private var todayOperationCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return service.operationRecords.filter { $0.timestamp >= start }.count
    }

    private var hourOperationCount: Int {
        service.operationRecords.filter { Date().timeIntervalSince($0.timestamp) < 3600 }.count
    }

    private struct AgentStat {
        let name: String
        let count: Int
        let index: Int
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
                return TypeStat(label: type.rawValue, icon: type.icon, color: opTypeColor(type), count: count)
            }
            return nil
        }
    }

    private var recentRecords: [OperationRecord] {
        Array(service.operationRecords.prefix(5))
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

private struct StatCard: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .monospacedDigit()
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.06))
        .cornerRadius(8)
    }
}

private struct HardwareStatCard: View {
    let icon: String
    let label: String
    let value: String
    let detail: String
    let color: Color
    let progress: Double?

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundColor(color)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundColor(color)

            if let progress = progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(color)
                    .scaleEffect(y: 1.5)
            }

            Text(detail)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(color.opacity(0.06))
        .cornerRadius(8)
    }
}
