import SwiftUI
import AppKit

struct ContentView: View {
    @State private var selectedTab: NavItem = .operations
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @State private var showSettings = false
    @State private var sidebarCollapsed = false
    @State private var hoveredItem: NavItem?
    @AppStorage("networkMode") private var networkMode = "internet"

    enum NavItem: String, CaseIterable {
        case operations = "Agent 监控"
        case cleaner = "Mac 清理"
        case app = "APP 管理"
        case dependency = "依赖管理"
        case other = "其它工具"
        case migration = "适配检测"

        var icon: String {
            switch self {
            case .cleaner: "arrow.down.doc.fill"
            case .app: "app.badge"
            case .dependency: "cube.box"
            case .other: "terminal"
            case .operations: "cpu"
            case .migration: "arrow.triangle.2.circlepath"
            }
        }

        var color: Color {
            switch self {
            case .cleaner: .blue
            case .app: .cyan
            case .dependency: .orange
            case .other: .gray
            case .operations: .green
            case .migration: .purple
            }
        }

        func label(_ localizer: Localizer) -> String {
            switch self {
            case .cleaner: localizer.navCleaner
            case .app: localizer.navApp
            case .dependency: localizer.navDependency
            case .other: localizer.navOther
            case .operations: localizer.navOperations
            case .migration: localizer.navMigration
            }
        }

