import SwiftUI
import Darwin

struct MenuBarDeferredSelectionTicket<Selection: Equatable> {
    let selection: Selection
    let generation: UInt64

    func isCurrent(selection currentSelection: Selection, generation currentGeneration: UInt64) -> Bool {
        selection == currentSelection && generation == currentGeneration
    }
}

private struct MenuBarTechBackdrop: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                LinearGradient(
                    colors: [
                        Theme.Colors.surface,
                        Theme.Colors.background,
                        Theme.Colors.accent.opacity(0.055)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Theme.Colors.accent.opacity(0.12))
                    .frame(width: 230, height: 230)
                    .blur(radius: 52)
                    .offset(x: proxy.size.width * 0.42, y: -proxy.size.height * 0.42)

                Circle()
                    .fill(Theme.Colors.purple.opacity(0.075))
                    .frame(width: 260, height: 260)
                    .blur(radius: 64)
                    .offset(x: -proxy.size.width * 0.42, y: proxy.size.height * 0.38)

                Path { path in
                    let step: CGFloat = 28
                    var x: CGFloat = 0
                    while x <= proxy.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                        x += step
                    }
                    var y: CGFloat = 0
                    while y <= proxy.size.height {
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: proxy.size.width, y: y))
                        y += step
                    }
                }
                .stroke(Theme.Colors.accent.opacity(0.035), lineWidth: 0.5)

                LinearGradient(
                    colors: [Color.white.opacity(0.055), .clear, Theme.Colors.accent.opacity(0.025)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .allowsHitTesting(false)
    }
}

struct MenuBarMonitor: View {
    @ObservedObject var service: ScannerService
    @ObservedObject var quotaService: ProviderQuotaService
    @ObservedObject var usageInsightsService: AgentUsageInsightsService
    @ObservedObject var captureService: CaptureShelfService
    let openMainConsole: () -> Void
    @ObservedObject private var artifactShelfService = ArtifactShelfService.shared
    @ObservedObject private var artifactSidecarController = ArtifactSidecarController.shared
    @ObservedObject private var pluginCatalogService = TraceFenceMarketplaceCatalogService.shared
    @ObservedObject private var pluginPackageManager = TraceFencePluginPackageManager.shared
    @ObservedObject private var pluginRuntimeHost = TraceFencePluginRuntimeHost.shared
    @EnvironmentObject var localizer: Localizer
    @State private var selectedTab: MonitorTab = .quotas
    @State private var selectedQuickPluginID: String?
    @AppStorage(TraceFencePluginDisplayPreferences.pinnedPluginIDsKey)
    private var pinnedPluginIDsJSON = TraceFencePluginDisplayPreferences.defaultPinnedPluginIDsJSON
    @AppStorage("networkMode") private var networkMode = "internet"
    @State private var alertThreshold: Double = 10.0
    @State private var monitoringEnabled: Bool = true
    @State private var operationMonitorEnabled: Bool = false
    @State private var trashInsteadOfDelete: Bool = true
    @State private var preventAutoEmptyTrash: Bool = true
    @AppStorage("agentGeoMirrorEnabled") private var agentGeoMirrorEnabled = false
    @State private var agentGeoMirrorBusy = false
    @State private var agentGeoMirrorMessage: String?
    @State private var captureSection: CaptureSection = .artifacts
    @State private var renameBookmark: ArtifactShelfBookmark?
    @State private var renameText = ""
    @State private var deferredMonitorGeneration: UInt64 = 0
    @State private var deferredMonitorWorkItem: DispatchWorkItem?
    @State private var quotaRefreshClock = Date()

    private enum CaptureSection: String, CaseIterable {
        case artifacts
        case clipboard
    }

    enum MonitorTab: String, CaseIterable {
        case quotas = "quotas"
        case capture = "capture"
        case operations = "operations"
        case overview = "overview"
        case plugins = "plugins"

        func label(_ localizer: Localizer) -> String {
            switch self {
            case .quotas: return localizer.t("额度 / 用量", en: "Quota / Usage", zhHant: "額度 / 用量", ja: "クォータ / 使用量", ko: "할당량 / 사용량", mt: "Quota / Usage")
            case .capture: return localizer.t("采集", en: "Capture", zhHant: "採集", ja: "収集", ko: "캡처", mt: "Capture")
            case .operations: return localizer.agentMonitorTitle
            case .overview: return localizer.systemMonitorTitle
            case .plugins: return localizer.t("插件", en: "Plugins", zhHant: "外掛", ja: "プラグイン", ko: "플러그인", mt: "Plugins")
            }
        }

        var icon: String {
            switch self {
            case .quotas: return "waveform.path.ecg.rectangle"
            case .capture: return "viewfinder"
            case .operations: return "chart.bar"
            case .overview: return "gauge.open.with.lines.needle.84percent"
            case .plugins: return "puzzlepiece.extension.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            MenuBarTechBackdrop()

            VStack(spacing: 0) {
                commandHeader
                tabBar

                Group {
                    switch selectedTab {
                    case .quotas:
                        quotaContent
                    case .capture:
                        captureContent
                    case .overview:
                        overviewContent
                    case .operations:
                        operationsContent
                    case .plugins:
                        pluginsContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                popoverFooter
            }
        }
        .frame(width: 520, height: 640)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Theme.Gradients.glassStroke, lineWidth: 1)
        }
        .onAppear {
            loadSettings()
            pluginPackageManager.refresh(catalog: pluginCatalogService.catalog)
#if DEBUG
            openPluginTabForUITestIfRequested()
#endif
            startDeferredMonitorForSelectedTab()
        }
        .onChange(of: selectedTab) { _ in
            startDeferredMonitorForSelectedTab()
        }
        .onDisappear {
            cancelDeferredMonitorStart()
        }
    }

