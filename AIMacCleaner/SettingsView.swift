import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab: SettingsTab = .features

    @AppStorage("menuBarMonitorEnabled") private var menuBarMonitorEnabled = true
    @AppStorage("sensorMonitorEnabled") private var sensorMonitorEnabled = false
    @AppStorage("operationMonitorEnabled") private var operationMonitorEnabled = false
    @AppStorage("networkMode") private var networkMode = "internet"
    @AppStorage("quitBehavior") private var quitBehavior: String = "quitAll"
    @AppStorage("colorPalette") private var colorPalette = AppColorPalette.porcelain.rawValue

    enum SettingsTab: String, CaseIterable {
        case ai = "AI"
        case features = "Features"
        case appearance = "Appearance"
        case lab = "Lab"
        case monitor = "Monitor"
        case network = "Network"
        case language = "Language"
        case version = "Version"

        static var visibleTabs: [SettingsTab] {
            allCases.filter { $0 != .ai }
        }

        var icon: String {
            switch self {
            case .ai: "brain"
            case .features: "switch.2"
            case .appearance: "paintpalette.fill"
            case .lab: "flask"
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
            case .appearance: "Appearance"
            case .lab: "Lab"
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
            case .appearance: localizer.t("外观", en: "Appearance", zhHant: "外觀", ja: "外観", ko: "외관", mt: "Appearance")
            case .lab: localizer.settingsTabLab
            case .monitor: localizer.settingsTabMonitor
            case .network: localizer.networkLabel
            case .language: localizer.settingsTabLanguage
            case .version: localizer.settingsTabVersion
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.lg)
                        .fill(Theme.Colors.accent.opacity(0.14))
                    Image(systemName: "gearshape.2.fill")
                        .font(Theme.Font.title2)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .frame(width: 44, height: 44)
                Text(localizer.settingsTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.xl)
            .background(.ultraThinMaterial)
            .background(Theme.Colors.elevatedCardBg.opacity(0.58))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.Gradients.glassStroke)
                    .frame(height: 1)
            }

            HStack(spacing: 0) {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(SettingsTab.visibleTabs, id: \.self) { tab in
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
                .background(Theme.Gradients.sidebar)
                .background(.ultraThinMaterial)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(Theme.Gradients.glassStroke)
                        .frame(width: 1)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                        switch selectedTab {
                        case .ai: aiSection
                        case .features: featuresSection
                        case .appearance: appearanceSection
                        case .lab: labSection
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

            HStack {
                Spacer()
                Button(localizer.cancel) { dismiss() }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .ghost, minHeight: 34))
                Button(localizer.save) { saveSettings() }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 34))
            }
            .padding(Theme.Spacing.lg)
            .background(.ultraThinMaterial)
            .background(Theme.Colors.elevatedCardBg.opacity(0.52))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Theme.Gradients.glassStroke)
                    .frame(height: 1)
            }
        }
        .frame(width: 680, height: 520)
        .appCanvas()
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: localizer.t("主题色彩", en: "Color Themes"), icon: "paintpalette.fill")
            Text(localizer.t(
                "每套主题都有自己的性格，并自动适配浅色和深色模式。",
                en: "Each theme has its own story and automatically adapts to light and dark mode."
            ))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.md) {
                ForEach(AppColorPalette.allCases, id: \.self) { palette in
                    paletteCard(palette)
                }
            }
        }
    }

    private func paletteCard(_ palette: AppColorPalette) -> some View {
        let isSelected = colorPalette == palette.rawValue
        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                colorPalette = palette.rawValue
                UserDefaults.standard.set(palette.rawValue, forKey: "colorPalette")
            }
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.sm) {
                    paletteSwatches(palette)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Theme.Font.subheadline)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(paletteTitle(palette))
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(paletteStory(palette))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Theme.Spacing.xs) {
                    Label(localizer.t("浅色", en: "Light"), systemImage: "sun.max.fill")
                    Label(localizer.t("深色", en: "Dark"), systemImage: "moon.fill")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
            .background(isSelected ? Theme.Colors.accent.opacity(0.10) : Theme.Colors.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(isSelected ? Theme.Colors.accent.opacity(0.45) : Theme.Colors.separator.opacity(0.7), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func paletteSwatches(_ palette: AppColorPalette) -> some View {
        HStack(spacing: -5) {
            ForEach(Array(palettePreviewColors(palette).enumerated()), id: \.offset) { _, color in
                Circle()
                    .fill(color)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.white.opacity(0.75), lineWidth: 1))
            }
        }
    }

    private func palettePreviewColors(_ palette: AppColorPalette) -> [Color] {
        switch palette {
        case .aurora:
            return [Color(red: 0.129, green: 0.784, blue: 0.839), Color(red: 0.204, green: 0.851, blue: 0.565), Color(red: 0.918, green: 0.984, blue: 0.984)]
        case .rose:
            return [Color(red: 0.933, green: 0.267, blue: 0.553), Color(red: 0.702, green: 0.365, blue: 0.930), Color(red: 1.000, green: 0.940, blue: 0.972)]
        case .shield:
            return [Color(red: 0.286, green: 0.416, blue: 0.686), Color(red: 0.392, green: 0.610, blue: 1.000), Color(red: 0.915, green: 0.950, blue: 1.000)]
        case .porcelain:
            return [Color(red: 0.286, green: 0.416, blue: 0.686), Color.white, Color(red: 0.895, green: 0.910, blue: 0.940)]
        }
    }

    private func paletteTitle(_ palette: AppColorPalette) -> String {
        switch palette {
        case .aurora:
            return localizer.t("极光青绿", en: "Aurora Cyan", zhHant: "極光青綠")
        case .rose:
            return localizer.t("玫瑰行动", en: "Rose Signal", zhHant: "玫瑰行動")
        case .shield:
            return localizer.t("蓝盾主题色", en: "Blue Shield", zhHant: "藍盾主題色")
        case .porcelain:
            return localizer.t("纯白默认", en: "Default White", zhHant: "純白預設")
        }
    }

    private func paletteStory(_ palette: AppColorPalette) -> String {
        switch palette {
        case .aurora:
            return localizer.t("像凌晨的状态面板，保留现在这套清爽科技感。", en: "A calm early-morning operations board; this keeps the current fresh tech mood.")
        case .rose:
            return localizer.t("更柔和、更有亲和力，适合想要一点情绪温度的工作台。", en: "Softer and warmer, for a workspace with a little more emotional temperature.")
        case .shield:
            return localizer.t("取自图标的深蓝玻璃与电光蓝高光，更像品牌默认主题。", en: "Deep glass blue and electric highlights sampled from the app icon, intended as the brand default.")
        case .porcelain:
            return localizer.t("默认主题。白底、蓝盾强调、低灰度层级，适合长时间盯数据。", en: "The default theme: white canvas, blue shield accents, and quiet layers for dense data.")
        }
    }

    private var aiSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: localizer.aiSettings, icon: "brain")
            Text(localizer.aiSettingsDesc)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "checkmark.seal.fill")
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(localizer.appReviewDemoMode)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.appReviewDemoModeDesc)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()
            }
            .cardStyle()
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

                ToggleSetting(
                    icon: "trash.slash",
                    title: localizer.preventAutoEmptyTrash,
                    desc: localizer.t(
                        "AgentGuard 不会自动清空废纸篓；受保护项在废纸篓中时会持续提醒。",
                        en: "AgentGuard never empties Trash automatically. It reminds you while guarded items remain in Trash."
                    ),
                    isOn: Binding(
                        get: { service.preventAutoEmptyTrash },
                        set: { service.preventAutoEmptyTrash = $0 }
                    )
                )

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(localizer.maxOperationRecords)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Picker("", selection: Binding(
                        get: {
                            [12, 48, 72, 96].contains(service.operationMonitor.recordRetentionHours) ? service.operationMonitor.recordRetentionHours : 0
                        },
                        set: { value in
                            service.operationMonitor.recordRetentionHours = value > 0 ? value : 120
                        }
                    )) {
                        Text("12\(localizer.hoursUnit)").tag(12)
                        Text("48\(localizer.hoursUnit)").tag(48)
                        Text("72\(localizer.hoursUnit)").tag(72)
                        Text("96\(localizer.hoursUnit)").tag(96)
                        Text(localizer.customHours).tag(0)
                    }
                    .pickerStyle(.segmented)

                    if ![12, 48, 72, 96].contains(service.operationMonitor.recordRetentionHours) {
                        Stepper(value: Binding(
                            get: { service.operationMonitor.recordRetentionHours },
                            set: { service.operationMonitor.recordRetentionHours = min(max($0, 1), 360) }
                        ), in: 1...360, step: 1) {
                            Text("\(service.operationMonitor.recordRetentionHours) \(localizer.hoursUnit)")
                                .font(Theme.Font.captionMedium)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    Text(localizer.retentionHoursHint)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .cardStyle()
        }
    }

    private var labSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: localizer.labSettingsTitle, icon: "flask")

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(localizer.labSettingsDesc)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Label(localizer.labSettingsNotice, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.warning)
            }
            .cardStyle()

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(localizer.labFeaturesOverview)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)

                VStack(spacing: Theme.Spacing.sm) {
                    LabFeatureRow(
                        icon: "arrow.down.doc.fill",
                        color: Theme.Colors.accent,
                        title: localizer.navCleaner,
                        desc: localizer.labFeatureCleanerDesc
                    )
                    LabFeatureRow(
                        icon: "app.badge",
                        color: Theme.Colors.info,
                        title: localizer.navApp,
                        desc: localizer.labFeatureAppDesc
                    )
                    LabFeatureRow(
                        icon: "cube.box",
                        color: .orange,
                        title: localizer.navDependency,
                        desc: localizer.labFeatureDependencyDesc
                    )
                    LabFeatureRow(
                        icon: "terminal",
                        color: .gray,
                        title: localizer.navOther,
                        desc: localizer.labFeatureOtherDesc
                    )
                    LabFeatureRow(
                        icon: "arrow.triangle.2.circlepath",
                        color: .purple,
                        title: localizer.navMigration,
                        desc: localizer.labFeatureMigrationDesc
                    )
                }
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
                    Image(systemName: "lock.circle")
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
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Theme.Spacing.sm) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        languageButton(lang)
                    }
                }
            }
        }
    }

    private func languageButton(_ lang: AppLanguage) -> some View {
        let isSelected = localizer.language == lang
        return Button {
            withAnimation(.none) {
                localizer.language = lang
            }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(lang.flag)
                    .font(Theme.Font.caption)
                Text(lang.label)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
            }
            .frame(minWidth: 80)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm - 2)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(isSelected ? Theme.Colors.accent.opacity(0.12) : Theme.Colors.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(isSelected ? Theme.Colors.accent.opacity(0.42) : Color.primary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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
                }
                Spacer()
                if let appStoreURL {
                    Button {
                        NSWorkspace.shared.open(appStoreURL)
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "arrow.up.circle")
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
                }
            }
            .cardStyle()
        }
    }

    private var appStoreURL: URL? {
        guard let appStoreID = Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String,
              appStoreID.range(of: #"^\d+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return URL(string: "macappstore://apps.apple.com/app/id\(appStoreID)")
    }

    private func saveSettings() {
        service.saveLocalAIConfig()
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
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                    isOn.toggle()
                }
            } label: {
                ZStack(alignment: isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isOn ? Theme.Colors.accent.opacity(0.92) : Theme.Colors.sidebarBg.opacity(0.8))
                    Circle()
                        .fill(.white)
                        .frame(width: 20, height: 20)
                        .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
                        .padding(3)
                }
                .frame(width: 48, height: 26)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(isOn ? Color.white.opacity(0.28) : Theme.Colors.separator.opacity(0.6), lineWidth: 1)
                )
                .shadow(color: isOn ? Theme.Colors.accent.opacity(0.18) : .clear, radius: 9, y: 4)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

struct LabFeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let desc: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(desc)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}
