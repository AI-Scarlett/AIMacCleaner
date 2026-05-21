import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) var dismiss

    @State private var apiBase = ""
    @State private var apiKey = ""
    @State private var model = ""
    @State private var selectedTab: SettingsTab = .ai

    @AppStorage("menuBarMonitorEnabled") private var menuBarMonitorEnabled = true
    @AppStorage("sensorMonitorEnabled") private var sensorMonitorEnabled = true
    @AppStorage("operationMonitorEnabled") private var operationMonitorEnabled = true
    @AppStorage("networkMode") private var networkMode = "internet"
    @AppStorage("quitBehavior") private var quitBehavior: String = "quitAll"

    enum SettingsTab: String, CaseIterable {
        case ai = "AI"
        case features = "Features"
        case monitor = "Monitor"
        case network = "Network"
        case language = "Language"
        case version = "Version"

        var icon: String {
            switch self {
            case .ai: "brain"
            case .features: "switch.2"
            case .monitor: "bell.badge"
            case .network: "network"
            case .language: "globe"
            case .version: "arrow.up.circle"
            }
        }

        var label: String {
            switch self {
            case .ai: "AI"
            case .features: "Features"
            case .monitor: "Monitor"
            case .network: "Network"
            case .language: "Language"
            case .version: "Version"
            }
        }

        func localizedLabel(_ localizer: Localizer) -> String {
            switch self {
            case .ai: localizer.settingsTabAI
            case .features: localizer.settingsTabFeatures
            case .monitor: localizer.settingsTabMonitor
            case .network: localizer.networkLabel
            case .language: localizer.settingsTabLanguage
            case .version: localizer.settingsTabVersion
            }
        }
    }

    let presets: [(name: String, base: String, model: String)] = [
        ("DeepSeek", "https://api.deepseek.com", "deepseek-chat"),
        ("OpenAI", "https://api.openai.com", "gpt-4o-mini"),
        ("Zhipu GLM", "https://open.bigmodel.cn/api/paas", "glm-4-flash"),
        ("Qwen (Tongyi)", "https://dashscope.aliyuncs.com/compatible-mode", "qwen-turbo"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .font(.title2).foregroundColor(.accentColor)
                Text(localizer.settingsTitle)
                    .font(.title2).fontWeight(.bold)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)
            Divider()

            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 12))
                                    .foregroundColor(selectedTab == tab ? .accentColor : .secondary)
                                    .frame(width: 16)
                                Text(tab.localizedLabel(localizer))
                                    .font(.system(size: 12))
                                    .fontWeight(selectedTab == tab ? .semibold : .regular)
                                    .foregroundColor(selectedTab == tab ? .primary : .secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(width: 120)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch selectedTab {
                        case .ai: aiSection
                        case .features: featuresSection
                        case .monitor: monitorSection
                        case .network: networkSection
                        case .language: languageSection
                        case .version: versionSection
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button(localizer.cancel) { dismiss() }.buttonStyle(.bordered)
                Button(localizer.save) { saveSettings() }.buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 680, height: 520)
        .onAppear { loadConfig() }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "brain").foregroundColor(.purple)
                Text(localizer.aiSettings).font(.headline)
            }
            Text(localizer.aiSettingsDesc).font(.caption).foregroundColor(.secondary)

            LabeledContent(localizer.apiBase) {
                TextField("https://api.deepseek.com", text: $apiBase)
                    .textFieldStyle(.roundedBorder).frame(width: 360)
            }
            LabeledContent(localizer.apiKey) {
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder).frame(width: 360)
            }
            LabeledContent(localizer.modelName) {
                TextField("deepseek-chat", text: $model)
                    .textFieldStyle(.roundedBorder).frame(width: 360)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(localizer.recommendedConfig)
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
                            .background(Color.purple.opacity(0.08)).cornerRadius(6)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "switch.2").foregroundColor(.blue)
                Text(localizer.featureToggles).font(.headline)
            }
            ToggleSetting(
                icon: "menubar.rectangle",
                title: localizer.menuBarMonitor,
                desc: localizer.menuBarMonitorDesc,
                isOn: $menuBarMonitorEnabled
            )
            ToggleSetting(
                icon: "video.fill",
                title: localizer.sensorMonitor,
                desc: localizer.sensorMonitorDesc,
                isOn: $sensorMonitorEnabled
            )
            ToggleSetting(
                icon: "clock.arrow.circlepath",
                title: localizer.operationMonitor,
                desc: localizer.operationMonitorDesc,
                isOn: $operationMonitorEnabled
            )

            ToggleSetting(
                icon: "brain.head.profile",
                title: localizer.aiSelfLearning,
                desc: localizer.aiSelfLearningDesc,
                isOn: Binding(
                    get: { service.operationMonitor.aiSelfLearningEnabled },
                    set: { newValue in
                        if newValue {
                            service.startAISelfLearning()
                        } else {
                            service.stopAISelfLearning()
                        }
                    }
                )
            )

            Divider().padding(.vertical, 4)

            HStack(spacing: 8) {
                Image(systemName: "rectangle.portrait.and.arrow.right").foregroundColor(.purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.quitBehaviorTitle).font(.subheadline).fontWeight(.medium)
                    Text(localizer.quitBehaviorDesc).font(.caption).foregroundColor(.secondary)
                }
            }
            Picker("", selection: $quitBehavior) {
                Text(localizer.quitAppAndMenu).tag("quitAll")
                Text(localizer.quitAppKeepMenu).tag("quitAppOnly")
            }
            .pickerStyle(.segmented)
            .frame(width: 320)
        }
    }

    private var monitorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge").foregroundColor(.orange)
                Text(localizer.monitorSettings).font(.headline)
            }
            LabeledContent(localizer.storageAlertThreshold) {
                HStack {
                    Slider(value: Binding(
                        get: { service.alertThreshold },
                        set: { service.alertThreshold = $0 }
                    ), in: 5...50, step: 5).frame(width: 200)
                    Text("\(Int(service.alertThreshold))%")
                        .font(.caption).monospacedDigit().foregroundColor(.secondary)
                }
            }
            ToggleSetting(
                icon: "trash",
                title: localizer.trashInsteadOfDelete,
                desc: localizer.trashInsteadOfDeleteDesc,
                isOn: Binding(
                    get: { service.trashInsteadOfDelete },
                    set: { service.trashInsteadOfDelete = $0 }
                )
            )
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "network").foregroundColor(.blue)
                Text(localizer.networkModeTitle).font(.headline)
            }
            Text(localizer.networkModeDesc)
                .font(.callout).foregroundColor(.secondary)

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Image(systemName: networkMode == "internet" ? "globe" : "globe")
                        .font(.title2)
                        .foregroundColor(networkMode == "internet" ? .blue : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizer.internetMode).font(.body).fontWeight(.medium)
                        Text(localizer.internetModeDesc)
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if networkMode == "internet" {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                    }
                }
                .padding(10)
                .background(networkMode == "internet" ? Color.blue.opacity(0.08) : Color.clear)
                .cornerRadius(8)
                .contentShape(Rectangle())
                .onTapGesture { networkMode = "internet" }

                HStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.title2)
                        .foregroundColor(networkMode == "intranet" ? .orange : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizer.intranetMode).font(.body).fontWeight(.medium)
                        Text(localizer.intranetModeDesc)
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if networkMode == "intranet" {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.orange)
                    }
                }
                .padding(10)
                .background(networkMode == "intranet" ? Color.orange.opacity(0.08) : Color.clear)
                .cornerRadius(8)
                .contentShape(Rectangle())
                .onTapGesture { networkMode = "intranet" }
            }

            if networkMode == "internet" {
                Divider()
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.circle").foregroundColor(.green)
                    Text(localizer.updateChecking).font(.subheadline).fontWeight(.medium)
                }
                Text(localizer.updateCheckingDesc)
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundColor(.teal)
                Text(localizer.languageLabel).font(.headline)
            }
            HStack(spacing: 8) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Button {
                        withAnimation(.none) {
                            localizer.language = lang
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(lang.flag).font(.caption)
                            Text(lang.label).font(.caption)
                                .fontWeight(localizer.language == lang ? .semibold : .regular)
                        }
                        .frame(minWidth: 80)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(localizer.language == lang ? Color.teal.opacity(0.15) : Color.clear)
                        )
                        .foregroundColor(localizer.language == lang ? .teal : .secondary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(localizer.language == lang ? Color.teal.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle").foregroundColor(.green)
                Text(localizer.versionUpdate).font(.headline)
            }

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(localizer.currentVersion).font(.caption).foregroundColor(.secondary)
                        Text("v\(service.currentVersion)").font(.caption).fontWeight(.semibold)
                        Circle().fill(Color.green).frame(width: 6, height: 6)
                    }
                    if service.updateAvailable {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill").foregroundColor(.blue).font(.caption)
                            Text(localizer.newVersionAvailable + service.latestVersion)
                                .font(.caption).fontWeight(.medium).foregroundColor(.blue)
                        }
                    } else if service.isCheckingUpdate {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text(localizer.downloadingUpdate).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                Spacer()
                Button {
                    Task { await service.checkForUpdates() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text(localizer.checkUpdate)
                    }
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(service.isCheckingUpdate)

                if service.updateAvailable {
                    Button {
                        service.openDownloadPage()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle")
                            Text(localizer.downloadUpdate)
                        }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.small)
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
                Text(title).font(.caption).fontWeight(.medium)
                Text(desc).font(.system(size: 10)).foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}
