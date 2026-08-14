import SwiftUI
import AppKit
import SQLite3
import CoreImage.CIFilterBuiltins

struct ContentView: View {
    @State private var selectedTab: NavItem = .overview
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var licenseService: DirectLicenseService
    @EnvironmentObject var marketplaceCatalogService: TraceFenceMarketplaceCatalogService
    @EnvironmentObject var pluginEntitlementService: TraceFencePluginEntitlementService
    @StateObject private var pluginPackageManager = TraceFencePluginPackageManager.shared
    @StateObject private var pluginRuntimeHost = TraceFencePluginRuntimeHost.shared
    @StateObject private var pluginPresentationCenter = TraceFencePluginPresentationCenter.shared
    @StateObject private var iOSRemoteGatewayService = IOSRemoteControlGatewayService.shared
    @ObservedObject var overviewStore: AgentMonitorOverviewStore
    @State private var showSettings = false
    @State private var settingsInitialTab: SettingsView.SettingsTab = .features
    @State private var showIOSRemotePairing = false
    @State private var selectedPluginID: String?
    @State private var sidebarCollapsed = false
    @State private var toolboxExpanded = false
    @State private var hoveredItem: NavItem?
    @AppStorage("networkMode") private var networkMode = "internet"
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("colorPalette") private var colorPalette = AppColorPalette.porcelain.rawValue
    @AppStorage(IOSRemoteControlGatewayService.enabledKey) private var iOSRemoteGatewayEnabled = false
    @AppStorage(IOSRemoteControlGatewayService.portKey) private var iOSRemoteGatewayPort = 17895

    private enum AppearanceMode: String, CaseIterable {
        case system
        case light
        case dark

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }

        var icon: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max"
            case .dark: "moon"
            }
        }
    }

    private var isToolboxSubItemSelected: Bool {
        Self.toolboxSubItems.contains(selectedTab)
    }

    private static var toolboxSubItems: [NavItem] {
        var items: [NavItem] = [.tokenScope, .diskAdvisor, .agentProfile, .localDiagnostics]
        items.append(contentsOf: [.cleaner, .app, .dependency, .other, .migration])
        return items
    }

    enum NavItem: String, CaseIterable {
        case overview = "overview"
        case agentGuard = "agentGuard"
        case operations = "operations"
        case plugins = "plugins"
        case toolbox = "toolbox"
        case tokenScope = "tokenScope"
        case diskAdvisor = "diskAdvisor"
        case agentProfile = "agentProfile"
        case localDiagnostics = "localDiagnostics"
        case cleaner = "cleaner"
        case app = "app"
        case dependency = "dependency"
        case other = "other"
        case migration = "migration"

        var isSubItem: Bool {
            switch self {
            case .tokenScope, .diskAdvisor, .agentProfile, .localDiagnostics, .cleaner, .app, .dependency, .other, .migration: return true
            default: return false
            }
        }

        var pluginID: String? {
            switch self {
            case .overview:
                return "tracefence.agent-monitor"
            case .agentGuard, .operations:
                return "tracefence.agent-guard"
            case .tokenScope:
                return "tracefence.token-usage"
            case .diskAdvisor:
                return "tracefence.disk-advisor"
            default:
                return nil
            }
        }

        var icon: String {
            switch self {
            case .cleaner: "arrow.down.doc.fill"
            case .app: "app.badge"
            case .dependency: "cube.box"
            case .other: "terminal"
            case .overview: "chart.bar.xaxis"
            case .operations: "eye.fill"
            case .plugins: "puzzlepiece.extension.fill"
            case .agentGuard: "shield.fill"
            case .toolbox: "wrench.and.screwdriver.fill"
            case .tokenScope: "chart.xyaxis.line"
            case .diskAdvisor: "sparkles"
            case .agentProfile: "globe.badge.chevron.backward"
            case .localDiagnostics: "network"
            case .migration: "arrow.triangle.2.circlepath"
            }
        }

        var color: Color {
            switch self {
            case .cleaner: Theme.Colors.info
            case .app: Theme.Colors.accent
            case .dependency: Theme.Colors.warning
            case .other: Theme.Colors.textSecondary
            case .overview: Theme.Colors.info
            case .operations: Theme.Colors.accent
            case .plugins: Theme.Colors.purple
            case .agentGuard: Theme.Colors.accent
            case .toolbox: Theme.Colors.info
            case .tokenScope: Theme.Colors.accent
            case .diskAdvisor: Theme.Colors.purple
            case .agentProfile: Theme.Colors.info
            case .localDiagnostics: Theme.Colors.teal
            case .migration: Theme.Colors.purple
            }
        }

        func label(_ localizer: Localizer) -> String {
            switch self {
            case .cleaner: localizer.navCleaner
            case .app: localizer.navApp
            case .dependency: localizer.navDependency
            case .other: localizer.navOther
            case .overview: localizer.navOverview
            case .operations: localizer.navOperations
            case .plugins: localizer.t("我的插件", en: "My Plugins", zhHant: "我的外掛", ja: "マイプラグイン", ko: "내 플러그인", mt: "My Plugins")
            case .agentGuard: localizer.navAgentGuard
            case .toolbox: localizer.navToolbox
            case .tokenScope: localizer.tokenScopeTitle
            case .diskAdvisor: localizer.t("AI 磁盘顾问", en: "AI Disk Advisor", zhHant: "AI 磁碟顧問", ja: "AI ディスクアドバイザー", ko: "AI 디스크 어드바이저", mt: "AI Disk Advisor")
            case .agentProfile: localizer.t("Agent 画像", en: "Agent Profile", zhHant: "Agent 畫像", ja: "Agent プロファイル", ko: "Agent 프로필", mt: "Agent Profile")
            case .localDiagnostics: localizer.t("本机诊断", en: "Local Diagnostics", zhHant: "本機診斷", ja: "ローカル診断", ko: "로컬 진단", mt: "Local Diagnostics")
            case .migration: localizer.navMigration
            }
        }

        func subtitle(_ localizer: Localizer) -> String {
            switch self {
            case .cleaner: localizer.subCleaner
            case .app: localizer.subApp
            case .dependency: localizer.subDependency
            case .other: localizer.subOther
            case .overview: localizer.subOverview
            case .operations: localizer.subOperations
            case .plugins: localizer.t("运行已安装插件与管理快捷入口", en: "Run installed plugins and manage quick access", zhHant: "執行已安裝外掛與管理快速入口", ja: "インストール済みプラグインを実行", ko: "설치된 플러그인 실행 및 빠른 접근 관리", mt: "Run installed plugins and manage quick access")
            case .agentGuard: localizer.subAgentGuard
            case .toolbox: localizer.subToolbox
            case .tokenScope: localizer.tokenScopeSubtitle
            case .diskAdvisor: localizer.t("Apple Intelligence 磁盘清理建议", en: "Apple Intelligence cleanup advice", zhHant: "Apple Intelligence 磁碟清理建議", ja: "Apple Intelligence のクリーンアップ提案", ko: "Apple Intelligence 정리 제안", mt: "Apple Intelligence cleanup advice")
            case .agentProfile: localizer.t("给 Agent 注入语言、时区与本地探测画像", en: "Inject language, timezone, and local probe profiles for agents", zhHant: "為 Agent 注入語言、時區與本機探測畫像", ja: "Agent に言語、タイムゾーン、ローカル診断プロファイルを注入", ko: "Agent에 언어, 시간대 및 로컬 탐지 프로필 주입", mt: "Inject language, timezone, and local probe profiles for agents")
            case .localDiagnostics: localizer.t("出口网络与启动项只读巡检", en: "Egress and launch item audit", zhHant: "出口網路與啟動項唯讀巡檢", ja: "出口ネットワークと起動項目監査", ko: "송신 네트워크 및 시작 항목 점검", mt: "Egress and launch item audit")
            case .migration: localizer.subMigration
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            detailContent
                .appCanvas()
        }
        .frame(minWidth: 960, minHeight: 640)
        .background(.clear)
        .id(colorPalette)
        .onAppear {
            licenseService.refreshTrialState()
            service.refreshDiskInfo()
            service.refreshHardwareInfo()
            iOSRemoteGatewayService.configure(scannerService: service)
#if DEBUG
            openPluginWorkspaceForUITestIfRequested()
#endif
            if TraceFenceDistributionPolicy.currentChannel.isDirect
                || AppStoreSubscriptionService.shared.canUseProFeatures {
                overviewStore.startBackgroundRefresh()
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(initialTab: settingsInitialTab)
                .id(settingsInitialTab)
                .environmentObject(service)
                .environmentObject(localizer)
                .environmentObject(licenseService)
        }
        .sheet(isPresented: $showIOSRemotePairing) {
            TraceFenceIOSPairingSheet(
                gatewayService: iOSRemoteGatewayService,
                isEnabled: $iOSRemoteGatewayEnabled,
                port: $iOSRemoteGatewayPort
            )
            .environmentObject(localizer)
        }
        .onReceive(pluginPresentationCenter.$request.compactMap { $0 }) { request in
            selectedPluginID = request.pluginID
            selectedTab = .plugins
            showSettings = false
            pluginPresentationCenter.consume(requestID: request.id)
        }
        .preferredColorScheme(currentAppearanceMode.colorScheme)
    }

    private var currentAppearanceMode: AppearanceMode {
        AppearanceMode(rawValue: appearanceMode) ?? .system
    }

#if DEBUG
    private func openPluginWorkspaceForUITestIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--tracefence-open-plugin-workspace") else { return }
        let pluginID = arguments.indices.contains(flagIndex + 1) ? arguments[flagIndex + 1] : nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            if let pluginID, pluginID.hasPrefix("tracefence.") {
                pluginPresentationCenter.open(pluginID: pluginID)
            } else {
                pluginPresentationCenter.openPluginWorkspace()
            }
        }
    }
#endif

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarLogo

            Rectangle()
                .fill(Theme.Colors.separator.opacity(0.5))
                .frame(height: 0.5)
                .padding(.horizontal, Theme.Spacing.md)

            ScrollView {
                sidebarNavItems
                    .frame(maxWidth: .infinity, alignment: sidebarCollapsed ? .center : .leading)
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity)
            .frame(maxHeight: .infinity, alignment: .top)

            Rectangle()
                .fill(Theme.Colors.separator.opacity(0.5))
                .frame(height: 0.5)
                .padding(.horizontal, Theme.Spacing.md)

            sidebarFooter
        }
        .frame(width: sidebarCollapsed ? Theme.Sidebar.collapsedWidth : Theme.Sidebar.expandedWidth)
        .background(
            ZStack {
                Theme.Gradients.sidebar
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.16))
                    .frame(width: 170, height: 170)
                    .blur(radius: 42)
                    .offset(x: -72, y: -260)
                Rectangle()
                    .fill(Theme.Colors.sidebarBg.opacity(0.82))
            }
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: 1)
        }
    }

    private var sidebarLogo: some View {
        HStack(spacing: 0) {
            if !sidebarCollapsed {
                HStack(spacing: Theme.Spacing.sm + 2) {
                    AgentGuardMark(size: 46)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizer.appName)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Theme.Colors.success)
                                .frame(width: 7, height: 7)
                                .shadow(color: Theme.Colors.success.opacity(0.65), radius: 5)
                            Text(localizer.monitoringLive)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(Theme.Colors.success)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                AgentGuardMark(size: Theme.Sidebar.iconSize + 12)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.md)
        .padding(.horizontal, sidebarCollapsed ? Theme.Spacing.xs : Theme.Spacing.md)
    }

    private var sidebarNavItems: some View {
        VStack(alignment: sidebarCollapsed ? .center : .leading, spacing: Theme.Spacing.xs) {
            if !sidebarCollapsed {
                Text(localizer.workspaceSection)
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xs)
            } else {
                Text("AI")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xs)
            }

            ForEach(NavItem.allCases.filter { !$0.isSubItem }, id: \.self) { item in
                if item == .toolbox && !sidebarCollapsed {
                    toolboxSection
                } else if item != .toolbox || sidebarCollapsed {
                    Button {
                        if item == .toolbox {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                toolboxExpanded.toggle()
                            }
                            selectedTab = .tokenScope
                        } else {
                            selectedTab = item
                        }
                    } label: {
                        Group {
                            if sidebarCollapsed {
                                sidebarCollapsedItem(item)
                            } else {
                                sidebarExpandedItem(item)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in
                        hoveredItem = hovering ? item : nil
                    }
                }
            }
        }
        .padding(.horizontal, sidebarCollapsed ? Theme.Spacing.xs : Theme.Spacing.md)
    }

    private var toolboxSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    toolboxExpanded.toggle()
                }
            } label: {
                HStack(spacing: Theme.Spacing.sm + 2) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.clear)
                        .frame(width: 3, height: Theme.Sidebar.itemHeight * 0.5)

                    Image(systemName: NavItem.toolbox.icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(hoveredItem == .toolbox ? Theme.Colors.accent : Theme.Colors.textSecondary)
                        .frame(width: 36, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Theme.Colors.textPrimary.opacity(0.045))
                        )

                    Text(NavItem.toolbox.label(localizer))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(hoveredItem == .toolbox ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)

                    Spacer()

                    Image(systemName: toolboxExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .frame(minHeight: Theme.Sidebar.itemHeight)
                .padding(.horizontal, Theme.Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Sidebar.itemRadius)
                        .fill(hoveredItem == .toolbox ? Theme.Colors.cardHover : Color.clear)
                )
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                hoveredItem = hovering ? .toolbox : nil
            }

            if toolboxExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.toolboxSubItems, id: \.self) { item in
                        Button {
                            selectedTab = item
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(selectedTab == item ? Color.white : Theme.Colors.textTertiary)
                                    .frame(width: 26, height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 9)
                                            .fill(selectedTab == item ? AnyShapeStyle(Theme.Gradients.hero) : AnyShapeStyle(Theme.Colors.textPrimary.opacity(0.035)))
                                    )

                                Text(item.label(localizer))
                                    .font(.system(size: 12))
                                    .fontWeight(selectedTab == item ? .bold : .semibold)
                                    .foregroundStyle(selectedTab == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)

                                Spacer()

                                if isDirectPluginLocked(item) {
                                    Image(systemName: "lock.fill")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(Theme.Colors.warning)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md + Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.xs + 2)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.md)
                                    .fill(selectedTab == item ? Theme.Colors.elevatedCardBg.opacity(0.82) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoveredItem = hovering ? item : nil
                        }
                    }
                }
                .padding(.top, Theme.Spacing.xs)
            }
        }
    }

    private func sidebarExpandedItem(_ item: NavItem) -> some View {
        HStack(spacing: Theme.Spacing.sm + 2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(selectedTab == item ? Theme.Gradients.hero : LinearGradient(colors: [.clear], startPoint: .top, endPoint: .bottom))
                .frame(width: 3, height: Theme.Sidebar.itemHeight * 0.52)

            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selectedTab == item ? Color.white : (hoveredItem == item ? Theme.Colors.accent : Theme.Colors.textSecondary))
                .frame(width: 36, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedTab == item ? AnyShapeStyle(Theme.Gradients.hero) : AnyShapeStyle(Theme.Colors.textPrimary.opacity(0.045)))
                )
                .shadow(color: selectedTab == item ? Theme.Colors.accent.opacity(0.20) : .clear, radius: 10, y: 5)

            Text(item.label(localizer))
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selectedTab == item ? Theme.Colors.textPrimary : (hoveredItem == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary))
                .lineLimit(1)

            Spacer()

            if isDirectPluginLocked(item) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Theme.Colors.warning)
            }

            if selectedTab == item {
                Text(navMeta(for: item))
                    .font(.system(size: 10, weight: .black))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(minHeight: Theme.Sidebar.itemHeight)
        .padding(.horizontal, Theme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Theme.Sidebar.itemRadius)
                .fill(selectedTab == item ? Theme.Colors.elevatedCardBg : (hoveredItem == item ? Theme.Colors.cardHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Sidebar.itemRadius)
                .stroke(selectedTab == item ? Theme.Colors.separator : Color.clear, lineWidth: 1)
        )
        .shadow(color: selectedTab == item ? Theme.Shadow.mdColor : .clear, radius: 12, y: 6)
    }

    private func navMeta(for item: NavItem) -> String {
        switch item {
        case .overview: return localizer.t("实时", en: "Live", zhHant: "即時", ja: "ライブ", ko: "실시간", mt: "Live")
        case .agentGuard: return service.guardFeature.unreadAlertCount > 0 ? "\(service.guardFeature.unreadAlertCount)" : localizer.t("守护", en: "Guard", zhHant: "守護", ja: "保護", ko: "보호", mt: "Guard")
        case .operations: return service.operationRecords.isEmpty ? localizer.t("审计", en: "Audit", zhHant: "稽核", ja: "監査", ko: "감사", mt: "Audit") : "\(service.operationRecords.count)"
        case .plugins:
            let installedCount = pluginPackageManager.records.count
            return installedCount > 0 ? "\(installedCount)" : localizer.t("应用", en: "Apps", zhHant: "應用", ja: "アプリ", ko: "앱", mt: "Apps")
        case .toolbox: return localizer.t("工具", en: "Tools", zhHant: "工具", ja: "ツール", ko: "도구", mt: "Tools")
        case .tokenScope: return localizer.t("测试", en: "Beta", zhHant: "測試", ja: "ベータ", ko: "베타", mt: "Beta")
        case .diskAdvisor: return localizer.t("实验", en: "Lab", zhHant: "實驗", ja: "ラボ", ko: "실험", mt: "Lab")
        case .agentProfile: return localizer.t("画像", en: "Profile", zhHant: "畫像", ja: "Profile", ko: "Profile", mt: "Profile")
        case .localDiagnostics: return localizer.t("诊断", en: "Diag", zhHant: "診斷", ja: "診断", ko: "진단", mt: "Diag")
        case .cleaner:
            let rawTotal = service.scanItems.reduce(Int64(0)) { $0 + $1.size }
            let total = service.diskInfo.map { min(rawTotal, $0.used) } ?? rawTotal
            return total > 0 ? service.formatSize(total) : localizer.t("清理", en: "Clean", zhHant: "清理", ja: "クリーン", ko: "정리", mt: "Clean")
        case .app: return service.installedApps.isEmpty ? localizer.t("应用", en: "Apps", zhHant: "應用", ja: "アプリ", ko: "앱", mt: "Apps") : "\(service.installedApps.count)"
        case .dependency: return localizer.t("依赖", en: "Deps", zhHant: "依賴", ja: "依存", ko: "의존성", mt: "Deps")
        case .other: return "CLI"
        case .migration: return localizer.t("适配", en: "Intel", zhHant: "適配", ja: "Intel", ko: "Intel", mt: "Intel")
        }
    }

    private func sidebarCollapsedItem(_ item: NavItem) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(selectedTab == item ? Color.white : (hoveredItem == item ? Theme.Colors.accent : Theme.Colors.textSecondary))
                .frame(width: 34, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(selectedTab == item ? AnyShapeStyle(Theme.Gradients.hero) : AnyShapeStyle(Theme.Colors.textPrimary.opacity(0.045)))
                )
                .overlay(alignment: .topTrailing) {
                    if isDirectPluginLocked(item) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 7, weight: .black))
                            .foregroundStyle(Theme.Colors.warning)
                            .padding(2)
                            .background(Theme.Colors.elevatedCardBg, in: Circle())
                    }
                }
            Text(item.label(localizer).split(separator: " ").first.map(String.init) ?? "")
                .font(.system(size: 8, weight: selectedTab == item ? .semibold : .regular))
                .foregroundStyle(selectedTab == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, Theme.Spacing.sm - 2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(selectedTab == item ? Theme.Colors.elevatedCardBg : (hoveredItem == item ? Theme.Colors.cardHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(selectedTab == item ? Theme.Colors.separator : Color.clear, lineWidth: 1)
        )
    }

    private var sidebarFooter: some View {
        Group {
            if sidebarCollapsed {
                VStack(spacing: 8) {
                    footerIconButton(icon: "sidebar.right", color: Theme.Colors.textSecondary, help: localizer.expandSidebar) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            sidebarCollapsed = false
                        }
                    }

                    footerIconButton(icon: iosRemoteFooterIcon, color: iosRemoteFooterColor, help: iosRemoteFooterHelp) {
                        openIOSRemotePairing()
                    }

                    if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                        footerIconButton(
                            icon: "creditcard.fill",
                            color: Theme.Colors.accent,
                            help: localizer.t("订阅 TraceFence Standard", en: "Subscribe to TraceFence Standard")
                        ) {
                            openSettings(.license)
                        }
                    }

                    footerIconButton(icon: "gearshape", color: Theme.Colors.textSecondary, help: localizer.settings) {
                        openSettings()
                    }

                    appearanceModeButton
                    languageToggleButton

                    footerStatusDot
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 8)
                .background(footerPanelBackground(cornerRadius: 12))
                .padding(.vertical, Theme.Spacing.lg)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(networkMode == "internet" ? Theme.Colors.success : Theme.Colors.warning)
                            .frame(width: 8, height: 8)
                            .shadow(color: (networkMode == "internet" ? Theme.Colors.success : Theme.Colors.warning).opacity(0.55), radius: 5)
                            .padding(.top, 4)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(localizer.protectionOn)
                                .font(.system(size: 12, weight: .black))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            HStack(spacing: 6) {
                                Text("\(networkMode == "internet" ? localizer.internetStatus : localizer.offlineStatus) · v\(service.currentVersion)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.78)
                                Spacer(minLength: 2)
                                footerLabeledButton(icon: iosRemoteFooterIcon, title: iosRemoteFooterTitle, color: iosRemoteFooterColor) {
                                    openIOSRemotePairing()
                                }
                                .frame(width: 98)
                            }
                        }
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                        appearanceModeButton
                        languageToggleButton
                    }

                    if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                        footerLabeledButton(
                            icon: "creditcard.fill",
                            title: localizer.t("订阅 Standard", en: "Subscribe Standard"),
                            color: Theme.Colors.accent
                        ) {
                            openSettings(.license)
                        }
                    }

                    HStack(spacing: 6) {
                        footerLabeledButton(icon: "gearshape", title: localizer.settings, color: Theme.Colors.textSecondary) {
                            openSettings()
                        }
                        footerLabeledButton(icon: "sidebar.left", title: localizer.collapseSidebar, color: Theme.Colors.textTertiary) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                sidebarCollapsed = true
                            }
                        }
                    }
                }
                .padding(10)
                .background(footerPanelBackground(cornerRadius: 14))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
    }

    private var iosRemoteFooterIcon: String {
        iOSRemoteGatewayService.isRunning ? "iphone.radiowaves.left.and.right" : "iphone.slash"
    }

    private func openSettings(_ tab: SettingsView.SettingsTab? = nil) {
        settingsInitialTab = tab
            ?? (TraceFenceDistributionPolicy.currentChannel.isAppStore ? .license : .features)
        showSettings = true
    }

    private func openIOSRemotePairing() {
        if TraceFenceDistributionPolicy.currentChannel.isDirect,
           !TraceFenceEntitlementPolicy.canUsePlugin("tracefence.ios-remote") {
            openSettings(.marketplace)
        } else {
            showIOSRemotePairing = true
        }
    }

    private func isDirectPluginLocked(_ item: NavItem) -> Bool {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect,
              let pluginID = item.pluginID else {
            return false
        }
        guard marketplaceCatalogService.catalog.plugin(id: pluginID) != nil else {
            return true
        }
        return !TraceFenceEntitlementPolicy.canUsePlugin(pluginID)
    }

    private var iosRemoteFooterColor: Color {
        iOSRemoteGatewayService.isRunning ? Theme.Colors.success : Theme.Colors.textTertiary
    }

    private var iosRemoteFooterTitle: String {
        iOSRemoteGatewayService.isRunning
            ? localizer.t("已连接", en: "Connected", zhHant: "已連接", ja: "接続済み", ko: "연결됨", mt: "Connected")
            : localizer.t("未连接", en: "Disconnected", zhHant: "未連接", ja: "未接続", ko: "연결 안 됨", mt: "Disconnected")
    }

    private var iosRemoteFooterHelp: String {
        localizer.t("iOS 远程配对", en: "iOS Remote Pairing", zhHant: "iOS 遠端配對", ja: "iOS リモートペアリング", ko: "iOS 원격 페어링", mt: "iOS Remote Pairing")
    }

    private func footerPanelBackground(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Theme.Colors.elevatedCardBg.opacity(0.76))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.86),
                                Theme.Colors.accent.opacity(0.22),
                                Theme.Colors.separator
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: Theme.Shadow.mdColor, radius: 12, x: 0, y: 6)
    }

    private func footerIconButton(icon: String, color: Color, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: sidebarCollapsed ? 12 : 11, weight: .semibold))
        }
        .buttonStyle(.plain)
        .modifier(HUDIconChrome(color: color, disabled: false, size: sidebarCollapsed ? 30 : 28, radius: 8))
        .help(help)
    }

    private func footerLabeledButton(icon: String, title: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            footerGlassControl(icon: icon, title: title, color: color)
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private var footerStatusDot: some View {
        VStack(spacing: 5) {
            Circle()
                .fill(networkMode == "internet" ? Theme.Colors.info : Theme.Colors.warning)
                .frame(width: 5, height: 5)
                .shadow(color: (networkMode == "internet" ? Theme.Colors.info : Theme.Colors.warning).opacity(0.55), radius: 4, x: 0, y: 0)
            Text("v")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(width: 30, height: 30)
        .help("\(networkMode == "internet" ? localizer.internetStatus : localizer.offlineStatus) · v\(service.currentVersion)")
    }

    private var appearanceModeButton: some View {
        Menu {
            ForEach(AppearanceMode.allCases, id: \.self) { mode in
                Button {
                    appearanceMode = mode.rawValue
                } label: {
                    Label(appearanceModeTitle(mode), systemImage: mode.icon)
                }
            }
        } label: {
            footerGlassControl(
                icon: currentAppearanceMode.icon,
                title: sidebarCollapsed ? "" : appearanceModeTitle(currentAppearanceMode),
                color: Theme.Colors.accent
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help(appearanceModeTitle(currentAppearanceMode))
    }

    private func appearanceModeTitle(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system:
            return localizer.t("跟随系统", en: "System", zhHant: "跟隨系統", ja: "システム", ko: "시스템", mt: "System")
        case .light:
            return localizer.t("浅色主题", en: "Light", zhHant: "淺色主題", ja: "ライト", ko: "라이트", mt: "Light")
        case .dark:
            return localizer.t("深色主题", en: "Dark", zhHant: "深色主題", ja: "ダーク", ko: "다크", mt: "Dark")
        }
    }

    private var languageToggleButton: some View {
        Menu {
            ForEach(AppLanguage.allCases, id: \.self) { lang in
                Button {
                    localizer.language = lang
                } label: {
                    Text(lang.nativeName)
                }
            }
        } label: {
            footerGlassControl(
                icon: "globe.asia.australia",
                title: sidebarCollapsed ? "" : localizer.language.nativeName,
                color: Theme.Colors.info
            )
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help(localizer.languageLabel)
    }

    private func footerGlassControl(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: sidebarCollapsed ? 12 : 11, weight: .semibold))
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
        }
        .foregroundStyle(color)
        .frame(width: sidebarCollapsed ? 30 : nil, height: 30)
        .frame(maxWidth: sidebarCollapsed ? nil : .infinity)
        .padding(.horizontal, sidebarCollapsed ? 0 : 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    LinearGradient(
                        colors: [color.opacity(0.62), color.opacity(0.16)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: color.opacity(0.12), radius: 6, x: 0, y: 0)
    }

    private var networkStatusBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: networkMode == "internet" ? "globe" : "lock.circle")
                .font(.system(size: 9))
                .foregroundStyle(networkMode == "internet" ? Theme.Colors.info : Theme.Colors.warning)
            if !sidebarCollapsed {
                Text(networkMode == "internet" ? localizer.internetStatus : localizer.offlineStatus)
                    .font(.system(size: 9))
                    .foregroundStyle(networkMode == "internet" ? Theme.Colors.info : Theme.Colors.warning)
            }
        }
        .padding(.horizontal, sidebarCollapsed ? 0 : Theme.Spacing.xs + 1)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill((networkMode == "internet" ? Theme.Colors.info : Theme.Colors.warning).opacity(sidebarCollapsed ? 0 : 0.08))
        )
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .overview:
            AppOverviewTab(overviewStore: overviewStore)
                .environmentObject(localizer)
        case .cleaner:
            MacCleanerTab()
                .environmentObject(localizer)
        case .app:
            AppManagerTab(filterType: .app)
                .environmentObject(localizer)
        case .dependency:
            AppManagerTab(filterType: .dependency)
                .environmentObject(localizer)
        case .other:
            AppManagerTab(filterType: .other)
                .environmentObject(localizer)
        case .operations:
            pluginContent("tracefence.agent-guard") {
                OperationLogTab(monitor: service.operationMonitor)
                    .environmentObject(localizer)
            }
        case .plugins:
            TraceFencePluginWorkspaceView(
                catalogService: marketplaceCatalogService,
                packageManager: pluginPackageManager,
                runtimeHost: pluginRuntimeHost,
                selectedPluginID: $selectedPluginID,
                openStore: { openSettings(.marketplace) }
            )
            .environmentObject(localizer)
        case .agentGuard:
            pluginContent("tracefence.agent-guard") {
                AgentGuardTab()
                    .environmentObject(localizer)
            }
        case .toolbox:
            ToolboxTab()
                .environmentObject(localizer)
        case .tokenScope:
            pluginContent("tracefence.token-usage") {
                TokenScopeLabView()
                    .environmentObject(localizer)
            }
        case .diskAdvisor:
            pluginContent("tracefence.disk-advisor") {
                DiskAdvisorLabView()
                    .environmentObject(localizer)
            }
        case .agentProfile:
            AgentGeoMirrorSettingsView()
                .environmentObject(localizer)
        case .localDiagnostics:
            LocalSystemDiagnosticsView()
                .environmentObject(localizer)
        case .migration:
            IntelMigrationTab()
                .environmentObject(localizer)
        }
    }

    @ViewBuilder
    private func pluginContent<Content: View>(
        _ pluginID: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if TraceFenceDistributionPolicy.currentChannel.isDirect,
           !TraceFenceEntitlementPolicy.canUsePlugin(pluginID) {
            TraceFencePluginAccessGateView(
                pluginID: pluginID,
                onOpenStore: { openSettings(.marketplace) }
            )
            .environmentObject(localizer)
            .environmentObject(pluginEntitlementService)
        } else {
            content()
        }
    }
}

private struct TraceFencePluginAccessGateView: View {
    @EnvironmentObject private var localizer: Localizer
    @EnvironmentObject private var pluginEntitlementService: TraceFencePluginEntitlementService
    let pluginID: String
    let onOpenStore: () -> Void

    private var plugin: TraceFencePluginDescriptor? {
        TraceFenceMarketplaceCatalogRuntime.plugin(id: pluginID)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()
            Image(systemName: plugin?.systemImage ?? "shippingbox.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 82, height: 82)
                .background(Theme.Colors.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 24))

            VStack(spacing: Theme.Spacing.sm) {
                Text(plugin?.name ?? localizer.t("插件", en: "Plugin"))
                    .font(Theme.Font.title2Bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(localizer.t(
                    plugin?.standaloneOfferID == nil
                        ? "这个功能现在由独立插件提供。你可以先试用 24 小时，或通过 Standard 订阅解锁全部插件。"
                        : "这个功能现在由独立插件提供。你可以先试用 24 小时、单独购买，或通过 Standard 订阅解锁全部插件。",
                    en: plugin?.standaloneOfferID == nil
                        ? "This feature is now provided as an independent plugin. Start a 24-hour trial or unlock every plugin with Standard."
                        : "This feature is now provided as an independent plugin. Start a 24-hour trial, buy it separately, or unlock every plugin with Standard."
                ))
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            }

            HStack(spacing: Theme.Spacing.md) {
                if let hours = plugin?.trialHours {
                    Button {
                        pluginEntitlementService.beginTrial(pluginID: pluginID)
                    } label: {
                        Label(localizer.t("试用 \(hours) 小时", en: "Try \(hours) hours"), systemImage: "timer")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 38))
                }
                Button(action: onOpenStore) {
                    Label(localizer.t("打开插件商城", en: "Open Plugin Store"), systemImage: "shippingbox.fill")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 38))
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }
}

struct TraceFenceIOSPairingSheet: View {
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var gatewayService: IOSRemoteControlGatewayService
    @Binding var isEnabled: Bool
    @Binding var port: Int
    @State private var copiedMessage: String?
    @State private var agentCoreStatus: TraceFenceAgentCoreStatus?
    @State private var isCheckingCoreUpdate = false

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    gatewayCard
                    sentinelInstallCard

                    if isEnabled {
                        pairingCard
                    }

                    agentAdaptersCard
                    accessRequirements
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .frame(width: 660, height: 680)
        .background(Theme.Colors.background)
        .onAppear {
            gatewayService.refreshNetworkEndpoint()
        }
        .task {
            if TraceFenceDistributionPolicy.currentChannel.isDirect {
                agentCoreStatus = await TraceFenceAgentCoreClient.shared.refresh()
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(statusColor.opacity(0.13))
                Image(systemName: statusIcon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 3) {
                Text(localizer.t("iOS 远程配对", en: "iOS Remote Pairing", zhHant: "iOS 遠端配對", ja: "iOS リモートペアリング", ko: "iOS 원격 페어링", mt: "iOS Remote Pairing"))
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(localizer.t(
                    "TraceFence Sentinel 通过本地 API 直接连接这台 Mac。",
                    en: "TraceFence Sentinel connects directly to this Mac through a local API.",
                    zhHant: "TraceFence Sentinel 透過本地 API 直接連接這台 Mac。",
                    ja: "TraceFence Sentinel はローカル API 経由でこの Mac に直接接続します。",
                    ko: "TraceFence Sentinel은 로컬 API를 통해 이 Mac에 직접 연결합니다.",
                    mt: "TraceFence Sentinel connects directly to this Mac through a local API."
                ))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xl)
        .background(.ultraThinMaterial)
        .background(Theme.Colors.elevatedCardBg.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Gradients.glassStroke)
                .frame(height: 1)
        }
    }

    private var gatewayCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(statusColor.opacity(0.12))
                    Image(systemName: statusIcon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(statusDetail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: $isEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: isEnabled) { enabled in
                        gatewayService.setEnabled(enabled, port: port)
                    }
            }

            Divider().overlay(Theme.Colors.separator.opacity(0.6))

            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.t("连接地址", en: "Endpoint", zhHant: "連接地址", ja: "接続先", ko: "연결 주소", mt: "Endpoint"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(gatewayService.endpoint.isEmpty ? "http://127.0.0.1:\(port)" : gatewayService.endpoint)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Stepper(value: $port, in: 1024...65535, step: 1) {
                    Text(localizer.t("端口 \(port)", en: "Port \(port)", zhHant: "連接埠 \(port)", ja: "ポート \(port)", ko: "포트 \(port)", mt: "Port \(port)"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(width: 160)
                .onChange(of: port) { newPort in
                    gatewayService.restart(port: newPort)
                }
            }

            Divider().overlay(Theme.Colors.separator.opacity(0.6))

            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: gatewayService.isKeepingMacAwake ? "moon.zzz.fill" : "moon.zzz")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(gatewayService.isKeepingMacAwake ? Theme.Colors.success : Theme.Colors.textTertiary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.t(
                        "锁屏时保持远程可用",
                        en: "Keep Remote Access Available While Locked",
                        zhHant: "鎖屏時保持遠端可用",
                        ja: "ロック中もリモートアクセスを維持",
                        ko: "잠금 중에도 원격 접근 유지",
                        mt: "Keep Remote Access Available While Locked"
                    ))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                    Text(localizer.t(
                        "开启远程控制时阻止 Mac 自动睡眠；屏幕仍可关闭和锁定。合盖、关机或断网后仍无法连接。",
                        en: "Prevents system sleep while remote control is enabled; the display may still turn off and lock. A closed lid, shutdown, or network outage still disconnects the Mac.",
                        zhHant: "開啟遠端控制時阻止 Mac 自動睡眠；螢幕仍可關閉和鎖定。合蓋、關機或斷網後仍無法連接。",
                        ja: "リモート制御中は自動スリープを防ぎます。画面の消灯とロックは可能です。蓋を閉じる、電源を切る、またはネットワークが切れると接続できません。",
                        ko: "원격 제어가 켜져 있는 동안 시스템 잠자기를 방지합니다. 화면 끄기와 잠금은 계속 가능합니다. 덮개를 닫거나 종료하거나 네트워크가 끊기면 연결할 수 없습니다.",
                        mt: "Prevents system sleep while remote control is enabled; the display may still turn off and lock. A closed lid, shutdown, or network outage still disconnects the Mac."
                    ))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Toggle("", isOn: Binding(
                    get: { gatewayService.keepMacAwakeEnabled },
                    set: { gatewayService.setKeepMacAwake($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.elevatedCardBg.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.Colors.separator.opacity(0.65), lineWidth: 1)
        )
    }

    private var sentinelInstallCard: some View {
        let testFlightURL = "https://testflight.apple.com/join/yZTXmaJ8"
        return HStack(alignment: .center, spacing: Theme.Spacing.lg) {
            TraceFencePairingQRCodeView(
                text: testFlightURL,
                accessibilityText: "TraceFence Sentinel TestFlight QR code"
            )
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Label(
                    localizer.t(
                        "安装 TraceFence Sentinel",
                        en: "Install TraceFence Sentinel",
                        zhHant: "安裝 TraceFence Sentinel",
                        ja: "TraceFence Sentinel をインストール",
                        ko: "TraceFence Sentinel 설치",
                        mt: "Install TraceFence Sentinel"
                    ),
                    systemImage: "arrow.down.app.fill"
                )
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)

                Text(localizer.t(
                    "如果 App Store 版本暂时不可用，请先扫描左侧二维码安装 TestFlight 版，再回到此页扫描下方的 Mac 配对二维码。",
                    en: "If the App Store version is temporarily unavailable, scan the code to install the TestFlight build, then return here and scan the Mac pairing code below.",
                    zhHant: "如果 App Store 版本暫時無法使用，請先掃描左側 QR Code 安裝 TestFlight 版，再回到此頁掃描下方的 Mac 配對 QR Code。",
                    ja: "App Store 版が一時的に利用できない場合は、左の QR コードから TestFlight 版をインストールし、この画面に戻って下の Mac ペアリングコードをスキャンしてください。",
                    ko: "App Store 버전을 일시적으로 사용할 수 없다면 왼쪽 QR 코드를 스캔해 TestFlight 버전을 설치한 뒤 이 화면으로 돌아와 아래의 Mac 페어링 코드를 스캔하세요.",
                    mt: "If the App Store version is temporarily unavailable, scan the code to install the TestFlight build, then return here and scan the Mac pairing code below."
                ))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        if let url = URL(string: testFlightURL) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label(localizer.t("打开 TestFlight", en: "Open TestFlight"), systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 34))

                    Button {
                        copyToPasteboard(testFlightURL)
                        showCopied(localizer.t("已复制 TestFlight 链接", en: "TestFlight link copied"))
                    } label: {
                        Label(localizer.t("复制链接", en: "Copy Link"), systemImage: "doc.on.doc")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .ghost, minHeight: 34))
                }
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.elevatedCardBg.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.Colors.separator.opacity(0.65), lineWidth: 1)
        )
    }

    private var pairingCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                TraceFencePairingQRCodeView(text: gatewayService.compactPairingPayloadText)
                    .frame(width: 196, height: 196)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Label(localizer.t("用 iPhone 扫码", en: "Scan with iPhone", zhHant: "用 iPhone 掃碼", ja: "iPhone でスキャン", ko: "iPhone으로 스캔", mt: "Scan with iPhone"), systemImage: "qrcode.viewfinder")
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Text(localizer.t(
                        "打开 TraceFence Sentinel 的“配对”页，扫描二维码即可导入 Mac 地址和配对密钥。",
                        en: "Open the Pairing tab in TraceFence Sentinel and scan this code to import the Mac endpoint and pairing token.",
                        zhHant: "打開 TraceFence Sentinel 的「配對」頁，掃描 QR Code 即可匯入 Mac 地址和配對密鑰。",
                        ja: "TraceFence Sentinel の「ペアリング」タブを開き、このコードをスキャンすると Mac の接続先とペアリングトークンを取り込めます。",
                        ko: "TraceFence Sentinel의 페어링 탭을 열고 이 코드를 스캔하면 Mac 주소와 페어링 토큰을 가져옵니다.",
                        mt: "Open the Pairing tab in TraceFence Sentinel and scan this code to import the Mac endpoint and pairing token."
                    ))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            copyToPasteboard(gatewayService.pairingPayloadText)
                            showCopied(localizer.t("已复制配对信息", en: "Pairing copied", zhHant: "已複製配對資訊", ja: "ペアリング情報をコピーしました", ko: "페어링 정보를 복사했습니다", mt: "Pairing copied"))
                        } label: {
                            Label(localizer.t("复制配对信息", en: "Copy Pairing", zhHant: "複製配對資訊", ja: "ペアリングをコピー", ko: "페어링 복사", mt: "Copy Pairing"), systemImage: "doc.on.doc")
                        }
                        .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 34))

                        Button {
                            gatewayService.rotatePairingToken()
                            copyToPasteboard(gatewayService.pairingPayloadText)
                            showCopied(localizer.t("已重置并复制新密钥", en: "Token reset and copied", zhHant: "已重設並複製新密鑰", ja: "トークンをリセットしてコピーしました", ko: "토큰을 재설정하고 복사했습니다", mt: "Token reset and copied"))
                        } label: {
                            Label(localizer.t("重置密钥", en: "Reset Token", zhHant: "重設密鑰", ja: "トークンをリセット", ko: "토큰 재설정", mt: "Reset Token"), systemImage: "key.horizontal.fill")
                        }
                        .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .ghost, minHeight: 34))
                    }

                    if let copiedMessage {
                        Label(copiedMessage, systemImage: "checkmark.circle.fill")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.success)
                    }
                }

                Spacer()
            }

            Text(localizer.t(
                "配对密钥可以控制这台 Mac 上的 Agent 审批和会话暂停/继续，只给自己的 iPhone 使用。",
                en: "The pairing token can control Agent approvals and session pause/resume on this Mac. Use it only with your own iPhone.",
                zhHant: "配對密鑰可以控制這台 Mac 上的 Agent 審批與會話暫停/繼續，只給自己的 iPhone 使用。",
                ja: "ペアリングトークンは、この Mac 上の Agent 承認とセッションの一時停止/再開を制御できます。自分の iPhone だけで使用してください。",
                ko: "페어링 토큰은 이 Mac의 Agent 승인과 세션 일시 중지/재개를 제어할 수 있습니다. 본인의 iPhone에서만 사용하세요.",
                mt: "The pairing token can control Agent approvals and session pause/resume on this Mac. Use it only with your own iPhone."
            ))
            .font(.system(size: 11))
            .foregroundStyle(Theme.Colors.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.cardBg.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.Colors.separator.opacity(0.62), lineWidth: 1)
        )
    }

    private var agentAdaptersCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(localizer.t("Agent 控制适配器", en: "Agent Control Adapters"), systemImage: "puzzlepiece.extension.fill")
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(localizer.t(
                "Agent Core 与每个 Agent 适配器独立升级。以后 Codex 或 Claude 协议变化时，只需更新对应适配器，不需要同时更换 macOS 和 iOS 客户端。",
                en: "Agent Core and each agent adapter update independently. When Codex or Claude changes its protocol, only that adapter needs an update; the macOS and iOS clients do not need to be replaced together."
            ))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                Label(
                    localizer.t(
                        "Mac App Store 版使用应用内 Hook 适配器。独立 Agent Core、CLI/PTY 启动和自更新仅在官网版提供。",
                        en: "The Mac App Store build uses in-app Hook adapters. Independent Agent Core, CLI/PTY launch, and self-updates are available only in the website build."
                    ),
                    systemImage: "app.badge.checkmark"
                )
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.info)
            } else if let status = agentCoreStatus, status.connected {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "cpu.fill")
                        .foregroundStyle(Theme.Colors.accent)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Core \(status.coreVersion ?? "-") (\(status.coreBuild ?? 0))")
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(coreUpdateDescription(status))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Button {
                        Task {
                            isCheckingCoreUpdate = true
                            agentCoreStatus = await TraceFenceAgentCoreClient.shared.checkForUpdates()
                            isCheckingCoreUpdate = false
                        }
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .rotationEffect(isCheckingCoreUpdate ? .degrees(180) : .zero)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isCheckingCoreUpdate)
                    .help(localizer.t(
                        "检查 Agent Core 更新",
                        en: "Check for Agent Core updates",
                        zhHant: "檢查 Agent Core 更新",
                        ja: "Agent Core の更新を確認",
                        ko: "Agent Core 업데이트 확인",
                        mt: "Check for Agent Core updates"
                    ))
                }

                Divider()

                ForEach(Array(status.adapters.enumerated()), id: \.offset) { _, adapter in
                    let adapterId = adapter["id"] as? String ?? "agent"
                    let name = adapter["displayName"] as? String ?? adapterId
                    let operational = adapter["operational"] as? Bool ?? false
                    let authenticated = adapter["authenticated"] as? Bool
                    let ready = operational && authenticated != false
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(ready ? Theme.Colors.success : Theme.Colors.warning)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(name)
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text(adapterDetail(id: adapterId, ready: ready))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                    }
                }
            } else {
                Label(
                    localizer.t("Agent Core 未连接，请重新安装或启动常驻服务。", en: "Agent Core is not connected. Reinstall or start the background service."),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.warning)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.elevatedCardBg.opacity(0.64))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.Colors.separator.opacity(0.65), lineWidth: 1)
        )
    }

    private func coreUpdateDescription(_ status: TraceFenceAgentCoreStatus) -> String {
        let state = status.update["state"] as? String ?? ""
        switch state {
        case "up_to_date", "installed":
            return localizer.t(
                "Core 已是最新版本，可独立于客户端升级。",
                en: "Core is current and updates independently from the clients.",
                zhHant: "Core 已是最新版本，可獨立於用戶端升級。",
                ja: "Core は最新で、クライアントとは独立して更新されます。",
                ko: "Core는 최신이며 클라이언트와 독립적으로 업데이트됩니다.",
                mt: "Core is current and updates independently from the clients."
            )
        case "checking", "downloading", "installing":
            return localizer.t(
                "正在由 Core 更新服务检查并安装…",
                en: "The Core update service is checking and installing…",
                zhHant: "Core 更新服務正在檢查並安裝…",
                ja: "Core 更新サービスが確認とインストールを実行中です…",
                ko: "Core 업데이트 서비스가 확인 및 설치 중입니다…",
                mt: "The Core update service is checking and installing..."
            )
        case "update_available":
            let version = status.update["latestVersion"] as? String ?? ""
            return localizer.t(
                "发现 Core \(version)，等待独立更新服务安装。",
                en: "Core \(version) is available for independent installation.",
                zhHant: "發現 Core \(version)，等待獨立更新服務安裝。",
                ja: "Core \(version) を独立更新サービスでインストールできます。",
                ko: "Core \(version)을 독립 업데이트 서비스로 설치할 수 있습니다.",
                mt: "Core \(version) is available for independent installation."
            )
        case "rolled_back":
            return localizer.t(
                "候选版本健康检查失败，已自动回滚。",
                en: "A candidate failed its health check and was rolled back automatically.",
                zhHant: "候選版本健康檢查失敗，已自動回滾。",
                ja: "候補版のヘルスチェックに失敗し、自動的にロールバックしました。",
                ko: "후보 버전의 상태 확인 실패로 자동 롤백했습니다.",
                mt: "A candidate failed its health check and was rolled back automatically."
            )
        case "failed":
            return localizer.t(
                "上次更新检查失败；当前 Core 继续正常运行。",
                en: "The last update check failed; the current Core remains operational.",
                zhHant: "上次更新檢查失敗；目前 Core 仍正常運作。",
                ja: "前回の更新確認に失敗しました。現在の Core は正常に動作しています。",
                ko: "마지막 업데이트 확인에 실패했지만 현재 Core는 정상 작동합니다.",
                mt: "The last update check failed; the current Core remains operational."
            )
        default:
            return localizer.t(
                "独立更新服务已就绪。",
                en: "The independent update service is ready.",
                zhHant: "獨立更新服務已就緒。",
                ja: "独立更新サービスの準備ができています。",
                ko: "독립 업데이트 서비스가 준비되었습니다.",
                mt: "The independent update service is ready."
            )
        }
    }

    private func adapterDetail(id: String, ready: Bool) -> String {
        switch id {
        case "codex":
            return ready
                ? localizer.t("官方 Codex app-server 已连接，可启动、插入指令、中断和审批。", en: "The official Codex app-server is connected for start, steer, interrupt, and approval controls.")
                : localizer.t("需要安装官方独立 Codex CLI，并运行 codex app-server daemon bootstrap。", en: "Install the official standalone Codex CLI, then run codex app-server daemon bootstrap.")
        case "claude":
            return ready
                ? localizer.t("Claude Code CLI 已登录；会话、停止、继续和权限 Hook 可用。", en: "Claude Code CLI is signed in; sessions, stop, continue, and permission hooks are available.")
                : localizer.t("需要安装并登录 Claude Code CLI：在终端运行 claude auth login。Claude Desktop 登录不能替代它。", en: "Install and sign in to Claude Code CLI by running claude auth login in Terminal. Claude Desktop sign-in does not replace it.")
        default:
            return ready
                ? localizer.t("适配器可用。", en: "Adapter ready.")
                : localizer.t("适配器需要处理。", en: "Adapter needs attention.")
        }
    }

    private var accessRequirements: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(localizer.t("互联网远程控制需要什么", en: "What Internet Control Needs", zhHant: "網際網路遠端控制需要什麼", ja: "インターネット越しの制御に必要なもの", ko: "인터넷 원격 제어에 필요한 것", mt: "What Internet Control Needs"), systemImage: "network")
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(localizer.t(
                "TraceFence 不提供云端中继，也不会保存你的 Agent 数据。离开同一局域网时，需要你自己提供一条能从 iPhone 访问到这台 Mac 的网络通道。",
                en: "TraceFence does not provide a cloud relay and does not store your Agent data. Outside the same local network, you provide the network path from iPhone to this Mac.",
                zhHant: "TraceFence 不提供雲端中繼，也不會保存你的 Agent 資料。離開同一區域網路時，需要你自己提供一條能從 iPhone 連到這台 Mac 的網路通道。",
                ja: "TraceFence はクラウドリレーを提供せず、Agent データも保存しません。同じローカルネットワーク外では、iPhone からこの Mac へ到達できるネットワーク経路をユーザー側で用意します。",
                ko: "TraceFence는 클라우드 릴레이를 제공하지 않으며 Agent 데이터를 저장하지 않습니다. 같은 로컬 네트워크 밖에서는 iPhone에서 이 Mac으로 접속할 수 있는 네트워크 경로를 사용자가 준비해야 합니다.",
                mt: "TraceFence does not provide a cloud relay and does not store your Agent data. Outside the same local network, you provide the network path from iPhone to this Mac."
            ))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
                ForEach(Array(accessRows.enumerated()), id: \.offset) { _, row in
                    remoteAccessRow(row)
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.elevatedCardBg.opacity(0.46))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func remoteAccessRow(_ row: RemoteAccessCopy) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: row.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(row.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(row.detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(row.note)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.cardBg.opacity(0.56))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusIcon: String {
        gatewayService.isRunning ? "iphone.radiowaves.left.and.right" : "iphone.slash"
    }

    private var statusColor: Color {
        gatewayService.isRunning ? Theme.Colors.success : Theme.Colors.textTertiary
    }

    private var statusTitle: String {
        gatewayService.isRunning
            ? localizer.t("已连接，iPhone 可配对", en: "Connected, iPhone can pair", zhHant: "已連接，iPhone 可配對", ja: "接続済み、iPhone でペアリング可能", ko: "연결됨, iPhone 페어링 가능", mt: "Connected, iPhone can pair")
            : localizer.t("未连接", en: "Disconnected", zhHant: "未連接", ja: "未接続", ko: "연결 안 됨", mt: "Disconnected")
    }

    private var statusDetail: String {
        gatewayService.isRunning
            ? localizer.t(
                "本地控制 API 正在监听。iOS 客户端配对后可查看 Agent 任务、远程审批，并暂停或继续会话。",
                en: "The local control API is listening. After pairing, the iOS client can monitor Agent tasks, approve operations, and pause or resume sessions.",
                zhHant: "本地控制 API 正在監聽。iOS 用戶端配對後可查看 Agent 任務、遠端審批，並暫停或繼續會話。",
                ja: "ローカル制御 API が待ち受け中です。ペアリング後、iOS クライアントで Agent タスクの監視、操作承認、セッションの一時停止/再開ができます。",
                ko: "로컬 제어 API가 대기 중입니다. 페어링 후 iOS 클라이언트에서 Agent 작업 확인, 원격 승인, 세션 일시 중지/재개를 할 수 있습니다.",
                mt: "The local control API is listening. After pairing, the iOS client can monitor Agent tasks, approve operations, and pause or resume sessions."
            )
            : localizer.t(
                "开启后会在这台 Mac 上启动本地控制 API，并生成供 TraceFence Sentinel 扫描的配对二维码。",
                en: "Turn it on to start the local control API on this Mac and generate a pairing QR code for TraceFence Sentinel.",
                zhHant: "開啟後會在這台 Mac 上啟動本地控制 API，並產生供 TraceFence Sentinel 掃描的配對 QR Code。",
                ja: "オンにすると、この Mac でローカル制御 API を開始し、TraceFence Sentinel 用のペアリング QR コードを生成します。",
                ko: "켜면 이 Mac에서 로컬 제어 API를 시작하고 TraceFence Sentinel이 스캔할 페어링 QR 코드를 생성합니다.",
                mt: "Turn it on to start the local control API on this Mac and generate a pairing QR code for TraceFence Sentinel."
            )
    }

    private var accessRows: [RemoteAccessCopy] {
        [
            RemoteAccessCopy(
                icon: "wifi",
                title: localizer.t("同一 Wi-Fi 或局域网", en: "Same Wi-Fi or LAN", zhHant: "同一 Wi-Fi 或區域網路", ja: "同じ Wi-Fi または LAN", ko: "같은 Wi-Fi 또는 LAN", mt: "Same Wi-Fi or LAN"),
                detail: localizer.t("Mac 和 iPhone 在同一网络下即可连接，不需要改路由器。", en: "Mac and iPhone can connect on the same network. No router changes are needed.", zhHant: "Mac 和 iPhone 在同一網路下即可連接，不需要修改路由器。", ja: "Mac と iPhone が同じネットワーク上にあれば接続できます。ルーター設定は不要です。", ko: "Mac과 iPhone이 같은 네트워크에 있으면 연결할 수 있으며 라우터 변경이 필요 없습니다.", mt: "Mac and iPhone can connect on the same network. No router changes are needed."),
                note: localizer.t("适合家里或办公室。离开这个网络后就不能直连。", en: "Best for home or office. It stops working after the phone leaves that network.", zhHant: "適合家裡或辦公室。手機離開這個網路後就無法直連。", ja: "自宅やオフィス向きです。iPhone がそのネットワークを離れると直結できません。", ko: "집이나 사무실에 적합합니다. 휴대폰이 이 네트워크를 벗어나면 직접 연결할 수 없습니다.", mt: "Best for home or office. It stops working after the phone leaves that network."),
                color: Theme.Colors.success
            ),
            RemoteAccessCopy(
                icon: "lock.shield.fill",
                title: localizer.t("私有 VPN / Tailnet", en: "Private VPN / Tailnet", zhHant: "私有 VPN / Tailnet", ja: "プライベート VPN / Tailnet", ko: "개인 VPN / Tailnet", mt: "Private VPN / Tailnet"),
                detail: localizer.t("在 Mac 和 iPhone 上安装并登录 Tailscale、ZeroTier、WireGuard 或公司 VPN。", en: "Install and sign in to Tailscale, ZeroTier, WireGuard, or a company VPN on both devices.", zhHant: "在 Mac 和 iPhone 上安裝並登入 Tailscale、ZeroTier、WireGuard 或公司 VPN。", ja: "Mac と iPhone の両方で Tailscale、ZeroTier、WireGuard、または会社の VPN にログインします。", ko: "Mac과 iPhone 모두에서 Tailscale, ZeroTier, WireGuard 또는 회사 VPN에 로그인합니다.", mt: "Install and sign in to Tailscale, ZeroTier, WireGuard, or a company VPN on both devices."),
                note: localizer.t("这是没有 TraceFence 后端时最推荐的互联网远程控制方式。", en: "Recommended for Internet control without a TraceFence backend.", zhHant: "這是沒有 TraceFence 後端時最推薦的網際網路遠端控制方式。", ja: "TraceFence バックエンドなしでインターネット越しに使う場合の推奨方式です。", ko: "TraceFence 백엔드 없이 인터넷 원격 제어를 할 때 권장되는 방식입니다.", mt: "Recommended for Internet control without a TraceFence backend."),
                color: Theme.Colors.info
            ),
            RemoteAccessCopy(
                icon: "network",
                title: localizer.t("端口转发 + DDNS", en: "Port Forwarding + DDNS", zhHant: "連接埠轉發 + DDNS", ja: "ポート転送 + DDNS", ko: "포트 포워딩 + DDNS", mt: "Port Forwarding + DDNS"),
                detail: localizer.t("你需要配置路由器端口转发、防火墙规则，以及稳定域名或静态 IP。", en: "You configure router port forwarding, firewall rules, and a stable hostname or static IP.", zhHant: "你需要配置路由器連接埠轉發、防火牆規則，以及穩定網域或固定 IP。", ja: "ルーターのポート転送、ファイアウォール規則、安定したホスト名または固定 IP を設定します。", ko: "라우터 포트 포워딩, 방화벽 규칙, 안정적인 호스트명 또는 고정 IP를 설정해야 합니다.", mt: "You configure router port forwarding, firewall rules, and a stable hostname or static IP."),
                note: localizer.t("只建议高级用户使用；公网暴露时请使用 HTTPS 或安全隧道。", en: "For advanced users only; use HTTPS or a secure tunnel on public endpoints.", zhHant: "只建議進階使用者使用；對公網暴露時請使用 HTTPS 或安全隧道。", ja: "上級者向けです。公開エンドポイントでは HTTPS または安全なトンネルを使ってください。", ko: "고급 사용자에게만 권장합니다. 공개 엔드포인트에는 HTTPS 또는 보안 터널을 사용하세요.", mt: "For advanced users only; use HTTPS or a secure tunnel on public endpoints."),
                color: Theme.Colors.warning
            ),
            RemoteAccessCopy(
                icon: "point.3.connected.trianglepath.dotted",
                title: localizer.t("自有反向隧道", en: "User-Owned Reverse Tunnel", zhHant: "自有反向隧道", ja: "ユーザー所有のリバーストンネル", ko: "사용자 소유 역방향 터널", mt: "User-Owned Reverse Tunnel"),
                detail: localizer.t("你可以使用 Cloudflare Tunnel、frp、SSH 反向隧道或自己的 VPS 中继。", en: "You can use Cloudflare Tunnel, frp, SSH reverse tunnel, or your own VPS relay.", zhHant: "你可以使用 Cloudflare Tunnel、frp、SSH 反向隧道或自己的 VPS 中繼。", ja: "Cloudflare Tunnel、frp、SSH リバーストンネル、または自分の VPS リレーを利用できます。", ko: "Cloudflare Tunnel, frp, SSH 역방향 터널 또는 본인 VPS 릴레이를 사용할 수 있습니다.", mt: "You can use Cloudflare Tunnel, frp, SSH reverse tunnel, or your own VPS relay."),
                note: localizer.t("隧道服务由你自己维护；TraceFence 只负责本机 API 和配对密钥。", en: "You operate the tunnel; TraceFence only provides the local API and pairing token.", zhHant: "隧道服務由你自己維護；TraceFence 只負責本地 API 和配對密鑰。", ja: "トンネルはユーザーが運用します。TraceFence はローカル API とペアリングトークンのみを提供します。", ko: "터널은 사용자가 운영합니다. TraceFence는 로컬 API와 페어링 토큰만 제공합니다.", mt: "You operate the tunnel; TraceFence only provides the local API and pairing token."),
                color: Theme.Colors.purple
            )
        ]
    }

    private func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    private func showCopied(_ message: String) {
        copiedMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            if copiedMessage == message {
                copiedMessage = nil
            }
        }
    }

    private struct RemoteAccessCopy {
        let icon: String
        let title: String
        let detail: String
        let note: String
        let color: Color
    }
}

private struct TraceFencePairingQRCodeView: View {
    let text: String
    let accessibilityText: String

    init(text: String, accessibilityText: String = "TraceFence iOS pairing QR code") {
        self.text = text
        self.accessibilityText = accessibilityText
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white)
            if let image = TraceFenceQRCodeImageFactory.image(from: text) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 46, weight: .regular))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.Colors.separator.opacity(0.7), lineWidth: 1)
        )
        .accessibilityLabel(accessibilityText)
    }
}

enum TraceFenceQRCodeImageFactory {
    private static let quietZoneModules = 4
    private static let pixelsPerModule = 8

    static func image(from text: String) -> NSImage? {
        guard let data = text.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = data
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.integral
        let ciContext = CIContext(options: [.useSoftwareRenderer: true])
        guard let source = ciContext.createCGImage(output, from: extent) else { return nil }

        let moduleWidth = source.width
        let moduleHeight = source.height
        let pixelWidth = (moduleWidth + quietZoneModules * 2) * pixelsPerModule
        let pixelHeight = (moduleHeight + quietZoneModules * 2) * pixelsPerModule
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.interpolationQuality = .none
        let inset = quietZoneModules * pixelsPerModule
        context.draw(
            source,
            in: CGRect(
                x: inset,
                y: inset,
                width: moduleWidth * pixelsPerModule,
                height: moduleHeight * pixelsPerModule
            )
        )
        guard let rendered = context.makeImage() else { return nil }
        return NSImage(cgImage: rendered, size: NSSize(width: pixelWidth, height: pixelHeight))
    }
}

// MARK: - Page Header Component

struct PageHeader: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let trailing: AnyView

    init(icon: String, title: String, subtitle: String, color: Color, @ViewBuilder trailing: () -> some View = { EmptyView() }) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.color = color
        self.trailing = AnyView(trailing())
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .fill(Theme.Gradients.hero)
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(Color.white.opacity(0.70), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 38, height: 38)
            .shadow(color: Theme.Colors.accent.opacity(0.18), radius: 10, y: 5)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.sm + 2)
        .background(Theme.Colors.elevatedCardBg.opacity(0.68))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(height: 1)
        }
    }
}

struct ScanningStatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            RadarScanGlyph(color: color)
            Text(title)
                .font(Theme.Font.subheadlineMedium)
                .lineLimit(1)
        }
        .foregroundStyle(color)
        .padding(.horizontal, Theme.Spacing.sm + 4)
        .padding(.vertical, Theme.Spacing.xs + 3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(color.opacity(0.09))
        )
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(color.opacity(0.20), lineWidth: 1)
        }
        .shadow(color: color.opacity(0.16), radius: 10, x: 0, y: 0)
    }
}

struct RadarScanGlyph: View {
    let color: Color
    @State private var sweep: Double = 0
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))

            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .stroke(color.opacity(0.42 - Double(index) * 0.12), lineWidth: 1.1)
                    .scaleEffect(pulse ? 1.08 + CGFloat(index) * 0.26 : 0.50 + CGFloat(index) * 0.12)
                    .opacity(pulse ? 0 : 0.72 - Double(index) * 0.20)
                    .animation(
                        .easeOut(duration: 1.55)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.34),
                        value: pulse
                    )
            }

            Circle()
                .stroke(color.opacity(0.24), lineWidth: 1)
                .scaleEffect(0.74)

            Circle()
                .trim(from: 0, to: 0.27)
                .stroke(
                    AngularGradient(
                        colors: [
                            color.opacity(0),
                            color.opacity(0.34),
                            color.opacity(0.95)
                        ],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 8, lineCap: .round)
                )
                .rotationEffect(.degrees(sweep))
                .scaleEffect(0.62)
                .blur(radius: 0.2)

            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
                .shadow(color: color.opacity(0.7), radius: 6)
        }
        .frame(width: 26, height: 26)
        .drawingGroup()
        .onAppear {
            withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                sweep = 360
            }
            withAnimation(.easeOut(duration: 1.55).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

struct ScanningProgressCaption: View {
    let detail: String
    let color: Color
    @State private var progress: CGFloat = -0.55

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(detail)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(color)
                .lineLimit(1)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.14))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0), color.opacity(0.95), Color.white.opacity(0.85), color.opacity(0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(42, proxy.size.width * 0.42))
                        .offset(x: proxy.size.width * progress)
                        .shadow(color: color.opacity(0.35), radius: 6, x: 0, y: 0)
                }
            }
            .frame(width: 142, height: 4)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.25).repeatForever(autoreverses: false)) {
                progress = 1.15
            }
        }
    }
}

// MARK: - Toolbox Tab

struct ToolboxTab: View {
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var service: ScannerService
    @State private var selectedTool = 0

    private var tools: [(icon: String, title: (Localizer) -> String, subtitle: (Localizer) -> String, color: Color)] {
        var items: [(icon: String, title: (Localizer) -> String, subtitle: (Localizer) -> String, color: Color)] = [
            ("chart.xyaxis.line", { $0.tokenScopeTitle }, { $0.tokenScopeSubtitle }, Theme.Colors.accent)
        ]
        items.append((icon: "sparkles", title: { $0.t("AI 磁盘顾问", en: "AI Disk Advisor", zhHant: "AI 磁碟顧問", ja: "AI ディスクアドバイザー", ko: "AI 디스크 어드바이저", mt: "AI Disk Advisor") }, subtitle: { $0.t("Apple Intelligence 磁盘清理建议", en: "Apple Intelligence cleanup advice", zhHant: "Apple Intelligence 磁碟清理建議", ja: "Apple Intelligence のクリーンアップ提案", ko: "Apple Intelligence 정리 제안", mt: "Apple Intelligence cleanup advice") }, color: Theme.Colors.purple))
        items.append((icon: "globe.badge.chevron.backward", title: { $0.t("Agent 画像", en: "Agent Profile", zhHant: "Agent 畫像", ja: "Agent プロファイル", ko: "Agent 프로필", mt: "Agent Profile") }, subtitle: { $0.t("语言、时区与本地探测画像", en: "Language, timezone, and local probe profile", zhHant: "語言、時區與本機探測畫像", ja: "言語、タイムゾーン、ローカル診断プロファイル", ko: "언어, 시간대 및 로컬 탐지 프로필", mt: "Language, timezone, and local probe profile") }, color: Theme.Colors.info))
        items.append((icon: "arrow.down.doc.fill", title: { $0.navCleaner }, subtitle: { $0.subCleaner }, color: Theme.Colors.info))
        items.append((icon: "app.badge", title: { $0.navApp }, subtitle: { $0.subApp }, color: Theme.Colors.accent))
        items.append((icon: "cube.box", title: { $0.navDependency }, subtitle: { $0.subDependency }, color: Theme.Colors.warning))
        items.append((icon: "terminal", title: { $0.navOther }, subtitle: { $0.subOther }, color: Theme.Colors.textSecondary))
        items.append((icon: "arrow.triangle.2.circlepath", title: { $0.navMigration }, subtitle: { $0.subMigration }, color: Theme.Colors.purple))
        return items
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "wrench.and.screwdriver.fill",
                title: localizer.navToolbox,
                subtitle: localizer.subToolbox,
                color: Theme.Colors.accent
            )

            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: Theme.Spacing.lg),
                    GridItem(.flexible(), spacing: Theme.Spacing.lg),
                    GridItem(.flexible(), spacing: Theme.Spacing.lg)
                ], spacing: Theme.Spacing.lg) {
                    ForEach(Array(tools.enumerated()), id: \.offset) { index, tool in
                        toolCard(index: index, tool: tool)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
            }
        }
    }

    private func toolCard(index: Int, tool: (icon: String, title: (Localizer) -> String, subtitle: (Localizer) -> String, color: Color)) -> some View {
        Button {
            selectedTool = index
        } label: {
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: tool.icon)
                    .font(.system(size: 28))
                    .foregroundStyle(tool.color)
                    .frame(width: 52, height: 52)
                    .background(tool.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                Text(tool.title(localizer))
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)

                Text(tool.subtitle(localizer))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.lg)
            .background(Theme.Colors.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(tool.color.opacity(0.12), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Filter Bar Component

struct FilterSearchBar: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm - 2) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Colors.textTertiary)
                .font(.system(size: 11))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm + 2)
        .padding(.vertical, Theme.Spacing.sm - 2)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

// MARK: - Operation Log Tab

fileprivate enum DisplayTime {
    static let withSeconds: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

fileprivate enum ResultListColumns {
    static let selection: CGFloat = 16
    static let state: CGFloat = 14
    static let name: CGFloat = 160
    static let source: CGFloat = 60
    static let project: CGFloat = 90
    static let risk: CGFloat = 60
    static let size: CGFloat = 70
    static let description: CGFloat = 180
    static let actions: CGFloat = 58
    static let spacing: CGFloat = 12
    static let rowPadding: CGFloat = 24
    static let total: CGFloat = selection + state + name + source + project + risk + size + description + actions + spacing * 8 + rowPadding * 2
}

struct AgentMonitorOverviewRow: Identifiable {
    let id: String
    let agentName: String
    let sessionCount: Int
    let operationCount: Int
    let totalTokens: Int
    let contextPercent: Double
    let processCount: Int
    let portCount: Int
    let latestActivity: Date?
    let projectPath: String
}

struct AgentMonitorTokenBreakdown: Codable {
    let input: Int
    let output: Int
    let cacheRead: Int

    var total: Int { input + output + cacheRead }
}

struct AgentMonitorSessionSnapshot: Identifiable, Codable {
    let id: String
    let agentName: String
    let pid: Int?
    let sessionId: String
    let status: String
    let projectName: String
    let projectPath: String
    let model: String
    let tokens: AgentMonitorTokenBreakdown
    let contextPercent: Double
    let contextWindow: Int
    let turnCount: Int
    let currentTask: String
    let toolCount: Int
    let runningToolCount: Int
    let childCount: Int
    let ports: [Int]
    let memoryMB: Int?
    let latestActivity: Date?
    let instructionDate: Date?
    let sourcePath: String
}

struct AgentNetworkConnection: Identifiable, Codable, Hashable {
    let id: String
    let agentName: String
    let pid: Int
    let processName: String
    let localEndpoint: String
    let remoteEndpoint: String
    let remoteHost: String
    let remotePort: Int?
    let state: String
    let route: String
    let riskLevel: String
    let safetyStatus: String?
    let safetyReason: String?
    let observedAt: Date
}

struct AgentMonitorUsageSnapshot: Identifiable, Codable {
    let id: String
    let agentName: String
    let sessionCount: Int
    let totalTokens: Int
    let contextPercent: Double
    let processCount: Int
    let portCount: Int
    let latestActivity: Date?
    let projectPath: String
    let sourcePath: String
}

@MainActor
final class AgentMonitorOverviewStore: ObservableObject {
    @Published var snapshots: [AgentMonitorUsageSnapshot] = []
    @Published var sessions: [AgentMonitorSessionSnapshot] = []
    @Published var networkConnections: [AgentNetworkConnection] = []
    @Published var isScanning = false
    @Published var authorizedRoots: [String] = []
    @Published var scannedRoots: [String] = []
    @Published var lastScanDate: Date?

    private let scanner = AgentMonitorOverviewScanner()
    private let cachedRootsKey = "agentMonitorOverview.scannedRoots"
    private var backgroundRefreshTimer: Timer?
    private var isBackgroundRefreshActive = false
    private var isRefreshingRealtime = false
    private var focusedRefreshKeysInFlight: Set<String> = []
    private var lastFocusedRefreshByKey: [String: Date] = [:]
    private var lastRealtimeRefreshDate: Date?
    private var lastFullScanDate: Date?
    private let activeRetentionWindow: TimeInterval = 30 * 60
    private let maxCachedSessions = 120

    private struct Cache: Codable {
        var version: Int = 2
        var updatedAt: Date = Date()
        var snapshots: [AgentMonitorUsageSnapshot] = []
        var sessions: [AgentMonitorSessionSnapshot] = []
        var networkConnections: [AgentNetworkConnection]? = nil
        var authorizedRoots: [String] = []
        var scannedRoots: [String] = []
        var lastScanDate: Date?
        var lastFullScanDate: Date?
    }

    init() {
        scannedRoots = UserDefaults.standard.stringArray(forKey: cachedRootsKey) ?? []
        loadCache()
    }

    deinit {
        backgroundRefreshTimer?.invalidate()
    }

    func startBackgroundRefresh() {
        guard backgroundRefreshTimer == nil else { return }
        isBackgroundRefreshActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            guard let self, self.isBackgroundRefreshActive else { return }
            self.refreshRealtime()
        }
        let timer = Timer(timeInterval: 120, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isBackgroundRefreshActive else { return }
                self.refreshRealtime()
            }
        }
        backgroundRefreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stopBackgroundRefresh() {
        isBackgroundRefreshActive = false
        backgroundRefreshTimer?.invalidate()
        backgroundRefreshTimer = nil
    }

    func refresh(force: Bool = false) {
        let needsFullScan = force ||
            snapshots.isEmpty ||
            (lastFullScanDate.map { Date().timeIntervalSince($0) >= 6 * 60 * 60 } ?? true)
        if !needsFullScan {
            refreshRealtime()
            return
        }
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .utility) { [scanner] in
            let result = scanner.scan()
            await MainActor.run {
                if !result.snapshots.isEmpty {
                    self.snapshots = Self.mergedSnapshots(
                        primary: result.snapshots,
                        fallback: Self.sanitizedSnapshots(self.snapshots)
                    )
                }
                if !result.sessions.isEmpty {
                    self.sessions = Self.mergedSessions(
                        primary: result.sessions,
                        fallback: Self.sanitizedSessions(self.sessions),
                        activeRetentionWindow: self.activeRetentionWindow
                    )
                }
                self.networkConnections = result.networkConnections
                self.authorizedRoots = result.authorizedRoots
                self.scannedRoots = result.scannedRoots
                UserDefaults.standard.set(result.scannedRoots, forKey: self.cachedRootsKey)
                self.lastScanDate = Date()
                self.lastFullScanDate = self.lastScanDate
                self.isScanning = false
                self.saveCache()
            }
        }
    }

    func refreshRealtime() {
        guard !isScanning, !isRefreshingRealtime else { return }
        if let lastRealtimeRefreshDate,
           Date().timeIntervalSince(lastRealtimeRefreshDate) < 90 {
            return
        }
        isRefreshingRealtime = true
        let cachedRoots = scannedRoots
        let retainedActiveSources = sessions
            .filter(Self.isActiveSession)
            .map(\.sourcePath)
        Task.detached(priority: .utility) { [scanner] in
            let result = scanner.realtimeScan(
                cachedRoots: cachedRoots,
                retainedActiveSources: retainedActiveSources
            )
            await MainActor.run {
                if !result.sessions.isEmpty {
                    self.sessions = Self.mergedSessions(
                        primary: result.sessions,
                        fallback: Self.sanitizedSessions(self.sessions),
                        activeRetentionWindow: self.activeRetentionWindow
                    )
                    let realtimeSnapshots = Self.usageSnapshots(from: self.sessions)
                    if !realtimeSnapshots.isEmpty {
                        self.snapshots = Self.mergedSnapshots(primary: realtimeSnapshots, fallback: Self.sanitizedSnapshots(self.snapshots))
                    }
                }
                if !result.authorizedRoots.isEmpty {
                    self.authorizedRoots = result.authorizedRoots
                }
                self.networkConnections = result.networkConnections
                if self.scannedRoots.isEmpty, !result.scannedRoots.isEmpty {
                    self.scannedRoots = result.scannedRoots
                }
                let cachedSessionSnapshots = Self.usageSnapshots(from: self.sessions)
                if !cachedSessionSnapshots.isEmpty {
                    self.snapshots = Self.mergedSnapshots(primary: cachedSessionSnapshots, fallback: Self.sanitizedSnapshots(self.snapshots))
                }
                self.lastScanDate = Date()
                self.saveCache()
                self.lastRealtimeRefreshDate = Date()
                self.isRefreshingRealtime = false
            }
        }
    }

    func refreshFocusedSession(_ session: AgentMonitorSessionSnapshot) {
        guard Self.isActiveSession(session) else { return }
        let key = Self.sessionKey(session)
        guard !focusedRefreshKeysInFlight.contains(key) else { return }
        if let last = lastFocusedRefreshByKey[key],
           Date().timeIntervalSince(last) < 60 {
            return
        }
        focusedRefreshKeysInFlight.insert(key)
        lastFocusedRefreshByKey[key] = Date()
        Task.detached(priority: .utility) { [scanner] in
            let refreshed = scanner.scanSession(session)
            await MainActor.run {
                self.focusedRefreshKeysInFlight.remove(key)
                guard let refreshed else { return }
                self.applyFocusedSessionRefresh(refreshed, previousKey: key)
            }
        }
    }

    private static func isActiveSession(_ session: AgentMonitorSessionSnapshot) -> Bool {
        ["Thinking", "Executing", "Waiting", "Paused"].contains(session.status) ||
        (!session.currentTask.isEmpty && session.status != "History" && session.status != "Done")
    }

    private static func usageSnapshots(from sessions: [AgentMonitorSessionSnapshot]) -> [AgentMonitorUsageSnapshot] {
        Dictionary(grouping: sessions, by: \.agentName).map { agentName, rows in
            let latest = rows.compactMap(\.latestActivity).max()
            let top = rows.max {
                ($0.latestActivity ?? .distantPast) < ($1.latestActivity ?? .distantPast)
            }
            return AgentMonitorUsageSnapshot(
                id: agentName,
                agentName: agentName,
                sessionCount: Set(rows.map(\.sessionId)).count,
                totalTokens: rows.reduce(0) { $0 + $1.tokens.total },
                contextPercent: rows.map(\.contextPercent).max() ?? 0,
                processCount: Set(rows.compactMap(\.pid)).count,
                portCount: rows.reduce(0) { $0 + $1.ports.count },
                latestActivity: latest,
                projectPath: top?.projectPath ?? "",
                sourcePath: top?.sourcePath ?? ""
            )
        }
        .sorted {
            let left = $0.latestActivity ?? .distantPast
            let right = $1.latestActivity ?? .distantPast
            if left == right { return $0.agentName < $1.agentName }
            return left > right
        }
    }

    private static func mergedSnapshots(primary: [AgentMonitorUsageSnapshot], fallback: [AgentMonitorUsageSnapshot]) -> [AgentMonitorUsageSnapshot] {
        var byName = Dictionary(uniqueKeysWithValues: fallback.map { ($0.agentName, $0) })
        for snapshot in primary {
            guard let cached = byName[snapshot.agentName] else {
                byName[snapshot.agentName] = snapshot
                continue
            }
            let latest = maxDate(cached.latestActivity, snapshot.latestActivity)
            let newest = (snapshot.latestActivity ?? .distantPast) >= (cached.latestActivity ?? .distantPast) ? snapshot : cached
            byName[snapshot.agentName] = AgentMonitorUsageSnapshot(
                id: snapshot.id,
                agentName: snapshot.agentName,
                sessionCount: max(snapshot.sessionCount, cached.sessionCount),
                totalTokens: max(snapshot.totalTokens, cached.totalTokens),
                contextPercent: newest.contextPercent,
                processCount: newest.processCount,
                portCount: newest.portCount,
                latestActivity: latest,
                projectPath: newest.projectPath,
                sourcePath: newest.sourcePath
            )
        }
        return Array(byName.values).sorted {
            let left = $0.latestActivity ?? .distantPast
            let right = $1.latestActivity ?? .distantPast
            if left == right { return $0.agentName < $1.agentName }
            return left > right
        }
    }

    private static func mergedSessions(
        primary: [AgentMonitorSessionSnapshot],
        fallback: [AgentMonitorSessionSnapshot],
        activeRetentionWindow: TimeInterval
    ) -> [AgentMonitorSessionSnapshot] {
        var byKey = Dictionary(uniqueKeysWithValues: fallback.map { (sessionKey($0), $0) })
        for session in primary {
            let key = sessionKey(session)
            if let cached = byKey[key] {
                byKey[key] = mergedSession(primary: session, fallback: cached)
            } else {
                byKey[key] = session
            }
        }

        let activeCutoff = Date().addingTimeInterval(-activeRetentionWindow)
        let rows = byKey.values.filter { session in
            if session.status == "Paused" || session.status == "Waiting" { return true }
            if isActiveSession(session) {
                return (session.latestActivity ?? .distantPast) >= activeCutoff
            }
            return true
        }
        .sorted {
            let leftActive = isActiveSession($0)
            let rightActive = isActiveSession($1)
            if leftActive != rightActive { return leftActive }
            let left = $0.latestActivity ?? .distantPast
            let right = $1.latestActivity ?? .distantPast
            if left == right { return $0.agentName < $1.agentName }
            return left > right
        }
        return Array(rows.prefix(160))
    }

    private static func sanitizedSessions(_ sessions: [AgentMonitorSessionSnapshot]) -> [AgentMonitorSessionSnapshot] {
        sessions.filter { !isInvalidCachedSession($0) }
    }

    private static func isInvalidCachedSession(_ session: AgentMonitorSessionSnapshot) -> Bool {
        if session.agentName == "Claude Code",
           session.model == "<synthetic>",
           session.tokens.total == 0,
           session.toolCount == 0,
           session.runningToolCount == 0,
           session.turnCount <= 1,
           session.currentTask.localizedCaseInsensitiveContains("Claude Code session") {
            return true
        }
        let lowerTask = session.currentTask.lowercased()
        if session.agentName == "Claude Code",
           session.tokens.total == 0,
           session.toolCount == 0,
           lowerTask.contains("conversation title generator") {
            return true
        }
        if session.agentName == "Claude Code",
           lowerTask.contains("this session is being continued from a previous conversation") {
            return true
        }
        return false
    }

    private static func mergedSession(
        primary: AgentMonitorSessionSnapshot,
        fallback: AgentMonitorSessionSnapshot,
        preserveNewerWaitingState: Bool = true
    ) -> AgentMonitorSessionSnapshot {
        let primaryIsNewer = (primary.latestActivity ?? .distantPast) >= (fallback.latestActivity ?? .distantPast)
        let newest = primaryIsNewer ? primary : fallback
        let fallbackIsNewer = (fallback.latestActivity ?? .distantPast) > (primary.latestActivity ?? .distantPast)
        let status: String
        if preserveNewerWaitingState,
           fallbackIsNewer,
           ["Paused", "Waiting"].contains(fallback.status),
           ["Done", "History"].contains(primary.status) {
            status = fallback.status
        } else {
            status = newest.status
        }
        return AgentMonitorSessionSnapshot(
            id: primary.id,
            agentName: primary.agentName,
            pid: primary.pid ?? fallback.pid,
            sessionId: primary.sessionId,
            status: status,
            projectName: newest.projectName.isEmpty ? fallback.projectName : newest.projectName,
            projectPath: newest.projectPath.isEmpty ? fallback.projectPath : newest.projectPath,
            model: newest.model == "—" ? fallback.model : newest.model,
            tokens: AgentMonitorTokenBreakdown(
                input: max(primary.tokens.input, fallback.tokens.input),
                output: max(primary.tokens.output, fallback.tokens.output),
                cacheRead: max(primary.tokens.cacheRead, fallback.tokens.cacheRead)
            ),
            contextPercent: newest.contextPercent,
            contextWindow: max(primary.contextWindow, fallback.contextWindow),
            turnCount: max(primary.turnCount, fallback.turnCount),
            currentTask: newest.currentTask.isEmpty ? fallback.currentTask : newest.currentTask,
            toolCount: max(primary.toolCount, fallback.toolCount),
            runningToolCount: status == "Executing" ? max(primary.runningToolCount, fallback.runningToolCount) : primary.runningToolCount,
            childCount: primary.childCount,
            ports: primary.ports,
            memoryMB: primary.memoryMB ?? fallback.memoryMB,
            latestActivity: maxDate(primary.latestActivity, fallback.latestActivity),
            instructionDate: newest.instructionDate ?? newest.latestActivity ?? fallback.instructionDate,
            sourcePath: primary.sourcePath
        )
    }

    private func applyFocusedSessionRefresh(_ refreshed: AgentMonitorSessionSnapshot, previousKey: String) {
        let refreshedKey = Self.sessionKey(refreshed)
        var byKey = Dictionary(uniqueKeysWithValues: Self.sanitizedSessions(sessions).map { (Self.sessionKey($0), $0) })
        let fallback = byKey.removeValue(forKey: previousKey) ?? byKey[refreshedKey]
        if let fallback {
            byKey[refreshedKey] = Self.mergedSession(
                primary: refreshed,
                fallback: fallback,
                preserveNewerWaitingState: false
            )
        } else {
            byKey[refreshedKey] = refreshed
        }
        sessions = Array(byKey.values)
            .sorted {
                let leftActive = Self.isActiveSession($0)
                let rightActive = Self.isActiveSession($1)
                if leftActive != rightActive { return leftActive }
                let left = $0.latestActivity ?? .distantPast
                let right = $1.latestActivity ?? .distantPast
                if left == right { return $0.agentName < $1.agentName }
                return left > right
            }
            .prefix(160)
            .map { $0 }

        let focusedSnapshots = Self.usageSnapshots(from: sessions)
        if !focusedSnapshots.isEmpty {
            snapshots = Self.mergedSnapshots(primary: focusedSnapshots, fallback: Self.sanitizedSnapshots(snapshots))
        }
        lastScanDate = Date()
        saveCache()
    }

    private static func sessionKey(_ session: AgentMonitorSessionSnapshot) -> String {
        "\(session.agentName)|\(session.sessionId)|\(session.sourcePath)"
    }

    private static func maxDate(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (left?, right?): return max(left, right)
        case let (left?, nil): return left
        case let (nil, right?): return right
        default: return nil
        }
    }

    private static func sanitizedSnapshots(_ snapshots: [AgentMonitorUsageSnapshot]) -> [AgentMonitorUsageSnapshot] {
        snapshots.filter { snapshot in
            let lower = snapshot.sourcePath.lowercased()
            switch snapshot.agentName {
            case "Claude Code":
                return lower.contains("/.claude/") || lower.contains("/.config/claude/")
            case "Cursor":
                return lower.hasSuffix(".vscdb") && lower.contains("cursor")
            case "OpenClaw":
                return lower.contains("/.openclaw/agents/") || lower.contains("/.qclaw/agents/")
            case "Hermes":
                return lower.contains("/.hermes/sessions/") || lower.hasSuffix("/.hermes/gateway_state.json") || lower.contains("hermes-sandbox") || lower.contains("hermes_sandbox")
            default:
                return true
            }
        }
    }

    private func loadCache() {
        let url = URL(fileURLWithPath: SandboxPaths.shared.agentMonitorCachePath)
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        guard cache.version == 2 else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        snapshots = cache.snapshots
        sessions = Array(Self.sanitizedSessions(cache.sessions).prefix(maxCachedSessions))
        networkConnections = cache.networkConnections ?? []
        authorizedRoots = cache.authorizedRoots
        if !cache.scannedRoots.isEmpty {
            scannedRoots = cache.scannedRoots
        }
        lastScanDate = cache.lastScanDate ?? (cache.snapshots.isEmpty ? nil : cache.updatedAt)
        lastFullScanDate = cache.lastFullScanDate ?? cache.lastScanDate
    }

    private func saveCache() {
        let cache = Cache(
            updatedAt: Date(),
            snapshots: snapshots,
            sessions: Array(Self.sanitizedSessions(sessions).prefix(maxCachedSessions)),
            networkConnections: networkConnections,
            authorizedRoots: authorizedRoots,
            scannedRoots: scannedRoots,
            lastScanDate: lastScanDate,
            lastFullScanDate: lastFullScanDate
        )
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: URL(fileURLWithPath: SandboxPaths.shared.agentMonitorCachePath), options: .atomic)
    }
}

private final class AgentOverviewProcessOutputCapture: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var value = Data()

    init(limit: Int) {
        self.limit = limit
    }

    func drain(_ handle: FileHandle) {
        while true {
            let chunk = handle.readData(ofLength: 64 * 1_024)
            if chunk.isEmpty { break }
            lock.lock()
            let available = max(0, limit - value.count)
            if available > 0 { value.append(chunk.prefix(available)) }
            lock.unlock()
        }
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private final class AgentMonitorOverviewScanner {
    private static let maximumUsageFileBytes = 8_000_000
    private static let maximumSessionStoreBytes = 32 * 1_024 * 1_024
    private static let maximumHermesFileBytes = 20_000_000
    private static let maximumSmallMetadataFileBytes = 2 * 1_024 * 1_024
    private static let iso8601Formatter = ISO8601DateFormatter()
    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    fileprivate struct ScanResult {
        let snapshots: [AgentMonitorUsageSnapshot]
        let sessions: [AgentMonitorSessionSnapshot]
        let networkConnections: [AgentNetworkConnection]
        let authorizedRoots: [String]
        let scannedRoots: [String]
    }

    private struct AgentSpec {
        let name: String
        let roots: [String]
        let processKeywords: [String]
        let contextWindow: Int
    }

    private struct ProcessInfo {
        let pid: Int
        let ppid: Int
        let rssKB: Int
        let cpu: Double
        let command: String
    }

    private struct ParsedSession {
        let sessionId: String
        let cwd: String
        let model: String
        let tokens: AgentMonitorTokenBreakdown
        let lastContextTokens: Int
        let contextWindow: Int
        let turnCount: Int
        let currentTask: String
        let status: String
        let toolCount: Int
        let runningToolCount: Int
        let latestActivity: Date?
        let instructionDate: Date?
        let sourcePath: String
    }

    private struct CodexGoalState {
        let threadId: String
        let objective: String
        let status: String
        let updatedAt: Date?
        let rolloutPath: String
        let cwd: String
        let title: String
        let model: String
    }

    private struct ParsedSessionCacheEntry {
        let fileSize: Int
        let modifiedAt: Date?
        let session: ParsedSession
    }

    private struct LatestInstructionCacheEntry {
        let fileSize: Int
        let modifiedAt: Date?
        let instruction: String?
    }

    private let fileManager = FileManager.default
    private let parsedSessionCacheLock = NSLock()
    private var parsedSessionCache: [String: ParsedSessionCacheEntry] = [:]
    private let latestInstructionCacheLock = NSLock()
    private var latestInstructionCache: [String: LatestInstructionCacheEntry] = [:]
    private let discoveryCacheLock = NSLock()
    private var specsCache: [AgentSpec] = []
    private var specsCacheDate: Date = .distantPast
    private var cursorStateDBPathCache: [String] = []
    private var cursorStateDBPathCacheDate: Date = .distantPast
    private var openClawSessionStorePathCache: [String] = []
    private var openClawSessionStorePathCacheDate: Date = .distantPast
    private let discoveryCacheTTL: TimeInterval = 180
    private let processInfoCacheLock = NSLock()
    private var processInfoCache: [Int: ProcessInfo] = [:]
    private var processInfoCacheDate: Date = .distantPast
    private let processInfoCacheTTL: TimeInterval = 45
    private let commandAgentCacheLock = NSLock()
    private var commandAgentCache: [String: String] = [:]
    private var nonAgentCommandCache: Set<String> = []
    private var home: String { SandboxPaths.realHomeDirectory }

    private var specs: [AgentSpec] {
        discoveryCacheLock.lock()
        if !specsCache.isEmpty, Date().timeIntervalSince(specsCacheDate) < discoveryCacheTTL {
            let cached = specsCache
            discoveryCacheLock.unlock()
            return cached
        }
        discoveryCacheLock.unlock()

        let built = buildSpecs()

        discoveryCacheLock.lock()
        specsCache = built
        specsCacheDate = Date()
        discoveryCacheLock.unlock()
        return built
    }

    private func buildSpecs() -> [AgentSpec] {
        var base = [
            AgentSpec(name: "Claude Code", roots: ["~/.claude", "~/.claude/projects", "~/.claude/sessions", "~/.config/claude/projects"], processKeywords: ["claude", "claude-code", "anthropic"], contextWindow: 200_000),
            AgentSpec(name: "Codex", roots: ["~/.codex/sessions", "~/.codex/archived_sessions", "~/.codex/goals_1.sqlite", "~/.codex/state_5.sqlite"], processKeywords: ["codex"], contextWindow: 200_000),
            AgentSpec(name: "OpenCode", roots: ["~/.opencode", "~/.local/share/opencode", "~/.local/share/opencode/opencode.db"], processKeywords: ["opencode"], contextWindow: 200_000),
            AgentSpec(name: "Gemini CLI", roots: ["~/.gemini"], processKeywords: ["gemini"], contextWindow: 1_000_000),
            AgentSpec(name: "Cursor", roots: cursorStateDBPaths(), processKeywords: ["/cursor.app/", "cursor-agent", "cursor agent"], contextWindow: 200_000),
            AgentSpec(name: "OpenClaw", roots: [
                "~/.openclaw/agents/main/sessions/sessions.json",
                "~/.qclaw/agents/main/sessions/sessions.json",
                "~/Library/Application Support/QClaw/openclaw/config/agents/main/sessions/sessions.json"
            ] + openClawSessionStorePaths(), processKeywords: ["openclaw", "open-claw", "qclaw"], contextWindow: 200_000),
            AgentSpec(name: "Hermes", roots: ["~/.hermes", "~/.hermes/sessions", "~/.hermes/gateway_state.json"], processKeywords: ["hermes", "hermes-agent", "hermes_cli"], contextWindow: 200_000),
            AgentSpec(name: "Trae", roots: ["~/.trae", "~/.trae-cn", "~/Library/Application Support/Trae", "~/Library/Application Support/Trae CN"], processKeywords: ["trae", "trae-cn"], contextWindow: 200_000),
            AgentSpec(name: "CodeBuddy", roots: ["~/.codebuddy/projects", "~/Library/Application Support/CodeBuddy", "~/Library/Application Support/CodeBuddy CN"], processKeywords: ["codebuddy", "codebuddy-cn"], contextWindow: 200_000),
            AgentSpec(name: "MiniMax Agent", roots: ["~/.minimax", "~/.minimax/sqlite.db", "~/.minimax/nexus/nexus.db", "~/.minimax-agent", "~/.minimax-agent-cn", "~/Library/Application Support/MiniMax", "~/Library/Application Support/MiniMax Agent"], processKeywords: ["minimax", "mavis"], contextWindow: 512_000)
        ]
        let existingNames = Set(base.map { $0.name.lowercased() })
        let existingRoots = Set(base.flatMap { $0.roots.map(expand) })
        let profileSpecs = AgentIntegrationProfile.allProfiles.compactMap { profile -> AgentSpec? in
            guard !existingNames.contains(profile.displayName.lowercased()) else { return nil }
            let configDir = URL(fileURLWithPath: home)
                .appendingPathComponent(profile.configurationPath)
                .deletingLastPathComponent()
                .path
            guard !existingRoots.contains(configDir) else { return nil }
            let compactName = profile.displayName.lowercased().replacingOccurrences(of: " ", with: "")
            let keywords = Array(Set([profile.executable, profile.id, compactName])).filter { !$0.isEmpty }
            return AgentSpec(name: profile.displayName, roots: [configDir], processKeywords: keywords, contextWindow: 200_000)
        }
        base.append(contentsOf: profileSpecs)
        return base
    }

    fileprivate func scan() -> ScanResult {
        let processInfo = scanProcessInfo()
        let children = childrenMap(processInfo)
        let networkConnections = scanOutboundConnections(processInfo: processInfo)
        let pidToSessionFiles = scanOpenSessionFiles(processInfo: processInfo)
        let portsByPid: [Int: [Int]] = [:]
        let processStats = countAgentProcesses(processInfo)
        let authorizedRoots = authorizedBookmarkRoots()
        let scannedRoots = Array(Set(specs.flatMap { spec in
            effectiveRoots(for: spec, authorizedRoots: authorizedRoots)
                .filter { fileManager.fileExists(atPath: $0) }
        })).sorted { $0.count < $1.count }
        let liveSessions = scanLiveSessions(
            processInfo: processInfo,
            children: children,
            pidToSessionFiles: pidToSessionFiles,
            portsByPid: portsByPid
        )
        let historySessions = scanRecentSessionFiles(
            excluding: Set(liveSessions.map { $0.sourcePath }),
            processInfo: processInfo,
            authorizedRoots: authorizedRoots
        )
        let goalSessions = scanCodexGoalSessions(processInfo: processInfo, children: children)

        let snapshots: [AgentMonitorUsageSnapshot] = specs.compactMap { spec in
            let roots = effectiveRoots(for: spec, authorizedRoots: authorizedRoots)
            var sessionIDs = Set<String>()
            var totalTokens = 0
            var lastContextTokens = 0
            var contextWindow = spec.contextWindow
            var latestActivity: Date?
            var projectPath = ""
            var sourcePath = roots.first ?? ""

            for root in roots where fileManager.fileExists(atPath: root) {
                sourcePath = root
                if root.hasSuffix("/opencode.db") {
                    let summary = summarizeOpenCodeDB(path: root)
                    sessionIDs.formUnion(summary.sessionIds)
                    totalTokens += summary.tokens.total
                    lastContextTokens = max(lastContextTokens, summary.lastContextTokens)
                    if let latest = summary.latestActivity, latestActivity == nil || latest > latestActivity! {
                        latestActivity = latest
                    }
                    if projectPath.isEmpty, let project = summary.project {
                        projectPath = project
                    }
                    continue
                }
                if root.hasSuffix("/sqlite.db"), spec.name == "MiniMax Agent" {
                    let summary = summarizeMiniMaxDB(path: root)
                    sessionIDs.formUnion(summary.sessionIds)
                    totalTokens += summary.tokens.total
                    lastContextTokens = max(lastContextTokens, summary.lastContextTokens)
                    if summary.contextWindow > 0 {
                        contextWindow = summary.contextWindow
                    }
                    if let latest = summary.latestActivity, latestActivity == nil || latest > latestActivity! {
                        latestActivity = latest
                    }
                    if projectPath.isEmpty, let project = summary.project {
                        projectPath = project
                    }
                    continue
                }
                if root.hasSuffix("/nexus.db"), spec.name == "MiniMax Agent" {
                    let summary = summarizeMiniMaxNexusDB(path: root)
                    sessionIDs.formUnion(summary.sessionIds)
                    totalTokens += summary.tokens.total
                    lastContextTokens = max(lastContextTokens, summary.lastContextTokens)
                    if let latest = summary.latestActivity, latestActivity == nil || latest > latestActivity! {
                        latestActivity = latest
                    }
                    if projectPath.isEmpty, let project = summary.project {
                        projectPath = project
                    }
                    continue
                }
                if root.hasSuffix(".vscdb"), spec.name == "Cursor" {
                    let summary = summarizeDatabaseSessions(parseCursorDBSessions(path: root, processInfo: [:]))
                    sessionIDs.formUnion(summary.sessionIds)
                    totalTokens += summary.tokens.total
                    lastContextTokens = max(lastContextTokens, summary.lastContextTokens)
                    if let latest = summary.latestActivity, latestActivity == nil || latest > latestActivity! {
                        latestActivity = latest
                    }
                    if projectPath.isEmpty, let project = summary.project {
                        projectPath = project
                    }
                    continue
                }
                if root.hasSuffix("/sessions.json"), spec.name == "OpenClaw" {
                    let summary = summarizeDatabaseSessions(parseOpenClawSessionStore(path: root, processInfo: [:]))
                    sessionIDs.formUnion(summary.sessionIds)
                    totalTokens += summary.tokens.total
                    lastContextTokens = max(lastContextTokens, summary.lastContextTokens)
                    if let latest = summary.latestActivity, latestActivity == nil || latest > latestActivity! {
                        latestActivity = latest
                    }
                    if projectPath.isEmpty, let project = summary.project {
                        projectPath = project
                    }
                    continue
                }
                guard shouldEnumerateUsageFiles(root: root, spec: spec) else { continue }
                let files = usageFiles(under: root)
                for file in files {
                    sessionIDs.insert(sessionID(for: file, root: root))
                    // JSONSerialization bridges through Foundation objects. Drain
                    // their autorelease storage after every session so a full
                    // multi-provider refresh cannot retain all parser temporaries
                    // until the detached scan task finishes.
                    let usage = autoreleasepool { parseUsage(file: file) }
                    totalTokens += usage.tokens
                    if usage.lastContextTokens > lastContextTokens {
                        lastContextTokens = usage.lastContextTokens
                    }
                    if usage.contextWindow > 0 {
                        contextWindow = usage.contextWindow
                    }
                    if let latest = usage.latest, latestActivity == nil || latest > latestActivity! {
                        latestActivity = latest
                    }
                    if projectPath.isEmpty, let project = usage.project {
                        projectPath = project
                    }
                }
            }

            let processCount = processStats[spec.name] ?? 0
            let portCount = 0
            guard !sessionIDs.isEmpty || totalTokens > 0 || processCount > 0 || portCount > 0 else { return nil }

            let contextPercent = contextWindow > 0 ? min(Double(lastContextTokens) / Double(contextWindow), 1) : 0
            return AgentMonitorUsageSnapshot(
                id: spec.name,
                agentName: spec.name,
                sessionCount: sessionIDs.count,
                totalTokens: totalTokens,
                contextPercent: contextPercent,
                processCount: processCount,
                portCount: portCount,
                latestActivity: latestActivity,
                projectPath: projectPath,
                sourcePath: sourcePath
            )
        }

        let activeLiveSessions = uniqueSessions(goalSessions + liveSessions + historySessions)
            .sorted { lhs, rhs in
                let left = lhs.latestActivity ?? .distantPast
                let right = rhs.latestActivity ?? .distantPast
                if left == right { return lhs.agentName < rhs.agentName }
                return left > right
            }
        return ScanResult(
            snapshots: snapshots,
            sessions: Array(activeLiveSessions.prefix(240)),
            networkConnections: networkConnections,
            authorizedRoots: authorizedRoots,
            scannedRoots: scannedRoots
        )
    }

    fileprivate func realtimeScan(cachedRoots: [String], retainedActiveSources: [String]) -> ScanResult {
        let processInfo = scanProcessInfo()
        let children = childrenMap(processInfo)
        let networkConnections = scanOutboundConnections(processInfo: processInfo)
        let pidToSessionFiles = scanOpenSessionFiles(processInfo: processInfo)
        let authorizedRoots = authorizedBookmarkRoots()
        let fixedRoots = Array(Set(cachedRoots + authorizedRoots + specs.flatMap { spec in
            effectiveRoots(for: spec, authorizedRoots: authorizedRoots)
        })).filter { fileManager.fileExists(atPath: $0) }
        let foregroundRoots = fixedRoots.filter(isForegroundSessionRoot)
        var liveSessions = scanCodexGoalSessions(processInfo: processInfo, children: children)
        let handledSources = Set(liveSessions.map(\.sourcePath))
            .union(pidToSessionFiles.values.flatMap { $0 })
        liveSessions.append(contentsOf: scanRetainedActiveSessionFiles(
            paths: retainedActiveSources.filter { !handledSources.contains($0) },
            processInfo: processInfo,
            children: children
        ))
        liveSessions.append(contentsOf: scanLiveSessions(
            processInfo: processInfo,
            children: children,
            pidToSessionFiles: pidToSessionFiles,
            portsByPid: [:]
        ))
        let seen = Set(liveSessions.map { "\($0.agentName)|\($0.sessionId)|\($0.sourcePath)" })
        let recentSessions = scanForegroundSessionFiles(
            roots: foregroundRoots,
            excluding: seen,
            processInfo: processInfo,
            children: children
        )
        liveSessions.append(contentsOf: recentSessions)
        liveSessions.append(contentsOf: scanPriorityHistorySessions(
            roots: fixedRoots,
            processInfo: processInfo,
            children: children
        ))
        let runningAgentNames = Set(processInfo.values.compactMap { matchingSpecName($0.command) })
        let hasCursorProcess = runningAgentNames.contains("Cursor")
        var parsedCursorDatabaseCount = 0
        for root in fixedRoots {
            if root.hasSuffix("/opencode.db") {
                guard runningAgentNames.contains("OpenCode") || runningAgentNames.contains("MiniMax Agent") else { continue }
                liveSessions.append(contentsOf: parseOpenCodeDBSessions(path: root, processInfo: processInfo))
            } else if root.hasSuffix("/sqlite.db"), root.lowercased().contains("minimax") {
                guard runningAgentNames.contains("MiniMax Agent") else { continue }
                liveSessions.append(contentsOf: parseMiniMaxDBSessions(path: root, processInfo: processInfo))
            } else if root.hasSuffix("/nexus.db"), root.lowercased().contains("minimax") {
                guard runningAgentNames.contains("MiniMax Agent") else { continue }
                liveSessions.append(contentsOf: parseMiniMaxNexusDBSessions(path: root, processInfo: processInfo))
            } else if root.hasSuffix(".vscdb"), root.lowercased().contains("cursor") {
                guard hasCursorProcess, parsedCursorDatabaseCount < 6 else { continue }
                parsedCursorDatabaseCount += 1
                liveSessions.append(contentsOf: parseCursorDBSessions(path: root, processInfo: processInfo, rowLimit: 800))
            } else if root.hasSuffix("/sessions.json"), root.lowercased().contains("openclaw") || root.lowercased().contains("qclaw") {
                guard runningAgentNames.contains("OpenClaw") else { continue }
                liveSessions.append(contentsOf: parseOpenClawSessionStore(path: root, processInfo: processInfo))
            }
        }
        let uniqueRows = uniqueSessions(liveSessions)
        let activeSessions = uniqueRows.filter { isRealtimeActiveSession($0) }
        let priorityAgents: Set<String> = ["Claude Code", "Cursor", "OpenClaw", "Hermes", "OpenCode", "MiniMax Agent"]
        let priorityHistory = Dictionary(grouping: uniqueRows.filter {
            priorityAgents.contains($0.agentName) && !isRealtimeActiveSession($0)
        }, by: \.agentName).values.flatMap { rows in
            rows.sorted { ($0.latestActivity ?? .distantPast) > ($1.latestActivity ?? .distantPast) }.prefix(20)
        }
        let selectedSessions = uniqueSessions(activeSessions + priorityHistory)
            .sorted {
                let left = $0.latestActivity ?? .distantPast
                let right = $1.latestActivity ?? .distantPast
                if left == right { return $0.agentName < $1.agentName }
                return left > right
            }
        return ScanResult(
            snapshots: [],
            sessions: Array(selectedSessions.prefix(120)),
            networkConnections: networkConnections,
            authorizedRoots: authorizedRoots,
            scannedRoots: fixedRoots.sorted { $0.count < $1.count }
        )
    }

    fileprivate func scanSession(_ session: AgentMonitorSessionSnapshot) -> AgentMonitorSessionSnapshot? {
        let processInfo = scanProcessInfo()
        let children = childrenMap(processInfo)
        let sourcePath = session.sourcePath
        let lower = sourcePath.lowercased()
        let rows: [AgentMonitorSessionSnapshot]
        if lower.hasSuffix("/opencode.db") {
            rows = parseOpenCodeDBSessions(path: sourcePath, processInfo: processInfo)
        } else if lower.hasSuffix("/sqlite.db"), lower.contains("minimax") {
            rows = parseMiniMaxDBSessions(path: sourcePath, processInfo: processInfo)
        } else if lower.hasSuffix("/nexus.db"), lower.contains("minimax") {
            rows = parseMiniMaxNexusDBSessions(path: sourcePath, processInfo: processInfo)
        } else if lower.hasSuffix(".vscdb"), lower.contains("cursor") {
            rows = parseCursorDBSessions(path: sourcePath, processInfo: processInfo)
        } else if lower.hasSuffix("/sessions.json"), lower.contains("openclaw") || lower.contains("qclaw") {
            rows = parseOpenClawSessionStore(path: sourcePath, processInfo: processInfo)
        } else if ["json", "jsonl", "log"].contains(URL(fileURLWithPath: sourcePath).pathExtension.lowercased()),
                  fileManager.fileExists(atPath: sourcePath),
                  let parsed = parseSessionFile(URL(fileURLWithPath: sourcePath)) {
            let agentName = resolvedAgentName(
                specName: specForSessionPath(sourcePath)?.name ?? session.agentName,
                parsed: parsed
            )
            return snapshotFromParsedSession(
                parsed,
                agentName: agentName,
                processInfo: processInfo,
                children: children,
                idSuffix: "focused"
            )
        } else {
            return nil
        }
        return rows.first { $0.sessionId == session.sessionId }
            ?? rows.first { $0.id == session.id }
            ?? rows.first { $0.agentName == session.agentName && $0.sourcePath == session.sourcePath }
    }

    private func isRealtimeActiveSession(_ session: AgentMonitorSessionSnapshot) -> Bool {
        ["Thinking", "Executing", "Waiting", "Paused"].contains(session.status) ||
        (!session.currentTask.isEmpty && session.status != "History" && session.status != "Done")
    }

    private func isParsedSessionActive(_ session: ParsedSession) -> Bool {
        ["Thinking", "Executing", "Waiting", "Paused"].contains(session.status) ||
        (!session.currentTask.isEmpty && session.status != "History" && session.status != "Done")
    }

    private func uniqueSessions(_ sessions: [AgentMonitorSessionSnapshot]) -> [AgentMonitorSessionSnapshot] {
        var seen: Set<String> = []
        return sessions.filter {
            seen.insert("\($0.agentName)|\($0.sessionId)|\($0.sourcePath)").inserted
        }
    }

    private func scanRecentSessionFiles(excluding liveSources: Set<String>, processInfo: [Int: ProcessInfo], authorizedRoots: [String]) -> [AgentMonitorSessionSnapshot] {
        var parsedRows: [(spec: AgentSpec, parsed: ParsedSession)] = []
        var databaseRows: [AgentMonitorSessionSnapshot] = []
        for spec in specs {
            for root in effectiveRoots(for: spec, authorizedRoots: authorizedRoots) where fileManager.fileExists(atPath: root) {
                if root.hasSuffix("/opencode.db") {
                    databaseRows.append(contentsOf: parseOpenCodeDBSessions(path: root, processInfo: processInfo))
                    continue
                }
                if root.hasSuffix("/sqlite.db"), spec.name == "MiniMax Agent" {
                    databaseRows.append(contentsOf: parseMiniMaxDBSessions(path: root, processInfo: processInfo))
                    continue
                }
                if root.hasSuffix("/nexus.db"), spec.name == "MiniMax Agent" {
                    databaseRows.append(contentsOf: parseMiniMaxNexusDBSessions(path: root, processInfo: processInfo))
                    continue
                }
                if root.hasSuffix(".vscdb"), spec.name == "Cursor" {
                    databaseRows.append(contentsOf: parseCursorDBSessions(path: root, processInfo: processInfo))
                    continue
                }
                if root.hasSuffix("/sessions.json"), spec.name == "OpenClaw" {
                    databaseRows.append(contentsOf: parseOpenClawSessionStore(path: root, processInfo: processInfo))
                    continue
                }
                guard shouldEnumerateUsageFiles(root: root, spec: spec) else { continue }
                let candidates = usageFiles(under: root)
                    .filter { !liveSources.contains($0.path) }
                    .sorted {
                        let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                        let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                        return left > right
                    }
                    .prefix(160)
                for file in candidates {
                    guard let parsed = parseSessionFile(file) else { continue }
                    parsedRows.append((spec, parsed))
                }
            }
        }

        let liveProcessByAgent = Dictionary(grouping: processInfo.values, by: { matchingSpecName($0.command) ?? "" })
        let sortedParsedRows = parsedRows.sorted {
                let left = $0.parsed.latestActivity ?? .distantPast
                let right = $1.parsed.latestActivity ?? .distantPast
                return left > right
            }
        var selectedSourcePaths = Set<String>()
        let prioritizedRows = sortedParsedRows.filter {
            isParsedSessionActive($0.parsed) && selectedSourcePaths.insert($0.parsed.sourcePath).inserted
        } + sortedParsedRows.filter {
            selectedSourcePaths.insert($0.parsed.sourcePath).inserted
        }.prefix(60)
        let fileRows = prioritizedRows
            .prefix(120)
            .map { item in
                let agentName = resolvedAgentName(specName: item.spec.name, parsed: item.parsed)
                let process = liveProcessByAgent[agentName]?.first
                    ?? (agentName == "Claude Code" ? processInfo.values.first { $0.command.lowercased().contains("/claude.app/") } : nil)
                let pid = process?.pid
                let contextPercent = item.parsed.contextWindow > 0 ? min(Double(item.parsed.lastContextTokens) / Double(item.parsed.contextWindow), 1) : 0
                let projectName = lastPathSegment(item.parsed.cwd).isEmpty ? agentName : lastPathSegment(item.parsed.cwd)
                let recentWindow: TimeInterval = agentName == "Claude Code" ? 10 * 60 : 180
                let isRecent = item.parsed.latestActivity.map { abs(Date().timeIntervalSince($0)) < recentWindow } == true
                let status = isRecent ? liveStatus(
                    isAlive: process != nil,
                    process: process,
                    childPids: [],
                    processInfo: processInfo,
                    currentTask: item.parsed.currentTask,
                    parsedStatus: item.parsed.status
                ) : item.parsed.status
                return AgentMonitorSessionSnapshot(
                    id: "\(agentName)-\(item.parsed.sessionId)-history-\(item.parsed.sourcePath)",
                    agentName: agentName,
                    pid: pid,
                    sessionId: item.parsed.sessionId,
                    status: status,
                    projectName: projectName,
                    projectPath: item.parsed.cwd,
                    model: item.parsed.model.isEmpty ? "—" : item.parsed.model,
                    tokens: item.parsed.tokens,
                    contextPercent: contextPercent,
                    contextWindow: item.parsed.contextWindow,
                    turnCount: item.parsed.turnCount,
                    currentTask: item.parsed.currentTask.isEmpty ? "History session record" : item.parsed.currentTask,
                    toolCount: item.parsed.toolCount,
                    runningToolCount: item.parsed.runningToolCount,
                    childCount: 0,
                    ports: [],
                    memoryMB: process.map { max($0.rssKB / 1024, 1) },
                    latestActivity: item.parsed.latestActivity,
                    instructionDate: item.parsed.instructionDate ?? item.parsed.latestActivity,
                    sourcePath: item.parsed.sourcePath
                )
            }
        return Array((databaseRows + fileRows)
            .sorted {
                let left = $0.latestActivity ?? .distantPast
                let right = $1.latestActivity ?? .distantPast
                if left == right { return $0.agentName < $1.agentName }
                return left > right
            }
            .prefix(120))
    }

    private func effectiveRoots(for spec: AgentSpec, authorizedRoots: [String]) -> [String] {
        var roots = Set(spec.roots.map(expand))
        let authorized = authorizedRoots.map(expand)
        for root in authorized {
            if root == home || root.hasSuffix("/\(NSUserName())") {
                roots.formUnion(homeAgentRoots(for: spec))
            } else {
                roots.formUnion(agentRoots(inside: root, for: spec))
            }
        }
        if spec.name == "Claude Code" {
            roots.formUnion(discoverClaudeProfileRoots().flatMap { [$0, $0 + "/sessions", $0 + "/projects"] })
        }
        if spec.name == "OpenCode" {
            roots.insert(home + "/.local/share/opencode/opencode.db")
        }
        if spec.name == "Cursor" {
            roots.formUnion(cursorStateDBPaths())
        }
        if spec.name == "OpenClaw" {
            roots.insert(home + "/.openclaw/agents/main/sessions/sessions.json")
            roots.insert(home + "/.qclaw/agents/main/sessions/sessions.json")
            roots.formUnion(openClawSessionStorePaths())
        }
        if spec.name == "MiniMax Agent" {
            roots.insert(home + "/.minimax/sqlite.db")
            roots.insert(home + "/.minimax/nexus/nexus.db")
            roots.insert(home + "/.minimax-agent-cn")
        }
        if spec.name == "Codex" {
            roots.insert(home + "/.codex/goals_1.sqlite")
            roots.insert(home + "/.codex/state_5.sqlite")
        }
        return roots
            .filter { !$0.isEmpty }
            .sorted { $0.count < $1.count }
    }

    private func homeAgentRoots(for spec: AgentSpec) -> [String] {
        switch spec.name {
        case "Claude Code":
            return discoverClaudeProfileRoots().flatMap { [$0, $0 + "/sessions", $0 + "/projects"] }
        case "Codex":
            return [home + "/.codex/sessions", home + "/.codex/archived_sessions", home + "/.codex/goals_1.sqlite", home + "/.codex/state_5.sqlite"]
        case "OpenCode":
            return [home + "/.opencode", home + "/.local/share/opencode", home + "/.local/share/opencode/opencode.db"]
        case "Cursor":
            return cursorStateDBPaths()
        case "OpenClaw":
            return [
                home + "/.openclaw/agents/main/sessions/sessions.json",
                home + "/.qclaw/agents/main/sessions/sessions.json"
            ] + openClawSessionStorePaths()
        case "Hermes":
            return [home + "/.hermes", home + "/.hermes/sessions", home + "/.hermes/gateway_state.json"]
        case "MiniMax Agent":
            return [home + "/.minimax", home + "/.minimax/sqlite.db", home + "/.minimax/nexus/nexus.db", home + "/.minimax/sessions", home + "/.minimax/logs", home + "/.minimax-agent", home + "/.minimax-agent-cn"]
        default:
            return spec.roots.map(expand).flatMap(genericAgentRoots)
        }
    }

    private func agentRoots(inside root: String, for spec: AgentSpec) -> [String] {
        let lower = root.lowercased()
        switch spec.name {
        case "Claude Code":
            if isClaudeProfileRoot(root) { return [root, root + "/sessions", root + "/projects"] }
            if lower.hasSuffix("/.claude") || lower.contains("/.claude-") { return [root] }
        case "Codex":
            if lower.hasSuffix("/.codex") { return [root + "/sessions", root + "/archived_sessions"] }
            if lower.contains("/.codex/sessions") { return [root] }
        case "OpenCode":
            if lower.hasSuffix("/opencode.db") { return [root] }
            if lower.hasSuffix("/opencode") || lower.hasSuffix("/.opencode") { return [root, root + "/opencode.db"] }
        case "Cursor":
            if lower.hasSuffix(".vscdb") { return [root] }
            if lower.contains("cursor") { return cursorStateDBPaths().filter { $0.hasPrefix(root) } }
        case "OpenClaw":
            if lower.hasSuffix("/sessions.json") { return [root] }
            if lower.contains("openclaw") || lower.contains("qclaw") { return openClawSessionStorePaths().filter { $0.hasPrefix(root) } }
        case "Hermes":
            if lower.hasSuffix("/gateway_state.json") { return [root] }
            if lower.contains("/.hermes") || lower.contains("hermes") { return [root, root + "/sessions", root + "/gateway_state.json"] }
        case "MiniMax Agent":
            if lower.hasSuffix("/sqlite.db") || lower.hasSuffix("/nexus.db") { return [root] }
            if lower.hasSuffix("/.minimax") || lower.contains("minimax") || lower.contains("mavis") {
                return [root, root + "/sqlite.db", root + "/nexus/nexus.db", root + "/sessions", root + "/logs"]
            }
        default:
            guard isRootLikelyForSpec(root, spec: spec) else { return [] }
            return genericAgentRoots(root)
        }
        return []
    }

    private func isRootLikelyForSpec(_ root: String, spec: AgentSpec) -> Bool {
        let lower = root.lowercased()
        let compactName = spec.name.lowercased().replacingOccurrences(of: " ", with: "")
        if lower.contains(compactName) { return true }
        if spec.processKeywords.contains(where: { lower.contains($0.lowercased()) }) { return true }
        let last = URL(fileURLWithPath: lower).lastPathComponent
        return last.hasPrefix(".") && spec.processKeywords.contains { keyword in
            last.contains(keyword.lowercased())
        }
    }

    private func genericAgentRoots(_ root: String) -> [String] {
        [
            root,
            root + "/sessions",
            root + "/projects",
            root + "/conversations",
            root + "/transcripts",
            root + "/history",
            root + "/chat_history",
            root + "/logs",
            root + "/.sessions"
        ]
    }

    private func discoverClaudeProfileRoots() -> [String] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: home) else {
            return [home + "/.claude"]
        }
        let roots = entries
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .map { home + "/" + $0 }
            .filter(isClaudeProfileRoot)
        return roots.isEmpty ? [home + "/.claude"] : roots
    }

    private func cursorStateDBPaths() -> [String] {
        discoveryCacheLock.lock()
        if !cursorStateDBPathCache.isEmpty,
           Date().timeIntervalSince(cursorStateDBPathCacheDate) < discoveryCacheTTL {
            let cached = cursorStateDBPathCache
            discoveryCacheLock.unlock()
            return cached
        }
        discoveryCacheLock.unlock()

        let bases = [
            home + "/Library/Application Support/Cursor/User",
            home + "/.cursor"
        ]
        var paths = Set<String>()
        for base in bases {
            let globalDB = base + "/globalStorage/state.vscdb"
            if fileManager.fileExists(atPath: globalDB) { paths.insert(globalDB) }
            let workspaceStorage = base + "/workspaceStorage"
            guard let workspaces = try? fileManager.contentsOfDirectory(atPath: workspaceStorage) else { continue }
            for workspace in workspaces.prefix(80) {
                let db = workspaceStorage + "/" + workspace + "/state.vscdb"
                if fileManager.fileExists(atPath: db) { paths.insert(db) }
            }
        }
        let sorted = paths.sorted()
        discoveryCacheLock.lock()
        cursorStateDBPathCache = sorted
        cursorStateDBPathCacheDate = Date()
        discoveryCacheLock.unlock()
        return sorted
    }

    private func openClawSessionStorePaths() -> [String] {
        discoveryCacheLock.lock()
        if !openClawSessionStorePathCache.isEmpty,
           Date().timeIntervalSince(openClawSessionStorePathCacheDate) < discoveryCacheTTL {
            let cached = openClawSessionStorePathCache
            discoveryCacheLock.unlock()
            return cached
        }
        discoveryCacheLock.unlock()

        let agentRoots = [
            home + "/.openclaw/agents",
            home + "/.qclaw/agents",
            home + "/Library/Application Support/OpenClaw/agents",
            home + "/Library/Application Support/QClaw/openclaw/config/agents"
        ]
        var paths = Set<String>()
        for root in agentRoots {
            guard let agents = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            for agent in agents.prefix(100) {
                let store = root + "/" + agent + "/sessions/sessions.json"
                if fileManager.fileExists(atPath: store) { paths.insert(store) }
            }
        }
        let sorted = paths.sorted()
        discoveryCacheLock.lock()
        openClawSessionStorePathCache = sorted
        openClawSessionStorePathCacheDate = Date()
        discoveryCacheLock.unlock()
        return sorted
    }

    private func isClaudeProfileRoot(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: path + "/sessions", isDirectory: &isDir) && isDir.boolValue &&
            fileManager.fileExists(atPath: path + "/projects", isDirectory: &isDir) && isDir.boolValue
    }

    private func summarizeOpenCodeDB(path: String) -> (sessionIds: Set<String>, tokens: AgentMonitorTokenBreakdown, lastContextTokens: Int, latestActivity: Date?, project: String?) {
        let sessions = parseOpenCodeDBSessions(path: path, processInfo: [:])
        return summarizeDatabaseSessions(sessions)
    }

    private func summarizeMiniMaxDB(path: String) -> (sessionIds: Set<String>, tokens: AgentMonitorTokenBreakdown, lastContextTokens: Int, contextWindow: Int, latestActivity: Date?, project: String?) {
        let sessions = parseMiniMaxDBSessions(path: path, processInfo: [:])
        let summary = summarizeDatabaseSessions(sessions)
        return (summary.sessionIds, summary.tokens, summary.lastContextTokens, 512_000, summary.latestActivity, summary.project)
    }

    private func summarizeMiniMaxNexusDB(path: String) -> (sessionIds: Set<String>, tokens: AgentMonitorTokenBreakdown, lastContextTokens: Int, latestActivity: Date?, project: String?) {
        let sessions = parseMiniMaxNexusDBSessions(path: path, processInfo: [:])
        return summarizeDatabaseSessions(sessions)
    }

    private func summarizeDatabaseSessions(_ sessions: [AgentMonitorSessionSnapshot]) -> (sessionIds: Set<String>, tokens: AgentMonitorTokenBreakdown, lastContextTokens: Int, latestActivity: Date?, project: String?) {
        var ids = Set<String>()
        var input = 0
        var output = 0
        var cache = 0
        var lastContextTokens = 0
        var latest: Date?
        var project: String?
        for session in sessions {
            ids.insert(session.sessionId)
            input += session.tokens.input
            output += session.tokens.output
            cache += session.tokens.cacheRead
            lastContextTokens = max(lastContextTokens, session.tokens.input + session.tokens.cacheRead)
            if let activity = session.latestActivity, latest == nil || activity > latest! {
                latest = activity
                project = session.projectPath
            }
        }
        return (ids, AgentMonitorTokenBreakdown(input: input, output: output, cacheRead: cache), lastContextTokens, latest, project)
    }

    private func usageFiles(under root: String) -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            return []
        }
        var files: [URL] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 2500 { break }
            let name = url.lastPathComponent.lowercased()
            if ["node_modules", ".git", "cache", "caches", "deriveddata", "tmp", "logs", "log", "telemetry", "plugins", ".builtin-skills"].contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let ext = url.pathExtension.lowercased()
            if ext == "jsonl" || ext == "json" || ext == "log" {
                files.append(url)
                if files.count >= 160 { break }
            }
        }
        return files
    }

    private func shouldEnumerateUsageFiles(root: String, spec: AgentSpec) -> Bool {
        let lower = root.lowercased()
        if spec.name == "OpenCode" {
            return false
        }
        if spec.name == "MiniMax Agent" {
            return false
        }
        if ["OpenClaw", "QClaw", "EasyClaw", "AutoClaw"].contains(spec.name) {
            return false
        }
        if lower.contains("/logs") || lower.hasSuffix("/log") || lower.contains("/telemetry") {
            return false
        }
        return true
    }

    private func parseUsage(file: URL) -> (tokens: Int, lastContextTokens: Int, contextWindow: Int, latest: Date?, project: String?) {
        guard let data = boundedData(
            contentsOf: file,
            maximumBytes: Self.maximumUsageFileBytes
        ) else {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            return (0, 0, 0, modified, nil)
        }
        let text = String(decoding: data, as: UTF8.self)
        var tokens = 0
        var previousTotal: Int?
        var lastContextTokens = 0
        var contextWindow = 0
        var latest: Date?
        var project: String?

        for line in text.split(whereSeparator: \.isNewline).prefix(20_000) {
            autoreleasepool {
                guard let lineData = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { return }

                if let timestamp = date(from: object) {
                    latest = maxDate(latest, timestamp)
                }
                if project == nil {
                    project = stringValue(object, keys: ["cwd", "project_path", "workspace"])
                        ?? stringValue(object["payload"] as? [String: Any], keys: ["cwd", "project_path", "workspace"])
                }
                if let payload = object["payload"] as? [String: Any],
                   let info = payload["info"] as? [String: Any] {
                    if let last = info["last_token_usage"] as? [String: Any] {
                        lastContextTokens = intKeys(last, ["input_tokens", "prompt_tokens"])
                    }
                    if let cw = intValue(info["model_context_window"]) {
                        contextWindow = cw
                    }
                }
                if let usage = usageTotal(from: object) {
                    if let previousTotal, usage >= previousTotal {
                        tokens += max(usage - previousTotal, 0)
                    } else {
                        tokens += usage
                    }
                    previousTotal = usage
                }
            }
        }

        if latest == nil {
            latest = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        }
        return (tokens, lastContextTokens, contextWindow, latest, project)
    }

    private func usageTotal(from object: [String: Any]) -> Int? {
        let candidates: [Any?] = [
            nestedValue(object, path: ["payload", "info", "total_token_usage"]),
            nestedValue(object, path: ["payload", "info", "last_token_usage"]),
            nestedValue(object, path: ["total_token_usage"]),
            nestedValue(object, path: ["last_token_usage"]),
            nestedValue(object, path: ["usage"]),
            nestedValue(object, path: ["message", "usage"])
        ]
        for candidate in candidates {
            if let intValue = candidate as? Int { return intValue }
            if let dict = candidate as? [String: Any] {
                let total = intKeys(dict, ["total_tokens", "total"])
                if total > 0 { return total }
                let input = intKeys(dict, ["input_tokens", "prompt_tokens"])
                let output = intKeys(dict, ["output_tokens", "completion_tokens"])
                let cache = intKeys(dict, ["cache_creation_input_tokens", "cache_read_input_tokens", "cached_tokens", "reasoning_tokens"])
                let sum = input + output + cache
                if sum > 0 { return sum }
            }
        }
        return nil
    }

    private func scanCodexGoalSessions(
        processInfo: [Int: ProcessInfo],
        children: [Int: [Int]]
    ) -> [AgentMonitorSessionSnapshot] {
        let goalsPath = home + "/.codex/goals_1.sqlite"
        let statePath = home + "/.codex/state_5.sqlite"
        guard fileManager.isReadableFile(atPath: goalsPath) else { return [] }

        var goalsDB: OpaquePointer?
        guard sqlite3_open_v2(goalsPath, &goalsDB, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(goalsDB) }

        var stateDB: OpaquePointer?
        if sqlite3_open_v2(statePath, &stateDB, SQLITE_OPEN_READONLY, nil) != SQLITE_OK {
            sqlite3_close(stateDB)
            stateDB = nil
        }
        defer {
            if stateDB != nil { sqlite3_close(stateDB) }
        }

        let goalSQL = """
        SELECT thread_id, objective, status, updated_at_ms
        FROM thread_goals
        WHERE lower(status) != 'complete'
        ORDER BY updated_at_ms DESC;
        """
        var goalStmt: OpaquePointer?
        guard sqlite3_prepare_v2(goalsDB, goalSQL, -1, &goalStmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(goalStmt) }

        var threadStmt: OpaquePointer?
        if let stateDB {
            sqlite3_prepare_v2(
                stateDB,
                "SELECT rollout_path, cwd, title, COALESCE(model, '') FROM threads WHERE id = ? LIMIT 1;",
                -1,
                &threadStmt,
                nil
            )
        }
        defer {
            if threadStmt != nil { sqlite3_finalize(threadStmt) }
        }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        var goals: [CodexGoalState] = []
        while sqlite3_step(goalStmt) == SQLITE_ROW {
            let threadId = sqliteText(goalStmt, 0)
            guard !threadId.isEmpty else { continue }
            var rolloutPath = ""
            var cwd = ""
            var title = ""
            var model = ""
            if let threadStmt {
                sqlite3_reset(threadStmt)
                sqlite3_clear_bindings(threadStmt)
                sqlite3_bind_text(threadStmt, 1, threadId, -1, transient)
                if sqlite3_step(threadStmt) == SQLITE_ROW {
                    rolloutPath = sqliteText(threadStmt, 0)
                    cwd = sqliteText(threadStmt, 1)
                    title = sqliteText(threadStmt, 2)
                    model = sqliteText(threadStmt, 3)
                }
            }
            goals.append(CodexGoalState(
                threadId: threadId,
                objective: sqliteText(goalStmt, 1),
                status: sqliteText(goalStmt, 2),
                updatedAt: dateFromMilliseconds(sqlite3_column_int64(goalStmt, 3)),
                rolloutPath: rolloutPath,
                cwd: cwd,
                title: title,
                model: model
            ))
        }

        let codexProcesses = processInfo.values.filter { matchingSpecName($0.command) == "Codex" }
        let preferredProcess = codexProcesses.first {
            $0.command.localizedCaseInsensitiveContains("codex app-server")
        } ?? codexProcesses.first
        return goals.map { goal in
            let parsed = goal.rolloutPath.isEmpty ? nil : parseSessionFile(URL(fileURLWithPath: goal.rolloutPath))
            let isActive = goal.status.lowercased() == "active"
            let status = isActive ? "Executing" : "Paused"
            let process = isActive ? preferredProcess : nil
            let childPids = process.map { descendants(of: $0.pid, children: children) } ?? []
            let contextWindow = parsed?.contextWindow ?? 200_000
            let contextPercent = contextWindow > 0
                ? min(Double(parsed?.lastContextTokens ?? 0) / Double(contextWindow), 1)
                : 0
            let latest = [parsed?.latestActivity, goal.updatedAt].compactMap { $0 }.max()
            let currentTask = normalizedInstruction(goal.objective)
                ?? (parsed?.currentTask.isEmpty == false ? parsed!.currentTask : nil)
                ?? normalizedInstruction(goal.title)
                ?? "Codex goal"
            return AgentMonitorSessionSnapshot(
                id: "Codex-\(goal.threadId)-goal",
                agentName: "Codex",
                pid: process?.pid,
                sessionId: goal.threadId,
                status: status,
                projectName: lastPathSegment(parsed?.cwd ?? goal.cwd).isEmpty ? "Codex" : lastPathSegment(parsed?.cwd ?? goal.cwd),
                projectPath: parsed?.cwd.isEmpty == false ? parsed!.cwd : goal.cwd,
                model: parsed?.model.isEmpty == false ? parsed!.model : (goal.model.isEmpty ? "—" : goal.model),
                tokens: parsed?.tokens ?? AgentMonitorTokenBreakdown(input: 0, output: 0, cacheRead: 0),
                contextPercent: contextPercent,
                contextWindow: contextWindow,
                turnCount: parsed?.turnCount ?? 0,
                currentTask: currentTask,
                toolCount: parsed?.toolCount ?? 0,
                runningToolCount: isActive ? max(parsed?.runningToolCount ?? 0, 1) : 0,
                childCount: childPids.count,
                ports: [],
                memoryMB: process.map { max($0.rssKB / 1024, 1) },
                latestActivity: latest,
                instructionDate: parsed?.instructionDate ?? latest,
                sourcePath: goal.rolloutPath.isEmpty ? goalsPath : goal.rolloutPath
            )
        }
    }

    private func parseOpenCodeDBSessions(path: String, processInfo: [Int: ProcessInfo]) -> [AgentMonitorSessionSnapshot] {
        guard fileManager.fileExists(atPath: path), fileManager.isReadableFile(atPath: path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
          s.id,
          COALESCE(s.title, ''),
          COALESCE(s.directory, ''),
          COALESCE(s.version, ''),
          COALESCE(s.time_created, 0),
          COALESCE(s.time_updated, 0),
          COALESCE(p.name, ''),
          COUNT(m.id),
          COALESCE(SUM(json_extract(m.data, '$.tokens.input')), 0),
          COALESCE(SUM(json_extract(m.data, '$.tokens.output')), 0),
          COALESCE(SUM(json_extract(m.data, '$.tokens.cache.read')), 0),
          COALESCE((
            SELECT json_extract(m2.data, '$.modelID')
            FROM message m2
            WHERE m2.session_id = s.id AND json_extract(m2.data, '$.role') = 'assistant'
            ORDER BY m2.time_created DESC
            LIMIT 1
          ), ''),
          COALESCE((
            SELECT SUBSTR(json_extract(pu.data, '$.text'), 1, 4096)
            FROM message mu
            JOIN part pu ON pu.message_id = mu.id
            WHERE mu.session_id = s.id
              AND lower(COALESCE(json_extract(mu.data, '$.role'), '')) = 'user'
              AND lower(COALESCE(json_extract(pu.data, '$.type'), '')) IN ('text', 'input_text')
            ORDER BY COALESCE(pu.time_created, mu.time_created) DESC, pu.id DESC
            LIMIT 1
          ), '')
        FROM session s
        LEFT JOIN project p ON s.project_id = p.id
        LEFT JOIN message m ON m.session_id = s.id AND json_extract(m.data, '$.role') = 'assistant'
        GROUP BY s.id
        ORDER BY s.time_updated DESC
        LIMIT 120;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let openCodeLikeProcesses = processInfo.values.filter {
            let lower = $0.command.lowercased()
            return matchingSpecName($0.command) == "OpenCode" ||
                lower.contains("opencode") ||
                lower.contains("open-code")
        }
        let miniMaxProcesses = processInfo.values.filter { matchingSpecName($0.command) == "MiniMax Agent" }
        let liveByCwd = Dictionary(grouping: openCodeLikeProcesses + miniMaxProcesses, by: { processCwd(pid: $0.pid) ?? "" })
        let fallbackMiniMaxProcess = miniMaxProcesses.first {
            $0.command.localizedCaseInsensitiveContains("opencode serve")
        } ?? miniMaxProcesses.first {
            $0.command.localizedCaseInsensitiveContains("daemon.js")
        } ?? miniMaxProcesses.first
        var rows: [AgentMonitorSessionSnapshot] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sessionId = sqliteText(stmt, 0)
            guard !sessionId.isEmpty else { continue }
            let title = sqliteText(stmt, 1)
            let directory = sqliteText(stmt, 2)
            let updatedMs = sqlite3_column_int64(stmt, 5)
            let projectName = sqliteText(stmt, 6)
            let turns = Int(sqlite3_column_int64(stmt, 7))
            let input = Int(sqlite3_column_int64(stmt, 8))
            let output = Int(sqlite3_column_int64(stmt, 9))
            let cache = Int(sqlite3_column_int64(stmt, 10))
            let model = sqliteText(stmt, 11)
            let latestInstruction = sqliteText(stmt, 12)
            let currentTask = normalizedInstruction(latestInstruction)
                ?? normalizedInstruction(title)
                ?? "OpenCode session"
            let latest = dateFromMilliseconds(updatedMs)
            let hostedByMiniMax = isMiniMaxHostedOpenCodeSession(directory: directory, projectName: projectName)
            let proc = liveByCwd[directory]?.first ?? (hostedByMiniMax ? fallbackMiniMaxProcess : nil)
            let isRecent = latest.map { Date().timeIntervalSince($0) < (hostedByMiniMax ? 2 * 60 * 60 : 30 * 60) } ?? false
            let isLive = proc != nil && isRecent
            let status: String
            if hostedByMiniMax, isRecent {
                status = proc == nil ? "Waiting" : "Executing"
            } else {
                status = isLive ? "Waiting" : "Done"
            }
            let agentName = hostedByMiniMax ? "MiniMax Agent" : "OpenCode"
            let contextWindow = hostedByMiniMax ? 512_000 : 200_000
            let contextPercent = min(Double(input + cache) / Double(contextWindow), 1)
            let fallbackProject = hostedByMiniMax ? "MiniMax" : "OpenCode"

            rows.append(AgentMonitorSessionSnapshot(
                id: "\(hostedByMiniMax ? "MiniMax-OpenCode" : "OpenCode")-\(sessionId)-db",
                agentName: agentName,
                pid: proc?.pid,
                sessionId: sessionId,
                status: status,
                projectName: projectName.isEmpty ? (lastPathSegment(directory).isEmpty ? fallbackProject : lastPathSegment(directory)) : projectName,
                projectPath: directory,
                model: model.isEmpty ? "—" : model,
                tokens: AgentMonitorTokenBreakdown(input: input, output: output, cacheRead: cache),
                contextPercent: contextPercent,
                contextWindow: contextWindow,
                turnCount: turns,
                currentTask: currentTask,
                toolCount: 0,
                runningToolCount: 0,
                childCount: proc.map { descendants(of: $0.pid, children: childrenMap(processInfo)).count } ?? 0,
                ports: [],
                memoryMB: proc.map { max($0.rssKB / 1024, 1) },
                latestActivity: latest,
                instructionDate: latest,
                sourcePath: path
            ))
        }
        return rows
    }

    private func isMiniMaxHostedOpenCodeSession(directory: String, projectName: String) -> Bool {
        let combined = "\(directory) \(projectName)".lowercased()
        return combined.contains("/.minimax/") ||
            combined.contains("/.mavis/") ||
            combined.contains("minimax") ||
            combined.contains("mavis")
    }

    private func parseMiniMaxDBSessions(path: String, processInfo: [Int: ProcessInfo]) -> [AgentMonitorSessionSnapshot] {
        guard fileManager.fileExists(atPath: path), fileManager.isReadableFile(atPath: path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
          s.session_id,
          COALESCE(s.agent_name, ''),
          COALESCE(s.title, ''),
          COALESCE(s.workspace_dir, ''),
          COALESCE(s.status, ''),
          COALESCE(s.pid, 0),
          COALESCE(s.process_alive, 0),
          COALESCE(s.effective_model, ''),
          COALESCE(s.updated_at, 0),
          COALESCE(s.last_active_at, 0),
          COALESCE(SUM(t.input_tokens), 0),
          COALESCE(SUM(t.output_tokens), 0),
          COALESCE(SUM(t.cache_read_tokens), 0),
          COUNT(DISTINCT t.turn_id),
          COALESCE((
            SELECT SUBSTR(sm.data, 1, 4096)
            FROM session_messages sm
            WHERE sm.session_id = s.session_id
              AND (
                lower(COALESCE(sm.role, '')) = 'user'
                OR lower(COALESCE(json_extract(sm.data, '$.role'), '')) = 'user'
                OR COALESCE(json_extract(sm.data, '$.msg_type'), 0) = 1
              )
            ORDER BY sm.timestamp DESC, sm.id DESC
            LIMIT 1
          ), '')
        FROM sessions s
        LEFT JOIN token_usage t ON t.session_id = s.session_id
        GROUP BY s.session_id
        ORDER BY s.updated_at DESC
        LIMIT 160;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let liveMiniMaxProcesses = processInfo.values.filter { matchingSpecName($0.command) == "MiniMax Agent" }
        let liveByCwd = Dictionary(grouping: liveMiniMaxProcesses, by: { processCwd(pid: $0.pid) ?? "" })
        let fallbackLiveProcess = liveMiniMaxProcesses.first {
            $0.command.localizedCaseInsensitiveContains("opencode serve")
        } ?? liveMiniMaxProcesses.first {
            $0.command.localizedCaseInsensitiveContains("daemon.js")
        } ?? liveMiniMaxProcesses.first
        let pendingSessionIDs = pendingMiniMaxSessionIDs(db: db)
        var claimedFallbackProcess = false
        var rows: [AgentMonitorSessionSnapshot] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sessionId = sqliteText(stmt, 0)
            guard !sessionId.isEmpty else { continue }
            let agent = sqliteText(stmt, 1)
            let title = sqliteText(stmt, 2)
            let workspace = sqliteText(stmt, 3)
            let rawStatus = sqliteText(stmt, 4).lowercased()
            let pidValue = Int(sqlite3_column_int64(stmt, 5))
            let processAlive = sqlite3_column_int64(stmt, 6) > 0
            let model = sqliteText(stmt, 7)
            let updatedMs = sqlite3_column_int64(stmt, 8)
            let activeMs = sqlite3_column_int64(stmt, 9)
            let input = Int(sqlite3_column_int64(stmt, 10))
            let output = Int(sqlite3_column_int64(stmt, 11))
            let cache = Int(sqlite3_column_int64(stmt, 12))
            let turns = Int(sqlite3_column_int64(stmt, 13))
            let latestInstruction = sqliteText(stmt, 14)
            let pid = pidValue > 0 ? pidValue : nil
            let latest = dateFromMilliseconds(activeMs > 0 ? activeMs : updatedMs)
            let hasActiveStatus = ["start", "running", "active", "working", "processing", "progress", "queued", "pending"]
                .contains { rawStatus.contains($0) }
            var proc = pid.flatMap { processInfo[$0] } ?? liveByCwd[workspace]?.first
            if proc == nil, hasActiveStatus, !claimedFallbackProcess, let fallbackLiveProcess {
                proc = fallbackLiveProcess
                claimedFallbackProcess = true
            }
            let resolvedPID = pid ?? proc?.pid
            let isLive = processAlive || proc != nil
            let isWaitingForInput = pendingSessionIDs.contains(sessionId)
            let status: String
            if isWaitingForInput {
                status = "Waiting"
            } else if rawStatus.contains("finish") || rawStatus.contains("done") || rawStatus.contains("complete") {
                status = isLive ? "Waiting" : "Done"
            } else if hasActiveStatus || isLive {
                status = "Executing"
            } else {
                status = "History"
            }
            let contextWindow = 512_000
            let contextPercent = min(Double(input + cache) / Double(contextWindow), 1)
            let label = agent.isEmpty ? "MiniMax" : "MiniMax \(agent)"
            let currentTask = instructionFromStoredText(latestInstruction)
                ?? normalizedInstruction(title)
                ?? label

            rows.append(AgentMonitorSessionSnapshot(
                id: "MiniMax-\(sessionId)-db",
                agentName: "MiniMax Agent",
                pid: resolvedPID,
                sessionId: sessionId,
                status: status,
                projectName: lastPathSegment(workspace).isEmpty ? label : lastPathSegment(workspace),
                projectPath: workspace,
                model: model.isEmpty ? "—" : model,
                tokens: AgentMonitorTokenBreakdown(input: input, output: output, cacheRead: cache),
                contextPercent: contextPercent,
                contextWindow: contextWindow,
                turnCount: turns,
                currentTask: currentTask,
                toolCount: 0,
                runningToolCount: status == "Executing" ? 1 : 0,
                childCount: resolvedPID.map { descendants(of: $0, children: childrenMap(processInfo)).count } ?? 0,
                ports: [],
                memoryMB: proc.map { max($0.rssKB / 1024, 1) },
                latestActivity: latest,
                instructionDate: latest,
                sourcePath: path
            ))
        }
        return rows
    }

    private func pendingMiniMaxSessionIDs(db: OpaquePointer?) -> Set<String> {
        let sql = """
        SELECT session_id
        FROM permission_requests
        WHERE lower(COALESCE(status, 'pending')) IN ('pending', 'waiting', 'open', 'requested')
        UNION
        SELECT session_id
        FROM questionnaire_requests
        WHERE lower(COALESCE(status, 'pending')) IN ('pending', 'waiting', 'open', 'requested');
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var ids = Set<String>()
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqliteText(stmt, 0)
            if !id.isEmpty { ids.insert(id) }
        }
        return ids
    }

    private func parseMiniMaxNexusDBSessions(path: String, processInfo: [Int: ProcessInfo]) -> [AgentMonitorSessionSnapshot] {
        guard fileManager.fileExists(atPath: path), fileManager.isReadableFile(atPath: path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT
          c.id,
          COALESCE(c.title, ''),
          COALESCE(c.local_context_dir, ''),
          COALESCE(c.default_model_id, ''),
          COALESCE(c.updated_at, ''),
          COALESCE(c.last_message_preview, ''),
          COUNT(m.id),
          COALESCE((SELECT r.status FROM runs r WHERE r.conversation_id = c.id ORDER BY r.updated_at DESC LIMIT 1), ''),
          COALESCE((SELECT r.model_id FROM runs r WHERE r.conversation_id = c.id ORDER BY r.updated_at DESC LIMIT 1), c.default_model_id, ''),
          COALESCE((SELECT r.updated_at FROM runs r WHERE r.conversation_id = c.id ORDER BY r.updated_at DESC LIMIT 1), c.updated_at, '')
        FROM conversations c
        LEFT JOIN messages m ON m.conversation_id = c.id
        WHERE c.deleted_at IS NULL
        GROUP BY c.id
        ORDER BY c.updated_at DESC
        LIMIT 160;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        let liveProcess = processInfo.values.first { matchingSpecName($0.command) == "MiniMax Agent" }
        var rows: [AgentMonitorSessionSnapshot] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let sessionId = sqliteText(stmt, 0)
            guard !sessionId.isEmpty else { continue }
            let title = sqliteText(stmt, 1)
            let workspace = sqliteText(stmt, 2)
            let fallbackModel = sqliteText(stmt, 3)
            let lastPreview = sqliteText(stmt, 5)
            let messageCount = Int(sqlite3_column_int64(stmt, 6))
            let rawStatus = sqliteText(stmt, 7).lowercased()
            let model = sqliteText(stmt, 8)
            let latest = dateFromISO(sqliteText(stmt, 9)) ?? dateFromISO(sqliteText(stmt, 4))
            let currentTask = latestMiniMaxNexusUserInstruction(db: db, conversationId: sessionId)
                ?? normalizedInstruction(lastPreview)
                ?? normalizedInstruction(title)
                ?? "MiniMax conversation"
            let status: String
            if rawStatus.contains("running") || rawStatus.contains("progress") || rawStatus.contains("queued") || rawStatus.contains("pending") {
                status = "Thinking"
            } else if rawStatus.contains("complete") || rawStatus.contains("success") || rawStatus.contains("done") {
                status = "Done"
            } else {
                status = liveProcess == nil ? "History" : "Waiting"
            }
            rows.append(AgentMonitorSessionSnapshot(
                id: "MiniMax-Nexus-\(sessionId)-db",
                agentName: "MiniMax Agent",
                pid: liveProcess?.pid,
                sessionId: sessionId,
                status: status,
                projectName: lastPathSegment(workspace).isEmpty ? "MiniMax" : lastPathSegment(workspace),
                projectPath: workspace,
                model: model.isEmpty ? (fallbackModel.isEmpty ? "—" : fallbackModel) : model,
                tokens: AgentMonitorTokenBreakdown(input: 0, output: 0, cacheRead: 0),
                contextPercent: 0,
                contextWindow: 512_000,
                turnCount: messageCount,
                currentTask: currentTask,
                toolCount: 0,
                runningToolCount: status == "Thinking" ? 1 : 0,
                childCount: liveProcess.map { descendants(of: $0.pid, children: childrenMap(processInfo)).count } ?? 0,
                ports: [],
                memoryMB: liveProcess.map { max($0.rssKB / 1024, 1) },
                latestActivity: latest,
                instructionDate: latest,
                sourcePath: path
            ))
        }
        return rows
    }

    private func parseOpenClawSessionStore(path: String, processInfo: [Int: ProcessInfo]) -> [AgentMonitorSessionSnapshot] {
        guard let data = boundedData(
                contentsOf: URL(fileURLWithPath: path),
                maximumBytes: Self.maximumSessionStoreBytes
              ),
              let store = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let liveProcess = processInfo.values.first { matchingSpecName($0.command) == "OpenClaw" }
        let children = childrenMap(processInfo)
        return store.compactMap { sessionKey, value in
            guard let row = value as? [String: Any] else { return nil }
            let sessionId = stringValue(row, keys: ["sessionId", "session_id", "id"]) ?? sessionKey
            let rawStatus = (stringValue(row, keys: ["status", "state"]) ?? "").lowercased()
            let updated = dateFromAny(row["updatedAt"] ?? row["updated_at"])
                ?? dateFromAny(row["endedAt"] ?? row["ended_at"])
                ?? dateFromAny(row["startedAt"] ?? row["started_at"])
            let ended = row["endedAt"] != nil || row["ended_at"] != nil
            let isRunning = ["running", "active", "working", "processing", "queued", "pending", "tooluse", "tool_use"]
                .contains { rawStatus.contains($0) }
            let isRecentlyLive = liveProcess != nil && !ended && updated.map { abs(Date().timeIntervalSince($0)) < 180 } == true
            let status = isRunning ? "Executing" : (rawStatus.contains("done") || rawStatus.contains("complete") || ended ? "Done" : (isRecentlyLive ? "Waiting" : "History"))
            let workspace = (nestedValue(row, path: ["systemPromptReport", "workspaceDir"]) as? String)
                ?? stringValue(row, keys: ["workspaceDir", "workspace", "cwd"]) ?? ""
            let model = stringValue(row, keys: ["model", "modelId", "model_id"]) ?? "—"
            let input = intKeys(row, ["inputTokens", "input_tokens"])
            let output = intKeys(row, ["outputTokens", "output_tokens"])
            let cache = intKeys(row, ["cacheRead", "cache_read", "cacheReadTokens"])
            let contextWindow = intValue(row["contextTokens"] ?? row["contextWindow"]) ?? 200_000
            let title = stringValue(row, keys: ["label", "title", "name", "lastMessage", "last_message"]) ?? sessionKey
            let source = stringValue(row, keys: ["sessionFile", "session_file"]) ?? path
            // Historical OpenClaw stores can contain multi-megabyte transcripts. The
            // index title is enough for history; only inspect a transcript while its
            // session is live, and let the transcript reader cache unchanged files.
            let shouldInspectTranscript = isRunning || isRecentlyLive
            let currentTask = (shouldInspectTranscript ? latestUserInstructionInJSONLines(path: source) : nil)
                ?? (shouldInspectTranscript ? latestUserInstruction(in: row) : nil)
                ?? normalizedInstruction(title)
                ?? sessionKey
            let pid = ["Executing", "Thinking", "Waiting"].contains(status) ? liveProcess?.pid : nil
            return AgentMonitorSessionSnapshot(
                id: "OpenClaw-\(sessionId)-store",
                agentName: "OpenClaw",
                pid: pid,
                sessionId: sessionId,
                status: status,
                projectName: lastPathSegment(workspace).isEmpty ? "OpenClaw" : lastPathSegment(workspace),
                projectPath: workspace,
                model: model,
                tokens: AgentMonitorTokenBreakdown(input: input, output: output, cacheRead: cache),
                contextPercent: contextWindow > 0 ? min(Double(input + cache) / Double(contextWindow), 1) : 0,
                contextWindow: contextWindow,
                turnCount: intValue(row["turnCount"] ?? row["messageCount"]) ?? 0,
                currentTask: currentTask,
                toolCount: intValue(row["toolCount"]) ?? 0,
                runningToolCount: status == "Executing" ? 1 : 0,
                childCount: pid.map { descendants(of: $0, children: children).count } ?? 0,
                ports: [],
                memoryMB: liveProcess.map { max($0.rssKB / 1024, 1) },
                latestActivity: updated,
                instructionDate: updated,
                sourcePath: source
            )
        }
    }

    private func parseCursorDBSessions(path: String, processInfo: [Int: ProcessInfo], rowLimit: Int = 5000) -> [AgentMonitorSessionSnapshot] {
        guard fileManager.fileExists(atPath: path), fileManager.isReadableFile(atPath: path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let workspaceJSON = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("workspace.json")
        var workspace = ""
        if let data = boundedData(
                contentsOf: workspaceJSON,
                maximumBytes: Self.maximumSmallMetadataFileBytes
           ),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            workspace = (stringValue(object, keys: ["folder", "workspace"]) ?? "")
                .replacingOccurrences(of: "file://", with: "")
                .removingPercentEncoding ?? ""
        }
        let dbModified = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let liveProcess = processInfo.values.first { $0.command.lowercased().contains("cursor") }
        let boundedRowLimit = max(100, min(rowLimit, 5000))
        let sql = """
        SELECT key, value FROM ItemTable
        WHERE lower(key) LIKE '%composer%' OR lower(key) LIKE '%chat%' OR lower(key) LIKE '%agent%'
        LIMIT \(boundedRowLimit);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var candidates: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let value = sqliteText(stmt, 1)
            guard let data = value.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else { continue }
            collectCursorSessionObjects(object, into: &candidates, depth: 0)
        }

        var seen = Set<String>()
        return candidates.compactMap { row in
            let sessionId = stringValue(row, keys: ["composerId", "sessionId", "session_id", "id", "uuid"]) ?? ""
            guard !sessionId.isEmpty, seen.insert(sessionId).inserted else { return nil }
            let updated = dateFromAny(row["lastUpdatedAt"] ?? row["updatedAt"] ?? row["createdAt"]) ?? dbModified
            let isRecent = updated.map { abs(Date().timeIntervalSince($0)) < 10 * 60 } == true
            let status = liveProcess != nil && isRecent ? "Waiting" : "History"
            let title = stringValue(row, keys: ["name", "title", "lastMessage", "subtitle"]) ?? "Cursor Agent session"
            let currentTask = latestUserInstruction(in: row)
                ?? normalizedInstruction(title)
                ?? "Cursor Agent session"
            let model = stringValue(row, keys: ["model", "modelId", "modelName"]) ?? "—"
            return AgentMonitorSessionSnapshot(
                id: "Cursor-\(sessionId)-db",
                agentName: "Cursor",
                pid: liveProcess?.pid,
                sessionId: sessionId,
                status: status,
                projectName: lastPathSegment(workspace).isEmpty ? "Cursor" : lastPathSegment(workspace),
                projectPath: workspace,
                model: model,
                tokens: AgentMonitorTokenBreakdown(input: 0, output: 0, cacheRead: 0),
                contextPercent: 0,
                contextWindow: 200_000,
                turnCount: intValue(row["turnCount"] ?? row["messageCount"]) ?? 0,
                currentTask: currentTask,
                toolCount: intValue(row["toolCount"]) ?? 0,
                runningToolCount: 0,
                childCount: liveProcess.map { descendants(of: $0.pid, children: childrenMap(processInfo)).count } ?? 0,
                ports: [],
                memoryMB: liveProcess.map { max($0.rssKB / 1024, 1) },
                latestActivity: updated,
                instructionDate: updated,
                sourcePath: path
            )
        }
    }

    private func collectCursorSessionObjects(_ value: Any, into results: inout [[String: Any]], depth: Int) {
        guard depth < 8 else { return }
        if let dict = value as? [String: Any] {
            let id = stringValue(dict, keys: ["composerId", "sessionId", "session_id", "id", "uuid"]) ?? ""
            let title = stringValue(dict, keys: ["name", "title", "lastMessage", "subtitle"]) ?? ""
            if !id.isEmpty, !title.isEmpty || dict["messages"] != nil || dict["conversation"] != nil {
                results.append(dict)
            }
            for child in dict.values {
                collectCursorSessionObjects(child, into: &results, depth: depth + 1)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectCursorSessionObjects(child, into: &results, depth: depth + 1)
            }
        }
    }

    private func latestOpenCodeUserInstruction(db: OpaquePointer?, sessionId: String) -> String? {
        latestInstructionFromSQLite(db: db, binding: sessionId, sql: """
        SELECT json_extract(p.data, '$.text')
        FROM message m
        JOIN part p ON p.message_id = m.id
        WHERE m.session_id = ?
          AND lower(COALESCE(json_extract(m.data, '$.role'), '')) = 'user'
          AND lower(COALESCE(json_extract(p.data, '$.type'), '')) IN ('text', 'input_text')
        ORDER BY COALESCE(p.time_created, m.time_created) DESC, p.id DESC
        LIMIT 60;
        """)
    }

    private func latestMiniMaxUserInstruction(db: OpaquePointer?, sessionId: String) -> String? {
        latestInstructionFromSQLite(db: db, binding: sessionId, sql: """
        SELECT data
        FROM session_messages
        WHERE session_id = ?
          AND (
            lower(COALESCE(role, '')) = 'user'
            OR lower(COALESCE(json_extract(data, '$.role'), '')) = 'user'
            OR COALESCE(json_extract(data, '$.msg_type'), 0) = 1
          )
        ORDER BY timestamp DESC, id DESC
        LIMIT 80;
        """)
    }

    private func latestMiniMaxNexusUserInstruction(db: OpaquePointer?, conversationId: String) -> String? {
        latestInstructionFromSQLite(db: db, binding: conversationId, sql: """
        SELECT content
        FROM messages
        WHERE conversation_id = ?
          AND lower(COALESCE(role, '')) = 'user'
        ORDER BY seq_id DESC
        LIMIT 80;
        """)
    }

    private func latestInstructionFromSQLite(db: OpaquePointer?, binding: String, sql: String) -> String? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, 1, binding, -1, transient)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let raw = sqliteText(stmt, 0)
            if let instruction = instructionFromStoredText(raw) {
                return instruction
            }
        }
        return nil
    }

    private func latestUserInstructionInJSONLines(path: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let fileSize = values.fileSize else { return nil }

        latestInstructionCacheLock.lock()
        if let cached = latestInstructionCache[path],
           cached.fileSize == fileSize,
           cached.modifiedAt == values.contentModificationDate {
            latestInstructionCacheLock.unlock()
            return cached.instruction
        }
        latestInstructionCacheLock.unlock()

        guard let text = sessionText(from: url) else { return nil }
        var latestInstruction: String?
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            guard let object = jsonObject(from: String(line)) else { continue }
            if let instruction = latestUserInstruction(in: object) {
                latestInstruction = instruction
                break
            }
        }

        latestInstructionCacheLock.lock()
        latestInstructionCache[path] = LatestInstructionCacheEntry(
            fileSize: fileSize,
            modifiedAt: values.contentModificationDate,
            instruction: latestInstruction
        )
        if latestInstructionCache.count > 2_048 {
            let stalePaths = latestInstructionCache.keys.filter { !fileManager.fileExists(atPath: $0) }
            for stalePath in stalePaths {
                latestInstructionCache.removeValue(forKey: stalePath)
            }
        }
        latestInstructionCacheLock.unlock()
        return latestInstruction
    }

    private func scanLiveSessions(
        processInfo: [Int: ProcessInfo],
        children: [Int: [Int]],
        pidToSessionFiles: [Int: [String]],
        portsByPid: [Int: [Int]]
    ) -> [AgentMonitorSessionSnapshot] {
        pidToSessionFiles.flatMap { pid, paths in
            paths.compactMap { path in
            let url = URL(fileURLWithPath: path)
            guard let parsed = parseSessionFile(url) else { return nil }
            let proc = processInfo[pid]
            let processAgentName = agentName(for: proc?.command ?? "codex", fallback: "Codex")
            let agentName = resolvedAgentName(specName: processAgentName, parsed: parsed)
            let childPids = descendants(of: pid, children: children)
            let ports = ([pid] + childPids).flatMap { portsByPid[$0] ?? [] }.sorted()
            let isAlive = proc != nil
            let status = liveStatus(
                isAlive: isAlive,
                process: proc,
                childPids: childPids,
                processInfo: processInfo,
                currentTask: parsed.currentTask,
                parsedStatus: parsed.status
            )
            let contextPercent = parsed.contextWindow > 0 ? min(Double(parsed.lastContextTokens) / Double(parsed.contextWindow), 1) : 0
            let projectName = lastPathSegment(parsed.cwd).isEmpty ? agentName : lastPathSegment(parsed.cwd)
            return AgentMonitorSessionSnapshot(
                id: "\(agentName)-\(parsed.sessionId)-\(pid)",
                agentName: agentName,
                pid: pid,
                sessionId: parsed.sessionId,
                status: status,
                projectName: projectName,
                projectPath: parsed.cwd,
                model: parsed.model.isEmpty ? "—" : parsed.model,
                tokens: parsed.tokens,
                contextPercent: contextPercent,
                contextWindow: parsed.contextWindow,
                turnCount: parsed.turnCount,
                currentTask: parsed.currentTask.isEmpty ? "waiting for input" : parsed.currentTask,
                toolCount: parsed.toolCount,
                runningToolCount: parsed.runningToolCount,
                childCount: childPids.count,
                ports: Array(Set(ports)).sorted(),
                memoryMB: proc.map { max($0.rssKB / 1024, 1) },
                latestActivity: parsed.latestActivity,
                instructionDate: parsed.instructionDate ?? parsed.latestActivity,
                sourcePath: parsed.sourcePath
            )
            }
        }
    }

    private func liveStatus(
        isAlive: Bool,
        process: ProcessInfo?,
        childPids: [Int],
        processInfo: [Int: ProcessInfo],
        currentTask: String,
        parsedStatus: String
    ) -> String {
        if ["Executing", "Thinking", "Paused"].contains(parsedStatus) {
            return parsedStatus
        }
        guard isAlive else { return parsedStatus == "History" ? "Done" : parsedStatus }
        let childCpu = childPids.map { processInfo[$0]?.cpu ?? 0 }.max() ?? 0
        let ownCpu = process?.cpu ?? 0
        if !currentTask.isEmpty || childCpu > 5.0 { return "Executing" }
        if ownCpu > 2.0 || childCpu > 1.0 { return "Thinking" }
        if parsedStatus == "Done" { return "Waiting" }
        return parsedStatus == "History" ? "History" : parsedStatus
    }

    private func parseSessionFile(_ url: URL) -> ParsedSession? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = values?.fileSize ?? -1
        let modifiedAt = values?.contentModificationDate
        parsedSessionCacheLock.lock()
        let cached = parsedSessionCache[url.path]
        parsedSessionCacheLock.unlock()
        if let cached,
           cached.fileSize == fileSize,
           cached.modifiedAt == modifiedAt {
            return cached.session
        }

        guard let parsed = autoreleasepool(invoking: { parseSessionFileUncached(url) }) else { return nil }
        parsedSessionCacheLock.lock()
        if parsedSessionCache.count >= 240 {
            parsedSessionCache.removeAll(keepingCapacity: true)
        }
        parsedSessionCache[url.path] = ParsedSessionCacheEntry(
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            session: parsed
        )
        parsedSessionCacheLock.unlock()
        return parsed
    }

    private func parseSessionFileUncached(_ url: URL) -> ParsedSession? {
        let lowerPath = url.path.lowercased()
        if lowerPath.contains("/.claude/") || lowerPath.contains("/.config/claude/") {
            return parseClaudeSessionFile(url)
        }
        if lowerPath.contains("/.openclaw/") || lowerPath.contains("/.qclaw/") {
            return parseOpenClawTranscript(url)
        }
        if lowerPath.contains("/.hermes/") {
            return parseHermesSessionFile(url)
        }
        guard let text = sessionText(from: url) else { return nil }
        var sessionId = url.deletingPathExtension().lastPathComponent
        var cwd = ""
        var model = ""
        var input = 0
        var output = 0
        var cache = 0
        var lastContextTokens = 0
        var contextWindow = 200_000
        var turnCount = 0
        var currentTask = ""
        var latestUserInstruction = ""
        var latestUserInstructionDate: Date?
        var activeGoalObjective = ""
        var activeGoalStatus = ""
        var status = "History"
        var toolCount = 0
        var latestActivity: Date?
        var pendingCalls: [String: String] = [:]

        for line in text.split(whereSeparator: \.isNewline) {
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
            if let timestamp = date(from: object) {
                latestActivity = maxDate(latestActivity, timestamp)
            }
            let type = stringValue(object, keys: ["type"]) ?? ""
            let payload = object["payload"] as? [String: Any]

            if type == "session_meta" || type == "turn_context" {
                if let id = stringValue(payload, keys: ["id", "session_id", "sessionId"]), !id.isEmpty {
                    sessionId = id
                }
                if let value = stringValue(payload, keys: ["cwd", "project_path", "workspace"]), !value.isEmpty {
                    cwd = value
                }
                if let value = stringValue(payload, keys: ["model", "model_id", "modelId"]), !value.isEmpty {
                    model = value
                }
                if let cw = intValue(payload?["model_context_window"]) {
                    contextWindow = cw
                }
            }

            if type == "event_msg", let payload {
                let eventType = stringValue(payload, keys: ["type"]) ?? ""
                if eventType == "task_started" {
                    status = "Thinking"
                } else if eventType == "user_message" {
                    if let message = normalizedInstruction(stringValue(payload, keys: ["message", "text", "content"])) {
                        latestUserInstruction = message
                        latestUserInstructionDate = date(from: object) ?? latestActivity ?? latestUserInstructionDate
                        currentTask = message
                        if status != "Executing" && status != "Paused" && status != "Done" {
                            status = "Thinking"
                        }
                    }
                } else if eventType == "agent_message" {
                    turnCount += 1
                    if pendingCalls.isEmpty && status != "Done" {
                        status = "Thinking"
                    }
                } else if eventType == "token_count", let info = payload["info"] as? [String: Any] {
                    if let total = info["total_token_usage"] as? [String: Any] {
                        let rawInput = intKeys(total, ["input_tokens", "prompt_tokens"])
                        let cached = intKeys(total, ["cached_input_tokens", "cache_read_input_tokens"])
                        input = max(0, rawInput - cached)
                        output = intKeys(total, ["output_tokens", "completion_tokens"])
                        cache = cached
                    }
                    if let last = info["last_token_usage"] as? [String: Any] {
                        lastContextTokens = intKeys(last, ["input_tokens", "prompt_tokens"])
                    }
                    if let cw = intValue(info["model_context_window"]) {
                        contextWindow = cw
                    }
                } else if eventType == "thread_goal_updated",
                          let goal = payload["goal"] as? [String: Any] {
                    let objective = stringValue(goal, keys: ["objective", "name", "title"]) ?? ""
                    let goalStatus = stringValue(goal, keys: ["status"]) ?? ""
                    if !objective.isEmpty {
                        activeGoalObjective = objective
                        activeGoalStatus = goalStatus
                        if latestUserInstruction.isEmpty {
                            latestUserInstruction = normalizedInstruction(objective) ?? ""
                        }
                        if isUnfinishedGoalStatus(goalStatus) {
                            currentTask = objective
                            status = goalStatus == "active" ? "Executing" : "Paused"
                        } else {
                            status = "Done"
                        }
                    }
                } else if eventType == "task_complete" {
                    currentTask = isUnfinishedGoalStatus(activeGoalStatus)
                        ? activeGoalObjective
                        : latestUserInstruction
                    pendingCalls.removeAll()
                    status = statusForGoal(activeGoalStatus)
                } else if eventType == "turn_aborted" {
                    currentTask = isUnfinishedGoalStatus(activeGoalStatus)
                        ? activeGoalObjective
                        : latestUserInstruction
                    pendingCalls.removeAll()
                    status = statusForGoal(activeGoalStatus)
                }
            }

            if type == "response_item", let payload {
                let payloadType = stringValue(payload, keys: ["type"]) ?? ""
                if payloadType == "message",
                   stringValue(payload, keys: ["role"]) == "user",
                   let message = normalizedInstruction(messageContent(from: payload)) {
                    latestUserInstruction = message
                    latestUserInstructionDate = date(from: object) ?? latestActivity ?? latestUserInstructionDate
                    currentTask = message
                    if status != "Executing" && status != "Paused" && status != "Done" {
                        status = "Thinking"
                    }
                } else if payloadType == "function_call" || payloadType == "custom_tool_call" {
                    let name = stringValue(payload, keys: ["name"]) ?? "tool"
                    let arg = parseToolArgument(payload)
                    let toolTask = arg.isEmpty ? name : "\(name) \(arg)"
                    toolCount += 1
                    status = "Executing"
                    if let callID = stringValue(payload, keys: ["call_id", "callId", "id"]) {
                        pendingCalls[callID] = toolTask
                    }
                } else if payloadType == "function_call_output",
                          let callID = stringValue(payload, keys: ["call_id", "callId", "id"]) {
                    pendingCalls.removeValue(forKey: callID)
                    status = pendingCalls.isEmpty ? "Thinking" : "Executing"
                }
            }
        }

        if !pendingCalls.isEmpty {
            status = "Executing"
            if !latestUserInstruction.isEmpty {
                currentTask = latestUserInstruction
            } else if !activeGoalObjective.isEmpty {
                currentTask = activeGoalObjective
            }
        } else if isUnfinishedGoalStatus(activeGoalStatus), !activeGoalObjective.isEmpty {
            currentTask = activeGoalObjective
            if activeGoalStatus != "active" {
                status = "Paused"
            } else {
                status = "Executing"
            }
        } else if !latestUserInstruction.isEmpty {
            currentTask = latestUserInstruction
        } else if currentTask.isEmpty, !activeGoalObjective.isEmpty {
            currentTask = activeGoalObjective
        }
        guard !cwd.isEmpty || input + output + cache > 0 || toolCount > 0 else { return nil }
        return ParsedSession(
            sessionId: sessionId,
            cwd: cwd,
            model: model,
            tokens: AgentMonitorTokenBreakdown(input: input, output: output, cacheRead: cache),
            lastContextTokens: lastContextTokens,
            contextWindow: contextWindow,
            turnCount: turnCount,
            currentTask: currentTask,
            status: status,
            toolCount: toolCount,
            runningToolCount: pendingCalls.count,
            latestActivity: latestActivity ?? ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate),
            instructionDate: latestUserInstructionDate ?? latestActivity,
            sourcePath: url.path
        )
    }

    private func parseClaudeSessionFile(_ url: URL) -> ParsedSession? {
        guard url.pathExtension.lowercased() == "jsonl", let text = sessionText(from: url) else { return nil }
        var sessionId = url.deletingPathExtension().lastPathComponent
        var cwd = ""
        var model = ""
        var input = 0
        var output = 0
        var cache = 0
        var lastContextTokens = 0
        var turnCount = 0
        var currentTask = ""
        var toolCount = 0
        var pendingTools = Set<String>()
        var latestActivity: Date?
        var latestUserInstructionDate: Date?

        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let timestamp = date(from: object) { latestActivity = maxDate(latestActivity, timestamp) }
            if let value = stringValue(object, keys: ["sessionId", "session_id"]), !value.isEmpty { sessionId = value }
            if let value = stringValue(object, keys: ["cwd", "projectPath"]), !value.isEmpty { cwd = value }
            let type = stringValue(object, keys: ["type"]) ?? ""
            guard let message = object["message"] as? [String: Any] else { continue }
            if let value = stringValue(message, keys: ["model"]),
               !value.isEmpty,
               value != "<synthetic>" {
                model = value
            }
            let role = stringValue(message, keys: ["role"]) ?? type
            if role == "user" {
                let rawContent = textContent(message["content"])
                if let task = normalizedInstruction(rawContent), !task.isEmpty {
                    currentTask = task
                    latestUserInstructionDate = date(from: object) ?? latestActivity ?? latestUserInstructionDate
                }
                for block in message["content"] as? [[String: Any]] ?? [] where stringValue(block, keys: ["type"]) == "tool_result" {
                    if let id = stringValue(block, keys: ["tool_use_id", "toolUseId"]) { pendingTools.remove(id) }
                }
            } else if role == "assistant" {
                turnCount += 1
                if let usage = message["usage"] as? [String: Any] {
                    let promptInput = intKeys(usage, ["input_tokens", "prompt_tokens"])
                    let cached = intKeys(usage, ["cache_read_input_tokens", "cached_input_tokens"])
                    let createdCache = intKeys(usage, ["cache_creation_input_tokens"])
                    input += promptInput
                    output += intKeys(usage, ["output_tokens", "completion_tokens"])
                    cache += cached + createdCache
                    lastContextTokens = max(lastContextTokens, promptInput + cached + createdCache)
                }
                for block in message["content"] as? [[String: Any]] ?? [] where stringValue(block, keys: ["type"]) == "tool_use" {
                    toolCount += 1
                    if let id = stringValue(block, keys: ["id", "tool_use_id"]) { pendingTools.insert(id) }
                }
            }
        }
        let isSyntheticTitleSession = model == "<synthetic>" &&
            currentTask.localizedCaseInsensitiveContains("conversation title generator")
        guard !isSyntheticTitleSession,
              !cwd.isEmpty || input + output + cache > 0 || toolCount > 0 || !currentTask.isEmpty else { return nil }
        return ParsedSession(
            sessionId: sessionId,
            cwd: cwd,
            model: model,
            tokens: AgentMonitorTokenBreakdown(input: input, output: output, cacheRead: cache),
            lastContextTokens: lastContextTokens,
            contextWindow: 200_000,
            turnCount: turnCount,
            currentTask: currentTask,
            status: "History",
            toolCount: toolCount,
            runningToolCount: pendingTools.count,
            latestActivity: latestActivity ?? ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate),
            instructionDate: latestUserInstructionDate ?? latestActivity,
            sourcePath: url.path
        )
    }

    private func parseOpenClawTranscript(_ url: URL) -> ParsedSession? {
        guard url.pathExtension.lowercased() == "jsonl", let text = sessionText(from: url) else { return nil }
        var model = ""
        var input = 0
        var output = 0
        var cache = 0
        var turnCount = 0
        var toolCount = 0
        var currentTask = ""
        var latestUserInstructionDate: Date?
        var latestActivity: Date?
        var lastContextTokens = 0
        var pendingTools = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            guard let data = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if let timestamp = date(from: object) { latestActivity = maxDate(latestActivity, timestamp) }
            guard let message = object["message"] as? [String: Any] else { continue }
            let role = stringValue(message, keys: ["role"]) ?? ""
            if role == "user", let task = normalizedInstruction(textContent(message["content"])), !task.isEmpty {
                currentTask = task
                latestUserInstructionDate = date(from: object) ?? latestActivity ?? latestUserInstructionDate
            }
            if role == "assistant" {
                turnCount += 1
                if let value = stringValue(message, keys: ["model"]), !value.isEmpty { model = value }
                if let usage = message["usage"] as? [String: Any] {
                    input += intKeys(usage, ["input", "inputTokens", "input_tokens"])
                    output += intKeys(usage, ["output", "outputTokens", "output_tokens"])
                    cache += intKeys(usage, ["cacheRead", "cache_read", "cacheWrite", "cache_write"])
                    lastContextTokens = max(lastContextTokens, intKeys(usage, ["input", "inputTokens", "input_tokens", "cacheRead", "cache_read"]))
                }
                for block in message["content"] as? [[String: Any]] ?? [] where ["toolCall", "tool_use", "tool_call"].contains(stringValue(block, keys: ["type"]) ?? "") {
                    toolCount += 1
                    if let id = stringValue(block, keys: ["id", "toolCallId"]) { pendingTools.insert(id) }
                }
            } else if role == "toolResult", let id = stringValue(message, keys: ["toolCallId", "tool_use_id"]) {
                pendingTools.remove(id)
            }
        }
        guard !currentTask.isEmpty || input + output + cache > 0 || toolCount > 0 else { return nil }
        let workspace = url.path.contains("/.qclaw/") ? home + "/.qclaw/workspace" : home + "/.openclaw/workspace"
        return ParsedSession(
            sessionId: url.deletingPathExtension().lastPathComponent,
            cwd: workspace,
            model: model,
            tokens: AgentMonitorTokenBreakdown(input: input, output: output, cacheRead: cache),
            lastContextTokens: lastContextTokens,
            contextWindow: 200_000,
            turnCount: turnCount,
            currentTask: currentTask,
            status: pendingTools.isEmpty ? "History" : "Executing",
            toolCount: toolCount,
            runningToolCount: pendingTools.count,
            latestActivity: latestActivity ?? ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate),
            instructionDate: latestUserInstructionDate ?? latestActivity,
            sourcePath: url.path
        )
    }

    private func parseHermesSessionFile(_ url: URL) -> ParsedSession? {
        guard let data = boundedData(
                contentsOf: url,
                maximumBytes: Self.maximumHermesFileBytes
              ),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if url.lastPathComponent == "gateway_state.json" {
            let state = stringValue(object, keys: ["gateway_state", "state"]) ?? "unknown"
            let activeAgents = intValue(object["active_agents"]) ?? 0
            let pid = intValue(object["pid"]) ?? 0
            return ParsedSession(
                sessionId: "gateway-\(pid)",
                cwd: home + "/.hermes",
                model: "Hermes Gateway",
                tokens: AgentMonitorTokenBreakdown(input: 0, output: 0, cacheRead: 0),
                lastContextTokens: 0,
                contextWindow: 200_000,
                turnCount: 0,
                currentTask: activeAgents > 0 ? "\(activeAgents) active Hermes agents" : "Hermes gateway \(state)",
                status: activeAgents > 0 ? "Executing" : (state.lowercased().contains("running") ? "Waiting" : "History"),
                toolCount: 0,
                runningToolCount: activeAgents,
                latestActivity: dateFromISO(stringValue(object, keys: ["updated_at", "updatedAt"]) ?? ""),
                instructionDate: dateFromISO(stringValue(object, keys: ["updated_at", "updatedAt"]) ?? ""),
                sourcePath: url.path
            )
        }
        let sessionId = stringValue(object, keys: ["session_id", "sessionId", "id"]) ?? url.deletingPathExtension().lastPathComponent
        let model = stringValue(object, keys: ["model", "model_id"]) ?? ""
        let workspace = stringValue(object, keys: ["cwd", "workspace", "project_dir"]) ?? home + "/.hermes"
        var currentTask = stringValue(object, keys: ["title", "name"]) ?? ""
        var input = 0
        var output = 0
        var cache = 0
        var turns = 0
        var tools = 0
        var latestUserInstructionDate: Date?
        for message in object["messages"] as? [[String: Any]] ?? [] {
            let role = stringValue(message, keys: ["role"]) ?? ""
            if role == "user", let task = normalizedInstruction(textContent(message["content"])), !task.isEmpty {
                currentTask = task
                latestUserInstructionDate = dateFromAny(message["timestamp"] ?? message["created_at"] ?? message["createdAt"]) ?? latestUserInstructionDate
            }
            if role == "assistant" {
                turns += 1
                tools += (message["tool_calls"] as? [Any])?.count ?? 0
                if let usage = message["usage"] as? [String: Any] {
                    input += intKeys(usage, ["input_tokens", "prompt_tokens"])
                    output += intKeys(usage, ["output_tokens", "completion_tokens"])
                    cache += intKeys(usage, ["cache_read_tokens", "cached_tokens"])
                }
            }
        }
        guard !currentTask.isEmpty || turns > 0 || tools > 0 else { return nil }
        return ParsedSession(
            sessionId: sessionId,
            cwd: workspace,
            model: model,
            tokens: AgentMonitorTokenBreakdown(input: input, output: output, cacheRead: cache),
            lastContextTokens: input + cache,
            contextWindow: 200_000,
            turnCount: turns,
            currentTask: currentTask,
            status: "History",
            toolCount: tools,
            runningToolCount: 0,
            latestActivity: dateFromISO(stringValue(object, keys: ["updated_at", "session_start", "created_at"]) ?? "")
                ?? ((try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate),
            instructionDate: latestUserInstructionDate ?? dateFromISO(stringValue(object, keys: ["updated_at", "session_start", "created_at"]) ?? ""),
            sourcePath: url.path
        )
    }

    private func sessionText(from url: URL) -> String? {
        let fullReadLimit = 1_000_000
        let headLimit = 96_000
        let tailLimit = 768_000
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        if size <= UInt64(fullReadLimit) {
            try? handle.seek(toOffset: 0)
            guard let data = try? handle.readToEnd() else { return nil }
            return String(decoding: data, as: UTF8.self)
        }
        try? handle.seek(toOffset: 0)
        let head = (try? handle.read(upToCount: headLimit)) ?? Data()
        let tailOffset = size > UInt64(tailLimit) ? size - UInt64(tailLimit) : 0
        try? handle.seek(toOffset: tailOffset)
        let tail = (try? handle.readToEnd()) ?? Data()
        return String(decoding: head, as: UTF8.self) + "\n" + String(decoding: tail, as: UTF8.self)
    }

    private func isUnfinishedGoalStatus(_ status: String) -> Bool {
        !status.isEmpty && status.lowercased() != "complete"
    }

    private func statusForGoal(_ status: String) -> String {
        guard isUnfinishedGoalStatus(status) else { return "Done" }
        return status == "active" ? "Executing" : "Paused"
    }

    private func scanProcessInfo() -> [Int: ProcessInfo] {
        processInfoCacheLock.lock()
        if !processInfoCache.isEmpty,
           Date().timeIntervalSince(processInfoCacheDate) < processInfoCacheTTL {
            let cached = processInfoCache
            processInfoCacheLock.unlock()
            return cached
        }
        processInfoCacheLock.unlock()

        let output = run("/bin/ps", ["-ww", "-eo", "pid=,ppid=,rss=,%cpu=,command="])
        var result: [Int: ProcessInfo] = [:]
        for line in output.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 4, omittingEmptySubsequences: true)
            guard parts.count >= 5,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]),
                  let rss = Int(parts[2]) else { continue }
            let cpu = Double(parts[3]) ?? 0
            let command = String(parts[4])
            result[pid] = ProcessInfo(pid: pid, ppid: ppid, rssKB: rss, cpu: cpu, command: command)
        }
        processInfoCacheLock.lock()
        processInfoCache = result
        processInfoCacheDate = Date()
        processInfoCacheLock.unlock()
        return result
    }

    private func scanOpenSessionFiles(processInfo: [Int: ProcessInfo]) -> [Int: [String]] {
        let agentPids = processInfo.values.compactMap { process -> Int? in
            let command = process.command.lowercased()
            guard matchingSpecName(process.command) != nil
                    || command.contains("codex app-server")
                    || command.contains("tracefenceclaudeadapter") else { return nil }
            return process.pid
        }
        let pidList = Array(Set(agentPids)).sorted().prefix(128).map(String.init).joined(separator: ",")
        guard !pidList.isEmpty else { return [:] }

        let output = run("/usr/sbin/lsof", ["+c", "0", "-w", "-Fpn", "-a", "-p", pidList])
        var result: [Int: [String]] = [:]
        var currentPid: Int?
        for line in output.components(separatedBy: .newlines) {
            if line.hasPrefix("p") {
                currentPid = Int(line.dropFirst())
            } else if line.hasPrefix("n"), let pid = currentPid {
                let path = String(line.dropFirst())
                if isAgentSessionPath(path) {
                    if !result[pid, default: []].contains(path) {
                        result[pid, default: []].append(path)
                    }
                }
            }
        }
        return result
    }

    private func scanForegroundSessionFiles(
        roots: [String],
        excluding seen: Set<String>,
        processInfo: [Int: ProcessInfo],
        children: [Int: [Int]]
    ) -> [AgentMonitorSessionSnapshot] {
        let cutoff = Date().addingTimeInterval(-180)
        var rows: [AgentMonitorSessionSnapshot] = []
        for file in recentSessionFiles(roots: roots, cutoff: cutoff) {
            guard let parsed = parseSessionFile(file),
                  let spec = specForSessionPath(file.path) else { continue }
            let agentName = resolvedAgentName(specName: spec.name, parsed: parsed)
            let key = "\(agentName)|\(parsed.sessionId)|\(parsed.sourcePath)"
            guard !seen.contains(key) else { continue }
            let proc = processInfo.values.first { matchingSpecName($0.command) == agentName }
            let childPids = proc.map { descendants(of: $0.pid, children: children) } ?? []
            let status = liveStatus(
                isAlive: proc != nil,
                process: proc,
                childPids: childPids,
                processInfo: processInfo,
                currentTask: parsed.currentTask,
                parsedStatus: parsed.status
            )
            guard ["Thinking", "Executing", "Waiting", "Paused"].contains(status) else { continue }
            let contextPercent = parsed.contextWindow > 0 ? min(Double(parsed.lastContextTokens) / Double(parsed.contextWindow), 1) : 0
            let projectName = lastPathSegment(parsed.cwd).isEmpty ? agentName : lastPathSegment(parsed.cwd)
            rows.append(AgentMonitorSessionSnapshot(
                id: "\(agentName)-\(parsed.sessionId)-recent-\(file.path)",
                agentName: agentName,
                pid: proc?.pid,
                sessionId: parsed.sessionId,
                status: status,
                projectName: projectName,
                projectPath: parsed.cwd,
                model: parsed.model.isEmpty ? "—" : parsed.model,
                tokens: parsed.tokens,
                contextPercent: contextPercent,
                contextWindow: parsed.contextWindow,
                turnCount: parsed.turnCount,
                currentTask: parsed.currentTask.isEmpty ? "live session activity" : parsed.currentTask,
                toolCount: parsed.toolCount,
                runningToolCount: parsed.runningToolCount,
                childCount: childPids.count,
                ports: [],
                memoryMB: proc.map { max($0.rssKB / 1024, 1) },
                latestActivity: parsed.latestActivity,
                instructionDate: parsed.instructionDate ?? parsed.latestActivity,
                sourcePath: parsed.sourcePath
            ))
        }
        return rows
    }

    private func scanRetainedActiveSessionFiles(
        paths: [String],
        processInfo: [Int: ProcessInfo],
        children: [Int: [Int]]
    ) -> [AgentMonitorSessionSnapshot] {
        var seen = Set<String>()
        return paths.compactMap { path in
            guard seen.insert(path).inserted,
                  ["json", "jsonl", "log"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()),
                  let parsed = parseSessionFile(URL(fileURLWithPath: path)),
                  isParsedSessionActive(parsed),
                  let spec = specForSessionPath(path) else {
                return nil
            }
            let agentName = resolvedAgentName(specName: spec.name, parsed: parsed)
            let process = processInfo.values.first { matchingSpecName($0.command) == agentName }
            let childPids = process.map { descendants(of: $0.pid, children: children) } ?? []
            let status = liveStatus(
                isAlive: process != nil,
                process: process,
                childPids: childPids,
                processInfo: processInfo,
                currentTask: parsed.currentTask,
                parsedStatus: parsed.status
            )
            let contextPercent = parsed.contextWindow > 0
                ? min(Double(parsed.lastContextTokens) / Double(parsed.contextWindow), 1)
                : 0
            return AgentMonitorSessionSnapshot(
                id: "\(agentName)-\(parsed.sessionId)-retained",
                agentName: agentName,
                pid: process?.pid,
                sessionId: parsed.sessionId,
                status: status,
                projectName: lastPathSegment(parsed.cwd).isEmpty ? agentName : lastPathSegment(parsed.cwd),
                projectPath: parsed.cwd,
                model: parsed.model.isEmpty ? "—" : parsed.model,
                tokens: parsed.tokens,
                contextPercent: contextPercent,
                contextWindow: parsed.contextWindow,
                turnCount: parsed.turnCount,
                currentTask: parsed.currentTask,
                toolCount: parsed.toolCount,
                runningToolCount: parsed.runningToolCount,
                childCount: childPids.count,
                ports: [],
                memoryMB: process.map { max($0.rssKB / 1024, 1) },
                latestActivity: parsed.latestActivity,
                instructionDate: parsed.instructionDate ?? parsed.latestActivity,
                sourcePath: parsed.sourcePath
            )
        }
    }

    private func snapshotFromParsedSession(
        _ parsed: ParsedSession,
        agentName: String,
        processInfo: [Int: ProcessInfo],
        children: [Int: [Int]],
        idSuffix: String
    ) -> AgentMonitorSessionSnapshot {
        let process = processInfo.values.first { matchingSpecName($0.command) == agentName }
            ?? (agentName == "Claude Code" ? processInfo.values.first { $0.command.lowercased().contains("/claude.app/") } : nil)
        let childPids = process.map { descendants(of: $0.pid, children: children) } ?? []
        let status = liveStatus(
            isAlive: process != nil,
            process: process,
            childPids: childPids,
            processInfo: processInfo,
            currentTask: parsed.currentTask,
            parsedStatus: parsed.status
        )
        let contextPercent = parsed.contextWindow > 0
            ? min(Double(parsed.lastContextTokens) / Double(parsed.contextWindow), 1)
            : 0
        return AgentMonitorSessionSnapshot(
            id: "\(agentName)-\(parsed.sessionId)-\(idSuffix)",
            agentName: agentName,
            pid: process?.pid,
            sessionId: parsed.sessionId,
            status: status,
            projectName: lastPathSegment(parsed.cwd).isEmpty ? agentName : lastPathSegment(parsed.cwd),
            projectPath: parsed.cwd,
            model: parsed.model.isEmpty ? "—" : parsed.model,
            tokens: parsed.tokens,
            contextPercent: contextPercent,
            contextWindow: parsed.contextWindow,
            turnCount: parsed.turnCount,
            currentTask: parsed.currentTask.isEmpty ? "\(agentName) session" : parsed.currentTask,
            toolCount: parsed.toolCount,
            runningToolCount: status == "Executing" ? parsed.runningToolCount : 0,
            childCount: childPids.count,
            ports: [],
            memoryMB: process.map { max($0.rssKB / 1024, 1) },
            latestActivity: parsed.latestActivity,
            instructionDate: parsed.instructionDate ?? parsed.latestActivity,
            sourcePath: parsed.sourcePath
        )
    }

    private func scanPriorityHistorySessions(
        roots: [String],
        processInfo: [Int: ProcessInfo],
        children: [Int: [Int]]
    ) -> [AgentMonitorSessionSnapshot] {
        let eligibleRoots = Set(roots.filter {
            let lower = $0.lowercased()
            return lower.contains("/.claude/projects") || lower.contains("/.config/claude/projects") || lower.contains("/.hermes/sessions")
        })
        var files: [URL] = []
        for root in eligibleRoots where fileManager.fileExists(atPath: root) {
            files.append(contentsOf: usageFiles(under: root))
        }
        let latestFiles = files.sorted {
            let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return left > right
        }.prefix(60)
        let liveProcessByAgent = Dictionary(grouping: processInfo.values, by: { matchingSpecName($0.command) ?? "" })
        var seen = Set<String>()
        let rows: [AgentMonitorSessionSnapshot] = latestFiles.compactMap { file -> AgentMonitorSessionSnapshot? in
            guard let parsed = parseSessionFile(file),
                  let spec = specForSessionPath(file.path),
                  ["Claude Code", "Hermes"].contains(spec.name) else { return nil }
            let agentName = resolvedAgentName(specName: spec.name, parsed: parsed)
            guard seen.insert("\(agentName)|\(parsed.sessionId)").inserted else { return nil }
            let process = liveProcessByAgent[agentName]?.first
                ?? (agentName == "Claude Code" ? processInfo.values.first { $0.command.lowercased().contains("/claude.app/") } : nil)
            let childPids = process.map { descendants(of: $0.pid, children: children) } ?? []
            let recentWindow: TimeInterval = agentName == "Claude Code" ? 10 * 60 : 180
            let isRecent = parsed.latestActivity.map { abs(Date().timeIntervalSince($0)) < recentWindow } == true
            let status = isRecent ? liveStatus(
                isAlive: process != nil,
                process: process,
                childPids: childPids,
                processInfo: processInfo,
                currentTask: parsed.currentTask,
                parsedStatus: parsed.status
            ) : parsed.status
            let contextPercent = parsed.contextWindow > 0 ? min(Double(parsed.lastContextTokens) / Double(parsed.contextWindow), 1) : 0
            return AgentMonitorSessionSnapshot(
                id: "\(agentName)-\(parsed.sessionId)-priority",
                agentName: agentName,
                pid: isRecent ? process?.pid : nil,
                sessionId: parsed.sessionId,
                status: status,
                projectName: lastPathSegment(parsed.cwd).isEmpty ? agentName : lastPathSegment(parsed.cwd),
                projectPath: parsed.cwd,
                model: parsed.model.isEmpty ? "—" : parsed.model,
                tokens: parsed.tokens,
                contextPercent: contextPercent,
                contextWindow: parsed.contextWindow,
                turnCount: parsed.turnCount,
                currentTask: parsed.currentTask.isEmpty ? "\(agentName) session" : parsed.currentTask,
                toolCount: parsed.toolCount,
                runningToolCount: status == "Executing" ? parsed.runningToolCount : 0,
                childCount: isRecent ? childPids.count : 0,
                ports: [],
                memoryMB: isRecent ? process.map { max($0.rssKB / 1024, 1) } : nil,
                latestActivity: parsed.latestActivity,
                instructionDate: parsed.instructionDate ?? parsed.latestActivity,
                sourcePath: parsed.sourcePath
            )
        }
        return rows
    }

    private func recentSessionFiles(roots: [String], cutoff: Date) -> [URL] {
        var results: [URL] = []
        let calendar = Calendar.current
        let dates = [Date(), calendar.date(byAdding: .day, value: -1, to: Date())].compactMap { $0 }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy/MM/dd"
        for root in Set(roots) {
            let lower = root.lowercased()
            if lower.contains("/.codex/sessions") {
                for date in dates {
                    let dayRoot = root + "/" + formatter.string(from: date)
                    results.append(contentsOf: sessionFiles(in: dayRoot, cutoff: cutoff, maxFiles: 80))
                }
            } else if lower.hasSuffix(".jsonl") || lower.hasSuffix(".json") {
                let url = URL(fileURLWithPath: root)
                if isRecentlyModified(url, cutoff: cutoff) {
                    results.append(url)
                }
            } else if specForSessionPath(root) != nil || specs.contains(where: { spec in
                lower.contains(spec.name.lowercased().replacingOccurrences(of: " ", with: "")) ||
                spec.processKeywords.contains(where: { lower.contains($0.lowercased()) })
            }) {
                results.append(contentsOf: sessionFiles(in: root, cutoff: cutoff, maxFiles: 80))
            }
            if results.count >= 160 { break }
        }
        return Array(Set(results)).sorted {
            (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast >
            (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        }
    }

    private func isForegroundSessionRoot(_ root: String) -> Bool {
        let lower = root.lowercased()
        if lower.hasSuffix(".sqlite") || lower.hasSuffix(".db") || lower.hasSuffix(".vscdb") {
            return false
        }
        if lower.contains("/.codex/sessions") ||
            lower.contains("/.codex/archived_sessions") ||
            lower.contains("/.claude/projects") ||
            lower.contains("/.claude/sessions") ||
            lower.contains("/.hermes/sessions") {
            return true
        }
        let component = URL(fileURLWithPath: lower).lastPathComponent
        return ["sessions", "projects", "conversations", "transcripts", "history", "chat_history", ".sessions"].contains(component)
    }

    private func sessionFiles(in root: String, cutoff: Date, maxFiles: Int) -> [URL] {
        guard fileManager.fileExists(atPath: root),
              let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: root),
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsPackageDescendants, .skipsHiddenFiles]
              ) else {
            return []
        }
        var files: [URL] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 1500 { break }
            let name = url.lastPathComponent.lowercased()
            if ["node_modules", ".git", "cache", "caches", "tmp", "logs"].contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let ext = url.pathExtension.lowercased()
            guard ext == "jsonl" || ext == "json" else { continue }
            if isRecentlyModified(url, cutoff: cutoff) {
                files.append(url)
                if files.count >= maxFiles { break }
            }
        }
        return files
    }

    private func isRecentlyModified(_ url: URL, cutoff: Date) -> Bool {
        guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else {
            return false
        }
        return modified >= cutoff
    }

    private func scanListeningPortsByPid() -> [Int: [Int]] {
        let output = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"])
        var result: [Int: [Int]] = [:]
        for line in output.components(separatedBy: .newlines).dropFirst() {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 9, let pid = Int(parts[1]) else { continue }
            let text = String(line)
            if let port = parsePort(from: text) {
                result[pid, default: []].append(port)
            }
        }
        return result
    }

    private func scanOutboundConnections(processInfo: [Int: ProcessInfo]) -> [AgentNetworkConnection] {
        let output = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:ESTABLISHED", "-FpcnT"])
        let observedAt = Date()
        let proxyGuardActive = isProxyGuardActive()
        var rows: [AgentNetworkConnection] = []
        var currentPID: Int?
        var currentProcessName = ""
        var currentEndpoint = ""
        var currentState = ""

        func flush() {
            guard let pid = currentPID,
                  !currentEndpoint.isEmpty,
                  let agentName = networkAgentName(forPID: pid, processName: currentProcessName, processInfo: processInfo),
                  let endpoints = splitConnectionEndpoint(currentEndpoint) else {
                return
            }
            let remote = remoteHostAndPort(from: endpoints.remote)
            let route = networkRoute(host: remote.host, port: remote.port)
            let risk = networkRiskLevel(host: remote.host, port: remote.port, route: route)
            let safety = networkSafetyStatus(
                host: remote.host,
                port: remote.port,
                route: route,
                proxyGuardActive: proxyGuardActive
            )
            rows.append(AgentNetworkConnection(
                id: "\(pid)|\(endpoints.remote)|\(currentState)",
                agentName: agentName,
                pid: pid,
                processName: currentProcessName.isEmpty ? processInfo[pid]?.command ?? "process" : currentProcessName,
                localEndpoint: endpoints.local,
                remoteEndpoint: endpoints.remote,
                remoteHost: remote.host,
                remotePort: remote.port,
                state: currentState.isEmpty ? "ESTABLISHED" : currentState,
                route: route,
                riskLevel: risk,
                safetyStatus: safety.status,
                safetyReason: safety.reason,
                observedAt: observedAt
            ))
        }

        for line in output.components(separatedBy: .newlines) {
            guard !line.isEmpty else { continue }
            let prefix = line[line.startIndex]
            let value = String(line.dropFirst())
            switch prefix {
            case "p":
                flush()
                currentPID = Int(value)
                currentProcessName = ""
                currentEndpoint = ""
                currentState = ""
            case "c":
                currentProcessName = value
            case "n":
                if !currentEndpoint.isEmpty {
                    flush()
                    currentState = ""
                }
                currentEndpoint = value
            case "T":
                if value.hasPrefix("ST=") {
                    currentState = String(value.dropFirst(3))
                }
            default:
                continue
            }
        }
        flush()

        var seen = Set<String>()
        return rows
            .filter { seen.insert($0.id).inserted }
            .sorted {
                if networkSafetyRank($0.safetyStatus) == networkSafetyRank($1.safetyStatus) {
                    if networkRiskRank($0.riskLevel) != networkRiskRank($1.riskLevel) {
                        return networkRiskRank($0.riskLevel) > networkRiskRank($1.riskLevel)
                    }
                    if $0.agentName == $1.agentName { return $0.remoteEndpoint < $1.remoteEndpoint }
                    return $0.agentName < $1.agentName
                }
                return networkSafetyRank($0.safetyStatus) > networkSafetyRank($1.safetyStatus)
            }
            .prefix(80)
            .map { $0 }
    }

    private func networkAgentName(forPID pid: Int, processName: String, processInfo: [Int: ProcessInfo]) -> String? {
        if let process = processInfo[pid],
           let name = matchingSpecName(process.command) {
            return name
        }
        if let name = matchingSpecName(processName) {
            return name
        }
        var current = processInfo[pid]?.ppid
        var visited = Set<Int>()
        for _ in 0..<10 {
            guard let candidate = current,
                  candidate > 0,
                  visited.insert(candidate).inserted,
                  let process = processInfo[candidate] else {
                break
            }
            if let name = matchingSpecName(process.command) {
                return name
            }
            current = process.ppid
        }
        return nil
    }

    private func splitConnectionEndpoint(_ value: String) -> (local: String, remote: String)? {
        let cleaned = value
            .replacingOccurrences(of: " (ESTABLISHED)", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let arrow = cleaned.range(of: "->") else { return nil }
        let local = String(cleaned[..<arrow.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let remote = String(cleaned[arrow.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !remote.isEmpty else { return nil }
        return (local, remote)
    }

    private func remoteHostAndPort(from endpoint: String) -> (host: String, port: Int?) {
        let cleaned = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: " []"))
        if endpoint.hasPrefix("["),
           let close = endpoint.firstIndex(of: "]") {
            let host = String(endpoint[endpoint.index(after: endpoint.startIndex)..<close])
            let suffix = endpoint[endpoint.index(after: close)...]
            let port = suffix.first == ":" ? Int(suffix.dropFirst()) : nil
            return (host, port)
        }
        if let colon = cleaned.lastIndex(of: ":") {
            let suffix = cleaned[cleaned.index(after: colon)...]
            if let port = Int(suffix) {
                return (String(cleaned[..<colon]), port)
            }
        }
        if let dot = cleaned.lastIndex(of: ".") {
            let suffix = cleaned[cleaned.index(after: dot)...]
            if let port = Int(suffix) {
                return (String(cleaned[..<dot]), port)
            }
        }
        return (cleaned, nil)
    }

    private func networkRoute(host: String, port: Int?) -> String {
        let lowerHost = host.lowercased()
        let proxyPorts: Set<Int> = [1080, 1086, 1087, 6152, 7890, 7891, 7897, 8080, 9090, 20171, 20172]
        if ["127.0.0.1", "::1", "localhost"].contains(lowerHost) || port.map(proxyPorts.contains) == true {
            return "Local proxy"
        }
        switch port {
        case 443: return "HTTPS"
        case 80: return "HTTP"
        case 22: return "SSH"
        default: return "TCP"
        }
    }

    private func networkRiskLevel(host: String, port: Int?, route: String) -> String {
        if route == "Local proxy" { return "proxy" }
        if port == 80 { return "cleartext" }
        if host.isEmpty || port == nil { return "unknown" }
        return "normal"
    }

    private func networkSafetyStatus(host: String, port: Int?, route: String, proxyGuardActive: Bool) -> (status: String, reason: String) {
        if route == "Local proxy" {
            return ("proxied", "Agent is using a local proxy endpoint.")
        }
        if port == 80 {
            return ("unsafe", "Plain HTTP egress can expose request metadata.")
        }
        guard !host.isEmpty else {
            return ("unknown", "Remote endpoint is empty.")
        }
        if isLocalOrPrivateHost(host) {
            return ("safe", "Remote endpoint is local or private network.")
        }
        if proxyGuardActive {
            return ("proxyBypass", "A proxy is active, but this agent opened a direct public-network socket.")
        }
        return ("publicDirect", "Direct public-network socket; review if this agent should use a proxy.")
    }

    private func isProxyGuardActive() -> Bool {
        let proxyText = run("/usr/sbin/scutil", ["--proxy"])
        if proxyText.range(of: #"(HTTPEnable|HTTPSEnable|SOCKSEnable)\s*:\s*1"#, options: .regularExpression) != nil {
            return true
        }

        let proxyPorts: Set<Int> = [1080, 1086, 1087, 6152, 7890, 7891, 7897, 8080, 9090, 20171, 20172]
        let listeners = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN"])
        for line in listeners.components(separatedBy: .newlines) {
            guard let port = portFromEndpointLikeText(line),
                  proxyPorts.contains(port) else {
                continue
            }
            let lower = line.lowercased()
            if lower.contains("127.0.0.1") || lower.contains("localhost") || lower.contains("*:") || lower.contains("[::1]") {
                return true
            }
        }
        return false
    }

    private func isLocalOrPrivateHost(_ host: String) -> Bool {
        let trimmed = host.trimmingCharacters(in: CharacterSet(charactersIn: " []")).lowercased()
        if trimmed.isEmpty { return true }
        if ["localhost", "127.0.0.1", "::1", "0.0.0.0"].contains(trimmed) { return true }
        if trimmed.hasPrefix("fc") || trimmed.hasPrefix("fd") || trimmed.hasPrefix("fe80:") { return true }
        let parts = trimmed.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        let first = parts[0]
        let second = parts[1]
        if first == 10 || first == 127 || first == 169 && second == 254 { return true }
        if first == 172 && (16...31).contains(second) { return true }
        if first == 192 && second == 168 { return true }
        if first == 100 && (64...127).contains(second) { return true }
        if first == 198 && (18...19).contains(second) { return true }
        return false
    }

    private func portFromEndpointLikeText(_ text: String) -> Int? {
        if let colon = text.lastIndex(of: ":") {
            let suffix = text[text.index(after: colon)...]
            let digits = suffix.prefix { $0.isNumber }
            if let port = Int(digits) { return port }
        }
        if let dot = text.lastIndex(of: ".") {
            let suffix = text[text.index(after: dot)...]
            let digits = suffix.prefix { $0.isNumber }
            if let port = Int(digits) { return port }
        }
        return nil
    }

    private func networkRiskRank(_ risk: String) -> Int {
        switch risk {
        case "cleartext": return 3
        case "unknown": return 2
        case "proxy": return 1
        default: return 0
        }
    }

    private func networkSafetyRank(_ status: String?) -> Int {
        switch status {
        case "proxyBypass": return 5
        case "unsafe": return 4
        case "publicDirect": return 3
        case "unknown": return 2
        case "proxied": return 1
        default: return 0
        }
    }

    private func countAgentProcesses(_ processInfo: [Int: ProcessInfo]) -> [String: Int] {
        var result: [String: Int] = [:]
        for process in processInfo.values {
            if let name = matchingSpecName(process.command) {
                result[name, default: 0] += 1
            }
        }
        return result
    }

    private func countAgentPorts(processInfo: [Int: ProcessInfo], portsByPid: [Int: [Int]]) -> [String: Int] {
        var result: [String: Int] = [:]
        for (pid, ports) in portsByPid {
            guard let process = processInfo[pid], let name = matchingSpecName(process.command) else { continue }
            result[name, default: 0] += ports.count
        }
        return result
    }

    private func childrenMap(_ processInfo: [Int: ProcessInfo]) -> [Int: [Int]] {
        var result: [Int: [Int]] = [:]
        for process in processInfo.values {
            result[process.ppid, default: []].append(process.pid)
        }
        return result
    }

    private func descendants(of pid: Int, children: [Int: [Int]]) -> [Int] {
        var result: [Int] = []
        var stack = children[pid] ?? []
        var seen: Set<Int> = []
        while let next = stack.popLast() {
            guard seen.insert(next).inserted else { continue }
            result.append(next)
            stack.append(contentsOf: children[next] ?? [])
        }
        return result
    }

    private func isAgentSessionPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        guard lower.hasSuffix(".jsonl") || lower.hasSuffix(".json") || lower.hasSuffix(".log") || lower.hasSuffix(".db") || lower.hasSuffix(".vscdb") else {
            return false
        }
        if lower.contains("/.codex/sessions/") || lower.contains("/.claude/") || lower.contains("/.opencode/") {
            return true
        }
        return specForSessionPath(path) != nil
    }

    private func parseToolArgument(_ payload: [String: Any]) -> String {
        let raw = stringValue(payload, keys: ["arguments", "input"]) ?? ""
        guard let data = raw.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(raw.prefix(80))
        }
        let candidates = ["cmd", "command", "file_path", "path", "pattern", "query"]
        for key in candidates {
            if let value = args[key] as? String, !value.isEmpty {
                return String(value.prefix(80))
            }
        }
        return ""
    }

    private func messageContent(from payload: [String: Any]) -> String? {
        if let text = stringValue(payload, keys: ["message", "text", "content"]) {
            return text
        }
        guard let content = payload["content"] as? [[String: Any]] else { return nil }
        let parts = content.compactMap { item -> String? in
            let type = stringValue(item, keys: ["type"]) ?? ""
            guard type == "input_text" || type == "text" else { return nil }
            return stringValue(item, keys: ["text", "content"])
        }
        let joined = parts.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    private func instructionFromStoredText(_ value: String) -> String? {
        if let object = jsonObject(from: value) {
            return latestUserInstruction(in: object)
        }
        return normalizedInstruction(value)
    }

    private func latestUserInstruction(in value: Any?, depth: Int = 0) -> String? {
        guard depth < 10, let value else { return nil }
        if let dict = value as? [String: Any] {
            if isUserMessage(dict),
               let instruction = instructionText(fromUserMessage: dict) {
                return instruction
            }
            if let raw = dict["data"] as? String,
               let object = jsonObject(from: raw),
               let instruction = latestUserInstruction(in: object, depth: depth + 1) {
                return instruction
            }
            let preferredKeys = [
                "messages", "conversation", "history", "turns", "items", "entries",
                "records", "children", "parts", "message", "payload", "data"
            ]
            for key in preferredKeys {
                if let instruction = latestUserInstruction(in: dict[key], depth: depth + 1) {
                    return instruction
                }
            }
            for child in Array(dict.values).reversed() {
                if let instruction = latestUserInstruction(in: child, depth: depth + 1) {
                    return instruction
                }
            }
        } else if let array = value as? [Any] {
            for item in array.reversed() {
                if let instruction = latestUserInstruction(in: item, depth: depth + 1) {
                    return instruction
                }
            }
        } else if let string = value as? String,
                  let object = jsonObject(from: string) {
            return latestUserInstruction(in: object, depth: depth + 1)
        }
        return nil
    }

    private func isUserMessage(_ dict: [String: Any]) -> Bool {
        let role = (stringValue(dict, keys: ["role", "sender", "author", "speaker"]) ?? "").lowercased()
        if ["user", "human"].contains(role) { return true }
        let type = (stringValue(dict, keys: ["type", "eventType"]) ?? "").lowercased()
        return ["user", "user_message", "human_message"].contains(type)
    }

    private func instructionText(fromUserMessage dict: [String: Any]) -> String? {
        let candidates: [Any?] = [
            dict["msg_content"],
            dict["content"],
            dict["text"],
            dict["message"],
            dict["prompt"],
            dict["input"]
        ]
        for candidate in candidates {
            if let text = textContent(candidate),
               let instruction = normalizedInstruction(text) {
                return instruction
            }
            if let raw = candidate as? String,
               let object = jsonObject(from: raw),
               let instruction = latestUserInstruction(in: object) {
                return instruction
            }
        }
        return nil
    }

    private func normalizedInstruction(_ value: String?) -> String? {
        guard let value else { return nil }
        if isConversationTitleGeneratorPrompt(value),
           let embedded = embeddedUserMessage(fromTitleGeneratorPrompt: value),
           !embedded.isEmpty {
            return normalizedInstruction(embedded)
        }
        let visibleText = removingAgentMetadataBlocks(from: value)
        let collapsed = visibleText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        let lower = collapsed.lowercased()
        let noisyFragments = [
            "conversation title generator",
            "<skill>",
            "<permission-response",
            "<system-reminder",
            "<agent-context",
            "<task-completion-reminder",
            "<turn_aborted",
            "<codex_internal_context",
            "an async command you ran earlier has completed.",
            "sender (untrusted metadata):",
            "this session is being continued from a previous conversation",
            "pre-compaction memory flush",
            "a new session was started via /new or /reset",
            "conversation info (untrusted metadata):"
        ]
        guard !noisyFragments.contains(where: { lower.contains($0) }) else { return nil }
        guard collapsed != "{}" && collapsed != "[]" && lower != "null" else { return nil }
        return String(collapsed.prefix(500))
    }

    private func isConversationTitleGeneratorPrompt(_ value: String?) -> Bool {
        guard let value else { return false }
        let lower = value.lowercased()
        return lower.contains("conversation title generator") &&
            lower.contains("user message:")
    }

    private func embeddedUserMessage(fromTitleGeneratorPrompt value: String) -> String? {
        guard let marker = value.range(of: "User message:", options: [.caseInsensitive]) else { return nil }
        var remainder = String(value[marker.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stopMarkers = [
            "\n\nAssistant message:",
            "\n\nAssistant response:",
            "\n\nConversation:",
            "\n\nTitle:"
        ]
        for stop in stopMarkers {
            if let range = remainder.range(of: stop, options: [.caseInsensitive]) {
                remainder = String(remainder[..<range.lowerBound])
            }
        }
        return remainder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removingAgentMetadataBlocks(from text: String) -> String {
        var result = text
        let tags = [
            "skill",
            "permission-response",
            "system-reminder",
            "agent-context",
            "task-completion-reminder",
            "turn_aborted",
            "codex_internal_context",
            "user_profile_missing",
            "environment_context",
            "developer_context"
        ]
        for tag in tags {
            result = removingTaggedBlocks(named: tag, from: result)
        }
        return result
    }

    private func removingTaggedBlocks(named tag: String, from text: String) -> String {
        var result = text
        let opening = "<\(tag)"
        let closing = "</\(tag)>"
        while let start = result.range(of: opening, options: [.caseInsensitive]) {
            if let end = result.range(of: closing, options: [.caseInsensitive], range: start.upperBound..<result.endIndex) {
                result.removeSubrange(start.lowerBound..<end.upperBound)
            } else {
                result.removeSubrange(start.lowerBound..<result.endIndex)
            }
        }
        return result
    }

    private func jsonObject(from text: String) -> Any? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else { return nil }
        return try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))
    }

    private func parsePort(from line: String) -> Int? {
        guard let range = line.range(of: #"[:.](\d+)\s+\(LISTEN\)"#, options: .regularExpression) else { return nil }
        let fragment = String(line[range])
        let digits = fragment.filter(\.isNumber)
        return Int(digits)
    }

    private func matchingSpecName(_ command: String) -> String? {
        let cacheKey = String(command.prefix(1_024)).lowercased()
        commandAgentCacheLock.lock()
        if let cached = commandAgentCache[cacheKey] {
            commandAgentCacheLock.unlock()
            return cached
        }
        if nonAgentCommandCache.contains(cacheKey) {
            commandAgentCacheLock.unlock()
            return nil
        }
        commandAgentCacheLock.unlock()

        let matched: String?
        if shouldIgnoreAgentProcess(command: cacheKey) {
            matched = nil
        } else if cacheKey.contains("minimax") || cacheKey.contains("mavis") {
            matched = specs.first { $0.name == "MiniMax Agent" }?.name
        } else {
            matched = specs.first { spec in
                spec.processKeywords.contains { cacheKey.contains($0) }
            }?.name
        }

        commandAgentCacheLock.lock()
        if commandAgentCache.count + nonAgentCommandCache.count >= 2_048 {
            commandAgentCache.removeAll(keepingCapacity: true)
            nonAgentCommandCache.removeAll(keepingCapacity: true)
        }
        if let matched {
            commandAgentCache[cacheKey] = matched
        } else {
            nonAgentCommandCache.insert(cacheKey)
        }
        commandAgentCacheLock.unlock()
        return matched
    }

    private func shouldIgnoreAgentProcess(command: String) -> Bool {
        let executable = command
            .split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        let executableName = URL(fileURLWithPath: executable)
            .lastPathComponent
            .lowercased()

        if executableName.hasPrefix("tracefence")
            || command.contains("/tracefence.app/")
            || command.contains("/application support/tracefence/core/") {
            return true
        }

        let inspectionAndShellTools: Set<String> = [
            "bash", "sh", "zsh", "fish", "dash", "rg", "grep", "egrep", "fgrep",
            "sed", "awk", "cat", "head", "tail", "find", "xargs", "jq", "ps",
            "sample", "git", "xcodebuild", "swiftc", "swift-frontend", "clang",
            "clang++", "make", "cmake", "ninja", "sleep", "env", "osascript", "open"
        ]
        return inspectionAndShellTools.contains(executableName)
    }

    private func specForSessionPath(_ path: String) -> AgentSpec? {
        let lower = path.lowercased()
        if lower.contains("/.codex/") { return specs.first { $0.name == "Codex" } }
        if lower.contains("/.claude") || lower.contains("claude") { return specs.first { $0.name == "Claude Code" } }
        if lower.contains("opencode") { return specs.first { $0.name == "OpenCode" } }
        if lower.contains("openclaw") || lower.contains("qclaw") { return specs.first { $0.name == "OpenClaw" } }
        if lower.contains("/.hermes") || lower.contains("hermes") { return specs.first { $0.name == "Hermes" } }
        if lower.contains("cursor") { return specs.first { $0.name == "Cursor" } }
        if lower.contains("minimax") || lower.contains("mavis") { return specs.first { $0.name == "MiniMax Agent" } }
        return specs.first { spec in
            spec.roots.map(expand).contains { lower.contains($0.lowercased()) }
        }
    }

    private func agentName(for command: String, fallback: String) -> String {
        matchingSpecName(command) ?? fallback
    }

    private func resolvedAgentName(specName: String, parsed: ParsedSession) -> String {
        let lower = (parsed.cwd + " " + parsed.sourcePath).lowercased()
        if lower.contains("hermes-sandbox") || lower.contains("hermes_sandbox") {
            return "Hermes"
        }
        return specName
    }

    private func processCwd(pid: Int) -> String? {
        let output = run("/usr/sbin/lsof", ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"])
        for line in output.components(separatedBy: .newlines) where line.hasPrefix("n") {
            let path = String(line.dropFirst())
            if !path.isEmpty { return path }
        }
        return nil
    }

    private func lastPathSegment(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func run(_ executable: String, _ arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        let reader = DispatchGroup()
        let capture = AgentOverviewProcessOutputCapture(limit: 8 * 1_024 * 1_024)
        task.terminationHandler = { _ in finished.signal() }

        do {
            try task.run()
            reader.enter()
            DispatchQueue.global(qos: .utility).async {
                capture.drain(pipe.fileHandleForReading)
                reader.leave()
            }
        } catch {
            return ""
        }

        if finished.wait(timeout: .now() + 3) == .timedOut {
            task.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                _ = kill(task.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            _ = reader.wait(timeout: .now() + 2)
            return ""
        }

        _ = reader.wait(timeout: .now() + 2)
        return String(data: capture.snapshot(), encoding: .utf8) ?? ""
    }

    private func expand(_ path: String) -> String {
        path.replacingOccurrences(of: "~", with: home)
    }

    /// Reads at most `maximumBytes + 1` bytes and never maps or allocates the
    /// complete source first. The old `Data(contentsOf:)` then `data.count`
    /// pattern allocated multi-gigabyte Codex rollouts before rejecting them.
    private func boundedData(contentsOf url: URL, maximumBytes: Int) -> Data? {
        guard maximumBytes > 0,
              let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize,
              fileSize >= 0,
              fileSize <= maximumBytes,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            guard data.count <= maximumBytes else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private func sqliteText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let ptr = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: ptr)
    }

    private func dateFromMilliseconds(_ value: Int64) -> Date? {
        guard value > 0 else { return nil }
        let seconds = value > 10_000_000_000 ? TimeInterval(value) / 1000.0 : TimeInterval(value)
        return Date(timeIntervalSince1970: seconds)
    }

    private func dateFromISO(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        return Self.iso8601Formatter.date(from: value)
            ?? Self.fractionalISO8601Formatter.date(from: value)
    }

    private func authorizedBookmarkRoots() -> [String] {
        let paths = [SandboxPaths.shared.bookmarksPath, SandboxPaths.shared.scanBookmarksPath]
        var roots = Set<String>()
        for path in paths {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
                  let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
                continue
            }
            roots.formUnion(bookmarks.keys)
        }
        return roots.sorted()
    }

    private func sessionID(for file: URL, root: String) -> String {
        file.path.replacingOccurrences(of: root + "/", with: "").components(separatedBy: "/").prefix(3).joined(separator: "/")
    }

    private func intKeys(_ dict: [String: Any], _ keys: [String]) -> Int {
        keys.reduce(0) { partial, key in
            if let value = dict[key] as? Int { return partial + value }
            if let value = dict[key] as? Double { return partial + Int(value) }
            if let value = dict[key] as? String, let intValue = Int(value) { return partial + intValue }
            return partial
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func nestedValue(_ object: [String: Any], path: [String]) -> Any? {
        var current: Any? = object
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        return current
    }

    private func stringValue(_ object: [String: Any]?, keys: [String]) -> String? {
        guard let object else { return nil }
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private func textContent(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let dict = value as? [String: Any] {
            if let direct = stringValue(dict, keys: ["text", "content", "message", "msg_content", "input", "prompt"]) {
                return direct
            }
            for key in ["parts", "blocks", "children"] {
                if let text = textContent(dict[key]) { return text }
            }
            return nil
        }
        if let blocks = value as? [[String: Any]] {
            let text = blocks.compactMap { block in
                let type = (stringValue(block, keys: ["type"]) ?? "").lowercased()
                let ignoredTypes = ["tool_result", "toolresult", "tool_use", "tool", "image", "reasoning", "thinking"]
                if ignoredTypes.contains(type) { return nil }
                if !type.isEmpty, !["text", "input_text", "inputtext", "message", "user"].contains(type) { return nil }
                return stringValue(block, keys: ["text", "content"])
            }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }
        if let array = value as? [Any] {
            let text = array.compactMap { textContent($0) }.joined(separator: "\n")
            return text.isEmpty ? nil : text
        }
        return nil
    }

    private func dateFromAny(_ value: Any?) -> Date? {
        if let value = value as? String { return dateFromISO(value) }
        if let value = value as? Int { return dateFromMilliseconds(Int64(value)) }
        if let value = value as? Int64 { return dateFromMilliseconds(value) }
        if let value = value as? Double { return dateFromMilliseconds(Int64(value)) }
        return nil
    }

    private func date(from object: [String: Any]) -> Date? {
        let raw = stringValue(object, keys: ["timestamp", "created_at", "createdAt"])
            ?? stringValue(object["payload"] as? [String: Any], keys: ["timestamp", "created_at", "createdAt"])
        guard let raw else { return nil }
        return Self.iso8601Formatter.date(from: raw)
            ?? Self.fractionalISO8601Formatter.date(from: raw)
    }

    private func maxDate(_ lhs: Date?, _ rhs: Date) -> Date {
        guard let lhs else { return rhs }
        return max(lhs, rhs)
    }
}

private struct OverviewSlice: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

private struct OverviewGaugeCard: View {
    let title: String
    let valueText: String
    let detail: String
    let progress: Double
    let color: Color

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .stroke(Theme.Colors.sidebarBg, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(valueText)
                    .font(Theme.Font.captionMedium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(width: 58, height: 58)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .cardStyle(padding: Theme.Spacing.md, cornerRadius: Theme.Radius.md)
    }
}

private struct OverviewBarsCard: View {
    let title: String
    let slices: [OverviewSlice]
    let valueFormatter: (Double) -> String

    private var maxValue: Double {
        max(slices.map(\.value).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(title)
                .font(Theme.Font.subheadlineMedium)
                .foregroundStyle(Theme.Colors.textPrimary)

            if slices.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("—")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(slices) { slice in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Label(slice.label, systemImage: "circle.fill")
                                    .font(Theme.Font.captionMedium)
                                    .foregroundStyle(slice.color)
                                Spacer()
                                Text(valueFormatter(slice.value))
                                    .font(Theme.Font.captionMedium)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            GeometryReader { proxy in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                        .fill(Theme.Colors.sidebarBg)
                                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                        .fill(slice.color)
                                        .frame(width: max(proxy.size.width * (slice.value / maxValue), 4))
                                }
                            }
                            .frame(height: 10)
                        }
                    }
                }
                .frame(minHeight: 160, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardStyle(padding: Theme.Spacing.lg, cornerRadius: Theme.Radius.md)
    }
}

struct AppOverviewTab: View {
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var usageInsightsService: AgentUsageInsightsService
    @ObservedObject var overviewStore: AgentMonitorOverviewStore
    @StateObject private var sessionScanner = AgentSessionScanner.shared
    @State private var didStartScan = false

    private var monitor: OperationMonitor { service.operationMonitor }

    private var rows: [AgentMonitorOverviewRow] {
        let discoveredByName = Dictionary(uniqueKeysWithValues: sessionScanner.discoveredAgents.map { ($0.name, $0) })
        let usageByName = Dictionary(uniqueKeysWithValues: overviewStore.snapshots.map { ($0.agentName, $0) })
        let operationRecords = service.operationRecords.isEmpty ? monitor.records : service.operationRecords
        let recordCounts = Dictionary(grouping: operationRecords.filter(isDisplayableAgentRecord), by: \.agentName)
            .mapValues(\.count)
        let names = Set(discoveredByName.keys)
            .union(usageByName.keys)
            .union(recordCounts.keys)
            .sorted { lhs, rhs in
                let leftDate = discoveredByName[lhs]?.latestActivity ?? usageByName[lhs]?.latestActivity ?? .distantPast
                let rightDate = discoveredByName[rhs]?.latestActivity ?? usageByName[rhs]?.latestActivity ?? .distantPast
                if leftDate == rightDate { return lhs < rhs }
                return leftDate > rightDate
            }

        return names.map { name in
            let discovered = discoveredByName[name]
            let usage = usageByName[name]
            return AgentMonitorOverviewRow(
                id: name,
                agentName: name,
                sessionCount: max(discovered?.sessionCount ?? 0, usage?.sessionCount ?? 0),
                operationCount: recordCounts[name] ?? 0,
                totalTokens: usage?.totalTokens ?? 0,
                contextPercent: usage?.contextPercent ?? 0,
                processCount: usage?.processCount ?? 0,
                portCount: usage?.portCount ?? 0,
                latestActivity: [discovered?.latestActivity, usage?.latestActivity].compactMap { $0 }.max(),
                projectPath: discovered?.projectDirs.first ?? usage?.projectPath ?? discovered?.dataPath ?? usage?.sourcePath ?? ""
            )
        }
    }

    private var activeAgentCount: Int {
        rows.filter { $0.processCount > 0 || $0.operationCount > 0 }.count
    }

    private var totalSessions: Int { rows.reduce(0) { $0 + $1.sessionCount } }
    private var totalPorts: Int { rows.reduce(0) { $0 + $1.portCount } }
    private var totalOperations: Int { rows.reduce(0) { $0 + $1.operationCount } }
    private var totalTokens: Int {
        Int(clamping: usageInsightsService.snapshot(for: .combined).allTime.total)
    }
    private var cleanupTotalSize: Int64 { cappedCleanupSize(service.scanItems.reduce(0) { $0 + $1.size }) }
    private var appTotalSize: Int64 { service.installedApps.reduce(0) { $0 + $1.totalSize } }

    private var cleanupRiskSlices: [OverviewSlice] {
        let grouped = Dictionary(grouping: service.scanItems, by: \.risk)
        return [
            OverviewSlice(label: localizer.safe, value: Double(grouped["safe"]?.reduce(Int64(0)) { $0 + $1.size } ?? 0), color: Theme.Colors.success),
            OverviewSlice(label: localizer.warning, value: Double(grouped["caution"]?.reduce(Int64(0)) { $0 + $1.size } ?? 0), color: Theme.Colors.warning),
            OverviewSlice(label: localizer.dangerous, value: Double(grouped["dangerous"]?.reduce(Int64(0)) { $0 + $1.size } ?? 0), color: Theme.Colors.danger)
        ].filter { $0.value > 0 }
    }

    private var cleanupCategorySlices: [OverviewSlice] {
        let grouped = Dictionary(grouping: service.scanItems, by: \.category)
        return grouped.map { category, items in
            OverviewSlice(
                label: localizer.localizedSubCategory(category),
                value: Double(items.reduce(Int64(0)) { $0 + $1.size }),
                color: categoryColor(category)
            )
        }
        .filter { $0.value > 0 }
        .sorted { $0.value > $1.value }
        .prefix(6)
        .map { $0 }
    }

    private var appFootprintSlices: [OverviewSlice] {
        let grouped = Dictionary(grouping: service.installedApps, by: \.appType)
        return AppInfo.AppType.allCases.map { type in
            let size = grouped[type]?.reduce(Int64(0)) { $0 + $1.totalSize } ?? 0
            return OverviewSlice(label: type.localizedLabel(localizer), value: Double(size), color: type.tabColor)
        }.filter { $0.value > 0 }
    }

    private func cappedCleanupSize(_ size: Int64) -> Int64 {
        guard let used = service.diskInfo?.used, used > 0 else { return size }
        return min(size, used)
    }

    private var appCountSlices: [OverviewSlice] {
        let grouped = Dictionary(grouping: service.installedApps, by: \.appType)
        return AppInfo.AppType.allCases.map { type in
            OverviewSlice(label: type.localizedLabel(localizer), value: Double(grouped[type]?.count ?? 0), color: type.tabColor)
        }.filter { $0.value > 0 }
    }

    private var operationTypeSlices: [OverviewSlice] {
        let operationRecords = service.operationRecords.isEmpty ? monitor.records : service.operationRecords
        let grouped = Dictionary(grouping: operationRecords.filter(isDisplayableAgentRecord), by: \.operationType)
        return OperationRecord.OperationType.allCases.map { type in
            OverviewSlice(label: type.localizedLabel(localizer), value: Double(grouped[type]?.count ?? 0), color: operationTypeColor(type))
        }.filter { $0.value > 0 }
    }

    private var tokenUsageSlices: [OverviewSlice] {
        rows
            .filter { $0.totalTokens > 0 }
            .sorted { lhs, rhs in
                if lhs.totalTokens == rhs.totalTokens { return lhs.agentName < rhs.agentName }
                return lhs.totalTokens > rhs.totalTokens
            }
            .prefix(6)
            .enumerated()
            .map { index, row in
                let colors: [Color] = [Theme.Colors.accent, Theme.Colors.info, Theme.Colors.purple, Theme.Colors.warning, Theme.Colors.danger, Theme.Colors.textSecondary]
                return OverviewSlice(label: row.agentName, value: Double(row.totalTokens), color: colors[index % colors.count])
            }
    }

    private var agentRuntimeSlices: [OverviewSlice] {
        [
            OverviewSlice(label: localizer.activeAgents, value: Double(activeAgentCount), color: Theme.Colors.success),
            OverviewSlice(label: localizer.openPorts, value: Double(totalPorts), color: Theme.Colors.warning),
            OverviewSlice(label: localizer.totalOps, value: Double(totalOperations), color: Theme.Colors.info)
        ].filter { $0.value > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "chart.bar.xaxis",
                title: localizer.navOverview,
                subtitle: localizer.overviewSubtitle,
                color: Theme.Colors.accent
            )

            AgentCommandDashboardView(
                store: overviewStore,
                monitor: monitor,
                onRefresh: refresh
            )
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear {
            if !didStartScan {
                didStartScan = true
                refresh()
            }
        }
    }

    private var summaryCards: some View {
        HStack(spacing: Theme.Spacing.sm) {
            StatCardView(icon: "internaldrive", iconColor: Theme.Colors.info, title: localizer.diskSpaceLabel, value: service.diskInfo.map { formatGB($0.freeGb) } ?? "—", subtitle: localizer.available)
            StatCardView(icon: "externaldrive", iconColor: Theme.Colors.warning, title: localizer.cleanupCandidates, value: formatBytes(cleanupTotalSize), subtitle: nil)
            StatCardView(icon: "eye.fill", iconColor: Theme.Colors.success, title: localizer.agentMonitorTitle, value: "\(totalOperations)", subtitle: localizer.totalOps)
            StatCardView(icon: "sum", iconColor: Theme.Colors.info, title: localizer.tokenScopeTotalTokens, value: compactCount(totalTokens), subtitle: nil)
            if !service.installedApps.isEmpty {
                StatCardView(icon: "app.badge", iconColor: Theme.Colors.accent, title: localizer.navApp, value: "\(service.installedApps.count)", subtitle: localizer.itemsLabel)
            }
        }
    }

    private var healthCharts: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            OverviewGaugeCard(
                title: localizer.diskUsage,
                valueText: service.diskInfo.map { "\(Int($0.usedPct))%" } ?? "—",
                detail: service.diskInfo.map { "\(formatGB($0.freeGb)) \(localizer.freeSpace)" } ?? localizer.notFound,
                progress: min(max((service.diskInfo?.usedPct ?? 0) / 100.0, 0), 1),
                color: Theme.Colors.info
            )
            OverviewGaugeCard(
                title: localizer.memoryUsage,
                valueText: service.hardwareInfo.map { "\(Int($0.memoryPressurePct))%" } ?? "—",
                detail: service.hardwareInfo.map { "\(formatGB($0.memoryFreeGb)) \(localizer.freeSpace)" } ?? localizer.notFound,
                progress: min(max((service.hardwareInfo?.memoryPressurePct ?? 0) / 100.0, 0), 1),
                color: Theme.Colors.purple
            )
            OverviewGaugeCard(
                title: localizer.cpuUsage,
                valueText: service.hardwareInfo.map { "\(Int($0.cpuUsage))%" } ?? "—",
                detail: service.hardwareInfo.map { "\($0.cpuCoreCount) \(localizer.cpuCores)" } ?? localizer.notFound,
                progress: min(max((service.hardwareInfo?.cpuUsage ?? 0) / 100.0, 0), 1),
                color: Theme.Colors.success
            )
        }
    }

    private var overviewChartGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Theme.Spacing.lg)], spacing: Theme.Spacing.lg) {
            if !cleanupCategorySlices.isEmpty {
                cleanupCategoryPanel
            }
            if !cleanupRiskSlices.isEmpty {
                cleanupRiskPanel
            }
            if !operationTypeSlices.isEmpty {
                agentOperationsPanel
            }
            if !agentRuntimeSlices.isEmpty {
                agentRuntimePanel
            }
            if !tokenUsageSlices.isEmpty {
                tokenUsagePanel
            }
            if !appFootprintSlices.isEmpty {
                appFootprintPanel
            }
            if !appCountSlices.isEmpty {
                appCountPanel
            }
        }
    }

    private var cleanupCategoryPanel: some View {
        OverviewBarsCard(
            title: localizer.overviewCleanupByCategory,
            slices: cleanupCategorySlices,
            valueFormatter: { formatBytes(Int64($0)) }
        )
    }

    private var cleanupRiskPanel: some View {
        OverviewBarsCard(
            title: localizer.cleanupRisk,
            slices: cleanupRiskSlices,
            valueFormatter: { formatBytes(Int64($0)) }
        )
    }

    private var appFootprintPanel: some View {
        OverviewBarsCard(
            title: localizer.appFootprint,
            slices: appFootprintSlices,
            valueFormatter: { formatBytes(Int64($0)) }
        )
    }

    private var appCountPanel: some View {
        OverviewBarsCard(
            title: localizer.overviewAppCounts,
            slices: appCountSlices,
            valueFormatter: { "\(Int($0))" }
        )
    }

    private var agentOperationsPanel: some View {
        OverviewBarsCard(
            title: localizer.overviewAgentOperations,
            slices: operationTypeSlices,
            valueFormatter: { "\(Int($0))" }
        )
    }

    private var agentRuntimePanel: some View {
        OverviewBarsCard(
            title: localizer.overviewAgentRuntime,
            slices: agentRuntimeSlices,
            valueFormatter: { compactCount(Int($0)) }
        )
    }

    private var tokenUsagePanel: some View {
        OverviewBarsCard(
            title: localizer.overviewTokenUsage,
            slices: tokenUsageSlices,
            valueFormatter: { compactCount(Int($0)) }
        )
    }

    private func refresh() {
        service.refreshDiskInfo()
        service.refreshHardwareInfo()
        service.refreshCachedSurfacesInBackground()
        overviewStore.refresh()
        sessionScanner.localizer = localizer
        sessionScanner.scanAllAgents()
        if service.installedApps.isEmpty {
            Task { await service.scanInstalledApps() }
        }
        service.importKnownAgentHistory()
    }

    private func isDisplayableAgentRecord(_ record: OperationRecord) -> Bool {
        let name = record.agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "—" || name == "Unattributed Agent" { return false }
        if name == localizer.systemProcess || name.localizedCaseInsensitiveContains("system process") { return false }
        return true
    }

    private func categoryColor(_ category: String) -> Color {
        let lower = category.lowercased()
        if lower.contains("agent") { return Theme.Colors.purple }
        if lower.contains("开发") || lower.contains("dev") { return Theme.Colors.info }
        if lower.contains("系统") || lower.contains("system") { return Theme.Colors.info }
        if lower.contains("浏览") || lower.contains("browser") { return Theme.Colors.warning }
        if lower.contains("办公") || lower.contains("office") { return Theme.Colors.success }
        return Theme.Colors.accent
    }

    private func operationTypeColor(_ type: OperationRecord.OperationType) -> Color {
        switch type {
        case .create: return Theme.Colors.success
        case .modify: return Theme.Colors.info
        case .delete: return Theme.Colors.danger
        case .move: return Theme.Colors.warning
        case .rename: return Theme.Colors.purple
        case .read: return Theme.Colors.info
        case .execute: return Theme.Colors.purple
        }
    }

    private func compactCount(_ value: Int) -> String {
        AgentUsageTokenFormatter.string(Int64(value))
    }

    private func formatBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    private func formatGB(_ value: Double) -> String {
        String(format: "%.1f GB", value)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct CommandCenterPanel<Content: View>: View {
    let title: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 2)
                .background(color.opacity(0.10))
                .clipShape(Capsule())
                .offset(y: -2)

            content
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(Theme.Colors.elevatedCardBg.opacity(0.78))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(Theme.Colors.separator, lineWidth: 1)
                )
        )
        .shadow(color: Theme.Shadow.smColor, radius: 8, y: 4)
    }
}

private struct CommandCenterBlockMeter: View {
    let progress: Double
    let color: Color

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Double(index) < min(max(progress, 0), 1) * 12 ? color : Theme.Colors.textTertiary.opacity(0.22))
            }
        }
    }
}

private struct CommandCenterSafeAction: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct CommandCenterDisabledAction: View {
    @EnvironmentObject var localizer: Localizer
    let icon: String
    let title: String

    var body: some View {
        Button {} label: {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(true)
        .help(localizer.unavailableInMacAppStoreBuild)
    }
}

private struct AgentCommandCenterView: View {
    @ObservedObject var store: AgentMonitorOverviewStore
    @ObservedObject var monitor: OperationMonitor
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var service: ScannerService
    let onRefresh: () -> Void

    @State private var selectedSessionID: String?
    @State private var filterText = ""

    private var sessions: [AgentMonitorSessionSnapshot] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.sessions }
        return store.sessions.filter {
            $0.agentName.lowercased().contains(query) ||
            $0.projectName.lowercased().contains(query) ||
            $0.projectPath.lowercased().contains(query) ||
            $0.model.lowercased().contains(query) ||
            $0.currentTask.lowercased().contains(query)
        }
    }

    private var selectedSession: AgentMonitorSessionSnapshot? {
        if let selectedSessionID,
           let match = sessions.first(where: { $0.id == selectedSessionID }) {
            return match
        }
        return sessions.first
    }

    private var totalTokens: Int {
        max(
            sessions.reduce(0) { $0 + $1.tokens.total },
            store.snapshots.reduce(0) { $0 + $1.totalTokens }
        )
    }

    private var projectRows: [(name: String, context: Double, tokens: Int, count: Int)] {
        Dictionary(grouping: sessions, by: \.projectName)
            .map { name, sessions in
                (
                    name: name,
                    context: sessions.map(\.contextPercent).max() ?? 0,
                    tokens: sessions.reduce(0) { $0 + $1.tokens.total },
                    count: sessions.count
                )
            }
            .sorted {
                if $0.context == $1.context { return $0.tokens > $1.tokens }
                return $0.context > $1.context
            }
    }

    private var ports: [(port: Int, session: AgentMonitorSessionSnapshot)] {
        sessions.flatMap { session in
            session.ports.map { (port: $0, session: session) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            if monitor.needsReauthorization {
                authorizationBanner
            }

            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    contextPanel

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(minimum: 220), spacing: Theme.Spacing.md),
                            GridItem(.flexible(minimum: 260), spacing: Theme.Spacing.md),
                            GridItem(.flexible(minimum: 230), spacing: Theme.Spacing.md),
                            GridItem(.flexible(minimum: 230), spacing: Theme.Spacing.md),
                            GridItem(.flexible(minimum: 230), spacing: Theme.Spacing.md)
                        ],
                        spacing: Theme.Spacing.md
                    ) {
                        quotaPanel
                        tokensPanel
                        projectsPanel
                        portsPanel
                        mcpPanel
                    }

                    sessionsPanel
                    detailPanel
                }
                .padding(Theme.Spacing.lg)
            }
            .background(Color.black.opacity(0.04))
        }
        .onAppear {
            onRefresh()
            normalizeSelection()
        }
        .onChange(of: store.sessions.map(\.id).joined(separator: "|")) { _ in
            normalizeSelection()
        }
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.xs) {
                Text(localizer.t("智能体指挥中心", en: "Agent Command Center", zhHant: "智能體指揮中心", ja: "Agent コマンドセンター", ko: "Agent 명령 센터", mt: "Agent Command Center"))
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("Σ\(compactCount(totalTokens))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("\(localizer.t("上下文", en: "Context", zhHant: "上下文", ja: "コンテキスト", ko: "컨텍스트", mt: "Context"))%\(Int((sessions.map(\.contextPercent).max() ?? 0) * 100))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(contextColor(sessions.map(\.contextPercent).max() ?? 0))
            }

            Spacer()

            TextField(localizer.t("过滤", en: "Filter", zhHant: "篩選", ja: "フィルター", ko: "필터", mt: "Filter"), text: $filterText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .frame(width: 180)

            Button { moveSelection(-1) } label: {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(localizer.overviewPreviousSession)

            Button { moveSelection(1) } label: {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(localizer.overviewNextSession)

            Button { copySelectedPath() } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedSession == nil)
            .help(localizer.copyPath)

            Button { openSelectedProject() } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedSession?.projectPath.isEmpty ?? true)
            .help(localizer.openInFinder)

            Button {} label: {
                Image(systemName: "xmark.octagon")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)
            .help(localizer.t("App Store 版本禁用进程终止", en: "Process termination is disabled in the App Store build", zhHant: "App Store 版本已停用程序終止", ja: "App Store 版ではプロセス終了は無効です", ko: "App Store 빌드에서는 프로세스 종료가 비활성화되어 있습니다", mt: "Process termination is disabled in the App Store build"))
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.sidebarBg.opacity(0.48))
    }

    private var authorizationBanner: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.permissionExpired)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(localizer.selectMonitorDirs)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                monitor.requestAccessForStalePaths()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    service.importKnownAgentHistory()
                    onRefresh()
                }
            } label: {
                Label(localizer.reauthorize, systemImage: "lock.open")
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 1)
                    .background(Theme.Colors.warning)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.warning.opacity(0.08))
    }

    private var contextPanel: some View {
        CommandCenterPanel(title: localizer.t("1 上下文", en: "1 Context", zhHant: "1 上下文", ja: "1 コンテキスト", ko: "1 컨텍스트", mt: "1 Context"), color: Theme.Colors.success) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("\(localizer.t("Token 速率", en: "Token rate", zhHant: "Token 速率", ja: "Token レート", ko: "Token 속도", mt: "Token rate"))  0/min")
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.success)
                    Spacer(minLength: 18)
                    Text("\(compactCount(totalTokens)) \(localizer.overviewTotal)")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    HStack {
                        Text(localizer.overviewProject).frame(width: 132, alignment: .leading)
                        Text(localizer.contextWindow).frame(width: 118, alignment: .leading)
                        Text(localizer.t("窗口", en: "Window", zhHant: "視窗", ja: "ウィンドウ", ko: "창", mt: "Window")).frame(width: 76, alignment: .leading)
                    }
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textSecondary)

                    ForEach(projectRows.prefix(5), id: \.name) { row in
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(row.name)
                                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                .lineLimit(1)
                                .frame(width: 132, alignment: .leading)
                            CommandCenterBlockMeter(progress: row.context, color: contextColor(row.context))
                                .frame(width: 92, height: 12)
                            Text("\(Int(row.context * 100))%")
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(contextColor(row.context))
                                .frame(width: 38, alignment: .trailing)
                            Text(selectedWindowText(forProject: row.name))
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .frame(width: 76, alignment: .leading)
                        }
                    }

                    if projectRows.isEmpty {
                        Text(localizer.overviewNoActiveSession)
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            .frame(minHeight: 130)
        }
    }

    private var quotaPanel: some View {
        CommandCenterPanel(title: localizer.t("2 配额", en: "2 Quota", zhHant: "2 配額", ja: "2 クォータ", ko: "2 할당량", mt: "2 Quota"), color: Theme.Colors.success) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text("CLAUDE").frame(width: 86, alignment: .leading)
                    Text("CODEX").frame(width: 86, alignment: .leading)
                }
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)

                HStack {
                    Text("— \(localizer.t("无数据", en: "No data", zhHant: "無資料", ja: "データなし", ko: "데이터 없음", mt: "No data"))").frame(width: 86, alignment: .leading)
                    Text(localizer.t("只读", en: "Read-only", zhHant: "唯讀", ja: "読み取り専用", ko: "읽기 전용", mt: "Read-only")).frame(width: 86, alignment: .leading)
                        .foregroundStyle(Theme.Colors.success)
                }
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textTertiary)

                Text("\(localizer.overviewTotal) \(compactCount(totalTokens))  0/min")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.top, Theme.Spacing.lg)

                Text(localizer.t("直售版本机读取 · 不上传数据", en: "Direct build reads locally · no data upload", zhHant: "直售版本機讀取 · 不上傳資料", ja: "直販版はローカルで読み取り · データはアップロードしません", ko: "직접 배포 빌드는 로컬에서 읽음 · 데이터 업로드 없음", mt: "Direct build reads locally · no data upload"))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .frame(minHeight: 135, alignment: .topLeading)
        }
    }

    private var tokensPanel: some View {
        let session = selectedSession
        return CommandCenterPanel(title: "3 Token", color: Theme.Colors.warning) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                tokenLine(localizer.overviewTotal, value: session?.tokens.total ?? totalTokens, color: Theme.Colors.textPrimary)
                tokenLine(localizer.overviewInput, value: session?.tokens.input ?? 0, color: Theme.Colors.success)
                tokenLine(localizer.overviewOutput, value: session?.tokens.output ?? 0, color: Theme.Colors.danger)
                tokenLine(localizer.overviewCacheRead, value: session?.tokens.cacheRead ?? 0, color: Theme.Colors.info)
                tokenLine(localizer.t("缓存写", en: "Cache Write", zhHant: "快取寫入", ja: "キャッシュ書込", ko: "캐시 쓰기", mt: "Cache Write"), value: 0, color: Theme.Colors.textTertiary)
                Text("\(session?.turnCount ?? 0) \(localizer.overviewTurns)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, 2)
            }
            .frame(minHeight: 135, alignment: .topLeading)
        }
    }

    private func tokenLine(_ label: String, value: Int, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(label)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 54, alignment: .leading)
            CommandCenterBlockMeter(progress: tokenProgress(value), color: color)
                .frame(width: 76, height: 10)
            Text(compactCount(value))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var projectsPanel: some View {
        CommandCenterPanel(title: localizer.t("4 项目", en: "4 Projects", zhHant: "4 專案", ja: "4 プロジェクト", ko: "4 프로젝트", mt: "4 Projects"), color: Theme.Colors.warning) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(projectRows.prefix(5), id: \.name) { row in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Text("\(localizer.overviewSessions) \(row.count) · \(compactCount(row.tokens)) · Git \(localizer.t("只读", en: "read-only", zhHant: "唯讀", ja: "読み取り専用", ko: "읽기 전용", mt: "read-only"))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                }
                if projectRows.isEmpty {
                    Text(localizer.overviewNoProject)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(minHeight: 135, alignment: .topLeading)
        }
    }

    private var portsPanel: some View {
        CommandCenterPanel(title: localizer.t("5 端口", en: "5 Ports", zhHant: "5 連接埠", ja: "5 ポート", ko: "5 포트", mt: "5 Ports"), color: Theme.Colors.purple) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text(localizer.t("端口", en: "Port", zhHant: "連接埠", ja: "ポート", ko: "포트", mt: "Port")).frame(width: 58, alignment: .leading)
                    Text(localizer.overviewSession).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)

                ForEach(ports.prefix(5), id: \.port) { item in
                    HStack {
                        Text("\(item.port)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.Colors.warning)
                            .frame(width: 58, alignment: .leading)
                        Text(item.session.projectName)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                if ports.isEmpty {
                    Text(localizer.t("无开放端口", en: "No open ports", zhHant: "無開放連接埠", ja: "開いているポートはありません", ko: "열린 포트 없음", mt: "No open ports"))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Text(localizer.t("终止端口：App Store 版禁用", en: "Port termination: disabled in App Store build", zhHant: "終止連接埠：App Store 版停用", ja: "ポート終了: App Store 版では無効", ko: "포트 종료: App Store 빌드에서 비활성화", mt: "Port termination: disabled in App Store build"))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.sm)
            }
            .frame(minHeight: 135, alignment: .topLeading)
        }
    }

    private var mcpPanel: some View {
        CommandCenterPanel(title: localizer.t("7 MCP 服务", en: "7 MCP Services", zhHant: "7 MCP 服務", ja: "7 MCP サービス", ko: "7 MCP 서비스", mt: "7 MCP Services"), color: Theme.Colors.purple) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Text(localizer.t("父进程", en: "Parent", zhHant: "父程序", ja: "親プロセス", ko: "상위 프로세스", mt: "Parent")).frame(width: 86, alignment: .leading)
                    Text(localizer.configCol).frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)

                Text(localizer.t("无 MCP 服务器", en: "No MCP servers", zhHant: "無 MCP 伺服器", ja: "MCP サーバーなし", ko: "MCP 서버 없음", mt: "No MCP servers"))
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.xs)

                Text(localizer.t("读取配置需用户授权目录", en: "Reading config requires an authorized folder", zhHant: "讀取配置需要使用者授權目錄", ja: "設定の読み取りには許可済みフォルダが必要です", ko: "설정 읽기에는 승인된 폴더가 필요합니다", mt: "Reading config requires an authorized folder"))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.lg)
            }
            .frame(minHeight: 135, alignment: .topLeading)
        }
    }

    private var sessionsPanel: some View {
        CommandCenterPanel(title: localizer.t("6 会话", en: "6 Sessions", zhHant: "6 會話", ja: "6 セッション", ko: "6 세션", mt: "6 Sessions"), color: Theme.Colors.danger) {
            VStack(spacing: 0) {
                sessionHeader

                ForEach(Array(sessions.prefix(10).enumerated()), id: \.element.id) { index, session in
                    sessionTableRow(session, index: index)
                }

                if sessions.isEmpty {
                    VStack(spacing: Theme.Spacing.sm) {
                        Text(localizer.overviewNoActiveSession)
                            .font(.system(size: 15, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Button {
                            monitor.requestAccessForStalePaths()
                        } label: {
                            Label(localizer.t("授权 ~/.codex / ~/.claude", en: "Authorize ~/.codex / ~/.claude", zhHant: "授權 ~/.codex / ~/.claude", ja: "~/.codex / ~/.claude を許可", ko: "~/.codex / ~/.claude 승인", mt: "Authorize ~/.codex / ~/.claude"), systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .frame(maxWidth: .infinity, minHeight: 96)
                }
            }
        }
    }

    private var sessionHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("AI").frame(width: 54, alignment: .leading)
            Text(localizer.overviewProject).frame(width: 130, alignment: .leading)
            Text(localizer.overviewSession).frame(width: 96, alignment: .leading)
            Text(localizer.t("时间", en: "Time", zhHant: "時間", ja: "時刻", ko: "시간", mt: "Time")).frame(width: 72, alignment: .leading)
            Text(localizer.configCol).frame(width: 90, alignment: .leading)
            Text(localizer.overviewSummary).frame(maxWidth: .infinity, alignment: .leading)
            Text(localizer.status).frame(width: 78, alignment: .leading)
            Text(localizer.overviewModel).frame(width: 92, alignment: .leading)
            Text(localizer.contextWindow).frame(width: 74, alignment: .trailing)
            Text("Token").frame(width: 86, alignment: .trailing)
            Text(localizer.overviewTurns).frame(width: 44, alignment: .trailing)
        }
        .font(.system(size: 13, weight: .bold, design: .monospaced))
        .foregroundStyle(Theme.Colors.textSecondary)
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private func sessionTableRow(_ session: AgentMonitorSessionSnapshot, index: Int) -> some View {
        let selected = selectedSession?.id == session.id
        return Button {
            selectedSessionID = session.id
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text("\(selected ? "▶" : " ") >\(session.agentName == "Codex" ? "CD" : "AG")")
                    .frame(width: 54, alignment: .leading)
                    .foregroundStyle(selected ? Theme.Colors.info : Theme.Colors.textSecondary)
                Text(session.projectName)
                    .frame(width: 130, alignment: .leading)
                    .lineLimit(1)
                Text(shortSessionId(session.sessionId))
                    .frame(width: 96, alignment: .leading)
                    .foregroundStyle(Theme.Colors.warning)
                Text(sessionInstructionTimeText(session))
                    .frame(width: 72, alignment: .leading)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(configRoot(for: session))
                    .frame(width: 90, alignment: .leading)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                Text(session.currentTask)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("● \(localizedStatus(session.status))")
                    .frame(width: 78, alignment: .leading)
                    .foregroundStyle(session.status == "Executing" ? Theme.Colors.danger : Theme.Colors.warning)
                Text(sessionModelText(session))
                    .frame(width: 92, alignment: .leading)
                    .lineLimit(1)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(sessionContextPercentText(session))
                    .frame(width: 74, alignment: .trailing)
                    .foregroundStyle(contextColor(session.contextPercent))
                Text(sessionTokenText(session))
                    .frame(width: 86, alignment: .trailing)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(session.turnCount)")
                    .frame(width: 44, alignment: .trailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .font(.system(size: 13, weight: selected ? .bold : .semibold, design: .monospaced))
            .foregroundStyle(selected ? Color.white.opacity(0.92) : Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(selected ? Theme.Colors.danger.opacity(0.45) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
    }

    private var detailPanel: some View {
        CommandCenterPanel(title: selectedSession.map { "\(localizer.overviewSession) (▶\(shortSessionId($0.sessionId)) · \($0.projectPath))" } ?? localizer.overviewSession, color: Theme.Colors.danger) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                if let session = selectedSession {
                    HStack(spacing: Theme.Spacing.lg) {
                        Text("\(sessionModelText(session)) · \(session.turnCount) \(localizer.overviewTurns) · \(session.toolCount) \(localizer.tokenScopeTools)")
                        Text("\(localizer.contextWindow) \(sessionContextText(session))")
                        Text("pid \(session.pid.map(String.init) ?? "—")")
                    }
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)

                    Text(session.currentTask)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(2)

                    HStack(spacing: Theme.Spacing.sm) {
                        CommandCenterSafeAction(icon: "doc.on.doc", title: localizer.t("复制", en: "Copy", zhHant: "複製", ja: "コピー", ko: "복사", mt: "Copy")) { copySelectedPath() }
                        CommandCenterSafeAction(icon: "folder", title: localizer.t("打开", en: "Open", zhHant: "開啟", ja: "開く", ko: "열기", mt: "Open")) { openSelectedProject() }
                        CommandCenterDisabledAction(icon: "xmark.octagon", title: localizer.t("终止", en: "Terminate", zhHant: "終止", ja: "終了", ko: "종료", mt: "Terminate"))
                        CommandCenterDisabledAction(icon: "network", title: localizer.t("断开端口", en: "Disconnect Port", zhHant: "斷開連接埠", ja: "ポート切断", ko: "포트 연결 해제", mt: "Disconnect Port"))
                        Spacer()
                        Text(localizer.t("直售版监控 · 本机数据源", en: "Direct monitor · local data sources", zhHant: "直售版監控 · 本機資料源", ja: "直販版モニター · ローカルデータソース", ko: "직접 배포 모니터 · 로컬 데이터 소스", mt: "Direct monitor · local data sources"))
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                } else {
                    Text(localizer.t("暂无会话。请授权 Agent 数据目录或启动 Codex/Claude 会话。", en: "No sessions yet. Authorize an Agent data folder or start a Codex/Claude session.", zhHant: "暫無會話。請授權 Agent 資料目錄或啟動 Codex/Claude 會話。", ja: "セッションはまだありません。Agent データフォルダを許可するか Codex/Claude セッションを開始してください。", ko: "아직 세션이 없습니다. Agent 데이터 폴더를 승인하거나 Codex/Claude 세션을 시작하세요.", mt: "No sessions yet. Authorize an Agent data folder or start a Codex/Claude session."))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            .frame(minHeight: 110, alignment: .topLeading)
        }
    }

    private func normalizeSelection() {
        guard !sessions.isEmpty else {
            selectedSessionID = nil
            return
        }
        if let selectedSessionID,
           sessions.contains(where: { $0.id == selectedSessionID }) {
            return
        }
        selectedSessionID = sessions.first?.id
    }

    private func moveSelection(_ offset: Int) {
        guard !sessions.isEmpty else { return }
        let current = selectedSession.flatMap { session in
            sessions.firstIndex(where: { $0.id == session.id })
        } ?? 0
        let next = min(max(current + offset, 0), sessions.count - 1)
        selectedSessionID = sessions[next].id
    }

    private func copySelectedPath() {
        guard let session = selectedSession else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.projectPath.isEmpty ? session.sourcePath : session.projectPath, forType: .string)
    }

    private func openSelectedProject() {
        guard let path = selectedSession?.projectPath, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func selectedWindowText(forProject projectName: String) -> String {
        let window = sessions.first(where: { $0.projectName == projectName })?.contextWindow ?? 0
        return windowText(window)
    }

    private func sessionInstructionTimeText(_ session: AgentMonitorSessionSnapshot) -> String {
        guard let date = session.instructionDate ?? session.latestActivity else { return "—" }
        return DisplayTime.withSeconds.string(from: date)
    }

    private func unreportedText() -> String {
        localizer.t("未上报", en: "unreported", zhHant: "未上報", ja: "未報告", ko: "미보고", mt: "unreported")
    }

    private func sessionModelText(_ session: AgentMonitorSessionSnapshot) -> String {
        let raw = session.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        if raw.isEmpty || raw == "—" || lower == "null" || lower == "unknown" {
            return "\(session.agentName) / \(unreportedText())"
        }
        if lower == "<synthetic>" {
            return session.agentName == "Claude Code"
                ? "Claude Desktop"
                : session.agentName
        }
        if lower.hasPrefix("aimami_relay_") {
            return "Codex Relay"
        }
        if raw.count > 36 || raw.range(of: #"^[A-Za-z0-9_-]{24,}$"#, options: .regularExpression) != nil {
            return "\(session.agentName) / \(localizer.t("内部模型", en: "internal model", zhHant: "內部模型", ja: "内部モデル", ko: "내부 모델", mt: "internal model"))"
        }
        return raw
    }

    private func sessionTokenText(_ session: AgentMonitorSessionSnapshot) -> String {
        session.tokens.total > 0 ? compactCount(session.tokens.total) : unreportedText()
    }

    private func sessionContextPercentText(_ session: AgentMonitorSessionSnapshot) -> String {
        if session.contextPercent == 0, session.tokens.total == 0 { return unreportedText() }
        return "\(Int(session.contextPercent * 100))%"
    }

    private func sessionContextText(_ session: AgentMonitorSessionSnapshot) -> String {
        if session.contextPercent == 0, session.tokens.total == 0 {
            return "\(unreportedText()) / \(windowText(session.contextWindow))"
        }
        return "\(Int(session.contextPercent * 100))% / \(windowText(session.contextWindow))"
    }

    private func windowText(_ window: Int) -> String {
        guard window > 0 else { return unreportedText() }
        if window >= 1_000_000 { return String(format: "%.1fM", Double(window) / 1_000_000.0) }
        if window >= 1_000 { return String(format: "%.1fk", Double(window) / 1_000.0) }
        return "\(window)"
    }

    private func tokenProgress(_ value: Int) -> Double {
        let maxValue = max(selectedSession?.tokens.total ?? totalTokens, 1)
        return min(Double(value) / Double(maxValue), 1)
    }

    private func shortSessionId(_ sessionId: String) -> String {
        String(sessionId.prefix(8))
    }

    private func configRoot(for session: AgentMonitorSessionSnapshot) -> String {
        let lower = session.sourcePath.lowercased()
        if lower.contains("/.codex/") { return "~/.codex" }
        if lower.contains("/.claude/") { return "~/.claude" }
        if lower.contains("/.opencode/") { return "~/.opencode" }
        return localizer.t("授权目录", en: "Authorized folder", zhHant: "授權目錄", ja: "許可済みフォルダ", ko: "승인된 폴더", mt: "Authorized folder")
    }

    private func localizedStatus(_ status: String) -> String {
        switch status {
        case "Waiting", "Paused": return localizer.overviewStatusWaiting
        case "Thinking": return localizer.overviewStatusThinking
        case "Executing": return localizer.overviewStatusExecuting
        case "History": return localizer.overviewStatusHistory
        case "Done": return localizer.overviewStatusDone
        default: return status
        }
    }

    private func compactCount(_ value: Int) -> String {
        AgentUsageTokenFormatter.string(Int64(value))
    }

    private func contextColor(_ progress: Double) -> Color {
        if progress >= 0.85 { return Theme.Colors.danger }
        if progress >= 0.65 { return Theme.Colors.warning }
        return Theme.Colors.success
    }
}

private struct HUDIconChrome: ViewModifier {
    let color: Color
    let disabled: Bool
    var size: CGFloat = 28
    var radius: CGFloat = 8

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(disabled ? Theme.Colors.textTertiary : color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: radius)
                    .fill(disabled ? Theme.Colors.sidebarBg.opacity(0.45) : color.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: radius)
                            .fill(Theme.Colors.cardBg.opacity(disabled ? 0.45 : 0.55))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius)
                    .stroke(
                        LinearGradient(
                            colors: disabled
                                ? [Theme.Colors.separator.opacity(0.5), Theme.Colors.separator.opacity(0.2)]
                                : [color.opacity(0.65), color.opacity(0.16)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: disabled ? .clear : color.opacity(0.14), radius: 7, x: 0, y: 0)
            .opacity(disabled ? 0.55 : 1)
            .scaleEffect(disabled ? 1 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: disabled)
    }
}

private struct AgentCommandProjectRow: Identifiable {
    let name: String
    let context: Double
    let tokens: Int
    let count: Int

    var id: String { name }
}

private struct AgentCommandDashboardData {
    let allSessions: [AgentMonitorSessionSnapshot]
    let activeSessions: [AgentMonitorSessionSnapshot]
    let selectedSession: AgentMonitorSessionSnapshot?
    let selectedActiveSession: AgentMonitorSessionSnapshot?
    let displayedSessions: [AgentMonitorSessionSnapshot]
    let networkConnections: [AgentNetworkConnection]
    let totalTokens: Int
    let projectRows: [AgentCommandProjectRow]
    let sessionChartValues: [Double]
    let activeChartValues: [Double]
    let projectChartValues: [Double]
    let tokenChartValues: [Double]
    let realtimeToolCallCount: Int
    let realtimeAgentRunCount: Int
    let sessionSignature: String
}

private struct AgentCommandDashboardView: View {
    @ObservedObject var store: AgentMonitorOverviewStore
    @ObservedObject var monitor: OperationMonitor
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var usageInsightsService: AgentUsageInsightsService
    let onRefresh: () -> Void

    @State private var selectedSessionID: String?
    @State private var filterText = ""
    @State private var authorizationStatus = ""
    @State private var visibleSessionCount = 24
    @State private var showingSessionDetail = false

    private func makeDashboardData() -> AgentCommandDashboardData {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allSessions: [AgentMonitorSessionSnapshot]
        if query.isEmpty {
            allSessions = store.sessions
        } else {
            allSessions = store.sessions.filter {
                $0.agentName.lowercased().contains(query) ||
                $0.projectName.lowercased().contains(query) ||
                $0.projectPath.lowercased().contains(query) ||
                $0.model.lowercased().contains(query) ||
                $0.currentTask.lowercased().contains(query)
            }
        }

        let activeSessions = allSessions.filter(isActiveSession)
        let networkConnections: [AgentNetworkConnection]
        if query.isEmpty {
            networkConnections = store.networkConnections
        } else {
            networkConnections = store.networkConnections.filter {
                $0.agentName.lowercased().contains(query) ||
                $0.processName.lowercased().contains(query) ||
                $0.remoteEndpoint.lowercased().contains(query) ||
                $0.remoteHost.lowercased().contains(query) ||
                $0.route.lowercased().contains(query) ||
                $0.riskLevel.lowercased().contains(query) ||
                ($0.safetyStatus ?? "").lowercased().contains(query) ||
                ($0.safetyReason ?? "").lowercased().contains(query)
            }
        }
        let selectedSession = selectedSessionID.flatMap { id in
            allSessions.first { $0.id == id }
        } ?? allSessions.first
        let selectedActiveSession = selectedSessionID.flatMap { id in
            activeSessions.first { $0.id == id }
        } ?? activeSessions.first

        let projectRows = Dictionary(grouping: allSessions, by: \.projectName)
            .map { name, rows in
                AgentCommandProjectRow(
                    name: name,
                    context: rows.map(\.contextPercent).max() ?? 0,
                    tokens: rows.reduce(0) { $0 + $1.tokens.total },
                    count: rows.count
                )
            }
            .sorted {
                if $0.context == $1.context { return $0.tokens > $1.tokens }
                return $0.context > $1.context
            }

        let combinedUsage = usageInsightsService.snapshot(for: .combined)
        let totalTokens = Int(clamping: combinedUsage.allTime.total)
        let activeChartValues = activeSessions
            .sorted { $0.contextPercent > $1.contextPercent }
            .prefix(6)
            .map { max($0.contextPercent, 0.18) }
        let livePids = Set(activeSessions.compactMap(\.pid))

        return AgentCommandDashboardData(
            allSessions: allSessions,
            activeSessions: activeSessions,
            selectedSession: selectedSession,
            selectedActiveSession: selectedActiveSession,
            displayedSessions: Array(allSessions.prefix(visibleSessionCount)),
            networkConnections: networkConnections,
            totalTokens: totalTokens,
            projectRows: projectRows,
            sessionChartValues: Dictionary(grouping: allSessions, by: \.agentName)
                .map { Double($0.value.count) }
                .sorted(by: >)
                .prefix(6)
                .map { $0 },
            activeChartValues: activeChartValues.isEmpty && !allSessions.isEmpty ? [0.08] : activeChartValues,
            projectChartValues: projectRows
                .map { Double($0.count) }
                .sorted(by: >)
                .prefix(6)
                .map { $0 },
            tokenChartValues: combinedUsage.projectRankingsAllTime
                .map { Double($0.tokens.total) }
                .sorted(by: >)
                .prefix(6)
                .map { $0 },
            realtimeToolCallCount: activeSessions.reduce(0) { total, session in
                let liveTools = max(session.runningToolCount, session.status == "Executing" && session.toolCount > 0 ? 1 : 0)
                return total + liveTools
            },
            realtimeAgentRunCount: !livePids.isEmpty ? livePids.count : Set(activeSessions.map(\.agentName)).count,
            sessionSignature: [
                "\(store.sessions.count)",
                store.sessions.first?.id ?? "",
                store.sessions.last?.id ?? "",
                "\(Int(store.sessions.first?.latestActivity?.timeIntervalSince1970 ?? 0))",
                "\(Int(store.sessions.last?.latestActivity?.timeIntervalSince1970 ?? 0))",
                "\(store.networkConnections.count)",
                store.networkConnections.first?.id ?? ""
            ].joined(separator: "|")
        )
    }

    private var allSessions: [AgentMonitorSessionSnapshot] {
        let query = filterText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.sessions }
        return store.sessions.filter {
            $0.agentName.lowercased().contains(query) ||
            $0.projectName.lowercased().contains(query) ||
            $0.projectPath.lowercased().contains(query) ||
            $0.model.lowercased().contains(query) ||
            $0.currentTask.lowercased().contains(query)
        }
    }

    private var sessions: [AgentMonitorSessionSnapshot] {
        allSessions
    }

    private var activeSessions: [AgentMonitorSessionSnapshot] {
        allSessions.filter(isActiveSession)
    }

    private var selectedSession: AgentMonitorSessionSnapshot? {
        if let selectedSessionID,
           let match = sessions.first(where: { $0.id == selectedSessionID }) {
            return match
        }
        return sessions.first
    }

    private var selectedActiveSession: AgentMonitorSessionSnapshot? {
        if let selectedSessionID,
           let match = activeSessions.first(where: { $0.id == selectedSessionID }) {
            return match
        }
        return activeSessions.first
    }

    private var displayedSessions: [AgentMonitorSessionSnapshot] {
        Array(sessions.prefix(visibleSessionCount))
    }

    private var totalTokens: Int {
        Int(clamping: usageInsightsService.snapshot(for: .combined).allTime.total)
    }
    private var realtimeConversationCount: Int { activeSessions.count }
    private var realtimeToolCallCount: Int {
        activeSessions.reduce(0) { total, session in
            let liveTools = max(session.runningToolCount, session.status == "Executing" && session.toolCount > 0 ? 1 : 0)
            return total + liveTools
        }
    }
    private var realtimeAgentRunCount: Int {
        let livePids = Set(activeSessions.compactMap(\.pid))
        if !livePids.isEmpty { return livePids.count }
        return Set(activeSessions.map(\.agentName)).count
    }
    private func dataStatusIcon(_ data: AgentCommandDashboardData) -> String {
        if store.isScanning { return "arrow.triangle.2.circlepath" }
        if !data.allSessions.isEmpty { return "checkmark.seal.fill" }
        if !store.authorizedRoots.isEmpty { return "folder.badge.questionmark" }
        return "exclamationmark.triangle.fill"
    }
    private var dataStatusColor: Color {
        if store.isScanning { return Theme.Colors.warning }
        if !allSessions.isEmpty { return Theme.Colors.success }
        if !store.authorizedRoots.isEmpty { return Theme.Colors.info }
        return Theme.Colors.warning
    }
    private func dataStatusTitle(_ data: AgentCommandDashboardData) -> String {
        if store.isScanning { return localizer.overviewScanningAgentData }
        if !data.allSessions.isEmpty { return localizer.overviewAgentSessionsLoaded }
        if !store.authorizedRoots.isEmpty { return localizer.overviewAuthorizedNoSessions }
        return localizer.overviewNoAgentFolders
    }
    private func dataStatusDetail(_ data: AgentCommandDashboardData) -> String {
        if store.isScanning { return localizer.overviewScanningDetail }
        if !data.allSessions.isEmpty { return localizedAggregationSummary(data) }
        if !store.scannedRoots.isEmpty { return "\(localizedScanCoverageStatus): \(store.scannedRoots.prefix(6).map(shortRoot).joined(separator: ", ")). \(localizer.overviewSuggestedFolders)" }
        if !store.authorizedRoots.isEmpty { return "\(localizer.overviewAuthorizedFolders): \(store.authorizedRoots.map(shortRoot).joined(separator: ", ")). \(localizer.overviewSuggestedFolders)" }
        return localizer.overviewChooseAgentFolders
    }
    private var lastScanText: String {
        if store.isScanning { return localizer.overviewScanningAgentData }
        guard let date = store.lastScanDate else { return localizer.overviewNeverScanned }
        return "\(localizer.overviewLastScan) \(DisplayTime.withSeconds.string(from: date))"
    }
    private var localizedAuthorizationStatus: String {
        if store.isScanning { return localizer.overviewScanningAgentData }
        if !authorizationStatus.isEmpty { return authorizationStatus }
        if !store.scannedRoots.isEmpty { return localizedScanCoverageStatus }
        return store.authorizedRoots.isEmpty ? localizer.overviewNotAuthorized : "\(localizer.overviewAuthorizedFolders) \(store.authorizedRoots.count)\(localizer.overviewFoldersUnit)"
    }

    private var localizedScanCoverageStatus: String {
        if store.scannedRoots.isEmpty {
            return store.authorizedRoots.isEmpty ? localizer.overviewNotAuthorized : "\(localizer.overviewAuthorizedFolders) \(store.authorizedRoots.count)\(localizer.overviewFoldersUnit)"
        }
        switch localizer.language {
        case .simplifiedChinese:
            return "已扫描 \(store.scannedRoots.count) 个 Agent 数据源"
        case .traditionalChinese:
            return "已掃描 \(store.scannedRoots.count) 個 Agent 資料源"
        case .japanese:
            return "\(store.scannedRoots.count) 件の Agent データソースをスキャン"
        case .korean:
            return "\(store.scannedRoots.count)개 Agent 데이터 소스 스캔됨"
        case .english, .maltese:
            return "Scanned \(store.scannedRoots.count) agent data sources"
        }
    }
    private func localizedAggregationSummary(_ data: AgentCommandDashboardData) -> String {
        switch localizer.language {
        case .simplifiedChinese:
            return "已聚合 \(data.allSessions.count) 个会话，其中 \(data.activeSessions.count) 个活跃，覆盖 \(data.projectRows.count) 个项目、\(compactCount(data.totalTokens)) Token 和 \(data.networkConnections.count) 条出站连接。"
        case .traditionalChinese:
            return "已彙總 \(data.allSessions.count) 個會話，其中 \(data.activeSessions.count) 個活躍，覆蓋 \(data.projectRows.count) 個專案、\(compactCount(data.totalTokens)) Token 和 \(data.networkConnections.count) 條出站連線。"
        case .japanese:
            return "\(data.allSessions.count) 件のセッション、うち \(data.activeSessions.count) 件がアクティブ、\(data.projectRows.count) 件のプロジェクト、\(compactCount(data.totalTokens)) トークン、\(data.networkConnections.count) 件の送信接続を集計しました。"
        case .korean:
            return "\(data.allSessions.count)개 세션 중 \(data.activeSessions.count)개 활성, \(data.projectRows.count)개 프로젝트, \(compactCount(data.totalTokens)) 토큰, \(data.networkConnections.count)개 아웃바운드 연결을 집계했습니다."
        case .english, .maltese:
            return "Grouped \(data.allSessions.count) sessions, \(data.activeSessions.count) active, \(data.projectRows.count) projects, \(compactCount(data.totalTokens)) tokens, and \(data.networkConnections.count) egress connections."
        }
    }
    private var localizedCommandCenterIntro: String {
        switch localizer.language {
        case .simplifiedChinese:
            return "关键数据已按会话、活跃状态、项目和 Token 聚合。"
        case .traditionalChinese:
            return "關鍵資料已按會話、活躍狀態、專案和 Token 彙總。"
        case .japanese:
            return "主要データをセッション、稼働状況、プロジェクト、Token 別に集計しています。"
        case .korean:
            return "핵심 데이터를 세션, 활성 상태, 프로젝트, Token 기준으로 집계했습니다."
        case .english, .maltese:
            return "Key data is grouped by sessions, activity, projects, and tokens."
        }
    }

    private var sessionChartValues: [Double] {
        Dictionary(grouping: allSessions, by: \.agentName)
            .map { Double($0.value.count) }
            .sorted(by: >)
            .prefix(6)
            .map { $0 }
    }

    private var activeChartValues: [Double] {
        let values = activeSessions
            .sorted { $0.contextPercent > $1.contextPercent }
            .prefix(6)
            .map { max($0.contextPercent, 0.18) }
        return values.isEmpty && !allSessions.isEmpty ? [0.08] : values
    }

    private var projectChartValues: [Double] {
        projectRows
            .map { Double($0.count) }
            .sorted(by: >)
            .prefix(6)
            .map { $0 }
    }

    private var tokenChartValues: [Double] {
        usageInsightsService.snapshot(for: .combined).projectRankingsAllTime
            .map { Double($0.tokens.total) }
            .sorted(by: >)
            .prefix(6)
            .map { $0 }
    }

    private var projectRows: [(name: String, context: Double, tokens: Int, count: Int)] {
        Dictionary(grouping: allSessions, by: \.projectName)
            .map { name, rows in
                (
                    name: name,
                    context: rows.map(\.contextPercent).max() ?? 0,
                    tokens: rows.reduce(0) { $0 + $1.tokens.total },
                    count: rows.count
                )
            }
            .sorted {
                if $0.context == $1.context { return $0.tokens > $1.tokens }
                return $0.context > $1.context
            }
    }

    private var ports: [(port: Int, session: AgentMonitorSessionSnapshot)] {
        allSessions.flatMap { session in session.ports.map { (port: $0, session: session) } }
    }

    private func isActiveSession(_ session: AgentMonitorSessionSnapshot) -> Bool {
        ["Thinking", "Executing", "Waiting", "Paused"].contains(session.status) ||
        (!session.currentTask.isEmpty && session.status != "History" && session.status != "Done")
    }

    var body: some View {
        let data = makeDashboardData()

        return VStack(spacing: 0) {
            if monitor.needsReauthorization { authorizationBanner }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    commandCenterHero(data)

                    currentSessionUsageCard(data)
                    networkAuditCard(data)
                    sessionListCard(data)

                    VStack(spacing: Theme.Spacing.md) {
                        projectCard(data)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Colors.sidebarBg.opacity(0.24))
        }
        .onAppear {
            usageInsightsService.startScheduling()
            onRefresh()
            normalizeSelection()
            refreshSelectedActiveSessionIfNeeded(data)
        }
        .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
            refreshSelectedActiveSessionIfNeeded(makeDashboardData())
        }
        .onChange(of: data.sessionSignature) { _ in
            normalizeSelection()
            refreshSelectedActiveSessionIfNeeded(makeDashboardData())
        }
        .onChange(of: selectedSessionID ?? "") { _ in
            refreshSelectedActiveSessionIfNeeded(makeDashboardData())
        }
        .onChange(of: filterText) { _ in
            visibleSessionCount = 24
            normalizeSelection()
            refreshSelectedActiveSessionIfNeeded(makeDashboardData())
        }
        .onChange(of: store.scannedRoots.joined(separator: "|")) { _ in
            authorizationStatus = localizedScanCoverageStatus
        }
        .sheet(isPresented: $showingSessionDetail) {
            let sheetData = makeDashboardData()
            if let session = sheetData.selectedActiveSession ?? sheetData.selectedSession {
                ActiveSessionDetailSheet(
                    session: session,
                    statusText: statusText(session.status),
                    statusColor: statusColor(session.status),
                    contextColor: contextColor(session.contextPercent),
                    displayLocation: displayLocation(for: session),
                    configRoot: configRoot(for: session),
                    modelText: sessionModelText(session),
                    contextText: sessionContextText(session),
                    tokenText: sessionTokenText(session),
                    shortSessionId: shortSessionId(session.sessionId),
                    memoryText: memoryText(session.memoryMB),
                    compactCount: compactCount,
                    onCopyPath: { copyPath(for: session) },
                    onOpenProject: { openProject(for: session) }
                )
                .environmentObject(localizer)
            } else {
                ActiveSessionEmptySheet()
                    .environmentObject(localizer)
            }
        }
    }

    private func commandCenterHero(_ data: AgentCommandDashboardData) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm + 2) {
                ZStack(alignment: .bottomTrailing) {
                    AgentGuardMark(size: 28, showGlow: false)
                    Circle()
                        .fill(data.activeSessions.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.success)
                        .frame(width: 9, height: 9)
                        .overlay(
                            Circle()
                                .stroke(Theme.Colors.elevatedCardBg, lineWidth: 2)
                        )
                        .shadow(color: Theme.Colors.success.opacity(data.activeSessions.isEmpty ? 0 : 0.55), radius: 7)
                }

                Text(data.activeSessions.isEmpty ? localizer.overviewWaitingSessions : localizer.overviewLiveActivity)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(data.activeSessions.isEmpty ? Theme.Colors.textSecondary : Theme.Colors.success)
                    .textCase(.uppercase)

                VStack(alignment: .leading, spacing: 1) {
                    Text(localizer.commandCenterTitle)
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)

                    Text(localizedCommandCenterIntro)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }

                Spacer(minLength: 0)
            }

            heroMetricsGrid(data)

            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    if store.isScanning {
                        ScanningStatusPill(title: dataStatusTitle(data), color: dataStatusColor)
                    } else {
                        Text(dataStatusTitle(data))
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if store.isScanning {
                    ScanningProgressCaption(detail: dataStatusDetail(data), color: dataStatusColor)
                        .frame(minWidth: 156, alignment: .trailing)
                } else {
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(localizedAuthorizationStatus)
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(dataStatusColor)
                            .lineLimit(1)
                        Text(lastScanText)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(minWidth: 132, alignment: .trailing)
                }

                Button {
                    authorizationStatus = localizer.overviewRescanning
                    store.refresh(force: true)
                } label: {
                    Label(localizer.refresh, systemImage: "arrow.clockwise")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 30))
                .disabled(store.isScanning)

                Button {
                    authorizationStatus = localizer.overviewWaitingForSelection
                    monitor.requestAccessForStalePaths()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        authorizationStatus = localizer.overviewScanningAuthorizedFolders
                        service.importKnownAgentHistory()
                        onRefresh()
                    }
                } label: {
                    Label(store.authorizedRoots.isEmpty ? localizer.overviewAuthorizeFolder : localizer.overviewReauthorizeFolder, systemImage: "folder.badge.plus")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .primary, minHeight: 30))
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm + 2)
            .background(Theme.Colors.elevatedCardBg.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(dataStatusColor.opacity(0.16), lineWidth: 1)
            )
        }
        .padding(Theme.Spacing.md)
        .background(
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [
                        Theme.Colors.elevatedCardBg,
                        Theme.Colors.accent.opacity(0.055),
                        Theme.Colors.info.opacity(0.035)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.075))
                    .frame(width: 180, height: 180)
                    .blur(radius: 34)
                    .offset(x: 76, y: -90)
                Circle()
                    .stroke(Theme.Colors.info.opacity(0.12), lineWidth: 1)
                    .frame(width: 132, height: 132)
                    .offset(x: -40, y: 58)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.xxl))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.xxl)
                .stroke(Theme.Gradients.glassStroke, lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.lgColor, radius: 26, y: 14)
    }

    private func heroMetricsGrid(_ data: AgentCommandDashboardData) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 124), spacing: Theme.Spacing.sm), count: 4), spacing: Theme.Spacing.sm) {
            heroMetricChart(
                title: localizer.overviewSessions,
                value: "\(data.allSessions.count)",
                detail: localizer.overviewLiveAndHistory,
                icon: "rectangle.3.group",
                color: Theme.Colors.info,
                values: data.sessionChartValues
            )
            heroMetricChart(
                title: localizer.activeAgents,
                value: "\(data.activeSessions.count)",
                detail: localizer.overviewLiveActivity,
                icon: "dot.radiowaves.left.and.right",
                color: Theme.Colors.success,
                values: data.activeChartValues
            )
            heroMetricChart(
                title: localizer.overviewProject,
                value: "\(data.projectRows.count)",
                detail: localizer.overviewProjectContext,
                icon: "folder.fill",
                color: Theme.Colors.warning,
                values: data.projectChartValues
            )
            heroMetricChart(
                title: localizer.t("全部可信 Agent · 全部时间 Token", en: "All Trusted Agents · All-time Tokens", zhHant: "全部可信 Agent · 全部時間 Token", ja: "信頼済み Agent · 全期間 Token", ko: "신뢰할 수 있는 Agent · 전체 기간 Token", mt: "All Trusted Agents · All-time Tokens"),
                value: compactCount(data.totalTokens),
                detail: overviewTokenDetail(data.totalTokens),
                icon: "sum",
                color: Theme.Colors.purple,
                values: data.tokenChartValues
            )
        }
    }

    private func overviewTokenDetail(_ total: Int) -> String {
        let exact = AgentUsageTokenFormatter.exactString(Int64(total))
        return localizer.t(
            "\(exact) Token · B=十亿 · 同 Token 页",
            en: "\(exact) tokens · B=billion · same as Token page",
            zhHant: "\(exact) Token · B=十億 · 同 Token 頁",
            ja: "\(exact) トークン · B=10億 · Token画面と同一",
            ko: "\(exact) 토큰 · B=10억 · Token 페이지와 동일",
            mt: "\(exact) tokens · B=billion · same as Token page"
        )
    }

    private func heroMetricChart(title: String, value: String, detail: String, icon: String, color: Color, values: [Double]) -> some View {
        let safeValues = values.isEmpty ? [0.08, 0.16, 0.10, 0.22] : values
        let maxValue = max(safeValues.max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: Theme.Spacing.xs + 1) {
            HStack(alignment: .top, spacing: Theme.Spacing.xs + 2) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                    Text(value)
                        .font(.system(size: 18, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                Spacer(minLength: 0)
            }

            HStack(alignment: .bottom, spacing: 4) {
                ForEach(Array(safeValues.enumerated()), id: \.offset) { index, item in
                    Capsule()
                        .fill(color.opacity(index == 0 ? 0.95 : 0.34 + min(0.36, item / maxValue * 0.36)))
                        .frame(maxWidth: .infinity)
                        .frame(height: max(5, CGFloat(item / maxValue) * 20))
                }
            }
            .frame(height: 22, alignment: .bottom)

            Text(detail)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 1)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .background(Theme.Colors.elevatedCardBg.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
    }

    private func heroSignal(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Theme.Gradients.hero)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .frame(width: 116, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.elevatedCardBg.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Theme.Colors.separator, lineWidth: 1)
        )
    }

    private var commandToolbar: some View {
        HStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(store.isScanning ? Theme.Colors.warning : (allSessions.isEmpty ? Theme.Colors.textTertiary : Theme.Colors.success))
                    .frame(width: 8, height: 8)
                Text(store.isScanning ? localizer.overviewScanning : (allSessions.isEmpty ? localizer.overviewWaitingSessions : "\(allSessions.count) \(localizer.overviewSessions)"))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                TextField(localizer.overviewSearchPlaceholder, text: $filterText)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.caption)
                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .frame(width: 260)
            .background(Theme.Colors.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(Theme.Colors.separator.opacity(0.65), lineWidth: 1)
            )

            sessionHudButton(icon: "chevron.up", color: Theme.Colors.info, disabled: sessions.count < 2, help: localizer.overviewPreviousSession) {
                moveSelection(-1)
            }

            sessionHudButton(icon: "chevron.down", color: Theme.Colors.info, disabled: sessions.count < 2, help: localizer.overviewNextSession) {
                moveSelection(1)
            }

            sessionHudButton(icon: "doc.on.doc", color: Theme.Colors.accent, disabled: selectedSession == nil, help: localizer.copyPath) {
                copySelectedPath()
            }

            sessionHudButton(icon: "folder", color: Theme.Colors.warning, disabled: selectedSession?.projectPath.isEmpty ?? true, help: localizer.openInFinder) {
                openSelectedProject()
            }

            Button {
                authorizationStatus = localizer.overviewRescanning
                store.refresh(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .modifier(HUDIconChrome(color: Theme.Colors.purple, disabled: store.isScanning))
            .disabled(store.isScanning)
            .help(localizer.refresh)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.cardBg.opacity(0.82))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.Colors.separator.opacity(0.45)).frame(height: 1)
        }
    }

    private var authorizationBanner: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.Colors.warning)
                .frame(width: 34, height: 34)
                .background(Theme.Colors.warning.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.overviewNeedAuthorize)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(localizer.overviewNeedAuthorizeHint)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                authorizationStatus = localizer.overviewWaitingForSelection
                monitor.requestAccessForStalePaths()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    authorizationStatus = localizer.overviewScanningAuthorizedFolders
                    service.importKnownAgentHistory()
                    onRefresh()
                }
            } label: {
                Label(localizer.reauthorize, systemImage: "lock.open")
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 2)
                    .background(Theme.Colors.warning)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.warning.opacity(0.08))
    }

    private var dataStatusCard: some View {
        let data = makeDashboardData()

        return HStack(alignment: .center, spacing: Theme.Spacing.md) {
                VStack(alignment: .leading, spacing: 3) {
                    Label(dataStatusTitle(data), systemImage: dataStatusIcon(data))
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(dataStatusColor)
                    Text(dataStatusDetail(data))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(localizedAuthorizationStatus)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(dataStatusColor)
                        .lineLimit(1)
                    Text(lastScanText)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
                .frame(minWidth: 132, alignment: .trailing)

                Button {
                    authorizationStatus = localizer.overviewRescanning
                    store.refresh(force: true)
                } label: {
                    Label(localizer.refresh, systemImage: "arrow.clockwise")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 30))
                .disabled(store.isScanning)

                Button {
                    authorizationStatus = localizer.overviewWaitingForSelection
                    monitor.requestAccessForStalePaths()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        authorizationStatus = localizer.overviewScanningAuthorizedFolders
                        service.importKnownAgentHistory()
                        onRefresh()
                    }
                } label: {
                    Label(store.authorizedRoots.isEmpty ? localizer.overviewAuthorizeFolder : localizer.overviewReauthorizeFolder, systemImage: "folder.badge.plus")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .primary, minHeight: 30))
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial)
        .background(Theme.Colors.elevatedCardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(dataStatusColor.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: dataStatusColor.opacity(0.06), radius: 16, y: 8)
    }

    private var metricStrip: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 118), spacing: Theme.Spacing.sm), count: 5), spacing: Theme.Spacing.sm) {
            metricCard(icon: "rectangle.3.group", title: localizer.overviewSessions, value: "\(allSessions.count)", detail: localizer.overviewLiveAndHistory, color: Theme.Colors.accent)
            metricCard(icon: "chart.bar.xaxis", title: localizer.overviewTokensTotal, value: compactCount(totalTokens), detail: exactTokenHeadline, color: Theme.Colors.info)
            metricCard(icon: "bubble.left.and.bubble.right.fill", title: localizer.overviewRealtimeConversations, value: "\(realtimeConversationCount)", detail: selectedActiveSession?.projectName ?? localizer.overviewWaitingSessions, color: Theme.Colors.info)
            metricCard(icon: "wrench.and.screwdriver.fill", title: localizer.overviewRealtimeToolCalls, value: "\(realtimeToolCallCount)", detail: activeSessions.isEmpty ? localizer.overviewWaitingSessions : localizer.overviewLiveActivity, color: Theme.Colors.warning)
            metricCard(icon: "cpu.fill", title: localizer.overviewRealtimeAgentRuns, value: "\(realtimeAgentRunCount)", detail: activeSessions.isEmpty ? localizer.overviewWaitingSessions : "\(activeSessions.count) \(localizer.overviewSessions)", color: Theme.Colors.purple)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricCard(icon: String, title: String, value: String, detail: String, color: Color) -> some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(Theme.Gradients.hero)
                        .clipShape(RoundedRectangle(cornerRadius: 11))
                        .shadow(color: Theme.Colors.accent.opacity(0.18), radius: 8, y: 4)
                    Text(title)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
                Text(value)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Text(detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(.ultraThinMaterial)
        .background(Theme.Colors.elevatedCardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Colors.separator, lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.mdColor, radius: 12, y: 6)
    }

    private var exactTokenHeadline: String {
        let exact = AgentUsageTokenFormatter.exactString(Int64(totalTokens))
        return localizer.t(
            "\(exact) Token（B=十亿）",
            en: "\(exact) tokens (B=billion)",
            zhHant: "\(exact) Token（B=十億）",
            ja: "\(exact) トークン（B=10億）",
            ko: "\(exact) 토큰 (B=10억)",
            mt: "\(exact) tokens (B=billion)"
        )
    }

    private func sessionHudButton(icon: String, color: Color, disabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
        }
        .buttonStyle(.plain)
        .modifier(HUDIconChrome(color: color, disabled: disabled))
        .disabled(disabled)
        .help(help)
    }

    private func currentSessionUsageCard(_ data: AgentCommandDashboardData) -> some View {
        dashboardCard(title: "\(localizer.currentSession) / \(localizer.overviewTokenUse)", icon: "chart.bar.xaxis", color: Theme.Colors.accent) {
            sessionHudButton(icon: "sidebar.right", color: Theme.Colors.accent, disabled: data.selectedActiveSession == nil && data.selectedSession == nil, help: localizer.agentSessionDetail) {
                showingSessionDetail = true
            }

            sessionHudButton(icon: "chevron.up", color: Theme.Colors.info, disabled: data.activeSessions.count < 2, help: localizer.overviewPreviousSession) {
                moveSelection(-1)
            }

            sessionHudButton(icon: "chevron.down", color: Theme.Colors.info, disabled: data.activeSessions.count < 2, help: localizer.overviewNextSession) {
                moveSelection(1)
            }

            sessionHudButton(icon: "doc.on.doc", color: Theme.Colors.accent, disabled: data.selectedSession == nil, help: localizer.copyPath) {
                copySelectedPath()
            }

            sessionHudButton(icon: "folder", color: Theme.Colors.warning, disabled: data.selectedSession?.projectPath.isEmpty ?? true, help: localizer.openInFinder) {
                openSelectedProject()
            }
        } content: {
            if let session = data.selectedActiveSession {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                sessionField("AI", agentCode(session.agentName), width: 44, color: agentColor(session.agentName))
                                sessionField(localizer.overviewProject, session.projectName, width: 116)
                                sessionField(localizer.overviewSession, shortSessionId(session.sessionId), width: 84, color: Theme.Colors.warning)
                                sessionField(localizer.t("时间", en: "Time", zhHant: "時間", ja: "時刻", ko: "시간", mt: "Time"), sessionInstructionTimeText(session), width: 72)
                                sessionField(localizer.overviewLocation, displayLocation(for: session), width: 150)
                                sessionField(localizer.status, statusText(session.status), width: 64, color: statusColor(session.status))
                                sessionField(localizer.overviewModel, sessionModelText(session), width: 108)
                                sessionField(localizer.contextWindow, sessionContextText(session), width: 118, color: contextColor(session.contextPercent))
                                sessionField("token", sessionTokenText(session), width: 82, color: Theme.Colors.info)
                                sessionField(localizer.overviewMemory, memoryText(session.memoryMB), width: 58)
                                sessionField(localizer.overviewTurns, "\(session.turnCount)", width: 38)
                                sessionField("pid", session.pid.map(String.init) ?? "—", width: 58)
                                sessionField("tool", "\(max(session.runningToolCount, session.toolCount))", width: 42)
                            }
                        }

                        Text(session.currentTask)
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(2)
                            .help(session.currentTask)

                        contextProgress(session.contextPercent, window: session.contextWindow)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    tokenUsageGrid(for: session)
                }
            } else {
                activeSessionEmptyState
            }
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .top)
    }

    private func networkAuditCard(_ data: AgentCommandDashboardData) -> some View {
        let warningCount = data.networkConnections.filter { connection in
            ["proxyBypass", "unsafe", "publicDirect", "unknown"].contains(connection.safetyStatus ?? "")
        }.count
        let hasProxyBypass = data.networkConnections.contains { $0.safetyStatus == "proxyBypass" }
        let badgeColor = hasProxyBypass ? Theme.Colors.danger : (warningCount > 0 ? Theme.Colors.warning : Theme.Colors.cyan)

        return dashboardCard(title: localizer.t("Agent 出站网络", en: "Agent Network Egress", zhHant: "Agent 出站網路", ja: "Agent 送信ネットワーク", ko: "Agent 아웃바운드 네트워크", mt: "Agent Network Egress"), icon: "network", color: Theme.Colors.cyan) {
            Text(warningCount > 0 ? "\(warningCount) / \(data.networkConnections.count)" : "\(data.networkConnections.count)")
                .font(Theme.Font.captionMedium)
                .foregroundStyle(badgeColor)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 4)
                .background(badgeColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        } content: {
            if data.networkConnections.isEmpty {
                emptyState(
                    icon: "network",
                    title: localizer.t("暂无出站连接", en: "No egress connections", zhHant: "暫無出站連線", ja: "送信接続なし", ko: "아웃바운드 연결 없음", mt: "No egress connections"),
                    detail: localizer.t("活跃 Agent 的 TCP 出站元数据会显示在这里。", en: "Active agent TCP egress metadata appears here.", zhHant: "活躍 Agent 的 TCP 出站中繼資料會顯示在這裡。", ja: "稼働中 Agent の TCP 送信メタデータがここに表示されます。", ko: "활성 Agent의 TCP 아웃바운드 메타데이터가 여기에 표시됩니다.", mt: "Active agent TCP egress metadata appears here.")
                )
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(Array(data.networkConnections.prefix(12))) { connection in
                        networkConnectionRow(connection)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .top)
    }

    private func networkConnectionRow(_ connection: AgentNetworkConnection) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(agentCode(connection.agentName))
                .font(Theme.Font.captionMedium)
                .foregroundStyle(agentColor(connection.agentName))
                .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(connection.remoteEndpoint)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(connection.processName) · pid \(connection.pid) · \(connection.localEndpoint)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(networkSafetyText(connection.safetyStatus))
                .font(Theme.Font.captionMedium)
                .foregroundStyle(networkSafetyColor(connection.safetyStatus))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 4)
                .background(networkSafetyColor(connection.safetyStatus).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .frame(width: 108, alignment: .trailing)

            Text(connection.route)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 78, alignment: .leading)

            Text(networkRiskText(connection.riskLevel))
                .font(Theme.Font.captionMedium)
                .foregroundStyle(networkRiskColor(connection.riskLevel))
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, 4)
                .background(networkRiskColor(connection.riskLevel).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                .frame(width: 78, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.sidebarBg.opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .help("\(connection.agentName)\n\(connection.localEndpoint) -> \(connection.remoteEndpoint)\n\(connection.state)\n\(connection.safetyReason ?? "")")
    }

    private var activeSessionEmptyState: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(Theme.Colors.success)
                    .frame(width: 8, height: 8)
                Text(localizer.overviewLiveActivity)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.success)
            }
            emptyState(
                icon: "dot.radiowaves.left.and.right",
                title: localizer.overviewNoActiveSession,
                detail: localizer.overviewNoActiveSessionHint
            )
        }
        .frame(maxWidth: .infinity, minHeight: 168)
    }

    private func projectCard(_ data: AgentCommandDashboardData) -> some View {
        dashboardCard(title: localizer.overviewProjectContext, icon: "folder", color: Theme.Colors.info) {
            EmptyView()
        } content: {
            if data.projectRows.isEmpty {
                emptyState(icon: "folder", title: localizer.overviewNoProject, detail: localizer.overviewNoProjectHint)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(data.projectRows.prefix(8)) { row in
                        HStack(spacing: Theme.Spacing.md) {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                Text(row.name)
                                    .font(Theme.Font.captionMedium)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                HStack(spacing: Theme.Spacing.md) {
                                    Text("\(row.count) \(localizer.overviewSessions)")
                                    Text(compactCount(row.tokens))
                                }
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .frame(width: 220, alignment: .leading)

                            ProgressView(value: row.context)
                                .progressViewStyle(.linear)
                                .tint(contextColor(row.context))
                                .frame(maxWidth: .infinity)

                            Text("\(Int(row.context * 100))%")
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(contextColor(row.context))
                                .frame(width: 52, alignment: .trailing)
                        }
                        .padding(.vertical, Theme.Spacing.sm)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .top)
    }

    private func sessionListCard(_ data: AgentCommandDashboardData) -> some View {
        dashboardCard(title: localizer.overviewSessionList, icon: "list.bullet.rectangle", color: Theme.Colors.danger) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                TextField(localizer.overviewSearchPlaceholder, text: $filterText)
                    .textFieldStyle(.plain)
                    .font(Theme.Font.caption)
                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs + 2)
            .frame(width: 260)
            .background(Theme.Colors.sidebarBg.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        } content: {
            if data.allSessions.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    emptyState(icon: "dot.radiowaves.left.and.right", title: localizer.overviewNoSessions, detail: localizer.overviewNoSessionsHint)
                    Button {
                        monitor.requestAccessForStalePaths()
                    } label: {
                        Label(localizer.overviewAuthorizeAgentData, systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .primary, minHeight: 34))
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyVStack(spacing: Theme.Spacing.xs) {
                        sessionTableHeader
                        ForEach(data.displayedSessions) { session in
                            sessionTableRow(session, selectedID: data.selectedSession?.id)
                        }
                        if visibleSessionCount < data.allSessions.count {
                            Button {
                                visibleSessionCount = min(visibleSessionCount + 24, data.allSessions.count)
                            } label: {
                                HStack {
                                    Spacer()
                                    Label(loadMoreOverviewSessionsText(remaining: data.allSessions.count - visibleSessionCount), systemImage: "arrow.down.circle")
                                        .font(Theme.Font.captionMedium)
                                        .foregroundStyle(Theme.Colors.info)
                                    Spacer()
                                }
                                .padding(Theme.Spacing.sm)
                                .background(Theme.Colors.sidebarBg.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(minWidth: 1180, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 360, alignment: .top)
    }

    private var sessionTableHeader: some View {
        HStack(spacing: Theme.Spacing.sm) {
            tableHeader("AI", width: 58, alignment: .leading)
            tableHeader(localizer.overviewProject, width: 130, alignment: .leading)
            tableHeader(localizer.overviewSession, width: 92, alignment: .leading)
            tableHeader(localizer.t("时间", en: "Time", zhHant: "時間", ja: "時刻", ko: "시간", mt: "Time"), width: 76, alignment: .leading)
            tableHeader(localizer.overviewLocation, width: 108, alignment: .leading)
            tableHeader(localizer.overviewSummary, width: 248, alignment: .leading)
            tableHeader(localizer.status, width: 70, alignment: .leading)
            tableHeader(localizer.overviewModel, width: 96, alignment: .leading)
            tableHeader(localizer.contextWindow, width: 70, alignment: .trailing)
            tableHeader("token", width: 78, alignment: .trailing)
            tableHeader(localizer.overviewMemory, width: 58, alignment: .trailing)
            tableHeader(localizer.overviewTurns, width: 42, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.sidebarBg.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func tableHeader(_ title: String, width: CGFloat?, alignment: Alignment) -> some View {
        Text(title)
            .font(Theme.Font.captionMedium)
            .foregroundStyle(Theme.Colors.textTertiary)
            .frame(width: width, alignment: alignment)
    }

    private func sessionTableRow(_ session: AgentMonitorSessionSnapshot, selectedID: String?) -> some View {
        let selected = selectedID == session.id
        return Button {
            selectedSessionID = session.id
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: 4) {
                    Text(selected ? "▶" : " ")
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.accent)
                    Text(agentCode(session.agentName))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(agentColor(session.agentName))
                }
                .frame(width: 58, alignment: .leading)

                Text(session.projectName)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .frame(width: 130, alignment: .leading)

                Text(shortSessionId(session.sessionId))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.warning)
                    .lineLimit(1)
                    .frame(width: 92, alignment: .leading)

                Text(sessionInstructionTimeText(session))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .frame(width: 76, alignment: .leading)

                Text(displayLocation(for: session))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 108, alignment: .leading)

                Text(session.currentTask)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 248, alignment: .leading)

                Text(statusText(session.status))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(statusColor(session.status))
                    .lineLimit(1)
                    .frame(width: 70, alignment: .leading)

                Text(sessionModelText(session))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 96, alignment: .leading)

                Text(sessionContextPercentText(session))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(contextColor(session.contextPercent))
                    .frame(width: 70, alignment: .trailing)

                Text(sessionTokenText(session))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.info)
                    .frame(width: 78, alignment: .trailing)

                Text(memoryText(session.memoryMB))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 58, alignment: .trailing)

                Text("\(session.turnCount)")
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 42, alignment: .trailing)

                if !session.ports.isEmpty {
                    Text(":\(session.ports.map(String.init).joined(separator: ",:"))")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.warning)
                        .frame(width: 0)
                        .hidden()
                }
            }
            .padding(Theme.Spacing.md)
            .background(selected ? Theme.Colors.accent.opacity(0.12) : Theme.Colors.elevatedCardBg.opacity(0.58))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(selected ? Theme.Colors.accent.opacity(0.44) : Theme.Colors.separator.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: selected ? Theme.Colors.accent.opacity(0.08) : .clear, radius: 5, y: 2)
        }
        .buttonStyle(.plain)
    }

    private func dashboardCard<Actions: View, Content: View>(
        title: String,
        icon: String,
        color: Color,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Theme.Gradients.hero)
                    .clipShape(RoundedRectangle(cornerRadius: 11))
                    .shadow(color: Theme.Colors.accent.opacity(0.16), radius: 8, y: 4)
                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                actions()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.elevatedCardBg.opacity(0.86))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Colors.separator, lineWidth: 1)
        )
        .shadow(color: Theme.Shadow.mdColor, radius: 18, y: 9)
    }

    private func tokenRow(_ title: String, value: Int, total: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(compactCount(value))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(color)
            }
            ProgressView(value: min(Double(value) / Double(max(total, 1)), 1))
                .progressViewStyle(.linear)
                .tint(color)
        }
    }

    private func tokenUsageGrid(for session: AgentMonitorSessionSnapshot) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(minimum: 180), spacing: Theme.Spacing.md),
                GridItem(.flexible(minimum: 180), spacing: Theme.Spacing.md)
            ],
            spacing: Theme.Spacing.sm
        ) {
            tokenRow(localizer.overviewInput, value: session.tokens.input, total: max(session.tokens.total, 1), color: Theme.Colors.success)
            tokenRow(localizer.overviewOutput, value: session.tokens.output, total: max(session.tokens.total, 1), color: Theme.Colors.danger)
            tokenRow(localizer.overviewCacheRead, value: session.tokens.cacheRead, total: max(session.tokens.total, 1), color: Theme.Colors.info)
            tokenRow(localizer.overviewTotal, value: session.tokens.total, total: max(session.tokens.total, 1), color: Theme.Colors.info)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func contextProgress(_ value: Double, window: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(localizer.overviewContextWindow)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text("\(Int(value * 100))% / \(windowText(window))")
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(contextColor(value))
            }
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(contextColor(value))
        }
    }

    private func smallInfo(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value.isEmpty ? "—" : value)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.sidebarBg.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func sessionField(_ title: String, _ value: String, width: CGFloat, color: Color = Theme.Colors.textPrimary) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value.isEmpty ? "—" : value)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.middle)
        }
        .frame(width: width, alignment: .topLeading)
        .frame(minHeight: 32, alignment: .topLeading)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(Theme.Colors.sidebarBg.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func agentAvatar(_ name: String) -> some View {
        Text(name.prefix(2).uppercased())
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(name == "Codex" ? Theme.Colors.accent : Theme.Colors.purple)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(title)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(detail)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 118)
    }

    private func normalizeSelection() {
        guard !sessions.isEmpty else {
            selectedSessionID = nil
            return
        }
        if let selectedSessionID,
           sessions.contains(where: { $0.id == selectedSessionID }) {
            return
        }
        selectedSessionID = sessions.first?.id
    }

    private func refreshSelectedActiveSessionIfNeeded(_ data: AgentCommandDashboardData) {
        guard let session = data.selectedActiveSession,
              isActiveSession(session) else { return }
        store.refreshFocusedSession(session)
    }

    private func moveSelection(_ offset: Int) {
        guard !activeSessions.isEmpty else { return }
        let current = selectedActiveSession.flatMap { session in
            activeSessions.firstIndex(where: { $0.id == session.id })
        } ?? 0
        let next = (current + offset + activeSessions.count) % activeSessions.count
        selectedSessionID = activeSessions[next].id
    }

    private func copySelectedPath() {
        guard let session = selectedSession else { return }
        copyPath(for: session)
    }

    private func copyPath(for session: AgentMonitorSessionSnapshot) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(session.projectPath.isEmpty ? session.sourcePath : session.projectPath, forType: .string)
    }

    private func openSelectedProject() {
        guard let session = selectedSession else { return }
        openProject(for: session)
    }

    private func openProject(for session: AgentMonitorSessionSnapshot) {
        let path = session.projectPath.isEmpty ? session.sourcePath : session.projectPath
        guard !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    private func loadMoreOverviewSessionsText(remaining: Int) -> String {
        switch localizer.language {
        case .simplifiedChinese:
            return "加载更多（剩余 \(remaining)）"
        case .traditionalChinese:
            return "載入更多（剩餘 \(remaining)）"
        case .japanese:
            return "さらに読み込む（残り \(remaining)）"
        case .korean:
            return "더 불러오기 (\(remaining)개 남음)"
        case .english, .maltese:
            return "Load more (\(remaining) left)"
        }
    }

    private func statusText(_ status: String) -> String {
        switch status {
        case "Waiting": return localizer.overviewStatusWaiting
        case "Paused": return pausedStatusText
        case "Thinking": return localizer.overviewStatusThinking
        case "Executing": return localizer.overviewStatusExecuting
        case "History": return localizer.overviewStatusHistory
        case "Done": return localizer.overviewStatusDone
        default: return localizer.overviewStatusUnknown
        }
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Waiting": return Theme.Colors.info
        case "Paused": return Theme.Colors.warning
        case "Thinking": return Theme.Colors.purple
        case "Executing": return Theme.Colors.success
        case "History": return Theme.Colors.textTertiary
        case "Done": return Theme.Colors.info
        default: return Theme.Colors.textTertiary
        }
    }

    private var pausedStatusText: String {
        switch localizer.language {
        case .simplifiedChinese: return "暂停"
        case .traditionalChinese: return "暫停"
        case .japanese: return "一時停止"
        case .korean: return "일시 중지"
        case .english, .maltese: return "Paused"
        }
    }

    private func agentCode(_ name: String) -> String {
        if name.localizedCaseInsensitiveContains("codex") { return "CD" }
        if name.localizedCaseInsensitiveContains("claude") { return "CL" }
        if name.localizedCaseInsensitiveContains("opencode") { return "OC" }
        if name.localizedCaseInsensitiveContains("gemini") { return "GM" }
        if name.localizedCaseInsensitiveContains("cursor") { return "CU" }
        return String(name.prefix(2)).uppercased()
    }

    private func agentColor(_ name: String) -> Color {
        if name.localizedCaseInsensitiveContains("codex") { return Theme.Colors.accent }
        if name.localizedCaseInsensitiveContains("claude") { return Theme.Colors.purple }
        if name.localizedCaseInsensitiveContains("opencode") { return Theme.Colors.success }
        return Theme.Colors.info
    }

    private func networkRiskColor(_ risk: String) -> Color {
        switch risk {
        case "cleartext": return Theme.Colors.danger
        case "unknown": return Theme.Colors.warning
        case "proxy": return Theme.Colors.info
        default: return Theme.Colors.success
        }
    }

    private func networkSafetyColor(_ status: String?) -> Color {
        switch status {
        case "proxyBypass", "unsafe": return Theme.Colors.danger
        case "publicDirect", "unknown": return Theme.Colors.warning
        case "proxied": return Theme.Colors.info
        default: return Theme.Colors.success
        }
    }

    private func networkSafetyText(_ status: String?) -> String {
        switch status {
        case "proxyBypass":
            return localizer.t("疑似绕过代理", en: "Proxy bypass", zhHant: "疑似繞過代理", ja: "プロキシ迂回", ko: "프록시 우회", mt: "Proxy bypass")
        case "unsafe":
            return localizer.t("不安全", en: "Unsafe", zhHant: "不安全", ja: "安全でない", ko: "안전하지 않음", mt: "Unsafe")
        case "publicDirect":
            return localizer.t("公网直连", en: "Public direct", zhHant: "公網直連", ja: "公開網直結", ko: "공용망 직접", mt: "Public direct")
        case "unknown":
            return localizer.t("待确认", en: "Review", zhHant: "待確認", ja: "要確認", ko: "확인 필요", mt: "Review")
        case "proxied":
            return localizer.t("经代理", en: "Proxied", zhHant: "經代理", ja: "プロキシ経由", ko: "프록시 경유", mt: "Proxied")
        default:
            return localizer.t("安全", en: "Safe", zhHant: "安全", ja: "安全", ko: "안전", mt: "Safe")
        }
    }

    private func networkRiskText(_ risk: String) -> String {
        switch risk {
        case "cleartext":
            return localizer.t("明文", en: "Clear", zhHant: "明文", ja: "平文", ko: "평문", mt: "Clear")
        case "unknown":
            return localizer.t("未知", en: "Unknown", zhHant: "未知", ja: "不明", ko: "알 수 없음", mt: "Unknown")
        case "proxy":
            return localizer.t("代理", en: "Proxy", zhHant: "代理", ja: "プロキシ", ko: "프록시", mt: "Proxy")
        default:
            return localizer.t("正常", en: "Normal", zhHant: "正常", ja: "通常", ko: "정상", mt: "Normal")
        }
    }

    private func configRoot(for session: AgentMonitorSessionSnapshot) -> String {
        let lower = session.sourcePath.lowercased()
        if lower.contains("/.codex/") { return "~/.codex" }
        if lower.contains("/.claude/") { return "~/.claude" }
        if lower.contains("/.opencode/") { return "~/.opencode" }
        if lower.contains("/.gemini/") { return "~/.gemini" }
        return localizer.overviewAuthorizeFolder
    }

    private func displayLocation(for session: AgentMonitorSessionSnapshot) -> String {
        if !session.projectPath.isEmpty {
            return shortPath(session.projectPath)
        }
        return configRoot(for: session)
    }

    private func shortPath(_ path: String) -> String {
        let home = SandboxPaths.realHomeDirectory
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~/" + path.dropFirst(home.count + 1)
        }
        return path
    }

    private func memoryText(_ value: Int?) -> String {
        guard let value, value > 0 else { return "—" }
        if value >= 1024 { return String(format: "%.1fG", Double(value) / 1024.0) }
        return "\(value)M"
    }

    private func shortRoot(_ path: String) -> String {
        let home = SandboxPaths.realHomeDirectory
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~/" + path.dropFirst(home.count + 1)
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func contextDetail(_ value: Double) -> String {
        if value >= 0.85 { return localizer.overviewContextNearLimit }
        if value >= 0.65 { return localizer.overviewContextWatch }
        return localizer.overviewContextHealthy
    }

    private func shortSessionId(_ sessionId: String) -> String {
        String(sessionId.prefix(8))
    }

    private func sessionInstructionTimeText(_ session: AgentMonitorSessionSnapshot) -> String {
        guard let date = session.instructionDate ?? session.latestActivity else { return "—" }
        return DisplayTime.withSeconds.string(from: date)
    }

    private func unreportedText() -> String {
        localizer.t("未上报", en: "unreported", zhHant: "未上報", ja: "未報告", ko: "미보고", mt: "unreported")
    }

    private func sessionModelText(_ session: AgentMonitorSessionSnapshot) -> String {
        let raw = session.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = raw.lowercased()
        if raw.isEmpty || raw == "—" || lower == "null" || lower == "unknown" {
            return "\(session.agentName) / \(unreportedText())"
        }
        if lower == "<synthetic>" {
            return session.agentName == "Claude Code"
                ? "Claude Desktop"
                : session.agentName
        }
        if lower.hasPrefix("aimami_relay_") {
            return "Codex Relay"
        }
        if raw.count > 36 || raw.range(of: #"^[A-Za-z0-9_-]{24,}$"#, options: .regularExpression) != nil {
            return "\(session.agentName) / \(localizer.t("内部模型", en: "internal model", zhHant: "內部模型", ja: "内部モデル", ko: "내부 모델", mt: "internal model"))"
        }
        return raw
    }

    private func sessionTokenText(_ session: AgentMonitorSessionSnapshot) -> String {
        session.tokens.total > 0 ? compactCount(session.tokens.total) : unreportedText()
    }

    private func sessionContextPercentText(_ session: AgentMonitorSessionSnapshot) -> String {
        if session.contextPercent == 0, session.tokens.total == 0 { return unreportedText() }
        return "\(Int(session.contextPercent * 100))%"
    }

    private func sessionContextText(_ session: AgentMonitorSessionSnapshot) -> String {
        if session.contextPercent == 0, session.tokens.total == 0 {
            return "\(unreportedText()) / \(windowText(session.contextWindow))"
        }
        return "\(Int(session.contextPercent * 100))% / \(windowText(session.contextWindow))"
    }

    private func windowText(_ window: Int) -> String {
        guard window > 0 else { return unreportedText() }
        if window >= 1_000_000 { return String(format: "%.1fM", Double(window) / 1_000_000.0) }
        if window >= 1_000 { return String(format: "%.1fk", Double(window) / 1_000.0) }
        return "\(window)"
    }

    private func compactCount(_ value: Int) -> String {
        AgentUsageTokenFormatter.string(Int64(value))
    }

    private func contextColor(_ progress: Double) -> Color {
        if progress >= 0.85 { return Theme.Colors.danger }
        if progress >= 0.65 { return Theme.Colors.warning }
        return Theme.Colors.success
    }
}

private struct ActiveSessionDetailSheet: View {
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) private var dismiss

    let session: AgentMonitorSessionSnapshot
    let statusText: String
    let statusColor: Color
    let contextColor: Color
    let displayLocation: String
    let configRoot: String
    let modelText: String
    let contextText: String
    let tokenText: String
    let shortSessionId: String
    let memoryText: String
    let compactCount: (Int) -> String
    let onCopyPath: () -> Void
    let onOpenProject: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    taskBlock
                    metricsGrid
                    tokenBlock
                    pathBlock
                }
                .padding(Theme.Spacing.xl)
            }
            Divider()
            footer
        }
        .frame(width: 720, height: 540)
        .background(Theme.Colors.cardBg)
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "sidebar.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(Theme.Gradients.hero)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 3) {
                Text(localizer.agentSessionDetail)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text("\(session.agentName) · \(session.projectName)")
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            statusBadge

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help(localizer.confirmBtn)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var taskBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(localizer.overviewCurrentTurn)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(session.currentTask.isEmpty ? localizer.overviewWaitingAgentSession : session.currentTask)
                .font(Theme.Font.subheadlineMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.sidebarBg.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.sm)], spacing: Theme.Spacing.sm) {
            infoTile(localizer.overviewSession, shortSessionId, Theme.Colors.warning)
            infoTile(localizer.overviewModel, modelText, Theme.Colors.textPrimary)
            infoTile(localizer.overviewProject, session.projectName, Theme.Colors.info)
            infoTile(localizer.overviewLocation, displayLocation, Theme.Colors.textPrimary)
            infoTile(localizer.contextWindow, contextText, contextColor)
            infoTile(localizer.overviewMemory, memoryText, Theme.Colors.textPrimary)
            infoTile(localizer.overviewTurns, "\(session.turnCount)", Theme.Colors.textPrimary)
            infoTile("PID", session.pid.map(String.init) ?? "-", Theme.Colors.textPrimary)
        }
    }

    private var tokenBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(localizer.overviewTokenUse)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(tokenText)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.info)
            }
            ProgressView(value: min(Double(session.tokens.total) / Double(max(session.contextWindow, 1)), 1))
                .progressViewStyle(.linear)
                .tint(Theme.Colors.info)
            HStack(spacing: Theme.Spacing.sm) {
                infoTile(localizer.overviewInput, compactCount(session.tokens.input), Theme.Colors.success)
                infoTile(localizer.overviewOutput, compactCount(session.tokens.output), Theme.Colors.danger)
                infoTile(localizer.overviewCacheRead, compactCount(session.tokens.cacheRead), Theme.Colors.info)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.sidebarBg.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var pathBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            detailRow(title: localizer.overviewProject, value: session.projectPath.isEmpty ? "-" : session.projectPath)
            detailRow(title: localizer.sourceCol, value: session.sourcePath)
            detailRow(title: localizer.configCol, value: configRoot)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.sidebarBg.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var footer: some View {
        HStack {
            Button { onCopyPath() } label: {
                Label(localizer.copyPath, systemImage: "doc.on.doc")
            }
            .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .secondary, minHeight: 34))

            Button { onOpenProject() } label: {
                Label(localizer.openInFinder, systemImage: "folder")
            }
            .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .secondary, minHeight: 34))

            Spacer()

            Button { dismiss() } label: {
                Text(localizer.confirmBtn)
                    .frame(minWidth: 72)
            }
            .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 34))
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .background(.ultraThinMaterial)
        .background(Theme.Colors.elevatedCardBg.opacity(0.52))
    }

    private func infoTile(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value.isEmpty ? "-" : value)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.cardBg.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(value.isEmpty ? "-" : value)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ActiveSessionEmptySheet: View {
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(localizer.overviewNoActiveSession)
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(localizer.overviewNoActiveSessionHint)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button { dismiss() } label: {
                Text(localizer.confirmBtn)
                    .frame(minWidth: 72)
            }
            .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 34))
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460, height: 300)
        .appCanvas()
    }
}

struct OperationLogTab: View {
    @ObservedObject var monitor: OperationMonitor
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var sessionsViewModel: SessionsViewModel
    @EnvironmentObject var usageInsightsService: AgentUsageInsightsService
    @State private var searchText = ""
    @State private var filterAgent = ""
    @State private var filterOpType: OperationRecord.OperationType?
    @State private var filterTimeRange: TimeRange = .all
    @State private var autoRefreshSeconds = 5
    @State private var lastAutoRefresh = Date.distantPast
    @State private var viewMode = 0
    @State private var selectedProjectId: String?
    @State private var automationProjectSnapshots: [MonitorProjectSnapshot] = []
    @State private var coreSessionSnapshots: [TraceFenceAgentCoreSessionSnapshot] = []
    @State private var cachedProjectSnapshots: [MonitorProjectSnapshot] = []
    @State private var cachedDisplayableRecords: [OperationRecord] = []
    @State private var cachedAgentNames: [String] = []
    @State private var projectSnapshotSignature = ""
    @State private var lastHeavyRefresh = Date.distantPast
    @State private var lastCoreRefresh = Date.distantPast
    @State private var coreRefreshInFlight = false
    @Namespace private var segmentNS

    private static let projectRecordWindowLimit = 2_000
    private static let heavyRefreshInterval: TimeInterval = 60
    private static let coreRefreshInterval: TimeInterval = 10

    enum TimeRange: String, CaseIterable {
        case all = "all"
        case today = "today"
        case hour1 = "hour1"
        case hour6 = "hour6"
        case day1 = "day1"
        case day7 = "day7"

        func label(_ localizer: Localizer) -> String {
            switch self {
            case .all: return localizer.timeAll
            case .today: return localizer.timeToday
            case .hour1: return localizer.time1h
            case .hour6: return localizer.time6h
            case .day1: return localizer.time24h
            case .day7: return localizer.time7d
            }
        }
    }

    private enum MonitorProjectLane: String, CaseIterable {
        case live
        case scheduled
        case blocked
        case completed

        func title(_ localizer: Localizer) -> String {
            switch self {
            case .live:
                return localizer.t("实时项目", en: "Live Projects", zhHant: "即時專案", ja: "ライブプロジェクト", ko: "실시간 프로젝트", mt: "Live Projects")
            case .scheduled:
                return localizer.t("定时项目", en: "Scheduled", zhHant: "排程專案", ja: "予定タスク", ko: "예약 작업", mt: "Scheduled")
            case .blocked:
                return localizer.t("阻塞关注", en: "Blocked", zhHant: "阻塞關注", ja: "ブロック中", ko: "차단됨", mt: "Blocked")
            case .completed:
                return localizer.t("最近完成", en: "Recently Done", zhHant: "最近完成", ja: "最近完了", ko: "최근 완료", mt: "Recently Done")
            }
        }

        var icon: String {
            switch self {
            case .live: return "dot.radiowaves.left.and.right"
            case .scheduled: return "calendar.badge.clock"
            case .blocked: return "exclamationmark.triangle.fill"
            case .completed: return "checkmark.seal.fill"
            }
        }

        var color: Color {
            switch self {
            case .live: return Theme.Colors.success
            case .scheduled: return Theme.Colors.info
            case .blocked: return Theme.Colors.warning
            case .completed: return Theme.Colors.purple
            }
        }
    }

    private struct MonitorProjectSnapshot: Identifiable {
        let id: String
        let title: String
        let path: String
        let lane: MonitorProjectLane
        let agents: [String]
        let sessions: [SessionState]
        let records: [OperationRecord]
        let progress: Double
        let summary: String
        let blocker: String?
        let scheduledHint: String?
        let lastActivity: Date
        let activeTools: [String]
        let completedTasks: Int
        let totalTasks: Int

        var recordCount: Int { records.count }
        var sessionCount: Int { sessions.count }
    }

    private struct ProjectUsageRollup {
        var sevenDayTokens = AgentUsageTokenTotals.zero
        var allTimeTokens = AgentUsageTokenTotals.zero
        var estimatedAPIValueUSD: Double = 0
        var sessionCount = 0
        var lastActiveAt: Date?
        var agents = Set<String>()
        var sourceQuality: AgentUsageSourceQuality = .unavailable
    }

    private struct MonitorAutomationConfig {
        let id: String
        let name: String
        let status: String
        let model: String
        let kind: String
        let schedule: String
        let description: String
        let cwds: [String]
        let directoryPath: String
        let updatedAt: Date
    }

    var agentNames: [String] {
        if !projectSnapshotSignature.isEmpty { return cachedAgentNames }
        return Array(Set(displayableOperationRecords.map(\.agentName))).sorted()
    }

    var filteredRecords: [OperationRecord] {
        var result = displayableOperationRecords
        let now = Date()
        if !filterAgent.isEmpty {
            result = result.filter { $0.agentName == filterAgent }
        }
        if let opType = filterOpType {
            result = result.filter { $0.operationType == opType }
        }
        switch filterTimeRange {
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            result = result.filter { $0.timestamp >= start }
        case .hour1:
            result = result.filter { now.timeIntervalSince($0.timestamp) < 3600 }
        case .hour6:
            result = result.filter { now.timeIntervalSince($0.timestamp) < 21600 }
        case .day1:
            result = result.filter { now.timeIntervalSince($0.timestamp) < 86400 }
        case .day7:
            result = result.filter { now.timeIntervalSince($0.timestamp) < 604800 }
        case .all:
            break
        }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            result = result.filter {
                $0.targetPath.lowercased().contains(q) ||
                $0.agentName.lowercased().contains(q) ||
                $0.detail.lowercased().contains(q)
            }
        }
        return deduplicatedRecords(result)
    }

    private var filteredProjectSnapshots: [MonitorProjectSnapshot] {
        let snapshots = projectSnapshots
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return snapshots }
        return snapshots.filter { project in
            project.title.lowercased().contains(query) ||
            project.path.lowercased().contains(query) ||
            project.summary.lowercased().contains(query) ||
            project.agents.contains { $0.lowercased().contains(query) } ||
            project.activeTools.contains { $0.lowercased().contains(query) }
        }
    }

    private var selectedProject: MonitorProjectSnapshot? {
        if let selectedProjectId,
           let match = filteredProjectSnapshots.first(where: { $0.id == selectedProjectId }) {
            return match
        }
        return filteredProjectSnapshots.first
    }

    private var projectSnapshots: [MonitorProjectSnapshot] {
        cachedProjectSnapshots
    }

    private func rebuildProjectSnapshotCache(force: Bool = false) {
        let records = Array(allOperationRecords.prefix(Self.projectRecordWindowLimit))
        let signature = projectDataSignature(records: records)
        guard force || signature != projectSnapshotSignature else { return }

        let displayableRecords = records.filter(isDisplayableAgentRecord)
        let recentCutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let recentRecords = displayableRecords.filter { $0.timestamp >= recentCutoff }
        let recordsByProject = Dictionary(grouping: recentRecords) { operationProjectKey($0) }
        let sessionGroups = Dictionary(grouping: sessionsViewModel.sessions) { sessionProjectKey($0) }

        var snapshots = sessionGroups.compactMap { key, sessions in
            makeSessionProject(key: key, sessions: sessions, recordsByProject: recordsByProject)
        }
        var knownKeys = Set(snapshots.map(\.id))
        let operationSnapshots = operationProjectSnapshots(excluding: knownKeys, groupedRecords: recordsByProject)
        snapshots.append(contentsOf: operationSnapshots)
        knownKeys.formUnion(operationSnapshots.map(\.id))
        let coreSnapshots = coreProjectSnapshots(excluding: knownKeys)
        snapshots.append(contentsOf: coreSnapshots)
        knownKeys.formUnion(coreSnapshots.map(\.id))
        snapshots.append(contentsOf: automationProjectSnapshots)
        knownKeys.formUnion(automationProjectSnapshots.map(\.id))
        snapshots.append(contentsOf: usageProjectSnapshots(excluding: knownKeys, existing: snapshots))
        snapshots.sort {
            if lanePriority($0.lane) != lanePriority($1.lane) {
                return lanePriority($0.lane) < lanePriority($1.lane)
            }
            return $0.lastActivity > $1.lastActivity
        }

        cachedDisplayableRecords = displayableRecords
        cachedAgentNames = Array(Set(displayableRecords.map(\.agentName) + coreSessionSnapshots.map(\.agentType))).sorted()
        cachedProjectSnapshots = snapshots
        projectSnapshotSignature = signature
        if let selectedProjectId, !snapshots.contains(where: { $0.id == selectedProjectId }) {
            self.selectedProjectId = nil
        }
    }

    private func projectDataSignature(records: [OperationRecord]) -> String {
        let recordKey = records.prefix(4)
            .map { "\($0.id):\(Int($0.timestamp.timeIntervalSince1970))" }
            .joined(separator: ",")
        let sessionKey = sessionsViewModel.sessions
            .map { session in
                "\(session.id):\(session.phase.rawValue):\(Int(sessionLastActivity(session).timeIntervalSince1970)):\(session.tasks.count):\(session.activeTools.count)"
            }
            .sorted()
            .joined(separator: ",")
        let automationKey = automationProjectSnapshots
            .map { "\($0.id):\(Int($0.lastActivity.timeIntervalSince1970)):\($0.lane.rawValue)" }
            .joined(separator: ",")
        let coreKey = coreSessionSnapshots
            .prefix(80)
            .map { "\($0.id):\($0.phase):\(Int($0.lastActivityAt.timeIntervalSince1970))" }
            .joined(separator: ",")
        return "\(records.count)|\(recordKey)|\(sessionKey)|\(automationKey)|\(coreKey)"
    }

    private func coreProjectSnapshots(excluding knownKeys: Set<String>) -> [MonitorProjectSnapshot] {
        let now = Date()
        let recentCutoff = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let attentionCutoff = now.addingTimeInterval(-24 * 60 * 60)
        let activeCutoff = now.addingTimeInterval(-20 * 60)
        let rows = coreSessionSnapshots.filter {
            !$0.scheduledTask && $0.lastActivityAt >= recentCutoff
        }
        let groups = Dictionary(grouping: rows) { row -> String in
            let cwdRoot = projectRoot(from: row.cwd)
            if !cwdRoot.isEmpty { return cwdRoot }
            let projectRootValue = projectRoot(from: row.project)
            if !projectRootValue.isEmpty { return projectRootValue }
            let project = row.project.trimmingCharacters(in: .whitespacesAndNewlines)
            if !project.isEmpty { return project }
            return "core-agent:\(row.agentType.lowercased())"
        }

        return groups.compactMap { key, sessions in
            guard !knownKeys.contains(key),
                  let latest = sessions.max(by: { $0.lastActivityAt < $1.lastActivityAt }) else {
                return nil
            }

            let hasLiveSession = sessions.contains {
                $0.isActive && ($0.controlAvailable || $0.lastActivityAt >= activeCutoff)
            }
            let hasAttention = sessions.contains {
                $0.needsAttention && $0.lastActivityAt >= attentionCutoff
            }
            let lane: MonitorProjectLane = hasLiveSession ? .live : (hasAttention ? .blocked : .completed)
            let title: String
            if key.hasPrefix("core-agent:") {
                title = localizer.t("无项目", en: "No Project", zhHant: "無專案", ja: "プロジェクトなし", ko: "프로젝트 없음", mt: "No Project")
            } else {
                title = projectDisplayName(for: key, fallback: latest.project.isEmpty ? latest.agentType : latest.project)
            }
            let summaryCandidates = [latest.statusLineText, latest.title, latest.lastToolName]
            let summary = summaryCandidates.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                ?? localizer.t("已从 Agent Core 读取会话状态", en: "Session state loaded from Agent Core", zhHant: "已從 Agent Core 讀取工作階段狀態", ja: "Agent Core からセッション状態を読み込みました", ko: "Agent Core에서 세션 상태를 불러왔습니다", mt: "Session state loaded from Agent Core")
            let blocker = hasAttention
                ? localizer.t("Agent 会话需要处理", en: "Agent session needs attention", zhHant: "Agent 工作階段需要處理", ja: "Agent セッションへの対応が必要です", ko: "Agent 세션에 주의가 필요합니다", mt: "Agent session needs attention")
                : nil

            return MonitorProjectSnapshot(
                id: key,
                title: title,
                path: key.hasPrefix("core-agent:") ? "" : key,
                lane: lane,
                agents: uniqueStrings(sessions.map(\.agentType)),
                sessions: [],
                records: [],
                progress: lane == .live ? 0.55 : (lane == .blocked ? 0.35 : 1.0),
                summary: shortText(summary, limit: 150),
                blocker: blocker,
                scheduledHint: nil,
                lastActivity: latest.lastActivityAt,
                activeTools: uniqueStrings(sessions.map(\.lastToolName)),
                completedTasks: 0,
                totalTasks: 0
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    private func usageProjectSnapshots(
        excluding knownKeys: Set<String>,
        existing: [MonitorProjectSnapshot]
    ) -> [MonitorProjectSnapshot] {
        let knownPaths = Set(existing.compactMap { project -> String? in
            let value = normalizedProjectPath(project.path)
            return value.isEmpty ? nil : value
        }).union(knownKeys.compactMap { key -> String? in
            guard key.hasPrefix("/") || key.hasPrefix("~") else { return nil }
            let value = normalizedProjectPath(key)
            return value.isEmpty ? nil : value
        })

        return projectUsageRollups().compactMap { path, usage -> MonitorProjectSnapshot? in
            guard !path.isEmpty, !knownPaths.contains(path) else { return nil }
            let title = URL(fileURLWithPath: path).lastPathComponent
            let tasks = usageTasks(projectPath: path, projectName: title)
            return MonitorProjectSnapshot(
                id: path,
                title: title.isEmpty ? localizer.t("未知项目", en: "Unknown Project") : title,
                path: path,
                lane: .completed,
                agents: usage.agents.sorted(),
                sessions: [],
                records: [],
                progress: 1,
                summary: localizer.t(
                    "来自统一 Token 与用量统计的历史项目。",
                    en: "Historical project from unified Token & Usage analytics."
                ),
                blocker: nil,
                scheduledHint: nil,
                lastActivity: usage.lastActiveAt ?? .distantPast,
                activeTools: [],
                completedTasks: tasks.filter { $0.category == .done }.count,
                totalTasks: tasks.count
            )
        }
    }

    private func projectUsageRollups() -> [String: ProjectUsageRollup] {
        let snapshot = usageInsightsService.snapshot(for: .combined)
        var result: [String: ProjectUsageRollup] = [:]

        for project in snapshot.projectRankingsAllTime {
            let path = normalizedProjectPath(project.fullPath)
            guard !path.isEmpty else { continue }
            var value = result[path, default: ProjectUsageRollup()]
            value.allTimeTokens.add(project.tokens)
            value.estimatedAPIValueUSD += project.estimatedAPIValueUSD
            value.sessionCount += project.sessionCount
            if let date = project.lastActiveAt,
               value.lastActiveAt == nil || date > value.lastActiveAt! {
                value.lastActiveAt = date
            }
            value.agents.insert(usageScopeName(project.id))
            value.sourceQuality = mergedSourceQuality(value.sourceQuality, project.sourceQuality)
            result[path] = value
        }

        for project in snapshot.projectRankings7Days {
            let path = normalizedProjectPath(project.fullPath)
            guard !path.isEmpty else { continue }
            var value = result[path, default: ProjectUsageRollup()]
            value.sevenDayTokens.add(project.tokens)
            value.agents.insert(usageScopeName(project.id))
            value.sourceQuality = mergedSourceQuality(value.sourceQuality, project.sourceQuality)
            result[path] = value
        }
        return result
    }

    private func usageForProject(_ project: MonitorProjectSnapshot) -> ProjectUsageRollup? {
        let path = normalizedProjectPath(project.path)
        guard !path.isEmpty else { return nil }
        return projectUsageRollups()[path]
    }

    private func usageTasks(for project: MonitorProjectSnapshot) -> [AgentUsageTaskItem] {
        usageTasks(projectPath: project.path, projectName: project.title)
    }

    private func usageTasks(projectPath: String, projectName: String) -> [AgentUsageTaskItem] {
        let normalizedPath = normalizedProjectPath(projectPath)
        let normalizedName = projectName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return usageInsightsService.snapshot(for: .combined).tasks.all.filter { task in
            guard let taskProject = task.project?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !taskProject.isEmpty else { return false }
            let taskPath = normalizedProjectPath(taskProject)
            if !normalizedPath.isEmpty, !taskPath.isEmpty, taskPath == normalizedPath { return true }
            let taskName = URL(fileURLWithPath: taskProject).lastPathComponent.lowercased()
            return !normalizedName.isEmpty && (taskProject.lowercased() == normalizedName || taskName == normalizedName)
        }
    }

    private func normalizedProjectPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Unknown project" else { return "" }
        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else { return "" }
        return URL(fileURLWithPath: expanded).standardizedFileURL.path
    }

    private func usageScopeName(_ projectID: String) -> String {
        if projectID.hasPrefix("claude:") { return "Claude Code" }
        if projectID.hasPrefix("codex:") { return "Codex" }
        return localizer.t("Agent", en: "Agent")
    }

    private func mergedSourceQuality(
        _ lhs: AgentUsageSourceQuality,
        _ rhs: AgentUsageSourceQuality
    ) -> AgentUsageSourceQuality {
        if lhs == .unavailable { return rhs }
        if rhs == .unavailable || lhs == rhs { return lhs }
        return .mixed
    }

    private var liveProjectCount: Int {
        projectSnapshots.filter { $0.lane == .live }.count
    }

    private var scheduledProjectCount: Int {
        projectSnapshots.filter { $0.lane == .scheduled }.count
    }

    private var blockedProjectCount: Int {
        projectSnapshots.filter { $0.lane == .blocked }.count
    }

    private func timeWithSeconds(_ date: Date) -> String {
        DisplayTime.withSeconds.string(from: date)
    }

    private func deduplicatedRecords(_ records: [OperationRecord]) -> [OperationRecord] {
        var seen: Set<String> = []
        return records.filter { record in
            let bucket = Int(record.timestamp.timeIntervalSince1970 / 5.0)
            var parts = [
                record.agentName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                record.operationType.rawValue,
                record.targetPath.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                "\(bucket)"
            ]
            if record.operationType == .execute {
                parts.append(record.detail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            }
            let key = parts.joined(separator: "|")
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private var agentActivityProgress: Double {
        guard !agentNames.isEmpty else { return 0 }
        let now = Date()
        let recentAgents = Set(displayableOperationRecords.filter { now.timeIntervalSince($0.timestamp) < 3600 }.map(\.agentName)).count
        return Double(recentAgents) / Double(agentNames.count)
    }

    private var todayRecordCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return displayableOperationRecords.filter { $0.timestamp >= start }.count
    }

    private var hourRecordCount: Int {
        let now = Date()
        return displayableOperationRecords.filter { now.timeIntervalSince($0.timestamp) < 3600 }.count
    }

    private var allOperationRecords: [OperationRecord] {
        let serviceRecords = service.operationRecords
        let liveRecords = monitor.records
        if serviceRecords.isEmpty { return liveRecords }
        if liveRecords.count > serviceRecords.count { return liveRecords }
        return serviceRecords
    }

    private var displayableOperationRecords: [OperationRecord] {
        if !projectSnapshotSignature.isEmpty || allOperationRecords.isEmpty {
            return cachedDisplayableRecords
        }
        return allOperationRecords.filter(isDisplayableAgentRecord)
    }

    private func isDisplayableAgentRecord(_ record: OperationRecord) -> Bool {
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

    private func makeSessionProject(
        key: String,
        sessions: [SessionState],
        recordsByProject: [String: [OperationRecord]]? = nil
    ) -> MonitorProjectSnapshot? {
        guard !sessions.isEmpty else { return nil }
        let sortedSessions = sessions.sorted { sessionLastActivity($0) > sessionLastActivity($1) }
        let records = recordsForProject(key: key, sessions: sortedSessions, recordsByProject: recordsByProject)
        let pending = sortedSessions.filter(hasPendingAttention)
        let tasks = sortedSessions.flatMap(\.tasks)
        let completedTasks = tasks.filter { taskIsDone($0) }.count
        let totalTasks = tasks.count
        let hasScheduledSignal = sortedSessions.contains(where: isScheduledSession)
        let lane: MonitorProjectLane

        if !pending.isEmpty {
            lane = .blocked
        } else if sortedSessions.contains(where: { $0.phase.isActive }) {
            lane = .live
        } else if hasScheduledSignal {
            lane = .scheduled
        } else {
            lane = .completed
        }

        return MonitorProjectSnapshot(
            id: key,
            title: projectTitle(for: sortedSessions, fallback: key),
            path: key,
            lane: lane,
            agents: uniqueStrings(sortedSessions.map(\.agentType) + records.map(\.agentName)),
            sessions: sortedSessions,
            records: records,
            progress: progressForProject(sessions: sortedSessions, completedTasks: completedTasks, totalTasks: totalTasks),
            summary: projectSummary(sessions: sortedSessions, records: records),
            blocker: blockerText(for: pending.first),
            scheduledHint: hasScheduledSignal ? scheduleHint(for: sortedSessions) : nil,
            lastActivity: max(records.map(\.timestamp).max() ?? .distantPast, sortedSessions.map(sessionLastActivity).max() ?? .distantPast),
            activeTools: uniqueStrings(sortedSessions.flatMap { $0.activeTools.map(\.toolName) + [ $0.lastToolName ].compactMap { $0 } } + records.compactMap(\.toolInfo)),
            completedTasks: completedTasks,
            totalTasks: totalTasks
        )
    }

    private func operationProjectSnapshots(
        excluding knownKeys: Set<String>,
        groupedRecords: [String: [OperationRecord]]? = nil
    ) -> [MonitorProjectSnapshot] {
        let groups: [String: [OperationRecord]]
        if let groupedRecords {
            groups = groupedRecords
        } else {
            let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
            let recentRecords = allOperationRecords
                .filter(isDisplayableAgentRecord)
                .filter { $0.timestamp >= cutoff }
            groups = Dictionary(grouping: recentRecords) { operationProjectKey($0) }
        }

        return groups.compactMap { key, records in
            guard !key.isEmpty, !knownKeys.contains(key) else { return nil }
            let sorted = records.sorted { $0.timestamp > $1.timestamp }
            guard let latest = sorted.first else { return nil }
            let isRecent = Date().timeIntervalSince(latest.timestamp) < 3600
            let hasScheduled = sorted.contains { recordHasScheduledSignal($0) }
            let lane: MonitorProjectLane = hasScheduled ? .scheduled : (isRecent ? .live : .completed)
            let title = projectDisplayName(for: key, fallback: latest.agentName)

            return MonitorProjectSnapshot(
                id: key,
                title: title,
                path: key,
                lane: lane,
                agents: uniqueStrings(sorted.map(\.agentName)),
                sessions: [],
                records: Array(sorted.prefix(20)),
                progress: lane == .live ? 0.55 : lane == .scheduled ? 0.2 : 0.95,
                summary: shortText(latest.detail.isEmpty ? latest.targetPath : latest.detail, limit: 150),
                blocker: nil,
                scheduledHint: hasScheduled ? localizer.t("检测到定时/自动化活动", en: "Scheduled or automation activity detected", zhHant: "偵測到排程/自動化活動", ja: "予定/自動化アクティビティを検出", ko: "예약/자동화 활동 감지", mt: "Scheduled or automation activity detected") : nil,
                lastActivity: latest.timestamp,
                activeTools: uniqueStrings(sorted.compactMap(\.toolInfo)),
                completedTasks: 0,
                totalTasks: 0
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    private func readAutomationProjectSnapshots() -> [MonitorProjectSnapshot] {
        let root = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
            .appendingPathComponent(".codex/automations", isDirectory: true)
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return directories.compactMap { directory -> MonitorProjectSnapshot? in
            let file = directory.appendingPathComponent("automation.toml")
            guard let config = parseAutomationConfig(file: file, directory: directory) else { return nil }

            let status = config.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let isPaused = ["disabled", "paused", "inactive", "stopped", "off"].contains(status)
            let path = config.cwds.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? config.directoryPath
            let scheduleText = [config.kind, config.schedule]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " · ")
            let hint = scheduleText.isEmpty
                ? localizer.t("等待下一次触发", en: "Waiting for next trigger", zhHant: "等待下一次觸發", ja: "次回トリガー待ち", ko: "다음 트리거 대기 중", mt: "Waiting for next trigger")
                : scheduleText
            let description = config.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = description.isEmpty
                ? localizer.t("Codex 定时项目会在触发后进入实时项目。", en: "This Codex automation will move into live projects after it starts.", zhHant: "Codex 排程專案觸發後會進入即時專案。", ja: "このCodex自動化は開始後にライブプロジェクトへ移動します。", ko: "이 Codex 자동화는 시작 후 실시간 프로젝트로 이동합니다.", mt: "This Codex automation will move into live projects after it starts.")
                : shortText(description, limit: 150)

            return MonitorProjectSnapshot(
                id: "codex-automation:\(config.id)",
                title: config.name,
                path: path,
                lane: isPaused ? .blocked : .scheduled,
                agents: uniqueStrings(["Codex", config.model]),
                sessions: [],
                records: [],
                progress: isPaused ? 0.08 : 0.18,
                summary: summary,
                blocker: isPaused ? localizer.t("定时项目当前处于暂停或禁用状态", en: "This scheduled project is paused or disabled.", zhHant: "此排程專案目前暫停或停用", ja: "この予定プロジェクトは一時停止または無効です。", ko: "이 예약 프로젝트는 일시 중지되었거나 비활성화되었습니다.", mt: "This scheduled project is paused or disabled.") : nil,
                scheduledHint: hint,
                lastActivity: config.updatedAt,
                activeTools: [],
                completedTasks: 0,
                totalTasks: 1
            )
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }

    private func parseAutomationConfig(file: URL, directory: URL) -> MonitorAutomationConfig? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }

        var name = directory.lastPathComponent
        var status = "active"
        var model = ""
        var kind = ""
        var schedule = ""
        var description = ""
        var cwds: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }

            if let value = tomlStringValue(line, key: "name") {
                name = value
            } else if let value = tomlStringValue(line, key: "status") {
                status = value
            } else if let value = tomlStringValue(line, key: "model") {
                model = value
            } else if let value = tomlStringValue(line, key: "kind") {
                kind = value
            } else if let value = tomlStringValue(line, key: "rrule") {
                schedule = value
            } else if let value = tomlStringValue(line, key: "cron") {
                schedule = value
            } else if let value = tomlStringValue(line, key: "schedule") {
                schedule = value
            } else if let value = tomlStringValue(line, key: "description") {
                description = value
            } else if let value = tomlStringValue(line, key: "objective") {
                description = description.isEmpty ? value : description
            } else if let value = tomlStringValue(line, key: "prompt") {
                description = description.isEmpty ? value : description
            } else if let value = tomlStringValue(line, key: "cwd") {
                cwds.append(value)
            } else if let values = tomlArrayValue(line, key: "cwds") {
                cwds.append(contentsOf: values)
            }
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
        let modified = attrs?[.modificationDate] as? Date ?? Date.distantPast
        return MonitorAutomationConfig(
            id: directory.lastPathComponent,
            name: name,
            status: status,
            model: model,
            kind: kind,
            schedule: schedule,
            description: description,
            cwds: uniqueStrings(cwds),
            directoryPath: directory.path,
            updatedAt: modified
        )
    }

    private func tomlStringValue(_ line: String, key: String) -> String? {
        guard line.hasPrefix("\(key) =") || line.hasPrefix("\(key)="),
              let first = line.firstIndex(of: "\""),
              let last = line.lastIndex(of: "\""),
              first < last else {
            return nil
        }
        return String(line[line.index(after: first)..<last])
    }

    private func tomlArrayValue(_ line: String, key: String) -> [String]? {
        guard line.hasPrefix("\(key) =") || line.hasPrefix("\(key)="),
              let open = line.firstIndex(of: "["),
              let close = line.lastIndex(of: "]"),
              open < close else {
            return nil
        }
        let body = line[line.index(after: open)..<close]
        return body
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"")) }
            .filter { !$0.isEmpty }
    }

    private func recordsForProject(
        key: String,
        sessions: [SessionState],
        recordsByProject: [String: [OperationRecord]]? = nil
    ) -> [OperationRecord] {
        let sessionKeys = Set(sessions.map { sessionProjectKey($0) })
        if let recordsByProject {
            var lookupKeys = sessionKeys
            lookupKeys.insert(key)
            var collected: [OperationRecord] = []
            for lookupKey in lookupKeys {
                if let records = recordsByProject[lookupKey] {
                    collected.append(contentsOf: records)
                }
            }
            return Array(collected.sorted { $0.timestamp > $1.timestamp }.prefix(20))
        }
        return allOperationRecords
            .filter(isDisplayableAgentRecord)
            .filter { record in
                let recordKey = operationProjectKey(record)
                return recordKey == key || sessionKeys.contains(recordKey)
            }
            .prefix(20)
            .map { $0 }
    }

    private func hasPendingAttention(_ session: SessionState) -> Bool {
        session.pendingPermission != nil ||
            session.pendingQuestion != nil ||
            session.pendingPlan != nil ||
            session.phase == .waitingApproval ||
            session.phase == .waitingInput ||
            session.phase == .error ||
            session.phase == .interrupted
    }

    private func isScheduledSession(_ session: SessionState) -> Bool {
        if (session.phase == .ready || session.phase == .idle) && session.hasUnfinishedTasks {
            return true
        }
        let text = [
            session.sessionTitle,
            session.description,
            session.statusLineText,
            session.lastUserMessage,
            session.lastResponse
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
        return scheduledKeywords.contains { text.contains($0) }
    }

    private func recordHasScheduledSignal(_ record: OperationRecord) -> Bool {
        let text = "\(record.targetPath) \(record.detail) \(record.toolInfo ?? "")".lowercased()
        return scheduledKeywords.contains { text.contains($0) }
    }

    private var scheduledKeywords: [String] {
        ["定时", "排程", "计划任务", "scheduled", "recurring", "cron", "automation", "monitor", "定期"]
    }

    private func blockerText(for session: SessionState?) -> String? {
        guard let session else { return nil }
        if let permission = session.pendingPermission {
            return localizer.t("等待权限审批: \(permission.toolName)", en: "Waiting for permission: \(permission.toolName)", zhHant: "等待權限審批: \(permission.toolName)", ja: "権限承認待ち: \(permission.toolName)", ko: "권한 승인 대기: \(permission.toolName)", mt: "Waiting for permission: \(permission.toolName)")
        }
        if let question = session.pendingQuestion {
            return localizer.t("等待回复: \(shortText(question.question, limit: 80))", en: "Waiting for reply: \(shortText(question.question, limit: 80))", zhHant: "等待回覆: \(shortText(question.question, limit: 80))", ja: "返信待ち: \(shortText(question.question, limit: 80))", ko: "응답 대기: \(shortText(question.question, limit: 80))", mt: "Waiting for reply: \(shortText(question.question, limit: 80))")
        }
        if let plan = session.pendingPlan {
            return localizer.t("等待计划确认: \(plan.title)", en: "Waiting for plan approval: \(plan.title)", zhHant: "等待計劃確認: \(plan.title)", ja: "計画承認待ち: \(plan.title)", ko: "계획 승인 대기: \(plan.title)", mt: "Waiting for plan approval: \(plan.title)")
        }
        if session.phase == .error { return localizer.agentCenterPhaseError }
        if session.phase == .interrupted { return localizer.agentCenterPhaseInterrupted }
        return nil
    }

    private func scheduleHint(for sessions: [SessionState]) -> String? {
        if let task = sessions.flatMap(\.tasks).first(where: { !taskIsDone($0) }) {
            return task.name
        }
        if let title = sessions.compactMap(\.sessionTitle).first(where: { !$0.isEmpty }) {
            return title
        }
        return localizer.t("等待下一次触发", en: "Waiting for next trigger", zhHant: "等待下一次觸發", ja: "次回トリガー待ち", ko: "다음 트리거 대기 중", mt: "Waiting for next trigger")
    }

    private func projectSummary(sessions: [SessionState], records: [OperationRecord]) -> String {
        let candidates = sessions.sorted { sessionLastActivity($0) > sessionLastActivity($1) }.flatMap { session in
            [
                session.statusLineText,
                session.description,
                session.lastResponse,
                session.lastThought,
                session.lastUserMessage,
                session.lastToolName
            ]
        }
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }

        if let text = candidates.first(where: { !$0.isEmpty }) {
            return shortText(text, limit: 150)
        }
        if let record = records.first {
            return shortText(record.detail.isEmpty ? record.targetPath : record.detail, limit: 150)
        }
        return localizer.t("等待更多实时事件", en: "Waiting for more live events", zhHant: "等待更多即時事件", ja: "ライブイベント待ち", ko: "추가 실시간 이벤트 대기 중", mt: "Waiting for more live events")
    }

    private func progressForProject(sessions: [SessionState], completedTasks: Int, totalTasks: Int) -> Double {
        if totalTasks > 0 {
            return min(max(Double(completedTasks) / Double(totalTasks), 0.05), 1.0)
        }
        let values = sessions.map { phaseProgress($0.phase) }
        guard !values.isEmpty else { return 0.55 }
        return values.reduce(0, +) / Double(values.count)
    }

    private func phaseProgress(_ phase: SessionPhase) -> Double {
        switch phase {
        case .ready: return 0.12
        case .idle: return 0.18
        case .processing: return 0.55
        case .waitingApproval, .waitingInput: return 0.48
        case .compacting: return 0.72
        case .done: return 1.0
        case .error: return 0.35
        case .interrupted: return 0.25
        }
    }

    private func taskIsDone(_ task: TaskInfo) -> Bool {
        let status = task.status.lowercased()
        return status == "completed" || status == "done" || status == "success" || status == "finished"
    }

    private func sessionLastActivity(_ session: SessionState) -> Date {
        if let lastMainAgentAt = session.lastMainAgentAt, lastMainAgentAt > 0 {
            let value = Double(lastMainAgentAt)
            return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value)
        }
        return session.endedAt ?? session.startedAt
    }

    private func sessionProjectKey(_ session: SessionState) -> String {
        let cwdRoot = projectRoot(from: session.cwd)
        if !cwdRoot.isEmpty { return cwdRoot }
        let projectRootValue = projectRoot(from: session.project)
        if !projectRootValue.isEmpty { return projectRootValue }
        let project = session.project.trimmingCharacters(in: .whitespacesAndNewlines)
        return project.isEmpty ? session.id : project
    }

    private func operationProjectKey(_ record: OperationRecord) -> String {
        let targetRoot = projectRoot(from: record.targetPath)
        if !targetRoot.isEmpty { return targetRoot }
        let detailRoot = projectRoot(from: record.detail)
        if !detailRoot.isEmpty { return detailRoot }
        return "\(localizer.agentCol): \(record.agentName)"
    }

    private func projectRoot(from rawText: String) -> String {
        guard let candidate = firstPathCandidate(in: rawText) else { return "" }
        let expanded = NSString(string: candidate).expandingTildeInPath
        let lower = expanded.lowercased()
        if lower.contains("/library/") || lower.contains("/.codex/sessions/") || lower.contains("/.trash/") {
            return ""
        }
        let components = URL(fileURLWithPath: expanded).pathComponents
        let anchors = ["Downloads", "Documents", "Desktop", "Developer", "Projects", "Code", "Workspace", "Work"]
        if let index = components.firstIndex(where: { anchors.contains($0) }),
           components.count > index + 1 {
            return NSString.path(withComponents: Array(components.prefix(index + 2)))
        }
        if URL(fileURLWithPath: expanded).pathExtension.isEmpty {
            return expanded
        }
        return URL(fileURLWithPath: expanded).deletingLastPathComponent().path
    }

    private func firstPathCandidate(in text: String) -> String? {
        let ns = text as NSString
        let markers = ["/Users/", "/Volumes/", "~/"]
        let delimiters = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'，,;；)］]}>"))
        for marker in markers {
            let range = ns.range(of: marker)
            guard range.location != NSNotFound else { continue }
            var end = range.location
            while end < ns.length {
                let scalarValue = ns.character(at: end)
                if let scalar = UnicodeScalar(scalarValue), delimiters.contains(scalar) {
                    break
                }
                end += 1
            }
            guard end > range.location else { continue }
            return ns.substring(with: NSRange(location: range.location, length: end - range.location))
        }
        return nil
    }

    private func projectTitle(for sessions: [SessionState], fallback: String) -> String {
        if let title = sessions.compactMap(\.sessionTitle).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return shortText(title, limit: 42)
        }
        if let project = sessions.map(\.project).first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            return projectDisplayName(for: project, fallback: fallback)
        }
        return projectDisplayName(for: fallback, fallback: fallback)
    }

    private func projectDisplayName(for path: String, fallback: String) -> String {
        if path.hasPrefix(localizer.agentCol + ":") { return path }
        let expanded = NSString(string: path).expandingTildeInPath
        let last = URL(fileURLWithPath: expanded).lastPathComponent
        return last.isEmpty ? fallback : shortText(last, limit: 42)
    }

    private func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed.lowercased()) else { continue }
            seen.insert(trimmed.lowercased())
            result.append(trimmed)
        }
        return result
    }

    private func shortText(_ text: String, limit: Int) -> String {
        let normalized = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.count > limit else { return normalized }
        return String(normalized.prefix(limit - 1)) + "…"
    }

    private func lanePriority(_ lane: MonitorProjectLane) -> Int {
        switch lane {
        case .blocked: return 0
        case .live: return 1
        case .scheduled: return 2
        case .completed: return 3
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "eye.fill",
                title: localizer.agentMonitorTitle,
                subtitle: localizer.agentMonitorSubtitle,
                color: Theme.Colors.accent
            ) {
                HStack(spacing: 8) {
                    Button { refreshAgentMonitor(forceHeavy: true) } label: {
                        Label(localizer.refresh, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Picker(localizer.autoRefresh, selection: $autoRefreshSeconds) {
                        Text(localizer.off).tag(0)
                        Text("5s").tag(5)
                        Text("10s").tag(10)
                        Text("30s").tag(30)
                    }
                    .labelsHidden()
                    .frame(width: 86)

                    Button { service.ensureAgentGuardDataPipeline() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: monitor.isMonitoring ? "record.circle.fill" : "record.circle")
                            Text(monitor.isMonitoring ? localizer.monitoring : localizer.startMonitoring)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(monitor.isMonitoring ? .green : .blue)
                    .disabled(monitor.isMonitoring)

                    Button { service.clearOperationRecords() } label: {
                        HStack(spacing: 3) { Image(systemName: "trash"); Text(localizer.clear) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.sm)],
                alignment: .leading,
                spacing: Theme.Spacing.sm
            ) {
                StatCardView(
                    icon: "rectangle.3.group.fill",
                    iconColor: Theme.Colors.info,
                    title: localizer.t("项目", en: "Projects", zhHant: "專案", ja: "プロジェクト", ko: "프로젝트", mt: "Projects"),
                    value: "\(projectSnapshots.count)",
                    subtitle: localizer.t("看板", en: "board", zhHant: "看板", ja: "ボード", ko: "보드", mt: "board")
                )
                StatCardView(
                    icon: "dot.radiowaves.left.and.right",
                    iconColor: Theme.Colors.success,
                    title: localizer.t("实时项目", en: "Live", zhHant: "即時專案", ja: "ライブ", ko: "실시간", mt: "Live"),
                    value: "\(liveProjectCount)",
                    subtitle: localizer.t("正在推进", en: "in progress", zhHant: "正在推進", ja: "進行中", ko: "진행 중", mt: "in progress")
                )
                StatCardView(
                    icon: "calendar.badge.clock",
                    iconColor: Theme.Colors.teal,
                    title: localizer.t("定时项目", en: "Scheduled", zhHant: "排程專案", ja: "予定", ko: "예약", mt: "Scheduled"),
                    value: "\(scheduledProjectCount)",
                    subtitle: localizer.t("等待触发", en: "queued", zhHant: "等待觸發", ja: "待機中", ko: "대기 중", mt: "queued")
                )
                StatCardView(
                    icon: "exclamationmark.triangle.fill",
                    iconColor: blockedProjectCount > 0 ? Theme.Colors.warning : Theme.Colors.success,
                    title: localizer.t("阻塞事项", en: "Blockers", zhHant: "阻塞事項", ja: "ブロッカー", ko: "차단 항목", mt: "Blockers"),
                    value: "\(blockedProjectCount)",
                    subtitle: localizer.t("需要处理", en: "need attention", zhHant: "需要處理", ja: "要対応", ko: "처리 필요", mt: "need attention")
                )
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.sm)
            .padding(.bottom, 0)

            if monitor.needsReauthorization {
                agentMonitorAuthorizationBanner
            }

            if monitor.isMonitoring {
                HStack(spacing: Theme.Spacing.sm) {
                    Circle().fill(Theme.Colors.success).frame(width: 6, height: 6)
                    Text(localizer.monitoring).font(Theme.Font.caption).foregroundColor(Theme.Colors.success)
                    Text("·").foregroundColor(Theme.Colors.textTertiary)
                    Text("\(allOperationRecords.count) \(localizer.records)").font(Theme.Font.caption).foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                    if monitor.aiSelfLearningEnabled {
                        PillBadge(text: localizer.aiLearning, color: Theme.Colors.purple)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.xs + 1)
                .background(Theme.Colors.success.opacity(0.05))
            }

            HStack(spacing: Theme.Spacing.lg) {
                modeSelector

                Spacer()

                if viewMode == 2 {
                    if !sessionScanner.opRecords.isEmpty {
                        Button {
                            sessionScanner.opRecords = []
                            selectedAgentForAudit = nil
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "xmark.circle").font(.system(size: 10))
                                Text(localizer.clearResults).font(Theme.Font.caption)
                            }
                            .foregroundColor(Theme.Colors.textSecondary)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.sm - 2)
            .background(Theme.Colors.sidebarBg.opacity(0.3))

            Divider()

            switch viewMode {
            case 0:
                projectBoardView
            case 1:
                liveView
            case 2:
                targetedView
            default:
                ScrollView {
                    AgentUsageInsightsView(mode: .projectMonitor)
                        .environmentObject(localizer)
                }
                .background(Theme.Colors.sidebarBg.opacity(0.24))
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            usageInsightsService.startScheduling()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                service.ensureAgentGuardDataPipeline()
                refreshAgentMonitor(forceHeavy: true)
            }
            if monitor.autoCurationInterval > 0 { service.startAutoCuration() }
        }
        .onChange(of: service.operationRecords.count) { _ in
            rebuildProjectSnapshotCache()
        }
        .onChange(of: monitor.records.count) { _ in
            rebuildProjectSnapshotCache()
        }
        .onChange(of: sessionsViewModel.sessions.count) { _ in
            rebuildProjectSnapshotCache()
        }
        .onChange(of: usageInsightsService.snapshot.generatedAt) { _ in
            rebuildProjectSnapshotCache(force: true)
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { now in
            guard viewMode != 2, autoRefreshSeconds > 0 else { return }
            guard now.timeIntervalSince(lastAutoRefresh) >= Double(autoRefreshSeconds) else { return }
            lastAutoRefresh = now
            refreshAgentMonitor()
        }
    }

    private func refreshAgentMonitor(forceHeavy: Bool = false) {
        let now = Date()
        let shouldHeavyRefresh = forceHeavy || now.timeIntervalSince(lastHeavyRefresh) >= Self.heavyRefreshInterval
        if shouldHeavyRefresh {
            service.refreshOperationRecordsSnapshot()
            service.importKnownAgentHistory()
            monitor.loadCurated()
            lastHeavyRefresh = now
        }
        automationProjectSnapshots = readAutomationProjectSnapshots()
        refreshCoreSessionsIfNeeded(force: forceHeavy, now: now)
        rebuildProjectSnapshotCache(force: forceHeavy || shouldHeavyRefresh)
    }

    private func refreshCoreSessionsIfNeeded(force: Bool, now: Date) {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect,
              !coreRefreshInFlight,
              force || now.timeIntervalSince(lastCoreRefresh) >= Self.coreRefreshInterval else {
            return
        }
        coreRefreshInFlight = true
        lastCoreRefresh = now

        Task { @MainActor in
            let snapshots = await TraceFenceAgentCoreClient.shared.sessionSnapshots()
            if !snapshots.isEmpty || coreSessionSnapshots.isEmpty {
                coreSessionSnapshots = snapshots
            }
            coreRefreshInFlight = false
            rebuildProjectSnapshotCache(force: true)
#if DEBUG
            if !snapshots.isEmpty {
                print("[TraceFence] Agent Monitor loaded \(snapshots.count) Core sessions; projects=\(cachedProjectSnapshots.count)")
            }
#endif
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 0) {
            modeButton(title: localizer.t("项目看板", en: "Project Board", zhHant: "專案看板", ja: "プロジェクトボード", ko: "프로젝트 보드", mt: "Project Board"), mode: 0)
            modeButton(title: localizer.t("实时明细", en: "Live Details", zhHant: "即時明細", ja: "ライブ詳細", ko: "실시간 상세", mt: "Live Details"), mode: 1)
            modeButton(title: localizer.audit, mode: 2)
            modeButton(title: localizer.t("项目用量", en: "Project Usage", zhHant: "專案用量", ja: "プロジェクト使用量", ko: "프로젝트 사용량", mt: "Project Usage"), mode: 3)
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(Theme.Colors.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func modeButton(title: String, mode: Int) -> some View {
        Button {
            withAnimation(.spring(duration: 0.3)) { viewMode = mode }
        } label: {
            Text(title)
                .font(Theme.Font.captionMedium)
                .foregroundColor(viewMode == mode ? .white : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm - 2)
                .background {
                    if viewMode == mode {
                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                            .fill(Theme.Colors.accent)
                            .matchedGeometryEffect(id: "segment", in: segmentNS)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var agentMonitorAuthorizationBanner: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Colors.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.permissionExpired)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(localizer.selectMonitorDirs)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                monitor.requestAccessForStalePaths()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    service.importKnownAgentHistory()
                }
            } label: {
                Label(localizer.reauthorize, systemImage: "lock.open")
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs + 1)
                    .background(Theme.Colors.warning)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.warning.opacity(0.08))
    }

    private var projectBoardView: some View {
        let visibleProjects = filteredProjectSnapshots
        let activeProject = selectedProject
        let activeProjectId = activeProject?.id

        return VStack(spacing: 0) {
            if visibleProjects.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(Theme.Colors.info.opacity(0.78))
                    Text(localizer.t("暂无可展示项目", en: "No projects to show", zhHant: "暫無可展示專案", ja: "表示できるプロジェクトはありません", ko: "표시할 프로젝트가 없습니다", mt: "No projects to show"))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t("接入 Agent Hook 或授权 Agent 数据目录后，这里会按项目展示实时进度、定时任务和阻塞事项。", en: "Connect agent hooks or authorize agent data folders to see live progress, scheduled work, and blockers by project.", zhHant: "接入 Agent Hook 或授權 Agent 資料目錄後，這裡會按專案展示即時進度、排程任務和阻塞事項。", ja: "Agent Hookを接続するかデータフォルダを許可すると、プロジェクト別の進捗、予定タスク、ブロッカーが表示されます。", ko: "Agent Hook을 연결하거나 데이터 폴더를 승인하면 프로젝트별 실시간 진행률, 예약 작업, 차단 항목이 표시됩니다.", mt: "Connect agent hooks or authorize agent data folders to see live progress, scheduled work, and blockers by project."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 560)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            ForEach(MonitorProjectLane.allCases, id: \.self) { lane in
                                let laneProjects = visibleProjects.filter { $0.lane == lane }
                                projectLaneView(lane: lane, projects: laneProjects, activeProjectId: activeProjectId)
                            }
                        }

                        projectDetailPanel(activeProject)
                            .frame(maxWidth: .infinity)
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
        }
        .frame(minHeight: 260)
    }

    private func projectLaneView(
        lane: MonitorProjectLane,
        projects: [MonitorProjectSnapshot],
        activeProjectId: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: lane.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(lane.color)
                    .frame(width: 26, height: 26)
                    .background(lane.color.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                VStack(alignment: .leading, spacing: 2) {
                    Text(lane.title(localizer))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(laneSubtitle(lane, count: projects.count))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Text("\(projects.count)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(lane.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(lane.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
            .padding(.horizontal, Theme.Spacing.sm)

            if projects.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.Colors.textTertiary.opacity(0.7))
                    Text(localizer.t("暂无项目", en: "No projects", zhHant: "暫無專案", ja: "プロジェクトなし", ko: "프로젝트 없음", mt: "No projects"))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 118)
                .background(Theme.Colors.cardBg.opacity(0.55))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 238, maximum: 340), spacing: Theme.Spacing.md, alignment: .top)],
                    alignment: .leading,
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(projects) { project in
                        projectCard(project, activeProjectId: activeProjectId)
                    }
                }
            }
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.Colors.elevatedCardBg.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        )
    }

    private func projectCard(_ project: MonitorProjectSnapshot, activeProjectId: String?) -> some View {
        let usage = usageForProject(project)
        return Button {
            selectedProjectId = project.id
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                    Image(systemName: project.lane.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(project.lane.color)
                        .frame(width: 30, height: 30)
                        .background(project.lane.color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(project.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(2)
                            .help(project.title)
                        Text(project.path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(project.path)
                    }

                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(localizer.t("进度", en: "Progress", zhHant: "進度", ja: "進捗", ko: "진행률", mt: "Progress"))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Spacer()
                        Text("\(Int((project.progress * 100).rounded()))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(project.lane.color)
                    }
                    ProgressView(value: min(max(project.progress, 0), 1))
                        .progressViewStyle(.linear)
                        .tint(project.lane.color)
                }

                if let blocker = project.blocker, !blocker.isEmpty {
                    projectCallout(icon: "exclamationmark.triangle.fill", text: blocker, color: Theme.Colors.warning, lineLimit: 2)
                } else if let scheduleHint = project.scheduledHint, !scheduleHint.isEmpty {
                    projectCallout(icon: "clock", text: scheduleHint, color: Theme.Colors.info, lineLimit: 1)
                }

                HStack(spacing: 5) {
                    ForEach(Array(project.agents.prefix(3)), id: \.self) { agent in
                        projectTinyBadge(text: agent, color: Theme.Colors.accent)
                    }
                    if project.agents.count > 3 {
                        projectTinyBadge(text: "+\(project.agents.count - 3)", color: Theme.Colors.textSecondary)
                    }
                }

                Text(project.summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .frame(minHeight: 30, alignment: .topLeading)

                HStack(spacing: Theme.Spacing.sm) {
                    projectMetricPill(icon: "terminal", value: "\(project.sessionCount)", color: Theme.Colors.info, help: localizer.t("会话", en: "Sessions", zhHant: "會話", ja: "セッション", ko: "세션", mt: "Sessions"))
                    projectMetricPill(icon: "doc.text.magnifyingglass", value: "\(project.recordCount)", color: Theme.Colors.purple, help: localizer.audit)
                    if project.totalTasks > 0 {
                        projectMetricPill(icon: "checklist", value: "\(project.completedTasks)/\(project.totalTasks)", color: Theme.Colors.success, help: localizer.t("任务", en: "Tasks", zhHant: "任務", ja: "タスク", ko: "작업", mt: "Tasks"))
                    }
                    if let usage, usage.allTimeTokens.total > 0 {
                        projectMetricPill(
                            icon: "sum",
                            value: compactUsageTokens(usage.allTimeTokens.total),
                            color: Theme.Colors.accent,
                            help: localizer.t("全部时间 Token", en: "All-time Tokens")
                        )
                    }
                    Spacer()
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
            .background(activeProjectId == project.id ? project.lane.color.opacity(0.11) : Theme.Colors.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(activeProjectId == project.id ? project.lane.color.opacity(0.38) : Color.primary.opacity(0.06), lineWidth: activeProjectId == project.id ? 1.2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func projectDetailPanel(_ project: MonitorProjectSnapshot?) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "rectangle.bottomthird.inset.filled")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                Text(localizer.t("项目详情", en: "Project Detail", zhHant: "專案詳情", ja: "プロジェクト詳細", ko: "프로젝트 상세", mt: "Project Detail"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.sidebarBg.opacity(0.32))

            Divider()

            if let project {
                let usage = usageForProject(project)
                let attributedTasks = usageTasks(for: project)
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                                Image(systemName: project.lane.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(project.lane.color)
                                    .frame(width: 34, height: 34)
                                    .background(project.lane.color.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(project.title)
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .lineLimit(3)
                                    Text(project.lane.title(localizer))
                                        .font(Theme.Font.captionMedium)
                                        .foregroundStyle(project.lane.color)
                                }
                                Spacer()
                            }

                            HStack(spacing: 6) {
                                Text(project.path)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(project.path)
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(project.path, forType: .string)
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 10))
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(Theme.Colors.accent)
                                .help(localizer.copyPath)
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(localizer.t("整体进度", en: "Overall Progress", zhHant: "整體進度", ja: "全体進捗", ko: "전체 진행률", mt: "Overall Progress"))
                                    .font(Theme.Font.captionMedium)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Spacer()
                                Text("\(Int((project.progress * 100).rounded()))%")
                                    .font(.system(size: 12, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(project.lane.color)
                            }
                            ProgressView(value: min(max(project.progress, 0), 1))
                                .progressViewStyle(.linear)
                                .tint(project.lane.color)
                        }

                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 132), spacing: Theme.Spacing.sm, alignment: .top)],
                            alignment: .leading,
                            spacing: Theme.Spacing.sm
                        ) {
                            projectDetailStat(title: localizer.t("会话", en: "Sessions", zhHant: "會話", ja: "セッション", ko: "세션", mt: "Sessions"), value: "\(project.sessionCount)", icon: "terminal", color: Theme.Colors.info)
                            projectDetailStat(title: localizer.audit, value: "\(project.recordCount)", icon: "doc.text.magnifyingglass", color: Theme.Colors.purple)
                            projectDetailStat(title: localizer.t("子 Agent", en: "Subagents", zhHant: "子 Agent", ja: "サブAgent", ko: "하위 Agent", mt: "Subagents"), value: "\(project.sessions.reduce(0) { $0 + $1.subagents.count })", icon: "person.2.fill", color: Theme.Colors.teal)
                            projectDetailStat(title: localizer.t("待处理", en: "Pending", zhHant: "待處理", ja: "保留中", ko: "대기", mt: "Pending"), value: "\(project.sessions.filter(hasPendingAttention).count)", icon: "hand.raised.fill", color: project.sessions.contains(where: hasPendingAttention) ? Theme.Colors.warning : Theme.Colors.success)
                            if let usage {
                                projectDetailStat(title: localizer.t("7 天 Token", en: "7-day Tokens"), value: compactUsageTokens(usage.sevenDayTokens.total), icon: "calendar.badge.clock", color: Theme.Colors.accent)
                                projectDetailStat(title: localizer.t("全部 Token", en: "All-time Tokens"), value: compactUsageTokens(usage.allTimeTokens.total), icon: "sum", color: Theme.Colors.purple)
                                projectDetailStat(title: localizer.t("API 等值", en: "API Equivalent"), value: usageCurrency(usage.estimatedAPIValueUSD), icon: "dollarsign.circle", color: Theme.Colors.warning)
                                projectDetailStat(title: localizer.t("用量会话", en: "Usage Sessions"), value: "\(usage.sessionCount)", icon: "chart.bar.doc.horizontal", color: Theme.Colors.teal)
                            }
                        }

                        if let blocker = project.blocker {
                            projectDetailSection(title: localizer.t("当前阻塞", en: "Current Blocker", zhHant: "目前阻塞", ja: "現在のブロッカー", ko: "현재 차단 항목", mt: "Current Blocker"), icon: "exclamationmark.triangle.fill", color: Theme.Colors.warning) {
                                Text(blocker)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .lineLimit(4)
                            }
                        }

                        if !project.activeTools.isEmpty {
                            projectDetailSection(title: localizer.t("当前工具", en: "Active Tools", zhHant: "目前工具", ja: "アクティブツール", ko: "활성 도구", mt: "Active Tools"), icon: "hammer.fill", color: Theme.Colors.info) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(project.activeTools.prefix(6), id: \.self) { tool in
                                        projectToolRow(tool)
                                    }
                                }
                            }
                        }

                        if !attributedTasks.isEmpty {
                            projectDetailSection(title: localizer.t("Agent 任务", en: "Agent Tasks"), icon: "checklist", color: Theme.Colors.accent) {
                                VStack(spacing: 7) {
                                    ForEach(attributedTasks.prefix(10)) { task in
                                        HStack(alignment: .top, spacing: 7) {
                                            Circle()
                                                .fill(usageTaskColor(task.category))
                                                .frame(width: 7, height: 7)
                                                .padding(.top, 5)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(task.title)
                                                    .font(Theme.Font.captionMedium)
                                                    .foregroundStyle(Theme.Colors.textPrimary)
                                                    .lineLimit(2)
                                                Text(usageTaskLabel(task.category) + " · " + task.scope.displayName)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(Theme.Colors.textTertiary)
                                            }
                                            Spacer(minLength: 4)
                                            if let tokens = task.tokens {
                                                Text(compactUsageTokens(tokens))
                                                    .font(.system(size: 9, design: .rounded))
                                                    .foregroundStyle(Theme.Colors.textSecondary)
                                                    .monospacedDigit()
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        projectDetailSection(title: localizer.t("项目摘要", en: "Project Summary", zhHant: "專案摘要", ja: "プロジェクト概要", ko: "프로젝트 요약", mt: "Project Summary"), icon: "text.alignleft", color: Theme.Colors.accent) {
                            Text(project.summary)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(6)
                        }

                        if !project.sessions.isEmpty {
                            projectDetailSection(title: localizer.t("会话流", en: "Session Flow", zhHant: "會話流", ja: "セッションフロー", ko: "세션 흐름", mt: "Session Flow"), icon: "point.3.connected.trianglepath.dotted", color: Theme.Colors.teal) {
                                VStack(spacing: 8) {
                                    ForEach(project.sessions.prefix(5)) { session in
                                        projectSessionRow(session)
                                    }
                                }
                            }
                        }

                        if !project.records.isEmpty {
                            projectDetailSection(title: localizer.t("最近审计", en: "Recent Audit", zhHant: "最近審計", ja: "最近の監査", ko: "최근 감사", mt: "Recent Audit"), icon: "clock.arrow.circlepath", color: Theme.Colors.purple) {
                                VStack(spacing: 8) {
                                    ForEach(project.records.prefix(6)) { operation in
                                        projectOperationRow(operation)
                                    }
                                }
                            }
                        }
                    }
                    .padding(Theme.Spacing.md)
            } else {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "rectangle.dashed")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(localizer.t("选择一个项目查看详情", en: "Select a project", zhHant: "選擇一個專案", ja: "プロジェクトを選択", ko: "프로젝트 선택", mt: "Select a project"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Theme.Colors.elevatedCardBg.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg)
                .stroke(Color.primary.opacity(0.055), lineWidth: 1)
        )
    }

    private func projectCallout(icon: String, text: String, color: Color, lineLimit: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
            Text(text)
                .font(Theme.Font.caption)
                .lineLimit(lineLimit)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func projectTinyBadge(text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func projectMetricPill(icon: String, value: String, color: Color, help: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.09))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .help(help)
    }

    private func compactUsageTokens(_ value: Int64) -> String {
        let amount = Double(max(0, value))
        switch amount {
        case 1_000_000_000...: return String(format: "%.2fB", amount / 1_000_000_000)
        case 1_000_000...: return String(format: "%.2fM", amount / 1_000_000)
        case 1_000...: return String(format: "%.1fK", amount / 1_000)
        default: return String(Int64(amount))
        }
    }

    private func usageCurrency(_ value: Double) -> String {
        if value >= 1_000 { return String(format: "$%.0f", value) }
        if value >= 100 { return String(format: "$%.1f", value) }
        return String(format: "$%.2f", value)
    }

    private func usageTaskLabel(_ category: AgentUsageTaskCategory) -> String {
        switch category {
        case .active: return localizer.t("进行中", en: "Active")
        case .pending: return localizer.t("待处理", en: "Pending")
        case .scheduled: return localizer.t("已计划", en: "Scheduled")
        case .done: return localizer.t("已完成", en: "Done")
        }
    }

    private func usageTaskColor(_ category: AgentUsageTaskCategory) -> Color {
        switch category {
        case .active: return Theme.Colors.accent
        case .pending: return Theme.Colors.warning
        case .scheduled: return Theme.Colors.info
        case .done: return Theme.Colors.success
        }
    }

    private func projectDetailStat(title: String, value: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22, height: 22)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func projectToolRow(_ name: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "hammer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.info)
                .frame(width: 20, height: 20)
                .background(Theme.Colors.info.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            Text(name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private func projectSessionRow(_ session: SessionState) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(phaseColor(session.phase))
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.agentType)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(phaseLabel(session.phase))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(phaseColor(session.phase))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(phaseColor(session.phase).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    Spacer(minLength: 0)
                }

                Text(session.lastToolName ?? session.description ?? session.cwd)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                Text(relativeTimeText(sessionLastActivity(session)))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private func projectOperationRow(_ operation: OperationRecord) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: operation.operationType.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(operationRecordColor(operation.operationType))
                .frame(width: 22, height: 22)
                .background(operationRecordColor(operation.operationType).opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(operation.operationType.localizedLabel(localizer))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("·")
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(operation.agentName)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }

                Text(operation.targetPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(operation.targetPath)

                Text(relativeTimeText(operation.timestamp))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    @ViewBuilder
    private func projectDetailSection<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }
            content()
        }
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func laneSubtitle(_ lane: MonitorProjectLane, count: Int) -> String {
        switch lane {
        case .live:
            return localizer.t("\(count) 个正在推进", en: "\(count) in progress", zhHant: "\(count) 個正在推進", ja: "\(count) 件進行中", ko: "\(count)개 진행 중", mt: "\(count) in progress")
        case .scheduled:
            return localizer.t("\(count) 个等待触发", en: "\(count) queued or scheduled", zhHant: "\(count) 個等待觸發", ja: "\(count) 件待機中", ko: "\(count)개 대기 중", mt: "\(count) queued or scheduled")
        case .blocked:
            return localizer.t("\(count) 个需要处理", en: "\(count) need attention", zhHant: "\(count) 個需要處理", ja: "\(count) 件要対応", ko: "\(count)개 처리 필요", mt: "\(count) need attention")
        case .completed:
            return localizer.t("\(count) 个可回看", en: "\(count) for review", zhHant: "\(count) 個可回看", ja: "\(count) 件確認可能", ko: "\(count)개 검토 가능", mt: "\(count) for review")
        }
    }

    private func phaseLabel(_ phase: SessionPhase) -> String {
        switch phase {
        case .ready: return localizer.agentCenterPhaseReady
        case .idle: return localizer.agentCenterPhaseIdle
        case .processing: return localizer.agentCenterPhaseRunning
        case .waitingApproval: return localizer.agentCenterPending
        case .waitingInput: return localizer.agentCenterQuestion
        case .compacting: return localizer.agentCenterPhaseCompacting
        case .done: return localizer.agentCenterPhaseDone
        case .error: return localizer.agentCenterPhaseError
        case .interrupted: return localizer.agentCenterPhaseInterrupted
        }
    }

    private func phaseColor(_ phase: SessionPhase) -> Color {
        switch phase {
        case .processing, .compacting: return Theme.Colors.info
        case .waitingApproval, .waitingInput: return Theme.Colors.warning
        case .done, .idle, .ready: return Theme.Colors.success
        case .error, .interrupted: return Theme.Colors.danger
        }
    }

    private func operationRecordColor(_ type: OperationRecord.OperationType) -> Color {
        switch type {
        case .create: return Theme.Colors.success
        case .modify: return Theme.Colors.info
        case .delete: return Theme.Colors.danger
        case .move: return Theme.Colors.warning
        case .rename: return Theme.Colors.purple
        case .read: return Theme.Colors.teal
        case .execute: return Theme.Colors.purple
        }
    }

    private func relativeTimeText(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var liveView: some View {
        let records = filteredRecords
        let visibleRecords = Array(records.prefix(1000))

        return VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                Picker(localizer.agentLabel, selection: $filterAgent) {
                    Text(localizer.allAgents).tag("")
                    ForEach(agentNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .frame(minWidth: 140)

                Picker(localizer.opTypeLabel, selection: $filterOpType) {
                    Text(localizer.allTypes).tag(nil as OperationRecord.OperationType?)
                    ForEach(OperationRecord.OperationType.allCases, id: \.self) { type in
                        Text(type.localizedLabel(localizer)).tag(type as OperationRecord.OperationType?)
                    }
                }
                .labelsHidden()
                .frame(minWidth: 140)

                Picker(localizer.timeRange, selection: $filterTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { Text($0.label(localizer)).tag($0) }
                }
                .labelsHidden()
                .frame(minWidth: 120)

                Spacer()

                Button {
                    let content = service.guardFeature.exportRecordsAsCSV(records: records)
                    _ = service.guardFeature.saveExport(content: content, filename: "agent-monitor-records.csv")
                } label: {
                    Label(localizer.exportCSV, systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(records.isEmpty)

                Button {
                    let content = service.guardFeature.exportRecordsAsJSON(records: records)
                    _ = service.guardFeature.saveExport(content: content, filename: "agent-monitor-records.json")
                } label: {
                    Label(localizer.exportJSON, systemImage: "doc.text")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(records.isEmpty)

                Text("\(visibleRecords.count)/\(records.count) \(localizer.recordsCount)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.sidebarBg.opacity(0.3))

            Divider()

            if visibleRecords.isEmpty {
                VStack(spacing: Theme.Spacing.lg) {
                    Spacer()
                    Image(systemName: "cpu")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(localizer.noRecords)
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.noRecordsHint)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if !monitor.isMonitoring {
                        Button(localizer.startMonitoring) { monitor.start() }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                    } else {
                        VStack(spacing: Theme.Spacing.xs) {
                            Text(localizer.monitoringStarted)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(localizer.monitoringHint)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                operationListHeader
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(visibleRecords) { record in
                            HStack(spacing: Theme.Spacing.md) {
                                Text(timeWithSeconds(record.timestamp))
                                    .font(Theme.Font.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .frame(width: 70, alignment: .leading)

                                HStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: "cpu")
                                        .font(Theme.Font.caption)
                                        .foregroundColor(record.agentName == "—" ? Theme.Colors.textTertiary : Theme.Colors.purple)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(record.agentName)
                                            .font(Theme.Font.captionMedium)
                                            .lineLimit(1)
                                            .help(record.agentName)
                                        if let pn = record.processName, !pn.isEmpty, pn != "path-match", pn != "dir-match" {
                                            Text(pn)
                                                .font(Theme.Font.caption)
                                                .foregroundStyle(Theme.Colors.textTertiary)
                                                .lineLimit(1)
                                                .help("\(localizer.processHelp)\(pn)")
                                        }
                                    }
                                }
                                .frame(width: 120, alignment: .leading)

                                PillBadge(
                                    text: record.operationType.localizedLabel(localizer),
                                    color: opTypeColor(record.operationType),
                                    size: .small
                                )
                                .frame(width: 70, alignment: .center)

                                HStack(spacing: Theme.Spacing.xs) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(record.targetPath)
                                            .font(Theme.Font.caption)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(record.targetPath)
                                        if let ti = record.toolInfo, !ti.isEmpty {
                                            Text(ti)
                                                .font(Theme.Font.caption)
                                                .foregroundStyle(Theme.Colors.warning.opacity(0.8))
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                                .help(ti)
                                        }
                                    }
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(record.targetPath, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(Theme.Colors.accent)
                                    .help(localizer.copyPath)
                                    if record.targetPath.hasPrefix("/") {
                                        Button {
                                            let url = URL(fileURLWithPath: record.targetPath)
                                            NSWorkspace.shared.activateFileViewerSelecting([url])
                                        } label: {
                                            Image(systemName: "folder")
                                                .font(.system(size: 10))
                                        }
                                        .buttonStyle(.plain)
                                        .foregroundColor(Theme.Colors.accent)
                                        .help(localizer.openInFinder)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Text(record.fileSize > 0 ? ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file) : "—")
                                    .font(Theme.Font.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.Colors.textTertiary)
                                    .frame(width: 60, alignment: .trailing)
                                    .help(record.fileSize > 0 ? ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file) : "—")
                            }
                            .cardStyle(padding: Theme.Spacing.md, cornerRadius: Theme.Radius.md)
                        }
                    }
                    .padding(Theme.Spacing.lg)
                }
            }
        }
        .frame(minHeight: 200)
    }

    private func compactCount(_ value: Int) -> String {
        AgentUsageTokenFormatter.string(Int64(value))
    }

    private func contextColor(_ progress: Double) -> Color {
        if progress >= 0.85 { return Theme.Colors.danger }
        if progress >= 0.65 { return Theme.Colors.warning }
        return Theme.Colors.success
    }

    private var operationListHeader: some View {
        HStack(spacing: Theme.Spacing.md) {
            Text(localizer.timeCol)
                .frame(width: 70, alignment: .center)
            Text(localizer.agentCol)
                .frame(width: 120, alignment: .center)
            Text(localizer.opCol)
                .frame(width: 70, alignment: .center)
            Text(localizer.pathCol)
                .frame(maxWidth: .infinity, alignment: .center)
            Text(localizer.fileSizeCol)
                .frame(width: 60, alignment: .center)
        }
        .font(Theme.Font.captionMedium)
        .foregroundStyle(Theme.Colors.textTertiary)
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.sidebarBg.opacity(0.35))
    }

    private var curatedView: some View {
        Group {
            if monitor.curatedRecords.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text(localizer.noCuratedData).font(.title3).fontWeight(.medium)
                    Text(localizer.noCuratedHint).font(.caption).foregroundColor(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(monitor.curatedRecords) {
                    TableColumn(localizer.timeCol) { record in
                        Text(timeWithSeconds(record.timestamp))
                            .font(.caption).monospacedDigit()
                    }.width(65)

                    TableColumn(localizer.agentCol) { record in
                        HStack(spacing: 4) {
                            Image(systemName: record.confidence >= 0.8 ? "checkmark.seal.fill" : record.confidence >= 0.5 ? "checkmark.circle" : "questionmark.circle")
                                .font(.caption2)
                                .foregroundColor(confidenceColor(record.confidence))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.agentName)
                                    .font(.caption).fontWeight(.medium).lineLimit(1)
                                Text(localizer.confidence + ": \(String(format: "%.0f", record.confidence * 100))%")
                                    .font(.system(size: 9)).foregroundColor(.secondary)
                            }
                        }
                    }.width(min: 100)

                    TableColumn(localizer.opCol) { record in
                        Text(record.operationType)
                            .font(.caption2).fontWeight(.medium)
                    }.width(60)

                    TableColumn(localizer.pathCol) { record in
                        HStack(spacing: 4) {
                            Text(record.targetPath)
                                .font(.caption2).lineLimit(1).truncationMode(.middle)
                                .help(record.targetPath)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(record.targetPath, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc").font(.system(size: 10))
                            }
                            .buttonStyle(.plain).foregroundColor(.accentColor)
                            .help(localizer.copyPath)
                            if record.targetPath.hasPrefix("/") {
                                Button {
                                    let url = URL(fileURLWithPath: record.targetPath)
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                } label: {
                                    Image(systemName: "folder").font(.system(size: 10))
                                }
                                .buttonStyle(.plain).foregroundColor(.accentColor)
                                .help(localizer.openInFinder)
                            }
                        }
                    }

                    TableColumn(localizer.fileSizeCol) { record in
                        if record.fileSize > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file))
                                .font(.caption2).monospacedDigit().foregroundColor(.secondary)
                        }
                    }.width(70)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .onAppear { sessionScanner.localizer = localizer }
    }

    @State private var selectedAgentName: String = ""
    @State private var customAgentName: String = ""
    @State private var customAgentPath: String = ""
    @State private var targetedChecked: Set<String> = []
    @StateObject private var sessionScanner = AgentSessionScanner.shared
    @AppStorage("customAgentSources") private var customAgentSourcesData: Data = Data()
    @State private var selectedAppToAdd: AppInfo?
    @State private var showAddAgentSheet: Bool = false

    private var customAgentSources: [CustomAgentSource] {
        get {
            guard let decoded = try? JSONDecoder().decode([CustomAgentSource].self, from: customAgentSourcesData) else { return [] }
            return decoded
        }
    }

    private func addCustomAgent() {
        let name = customAgentName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let dirs = sessionScanner.searchJSONLDirs(forAgentName: name, bundlePath: nil)
        var paths: [String]
        if !customAgentPath.isEmpty {
            paths = [customAgentPath]
        } else if !dirs.isEmpty {
            paths = dirs
        } else {
            let home = SandboxPaths.realHomeDirectory
            let lower = name.lowercased().replacingOccurrences(of: " ", with: "")
            paths = [home + "/.\(lower)", home + "/Library/Application Support/\(name)", home + "/.config/\(lower)"]
        }
        saveCustomAgentSource(CustomAgentSource(name: name, searchPaths: paths, addedAt: Date()))
        customAgentName = ""
        customAgentPath = ""
    }

    private func saveCustomAgentSource(_ source: CustomAgentSource) {
        var sources = customAgentSources
        if let idx = sources.firstIndex(where: { $0.name == source.name }) {
            sources[idx] = source
        } else {
            sources.append(source)
        }
        customAgentSourcesData = (try? JSONEncoder().encode(sources)) ?? Data()
        let home = SandboxPaths.realHomeDirectory
        let paths = source.searchPaths.map { $0.replacingOccurrences(of: "~", with: home) }
        let isVSCode = paths.contains { $0.contains("Library/Application Support") || $0.contains("globalStorage") }
        let ds = AgentDataSource(
            agentName: source.name,
            searchPaths: paths,
            filePattern: "*",
            isCustom: true,
            isVSCodeType: isVSCode,
            parser: { [sessionScanner] url, agentName in
                sessionScanner.parseAutoDetectedSource(url: url, agentName: agentName)
            }
        )
        sessionScanner.registerSource(ds)
        sessionScanner.scanAllAgents()
    }

    private func registerInstalledAgentSources() {
        let agentApps = service.installedApps.filter { $0.subCategory == "AI Agent" }
        for app in agentApps {
            let dirs = sessionScanner.searchJSONLDirs(forAgentName: app.displayName, bundlePath: app.appPath)
            var paths = dirs
            if paths.isEmpty {
                let home = SandboxPaths.realHomeDirectory
                let lowerName = app.name.lowercased().replacingOccurrences(of: " ", with: "")
                let lowerDisplay = app.displayName.lowercased().replacingOccurrences(of: " ", with: "")
                paths = [
                    app.appPath,
                    home + "/.\(lowerName)",
                    home + "/.\(lowerDisplay)",
                    home + "/Library/Application Support/\(app.displayName)",
                    home + "/Library/Application Support/\(app.name)",
                    home + "/.config/\(lowerName)",
                ]
            }
            let existingPaths = paths.filter { !$0.isEmpty }
            let isVSCode = existingPaths.contains { $0.contains("Library/Application Support") || $0.contains("globalStorage") }
            let ds = AgentDataSource(
                agentName: app.displayName,
                searchPaths: existingPaths,
                filePattern: "*",
                isCustom: true,
                isVSCodeType: isVSCode,
                parser: { [sessionScanner] url, agentName in
                    sessionScanner.parseAutoDetectedSource(url: url, agentName: agentName)
                }
            )
            sessionScanner.registerSource(ds)
        }
    }

    private func addAgentAndSearch(_ app: AppInfo) {
        let dirs = sessionScanner.searchJSONLDirs(forAgentName: app.displayName, bundlePath: app.appPath)
        var finalPaths: [String]
        if dirs.isEmpty {
            let home = SandboxPaths.realHomeDirectory
            let lower = app.name.lowercased().replacingOccurrences(of: " ", with: "")
            finalPaths = [
                home + "/.\(lower)",
                home + "/Library/Application Support/\(app.displayName)",
                home + "/.config/\(lower)",
            ]
            if let bp = app.appPath as String? {
                finalPaths.append(bp)
                if bp.hasSuffix(".app") {
                    finalPaths.append(bp.replacingOccurrences(of: ".app", with: ""))
                }
            }
        } else {
            finalPaths = dirs
        }
        saveCustomAgentSource(CustomAgentSource(name: app.displayName, searchPaths: finalPaths, addedAt: Date()))
    }

    private func removeCustomAgentSource(_ name: String) {
        var sources = customAgentSources
        sources.removeAll { $0.name == name }
        customAgentSourcesData = (try? JSONEncoder().encode(sources)) ?? Data()
        sessionScanner.removeDataSource(forAgentName: name)
        sessionScanner.scanAllAgents()
    }

    private var allMonitorableApps: [AppInfo] {
        service.installedApps
    }
    @State private var selectedAgentForAudit: String?
    @State private var auditFilterAgent: String?
    @State private var auditFilterTimeRange: TimeRange = .all
    @State private var auditFilterOpType: String = ""
    @State private var aiSummary: String = ""
    @State private var isGeneratingSummary: Bool = false

    private var auditFilteredRecords: [AgentOpRecord] {
        var result = sessionScanner.opRecords.filter { record in
            let hasTarget = !record.targetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasDetail = !record.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasOpType = !record.opType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return hasTarget || hasDetail || hasOpType
        }
        if let filter = auditFilterAgent {
            result = result.filter { $0.agentName == filter }
        }
        if !auditFilterOpType.isEmpty {
            result = result.filter { $0.opType == auditFilterOpType }
        }
        switch auditFilterTimeRange {
        case .today:
            let start = Calendar.current.startOfDay(for: Date())
            result = result.filter { $0.timestamp >= start }
        case .hour1:
            result = result.filter { Date().timeIntervalSince($0.timestamp) < 3600 }
        case .hour6:
            result = result.filter { Date().timeIntervalSince($0.timestamp) < 21600 }
        case .day1:
            result = result.filter { Date().timeIntervalSince($0.timestamp) < 86400 }
        case .day7:
            result = result.filter { Date().timeIntervalSince($0.timestamp) < 604800 }
        case .all:
            break
        }
        return result
    }

    private var auditStats: [String: Int] {
        var stats: [String: Int] = [:]
        for rec in auditFilteredRecords {
            stats[localizer.totalOps, default: 0] += 1
            stats[rec.opType, default: 0] += 1
        }
        return stats
    }

    private var auditFileStats: [String: Int] {
        var stats: [String: Int] = [:]
        for rec in auditFilteredRecords where !rec.targetPath.isEmpty {
            stats[rec.targetPath, default: 0] += 1
        }
        return stats.sorted { $0.value > $1.value }.prefix(20).reduce(into: [:]) { $0[$1.key] = $1.value }
    }

    private var targetedView: some View {
        VStack(spacing: 0) {
            if let sel = selectedAgentForAudit, !sessionScanner.opRecords.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            selectedAgentForAudit = nil
                            sessionScanner.opRecords = []
                            aiSummary = ""
                            auditFilterAgent = nil
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "chevron.left").font(.system(size: 9))
                                Text(localizer.back).font(Theme.Font.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.Colors.textSecondary)

                        Text("\(localizer.audit): \(sel)")
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.purple)
                        Text("·").foregroundColor(Theme.Colors.textTertiary)
                        Text("\(auditFilteredRecords.count) \(localizer.auditRecordCount)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.purple.opacity(0.06))

                    Divider()

                    VStack(spacing: 0) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: Theme.Spacing.sm) {
                                ForEach(Array(auditStats.sorted(by: { $0.key < $1.key })), id: \.key) { key, val in
                                    PillBadge(
                                        text: "\(key) \(val)",
                                        color: key == localizer.totalOps ? Theme.Colors.info : opTypeColor(key),
                                        size: .small
                                    )
                                }
                                Spacer()
                                if let filter = auditFilterAgent {
                                    HStack(spacing: Theme.Spacing.xs) {
                                        Text("\(localizer.filterColon)\(filter)")
                                            .font(Theme.Font.caption)
                                            .foregroundStyle(Theme.Colors.info)
                                        Button {
                                            auditFilterAgent = nil
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 9))
                                                .foregroundColor(Theme.Colors.textTertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.xl)
                            .padding(.vertical, Theme.Spacing.xs + 1)
                        }
                        .background(Theme.Colors.sidebarBg.opacity(0.3))

                        HStack(spacing: Theme.Spacing.md) {
                            Picker(localizer.timeRange, selection: $auditFilterTimeRange) {
                                ForEach(TimeRange.allCases, id: \.self) { t in
                                    Text(t.label(localizer)).tag(t)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 130)

                            let auditOpTypes = Array(Set(sessionScanner.opRecords.map(\.opType))).sorted()
                            Picker(localizer.opTypeLabel, selection: $auditFilterOpType) {
                                Text(localizer.allTypes).tag("")
                                ForEach(auditOpTypes, id: \.self) { t in
                                    Text(t).tag(t)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(minWidth: 130)

                            Text("\(localizer.total) \(auditFilteredRecords.count) \(localizer.recordsCount)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(.horizontal, Theme.Spacing.xl)
                        .padding(.vertical, Theme.Spacing.xs)

                        if !auditFileStats.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Text(localizer.highFreqFiles)
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                    ForEach(Array(auditFileStats.sorted(by: { $0.value > $1.value }).prefix(8)), id: \.key) { path, count in
                                        PillBadge(
                                            text: "\(URL(fileURLWithPath: path).lastPathComponent) ×\(count)",
                                            color: Theme.Colors.warning,
                                            size: .small
                                        )
                                    }
                                }
                                .padding(.horizontal, Theme.Spacing.xl)
                                .padding(.vertical, Theme.Spacing.xs - 1)
                            }
                        }

                        if !aiSummary.isEmpty {
                            CardView {
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    HStack(spacing: Theme.Spacing.xs) {
                                        Image(systemName: "wand.and.stars")
                                            .font(.system(size: 10))
                                            .foregroundColor(Theme.Colors.purple)
                                        Text(localizer.aiSummaryTitle)
                                            .font(Theme.Font.captionMedium)
                                            .foregroundStyle(Theme.Colors.purple)
                                        Spacer()
                                        Button {
                                            aiSummary = ""
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(Theme.Colors.textTertiary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    ScrollView {
                                        Text(aiSummary)
                                            .font(Theme.Font.caption)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(maxHeight: 200)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.xl)
                            .padding(.vertical, Theme.Spacing.sm)
                        }

                        Divider()
                    }

                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.sm) {
                            ForEach(auditFilteredRecords) { rec in
                                HStack(spacing: Theme.Spacing.md) {
                                    Text(timeStr(rec.timestamp))
                                        .font(Theme.Font.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .frame(width: 80, alignment: .leading)

                                    PillBadge(
                                        text: rec.opType,
                                        color: opTypeColor(rec.opType),
                                        size: .small
                                    )
                                    .frame(width: 70, alignment: .center)

                                    Text(rec.toolName)
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(width: 80, alignment: .leading)

                                    HStack(spacing: Theme.Spacing.xs) {
                                        Text(rec.targetPath)
                                            .font(Theme.Font.caption)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .help(rec.targetPath)
                                        Button {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(rec.targetPath, forType: .string)
                                        } label: {
                                            Image(systemName: "doc.on.doc")
                                                .font(.system(size: 9))
                                                .foregroundColor(Theme.Colors.accent)
                                        }
                                        .buttonStyle(.plain)
                                        .help(localizer.copyPath)
                                        if !rec.targetPath.isEmpty, rec.targetPath.hasPrefix("/") {
                                            Button {
                                                let url = URL(fileURLWithPath: rec.targetPath)
                                                NSWorkspace.shared.activateFileViewerSelecting([url])
                                            } label: {
                                                Image(systemName: "folder")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(Theme.Colors.accent)
                                            }
                                            .buttonStyle(.plain)
                                            .help(localizer.openInFinder)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                    Text(rec.projectDir)
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .frame(width: 100, alignment: .leading)

                                    Text(rec.detail)
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(width: 80, alignment: .leading)
                                }
                                .cardStyle(padding: Theme.Spacing.md, cornerRadius: Theme.Radius.md)
                            }
                        }
                        .padding(Theme.Spacing.lg)
                    }
                }
            } else if sessionScanner.isScanning {
                VStack(spacing: Theme.Spacing.lg) {
                    Spacer()
                    ProgressView().controlSize(.regular)
                    Text(selectedAgentForAudit == nil ? localizer.scanAgentSession : "\(localizer.parsingAgentOps) \(selectedAgentForAudit!) \(localizer.operationsRecord)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let sel = selectedAgentForAudit {
                VStack(spacing: Theme.Spacing.lg) {
                    HStack {
                        Button {
                            selectedAgentForAudit = nil
                            aiSummary = ""
                            auditFilterAgent = nil
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "chevron.left").font(.system(size: 9))
                                Text(localizer.back).font(Theme.Font.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(Theme.Colors.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.sm)

                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text("\(localizer.audit): \(sel)")
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.noOpRecordsLabel)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if !sessionScanner.scanError.isEmpty {
                        Text(sessionScanner.scanError)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.warning)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 560)
                    }
                    Button {
                        sessionScanner.scanAgentOps(agentName: sel)
                    } label: {
                        Label(localizer.scanRefresh, systemImage: "arrow.clockwise")
                            .font(Theme.Font.captionMedium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 13))
                            .foregroundColor(Theme.Colors.purple)
                        Text(localizer.agentOpAudit)
                            .font(Theme.Font.captionMedium)
                        Text("·").foregroundColor(Theme.Colors.textTertiary)
                        Text("\(sessionScanner.discoveredAgents.count) \(localizer.unitAgent)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        Button {
                            showAddAgentSheet = true
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "plus.circle.fill")
                                Text(localizer.addCustomAgent)
                            }
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.success)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs + 1)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .fill(Theme.Colors.success.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { sessionScanner.scanAllAgents(force: true) }
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "arrow.clockwise").font(.system(size: 9))
                                Text(localizer.scanRefresh).font(Theme.Font.caption)
                            }
                            .foregroundStyle(Theme.Gradients.accent)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs + 1)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .fill(Theme.Colors.accent.opacity(0.1))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.sidebarBg.opacity(0.3))

                    Divider()

                    if sessionScanner.discoveredAgents.isEmpty {
                        VStack(spacing: Theme.Spacing.lg) {
                            Spacer()
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 40))
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Text(localizer.scanToDiscover)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                            Text(localizer.supportedAgents)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: Theme.Spacing.sm) {
                                ForEach(sessionScanner.discoveredAgents) { agent in
                                    HStack(spacing: Theme.Spacing.md) {
                                        Image(systemName: agentIconName(agent.name))
                                            .font(.system(size: 16))
                                            .foregroundColor(agentColorName(agent.name))
                                            .frame(width: 36, height: 36)
                                            .background(agentColorName(agent.name).opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack(spacing: Theme.Spacing.xs) {
                                                Text(agent.name)
                                                    .font(Theme.Font.bodyMedium)
                                                if customAgentSources.contains(where: { $0.name == agent.name }) {
                                                    PillBadge(text: localizer.customBadge, color: Theme.Colors.success, size: .small)
                                                }
                                            }
                                            HStack(spacing: Theme.Spacing.sm) {
                                                Text("\(agent.sessionCount) \(localizer.unitSession)")
                                                    .font(Theme.Font.caption)
                                                    .foregroundStyle(Theme.Colors.textSecondary)
                                                if let date = agent.latestActivity {
                                                    Text("\(localizer.recentLabel): \(timeStr(date))")
                                                        .font(Theme.Font.caption)
                                                        .foregroundStyle(Theme.Colors.textSecondary)
                                                }
                                                if !agent.projectDirs.isEmpty {
                                                    Text(agent.projectDirs.first ?? "")
                                                        .font(Theme.Font.caption)
                                                        .foregroundStyle(Theme.Colors.textTertiary)
                                                        .lineLimit(1)
                                                }
                                            }
                                        }

                                        Spacer()

                                        if customAgentSources.contains(where: { $0.name == agent.name }) {
                                            Button {
                                                removeCustomAgentSource(agent.name)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(Theme.Colors.textTertiary)
                                            }
                                            .buttonStyle(.plain)
                                            .help(localizer.removeCustomAgent)
                                        }

                                        Button {
                                            selectedAgentForAudit = agent.name
                                            auditFilterAgent = nil
                                            auditFilterTimeRange = .all
                                            auditFilterOpType = ""
                                            aiSummary = ""
                                            Task {
                                                sessionScanner.scanAgentOps(agentName: agent.name)
                                            }
                                        } label: {
                                            HStack(spacing: Theme.Spacing.xs) {
                                                Image(systemName: "magnifyingglass").font(.system(size: 9))
                                                Text(localizer.audit).font(Theme.Font.caption)
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, Theme.Spacing.md)
                                            .padding(.vertical, Theme.Spacing.xs + 1)
                                            .background(Theme.Gradients.accent)
                                            .clipShape(Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .cardStyle(padding: Theme.Spacing.md, cornerRadius: Theme.Radius.md)
                                }
                            }
                            .padding(Theme.Spacing.lg)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAddAgentSheet) {
            AddAgentSheetView(
                localizer: localizer,
                apps: allMonitorableApps.filter { $0.appType == .app },
                deps: allMonitorableApps.filter { $0.appType == .dependency },
                others: allMonitorableApps.filter { $0.appType == .other },
                existingNames: Set(sessionScanner.discoveredAgents.map(\.name)),
                onAddApp: { app in
                    addAgentAndSearch(app)
                    showAddAgentSheet = false
                },
                onAddManual: { name, path in
                    customAgentName = name
                    customAgentPath = path
                    addCustomAgent()
                    if !name.isEmpty { showAddAgentSheet = false }
                }
            )
        }
        .onAppear {
            loadCustomAgentSources()
            Task {
                if service.installedApps.isEmpty {
                    await service.scanInstalledApps()
                }
                registerInstalledAgentSources()
                sessionScanner.scanAllAgents()
            }
        }
        .onChange(of: sessionScanner.opRecords.map(\.id)) { _ in
            service.ingestAgentSessionRecords(sessionScanner.opRecords)
        }
    }

    private func loadCustomAgentSources() {
        let sources = customAgentSources
        let home = SandboxPaths.realHomeDirectory
        for src in sources {
            let paths = src.searchPaths.map { $0.replacingOccurrences(of: "~", with: home) }
            let isVSCode = paths.contains { $0.contains("Library/Application Support") || $0.contains("globalStorage") }
            let ds = AgentDataSource(
                agentName: src.name,
                searchPaths: paths,
                filePattern: "*",
                isCustom: true,
                isVSCodeType: isVSCode,
                parser: { [sessionScanner] url, agentName in
                    sessionScanner.parseAutoDetectedSource(url: url, agentName: agentName)
                }
            )
            sessionScanner.registerSource(ds)
        }
    }

    private func generateAISummary() {
        let records = auditFilteredRecords
        guard !records.isEmpty else { return }

        isGeneratingSummary = true
        aiSummary = ""

        Task {
            let agentName = records.first?.agentName ?? localizer.unknownAgent
            var opSummary: [String: Int] = [:]
            var fileSummary: [String: Int] = [:]

            for rec in records {
                opSummary[rec.opType, default: 0] += 1
                if !rec.targetPath.isEmpty {
                    fileSummary[rec.targetPath, default: 0] += 1
                }
            }

            let topFiles = fileSummary.sorted { $0.value > $1.value }.prefix(10).map { "\($0.key) (\($0.value)\(localizer.timesUnit))" }.joined(separator: "\n")
            let opCounts = opSummary.map { "\($0.key): \($0.value)\(localizer.timesUnit)" }.joined(separator: ", ")
            try? await Task.sleep(nanoseconds: 250_000_000)
            aiSummary = localizer.t(
                "本地分析：Agent「\(agentName)」共有 \(records.count) 条审计记录。操作分布：\(opCounts)。高频文件：\n\(topFiles)\n建议：重点复核写入、删除和执行类操作，再批准大范围文件访问。",
                en: "Local analysis for \(agentName): \(records.count) audit records. Operation mix: \(opCounts). Main touched paths:\n\(topFiles)\nRecommendation: review write/delete operations before approving broad file access.",
                zhHant: "本地分析：Agent「\(agentName)」共有 \(records.count) 條審計記錄。操作分佈：\(opCounts)。高頻檔案：\n\(topFiles)\n建議：重點覆核寫入、刪除和執行類操作，再批准大範圍檔案存取。",
                ja: "ローカル分析：Agent「\(agentName)」には \(records.count) 件の監査記録があります。操作内訳：\(opCounts)。主な対象パス：\n\(topFiles)\n推奨：広範なファイルアクセスを承認する前に、書き込み・削除・実行操作を確認してください。",
                ko: "로컬 분석: Agent \"\(agentName)\"에 감사 기록 \(records.count)건이 있습니다. 작업 분포: \(opCounts). 주요 접근 경로:\n\(topFiles)\n권장: 광범위한 파일 접근을 승인하기 전에 쓰기, 삭제, 실행 작업을 중점적으로 검토하세요.",
                mt: "Local analysis for \(agentName): \(records.count) audit records. Operation mix: \(opCounts). Main touched paths:\n\(topFiles)\nRecommendation: review write/delete operations before approving broad file access."
            )
            isGeneratingSummary = false
        }
    }

    private func agentIconName(_ name: String) -> String {
        switch name {
        case "Claude Code": "brain.head.profile"
        case "Codex": "curlybraces"
        case "Trae": "laptopcomputer.and.arrow.down"
        case "Cursor": "cursorarrow"
        case "Windsurf": "wind"
        case "CodeBuddy": "person.wave.2"
        case "Aider": "terminal"
        case "Cline": "terminal"
        case "Gemini CLI": "sparkles"
        case "DeepSeek": "magnifyingglass"
        case "GLM": "text.bubble"
        case "Doubao": "cup.and.saucer.fill"
        case "Kimi": "moon.fill"
        case "Lingma": "bolt.fill"
        case "OpenClaw": "bird"
        case "Hermes": "ant.circle"
        case "CrewAI": "person.3.fill"
        case "AutoGen": "gearshape.2.fill"
        case "OpenHands": "hand.raised.fill"
        case "Dify": "app.fill"
        case "MetaGPT": "building.2.fill"
        case "CAMEL": "hare.fill"
        case "DeerFlow": "deer.fill"
        case "Huginn": "bird.fill"
        case "BrowserUse": "globe"
        case "AgentGPT": "robot"
        case "LobeHub": "hub.fill"
        case "LangGraph": "point.topleft.down.to.point.bottomright.curvepath"
        case "Swarm": "ant.fill"
        case "AgentScope": "scope"
        case "UI-TARS": "desktopcomputer"
        case "Roo Code": "pawprint.fill"
        case "Continue": "forward.fill"
        case "Cody": "dog.fill"
        case "Amazon Q": "q.square.fill"
        case "Augment": "arrow.up.forward.app.fill"
        case "Tabnine": "number.square.fill"
        default: "cpu"
        }
    }

    private func agentColorName(_ name: String) -> Color {
        switch name {
        case "Claude Code": .orange
        case "Codex": .green
        case "Trae": .purple
        case "Cursor": .blue
        case "Windsurf": .cyan
        case "CodeBuddy": .green
        case "Aider": .orange
        case "Cline": .pink
        case "Gemini CLI": .blue
        case "DeepSeek": .indigo
        case "GLM": .blue
        case "Doubao": .pink
        case "Kimi": .yellow
        case "Lingma": .orange
        case "OpenClaw": .red
        case "Hermes": .purple
        case "CrewAI": .blue
        case "AutoGen": .teal
        case "OpenHands": .green
        case "Dify": .indigo
        case "MetaGPT": .orange
        case "CAMEL": .yellow
        case "DeerFlow": .brown
        case "Huginn": .cyan
        case "BrowserUse": .blue
        case "AgentGPT": .purple
        case "LobeHub": .pink
        case "LangGraph": .green
        case "Swarm": .orange
        case "AgentScope": .blue
        case "UI-TARS": .indigo
        case "Roo Code": .brown
        case "Continue": .green
        case "Cody": .red
        case "Amazon Q": .orange
        case "Augment": .purple
        case "Tabnine": .blue
        default: .secondary
        }
    }

    private func opTypeColor(_ op: String) -> Color {
        switch op {
        case "Write", "写入": .red
        case "Edit", "编辑": .orange
        case "Read", "读取": .blue
        case "Delete", "删除": .red
        case "Execute", "执行命令": .purple
        case "Search", "搜索": .cyan
        default: .secondary
        }
    }

    private func timeStr(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "MM-dd HH:mm"
        return f.string(from: date)
    }

    private func confidenceColor(_ conf: Double) -> Color {
        if conf >= 0.8 { return .green }
        if conf >= 0.5 { return .orange }
        return .red
    }

    private func formattedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
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
}

struct AddAgentSheetView: View {
    let localizer: Localizer
    let apps: [AppInfo]
    let deps: [AppInfo]
    let others: [AppInfo]
    let existingNames: Set<String>
    let onAddApp: (AppInfo) -> Void
    let onAddManual: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: Int = 0
    @State private var searchText: String = ""
    @State private var selectedApp: AppInfo?
    @State private var manualName: String = ""
    @State private var manualPath: String = ""

    private func appList(_ items: [AppInfo]) -> some View {
        let filtered = searchText.isEmpty ? items : items.filter { app in
            localizer.localizedAppDisplayName(app.displayName).localizedCaseInsensitiveContains(searchText) ||
            localizer.localizedAppDescription(app.desc, name: localizer.localizedAppDisplayName(app.displayName)).localizedCaseInsensitiveContains(searchText) ||
            app.displayName.localizedCaseInsensitiveContains(searchText) ||
            app.name.localizedCaseInsensitiveContains(searchText)
        }
        return Group {
            if filtered.isEmpty {
                VStack(spacing: Theme.Spacing.sm) {
                    Spacer()
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(localizer.noMatchingApp)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Spacer()
                }
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(localizer.nameCol)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(localizer.projectCol)
                            .frame(width: 120, alignment: .leading)
                        Text(localizer.status)
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.Colors.sidebarBg.opacity(0.35))

                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.xs) {
                            ForEach(filtered) { app in
                                Button {
                                    selectedApp = app
                                } label: {
                                    HStack(spacing: Theme.Spacing.sm) {
                                        if let iconPath = app.iconPath, let img = NSImage(contentsOfFile: iconPath) {
                                            Image(nsImage: img)
                                                .resizable()
                                                .frame(width: 22, height: 22)
                                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                        } else {
                                            Image(systemName: "app.fill")
                                                .font(.system(size: 12))
                                                .foregroundColor(.secondary)
                                                .frame(width: 22, height: 22)
                                        }
                                        Text(localizer.localizedAppDisplayName(app.displayName))
                                            .font(Theme.Font.captionMedium)
                                            .foregroundStyle(Theme.Colors.textPrimary)
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(localizer.localizedSubCategory(app.subCategory))
                                            .font(Theme.Font.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .frame(width: 120, alignment: .leading)
                                        if existingNames.contains(app.displayName) {
                                            Text(localizer.alreadyAdded)
                                                .font(.system(size: 9, weight: .medium))
                                                .foregroundColor(.green)
                                                .frame(width: 80, alignment: .trailing)
                                        } else {
                                            Image(systemName: selectedApp?.id == app.id ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 12))
                                                .foregroundStyle(selectedApp?.id == app.id ? Theme.Colors.accent : Theme.Colors.textTertiary)
                                                .frame(width: 80, alignment: .trailing)
                                        }
                                    }
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .padding(.vertical, Theme.Spacing.sm)
                                    .background(selectedApp?.id == app.id ? Theme.Colors.info.opacity(0.08) : Theme.Colors.cardBg)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                            .stroke(selectedApp?.id == app.id ? Theme.Colors.info.opacity(0.25) : Color.primary.opacity(0.06), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Theme.Spacing.sm)
                    }
                }
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                Text(localizer.addCustomAgent)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.lg)

            HStack(spacing: 0) {
                ForEach(Array([(0, localizer.tabApps, "app"), (1, localizer.tabDeps, "puzzlepiece.extension"), (2, localizer.tabOther, "wrench.and.screwdriver"), (3, localizer.tabManual, "keyboard")].enumerated()), id: \.offset) { _, tab in
                    Button {
                        selectedTab = tab.0
                        selectedApp = nil
                        searchText = ""
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: tab.2)
                                .font(.system(size: 11))
                            Text(tab.1)
                                .font(Theme.Font.captionMedium)
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(selectedTab == tab.0 ? Theme.Colors.accent.opacity(0.12) : Color.clear)
                        .foregroundStyle(selectedTab == tab.0 ? Theme.Colors.accent : Theme.Colors.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.sm)

            Divider()

            if selectedTab == 3 {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    Text(localizer.customAgentName)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField(localizer.customAgentName, text: $manualName)
                        .textFieldStyle(.roundedBorder)

                    Text(localizer.sessionPathHint)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField(localizer.sessionPathHint, text: $manualPath)
                        .textFieldStyle(.roundedBorder)

                    Spacer()

                    Button {
                        onAddManual(manualName, manualPath)
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "plus.circle.fill")
                            Text(localizer.addAndScan)
                        }
                        .font(Theme.Font.body)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Gradients.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(manualName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(Theme.Spacing.lg)
            } else {
                TextField(localizer.searchingPlaceholder, text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.sm)

                let currentItems = selectedTab == 0 ? apps : selectedTab == 1 ? deps : others
                appList(currentItems)

                Divider()

                HStack {
                    if let app = selectedApp {
                        Text("\(localizer.selected): \(localizer.localizedAppDisplayName(app.displayName))")
                            .font(Theme.Font.caption)
                            .foregroundColor(.green)
                    } else {
                        Text(localizer.selectAppFromList)
                            .font(Theme.Font.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        if let app = selectedApp {
                            if existingNames.contains(app.displayName) { return }
                            onAddApp(app)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text(localizer.addAndScan)
                        }
                        .font(Theme.Font.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .tint(Theme.Colors.accent)
                    .disabled(selectedApp == nil || (selectedApp != nil && existingNames.contains(selectedApp!.displayName)))
                }
                .padding(Theme.Spacing.lg)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

struct TargetedOpsTable: View {
    let ops: [TargetedFileOp]
    @EnvironmentObject var localizer: Localizer

    var filteredOps: [TargetedFileOp] {
        ops.filter { op in
            let p = op.targetPath
            if p.contains("/.git/") || p.hasSuffix(".DS_Store") { return false }
            if p.contains("/node_modules/") || p.contains("/.vite/") { return false }
            if p.contains("/Library/Caches/") || p.contains("/private/var/") { return false }
            if p.hasSuffix(".nib") || p.hasSuffix(".plist") || p.hasSuffix(".strings") { return false }
            return true
        }
    }

    var body: some View {
        Table(filteredOps.prefix(500)) {
            TableColumn(localizer.timeCol) { op in
                Text(DisplayTime.withSeconds.string(from: op.timestamp)).font(.caption2).monospacedDigit()
            }.width(70)
            TableColumn(localizer.colProcess) { op in
                HStack(spacing: 3) {
                    Text(op.processComm).font(.caption).fontWeight(.medium).lineLimit(1)
                    Text("(\(String(op.processPid)))").font(.system(size: 9)).foregroundColor(.secondary)
                }
            }.width(min: 100)
            TableColumn(localizer.opCol) { op in
                HStack(spacing: 3) {
                    Image(systemName: targetedOpIcon(op.opType))
                        .font(.caption2)
                        .foregroundColor(targetedOpColor(op.opType))
                    Text(targetedOpLabel(op.opType))
                        .font(.caption2)
                }
            }.width(50)
            TableColumn(localizer.colPath) { op in
                HStack(spacing: 4) {
                    Text(op.targetPath).font(.caption2).lineLimit(1).truncationMode(.middle).help(op.targetPath)
                    Button { NSPasteboard.general.setString(op.targetPath, forType: .string) } label: {
                        Image(systemName: "doc.on.doc").font(.system(size: 9)).foregroundColor(.accentColor)
                    }.buttonStyle(.plain)
                    if op.targetPath.hasPrefix("/") {
                        Button {
                            let url = URL(fileURLWithPath: op.targetPath)
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Image(systemName: "folder").font(.system(size: 9)).foregroundColor(.accentColor)
                        }.buttonStyle(.plain)
                    }
                }
            }
            TableColumn(localizer.colSize) { op in
                if op.fileSize > 0 {
                    Text(ByteCountFormatter.string(fromByteCount: op.fileSize, countStyle: .file))
                        .font(.caption2).monospacedDigit().foregroundColor(.secondary)
                }
            }.width(70)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func targetedOpLabel(_ opType: String) -> String {
        switch opType {
        case "Modify", "修改": return localizer.modifyOps
        case "Open", "打开": return localizer.opOpen
        case "Delete", "删除": return localizer.deleteOps
        default: return opType
        }
    }

    private func targetedOpIcon(_ opType: String) -> String {
        switch opType {
        case "Modify", "修改": return "pencil"
        case "Open", "打开": return "plus.circle"
        default: return "xmark.circle"
        }
    }

    private func targetedOpColor(_ opType: String) -> Color {
        switch opType {
        case "Modify", "修改": return .blue
        case "Open", "打开": return .green
        default: return .red
        }
    }
}

// MARK: - Mac Cleaner Tab

struct MacCleanerTab: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var licenseService: DirectLicenseService
    @State private var selectedIds = Set<String>()
    @State private var filterCategory = ""
    @State private var filterApp = ""
    @State private var filterRisk = ""
    @State private var filterSource = ""
    @State private var showSettings = false
    @State private var settingsInitialTab: SettingsView.SettingsTab = .features
    @State private var showDeleteConfirm = false
    @State private var deleteTargetIds: [String] = []
    @State private var showCleanResult = false
    @State private var cleanedSize: Int64 = 0
    @State private var cleanedCount = 0
    @State private var cleanFailedCount = 0
    @State private var cleanFailureDetail = ""
    @State private var searchText = ""
    @State private var paywallMessage = ""

    var filteredItems: [ScanItem] {
        service.scanItems.filter { item in
            if !filterCategory.isEmpty && item.category != filterCategory { return false }
            if !filterApp.isEmpty && item.app != filterApp { return false }
            if !filterRisk.isEmpty && item.risk != filterRisk { return false }
            if !filterSource.isEmpty && item.sourceType.rawValue != filterSource { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                return item.name.lowercased().contains(q) || item.app.lowercased().contains(q) || item.path.lowercased().contains(q)
            }
            return true
        }
    }

    var categories: [String] { Array(Set(service.scanItems.map(\.category))).sorted() }
    var apps: [String] { Array(Set(service.scanItems.map(\.app))).sorted() }
    var totalCleanable: Int64 { cappedCleanupSize(filteredItems.reduce(0) { $0 + $1.size }) }
    var selectedSize: Int64 { cappedCleanupSize(filteredItems.filter { selectedIds.contains($0.id) }.reduce(0) { $0 + $1.size }) }

    private func cappedCleanupSize(_ size: Int64) -> Int64 {
        guard let used = service.diskInfo?.used, used > 0 else { return size }
        return min(size, used)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "arrow.down.doc.fill",
                title: localizer.macCleanerTitle,
                subtitle: localizer.macCleanerSubtitle,
                color: Theme.Colors.accent
            ) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button { runCoreAction { await service.scanLocal() } } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 14, weight: .semibold))
                            Text(localizer.localScan)
                                .font(Theme.Font.subheadlineMedium)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Gradients.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isScanning)
                    .opacity(service.isScanning ? 0.5 : 1)

                    Button { runProAction { await service.startEnhancedScan() } } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(localizer.enhancedScan)
                                .font(Theme.Font.subheadlineMedium)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Gradients.danger)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isEnhancedScanning)
                    .opacity(service.isEnhancedScanning ? 0.5 : 1)
                }
            }

            diskCard
            maintenanceOverviewBar
            Divider()

            if service.isAiScanning || service.isEnhancedScanning {
                HStack(spacing: Theme.Spacing.md) {
                    ProgressView().controlSize(.small)
                    Text(service.isEnhancedScanning ? localizer.enhancedScan + "..." : service.aiStatusMessage)
                        .font(Theme.Font.subheadline)
                        .foregroundStyle(Theme.Colors.purple)
                    Spacer()
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.purple.opacity(0.06))
                Divider()
            }
            if let error = service.errorMessage {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.Colors.warning)
                    Text(error)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(3)
                    Spacer()
                    Button { service.errorMessage = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.warning.opacity(0.06))
                Divider()
            }

            if service.isScanning { scanningOverlay }
            else if service.scanItems.isEmpty { welcomeCenter }
            else {
                HStack(spacing: Theme.Spacing.md) {
                    FilterSearchBar(placeholder: localizer.searchFiles, text: $searchText)
                        .frame(width: 180)

                    if !categories.isEmpty {
                        Picker(localizer.allCategories, selection: $filterCategory) {
                            Text(localizer.allCategories).tag("")
                            ForEach(categories, id: \.self) { Text(localizer.localizedSubCategory($0)).tag($0) }
                        }
                        .labelsHidden()
                    }
                    if !apps.isEmpty {
                        Picker(localizer.allApps, selection: $filterApp) {
                            Text(localizer.allApps).tag("")
                            ForEach(apps, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }

                    HStack(spacing: Theme.Spacing.xs) {
                        Text(localizer.riskLabel + ":")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        RiskPillFilterButton(label: localizer.riskSafe, color: Theme.Colors.success, isActive: filterRisk == "safe") { filterRisk = "safe" }
                        RiskPillFilterButton(label: localizer.riskCaution, color: Theme.Colors.warning, isActive: filterRisk == "caution") { filterRisk = "caution" }
                        RiskPillFilterButton(label: localizer.riskDangerous, color: Theme.Colors.danger, isActive: filterRisk == "dangerous") { filterRisk = "dangerous" }
                        if !filterRisk.isEmpty {
                            Button { filterRisk = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()
                    Button { requireProAction { smartClean() } } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "wand.and.stars")
                            Text(localizer.smartClean)
                        }
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Gradients.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.scanItems.filter { $0.risk == "safe" && !$0.ignored }.isEmpty)
                    .opacity(service.scanItems.filter { $0.risk == "safe" && !$0.ignored }.isEmpty ? 0.5 : 1)
                    Text("\(filteredItems.count) \(localizer.selected) · \(service.formatSize(totalCleanable))")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.cardBg.opacity(0.5))
                Divider()

                if !selectedIds.isEmpty {
                    HStack(spacing: Theme.Spacing.md) {
                        Button { selectAll() } label: {
                            Text(localizer.selectAll)
                                .font(Theme.Font.captionMedium)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button { selectSafe() } label: {
                            Text(localizer.safeOnly)
                                .font(Theme.Font.captionMedium)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button { selectedIds.removeAll() } label: {
                            Text(localizer.cancelSelection)
                                .font(Theme.Font.captionMedium)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Text("\(localizer.selected) \(selectedIds.count) \(localizer.selected) · \(service.formatSize(selectedSize))")
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.accent)

                        Spacer()

                        Button { ignoreSelected() } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "eye.slash")
                                Text(localizer.ignoreSelected)
                            }
                            .font(Theme.Font.captionMedium)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(selectedIds.isEmpty)

                        Button { requireProAction { confirmDeleteSelected() } } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "trash")
                                Text(localizer.deleteSelected)
                            }
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(Theme.Colors.danger)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                        .buttonStyle(.plain)
                        .controlSize(.small)
                        .disabled(selectedIds.isEmpty)
                        .opacity(selectedIds.isEmpty ? 0.5 : 1)
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.md)
                    .background(Theme.Colors.accent.opacity(0.06))
                    Divider()
                }

                if filteredItems.isEmpty { noResultView } else { resultList }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView(initialTab: settingsInitialTab)
                .id(settingsInitialTab)
                .environmentObject(service)
                .environmentObject(localizer)
                .environmentObject(licenseService)
        }
        .onAppear {
            licenseService.refreshTrialState()
        }
        .alert(localizer.t("需要 TraceFence 订阅", en: "TraceFence subscription required"), isPresented: Binding(
            get: { !paywallMessage.isEmpty },
            set: { if !$0 { paywallMessage = "" } }
        )) {
            if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                Button(localizer.t("管理订阅", en: "Manage Subscription")) {
                    settingsInitialTab = .license
                    showSettings = true
                    paywallMessage = ""
                }
            } else {
                Button(localizer.t("月付 $9.99", en: "Monthly $9.99")) {
                    licenseService.openPurchasePage(for: .monthly)
                    paywallMessage = ""
                }
                Button(localizer.t("年付 $79.99", en: "Annual $79.99")) {
                    licenseService.openPurchasePage(for: .annual)
                    paywallMessage = ""
                }
            }
            Button(localizer.cancel, role: .cancel) {
                paywallMessage = ""
            }
        } message: {
            Text(paywallMessage)
        }
        .alert(localizer.confirmDelete, isPresented: $showDeleteConfirm) {
            Button(localizer.cancelBtn, role: .cancel) {}
            Button(localizer.deleteBtn, role: .destructive) { performDelete() }
        } message: {
            let items = service.scanItems.filter { deleteTargetIds.contains($0.id) }
            Text("\(localizer.confirmDeleteMsg) \(deleteTargetIds.count) \(localizer.itemsLabel) (\(localizer.total) \(service.formatSize(items.reduce(Int64(0)) { $0 + $1.size })))？")
        }
        .sheet(isPresented: $showCleanResult) {
            VStack(spacing: Theme.Spacing.xl) {
                Image(systemName: cleanFailedCount > 0
                      ? (cleanedCount > 0 ? "exclamationmark.triangle.fill" : "xmark.circle.fill")
                      : "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(cleanFailedCount > 0
                                     ? (cleanedCount > 0 ? Theme.Colors.warning : Theme.Colors.danger)
                                     : Theme.Colors.success)

                Text(cleanFailedCount > 0 && cleanedCount == 0 ? localizer.cleanFailed : localizer.cleanComplete)
                    .font(Theme.Font.title2Bold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                CardView(padding: Theme.Spacing.xl, cornerRadius: Theme.Radius.lg) {
                    VStack(spacing: Theme.Spacing.md) {
                        Text(service.formatSize(cleanedSize))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(cleanedCount > 0 ? Theme.Colors.success : Theme.Colors.textSecondary)

                        Text("\(localizer.total) \(cleanedCount) \(localizer.itemsLabel)")
                            .font(Theme.Font.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)

                        if cleanFailedCount > 0 {
                            Text("\(localizer.cleanFailedCount) \(cleanFailedCount)")
                                .font(Theme.Font.subheadline)
                                .foregroundStyle(Theme.Colors.danger)
                            if !cleanFailureDetail.isEmpty {
                                Text(cleanFailureDetail)
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .multilineTextAlignment(.center)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: 240)
                }

                Button { showCleanResult = false } label: {
                    Text(localizer.ok)
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(.white)
                        .frame(width: 120)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Gradients.accent)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                }
                .buttonStyle(.plain)
            }
            .padding(Theme.Spacing.xxl)
            .frame(width: 360)
        }
    }

    private var diskCard: some View {
        Group {
            if let disk = service.diskInfo {
                HStack(spacing: Theme.Spacing.lg) {
                    VStack(spacing: Theme.Spacing.xs) {
                        ProgressRing(
                            progress: disk.usedPct / 100.0,
                            lineWidth: 10,
                            size: 80,
                            showLabel: true
                        )
                        Text(localizer.diskSpaceLabel)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(width: 100)

                    VStack(spacing: Theme.Spacing.xs) {
                        HStack(spacing: Theme.Spacing.sm) {
                            CompactStatItem(icon: "internaldrive", iconColor: Theme.Colors.info, title: localizer.totalCapacity, value: String(format: "%.0f GB", disk.totalGb))
                            CompactStatItem(icon: "arrow.down.circle.fill", iconColor: Theme.Colors.warning, title: localizer.usedLabel, value: String(format: "%.0f GB (%.1f%%)", disk.usedGb, disk.usedPct))
                        }
                        HStack(spacing: Theme.Spacing.sm) {
                            CompactStatItem(icon: "arrow.up.circle.fill", iconColor: disk.freeGb < 20 ? Theme.Colors.danger : Theme.Colors.success, title: localizer.available, value: String(format: "%.0f GB", disk.freeGb))
                            CompactStatItem(icon: "sparkles", iconColor: Theme.Colors.info, title: localizer.releasable, value: service.formatSize(totalCleanable))
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(.ultraThinMaterial)
                .background(Theme.Colors.elevatedCardBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Theme.Gradients.glassStroke, lineWidth: 1)
                )
                .shadow(color: Theme.Colors.info.opacity(0.06), radius: 18, y: 8)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xs)
            }
        }
    }

    private var maintenanceOverviewBar: some View {
        let projectItems = service.scanItems.filter { $0.id.hasPrefix("maintenance.project.") }
        let installerItems = service.scanItems.filter { $0.id.hasPrefix("maintenance.installer.") }

        return HStack(spacing: Theme.Spacing.sm) {
            Label(localizer.t("先预览再清理", en: "Review before cleanup"), systemImage: "checklist")
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.accent)

            Label(localizer.t("默认移入废纸篓", en: "Trash by default"), systemImage: "trash.slash")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            Spacer()

            if !projectItems.isEmpty {
                Button { filterCategory = projectItems.first?.category ?? "" } label: {
                    PillBadge(
                        text: "\(localizer.t("项目产物", en: "Project artifacts")) \(projectItems.count)",
                        color: Theme.Colors.purple,
                        size: .small
                    )
                }
                .buttonStyle(.plain)
            }

            if !installerItems.isEmpty {
                Button { filterCategory = installerItems.first?.category ?? "" } label: {
                    PillBadge(
                        text: "\(localizer.t("安装包", en: "Installers")) \(installerItems.count)",
                        color: Theme.Colors.warning,
                        size: .small
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xs + 1)
        .background(.ultraThinMaterial)
        .background(Theme.Colors.accent.opacity(0.045))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Colors.accent.opacity(0.12))
                .frame(height: 1)
        }
    }

    private var scanningOverlay: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ProgressView().controlSize(.large)
            Text(localizer.scanningStorage)
                .font(Theme.Font.title2)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(localizer.scanningStorageHint)
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeCenter: some View {
        VStack(spacing: Theme.Spacing.xxl) {
            Spacer()
            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "eye.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.accent.opacity(0.6))
                Text(localizer.appName)
                    .font(Theme.Font.title2Bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(localizer.smartCleanDesc)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            HStack(spacing: Theme.Spacing.xl) {
                ScanActionCard(
                    icon: "magnifyingglass",
                    title: localizer.localScan,
                    subtitle: localizer.localScanSubtitle,
                    iconColor: Theme.Colors.accent,
                    isDisabled: service.isScanning
                ) { runCoreAction { await service.scanLocal() } }
                ScanActionCard(
                    icon: "bolt.fill",
                    title: localizer.enhancedScan,
                    subtitle: localizer.enhancedScanSubtitle,
                    iconColor: Theme.Colors.warning,
                    isDisabled: service.isEnhancedScanning
                ) { runProAction { await service.startEnhancedScan() } }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }

    private var noResultView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40))
                .foregroundStyle(Theme.Colors.textTertiary.opacity(0.5))
            Text(localizer.noMatchesHint)
                .font(Theme.Font.headline)
                .foregroundStyle(Theme.Colors.textPrimary)
            HStack(spacing: Theme.Spacing.md) {
                if !filterRisk.isEmpty {
                    Button { filterRisk = "" } label: {
                        PillBadge(text: localizer.clearRiskFilter, color: Theme.Colors.danger, size: .medium)
                    }
                    .buttonStyle(.plain)
                }
                if !filterCategory.isEmpty {
                    Button { filterCategory = "" } label: {
                        PillBadge(text: localizer.clearCategoryFilter, color: Theme.Colors.info, size: .medium)
                    }
                    .buttonStyle(.plain)
                }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        PillBadge(text: localizer.clearSearch, color: Theme.Colors.textSecondary, size: .medium)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultList: some View {
        GeometryReader { proxy in
            let tableWidth = max(ResultListColumns.total, proxy.size.width - Theme.Spacing.xl * 2)

            ScrollView([.horizontal, .vertical]) {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: ResultListColumns.spacing) {
                        Color.clear.frame(width: ResultListColumns.selection)
                        Color.clear.frame(width: ResultListColumns.state)
                        Text(localizer.nameCol)
                            .frame(width: ResultListColumns.name, alignment: .center)
                        Text(localizer.sourceCol)
                            .frame(width: ResultListColumns.source, alignment: .center)
                        Text(localizer.projectCol)
                            .frame(width: ResultListColumns.project, alignment: .center)
                        Text(localizer.riskCol)
                            .frame(width: ResultListColumns.risk, alignment: .center)
                        Text(localizer.sizeCol)
                            .frame(width: ResultListColumns.size, alignment: .center)
                        Text(localizer.descriptionCol)
                            .frame(width: ResultListColumns.description, alignment: .center)
                        Text(localizer.actionCol)
                            .frame(width: ResultListColumns.actions, alignment: .center)
                    }
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, ResultListColumns.rowPadding)
                    .padding(.vertical, Theme.Spacing.xs)
                    .frame(width: tableWidth, alignment: .leading)
                    .background(Theme.Colors.sidebarBg.opacity(0.35))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                    ForEach(filteredItems) { item in
                        HStack(spacing: ResultListColumns.spacing) {
                            Toggle("", isOn: Binding(
                                get: { selectedIds.contains(item.id) },
                                set: { _ in
                                    if selectedIds.contains(item.id) {
                                        selectedIds.remove(item.id)
                                    } else {
                                        selectedIds.insert(item.id)
                                    }
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                            .frame(width: ResultListColumns.selection, alignment: .leading)

                            Group {
                                if item.ignored {
                                    Image(systemName: "eye.slash")
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(width: ResultListColumns.state, alignment: .center)

                            Text(item.name)
                                .font(Theme.Font.bodyMedium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: ResultListColumns.name, alignment: .leading)
                                .help(item.name)

                            PillBadge(
                                text: item.sourceType.localizedLabel(localizer),
                                color: item.sourceType == .ai ? Theme.Colors.purple : Theme.Colors.info,
                                size: .small
                            )
                            .frame(width: ResultListColumns.source, alignment: .center)

                            Text(item.app)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: ResultListColumns.project, alignment: .leading)
                                .help(item.app)

                            PillBadge(
                                text: item.riskLevel.localizedLabel(localizer),
                                color: riskColor(item.riskLevel),
                                size: .small
                            )
                            .frame(width: ResultListColumns.risk, alignment: .center)

                            Text(service.formatSize(item.size))
                                .font(Theme.Font.subheadlineMedium)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Colors.info)
                                .frame(width: ResultListColumns.size, alignment: .trailing)

                            Text(item.reason ?? item.riskDesc)
                                .font(Theme.Font.caption)
                                .foregroundStyle(item.sourceType == .ai ? Theme.Colors.purple : Theme.Colors.warning)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(width: ResultListColumns.description, alignment: .leading)
                                .help(item.reason ?? item.riskDesc)

                            HStack(spacing: Theme.Spacing.xs) {
                                Button { requireProAction { confirmDeleteSingle(item) } } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.Colors.danger)
                                        .padding(Theme.Spacing.xs)
                                        .background(Theme.Colors.danger.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                }
                                .buttonStyle(.plain)

                                Button { toggleIgnore(item) } label: {
                                    Image(systemName: item.ignored ? "eye" : "eye.slash")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                        .padding(Theme.Spacing.xs)
                                        .background(Theme.Colors.textSecondary.opacity(0.08))
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                }
                                .buttonStyle(.plain)
                            }
                            .frame(width: ResultListColumns.actions, alignment: .trailing)
                        }
                        .padding(.horizontal, ResultListColumns.rowPadding)
                        .padding(.vertical, Theme.Spacing.sm + 2)
                        .frame(width: tableWidth, alignment: .leading)
                        .cardStyle(padding: 0, cornerRadius: Theme.Radius.md)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selectedIds.contains(item.id) {
                                selectedIds.remove(item.id)
                            } else {
                                selectedIds.insert(item.id)
                            }
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.sm)
            }
        }
    }

    private func riskColor(_ level: ScanItem.RiskLevel) -> Color { switch level { case .safe: .green; case .caution: .orange; case .dangerous: .red } }
    private func selectAll() { selectedIds = Set(filteredItems.filter { !$0.ignored }.map(\.id)) }
    private func selectSafe() { selectedIds = Set(filteredItems.filter { $0.risk == "safe" && !$0.ignored }.map(\.id)) }
    private func smartClean() { let safe = service.scanItems.filter { $0.risk == "safe" && !$0.ignored }; guard !safe.isEmpty else { return }; deleteTargetIds = safe.map(\.id); showDeleteConfirm = true }
    private func performAiScan() async { await service.startAiScan() }
    private func confirmDeleteSelected() { deleteTargetIds = Array(selectedIds); showDeleteConfirm = true }
    private func confirmDeleteSingle(_ item: ScanItem) { deleteTargetIds = [item.id]; showDeleteConfirm = true }
    private func performDelete() {
        let requestedIDs = deleteTargetIds
        let targets = service.scanItems.filter { requestedIDs.contains($0.id) }
        Task {
            let result = await service.deleteItems(ids: requestedIDs)
            let entries = result.results ?? []
            let explicitlyFailedIDs = Set(entries.filter { $0.success != true }.compactMap { $0.id })
            let succeededIds = Set(entries.filter { $0.success == true }.compactMap { $0.id })
                .subtracting(explicitlyFailedIDs)
            let cleanedItems = targets.filter { succeededIds.contains($0.id) }
            service.removeScannedItems(ids: Array(succeededIds))
            selectedIds.subtract(succeededIds)
            deleteTargetIds = []
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            service.refreshDiskInfo()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            service.refreshDiskInfo()
            cleanedSize = cleanedItems.reduce(Int64(0)) { $0 + $1.size }
            cleanedCount = cleanedItems.count
            cleanFailedCount = max(0, requestedIDs.count - succeededIds.count)
            cleanFailureDetail = entries.first(where: { $0.success != true })?.message
                ?? (cleanFailedCount > 0 ? (service.errorMessage ?? "") : "")
            showCleanResult = true
        }
    }
    private func ignoreSelected() { service.ignoreItems(ids: Array(selectedIds)); selectedIds.removeAll() }
    private func toggleIgnore(_ item: ScanItem) { if item.ignored { service.unignoreItems(ids: [item.id]) } else { service.ignoreItems(ids: [item.id]) } }

    private func runCoreAction(_ action: @escaping () async -> Void) {
        licenseService.refreshTrialState()
        guard TraceFenceEntitlementPolicy.canUseCoreFeatures else {
            showTrialExpiredPrompt()
            return
        }
        Task { await action() }
    }

    private func runProAction(_ action: @escaping () async -> Void) {
        guard requireProAccess() else { return }
        Task { await action() }
    }

    private func requireProAction(_ action: () -> Void) {
        guard requireProAccess() else { return }
        action()
    }

    private func requireProAccess() -> Bool {
        licenseService.refreshTrialState()
        guard TraceFenceEntitlementPolicy.canUseProFeatures else {
            if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                paywallMessage = localizer.t(
                    "订阅 TraceFence Standard 后可使用增强扫描、智能清理和删除执行。",
                    en: "Subscribe to TraceFence Standard to use enhanced scans, smart cleanup, and deletion actions."
                )
            } else {
                paywallMessage = localizer.t(
                    "试用期可以扫描、浏览和预览清理结果；增强扫描、智能清理和删除执行需要激活 TraceFence Standard。",
                    en: "The trial can scan, browse, and preview cleanup results. Enhanced scans, smart cleanup, and deletion actions require TraceFence Standard."
                )
            }
            return false
        }
        return true
    }

    private func showTrialExpiredPrompt() {
        if TraceFenceDistributionPolicy.currentChannel.isAppStore {
            paywallMessage = localizer.t(
                "订阅 TraceFence Standard 后可继续扫描并使用高级操作。",
                en: "Subscribe to TraceFence Standard to continue scanning and using advanced actions."
            )
        } else {
            paywallMessage = localizer.t(
                "48 小时试用已结束。订阅并激活 TraceFence Standard 后可继续扫描和使用高级操作。",
                en: "The 48-hour trial has ended. Subscribe and activate TraceFence Standard to continue scanning and using advanced actions."
            )
        }
    }
}

// MARK: - App Manager Tab

struct AppRowCard: View {
    let app: AppInfo
    let filterType: AppInfo.AppType
    let isSelected: Bool
    let aiResult: String?
    let subCategoryColor: (String) -> Color
    let onToggle: () -> Void
    let onAction: (AppManagerTab.AppAction) -> Void
    let formatSize: (Int64) -> String
    let localizer: Localizer

    @State private var isHovered = false

    private var riskColor: Color {
        app.risk == "safe" ? Theme.Colors.success : app.risk == "dangerous" ? Theme.Colors.danger : Theme.Colors.warning
    }

    private var riskLabel: String {
        app.risk == "safe" ? localizer.safe : app.risk == "dangerous" ? localizer.dangerous : localizer.warning
    }

    private var displayName: String {
        localizer.localizedAppDisplayName(app.displayName)
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textTertiary)
            }
            .buttonStyle(.plain)

            if let iconPath = app.iconPath, let img = NSImage(contentsOfFile: iconPath) {
                Image(nsImage: img).resizable().frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            } else {
                Image(systemName: filterType == .app ? "app.fill" : filterType == .dependency ? "cube.box.fill" : "terminal.fill")
                    .font(.title3).foregroundStyle(Theme.Colors.textTertiary).frame(width: 36, height: 36)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(displayName)
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    if filterType != .app {
                        PillBadge(text: localizer.localizedSubCategory(app.subCategory), color: subCategoryColor(app.subCategory), size: .small)
                    }
                }
                Text(localizer.localizedAppDescription(app.desc, name: displayName))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            .frame(minWidth: 160, maxWidth: 220, alignment: .leading)

            Spacer()

            PillBadge(text: riskLabel, color: riskColor, size: .small)
                .frame(width: 60, alignment: .center)

            if let aiResult = aiResult {
                Text(aiResult)
                    .font(Theme.Font.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(
                        aiResult.hasPrefix("🤖") ? Theme.Colors.purple :
                        aiResult.hasPrefix("❌") ? Theme.Colors.danger :
                        aiResult.hasPrefix("⚠️") ? Theme.Colors.warning :
                        Theme.Colors.textSecondary
                    )
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
            } else {
                Text(localizer.localizedRiskDescription(app.riskDesc, name: displayName))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.warning)
                    .lineLimit(1)
                    .frame(maxWidth: 120, alignment: .leading)
            }

            Text(formatSize(app.totalSize))
                .font(Theme.Font.subheadlineMedium)
                .monospacedDigit()
                .foregroundStyle(Theme.Colors.info)
                .frame(width: 80, alignment: .trailing)

            Text(localizer.reviewOnly)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 156, alignment: .trailing)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(isSelected ? Theme.Colors.accent.opacity(0.06) : (isHovered ? Theme.Colors.cardHover : Theme.Colors.cardBg))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(isSelected ? Theme.Colors.accent.opacity(0.3) : Color.primary.opacity(0.06), lineWidth: isSelected ? 1.5 : 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .onHover { isHovered = $0 }
    }

    private func rowActionLabel(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(title)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(color.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Color.white.opacity(0.22), lineWidth: 0.5)
        )
    }
}

struct AppManagerTab: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    let filterType: AppInfo.AppType
    @State private var searchText = ""
    @State private var filterSubCategory = ""
    @State private var selectedAppIds = Set<String>()
    @State private var showActionConfirm = false
    @State private var pendingAction: AppAction = .reset
    @State private var pendingAppIds: [String] = []
    @State private var showActionResult = false
    @State private var actionResultMsg = ""

    enum AppAction: String, CaseIterable {
        case reset, basicUninstall, fullUninstall
        var icon: String { switch self { case .reset: "arrow.counterclockwise"; case .basicUninstall: "xmark.circle"; case .fullUninstall: "trash" } }
        var color: Color { switch self { case .reset: Theme.Colors.warning; case .basicUninstall: Theme.Colors.info; case .fullUninstall: Theme.Colors.danger } }
        var labelColor: Color { .white }
        var isDestructivePrimary: Bool { self == .fullUninstall }
        func label(_ localizer: Localizer) -> String { switch self {
        case .reset: return localizer.resetAction
        case .basicUninstall: return localizer.basicUninstall
        case .fullUninstall: return localizer.fullUninstall
        } }
        func desc(_ localizer: Localizer) -> String { switch self {
        case .reset: return localizer.resetDesc
        case .basicUninstall: return localizer.basicUninstallDesc
        case .fullUninstall: return localizer.fullUninstallDesc
        } }
    }

    var subCategories: [String] {
        let base = service.installedApps.filter { $0.appType == filterType }
        return Array(Set(base.map(\.subCategory))).sorted()
    }

    var filteredApps: [AppInfo] {
        var base = service.installedApps.filter { $0.appType == filterType }
        if !filterSubCategory.isEmpty {
            base = base.filter { $0.subCategory == filterSubCategory }
        }
        if searchText.isEmpty { return base }
        let q = searchText.lowercased()
        return base.filter {
            localizer.localizedAppDisplayName($0.displayName).lowercased().contains(q) ||
            localizer.localizedAppDescription($0.desc, name: localizer.localizedAppDisplayName($0.displayName)).lowercased().contains(q) ||
            localizer.localizedRiskDescription($0.riskDesc, name: localizer.localizedAppDisplayName($0.displayName)).lowercased().contains(q) ||
            $0.displayName.lowercased().contains(q) ||
            $0.name.lowercased().contains(q) ||
            $0.bundleId.lowercased().contains(q) ||
            $0.desc.lowercased().contains(q)
        }
    }

    var selectedApps: [AppInfo] { service.installedApps.filter { selectedAppIds.contains($0.id) } }
    var selectedTotalSize: Int64 { selectedApps.reduce(0) { $0 + $1.totalSize } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: filterType.tabIcon,
                title: filterType.localizedTabLabel(localizer),
                subtitle: filterType == .app ? localizer.appManagerSubtitle : filterType == .dependency ? localizer.dependencySubtitle : localizer.otherToolsSubtitle,
                color: filterType.tabColor
            ) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button { Task { await service.scanInstalledApps() } } label: {
                        topActionLabel(icon: "arrow.clockwise", title: localizer.refresh, color: Theme.Colors.info)
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isScanningApps)
                    .opacity(service.isScanningApps ? 0.5 : 1)
                }
            }

            DashboardGrid(columns: 4) {
                StatCardView(
                    icon: "app.badge",
                    iconColor: filterType.tabColor,
                    title: localizer.typeApp,
                    value: "\(filteredApps.count)",
                    subtitle: localizer.itemsLabel
                )
                StatCardView(
                    icon: "internaldrive",
                    iconColor: Theme.Colors.info,
                    title: localizer.sizeCol,
                    value: service.formatSize(filteredApps.reduce(Int64(0)) { $0 + $1.totalSize }),
                    subtitle: nil
                )
                StatCardView(
                    icon: "exclamationmark.triangle",
                    iconColor: Theme.Colors.danger,
                    title: localizer.warning,
                    value: "\(filteredApps.filter { $0.risk == "caution" || $0.risk == "dangerous" }.count)",
                    subtitle: nil
                )
                StatCardView(
                    icon: "checklist",
                    iconColor: Theme.Colors.info,
                    title: localizer.t("待复核", en: "Review First"),
                    value: "\(filteredApps.filter { $0.risk != "safe" }.count)",
                    subtitle: localizer.t("删除前预览", en: "Preview before removal")
                )
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.md)

            if subCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button { filterSubCategory = "" } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "square.grid.2x2")
                                    .font(Theme.Font.caption)
                                Text(localizer.all)
                                    .font(Theme.Font.captionMedium)
                                Text("\(service.installedApps.filter { $0.appType == filterType }.count)")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(filterSubCategory.isEmpty ? .white.opacity(0.8) : Theme.Colors.textTertiary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(filterSubCategory.isEmpty ? Color.white.opacity(0.2) : Theme.Colors.accent.opacity(0.1))
                                    .clipShape(Capsule())
                            }
                            .foregroundStyle(filterSubCategory.isEmpty ? .white : Theme.Colors.textPrimary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(filterSubCategory.isEmpty ? Theme.Colors.accent : Theme.Colors.cardBg)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(filterSubCategory.isEmpty ? Color.clear : Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                        }
                        .buttonStyle(.plain)

                        ForEach(subCategories, id: \.self) { cat in
                            let count = service.installedApps.filter { $0.appType == filterType && $0.subCategory == cat }.count
                            let catColor = subCategoryColor(cat)
                            Button { filterSubCategory = filterSubCategory == cat ? "" : cat } label: {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: subCategoryIconName(cat))
                                        .font(Theme.Font.caption)
                                    Text(localizer.localizedSubCategory(cat))
                                        .font(Theme.Font.captionMedium)
                                    Text("\(count)")
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(filterSubCategory == cat ? .white.opacity(0.8) : Theme.Colors.textTertiary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(filterSubCategory == cat ? Color.white.opacity(0.2) : catColor.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                .foregroundStyle(filterSubCategory == cat ? .white : Theme.Colors.textPrimary)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, 5)
                                .background(
                                    Capsule()
                                        .fill(filterSubCategory == cat ? catColor : Theme.Colors.cardBg)
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(filterSubCategory == cat ? Color.clear : catColor.opacity(0.3), lineWidth: 0.5)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                FilterSearchBar(placeholder: localizer.searchingApps, text: $searchText)
                    .frame(width: 220)

                Spacer()

                if !selectedAppIds.isEmpty {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.accent)
                        Text("\(localizer.selected) \(selectedAppIds.count) \(localizer.itemsLabel) · \(service.formatSize(selectedTotalSize))")
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }

                HStack(spacing: Theme.Spacing.xs) {
                    Button { selectedAppIds = Set(filteredApps.map(\.id)) } label: {
                        toolbarActionLabel(icon: "checkmark.circle", title: localizer.selectAllBtn, color: Theme.Colors.info, isPrimary: false)
                    }
                    .buttonStyle(.plain)
                    Button { selectedAppIds.removeAll() } label: {
                        toolbarActionLabel(icon: "xmark.circle", title: localizer.cancelBtn, color: Theme.Colors.textSecondary, isPrimary: false)
                    }
                    .buttonStyle(.plain)
                }

            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.sm)

            Divider()

            if service.isScanningApps {
                VStack(spacing: Theme.Spacing.lg) { ProgressView().controlSize(.large); Text(localizer.searching).foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                VStack(spacing: Theme.Spacing.lg) {
                    Spacer()
                    Image(systemName: filterType == .app ? "app.dashed" : filterType == .dependency ? "cube.box" : "terminal")
                        .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text("\(localizer.notFound)\(filterType.localizedLabel(localizer))").font(Theme.Font.title2).fontWeight(.medium)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        HStack(spacing: Theme.Spacing.md) {
                            Color.clear.frame(width: 16)
                            Text(localizer.nameCol)
                                .frame(minWidth: 196, maxWidth: 256, alignment: .leading)
                            Spacer()
                            Text(localizer.riskCol)
                                .frame(width: 60, alignment: .center)
                            Text(localizer.descriptionCol)
                                .frame(maxWidth: 120, alignment: .leading)
                            Text(localizer.sizeCol)
                                .frame(width: 80, alignment: .trailing)
                            Text(localizer.actionCol)
                                .frame(width: 156, alignment: .trailing)
                        }
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.sidebarBg.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                        ForEach(filteredApps) { app in
                            AppRowCard(
                                app: app,
                                filterType: filterType,
                                isSelected: selectedAppIds.contains(app.id),
                                aiResult: service.aiAnalysisMap[app.id],
                                subCategoryColor: subCategoryColor,
                                onToggle: {
                                    if selectedAppIds.contains(app.id) {
                                        selectedAppIds.remove(app.id)
                                    } else {
                                        selectedAppIds.insert(app.id)
                                    }
                                },
                                onAction: { action in
                                    pendingAction = action
                                    pendingAppIds = [app.id]
                                    showActionConfirm = true
                                },
                                formatSize: { service.formatSize($0) },
                                localizer: localizer
                            )
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm)
                }
            }
        }
        .onAppear { if service.installedApps.isEmpty { Task { await service.scanInstalledApps() } } }
        .overlay {
            if showActionConfirm {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showActionConfirm = false }

                    CardView(cornerRadius: Theme.Radius.lg) {
                        VStack(spacing: Theme.Spacing.lg) {
                            Image(systemName: pendingAction.icon)
                                .font(.system(size: 28))
                                .foregroundStyle(pendingAction.color)
                                .frame(width: 52, height: 52)
                                .background(pendingAction.color.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                            Text(localizer.actionConfirm)
                                .font(Theme.Font.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            let apps = service.installedApps.filter { pendingAppIds.contains($0.id) }
                            let size = pendingAction == .basicUninstall ? apps.reduce(Int64(0)) { $0 + $1.appSize } : apps.reduce(Int64(0)) { $0 + $1.totalSize }

                            VStack(spacing: Theme.Spacing.xs) {
                                Text(pendingAction.desc(localizer))
                                    .font(Theme.Font.body)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text("\(localizer.willAction)\(pendingAction.label(localizer)) \(apps.count) \(localizer.itemsLabel)，\(localizer.total) \(service.formatSize(size))")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }

                            HStack(spacing: Theme.Spacing.md) {
                                Button { showActionConfirm = false } label: {
                                    Text(localizer.cancelBtn)
                                        .font(Theme.Font.subheadlineMedium)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, Theme.Spacing.sm)
                                        .background(Theme.Colors.cardBg)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                                        )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    showActionConfirm = false
                                    performAction()
                                } label: {
                                    Text(localizer.confirmBtn)
                                        .font(Theme.Font.subheadlineMedium)
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, Theme.Spacing.sm)
                                        .background(Theme.Colors.danger)
                                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(width: 360)
                }
            }
        }
        .overlay {
            if showActionResult {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { showActionResult = false }

                    CardView(cornerRadius: Theme.Radius.lg) {
                        VStack(spacing: Theme.Spacing.lg) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Theme.Colors.success)
                                .frame(width: 52, height: 52)

                            Text(localizer.actionDone)
                                .font(Theme.Font.headline)
                                .foregroundStyle(Theme.Colors.textPrimary)

                            Text(actionResultMsg)
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Colors.textSecondary)

                            Button { showActionResult = false } label: {
                                Text(localizer.confirmBtn)
                                    .font(Theme.Font.subheadlineMedium)
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, Theme.Spacing.sm)
                                    .background(Theme.Colors.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(width: 340)
                }
            }
        }
    }

    private func subCategoryColor(_ cat: String) -> Color {
        switch cat {
        case "AI Agent": .purple
        case "CLI": .blue
        case "Package Manager", "包管理": .orange
        case "Development", "开发": .green
        case "Project Artifacts", "项目产物": .purple
        case "Installers", "安装包": .orange
        case "Apps", "应用": .cyan
        case "Other", "其它": .gray
        default: .gray
        }
    }

    private func subCategoryIconName(_ cat: String) -> String {
        switch cat {
        case "AI Agent": "cpu"
        case "CLI": "terminal"
        case "Package Manager", "包管理": "cube.box"
        case "Development", "开发": "hammer"
        case "Project Artifacts", "项目产物": "shippingbox"
        case "Installers", "安装包": "externaldrive.badge.plus"
        case "Apps", "应用": "app.fill"
        case "Other", "其它": "questionmark.folder"
        default: "folder"
        }
    }

    private func topActionLabel(icon: String, title: String, color: Color, isUnavailable: Bool = false) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
            Text(title)
                .font(Theme.Font.subheadlineMedium)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.86)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, 7)
        .frame(minHeight: 32)
        .background(color.opacity(isUnavailable ? 0.62 : 0.76))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Color.white.opacity(isUnavailable ? 0.28 : 0.34), lineWidth: 0.8)
        )
        .shadow(color: color.opacity(isUnavailable ? 0.12 : 0.2), radius: 5, y: 2)
    }

    private func bulkOperationLabel(action: AppAction, isUnavailable: Bool = false) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: action.icon)
                .font(.system(size: 12, weight: .semibold))
            Text(action.label(localizer))
                .font(Theme.Font.captionMedium)
                .fontWeight(.semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .background(action.color.opacity(isUnavailable ? 0.62 : 0.76))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Color.white.opacity(isUnavailable ? 0.28 : 0.34), lineWidth: 0.9)
        )
        .shadow(color: action.color.opacity(isUnavailable ? 0.12 : 0.22), radius: 5, y: 2)
    }

    private func toolbarActionLabel(icon: String, title: String, color: Color, isPrimary: Bool) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
                .font(Theme.Font.captionMedium)
                .lineLimit(1)
        }
        .foregroundStyle(isPrimary ? .white : color)
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, 6)
        .frame(minHeight: 28)
        .background(isPrimary ? color : color.opacity(0.11))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(isPrimary ? Color.white.opacity(0.16) : color.opacity(0.28), lineWidth: 0.7)
        )
    }

    private func performAction() {
        let apps = service.installedApps.filter { pendingAppIds.contains($0.id) }
        guard !apps.isEmpty else { return }
        Task {
            var successCount = 0
            var failCount = 0
            var removedIds: Set<String> = []
            for app in apps {
                let ok: Bool
                switch pendingAction {
                case .reset: ok = await service.resetApp(app: app)
                case .basicUninstall: ok = await service.basicUninstall(app: app)
                case .fullUninstall: ok = await service.fullUninstall(app: app)
                }
                if ok {
                    successCount += 1
                    if pendingAction != .reset {
                        removedIds.insert(app.id)
                    }
                } else { failCount += 1 }
            }
            if !removedIds.isEmpty {
                service.installedApps.removeAll { removedIds.contains($0.id) }
            }
            service.refreshDiskInfo()
            selectedAppIds.removeAll()
            actionResultMsg = "\(pendingAction.label(localizer))\(localizer.actionComplete)：\(localizer.successCount) \(successCount) \(localizer.unitItems)" + (failCount > 0 ? "，\(localizer.failCount) \(failCount) \(localizer.unitItems)" : "")
            showActionResult = true
        }
    }
}

// MARK: - Shared Components

struct ActionCard: View {
    let icon: String; let title: String; let subtitle: String; let color: Color; let isDisabled: Bool; let action: () -> Void
    @State private var isHovered = false
    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 32)).foregroundColor(isDisabled ? .secondary : color)
                VStack(spacing: 4) { Text(title).font(.headline).foregroundColor(isDisabled ? .secondary : .primary); Text(subtitle).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center).lineLimit(2) }
            }.frame(width: 150, height: 140).padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(isHovered && !isDisabled ? color.opacity(0.08) : Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(isHovered && !isDisabled ? color.opacity(0.4) : Color(nsColor: .separatorColor), lineWidth: isHovered && !isDisabled ? 2 : 1))
        }.buttonStyle(.plain).disabled(isDisabled).onHover { isHovered = $0 }
    }
}

struct ScanActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let iconColor: Color
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(isHovered && !isDisabled ? 0.3 : 0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: icon)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(isDisabled ? Theme.Colors.textTertiary : iconColor)
                }
                VStack(spacing: Theme.Spacing.xs) {
                    Text(title)
                        .font(Theme.Font.headline)
                        .foregroundStyle(isDisabled ? Theme.Colors.textTertiary : Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(width: 170, height: 160)
            .padding(Theme.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .fill(isHovered && !isDisabled ? iconColor.opacity(0.06) : Theme.Colors.cardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.lg)
                    .stroke(isHovered && !isDisabled ? iconColor.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: isHovered && !isDisabled ? 2 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
    }
}

struct RiskFilterButton: View {
    let label: String; let color: Color; let isActive: Bool; let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) { Circle().fill(isActive ? color : Color.secondary.opacity(0.4)).frame(width: 6, height: 6); Text(label).font(.caption2).fontWeight(isActive ? .bold : .regular) }
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 8).fill(isActive ? color.opacity(0.15) : Color.clear))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(isActive ? color.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1))
        }.buttonStyle(.plain).foregroundColor(isActive ? color : .secondary)
    }
}

struct RiskPillFilterButton: View {
    let label: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(isActive ? color : Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .fill(isActive ? color.opacity(0.12) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                        .stroke(isActive ? color.opacity(0.4) : Theme.Colors.separator, lineWidth: isActive ? 1.5 : 0.5)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DiskStat: View {
    let title: String; let value: String; var color: Color = .primary
    var body: some View { VStack(spacing: 2) { Text(title).font(.caption2).foregroundColor(.secondary).textCase(.uppercase); Text(value).font(.title3).fontWeight(.bold).foregroundColor(color) } }
}


// MARK: - Sensor Monitor Tab

struct SensorMonitorTab: View {
    @ObservedObject var monitor: SensorMonitor
    @EnvironmentObject var localizer: Localizer
    @State private var filterType: SensorEvent.SensorType?

    var filteredEvents: [SensorEvent] {
        if let type = filterType {
            return monitor.events.filter { $0.sensorType == type }
        }
        return monitor.events
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "video.fill",
                title: localizer.deviceMonitor,
                subtitle: localizer.deviceMonitorSubtitle,
                color: .red
            ) {
                HStack(spacing: 8) {
                    if monitor.cameraActive {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Image(systemName: "video.fill").font(.caption2)
                            Text(monitor.cameraProcess ?? localizer.camera).font(.caption2)
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    if monitor.microphoneActive {
                        HStack(spacing: 4) {
                            Circle().fill(Color.blue).frame(width: 6, height: 6)
                            Image(systemName: "mic.fill").font(.caption2)
                            Text(monitor.microphoneProcess ?? localizer.microphone).font(.caption2)
                        }
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }

                    Button {
                        if monitor.isMonitoring { monitor.stop() } else { monitor.start() }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: monitor.isMonitoring ? "stop.circle" : "play.circle")
                            Text(monitor.isMonitoring ? localizer.stopMonitor : localizer.startMonitoringBtn)
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .tint(monitor.isMonitoring ? .red : .green)

                    if !monitor.events.isEmpty {
                        Button { monitor.clearEvents() } label: {
                            HStack(spacing: 3) { Image(systemName: "trash"); Text(localizer.clear) }
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(.red)
                    }
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    SensorFilterChip(label: localizer.all, icon: "sensor.fill", color: .gray, isActive: filterType == nil) { filterType = nil }
                    SensorFilterChip(label: localizer.camera, icon: "video.fill", color: .red, isActive: filterType == .camera) { filterType = .camera }
                    SensorFilterChip(label: localizer.microphone, icon: "mic.fill", color: Theme.Colors.info, isActive: filterType == .microphone) { filterType = .microphone }
                }

                Spacer()

                Text("\(filteredEvents.count) \(localizer.recordsCount)").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            Divider()

            if !monitor.isMonitoring && monitor.events.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "video.slash")
                        .font(.system(size: 48)).foregroundColor(.secondary.opacity(0.5))
                    Text(localizer.deviceMonitorStopped).font(.title3).fontWeight(.medium)
                    Text(localizer.deviceMonitorHint).font(.caption).foregroundColor(.secondary)
                    Button(localizer.startMonitoringBtn) { monitor.start() }
                        .buttonStyle(.borderedProminent).tint(.red).controlSize(.regular)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEvents.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40)).foregroundColor(.green.opacity(0.6))
                    Text(localizer.noDeviceCall).font(.title3).fontWeight(.medium)
                    Text(localizer.noDeviceCallHint).font(.caption).foregroundColor(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredEvents) {
                    TableColumn(localizer.timeCol) { event in
                        Text(DisplayTime.withSeconds.string(from: event.timestamp)).font(.caption).monospacedDigit()
                    }.width(70)

                    TableColumn(localizer.colType) { event in
                        HStack(spacing: 4) {
                            Image(systemName: event.sensorType.icon)
                                .font(.caption)
                                .foregroundColor(event.sensorType.color)
                            Text(event.sensorType.localizedLabel(localizer))
                                .font(.caption2).fontWeight(.medium)
                                .foregroundColor(event.sensorType.color)
                        }
                    }.width(70)

                    TableColumn(localizer.colProcess) { event in
                        HStack(spacing: 4) {
                            Image(systemName: "app.fill").font(.caption2).foregroundColor(.secondary)
                            Text(event.processName).font(.caption).fontWeight(.medium).lineLimit(1)
                        }
                    }.width(min: 120)

                    TableColumn(localizer.colPID) { event in
                        Text("\(event.pid)").font(.caption2).monospacedDigit().foregroundColor(.secondary)
                    }.width(60)

                    TableColumn(localizer.colBundleID) { event in
                        if let bid = event.bundleId {
                            Text(bid).font(.caption2).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                        } else {
                            Text("-").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}

struct SensorFilterChip: View {
    let label: String
    let icon: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon).font(.caption2)
                Text(label).font(.caption2).fontWeight(isActive ? .semibold : .regular)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(isActive ? color.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .foregroundColor(isActive ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}
