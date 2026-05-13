import SwiftUI

struct MenuBarMonitor: View {
    @ObservedObject var service: ScannerService
    @State private var alertThreshold: Double = 10.0
    @State private var monitoringEnabled: Bool = true
    @State private var operationMonitorEnabled: Bool = false
    @State private var trashInsteadOfDelete: Bool = true
    @State private var preventAutoEmptyTrash: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            diskOverview
            Divider()
            monitoringSettings
            Divider()
            safetySettings
            Divider()
            quickActions
        }
        .frame(width: 300)
        .onAppear {
            loadSettings()
            if monitoringEnabled { service.startMonitoring() }
        }
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

    private func diskColor(pct: Double) -> Color {
        if pct > 90 { return .red }
        if pct > 80 { return .orange }
        return .green
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
