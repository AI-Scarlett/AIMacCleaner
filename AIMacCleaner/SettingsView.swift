import SwiftUI
import StoreKit
import AppKit
import CoreImage.CIFilterBuiltins

struct SettingsView: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) var dismiss

    private let initialTab: SettingsTab
    @State private var selectedTab: SettingsTab
    @State private var showAIConfig = false
    @StateObject private var licenseService = DirectLicenseService.shared
    @StateObject private var marketplaceCatalogService = TraceFenceMarketplaceCatalogService.shared
    @StateObject private var pluginEntitlementService = TraceFencePluginEntitlementService.shared
    @StateObject private var appStoreSubscriptionService = AppStoreSubscriptionService.shared
    @StateObject private var updateService = DirectUpdateService.shared
    @StateObject private var iOSRemoteGatewayService = IOSRemoteControlGatewayService.shared
    @ObservedObject private var captureService = CaptureShelfService.shared
    @State private var licenseKeyInput = ""
    @State private var pluginLicenseInputs: [String: String] = [:]
    @State private var shortcutSettings: [GlobalShortcut] = GlobalShortcutService.defaultShortcuts
    @State private var recordingShortcutAction: GlobalShortcut.ShortcutAction?
    @State private var shortcutRecorderMonitor: Any?
    @State private var shortcutMessage: String?
#if DEBUG
    @State private var debugDodoEnvironment = TraceFenceDodoEnvironment.test.rawValue
    @State private var debugDodoBusinessID = ""
    @State private var debugDodoMonthlyProductID = ""
    @State private var debugDodoAnnualProductID = ""
    @State private var debugDodoConfigurationMessage: String?
    @State private var debugDodoConfigurationSucceeded = false
