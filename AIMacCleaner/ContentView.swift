import SwiftUI
import AppKit
import SQLite3

struct ContentView: View {
    @State private var selectedTab: NavItem = .overview
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @State private var showSettings = false
    @State private var sidebarCollapsed = false
    @State private var toolboxExpanded = false
    @State private var hoveredItem: NavItem?
    @StateObject private var overviewStore = AgentMonitorOverviewStore()
    @AppStorage("networkMode") private var networkMode = "internet"

    private var isToolboxSubItemSelected: Bool {
        [.tokenScope, .cleaner, .app, .dependency, .other, .migration].contains(selectedTab)
    }

    enum NavItem: String, CaseIterable {
        case overview = "overview"
        case agentGuard = "agentGuard"
        case operations = "operations"
        case toolbox = "toolbox"
        case tokenScope = "tokenScope"
        case cleaner = "cleaner"
        case app = "app"
        case dependency = "dependency"
        case other = "other"
        case migration = "migration"

        var isSubItem: Bool {
            switch self {
            case .tokenScope, .cleaner, .app, .dependency, .other, .migration: return true
            default: return false
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
            case .agentGuard: "shield.fill"
            case .toolbox: "wrench.and.screwdriver.fill"
            case .tokenScope: "chart.xyaxis.line"
            case .migration: "arrow.triangle.2.circlepath"
            }
        }

        var color: Color {
            switch self {
            case .cleaner: .blue
            case .app: .cyan
            case .dependency: .orange
            case .other: .gray
            case .overview: Theme.Colors.info
            case .operations: Theme.Colors.teal
            case .agentGuard: .orange
            case .toolbox: .blue
            case .tokenScope: Theme.Colors.teal
            case .migration: .purple
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
            case .agentGuard: localizer.navAgentGuard
            case .toolbox: localizer.navToolbox
            case .tokenScope: localizer.tokenScopeTitle
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
            case .agentGuard: localizer.subAgentGuard
            case .toolbox: localizer.subToolbox
            case .tokenScope: localizer.tokenScopeSubtitle
            case .migration: localizer.subMigration
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: 0.5)
            detailContent
        }
        .frame(minWidth: 960, minHeight: 640)
        .onAppear {
            service.refreshDiskInfo()
            service.refreshHardwareInfo()
            service.refreshCachedSurfacesInBackground(minInterval: 30)
            overviewStore.refresh(force: true)
            service.importKnownAgentHistory()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(service)
                .environmentObject(localizer)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarLogo

            Rectangle()
                .fill(Theme.Colors.separator.opacity(0.5))
                .frame(height: 0.5)
                .padding(.horizontal, Theme.Spacing.md)

            sidebarNavItems

            Spacer()

            Rectangle()
                .fill(Theme.Colors.separator.opacity(0.5))
                .frame(height: 0.5)
                .padding(.horizontal, Theme.Spacing.md)

            sidebarFooter
        }
        .frame(width: sidebarCollapsed ? Theme.Sidebar.collapsedWidth : Theme.Sidebar.expandedWidth)
        .background(
            ZStack {
                Theme.Colors.sidebarBg
                Theme.Gradients.sidebar
            }
        )
    }

    private var sidebarLogo: some View {
        HStack(spacing: 0) {
            if !sidebarCollapsed {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                    Text(localizer.appName)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Gradients.accent)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: Theme.Sidebar.iconSize + 2, height: Theme.Sidebar.iconSize + 2)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, Theme.Spacing.xl)
        .padding(.bottom, Theme.Spacing.lg)
        .padding(.horizontal, sidebarCollapsed ? Theme.Spacing.xs : Theme.Spacing.md)
    }

    private var sidebarNavItems: some View {
        VStack(alignment: sidebarCollapsed ? .center : .leading, spacing: Theme.Spacing.xs) {
            if !sidebarCollapsed {
                Text(localizer.features)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .textCase(.uppercase)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.top, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xs)
            } else {
                Text(localizer.features)
                    .font(.system(size: 8, weight: .semibold))
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
        .padding(.horizontal, sidebarCollapsed ? Theme.Spacing.xs : Theme.Spacing.sm)
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
                        .font(.system(size: Theme.Sidebar.iconSize * 0.65, weight: .medium))
                        .foregroundStyle(hoveredItem == .toolbox ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                        .frame(width: Theme.Sidebar.iconSize)

                    Text(NavItem.toolbox.label(localizer))
                        .font(.system(size: 13))
                        .fontWeight(.regular)
                        .foregroundStyle(hoveredItem == .toolbox ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)

                    Spacer()

                    Image(systemName: toolboxExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.md + 1)
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
                    ForEach([NavItem.tokenScope, .cleaner, .app, .dependency, .other, .migration], id: \.self) { item in
                        Button {
                            selectedTab = item
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 11, weight: selectedTab == item ? .semibold : .regular))
                                    .foregroundStyle(selectedTab == item ? item.color : Theme.Colors.textTertiary)
                                    .frame(width: 16)

                                Text(item.label(localizer))
                                    .font(.system(size: 12))
                                    .fontWeight(selectedTab == item ? .semibold : .regular)
                                    .foregroundStyle(selectedTab == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)

                                Spacer()
                            }
                            .padding(.horizontal, Theme.Spacing.md + Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.sm + 2)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .fill(selectedTab == item ? item.color.opacity(0.08) : Color.clear)
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
                .fill(selectedTab == item ? item.color : Color.clear)
                .frame(width: 3, height: Theme.Sidebar.itemHeight * 0.5)

            Image(systemName: item.icon)
                .font(.system(size: Theme.Sidebar.iconSize * 0.65, weight: .medium))
                .foregroundStyle(selectedTab == item ? item.color : (hoveredItem == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary))
                .frame(width: Theme.Sidebar.iconSize)

            Text(item.label(localizer))
                .font(.system(size: 12))
                .fontWeight(.regular)
                .foregroundStyle(selectedTab == item ? Theme.Colors.textPrimary : (hoveredItem == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary))
                .lineLimit(1)

            Spacer()

            if selectedTab == item {
                Circle()
                    .fill(item.color.opacity(0.6))
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm + 1)
        .background(
            RoundedRectangle(cornerRadius: Theme.Sidebar.itemRadius)
                .fill(selectedTab == item ? item.color.opacity(0.1) : (hoveredItem == item ? Theme.Colors.cardHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Sidebar.itemRadius)
                .stroke(selectedTab == item ? item.color.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }

    private func sidebarCollapsedItem(_ item: NavItem) -> some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: item.icon)
                .font(.system(size: Theme.Sidebar.iconSize * 0.75, weight: selectedTab == item ? .semibold : .medium))
                .foregroundStyle(selectedTab == item ? item.color : (hoveredItem == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary))
                .frame(width: 24, height: 24)
            Text(item.label(localizer).split(separator: " ").first.map(String.init) ?? "")
                .font(.system(size: 8, weight: selectedTab == item ? .semibold : .regular))
                .foregroundStyle(selectedTab == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, Theme.Spacing.sm - 2)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .fill(selectedTab == item ? item.color.opacity(0.12) : (hoveredItem == item ? Theme.Colors.cardHover : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(selectedTab == item ? item.color.opacity(0.25) : Color.clear, lineWidth: 1)
        )
    }

    private var sidebarFooter: some View {
        Group {
            if sidebarCollapsed {
                VStack(spacing: Theme.Spacing.sm) {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            sidebarCollapsed = false
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(localizer.expandSidebar)

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(localizer.settings)

                    languageToggleButton

                    Image(systemName: networkMode == "internet" ? "globe" : "lock.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(networkMode == "internet" ? Theme.Colors.info : Theme.Colors.warning)

                    Text("v\(service.currentVersion)")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.vertical, Theme.Spacing.lg)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .help(localizer.settings)

                        languageToggleButton

                        Spacer()
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: networkMode == "internet" ? "globe" : "lock.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(networkMode == "internet" ? Theme.Colors.info : Theme.Colors.warning)

                        Text("v\(service.currentVersion)")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.Colors.textTertiary)

                        Spacer()

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                sidebarCollapsed = true
                            }
                        } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help(localizer.collapseSidebar)
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
            }
        }
    }

    private var languageToggleButton: some View {
        Picker("", selection: $localizer.language) {
            ForEach(AppLanguage.allCases, id: \.self) { lang in
                Text(lang.nativeName)
                    .font(.system(size: 10))
                    .tag(lang)
            }
        }
        .pickerStyle(.menu)
        .frame(minWidth: sidebarCollapsed ? 36 : 60, maxWidth: sidebarCollapsed ? 36 : 100)
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
            OperationLogTab(monitor: service.operationMonitor)
                .environmentObject(localizer)
        case .agentGuard:
            AgentGuardTab()
                .environmentObject(localizer)
        case .toolbox:
            ToolboxTab()
                .environmentObject(localizer)
        case .tokenScope:
            TokenScopeLabView()
                .environmentObject(localizer)
        case .migration:
            IntelMigrationTab()
                .environmentObject(localizer)
        }
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
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .background(Theme.Colors.background)
    }
}

