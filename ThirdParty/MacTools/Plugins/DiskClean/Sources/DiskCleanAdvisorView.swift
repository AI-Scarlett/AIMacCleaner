import AppKit
import QuickLookUI
import SwiftUI
import MacToolsPluginKit

struct DiskCleanAdvisorOverviewView: View {
    @ObservedObject var model: DiskCleanAdvisorModel
    @ObservedObject var cleanupController: DiskCleanController
    let localization: PluginLocalization
    let openCleanup: () -> Void

    @State private var selectedFindingPaths: Set<String> = []
    @State private var visibleFindingLimit = 200

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            hero

            if let summary = model.storageSummary {
                metricGrid(summary)
                if let systemDataSummary = model.systemDataSummary {
                    systemDataBreakdown(systemDataSummary)
                }
                agentBreakdown(summary)
                cleanupFindings(summary)
                if !cleanupController.snapshot.scope.advisorFindings.isEmpty {
                    DiskCleanCleanupSectionView(
                        controller: cleanupController,
                        title: localization.string(
                            "advisor.cleanup.title",
                            defaultValue: "安全清理磁盘顾问建议"
                        ),
                        symbolName: "shield.checkered",
                        localization: localization
                    )
                }
            } else if !model.isScanning {
                DiskCleanEmptyState(
                    symbolName: "sparkles",
                    text: localization.string(
                        "advisor.empty",
                        defaultValue: "运行智能扫描，分析 Agent 会话、重复媒体、构建历史和安装包。"
                    )
                ) {
                    scanButton
                }
            }

