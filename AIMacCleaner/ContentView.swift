import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            MacCleanerTab()
                .tabItem { Label("Mac 清理", systemImage: "arrow.down.doc.fill") }
                .tag(0)

            AppManagerTab(filterType: .app)
                .tabItem { Label("APP 管理", systemImage: "app.badge") }
                .tag(1)

            AppManagerTab(filterType: .dependency)
                .tabItem { Label("依赖管理", systemImage: "cube.box") }
                .tag(2)

            AppManagerTab(filterType: .other)
                .tabItem { Label("其它工具", systemImage: "terminal") }
                .tag(3)
        }
    }
}

// MARK: - Mac Cleaner Tab (保持不变)

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
                    HStack(spacing: 4) { Image(systemName: "gearshape"); Text("AI 设置") }
                }
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

    private var sidebar: some View {
        List(selection: $sidebarSelection) {
            Section("概览") {
                Label("全部项目", systemImage: "externaldrive.fill").tag(SidebarItem.all)
            }
            Section("按分类") {
                ForEach(categories, id: \.self) { cat in
                    let size = service.scanItems.filter { $0.category == cat }.reduce(Int64(0)) { $0 + $1.size }
                    Label {
                        HStack { Text(cat); Spacer(); Text(service.formatSize(size)).foregroundColor(.secondary).font(.caption) }
                    } icon: { Image(systemName: categoryIcon(cat)) }
                    .tag(SidebarItem.category(cat))
                }
            }
            Section("按应用") {
                ForEach(apps, id: \.self) { app in
                    let size = service.scanItems.filter { $0.app == app }.reduce(Int64(0)) { $0 + $1.size }
                    HStack { Text(app).lineLimit(1).truncationMode(.tail); Spacer(); Text(service.formatSize(size)).foregroundColor(.secondary).font(.caption) }
                    .tag(SidebarItem.app(app))
                }
            }
        }
        .listStyle(.sidebar).frame(minWidth: 200)
        .onChange(of: sidebarSelection) { newValue in
            filterCategory = ""; filterApp = ""; filterRisk = ""; filterSource = ""
            switch newValue {
            case .category(let cat): filterCategory = cat
            case .app(let app): filterApp = app
            default: break
            }
        }
    }

    private func categoryIcon(_ cat: String) -> String {
        switch cat {
        case "浏览器": "globe"; case "办公": "briefcase"; case "AI Agent": "cpu"
        case "开发": "hammer"; case "系统": "gearshape.2"; case "社交": "bubble.left.and.bubble.right"
        default: "folder"
        }
    }

    private var detailView: some View {
        VStack(spacing: 0) {
            diskCard
            Divider()
            if service.isAiScanning || service.isEnhancedScanning {
                HStack(spacing: 10) { ProgressView().controlSize(.small); Text(service.isEnhancedScanning ? "增强扫描中..." : service.aiStatusMessage).foregroundColor(.purple); Spacer() }
                    .padding(12).background(Color.purple.opacity(0.05)); Divider()
            }
            if let error = service.errorMessage {
                HStack(spacing: 10) { Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange); Text(error).font(.caption).foregroundColor(.secondary).lineLimit(3); Spacer()
                    Button { service.errorMessage = nil } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain)
                }.padding(12).background(Color.orange.opacity(0.05)); Divider()
            }
            if service.isScanning { scanningOverlay }
            else if service.scanItems.isEmpty { welcomeCenter }
            else {
                searchAndFilterBar; Divider()
                if !selectedIds.isEmpty { selectionActionBar; Divider() }
                if filteredItems.isEmpty { noResultView } else { resultList }
            }
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
        }.padding(20).background(Color(nsColor: .windowBackgroundColor))
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
                if !filterCategory.isEmpty { Button { filterCategory = ""; sidebarSelection = .all } label: { Text("清除分类筛选") }.buttonStyle(.bordered).controlSize(.small) }
                if !searchText.isEmpty { Button { searchText = "" } label: { Text("清除搜索") }.buttonStyle(.bordered).controlSize(.small) }
            }
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchAndFilterBar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Button { Task { await service.scanLocal() } } label: { HStack(spacing: 3) { Image(systemName: "magnifyingglass"); Text("本地扫描") } }
                    .buttonStyle(.bordered).controlSize(.small).disabled(service.isScanning)
                Button { Task { await performAiScan() } } label: { HStack(spacing: 3) { Image(systemName: "brain"); Text("AI 扫描") } }
                    .buttonStyle(.bordered).controlSize(.small).tint(.purple).disabled(service.isAiScanning)
            }
            Divider().frame(height: 16)
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease").foregroundColor(.secondary).font(.caption)
                TextField("搜索...", text: $searchText).textFieldStyle(.plain).font(.caption)
                if !searchText.isEmpty { Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary) }.buttonStyle(.plain) }
            }.padding(.horizontal, 8).padding(.vertical, 4).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(6).frame(width: 140)
            Divider().frame(height: 16)
            HStack(spacing: 6) {
                Text("风险:").font(.caption).foregroundColor(.secondary)
                RiskFilterButton(label: "安全", color: .green, isActive: filterRisk == "safe") { filterRisk = "safe" }
                RiskFilterButton(label: "注意", color: .orange, isActive: filterRisk == "caution") { filterRisk = "caution" }
                RiskFilterButton(label: "危险", color: .red, isActive: filterRisk == "dangerous") { filterRisk = "dangerous" }
                if !filterRisk.isEmpty { Button { filterRisk = "" } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary) }.buttonStyle(.plain) }
            }
            Spacer()
            Button { smartClean() } label: { Label("智能清理", systemImage: "wand.and.stars") }
                .buttonStyle(.borderedProminent).tint(.green).controlSize(.regular)
                .disabled(service.scanItems.filter { $0.risk == "safe" && !$0.ignored }.isEmpty)
            Text("\(filteredItems.count) 项 · \(service.formatSize(totalCleanable))").font(.caption).foregroundColor(.secondary)
        }.padding(.horizontal, 20).padding(.vertical, 8).background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
    }

    private var hasOtherFilters: Bool { !filterSource.isEmpty || !filterCategory.isEmpty || !filterApp.isEmpty }

    private var selectionActionBar: some View {
        HStack(spacing: 10) {
            Button { selectAll() } label: { Text("全选") }.buttonStyle(.bordered).controlSize(.small)
            Button { selectSafe() } label: { Text("仅安全") }.buttonStyle(.bordered).controlSize(.small)
            Button { selectedIds.removeAll() } label: { Text("取消选择") }.buttonStyle(.bordered).controlSize(.small)
            Text("已选 \(selectedIds.count) 项 · \(service.formatSize(selectedSize))").font(.caption).foregroundColor(.blue).fontWeight(.medium)
            Spacer()
            Button { ignoreSelected() } label: { Label("忽略选中", systemImage: "eye.slash") }.buttonStyle(.bordered).controlSize(.small).disabled(selectedIds.isEmpty)
            Button { confirmDeleteSelected() } label: { Label("删除选中", systemImage: "trash") }.buttonStyle(.bordered).tint(.red).controlSize(.small).disabled(selectedIds.isEmpty)
        }.padding(.horizontal, 20).padding(.vertical, 8).background(Color.accentColor.opacity(0.06))
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

// MARK: - App Manager Tab (通用，按类型筛选)

struct AppManagerTab: View {
    @EnvironmentObject var service: ScannerService
    let filterType: AppInfo.AppType
    @State private var searchText = ""
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

    var filteredApps: [AppInfo] {
        let base = service.installedApps.filter { $0.appType == filterType }
        if searchText.isEmpty { return base }
        let q = searchText.lowercased()
        return base.filter { $0.displayName.lowercased().contains(q) || $0.name.lowercased().contains(q) || $0.bundleId.lowercased().contains(q) || $0.desc.lowercased().contains(q) }
    }

    var selectedApps: [AppInfo] { service.installedApps.filter { selectedAppIds.contains($0.id) } }
    var selectedTotalSize: Int64 { selectedApps.reduce(0) { $0 + $1.totalSize } }

    var body: some View {
        VStack(spacing: 0) {
            actionBar
            Divider()
            if service.isScanningApps {
                VStack(spacing: 16) { ProgressView().controlSize(.large); Text("正在扫描...").foregroundColor(.secondary) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredApps.isEmpty {
                emptyView
            } else {
                appTable
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

    private var actionBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary).font(.caption)
                    TextField("搜索...", text: $searchText).textFieldStyle(.plain).font(.caption)
                    if !searchText.isEmpty { Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill").font(.caption).foregroundColor(.secondary) }.buttonStyle(.plain) }
                }.padding(.horizontal, 8).padding(.vertical, 4).background(Color(nsColor: .controlBackgroundColor)).cornerRadius(6).frame(width: 200)
                Spacer()
                Text("\(filteredApps.count) 项").font(.caption).foregroundColor(.secondary)
                Button { Task { await service.scanInstalledApps() } } label: { HStack(spacing: 3) { Image(systemName: "arrow.clockwise"); Text("刷新") } }
                    .buttonStyle(.bordered).controlSize(.small).disabled(service.isScanningApps)
            }.padding(.horizontal, 20).padding(.vertical, 10)

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Button { selectedAppIds = Set(filteredApps.map(\.id)) } label: { Text("全选") }.buttonStyle(.bordered).controlSize(.small)
                    Button { selectedAppIds.removeAll() } label: { Text("取消") }.buttonStyle(.bordered).controlSize(.small)
                    if !selectedAppIds.isEmpty { Text("已选 \(selectedAppIds.count) 项 · \(service.formatSize(selectedTotalSize))").font(.caption).foregroundColor(.blue).fontWeight(.medium) }
                }
                Spacer()
                ForEach(AppAction.allCases, id: \.self) { action in
                    Button { pendingAction = action; pendingAppIds = Array(selectedAppIds); showActionConfirm = true } label: {
                        HStack(spacing: 4) { Image(systemName: action.icon); Text(action.rawValue) }
                    }
                    .buttonStyle(.bordered).controlSize(.small).tint(action.color)
                    .disabled(selectedAppIds.isEmpty)
                }
            }.padding(.horizontal, 20).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))

            HStack(spacing: 20) {
                ForEach(AppAction.allCases, id: \.self) { action in
                    HStack(spacing: 6) {
                        Image(systemName: action.icon).foregroundColor(action.color).font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.rawValue).font(.caption).fontWeight(.semibold)
                            Text(action.desc).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }.padding(.horizontal, 20).padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: filterType == .app ? "app.dashed" : filterType == .dependency ? "cube.box" : "terminal")
                .font(.system(size: 40)).foregroundColor(.secondary.opacity(0.5))
            Text("未发现\(filterType.label)").font(.title3).fontWeight(.medium)
            Spacer()
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var appTable: some View {
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
                Text(app.riskDesc).font(.caption2).foregroundColor(.orange).lineLimit(2)
            }.width(min: 120)

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
        }.tableStyle(.inset(alternatesRowBackgrounds: true))
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

struct FilterChip: View {
    let label: String; let onRemove: () -> Void
    var body: some View {
        HStack(spacing: 4) { Text(label).font(.caption2).fontWeight(.medium); Button(action: onRemove) { Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.secondary) }.buttonStyle(.plain) }
            .padding(.horizontal, 8).padding(.vertical, 3).background(Color.accentColor.opacity(0.1)).cornerRadius(10)
    }
}
