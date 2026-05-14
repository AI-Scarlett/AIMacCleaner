import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var service: ScannerService
    @Environment(\.dismiss) var dismiss

    @State private var apiBase = ""
    @State private var apiKey = ""
    @State private var model = ""

    @AppStorage("monitorEnabled") private var monitorEnabled = true
    @AppStorage("operationMonitorEnabled") private var operationMonitorEnabled = true
    @AppStorage("sensorMonitorEnabled") private var sensorMonitorEnabled = true
    @AppStorage("menuBarMonitorEnabled") private var menuBarMonitorEnabled = true

    @State private var showCheckUpdate = false

    let presets: [(name: String, base: String, model: String)] = [
        ("DeepSeek", "https://api.deepseek.com", "deepseek-chat"),
        ("OpenAI", "https://api.openai.com", "gpt-4o-mini"),
        ("智谱 GLM", "https://open.bigmodel.cn/api/paas", "glm-4-flash"),
        ("通义千问", "https://dashscope.aliyuncs.com/compatible-mode", "qwen-turbo"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .font(.title2).foregroundColor(.accentColor)
                Text("设置")
                    .font(.title2).fontWeight(.bold)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    aiSettingsSection
                    Divider()
                    toggleSettingsSection
                    Divider()
                    monitorSettingsSection
                    Divider()
                    versionSection
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button("保存设置") { saveSettings() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 560, height: 600)
        .onAppear { loadConfig() }
    }

    private var aiSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain").foregroundColor(.purple)
                Text("AI 设置")
                    .font(.headline)
            }

            Text("配置大模型 API，用于智能分析目录结构和识别可清理项")
                .font(.caption).foregroundColor(.secondary)

            LabeledContent("API Base") {
                TextField("https://api.deepseek.com", text: $apiBase)
                    .textFieldStyle(.roundedBorder).frame(width: 340)
            }
            LabeledContent("API Key") {
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder).frame(width: 340)
            }
            LabeledContent("模型名称") {
                TextField("deepseek-chat", text: $model)
                    .textFieldStyle(.roundedBorder).frame(width: 340)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("推荐配置（点击自动填入）")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.purple)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                    ForEach(presets, id: \.name) { preset in
                        Button {
                            apiBase = preset.base
                            model = preset.model
                        } label: {
                            HStack {
                                Text(preset.name).font(.caption)
                                Spacer()
                                Text(preset.model).font(.system(size: 9)).foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.purple.opacity(0.08))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var toggleSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "switch.2").foregroundColor(.blue)
                Text("功能开关")
                    .font(.headline)
            }

            ToggleSetting(
                icon: "menubar.rectangle",
                title: "菜单栏监控",
                desc: "在菜单栏显示系统资源监控",
                isOn: $menuBarMonitorEnabled
            )
            ToggleSetting(
                icon: "video.fill",
                title: "设备监控",
                desc: "监控摄像头和麦克风调用",
                isOn: $sensorMonitorEnabled
            )
            ToggleSetting(
                icon: "clock.arrow.circlepath",
                title: "操作记录",
                desc: "监控 AI Agent 的文件操作",
                isOn: $operationMonitorEnabled
            )
        }
    }

    private var monitorSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge").foregroundColor(.orange)
                Text("监控设置")
                    .font(.headline)
            }

            LabeledContent("存储警告阈值") {
                HStack {
                    Slider(value: Binding(
                        get: { service.alertThreshold },
                        set: { service.alertThreshold = $0 }
                    ), in: 5...50, step: 5)
                    .frame(width: 200)
                    Text("\(Int(service.alertThreshold))%")
                        .font(.caption).monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
            ToggleSetting(
                icon: "trash",
                title: "使用回收站",
                desc: "删除文件时移入回收站而非直接删除",
                isOn: Binding(
                    get: { service.trashInsteadOfDelete },
                    set: { service.trashInsteadOfDelete = $0 }
                )
            )
        }
    }

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle").foregroundColor(.green)
                Text("版本与更新")
                    .font(.headline)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("当前版本")
                            .font(.caption).foregroundColor(.secondary)
                        Text("v\(service.currentVersion)")
                            .font(.caption).fontWeight(.semibold)
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                    }

                    if service.updateAvailable {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundColor(.blue).font(.caption)
                            Text("发现新版本 v\(service.latestVersion)")
                                .font(.caption).fontWeight(.medium)
                                .foregroundColor(.blue)
                        }
                    } else if service.isCheckingUpdate {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("正在检查更新...")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                Button {
                    Task { await service.checkForUpdates() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("检查更新")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(service.isCheckingUpdate)

                if service.updateAvailable {
                    Button {
                        service.openDownloadPage()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                            Text("下载更新")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
    }

    private func loadConfig() {
        if let config = service.aiConfig {
            apiBase = config.apiBase ?? "https://api.deepseek.com"
            apiKey = config.apiKey ?? ""
            model = config.model ?? "deepseek-chat"
        }
    }

    private func saveSettings() {
        service.saveAIConfig(apiBase: apiBase, apiKey: apiKey, model: model)

        if operationMonitorEnabled {
            service.startOperationMonitor()
        } else {
            service.stopOperationMonitor()
        }

        dismiss()
    }
}

struct ToggleSetting: View {
    let icon: String
    let title: String
    let desc: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(isOn ? .accentColor : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption).fontWeight(.medium)
                Text(desc)
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