#endif

    @AppStorage("menuBarMonitorEnabled") private var menuBarMonitorEnabled = true
    @AppStorage("sensorMonitorEnabled") private var sensorMonitorEnabled = false
    @AppStorage("operationMonitorEnabled") private var operationMonitorEnabled = false
    @AppStorage("networkMode") private var networkMode = "internet"
    @AppStorage("quitBehavior") private var quitBehavior: String = "quitAll"
    @AppStorage("mainWindowAlwaysOnTop") private var mainWindowAlwaysOnTop = false
    @AppStorage("automaticUpdateChecksEnabled") private var automaticUpdateChecksEnabled = true
    @AppStorage(MenuBarStatusPreferences.styleKey) private var menuBarStatusStyle = MenuBarStatusStyle.classic.rawValue
    @AppStorage(MenuBarStatusPreferences.quotaDisplayModeKey) private var menuBarQuotaDisplayMode = MenuBarQuotaDisplayMode.remaining.rawValue
    @AppStorage(MenuBarStatusPreferences.primaryMetricKey) private var menuBarPrimaryMetric = MenuBarPrimaryMetric.tightest.rawValue
    @AppStorage(MenuBarStatusPreferences.showResetCountdownKey) private var menuBarShowResetCountdown = true
    @AppStorage("colorPalette") private var colorPalette = AppColorPalette.porcelain.rawValue
    @AppStorage(IOSRemoteControlGatewayService.enabledKey) private var iOSRemoteGatewayEnabled = false
    @AppStorage(IOSRemoteControlGatewayService.portKey) private var iOSRemoteGatewayPort = 17895
    @AppStorage(DirectUpdateService.cliUpdateStrongReminderEnabledKey) private var cliUpdateStrongReminderEnabled = true

    enum SettingsTab: String, CaseIterable {
        case ai = "AI"
        case features = "Features"
        case license = "License"
        case marketplace = "Marketplace"
        case appearance = "Appearance"
        case lab = "Lab"
        case monitor = "Monitor"
        case network = "Network"
        case language = "Language"
        case version = "Version"

        var icon: String {
            switch self {
            case .ai: "brain"
            case .features: "switch.2"
            case .license: TraceFenceDistributionPolicy.currentChannel.isAppStore ? "creditcard.fill" : "key.fill"
            case .marketplace: "shippingbox.fill"
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
            case .license: "License"
            case .marketplace: "Marketplace"
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
            case .license:
                if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                    localizer.t("订阅", en: "Subscription", zhHant: "訂閱", ja: "サブスクリプション", ko: "구독", mt: "Subscription")
                } else {
                    localizer.t("授权", en: "License", zhHant: "授權", ja: "ライセンス", ko: "라이선스", mt: "License")
                }
            case .marketplace:
                localizer.t("插件商城", en: "Plugin Store", zhHant: "外掛商城", ja: "プラグインストア", ko: "플러그인 스토어", mt: "Plugin Store")
            case .appearance: localizer.t("外观", en: "Appearance", zhHant: "外觀", ja: "外観", ko: "외관", mt: "Appearance")
            case .lab: localizer.settingsTabLab
            case .monitor: localizer.settingsTabMonitor
            case .network: localizer.networkLabel
            case .language: localizer.settingsTabLanguage
            case .version: localizer.settingsTabVersion
            }
        }
    }

    init(initialTab: SettingsTab = .features) {
        self.initialTab = initialTab
        _selectedTab = State(initialValue: initialTab)
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
                    ForEach(SettingsTab.allCases, id: \.self) { tab in
                        if tab == .marketplace && TraceFenceDistributionPolicy.currentChannel.isAppStore {
                            EmptyView()
                        } else {
                        Button {
                            stopShortcutRecording()
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

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                            Color.clear
                                .frame(height: 0)
                                .id("settingsContentTop")
                            switch selectedTab {
                            case .ai: aiSection
                            case .features: featuresSection
                            case .license: licenseSection
                            case .marketplace: marketplaceSection
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
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo("settingsContentTop", anchor: .top)
                        }
                    }
                    .onChange(of: selectedTab) { _ in
                        stopShortcutRecording()
                        proxy.scrollTo("settingsContentTop", anchor: .top)
                    }
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
        .frame(width: 760, height: 640)
        .appCanvas()
        .sheet(isPresented: $showAIConfig) {
            AIConfigView()
                .environmentObject(service)
                .environmentObject(localizer)
        }
        .onAppear {
            selectedTab = initialTab
        }
        .onDisappear {
            stopShortcutRecording()
        }
        .task {
            licenseService.refreshTrialState()
            iOSRemoteGatewayService.configure(scannerService: service)
            if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                await appStoreSubscriptionService.refresh()
            }
            loadShortcutSettings()
#if DEBUG
            loadDebugDodoConfiguration()
#endif
        }
        .onDisappear {
            stopShortcutRecording()
        }
        .onChange(of: mainWindowAlwaysOnTop) { _ in
            NotificationCenter.default.post(name: .traceFenceMainWindowLevelChanged, object: nil)
        }
        .onChange(of: menuBarStatusStyle) { value in
            if value == MenuBarStatusStyle.detailed.rawValue {
                AgentUsageInsightsService.shared.startScheduling()
            }
        }
        .onChange(of: menuBarPrimaryMetric) { value in
            if value == MenuBarPrimaryMetric.todayTokens.rawValue {
                AgentUsageInsightsService.shared.startScheduling()
            }
        }
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
                    Text(localizer.t("AI 模型策略", en: "AI Model Strategy", zhHant: "AI 模型策略", ja: "AI モデル方針", ko: "AI 모델 전략", mt: "AI Model Strategy"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t("默认先使用 Apple Intelligence；不可用时可按你的设置回退到第三方模型。", en: "Uses Apple Intelligence first by default; if unavailable, it can fall back to your configured external model.", zhHant: "預設先使用 Apple Intelligence；不可用時可依你的設定回退到第三方模型。", ja: "既定では Apple Intelligence を優先し、利用できない場合は設定済みの外部モデルへフォールバックできます。", ko: "기본적으로 Apple Intelligence를 먼저 사용하고, 사용할 수 없으면 설정한 외부 모델로 전환할 수 있습니다.", mt: "Uses Apple Intelligence first by default; if unavailable, it can fall back to your configured external model."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Button(localizer.t("模型设置", en: "Model Settings")) {
                    showAIConfig = true
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .ghost, minHeight: 32))
            }
            .cardStyle()
        }
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: localizer.featureToggles, icon: "switch.2")

            VStack(spacing: 0) {
                ToggleSetting(
                    icon: "menubar.rectangle",
                    title: localizer.menuBarMonitor,
                    desc: localizer.menuBarMonitorDesc,
                    isOn: $menuBarMonitorEnabled
                )
                SettingsRowDivider()
                windowAndMenuBarPresentationSetting
                SettingsRowDivider()
                ToggleSetting(
                    icon: "video.fill",
                    title: localizer.sensorMonitor,
                    desc: localizer.sensorMonitorDesc,
                    isOn: $sensorMonitorEnabled
                )
                SettingsRowDivider()
                ToggleSetting(
                    icon: "clock.arrow.circlepath",
                    title: localizer.operationMonitor,
                    desc: localizer.operationMonitorDesc,
                    isOn: $operationMonitorEnabled
                )
                SettingsRowDivider()
                localCaptureSetting
                SettingsRowDivider()
                shortcutSetting
                SettingsRowDivider()
                quitBehaviorSetting
            }
            .cardStyle()
        }
    }

    private var windowAndMenuBarPresentationSetting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "rectangle.topthird.inset.filled")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.t("窗口与菜单栏信息", en: "Window & Menu Bar Info", zhHant: "視窗與選單列資訊", ja: "ウインドウとメニューバー", ko: "윈도우 및 메뉴 막대", mt: "Window & Menu Bar Info"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t("控制主窗口置顶，并选择菜单栏显示的额度或今日 Token。", en: "Keep the main window on top and choose which quota or token metric appears in the menu bar.", zhHant: "控制主視窗置頂，並選擇選單列顯示的額度或今日 Token。", ja: "メインウインドウの常時表示とメニューバー指標を設定します。", ko: "기본 창 고정과 메뉴 막대 지표를 설정합니다.", mt: "Keep the main window on top and choose the menu bar metric."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: $mainWindowAlwaysOnTop)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help(localizer.t("主窗口始终置顶", en: "Keep main window on top", zhHant: "主視窗始終置頂", ja: "常に手前に表示", ko: "항상 위에 표시", mt: "Keep main window on top"))
            }

            VStack(spacing: Theme.Spacing.sm) {
                HStack {
                    Text(localizer.t("菜单栏样式", en: "Menu bar style", zhHant: "選單列樣式", ja: "表示スタイル", ko: "메뉴 막대 스타일", mt: "Menu bar style"))
                    Spacer()
                    Picker("", selection: $menuBarStatusStyle) {
                        Text(localizer.t("仅图标", en: "Icon only", zhHant: "僅圖示", ja: "アイコンのみ", ko: "아이콘만", mt: "Icon only")).tag(MenuBarStatusStyle.minimal.rawValue)
                        Text(localizer.t("单项", en: "Single metric", zhHant: "單項", ja: "単一指標", ko: "단일 지표", mt: "Single metric")).tag(MenuBarStatusStyle.classic.rawValue)
                        Text(localizer.t("详细", en: "Detailed", zhHant: "詳細", ja: "詳細", ko: "상세", mt: "Detailed")).tag(MenuBarStatusStyle.detailed.rawValue)
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                if menuBarStatusStyle == MenuBarStatusStyle.classic.rawValue {
                    HStack {
                        Text(localizer.t("主指标", en: "Primary metric", zhHant: "主指標", ja: "主な指標", ko: "기본 지표", mt: "Primary metric"))
                        Spacer()
                        Picker("", selection: $menuBarPrimaryMetric) {
                            Text(localizer.t("最紧额度", en: "Tightest quota", zhHant: "最緊額度", ja: "最小クォータ", ko: "가장 낮은 할당량", mt: "Tightest quota")).tag(MenuBarPrimaryMetric.tightest.rawValue)
                            Text("5h").tag(MenuBarPrimaryMetric.fiveHour.rawValue)
                            Text("7d").tag(MenuBarPrimaryMetric.weekly.rawValue)
                            Text("Fable").tag(MenuBarPrimaryMetric.fable.rawValue)
                            Text(localizer.t("今日 Token", en: "Today's tokens", zhHant: "今日 Token", ja: "今日のトークン", ko: "오늘 토큰", mt: "Today's tokens")).tag(MenuBarPrimaryMetric.todayTokens.rawValue)
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }

                if menuBarStatusStyle != MenuBarStatusStyle.minimal.rawValue {
                    HStack {
                        Picker("", selection: $menuBarQuotaDisplayMode) {
                            Text(localizer.t("显示剩余", en: "Show remaining", zhHant: "顯示剩餘", ja: "残りを表示", ko: "잔여 표시", mt: "Show remaining")).tag(MenuBarQuotaDisplayMode.remaining.rawValue)
                            Text(localizer.t("显示已用", en: "Show used", zhHant: "顯示已用", ja: "使用量を表示", ko: "사용량 표시", mt: "Show used")).tag(MenuBarQuotaDisplayMode.used.rawValue)
                        }
                        .labelsHidden()
                        Spacer()
                        if menuBarStatusStyle == MenuBarStatusStyle.detailed.rawValue {
                            Toggle(localizer.t("重置倒计时", en: "Reset countdown", zhHant: "重置倒數", ja: "リセットまで", ko: "초기화 카운트다운", mt: "Reset countdown"), isOn: $menuBarShowResetCountdown)
                                .toggleStyle(.checkbox)
                        }
                    }
                }
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.leading, 36)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var localCaptureSetting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "viewfinder")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(captureService.isClipboardHistoryEnabled ? Theme.Colors.accent : Theme.Colors.textTertiary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.t("本地采集", en: "Local Capture", zhHant: "本機採集", ja: "ローカル収集", ko: "로컬 캡처", mt: "Local Capture"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t("截屏入口和剪贴板历史，数据仅保存在本机。", en: "Screenshot entry and clipboard history, stored only on this Mac.", zhHant: "截圖入口與剪貼簿歷史，資料只保存在本機。", ja: "スクリーンショット入口とクリップボード履歴は、このMac内にのみ保存されます。", ko: "스크린샷 진입점과 클립보드 기록은 이 Mac에만 저장됩니다.", mt: "Screenshot entry and clipboard history, stored only on this Mac."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: captureHistoryEnabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            if captureService.isClipboardHistoryEnabled {
                VStack(spacing: Theme.Spacing.sm) {
                    HStack {
                        Text(localizer.t("剪贴板保留 \(captureService.historyLimit) 条", en: "Keep \(captureService.historyLimit) clipboard items", zhHant: "剪貼簿保留 \(captureService.historyLimit) 筆", ja: "クリップボードを\(captureService.historyLimit)件保存", ko: "클립보드 \(captureService.historyLimit)개 보관", mt: "Keep \(captureService.historyLimit) clipboard items"))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Stepper("", value: captureHistoryLimitBinding, in: CaptureShelfService.minHistoryLimit...CaptureShelfService.maxHistoryLimit, step: 20)
                            .labelsHidden()
                            .controlSize(.small)
                    }

                    HStack(spacing: Theme.Spacing.lg) {
                        Toggle(localizer.t("记录图片", en: "Save images", zhHant: "記錄圖片", ja: "画像を保存", ko: "이미지 저장", mt: "Save images"), isOn: captureImagesBinding)
                            .toggleStyle(.checkbox)
                        Toggle(localizer.t("记录文件", en: "Save files", zhHant: "記錄檔案", ja: "ファイルを保存", ko: "파일 저장", mt: "Save files"), isOn: captureFilesBinding)
                            .toggleStyle(.checkbox)
                        Spacer()
                    }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.leading, 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var shortcutSetting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "keyboard")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.t("快捷键", en: "Shortcuts", zhHant: "快捷鍵", ja: "ショートカット", ko: "단축키", mt: "Shortcuts"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }

                Spacer()

                Button(localizer.t("恢复默认", en: "Restore Defaults", zhHant: "恢復預設", ja: "デフォルトに戻す", ko: "기본값 복원", mt: "Restore Defaults")) {
                    stopShortcutRecording()
                    shortcutSettings = GlobalShortcutService.defaultShortcuts
                    GlobalShortcutService.savePersistedShortcuts(shortcutSettings)
                    NotificationCenter.default.post(name: .traceFenceShortcutsChanged, object: nil)
                    shortcutMessage = localizer.t("已恢复默认快捷键。", en: "Default shortcuts restored.", zhHant: "已恢復預設快捷鍵。", ja: "デフォルトのショートカットに戻しました。", ko: "기본 단축키를 복원했습니다.", mt: "Default shortcuts restored.")
                }
                .buttonStyle(.borderless)
                .font(Theme.Font.caption)
            }

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(shortcutSettings, id: \.id) { shortcut in
                    shortcutRow(shortcut)
                }
            }
            .padding(.leading, 36)

            if let shortcutMessage {
                Text(shortcutMessage)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .padding(.leading, 36)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func shortcutRow(_ shortcut: GlobalShortcut) -> some View {
        let isRecording = recordingShortcutAction == shortcut.action
        return HStack(spacing: Theme.Spacing.sm) {
            Text(shortcut.action.localizedName(localizer))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(isRecording ? localizer.t("按下组合键…", en: "Press keys…", zhHant: "按下組合鍵…", ja: "キーを押す…", ko: "키를 누르세요…", mt: "Press keys…") : shortcut.displayString)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(isRecording ? Theme.Colors.warning : Theme.Colors.textSecondary)
                .lineLimit(1)
                .frame(minWidth: 96, alignment: .trailing)

            Button {
                beginShortcutRecording(for: shortcut.action)
            } label: {
                Image(systemName: isRecording ? "xmark.circle" : "record.circle")
                    .font(Theme.Font.captionMedium)
            }
            .buttonStyle(.plain)
            .help(isRecording ? localizer.cancel : localizer.t("录制快捷键", en: "Record shortcut", zhHant: "錄製快捷鍵", ja: "ショートカットを記録", ko: "단축키 기록", mt: "Record shortcut"))
        }
        .padding(.vertical, 3)
    }

    private var quitBehaviorSetting: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.purple)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.quitBehaviorTitle)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.quitBehaviorDesc)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.sm)
            }

            Picker("", selection: $quitBehavior) {
                Text(localizer.quitAppAndMenu).tag("quitAll")
                Text(localizer.quitAppKeepMenu).tag("quitAppOnly")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(
                title: localizer.t("TraceFence 订阅", en: "TraceFence Subscription", zhHant: "TraceFence 訂閱", ja: "TraceFence サブスクリプション", ko: "TraceFence 구독", mt: "Abbonament TraceFence"),
                icon: TraceFenceDistributionPolicy.currentChannel.isAppStore ? "creditcard.fill" : "key.fill"
            )
            Text(subscriptionIntroText)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)

            subscriptionChannelCard

            if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                appStoreSubscriptionControls
            } else {
                directSubscriptionControls
#if DEBUG
                debugDodoConfigurationSection
#endif
            }
        }
    }

    private var subscriptionChannelCard: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .fill(Theme.Colors.info.opacity(0.12))
                Image(systemName: TraceFenceDistributionPolicy.currentChannel.isAppStore ? "app.badge.fill" : "globe.badge.chevron.backward")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.info)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(installedChannelTitle)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(channelDetailText)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .cardStyle()
    }

    private var appStoreSubscriptionControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(appStoreStatusColor.opacity(0.12))
                    Image(systemName: appStoreStatusIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(appStoreStatusColor)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text(appStoreStatusTitle)
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(appStoreStatusDetail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if appStoreSubscriptionService.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let noticeText = appStoreNoticeText {
                Label(noticeText, systemImage: "info.circle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            appStoreSubscriptionButtons

            Text(localizer.t(
                "App Store 版只通过 Apple 应用内购买解锁，不显示官网结账或许可证密钥。",
                en: "The App Store build unlocks only through Apple in-app purchases and does not show website checkout or license keys.",
                zhHant: "App Store 版只透過 Apple App 內購買解鎖，不顯示官網結帳或授權金鑰。",
                ja: "App Store 版は Apple のアプリ内課金でのみ解除され、公式サイトの決済やライセンスキーは表示しません。",
                ko: "App Store 버전은 Apple 앱 내 구입으로만 잠금 해제되며 웹사이트 결제나 라이선스 키를 표시하지 않습니다.",
                mt: "Il-verżjoni tal-App Store tinfetaħ biss permezz ta' xiri fl-app ta' Apple u ma turix ħlas mis-sit jew ċwievet tal-liċenzja."
            ))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)

            appStoreLegalDisclosure
        }
        .cardStyle()
    }

    private var appStoreSubscriptionButtons: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(TraceFenceDistributionPolicy.appStoreProductIDs, id: \.self) { productID in
                if let product = appStoreSubscriptionService.products.first(where: { $0.id == productID }) {
                    appStoreProductButton(product)
                } else {
                    legacyProductPlaceholder(
                        title: appStoreProductTitle(productID),
                        detail: appStoreProductTerm(productID)
                    )
                }
            }

            if appStoreSubscriptionService.products.count < TraceFenceDistributionPolicy.appStoreProductIDs.count {
                Button {
                    Task { await appStoreSubscriptionService.refresh() }
                } label: {
                    Label(localizer.t(
                        "重新载入 Apple 价格",
                        en: "Reload Apple Prices",
                        zhHant: "重新載入 Apple 價格",
                        ja: "Apple の価格を再読み込み",
                        ko: "Apple 가격 다시 불러오기",
                        mt: "Erġa' tella' l-prezzijiet ta' Apple"
                    ), systemImage: "arrow.clockwise")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 34))
                .disabled(appStoreSubscriptionService.isLoading)
            }

            Button {
                Task { await appStoreSubscriptionService.restorePurchases() }
            } label: {
                Label(localizer.t(
                    "恢复购买",
                    en: "Restore Purchases",
                    zhHant: "恢復購買",
                    ja: "購入を復元",
                    ko: "구입 복원",
                    mt: "Irrestawra x-xiri"
                ), systemImage: "arrow.clockwise")
            }
            .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .ghost, minHeight: 34))
            .disabled(appStoreSubscriptionService.isLoading)
        }
    }

    private func legacyProductPlaceholder(title: String, detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            Text(localizer.t(
                "正在载入本地价格",
                en: "Loading local price",
                zhHant: "正在載入當地價格",
                ja: "現地価格を読み込み中",
                ko: "현지 가격 불러오는 중",
                mt: "Qed jitgħabba l-prezz lokali"
            ))
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.elevatedCardBg.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var appStoreLegalDisclosure: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(localizer.t(
                "付款确认后订阅将自动续订，除非在当前计费周期结束前至少 24 小时通过 Apple 取消。",
                en: "Payment is charged by Apple after confirmation. The subscription renews automatically unless canceled through Apple at least 24 hours before the end of the current billing period.",
                zhHant: "付款確認後訂閱將自動續訂，除非在目前計費週期結束前至少 24 小時透過 Apple 取消。",
                ja: "購入確認後、Apple により課金されます。現在の請求期間が終了する24時間前までに Apple で解約しない限り、自動更新されます。",
                ko: "구매 확인 후 Apple에서 결제됩니다. 현재 결제 기간 종료 최소 24시간 전에 Apple을 통해 취소하지 않으면 자동 갱신됩니다.",
                mt: "Payment is charged by Apple after confirmation. The subscription renews automatically unless canceled through Apple at least 24 hours before the end of the current billing period."
            ))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.lg) {
                Link(destination: TraceFenceDistributionPolicy.privacyPolicyURL) {
                    Label(localizer.t("隐私政策", en: "Privacy Policy", zhHant: "隱私權政策", ja: "プライバシーポリシー", ko: "개인정보 처리방침", mt: "Politika tal-Privatezza"), systemImage: "hand.raised.fill")
                }
                Link(destination: TraceFenceDistributionPolicy.standardEULAURL) {
                    Label(localizer.t("使用条款（EULA）", en: "Terms of Use (EULA)", zhHant: "使用條款（EULA）", ja: "利用規約（EULA）", ko: "이용 약관(EULA)", mt: "Termini tal-Użu (EULA)"), systemImage: "doc.text.fill")
                }
            }
            .font(Theme.Font.captionMedium)
        }
    }

    private func appStoreProductButton(_ product: Product) -> some View {
        Button {
            Task { await appStoreSubscriptionService.purchase(product) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appStoreProductTitle(product.id))
                        .font(Theme.Font.bodyMedium)
                    Text(appStoreProductTerm(product))
                        .font(Theme.Font.caption)
                }
                Spacer()
                Text(product.displayPrice)
                    .font(Theme.Font.bodyMedium)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 34))
        .disabled(appStoreSubscriptionService.isLoading)
    }

    private func appStoreProductTerm(_ product: Product) -> String {
        appStoreProductTerm(product.id)
    }

    private func appStoreProductTerm(_ productID: String) -> String {
        if productID == TraceFenceDistributionPolicy.appStoreProductIDs.first {
            return appStoreMonthlyTerm
        }
        return appStoreYearlyTerm
    }

    private var directSubscriptionControls: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ForEach(TraceFenceDistributionPolicy.directPlans) { plan in
                subscriptionPlanCard(plan)
            }

            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(licenseStatusColor.opacity(0.12))
                    Image(systemName: licenseStatusIcon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(licenseStatusColor)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(licenseStatusTitle)
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(licenseStatusDetail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if licenseService.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let message = licenseService.snapshot.message, !message.isEmpty {
                Label(message, systemImage: "info.circle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Theme.Colors.separator)

            HStack(spacing: Theme.Spacing.sm) {
                TextField(localizer.t("输入 License Key", en: "Enter license key", zhHant: "輸入 License Key", ja: "ライセンスキーを入力", ko: "라이선스 키 입력", mt: "Enter license key"), text: $licenseKeyInput)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.caption)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.elevatedCardBg.opacity(0.75))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .stroke(Theme.Colors.separator.opacity(0.75), lineWidth: 1)
                    )

                Button {
                    Task { await licenseService.activate(licenseKey: licenseKeyInput) }
                } label: {
                    Label(localizer.t("激活", en: "Activate", zhHant: "啟用", ja: "有効化", ko: "활성화", mt: "Activate"), systemImage: "checkmark.seal.fill")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 34))
                .disabled(licenseService.isBusy)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    licenseService.openPurchasePage(for: .monthly)
                } label: {
                    Label(
                        localizer.t(
                            "月付 · \(TraceFenceCheckoutPlan.monthly.priceLine)",
                            en: "Monthly · \(TraceFenceCheckoutPlan.monthly.priceLine)",
                            zhHant: "月付 · \(TraceFenceCheckoutPlan.monthly.priceLine)",
                            ja: "月払い · \(TraceFenceCheckoutPlan.monthly.priceLine)",
                            ko: "월간 · \(TraceFenceCheckoutPlan.monthly.priceLine)",
                            mt: "Monthly · \(TraceFenceCheckoutPlan.monthly.priceLine)"
                        ),
                        systemImage: "calendar"
                    )
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 32))
                .disabled(TraceFenceDistributionPolicy.checkoutURL(for: .monthly) == nil)

                Button {
                    licenseService.openPurchasePage(for: .annual)
                } label: {
                    Label(
                        localizer.t(
                            "年付 · \(TraceFenceCheckoutPlan.annual.priceLine)",
                            en: "Annual · \(TraceFenceCheckoutPlan.annual.priceLine)",
                            zhHant: "年付 · \(TraceFenceCheckoutPlan.annual.priceLine)",
                            ja: "年払い · \(TraceFenceCheckoutPlan.annual.priceLine)",
                            ko: "연간 · \(TraceFenceCheckoutPlan.annual.priceLine)",
                            mt: "Annual · \(TraceFenceCheckoutPlan.annual.priceLine)"
                        ),
                        systemImage: "calendar.badge.checkmark"
                    )
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.success, variant: .secondary, minHeight: 32))
                .disabled(TraceFenceDistributionPolicy.checkoutURL(for: .annual) == nil)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    Task { await licenseService.validateCurrentLicense() }
                } label: {
                    Label(localizer.t("重新验证", en: "Recheck", zhHant: "重新驗證", ja: "再確認", ko: "다시 확인", mt: "Recheck"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .ghost, minHeight: 32))
                .disabled(licenseService.isBusy)

                Button {
                    Task { await licenseService.deactivateCurrentLicense() }
                } label: {
                    Label(localizer.t("解绑本机", en: "Deactivate Mac", zhHant: "解除本機", ja: "このMacを解除", ko: "이 Mac 비활성화", mt: "Deactivate Mac"), systemImage: "xmark.circle")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.danger, variant: .ghost, minHeight: 32))
                .disabled(licenseService.isBusy || licenseService.snapshot.status == .unlicensed)
            }

            if TraceFenceDistributionPolicy.dodoEnvironment == .test {
                Label(
                    localizer.t(
                        "Dodo Payments 测试环境：支付不会产生真实扣款，测试 Key 不能用于正式版。",
                        en: "Dodo Payments Test Mode: no real charge is made, and test license keys cannot be used in production."
                    ),
                    systemImage: "testtube.2"
                )
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
            }

            if TraceFenceDistributionPolicy.checkoutURL(for: .monthly) == nil ||
                TraceFenceDistributionPolicy.checkoutURL(for: .annual) == nil {
                Text(localizer.t(
                    "Dodo Payments 的月付或年付商品 ID 尚未配置完整。",
                    en: "The Dodo Payments monthly or annual product ID is not fully configured."
                ))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .cardStyle()
    }

    private var marketplaceSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Colors.accent.opacity(0.12))
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.t("TraceFence 插件商城", en: "TraceFence Plugin Store"))
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t(
                        "免费插件可直接使用；付费插件支持 24 小时试用，配置独立商品后可单独购买。Standard 订阅包含所有符合当前宿主版本的插件。",
                        en: "Free plugins work immediately. Paid plugins include a 24-hour trial and can be purchased separately once their standalone offer is configured. Standard includes every plugin compatible with this host version."
                    ))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    Task { await marketplaceCatalogService.refresh(force: true) }
                } label: {
                    if marketplaceCatalogService.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(localizer.t("刷新", en: "Refresh"), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .ghost, minHeight: 34))
                .disabled(marketplaceCatalogService.isRefreshing)
            }
            .cardStyle()

            marketplaceCatalogStatus

            ForEach(marketplaceCatalogService.catalog.plugins) { plugin in
                marketplacePluginCard(plugin)
            }
        }
    }

    private var marketplaceCatalogStatus: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: TraceFenceMarketplaceCatalogRuntime.isUsingVerifiedRemoteCatalog
                ? "checkmark.shield.fill"
                : "internaldrive.fill")
                .foregroundStyle(TraceFenceMarketplaceCatalogRuntime.isUsingVerifiedRemoteCatalog
                    ? Theme.Colors.success
                    : Theme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(TraceFenceMarketplaceCatalogRuntime.isUsingVerifiedRemoteCatalog
                    ? localizer.t("已验证远程目录", en: "Verified remote catalog")
                    : localizer.t("正在使用内置离线目录", en: "Using built-in offline catalog"))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(localizer.t(
                    "目录修订版 \(marketplaceCatalogService.catalog.revision) · 价格以 Dodo 最终结账页为准",
                    en: "Catalog revision \(marketplaceCatalogService.catalog.revision) · Dodo checkout is the final billing authority"
                ))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.elevatedCardBg.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func marketplacePluginCard(_ plugin: TraceFencePluginDescriptor) -> some View {
        let access = pluginEntitlementService.accessState(pluginID: plugin.id)
        let offer = plugin.standaloneOfferID.flatMap { marketplaceCatalogService.catalog.offer(id: $0) }
        let isBusy = pluginEntitlementService.busyPluginIDs.contains(plugin.id)
        let hostVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let isCompatible = marketplaceCatalogService.catalog.isCompatible(plugin, hostVersion: hostVersion)

        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(plugin.featured ? Theme.Colors.accent.opacity(0.12) : Theme.Colors.elevatedCardBg)
                    Image(systemName: plugin.systemImage)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(plugin.featured ? Theme.Colors.accent : Theme.Colors.textSecondary)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(plugin.name)
                            .font(Theme.Font.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(plugin.delivery == .builtIn
                            ? localizer.t("内置", en: "Built in")
                            : localizer.t("可下载", en: "Download"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.Colors.separator.opacity(0.35))
                            .clipShape(Capsule())
                    }
                    Text(plugin.summary)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(plugin.category) · v\(plugin.version) · ID: \(plugin.id)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
                marketplaceAccessBadge(access, offer: offer, isCompatible: isCompatible)
            }

            if !isCompatible {
                Label(
                    localizer.t(
                        "需要 TraceFence \(plugin.minimumHostVersion) 或更高版本",
                        en: "Requires TraceFence \(plugin.minimumHostVersion) or later"
                    ),
                    systemImage: "arrow.up.circle"
                )
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.warning)
            } else if case .locked = access, !plugin.isFree {
                HStack(spacing: Theme.Spacing.sm) {
                    if let trialHours = plugin.trialHours {
                        Button {
                            pluginEntitlementService.beginTrial(pluginID: plugin.id)
                        } label: {
                            Label(localizer.t("试用 \(trialHours) 小时", en: "Try \(trialHours) hours"), systemImage: "timer")
                        }
                        .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 32))
                    }
                    if let offer {
                        Button {
                            pluginEntitlementService.openCheckout(pluginID: plugin.id)
                        } label: {
                            Label(localizer.t("购买 \(offer.displayPrice)", en: "Buy \(offer.displayPrice)"), systemImage: "cart.fill")
                        }
                        .buttonStyle(BrandButtonStyle(color: Theme.Colors.success, variant: .secondary, minHeight: 32))
                    }
                    if plugin.includedInAllAccess {
                        Button {
                            selectedTab = .license
                        } label: {
                            Label(localizer.t("订阅 Standard", en: "Subscribe Standard"), systemImage: "sparkles")
                        }
                        .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .ghost, minHeight: 32))
                    }
                }

                if plugin.standaloneOfferID != nil {
                    HStack(spacing: Theme.Spacing.sm) {
                        TextField(
                            localizer.t("输入此插件的 License Key", en: "Enter this plugin's license key"),
                            text: Binding(
                                get: { pluginLicenseInputs[plugin.id, default: ""] },
                                set: { pluginLicenseInputs[plugin.id] = $0 }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        Button(localizer.t("兑换", en: "Redeem")) {
                            Task {
                                await pluginEntitlementService.activate(
                                    pluginID: plugin.id,
                                    licenseKey: pluginLicenseInputs[plugin.id, default: ""]
                                )
                            }
                        }
                        .disabled(isBusy)
                    }
                }
            } else if case .licensed = access {
                HStack(spacing: Theme.Spacing.sm) {
                    Button(localizer.t("重新验证", en: "Recheck")) {
                        Task { await pluginEntitlementService.validate(pluginID: plugin.id) }
                    }
                    .disabled(isBusy)
                    Button(localizer.t("解绑", en: "Deactivate"), role: .destructive) {
                        Task { await pluginEntitlementService.deactivate(pluginID: plugin.id) }
                    }
                    .disabled(isBusy)
                }
            }

            if let message = pluginEntitlementService.grants[plugin.id]?.message, !message.isEmpty {
                Label(message, systemImage: "info.circle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        .cardStyle()
    }

    private func marketplaceAccessBadge(
        _ access: TraceFencePluginAccessState,
        offer: TraceFenceMarketplaceOffer?,
        isCompatible: Bool
    ) -> some View {
        let title: String
        let color: Color
        if !isCompatible {
            title = localizer.t("需更新", en: "Update required")
            color = Theme.Colors.warning
        } else { switch access {
        case .free:
            title = localizer.t("免费", en: "Free")
            color = Theme.Colors.success
        case .allAccess:
            title = "Standard"
            color = Theme.Colors.accent
        case .licensed:
            title = localizer.t("已购买", en: "Owned")
            color = Theme.Colors.success
        case .trial(let expiresAt):
            let hours = max(1, Int(ceil(expiresAt.timeIntervalSinceNow / 3600)))
            title = localizer.t("试用剩余 \(hours) 小时", en: "Trial · \(hours)h left")
            color = Theme.Colors.info
        case .locked:
            title = offer?.displayPrice ?? localizer.t("需授权", en: "License required")
            color = Theme.Colors.textSecondary
        } }
        return Text(title)
            .font(Theme.Font.captionMedium)
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.11))
            .clipShape(Capsule())
    }

