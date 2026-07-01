import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) var dismiss

    @State private var selectedTab: SettingsTab = .features
    @StateObject private var licenseService = DirectLicenseService.shared
    @StateObject private var updateService = DirectUpdateService.shared
    @State private var licenseKeyInput = ""

    @AppStorage("menuBarMonitorEnabled") private var menuBarMonitorEnabled = true
    @AppStorage("sensorMonitorEnabled") private var sensorMonitorEnabled = false
    @AppStorage("operationMonitorEnabled") private var operationMonitorEnabled = false
    @AppStorage("networkMode") private var networkMode = "internet"
    @AppStorage("quitBehavior") private var quitBehavior: String = "quitAll"
    @AppStorage("colorPalette") private var colorPalette = AppColorPalette.porcelain.rawValue

    enum SettingsTab: String, CaseIterable {
        case ai = "AI"
        case features = "Features"
        case license = "License"
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
            case .license: "key.fill"
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
            case .license: localizer.t("授权", en: "License", zhHant: "授權", ja: "ライセンス", ko: "라이선스", mt: "License")
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
                        case .license: licenseSection
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
        .task {
            licenseService.refreshTrialState()
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

    private var licenseSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            SectionHeader(title: localizer.t("TraceFence 授权", en: "TraceFence License", zhHant: "TraceFence 授權", ja: "TraceFence ライセンス", ko: "TraceFence 라이선스", mt: "TraceFence License"), icon: "key.fill")
            Text(localizer.t(
                "未购买用户可体验 48 小时；购买后由 Lemon Squeezy 处理付款、税务、发票与 License Key，TraceFence 只在本机保存授权密钥并验证状态。",
                en: "Unlicensed users get a 48-hour local trial. After purchase, Lemon Squeezy handles checkout, tax, invoices, and license keys; TraceFence stores the key locally and validates it.",
                zhHant: "未購買使用者可體驗 48 小時；購買後由 Lemon Squeezy 處理付款、稅務、發票與 License Key，TraceFence 只在本機保存授權密鑰並驗證狀態。",
                ja: "未購入ユーザーは48時間のローカルトライアルを利用できます。購入後は Lemon Squeezy が決済、税務、請求書、ライセンスキーを処理し、TraceFence はキーをローカル保存して検証します。",
                ko: "미구매 사용자는 48시간 로컬 평가판을 사용할 수 있습니다. 구매 후 Lemon Squeezy가 결제, 세금, 인보이스, 라이선스 키를 처리하고 TraceFence는 키를 로컬에 저장해 검증합니다.",
                mt: "Unlicensed users get a 48-hour local trial. After purchase, Lemon Squeezy handles checkout, tax, invoices, and license keys; TraceFence stores the key locally and validates it."
            ))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
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
                            .lineLimit(2)
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
                        licenseService.openPurchasePage()
                    } label: {
                        Label(localizer.t("购买 TraceFence Pro", en: "Buy TraceFence Pro", zhHant: "購買 TraceFence Pro", ja: "TraceFence Pro を購入", ko: "TraceFence Pro 구매", mt: "Buy TraceFence Pro"), systemImage: "cart.fill")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 32))

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
                            .fill(Theme.Colors.accent.opacity(0.12))
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .frame(width: 46, height: 46)

                    VStack(alignment: .leading, spacing: 5) {
                        Text("TraceFence v\(updateService.currentVersion)")
                            .font(Theme.Font.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.t(
                            "更新将自动下载、校验、安装并重新启动，原有文件夹授权会继续保留。",
                            en: "Updates are downloaded, verified, installed, and relaunched automatically while preserving folder access.",
                            zhHant: "更新會自動下載、驗證、安裝並重新啟動，原有資料夾授權會繼續保留。",
                            ja: "アップデートは自動的にダウンロード、検証、インストール、再起動され、フォルダアクセスは保持されます。",
                            ko: "업데이트는 자동으로 다운로드, 검증, 설치 및 재시작되며 기존 폴더 접근 권한은 유지됩니다.",
                            mt: "Updates are downloaded, verified, installed, and relaunched automatically while preserving folder access."
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

                if let latest = updateService.latestUpdate {
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

                if let message = updateService.message {
                    Label(message, systemImage: "info.circle")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        Task { await updateService.checkForUpdates() }
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

    private var licenseStatusTitle: String {
        if licenseService.isTrialActive {
            return localizer.t("48 小时试用中", en: "48-hour trial active", zhHant: "48 小時試用中", ja: "48時間トライアル中", ko: "48시간 평가판 사용 중", mt: "48-hour trial active")
        }
        if licenseService.isTrialExpired {
            return localizer.t("试用已结束", en: "Trial ended", zhHant: "試用已結束", ja: "トライアル終了", ko: "평가판 종료", mt: "Trial ended")
        }
        switch licenseService.snapshot.status {
        case .licensed:
            return localizer.t("授权已激活", en: "License active", zhHant: "授權已啟用", ja: "ライセンス有効", ko: "라이선스 활성", mt: "License active")
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
                    "剩余 \(trialRemainingText)。试用期内可扫描、浏览和预览清理，Pro 解锁增强扫描与执行清理。",
                    en: "\(trialRemainingText) left. Trial can scan, browse, and preview cleanup; Pro unlocks enhanced scan and cleanup actions.",
                    zhHant: "剩餘 \(trialRemainingText)。試用期內可掃描、瀏覽和預覽清理，Pro 解鎖增強掃描與執行清理。",
                    ja: "残り \(trialRemainingText)。トライアルではスキャン、閲覧、整理プレビューが使え、Pro で強化スキャンと整理実行が解放されます。",
                    ko: "\(trialRemainingText) 남음. 평가판은 스캔, 탐색, 정리 미리보기를 사용할 수 있고 Pro는 강화 스캔과 정리 실행을 해제합니다.",
                    mt: "\(trialRemainingText) left. Trial can scan, browse, and preview cleanup; Pro unlocks enhanced scan and cleanup actions."
                )
            }
            if licenseService.isTrialExpired {
                return localizer.t(
                    "48 小时试用已结束。购买并激活 TraceFence Pro 后可继续使用扫描和高级操作。",
                    en: "The 48-hour trial has ended. Buy and activate TraceFence Pro to continue scanning and using advanced actions.",
                    zhHant: "48 小時試用已結束。購買並啟用 TraceFence Pro 後可繼續使用掃描和高級操作。",
                    ja: "48時間トライアルは終了しました。TraceFence Pro を購入して有効化すると、スキャンと高度な操作を続けられます。",
                    ko: "48시간 평가판이 종료되었습니다. TraceFence Pro를 구매하고 활성화하면 스캔과 고급 작업을 계속 사용할 수 있습니다.",
                    mt: "The 48-hour trial has ended. Buy and activate TraceFence Pro to continue scanning and using advanced actions."
                )
            }
            return localizer.t("购买后粘贴 Lemon Squeezy 发出的 License Key 即可激活。", en: "After purchase, paste the license key from Lemon Squeezy to activate.", zhHant: "購買後貼上 Lemon Squeezy 發出的 License Key 即可啟用。", ja: "購入後、Lemon Squeezy のライセンスキーを貼り付けて有効化します。", ko: "구매 후 Lemon Squeezy에서 받은 라이선스 키를 붙여 넣어 활성화하세요.", mt: "After purchase, paste the license key from Lemon Squeezy to activate.")
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

    private func saveSettings() {
        service.saveLocalAIConfig()
        if operationMonitorEnabled {
            guard licenseService.canUseProFeatures else {
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
