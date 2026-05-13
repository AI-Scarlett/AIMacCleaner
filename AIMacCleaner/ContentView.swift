import SwiftUI

struct ContentView: View {
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
    @State private var sidebarSelection: SidebarItem? = .all

    enum SidebarItem: Hashable {
        case all
        case category(String)
        case app(String)
    }

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
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showAIConfig = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape")
                        Text("AI 设置")
                    }
                }
                .help("AI 配置")
            }
        }
        .sheet(isPresented: $showAIConfig) {
            AIConfigView().environmentObject(service)
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

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section("概览") {
                Label("全部项目", systemImage: "externaldrive.fill")
                    .tag(SidebarItem.all)
            }

            Section("按分类") {
                ForEach(categories, id: \.self) { cat in
                    let size = service.scanItems.filter { $0.category == cat }.reduce(Int64(0)) { $0 + $1.size }
                    Label {
                        HStack {
                            Text(cat)
                            Spacer()
                            Text(service.formatSize(size))
                                .foregroundColor(.secondary).font(.caption)
                        }
                    } icon: {
                        Image(systemName: categoryIcon(cat))
                    }
                    .tag(SidebarItem.category(cat))
                }
            }

            Section("按应用") {
                ForEach(apps, id: \.self) { app in
                    let size = service.scanItems.filter { $0.app == app }.reduce(Int64(0)) { $0 + $1.size }
                    HStack {
                        Text(app).lineLimit(1).truncationMode(.tail)
                        Spacer()
                        Text(service.formatSize(size))
                            .foregroundColor(.secondary).font(.caption)
                    }
                    .tag(SidebarItem.app(app))
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .onChange(of: sidebarSelection) { newValue in
            filterCategory = ""
            filterApp = ""
            filterRisk = ""
            filterSource = ""
            switch newValue {
            case .category(let cat): filterCategory = cat
            case .app(let app): filterApp = app
            default: break
            }
        }
    }

    private func categoryIcon(_ cat: String) -> String {
        switch cat {
        case "浏览器": return "globe"
        case "办公": return "briefcase"
        case "AI Agent": return "cpu"
        case "开发": return "hammer"
        case "系统": return "gearshape.2"
        case "社交": return "bubble.left.and.bubble.right"
        default: return "folder"
        }
    }

    // MARK: - Detail View

    private var detailView: some View {
        VStack(spacing: 0) {
            diskCard
            Divider()

            if service.isAiScanning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text(service.aiStatusMessage).foregroundColor(.purple)
                    Spacer()
                }
                .padding(12).background(Color.purple.opacity(0.05))
                Divider()
            }

            if let error = service.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                    Text(error).font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button { service.errorMessage = nil } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
                .padding(12).background(Color.orange.opacity(0.05))
                Divider()
            }

            if service.isScanning {
                scanningOverlay
            } else if service.scanItems.isEmpty {
                welcomeCenter
            } else {
                searchAndFilterBar
                Divider()

                if !selectedIds.isEmpty {
                    selectionActionBar
                    Divider()
                }

                if filteredItems.isEmpty {
                    noResultView
                } else {
                    resultList
                }
            }
        }
    }

    // MARK: - Disk Card

    private var diskCard: some View {
        HStack(spacing: 32) {
            if let disk = service.diskInfo {
                VStack(alignment: .leading, spacing: 6) {
                    Text("磁盘空间").font(.headline)
                    ProgressView(value: disk.usedPct / 100.0)
                        .progressViewStyle(.linear)
                        .tint(disk.usedPct > 85 ? .red : disk.usedPct > 70 ? .orange : .green)
                    Text(String(format: "%.1f%% 已使用", disk.usedPct))
                        .font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: 280)

                HStack(spacing: 28) {
                    DiskStat(title: "总容量", value: String(format: "%.0f GB", disk.totalGb))
                    DiskStat(title: "已使用", value: String(format: "%.0f GB", disk.usedGb))
                    DiskStat(title: "可用", value: String(format: "%.0f GB", disk.freeGb), color: disk.freeGb < 20 ? .red : .green)
                    DiskStat(title: "可释放", value: service.formatSize(totalCleanable), color: .cyan)
                }

                Spacer()
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Scanning Overlay

    private var scanningOverlay: some View {
        VStack(spacing: 20) {
            ProgressView()
                .controlSize(.large)
            Text("正在扫描存储空间...")
                .font(.title3).fontWeight(.medium)
            Text("请稍候，正在分析可清理的文件")
                .foregroundColor(.secondary).font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Welcome Center (仅本地扫描 + AI扫描)

    private var welcomeCenter: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 48)).foregroundColor(.accentColor.opacity(0.6))
                Text("AIMacCleaner")
                    .font(.title).fontWeight(.bold)
                Text("智能清理 Mac 存储空间")
                    .foregroundColor(.secondary).font(.callout)
            }

            HStack(spacing: 28) {
                ActionCard(
                    icon: "magnifyingglass",
                    title: "本地扫描",
                    subtitle: "扫描缓存、日志等可清理文件",
                    color: .blue,
                    isDisabled: service.isScanning
                ) {
                    Task { await service.scanLocal() }
                }

                ActionCard(
                    icon: "brain",
                    title: "AI 扫描",
                    subtitle: "大模型智能分析可清理目录",
                    color: .purple,
                    isDisabled: service.isAiScanning
                ) {
                    Task { await performAiScan() }
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - No Result View (筛选无结果)

    private var noResultView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
            Text("当前筛选条件下没有匹配项")
                .font(.title3).fontWeight(.medium)
            HStack(spacing: 10) {
                if !filterRisk.isEmpty {
                    Button { filterRisk = "" } label: {
                        Text("清除风险筛选")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                if !filterCategory.isEmpty {
                    Button { filterCategory = ""; sidebarSelection = .all } label: {
                        Text("清除分类筛选")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                if !filterApp.isEmpty {
                    Button { filterApp = ""; sidebarSelection = .all } label: {
                        Text("清除应用筛选")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Text("清除搜索")
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Search & Filter Bar (含风险筛选 + 智能清理大按钮)

    private var searchAndFilterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                TextField("搜索项目...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(6)
            .frame(width: 160)

            Divider().frame(height: 16)

            HStack(spacing: 6) {
                Text("风险:").font(.caption).foregroundColor(.secondary)
                RiskFilterButton(label: "安全", color: .green, isActive: filterRisk == "safe") {
                    filterRisk = "safe"
                }
                RiskFilterButton(label: "注意", color: .orange, isActive: filterRisk == "caution") {
                    filterRisk = "caution"
                }
                RiskFilterButton(label: "危险", color: .red, isActive: filterRisk == "dangerous") {
                    filterRisk = "dangerous"
                }
                if !filterRisk.isEmpty {
                    Button { filterRisk = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary)
                    }.buttonStyle(.plain).help("清除风险筛选")
                }
            }

            if hasOtherFilters {
                HStack(spacing: 6) {
                    if !filterCategory.isEmpty { FilterChip(label: filterCategory) { filterCategory = ""; sidebarSelection = .all } }
                    if !filterApp.isEmpty { FilterChip(label: filterApp) { filterApp = ""; sidebarSelection = .all } }
                    if !filterSource.isEmpty { FilterChip(label: filterSource == "ai" ? "AI" : "本地") { filterSource = "" } }
                }
            }

            Spacer()

            Button { smartClean() } label: {
                Label("智能清理", systemImage: "wand.and.stars")
            }
            .buttonStyle(.borderedProminent).tint(.green).controlSize(.regular)
            .disabled(service.scanItems.filter { $0.risk == "safe" && !$0.ignored }.isEmpty)
            .help("一键清理所有安全项")

            Text("\(filteredItems.count) 项 · \(service.formatSize(totalCleanable))")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private var hasOtherFilters: Bool {
        !filterSource.isEmpty || !filterCategory.isEmpty || !filterApp.isEmpty
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        HStack(spacing: 10) {
            Button { selectAll() } label: { Text("全选") }
                .buttonStyle(.bordered).controlSize(.small)
            Button { selectSafe() } label: { Text("仅安全") }
                .buttonStyle(.bordered).controlSize(.small)
            Button { selectedIds.removeAll() } label: { Text("取消选择") }
                .buttonStyle(.bordered).controlSize(.small)

            Text("已选 \(selectedIds.count) 项 · \(service.formatSize(selectedSize))")
                .font(.caption).foregroundColor(.blue).fontWeight(.medium)

            Spacer()

            Button { ignoreSelected() } label: {
                Label("忽略选中", systemImage: "eye.slash")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .disabled(selectedIds.isEmpty)

            Button { confirmDeleteSelected() } label: {
                Label("删除选中", systemImage: "trash")
            }
            .buttonStyle(.bordered).tint(.red).controlSize(.small)
            .disabled(selectedIds.isEmpty)
        }
        .padding(.horizontal, 20).padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.06))
    }

    // MARK: - Result List

    private var resultList: some View {
        Table(filteredItems, selection: $selectedIds) {
            TableColumn("✓") { item in
                Toggle("", isOn: Binding(
                    get: { selectedIds.contains(item.id) },
                    set: { _ in
                        if selectedIds.contains(item.id) { selectedIds.remove(item.id) }
                        else { selectedIds.insert(item.id) }
                    }
                ))
                .toggleStyle(.checkbox).labelsHidden()
            }
            .width(36)

            TableColumn("名称") { item in
                HStack(spacing: 6) {
                    if item.ignored { Image(systemName: "eye.slash").foregroundColor(.secondary).font(.caption) }
                    Text(item.name).fontWeight(.semibold)
                }
            }
            .width(min: 150)

            TableColumn("来源") { item in
                Text(item.sourceType.label)
                    .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(item.sourceType == .ai ? Color.purple.opacity(0.12) : Color.blue.opacity(0.12))
                    .cornerRadius(4)
            }
            .width(50)

            TableColumn("应用") { item in
                Text(item.app).font(.caption).foregroundColor(.secondary)
            }
            .width(90)

            TableColumn("风险") { item in
                HStack(spacing: 3) {
                    Image(systemName: item.riskLevel.systemImage)
                        .foregroundColor(riskColor(item.riskLevel)).font(.caption)
                    Text(item.riskLevel.label).font(.caption2).fontWeight(.medium)
                }
            }
            .width(60)

            TableColumn("大小") { item in
                Text(service.formatSize(item.size))
                    .fontWeight(.bold).monospacedDigit().foregroundColor(.cyan)
            }
            .width(70)

            TableColumn("说明") { item in
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.reason ?? item.riskDesc)
                        .font(.caption2).foregroundColor(item.sourceType == .ai ? .purple : .orange).lineLimit(2)
                }
            }

            TableColumn("操作") { item in
                HStack(spacing: 4) {
                    Button { confirmDeleteSingle(item) } label: {
                        Image(systemName: "trash").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.mini).tint(.red)

                    Button { toggleIgnore(item) } label: {
                        Image(systemName: item.ignored ? "eye" : "eye.slash").font(.caption)
                    }
                    .buttonStyle(.bordered).controlSize(.mini)
                }
            }
            .width(70)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Helpers

    private func riskColor(_ level: ScanItem.RiskLevel) -> Color {
        switch level { case .safe: .green; case .caution: .orange; case .dangerous: .red }
    }

    private func selectAll() { selectedIds = Set(filteredItems.filter { !$0.ignored }.map(\.id)) }
    private func selectSafe() { selectedIds = Set(filteredItems.filter { $0.risk == "safe" && !$0.ignored }.map(\.id)) }

    private func smartClean() {
        let safeItems = service.scanItems.filter { $0.risk == "safe" && !$0.ignored }
        guard !safeItems.isEmpty else { return }
        deleteTargetIds = safeItems.map(\.id)
        showDeleteConfirm = true
    }

    private func performAiScan() async {
        if service.aiConfig?.hasKey != true { showAIConfig = true; return }
        await service.startAiScan()
    }

    private func confirmDeleteSelected() {
        deleteTargetIds = Array(selectedIds)
        showDeleteConfirm = true
    }

    private func confirmDeleteSingle(_ item: ScanItem) {
        deleteTargetIds = [item.id]
        showDeleteConfirm = true
    }

    private func performDelete() {
        let sizeBefore = service.scanItems.filter { deleteTargetIds.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }
        let countBefore = deleteTargetIds.count
        Task {
            let _ = await service.deleteItems(ids: deleteTargetIds)
            selectedIds.subtract(deleteTargetIds)
            deleteTargetIds = []
            await service.scanLocal()
            service.refreshDiskInfo()
            cleanedSize = sizeBefore
            cleanedCount = countBefore
            showCleanResult = true
        }
    }

    private func ignoreSelected() {
        service.ignoreItems(ids: Array(selectedIds))
        selectedIds.removeAll()
    }

    private func toggleIgnore(_ item: ScanItem) {
        if item.ignored { service.unignoreItems(ids: [item.id]) }
        else { service.ignoreItems(ids: [item.id]) }
    }
}

// MARK: - Action Card

struct ActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let isDisabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundColor(isDisabled ? .secondary : color)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(isDisabled ? .secondary : .primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
            .frame(width: 160, height: 150)
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isHovered && !isDisabled ? color.opacity(0.08) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isHovered && !isDisabled ? color.opacity(0.4) : Color(nsColor: .separatorColor), lineWidth: isHovered && !isDisabled ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Risk Filter Button

struct RiskFilterButton: View {
    let label: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Circle().fill(isActive ? color : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(label).font(.caption2).fontWeight(isActive ? .bold : .regular)
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isActive ? color.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isActive ? color.opacity(0.5) : Color.secondary.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .foregroundColor(isActive ? color : .secondary)
    }
}

// MARK: - Sub Components

struct DiskStat: View {
    let title: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption2).foregroundColor(.secondary).textCase(.uppercase)
            Text(value).font(.title3).fontWeight(.bold).foregroundColor(color)
        }
    }
}

struct FilterChip: View {
    let label: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(label).font(.caption2).fontWeight(.medium)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(10)
    }
}