#if DEBUG
    private var debugDodoConfigurationSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "testtube.2")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.warning)
                    .frame(width: 24)
                Text(localizer.t(
                    "Dodo 测试配置",
                    en: "Dodo Test Configuration",
                    zhHant: "Dodo 測試設定",
                    ja: "Dodo テスト設定",
                    ko: "Dodo 테스트 구성",
                    mt: "Dodo Test Configuration"
                ))
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("DEBUG ONLY")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.Colors.warning)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.Colors.warning.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }

            Text(localizer.t(
                "仅当前调试构建读取这些本机覆盖值；正式 Release 包会忽略它们，只读取包内的 Live 配置。",
                en: "Only this debug build reads these local overrides. Production Release builds ignore them and use only bundled Live configuration.",
                zhHant: "只有目前的除錯版本會讀取這些本機覆寫值；正式 Release 版本會忽略它們，只讀取套件內的 Live 設定。",
                ja: "このデバッグビルドだけがローカル上書きを読み取ります。正式な Release ビルドは無視し、バンドルされた Live 設定のみを使用します。",
                ko: "현재 디버그 빌드만 로컬 재정의 값을 읽습니다. 정식 Release 빌드는 이를 무시하고 번들된 Live 구성만 사용합니다.",
                mt: "Only this debug build reads these local overrides. Production Release builds ignore them and use only bundled Live configuration."
            ))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Spacing.md) {
                Text(localizer.t("环境", en: "Environment", zhHant: "環境", ja: "環境", ko: "환경", mt: "Environment"))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 92, alignment: .leading)
                Picker("", selection: $debugDodoEnvironment) {
                    Text("Test").tag(TraceFenceDodoEnvironment.test.rawValue)
                    Text("Live").tag(TraceFenceDodoEnvironment.live.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 260)
                Spacer()
            }

            debugDodoTextField(
                title: localizer.t("商户 ID", en: "Business ID", zhHant: "商戶 ID", ja: "事業者 ID", ko: "비즈니스 ID", mt: "Business ID"),
                text: $debugDodoBusinessID
            )
            debugDodoTextField(
                title: localizer.t("月付商品", en: "Monthly Product", zhHant: "月付商品", ja: "月額商品", ko: "월간 상품", mt: "Monthly Product"),
                text: $debugDodoMonthlyProductID
            )
            debugDodoTextField(
                title: localizer.t("年付商品", en: "Annual Product", zhHant: "年付商品", ja: "年額商品", ko: "연간 상품", mt: "Annual Product"),
                text: $debugDodoAnnualProductID
            )

            if debugDodoEnvironment == TraceFenceDodoEnvironment.live.rawValue {
                Label(
                    localizer.t(
                        "Live 环境可能产生真实扣款，请只使用专门的内部测试账号。",
                        en: "Live mode may create real charges. Use only a dedicated internal test account.",
                        zhHant: "Live 環境可能產生真實扣款，請只使用專門的內部測試帳號。",
                        ja: "Live 環境では実際に課金される可能性があります。専用の内部テストアカウントのみを使用してください。",
                        ko: "Live 환경에서는 실제 결제가 발생할 수 있습니다. 전용 내부 테스트 계정만 사용하세요.",
                        mt: "Live mode may create real charges. Use only a dedicated internal test account."
                    ),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.danger)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    saveDebugDodoConfiguration()
                } label: {
                    Label(localizer.t("应用测试配置", en: "Apply Test Configuration", zhHant: "套用測試設定", ja: "テスト設定を適用", ko: "테스트 구성 적용", mt: "Apply Test Configuration"), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .secondary, minHeight: 32))

                Button {
                    resetDebugDodoConfiguration()
                } label: {
                    Label(localizer.t("恢复内置值", en: "Restore Bundled Values", zhHant: "還原內建值", ja: "内蔵値に戻す", ko: "번들 값 복원", mt: "Restore Bundled Values"), systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .ghost, minHeight: 32))
            }

            if let message = debugDodoConfigurationMessage {
                Label(message, systemImage: debugDodoConfigurationSucceeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(Theme.Font.caption)
                    .foregroundStyle(debugDodoConfigurationSucceeded ? Theme.Colors.success : Theme.Colors.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private func debugDodoTextField(title: String, text: Binding<String>) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 92, alignment: .leading)
            TextField("", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 7)
                .background(Theme.Colors.elevatedCardBg.opacity(0.75))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.Colors.separator.opacity(0.75), lineWidth: 1)
                }
        }
    }

    private func loadDebugDodoConfiguration() {
        debugDodoEnvironment = TraceFenceDistributionPolicy.dodoEnvironment.rawValue
        debugDodoBusinessID = TraceFenceDistributionPolicy.dodoBusinessID ?? ""
        debugDodoMonthlyProductID = TraceFenceDistributionPolicy.dodoProductID(for: .monthly) ?? ""
        debugDodoAnnualProductID = TraceFenceDistributionPolicy.dodoProductID(for: .annual) ?? ""
        debugDodoConfigurationMessage = nil
    }

    private func saveDebugDodoConfiguration() {
        let businessID = debugDodoBusinessID.trimmingCharacters(in: .whitespacesAndNewlines)
        let monthlyProductID = debugDodoMonthlyProductID.trimmingCharacters(in: .whitespacesAndNewlines)
        let annualProductID = debugDodoAnnualProductID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard TraceFenceDodoEnvironment(rawValue: debugDodoEnvironment) != nil,
              businessID.range(of: #"^bus_[A-Za-z0-9]+$"#, options: .regularExpression) != nil,
              monthlyProductID.range(of: #"^pdt_[A-Za-z0-9]+$"#, options: .regularExpression) != nil,
              annualProductID.range(of: #"^pdt_[A-Za-z0-9]+$"#, options: .regularExpression) != nil else {
            debugDodoConfigurationSucceeded = false
            debugDodoConfigurationMessage = localizer.t(
                "配置格式不正确：商户 ID 应以 bus_ 开头，商品 ID 应以 pdt_ 开头。",
                en: "Invalid configuration. Business IDs must start with bus_ and product IDs with pdt_.",
                zhHant: "設定格式不正確：商戶 ID 應以 bus_ 開頭，商品 ID 應以 pdt_ 開頭。",
                ja: "設定形式が正しくありません。事業者 ID は bus_、商品 ID は pdt_ で始まる必要があります。",
                ko: "구성 형식이 올바르지 않습니다. 비즈니스 ID는 bus_, 상품 ID는 pdt_로 시작해야 합니다.",
                mt: "Invalid configuration. Business IDs must start with bus_ and product IDs with pdt_."
            )
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(debugDodoEnvironment, forKey: TraceFenceDistributionPolicy.dodoEnvironmentDefaultsKey)
        defaults.set(businessID, forKey: TraceFenceDistributionPolicy.dodoBusinessIDDefaultsKey)
        defaults.set(monthlyProductID, forKey: TraceFenceDistributionPolicy.dodoMonthlyProductIDDefaultsKey)
        defaults.set(annualProductID, forKey: TraceFenceDistributionPolicy.dodoAnnualProductIDDefaultsKey)
        debugDodoBusinessID = businessID
        debugDodoMonthlyProductID = monthlyProductID
        debugDodoAnnualProductID = annualProductID
        debugDodoConfigurationSucceeded = true
        debugDodoConfigurationMessage = localizer.t(
            "测试配置已生效，后续购买、激活和验证会立即使用这些值。",
            en: "The test configuration is active. New checkout, activation, and validation requests use it immediately.",
            zhHant: "測試設定已生效，後續購買、啟用和驗證會立即使用這些值。",
            ja: "テスト設定を適用しました。以後の購入、有効化、検証にすぐ使用されます。",
            ko: "테스트 구성이 적용되었습니다. 이후 구매, 활성화 및 검증 요청에 즉시 사용됩니다.",
            mt: "The test configuration is active. New checkout, activation, and validation requests use it immediately."
        )
    }

    private func resetDebugDodoConfiguration() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: TraceFenceDistributionPolicy.dodoEnvironmentDefaultsKey)
        defaults.removeObject(forKey: TraceFenceDistributionPolicy.dodoBusinessIDDefaultsKey)
        defaults.removeObject(forKey: TraceFenceDistributionPolicy.dodoMonthlyProductIDDefaultsKey)
        defaults.removeObject(forKey: TraceFenceDistributionPolicy.dodoAnnualProductIDDefaultsKey)
        loadDebugDodoConfiguration()
        debugDodoConfigurationSucceeded = true
        debugDodoConfigurationMessage = localizer.t(
            "已恢复当前 Debug 包内置的 Dodo 测试配置。",
            en: "Restored the Dodo test configuration bundled with this Debug build.",
            zhHant: "已還原目前 Debug 版本內建的 Dodo 測試設定。",
            ja: "この Debug ビルドに内蔵された Dodo テスト設定へ戻しました。",
            ko: "현재 Debug 빌드에 번들된 Dodo 테스트 구성을 복원했습니다.",
            mt: "Restored the Dodo test configuration bundled with this Debug build."
        )
    }
#endif

    private func subscriptionPlanCard(_ plan: TraceFenceSubscriptionPlan) -> some View {
        let isActive = isPlanActive(plan)
        return HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: isActive ? "checkmark.seal.fill" : "shield.lefthalf.filled")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(isActive ? Theme.Colors.success : Theme.Colors.accent)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(plan.title)
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if plan.isRecommended {
                        Text(localizer.t("推荐", en: "Recommended"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.success)
                            .clipShape(Capsule())
                    }
                    if isActive {
                        Text(localizer.t("当前", en: "Current"))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.Colors.accent)
                            .clipShape(Capsule())
                    }
                }
                Text(plan.priceLine)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(plan.featureLine)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(isActive ? Theme.Colors.success.opacity(0.08) : Theme.Colors.elevatedCardBg.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(isActive ? Theme.Colors.success.opacity(0.38) : Theme.Colors.separator.opacity(0.6), lineWidth: 1)
        )
    }

    private var remoteAccessSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: localizer.t("iOS 远程控制连接方式", en: "iOS Remote Control Connectivity"), icon: "iphone.radiowaves.left.and.right")
            Text(localizer.t(
                "TraceFence 不运行云端中继，也不保存你的 Agent 数据。iPhone 远程控制需要 Mac 暴露一个用户可到达的加密本地 API；客户端会引导你选择下面任一种连接方式。",
                en: "TraceFence does not run a cloud relay and does not store your agent data. iPhone remote control needs the Mac to expose an encrypted local API reachable by the user; the clients guide you through one of these connectivity options."
            ))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            remoteGatewayControlCard

            ForEach(TraceFenceRemoteAccessMode.allCases) { mode in
                remoteAccessRow(mode)
            }
        }
        .cardStyle()
    }

    private var remoteGatewayControlCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill((iOSRemoteGatewayService.isRunning ? Theme.Colors.success : Theme.Colors.textTertiary).opacity(0.12))
                    Image(systemName: iOSRemoteGatewayService.isRunning ? "antenna.radiowaves.left.and.right.circle.fill" : "antenna.radiowaves.left.and.right.slash")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(iOSRemoteGatewayService.isRunning ? Theme.Colors.success : Theme.Colors.textTertiary)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 3) {
                    Text(localizer.t("Mac 本地控制 API", en: "Mac Local Control API"))
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t(
                        "默认关闭。开启后 iOS 客户端用配对 token 直连这台 Mac；离开同一网络时，需要你自己的 VPN、DDNS/端口转发或反向隧道。",
                        en: "Off by default. When enabled, the iOS client connects directly to this Mac with a pairing token; away from the same network, it needs your own VPN, DDNS/port forwarding, or reverse tunnel."
                    ))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $iOSRemoteGatewayEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: iOSRemoteGatewayEnabled) { enabled in
                        iOSRemoteGatewayService.setEnabled(enabled, port: iOSRemoteGatewayPort)
                    }
            }

            Divider().overlay(Theme.Colors.separator.opacity(0.6))

            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(iOSRemoteGatewayService.statusMessage)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(iOSRemoteGatewayService.isRunning ? Theme.Colors.success : Theme.Colors.textSecondary)
                    Text(iOSRemoteGatewayService.endpoint)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Stepper(value: $iOSRemoteGatewayPort, in: 1024...65535, step: 1) {
                    Text(localizer.t("端口 \(iOSRemoteGatewayPort)", en: "Port \(iOSRemoteGatewayPort)"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(width: 150)
                .onChange(of: iOSRemoteGatewayPort) { port in
                    iOSRemoteGatewayService.restart(port: port)
                }
            }

            if iOSRemoteGatewayEnabled {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    TraceFenceQRCodeView(text: iOSRemoteGatewayService.compactPairingPayloadText)
                        .frame(width: 168, height: 168)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(localizer.t("iPhone 扫码配对", en: "Pair with iPhone"))
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.t(
                            "在 iOS 客户端打开“配对”，扫描这里的二维码即可导入 Mac 地址和配对密钥。",
                            en: "Open Pairing in the iOS client and scan this code to import the Mac endpoint and pairing token."
                        ))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(Theme.Spacing.sm)
                .background(Theme.Colors.cardBg.opacity(0.58))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    copyToPasteboard(iOSRemoteGatewayService.pairingPayloadText)
                } label: {
                    Label(localizer.t("复制 iOS 配对信息", en: "Copy iOS Pairing"), systemImage: "doc.on.doc")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 32))

                Button {
                    iOSRemoteGatewayService.rotatePairingToken()
                    copyToPasteboard(iOSRemoteGatewayService.pairingPayloadText)
                } label: {
                    Label(localizer.t("重置密钥", en: "Reset Token"), systemImage: "key.horizontal.fill")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .ghost, minHeight: 32))

                Spacer()
            }

            Text(localizer.t(
                "配对信息包含控制密钥，只给自己的 iPhone。TraceFence 不提供公网中继；公网可达性、防火墙规则和域名证书由用户自己的网络方案负责。",
                en: "Pairing includes the control token; share it only with your own iPhone. TraceFence does not provide a public relay; public reachability, firewall rules, and certificates belong to the user's own network setup."
            ))
            .font(.system(size: 11))
            .foregroundStyle(Theme.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.elevatedCardBg.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Colors.separator.opacity(0.62), lineWidth: 1)
        )
    }

    private func remoteAccessRow(_ mode: TraceFenceRemoteAccessMode) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Image(systemName: remoteAccessIcon(mode))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(remoteAccessColor(mode))
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(mode.title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(mode.requirement)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(mode.securityNote)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.elevatedCardBg.opacity(0.42))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private struct TraceFenceQRCodeView: View {
        let text: String

        var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .fill(Color.white)
                if let image = TraceFenceQRCodeImageFactory.image(from: text) {
                    Image(nsImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(4)
                } else {
                    Image(systemName: "qrcode")
                        .font(.system(size: 42, weight: .regular))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.Colors.separator.opacity(0.7), lineWidth: 1)
            )
            .accessibilityLabel("TraceFence iOS pairing QR code")
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
                        "TraceFence 不会自动清空废纸篓；受保护项在废纸篓中时会持续提醒。",
                        en: "TraceFence never empties Trash automatically. It reminds you while guarded items remain in Trash."
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
                        icon: "sparkles",
                        color: Theme.Colors.purple,
                        title: localizer.t("AI 磁盘顾问", en: "AI Disk Advisor", zhHant: "AI 磁碟顧問", ja: "AI ディスクアドバイザー", ko: "AI 디스크 어드바이저", mt: "AI Disk Advisor"),
                        desc: localizer.t("扫描用户授权的大文件、缓存和构建产物，并用 AI 解释作用、风险和清理建议。", en: "Scans user-authorized large files, caches, and build artifacts, then uses AI to explain purpose, risk, and cleanup advice.", zhHant: "掃描使用者授權的大型檔案、快取與建置產物，並用 AI 解釋用途、風險與清理建議。", ja: "ユーザーが許可した大きなファイル、キャッシュ、ビルド成果物をスキャンし、AI が用途、リスク、整理提案を説明します。", ko: "사용자가 승인한 대용량 파일, 캐시, 빌드 산출물을 스캔하고 AI가 용도, 위험, 정리 제안을 설명합니다.", mt: "Scans user-authorized large files, caches, and build artifacts, then uses AI to explain purpose, risk, and cleanup advice.")
                    )
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

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill((TraceFenceDistributionPolicy.currentChannel.isDirect ? Theme.Colors.accent : Theme.Colors.info).opacity(0.12))
                        Image(systemName: TraceFenceDistributionPolicy.currentChannel.isDirect ? "arrow.down.circle.fill" : "app.badge.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(TraceFenceDistributionPolicy.currentChannel.isDirect ? Theme.Colors.accent : Theme.Colors.info)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(appVersionTitle)
                            .font(Theme.Font.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(TraceFenceDistributionPolicy.currentChannel.isDirect
                             ? localizer.t(
                                "官网版更新将自动下载、校验、安装并重新启动，原有文件夹授权会继续保留。",
                                en: "Website build updates are downloaded, verified, installed, and relaunched automatically while preserving folder access."
                             )
                             : localizer.t(
                                "上架版通过 Mac App Store 更新。TraceFence 不会在上架版里下载或安装官网 DMG。",
                                en: "The App Store build updates through the Mac App Store. TraceFence does not download or install website DMGs in this build."
                             ))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    if updateService.isChecking || updateService.isDownloading || updateService.isInstalling {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if TraceFenceDistributionPolicy.currentChannel.isDirect {
                    Toggle(isOn: $automaticUpdateChecksEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizer.t("启动后自动检查更新", en: "Check for updates automatically", zhHant: "啟動後自動檢查更新", ja: "起動時に自動確認", ko: "시작 시 자동 업데이트 확인", mt: "Check for updates automatically"))
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(localizer.t("关闭后仍可手动检查；不会降低下载包的签名、校验和版本验证。", en: "Manual checks remain available; signature, checksum, and version verification are unchanged.", zhHant: "關閉後仍可手動檢查；簽章、校驗和版本驗證不變。", ja: "オフでも手動確認でき、署名・チェックサム・バージョン検証は維持されます。", ko: "꺼도 수동 확인이 가능하며 서명, 체크섬, 버전 검증은 유지됩니다.", mt: "Manual checks remain available; verification is unchanged."))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                if TraceFenceDistributionPolicy.currentChannel.isDirect, let latest = updateService.latestUpdate {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(localizer.t("发现新版本 v\(latest.version)", en: "New version available v\(latest.version)"))
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.success)
                        if !latest.notes.isEmpty {
                            Text(latest.notes)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(3)
                        }
                    }
                }

                if TraceFenceDistributionPolicy.currentChannel.isDirect, let message = updateService.message {
                    Label(message, systemImage: "info.circle")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider()
                    .overlay(Theme.Colors.separator.opacity(0.6))

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "terminal.fill")
                                .foregroundStyle(Theme.Colors.warning)
                            Text(localizer.t(
                                "AI CLI 安全更新",
                                en: "AI CLI Security Updates",
                                zhHant: "AI CLI 安全更新",
                                ja: "AI CLI セキュリティ更新",
                                ko: "AI CLI 보안 업데이트",
                                mt: "AI CLI Security Updates"
                            ))
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        }

                        Spacer()

                        Toggle(isOn: $cliUpdateStrongReminderEnabled) {
                            Text(localizer.t("强提醒", en: "Strong reminder", zhHant: "強提醒", ja: "強い通知", ko: "강한 알림", mt: "Strong reminder"))
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .tint(Theme.Colors.warning)
                    }

                    Text(cliUpdateStrongReminderEnabled
                         ? localizer.t(
                            "自动检查 Codex / Claude Code CLI；每个新版本只发送一次系统通知，主动检查时才显示弹窗。",
                            en: "TraceFence checks Codex / Claude Code CLI automatically. Each new version sends one macOS notification; alerts appear only for manual checks.",
                            zhHant: "自動檢查 Codex / Claude Code CLI；每個新版本只傳送一次系統通知，主動檢查時才顯示彈窗。",
                            ja: "Codex / Claude Code CLI を自動確認します。新しいバージョンごとに通知は一度だけ送信され、手動確認時のみアラートを表示します。",
                            ko: "Codex / Claude Code CLI를 자동으로 확인합니다. 새 버전마다 macOS 알림은 한 번만 보내며, 수동 확인 때만 팝업을 표시합니다.",
                            mt: "TraceFence checks Codex / Claude Code CLI automatically. Each new version sends one macOS notification; alerts appear only for manual checks."
                         )
                         : localizer.t(
                            "强提醒已关闭。TraceFence 仍会检查 CLI 状态，但只在这里显示结果。",
                            en: "Strong reminders are off. TraceFence still checks CLI status, but only shows results here.",
                            zhHant: "強提醒已關閉。TraceFence 仍會檢查 CLI 狀態，但只在這裡顯示結果。",
                            ja: "強い通知はオフです。TraceFence は CLI 状態を確認しますが、結果はここにのみ表示します。",
                            ko: "강한 알림이 꺼져 있습니다. TraceFence는 CLI 상태를 계속 확인하지만 결과는 여기에서만 표시합니다.",
                            mt: "Strong reminders are off. TraceFence still checks CLI status, but only shows results here."
                         ))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    if updateService.cliToolUpdates.isEmpty {
                        Text(localizer.t(
                            "点击“检查更新”后会显示 Codex / Claude CLI 的本机版本和最新版本。",
                            en: "Click Check for Updates to show local and latest Codex / Claude CLI versions.",
                            zhHant: "點擊「檢查更新」後會顯示 Codex / Claude CLI 的本機版本和最新版本。",
                            ja: "「アップデートを確認」を押すと、Codex / Claude CLI のローカル版と最新版を表示します。",
                            ko: "업데이트 확인을 누르면 Codex / Claude CLI의 로컬 버전과 최신 버전을 표시합니다.",
                            mt: "Click Check for Updates to show local and latest Codex / Claude CLI versions."
                        ))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    } else {
                        ForEach(updateService.cliToolUpdates) { result in
                            cliUpdateRow(result)
                        }
                    }
                }

                if TraceFenceDistributionPolicy.currentChannel.isDirect {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            Task { await updateService.checkForUpdates(userInitiated: true) }
                        } label: {
                            Label(updateService.isChecking ? localizer.downloadingUpdate : localizer.checkUpdate, systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .secondary, minHeight: 32))
                        .disabled(updateService.isChecking || updateService.isDownloading || updateService.isInstalling)

                        if updateService.latestUpdate != nil {
                            Button {
                                Task { await updateService.downloadLatestUpdate() }
                            } label: {
                                Label(
                                    updateService.isDownloading
                                        ? localizer.downloadingUpdateFmt
                                        : updateService.isInstalling
                                            ? localizer.t("正在安装…", en: "Installing…", zhHant: "正在安裝…", ja: "インストール中…", ko: "설치 중…", mt: "Installing…")
                                            : localizer.t("更新并重启", en: "Update and Relaunch", zhHant: "更新並重新啟動", ja: "更新して再起動", ko: "업데이트 및 재시작", mt: "Update and Relaunch"),
                                    systemImage: "arrow.down.circle.fill"
                                )
                            }
                            .buttonStyle(BrandButtonStyle(color: Theme.Colors.success, variant: .primary, minHeight: 32))
                            .disabled(updateService.isChecking || updateService.isDownloading || updateService.isInstalling)
                        }
                    }
                } else {
                    Label(localizer.t("当前安装包的应用更新由 Mac App Store 管理。", en: "App updates for this build are managed by the Mac App Store."), systemImage: "app.badge")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .cardStyle()
        }
    }

    private func cliUpdateRow(_ result: CLIUpdateCheckResult) -> some View {
        let color = cliStatusColor(result.status)
        return VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                Image(systemName: cliStatusIcon(result.status))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(result.displayName)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(cliVersionLine(result))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                Text(cliStatusText(result))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(color)
            }

            if result.needsStrongReminder {
                if case .checkFailed(let reason) = result.status {
                    Text(cliFailureDetail(result, reason: reason))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Text(result.updateCommand)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.sidebarBg.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                    Button {
                        copyToPasteboard(result.updateCommand)
                    } label: {
                        Label(localizer.t("复制", en: "Copy", zhHant: "複製", ja: "コピー", ko: "복사", mt: "Copy"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .ghost, minHeight: 28))

                    Button {
                        NSWorkspace.shared.open(result.packageURL)
                    } label: {
                        Label(localizer.t("包页", en: "Package", zhHant: "套件頁", ja: "パッケージ", ko: "패키지", mt: "Package"), systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .ghost, minHeight: 28))
                }
            } else if case .checkFailed(let reason) = result.status {
                Text(reason)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.sm)
        .background(color.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func cliVersionLine(_ result: CLIUpdateCheckResult) -> String {
        switch result.status {
        case .notInstalled:
            return localizer.t(
                "未检测到 \(result.commandName) 命令",
                en: "\(result.commandName) command not found",
                zhHant: "未偵測到 \(result.commandName) 命令",
                ja: "\(result.commandName) コマンドが見つかりません",
                ko: "\(result.commandName) 명령을 찾을 수 없습니다",
                mt: "\(result.commandName) command not found"
            )
        default:
            let installed = result.installedVersion ?? localizer.t("未知", en: "unknown", zhHant: "未知", ja: "不明", ko: "알 수 없음", mt: "unknown")
            let latest = result.latestVersion ?? localizer.t("未知", en: "unknown", zhHant: "未知", ja: "不明", ko: "알 수 없음", mt: "unknown")
            return localizer.t(
                "本机 \(installed) · 最新 \(latest)",
                en: "Local \(installed) · Latest \(latest)",
                zhHant: "本機 \(installed) · 最新 \(latest)",
                ja: "ローカル \(installed) · 最新 \(latest)",
                ko: "로컬 \(installed) · 최신 \(latest)",
                mt: "Local \(installed) · Latest \(latest)"
            )
        }
    }

    private func cliStatusText(_ result: CLIUpdateCheckResult) -> String {
        switch result.status {
        case .upToDate:
            return localizer.t("最新", en: "Current", zhHant: "最新", ja: "最新", ko: "최신", mt: "Current")
        case .updateAvailable:
            return localizer.t("需要升级", en: "Update now", zhHant: "需要升級", ja: "更新が必要", ko: "업데이트 필요", mt: "Update now")
        case .notInstalled:
            return localizer.t("未安装", en: "Not installed", zhHant: "未安裝", ja: "未インストール", ko: "미설치", mt: "Not installed")
        case .checkFailed:
            if result.installedPath != nil, result.installedVersion == nil {
                return localizer.t("需重装", en: "Reinstall", zhHant: "需重裝", ja: "再インストール", ko: "재설치 필요", mt: "Reinstall")
            }
            return localizer.t("检查失败", en: "Check failed", zhHant: "檢查失敗", ja: "確認失敗", ko: "확인 실패", mt: "Check failed")
        }
    }

    private func cliStatusIcon(_ status: CLIUpdateStatus) -> String {
        switch status {
        case .upToDate:
            return "checkmark.circle.fill"
        case .updateAvailable:
            return "exclamationmark.triangle.fill"
        case .notInstalled:
            return "minus.circle.fill"
        case .checkFailed:
            return "wrench.and.screwdriver.fill"
        }
    }

    private func cliStatusColor(_ status: CLIUpdateStatus) -> Color {
        switch status {
        case .upToDate:
            return Theme.Colors.success
        case .updateAvailable:
            return Theme.Colors.warning
        case .notInstalled:
            return Theme.Colors.textTertiary
        case .checkFailed:
            return Theme.Colors.warning
        }
    }

    private func cliFailureDetail(_ result: CLIUpdateCheckResult, reason: String) -> String {
        if let path = result.installedPath, result.installedVersion == nil {
            return localizer.t(
                "已找到 \(result.commandName)，但无法读取版本，通常是 CLI 安装不完整或 native binary 缺失。路径：\(path)",
                en: "\(result.commandName) was found, but its version could not be read. The install is likely incomplete or missing its native binary. Path: \(path)",
                zhHant: "已找到 \(result.commandName)，但無法讀取版本，通常是 CLI 安裝不完整或 native binary 缺失。路徑：\(path)",
                ja: "\(result.commandName) は見つかりましたが、バージョンを読み取れません。CLI のインストールが不完全、または native binary が欠落している可能性があります。パス: \(path)",
                ko: "\(result.commandName)을 찾았지만 버전을 읽을 수 없습니다. CLI 설치가 불완전하거나 native binary가 누락되었을 수 있습니다. 경로: \(path)",
                mt: "\(result.commandName) was found, but its version could not be read. The install is likely incomplete or missing its native binary. Path: \(path)"
            )
        }
        return reason
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private var appStoreURL: URL? {
        guard let appStoreID = Bundle.main.object(forInfoDictionaryKey: "AppStoreID") as? String,
              appStoreID.range(of: #"^\d+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return URL(string: "macappstore://apps.apple.com/app/id\(appStoreID)")
    }

    private var appVersionTitle: String {
        if TraceFenceDistributionPolicy.currentChannel.isAppStore {
            return "TraceFence \(updateService.currentVersion) (\(updateService.currentBuildNumber)) · Mac App Store"
        }
        return localizer.t(
            "TraceFence \(updateService.currentVersion) · 官网版",
            en: "TraceFence \(updateService.currentVersion) · Website Build",
            zhHant: "TraceFence \(updateService.currentVersion) · 官網版",
            ja: "TraceFence \(updateService.currentVersion) · 公式サイト版",
            ko: "TraceFence \(updateService.currentVersion) · 웹사이트 버전",
            mt: "TraceFence \(updateService.currentVersion) · Verżjoni tas-Sit"
        )
    }

    private var installedChannelTitle: String {
        if TraceFenceDistributionPolicy.currentChannel.isAppStore {
            return localizer.t(
                "当前安装渠道：Mac App Store",
                en: "Installed channel: Mac App Store",
                zhHant: "目前安裝管道：Mac App Store",
                ja: "インストール元：Mac App Store",
                ko: "설치 채널: Mac App Store",
                mt: "Kanal tal-installazzjoni: Mac App Store"
            )
        }
        return localizer.t(
            "当前安装渠道：TraceFence 官网",
            en: "Installed channel: TraceFence Website",
            zhHant: "目前安裝管道：TraceFence 官網",
            ja: "インストール元：TraceFence 公式サイト",
            ko: "설치 채널: TraceFence 웹사이트",
            mt: "Kanal tal-installazzjoni: is-Sit ta' TraceFence"
        )
    }

    private var subscriptionIntroText: String {
        if TraceFenceDistributionPolicy.currentChannel.isAppStore {
            return localizer.t(
                "请选择月度或年度自动续订方案。商品名称、订阅周期和所在商店的价格会在下方完整显示，购买由 Apple 处理。",
                en: "Choose a monthly or yearly auto-renewable plan. The product name, subscription period, and storefront price are shown below, and Apple handles the purchase.",
                zhHant: "請選擇月度或年度自動續訂方案。商品名稱、訂閱週期和所在商店的價格會在下方完整顯示，購買由 Apple 處理。",
                ja: "月額または年額の自動更新プランを選択してください。商品名、期間、ストア価格は以下に表示され、購入は Apple が処理します。",
                ko: "월간 또는 연간 자동 갱신 요금제를 선택하세요. 상품명, 구독 기간, 스토어 가격이 아래에 표시되며 결제는 Apple에서 처리합니다.",
                mt: "Agħżel pjan li jiġġedded kull xahar jew kull sena. L-isem, il-perjodu u l-prezz tal-ħanut jidhru hawn taħt, u x-xiri jiġi pproċessat minn Apple."
            )
        }
        return localizer.t(
            "官网版提供 TraceFence 标准版月度和年度订阅，并使用许可证密钥激活。",
            en: "The website build offers monthly and yearly TraceFence Standard subscriptions activated with a license key.",
            zhHant: "官網版提供 TraceFence 標準版月度和年度訂閱，並使用授權金鑰啟用。",
            ja: "公式サイト版では TraceFence Standard の月額・年額プランを提供し、ライセンスキーで有効化します。",
            ko: "웹사이트 버전은 TraceFence Standard 월간 및 연간 구독을 제공하며 라이선스 키로 활성화합니다.",
            mt: "Il-verżjoni tas-sit toffri abbonamenti TraceFence Standard ta' kull xahar u ta' kull sena, attivati b'ċavetta tal-liċenzja."
        )
    }

    private var channelDetailText: String {
        switch TraceFenceDistributionPolicy.currentChannel {
        case .appStore:
            return localizer.t(
                "此版本仅使用 Apple 应用内购买，不显示官网结账或许可证密钥。订阅后可使用 Agent 时间线、AI 报告、iPhone 远程控制和审批功能。",
                en: "This build uses Apple in-app purchases only and does not show website checkout or license keys. A subscription unlocks agent timelines, AI reports, iPhone remote control, and approvals.",
                zhHant: "此版本僅使用 Apple App 內購買，不顯示官網結帳或授權金鑰。訂閱後可使用 Agent 時間線、AI 報告、iPhone 遠端控制和審批功能。",
                ja: "このバージョンは Apple のアプリ内課金のみを使用し、公式サイトの決済やライセンスキーは表示しません。サブスクリプションで Agent タイムライン、AI レポート、iPhone 遠隔操作、承認機能を利用できます。",
                ko: "이 버전은 Apple 앱 내 구입만 사용하며 웹사이트 결제나 라이선스 키를 표시하지 않습니다. 구독하면 Agent 타임라인, AI 보고서, iPhone 원격 제어 및 승인 기능을 사용할 수 있습니다.",
                mt: "Din il-verżjoni tuża biss xiri fl-app ta' Apple u ma turix ħlas mis-sit jew ċwievet tal-liċenzja. Abbonament jiftaħ il-linja taż-żmien tal-Agent, rapporti tal-AI, kontroll mill-iPhone u approvazzjonijiet."
            )
        case .direct:
            return localizer.t(
                "官网版当前只提供 TraceFence Standard，由 Dodo Payments 处理月付或年付订阅、税务和账单。",
                en: "The website build currently offers TraceFence Standard only. Dodo Payments handles monthly or annual subscriptions, taxes, and billing.",
                zhHant: "官網版目前只提供 TraceFence Standard，由 Dodo Payments 處理月付或年付訂閱、稅務和帳單。",
                ja: "公式サイト版では現在 TraceFence Standard のみを提供し、月額・年額のサブスクリプション、税金、請求は Dodo Payments が処理します。",
                ko: "웹사이트 버전은 현재 TraceFence Standard만 제공하며 월간 또는 연간 구독, 세금 및 청구는 Dodo Payments에서 처리합니다.",
                mt: "Il-verżjoni tas-sit bħalissa toffri TraceFence Standard biss. Dodo Payments tipproċessa l-abbonamenti, it-taxxi u l-ħlasijiet."
            )
        }
    }

    private var appStoreMonthlyTerm: String {
        localizer.t(
            "1 个月 · 每月自动续订",
            en: "1 month · auto-renews monthly",
            zhHant: "1 個月 · 每月自動續訂",
            ja: "1か月 · 毎月自動更新",
            ko: "1개월 · 매월 자동 갱신",
            mt: "Xahar · jiġġedded kull xahar"
        )
    }

    private var appStoreYearlyTerm: String {
        localizer.t(
            "1 年 · 每年自动续订",
            en: "1 year · auto-renews yearly",
            zhHant: "1 年 · 每年自動續訂",
            ja: "1年 · 毎年自動更新",
            ko: "1년 · 매년 자동 갱신",
            mt: "Sena · jiġġedded kull sena"
        )
    }

    private func appStoreProductTitle(_ productID: String) -> String {
        let isMonthly = productID == TraceFenceDistributionPolicy.appStoreProductIDs.first
        if isMonthly {
            return localizer.t(
                "TraceFence 标准版（月度）",
                en: "TraceFence Standard Monthly",
                zhHant: "TraceFence 標準版（月度）",
                ja: "TraceFence Standard（月額）",
                ko: "TraceFence Standard 월간",
                mt: "TraceFence Standard ta' Kull Xahar"
            )
        }
        return localizer.t(
            "TraceFence 标准版（年度）",
            en: "TraceFence Standard Yearly",
            zhHant: "TraceFence 標準版（年度）",
            ja: "TraceFence Standard（年額）",
            ko: "TraceFence Standard 연간",
            mt: "TraceFence Standard ta' Kull Sena"
        )
    }

    private var appStoreNoticeText: String? {
        guard let notice = appStoreSubscriptionService.notice else { return nil }
        switch notice {
        case .productsUnavailable:
            return localizer.t(
                "暂时无法从 Apple 载入价格。请检查网络后重试；月度和年度方案仍列在下方。",
                en: "Apple prices are temporarily unavailable. Check the network and try again; both plans remain listed below.",
                zhHant: "暫時無法從 Apple 載入價格。請檢查網路後重試；月度和年度方案仍列在下方。",
                ja: "Apple の価格を一時的に読み込めません。ネットワークを確認して再試行してください。両方のプランは下に表示されています。",
                ko: "Apple 가격을 일시적으로 불러올 수 없습니다. 네트워크를 확인한 후 다시 시도하세요. 두 요금제는 아래에 계속 표시됩니다.",
                mt: "Il-prezzijiet ta' Apple mhumiex disponibbli bħalissa. Iċċekkja n-network u erġa' pprova; iż-żewġ pjanijiet jibqgħu jidhru hawn taħt."
            )
        case .subscriptionActive:
            return localizer.t("订阅已激活。", en: "Subscription active.", zhHant: "訂閱已啟用。", ja: "サブスクリプションが有効になりました。", ko: "구독이 활성화되었습니다.", mt: "L-abbonament huwa attiv.")
        case .purchaseCancelled:
            return localizer.t("已取消购买。", en: "Purchase canceled.", zhHant: "已取消購買。", ja: "購入をキャンセルしました。", ko: "구입이 취소되었습니다.", mt: "Ix-xiri ġie kkanċellat.")
        case .purchasePending:
            return localizer.t("购买正在等待批准。", en: "Purchase is awaiting approval.", zhHant: "購買正在等待批准。", ja: "購入は承認待ちです。", ko: "구입이 승인 대기 중입니다.", mt: "Ix-xiri qed jistenna l-approvazzjoni.")
        case .purchaseStateUnknown:
            return localizer.t("暂时无法确认购买状态，请稍后刷新。", en: "The purchase status could not be confirmed. Refresh shortly.", zhHant: "暫時無法確認購買狀態，請稍後重新整理。", ja: "購入状態を確認できません。しばらくしてから更新してください。", ko: "구입 상태를 확인할 수 없습니다. 잠시 후 새로 고치세요.", mt: "L-istat tax-xiri ma setax jiġi kkonfermat. Aġġorna dalwaqt.")
        case .subscriptionRestored:
            return localizer.t("订阅已恢复。", en: "Subscription restored.", zhHant: "訂閱已恢復。", ja: "サブスクリプションを復元しました。", ko: "구독이 복원되었습니다.", mt: "L-abbonament ġie rrestawrat.")
        case .noActiveSubscription:
            return localizer.t("没有找到有效订阅。", en: "No active subscription was found.", zhHant: "沒有找到有效訂閱。", ja: "有効なサブスクリプションが見つかりません。", ko: "활성 구독을 찾을 수 없습니다.", mt: "Ma nstab ebda abbonament attiv.")
        case .requestFailed:
            return localizer.t("无法连接 Apple 购买服务，请检查网络后重试。", en: "Apple's purchase service could not be reached. Check the network and try again.", zhHant: "無法連接 Apple 購買服務，請檢查網路後重試。", ja: "Apple の購入サービスに接続できません。ネットワークを確認して再試行してください。", ko: "Apple 구입 서비스에 연결할 수 없습니다. 네트워크를 확인한 후 다시 시도하세요.", mt: "Ma setax jintlaħaq is-servizz tax-xiri ta' Apple. Iċċekkja n-network u erġa' pprova.")
        }
    }

    private var appStoreStatusTitle: String {
        if appStoreSubscriptionService.isSubscribed {
            return localizer.t("App Store 订阅已激活", en: "App Store subscription active", zhHant: "App Store 訂閱已啟用", ja: "App Store サブスクリプション有効", ko: "App Store 구독 활성", mt: "L-abbonament tal-App Store huwa attiv")
        }
        if appStoreSubscriptionService.isLoading {
            return localizer.t("正在同步订阅", en: "Syncing subscription", zhHant: "正在同步訂閱", ja: "サブスクリプションを同期中", ko: "구독 동기화 중", mt: "Qed jiġi sinkronizzat l-abbonament")
        }
        return localizer.t("尚未订阅", en: "Not subscribed", zhHant: "尚未訂閱", ja: "未登録", ko: "구독하지 않음", mt: "Mhux abbonat")
    }

    private var appStoreStatusDetail: String {
        if let expiresAt = appStoreSubscriptionService.expiresAt {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            formatter.locale = Locale(identifier: localizer.language.rawValue)
            return localizer.t(
                "当前方案：\(appStoreProductTitle(appStoreSubscriptionService.activeProductID ?? ""))，有效期至 \(formatter.string(from: expiresAt))。",
                en: "Current plan: \(appStoreProductTitle(appStoreSubscriptionService.activeProductID ?? "")), valid until \(formatter.string(from: expiresAt)).",
                zhHant: "目前方案：\(appStoreProductTitle(appStoreSubscriptionService.activeProductID ?? ""))，有效期至 \(formatter.string(from: expiresAt))。",
                ja: "現在のプラン：\(appStoreProductTitle(appStoreSubscriptionService.activeProductID ?? ""))。有効期限：\(formatter.string(from: expiresAt))。",
                ko: "현재 요금제: \(appStoreProductTitle(appStoreSubscriptionService.activeProductID ?? "")), 유효 기간: \(formatter.string(from: expiresAt)).",
                mt: "Pjan attwali: \(appStoreProductTitle(appStoreSubscriptionService.activeProductID ?? "")), validu sa \(formatter.string(from: expiresAt))."
            )
        }
        if appStoreSubscriptionService.isSubscribed {
            return localizer.t("Apple 已确认当前订阅有效。", en: "Apple confirmed the current subscription is active.", zhHant: "Apple 已確認目前訂閱有效。", ja: "Apple が現在のサブスクリプションを有効と確認しました。", ko: "Apple에서 현재 구독이 유효함을 확인했습니다.", mt: "Apple ikkonfermat li l-abbonament attwali huwa attiv.")
        }
        return localizer.t(
            "按月或按年订阅后可解锁标准版能力；购买、退款和续订都由 Apple 处理。",
            en: "Subscribe monthly or yearly to unlock Standard features. Purchases, refunds, and renewals are handled by Apple.",
            zhHant: "按月或按年訂閱後可解鎖標準版功能；購買、退款和續訂都由 Apple 處理。",
            ja: "月額または年額で登録すると Standard 機能を利用できます。購入、返金、更新は Apple が処理します。",
            ko: "월간 또는 연간 구독으로 Standard 기능을 사용할 수 있습니다. 구입, 환불 및 갱신은 Apple에서 처리합니다.",
            mt: "Abbona kull xahar jew kull sena biex tiftaħ il-karatteristiċi Standard. Ix-xiri, ir-rifużjonijiet u t-tiġdid jiġu pproċessati minn Apple."
        )
    }

    private var appStoreStatusIcon: String {
        appStoreSubscriptionService.isSubscribed ? "checkmark.seal.fill" : "cart.badge.plus"
    }

    private var appStoreStatusColor: Color {
        appStoreSubscriptionService.isSubscribed ? Theme.Colors.success : Theme.Colors.accent
    }

    private func isPlanActive(_ plan: TraceFenceSubscriptionPlan) -> Bool {
        switch plan.id {
        case .appStoreStandard:
            return appStoreSubscriptionService.isSubscribed
        case .directStandard:
            return licenseService.currentTier == plan.id
        case .none:
            return false
        }
    }

    private func remoteAccessIcon(_ mode: TraceFenceRemoteAccessMode) -> String {
        switch mode {
        case .localNetwork: return "wifi"
        case .tailnetVPN: return "lock.icloud.fill"
        case .publicEndpoint: return "network"
        case .reverseTunnel: return "arrow.triangle.turn.up.right.diamond.fill"
        }
    }

    private func remoteAccessColor(_ mode: TraceFenceRemoteAccessMode) -> Color {
        switch mode {
        case .localNetwork: return Theme.Colors.success
        case .tailnetVPN: return Theme.Colors.info
        case .publicEndpoint: return Theme.Colors.warning
        case .reverseTunnel: return Theme.Colors.purple
        }
    }

    private var licenseStatusTitle: String {
        if licenseService.isTrialActive {
            return localizer.t("48 小时试用中", en: "48-hour trial active", zhHant: "48 小時試用中", ja: "48時間トライアル中", ko: "48시간 평가판 사용 중", mt: "48-hour trial active")
        }
        if licenseService.isTrialExpired {
            return localizer.t("试用已结束", en: "Trial ended", zhHant: "試用已結束", ja: "トライアル終了", ko: "평가판 종료", mt: "Trial ended")
        }
        switch licenseService.snapshot.status {
        case .licensed:
            switch licenseService.currentTier {
            case .directStandard:
                return localizer.t("官网标准订阅已激活", en: "Website Standard active")
            default:
                return localizer.t("授权已激活", en: "License active", zhHant: "授權已啟用", ja: "ライセンス有効", ko: "라이선스 활성", mt: "License active")
            }
        case .expired:
            return localizer.t("授权已过期", en: "License expired", zhHant: "授權已過期", ja: "ライセンス期限切れ", ko: "라이선스 만료", mt: "License expired")
        case .disabled:
            return localizer.t("授权已停用", en: "License disabled", zhHant: "授權已停用", ja: "ライセンス無効", ko: "라이선스 비활성", mt: "License disabled")
        case .inactive:
            return localizer.t("授权未激活", en: "License inactive", zhHant: "授權未啟用", ja: "ライセンス未有効", ko: "라이선스 미활성", mt: "License inactive")
        case .validating:
            return localizer.t("正在验证授权", en: "Validating license", zhHant: "正在驗證授權", ja: "ライセンス確認中", ko: "라이선스 확인 중", mt: "Validating license")
        case .error:
            return localizer.t("授权验证异常", en: "License check failed", zhHant: "授權驗證異常", ja: "ライセンス確認失敗", ko: "라이선스 확인 실패", mt: "License check failed")
        case .unlicensed:
            return localizer.t("尚未授权", en: "Not licensed", zhHant: "尚未授權", ja: "未ライセンス", ko: "라이선스 없음", mt: "Not licensed")
        }
    }

    private var licenseStatusDetail: String {
        let snapshot = licenseService.snapshot
        switch snapshot.status {
        case .licensed:
            if licenseService.currentTier == .directStandard {
                let planName = snapshot.productName ?? "TraceFence Standard"
                return localizer.t(
                    "这台 Mac 已通过 Dodo Payments 激活：\(planName)。",
                    en: "This Mac is activated through Dodo Payments: \(planName).",
                    zhHant: "這台 Mac 已透過 Dodo Payments 啟用：\(planName)。",
                    ja: "この Mac は Dodo Payments 経由で有効化されています：\(planName)。",
                    ko: "이 Mac은 Dodo Payments를 통해 활성화되었습니다: \(planName).",
                    mt: "This Mac is activated through Dodo Payments: \(planName)."
                )
            }
            if licenseService.licenseSyncedThisRun {
                let usage = licenseUsageText(snapshot)
                return localizer.t(
                    "这台 Mac 已绑定。\(usage)",
                    en: "This Mac is activated. \(usage)",
                    zhHant: "這台 Mac 已綁定。\(usage)",
                    ja: "このMacは有効化済みです。\(usage)",
                    ko: "이 Mac은 활성화되었습니다. \(usage)",
                    mt: "This Mac is activated. \(usage)"
                )
            }
            return localizer.t(
                "这台 Mac 已绑定。点击“重新验证”同步最新设备名额。",
                en: "This Mac is activated. Click Recheck to sync the latest device limit.",
                zhHant: "這台 Mac 已綁定。點擊「重新驗證」同步最新裝置名額。",
                ja: "このMacは有効化済みです。「再確認」をクリックして最新のデバイス上限を同期してください。",
                ko: "이 Mac은 활성화되었습니다. 다시 확인을 눌러 최신 기기 한도를 동기화하세요.",
                mt: "This Mac is activated. Click Recheck to sync the latest device limit."
            )
        case .unlicensed:
            if licenseService.isTrialActive {
                return localizer.t(
                    "剩余 \(trialRemainingText)。试用期内可扫描、浏览和预览；订阅后解锁持续监控、远程审批和高级操作。",
                    en: "\(trialRemainingText) left. Trial can scan, browse, and preview; subscription unlocks ongoing monitoring, remote approvals, and advanced actions.",
                    zhHant: "剩餘 \(trialRemainingText)。試用期內可掃描、瀏覽和預覽；訂閱後解鎖持續監控、遠端審批和高級操作。",
                    ja: "残り \(trialRemainingText)。トライアルではスキャン、閲覧、プレビューが使え、サブスクリプションで継続監視、リモート承認、高度な操作が解放されます。",
                    ko: "\(trialRemainingText) 남음. 평가판은 스캔, 탐색, 미리보기를 사용할 수 있고 구독하면 지속 모니터링, 원격 승인, 고급 작업을 사용할 수 있습니다.",
                    mt: "\(trialRemainingText) left. Trial can scan, browse, and preview; subscription unlocks ongoing monitoring, remote approvals, and advanced actions."
                )
            }
            if licenseService.isTrialExpired {
                return localizer.t(
                    "48 小时试用已结束。订阅官网 Standard 后可继续使用 TraceFence v2 能力。",
                    en: "The 48-hour trial has ended. Subscribe to Website Standard to continue using TraceFence v2 capabilities.",
                    zhHant: "48 小時試用已結束。訂閱官網 Standard 後可繼續使用 TraceFence v2 功能。",
                    ja: "48時間トライアルは終了しました。Website Standard に登録すると TraceFence v2 機能を継続利用できます。",
                    ko: "48시간 평가판이 종료되었습니다. Website Standard를 구독하면 TraceFence v2 기능을 계속 사용할 수 있습니다.",
                    mt: "The 48-hour trial has ended. Subscribe to Website Standard to continue using TraceFence v2 capabilities."
                )
            }
            return localizer.t("订阅后粘贴 Dodo Payments 发出的 License Key 即可激活。", en: "After subscribing, paste the license key from Dodo Payments to activate.", zhHant: "訂閱後貼上 Dodo Payments 發出的 License Key 即可啟用。", ja: "登録後、Dodo Payments のライセンスキーを貼り付けて有効化します。", ko: "구독 후 Dodo Payments에서 받은 라이선스 키를 붙여 넣어 활성화하세요.", mt: "After subscribing, paste the license key from Dodo Payments to activate.")
        default:
            return snapshot.licenseKeySuffix.map {
                localizer.t("License Key：\($0)", en: "License key: \($0)", zhHant: "License Key：\($0)", ja: "ライセンスキー：\($0)", ko: "라이선스 키: \($0)", mt: "License key: \($0)")
            } ?? localizer.t("请重新验证或重新输入 License Key。", en: "Recheck or enter the license key again.", zhHant: "請重新驗證或重新輸入 License Key。", ja: "再確認するか、ライセンスキーを再入力してください。", ko: "다시 확인하거나 라이선스 키를 다시 입력하세요.", mt: "Recheck or enter the license key again.")
        }
    }

    private var licenseStatusIcon: String {
        if licenseService.isTrialActive { return "timer.circle.fill" }
        if licenseService.isTrialExpired { return "lock.circle.fill" }
        switch licenseService.snapshot.status {
        case .licensed: return "checkmark.seal.fill"
        case .validating: return "arrow.triangle.2.circlepath"
        case .expired, .disabled, .error: return "exclamationmark.triangle.fill"
        default: return "key.fill"
        }
    }

    private var licenseStatusColor: Color {
        if licenseService.isTrialActive { return Theme.Colors.warning }
        if licenseService.isTrialExpired { return Theme.Colors.danger }
        switch licenseService.snapshot.status {
        case .licensed: return Theme.Colors.success
        case .expired, .disabled, .error: return Theme.Colors.danger
        case .validating: return Theme.Colors.info
        default: return Theme.Colors.accent
        }
    }

    private func licenseUsageText(_ snapshot: DirectLicenseSnapshot) -> String {
        if let usage = snapshot.activationUsage, let limit = snapshot.activationLimit {
            return localizer.t("已使用 \(usage)/\(limit) 个设备名额。", en: "\(usage)/\(limit) activations used.", zhHant: "已使用 \(usage)/\(limit) 個裝置名額。", ja: "\(usage)/\(limit) 台分を使用中。", ko: "\(usage)/\(limit)개 활성화 사용 중.", mt: "\(usage)/\(limit) activations used.")
        }
        if let limit = snapshot.activationLimit {
            return localizer.t("最多可激活 \(limit) 台设备。", en: "Up to \(limit) device activations.", zhHant: "最多可啟用 \(limit) 台裝置。", ja: "最大 \(limit) 台まで有効化できます。", ko: "최대 \(limit)개 기기에서 활성화할 수 있습니다.", mt: "Up to \(limit) device activations.")
        }
        if let usage = snapshot.activationUsage {
            return localizer.t("已使用 \(usage) 个设备名额。", en: "\(usage) activations used.", zhHant: "已使用 \(usage) 個裝置名額。", ja: "\(usage) 台分を使用中。", ko: "\(usage)개 활성화 사용 중.", mt: "\(usage) activations used.")
        }
        if let email = snapshot.customerEmail {
            return localizer.t("绑定账号：\(email)", en: "Account: \(email)", zhHant: "綁定帳號：\(email)", ja: "アカウント：\(email)", ko: "계정: \(email)", mt: "Account: \(email)")
        }
        return snapshot.licenseKeySuffix.map {
            localizer.t("License Key：\($0)", en: "License key: \($0)", zhHant: "License Key：\($0)", ja: "ライセンスキー：\($0)", ko: "라이선스 키: \($0)", mt: "License key: \($0)")
        } ?? ""
    }

    private var trialRemainingText: String {
        let seconds = Int(licenseService.trialRemainingSeconds.rounded(.down))
        let hours = max(0, seconds / 3600)
        let minutes = max(0, (seconds % 3600) / 60)
        if hours > 0 {
            return localizer.t("\(hours) 小时 \(minutes) 分钟", en: "\(hours)h \(minutes)m", zhHant: "\(hours) 小時 \(minutes) 分鐘", ja: "\(hours)時間\(minutes)分", ko: "\(hours)시간 \(minutes)분", mt: "\(hours)h \(minutes)m")
        }
        return localizer.t("\(minutes) 分钟", en: "\(minutes)m", zhHant: "\(minutes) 分鐘", ja: "\(minutes)分", ko: "\(minutes)분", mt: "\(minutes)m")
    }

    private var captureHistoryEnabledBinding: Binding<Bool> {
        Binding(
            get: { captureService.isClipboardHistoryEnabled },
            set: { captureService.setClipboardHistoryEnabled($0) }
        )
    }

    private var captureImagesBinding: Binding<Bool> {
        Binding(
            get: { captureService.includeImages },
            set: { captureService.setIncludeImages($0) }
        )
    }

    private var captureFilesBinding: Binding<Bool> {
        Binding(
            get: { captureService.includeFiles },
            set: { captureService.setIncludeFiles($0) }
        )
    }

    private var captureHistoryLimitBinding: Binding<Int> {
        Binding(
            get: { captureService.historyLimit },
            set: { captureService.setHistoryLimit($0) }
        )
    }

    private func loadShortcutSettings() {
        shortcutSettings = GlobalShortcutService.loadPersistedShortcuts()
    }

    private func beginShortcutRecording(for action: GlobalShortcut.ShortcutAction) {
        if recordingShortcutAction == action {
            stopShortcutRecording()
            return
        }
        stopShortcutRecording()
        shortcutMessage = localizer.t("请按下至少两个修饰键，并包含 ⌘ 或 ⌃。", en: "Press a combo with at least two modifiers, including Command or Control.", zhHant: "請按下至少兩個修飾鍵，並包含 ⌘ 或 ⌃。", ja: "2つ以上の修飾キーを使い、Command または Control を含めてください。", ko: "보조 키를 2개 이상 누르고 Command 또는 Control을 포함하세요.", mt: "Press a combo with at least two modifiers, including Command or Control.")
        recordingShortcutAction = action
        shortcutRecorderMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard recordingShortcutAction != nil else { return event }
            handleShortcutRecordingEvent(event)
            return nil
        }
    }

    private func handleShortcutRecordingEvent(_ event: NSEvent) {
        guard let action = recordingShortcutAction else { return }
        if event.keyCode == 53 {
            stopShortcutRecording()
            return
        }

        guard let index = shortcutSettings.firstIndex(where: { $0.action == action }) else {
            stopShortcutRecording()
            return
        }

        let modifiers = GlobalShortcut.ModifierFlags(eventModifiers: event.modifierFlags)
        var candidate = shortcutSettings[index]
        candidate.keyCode = Int(event.keyCode)
        candidate.modifiers = modifiers
        if let issue = GlobalShortcutService.validationIssue(for: candidate, among: shortcutSettings) {
            shortcutMessage = issue.localizedMessage(localizer)
            return
        }

        let previous = shortcutSettings[index]
        let registrationChanged = previous.keyCode != candidate.keyCode || previous.modifiers != candidate.modifiers
        if registrationChanged, !GlobalShortcutService.canRegisterTemporarily(candidate) {
            shortcutMessage = GlobalShortcutValidationIssue.unavailable.localizedMessage(localizer)
            return
        }

        shortcutSettings[index] = candidate
        GlobalShortcutService.savePersistedShortcuts(shortcutSettings)
        NotificationCenter.default.post(name: .traceFenceShortcutsChanged, object: nil)
        shortcutMessage = localizer.t("快捷键已保存。", en: "Shortcut saved.", zhHant: "快捷鍵已儲存。", ja: "ショートカットを保存しました。", ko: "단축키가 저장되었습니다.", mt: "Shortcut saved.")
        stopShortcutRecording(keepMessage: true)
    }

    private func stopShortcutRecording(keepMessage: Bool = false) {
        if let shortcutRecorderMonitor {
            NSEvent.removeMonitor(shortcutRecorderMonitor)
            self.shortcutRecorderMonitor = nil
        }
        recordingShortcutAction = nil
        if !keepMessage {
            shortcutMessage = nil
        }
    }

    private func saveSettings() {
        service.saveLocalAIConfig()
        if operationMonitorEnabled {
            guard TraceFenceEntitlementPolicy.canUseProFeatures else {
                operationMonitorEnabled = false
                service.stopOperationMonitor()
                selectedTab = .license
                licenseService.refreshTrialState()
                return
            }
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
        .frame(minHeight: 54)
    }
}

struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.Colors.separator.opacity(0.62))
            .frame(height: 1)
            .padding(.leading, 36)
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