// MARK: - Toolbox Tab

struct ToolboxTab: View {
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var service: ScannerService
    @State private var selectedTool = 0

    private let tools: [(icon: String, title: (Localizer) -> String, subtitle: (Localizer) -> String, color: Color)] = [
        ("chart.xyaxis.line", { $0.tokenScopeTitle }, { $0.tokenScopeSubtitle }, Theme.Colors.teal),
        ("arrow.down.doc.fill", { $0.navCleaner }, { $0.subCleaner }, .blue),
        ("app.badge", { $0.navApp }, { $0.subApp }, .cyan),
        ("cube.box", { $0.navDependency }, { $0.subDependency }, .orange),
        ("terminal", { $0.navOther }, { $0.subOther }, .gray),
        ("arrow.triangle.2.circlepath", { $0.navMigration }, { $0.subMigration }, .purple),
    ]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "wrench.and.screwdriver.fill",
                title: localizer.navToolbox,
                subtitle: localizer.subToolbox,
                color: .blue
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
    let sourcePath: String
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
    @Published var isScanning = false
    @Published var authorizedRoots: [String] = []
    @Published var scannedRoots: [String] = []
    @Published var lastScanDate: Date?

    private let scanner = AgentMonitorOverviewScanner()
    private let cachedRootsKey = "agentMonitorOverview.scannedRoots"
    private var isRefreshingRealtime = false
    private var lastRealtimeRefreshDate: Date?
    private let activeRetentionWindow: TimeInterval = 10 * 60

    private struct Cache: Codable {
        var version: Int = 1
        var updatedAt: Date = Date()
        var snapshots: [AgentMonitorUsageSnapshot] = []
        var sessions: [AgentMonitorSessionSnapshot] = []
        var authorizedRoots: [String] = []
        var scannedRoots: [String] = []
        var lastScanDate: Date?
    }

    init() {
        scannedRoots = UserDefaults.standard.stringArray(forKey: cachedRootsKey) ?? []
        loadCache()
    }

    func refresh(force: Bool = false) {
        refreshRealtime()
        if !force,
           let lastScanDate,
           !snapshots.isEmpty,
           Date().timeIntervalSince(lastScanDate) < 45 {
            return
        }
        guard !isScanning else { return }
        isScanning = true
        Task.detached(priority: .utility) { [scanner] in
            let result = scanner.scan()
            await MainActor.run {
                self.snapshots = result.snapshots
                if !result.sessions.isEmpty || self.sessions.isEmpty {
                    self.sessions = result.sessions
                }
                self.authorizedRoots = result.authorizedRoots
                self.scannedRoots = result.scannedRoots
                UserDefaults.standard.set(result.scannedRoots, forKey: self.cachedRootsKey)
                self.lastScanDate = Date()
                self.isScanning = false
                self.saveCache()
            }
        }
    }

    func refreshRealtime() {
        guard !isRefreshingRealtime else { return }
        if let lastRealtimeRefreshDate,
           Date().timeIntervalSince(lastRealtimeRefreshDate) < 3 {
            return
        }
        isRefreshingRealtime = true
        let cachedRoots = scannedRoots
        Task.detached(priority: .utility) { [scanner] in
            let result = scanner.realtimeScan(cachedRoots: cachedRoots)
            await MainActor.run {
                if !result.sessions.isEmpty {
                    let activeKeys = Set(result.sessions.map { "\($0.agentName)|\($0.sessionId)|\($0.sourcePath)" })
                    let retentionCutoff = Date().addingTimeInterval(-self.activeRetentionWindow)
                    let retained = self.sessions.filter {
                        let key = "\($0.agentName)|\($0.sessionId)|\($0.sourcePath)"
                        guard !activeKeys.contains(key) else { return false }
                        if Self.isActiveSession($0) {
                            if $0.status == "Paused" { return true }
                            return ($0.latestActivity ?? .distantPast) >= retentionCutoff
                        }
                        return true
                    }
                    self.sessions = (result.sessions + retained)
                        .sorted {
                            let left = $0.latestActivity ?? .distantPast
                            let right = $1.latestActivity ?? .distantPast
                            if left == right { return $0.agentName < $1.agentName }
                            return left > right
                        }
                    let realtimeSnapshots = Self.usageSnapshots(from: self.sessions)
                    if !realtimeSnapshots.isEmpty {
                        self.snapshots = Self.mergedSnapshots(primary: realtimeSnapshots, fallback: self.snapshots)
                    }
                }
                if !result.authorizedRoots.isEmpty {
                    self.authorizedRoots = result.authorizedRoots
                }
                if self.scannedRoots.isEmpty, !result.scannedRoots.isEmpty {
                    self.scannedRoots = result.scannedRoots
                }
                let cachedSessionSnapshots = Self.usageSnapshots(from: self.sessions)
                if !cachedSessionSnapshots.isEmpty {
                    self.snapshots = Self.mergedSnapshots(primary: cachedSessionSnapshots, fallback: self.snapshots)
                }
                self.saveCache()
                self.lastRealtimeRefreshDate = Date()
                self.isRefreshingRealtime = false
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
            byName[snapshot.agentName] = snapshot
        }
        return Array(byName.values).sorted {
            let left = $0.latestActivity ?? .distantPast
            let right = $1.latestActivity ?? .distantPast
            if left == right { return $0.agentName < $1.agentName }
            return left > right
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: SandboxPaths.shared.agentMonitorCachePath)),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        snapshots = cache.snapshots
        sessions = cache.sessions
        authorizedRoots = cache.authorizedRoots
        if !cache.scannedRoots.isEmpty {
            scannedRoots = cache.scannedRoots
        }
        lastScanDate = cache.lastScanDate
    }