    private var commandHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Gradients.hero)
                    .shadow(color: Theme.Colors.accent.opacity(0.26), radius: 10, y: 4)
                MenuBarShieldEyeIcon(color: .white)
                    .frame(width: 20, height: 20)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 2) {
                Text("TRACEFENCE // LIVE DECK")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(localizer.t("本机安全与 Agent 实时态势", en: "Local security and live Agent telemetry", zhHant: "本機安全與 Agent 即時態勢", ja: "ローカルセキュリティと Agent テレメトリ", ko: "로컬 보안 및 Agent 실시간 상태", mt: "Local security and live Agent telemetry"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()

            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(Theme.Colors.success.opacity(0.20))
                        .frame(width: 15, height: 15)
                    Circle()
                        .fill(Theme.Colors.success)
                        .frame(width: 6, height: 6)
                }
                Text("LIVE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(Theme.Colors.success)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Theme.Colors.success.opacity(0.09))
            .clipShape(Capsule())
            .overlay {
                Capsule()
                    .stroke(Theme.Colors.success.opacity(0.18), lineWidth: 1)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var tabBar: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(MonitorTab.allCases, id: \.self) { tab in
                let isSelected = selectedTab == tab
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(tab.label(localizer))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.68)
                    }
                    .foregroundStyle(isSelected ? .white : Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, 7)
                    .contentShape(Capsule())
                    .background {
                        if isSelected {
                            Capsule()
                                .fill(Theme.Gradients.accent)
                                .shadow(color: Theme.Colors.accent.opacity(0.24), radius: 7, y: 3)
                        } else {
                            Capsule()
                                .fill(Color.clear)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .fill(Theme.Colors.elevatedCardBg.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Theme.Colors.separator.opacity(0.72), lineWidth: 1)
        )
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.sm)
    }

    private var popoverFooter: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Button {
                openMainConsole()
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    MenuBarShieldEyeIcon(color: .white)
                        .frame(width: 14, height: 14)
                    Text(localizer.t("打开 TraceFence 主控台", en: "Open TraceFence Console", zhHant: "打開 TraceFence 主控台", ja: "TraceFence コンソールを開く", ko: "TraceFence 콘솔 열기", mt: "Open TraceFence Console"))
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 10, weight: .bold))
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, 8)
                .background(Theme.Gradients.hero)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                }
                .shadow(color: Theme.Colors.accent.opacity(0.18), radius: 8, y: 3)
            }
            .buttonStyle(.plain)

            HStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(networkMode == "internet" ? Theme.Colors.success : Theme.Colors.warning)
                        .frame(width: 5, height: 5)
                    Text(networkMode == "internet" ? localizer.internetStatus : localizer.offlineStatus)
                }
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.Colors.cardBg.opacity(0.60))
                .clipShape(Capsule())

                Text("BUILD \(service.currentVersion)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)

                Spacer()

                Picker("", selection: $localizer.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.nativeName)
                            .font(.system(size: 10))
                            .tag(lang)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 76)

                Button {
                    if let appDelegate = NSApp.delegate as? AppDelegate {
                        appDelegate.requestMenuBarQuit()
                    } else {
                        Darwin.exit(0)
                    }
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.danger)
                        .frame(width: 26, height: 26)
                        .background(Theme.Colors.danger.opacity(0.10))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .help(localizer.quitApp)
                .accessibilityLabel(localizer.quitApp)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.md)
        .background(
            LinearGradient(
                colors: [Theme.Colors.elevatedCardBg.opacity(0.28), Theme.Colors.accent.opacity(0.035)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.Colors.separator.opacity(0.62))
                .frame(height: 1)
        }
    }

    private var pluginsContent: some View {
        Group {
            if let selectedQuickPluginID {
                TraceFencePluginRuntimeView(
                    runtimeHost: pluginRuntimeHost,
                    pluginID: selectedQuickPluginID,
                    presentation: .menuBar,
                    onClose: { self.selectedQuickPluginID = nil }
                )
                .id(selectedQuickPluginID)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(localizer.t("快捷插件", en: "Quick Plugins"))
                                    .font(Theme.Font.headline)
                                Text(localizer.t(
                                    "在“我的插件”中点星标固定常用工具",
                                    en: "Star frequently used tools in My Plugins"
                                ))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Button {
                                TraceFencePluginPresentationCenter.shared.openPluginWorkspace()
                                openMainConsole()
                            } label: {
                                Label(localizer.t("管理", en: "Manage"), systemImage: "arrow.up.right")
                            }
                            .buttonStyle(.borderless)
                        }

                        if quickPlugins.isEmpty {
                            VStack(spacing: Theme.Spacing.md) {
                                Image(systemName: "star.circle")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                Text(localizer.t(
                                    "还没有可用的快捷插件",
                                    en: "No quick plugins are available yet"
                                ))
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                Button {
                                    TraceFencePluginPresentationCenter.shared.openPluginWorkspace()
                                    openMainConsole()
                                } label: {
                                    Label(localizer.t("打开我的插件", en: "Open My Plugins"), systemImage: "puzzlepiece.extension.fill")
                                }
                                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .secondary, minHeight: 32))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.xxl)
                            .cardStyle()
                        } else {
                            LazyVGrid(
                                columns: [GridItem(.flexible()), GridItem(.flexible())],
                                spacing: Theme.Spacing.sm
                            ) {
                                ForEach(quickPlugins) { plugin in
                                    Button {
                                        selectedQuickPluginID = plugin.id
                                    } label: {
                                        HStack(spacing: Theme.Spacing.sm) {
                                            Image(systemName: plugin.systemImage)
                                                .font(.system(size: 15, weight: .semibold))
                                                .foregroundStyle(Theme.Colors.accent)
                                                .frame(width: 34, height: 34)
                                                .background(Theme.Colors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(plugin.localizedName())
                                                    .font(Theme.Font.captionMedium)
                                                    .foregroundStyle(Theme.Colors.textPrimary)
                                                    .lineLimit(1)
                                                Text(localizer.t("点击使用", en: "Open"))
                                                    .font(.system(size: 9, weight: .medium))
                                                    .foregroundStyle(Theme.Colors.textTertiary)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(Theme.Spacing.sm)
                                        .contentShape(Rectangle())
                                        .background(Theme.Colors.elevatedCardBg.opacity(0.74), in: RoundedRectangle(cornerRadius: Theme.Radius.md))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: Theme.Radius.md)
                                                .stroke(Theme.Colors.separator, lineWidth: 1)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var quickPlugins: [TraceFencePluginDescriptor] {
        let pinned = TraceFencePluginDisplayPreferences.pinnedPluginIDs(from: pinnedPluginIDsJSON)
        return pinned.compactMap { pluginID in
            guard pluginPackageManager.records[pluginID] != nil,
                  let plugin = pluginCatalogService.catalog.plugin(id: pluginID),
                  plugin.supportsMenuBarQuickPanel else {
                return nil
            }
            return plugin
        }
    }

#if DEBUG
    private func openPluginTabForUITestIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--tracefence-menu-plugin-tab") else { return }
        selectedTab = .plugins
        if let flagIndex = arguments.firstIndex(of: "--tracefence-open-quick-plugin"),
           arguments.indices.contains(flagIndex + 1) {
            selectedQuickPluginID = arguments[flagIndex + 1]
        }
    }
#endif

    private var overviewContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                hardwareOverview
                Divider()
                diskOverview
                Divider()
                monitoringSettings
                if SandboxPaths.isDirectDistribution {
                    Divider()
                    agentGeoMirrorQuickSwitch
                }
                Divider()
                safetySettings
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var quotaContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                AgentUsageRuntimeSummaryView(service: usageInsightsService)

                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Theme.Colors.info.opacity(0.11))
                            Image(systemName: "gauge.with.dots.needle.67percent")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Colors.info)
                        }
                        .frame(width: 30, height: 30)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(localizer.t("Provider 额度", en: "Provider Quotas", zhHant: "Provider 額度", ja: "Provider クォータ", ko: "Provider 할당량", mt: "Provider Quotas"))
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            Text(localizer.t("官方窗口 · 重置时间 · 可信缓存", en: "Official windows · reset times · trusted cache", zhHant: "官方窗口 · 重置時間 · 可信快取", ja: "公式ウィンドウ · リセット · 信頼キャッシュ", ko: "공식 창 · 재설정 · 신뢰 캐시", mt: "Official windows · reset times · trusted cache"))
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }

                    Spacer()

                    HStack(spacing: Theme.Spacing.xs) {
                        if SandboxPaths.isSandboxed {
                            Button {
                                authorizeQuotaData()
                            } label: {
                                Label(
                                    localizer.t(
                                        "授权 Agent 数据",
                                        en: "Authorize Data",
                                        zhHant: "授權 Agent 資料",
                                        ja: "データを許可",
                                        ko: "데이터 승인",
                                        mt: "Authorize Data"),
                                    systemImage: "folder.badge.gearshape")
                                .font(Theme.Font.captionMedium)
                            }
                            .buttonStyle(.bordered)
                        }

                        Button {
                            quotaService.refresh()
                        } label: {
                            Label(quotaRefreshButtonTitle(), systemImage: "arrow.clockwise")
                                .font(Theme.Font.captionMedium)
                        }
                        .buttonStyle(.bordered)
                        .disabled(quotaService.isRefreshing || quotaService.refreshCooldownRemaining() > 0)
                    }
                }

                if let status = quotaRefreshStatusText() {
                    Text(status)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if quotaService.snapshots.isEmpty {
                    quotaEmptyStateCard
                } else {
                    ForEach(quotaService.snapshots) { snapshot in
                        quotaProviderCard(snapshot)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            quotaService.start()
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            quotaRefreshClock = now
        }
    }

    private var captureContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                if SandboxPaths.isDirectDistribution {
                    Picker("", selection: $captureSection) {
                        Text(localizer.t("任务资料", en: "Task Artifacts", zhHant: "任務資料", ja: "タスク資料", ko: "작업 자료", mt: "Task Artifacts")).tag(CaptureSection.artifacts)
                        Text(localizer.t("剪贴板", en: "Clipboard", zhHant: "剪貼簿", ja: "クリップボード", ko: "클립보드", mt: "Clipboard")).tag(CaptureSection.clipboard)
                    }
                    .pickerStyle(.segmented)
                }

                if SandboxPaths.isDirectDistribution && captureSection == .artifacts {
                    artifactShelfPanel
                } else {
                    captureActionPanel
                    captureHistorySettingsPanel
                    captureHistoryPanel
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            captureService.start()
            captureService.refreshScreenCaptureAccess()
            if captureSection == .artifacts {
                artifactShelfService.start(for: .taskArtifactsView)
            }
        }
        .onChange(of: captureSection) { section in
            if section == .artifacts {
                artifactShelfService.start(for: .taskArtifactsView)
            } else {
                artifactShelfService.stop(for: .taskArtifactsView)
            }
        }
        .onDisappear {
            artifactShelfService.stop(for: .taskArtifactsView)
        }
        .alert(localizer.t("重命名收藏", en: "Rename Bookmark", zhHant: "重新命名收藏", ja: "名前を変更", ko: "이름 변경", mt: "Rename Bookmark"), isPresented: Binding(
            get: { renameBookmark != nil },
            set: { if !$0 { renameBookmark = nil } }
        )) {
            TextField(localizer.t("显示名称", en: "Display name", zhHant: "顯示名稱", ja: "表示名", ko: "표시 이름", mt: "Display name"), text: $renameText)
            Button(localizer.t("取消", en: "Cancel", zhHant: "取消", ja: "キャンセル", ko: "취소", mt: "Cancel"), role: .cancel) { renameBookmark = nil }
            Button(localizer.t("保存", en: "Save", zhHant: "儲存", ja: "保存", ko: "저장", mt: "Save")) {
                if let bookmark = renameBookmark { artifactShelfService.renameBookmark(bookmark, title: renameText) }
                renameBookmark = nil
            }
        }
    }

    private var artifactShelfPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Picker("", selection: Binding(
                    get: { artifactShelfService.selectedTaskID ?? "" },
                    set: {
                        if !$0.isEmpty {
                            artifactShelfService.selectTask($0)
                            artifactSidecarController.setFollowPaused(true)
                        }
                    }
                )) {
                    if artifactShelfService.tasks.isEmpty {
                        Text(localizer.t("没有可用任务", en: "No tasks available", zhHant: "沒有可用任務", ja: "利用可能なタスクなし", ko: "사용 가능한 작업 없음", mt: "No tasks available")).tag("")
                    }
                    ForEach(artifactShelfService.tasks) { task in
                        Text(task.title).tag(task.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)

                Button { artifactShelfService.refresh(force: true) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(artifactShelfService.isLoadingCandidates)
            }

            TextField(localizer.t("搜索文件、目录或链接", en: "Search files, folders, or links", zhHant: "搜尋檔案、目錄或連結", ja: "ファイル・フォルダ・リンクを検索", ko: "파일, 폴더 또는 링크 검색", mt: "Search files, folders, or links"), text: $artifactShelfService.searchText)
                .textFieldStyle(.roundedBorder)

            artifactHistoryStatusStrip

            artifactSectionHeader(
                localizer.t("已收藏", en: "Saved", zhHant: "已收藏", ja: "保存済み", ko: "저장됨", mt: "Saved"),
                icon: "star.fill",
                count: artifactShelfService.bookmarksForSelectedTask.count
            )

            if artifactShelfService.bookmarksForSelectedTask.isEmpty {
                artifactEmptyState(
                    title: localizer.t("还没有收藏", en: "Nothing saved yet", zhHant: "尚未收藏", ja: "まだ保存されていません", ko: "저장된 항목 없음", mt: "Nothing saved yet"),
                    detail: localizer.t("从下面发现的任务产物中点击星标。", en: "Star a discovered task output below.", zhHant: "從下方發現的任務產物點擊星標。", ja: "下のタスク成果物にスターを付けます。", ko: "아래 작업 결과물에 별표를 지정하세요.", mt: "Star a discovered task output below.")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(artifactShelfService.bookmarksForSelectedTask) { bookmark in
                        artifactBookmarkRow(bookmark)
                        if bookmark.id != artifactShelfService.bookmarksForSelectedTask.last?.id { Divider() }
                    }
                }
                .background(Theme.Colors.cardBg.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }

            artifactSectionHeader(
                localizer.t("发现的任务产物", en: "Discovered Outputs", zhHant: "發現的任務產物", ja: "検出した成果物", ko: "발견된 결과물", mt: "Discovered Outputs"),
                icon: "sparkle.magnifyingglass",
                count: artifactShelfService.visibleCandidates.count
            )

            if artifactShelfService.visibleCandidates.isEmpty {
                if artifactHistoryIsLoading {
                    artifactEmptyState(
                        title: localizer.t("正在扫描", en: "Scanning", zhHant: "正在掃描", ja: "スキャン中", ko: "검색 중", mt: "Scanning"),
                        detail: artifactHistoryLoadingDetail
                    )
                } else if !artifactShelfService.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    artifactEmptyState(
                        title: localizer.t("没有匹配结果", en: "No matches", zhHant: "沒有相符結果", ja: "一致する項目なし", ko: "일치하는 결과 없음", mt: "No matches"),
                        detail: localizer.t("换个关键词，或清空搜索查看最近交付。", en: "Try another term or clear search to see recent deliveries.", zhHant: "請更換關鍵字，或清除搜尋以查看最近交付。", ja: "別の語句を試すか、検索を消去して最近の成果物を表示してください。", ko: "다른 검색어를 시도하거나 검색을 지워 최근 결과물을 확인하세요.", mt: "Try another term or clear search to see recent deliveries.")
                    )
                } else if artifactShelfService.hiddenCandidateCount > 0 {
                    artifactEmptyState(
                        title: localizer.t("旧批次与过程文件已收起", en: "Older and process files are tucked away", zhHant: "舊批次與過程檔案已收起", ja: "旧版・作業ファイルは折りたたまれています", ko: "이전 버전 및 작업 파일이 숨겨져 있습니다", mt: "Older and process files are tucked away"),
                        detail: localizer.t("使用搜索可以找回。", en: "Use search to find them.", zhHant: "可使用搜尋找回。", ja: "検索して表示できます。", ko: "검색으로 찾을 수 있습니다.", mt: "Use search to find them.")
                    )
                } else {
                    artifactEmptyState(
                        title: localizer.t("暂未发现产物", en: "No outputs found", zhHant: "暫未發現產物", ja: "成果物がありません", ko: "발견된 결과물 없음", mt: "No outputs found"),
                        detail: localizer.t("这里只显示最终答复明确交付的文件和目录。", en: "Only files and folders explicitly delivered in final answers appear here.", zhHant: "此處只顯示最終答覆明確交付的檔案與目錄。", ja: "最終回答で明示的に納品されたファイルとフォルダだけを表示します。", ko: "최종 답변에서 명시적으로 전달된 파일과 폴더만 표시됩니다.", mt: "Only files and folders explicitly delivered in final answers appear here.")
                    )
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(artifactShelfService.visibleCandidates.prefix(30)) { candidate in
                        artifactCandidateRow(candidate)
                        if candidate.id != artifactShelfService.visibleCandidates.prefix(30).last?.id { Divider() }
                    }
                }
                .background(Theme.Colors.cardBg.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            if artifactShelfService.hiddenCandidateCount > 0 {
                Text(localizer.t(
                    "已优先显示最近交付；搜索可查另外 \(artifactShelfService.hiddenCandidateCount) 项旧批次或过程文件。",
                    en: "Recent deliveries are prioritized; search to find \(artifactShelfService.hiddenCandidateCount) older or process files.",
                    zhHant: "已優先顯示最近交付；搜尋可查另外 \(artifactShelfService.hiddenCandidateCount) 個舊批次或過程檔案。",
                    ja: "最近の成果物を優先表示しています。検索すると、ほかの \(artifactShelfService.hiddenCandidateCount) 件の旧版・作業ファイルを確認できます。",
                    ko: "최근 결과물을 우선 표시합니다. 검색하면 이전 버전 또는 작업 파일 \(artifactShelfService.hiddenCandidateCount)개를 더 찾을 수 있습니다.",
                    mt: "Recent deliveries are prioritized; search to find \(artifactShelfService.hiddenCandidateCount) older or process files."
                ))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            }

            HStack {
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = true
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url { artifactShelfService.addTarget(url.path) }
                } label: {
                    Label(localizer.t("添加文件或目录", en: "Add File or Folder", zhHant: "新增檔案或目錄", ja: "ファイル・フォルダを追加", ko: "파일 또는 폴더 추가", mt: "Add File or Folder"), systemImage: "plus")
                }
                .buttonStyle(.bordered)
                Spacer()
                Toggle(isOn: Binding(
                    get: { artifactSidecarController.isEnabled },
                    set: { artifactSidecarController.setEnabled($0) }
                )) {
                    Text(localizer.t("伴随侧栏", en: "Companion Sidebar", zhHant: "伴隨側欄", ja: "コンパニオンサイドバー", ko: "동반 사이드바", mt: "Companion Sidebar"))
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .help(localizer.t("跟随当前 Agent 窗口并在侧栏内预览产物", en: "Follow the current agent window and preview outputs in the sidebar", zhHant: "跟隨目前 Agent 視窗並在側欄內預覽產物", ja: "現在の Agent ウィンドウに追従して成果物をプレビューします", ko: "현재 Agent 창을 따라가며 사이드바에서 결과물을 미리 봅니다", mt: "Follow the current agent window and preview outputs in the sidebar"))
                Text(localizer.t("仅保存在本机", en: "Stored only on this Mac", zhHant: "僅儲存在本機", ja: "このMacのみに保存", ko: "이 Mac에만 저장", mt: "Stored only on this Mac"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private var artifactHistoryStatusStrip: some View {
        switch artifactShelfService.historyStatus {
        case .idle:
            EmptyView()
        case .loadingRecent(let totalBytes):
            artifactHistoryStatusRow(
                icon: "clock.arrow.circlepath",
                message: localizer.t(
                    "正在读取最近记录（任务日志 \(artifactFormattedByteCount(totalBytes))）…",
                    en: "Reading recent records (task log: \(artifactFormattedByteCount(totalBytes)))…",
                    zhHant: "正在讀取最近記錄（任務記錄 \(artifactFormattedByteCount(totalBytes))）…",
                    ja: "最近の記録を読み込み中（タスクログ：\(artifactFormattedByteCount(totalBytes))）…",
                    ko: "최근 기록을 읽는 중입니다(작업 로그: \(artifactFormattedByteCount(totalBytes)))…",
                    mt: "Reading recent records (task log: \(artifactFormattedByteCount(totalBytes)))…"
                ),
                isLoading: true
            )
        case .recentOnly(let loadedBytes, let totalBytes):
            artifactHistoryStatusRow(
                icon: "clock.badge.exclamationmark",
                message: localizer.t(
                    "当前仅显示最近 \(artifactFormattedByteCount(loadedBytes)) / 共 \(artifactFormattedByteCount(totalBytes))，找到 \(artifactShelfService.candidates.count) 项；搜索只覆盖已加载内容。",
                    en: "Showing only the latest \(artifactFormattedByteCount(loadedBytes)) of \(artifactFormattedByteCount(totalBytes)); \(artifactShelfService.candidates.count) outputs found. Search covers loaded content only.",
                    zhHant: "目前只顯示最近 \(artifactFormattedByteCount(loadedBytes)) / 共 \(artifactFormattedByteCount(totalBytes))，找到 \(artifactShelfService.candidates.count) 項；搜尋只涵蓋已載入內容。",
                    ja: "全 \(artifactFormattedByteCount(totalBytes)) のうち最新 \(artifactFormattedByteCount(loadedBytes)) のみ表示し、\(artifactShelfService.candidates.count) 件を検出しました。検索対象は読み込み済みの内容のみです。",
                    ko: "전체 \(artifactFormattedByteCount(totalBytes)) 중 최근 \(artifactFormattedByteCount(loadedBytes))만 표시하며 \(artifactShelfService.candidates.count)개 결과를 찾았습니다. 검색은 로드된 내용만 포함합니다.",
                    mt: "Showing only the latest \(artifactFormattedByteCount(loadedBytes)) of \(artifactFormattedByteCount(totalBytes)); \(artifactShelfService.candidates.count) outputs found. Search covers loaded content only."
                ),
                actionTitle: localizer.t("加载完整历史", en: "Load Full History", zhHant: "載入完整歷史", ja: "全履歴を読み込む", ko: "전체 기록 로드", mt: "Load Full History"),
                action: artifactShelfService.loadCompleteHistory
            )
        case .loadingComplete(let totalBytes):
            artifactHistoryStatusRow(
                icon: "arrow.triangle.2.circlepath",
                message: localizer.t(
                    "正在后台读取完整历史（\(artifactFormattedByteCount(totalBytes))）；当前 \(artifactShelfService.candidates.count) 项仍可使用。",
                    en: "Loading the full history in the background (\(artifactFormattedByteCount(totalBytes))); the current \(artifactShelfService.candidates.count) outputs remain available.",
                    zhHant: "正在背景讀取完整歷史（\(artifactFormattedByteCount(totalBytes))）；目前 \(artifactShelfService.candidates.count) 項仍可使用。",
                    ja: "全履歴をバックグラウンドで読み込み中（\(artifactFormattedByteCount(totalBytes))）。現在の \(artifactShelfService.candidates.count) 件は引き続き利用できます。",
                    ko: "전체 기록을 백그라운드에서 읽는 중입니다(\(artifactFormattedByteCount(totalBytes))). 현재 \(artifactShelfService.candidates.count)개 결과는 계속 사용할 수 있습니다.",
                    mt: "Loading the full history in the background (\(artifactFormattedByteCount(totalBytes))); the current \(artifactShelfService.candidates.count) outputs remain available."
                ),
                isLoading: true
            )
        case .pausedRecent:
            artifactHistoryStatusRow(
                icon: "pause.circle",
                message: localizer.t("最近记录读取已暂停；返回产物列表后会继续。", en: "Reading recent records is paused and will resume when you return to the output list.", zhHant: "最近記錄讀取已暫停；返回產物清單後會繼續。", ja: "最近の記録の読み込みは一時停止中です。成果物一覧に戻ると再開します。", ko: "최근 기록 읽기가 일시 중지되었습니다. 결과 목록으로 돌아가면 계속됩니다.", mt: "Reading recent records is paused and will resume when you return to the output list."),
                actionTitle: localizer.t("继续", en: "Resume", zhHant: "繼續", ja: "再開", ko: "계속", mt: "Resume"),
                action: artifactShelfService.retryHistoryScan
            )
        case .pausedComplete:
            artifactHistoryStatusRow(
                icon: "pause.circle",
                message: localizer.t("完整历史读取已暂停；已加载结果仍然保留。", en: "Full-history loading is paused; loaded outputs are preserved.", zhHant: "完整歷史讀取已暫停；已載入結果仍會保留。", ja: "全履歴の読み込みは一時停止中です。読み込み済みの成果物は保持されます。", ko: "전체 기록 읽기가 일시 중지되었습니다. 로드된 결과는 유지됩니다.", mt: "Full-history loading is paused; loaded outputs are preserved."),
                actionTitle: localizer.t("继续", en: "Resume", zhHant: "繼續", ja: "再開", ko: "계속", mt: "Resume"),
                action: artifactShelfService.retryHistoryScan
            )
        case .complete:
            artifactHistoryStatusRow(
                icon: "checkmark.circle.fill",
                message: localizer.t(
                    "完整历史已加载 · 找到 \(artifactShelfService.candidates.count) 项",
                    en: "Full history loaded · \(artifactShelfService.candidates.count) outputs found",
                    zhHant: "完整歷史已載入 · 找到 \(artifactShelfService.candidates.count) 項",
                    ja: "全履歴を読み込み済み · \(artifactShelfService.candidates.count) 件を検出",
                    ko: "전체 기록 로드됨 · \(artifactShelfService.candidates.count)개 결과 발견",
                    mt: "Full history loaded · \(artifactShelfService.candidates.count) outputs found"
                )
            )
        case .failed:
            artifactHistoryStatusRow(
                icon: "exclamationmark.triangle.fill",
                message: localizer.t("任务历史读取失败，请重试。", en: "Task history could not be read. Try again.", zhHant: "任務歷史讀取失敗，請重試。", ja: "タスク履歴を読み込めませんでした。再試行してください。", ko: "작업 기록을 읽지 못했습니다. 다시 시도하세요.", mt: "Task history could not be read. Try again."),
                actionTitle: localizer.t("重试", en: "Retry", zhHant: "重試", ja: "再試行", ko: "다시 시도", mt: "Retry"),
                action: artifactShelfService.retryHistoryScan
            )
        }
    }

    private var artifactHistoryIsLoading: Bool {
        switch artifactShelfService.historyStatus {
        case .loadingRecent, .loadingComplete:
            return true
        default:
            return false
        }
    }

    private var artifactHistoryLoadingDetail: String {
        switch artifactShelfService.historyStatus {
        case .loadingComplete:
            return localizer.t("正在后台读取完整历史；已加载结果会保持可用。", en: "Full history is loading in the background; loaded outputs stay available.", zhHant: "正在背景讀取完整歷史；已載入結果會保持可用。", ja: "全履歴をバックグラウンドで読み込み中です。読み込み済みの成果物は引き続き利用できます。", ko: "전체 기록을 백그라운드에서 읽는 중이며 로드된 결과는 계속 사용할 수 있습니다.", mt: "Full history is loading in the background; loaded outputs stay available.")
        default:
            return localizer.t("正在读取最近记录；完成后会标明读取范围。", en: "Reading recent records; the loaded range will be shown when finished.", zhHant: "正在讀取最近記錄；完成後會標明讀取範圍。", ja: "最近の記録を読み込み中です。完了後に読み込み範囲を表示します。", ko: "최근 기록을 읽는 중이며 완료되면 읽은 범위가 표시됩니다.", mt: "Reading recent records; the loaded range will be shown when finished.")
        }
    }

    private func artifactHistoryStatusRow(
        icon: String,
        message: String,
        isLoading: Bool = false,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.sm) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: icon)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Text(message)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func artifactFormattedByteCount(_ bytes: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .file)
    }

    private func artifactSectionHeader(_ title: String, icon: String, count: Int) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            Text("\(count)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }

    private func artifactEmptyState(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Theme.Font.captionMedium).foregroundStyle(Theme.Colors.textPrimary)
            Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardBg.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func artifactCandidateRow(_ candidate: ArtifactShelfCandidate) -> some View {
        artifactRow(kind: candidate.kind, target: candidate.target, title: candidate.title, image: artifactShelfService.thumbnail(for: candidate)) {
            Button { artifactShelfService.addBookmark(candidate) } label: { Image(systemName: "star") }.help(localizer.t("收藏", en: "Save", zhHant: "收藏", ja: "保存", ko: "저장", mt: "Save"))
            artifactOpenButtons(target: candidate.target, kind: candidate.kind)
        }
    }

    private func artifactBookmarkRow(_ bookmark: ArtifactShelfBookmark) -> some View {
        artifactRow(kind: bookmark.kind, target: bookmark.target, title: bookmark.title, image: artifactShelfService.thumbnail(for: bookmark)) {
            Button { artifactShelfService.moveBookmark(bookmark, offset: -1) } label: { Image(systemName: "chevron.up") }.help(localizer.t("上移", en: "Move Up", zhHant: "上移", ja: "上へ", ko: "위로", mt: "Move Up"))
            Button { artifactShelfService.moveBookmark(bookmark, offset: 1) } label: { Image(systemName: "chevron.down") }.help(localizer.t("下移", en: "Move Down", zhHant: "下移", ja: "下へ", ko: "아래로", mt: "Move Down"))
            Button {
                renameText = bookmark.title
                renameBookmark = bookmark
            } label: { Image(systemName: "pencil") }.help(localizer.t("重命名", en: "Rename", zhHant: "重新命名", ja: "名前を変更", ko: "이름 변경", mt: "Rename"))
            artifactOpenButtons(target: bookmark.target, kind: bookmark.kind)
            Button { artifactShelfService.removeBookmark(bookmark) } label: { Image(systemName: "star.slash") }.help(localizer.t("取消收藏", en: "Remove", zhHant: "取消收藏", ja: "保存解除", ko: "저장 취소", mt: "Remove"))
        }
    }

    private func artifactRow<Actions: View>(kind: ArtifactShelfCandidate.Kind, target: String, title: String, image: NSImage?, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let image {
                Image(nsImage: image).resizable().scaledToFill().frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            } else {
                Image(systemName: artifactIcon(kind)).frame(width: 34, height: 34).foregroundStyle(Theme.Colors.accent).background(Theme.Colors.accent.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.captionMedium).foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                Text(target).font(Theme.Font.caption).foregroundStyle(Theme.Colors.textTertiary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 4)
            HStack(spacing: 7) { actions() }.buttonStyle(.plain).foregroundStyle(Theme.Colors.textSecondary)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(minHeight: 50)
    }

    @ViewBuilder
    private func artifactOpenButtons(target: String, kind: ArtifactShelfCandidate.Kind) -> some View {
        Button { artifactShelfService.open(target) } label: { Image(systemName: "arrow.up.forward.square") }.help(localizer.t("打开", en: "Open", zhHant: "開啟", ja: "開く", ko: "열기", mt: "Open"))
        if kind != .url {
            Button { artifactShelfService.reveal(target) } label: { Image(systemName: "folder") }.help(localizer.t("在 Finder 中显示", en: "Reveal in Finder", zhHant: "在 Finder 中顯示", ja: "Finderに表示", ko: "Finder에서 보기", mt: "Reveal in Finder"))
        }
        Button { artifactShelfService.copyTarget(target) } label: { Image(systemName: "doc.on.doc") }.help(localizer.t("复制路径", en: "Copy Path", zhHant: "複製路徑", ja: "パスをコピー", ko: "경로 복사", mt: "Copy Path"))
    }

    private func artifactIcon(_ kind: ArtifactShelfCandidate.Kind) -> String {
        switch kind {
        case .file: return "doc"
        case .directory: return "folder.fill"
        case .image: return "photo"
        case .html: return "safari"
        case .url: return "link"
        }
    }

    private var captureActionPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(localizer.t("本地采集", en: "Local Capture", zhHant: "本機採集", ja: "ローカル収集", ko: "로컬 캡처", mt: "Local Capture"), systemImage: "viewfinder")
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t("截屏和剪贴板历史仅保存在本机，不上传到云端。", en: "Screenshots and clipboard history stay on this Mac.", zhHant: "截圖與剪貼簿歷史只保存在本機。", ja: "スクリーンショットとクリップボード履歴はこのMac内に保存されます。", ko: "스크린샷과 클립보드 기록은 이 Mac에만 저장됩니다.", mt: "Screenshots and clipboard history stay on this Mac."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Button {
                    captureService.refreshScreenCaptureAccess()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(Theme.Font.captionMedium)
                }
                .buttonStyle(.bordered)
                .help(localizer.refresh)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    captureService.captureSelectedRegionToClipboard()
                } label: {
                    Label(captureService.isCapturingScreen ? localizer.t("正在截屏", en: "Capturing", zhHant: "正在截圖", ja: "取得中", ko: "캡처 중", mt: "Capturing") : localizer.t("区域截屏", en: "Area", zhHant: "區域截圖", ja: "範囲", ko: "영역", mt: "Area"), systemImage: "selection.pin.in.out")
                        .font(Theme.Font.captionMedium)
                }
                .buttonStyle(.borderedProminent)
                .disabled(captureService.isCapturingScreen)

                Button {
                    captureService.captureVisibleScreenToClipboard()
                } label: {
                    Label(localizer.t("全屏", en: "Full Screen", zhHant: "全螢幕", ja: "全画面", ko: "전체 화면", mt: "Full Screen"), systemImage: "rectangle.dashed")
                        .font(Theme.Font.captionMedium)
                }
                .buttonStyle(.bordered)
                .disabled(captureService.isCapturingScreen)

                Button {
                    captureService.toggleScreenRecording()
                } label: {
                    Label(
                        captureService.isRecordingScreen
                            ? localizer.t("停止录屏", en: "Stop Recording", zhHant: "停止錄屏", ja: "録画停止", ko: "녹화 중지", mt: "Stop Recording")
                            : localizer.t("录屏", en: "Record", zhHant: "錄屏", ja: "録画", ko: "녹화", mt: "Record"),
                        systemImage: captureService.isRecordingScreen ? "stop.circle.fill" : "record.circle"
                    )
                    .font(Theme.Font.captionMedium)
                }
                .buttonStyle(.bordered)
                .tint(captureService.isRecordingScreen ? Theme.Colors.danger : Theme.Colors.accent)
                .disabled(captureService.isCapturingScreen)

                if !captureService.screenCaptureAccessGranted {
                    Button {
                        captureService.openScreenCaptureSettings()
                    } label: {
                        Label(localizer.t("屏幕录制权限", en: "Screen Access", zhHant: "螢幕錄製權限", ja: "画面収録の権限", ko: "화면 기록 권한", mt: "Screen Access"), systemImage: "lock.open")
                            .font(Theme.Font.captionMedium)
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()
            }

            if let status = captureService.status {
                captureStatusBanner(status)
            }
        }
        .cardStyle(padding: Theme.Spacing.md)
    }

    private var captureHistorySettingsPanel: some View {
        VStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "doc.on.clipboard")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(captureService.isClipboardHistoryEnabled ? Theme.Colors.accent : Theme.Colors.textTertiary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.t("剪贴板历史", en: "Clipboard History", zhHant: "剪貼簿歷史", ja: "クリップボード履歴", ko: "클립보드 기록", mt: "Clipboard History"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t("保留条数可配置，默认 100 条。", en: "Configurable retention, default 100 items.", zhHant: "保留筆數可設定，預設 100 筆。", ja: "保存件数は変更可能、既定は100件です。", ko: "보관 개수를 설정할 수 있으며 기본값은 100개입니다.", mt: "Configurable retention, default 100 items."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Toggle("", isOn: captureHistoryEnabledBinding)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }

            if captureService.isClipboardHistoryEnabled {
                Divider().overlay(Theme.Colors.separator.opacity(0.6))

                HStack {
                    Text(localizer.t("保留 \(captureService.historyLimit) 条", en: "Keep \(captureService.historyLimit) items", zhHant: "保留 \(captureService.historyLimit) 筆", ja: "\(captureService.historyLimit)件保存", ko: "\(captureService.historyLimit)개 보관", mt: "Keep \(captureService.historyLimit) items"))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                    Stepper("", value: captureHistoryLimitBinding, in: CaptureShelfService.minHistoryLimit...CaptureShelfService.maxHistoryLimit, step: 20)
                        .labelsHidden()
                        .controlSize(.small)
                }

                HStack(spacing: Theme.Spacing.md) {
                    Toggle(localizer.t("图片", en: "Images", zhHant: "圖片", ja: "画像", ko: "이미지", mt: "Images"), isOn: captureImagesBinding)
                        .toggleStyle(.checkbox)
                    Toggle(localizer.t("文件", en: "Files", zhHant: "檔案", ja: "ファイル", ko: "파일", mt: "Files"), isOn: captureFilesBinding)
                        .toggleStyle(.checkbox)
                    Spacer()
                }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .cardStyle(padding: Theme.Spacing.md)
    }

    private var captureHistoryPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                SectionHeader(title: localizer.t("最近历史", en: "Recent History", zhHant: "最近歷史", ja: "最近の履歴", ko: "최근 기록", mt: "Recent History"), icon: "clock.arrow.circlepath")
                Spacer()
                if !captureService.items.isEmpty {
                    Button {
                        captureService.clearHistory()
                    } label: {
                        Image(systemName: "trash")
                            .font(Theme.Font.captionMedium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(localizer.t("清空历史", en: "Clear history", zhHant: "清空歷史", ja: "履歴を消去", ko: "기록 지우기", mt: "Clear history"))
                }
            }

            if !captureService.isClipboardHistoryEnabled {
                captureEmptyCard(
                    icon: "pause.circle",
                    title: localizer.t("剪贴板历史已暂停", en: "Clipboard history is paused", zhHant: "剪貼簿歷史已暫停", ja: "クリップボード履歴は一時停止中", ko: "클립보드 기록이 일시 중지됨", mt: "Clipboard history is paused"),
                    detail: localizer.t("开启后记录后续复制内容。", en: "Enable it to keep future copied items.", zhHant: "開啟後會記錄後續複製內容。", ja: "有効にすると以降のコピー内容を保存します。", ko: "켜면 이후 복사한 항목을 보관합니다.", mt: "Enable it to keep future copied items.")
                )
            } else if captureService.items.isEmpty {
                captureEmptyCard(
                    icon: "tray",
                    title: localizer.t("还没有历史", en: "No history yet", zhHant: "尚無歷史", ja: "履歴はまだありません", ko: "기록이 아직 없습니다", mt: "No history yet"),
                    detail: localizer.t("复制文本、图片或文件后会显示在这里。", en: "Copied text, images, and files appear here.", zhHant: "複製文字、圖片或檔案後會顯示在這裡。", ja: "コピーしたテキスト、画像、ファイルがここに表示されます。", ko: "복사한 텍스트, 이미지, 파일이 여기에 표시됩니다.", mt: "Copied text, images, and files appear here.")
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(captureService.items.prefix(8))) { item in
                        captureHistoryRow(item)
                        if item.id != captureService.items.prefix(8).last?.id {
                            Divider().overlay(Theme.Colors.separator.opacity(0.5))
                        }
                    }
                }
                .background(Theme.Colors.cardBg.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                if captureService.items.count > 8 {
                    Text(localizer.t("还有 \(captureService.items.count - 8) 条保存在本机历史。", en: "\(captureService.items.count - 8) more items are kept locally.", zhHant: "還有 \(captureService.items.count - 8) 筆保存在本機歷史。", ja: "ほかに\(captureService.items.count - 8)件がローカル履歴に保存されています。", ko: "\(captureService.items.count - 8)개 항목이 로컬 기록에 더 있습니다.", mt: "\(captureService.items.count - 8) more items are kept locally."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .cardStyle(padding: Theme.Spacing.md)
    }

    private func captureStatusBanner(_ status: CaptureShelfStatus) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: captureStatusIcon(status))
                .font(Theme.Font.captionMedium)
            Text(captureStatusText(status))
                .font(Theme.Font.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(captureStatusColor(status))
        .padding(Theme.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(captureStatusColor(status).opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func captureEmptyCard(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Colors.textTertiary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.cardBg.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func captureHistoryRow(_ item: CaptureShelfItem) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            captureHistoryIcon(item)

            VStack(alignment: .leading, spacing: 3) {
                Text(captureItemTitle(item))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(captureItemDetail(item))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Button {
                captureService.copy(item)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(Theme.Font.captionMedium)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .help(localizer.t("复制", en: "Copy", zhHant: "複製", ja: "コピー", ko: "복사", mt: "Copy"))

            Button {
                captureService.delete(item)
            } label: {
                Image(systemName: "xmark")
                    .font(Theme.Font.captionMedium)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.textTertiary)
            .help(localizer.t("删除", en: "Delete", zhHant: "刪除", ja: "削除", ko: "삭제", mt: "Delete"))
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .frame(minHeight: 48)
    }

    @ViewBuilder
    private func captureHistoryIcon(_ item: CaptureShelfItem) -> some View {
        if item.kind == .image, let data = item.imagePNGData, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 32, height: 32)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        } else {
            Image(systemName: captureItemIcon(item))
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(captureItemColor(item))
                .frame(width: 32, height: 32)
                .background(captureItemColor(item).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
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

    private func captureItemTitle(_ item: CaptureShelfItem) -> String {
        switch item.kind {
        case .text:
            return item.title.isEmpty ? localizer.t("文本", en: "Text", zhHant: "文字", ja: "テキスト", ko: "텍스트", mt: "Text") : item.title
        case .image:
            if item.title == "selection" {
                return localizer.t("区域截图", en: "Area Screenshot", zhHant: "區域截圖", ja: "範囲スクリーンショット", ko: "영역 스크린샷", mt: "Area Screenshot")
            }
            if item.title == "screen" {
                return localizer.t("屏幕截图", en: "Screenshot", zhHant: "螢幕截圖", ja: "スクリーンショット", ko: "스크린샷", mt: "Screenshot")
            }
            return localizer.t("图片", en: "Image", zhHant: "圖片", ja: "画像", ko: "이미지", mt: "Image")
        case .files:
            return item.title.isEmpty ? localizer.t("文件", en: "Files", zhHant: "檔案", ja: "ファイル", ko: "파일", mt: "Files") : item.title
        }
    }

    private func captureItemDetail(_ item: CaptureShelfItem) -> String {
        let time = relativeTimeText(for: item.createdAt)
        switch item.kind {
        case .text:
            return "\(item.detail) · \(time)"
        case .image:
            return "\(item.detail) · \(time)"
        case .files:
            return item.filePaths.count <= 1 ? "\(item.detail) · \(time)" : "\(item.filePaths.count) · \(time)"
        }
    }

    private func captureItemIcon(_ item: CaptureShelfItem) -> String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc.fill"
        }
    }

    private func captureItemColor(_ item: CaptureShelfItem) -> Color {
        switch item.kind {
        case .text: return Theme.Colors.accent
        case .image: return Theme.Colors.info
        case .files: return Theme.Colors.warning
        }
    }

    private func captureStatusText(_ status: CaptureShelfStatus) -> String {
        switch status.code {
        case .captureCopied:
            return localizer.t("截图已复制到剪贴板。", en: "Screenshot copied to clipboard.", zhHant: "截圖已複製到剪貼簿。", ja: "スクリーンショットをクリップボードにコピーしました。", ko: "스크린샷을 클립보드에 복사했습니다.", mt: "Screenshot copied to clipboard.")
        case .capturePermissionNeeded:
            return localizer.t("需要开启屏幕录制权限后再截屏。", en: "Screen Recording permission is required before capture.", zhHant: "需要開啟螢幕錄製權限後再截圖。", ja: "取得するには画面収録の権限が必要です。", ko: "캡처하려면 화면 기록 권한이 필요합니다.", mt: "Screen Recording permission is required before capture.")
        case .captureFailed:
            return localizer.t("截屏失败，请确认屏幕录制权限。", en: "Capture failed. Check Screen Recording permission.", zhHant: "截圖失敗，請確認螢幕錄製權限。", ja: "取得に失敗しました。画面収録の権限を確認してください。", ko: "캡처에 실패했습니다. 화면 기록 권한을 확인하세요.", mt: "Capture failed. Check Screen Recording permission.")
        case .recordingStarted:
            return localizer.t("正在录屏。", en: "Recording started.", zhHant: "正在錄屏。", ja: "録画を開始しました。", ko: "녹화를 시작했습니다.", mt: "Recording started.")
        case .recordingStopped:
            return localizer.t("录屏已保存到本地采集历史。", en: "Recording saved to local capture history.", zhHant: "錄屏已儲存到本機採集歷史。", ja: "録画をローカル収集履歴に保存しました。", ko: "녹화가 로컬 캡처 기록에 저장되었습니다.", mt: "Recording saved to local capture history.")
        case .recordingFailed:
            return status.detail ?? localizer.t("录屏失败，请确认屏幕录制权限。", en: "Recording failed. Check Screen Recording permission.", zhHant: "錄屏失敗，請確認螢幕錄製權限。", ja: "録画に失敗しました。画面収録の権限を確認してください。", ko: "녹화에 실패했습니다. 화면 기록 권한을 확인하세요.", mt: "Recording failed. Check Screen Recording permission.")
        case .itemCopied:
            return localizer.t("已复制到剪贴板。", en: "Copied to clipboard.", zhHant: "已複製到剪貼簿。", ja: "クリップボードにコピーしました。", ko: "클립보드에 복사했습니다.", mt: "Copied to clipboard.")
        case .historyCleared:
            return localizer.t("历史已清空。", en: "History cleared.", zhHant: "歷史已清空。", ja: "履歴を消去しました。", ko: "기록을 지웠습니다.", mt: "History cleared.")
        case .historyPaused:
            return localizer.t("剪贴板历史已暂停。", en: "Clipboard history paused.", zhHant: "剪貼簿歷史已暫停。", ja: "クリップボード履歴を一時停止しました。", ko: "클립보드 기록을 일시 중지했습니다.", mt: "Clipboard history paused.")
        }
    }

    private func captureStatusIcon(_ status: CaptureShelfStatus) -> String {
        switch status.level {
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }

    private func captureStatusColor(_ status: CaptureShelfStatus) -> Color {
        switch status.level {
        case .success: return Theme.Colors.success
        case .info: return Theme.Colors.info
        case .warning: return Theme.Colors.warning
        case .error: return Theme.Colors.danger
        }
    }

    private var quotaEmptyStateCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Colors.accent.opacity(0.12))
                        .frame(width: 44, height: 44)
                    if quotaService.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(quotaService.isRefreshing
                        ? localizer.t("正在读取额度数据", en: "Reading quota data", zhHant: "正在讀取額度資料", ja: "クォータデータを読み取り中", ko: "할당량 데이터를 읽는 중", mt: "Reading quota data")
                        : localizer.t("准备检查 provider 状态", en: "Ready to check provider status", zhHant: "準備檢查 provider 狀態", ja: "Provider 状態を確認できます", ko: "Provider 상태 확인 준비됨", mt: "Ready to check provider status"))
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(localizer.t(
                        "TraceFence 正在通过本机的 Codex、Claude、Cursor 等 provider 读取 5 小时、周/月额度和重置时间。首次读取可能需要几秒；如果缺少登录、API Key 或完全磁盘访问权限，结果会在这里给出处理建议。",
                        en: "TraceFence is reading 5-hour, weekly/monthly quota windows and reset times from local providers such as Codex, Claude, and Cursor. The first read can take a few seconds; missing login, API key, or Full Disk Access issues will appear here with next steps.",
                        zhHant: "TraceFence 正在透過本機的 Codex、Claude、Cursor 等 provider 讀取 5 小時、週/月額度與重置時間。首次讀取可能需要幾秒；如果缺少登入、API Key 或完整磁碟存取權限，結果會在這裡給出處理建議。",
                        ja: "TraceFence は Codex、Claude、Cursor などのローカル provider から 5 時間、週/月クォータとリセット時刻を読み取っています。初回読み取りには数秒かかる場合があります。ログイン、API キー、フルディスクアクセスが不足している場合は、ここに対処方法が表示されます。",
                        ko: "TraceFence는 Codex, Claude, Cursor 같은 로컬 provider에서 5시간, 주간/월간 할당량과 재설정 시간을 읽고 있습니다. 첫 읽기에는 몇 초가 걸릴 수 있으며 로그인, API Key, 전체 디스크 접근 권한 문제가 있으면 여기에서 처리 방법을 안내합니다.",
                        mt: "TraceFence is reading 5-hour, weekly/monthly quota windows and reset times from local providers such as Codex, Claude, and Cursor. The first read can take a few seconds; missing login, API key, or Full Disk Access issues will appear here with next steps."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !quotaService.isRefreshing {
                Button {
                    quotaService.refresh()
                } label: {
                    Label(quotaRefreshButtonTitle(), systemImage: "arrow.clockwise")
                        .font(Theme.Font.captionMedium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(quotaService.refreshCooldownRemaining() > 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: Theme.Spacing.lg)
    }

    private func quotaRefreshButtonTitle() -> String {
        _ = quotaRefreshClock
        if quotaService.isRefreshing {
            return localizer.tokenScopeScanning
        }
        let remaining = Int(ceil(quotaService.refreshCooldownRemaining()))
        guard remaining > 0 else { return localizer.refresh }
        return localizer.t(
            "等 \(remaining) 秒后刷新",
            en: "Refresh in \(remaining)s",
            zhHant: "等 \(remaining) 秒後刷新",
            ja: "\(remaining) 秒後に更新",
            ko: "\(remaining)초 후 새로고침",
            mt: "Refresh in \(remaining)s"
        )
    }

    private func quotaRefreshStatusText() -> String? {
        _ = quotaRefreshClock
        if quotaService.isRefreshing {
            if let lastStart = quotaService.lastRefreshRequestedDate {
                let lastStartText = relativeTimeText(for: lastStart)
                return localizer.t(
                    "额度扫描进行中，\(lastStartText)开始",
                    en: "Quota scan running, started \(lastStartText)",
                    zhHant: "額度掃描進行中，\(lastStartText)開始",
                    ja: "クォータスキャン実行中（\(lastStartText)開始）",
                    ko: "할당량 스캔 진행 중, \(lastStartText) 시작",
                    mt: "Quota scan running, started \(lastStartText)"
                )
            }
            return localizer.t("额度扫描进行中", en: "Quota scan running", zhHant: "額度掃描進行中", ja: "クォータスキャン実行中", ko: "할당량 스캔 진행 중", mt: "Quota scan running")
        }
        guard let lastRefreshDate = quotaService.lastRefreshDate else { return nil }
        let refreshAgo = relativeTimeText(for: lastRefreshDate)
        let remaining = Int(ceil(quotaService.refreshCooldownRemaining()))
        if remaining > 0 {
            return localizer.t(
                "上次更新：\(refreshAgo)，\(remaining) 秒后可再刷新",
                en: "Updated \(refreshAgo), refresh again in \(remaining)s",
                zhHant: "上次更新：\(refreshAgo)，\(remaining) 秒後可再刷新",
                ja: "最終更新: \(refreshAgo)、\(remaining)秒後に再更新",
                ko: "마지막 업데이트: \(refreshAgo), \(remaining)초 후 다시 새로고침",
                mt: "Updated \(refreshAgo), refresh again in \(remaining)s"
            )
        }
        return localizer.t(
            "上次更新：\(refreshAgo)",
            en: "Updated \(refreshAgo)",
            zhHant: "上次更新：\(refreshAgo)",
            ja: "最終更新: \(refreshAgo)",
            ko: "마지막 업데이트: \(refreshAgo)",
            mt: "Updated \(refreshAgo)"
        )
    }

    private func quotaProviderCard(_ snapshot: ProviderQuotaSnapshot) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: snapshot.isSetupNotice ? "slider.horizontal.3" : "terminal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(snapshot.isSetupNotice ? Theme.Colors.warning : .white)
                    .frame(width: 30, height: 30)
                    .background(snapshot.isSetupNotice ? Theme.Colors.warning.opacity(0.12) : Theme.Colors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Text(localizedQuotaText(snapshot.providerName))
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if let plan = snapshot.planName, !plan.isEmpty {
                            Text(plan.uppercased())
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.accent.opacity(0.1))
                                .clipShape(Capsule())
                        }
                        if snapshot.isStale {
                            Text(localizer.t("缓存", en: "STALE", zhHant: "快取", ja: "古い値", ko: "이전 값", mt: "STALE"))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.warning)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.Colors.warning.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Text(localizedQuotaText(snapshot.accountLabel ?? sourceLabel(snapshot.source)))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(relativeRefreshText(snapshot.lastSuccessfulAt ?? snapshot.updatedAt))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    if let credits = snapshot.credits {
                        Text(localizer.t("Credits \(String(format: "%.0f", credits))", en: "Credits \(String(format: "%.0f", credits))", zhHant: "Credits \(String(format: "%.0f", credits))", ja: "Credits \(String(format: "%.0f", credits))", ko: "Credits \(String(format: "%.0f", credits))", mt: "Credits \(String(format: "%.0f", credits))"))
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.warning)
                    }
                }
            }

            if snapshot.isStale {
                Label(
                    localizedQuotaText(snapshot.refreshErrorMessage ?? localizer.t(
                        "本次刷新失败，当前显示上一次可信额度。",
                        en: "The latest refresh failed. Showing the last trusted quota values.",
                        zhHant: "本次重新整理失敗，目前顯示上一次可信額度。",
                        ja: "最新の更新に失敗したため、前回の信頼できる値を表示しています。",
                        ko: "최근 새로 고침에 실패하여 마지막으로 확인된 값을 표시합니다.",
                        mt: "The latest refresh failed. Showing the last trusted values."
                    )),
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.warning)
                .fixedSize(horizontal: false, vertical: true)
            }

            if let error = quotaErrorText(snapshot.errorMessage) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(localizedQuotaText(error), systemImage: snapshot.isSetupNotice ? "info.circle.fill" : "exclamationmark.triangle.fill")
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(snapshot.isSetupNotice ? Theme.Colors.textSecondary : Theme.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    if let hint = snapshot.setupHint, !hint.isEmpty {
                        Text(localizedQuotaText(hint))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if shouldOfferQuotaDataAuthorization(snapshot) {
                        Button {
                            authorizeQuotaData()
                        } label: {
                            Label(
                                localizer.t(
                                    "授权 Grok 数据目录",
                                    en: "Authorize Grok Data Folder",
                                    zhHant: "授權 Grok 資料目錄",
                                    ja: "Grok データフォルダを許可",
                                    ko: "Grok 데이터 폴더 승인",
                                    mt: "Authorize Grok Data Folder"),
                                systemImage: "folder.badge.gearshape")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background((snapshot.isSetupNotice ? Theme.Colors.textSecondary : Theme.Colors.warning).opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(snapshot.windows) { window in
                        quotaWindowRow(window)
                    }
                    if let resetCredits = snapshot.resetCredits {
                        quotaResetCreditsSection(resetCredits)
                    }
                }
            }
        }
        .cardStyle(padding: Theme.Spacing.md)
    }

    private func sourceLabel(_ source: String) -> String {
        switch source {
        case "oauth": return "OAuth"
        case "api": return "API"
        case "web": return localizer.t("网页会话", en: "Web session", zhHant: "網頁會話", ja: "Web セッション", ko: "웹 세션", mt: "Web session")
        case "claude-desktop": return "Claude Desktop"
        case "cli": return "CLI"
        case "auto": return localizer.t("自动读取", en: "Auto", zhHant: "自動讀取", ja: "自動読み取り", ko: "자동 읽기", mt: "Auto")
        case "setup": return localizer.t("可选配置", en: "Optional setup", zhHant: "可選配置", ja: "任意設定", ko: "선택 설정", mt: "Optional setup")
        default: return source
        }
    }

    private func shouldOfferQuotaDataAuthorization(_ snapshot: ProviderQuotaSnapshot) -> Bool {
        guard SandboxPaths.isSandboxed,
              snapshot.providerName.caseInsensitiveCompare("Grok") == .orderedSame,
              let error = snapshot.errorMessage?.lowercased()
        else { return false }
        return error.contains("fetch strategy") || error.contains("login session") || error.contains("登录会话")
    }

    private func authorizeQuotaData() {
        service.operationMonitor.requestAccessForStalePaths()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            quotaService.refresh()
        }
    }

    private func quotaWindowTitle(_ window: ProviderQuotaWindow) -> String {
        if let scopedName = window.scopedWeeklyAllowanceDisplayName {
            return localizer.t(
                "Claude \(scopedName) 每周额度",
                en: "Claude \(scopedName) weekly quota",
                zhHant: "Claude \(scopedName) 每週額度",
                ja: "Claude \(scopedName) 週間クォータ",
                ko: "Claude \(scopedName) 주간 할당량",
                mt: "Claude \(scopedName) weekly quota"
            )
        }
        if isCodexSparkQuotaWindow(window) {
            switch window.kind {
            case .fiveHour:
                return localizer.t("Codex Spark 5 小时额度", en: "Codex Spark 5-hour quota", zhHant: "Codex Spark 5 小時額度", ja: "Codex Spark 5時間クォータ", ko: "Codex Spark 5시간 할당량", mt: "Codex Spark 5-hour quota")
            case .weekly:
                return localizer.t("Codex Spark 每周额度", en: "Codex Spark weekly quota", zhHant: "Codex Spark 每週額度", ja: "Codex Spark 週間クォータ", ko: "Codex Spark 주간 할당량", mt: "Codex Spark weekly quota")
            case .monthly:
                return localizer.t("Codex Spark 每月额度", en: "Codex Spark monthly quota", zhHant: "Codex Spark 每月額度", ja: "Codex Spark 月間クォータ", ko: "Codex Spark 월간 할당량", mt: "Codex Spark monthly quota")
            case .extra:
                return localizedQuotaText(window.title)
            }
        }

        switch window.kind {
        case .fiveHour:
            return localizer.t("5 小时额度", en: "5-hour quota", zhHant: "5 小時額度", ja: "5時間クォータ", ko: "5시간 할당량", mt: "5-hour quota")
        case .weekly:
            return localizer.t("每周额度", en: "Weekly quota", zhHant: "每週額度", ja: "週間クォータ", ko: "주간 할당량", mt: "Weekly quota")
        case .monthly:
            return localizer.t("每月额度", en: "Monthly quota", zhHant: "每月額度", ja: "月間クォータ", ko: "월간 할당량", mt: "Monthly quota")
        case .extra:
            return localizedQuotaText(window.title)
        }
    }

    private func isCodexSparkQuotaWindow(_ window: ProviderQuotaWindow) -> Bool {
        let normalized = "\(window.id) \(window.title)"
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
        return normalized.contains("codex spark")
    }

    private func localizedResetType(_ raw: String) -> String {
        let normalized = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalized.lowercased()
        if lower.contains("manual") || lower.contains("rate limit") || lower.contains("reset") || raw.contains("重置") {
            return localizer.t("速率重置", en: "Rate-limit reset", zhHant: "速率重置", ja: "レート制限リセット", ko: "속도 제한 재설정", mt: "Rate-limit reset")
        }
        return localizedQuotaText(normalized)
    }

    private func quotaErrorText(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            return "Quota monitor engine stopped before returning data. Please update or reinstall TraceFence."
        }
        let normalized = value.lowercased()
        if normalized.contains("inherited-sandbox")
            || normalized.contains("not in an inherited sandbox") {
            return localizer.t(
                "额度监控引擎无法启动：当前 TraceFence 与当前分发渠道的 Helper 沙箱不匹配。请使用同分发渠道的配套安装包或重装 TraceFence。",
                en: "Quota monitor helper cannot start: helper sandbox mode does not match the current TraceFence distribution channel. Use the matching release package or reinstall TraceFence.",
                zhHant: "額度監控引擎無法啟動：目前 TraceFence 與當前發佈渠道的 Helper 沙盒不匹配。請使用同渠道的配套安裝包或重新安裝 TraceFence。",
                ja: "クォータ監視ヘルパーを起動できません。現在の TraceFence と配信チャンネルの Helper サンドボックスが一致しません。対応する配布パッケージを使用するか再インストールしてください。",
                ko: "할당량 모니터 헬퍼를 시작할 수 없습니다. 현재 TraceFence와 배포 채널의 헬퍼 샌드박스가 일치하지 않습니다. 동일 채널 설치본을 사용하거나 TraceFence를 재설치하세요.",
                mt: "Quota monitor helper cannot start: helper sandbox mode does not match the current TraceFence distribution channel. Use the matching release package or reinstall TraceFence."
            )
        }
        return value
    }

    private func localizedQuotaText(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return text }

        switch text {
        case "Other Providers", "其它 Provider":
            return localizer.t("其它 Provider", en: "Other Providers", zhHant: "其它 Provider", ja: "その他の Provider", ko: "기타 Provider", mt: "Other Providers")
        case "Optional setup", "可选配置":
            return localizer.t("可选配置", en: "Optional setup", zhHant: "可選配置", ja: "任意設定", ko: "선택 설정", mt: "Optional setup")
        case "auto", "Auto", "AUTO":
            return localizer.t("自动读取", en: "Auto", zhHant: "自動讀取", ja: "自動読み取り", ko: "자동 읽기", mt: "Auto")
        case "Manual reset credits", "Manual reset credit", "manual_reset", "manual reset", "手动重置次数":
            return localizer.t("手动重置", en: "Manual reset", zhHant: "手動重置", ja: "手動リセット", ko: "수동 재설정", mt: "Manual reset")
        case "Rate-limit reset", "Rate limit reset", "rate_limit_reset", "rate limit reset", "速率重置":
            return localizer.t("速率重置", en: "Rate-limit reset", zhHant: "速率重置", ja: "レート制限リセット", ko: "속도 제한 재설정", mt: "Rate-limit reset")
        case "Quota monitor engine was not found. Please reinstall TraceFence.", "未找到额度监控引擎，请重新安装 TraceFence。":
            return localizer.t("未找到额度监控引擎，请重新安装 TraceFence。", en: "Quota monitor engine was not found. Please reinstall TraceFence.", zhHant: "找不到額度監控引擎，請重新安裝 TraceFence。", ja: "クォータ監視エンジンが見つかりません。TraceFence を再インストールしてください。", ko: "할당량 모니터 엔진을 찾을 수 없습니다. TraceFence를 다시 설치하세요.", mt: "Quota monitor engine was not found. Please reinstall TraceFence.")
        case "No quota data is available yet. Log in or enable the Agent you want to monitor.", "暂时没有可显示的额度数据。请先登录或启用需要监控的 Agent。":
            return localizer.t("暂时没有可显示的额度数据。请先登录或启用需要监控的 Agent。", en: "No quota data is available yet. Log in or enable the Agent you want to monitor.", zhHant: "暫時沒有可顯示的額度資料。請先登入或啟用需要監控的 Agent。", ja: "表示できるクォータデータはまだありません。監視したい Agent にログインするか有効にしてください。", ko: "아직 표시할 할당량 데이터가 없습니다. 모니터링할 Agent에 로그인하거나 활성화하세요.", mt: "No quota data is available yet. Log in or enable the Agent you want to monitor.")
        case "Installed Agents such as Codex, Claude, and Cursor will show actionable diagnostics here.", "已安装的 Codex、Claude、Cursor 等 Agent 会在这里显示可操作诊断。":
            return localizer.t("已安装的 Codex、Claude、Cursor 等 Agent 会在这里显示可操作诊断。", en: "Installed Agents such as Codex, Claude, and Cursor will show actionable diagnostics here.", zhHant: "已安裝的 Codex、Claude、Cursor 等 Agent 會在這裡顯示可操作診斷。", ja: "Codex、Claude、Cursor などインストール済みの Agent は、ここに対処可能な診断を表示します。", ko: "설치된 Codex, Claude, Cursor 같은 Agent의 실행 가능한 진단이 여기에 표시됩니다.", mt: "Installed Agents such as Codex, Claude, and Cursor will show actionable diagnostics here.")
        case "Install or log in to the matching Agent, or enable its provider to show detailed diagnostics.", "安装/登录对应 Agent，或启用 provider 后，TraceFence 会显示具体诊断。":
            return localizer.t("安装/登录对应 Agent，或启用 provider 后，TraceFence 会显示具体诊断。", en: "Install or log in to the matching Agent, or enable its provider to show detailed diagnostics.", zhHant: "安裝/登入對應 Agent，或啟用 provider 後，TraceFence 會顯示具體診斷。", ja: "該当 Agent をインストールまたはログインするか、Provider を有効にすると詳細な診断が表示されます。", ko: "해당 Agent를 설치/로그인하거나 provider를 활성화하면 자세한 진단이 표시됩니다.", mt: "Install or log in to the matching Agent, or enable its provider to show detailed diagnostics.")
        case "Quota monitor engine timed out. TraceFence stopped this read automatically.", "额度监控引擎响应超时，TraceFence 已自动结束本次读取。":
            return localizer.t("额度监控引擎响应超时，TraceFence 已自动结束本次读取。", en: "Quota monitor engine timed out. TraceFence stopped this read automatically.", zhHant: "額度監控引擎回應逾時，TraceFence 已自動結束本次讀取。", ja: "クォータ監視エンジンがタイムアウトしました。TraceFence は今回の読み取りを自動停止しました。", ko: "할당량 모니터 엔진 응답 시간이 초과되어 TraceFence가 이번 읽기를 자동으로 중지했습니다.", mt: "Quota monitor engine timed out. TraceFence stopped this read automatically.")
        case "Quota monitor engine cannot run due inherited-sandbox mismatch", "Quota monitor engine cannot run in this build context due inherited-sandbox mismatch.":
            return localizer.t("额度监控引擎无法启动：当前 TraceFence 与当前分发渠道的 Helper 沙箱不匹配。请使用同分发渠道的配套安装包或重装 TraceFence。", en: "Quota monitor helper cannot start: helper sandbox mode does not match the current TraceFence distribution channel. Use the matching release package or reinstall TraceFence.", zhHant: "額度監控引擎無法啟動：目前 TraceFence 與當前發佈渠道的 Helper 沙盒不匹配。請使用同渠道的配套安裝包或重新安裝 TraceFence。", ja: "クォータ監視ヘルパーを起動できません。現在の TraceFence と配信チャンネルの Helper サンドボックスが一致しません。対応する配布パッケージを使用するか再インストールしてください。", ko: "할당량 모니터 헬퍼를 시작할 수 없습니다. 현재 TraceFence와 배포 채널의 헬퍼 샌드박스가 일치하지 않습니다. 동일 채널 설치본을 사용하거나 TraceFence를 재설치하세요.", mt: "Quota monitor helper cannot start: helper sandbox mode does not match the current TraceFence distribution channel. Use the matching release package or reinstall TraceFence.")
        case "Quota monitor engine produced no output.", "额度监控引擎没有输出。":
            return localizer.t("额度监控引擎没有输出。", en: "Quota monitor engine produced no output.", zhHant: "額度監控引擎沒有輸出。", ja: "クォータ監視エンジンから出力がありません。", ko: "할당량 모니터 엔진 출력이 없습니다.", mt: "Quota monitor engine produced no output.")
        case "Quota monitor engine stopped before returning data. Please update or reinstall TraceFence.", "额度监控引擎启动失败，请更新或重新安装 TraceFence。":
            return localizer.t("额度监控引擎启动失败，请更新或重新安装 TraceFence。", en: "Quota monitor engine stopped before returning data. Please update or reinstall TraceFence.", zhHant: "額度監控引擎啟動失敗，請更新或重新安裝 TraceFence。", ja: "クォータ監視エンジンを起動できませんでした。TraceFence を更新または再インストールしてください。", ko: "할당량 모니터 엔진을 시작하지 못했습니다. TraceFence를 업데이트하거나 다시 설치하세요.", mt: "Quota monitor engine stopped before returning data. Please update or reinstall TraceFence.")
        case "No Cursor login session found", "未发现 Cursor 登录会话", "No Cursor session found":
            return localizer.t("未发现 Cursor 登录会话", en: "No Cursor login session found", zhHant: "未發現 Cursor 登入會話", ja: "Cursor のログインセッションが見つかりません", ko: "Cursor 로그인 세션을 찾을 수 없습니다", mt: "No Cursor login session found")
        case "Command line tool is not installed or not on PATH", "命令行工具未安装或不在 PATH 中":
            return localizer.t("命令行工具未安装或不在 PATH 中", en: "Command line tool is not installed or not on PATH", zhHant: "命令列工具未安裝或不在 PATH 中", ja: "コマンドラインツールが未インストール、または PATH にありません", ko: "명령줄 도구가 설치되지 않았거나 PATH에 없습니다", mt: "Command line tool is not installed or not on PATH")
        case "Grok is installed, but its login data is not readable. Authorize your Home or ~/.grok folder in TraceFence, then refresh. If it still fails, run `grok login`.":
            return localizer.t(
                "已检测到 Grok，但暂时无法读取登录数据。请授权主目录或 ~/.grok 后刷新；若仍失败，请运行 `grok login`。",
                en: "Grok is installed, but its login data is not readable. Authorize your Home or ~/.grok folder in TraceFence, then refresh. If it still fails, run `grok login`.",
                zhHant: "已偵測到 Grok，但暫時無法讀取登入資料。請授權主目錄或 ~/.grok 後重新整理；若仍失敗，請執行 `grok login`。",
                ja: "Grok は検出されましたが、ログインデータを読み取れません。ホームまたは ~/.grok フォルダを許可して更新してください。解決しない場合は `grok login` を実行してください。",
                ko: "Grok가 감지되었지만 로그인 데이터를 읽을 수 없습니다. 홈 또는 ~/.grok 폴더를 승인한 뒤 새로고침하세요. 계속 실패하면 `grok login`을 실행하세요.",
                mt: "Grok is installed, but its login data is not readable. Authorize your Home or ~/.grok folder in TraceFence, then refresh. If it still fails, run `grok login`.")
        default:
            break
        }

        if let count = collapsedProviderCount(in: text) {
            return localizer.t("还有 \(count) 个未安装或未启用的 provider 已收起。", en: "\(count) inactive providers are collapsed.", zhHant: "還有 \(count) 個未安裝或未啟用的 provider 已收起。", ja: "\(count) 個の未インストールまたは未有効化の Provider を折りたたみました。", ko: "\(count)개의 설치되지 않았거나 비활성화된 provider를 접었습니다.", mt: "\(count) inactive providers are collapsed.")
        }
        if let resetCreditTitle = localizedResetCreditQuotaTitle(text) {
            return resetCreditTitle
        }

        if let provider = providerName(from: text, suffix: " API Key 未配置") {
            return providerApiKeyMissing(provider)
        }
        if let provider = providerName(from: text, suffix: " API key is not configured") {
            return providerApiKeyMissing(provider)
        }
        if let provider = providerName(from: text, suffix: " CLI 暂时无法调用") {
            return providerCliUnavailable(provider)
        }
        if let provider = providerName(from: text, suffix: " CLI is temporarily unavailable") {
            return providerCliUnavailable(provider)
        }
        if let provider = providerName(from: text, suffix: " CLI 未安装") {
            return providerCliMissing(provider)
        }
        if let provider = providerName(from: text, suffix: " CLI is not installed") {
            return providerCliMissing(provider)
        }
        if let provider = providerName(from: text, prefix: "No usable ", suffix: " login session found") {
            return providerSessionMissing(provider)
        }
        if let provider = providerName(from: text, suffix: " 未发现可用登录会话") {
            return providerSessionMissing(provider)
        }
        if let provider = providerName(from: text, prefix: "No available fetch strategy for ", suffix: "") {
            return providerNoFetchStrategy(provider)
        }
        if let provider = providerName(from: text, suffix: " 暂无可用读取方式") {
            return providerNoFetchStrategy(provider)
        }
        if let provider = providerName(from: text, prefix: "需要配置 ", suffix: " 的 API Key。") {
            return providerApiKeySetupHint(provider)
        }
        if let provider = providerName(from: text, prefix: "Configure the ", suffix: " API key.") {
            return providerApiKeySetupHint(provider)
        }
        if let provider = providerName(from: text, prefix: "Configure the ", suffix: " API key or account credentials, then refresh the TraceFence provider monitor.") {
            return providerApiKeySetupHint(provider)
        }
        if let provider = providerName(from: text, prefix: "本机已检测到 ", suffix: "，但额度读取器无法调用它的命令行工具。") {
            return providerCliRepairHint(provider)
        }
        if let provider = providerName(before: " appears to be installed, but the quota reader cannot run its CLI", in: text) {
            return providerCliRepairHint(provider)
        }
        if text.contains("This provider is enabled, but its CLI was not found.") || text.contains("已启用该 provider，但本机未检测到命令行工具。") {
            return localizer.t("已启用该 provider，但本机未检测到命令行工具。安装对应 CLI 并确保命令在 PATH 中后即可监控。", en: text, zhHant: "已啟用該 provider，但本機未偵測到命令列工具。安裝對應 CLI 並確保命令在 PATH 中後即可監控。", ja: text, ko: text, mt: text)
        }
        if text.contains("The related Agent was detected") || text.contains("本机检测到相关 Agent") {
            return localizer.t("本机检测到相关 Agent，但没有可读取的登录会话。请先登录对应 Provider，并在 TraceFence 中授权对应数据目录后重试。", en: text, zhHant: "本機偵測到相關 Agent，但沒有可讀取的登入會話。請先登入對應 Provider，並在 TraceFence 中授權對應資料目錄後重試。", ja: text, ko: text, mt: text)
        }
        if text.contains("Cursor was detected") || text.contains("检测到 Cursor") {
            return localizer.t("检测到 Cursor，但未读到可用会话。请登录 Cursor，并在 TraceFence 中授权对应数据目录后重试。", en: "Cursor was detected, but no usable session was found. Log in to Cursor, authorize the matching data folder in TraceFence, then try again.", zhHant: "偵測到 Cursor，但未讀到可用會話。請登入 Cursor，並在 TraceFence 中授權對應資料目錄後重試。", ja: "Cursor は検出されましたが、利用可能なセッションがありません。Cursor にログインし、TraceFence で該当データフォルダを許可してから再試行してください。", ko: "Cursor가 감지되었지만 사용 가능한 세션을 찾지 못했습니다. Cursor에 로그인하고 TraceFence에서 해당 데이터 폴더를 승인한 뒤 다시 시도하세요.", mt: "Cursor was detected, but no usable session was found. Log in to Cursor, authorize the matching data folder in TraceFence, then try again.")
        }
        if text.contains("Claude was detected") || text.contains("检测到 Claude") {
            return localizer.t("检测到 Claude。请确认 Claude CLI 可运行，并在 Claude 中完成登录。", en: "Claude was detected. Make sure the Claude CLI runs, then finish signing in to Claude.", zhHant: "偵測到 Claude。請確認 Claude CLI 可執行，並在 Claude 中完成登入。", ja: "Claude が検出されました。Claude CLI が実行できることを確認し、Claude へのサインインを完了してください。", ko: "Claude가 감지되었습니다. Claude CLI가 실행되는지 확인한 뒤 Claude 로그인을 완료하세요.", mt: "Claude was detected. Make sure the Claude CLI runs, then finish signing in to Claude.")
        }

        return text
    }

    private func localizedResetCreditQuotaTitle(_ text: String) -> String? {
        let lower = text
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .lowercased()
        let providerPrefix: String
        if lower.contains("codex spark") {
            providerPrefix = "Codex Spark"
        } else if lower.contains("codex") {
            providerPrefix = "Codex"
        } else {
            providerPrefix = ""
        }

        let zhPrefix = providerPrefix.isEmpty ? "" : "\(providerPrefix) "
        if lower.contains("5 hour") || lower.contains("5h") || lower.contains("five hour") || text.contains("5 小时") || text.contains("5 小時") {
            return localizer.t("\(zhPrefix)5 小时", en: providerPrefix.isEmpty ? "5-hour" : "\(providerPrefix) 5-hour", zhHant: "\(zhPrefix)5 小時", ja: providerPrefix.isEmpty ? "5時間" : "\(providerPrefix) 5時間", ko: providerPrefix.isEmpty ? "5시간" : "\(providerPrefix) 5시간", mt: providerPrefix.isEmpty ? "5-hour" : "\(providerPrefix) 5-hour")
        }
        if lower.contains("weekly") || lower.contains("week") || text.contains("每周") || text.contains("每週") {
            return localizer.t("\(zhPrefix)每周", en: providerPrefix.isEmpty ? "Weekly" : "\(providerPrefix) weekly", zhHant: "\(zhPrefix)每週", ja: providerPrefix.isEmpty ? "週間" : "\(providerPrefix) 週間", ko: providerPrefix.isEmpty ? "주간" : "\(providerPrefix) 주간", mt: providerPrefix.isEmpty ? "Weekly" : "\(providerPrefix) weekly")
        }
        if lower.contains("monthly") || lower.contains("month") || text.contains("每月") {
            return localizer.t("\(zhPrefix)每月", en: providerPrefix.isEmpty ? "Monthly" : "\(providerPrefix) monthly", zhHant: "\(zhPrefix)每月", ja: providerPrefix.isEmpty ? "月間" : "\(providerPrefix) 月間", ko: providerPrefix.isEmpty ? "월간" : "\(providerPrefix) 월간", mt: providerPrefix.isEmpty ? "Monthly" : "\(providerPrefix) monthly")
        }
        return nil
    }

    private func collapsedProviderCount(in text: String) -> Int? {
        guard text.contains("inactive providers are collapsed") || text.contains("未安装或未启用") else { return nil }
        let digits = text.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        return Int(String(String.UnicodeScalarView(digits)))
    }

    private func providerName(from text: String, prefix: String = "", suffix: String) -> String? {
        guard text.hasPrefix(prefix), suffix.isEmpty || text.hasSuffix(suffix) || text.contains(suffix) else { return nil }
        let start = text.index(text.startIndex, offsetBy: prefix.count)
        let end: String.Index
        if suffix.isEmpty {
            end = text.endIndex
        } else if let suffixRange = text.range(of: suffix, range: start..<text.endIndex) {
            end = suffixRange.lowerBound
        } else {
            return nil
        }
        let value = String(text[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func providerName(before marker: String, in text: String) -> String? {
        guard let range = text.range(of: marker) else { return nil }
        let value = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func providerApiKeyMissing(_ provider: String) -> String {
        localizer.t("\(provider) API Key 未配置", en: "\(provider) API key is not configured", zhHant: "\(provider) API Key 未配置", ja: "\(provider) API キーが未設定です", ko: "\(provider) API Key가 설정되지 않았습니다", mt: "\(provider) API key is not configured")
    }

    private func providerCliUnavailable(_ provider: String) -> String {
        localizer.t("\(provider) CLI 暂时无法调用", en: "\(provider) CLI is temporarily unavailable", zhHant: "\(provider) CLI 暫時無法呼叫", ja: "\(provider) CLI は一時的に利用できません", ko: "\(provider) CLI를 일시적으로 호출할 수 없습니다", mt: "\(provider) CLI is temporarily unavailable")
    }

    private func providerCliMissing(_ provider: String) -> String {
        localizer.t("\(provider) CLI 未安装", en: "\(provider) CLI is not installed", zhHant: "\(provider) CLI 未安裝", ja: "\(provider) CLI がインストールされていません", ko: "\(provider) CLI가 설치되지 않았습니다", mt: "\(provider) CLI is not installed")
    }

    private func providerSessionMissing(_ provider: String) -> String {
        localizer.t("\(provider) 未发现可用登录会话", en: "No usable \(provider) login session found", zhHant: "\(provider) 未發現可用登入會話", ja: "\(provider) の利用可能なログインセッションが見つかりません", ko: "사용 가능한 \(provider) 로그인 세션을 찾을 수 없습니다", mt: "No usable \(provider) login session found")
    }

    private func providerNoFetchStrategy(_ provider: String) -> String {
        localizer.t("\(provider) 暂无可用读取方式", en: "No available fetch strategy for \(provider)", zhHant: "\(provider) 暫無可用讀取方式", ja: "\(provider) で利用可能な読み取り方式がありません", ko: "\(provider)에 사용할 수 있는 읽기 방식이 없습니다", mt: "No available fetch strategy for \(provider)")
    }

    private func providerApiKeySetupHint(_ provider: String) -> String {
        localizer.t(
            "需要配置 \(provider) 的 API Key 或账号凭证，然后刷新 TraceFence 额度监控。",
            en: "Configure the \(provider) API key or account credentials, then refresh the TraceFence provider monitor.",
            zhHant: "需要配置 \(provider) 的 API Key 或帳號憑證，然後重新整理 TraceFence 額度監控。",
            ja: "\(provider) の API キーまたはアカウント認証情報を設定してから、TraceFence のクォータ監視を更新してください。",
            ko: "\(provider) API Key 또는 계정 인증 정보를 설정한 뒤 TraceFence 할당량 모니터를 새로고침하세요.",
            mt: "Configure the \(provider) API key or account credentials, then refresh the TraceFence provider monitor."
        )
    }

    private func providerCliRepairHint(_ provider: String) -> String {
        localizer.t(
            "本机已检测到 \(provider)，但额度读取器无法调用它的命令行工具。请重新安装或修复 \(provider) CLI，确保终端中可直接运行。",
            en: "\(provider) appears to be installed, but the quota reader cannot run its CLI. Reinstall or repair the \(provider) CLI so it works directly in Terminal.",
            zhHant: "本機已偵測到 \(provider)，但額度讀取器無法呼叫它的命令列工具。請重新安裝或修復 \(provider) CLI，確保終端機中可直接執行。",
            ja: "\(provider) はインストール済みのようですが、クォータリーダーが CLI を実行できません。\(provider) CLI を再インストールまたは修復し、Terminal で直接実行できるようにしてください。",
            ko: "\(provider)이 설치된 것으로 보이지만 할당량 리더가 CLI를 실행할 수 없습니다. \(provider) CLI를 다시 설치하거나 복구해 터미널에서 직접 실행되도록 하세요.",
            mt: "\(provider) appears to be installed, but the quota reader cannot run its CLI. Reinstall or repair the \(provider) CLI so it works directly in Terminal."
        )
    }

    private func quotaWindowRow(_ window: ProviderQuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(quotaWindowTitle(window))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(resetText(window.resetsAt))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
                Text("\(Int(window.remainingPercent.rounded()))%")
                    .font(Theme.Font.headline)
                    .monospacedDigit()
                    .foregroundStyle(quotaColor(window.remainingPercent))
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Theme.Colors.textTertiary.opacity(0.14))
                    Capsule()
                        .fill(quotaColor(window.remainingPercent))
                        .frame(width: max(8, proxy.size.width * window.remainingPercent / 100))
                }
            }
            .frame(height: 8)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.background.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func quotaResetCreditsSection(_ resetCredits: ProviderQuotaResetCredits) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                Label(localizer.t("手动重置次数", en: "Manual reset credits", zhHant: "手動重置次數", ja: "手動リセット回数", ko: "수동 재설정 횟수", mt: "Manual reset credits"), systemImage: "arrow.counterclockwise.circle.fill")
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                Text(localizer.t("剩余 \(resetCredits.availableCount) 次", en: "\(resetCredits.availableCount) available", zhHant: "剩餘 \(resetCredits.availableCount) 次", ja: "\(resetCredits.availableCount) 回利用可能", ko: "\(resetCredits.availableCount)회 남음", mt: "\(resetCredits.availableCount) available"))
                    .font(Theme.Font.captionMedium)
                    .monospacedDigit()
                    .foregroundStyle(resetCredits.availableCount > 0 ? Theme.Colors.success : Theme.Colors.textTertiary)
            }

            if let next = resetCredits.nextExpiringAvailableCredit, let expiresAt = next.expiresAt {
                Text(localizer.t("最近到期：\(dateTimeText(expiresAt))", en: "Next expires: \(dateTimeText(expiresAt))", zhHant: "最近到期：\(dateTimeText(expiresAt))", ja: "次の期限: \(dateTimeText(expiresAt))", ko: "다음 만료: \(dateTimeText(expiresAt))", mt: "Next expires: \(dateTimeText(expiresAt))"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            let rows = resetCreditRows(resetCredits)
            VStack(spacing: Theme.Spacing.xs) {
                ForEach((0..<rows.count).map { $0 }, id: \.self) { index in
                    resetCreditRow(rows[index])
                }
            }
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func resetCreditRow(_ credit: ProviderQuotaResetCredit) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: resetCreditIcon(credit.status))
                .font(Theme.Font.caption)
                .foregroundStyle(resetCreditColor(credit.status))
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(resetCreditTitle(credit))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(resetCreditDetail(credit))
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: Theme.Spacing.sm)

            Text(resetCreditStatusText(credit.status))
                .font(.caption2)
                .foregroundStyle(resetCreditColor(credit.status))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(resetCreditColor(credit.status).opacity(0.1))
                .clipShape(Capsule())
        }
        .padding(.vertical, 2)
    }

    private func resetCreditRows(_ resetCredits: ProviderQuotaResetCredits) -> [ProviderQuotaResetCredit] {
        resetCredits.credits.sorted { lhs, rhs in
            if lhs.status == .available, rhs.status != .available { return true }
            if lhs.status != .available, rhs.status == .available { return false }
            let lhsDate = lhs.expiresAt ?? lhs.redeemedAt ?? lhs.grantedAt ?? .distantFuture
            let rhsDate = rhs.expiresAt ?? rhs.redeemedAt ?? rhs.grantedAt ?? .distantFuture
            return lhsDate < rhsDate
        }
    }

    private func resetCreditTitle(_ credit: ProviderQuotaResetCredit) -> String {
        if let title = credit.title, !title.isEmpty { return localizedQuotaText(title) }
        if !credit.resetType.isEmpty { return localizedResetType(credit.resetType) }
        return localizer.t("速率重置", en: "Rate-limit reset", zhHant: "速率重置", ja: "レート制限リセット", ko: "속도 제한 재설정", mt: "Rate-limit reset")
    }

    private func resetCreditDetail(_ credit: ProviderQuotaResetCredit) -> String {
        if let expiresAt = credit.expiresAt {
            return localizer.t("到期 \(dateTimeText(expiresAt))", en: "Expires \(dateTimeText(expiresAt))", zhHant: "到期 \(dateTimeText(expiresAt))", ja: "期限 \(dateTimeText(expiresAt))", ko: "\(dateTimeText(expiresAt)) 만료", mt: "Expires \(dateTimeText(expiresAt))")
        }
        if let redeemedAt = credit.redeemedAt {
            return localizer.t("已使用 \(dateTimeText(redeemedAt))", en: "Used \(dateTimeText(redeemedAt))", zhHant: "已使用 \(dateTimeText(redeemedAt))", ja: "使用済み \(dateTimeText(redeemedAt))", ko: "\(dateTimeText(redeemedAt)) 사용됨", mt: "Used \(dateTimeText(redeemedAt))")
        }
        return localizer.t("到期时间未知", en: "Expiry unknown", zhHant: "到期時間未知", ja: "期限不明", ko: "만료 시간 알 수 없음", mt: "Expiry unknown")
    }

    private func resetCreditStatusText(_ status: ProviderQuotaResetCredit.Status) -> String {
        switch status {
        case .available:
            return localizer.t("可用", en: "Available", zhHant: "可用", ja: "利用可能", ko: "사용 가능", mt: "Available")
        case .redeeming:
            return localizer.t("使用中", en: "Redeeming", zhHant: "使用中", ja: "使用中", ko: "사용 중", mt: "Redeeming")
        case .redeemed:
            return localizer.t("已使用", en: "Used", zhHant: "已使用", ja: "使用済み", ko: "사용됨", mt: "Used")
        case .expired:
            return localizer.t("已过期", en: "Expired", zhHant: "已過期", ja: "期限切れ", ko: "만료됨", mt: "Expired")
        case .unknown:
            return localizer.t("未知", en: "Unknown", zhHant: "未知", ja: "不明", ko: "알 수 없음", mt: "Unknown")
        }
    }

    private func resetCreditIcon(_ status: ProviderQuotaResetCredit.Status) -> String {
        switch status {
        case .available: return "checkmark.circle.fill"
        case .redeeming: return "clock.arrow.circlepath"
        case .redeemed: return "checkmark.seal.fill"
        case .expired: return "xmark.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }

    private func resetCreditColor(_ status: ProviderQuotaResetCredit.Status) -> Color {
        switch status {
        case .available: return Theme.Colors.success
        case .redeeming: return Theme.Colors.info
        case .redeemed: return Theme.Colors.textSecondary
        case .expired: return Theme.Colors.danger
        case .unknown: return Theme.Colors.textTertiary
        }
    }

    private func quotaColor(_ remaining: Double) -> Color {
        if remaining <= 15 { return Theme.Colors.danger }
        if remaining <= 35 { return Theme.Colors.warning }
        return Theme.Colors.success
    }

    private func resetText(_ date: Date?) -> String {
        guard let date else {
            return localizer.t("重置时间未知", en: "Reset time unknown", zhHant: "重置時間未知", ja: "リセット時刻不明", ko: "재설정 시간 알 수 없음", mt: "Reset time unknown")
        }
        let relative = relativeTimeText(for: date)
        let time = DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short)
        return localizer.t("重置 \(relative) · \(time)", en: "Resets \(relative) · \(time)", zhHant: "重置 \(relative) · \(time)", ja: "\(relative) にリセット · \(time)", ko: "\(relative) 재설정 · \(time)", mt: "Resets \(relative) · \(time)")
    }

    private func dateTimeText(_ date: Date) -> String {
        let relativeText = relativeTimeText(for: date)
        let absolute = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
        return "\(relativeText) · \(absolute)"
    }

    private func relativeRefreshText(_ date: Date) -> String {
        relativeTimeText(for: date)
    }

    private func relativeTimeText(for date: Date) -> String {
        let delta = Int(date.timeIntervalSince(Date()))
        if delta >= 0 {
            if delta < 60 {
                return localizer.t("不到 1 分钟后", en: "in <1 min", zhHant: "不到 1 分鐘後", ja: "1分以内", ko: "1분 이내", mt: "in <1 min")
            }
            if delta < 3600 {
                let minutes = max(1, delta / 60)
                return localizer.t("\(minutes) 分钟后", en: "in \(minutes) min.", zhHant: "\(minutes) 分鐘後", ja: "\(minutes)分後", ko: "\(minutes)분 후", mt: "in \(minutes) min.")
            }
            if delta < 86_400 {
                let hours = max(1, delta / 3600)
                return localizer.t("\(hours) 小时后", en: "in \(hours) hr.", zhHant: "\(hours) 小時後", ja: "\(hours)時間後", ko: "\(hours)시간 후", mt: "in \(hours) hr.")
            }
            let days = max(1, delta / 86_400)
            return localizer.t("\(days) 天后", en: "in \(days) days", zhHant: "\(days) 天後", ja: "\(days)日後", ko: "\(days)일 후", mt: "in \(days) days")
        }

        let elapsed = abs(delta)
        if elapsed < 60 {
            return localizer.t("刚刚", en: "just now", zhHant: "剛剛", ja: "たった今", ko: "방금", mt: "just now")
        }
        if elapsed < 3600 {
            let minutes = max(1, elapsed / 60)
            return localizer.t("\(minutes) 分钟前", en: "\(minutes) min. ago", zhHant: "\(minutes) 分鐘前", ja: "\(minutes)分前", ko: "\(minutes)분 전", mt: "\(minutes) min. ago")
        }
        if elapsed < 86_400 {
            let hours = max(1, elapsed / 3600)
            return localizer.t("\(hours) 小时前", en: "\(hours) hr. ago", zhHant: "\(hours) 小時前", ja: "\(hours)時間前", ko: "\(hours)시간 전", mt: "\(hours) hr. ago")
        }
        let days = max(1, elapsed / 86_400)
        return localizer.t("\(days) 天前", en: "\(days) days ago", zhHant: "\(days) 天前", ja: "\(days)日前", ko: "\(days)일 전", mt: "\(days) days ago")
    }

    private var hardwareOverview: some View {
        VStack(spacing: Theme.Spacing.md) {
            SectionHeader(title: localizer.hardwareMonitor, icon: "gauge.open.with.lines.needle.84percent")

            if let hw = service.hardwareInfo {
                let displayItems: [( icon: String, iconColor: Color, title: String, value: String, subtitle: String, valueColor: Color )] = {
                    var items: [( icon: String, iconColor: Color, title: String, value: String, subtitle: String, valueColor: Color )] = [
                        ("cpu", Theme.Colors.statusColor(for: hw.cpuUsage / 100.0), localizer.cpuLabel, String(format: "%.0f%%", hw.cpuUsage), "\(hw.cpuCoreCount) " + localizer.coresLabel, Theme.Colors.statusColor(for: hw.cpuUsage / 100.0)),
                        ("memorychip", Theme.Colors.statusColor(for: hw.memoryPressurePct / 100.0), localizer.memoryLabel, String(format: "%.0f%%", hw.memoryPressurePct), String(format: "%.1f/%.0fG", hw.memoryUsedGb, hw.memoryTotalGb), Theme.Colors.statusColor(for: hw.memoryPressurePct / 100.0)),
                    ]
                    if let temp = hw.cpuTemperature {
                        items.append(("thermometer.medium", Theme.Colors.statusColor(for: min(temp / 100.0, 1.0)), localizer.cpuTempLabel, String(format: "%.0f°C", temp), temp > 80 ? localizer.overheating : temp > 60 ? localizer.high : localizer.normal, Theme.Colors.statusColor(for: min(temp / 100.0, 1.0))))
                    }
                    if let battery = hw.batteryPercent {
                        items.append((hw.batteryCharging ? "battery.100.bolt" : "battery.75", Theme.Colors.statusColor(for: 1.0 - battery / 100.0), localizer.batteryLabel, String(format: "%.0f%%", battery), hw.batteryCharging ? localizer.charging : (hw.batteryTimeRemaining.map { "\($0)\(localizer.minuteUnit)" } ?? localizer.inUse), Theme.Colors.statusColor(for: 1.0 - battery / 100.0)))
                    }
                    items.append(("arrow.up.arrow.down", Theme.Colors.teal, localizer.networkLabel, "↓\(hw.networkInFormatted)", "↑\(hw.networkOutFormatted)", Theme.Colors.teal))
                    return items
                }()

                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.sm),
                    GridItem(.flexible(), spacing: Theme.Spacing.sm)
                ], spacing: Theme.Spacing.sm) {
                    ForEach(Array(displayItems.enumerated()), id: \.offset) { _, item in
                        VStack(spacing: Theme.Spacing.xs) {
                            Spacer(minLength: 0)
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: item.icon)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(item.iconColor)
                                Text(item.title)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            Text(item.value)
                                .font(Theme.Font.title2Bold)
                                .monospacedDigit()
                                .foregroundStyle(item.valueColor)
                            Text(item.subtitle)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76)
                        .cardStyle(padding: Theme.Spacing.sm)
                    }
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
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(String(format: "%.0f%%", disk.usedPct))
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(diskColor(pct: disk.usedPct))

                        Text(localizer.usedLabel)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Spacer()

                        Text(String(format: "%.0f GB / %.0f GB", disk.usedGb, disk.totalGb))
                            .font(Theme.Font.captionMedium)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    GeometryReader { proxy in
                        let progress = min(max(disk.usedPct / 100.0, 0), 1)
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Theme.Colors.separator.opacity(0.45))
                            Capsule()
                                .fill(diskColor(pct: disk.usedPct))
                                .frame(width: max(8, proxy.size.width * progress))
                        }
                    }
                    .frame(height: 10)
                    .accessibilityLabel(localizer.diskSpaceLabel)
                    .accessibilityValue(String(format: "%.0f%% %@", disk.usedPct, localizer.usedLabel))

                    HStack {
                        Text(localizer.available)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Spacer()

                        Text(String(format: "%.0f GB", disk.freeGb))
                            .font(Theme.Font.subheadlineMedium)
                            .monospacedDigit()
                            .foregroundStyle(disk.freeGb < 20 ? Theme.Colors.danger : Theme.Colors.success)
                    }
                }
                .cardStyle(padding: Theme.Spacing.md)

                if disk.usedPct > (100 - alertThreshold) {
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
                switchStateLabel(monitoringEnabled, color: Theme.Colors.warning)
                Toggle("", isOn: $monitoringEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.Colors.warning)
                    .onChange(of: monitoringEnabled) { newValue in
                        if newValue {
                            guard TraceFenceEntitlementPolicy.canUseProFeatures else {
                                monitoringEnabled = false
                                service.stopMonitoring()
                                saveSettings()
                                return
                            }
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

    private var agentGeoMirrorQuickSwitch: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(Theme.Font.caption)
                    .foregroundStyle(agentGeoMirrorEnabled ? Theme.Colors.success : Theme.Colors.info)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.t("Agent 环境画像", en: "Agent Environment Profile", zhHant: "Agent 環境畫像", ja: "Agent 環境プロファイル", ko: "Agent 환경 프로필", mt: "Agent Environment Profile"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(agentGeoMirrorEnabled
                        ? localizer.t("已启动。正在运行的 Agent 需重启才会生效。", en: "Running. Already-running agents must restart to take effect.", zhHant: "已啟動。正在執行的 Agent 需重啟才會生效。", ja: "実行中。起動済みの Agent は再起動が必要です。", ko: "실행 중입니다. 이미 실행 중인 Agent는 다시 시작해야 적용됩니다.", mt: "Running. Already-running agents must restart to take effect.")
                        : localizer.t("打开后自动生成本地 Profile。", en: "Turn on to generate the local profile automatically.", zhHant: "開啟後會自動產生本機 Profile。", ja: "オンにするとローカルプロファイルを自動生成します。", ko: "켜면 로컬 프로필을 자동 생성합니다.", mt: "Turn on to generate the local profile automatically."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                switchStateLabel(agentGeoMirrorEnabled, color: Theme.Colors.success)
                Toggle("", isOn: Binding(
                    get: { agentGeoMirrorEnabled },
                    set: { setAgentGeoMirrorEnabled($0) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .tint(Theme.Colors.success)
                .disabled(agentGeoMirrorBusy)
            }

            if agentGeoMirrorBusy || agentGeoMirrorMessage != nil {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: agentGeoMirrorBusy ? "arrow.clockwise" : "checkmark.circle.fill")
                        .font(Theme.Font.caption)
                        .foregroundStyle(agentGeoMirrorBusy ? Theme.Colors.info : Theme.Colors.success)
                    Text(agentGeoMirrorBusy
                        ? localizer.t("正在处理...", en: "Working...", zhHant: "正在處理...", ja: "処理中...", ko: "처리 중...", mt: "Working...")
                        : (agentGeoMirrorMessage ?? ""))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.top, 2)
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
                switchStateLabel(operationMonitorEnabled, color: Theme.Colors.purple)
                Toggle("", isOn: $operationMonitorEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.Colors.purple)
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
                switchStateLabel(trashInsteadOfDelete, color: Theme.Colors.info)
                Toggle("", isOn: $trashInsteadOfDelete)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.Colors.info)
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
                switchStateLabel(preventAutoEmptyTrash, color: Theme.Colors.danger)
                Toggle("", isOn: $preventAutoEmptyTrash)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(Theme.Colors.danger)
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

    private func switchStateLabel(_ isOn: Bool, color: Color) -> some View {
        Text(isOn
            ? localizer.t("已开启", en: "On", zhHant: "已開啟", ja: "オン", ko: "켜짐", mt: "On")
            : localizer.t("已关闭", en: "Off", zhHant: "已關閉", ja: "オフ", ko: "꺼짐", mt: "Off"))
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(isOn ? color : Theme.Colors.textSecondary)
            .frame(minWidth: 54)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isOn ? color.opacity(0.16) : Theme.Colors.surface)
            .overlay {
                Capsule()
                    .stroke(isOn ? color.opacity(0.35) : Theme.Colors.separator, lineWidth: 1)
            }
            .clipShape(Capsule())
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
                    value: "\(displayableOperationRecords.count)"
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
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(localizer.recentOpsLabel)
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()

                if !displayableOperationRecords.isEmpty {
                    Button {
                        openMainConsole()
                    } label: {
                        HStack(spacing: 2) {
                            Text("\(displayableOperationRecords.count) \(localizer.recordsUnit)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Image(systemName: "arrow.up.right.and.arrow.down.left")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Colors.accent)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if displayableOperationRecords.isEmpty {
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
                    if operationMonitorEnabled, !TraceFenceEntitlementPolicy.canUseProFeatures {
                        operationMonitorEnabled = false
                        service.stopOperationMonitor()
                        saveSettings()
                        return
                    }
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
                    .foregroundStyle(.primary)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(operationMonitorEnabled ? Theme.Colors.warning.opacity(0.85) : Theme.Colors.success.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
                .buttonStyle(.plain)

                Spacer()

                if !displayableOperationRecords.isEmpty {
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

        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    // MARK: - Computed Properties

    private var todayOperationCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return displayableOperationRecords.filter { $0.timestamp >= start }.count
    }

    private var hourOperationCount: Int {
        displayableOperationRecords.filter { Date().timeIntervalSince($0.timestamp) < 3600 }.count
    }

    private struct AgentStat: Identifiable {
        let name: String
        let count: Int
        let index: Int
        var id: String { name }
    }

    private var agentStats: [AgentStat] {
        var counts: [String: Int] = [:]
        for record in displayableOperationRecords {
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
        for record in displayableOperationRecords {
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
        Array(displayableOperationRecords.prefix(5))
    }

    private var topAgentStats: [AgentStat] {
        let stats = agentStats
        return Array(stats.prefix(min(5, stats.count)))
    }

    private var displayableOperationRecords: [OperationRecord] {
        service.operationRecords.filter { record in
            let name = record.agentName.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty || name == "—" || name == "Unattributed Agent" { return false }
            if name == localizer.systemProcess || name.localizedCaseInsensitiveContains("system process") { return false }
            let nonAgentToolNames: Set<String> = [
                "Node.js", "Python", "npm", "npx", "Yarn", "pnpm", "Cargo", "Rust",
                "Deno", "Bun", "Go", "Swift", "Java", "Gradle", "Maven", "Make",
                "CMake", "Xcode", "Git", "Docker", "pip", "pip3", "Clang",
                "rsync", "cp", "mv", "rm", "zip", "tar", "mkdir"
            ]
            return !nonAgentToolNames.contains(name)
        }
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
        case .execute: .purple
        }
    }

    private func agentStatColor(index: Int) -> Color {
        let colors: [Color] = [.blue, .purple, .green, .orange, .cyan, .pink, .indigo, .teal]
        return colors[index % colors.count]
    }

    private func startDeferredMonitorForSelectedTab() {
        deferredMonitorWorkItem?.cancel()
        deferredMonitorGeneration &+= 1
        let ticket = MenuBarDeferredSelectionTicket(
            selection: selectedTab,
            generation: deferredMonitorGeneration
        )
        let workItem = DispatchWorkItem {
            guard ticket.isCurrent(
                selection: selectedTab,
                generation: deferredMonitorGeneration
            ) else { return }

            switch ticket.selection {
            case .overview:
                guard monitoringEnabled else { return }
                service.startMonitoring()
            case .operations:
                guard operationMonitorEnabled else { return }
                service.startOperationMonitor()
            case .quotas:
                usageInsightsService.startScheduling()
            case .capture:
                captureService.start()
            case .plugins:
                break
            }
        }
        deferredMonitorWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func cancelDeferredMonitorStart() {
        deferredMonitorWorkItem?.cancel()
        deferredMonitorWorkItem = nil
        deferredMonitorGeneration &+= 1
    }

#if DEBUG
    static func debugTabSelectionSelfTestFailures() -> [String] {
        var failures: [String] = []
        let quotaTicket = MenuBarDeferredSelectionTicket(selection: MonitorTab.quotas, generation: 1)
        let captureTicket = MenuBarDeferredSelectionTicket(selection: MonitorTab.capture, generation: 2)

        if quotaTicket.isCurrent(selection: .capture, generation: 2) {
            failures.append("stale quota action survived a capture-tab selection")
        }
        if !captureTicket.isCurrent(selection: .capture, generation: 2) {
            failures.append("current capture action was rejected")
        }
        if captureTicket.isCurrent(selection: .capture, generation: 3) {
            failures.append("cancelled capture action survived a generation change")
        }
        return failures
    }
#endif

    private func settingsPath() -> String {
        SandboxPaths.shared.monitorPath
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

    private func setAgentGeoMirrorEnabled(_ isEnabled: Bool) {
        guard SandboxPaths.isDirectDistribution else { return }
        agentGeoMirrorEnabled = isEnabled
        agentGeoMirrorBusy = true
        agentGeoMirrorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                _ = try AgentGeoMirrorService.shared.setEnabledFromDefaults(isEnabled)
                DispatchQueue.main.async {
                    agentGeoMirrorBusy = false
                    agentGeoMirrorMessage = isEnabled
                        ? localizer.t("已启动。请重启正在运行的 Agent/CLI，否则不会读取新画像。", en: "Started. Restart running agents or CLIs, otherwise they will not read the new profile.", zhHant: "已啟動。請重啟正在執行的 Agent/CLI，否則不會讀取新畫像。", ja: "開始しました。実行中の Agent/CLI を再起動しないと新しいプロファイルは読み込まれません。", ko: "시작되었습니다. 실행 중인 Agent/CLI를 다시 시작해야 새 프로필을 읽습니다.", mt: "Started. Restart running agents or CLIs, otherwise they will not read the new profile.")
                        : localizer.t("已停止。后续启动不会注入画像。", en: "Stopped. Future launches will not inject the profile.", zhHant: "已停止。後續啟動不會注入畫像。", ja: "停止しました。以後の起動ではプロファイルを注入しません。", ko: "중지되었습니다. 이후 실행에는 프로필을 주입하지 않습니다.", mt: "Stopped. Future launches will not inject the profile.")
                }
            } catch {
                DispatchQueue.main.async {
                    agentGeoMirrorEnabled = !isEnabled
                    agentGeoMirrorBusy = false
                    agentGeoMirrorMessage = error.localizedDescription
                }
            }
        }
    }
}
