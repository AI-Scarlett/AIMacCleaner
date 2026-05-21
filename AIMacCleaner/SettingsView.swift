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
                    .font(Theme.Font.title2)
                    .foregroundStyle(Theme.Colors.accent)
                Text(localizer.settingsTitle)
                    .font(Theme.Font.title2Bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.xl)
            Divider()

            HStack(spacing: 0) {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        Button {
                            selectedTab = tab
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(selectedTab == tab ? Theme.Colors.accent : Color.clear)
                                    .frame(width: 3, height: 20)

                                Image(systemName: tab.icon)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(selectedTab == tab ? Theme.Colors.accent : Theme.Colors.textSecondary)
                                    .frame(width: 16)
                                Text(tab.localizedLabel(localizer))
                                    .font(Theme.Font.captionMedium)
                                    .foregroundStyle(selectedTab == tab ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                                Spacer()
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .fill(selectedTab == tab ? Theme.Colors.accent.opacity(0.08) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .frame(width: 140)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.sidebarBg)
                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
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
                    .padding(Theme.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()
            HStack {
                Spacer()
                Button(localizer.cancel) { dismiss() }
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )
                    .buttonStyle(.plain)
                Button(localizer.save) { saveSettings() }
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(width: 680, height: 520)
        .onAppear { loadConfig() }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: localizer.aiSettings, icon: "brain")
            Text(localizer.aiSettingsDesc)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(localizer.apiBase)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("https://api.deepseek.com", text: $apiBase)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.body)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(localizer.apiKey)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    SecureField("sk-...", text: $apiKey)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.body)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(localizer.modelName)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("deepseek-chat", text: $model)
                        .textFieldStyle(.plain)
                        .font(Theme.Font.body)
                        .padding(Theme.Spacing.sm)
                        .background(Theme.Colors.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                        )
                }
            }
            .cardStyle()

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(localizer.recommendedConfig)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.purple)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                    ForEach(presets, id: \.name) { preset in
                        Button {
                            apiBase = preset.base
                            model = preset.model
                        } label: {
                            HStack {
                                Text(preset.name)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                Text(preset.model)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs + 1)
                            .background(Theme.Colors.purple.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: localizer.featureToggles, icon: "switch.2")

            VStack(spacing: Theme.Spacing.sm) {
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
            }
            .cardStyle()

            VStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .foregroundStyle(Theme.Colors.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizer.quitBehaviorTitle)
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.quitBehaviorDesc)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Picker("", selection: $quitBehavior) {
                    Text(localizer.quitAppAndMenu).tag("quitAll")
                    Text(localizer.quitAppKeepMenu).tag("quitAppOnly")
                }
                .pickerStyle(.segmented)
            }
            .cardStyle()
        }
    }

    private var monitorSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: localizer.monitorSettings, icon: "bell.badge")

            VStack(spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(localizer.storageAlertThreshold)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    HStack {
                        Slider(value: Binding(
                            get: { service.alertThreshold },
                            set: { service.alertThreshold = $0 }
                        ), in: 5...50, step: 5)
                        .tint(Theme.Colors.warning)
                        Text("\(Int(service.alertThreshold))%")
                            .font(Theme.Font.captionMedium)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.textSecondary)
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
            .cardStyle()
        }
    }

    private var networkSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: localizer.networkModeTitle, icon: "network")
            Text(localizer.networkModeDesc)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            VStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "globe")
                        .font(Theme.Font.title2)
                        .foregroundStyle(networkMode == "internet" ? Theme.Colors.info : Theme.Colors.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizer.internetMode)
                            .font(Theme.Font.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.internetModeDesc)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    if networkMode == "internet" {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.Colors.info)
                    }
                }
                .padding(Theme.Spacing.md)
                .background(networkMode == "internet" ? Theme.Colors.info.opacity(0.08) : Theme.Colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(networkMode == "internet" ? Theme.Colors.info.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: networkMode == "internet" ? 1.5 : 0.5)
                )
                .contentShape(Rectangle())
                .onTapGesture { networkMode = "internet" }

                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "lock.shield")
                        .font(Theme.Font.title2)
                        .foregroundStyle(networkMode == "intranet" ? Theme.Colors.warning : Theme.Colors.textTertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizer.intranetMode)
                            .font(Theme.Font.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.intranetModeDesc)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    if networkMode == "intranet" {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.Colors.warning)
                    }
                }
                .padding(Theme.Spacing.md)
                .background(networkMode == "intranet" ? Theme.Colors.warning.opacity(0.08) : Theme.Colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(networkMode == "intranet" ? Theme.Colors.warning.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: networkMode == "intranet" ? 1.5 : 0.5)
                )
                .contentShape(Rectangle())
                .onTapGesture { networkMode = "intranet" }
            }

            if networkMode == "internet" {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "arrow.up.circle")
                        .foregroundStyle(Theme.Colors.success)
                    Text(localizer.updateChecking)
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .cardStyle(padding: Theme.Spacing.md)
                Text(localizer.updateCheckingDesc)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: localizer.languageLabel, icon: "globe")
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(AppLanguage.allCases, id: \.self) { lang in
                    Button {
                        withAnimation(.none) {
                            localizer.language = lang
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(lang.flag)
                                .font(Theme.Font.caption)
                            Text(lang.label)
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(localizer.language == lang ? Theme.Colors.teal : Theme.Colors.textSecondary)
                        }
                        .frame(minWidth: 80)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm - 2)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .fill(localizer.language == lang ? Theme.Colors.teal.opacity(0.15) : Theme.Colors.cardBg)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .stroke(localizer.language == lang ? Theme.Colors.teal.opacity(0.5) : Color.primary.opacity(0.1), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var versionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: localizer.versionUpdate, icon: "arrow.up.circle")

            HStack {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(localizer.currentVersion)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("v\(service.currentVersion)")
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Circle()
                            .fill(Theme.Colors.success)
                            .frame(width: 6, height: 6)
                    }
                    if service.updateAvailable {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(Theme.Colors.info)
                                .font(Theme.Font.caption)
                            Text(localizer.newVersionAvailable + service.latestVersion)
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(Theme.Colors.info)
                        }
                    } else if service.isCheckingUpdate {
                        HStack(spacing: Theme.Spacing.sm) {
                            ProgressView().controlSize(.mini)
                            Text(localizer.downloadingUpdate)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
                Spacer()
                Button {
                    Task { await service.checkForUpdates() }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                        Text(localizer.checkUpdate)
                    }
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.accent)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 1)
                    .background(Theme.Colors.accent.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)
                .disabled(service.isCheckingUpdate)
                .opacity(service.isCheckingUpdate ? 0.5 : 1)

                if service.updateAvailable {
                    Button {
                        service.openDownloadPage()
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "arrow.down.circle")
                            Text(localizer.downloadUpdate)
                        }
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.xs + 1)
                        .background(Theme.Gradients.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardStyle()
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
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(Theme.Font.subheadline)
                .foregroundStyle(isOn ? Theme.Colors.accent : Theme.Colors.textTertiary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(desc)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