    private func saveCache() {
        let cache = Cache(
            updatedAt: Date(),
            snapshots: snapshots,
            sessions: Array(sessions.prefix(240)),
            authorizedRoots: authorizedRoots,
            scannedRoots: scannedRoots,
            lastScanDate: lastScanDate
        )
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: URL(fileURLWithPath: SandboxPaths.shared.agentMonitorCachePath), options: .atomic)
    }
}

private final class AgentMonitorOverviewScanner {
    fileprivate struct ScanResult {
        let snapshots: [AgentMonitorUsageSnapshot]
        let sessions: [AgentMonitorSessionSnapshot]
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
        let sourcePath: String
    }

    private let fileManager = FileManager.default
    private var home: String { SandboxPaths.realHomeDirectory }

    private var specs: [AgentSpec] {
        var base = [
            AgentSpec(name: "Claude Code", roots: ["~/.claude", "~/.claude/projects", "~/.claude/sessions"], processKeywords: ["claude", "claude-code", "anthropic"], contextWindow: 200_000),
            AgentSpec(name: "Codex", roots: ["~/.codex/sessions", "~/.codex/archived_sessions"], processKeywords: ["codex"], contextWindow: 200_000),
            AgentSpec(name: "OpenCode", roots: ["~/.opencode", "~/.local/share/opencode", "~/.local/share/opencode/opencode.db"], processKeywords: ["opencode"], contextWindow: 200_000),
            AgentSpec(name: "Gemini CLI", roots: ["~/.gemini"], processKeywords: ["gemini"], contextWindow: 1_000_000),
            AgentSpec(name: "Cursor", roots: ["~/Library/Application Support/Cursor/User/workspaceStorage"], processKeywords: ["cursor"], contextWindow: 200_000),
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
        let pidToSessionFiles = scanOpenSessionFiles()
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
                guard shouldEnumerateUsageFiles(root: root, spec: spec) else { continue }
                let files = usageFiles(under: root)
                for file in files {
                    sessionIDs.insert(sessionID(for: file, root: root))
                    let usage = parseUsage(file: file)
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

        let activeLiveSessions = uniqueSessions(liveSessions + historySessions)
            .sorted { lhs, rhs in
                let left = lhs.latestActivity ?? .distantPast
                let right = rhs.latestActivity ?? .distantPast
                if left == right { return lhs.agentName < rhs.agentName }
                return left > right
            }
        return ScanResult(
            snapshots: snapshots,
            sessions: Array(activeLiveSessions.prefix(240)),
            authorizedRoots: authorizedRoots,
            scannedRoots: scannedRoots
        )
    }

    fileprivate func realtimeScan(cachedRoots: [String]) -> ScanResult {
        let processInfo = scanProcessInfo()
        let children = childrenMap(processInfo)
        let pidToSessionFiles = scanOpenSessionFiles()
        let authorizedRoots = authorizedBookmarkRoots()
        let fixedRoots = Array(Set(cachedRoots + authorizedRoots + specs.flatMap { spec in
            effectiveRoots(for: spec, authorizedRoots: authorizedRoots)
        })).filter { fileManager.fileExists(atPath: $0) }
        var liveSessions = scanLiveSessions(
            processInfo: processInfo,
            children: children,
            pidToSessionFiles: pidToSessionFiles,
            portsByPid: [:]
        )
        let seen = Set(liveSessions.map { "\($0.agentName)|\($0.sessionId)|\($0.sourcePath)" })
        let recentSessions = scanForegroundSessionFiles(
            roots: fixedRoots,
            excluding: seen,
            processInfo: processInfo,
            children: children
        )
        liveSessions.append(contentsOf: recentSessions)
        for root in fixedRoots {
            if root.hasSuffix("/opencode.db") {
                liveSessions.append(contentsOf: parseOpenCodeDBSessions(path: root, processInfo: processInfo))
            } else if root.hasSuffix("/sqlite.db"), root.lowercased().contains("minimax") {
                liveSessions.append(contentsOf: parseMiniMaxDBSessions(path: root, processInfo: processInfo))
            } else if root.hasSuffix("/nexus.db"), root.lowercased().contains("minimax") {
                liveSessions.append(contentsOf: parseMiniMaxNexusDBSessions(path: root, processInfo: processInfo))
            }
        }
        let activeSessions = uniqueSessions(liveSessions.filter { isRealtimeActiveSession($0) })
            .sorted {
                let left = $0.latestActivity ?? .distantPast
                let right = $1.latestActivity ?? .distantPast
                if left == right { return $0.agentName < $1.agentName }
                return left > right
            }
        return ScanResult(
            snapshots: [],
            sessions: Array(activeSessions.prefix(80)),
            authorizedRoots: authorizedRoots,
            scannedRoots: fixedRoots.sorted { $0.count < $1.count }
        )
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
                guard shouldEnumerateUsageFiles(root: root, spec: spec) else { continue }
                for file in usageFiles(under: root).filter({ !liveSources.contains($0.path) }) {
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
                let process = liveProcessByAgent[item.spec.name]?.first
                let pid = process?.pid
                let contextPercent = item.parsed.contextWindow > 0 ? min(Double(item.parsed.lastContextTokens) / Double(item.parsed.contextWindow), 1) : 0
                let projectName = lastPathSegment(item.parsed.cwd).isEmpty ? item.spec.name : lastPathSegment(item.parsed.cwd)
                return AgentMonitorSessionSnapshot(
                    id: "\(item.spec.name)-\(item.parsed.sessionId)-history-\(item.parsed.sourcePath)",
                    agentName: item.spec.name,
                    pid: pid,
                    sessionId: item.parsed.sessionId,
                    status: item.parsed.status,
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
            roots.insert(root)
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
        if spec.name == "MiniMax Agent" {
            roots.insert(home + "/.minimax/sqlite.db")
            roots.insert(home + "/.minimax/nexus/nexus.db")
            roots.insert(home + "/.minimax-agent-cn")
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
            return [home + "/.codex/sessions", home + "/.codex/archived_sessions"]
        case "OpenCode":
            return [home + "/.opencode", home + "/.local/share/opencode", home + "/.local/share/opencode/opencode.db"]
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
        guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsPackageDescendants]) else {
            return []
        }
        var files: [URL] = []
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 8000 { break }
            let name = url.lastPathComponent.lowercased()
            if ["node_modules", ".git", "cache", "caches", "deriveddata", "tmp", "logs", "log", "telemetry", "plugins", ".builtin-skills"].contains(name) {
                enumerator.skipDescendants()
                continue
            }
            let ext = url.pathExtension.lowercased()
            if ext == "jsonl" || ext == "json" || ext == "log" {
                files.append(url)
                if files.count >= 500 { break }
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
        if lower.contains("/logs") || lower.hasSuffix("/log") || lower.contains("/telemetry") {
            return false
        }
        return true
    }

    private func parseUsage(file: URL) -> (tokens: Int, lastContextTokens: Int, contextWindow: Int, latest: Date?, project: String?) {
        guard let data = try? Data(contentsOf: file), data.count <= 8_000_000 else {
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
            guard let lineData = String(line).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

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

        let liveByCwd = Dictionary(grouping: processInfo.values.filter { matchingSpecName($0.command) == "OpenCode" }, by: { processCwd(pid: $0.pid) ?? "" })
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
            let latest = dateFromMilliseconds(updatedMs)
            let proc = liveByCwd[directory]?.first
            let isLive = proc != nil
            let status = isLive ? "Waiting" : "Done"
            let contextWindow = 200_000
            let contextPercent = min(Double(input + cache) / Double(contextWindow), 1)

            rows.append(AgentMonitorSessionSnapshot(
                id: "OpenCode-\(sessionId)-db",
                agentName: "OpenCode",
                pid: proc?.pid,
                sessionId: sessionId,
                status: status,
                projectName: projectName.isEmpty ? (lastPathSegment(directory).isEmpty ? "OpenCode" : lastPathSegment(directory)) : projectName,
                projectPath: directory,
                model: model.isEmpty ? "—" : model,
                tokens: AgentMonitorTokenBreakdown(input: input, output: output, cacheRead: cache),
                contextPercent: contextPercent,
                contextWindow: contextWindow,
                turnCount: turns,
                currentTask: title.isEmpty ? "OpenCode session" : title,
                toolCount: 0,
                runningToolCount: 0,
                childCount: proc.map { descendants(of: $0.pid, children: childrenMap(processInfo)).count } ?? 0,
                ports: [],
                memoryMB: proc.map { max($0.rssKB / 1024, 1) },
                latestActivity: latest,
                sourcePath: path
            ))
        }
        return rows
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
          COUNT(DISTINCT t.turn_id)
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
            let status: String
            if rawStatus.contains("finish") || rawStatus.contains("done") || rawStatus.contains("complete") {
                status = isLive ? "Waiting" : "Done"
            } else if hasActiveStatus || isLive {
                status = "Executing"
            } else {
                status = "History"
            }
            let contextWindow = 512_000
            let contextPercent = min(Double(input + cache) / Double(contextWindow), 1)
            let label = agent.isEmpty ? "MiniMax" : "MiniMax \(agent)"

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
                currentTask: title.isEmpty ? label : title,
                toolCount: 0,
                runningToolCount: status == "Executing" ? 1 : 0,
                childCount: resolvedPID.map { descendants(of: $0, children: childrenMap(processInfo)).count } ?? 0,
                ports: [],
                memoryMB: proc.map { max($0.rssKB / 1024, 1) },
                latestActivity: latest,
                sourcePath: path
            ))
        }
        return rows
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
            let messageCount = Int(sqlite3_column_int64(stmt, 5))
            let rawStatus = sqliteText(stmt, 6).lowercased()
            let model = sqliteText(stmt, 7)
            let latest = dateFromISO(sqliteText(stmt, 8)) ?? dateFromISO(sqliteText(stmt, 4))
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
                currentTask: title.isEmpty ? "MiniMax conversation" : title,
                toolCount: 0,
                runningToolCount: status == "Thinking" ? 1 : 0,
                childCount: liveProcess.map { descendants(of: $0.pid, children: childrenMap(processInfo)).count } ?? 0,
                ports: [],
                memoryMB: liveProcess.map { max($0.rssKB / 1024, 1) },
                latestActivity: latest,
                sourcePath: path
            ))
        }
        return rows
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
            let agentName = agentName(for: proc?.command ?? "codex", fallback: "Codex")
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
                            currentTask = latestUserInstruction.isEmpty ? objective : latestUserInstruction
                            status = goalStatus == "active" ? "Executing" : "Paused"
                        } else {
                            status = "Done"
                        }
                    }
                } else if eventType == "task_complete" {
                    currentTask = latestUserInstruction.isEmpty ? activeGoalObjective : latestUserInstruction
                    pendingCalls.removeAll()
                    status = statusForGoal(activeGoalStatus)
                } else if eventType == "turn_aborted" {
                    currentTask = latestUserInstruction.isEmpty ? activeGoalObjective : latestUserInstruction
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
            currentTask = latestUserInstruction.isEmpty ? activeGoalObjective : latestUserInstruction
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
            sourcePath: url.path
        )
    }

    private func sessionText(from url: URL) -> String? {
        let fullReadLimit = 120_000_000
        let headLimit = 1_000_000
        let tailLimit = 80_000_000
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
        try? handle.seek(toOffset: size - UInt64(tailLimit))
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
        return result
    }

    private func scanOpenSessionFiles() -> [Int: [String]] {
        let output = run("/usr/sbin/lsof", ["+c", "0", "-w", "-Fpn", "-u", "\(getuid())"])
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
            let key = "\(spec.name)|\(parsed.sessionId)|\(parsed.sourcePath)"
            guard !seen.contains(key) else { continue }
            let proc = processInfo.values.first { matchingSpecName($0.command) == spec.name }
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
            let projectName = lastPathSegment(parsed.cwd).isEmpty ? spec.name : lastPathSegment(parsed.cwd)
            rows.append(AgentMonitorSessionSnapshot(
                id: "\(spec.name)-\(parsed.sessionId)-recent-\(file.path)",
                agentName: spec.name,
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
                sourcePath: parsed.sourcePath
            ))
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

    private func sessionFiles(in root: String, cutoff: Date, maxFiles: Int) -> [URL] {
        guard fileManager.fileExists(atPath: root),
              let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsPackageDescendants]) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
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

    private func normalizedInstruction(_ value: String?) -> String? {
        guard let value else { return nil }
        let collapsed = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        return String(collapsed.prefix(500))
    }

    private func parsePort(from line: String) -> Int? {
        guard let range = line.range(of: #"[:.](\d+)\s+\(LISTEN\)"#, options: .regularExpression) else { return nil }
        let fragment = String(line[range])
        let digits = fragment.filter(\.isNumber)
        return Int(digits)
    }

    private func matchingSpecName(_ command: String) -> String? {
        let lower = command.lowercased()
        return specs.first { spec in
            spec.processKeywords.contains { lower.contains($0) }
        }?.name
    }

    private func specForSessionPath(_ path: String) -> AgentSpec? {
        let lower = path.lowercased()
        if lower.contains("/.codex/") { return specs.first { $0.name == "Codex" } }
        if lower.contains("/.claude") || lower.contains("claude") { return specs.first { $0.name == "Claude Code" } }
        if lower.contains("opencode") { return specs.first { $0.name == "OpenCode" } }
        if lower.contains("minimax") || lower.contains("mavis") { return specs.first { $0.name == "MiniMax Agent" } }
        return specs.first { spec in
            spec.roots.map(expand).contains { lower.contains($0.lowercased()) }
        }
    }

    private func agentName(for command: String, fallback: String) -> String {
        matchingSpecName(command) ?? fallback
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
        do {
            try task.run()
            let deadline = DispatchTime.now() + .seconds(3)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: deadline) {
                if task.isRunning {
                    task.terminate()
                }
            }
            task.waitUntilExit()
            guard let data = try? pipe.fileHandleForReading.readToEnd() else { return "" }
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func expand(_ path: String) -> String {
        path.replacingOccurrences(of: "~", with: home)
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
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
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

    private func date(from object: [String: Any]) -> Date? {
        let raw = stringValue(object, keys: ["timestamp", "created_at", "createdAt"])
            ?? stringValue(object["payload"] as? [String: Any], keys: ["timestamp", "created_at", "createdAt"])
        guard let raw else { return nil }
        return ISO8601DateFormatter().date(from: raw)
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
    @ObservedObject var overviewStore: AgentMonitorOverviewStore
    @StateObject private var sessionScanner = AgentSessionScanner()
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
    private var totalTokens: Int { rows.reduce(0) { $0 + $1.totalTokens } }
    private var cleanupTotalSize: Int64 { service.scanItems.reduce(0) { $0 + $1.size } }
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
                let colors: [Color] = [Theme.Colors.teal, Theme.Colors.info, Theme.Colors.purple, Theme.Colors.success, Theme.Colors.warning, Theme.Colors.danger]
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
                color: Theme.Colors.teal
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
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            overviewStore.refresh()
        }
    }

    private var summaryCards: some View {
        HStack(spacing: Theme.Spacing.sm) {
            StatCardView(icon: "internaldrive", iconColor: Theme.Colors.info, title: localizer.diskSpaceLabel, value: service.diskInfo.map { formatGB($0.freeGb) } ?? "—", subtitle: localizer.available)
            StatCardView(icon: "externaldrive", iconColor: Theme.Colors.warning, title: localizer.cleanupCandidates, value: formatBytes(cleanupTotalSize), subtitle: nil)
            StatCardView(icon: "eye.fill", iconColor: Theme.Colors.success, title: localizer.agentMonitorTitle, value: "\(totalOperations)", subtitle: localizer.totalOps)
            StatCardView(icon: "sum", iconColor: Theme.Colors.teal, title: localizer.tokenScopeTotalTokens, value: compactCount(totalTokens), subtitle: nil)
            if !service.installedApps.isEmpty {
                StatCardView(icon: "app.badge", iconColor: Theme.Colors.cyan, title: localizer.navApp, value: "\(service.installedApps.count)", subtitle: localizer.itemsLabel)
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
        sessionScanner.isScanning = true
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
        if lower.contains("系统") || lower.contains("system") { return Theme.Colors.teal }
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
        case .read: return Theme.Colors.teal
        case .execute: return Theme.Colors.purple
        }
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000.0) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000.0) }
        return "\(value)"
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
                .font(.system(size: 15, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.xs)
                .background(Theme.Colors.cardBg)
                .offset(y: -2)

            content
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.bottom, Theme.Spacing.sm)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, Theme.Spacing.xs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(color.opacity(0.72), lineWidth: 1)
                .background(Theme.Colors.cardBg.opacity(0.72))
        )
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
        .help("Unavailable in Mac App Store build")
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
        sessions.reduce(0) { $0 + $1.tokens.total }
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

                Text(localizer.t("App Store 版只读取授权数据", en: "App Store build only reads authorized data", zhHant: "App Store 版只讀取授權資料", ja: "App Store 版は許可済みデータのみ読み取ります", ko: "App Store 빌드는 승인된 데이터만 읽습니다", mt: "App Store build only reads authorized data"))
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
                    Text(localizer.t("配置", en: "Config", zhHant: "配置", ja: "設定", ko: "설정", mt: "Config")).frame(maxWidth: .infinity, alignment: .leading)
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
            Text(localizer.t("配置", en: "Config", zhHant: "配置", ja: "設定", ko: "설정", mt: "Config")).frame(width: 90, alignment: .leading)
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
                Text(session.model)
                    .frame(width: 92, alignment: .leading)
                    .lineLimit(1)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("\(Int(session.contextPercent * 100))%")
                    .frame(width: 74, alignment: .trailing)
                    .foregroundStyle(contextColor(session.contextPercent))
                Text(compactCount(session.tokens.total))
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
                        Text("\(session.model) · \(session.turnCount) \(localizer.overviewTurns) · \(session.toolCount) \(localizer.tokenScopeTools)")
                        Text("\(localizer.contextWindow) \(Int(session.contextPercent * 100))% / \(windowText(session.contextWindow))")
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
                        Text(localizer.t("只读监控 · 沙盒授权数据源", en: "Read-only monitor · sandbox-authorized data", zhHant: "唯讀監控 · 沙盒授權資料源", ja: "読み取り専用監視 · サンドボックス許可データ", ko: "읽기 전용 모니터 · 샌드박스 승인 데이터", mt: "Read-only monitor · sandbox-authorized data"))
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

    private func windowText(_ window: Int) -> String {
        guard window > 0 else { return "—" }
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
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000.0) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000.0) }
        return "\(value)"
    }

    private func contextColor(_ progress: Double) -> Color {
        if progress >= 0.85 { return Theme.Colors.danger }
        if progress >= 0.65 { return Theme.Colors.warning }
        return Theme.Colors.success
    }
}

