import SwiftUI

struct ContentView: View {
    @State private var selectedTab: NavItem = .cleaner
    @EnvironmentObject var service: ScannerService
    @State private var showAIConfig = false
    @StateObject private var sensorMonitor = SensorMonitor()
    @StateObject private var storageAnalyzer = StorageAnalyzer()

    enum NavItem: String, CaseIterable {
        case cleaner = "Mac 清理"
        case storage = "存储分析"
        case sensor = "设备监控"
        case app = "APP 管理"
        case dependency = "依赖管理"
        case other = "其它工具"
        case operations = "操作记录"

        var icon: String {
            switch self {
            case .cleaner: "arrow.down.doc.fill"
            case .storage: "chart.pie"
            case .sensor: "video.fill"
            case .app: "app.badge"
            case .dependency: "cube.box"
            case .other: "terminal"
            case .operations: "clock.arrow.circlepath"
            }
        }

        var color: Color {
            switch self {
            case .cleaner: .blue
            case .storage: .indigo
            case .sensor: .red
            case .app: .cyan
            case .dependency: .orange
            case .other: .gray
            case .operations: .green
            }
        }

        var subtitle: String {
            switch self {
            case .cleaner: "扫描并清理存储空间"
            case .storage: "存储空间分析与AI建议"
            case .sensor: "摄像头与麦克风监控"
            case .app: "管理已安装的应用"
            case .dependency: "管理开发依赖"
            case .other: "管理命令行工具"
            case .operations: "监控 AI Agent 操作"
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
        .sheet(isPresented: $showAIConfig) {
            AIConfigView().environmentObject(service)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(.accentColor)
                Text("AIMacCleaner")
                    .font(.system(size: 14, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text("功能")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 4)

                ForEach(NavItem.allCases, id: \.self) { item in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedTab = item
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(selectedTab == item ? item.color : .secondary)
                                .frame(width: 18)

                            Text(item.rawValue)
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
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)

            Spacer()

            Divider()

            HStack(spacing: 8) {
                Button { showAIConfig = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 10))
                        Text("AI 设置")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                    Text("v1.6.2")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(width: 180)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedTab {
        case .cleaner:
            MacCleanerTab()
        case .storage:
            StorageAnalysisTab(analyzer: storageAnalyzer, service: service)
        case .sensor:
            SensorMonitorTab(monitor: sensorMonitor)
        case .app:
            AppManagerTab(filterType: .app)
        case .dependency:
            AppManagerTab(filterType: .dependency)
        case .other:
            AppManagerTab(filterType: .other)
        case .operations:
            OperationLogTab(monitor: service.operationMonitor)
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
    @State private var searchText = ""
    @State private var filterAgent = ""
    @State private var filterOpType: OperationRecord.OperationType?
    @State private var filterTimeRange: TimeRange = .all

    enum TimeRange: String, CaseIterable {
        case all = "全部"
        case today = "今天"
        case hour1 = "1小时"
        case hour6 = "6小时"
        case day1 = "24小时"
        case day7 = "7天"
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
                icon: "clock.arrow.circlepath",
                title: "操作记录",
                subtitle: "监控 AI Agent 的文件操作",
                color: .green
            ) {
                HStack(spacing: 8) {
                    Button { monitor.start() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: monitor.isMonitoring ? "record.circle.fill" : "record.circle")
                            Text(monitor.isMonitoring ? "监控中" : "开始监控")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(monitor.isMonitoring ? .green : .blue)
                    .disabled(monitor.isMonitoring)

                    Button { monitor.clearRecords() } label: {
                        HStack(spacing: 3) { Image(systemName: "trash"); Text("清空") }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                }
            }

            if monitor.isMonitoring {
                HStack(spacing: 6) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("监控中").font(.caption2).foregroundColor(.green)
                    Text("·").foregroundColor(.secondary)
                    Text("\(monitor.records.count) 条记录").font(.caption2).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 5)
                .background(Color.green.opacity(0.05))
            }

            HStack(spacing: 12) {
                FilterSearchBar(placeholder: "搜索路径、Agent...", text: $searchText)
                    .frame(width: 200)

                Picker("Agent", selection: $filterAgent) {
                    Text("全部 Agent").tag("")
                    ForEach(agentNames, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()

                Picker("操作类型", selection: $filterOpType) {
                    Text("全部类型").tag(nil as OperationRecord.OperationType?)
                    ForEach(OperationRecord.OperationType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type as OperationRecord.OperationType?)
                    }
                }
                .labelsHidden()

                Picker("时间范围", selection: $filterTimeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()

                Spacer()

                Text("\(filteredRecords.count) 条").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

            Divider()

            if filteredRecords.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text("暂无操作记录").font(.title3).fontWeight(.medium)
                    Text("启动监控后将自动记录 AI Agent 的文件操作").font(.caption).foregroundColor(.secondary)
                    if !monitor.isMonitoring {
                        Button("开始监控") { monitor.start() }
                            .buttonStyle(.bordered).controlSize(.regular)
                    }
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredRecords) {
                    TableColumn("时间") { record in
                        Text(record.timestamp, style: .time)
                            .font(.caption).monospacedDigit()
                    }.width(65)

                    TableColumn("Agent") { record in
                        HStack(spacing: 4) {
                            Image(systemName: "cpu")
                                .font(.caption2)
                                .foregroundColor(.purple)
                            Text(record.agentName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                        }
                    }.width(min: 100)

                    TableColumn("操作") { record in
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

                    TableColumn("目标路径") { record in
                        Text(record.targetPath)
                            .font(.caption2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(record.targetPath)
                    }

                    TableColumn("大小") { record in
                        if record.fileSize > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: record.fileSize, countStyle: .file))
                                .font(.caption2).monospacedDigit().foregroundColor(.secondary)
                        }
                    }.width(70)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .onAppear {
            if !monitor.isMonitoring { monitor.start() }
        }
    }

    private func opTypeColor(_ type: OperationRecord.OperationType) -> Color {
        switch type {
        case .create: .green
        case .modify: .blue
        case .delete: .red
        case .move: .orange
        case .rename: .purple
        }
    }
}

// MARK: - Mac Cleaner Tab

struct MacCleanerTab: View {
    @EnvironmentObject var service: ScannerService
    @State private var selectedIds = Set<String>()
    @State private var filterCategory = ""
    @State private var filterApp = ""
    @State private var filterRisk = ""
    @State private var filterSource = ""
    @State private var showAIConfig = false
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
                title: "Mac 清理",
                subtitle: "扫描并清理存储空间",
                color: .blue
            ) {
                HStack(spacing: 8) {
                    Button { Task { await service.scanLocal() } } label: {
                        HStack(spacing: 4) { Image(systemName: "magnifyingglass"); Text("本地扫描") }
                    }
                    .buttonStyle(.bordered).controlSize(.small).disabled(service.isScanning)

                    Button { Task { await performAiScan() } } label: {
                        HStack(spacing: 4) { Image(systemName: "brain"); Text("AI 扫描") }
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(.purple).disabled(service.isAiScanning)

                    Button { Task { await service.startEnhancedScan() } } label: {
                        HStack(spacing: 4) { Image(systemName: "bolt.fill"); Text("增强扫描") }
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(.orange).disabled(service.isEnhancedScanning)
                }
            }

            diskCard
            Divider()

            if service.isAiScanning || service.isEnhancedScanning {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text(service.isEnhancedScanning ? "增强扫描中..." : service.aiStatusMessage).foregroundColor(.purple); Spacer() }
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
                    FilterSearchBar(placeholder: "搜索文件...", text: $searchText)
                        .frame(width: 180)

                    if !categories.isEmpty {
                        Picker("分类", selection: $filterCategory) {
                            Text("全部分类").tag("")
                            ForEach(categories, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }
                    if !apps.isEmpty {
                        Picker("应用", selection: $filterApp) {
                            Text("全部应用").tag("")
                            ForEach(apps, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                    }

                    HStack(spacing: 4) {
                        Text("风险:").font(.caption).foregroundColor(.secondary)
                        RiskFilterButton(label: "安全", color: .green, isActive: filterRisk == "safe") { filterRisk = "safe" }
                        RiskFilterButton(label: "注意", color: .orange, isActive: filterRisk == "caution") { filterRisk = "caution" }
                        RiskFilterButton(label: "危险", color: .red, isActive: filterRisk == "dangerous") { filterRisk = "dangerous" }
                        if !filterRisk.isEmpty { Button { filterRisk = "" } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary) }.buttonStyle(.plain) }
                    }

                    Spacer()
                    Button { smartClean() } label: { Label("智能清理", systemImage: "wand.and.stars") }
                        .buttonStyle(.borderedProminent).tint(.green).controlSize(.small)
                        .disabled(service.scanItems.filter { $0.risk == "safe" && !$0.ignored }.isEmpty)
                    Text("\(filteredItems.count) 项 · \(service.formatSize(totalCleanable))").font(.caption).foregroundColor(.secondary)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                Divider()

                if !selectedIds.isEmpty {
                    HStack(spacing: 10) {
                        Button { selectAll() } label: { Text("全选") }.buttonStyle(.bordered).controlSize(.small)
                        Button { selectSafe() } label: { Text("仅安全") }.buttonStyle(.bordered).controlSize(.small)
                        Button { selectedIds.removeAll() } label: { Text("取消选择") }.buttonStyle(.bordered).controlSize(.small)
                        Text("已选 \(selectedIds.count) 项 · \(service.formatSize(selectedSize))").font(.caption).foregroundColor(.blue).fontWeight(.medium)
                        Spacer()
                        Button { ignoreSelected() } label: { Label("忽略选中", systemImage: "eye.slash") }.buttonStyle(.bordered).controlSize(.small).disabled(selectedIds.isEmpty)
                        Button { confirmDeleteSelected() } label: { Label("删除选中", systemImage: "trash") }.buttonStyle(.bordered).tint(.red).controlSize(.small).disabled(selectedIds.isEmpty)
                    }.padding(.horizontal, 24).padding(.vertical, 8).background(Color.accentColor.opacity(0.06))
                    Divider()
                }

                if filteredItems.isEmpty { noResultView } else { resultList }
            }
        }
        .sheet(isPresented: $showAIConfig) { AIConfigView().environmentObject(service) }
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
    private func performAiScan() async { if service.aiConfig?.hasKey != true { showAIConfig = true; return }; await service.startAiScan() }
    private func confirmDeleteSelected() { deleteTargetIds = Array(selectedIds); showDeleteConfirm = true }
    private func confirmDeleteSingle(_ item: ScanItem) { deleteTargetIds = [item.id]; showDeleteConfirm = true }
    private func performDelete() { let s = service.scanItems.filter { deleteTargetIds.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }; let c = deleteTargetIds.count; Task { let _ = await service.deleteItems(ids: deleteTargetIds); service.removeScannedItems(ids: deleteTargetIds); selectedIds.subtract(deleteTargetIds); deleteTargetIds = []; service.refreshDiskInfo(); cleanedSize = s; cleanedCount = c; showCleanResult = true } }
    private func ignoreSelected() { service.ignoreItems(ids: Array(selectedIds)); selectedIds.removeAll() }
    private func toggleIgnore(_ item: ScanItem) { if item.ignored { service.unignoreItems(ids: [item.id]) } else { service.ignoreItems(ids: [item.id]) } }
}

// MARK: - App Manager Tab

struct AppManagerTab: View {
    @EnvironmentObject var service: ScannerService
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
        case reset = "重置", basicUninstall = "基础卸载", fullUninstall = "完全卸载"
        var icon: String { switch self { case .reset: "arrow.counterclockwise"; case .basicUninstall: "xmark.circle"; case .fullUninstall: "trash" } }
        var color: Color { switch self { case .reset: .orange; case .basicUninstall: .blue; case .fullUninstall: .red } }
        var desc: String { switch self {
        case .reset: "清除缓存和历史数据，恢复为全新安装状态（APP本身保留）"
        case .basicUninstall: "仅卸载安装文件，保留缓存和历史数据（重新安装后可恢复）"
        case .fullUninstall: "卸载并清除所有缓存、历史数据和配置（彻底清除，不可恢复）"
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
                subtitle: filterType == .app ? "管理已安装的应用" : filterType == .dependency ? "管理开发依赖" : "管理命令行工具",
                color: filterType.tabColor
            ) {
                HStack(spacing: 8) {
                    Button { Task { await service.scanInstalledApps() } } label: {
                        HStack(spacing: 4) { Image(systemName: "arrow.clockwise"); Text("刷新") }
                    }
                    .buttonStyle(.bordered).controlSize(.small).disabled(service.isScanningApps)

                    Button {
                        let apps = service.installedApps.filter { selectedAppIds.contains($0.id) }
                        if !apps.isEmpty { Task { await service.analyzeImpactWithAI(apps: apps) } }
                    } label: {
                        HStack(spacing: 4) { Image(systemName: "sparkles"); Text("AI 分析") }
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(.purple)
                    .disabled(selectedAppIds.isEmpty || service.isAnalyzingImpact)
                }
            }

            if subCategories.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        SubCategoryChip(label: "全部", count: service.installedApps.filter { $0.appType == filterType }.count, isActive: filterSubCategory.isEmpty, color: .accentColor) { filterSubCategory = "" }
                        ForEach(subCategories, id: \.self) { cat in
                            let count = service.installedApps.filter { $0.appType == filterType && $0.subCategory == cat }.count
                            SubCategoryChip(label: cat, count: count, isActive: filterSubCategory == cat, color: subCategoryColor(cat)) { filterSubCategory = filterSubCategory == cat ? "" : cat }
                        }
                    }.padding(.horizontal, 24).padding(.vertical, 8)
                }.background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                Divider()
            }

            HStack(spacing: 12) {
                FilterSearchBar(placeholder: "搜索应用...", text: $searchText)
                    .frame(width: 200)

                Spacer()

                if !selectedAppIds.isEmpty {
                    Text("已选 \(selectedAppIds.count) 项 · \(service.formatSize(selectedTotalSize))").font(.caption).foregroundColor(.blue).fontWeight(.medium)
                }

                HStack(spacing: 4) {
                    Button { selectedAppIds = Set(filteredApps.map(\.id)) } label: { Text("全选") }.buttonStyle(.bordered).controlSize(.small)
                    Button { selectedAppIds.removeAll() } label: { Text("取消") }.buttonStyle(.bordered).controlSize(.small)
                }

                ForEach(AppAction.allCases, id: \.self) { action in
                    Button { pendingAction = action; pendingAppIds = Array(selectedAppIds); showActionConfirm = true } label: {
                        HStack(spacing: 4) { Image(systemName: action.icon); Text(action.rawValue) }
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
                            Text(action.rawValue).font(.caption).fontWeight(.semibold)
                            Text(action.desc).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 6)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))

            Divider()

            if service.isScanningApps {
                VStack(spacing: 16) { ProgressView().controlSize(.large); Text("正在扫描...").foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: filterType == .app ? "app.dashed" : filterType == .dependency ? "cube.box" : "terminal")
                        .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
                    Text("未发现\(filterType.label)").font(.title3).fontWeight(.medium)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(filteredApps, selection: $selectedAppIds) {
                    TableColumn("✓") { app in Toggle("", isOn: Binding(get: { selectedAppIds.contains(app.id) }, set: { _ in if selectedAppIds.contains(app.id) { selectedAppIds.remove(app.id) } else { selectedAppIds.insert(app.id) } })).toggleStyle(.checkbox).labelsHidden() }.width(36)
                    TableColumn("名称") { app in
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
                    TableColumn("风险") { app in
                        HStack(spacing: 3) {
                            let rc: Color = app.risk == "safe" ? .green : app.risk == "dangerous" ? .red : .orange
                            let rl: String = app.risk == "safe" ? "安全" : app.risk == "dangerous" ? "危险" : "注意"
                            Image(systemName: app.risk == "safe" ? "checkmark.circle.fill" : app.risk == "dangerous" ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(rc).font(.caption)
                            Text(rl).font(.caption2).fontWeight(.medium).foregroundColor(rc)
                        }
                    }.width(60)
                    TableColumn("影响说明") { app in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.riskDesc).font(.caption2).foregroundColor(.orange).lineLimit(2)
                            if let aiResult = service.aiAnalysisMap[app.id] {
                                Text(aiResult).font(.caption2).fontWeight(.medium)
                                    .foregroundColor(aiResult.hasPrefix("🤖") ? .purple : aiResult.hasPrefix("❌") ? .red : aiResult.hasPrefix("⚠️") ? .yellow : .secondary)
                                    .lineLimit(2)
                            }
                        }
                    }.width(min: 140)
                    TableColumn("大小") { app in
                        Text(service.formatSize(app.totalSize)).fontWeight(.bold).monospacedDigit().foregroundColor(.cyan)
                    }.width(80)
                    TableColumn("操作") { app in
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
        .alert("确认操作", isPresented: $showActionConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认", role: .destructive) { performAction() }
        } message: {
            let apps = selectedApps
            let size = pendingAction == .basicUninstall ? apps.reduce(Int64(0)) { $0 + $1.appSize } : apps.reduce(Int64(0)) { $0 + $1.totalSize }
            Text("\(pendingAction.desc)\n\n将\(pendingAction.rawValue) \(apps.count) 项，共 \(service.formatSize(size))")
        }
        .alert("操作完成", isPresented: $showActionResult) {
            Button("确定") {}
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
            for app in apps {
                let ok: Bool
                switch pendingAction {
                case .reset: ok = await service.resetApp(app: app)
                case .basicUninstall: ok = await service.basicUninstall(app: app)
                case .fullUninstall: ok = await service.fullUninstall(app: app)
                }
                if ok { successCount += 1 } else { failCount += 1 }
            }
            await service.scanInstalledApps()
            service.refreshDiskInfo()
            selectedAppIds.removeAll()
            actionResultMsg = "\(pendingAction.rawValue)完成：成功 \(successCount) 个" + (failCount > 0 ? "，失败 \(failCount) 个" : "")
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

// MARK: - Storage Analysis Tab

struct StorageAnalysisTab: View {
    @ObservedObject var analyzer: StorageAnalyzer
    @ObservedObject var service: ScannerService
    @State private var selectedCategory: StorageCategory?
    @State private var sortField: StorageFile.SortField = .size
    @State private var sortAscending = false
    @State private var showAIAnalysis = false
    @State private var aiAnalysisText = ""
    @State private var isAnalyzing = false
    @State private var analyzingFileName = ""

    var sortedFiles: [StorageFile] {
        guard let cat = selectedCategory else { return [] }
        let files = cat.files
        return files.sorted { a, b in
            switch sortField {
            case .size: return sortAscending ? a.size < b.size : a.size > b.size
            case .name: return sortAscending ? a.name < b.name : a.name > b.name
            case .created:
                let da = a.createdDate ?? .distantPast
                let db = b.createdDate ?? .distantPast
                return sortAscending ? da < db : da > db
            case .modified:
                let da = a.modifiedDate ?? .distantPast
                let db = b.modifiedDate ?? .distantPast
                return sortAscending ? da < db : da > db
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "chart.pie",
                title: "存储分析",
                subtitle: "存储空间分析与AI建议",
                color: .indigo
            ) {
                HStack(spacing: 8) {
                    Button { Task { await analyzer.scanStorage() } } label: {
                        HStack(spacing: 4) { Image(systemName: "arrow.clockwise"); Text(analyzer.isScanning ? analyzer.scanProgress : "扫描") }
                    }
                    .buttonStyle(.bordered).controlSize(.small).disabled(analyzer.isScanning)

                    if analyzer.categories.isEmpty {
                        EmptyView()
                    } else {
                        Button {
                            Task { await analyzeCategory() }
                        } label: {
                            HStack(spacing: 4) { Image(systemName: "sparkles"); Text("AI 分析") }
                        }
                        .buttonStyle(.bordered).controlSize(.small).tint(.purple)
                        .disabled(isAnalyzing || service.aiConfig?.hasKey != true)
                    }
                }
            }

            if analyzer.isScanning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(analyzer.scanProgress).foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 24).padding(.vertical, 8)
                .background(Color.indigo.opacity(0.05))
                Divider()
            }

            if !aiAnalysisText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "sparkles").foregroundColor(.purple).font(.caption)
                        Text("AI 分析结果").font(.caption).fontWeight(.semibold).foregroundColor(.purple)
                        Spacer()
                        Button { aiAnalysisText = "" } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary) }.buttonStyle(.plain)
                    }
                    ScrollView {
                        Text(aiAnalysisText).font(.caption).foregroundColor(.primary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 150)
                }
                .padding(12).background(Color.purple.opacity(0.05))
                Divider()
            }

            if analyzer.categories.isEmpty {
                VStack(spacing: 20) {
                    Spacer()
                    Image(systemName: "chart.pie").font(.system(size: 48)).foregroundColor(.secondary.opacity(0.5))
                    Text("存储分析").font(.title3).fontWeight(.medium)
                    Text("点击扫描分析存储空间使用情况").font(.caption).foregroundColor(.secondary)
                    Button("开始扫描") { Task { await analyzer.scanStorage() } }
                        .buttonStyle(.borderedProminent).tint(.indigo).controlSize(.regular)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    categorySidebar
                    Divider()
                    fileDetailPanel
                }
            }
        }
        .alert("AI 分析", isPresented: $showAIAnalysis) {
            Button("确定") {}
        } message: {
            Text(aiAnalysisText)
        }
    }

    private var categorySidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("存储分类").font(.caption).fontWeight(.semibold).foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 6)

            let totalSize = analyzer.categories.reduce(Int64(0)) { $0 + $1.size }
            ForEach(analyzer.categories) { cat in
                Button {
                    selectedCategory = cat
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 12))
                            .foregroundColor(selectedCategory?.id == cat.id ? cat.color : .secondary)
                            .frame(width: 16)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(cat.name)
                                .font(.system(size: 12))
                                .fontWeight(selectedCategory?.id == cat.id ? .semibold : .regular)
                                .foregroundColor(selectedCategory?.id == cat.id ? .primary : .secondary)

                            let pct = totalSize > 0 ? Double(cat.size) / Double(totalSize) * 100 : 0
                            ProgressView(value: pct / 100.0)
                                .progressViewStyle(.linear)
                                .tint(cat.color)
                                .frame(height: 3)
                        }

                        Text(cat.sizeFormatted)
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(selectedCategory?.id == cat.id ? cat.color.opacity(0.1) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text("已使用").font(.caption2).foregroundColor(.secondary)
                Text(ByteCountFormatter.string(fromByteCount: analyzer.totalUsed, countStyle: .file))
                    .font(.caption).fontWeight(.bold).foregroundColor(.indigo)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .frame(width: 200)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }

    private var fileDetailPanel: some View {
        VStack(spacing: 0) {
            if let cat = selectedCategory {
                HStack(spacing: 12) {
                    Text(cat.name)
                        .font(.headline)
                    Text("\(cat.files.count) 项 · \(cat.sizeFormatted)")
                        .font(.caption).foregroundColor(.secondary)

                    Spacer()

                    HStack(spacing: 6) {
                        Text("排序:").font(.caption).foregroundColor(.secondary)
                        ForEach(StorageFile.SortField.allCases, id: \.self) { field in
                            Button {
                                if sortField == field { sortAscending.toggle() }
                                else { sortField = field; sortAscending = false }
                            } label: {
                                HStack(spacing: 2) {
                                    Image(systemName: field.icon).font(.caption2)
                                    Text(field.rawValue).font(.caption2)
                                    if sortField == field {
                                        Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                            .font(.system(size: 8))
                                    }
                                }
                                .foregroundColor(sortField == field ? .accentColor : .secondary)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 4).fill(sortField == field ? Color.accentColor.opacity(0.1) : Color.clear))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 20).padding(.vertical, 10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                Divider()

                if sortedFiles.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "folder.open").font(.system(size: 36)).foregroundColor(.secondary.opacity(0.5))
                        Text("无大文件（>1MB）").font(.callout).foregroundColor(.secondary)
                        Spacer()
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Table(sortedFiles) {
                        TableColumn("名称") { file in
                            HStack(spacing: 6) {
                                Image(systemName: file.isDirectory ? "folder.fill" : "doc.fill")
                                    .font(.caption)
                                    .foregroundColor(file.isDirectory ? .blue : .gray)
                                Text(file.name)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .help(file.path)
                            }
                        }.width(min: 180)

                        TableColumn("大小") { file in
                            Text(file.sizeFormatted)
                                .font(.caption)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(.cyan)
                        }.width(80)

                        TableColumn("添加日期") { file in
                            if let date = file.createdDate {
                                Text(date, style: .date).font(.caption2).foregroundColor(.secondary)
                            } else {
                                Text("-").font(.caption2).foregroundColor(.secondary)
                            }
                        }.width(90)

                        TableColumn("修改日期") { file in
                            if let date = file.modifiedDate {
                                Text(date, style: .date).font(.caption2).foregroundColor(.secondary)
                            } else {
                                Text("-").font(.caption2).foregroundColor(.secondary)
                            }
                        }.width(90)

                        TableColumn("AI 分析") { file in
                            if let analysis = file.aiAnalysis {
                                Text(analysis).font(.caption2).foregroundColor(.purple).lineLimit(2)
                            } else {
                                Button {
                                    Task { await analyzeFile(file) }
                                } label: {
                                    HStack(spacing: 2) {
                                        if isAnalyzing && analyzingFileName == file.name {
                                            ProgressView().controlSize(.mini)
                                        } else {
                                            Image(systemName: "sparkle").font(.caption2)
                                        }
                                        Text("分析").font(.caption2)
                                    }
                                    .foregroundColor(.purple)
                                }
                                .buttonStyle(.plain)
                                .disabled(isAnalyzing)
                            }
                        }.width(min: 120)
                    }
                    .tableStyle(.inset(alternatesRowBackgrounds: true))
                }
            } else {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "arrow.left.circle").font(.system(size: 36)).foregroundColor(.secondary.opacity(0.5))
                    Text("选择左侧分类查看文件列表").font(.callout).foregroundColor(.secondary)
                    Spacer()
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func analyzeFile(_ file: StorageFile) async {
        guard let config = service.aiConfig, config.hasKey == true else { return }
        await MainActor.run {
            isAnalyzing = true
            analyzingFileName = file.name
        }
        let result = await analyzer.analyzeFileWithAI(file: file, config: config)
        await MainActor.run {
            isAnalyzing = false
            analyzingFileName = ""
            if let result = result {
                if let catIndex = analyzer.categories.firstIndex(where: { $0.id == selectedCategory?.id }),
                   let fileIndex = analyzer.categories[catIndex].files.firstIndex(where: { $0.id == file.id }) {
                    analyzer.categories[catIndex].files[fileIndex].aiAnalysis = result
                }
            }
        }
    }

    private func analyzeCategory() async {
        guard let config = service.aiConfig, config.hasKey == true, let cat = selectedCategory else { return }
        await MainActor.run {
            isAnalyzing = true
            analyzingFileName = cat.name
        }
        let result = await analyzer.analyzeCategoryWithAI(category: cat, config: config)
        await MainActor.run {
            isAnalyzing = false
            analyzingFileName = ""
            if let result = result {
                aiAnalysisText = result
            }
        }
    }
}
