import SwiftUI

struct ContentView: View {
    @State private var selectedTab: NavItem = .cleaner
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @State private var showSettings = false
    @State private var sidebarCollapsed = false
    @AppStorage("networkMode") private var networkMode = "internet"

    enum NavItem: String, CaseIterable {
        case cleaner = "Mac 清理"
        case operations = "Agent 监控"
        case app = "APP 管理"
        case dependency = "依赖管理"
        case other = "其它工具"

        var icon: String {
            switch self {
            case .cleaner: "arrow.down.doc.fill"
            case .app: "app.badge"
            case .dependency: "cube.box"
            case .other: "terminal"
            case .operations: "cpu"
            }
        }

        var color: Color {
            switch self {
            case .cleaner: .blue
            case .app: .cyan
            case .dependency: .orange
            case .other: .gray
            case .operations: .green
            }
        }

        func label(_ localizer: Localizer) -> String {
            switch self {
            case .cleaner: localizer.navCleaner
            case .app: localizer.navApp
            case .dependency: localizer.navDependency
            case .other: localizer.navOther
            case .operations: localizer.navOperations
            }
        }

        func subtitle(_ localizer: Localizer) -> String {
            switch self {
            case .cleaner: localizer.subCleaner
            case .app: localizer.subApp
            case .dependency: localizer.subDependency
            case .other: localizer.subOther
            case .operations: localizer.subOperations
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailContent
        }
        .frame(minWidth: 960, minHeight: 640)
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(service)
                .environmentObject(localizer)
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                if !sidebarCollapsed {
                    VStack(spacing: 3) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(.accentColor)
                        Text("AIMacCleaner")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.top, 12)
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.accentColor)
                        .padding(.top, 12)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, sidebarCollapsed ? 6 : 12)
            .padding(.bottom, 10)

            Divider()

            VStack(alignment: sidebarCollapsed ? .center : .leading, spacing: 4) {
                if !sidebarCollapsed {
                    Text(localizer.features)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                } else {
                    Text(localizer.features)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }

                ForEach(NavItem.allCases, id: \.self) { item in
                    Button {
                        selectedTab = item
                    } label: {
                        Group {
                            if sidebarCollapsed {
                                VStack(spacing: 4) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundColor(selectedTab == item ? item.color : .secondary)
                                        .frame(width: 24, height: 24)
                                    Text(item.label(localizer).split(separator: " ").first.map(String.init) ?? "")
                                        .font(.system(size: 8))
                                        .foregroundColor(selectedTab == item ? .primary : .secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedTab == item ? item.color.opacity(0.12) : Color.clear)
                                )
                            } else {
                                HStack(spacing: 10) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(selectedTab == item ? item.color : .secondary)
                                        .frame(width: 18)

                                    Text(item.label(localizer))
                                        .font(.system(size: 13))
                                        .fontWeight(selectedTab == item ? .semibold : .regular)
                                        .foregroundColor(selectedTab == item ? .primary : .secondary)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selectedTab == item ? item.color.opacity(0.12) : Color.clear)
                                )
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, sidebarCollapsed ? 4 : 8)

            Spacer()

            Divider()

            if sidebarCollapsed {
                VStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            sidebarCollapsed = false
                        }
                    } label: {
                        Image(systemName: "sidebar.right")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .help(localizer.expandSidebar)

                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 18))
                            .foregroundColor(.secondary)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 4) {
                        Image(systemName: networkMode == "internet" ? "globe" : "lock.shield")
                            .font(.system(size: 10))
                            .foregroundColor(networkMode == "internet" ? .blue : .orange)
                        Text(networkMode == "internet" ? localizer.internetStatus : localizer.offlineStatus)
                            .font(.system(size: 9))
                            .foregroundColor(networkMode == "internet" ? .blue : .orange)
                    }

                    Text("v\(service.currentVersion)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 14)
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 12) {
                        Button { showSettings = true } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 12))
                                Text(localizer.settings)
                                    .font(.system(size: 11))
                            }
                            .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        HStack(spacing: 4) {
                            Image(systemName: networkMode == "internet" ? "globe" : "lock.shield")
                                .font(.system(size: 9))
                                .foregroundColor(networkMode == "internet" ? .blue : .orange)
                            Text(networkMode == "internet" ? localizer.internetStatus : localizer.offlineStatus)
                                .font(.system(size: 9))
                                .foregroundColor(networkMode == "internet" ? .blue : .orange)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                sidebarCollapsed = true
                            }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 11, weight: .medium))
                                Text(localizer.collapseSidebar)
                                    .font(.system(size: 10))
                            }
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.08))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 5, height: 5)
                            Text("v\(service.currentVersion)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
            }
        }
        .frame(width: sidebarCollapsed ? 60 : 180)
        .background(Color(nsColor: .controlBackgroundColor))
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
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 18, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            trailing
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: - Filter Bar Component