private struct AgentCommandDashboardView: View {
    @ObservedObject var store: AgentMonitorOverviewStore
    @ObservedObject var monitor: OperationMonitor
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var service: ScannerService
    let onRefresh: () -> Void

    @State private var selectedSessionID: String?
    @State private var filterText = ""
    @State private var authorizationStatus = ""
    @State private var visibleSessionCount = 24
    @State private var showingSessionDetail = false

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

    private var totalTokens: Int { allSessions.reduce(0) { $0 + $1.tokens.total } }
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
    private var dataStatusIcon: String {
        if store.isScanning { return "arrow.triangle.2.circlepath" }
        if !allSessions.isEmpty { return "checkmark.seal.fill" }
        if !store.authorizedRoots.isEmpty { return "folder.badge.questionmark" }
        return "exclamationmark.triangle.fill"
    }
    private var dataStatusColor: Color {
        if store.isScanning { return Theme.Colors.warning }
        if !allSessions.isEmpty { return Theme.Colors.success }
        if !store.authorizedRoots.isEmpty { return Theme.Colors.info }
        return Theme.Colors.warning
    }
    private var dataStatusTitle: String {
        if store.isScanning { return localizer.overviewScanningAgentData }
        if !allSessions.isEmpty { return localizer.overviewAgentSessionsLoaded }
        if !store.authorizedRoots.isEmpty { return localizer.overviewAuthorizedNoSessions }
        return localizer.overviewNoAgentFolders
    }
    private var dataStatusDetail: String {
        if store.isScanning { return localizer.overviewScanningDetail }
        if !allSessions.isEmpty { return localizedAggregationSummary }
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
    private var localizedAggregationSummary: String {
        switch localizer.language {
        case .simplifiedChinese:
            return "已聚合 \(allSessions.count) 个会话，其中 \(activeSessions.count) 个活跃，会话覆盖 \(projectRows.count) 个项目和 \(compactCount(totalTokens)) Token。"
        case .traditionalChinese:
            return "已彙總 \(allSessions.count) 個會話，其中 \(activeSessions.count) 個活躍，覆蓋 \(projectRows.count) 個專案和 \(compactCount(totalTokens)) Token。"
        case .japanese:
            return "\(allSessions.count) 件のセッション、うち \(activeSessions.count) 件がアクティブ、\(projectRows.count) 件のプロジェクト、\(compactCount(totalTokens)) トークンを集計しました。"
        case .korean:
            return "\(allSessions.count)개 세션 중 \(activeSessions.count)개 활성, \(projectRows.count)개 프로젝트, \(compactCount(totalTokens)) 토큰을 집계했습니다."
        case .english, .maltese:
            return "Grouped \(allSessions.count) sessions, \(activeSessions.count) active, \(projectRows.count) projects, and \(compactCount(totalTokens)) tokens."
        }
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
        VStack(spacing: 0) {
            if monitor.needsReauthorization { authorizationBanner }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    dataStatusCard
                    metricStrip

                    currentSessionUsageCard
                    sessionListCard

                    VStack(spacing: Theme.Spacing.md) {
                        projectCard
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
                .padding(Theme.Spacing.xl)
            }
            .background(Theme.Colors.sidebarBg.opacity(0.24))
        }
        .onAppear {
            onRefresh()
            normalizeSelection()
        }
        .onChange(of: store.sessions.map(\.id).joined(separator: "|")) { _ in
            normalizeSelection()
        }
        .onChange(of: filterText) { _ in
            visibleSessionCount = 24
            normalizeSelection()
        }
        .onChange(of: store.scannedRoots.joined(separator: "|")) { _ in
            authorizationStatus = localizedScanCoverageStatus
        }
        .sheet(isPresented: $showingSessionDetail) {
            if let session = selectedActiveSession ?? selectedSession {
                ActiveSessionDetailSheet(
                    session: session,
                    statusText: statusText(session.status),
                    statusColor: statusColor(session.status),
                    contextColor: contextColor(session.contextPercent),
                    displayLocation: displayLocation(for: session),
                    configRoot: configRoot(for: session),
                    shortSessionId: shortSessionId(session.sessionId),
                    windowText: windowText(session.contextWindow),
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

            Button { moveSelection(-1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(sessions.count < 2)
                .help(localizer.overviewPreviousSession)

            Button { moveSelection(1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(sessions.count < 2)
                .help(localizer.overviewNextSession)

            Button { copySelectedPath() } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedSession == nil)
                .help(localizer.copyPath)

            Button { openSelectedProject() } label: { Image(systemName: "folder") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedSession?.projectPath.isEmpty ?? true)
                .help(localizer.openInFinder)

            Button {
                authorizationStatus = localizer.overviewRescanning
                store.refresh(force: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
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
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
                Image(systemName: dataStatusIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(dataStatusColor)
                    .frame(width: 34, height: 34)
                    .background(dataStatusColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                VStack(alignment: .leading, spacing: 3) {
                    Text(dataStatusTitle)
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(dataStatusDetail)
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
                .buttonStyle(.bordered)
                .controlSize(.small)
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
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(Theme.Colors.warning)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(dataStatusColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var metricStrip: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 118), spacing: Theme.Spacing.sm), count: 5), spacing: Theme.Spacing.sm) {
            metricCard(icon: "rectangle.3.group", title: localizer.overviewSessions, value: "\(allSessions.count)", detail: localizer.overviewLiveAndHistory, color: Theme.Colors.success)
            metricCard(icon: "chart.bar.xaxis", title: localizer.overviewTokensTotal, value: compactCount(totalTokens), detail: localizer.overviewInputOutputCache, color: Theme.Colors.teal)
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
                        .foregroundStyle(color)
                        .frame(width: 20, height: 20)
                        .background(color.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
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
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(color.opacity(0.26), lineWidth: 1)
        )
    }

    private var currentSessionUsageCard: some View {
        dashboardCard(title: "\(localizer.currentSession) / \(localizer.overviewTokenUse)", icon: "chart.bar.xaxis", color: Theme.Colors.teal) {
            Button { showingSessionDetail = true } label: { Image(systemName: "sidebar.right") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedActiveSession == nil && selectedSession == nil)
                .help(localizer.agentSessionDetail)

            Button { moveSelection(-1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(activeSessions.count < 2)
                .help(localizer.overviewPreviousSession)

            Button { moveSelection(1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(activeSessions.count < 2)
                .help(localizer.overviewNextSession)

            Button { copySelectedPath() } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedSession == nil)
                .help(localizer.copyPath)

            Button { openSelectedProject() } label: { Image(systemName: "folder") }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedSession?.projectPath.isEmpty ?? true)
                .help(localizer.openInFinder)
        } content: {
            if let session = selectedActiveSession {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                                sessionField("AI", agentCode(session.agentName), width: 44, color: agentColor(session.agentName))
                                sessionField(localizer.overviewProject, session.projectName, width: 116)
                                sessionField(localizer.overviewSession, shortSessionId(session.sessionId), width: 84, color: Theme.Colors.warning)
                                sessionField(localizer.overviewLocation, displayLocation(for: session), width: 150)
                                sessionField(localizer.status, statusText(session.status), width: 64, color: statusColor(session.status))
                                sessionField(localizer.overviewModel, session.model, width: 86)
                                sessionField(localizer.contextWindow, "\(Int(session.contextPercent * 100))% / \(windowText(session.contextWindow))", width: 104, color: contextColor(session.contextPercent))
                                sessionField("token", compactCount(session.tokens.total), width: 70, color: Theme.Colors.teal)
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

    private var projectCard: some View {
        dashboardCard(title: localizer.overviewProjectContext, icon: "folder", color: Theme.Colors.info) {
            EmptyView()
        } content: {
            if projectRows.isEmpty {
                emptyState(icon: "folder", title: localizer.overviewNoProject, detail: localizer.overviewNoProjectHint)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    ForEach(projectRows.prefix(8), id: \.name) { row in
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

    private var sessionListCard: some View {
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
            if sessions.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    emptyState(icon: "dot.radiowaves.left.and.right", title: localizer.overviewNoSessions, detail: localizer.overviewNoSessionsHint)
                    Button {
                        monitor.requestAccessForStalePaths()
                    } label: {
                        Label(localizer.overviewAuthorizeAgentData, systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.xs) {
                        sessionTableHeader
                        ForEach(displayedSessions) { session in
                            sessionTableRow(session)
                        }
                        if visibleSessionCount < sessions.count {
                            Button {
                                visibleSessionCount = min(visibleSessionCount + 24, sessions.count)
                            } label: {
                                HStack {
                                    Spacer()
                                    Label(loadMoreOverviewSessionsText(remaining: sessions.count - visibleSessionCount), systemImage: "arrow.down.circle")
                                        .font(Theme.Font.captionMedium)
                                        .foregroundStyle(Theme.Colors.teal)
                                    Spacer()
                                }
                                .padding(Theme.Spacing.sm)
                                .background(Theme.Colors.sidebarBg.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(minWidth: 1120, alignment: .leading)
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
            tableHeader(localizer.overviewLocation, width: 116, alignment: .leading)
            tableHeader(localizer.overviewSummary, width: 260, alignment: .leading)
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

    private func sessionTableRow(_ session: AgentMonitorSessionSnapshot) -> some View {
        let selected = selectedSession?.id == session.id
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

                Text(displayLocation(for: session))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 116, alignment: .leading)

                Text(session.currentTask)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: 260, alignment: .leading)

                Text(statusText(session.status))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(statusColor(session.status))
                    .lineLimit(1)
                    .frame(width: 70, alignment: .leading)

                Text(session.model)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 96, alignment: .leading)

                Text("\(Int(session.contextPercent * 100))%")
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(contextColor(session.contextPercent))
                    .frame(width: 70, alignment: .trailing)

                Text(compactCount(session.tokens.total))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.teal)
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
            .background(selected ? Theme.Colors.accent.opacity(0.08) : Theme.Colors.sidebarBg.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(selected ? Theme.Colors.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
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
                    .foregroundStyle(color)
                    .frame(width: 26, height: 26)
                    .background(color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                Text(title)
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                actions()
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.cardBg.opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
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
            tokenRow(localizer.overviewTotal, value: session.tokens.total, total: max(session.tokens.total, 1), color: Theme.Colors.teal)
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
            .background(name == "Codex" ? Theme.Colors.teal : Theme.Colors.purple)
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
        if name.localizedCaseInsensitiveContains("codex") { return Theme.Colors.teal }
        if name.localizedCaseInsensitiveContains("claude") { return Theme.Colors.purple }
        if name.localizedCaseInsensitiveContains("opencode") { return Theme.Colors.success }
        return Theme.Colors.info
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

    private func windowText(_ window: Int) -> String {
        guard window > 0 else { return "—" }
        if window >= 1_000_000 { return String(format: "%.1fM", Double(window) / 1_000_000.0) }
        if window >= 1_000 { return String(format: "%.1fk", Double(window) / 1_000.0) }
        return "\(window)"
    }

    private func compactCount(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000.0) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000.0) }
        return "\(value)"
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
    let shortSessionId: String
    let windowText: String
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
                .foregroundStyle(Theme.Colors.teal)
                .frame(width: 38, height: 38)
                .background(Theme.Colors.teal.opacity(0.12))
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
            infoTile(localizer.overviewModel, session.model, Theme.Colors.textPrimary)
            infoTile(localizer.overviewProject, session.projectName, Theme.Colors.info)
            infoTile(localizer.overviewLocation, displayLocation, Theme.Colors.textPrimary)
            infoTile(localizer.contextWindow, "\(Int(session.contextPercent * 100))% / \(windowText)", contextColor)
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
                Text(compactCount(session.tokens.total))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.teal)
            }
            ProgressView(value: min(Double(session.tokens.total) / Double(max(session.contextWindow, 1)), 1))
                .progressViewStyle(.linear)
                .tint(Theme.Colors.teal)
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
            detailRow(title: "Source", value: session.sourcePath)
            detailRow(title: "Config", value: configRoot)
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
            .buttonStyle(.bordered)

            Button { onOpenProject() } label: {
                Label(localizer.openInFinder, systemImage: "folder")
            }
            .buttonStyle(.bordered)

            Spacer()

            Button { dismiss() } label: {
                Text(localizer.confirmBtn)
                    .frame(minWidth: 72)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.teal)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
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
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.teal)
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460, height: 300)
        .background(Theme.Colors.cardBg)
    }
}

struct OperationLogTab: View {
    @ObservedObject var monitor: OperationMonitor
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var service: ScannerService
    @State private var searchText = ""
    @State private var filterAgent = ""
    @State private var filterOpType: OperationRecord.OperationType?
    @State private var filterTimeRange: TimeRange = .all
    @State private var autoRefreshSeconds = 5
    @State private var lastAutoRefresh = Date.distantPast
    @State private var viewMode = 0
    @Namespace private var segmentNS

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

    var agentNames: [String] {
        Array(Set(allOperationRecords.filter(isDisplayableAgentRecord).map(\.agentName))).sorted()
    }

    var filteredRecords: [OperationRecord] {
        var result = allOperationRecords.filter(isDisplayableAgentRecord)
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

    private var displayedRecords: [OperationRecord] {
        Array(filteredRecords.prefix(1000))
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
        let recentAgents = Set(allOperationRecords.filter { isDisplayableAgentRecord($0) && Date().timeIntervalSince($0.timestamp) < 3600 }.map(\.agentName)).count
        return Double(recentAgents) / Double(agentNames.count)
    }

    private var todayRecordCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return allOperationRecords.filter { isDisplayableAgentRecord($0) && $0.timestamp >= start }.count
    }

    private var hourRecordCount: Int {
        allOperationRecords.filter { isDisplayableAgentRecord($0) && Date().timeIntervalSince($0.timestamp) < 3600 }.count
    }

    private var allOperationRecords: [OperationRecord] {
        let records = service.operationRecords.isEmpty ? monitor.records : service.operationRecords
        // `OperationMonitor` keeps records in newest-first order already.
        return records
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

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "eye.fill",
                title: localizer.agentMonitorTitle,
                subtitle: localizer.agentMonitorSubtitle,
                color: .green
            ) {
                HStack(spacing: 8) {
                    Button { refreshAgentMonitor() } label: {
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

            HStack(spacing: Theme.Spacing.sm) {
                StatCardView(
                    icon: "list.bullet.clipboard",
                    iconColor: Theme.Colors.info,
                    title: localizer.totalOps,
                    value: "\(allOperationRecords.count)",
                    subtitle: nil
                )
                StatCardView(
                    icon: "sun.max",
                    iconColor: Theme.Colors.warning,
                    title: localizer.timeToday,
                    value: "\(todayRecordCount)",
                    subtitle: nil
                )
                StatCardView(
                    icon: "clock",
                    iconColor: Theme.Colors.success,
                    title: localizer.time1h,
                    value: "\(hourRecordCount)",
                    subtitle: nil
                )
                StatCardView(
                    icon: "cpu",
                    iconColor: Theme.Colors.purple,
                    title: localizer.unitAgent,
                    value: "\(agentNames.count)",
                    subtitle: nil
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

                if viewMode == 1 {
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
                liveView
            default:
                targetedView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                service.ensureAgentGuardDataPipeline()
                refreshAgentMonitor()
            }
            monitor.loadCurated()
            if monitor.autoCurationInterval > 0 { service.startAutoCuration() }
        }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { now in
            guard viewMode == 0, autoRefreshSeconds > 0 else { return }
            guard now.timeIntervalSince(lastAutoRefresh) >= Double(autoRefreshSeconds) else { return }
            lastAutoRefresh = now
            refreshAgentMonitor()
        }
    }

    private func refreshAgentMonitor() {
        service.refreshOperationRecordsSnapshot()
        service.importKnownAgentHistory()
        monitor.loadCurated()
    }

    private var modeSelector: some View {
        HStack(spacing: 0) {
            modeButton(title: localizer.liveMonitor, mode: 0)
            modeButton(title: localizer.audit, mode: 1)
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
                            .fill(Theme.Colors.teal)
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

    private var liveView: some View {
        VStack(spacing: 0) {
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
                    let content = service.guardFeature.exportRecordsAsCSV(records: filteredRecords)
                    _ = service.guardFeature.saveExport(content: content, filename: "agent-monitor-records.csv")
                } label: {
                    Label(localizer.exportCSV, systemImage: "square.and.arrow.up")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(filteredRecords.isEmpty)

                Button {
                    let content = service.guardFeature.exportRecordsAsJSON(records: filteredRecords)
                    _ = service.guardFeature.saveExport(content: content, filename: "agent-monitor-records.json")
                } label: {
                    Label(localizer.exportJSON, systemImage: "doc.text")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(filteredRecords.isEmpty)

                Text("\(displayedRecords.count)/\(filteredRecords.count) \(localizer.recordsCount)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.sidebarBg.opacity(0.3))

            Divider()

            if displayedRecords.isEmpty {
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
                        ForEach(displayedRecords) { record in
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
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000.0) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000.0) }
        return "\(value)"
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
    @StateObject private var sessionScanner = AgentSessionScanner()
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
            isCustom: true,
            isVSCodeType: isVSCode,
            parser: { [sessionScanner] url, agentName in
                let ext = url.pathExtension
                if ext == "vscdb" {
                    return sessionScanner.parseVscdbSQLite(url: url, agentName: agentName)
                } else if ext == "json" && url.path.contains("file-changes") {
                    return sessionScanner.parseFileChangesJSON(url: url, agentName: agentName)
                } else if ext == "db" {
                    return sessionScanner.parseGenericJSONL(url: url, agentName: agentName)
                } else if ext == "sqlite" {
                    return sessionScanner.parseGenericJSONL(url: url, agentName: agentName)
                } else {
                    return sessionScanner.parseGenericJSONL(url: url, agentName: agentName)
                }
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
                isCustom: true,
                isVSCodeType: isVSCode,
                parser: { [sessionScanner] url, agentName in
                    let ext = url.pathExtension
                    if ext == "vscdb" {
                        return sessionScanner.parseVscdbSQLite(url: url, agentName: agentName)
                    } else if ext == "json" && url.path.contains("file-changes") {
                        return sessionScanner.parseFileChangesJSON(url: url, agentName: agentName)
                    } else {
                        return sessionScanner.parseGenericJSONL(url: url, agentName: agentName)
                    }
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
                            sessionScanner.isScanning = true
                            Task { sessionScanner.scanAllAgents() }
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
                                                sessionScanner.scanAllAgents()
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
                                            sessionScanner.isScanning = true
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
                sessionScanner.isScanning = true
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
                isCustom: true,
                isVSCodeType: isVSCode,
                parser: { [sessionScanner] url, agentName in
                    let ext = url.pathExtension
                    if ext == "vscdb" {
                        return sessionScanner.parseVscdbSQLite(url: url, agentName: agentName)
                    } else if ext == "json" && url.path.contains("file-changes") {
                        return sessionScanner.parseFileChangesJSON(url: url, agentName: agentName)
                    } else if ext == "db" {
                        return sessionScanner.parseGenericJSONL(url: url, agentName: agentName)
                    } else if ext == "sqlite" {
                        return sessionScanner.parseGenericJSONL(url: url, agentName: agentName)
                    } else {
                        return sessionScanner.parseGenericJSONL(url: url, agentName: agentName)
                    }
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
            if localizer.language == .english {
                aiSummary = "Local analysis for \(agentName): \(records.count) audit records. Operation mix: \(opCounts). Main touched paths:\n\(topFiles)\nRecommendation: review write/delete operations before approving broad file access."
            } else {
                aiSummary = "本地分析：Agent「\(agentName)」共有 \(records.count) 条审计记录。操作分布：\(opCounts)。高频文件：\n\(topFiles)\n建议：重点复核写入、删除和执行类操作，再批准大范围文件访问。"
            }
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
                        .background(selectedTab == tab.0 ? Theme.Colors.teal.opacity(0.12) : Color.clear)
                        .foregroundStyle(selectedTab == tab.0 ? Theme.Colors.teal : Theme.Colors.textSecondary)
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
                        .background(Theme.Gradients.success)
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
                    .tint(.green)
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
    @State private var selectedIds = Set<String>()
    @State private var filterCategory = ""
    @State private var filterApp = ""
    @State private var filterRisk = ""
    @State private var filterSource = ""
    @State private var showSettings = false
    @State private var showDeleteConfirm = false
    @State private var deleteTargetIds: [String] = []
    @State private var showCleanResult = false
    @State private var cleanedSize: Int64 = 0
    @State private var cleanedCount = 0
    @State private var searchText = ""

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
    var totalCleanable: Int64 { filteredItems.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { filteredItems.filter { selectedIds.contains($0.id) }.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "arrow.down.doc.fill",
                title: localizer.macCleanerTitle,
                subtitle: localizer.macCleanerSubtitle,
                color: .blue
            ) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button { Task { await service.scanLocal() } } label: {
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

                    Button { Task { await service.startEnhancedScan() } } label: {
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
                    Button { smartClean() } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "wand.and.stars")
                            Text(localizer.smartClean)
                        }
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Gradients.success)
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

                        Button { confirmDeleteSelected() } label: {
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
            SettingsView()
                .environmentObject(service)
                .environmentObject(localizer)
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
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.success)

                Text(localizer.cleanComplete)
                    .font(Theme.Font.title2Bold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                CardView(padding: Theme.Spacing.xl, cornerRadius: Theme.Radius.lg) {
                    VStack(spacing: Theme.Spacing.md) {
                        Text(service.formatSize(cleanedSize))
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.success)

                        Text("\(localizer.total) \(cleanedCount) \(localizer.itemsLabel)")
                            .font(Theme.Font.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: 240)
                }

                Button { showCleanResult = false } label: {
                    Text(localizer.ok)
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(.white)
                        .frame(width: 120)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(Theme.Gradients.success)
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
                            CompactStatItem(icon: "sparkles", iconColor: Theme.Colors.cyan, title: localizer.releasable, value: service.formatSize(totalCleanable))
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.md)
                .background(Theme.Colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xs)
            }
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
                ) { Task { await service.scanLocal() } }
                ScanActionCard(
                    icon: "bolt.fill",
                    title: localizer.enhancedScan,
                    subtitle: localizer.enhancedScanSubtitle,
                    iconColor: Theme.Colors.warning,
                    isDisabled: service.isEnhancedScanning
                ) { Task { await service.startEnhancedScan() } }
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
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                HStack(spacing: Theme.Spacing.md) {
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
                    Spacer()
                    Text(localizer.actionCol)
                        .frame(width: ResultListColumns.actions, alignment: .center)
                }
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textTertiary)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Colors.sidebarBg.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                ForEach(filteredItems) { item in
                    HStack(spacing: Theme.Spacing.md) {
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
                            .foregroundStyle(Theme.Colors.cyan)
                            .frame(width: ResultListColumns.size, alignment: .trailing)

                        Text(item.reason ?? item.riskDesc)
                            .font(Theme.Font.caption)
                            .foregroundStyle(item.sourceType == .ai ? Theme.Colors.purple : Theme.Colors.warning)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: ResultListColumns.description, alignment: .leading)
                            .help(item.reason ?? item.riskDesc)

                        Spacer()

                        HStack(spacing: Theme.Spacing.xs) {
                            Button { confirmDeleteSingle(item) } label: {
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
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.vertical, Theme.Spacing.md)
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
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.vertical, Theme.Spacing.sm)
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
        let targets = service.scanItems.filter { deleteTargetIds.contains($0.id) }
        Task {
            let result = await service.deleteItems(ids: deleteTargetIds)
            let succeededIds = Set((result.results ?? []).filter { $0.success == true }.compactMap { $0.id })
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
            showCleanResult = true
        }
    }
    private func ignoreSelected() { service.ignoreItems(ids: Array(selectedIds)); selectedIds.removeAll() }
    private func toggleIgnore(_ item: ScanItem) { if item.ignored { service.unignoreItems(ids: [item.id]) } else { service.ignoreItems(ids: [item.id]) } }
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
                .foregroundStyle(Theme.Colors.cyan)
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
                    SensorFilterChip(label: localizer.microphone, icon: "mic.fill", color: .blue, isActive: filterType == .microphone) { filterType = .microphone }
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