        func subtitle(_ localizer: Localizer) -> String {
            switch self {
            case .cleaner: localizer.subCleaner
            case .app: localizer.subApp
            case .dependency: localizer.subDependency
            case .other: localizer.subOther
            case .operations: localizer.subOperations
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
        .onAppear { service.refreshDiskInfo() }
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
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.Gradients.accent)
                    Text(localizer.t("Agent守护", en: "AgentGuard"))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.Gradients.accent)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: Theme.Sidebar.iconSize, weight: .semibold))
                    .foregroundStyle(Theme.Gradients.accent)
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

            ForEach(NavItem.allCases, id: \.self) { item in
                Button {
                    selectedTab = item
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
        .padding(.horizontal, sidebarCollapsed ? Theme.Spacing.xs : Theme.Spacing.sm)
    }

    private func sidebarExpandedItem(_ item: NavItem) -> some View {
        HStack(spacing: Theme.Spacing.sm + 2) {
            RoundedRectangle(cornerRadius: 2)
                .fill(selectedTab == item ? item.color : Color.clear)
                .frame(width: 3, height: Theme.Sidebar.itemHeight * 0.5)

            Image(systemName: item.icon)
                .font(.system(size: Theme.Sidebar.iconSize * 0.65, weight: selectedTab == item ? .semibold : .medium))
                .foregroundStyle(selectedTab == item ? item.color : (hoveredItem == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary))
                .frame(width: Theme.Sidebar.iconSize)

            Text(item.label(localizer))
                .font(.system(size: 13))
                .fontWeight(selectedTab == item ? .semibold : .regular)
                .foregroundStyle(selectedTab == item ? Theme.Colors.textPrimary : (hoveredItem == item ? Theme.Colors.textPrimary : Theme.Colors.textSecondary))

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
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .fill(Theme.Colors.cardHover)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(localizer.expandSidebar)

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .fill(Theme.Colors.cardHover)
                            )
                    }
                    .buttonStyle(.plain)

                    languageToggleButton

                    networkStatusBadge

                    Text("v\(service.currentVersion)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(.vertical, Theme.Spacing.lg)
            } else {
                VStack(spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.md) {
                        Button { showSettings = true } label: {
                            HStack(spacing: Theme.Spacing.xs + 1) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 11))
                                Text(localizer.settings)
                                    .font(.system(size: 11))
                            }
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs + 1)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .fill(Theme.Colors.cardHover)
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        languageToggleButton

                        networkStatusBadge
                    }

                    HStack(spacing: Theme.Spacing.md) {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                sidebarCollapsed = true
                            }
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 10, weight: .medium))
                                Text(localizer.collapseSidebar)
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(
                                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                    .fill(Theme.Colors.cardHover)
                            )
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        HStack(spacing: Theme.Spacing.xs) {
                            Circle()
                                .fill(Theme.Colors.success)
                                .frame(width: 5, height: 5)
                            Text("v\(service.currentVersion)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.lg)
            }
        }
    }

    private var languageToggleButton: some View {
        Button {
            withAnimation(.none) {
                localizer.language = localizer.language == .chinese ? .english : .chinese
            }
        } label: {
            Text(localizer.language == .chinese ? "EN" : "中")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .padding(.horizontal, sidebarCollapsed ? 6 : 8)
                .padding(.vertical, 2)
                .background(
                    Capsule()
                        .fill(Theme.Colors.accent.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .help(localizer.language == .chinese ? "Switch to English" : "切换到中文")
    }

    private var networkStatusBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: networkMode == "internet" ? "globe" : "lock.shield")
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

struct OperationLogTab: View {
    @ObservedObject var monitor: OperationMonitor
    @EnvironmentObject var localizer: Localizer
    @EnvironmentObject var service: ScannerService
    @State private var searchText = ""
    @State private var filterAgent = ""
    @State private var filterOpType: OperationRecord.OperationType?
    @State private var filterTimeRange: TimeRange = .all
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
        Array(Set(monitor.records.map(\.agentName))).sorted()
    }

    var filteredRecords: [OperationRecord] {
        var result = monitor.records
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
        return result
    }

    private var agentActivityProgress: Double {
        guard !agentNames.isEmpty else { return 0 }
        let recentAgents = Set(monitor.records.filter { Date().timeIntervalSince($0.timestamp) < 3600 }.map(\.agentName)).count
        return Double(recentAgents) / Double(agentNames.count)
    }

    private var todayRecordCount: Int {
        let start = Calendar.current.startOfDay(for: Date())
        return monitor.records.filter { $0.timestamp >= start }.count
    }

    private var hourRecordCount: Int {
        monitor.records.filter { Date().timeIntervalSince($0.timestamp) < 3600 }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "cpu",
                title: localizer.agentMonitorTitle,
                subtitle: localizer.agentMonitorSubtitle,
                color: .green
            ) {
                HStack(spacing: 8) {
                    Button { monitor.start() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: monitor.isMonitoring ? "record.circle.fill" : "record.circle")
                            Text(monitor.isMonitoring ? localizer.monitoring : localizer.startMonitoring)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(monitor.isMonitoring ? .green : .blue)
                    .disabled(monitor.isMonitoring)

                    Button { monitor.clearRecords() } label: {
                        HStack(spacing: 3) { Image(systemName: "trash"); Text(localizer.clear) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                DashboardGrid(columns: 4) {
                    StatCardView(
                        icon: "list.bullet.clipboard",
                        iconColor: Theme.Colors.info,
                        title: localizer.totalOps,
                        value: "\(monitor.records.count)",
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
                    CardView {
                        VStack(spacing: Theme.Spacing.sm) {
                            ProgressRing(
                                progress: agentActivityProgress,
                                lineWidth: 6,
                                size: 60,
                                color: Theme.Colors.purple
                            )
                            Text("\(agentNames.count) \(localizer.unitAgent)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.md)
            }

            if monitor.isMonitoring {
                HStack(spacing: Theme.Spacing.sm) {
                    Circle().fill(Theme.Colors.success).frame(width: 6, height: 6)
                    Text(localizer.monitoring).font(Theme.Font.caption).foregroundColor(Theme.Colors.success)
                    Text("·").foregroundColor(Theme.Colors.textTertiary)
                    Text("\(monitor.records.count) \(localizer.records)").font(Theme.Font.caption).foregroundColor(Theme.Colors.textTertiary)
                    Spacer()
                    if monitor.aiSelfLearningEnabled {
                        PillBadge(text: localizer.aiLearning, color: Theme.Colors.purple)
                    }
                    Button {
                        if monitor.aiSelfLearningEnabled {
                            service.stopAISelfLearning()
                        } else {
                            service.startAISelfLearning()
                        }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                            Text(monitor.aiSelfLearningEnabled ? localizer.closeAI : localizer.aiAnalysis)
                                .font(Theme.Font.caption)
                        }
                        .foregroundColor(monitor.aiSelfLearningEnabled ? Theme.Colors.purple : Theme.Colors.textTertiary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.Colors.purple.opacity(monitor.aiSelfLearningEnabled ? 0.1 : 0.05))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.xs + 1)
                .background(Theme.Colors.success.opacity(0.05))
            }

            HStack(spacing: Theme.Spacing.lg) {
                HStack(spacing: 0) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) { viewMode = 0 }
                    } label: {
                        Text(localizer.liveMonitor)
                            .font(Theme.Font.captionMedium)
                            .foregroundColor(viewMode == 0 ? .white : Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.sm - 2)
                            .background {
                                if viewMode == 0 {
                                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                        .fill(Theme.Gradients.accent)
                                        .matchedGeometryEffect(id: "segment", in: segmentNS)
                                }
                            }
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.spring(duration: 0.3)) { viewMode = 1 }
                    } label: {
                        Text(localizer.audit)
                            .font(Theme.Font.captionMedium)
                            .foregroundColor(viewMode == 1 ? .white : Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.vertical, Theme.Spacing.sm - 2)
                            .background {
                                if viewMode == 1 {
                                    RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                        .fill(Theme.Gradients.accent)
                                        .matchedGeometryEffect(id: "segment", in: segmentNS)
                                }
                            }
                    }
                    .buttonStyle(.plain)
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

            if viewMode == 0 {
                liveView
            } else {
                targetedView
            }
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            if !monitor.isMonitoring { monitor.start() }
            monitor.loadCurated()
            if monitor.autoCurationInterval > 0 { service.startAutoCuration() }
        }
    }

    private var liveView: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                FilterSearchBar(placeholder: localizer.searchFiles, text: $searchText)
                    .frame(width: 200)

                Picker(localizer.agentLabel, selection: $filterAgent) {
                    Text(localizer.allAgents).tag("")
                    ForEach(agentNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()

                Picker(localizer.opTypeLabel, selection: $filterOpType) {
                    Text(localizer.allTypes).tag(nil as OperationRecord.OperationType?)
                    ForEach(OperationRecord.OperationType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type as OperationRecord.OperationType?)
                    }
                }
                .labelsHidden()

                Picker(localizer.timeRange, selection: $filterTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { Text($0.label(localizer)).tag($0) }
                }
                .labelsHidden()

                Spacer()

                Text("\(filteredRecords.count) \(localizer.recordsCount)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.md)
            .background(Theme.Colors.sidebarBg.opacity(0.3))

            Divider()

            if filteredRecords.isEmpty {
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
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.sm) {
                        ForEach(filteredRecords) { record in
                            HStack(spacing: Theme.Spacing.md) {
                                Text(record.timestamp, style: .time)
                                    .font(Theme.Font.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .frame(width: 60, alignment: .leading)

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
                                    text: record.operationType.rawValue,
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

                                if record.fileSize > 0 {
                                    Text(ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file))
                                        .font(Theme.Font.caption)
                                        .monospacedDigit()
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                        .frame(width: 60, alignment: .trailing)
                                }
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
                        Text(record.timestamp, style: .time)
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

    private func saveCustomAgentSource(_ source: CustomAgentSource) {
        var sources = customAgentSources
        if let idx = sources.firstIndex(where: { $0.name == source.name }) {
            sources[idx] = source
        } else {
            sources.append(source)
        }
        customAgentSourcesData = (try? JSONEncoder().encode(sources)) ?? Data()
        let home = NSHomeDirectory()
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

    private func addAgentAndSearch(_ app: AppInfo) {
        let dirs = sessionScanner.searchJSONLDirs(forAgentName: app.displayName, bundlePath: app.appPath)
        var finalPaths: [String]
        if dirs.isEmpty {
            let home = NSHomeDirectory()
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
        var result = sessionScanner.opRecords
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

                        Button {
                            generateAISummary()
                        } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                if isGeneratingSummary {
                                    ProgressView().controlSize(.mini).scaleEffect(0.7)
                                } else {
                                    Image(systemName: "wand.and.stars").font(.system(size: 9))
                                }
                                Text(isGeneratingSummary ? localizer.aiAnalyzing : localizer.aiAnalysis)
                                    .font(Theme.Font.caption)
                            }
                            .foregroundColor(Theme.Colors.purple)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(Theme.Colors.purple)
                        .disabled(isGeneratingSummary || service.aiConfig?.hasKey != true)
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
                            .frame(width: 110)

                            let auditOpTypes = Array(Set(sessionScanner.opRecords.map(\.opType))).sorted()
                            Picker(localizer.opTypeLabel, selection: $auditFilterOpType) {
                                Text(localizer.allTypes).tag("")
                                ForEach(auditOpTypes, id: \.self) { t in
                                    Text(t).tag(t)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 110)

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

                    Divider()

                    VStack(spacing: Theme.Spacing.sm) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Image(systemName: "plus.circle").font(.system(size: 11)).foregroundColor(Theme.Colors.success)
                            Text(localizer.addCustomAgent).font(Theme.Font.captionMedium).foregroundStyle(Theme.Colors.success)
                            Spacer()
                        }

                        if !allMonitorableApps.isEmpty {
                            Button {
                                showAddAgentSheet = true
                            } label: {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: "app.badge.plus")
                                    Text(localizer.selectFromInstalled)
                                }
                                .font(Theme.Font.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        HStack(spacing: Theme.Spacing.sm) {
                            TextField(localizer.customAgentName, text: $customAgentName)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.Font.caption)
                                .frame(width: 100)

                            TextField(localizer.sessionPathHint, text: $customAgentPath)
                                .textFieldStyle(.roundedBorder)
                                .font(Theme.Font.caption)

                            Button {
                                let name = customAgentName.trimmingCharacters(in: .whitespaces)
                                guard !name.isEmpty else { return }
                                let existingNames = Set(sessionScanner.discoveredAgents.map(\.name))
                                guard !existingNames.contains(name) else { return }
                                let dirs = sessionScanner.searchJSONLDirs(forAgentName: name, bundlePath: nil)
                                var paths: [String]
                                if !customAgentPath.isEmpty {
                                    paths = [customAgentPath]
                                } else if !dirs.isEmpty {
                                    paths = dirs
                                } else {
                                    let home = NSHomeDirectory()
                                    let lower = name.lowercased().replacingOccurrences(of: " ", with: "")
                                    paths = [home + "/.\(lower)", home + "/Library/Application Support/\(name)", home + "/.config/\(lower)"]
                                }
                                saveCustomAgentSource(CustomAgentSource(name: name, searchPaths: paths, addedAt: Date()))
                                customAgentName = ""
                                customAgentPath = ""
                            } label: {
                                HStack(spacing: Theme.Spacing.xs) {
                                    Image(systemName: "plus.circle.fill")
                                    Text(localizer.addAndScan)
                                }
                                .font(Theme.Font.caption)
                                .foregroundColor(.white)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.xs + 1)
                                .background(Theme.Gradients.success)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(customAgentName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Colors.sidebarBg.opacity(0.3))
                }
            }
        }
        .sheet(isPresented: $showAddAgentSheet) {
            AddAgentFromAppsSheet(
                apps: allMonitorableApps,
                existingNames: Set(sessionScanner.discoveredAgents.map(\.name)),
                onAdd: { app in
                    addAgentAndSearch(app)
                    showAddAgentSheet = false
                }
            )
        }
        .onAppear {
            loadCustomAgentSources()
        }
    }

    private func loadCustomAgentSources() {
        let sources = customAgentSources
        let home = NSHomeDirectory()
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
        guard let config = service.aiConfig, config.hasKey == true else { return }
        let records = auditFilteredRecords
        guard !records.isEmpty else { return }
        isGeneratingSummary = true
        aiSummary = ""

        Task {
            let agentName = records.first?.agentName ?? localizer.unknownAgent
            var opSummary: [String: Int] = [:]
            var fileSummary: [String: Int] = [:]
            var recentOps: [String] = []

            for rec in records {
                opSummary[rec.opType, default: 0] += 1
                if !rec.targetPath.isEmpty {
                    fileSummary[rec.targetPath, default: 0] += 1
                }
            }

            for rec in records.prefix(30) {
                recentOps.append("[\(timeStr(rec.timestamp))] \(rec.opType): \(rec.targetPath)")
            }

            let topFiles = fileSummary.sorted { $0.value > $1.value }.prefix(10).map { "\($0.key) (\($0.value)\(localizer.timesUnit))" }.joined(separator: "\n")
            let opCounts = opSummary.map { "\($0.key): \($0.value)\(localizer.timesUnit)" }.joined(separator: ", ")

            let prompt = """
            你是一个系统安全分析专家。以下是 Agent「\(agentName)」在本机的操作审计记录，请分析总结：

            操作统计: \(opCounts)
            总操作数: \(records.count)

            高频操作文件 TOP10:
            \(topFiles)

            最近操作记录:
            \(recentOps.joined(separator: "\n"))

            请用中文总结：
            1. 这个 Agent 主要在做什么？
            2. 有哪些高风险操作（写入敏感目录、删除文件、执行危险命令）？
            3. 文件操作的主要影响范围（哪些项目/目录被影响）
            4. 安全建议

            请简洁明了，不要用markdown格式。
            """

            let apiBase = (config.apiBase ?? "https://api.deepseek.com").trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: "\(apiBase)/v1/chat/completions"),
                  let apiKey = config.apiKey else {
                aiSummary = localizer.apiConfigInvalid
                isGeneratingSummary = false
                return
            }

            let body: [String: Any] = [
                "model": config.model ?? "deepseek-chat",
                "messages": [["role": "user", "content": prompt]],
                "temperature": 0.3,
                "max_tokens": 2048,
            ]

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 120
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    aiSummary = localizer.apiRequestFailed
                    isGeneratingSummary = false
                    return
                }
                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let choices = json["choices"] as? [[String: Any]],
                      let content = choices.first?["message"] as? [String: Any],
                      let result = content["content"] as? String else {
                    aiSummary = localizer.aiFormatError
                    isGeneratingSummary = false
                    return
                }
                aiSummary = result
                isGeneratingSummary = false
            } catch {
                aiSummary = "\(localizer.requestFailed): \(error.localizedDescription)"
                isGeneratingSummary = false
            }
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
        case "写入", "Write": .red
        case "编辑", "Edit": .orange
        case "读取", "Read": .blue
        case "删除", "Delete": .red
        case "执行命令", "Execute": .purple
        case "搜索", "Search": .cyan
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
        }
    }
}

struct AddAgentFromAppsSheet: View {
    let apps: [AppInfo]
    let existingNames: Set<String>
    let onAdd: (AppInfo) -> Void
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var localizer: Localizer
    @State private var searchText: String = ""
    @State private var selectedApp: AppInfo?

    private var filteredApps: [AppInfo] {
        if searchText.isEmpty { return apps }
        return apps.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText) ||
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(localizer.selectAgentToAdd)
                    .font(.headline)
                Spacer()
                Button(localizer.cancelBtn) { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding(16)

            Divider()

            TextField(localizer.searchingPlaceholder, text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            if filteredApps.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text(localizer.noMatchingApp).foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { selectedApp?.id },
                    set: { id in
                        if let id = id, let app = apps.first(where: { $0.id == id }) {
                            selectedApp = app
                        }
                    }
                )) {
                    ForEach(filteredApps) { app in
                        HStack(spacing: 8) {
                            if let iconPath = app.iconPath, let img = NSImage(contentsOfFile: iconPath) {
                                Image(nsImage: img)
                                    .resizable()
                                    .frame(width: 20, height: 20)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            } else {
                                Image(systemName: "app.fill")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                                    .frame(width: 20, height: 20)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(app.displayName)
                                        .font(.body)
                                        .fontWeight(.medium)
                                    if existingNames.contains(app.displayName) {
                                        Text(localizer.alreadyAdded)
                                            .font(.system(size: 9))
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 3)
                                            .background(Color.green.opacity(0.1))
                                            .cornerRadius(2)
                                    }
                                }
                                HStack(spacing: 4) {
                                    Text(app.subCategory)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                    Text("·").foregroundColor(.secondary)
                                    Text(app.name)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .tag(app.id)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                if let app = selectedApp {
                    Text("\(localizer.selected): \(app.displayName)")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text(localizer.selectAppFromList)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    if let app = selectedApp {
                        if existingNames.contains(app.displayName) { return }
                        onAdd(app)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text(localizer.addAndScan)
                    }
                    .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .tint(.green)
                .disabled(selectedApp == nil || (selectedApp != nil && existingNames.contains(selectedApp!.displayName)))
            }
            .padding(16)
        }
        .frame(minWidth: 500, minHeight: 400)
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
                Text(op.timestamp, style: .time).font(.caption2).monospacedDigit()
            }.width(60)
            TableColumn(localizer.colProcess) { op in
                HStack(spacing: 3) {
                    Text(op.processComm).font(.caption).fontWeight(.medium).lineLimit(1)
                    Text("(\(String(op.processPid)))").font(.system(size: 9)).foregroundColor(.secondary)
                }
            }.width(min: 100)
            TableColumn(localizer.opCol) { op in
                HStack(spacing: 3) {
                    Image(systemName: op.opType == "修改" || op.opType == "Modify" ? "pencil" : op.opType == "打开" || op.opType == "Open" ? "plus.circle" : "xmark.circle")
                        .font(.caption2).foregroundColor(op.opType == "修改" || op.opType == "Modify" ? .blue : op.opType == "打开" || op.opType == "Open" ? .green : .red)
                    Text(op.opType).font(.caption2)
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

                    Button { Task { await performAiScan() } } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "brain")
                                .font(.system(size: 14, weight: .semibold))
                            Text(localizer.aiScan)
                                .font(Theme.Font.subheadlineMedium)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.sm)
                        .background(LinearGradient(
                            colors: [Color.purple.opacity(0.8), Color.pink.opacity(0.6)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isAiScanning)
                    .opacity(service.isAiScanning ? 0.5 : 1)

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
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
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
                CardView(padding: Theme.Spacing.lg, cornerRadius: Theme.Radius.lg) {
                    HStack(spacing: Theme.Spacing.xl) {
                        VStack(spacing: Theme.Spacing.sm) {
                            ProgressRing(
                                progress: disk.usedPct / 100.0,
                                lineWidth: 12,
                                size: 120,
                                showLabel: true
                            )
                            Text(localizer.diskSpaceLabel)
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        DashboardGrid(columns: 2) {
                            StatCardView(
                                icon: "internaldrive",
                                iconColor: Theme.Colors.info,
                                title: localizer.totalCapacity,
                                value: String(format: "%.0f GB", disk.totalGb),
                                subtitle: nil
                            )
                            StatCardView(
                                icon: "arrow.down.circle.fill",
                                iconColor: Theme.Colors.warning,
                                title: localizer.usedLabel,
                                value: String(format: "%.0f GB", disk.usedGb),
                                subtitle: String(format: "%.1f%%", disk.usedPct)
                            )
                            StatCardView(
                                icon: "arrow.up.circle.fill",
                                iconColor: disk.freeGb < 20 ? Theme.Colors.danger : Theme.Colors.success,
                                title: localizer.available,
                                value: String(format: "%.0f GB", disk.freeGb),
                                subtitle: nil
                            )
                            StatCardView(
                                icon: "sparkles",
                                iconColor: Theme.Colors.cyan,
                                title: localizer.releasable,
                                value: service.formatSize(totalCleanable),
                                subtitle: nil
                            )
                        }

                        Spacer()
                    }
                }
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.vertical, Theme.Spacing.sm)
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
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 48))
                    .foregroundStyle(Theme.Colors.accent.opacity(0.6))
                Text(localizer.t("Agent守护", en: "AgentGuard"))
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
                    icon: "brain",
                    title: localizer.aiScan,
                    subtitle: localizer.aiScanSubtitle,
                    iconColor: Theme.Colors.purple,
                    isDisabled: service.isAiScanning
                ) { Task { await performAiScan() } }
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

                        if item.ignored {
                            Image(systemName: "eye.slash")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }

                        Text(item.name)
                            .font(Theme.Font.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                            .frame(width: 160, alignment: .leading)

                        PillBadge(
                            text: item.sourceType.localizedLabel(localizer),
                            color: item.sourceType == .ai ? Theme.Colors.purple : Theme.Colors.info,
                            size: .small
                        )
                        .frame(width: 60, alignment: .center)

                        Text(item.app)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                            .frame(width: 90, alignment: .leading)

                        PillBadge(
                            text: item.riskLevel.localizedLabel(localizer),
                            color: riskColor(item.riskLevel),
                            size: .small
                        )
                        .frame(width: 60, alignment: .center)

                        Text(service.formatSize(item.size))
                            .font(Theme.Font.subheadlineMedium)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Colors.cyan)
                            .frame(width: 70, alignment: .trailing)

                        Text(item.reason ?? item.riskDesc)
                            .font(Theme.Font.caption)
                            .foregroundStyle(item.sourceType == .ai ? Theme.Colors.purple : Theme.Colors.warning)
                            .lineLimit(1)
                            .frame(maxWidth: 180, alignment: .leading)

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
    private func performAiScan() async { if service.aiConfig?.hasKey != true { showSettings = true; return }; await service.startAiScan() }
    private func confirmDeleteSelected() { deleteTargetIds = Array(selectedIds); showDeleteConfirm = true }
    private func confirmDeleteSingle(_ item: ScanItem) { deleteTargetIds = [item.id]; showDeleteConfirm = true }
    private func performDelete() { let s = service.scanItems.filter { deleteTargetIds.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }; let c = deleteTargetIds.count; Task { let _ = await service.deleteItems(ids: deleteTargetIds, permanent: true); service.removeScannedItems(ids: deleteTargetIds); selectedIds.subtract(deleteTargetIds); deleteTargetIds = []; try? await Task.sleep(nanoseconds: 2_000_000_000); service.refreshDiskInfo(); try? await Task.sleep(nanoseconds: 1_000_000_000); service.refreshDiskInfo(); cleanedSize = s; cleanedCount = c; showCleanResult = true } }
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
                    Text(app.displayName)
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)

                    if filterType != .app {
                        PillBadge(text: app.subCategory, color: subCategoryColor(app.subCategory), size: .small)
                    }
                }
                Text(app.desc)
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
                Text(app.riskDesc)
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

            HStack(spacing: Theme.Spacing.xs) {
                if app.canClean || app.canReset {
                    Button { onAction(.reset) } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.warning)
                            .frame(width: 28, height: 28)
                            .background(Theme.Colors.warning.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
                if app.canUninstall {
                    Button { onAction(.basicUninstall) } label: {
                        Image(systemName: "xmark.circle")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.info)
                            .frame(width: 28, height: 28)
                            .background(Theme.Colors.info.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    Button { onAction(.fullUninstall) } label: {
                        Image(systemName: "trash")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.danger)
                            .frame(width: 28, height: 28)
                            .background(Theme.Colors.danger.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }
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
        var color: Color { switch self { case .reset: .orange; case .basicUninstall: .blue; case .fullUninstall: .red } }
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
        return base.filter { $0.displayName.lowercased().contains(q) || $0.name.lowercased().contains(q) || $0.bundleId.lowercased().contains(q) || $0.desc.lowercased().contains(q) }
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
                        HStack(spacing: Theme.Spacing.xs) { Image(systemName: "arrow.clockwise"); Text(localizer.refresh) }
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs + 1)
                            .background(Theme.Colors.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isScanningApps)
                    .opacity(service.isScanningApps ? 0.5 : 1)

                    Button { service.checkAppUpdates() } label: {
                        HStack(spacing: Theme.Spacing.xs) { Image(systemName: "arrow.up.circle"); Text(localizer.checkUpdates) }
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.success)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs + 1)
                            .background(Theme.Colors.success.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .disabled(service.isCheckingAppUpdates)
                    .opacity(service.isCheckingAppUpdates ? 0.5 : 1)

                    Button {
                        let apps = service.installedApps.filter { selectedAppIds.contains($0.id) }
                        if !apps.isEmpty { Task { await service.analyzeImpactWithAI(apps: apps) } }
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) { Image(systemName: "sparkles"); Text(localizer.aiAnalysis) }
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs + 1)
                            .background(Theme.Colors.purple.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAppIds.isEmpty || service.isAnalyzingImpact)
                    .opacity(selectedAppIds.isEmpty || service.isAnalyzingImpact ? 0.5 : 1)
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
                    icon: "arrow.triangle.2.circlepath",
                    iconColor: Theme.Colors.warning,
                    title: localizer.checkUpdates,
                    value: "\(service.appUpdates.filter { $0.type == .app }.count)",
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
                                    Text(cat)
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
                        Text(localizer.selectAllBtn)
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.accent)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs + 1)
                            .background(Theme.Colors.accent.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    Button { selectedAppIds.removeAll() } label: {
                        Text(localizer.cancelBtn)
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs + 1)
                            .background(Theme.Colors.textTertiary.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }

                ForEach(AppAction.allCases, id: \.self) { action in
                    Button { pendingAction = action; pendingAppIds = Array(selectedAppIds); showActionConfirm = true } label: {
                        HStack(spacing: Theme.Spacing.xs) { Image(systemName: action.icon); Text(action.label(localizer)) }
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.xs + 1)
                            .background(action.color.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAppIds.isEmpty)
                    .opacity(selectedAppIds.isEmpty ? 0.5 : 1)
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

                            let apps = selectedApps
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
        case "包管理", "Package Manager": .orange
        case "开发", "Development": .green
        case "应用", "Apps": .cyan
        case "其它", "Other": .gray
        default: .gray
        }
    }

    private func subCategoryIconName(_ cat: String) -> String {
        switch cat {
        case "AI Agent": "cpu"
        case "CLI": "terminal"
        case "包管理", "Package Manager": "cube.box"
        case "开发", "Development": "hammer"
        case "应用", "Apps": "app.fill"
        case "其它", "Other": "questionmark.folder"
        default: "folder"
        }
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
                        .cornerRadius(6)
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
                        .cornerRadius(6)
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
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 40)).foregroundColor(.green.opacity(0.6))
                    Text(localizer.noDeviceCall).font(.title3).fontWeight(.medium)
                    Text(localizer.noDeviceCallHint).font(.caption).foregroundColor(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredEvents) {
                    TableColumn(localizer.timeCol) { event in
                        Text(event.timestamp, style: .time).font(.caption).monospacedDigit()
                    }.width(65)

                    TableColumn(localizer.colType) { event in
                        HStack(spacing: 4) {
                            Image(systemName: event.sensorType.icon)
                                .font(.caption)
                                .foregroundColor(event.sensorType.color)
                            Text(event.sensorType.rawValue)
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

                    TableColumn("PID") { event in
                        Text("\(event.pid)").font(.caption2).monospacedDigit().foregroundColor(.secondary)
                    }.width(60)

                    TableColumn("Bundle ID") { event in
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
            .cornerRadius(6)
            .foregroundColor(isActive ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
}