struct FilterSearchBar: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 11))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
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

            if monitor.isMonitoring {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text(localizer.monitoring).font(.caption2).foregroundColor(.green)
                    Text("·").foregroundColor(.secondary)
                    Text("\(monitor.records.count) \(localizer.records)").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    if monitor.aiSelfLearningEnabled {
                        HStack(spacing: 3) {
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 9))
                                .foregroundColor(.purple)
                            Text("AI 学习中")
                                .font(.caption2)
                                .foregroundColor(.purple)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.08))
                        .cornerRadius(4)
                    }
                    Button {
                        if monitor.aiSelfLearningEnabled {
                            service.stopAISelfLearning()
                        } else {
                            service.startAISelfLearning()
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 9))
                            Text(monitor.aiSelfLearningEnabled ? "关闭 AI" : "AI 分析")
                                .font(.caption2)
                        }
                        .foregroundColor(monitor.aiSelfLearningEnabled ? .purple : .secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(monitor.aiSelfLearningEnabled ? 0.1 : 0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.05))
            }

            HStack(spacing: 8) {
                Picker("", selection: $viewMode) {
                    Text("实时监控").tag(0)
                    Text("已梳理").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 160)

                Spacer()

                if viewMode == 1 {
                    if monitor.isCurating {
                        HStack(spacing: 4) {
                            ProgressView().controlSize(.mini)
                            Text("梳理中...").font(.caption2).foregroundColor(.secondary)
                        }
                    } else if let last = monitor.lastCurationTime {
                        HStack(spacing: 2) {
                            Image(systemName: "clock").font(.system(size: 9)).foregroundColor(.secondary)
                            Text("上次: \(formattedDate(last))").font(.caption2).foregroundColor(.secondary)
                        }
                    }

                    Button {
                        Task { await service.curateWithAI() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "wand.and.stars").font(.system(size: 10))
                            Text("立即梳理").font(.caption2)
                        }
                        .foregroundColor(.purple)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.purple)
                    .disabled(monitor.isCurating || service.aiConfig?.hasKey != true)

                    Menu {
                        ForEach([1, 2, 3, 6, 12], id: \.self) { h in
                            Button("每 \(h) 小时") {
                                monitor.autoCurationInterval = h
                                if h > 0 { service.startAutoCuration() }
                                else { service.stopAutoCuration() }
                            }
                        }
                        Button("关闭自动") { service.stopAutoCuration() }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "timer").font(.system(size: 10))
                            Text("每\(monitor.autoCurationInterval)h").font(.caption2)
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(monitor.isCurating)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

            Divider()

            if viewMode == 0 {
                liveView
            } else {
                curatedView
            }
        }
        .onAppear {
            if !monitor.isMonitoring { monitor.start() }
            monitor.loadCurated()
            if monitor.autoCurationInterval > 0 { service.startAutoCuration() }
        }
    }

    private var liveView: some View {
        Group {

            HStack(spacing: 12) {
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

                Text("\(filteredRecords.count) \(localizer.recordsCount)").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

            Divider()

            if filteredRecords.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cpu")
                        .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text(localizer.noRecords).font(.title3).fontWeight(.medium)
                    Text(localizer.noRecordsHint).font(.caption).foregroundColor(.secondary)
                    if !monitor.isMonitoring {
                        Button(localizer.startMonitoring) { monitor.start() }
                            .buttonStyle(.bordered).controlSize(.regular)
                    } else {
                        VStack(spacing: 4) {
                            Text("监控已启动，等待文件操作事件...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("请在其他应用中创建、修改或删除文件以产生记录")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                    }
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredRecords) {
                    TableColumn(localizer.timeCol) { record in
                        Text(record.timestamp, style: .time)
                            .font(.caption).monospacedDigit()
                    }.width(65)

                    TableColumn(localizer.agentCol) { record in
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.caption2)
                                .foregroundColor(record.agentName == "—" ? .secondary : .purple)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.agentName)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .help(record.agentName)
                                if let pn = record.processName, !pn.isEmpty, pn != "path-match", pn != "dir-match" {
                                    Text(pn)
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .help("进程: \(pn)")
                                }
                            }
                        }
                    }.width(min: 110)

                    TableColumn(localizer.opCol) { record in
                        HStack(spacing: 3) {
                            Image(systemName: record.operationType.icon)
                                .font(.caption)
                                .foregroundColor(opTypeColor(record.operationType))
                            Text(record.operationType.rawValue)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(opTypeColor(record.operationType))
                        }
                    }.width(60)

                    TableColumn(localizer.pathCol) { record in
                        HStack(spacing: 4) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.targetPath)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(record.targetPath)
                                if let ti = record.toolInfo, !ti.isEmpty {
                                    Text(ti)
                                        .font(.system(size: 9))
                                        .foregroundColor(.orange.opacity(0.8))
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
                            .foregroundColor(.accentColor)
                            .help("复制路径，可在 Finder 中搜索")
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
    }

    private var curatedView: some View {
        Group {
            if monitor.curatedRecords.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text("暂无梳理数据").font(.title3).fontWeight(.medium)
                    Text("点击「立即梳理」通过 AI 分析原始监控数据").font(.caption).foregroundColor(.secondary)
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
                                Text("置信度: \(String(format: "%.0f", record.confidence * 100))%")
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
                HStack(spacing: 8) {
                    Button { Task { await service.scanLocal() } } label: {
                        HStack(spacing: 4) { Image(systemName: "magnifyingglass"); Text(localizer.localScan) }
                    }
                    .buttonStyle(.bordered).controlSize(.small).disabled(service.isScanning)

                    Button { Task { await performAiScan() } } label: {
                        HStack(spacing: 4) { Image(systemName: "brain"); Text(localizer.aiScan) }
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(.purple).disabled(service.isAiScanning)

                    Button { Task { await service.startEnhancedScan() } } label: {
                        HStack(spacing: 4) { Image(systemName: "bolt.fill"); Text(localizer.enhancedScan) }
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(.orange).disabled(service.isEnhancedScanning)
                }
            }

            diskCard
            Divider()

            if service.isAiScanning || service.isEnhancedScanning {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text(service.isEnhancedScanning ? localizer.enhancedScan + "..." : service.aiStatusMessage).foregroundColor(.purple); Spacer() }
                    .padding(.horizontal, 24).padding(.vertical, 8).background(Color.purple.opacity(0.05))
                Divider()
            }
            if let error = service.errorMessage {
                HStack(spacing: 10) { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange); Text(error).font(.caption).foregroundColor(.secondary).lineLimit(3); Spacer()
                    Button { service.errorMessage = nil } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain)
                }.padding(.horizontal, 24).padding(.vertical, 8).background(Color.orange.opacity(0.05))
                Divider()
            }

            if service.isScanning { scanningOverlay }
            else if service.scanItems.isEmpty { welcomeCenter }
            else {
                HStack(spacing: 12) {
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

                    HStack(spacing: 4) {
                        Text(localizer.riskLabel + ":").font(.caption).foregroundColor(.secondary)
                        RiskFilterButton(label: localizer.riskSafe, color: .green, isActive: filterRisk == "safe") { filterRisk = "safe" }
                        RiskFilterButton(label: localizer.riskCaution, color: .orange, isActive: filterRisk == "caution") { filterRisk = "caution" }
                        RiskFilterButton(label: localizer.riskDangerous, color: .red, isActive: filterRisk == "dangerous") { filterRisk = "dangerous" }
                        if !filterRisk.isEmpty { Button { filterRisk = "" } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary) }.buttonStyle(.plain) }
                    }

                    Spacer()
                    Button { smartClean() } label: { Label(localizer.smartClean, systemImage: "wand.and.stars") }
                        .buttonStyle(.borderedProminent).tint(.green).controlSize(.small)
                        .disabled(service.scanItems.filter { $0.risk == "safe" && !$0.ignored }.isEmpty)
                    Text("\(filteredItems.count) \(localizer.selected) · \(service.formatSize(totalCleanable))").font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                Divider()

                if !selectedIds.isEmpty {
                    HStack(spacing: 10) {
                        Button { selectAll() } label: { Text(localizer.selectAll) }.buttonStyle(.bordered).controlSize(.small)
                        Button { selectSafe() } label: { Text(localizer.safeOnly) }.buttonStyle(.bordered).controlSize(.small)
                        Button { selectedIds.removeAll() } label: { Text(localizer.cancelSelection) }.buttonStyle(.bordered).controlSize(.small)
                        Text(localizer.selected + " \(selectedIds.count) \(localizer.selected) · \(service.formatSize(selectedSize))").font(.caption).foregroundColor(.blue).fontWeight(.medium)
                        Spacer()
                        Button { ignoreSelected() } label: { Label(localizer.ignoreSelected, systemImage: "eye.slash") }.buttonStyle(.bordered).controlSize(.small).disabled(selectedIds.isEmpty)
                        Button { confirmDeleteSelected() } label: { Label(localizer.deleteSelected, systemImage: "trash") }.buttonStyle(.bordered).tint(.red).controlSize(.small).disabled(selectedIds.isEmpty)
                    }.padding(.horizontal, 24).padding(.vertical, 8).background(Color.accentColor.opacity(0.06))
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
        .alert("确认删除", isPresented: $showDeleteConfirm) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { performDelete() }
        } message: {
            let items = service.scanItems.filter { deleteTargetIds.contains($0.id) }
            Text("确定删除 \(deleteTargetIds.count) 项（共 \(service.formatSize(items.reduce(Int64(0)) { $0 + $1.size }))）？")
        }
        .alert("🎉 清理完成", isPresented: $showCleanResult) {
            Button("确定") {}
        } message: {
            Text("本次清理释放了 \(service.formatSize(cleanedSize))，共清理 \(cleanedCount) 项。")
        }
    }

    private var diskCard: some View {
        HStack(spacing: 32) {
            if let disk = service.diskInfo {
                VStack(alignment: .leading, spacing: 6) {
                    Text("磁盘空间").font(.headline)
                    ProgressView(value: disk.usedPct / 100.0).progressViewStyle(.linear).tint(disk.usedPct > 85 ? .red : disk.usedPct > 70 ? .orange : .green)
                    Text(String(format: "%.1f%% 已使用", disk.usedPct)).font(.caption).foregroundColor(.secondary)
                }.frame(maxWidth: 280)
                HStack(spacing: 28) {
                    DiskStat(title: "总容量", value: String(format: "%.0f GB", disk.totalGb))
                    DiskStat(title: "已使用", value: String(format: "%.0f GB", disk.usedGb))
                    DiskStat(title: "可用", value: String(format: "%.0f GB", disk.freeGb), color: disk.freeGb < 20 ? .red : .green)
                    DiskStat(title: "可释放", value: service.formatSize(totalCleanable), color: .cyan)
                }
                Spacer()
            }
        }.padding(.horizontal, 24).padding(.vertical, 16).background(Color(nsColor: .windowBackgroundColor))
    }

    private var scanningOverlay: some View {
        VStack(spacing: 20) { ProgressView().controlSize(.large); Text("正在扫描存储空间...").font(.title3).fontWeight(.medium); Text("请稍候，正在分析可清理的文件").foregroundColor(.secondary).font(.callout) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var welcomeCenter: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 8) { Image(systemName: "arrow.down.doc.fill").font(.system(size: 48)).foregroundColor(.accentColor.opacity(0.6)); Text("AIMacCleaner").font(.title).fontWeight(.bold); Text("智能清理 Mac 存储空间").foregroundColor(.secondary).font(.callout) }
            HStack(spacing: 24) {
                ActionCard(icon: "magnifyingglass", title: "本地扫描", subtitle: "扫描缓存、日志等可清理文件", color: .blue, isDisabled: service.isScanning) { Task { await service.scanLocal() } }
                ActionCard(icon: "brain", title: "AI 扫描", subtitle: "大模型智能分析可清理目录", color: .purple, isDisabled: service.isAiScanning) { Task { await performAiScan() } }
                ActionCard(icon: "bolt.fill", title: "增强扫描", subtitle: "本地 + AI 同时扫描，最全面", color: .orange, isDisabled: service.isEnhancedScanning) { Task { await service.startEnhancedScan() } }
            }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    private var noResultView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle").font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
            Text("当前筛选条件下没有匹配项").font(.title3).fontWeight(.medium)
            HStack(spacing: 10) {
                if !filterRisk.isEmpty { Button { filterRisk = "" } label: { Text("清除风险筛选") }.buttonStyle(.bordered).controlSize(.small) }
                if !filterCategory.isEmpty { Button { filterCategory = "" } label: { Text("清除分类筛选") }.buttonStyle(.bordered).controlSize(.small) }
                if !searchText.isEmpty { Button { searchText = "" } label: { Text("清除搜索") }.buttonStyle(.bordered).controlSize(.small) }
            }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultList: some View {
        Table(filteredItems, selection: $selectedIds) {
            TableColumn("✓") { item in Toggle("", isOn: Binding(get: { selectedIds.contains(item.id) }, set: { _ in if selectedIds.contains(item.id) { selectedIds.remove(item.id) } else { selectedIds.insert(item.id) } })).toggleStyle(.checkbox).labelsHidden() }.width(36)
            TableColumn("名称") { item in HStack(spacing: 6) { if item.ignored { Image(systemName: "eye.slash").foregroundColor(.secondary).font(.caption) }; Text(item.name).fontWeight(.semibold) } }.width(min: 150)
            TableColumn("来源") { item in Text(item.sourceType.label).font(.caption2).padding(.horizontal, 6).padding(.vertical, 2).background(item.sourceType == .ai ? Color.purple.opacity(0.12) : Color.blue.opacity(0.12)).cornerRadius(4) }.width(50)
            TableColumn("应用") { item in Text(item.app).font(.caption).foregroundColor(.secondary) }.width(90)
            TableColumn("风险") { item in HStack(spacing: 3) { Image(systemName: item.riskLevel.systemImage).foregroundColor(riskColor(item.riskLevel)).font(.caption); Text(item.riskLevel.label).font(.caption2).fontWeight(.medium) } }.width(60)
            TableColumn("大小") { item in Text(service.formatSize(item.size)).fontWeight(.bold).monospacedDigit().foregroundColor(.cyan) }.width(70)
            TableColumn("说明") { item in Text(item.reason ?? item.riskDesc).font(.caption2).foregroundColor(item.sourceType == .ai ? .purple : .orange).lineLimit(2) }
            TableColumn("操作") { item in HStack(spacing: 4) {
                Button { confirmDeleteSingle(item) } label: { Image(systemName: "trash").font(.caption) }.buttonStyle(.bordered).controlSize(.mini).tint(.red)
                Button { toggleIgnore(item) } label: { Image(systemName: item.ignored ? "eye" : "eye.slash").font(.caption) }.buttonStyle(.bordered).controlSize(.mini)
            } }.width(70)
        }.tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    private func riskColor(_ level: ScanItem.RiskLevel) -> Color { switch level { case .safe: .green; case .caution: .orange; case .dangerous: .red } }
    private func selectAll() { selectedIds = Set(filteredItems.filter { !$0.ignored }.map(\.id)) }
    private func selectSafe() { selectedIds = Set(filteredItems.filter { $0.risk == "safe" && !$0.ignored }.map(\.id)) }
    private func smartClean() { let safe = service.scanItems.filter { $0.risk == "safe" && !$0.ignored }; guard !safe.isEmpty else { return }; deleteTargetIds = safe.map(\.id); showDeleteConfirm = true }
    private func performAiScan() async { if service.aiConfig?.hasKey != true { showSettings = true; return }; await service.startAiScan() }
    private func confirmDeleteSelected() { deleteTargetIds = Array(selectedIds); showDeleteConfirm = true }
    private func confirmDeleteSingle(_ item: ScanItem) { deleteTargetIds = [item.id]; showDeleteConfirm = true }
    private func performDelete() { let s = service.scanItems.filter { deleteTargetIds.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }; let c = deleteTargetIds.count; Task { let _ = await service.deleteItems(ids: deleteTargetIds); service.removeScannedItems(ids: deleteTargetIds); selectedIds.subtract(deleteTargetIds); deleteTargetIds = []; service.refreshDiskInfo(); cleanedSize = s; cleanedCount = c; showCleanResult = true } }
    private func ignoreSelected() { service.ignoreItems(ids: Array(selectedIds)); selectedIds.removeAll() }
    private func toggleIgnore(_ item: ScanItem) { if item.ignored { service.unignoreItems(ids: [item.id]) } else { service.ignoreItems(ids: [item.id]) } }
}

// MARK: - App Manager Tab

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
                title: filterType.tabLabel,
                subtitle: filterType == .app ? localizer.appManagerSubtitle : filterType == .dependency ? localizer.dependencySubtitle : localizer.otherToolsSubtitle,
                color: filterType.tabColor
            ) {
                HStack(spacing: 8) {
                    Button { Task { await service.scanInstalledApps() } } label: {
                        HStack(spacing: 4) { Image(systemName: "arrow.clockwise"); Text(localizer.refresh) }
                    }
                    .buttonStyle(.bordered).controlSize(.small).disabled(service.isScanningApps)

                    Button { service.checkAppUpdates() } label: {
                        HStack(spacing: 4) { Image(systemName: "arrow.up.circle"); Text("Check Updates") }
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(.green)
                    .disabled(service.isCheckingAppUpdates)

                    Button {
                        let apps = service.installedApps.filter { selectedAppIds.contains($0.id) }
                        if !apps.isEmpty { Task { await service.analyzeImpactWithAI(apps: apps) } }
                    } label: {
                        HStack(spacing: 4) { Image(systemName: "sparkles"); Text(localizer.aiAnalysis) }
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(.purple)
                    .disabled(selectedAppIds.isEmpty || service.isAnalyzingImpact)
                }
            }

            if subCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SubCategoryChip(label: localizer.all, count: service.installedApps.filter { $0.appType == filterType }.count, isActive: filterSubCategory.isEmpty, color: .accentColor) { filterSubCategory = "" }
                        ForEach(subCategories, id: \.self) { cat in
                            let count = service.installedApps.filter { $0.appType == filterType && $0.subCategory == cat }.count
                            SubCategoryChip(label: cat, count: count, isActive: filterSubCategory == cat, color: subCategoryColor(cat)) { filterSubCategory = filterSubCategory == cat ? "" : cat }
                        }
                    }.padding(.horizontal, 24).padding(.vertical, 8)
                }.background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                Divider()
            }

            HStack(spacing: 12) {
                FilterSearchBar(placeholder: localizer.searchingApps, text: $searchText)
                    .frame(width: 200)

                Spacer()

                if !selectedAppIds.isEmpty {
                    Text("\(localizer.selected) \(selectedAppIds.count) 项 · \(service.formatSize(selectedTotalSize))").font(.caption).foregroundColor(.blue).fontWeight(.medium)
                }

                HStack(spacing: 4) {
                    Button { selectedAppIds = Set(filteredApps.map(\.id)) } label: { Text(localizer.selectAllBtn) }.buttonStyle(.bordered).controlSize(.small)
                    Button { selectedAppIds.removeAll() } label: { Text(localizer.cancelBtn) }.buttonStyle(.bordered).controlSize(.small)
                }

                ForEach(AppAction.allCases, id: \.self) { action in
                    Button { pendingAction = action; pendingAppIds = Array(selectedAppIds); showActionConfirm = true } label: {
                        HStack(spacing: 4) { Image(systemName: action.icon); Text(action.label(localizer)) }
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(action.color)
                    .disabled(selectedAppIds.isEmpty)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

            HStack(spacing: 20) {
                ForEach(AppAction.allCases, id: \.self) { action in
                    HStack(spacing: 6) {
                        Image(systemName: action.icon).foregroundColor(action.color).font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.label(localizer)).font(.caption).fontWeight(.semibold)
                            Text(action.desc(localizer)).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            if service.isScanningApps {
                VStack(spacing: 16) { ProgressView().controlSize(.large); Text(localizer.searching).foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: filterType == .app ? "app.dashed" : filterType == .dependency ? "cube.box" : "terminal")
                        .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text("\(localizer.notFound)\(filterType.label)").font(.title3).fontWeight(.medium)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredApps, selection: $selectedAppIds) {
                    TableColumn("✓") { app in Toggle("", isOn: Binding(get: { selectedAppIds.contains(app.id) }, set: { _ in if selectedAppIds.contains(app.id) { selectedAppIds.remove(app.id) } else { selectedAppIds.insert(app.id) } })).toggleStyle(.checkbox).labelsHidden() }.width(36)
                    TableColumn(localizer.nameCol) { app in
                        HStack(spacing: 8) {
                            if let iconPath = app.iconPath, let img = NSImage(contentsOfFile: iconPath) {
                                Image(nsImage: img).resizable().frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: filterType == .app ? "app.fill" : filterType == .dependency ? "cube.box.fill" : "terminal.fill")
                                    .font(.title3).foregroundColor(.secondary).frame(width: 32, height: 32)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.displayName).fontWeight(.semibold)
                                if filterType != .app {
                                    Text(app.subCategory).font(.caption2).padding(.horizontal, 5).padding(.vertical, 1)
                                        .background(subCategoryColor(app.subCategory).opacity(0.12)).cornerRadius(4)
                                        .foregroundColor(subCategoryColor(app.subCategory))
                                }
                                Text(app.desc).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                            }
                        }
                    }.width(min: 220)
                    TableColumn(localizer.riskCol) { app in
                        HStack(spacing: 3) {
                            let rc: Color = app.risk == "safe" ? .green : app.risk == "dangerous" ? .red : .orange
                            let rl: String = app.risk == "safe" ? localizer.safe : app.risk == "dangerous" ? localizer.dangerous : localizer.warning
                            Image(systemName: app.risk == "safe" ? "checkmark.circle.fill" : app.risk == "dangerous" ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(rc).font(.caption)
                            Text(rl).font(.caption2).fontWeight(.medium).foregroundColor(rc)
                        }
                    }.width(60)
                    TableColumn(localizer.impactCol) { app in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.riskDesc).font(.caption2).foregroundColor(.orange).lineLimit(2)
                            if let aiResult = service.aiAnalysisMap[app.id] {
                                Text(aiResult).font(.caption2).fontWeight(.medium)
                                    .foregroundColor(aiResult.hasPrefix("🤖") ? .purple : aiResult.hasPrefix("❌") ? .red : aiResult.hasPrefix("⚠️") ? .yellow : .secondary)
                                    .lineLimit(2)
                            }
                        }
                    }.width(min: 140)
                    TableColumn(localizer.sizeCol) { app in
                        Text(service.formatSize(app.totalSize)).fontWeight(.bold).monospacedDigit().foregroundColor(.cyan)
                    }.width(80)
                    TableColumn(localizer.actionCol) { app in
                        HStack(spacing: 4) {
                            if app.canClean || app.canReset {
                                Button { pendingAction = .reset; pendingAppIds = [app.id]; showActionConfirm = true } label: { Image(systemName: "arrow.counterclockwise").font(.caption) }
                                    .buttonStyle(.bordered).controlSize(.mini).tint(.orange)
                            }
                            if app.canUninstall {
                                Button { pendingAction = .basicUninstall; pendingAppIds = [app.id]; showActionConfirm = true } label: { Image(systemName: "xmark.circle").font(.caption) }
                                    .buttonStyle(.bordered).controlSize(.mini)
                                Button { pendingAction = .fullUninstall; pendingAppIds = [app.id]; showActionConfirm = true } label: { Image(systemName: "trash").font(.caption) }
                                    .buttonStyle(.bordered).controlSize(.mini).tint(.red)
                            }
                        }
                    }.width(90)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .onAppear { if service.installedApps.isEmpty { Task { await service.scanInstalledApps() } } }
        .alert(localizer.actionConfirm, isPresented: $showActionConfirm) {
            Button(localizer.cancelBtn, role: .cancel) {}
            Button(localizer.confirmBtn, role: .destructive) { performAction() }
        } message: {
            let apps = selectedApps
            let size = pendingAction == .basicUninstall ? apps.reduce(Int64(0)) { $0 + $1.appSize } : apps.reduce(Int64(0)) { $0 + $1.totalSize }
            Text("\(pendingAction.desc(localizer))\n\n\(localizer.willAction)\(pendingAction.label(localizer)) \(apps.count) \(localizer.total)，共 \(service.formatSize(size))")
        }
        .alert(localizer.actionDone, isPresented: $showActionResult) {
            Button(localizer.confirmBtn) {}
        } message: { Text(actionResultMsg) }
    }

    private func subCategoryColor(_ cat: String) -> Color {
        switch cat {
        case "AI Agent": .purple
        case "CLI": .blue
        case "包管理": .orange
        case "开发": .green
        case "应用": .cyan
        case "其它": .gray
        default: .gray
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
            actionResultMsg = "\(pendingAction.label(localizer))\(localizer.actionComplete)：成功 \(successCount) 个" + (failCount > 0 ? "，失败 \(failCount) 个" : "")
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

struct DiskStat: View {
    let title: String; let value: String; var color: Color = .primary
    var body: some View { VStack(spacing: 2) { Text(title).font(.caption2).foregroundColor(.secondary).textCase(.uppercase); Text(value).font(.title3).fontWeight(.bold).foregroundColor(color) } }
}

struct SubCategoryChip: View {
    let label: String
    let count: Int
    let isActive: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: subCategoryIcon(label))
                    .font(.caption2)
                    .foregroundColor(isActive ? .white : color)
                Text(label)
                    .font(.caption)
                    .fontWeight(isActive ? .semibold : .regular)
                    .foregroundColor(isActive ? .white : .primary)
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(isActive ? .white.opacity(0.8) : .secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(isActive ? Color.white.opacity(0.2) : color.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? color : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? color.opacity(0.6) : color.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func subCategoryIcon(_ cat: String) -> String {
        switch cat {
        case "AI Agent": "cpu"
        case "CLI": "terminal"
        case "包管理": "cube.box"
        case "开发": "hammer"
        case "应用": "app.fill"
        case "其它": "questionmark.folder"
        default: "folder"
        }
    }
}

// MARK: - Sensor Monitor Tab

struct SensorMonitorTab: View {
    @ObservedObject var monitor: SensorMonitor
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
                title: "设备监控",
                subtitle: "摄像头与麦克风使用监控",
                color: .red
            ) {
                HStack(spacing: 8) {
                    if monitor.cameraActive {
                        HStack(spacing: 4) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Image(systemName: "video.fill").font(.caption2)
                            Text(monitor.cameraProcess ?? "摄像头").font(.caption2)
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
                            Text(monitor.microphoneProcess ?? "麦克风").font(.caption2)
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
                            Text(monitor.isMonitoring ? "停止监控" : "开始监控")
                        }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                    .tint(monitor.isMonitoring ? .red : .green)

                    if !monitor.events.isEmpty {
                        Button { monitor.clearEvents() } label: {
                            HStack(spacing: 3) { Image(systemName: "trash"); Text("清空") }
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(.red)
                    }
                }
            }

            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    SensorFilterChip(label: "全部", icon: "sensor.fill", color: .gray, isActive: filterType == nil) { filterType = nil }
                    SensorFilterChip(label: "摄像头", icon: "video.fill", color: .red, isActive: filterType == .camera) { filterType = .camera }
                    SensorFilterChip(label: "麦克风", icon: "mic.fill", color: .blue, isActive: filterType == .microphone) { filterType = .microphone }
                }

                Spacer()

                Text("\(filteredEvents.count) 条记录").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 24).padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            Divider()

            if !monitor.isMonitoring && monitor.events.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "video.slash")
                        .font(.system(size: 48)).foregroundColor(.secondary.opacity(0.5))
                    Text("设备监控未启动").font(.title3).fontWeight(.medium)
                    Text("启动后将监控摄像头和麦克风的使用情况").font(.caption).foregroundColor(.secondary)
                    Button("开始监控") { monitor.start() }
                        .buttonStyle(.borderedProminent).tint(.red).controlSize(.regular)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredEvents.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 40)).foregroundColor(.green.opacity(0.6))
                    Text("未检测到设备调用").font(.title3).fontWeight(.medium)
                    Text("摄像头和麦克风均未被使用").font(.caption).foregroundColor(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredEvents) {
                    TableColumn("时间") { event in
                        Text(event.timestamp, style: .time).font(.caption).monospacedDigit()
                    }.width(65)

                    TableColumn("类型") { event in
                        HStack(spacing: 4) {
                            Image(systemName: event.sensorType.icon)
                                .font(.caption)
                                .foregroundColor(event.sensorType.color)
                            Text(event.sensorType.rawValue)
                                .font(.caption2).fontWeight(.medium)
                                .foregroundColor(event.sensorType.color)
                        }
                    }.width(70)

                    TableColumn("进程") { event in
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