            if let errorMessage = model.errorMessage {
                DiskCleanBanner(
                    symbolName: "xmark.octagon.fill",
                    tint: .red,
                    title: localization.string("detail.error.title", defaultValue: "操作未完成"),
                    lines: [errorMessage]
                )
            }
        }
        .onChange(of: model.storageCleanupItems) {
            selectedFindingPaths.formIntersection(Set(model.storageCleanupItems.map(\.path)))
            visibleFindingLimit = 200
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DiskCleanVisual.heroStart, DiskCleanVisual.heroEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Image(systemName: "internaldrive")
                .font(.system(size: 112, weight: .ultraLight))
                .foregroundStyle(.white.opacity(0.07))
                .offset(x: 16, y: 22)

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "sparkles.rectangle.stack.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 3) {
                        Text(localization.string("advisor.title", defaultValue: "AI 磁盘顾问"))
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                        Text(localization.string(
                            "advisor.subtitle",
                            defaultValue: "只在本机分析 Agent、构建和文件元数据，不读取或上传对话正文。"
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)
                    heroScanButton
                }

                HStack(alignment: .bottom, spacing: 24) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(localization.string("advisor.hero.agentStorage", defaultValue: "本机 Agent 存储"))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))
                        Text(model.storageSummary.map { DiskCleanFormat.bytes($0.agentSessionBytes) }
                            ?? localization.string("advisor.hero.pending", defaultValue: "等待分析"))
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }

                    if let summary = model.storageSummary {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(localization.string("advisor.hero.reviewable", defaultValue: "构建与安装包待复核"))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.68))
                            Text(DiskCleanFormat.bytes(summary.historicalBuildBytes + summary.installerArtifactBytes))
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                        }
                    }

                    Spacer(minLength: 0)

                    if model.isScanning {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text(stageText)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.76))
                                .lineLimit(2)
                        }
                        .frame(maxWidth: 210, alignment: .trailing)
                    }
                }
            }
            .padding(20)
        }
        .frame(minHeight: 178)
        .shadow(color: DiskCleanVisual.heroEnd.opacity(0.20), radius: 18, y: 8)
    }

    private var heroScanButton: some View {
        Button(action: model.scan) {
            Label(
                model.hasResult
                    ? localization.string("advisor.action.rescan", defaultValue: "重新分析")
                    : localization.string("advisor.action.scan", defaultValue: "开始分析"),
                systemImage: "magnifyingglass"
            )
            .font(.callout.weight(.semibold))
            .foregroundStyle(DiskCleanVisual.heroStart)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isScanning)
        .opacity(model.isScanning ? 0.55 : 1)
    }

    private var scanButton: some View {
        Button(action: model.scan) {
            Label(
                model.hasResult
                    ? localization.string("advisor.action.rescan", defaultValue: "重新分析")
                    : localization.string("advisor.action.scan", defaultValue: "开始分析"),
                systemImage: "magnifyingglass"
            )
            .font(PluginSettingsTheme.Typography.controlLabel)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        .disabled(model.isScanning)
    }

    private var stageText: String {
        switch model.stage {
        case .idle, .completed:
            return localization.string("advisor.stage.ready", defaultValue: "分析完成")
        case .agentAndBuildStorage:
            return localization.string(
                "advisor.stage.storage",
                defaultValue: "正在增量分析 Agent 会话、重复媒体与构建历史…"
            )
        case .systemData:
            return localization.string(
                "advisor.stage.systemData",
                defaultValue: "正在拆分系统数据来源（只读分析）…"
            )
        case .fileInventory:
            return localization.string(
                "advisor.stage.inventory",
                defaultValue: "Agent 与构建分析完成，正在建立文件分类索引…"
            )
        case .duplicateFiles:
            return localization.string(
                "advisor.stage.duplicates",
                defaultValue: "正在用内容指纹核对重复文件…"
            )
        }
    }

    private func systemDataBreakdown(_ summary: SystemDataStorageSummary) -> some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            DiskCleanSectionHeader(
                title: localization.string("advisor.systemData.title", defaultValue: "系统数据来源分析"),
                symbolName: "internaldrive.fill"
            )

            VStack(spacing: 0) {
                ForEach(summary.buckets, id: \.kind) { bucket in
                    HStack(spacing: PluginSettingsTheme.Spacing.rowContentControl) {
                        DiskCleanIconBadge(
                            symbolName: systemDataSymbol(bucket.kind),
                            tint: systemDataTint(bucket.disposition),
                            size: 34
                        )
                        VStack(alignment: .leading, spacing: 2) {
                            Text(systemDataTitle(bucket.kind))
                                .font(PluginSettingsTheme.Typography.rowTitle)
                            Text(systemDataDisposition(bucket.disposition))
                                .font(PluginSettingsTheme.Typography.statusBadge)
                                .foregroundStyle(systemDataTint(bucket.disposition))
                        }
                        Spacer()
                        Text(DiskCleanFormat.bytes(bucket.allocatedBytes))
                            .font(PluginSettingsTheme.Typography.monospacedValue)
                            .frame(width: DiskCleanFormat.byteColumnWidth, alignment: .trailing)
                    }
                    .pluginSettingsListRowPadding()
                    if bucket.kind != summary.buckets.last?.kind {
                        PluginSettingsListDivider()
                    }
                }
            }
            .diskCleanSurface(.elevated)

            Text(localization.format(
                "advisor.systemData.note",
                defaultValue: "本次只读测得 %@；macOS 的“系统数据”还可能包含 APFS 可清除空间和受保护数据，不能把系统设置中的总数直接当作可删除空间。%@",
                DiskCleanFormat.bytes(summary.measuredBytes),
                summary.wasTruncated
                    ? localization.string("advisor.systemData.truncated", defaultValue: " 部分路径因时限、权限或卷边界未完整测量；当前显示已测部分。")
                    : ""
            ))
            .font(PluginSettingsTheme.Typography.rowDescription)
            .foregroundStyle(.secondary)
        }
    }

    private func systemDataTitle(_ kind: SystemDataStorageKind) -> String {
        switch kind {
        case .caches: return localization.string("advisor.systemData.caches", defaultValue: "用户与应用缓存")
        case .temporary: return localization.string("advisor.systemData.temporary", defaultValue: "用户临时目录")
        case .developer: return localization.string("advisor.systemData.developer", defaultValue: "开发者与模拟器数据")
        case .applicationSupport: return localization.string("advisor.systemData.applicationSupport", defaultValue: "应用支持数据")
        case .appContainers: return localization.string("advisor.systemData.containers", defaultValue: "应用容器数据")
        case .systemDiagnostics: return localization.string("advisor.systemData.diagnostics", defaultValue: "系统诊断数据")
        case .virtualMemory: return localization.string("advisor.systemData.virtualMemory", defaultValue: "虚拟内存 / Swap")
        }
    }

    private func systemDataDisposition(_ disposition: SystemDataStorageDisposition) -> String {
        switch disposition {
        case .cleanable:
            return localization.string("advisor.systemData.cleanable", defaultValue: "可进入安全清理")
        case .reviewRequired:
            return localization.string("advisor.systemData.review", defaultValue: "需逐项复核")
        case .systemManaged:
            return localization.string("advisor.systemData.managed", defaultValue: "macOS 管理，不直接删除")
        }
    }

    private func systemDataSymbol(_ kind: SystemDataStorageKind) -> String {
        switch kind {
        case .caches: return "shippingbox.fill"
        case .temporary: return "clock.arrow.circlepath"
        case .developer: return "hammer.fill"
        case .applicationSupport: return "app.badge.fill"
        case .appContainers: return "square.stack.3d.up.fill"
        case .systemDiagnostics: return "waveform.path.ecg"
        case .virtualMemory: return "memorychip.fill"
        }
    }

    private func systemDataTint(_ disposition: SystemDataStorageDisposition) -> Color {
        switch disposition {
        case .cleanable: return .green
        case .reviewRequired: return .orange
        case .systemManaged: return .secondary
        }
    }

    private func metricGrid(_ summary: StorageOptimizationSummary) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 132, maximum: 220), spacing: 10)],
            spacing: 10
        ) {
            advisorMetric(
                icon: "bubble.left.and.bubble.right.fill",
                tint: .blue,
                title: localization.string("advisor.metric.sessions", defaultValue: "Agent 会话"),
                value: DiskCleanFormat.bytes(summary.agentSessionBytes),
                detail: localization.format(
                    "advisor.metric.sessions.detail",
                    defaultValue: "%d 个会话文件",
                    summary.agentSessionFileCount
                )
            )
            advisorMetric(
                icon: "square.on.square",
                tint: .purple,
                title: localization.string("advisor.metric.duplicates", defaultValue: "完全重复媒体"),
                value: DiskCleanFormat.bytes(summary.duplicateMediaBytes),
                detail: localization.string(
                    "advisor.metric.duplicates.detail",
                    defaultValue: "只分析，不改写 Agent 历史"
                )
            )
            advisorMetric(
                icon: "hammer.fill",
                tint: .orange,
                title: localization.string("advisor.metric.builds", defaultValue: "历史构建"),
                value: DiskCleanFormat.bytes(summary.historicalBuildBytes),
                detail: localization.format(
                    "advisor.metric.builds.detail",
                    defaultValue: "%d 项；保留最新 %d 项",
                    summary.historicalBuildCount,
                    summary.retainedBuildCount
                )
            )
            advisorMetric(
                icon: "shippingbox.fill",
                tint: .green,
                title: localization.string("advisor.metric.installers", defaultValue: "安装与分发包"),
                value: DiskCleanFormat.bytes(summary.installerArtifactBytes),
                detail: localization.format(
                    "advisor.metric.installers.detail",
                    defaultValue: "%d 项，需手动确认",
                    summary.installerArtifactCount
                )
            )
        }
    }

    private func advisorMetric(
        icon: String,
        tint: Color,
        title: String,
        value: String,
        detail: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                DiskCleanIconBadge(symbolName: icon, tint: tint, size: 30)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(PluginSettingsTheme.Typography.statusBadge)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
        .padding(14)
        .diskCleanSurface(.elevated)
    }

    @ViewBuilder
    private func agentBreakdown(_ summary: StorageOptimizationSummary) -> some View {
        if !summary.agentBreakdown.isEmpty {
            let largest = max(summary.agentBreakdown.map(\.sessionBytes).max() ?? 1, 1)
            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
                DiskCleanSectionHeader(
                    title: localization.string("advisor.agents.title", defaultValue: "Agent 存储明细"),
                    symbolName: "cpu"
                )
                VStack(spacing: 0) {
                    ForEach(Array(summary.agentBreakdown.prefix(12)), id: \.agentName) { agent in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 8) {
                                Text(agent.agentName)
                                    .font(PluginSettingsTheme.Typography.rowTitle)
                                Spacer()
                                if agent.duplicateMediaBytes > 0 {
                                    Text(localization.format(
                                        "advisor.agents.duplicate",
                                        defaultValue: "重复 %@",
                                        DiskCleanFormat.bytes(agent.duplicateMediaBytes)
                                    ))
                                    .font(PluginSettingsTheme.Typography.statusBadge)
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(Color.purple.opacity(0.1), in: Capsule())
                                }
                                Text(DiskCleanFormat.bytes(agent.sessionBytes))
                                    .font(PluginSettingsTheme.Typography.monospacedValue)
                            }

                            GeometryReader { proxy in
                                Capsule()
                                    .fill(Color.primary.opacity(0.06))
                                    .overlay(alignment: .leading) {
                                        LinearGradient(
                                            colors: [DiskCleanVisual.accentBlue, DiskCleanVisual.accent],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                        .clipShape(Capsule())
                                        .frame(
                                            width: max(
                                                6,
                                                proxy.size.width * CGFloat(agent.sessionBytes) / CGFloat(largest)
                                            )
                                        )
                                    }
                            }
                            .frame(height: 6)
                        }
                        .pluginSettingsListRowPadding()
                        if agent.agentName != summary.agentBreakdown.prefix(12).last?.agentName {
                            PluginSettingsListDivider()
                        }
                    }
                }
                .diskCleanSurface(.elevated)
            }
        }
    }

    private func cleanupFindings(_ summary: StorageOptimizationSummary) -> some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            DiskCleanSectionHeader(
                title: localization.string("advisor.findings.title", defaultValue: "可执行建议"),
                symbolName: "checklist"
            )
            HStack(alignment: .top, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
                Image(systemName: "shield.checkered")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: PluginSettingsTheme.Size.rowIcon)
                VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                    Text(localization.string(
                        "advisor.findings.safePipeline.title",
                        defaultValue: "清理操作统一进入安全流水线"
                    ))
                    .font(PluginSettingsTheme.Typography.rowTitle)
                    Text(localization.string(
                        "advisor.findings.safePipeline.detail",
                        defaultValue: "缓存、历史构建和安装包在“Mac 清理”中复核；重复媒体仅计算可优化上限，不直接改写 Agent 会话。"
                    ))
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)
                Button(action: openCleanup) {
                    Label(
                        localization.string("advisor.action.openCleanup", defaultValue: "打开 Mac 清理"),
                        systemImage: "arrow.right.circle"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .pluginSettingsListRowPadding()
            .diskCleanSurface(.accented)

            HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                Image(systemName: "bolt.horizontal.circle")
                    .foregroundStyle(.blue)
                Text(localization.format(
                    "advisor.cache.summary",
                    defaultValue: "增量缓存命中 %d 个文件；本次读取 %d 个 / %@，耗时 %.1f 秒。",
                    summary.cacheHitCount,
                    summary.hashedFileCount,
                    DiskCleanFormat.bytes(summary.fingerprintedBytes),
                    summary.scanDuration
                ))
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(.secondary)
            }

            if !model.storageCleanupItems.isEmpty {
                advisorFindingSelection
            }
        }
    }

    private var advisorFindingSelection: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                Text(localization.format(
                    "advisor.findings.count",
                    defaultValue: "%d 项历史构建或安装分发包",
                    model.storageCleanupItems.count
                ))
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(.secondary)

                Spacer()

                Button(localization.string("inventory.action.selectVisible", defaultValue: "选择当前结果")) {
                    for item in visibleAdvisorFindings
                    where selectedFindingPaths.count < DiskCleanAdvisorFindingExpansion.maximumSelectionCount {
                        selectedFindingPaths.insert(item.path)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(localization.string("inventory.action.clear", defaultValue: "清空")) {
                    selectedFindingPaths.removeAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(selectedFindingPaths.isEmpty)

                Button {
                    cleanupController.setScope(.advisorFindings(items: selectedAdvisorFindings))
                    cleanupController.scan()
                } label: {
                    Text(localization.format(
                        "inventory.action.prepare",
                        defaultValue: "安全检查 %d 项",
                        selectedAdvisorFindings.count
                    ))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(selectedAdvisorFindings.isEmpty || cleanupController.snapshot.isBusy)
            }

            VStack(spacing: 0) {
                ForEach(visibleAdvisorFindings, id: \.path) { item in
                    advisorFindingRow(item)
                    if item.path != visibleAdvisorFindings.last?.path {
                        PluginSettingsListDivider()
                    }
                }
            }
            .diskCleanSurface(.elevated)

            if visibleFindingLimit < model.storageCleanupItems.count {
                Button {
                    visibleFindingLimit = min(
                        visibleFindingLimit + 200,
                        model.storageCleanupItems.count
                    )
                } label: {
                    Label(
                        localization.string("inventory.action.more", defaultValue: "再显示 200 项"),
                        systemImage: "chevron.down.circle"
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func advisorFindingRow(_ item: StorageCleanupItem) -> some View {
        HStack(alignment: .top, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            Toggle(
                "",
                isOn: Binding(
                    get: { selectedFindingPaths.contains(item.path) },
                    set: { selected in
                        if selected {
                            if selectedFindingPaths.count < DiskCleanAdvisorFindingExpansion.maximumSelectionCount {
                                selectedFindingPaths.insert(item.path)
                            }
                        } else {
                            selectedFindingPaths.remove(item.path)
                        }
                    }
                )
            )
            .toggleStyle(.checkbox)
            .labelsHidden()

            Image(systemName: item.isDirectory ? "folder.fill" : "shippingbox.fill")
                .foregroundStyle(item.kind == .historicalBuild ? Color.orange : Color.green)
                .frame(width: PluginSettingsTheme.Size.rowIcon)

            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                    Text(item.name)
                        .font(PluginSettingsTheme.Typography.rowTitle)
                        .lineLimit(1)
                    Text(advisorFindingKind(item.kind))
                        .font(PluginSettingsTheme.Typography.statusBadge)
                        .foregroundStyle(.secondary)
                }
                Text(item.path)
                    .font(PluginSettingsTheme.Typography.monospacedValue)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)
            Text(DiskCleanFormat.bytes(item.size))
                .font(PluginSettingsTheme.Typography.monospacedValue)
                .frame(width: DiskCleanFormat.byteColumnWidth, alignment: .trailing)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(localization.string("inventory.action.reveal", defaultValue: "在 Finder 中显示"))
        }
        .pluginSettingsListRowPadding(interactive: true)
    }

    private var visibleAdvisorFindings: [StorageCleanupItem] {
        Array(model.storageCleanupItems.prefix(visibleFindingLimit))
    }

    private var selectedAdvisorFindings: [DiskCleanAdvisorFinding] {
        model.storageCleanupItems.compactMap { item in
            guard selectedFindingPaths.contains(item.path) else { return nil }
            return DiskCleanAdvisorFinding(path: item.path, kind: item.kind)
        }
    }

    private func advisorFindingKind(_ kind: StorageCleanupItemKind) -> String {
        switch kind {
        case .historicalBuild:
            return localization.string("advisor.metric.builds", defaultValue: "历史构建")
        case .installerArtifact:
            return localization.string("advisor.metric.installers", defaultValue: "安装与分发包")
        }
    }
}

private enum DiskCleanFileInventoryMode: String, CaseIterable, Identifiable {
    case all
    case large
    case duplicates

    var id: String { rawValue }
}

struct DiskCleanFileInventoryView: View {
    @ObservedObject var model: DiskCleanAdvisorModel
    @ObservedObject var cleanupController: DiskCleanController
    let localization: PluginLocalization

    @State private var searchText = ""
    @State private var category = "all"
    @State private var age = "all"
    @State private var sort = "size"
    @State private var selectedPaths: Set<String> = []
    @State private var visibleLimit = 200
    @State private var visibleDuplicateLimit = 50
    @State private var previewFile: DiskFileRecord?
    @State private var mode = DiskCleanFileInventoryMode.all
    @State private var largeFileThreshold: Int64 = 100 * 1_024 * 1_024

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            header
            if let summary = model.inventorySummary {
                inventoryMetrics(summary)
                modePicker
                if mode == .all {
                    inventorySpaceMap(summary)
                }
                filters
                if mode == .duplicates {
                    duplicateList
                } else {
                    fileList
                }
                if mode == .all, !cleanupController.snapshot.scope.userFilePaths.isEmpty {
                    DiskCleanCleanupSectionView(
                        controller: cleanupController,
                        title: localization.string(
                            "inventory.cleanup.title",
                            defaultValue: "安全清理所选文件"
                        ),
                        symbolName: "shield.checkered",
                        localization: localization
                    )
                }
            } else if !model.isScanning {
                DiskCleanEmptyState(
                    symbolName: "doc.badge.magnifyingglass",
                    text: localization.string(
                        "inventory.empty",
                        defaultValue: "运行分析后，可按格式、大小和 7/30/90 天未使用标记筛选文件。"
                    )
                ) {
                    Button(action: model.scan) {
                        Label(
                            localization.string("advisor.action.scan", defaultValue: "开始分析"),
                            systemImage: "magnifyingglass"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
        }
        .sheet(item: $previewFile) { file in
            DiskCleanQuickLookSheet(file: file, localization: localization)
        }
        .onChange(of: model.files) {
            selectedPaths.formIntersection(Set(model.files.map(\.path)))
            visibleLimit = 200
        }
        .onChange(of: mode) {
            selectedPaths.removeAll()
            visibleLimit = 200
            visibleDuplicateLimit = 50
        }
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            Label(
                localization.string("inventory.mode.all", defaultValue: "全部文件"),
                systemImage: "doc.on.doc"
            ).tag(DiskCleanFileInventoryMode.all)
            Label(
                localization.string("inventory.mode.large", defaultValue: "大文件"),
                systemImage: "externaldrive.fill.badge.exclamationmark"
            ).tag(DiskCleanFileInventoryMode.large)
            Label(
                localization.string("inventory.mode.duplicates", defaultValue: "重复文件"),
                systemImage: "square.on.square"
            ).tag(DiskCleanFileInventoryMode.duplicates)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            DiskCleanIconBadge(symbolName: "doc.text.magnifyingglass", size: 42)
            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                Text(localization.string("inventory.title", defaultValue: "文件分析"))
                    .font(.title3.weight(.semibold))
                Text(localization.string(
                    "inventory.subtitle",
                    defaultValue: "只读取文件元数据，按格式、大小、最后打开/访问/修改时间分类；选中后仍需单独安全检查。"
                ))
                .font(PluginSettingsTheme.Typography.pageDescription)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                if let lastAnalyzedAt = model.lastAnalyzedAt {
                    Label(
                        model.isRestoredFromCache
                            ? localization.format(
                                "advisor.cache.restored",
                                defaultValue: "已载入上次本地分析 · %@",
                                DiskCleanFormat.timestamp(lastAnalyzedAt)
                            )
                            : localization.format(
                                "advisor.cache.updated",
                                defaultValue: "本地分析已更新 · %@",
                                DiskCleanFormat.timestamp(lastAnalyzedAt)
                            ),
                        systemImage: model.isRestoredFromCache ? "clock.arrow.circlepath" : "checkmark.circle"
                    )
                    .font(PluginSettingsTheme.Typography.statusBadge)
                    .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button(action: model.scan) {
                Label(
                    model.hasResult
                        ? localization.string("advisor.action.rescan", defaultValue: "重新分析")
                        : localization.string("advisor.action.scan", defaultValue: "开始分析"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isScanning)
        }
        .padding(18)
        .diskCleanSurface(.accented)
    }

    private func inventoryMetrics(_ summary: DiskFileInventorySummary) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 132, maximum: 220), spacing: 10)], spacing: 10) {
            inventoryMetric(
                icon: "doc.on.doc",
                title: localization.string("inventory.metric.files", defaultValue: "可分析文件"),
                value: "\(summary.eligibleFileCount)",
                detail: DiskCleanFormat.bytes(summary.eligibleBytes)
            )
            inventoryMetric(
                icon: "list.bullet.rectangle",
                title: localization.string("inventory.metric.rows", defaultValue: "已保留明细"),
                value: "\(summary.returnedFileCount)",
                detail: DiskCleanFormat.bytes(summary.returnedBytes)
            )
            inventoryMetric(
                icon: "bolt.horizontal.circle",
                title: localization.string("inventory.metric.cache", defaultValue: "缓存命中"),
                value: "\(summary.cacheHitCount)",
                detail: localization.format(
                    "inventory.metric.read",
                    defaultValue: "读取 %d 项元数据",
                    summary.metadataReadCount
                )
            )
            inventoryMetric(
                icon: "timer",
                title: localization.string("inventory.metric.duration", defaultValue: "扫描耗时"),
                value: String(format: "%.1fs", summary.scanDuration),
                detail: summary.wasTruncated
                    ? localization.string("inventory.metric.bounded", defaultValue: "已按性能上限截断")
                    : localization.string("inventory.metric.complete", defaultValue: "已完成")
            )
        }
    }

    private func inventoryMetric(icon: String, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DiskCleanVisual.accent)
                Text(title)
                    .font(PluginSettingsTheme.Typography.statusBadge)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text(detail)
                .font(PluginSettingsTheme.Typography.statusBadge)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(14)
        .diskCleanSurface(.elevated)
    }

    /// Bounded category space map based on the same aggregate counters as the inventory cards.
    /// It never triggers another filesystem walk; selecting a row only filters the retained list.
    private func inventorySpaceMap(_ summary: DiskFileInventorySummary) -> some View {
        let breakdown = summary.categoryBreakdown
            .filter { $0.totalBytes > 0 }
            .sorted { lhs, rhs in
                lhs.totalBytes == rhs.totalBytes
                    ? lhs.category.rawValue < rhs.category.rawValue
                    : lhs.totalBytes > rhs.totalBytes
            }
        let largest = max(breakdown.map(\.totalBytes).max() ?? 1, 1)

        return VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            HStack {
                DiskCleanSectionHeader(
                    title: localization.string("inventory.spaceMap.title", defaultValue: "文件类型空间图"),
                    symbolName: "square.3.layers.3d"
                )
                Spacer()
                Text(localization.string(
                    "inventory.spaceMap.hint",
                    defaultValue: "点击类型可筛选；数据来自本地元数据扫描"
                ))
                .font(PluginSettingsTheme.Typography.statusBadge)
                .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: PluginSettingsTheme.Spacing.controlCluster
            ) {
                ForEach(breakdown, id: \.category) { item in
                    Button {
                        category = item.category.rawValue
                    } label: {
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 6) {
                                Image(systemName: categoryIcon(item.category))
                                Text(categoryTitle(item.category))
                                    .font(PluginSettingsTheme.Typography.rowTitle)
                                Spacer()
                                Text(DiskCleanFormat.bytes(item.totalBytes))
                                    .font(PluginSettingsTheme.Typography.monospacedValue)
                            }
                            GeometryReader { proxy in
                                Capsule()
                                    .fill(Color(nsColor: .quaternaryLabelColor).opacity(0.35))
                                    .overlay(alignment: .leading) {
                                        Capsule()
                                            .fill(categoryTint(item.category))
                                            .frame(
                                                width: max(
                                                    4,
                                                    proxy.size.width * CGFloat(item.totalBytes) / CGFloat(largest)
                                                )
                                            )
                                    }
                            }
                            .frame(height: 7)
                            Text(localization.format(
                                "inventory.spaceMap.files",
                                defaultValue: "%d 个文件",
                                item.fileCount
                            ))
                            .font(PluginSettingsTheme.Typography.statusBadge)
                            .foregroundStyle(.secondary)
                        }
                        .padding(PluginSettingsTheme.Spacing.cardContent)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .diskCleanSurface(category == item.category.rawValue ? .accented : .elevated)
                }
            }
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            DiskCleanSectionHeader(
                title: mode == .all
                    ? localization.string("inventory.filters.title", defaultValue: "筛选与选择")
                    : localization.string("inventory.filters.review", defaultValue: "筛选与查看"),
                symbolName: "line.3.horizontal.decrease.circle"
            )
            VStack(alignment: .leading, spacing: 10) {
                filterControls
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                        filterSelectionSummary
                        Spacer(minLength: 8)
                        if mode == .all { selectionActions }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        filterSelectionSummary
                        if mode == .all { selectionActions }
                    }
                }
            }
            .pluginSettingsListRowPadding(interactive: true)
            .diskCleanSurface(.elevated)
        }
    }

    private var filterSelectionSummary: some View {
        Text(mode == .duplicates
            ? localization.format(
                "inventory.duplicates.summary",
                defaultValue: "%d 组重复文件 · 可手动释放约 %@",
                filteredDuplicateGroups.count,
                DiskCleanFormat.bytes(filteredDuplicateReclaimableBytes)
            )
            : mode == .large
                ? localization.format(
                    "inventory.large.summary",
                    defaultValue: "%d 个大文件 · 仅查看，不会在此删除",
                    filteredFiles.count
                )
                : localization.format(
                    "inventory.filters.summary",
                    defaultValue: "当前 %d 项 · 已选 %d 项 / %@",
                    filteredFiles.count,
                    selectedPaths.count,
                    DiskCleanFormat.bytes(selectedBytes)
                ))
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var filterControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                searchField
                filterPickers
            }
            VStack(alignment: .leading, spacing: 8) {
                searchField
                filterPickers
            }
        }
    }

    private var searchField: some View {
        TextField(
            localization.string("inventory.search", defaultValue: "搜索名称、格式或路径"),
            text: $searchText
        )
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: 160, maxWidth: .infinity)
    }

    private var filterPickers: some View {
        HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
            Picker("", selection: $category) {
                Text(localization.string("inventory.category.all", defaultValue: "全部格式")).tag("all")
                ForEach(DiskFileCategory.allCases, id: \.rawValue) { value in
                    Text(categoryTitle(value)).tag(value.rawValue)
                }
            }
            .labelsHidden()
            .frame(width: 112)

            Picker("", selection: $age) {
                Text(localization.string("inventory.age.all", defaultValue: "全部时间")).tag("all")
                Text(localization.string("inventory.age.7", defaultValue: "7 天未使用")).tag("days7")
                Text(localization.string("inventory.age.30", defaultValue: "30 天未使用")).tag("days30")
                Text(localization.string("inventory.age.90", defaultValue: "90 天未使用")).tag("days90")
                Text(localization.string("inventory.age.unknown", defaultValue: "时间未知")).tag("unknown")
            }
            .labelsHidden()
            .frame(width: 118)

            Picker("", selection: $sort) {
                Text(localization.string("inventory.sort.size", defaultValue: "按大小")).tag("size")
                Text(localization.string("inventory.sort.activity", defaultValue: "按闲置时间")).tag("activity")
                Text(localization.string("inventory.sort.name", defaultValue: "按名称")).tag("name")
            }
            .labelsHidden()
            .frame(width: 104)

            if mode == .large {
                Picker("", selection: $largeFileThreshold) {
                    Text("≥ 100 MB").tag(Int64(100 * 1_024 * 1_024))
                    Text("≥ 500 MB").tag(Int64(500 * 1_024 * 1_024))
                    Text("≥ 1 GB").tag(Int64(1 * 1_024 * 1_024 * 1_024))
                }
                .labelsHidden()
                .frame(width: 104)
            }
        }
    }

    private var selectionActions: some View {
        HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
            Button {
                let paths = visibleFiles.prefix(DiskCleanUserFileExpansion.maximumSelectionCount).map(\.path)
                selectedPaths = Set(paths)
            } label: {
                Text(localization.string("inventory.action.selectVisible", defaultValue: "选择当前结果"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(visibleFiles.isEmpty)

            Button {
                selectedPaths.removeAll()
            } label: {
                Text(localization.string("inventory.action.clear", defaultValue: "清空"))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedPaths.isEmpty)

            Button(action: prepareCleanup) {
                Label(
                    localization.format(
                        "inventory.action.prepare",
                        defaultValue: "安全检查 %d 项",
                        selectedPaths.count
                    ),
                    systemImage: "shield.checkered"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(selectedPaths.isEmpty || cleanupController.snapshot.isBusy)
        }
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            HStack {
                DiskCleanSectionHeader(
                    title: localization.format(
                        "inventory.results.title",
                        defaultValue: "文件明细 · %d 项",
                        filteredFiles.count
                    ),
                    symbolName: "doc.on.doc"
                )
                Spacer()
                if mode == .all {
                    Text(localization.format(
                        "inventory.results.selected",
                        defaultValue: "已选 %d 项 · %@",
                        selectedPaths.count,
                        DiskCleanFormat.bytes(selectedBytes)
                    ))
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                } else {
                    Label(
                        localization.string(
                            "inventory.manualOnly",
                            defaultValue: "预览或在 Finder 中显示后手动处理"
                        ),
                        systemImage: "hand.point.up.left"
                    )
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                }
            }

            if visibleFiles.isEmpty {
                DiskCleanEmptyState(
                    symbolName: "magnifyingglass",
                    text: localization.string("inventory.results.empty", defaultValue: "没有符合当前条件的文件")
                )
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleFiles) { file in
                        fileRow(file, allowsSelection: mode == .all)
                        if file.id != visibleFiles.last?.id {
                            PluginSettingsListDivider()
                        }
                    }
                }
                .diskCleanSurface(.elevated)

                if visibleLimit < filteredFiles.count {
                    Button {
                        visibleLimit = min(visibleLimit + 200, filteredFiles.count)
                    } label: {
                        Label(
                            localization.string("inventory.action.more", defaultValue: "再显示 200 项"),
                            systemImage: "chevron.down.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func fileRow(_ file: DiskFileRecord, allowsSelection: Bool) -> some View {
        let marker = file.activityMarker()
        HStack(alignment: .top, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            if allowsSelection {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { selectedPaths.contains(file.path) },
                        set: { selected in
                            if selected {
                                if selectedPaths.count < DiskCleanUserFileExpansion.maximumSelectionCount {
                                    selectedPaths.insert(file.path)
                                }
                            } else {
                                selectedPaths.remove(file.path)
                            }
                        }
                    )
                )
                .toggleStyle(.checkbox)
                .labelsHidden()
            }

            Image(systemName: categoryIcon(file.category))
                .foregroundStyle(categoryTint(file.category))
                .frame(width: PluginSettingsTheme.Size.rowIcon)

            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                    Text(file.name)
                        .font(PluginSettingsTheme.Typography.rowTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    badge(categoryTitle(file.category), tint: categoryTint(file.category))
                    badge(activityTitle(marker), tint: activityTint(marker))
                }
                Text(file.path)
                    .font(PluginSettingsTheme.Typography.monospacedValue)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(metadataText(file))
                    .font(PluginSettingsTheme.Typography.statusBadge)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)
            Text(DiskCleanFormat.bytes(file.size))
                .font(PluginSettingsTheme.Typography.monospacedValue)
                .frame(width: DiskCleanFormat.byteColumnWidth, alignment: .trailing)
            Button {
                previewFile = file
            } label: {
                Image(systemName: "eye")
            }
            .buttonStyle(.borderless)
            .help(localization.string("inventory.action.preview", defaultValue: "预览"))
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help(localization.string("inventory.action.reveal", defaultValue: "在 Finder 中显示"))
        }
        .pluginSettingsListRowPadding(interactive: true)
    }

    private var duplicateList: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            HStack {
                DiskCleanSectionHeader(
                    title: localization.string("inventory.duplicates.title", defaultValue: "内容完全相同的文件"),
                    symbolName: "square.on.square"
                )
                Spacer()
                if let summary = model.duplicateSummary {
                    Text(localization.format(
                        "inventory.duplicates.detail",
                        defaultValue: "%d 组 · %d 个文件 · 可手动释放约 %@",
                        summary.duplicateGroupCount,
                        summary.duplicateFileCount,
                        DiskCleanFormat.bytes(summary.reclaimableBytes)
                    ))
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                }
            }

            if let summary = model.duplicateSummary, summary.wasTruncated {
                DiskCleanBanner(
                    symbolName: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: localization.string("inventory.duplicates.bounded.title", defaultValue: "重复文件扫描已按性能上限结束"),
                    lines: [localization.string(
                        "inventory.duplicates.bounded.detail",
                        defaultValue: "当前结果仍可查看；重新扫描会继续复用本地哈希缓存。"
                    )]
                )
            }

            let groups = Array(filteredDuplicateGroups.prefix(visibleDuplicateLimit))
            if groups.isEmpty {
                DiskCleanEmptyState(
                    symbolName: "checkmark.seal",
                    text: localization.string(
                        "inventory.duplicates.empty",
                        defaultValue: "在本次文件范围内没有发现内容完全相同的大文件。"
                    )
                )
            } else {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Label(
                                localization.format(
                                    "inventory.duplicates.group",
                                    defaultValue: "%d 个副本 · 每个 %@",
                                    group.files.count,
                                    DiskCleanFormat.bytes(group.logicalSize)
                                ),
                                systemImage: "doc.on.doc.fill"
                            )
                            .font(PluginSettingsTheme.Typography.rowTitle)
                            Spacer()
                            Text(localization.format(
                                "inventory.duplicates.reclaimable",
                                defaultValue: "可手动释放约 %@",
                                DiskCleanFormat.bytes(group.reclaimableBytes)
                            ))
                            .font(PluginSettingsTheme.Typography.statusBadge)
                            .foregroundStyle(DiskCleanVisual.accent)
                        }
                        .pluginSettingsListRowPadding(interactive: false)
                        PluginSettingsListDivider()
                        ForEach(group.files) { file in
                            fileRow(file, allowsSelection: false)
                            if file.id != group.files.last?.id { PluginSettingsListDivider() }
                        }
                    }
                    .diskCleanSurface(.elevated)
                }
                if visibleDuplicateLimit < filteredDuplicateGroups.count {
                    Button {
                        visibleDuplicateLimit = min(visibleDuplicateLimit + 50, filteredDuplicateGroups.count)
                    } label: {
                        Label(
                            localization.string("inventory.duplicates.more", defaultValue: "再显示 50 组"),
                            systemImage: "chevron.down.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var filteredFiles: [DiskFileRecord] {
        var values = model.files.filter { file in
            if mode == .large, file.size < largeFileThreshold { return false }
            if category != "all", file.category.rawValue != category { return false }
            if !includesAge(file.activityMarker()) { return false }
            if !searchText.isEmpty {
                let query = searchText.localizedLowercase
                if !file.name.localizedLowercase.contains(query),
                   !file.path.localizedLowercase.contains(query),
                   !file.fileExtension.localizedLowercase.contains(query) {
                    return false
                }
            }
            return true
        }
        switch sort {
        case "activity":
            values.sort {
                ($0.lastActivityDate ?? .distantPast) < ($1.lastActivityDate ?? .distantPast)
            }
        case "name":
            values.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        default:
            values.sort { $0.size == $1.size ? $0.path < $1.path : $0.size > $1.size }
        }
        return values
    }

    private var filteredDuplicateGroups: [DiskDuplicateFileGroup] {
        guard mode == .duplicates else { return [] }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        return model.duplicateGroups.filter { group in
            if category != "all", !group.files.contains(where: { $0.category.rawValue == category }) {
                return false
            }
            if age != "all", !group.files.contains(where: { includesAge($0.activityMarker()) }) {
                return false
            }
            guard !query.isEmpty else { return true }
            return group.files.contains { file in
                file.name.localizedLowercase.contains(query)
                    || file.path.localizedLowercase.contains(query)
                    || file.fileExtension.localizedLowercase.contains(query)
            }
        }
    }

    private var filteredDuplicateReclaimableBytes: Int64 {
        filteredDuplicateGroups.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
    }

    private func includesAge(_ marker: DiskFileActivityMarker) -> Bool {
        switch age {
        case "days7":
            return marker == .days7 || marker == .days30 || marker == .days90
        case "days30":
            return marker == .days30 || marker == .days90
        case "days90":
            return marker == .days90
        case "unknown":
            return marker == .unknown
        default:
            return true
        }
    }

    private var visibleFiles: [DiskFileRecord] {
        Array(filteredFiles.prefix(visibleLimit))
    }

    private var selectedBytes: Int64 {
        model.files.reduce(Int64(0)) { total, file in
            total + (selectedPaths.contains(file.path) ? max(file.size, 0) : 0)
        }
    }

    private func prepareCleanup() {
        let paths = Array(selectedPaths)
            .sorted()
            .prefix(DiskCleanUserFileExpansion.maximumSelectionCount)
        cleanupController.setScope(.userFiles(paths: Array(paths)))
        cleanupController.scan()
    }

    private func categoryTitle(_ category: DiskFileCategory) -> String {
        localization.string("inventory.category.\(category.rawValue)", defaultValue: {
            switch category {
            case .image: "图片"
            case .video: "视频"
            case .audio: "音频"
            case .document: "文档"
            case .archive: "压缩包"
            case .installer: "安装包"
            case .code: "代码"
            case .other: "其他"
            }
        }())
    }

    private func categoryIcon(_ category: DiskFileCategory) -> String {
        switch category {
        case .image: "photo"
        case .video: "film"
        case .audio: "waveform"
        case .document: "doc.text"
        case .archive: "archivebox"
        case .installer: "shippingbox"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .other: "doc"
        }
    }

    private func categoryTint(_ category: DiskFileCategory) -> Color {
        switch category {
        case .image: .blue
        case .video: .purple
        case .audio: .pink
        case .document: .teal
        case .archive: .orange
        case .installer: .green
        case .code: .indigo
        case .other: .secondary
        }
    }

    private func activityTitle(_ marker: DiskFileActivityMarker) -> String {
        switch marker {
        case .recent: localization.string("inventory.activity.recent", defaultValue: "近期使用")
        case .days7: localization.string("inventory.activity.7", defaultValue: "7 天未使用")
        case .days30: localization.string("inventory.activity.30", defaultValue: "30 天未使用")
        case .days90: localization.string("inventory.activity.90", defaultValue: "90 天未使用")
        case .unknown: localization.string("inventory.activity.unknown", defaultValue: "时间未知")
        }
    }

    private func activityTint(_ marker: DiskFileActivityMarker) -> Color {
        switch marker {
        case .recent: .green
        case .days7: .blue
        case .days30: .orange
        case .days90: .red
        case .unknown: .secondary
        }
    }

    private func metadataText(_ file: DiskFileRecord) -> String {
        let unknown = localization.string("inventory.date.unknown", defaultValue: "未知")
        return localization.format(
            "inventory.date.summary",
            defaultValue: "打开 %@ · 访问 %@ · 修改 %@",
            dateText(file.lastOpenedDate) ?? unknown,
            dateText(file.accessedDate) ?? unknown,
            dateText(file.modifiedDate) ?? unknown
        )
    }

    private func dateText(_ date: Date?) -> String? {
        guard let date else { return nil }
        return Self.dateFormatter.string(from: date)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(PluginSettingsTheme.Typography.statusBadge)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.1), in: Capsule())
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

private struct DiskCleanQuickLookSheet: View {
    let file: DiskFileRecord
    let localization: PluginLocalization

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.name).font(.headline)
                    Text(file.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: file.path)])
                } label: {
                    Label(
                        localization.string("inventory.action.reveal", defaultValue: "在 Finder 中显示"),
                        systemImage: "folder"
                    )
                }
            }
            DiskCleanQuickLookPreview(url: URL(fileURLWithPath: file.path))
                .frame(minWidth: 640, minHeight: 440)
        }
        .padding(16)
    }
}

private struct DiskCleanQuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.previewItem = url as NSURL
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        let currentURL = (view.previewItem as? NSURL) as URL?
        guard currentURL != url else { return }
        view.previewItem = url as NSURL
        view.refreshPreviewItem()
    }

    static func dismantleNSView(_ view: QLPreviewView, coordinator: ()) {
        view.autostarts = false
        view.previewItem = nil
    }
}
