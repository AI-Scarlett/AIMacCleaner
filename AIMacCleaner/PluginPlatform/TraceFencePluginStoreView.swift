import SwiftUI

/// Commercial classification is immutable catalog metadata. It must stay
/// visible even when the current subscriber already has access.
struct TraceFencePluginPricingBadge: View {
    @EnvironmentObject private var localizer: Localizer

    let plugin: TraceFencePluginDescriptor
    var compact = false

    var body: some View {
        Text(title)
            .font(.system(size: compact ? 8 : 10, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 4)
            .background(color.opacity(0.11), in: Capsule())
            .help(helpText)
    }

    private var title: String {
        plugin.isFree
            ? localizer.t("免费", en: "Free", zhHant: "免費", ja: "無料", ko: "무료", mt: "Free")
            : localizer.t("收费", en: "Paid", zhHant: "收費", ja: "有料", ko: "유료", mt: "Paid")
    }

    private var helpText: String {
        if plugin.isFree {
            return localizer.t(
                "这是免费插件，不需要订阅或单独购买。",
                en: "This is a free plugin and requires no subscription or separate purchase.",
                zhHant: "這是免費外掛，不需要訂閱或單獨購買。",
                ja: "無料プラグインです。サブスクリプションや個別購入は不要です。",
                ko: "무료 플러그인으로 구독이나 별도 구매가 필요하지 않습니다.",
                mt: "This is a free plugin."
            )
        }
        return localizer.t(
            "这是收费插件；当前订阅权益会另外显示。",
            en: "This is a paid plugin; current subscription access is shown separately.",
            zhHant: "這是收費外掛；目前訂閱權益會另外顯示。",
            ja: "有料プラグインです。現在のサブスクリプション権限は別に表示されます。",
            ko: "유료 플러그인이며 현재 구독 권한은 별도로 표시됩니다.",
            mt: "This is a paid plugin."
        )
    }

    private var color: Color {
        plugin.isFree ? Theme.Colors.success : Theme.Colors.warning
    }
}

struct TraceFencePluginPlacementSummary: View {
    @EnvironmentObject private var localizer: Localizer
    let plugin: TraceFencePluginDescriptor

    var body: some View {
        HStack(spacing: 6) {
            if plugin.supportsOverview {
                placement(localizer.t("概览", en: "Overview"), icon: "rectangle.grid.2x2")
            }
            if plugin.supportsPluginTab {
                placement(localizer.t("插件 Tab", en: "Plugins"), icon: "puzzlepiece.extension")
            }
            if plugin.supportsMenuBarPluginTab {
                placement(localizer.t("菜单栏", en: "Menu Bar"), icon: "menubar.rectangle")
            }
            if !plugin.supportsOverview && !plugin.supportsPluginTab && !plugin.supportsMenuBarPluginTab {
                placement(localizer.t("系统页面", en: "System Page"), icon: "macwindow")
            }
        }
        .font(.system(size: 8, weight: .medium))
        .foregroundStyle(Theme.Colors.textTertiary)
    }

    private func placement(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .lineLimit(1)
    }
}

/// Store presentation is deliberately downstream of catalog, commerce,
/// installation and runtime. It never treats a downloaded archive as usable.
struct TraceFencePluginStoreView: View {
    @EnvironmentObject private var localizer: Localizer

    @ObservedObject var catalogService: TraceFenceMarketplaceCatalogService
    @ObservedObject var entitlementService: TraceFencePluginEntitlementService
    @ObservedObject var packageManager: TraceFencePluginPackageManager
    let openPlugin: (String) -> Void
    let openSubscription: () -> Void

    @State private var section: TraceFencePluginPlatformSection = .discover
    @State private var searchText = ""
    @State private var selectedCategory = "all"
    @State private var detailPluginID: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            storeHeader
            sectionPicker

            switch section {
            case .discover:
                discoveryContent
            case .library:
                libraryContent
            case .updates:
                updatesContent
            }
        }
        .sheet(isPresented: Binding(
            get: { detailPluginID != nil },
            set: { if !$0 { detailPluginID = nil } }
        )) {
            if let detailPluginID,
               let plugin = catalogService.catalog.plugin(id: detailPluginID) {
                TraceFencePluginDetailView(
                    plugin: plugin,
                    catalog: catalogService.catalog,
                    entitlementService: entitlementService,
                    packageManager: packageManager,
                    openSubscription: openSubscription,
                    openRuntime: {
                        self.detailPluginID = nil
                        DispatchQueue.main.async {
                            openPlugin(plugin.id)
                        }
                    }
                )
                .environmentObject(localizer)
                .frame(minWidth: 590, minHeight: 520)
                .appCanvas()
            }
        }
        .task {
            packageManager.refresh(catalog: catalogService.catalog)
        }
        .onChange(of: catalogService.catalog.revision) { _ in
            packageManager.refresh(catalog: catalogService.catalog)
        }
    }

    private var storeHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Colors.accent.opacity(0.12))
                    Image(systemName: "square.grid.2x2.fill")
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.t("插件中心", en: "Plugin Center"))
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t(
                        "每个插件独立安装、启停和升级。TraceFence 只提供可信目录、授权、运行环境与数据隔离。",
                        en: "Each plugin installs, runs, and updates independently. TraceFence provides the trusted catalog, entitlements, runtime, and data isolation."
                    ))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    Task {
                        await catalogService.refresh(force: true)
                        packageManager.refresh(catalog: catalogService.catalog)
                    }
                } label: {
                    if catalogService.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(localizer.t("检查更新", en: "Check for Updates"), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .ghost, minHeight: 34))
                .disabled(catalogService.isRefreshing)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Label(
                    TraceFenceMarketplaceCatalogRuntime.isUsingVerifiedRemoteCatalog
                        ? localizer.t("签名目录已验证", en: "Signed catalog verified")
                        : localizer.t("内置安全目录", en: "Built-in safe catalog"),
                    systemImage: "checkmark.shield.fill"
                )
                .foregroundStyle(TraceFenceMarketplaceCatalogRuntime.isUsingVerifiedRemoteCatalog
                    ? Theme.Colors.success : Theme.Colors.textSecondary)
                Text("·")
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text(localizer.t(
                    "修订 \(catalogService.catalog.revision) · \(downloadablePlugins.count) 个可独立升级插件",
                    en: "Revision \(catalogService.catalog.revision) · \(downloadablePlugins.count) independently updatable plugins"
                ))
                .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                if !updatePlugins.isEmpty {
                    Label(
                        localizer.t("\(updatePlugins.count) 个更新", en: "\(updatePlugins.count) updates"),
                        systemImage: "arrow.down.circle.fill"
                    )
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
            .font(Theme.Font.captionMedium)
        }
        .cardStyle()
    }

    private var sectionPicker: some View {
        Picker("", selection: $section) {
            Label(localizer.t("发现", en: "Discover"), systemImage: "sparkles")
                .tag(TraceFencePluginPlatformSection.discover)
            Label(localizer.t("资料库", en: "Library"), systemImage: "square.stack.3d.up.fill")
                .tag(TraceFencePluginPlatformSection.library)
            Text(updatePlugins.isEmpty
                ? localizer.t("更新", en: "Updates")
                : localizer.t("更新（\(updatePlugins.count)）", en: "Updates (\(updatePlugins.count))"))
                .tag(TraceFencePluginPlatformSection.updates)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var discoveryContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            filterBar
            if filteredDiscoveryPlugins.isEmpty {
                emptyState(
                    icon: "magnifyingglass",
                    title: localizer.t("没有匹配的插件", en: "No matching plugins"),
                    detail: localizer.t("换一个关键词或分类试试。", en: "Try another keyword or category.")
                )
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: Theme.Spacing.md), GridItem(.flexible())],
                    spacing: Theme.Spacing.md
                ) {
                    ForEach(filteredDiscoveryPlugins) { plugin in
                        compactCard(plugin)
                    }
                }
            }
        }
    }

    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(localizer.t(
                    "已购买、可用和已安装的插件都在这里。",
                    en: "Owned, available, and installed plugins live here."
                ))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(localizer.t("\(libraryPlugins.count) 个", en: "\(libraryPlugins.count) items"))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            if libraryPlugins.isEmpty {
                emptyState(
                    icon: "square.stack.3d.up",
                    title: localizer.t("资料库还是空的", en: "Your library is empty"),
                    detail: localizer.t("安装免费插件，或购买后在这里管理。", en: "Install a free plugin or purchase one to manage it here.")
                )
            } else {
                ForEach(libraryPlugins) { plugin in
                    libraryRow(plugin)
                }
            }
        }
    }

    private var updatesContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(updatePlugins.isEmpty
                        ? localizer.t("所有插件都是最新版本", en: "All plugins are up to date")
                        : localizer.t("有 \(updatePlugins.count) 个独立插件更新", en: "\(updatePlugins.count) independent plugin updates"))
                        .font(Theme.Font.bodyMedium)
                    Text(localizer.t(
                        "更新插件不会改变 TraceFence 的版本。安装前仍会验证签名、版本和 SHA-256。",
                        en: "Plugin updates do not change the TraceFence version. Signature, version, and SHA-256 are verified before installation."
                    ))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                if !updatePlugins.isEmpty {
                    Button {
                        Task {
                            for plugin in updatePlugins {
                                await packageManager.install(plugin: plugin)
                            }
                        }
                    } label: {
                        Label(localizer.t("全部更新", en: "Update All"), systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 34))
                }
            }
            .cardStyle()

            if updatePlugins.isEmpty {
                emptyState(
                    icon: "checkmark.circle.fill",
                    title: localizer.t("无需更新", en: "No updates available"),
                    detail: localizer.t("TraceFence 会按插件自己的版本检查更新。", en: "TraceFence checks updates against each plugin's own version.")
                )
            } else {
                ForEach(updatePlugins) { plugin in
                    libraryRow(plugin)
                }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.Colors.textTertiary)
                TextField(localizer.t("搜索名称、用途或分类", en: "Search name, purpose, or category"), text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: 36)
            .background(Theme.Colors.elevatedCardBg.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.Colors.separator.opacity(0.7), lineWidth: 1)
            }

            Picker("", selection: $selectedCategory) {
                Text(localizer.t("全部分类", en: "All Categories")).tag("all")
                ForEach(categories, id: \.self) { category in
                    Text(localizedCategory(category)).tag(category)
                }
            }
            .labelsHidden()
            .frame(width: 145)
        }
    }

    private func compactCard(_ plugin: TraceFencePluginDescriptor) -> some View {
        let state = packageManager.state(for: plugin)
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Button {
                detailPluginID = plugin.id
            } label: {
                HStack(alignment: .top, spacing: Theme.Spacing.md) {
                    pluginIcon(plugin, size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.localizedName())
                            .font(Theme.Font.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Text(localizedCategory(plugin.category))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        TraceFencePluginPlacementSummary(plugin: plugin)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        TraceFencePluginPricingBadge(plugin: plugin)
                        entitlementBadge(plugin)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(plugin.localizedSummary())
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(2)
                .frame(minHeight: 30, alignment: .topLeading)

            HStack {
                Text("v\(plugin.version)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                if !plugin.permissions.isEmpty {
                    Label("\(plugin.permissions.count)", systemImage: "hand.raised.fill")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.warning)
                }
                Spacer()
                primaryAction(plugin, state: state)
            }
        }
        .cardStyle()
    }

    private func libraryRow(_ plugin: TraceFencePluginDescriptor) -> some View {
        let state = packageManager.state(for: plugin)
        return HStack(spacing: Theme.Spacing.md) {
            pluginIcon(plugin, size: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(plugin.localizedName())
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(plugin.localizedSummary())
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                installationVersionLine(plugin, state: state)
            }
            Spacer()
            TraceFencePluginPricingBadge(plugin: plugin, compact: true)
            if case let .installed(_, enabled, _) = state {
                Toggle("", isOn: Binding(
                    get: { enabled },
                    set: { packageManager.setEnabled($0, pluginID: plugin.id) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
            primaryAction(plugin, state: state)
            Button {
                detailPluginID = plugin.id
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
        }
        .cardStyle()
    }

    @ViewBuilder
    private func primaryAction(
        _ plugin: TraceFencePluginDescriptor,
        state: TraceFencePluginInstallationState
    ) -> some View {
        if plugin.delivery == .builtIn {
            Button(localizer.t("系统组件", en: "System")) {
                detailPluginID = plugin.id
            }
            .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .ghost, minHeight: 30))
        } else if !isCompatible(plugin) {
            Button(localizer.t("需升级宿主", en: "Host Update")) {
                detailPluginID = plugin.id
            }
            .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .ghost, minHeight: 30))
        } else if !hasAccess(plugin) {
            Button(localizer.t("查看", en: "View")) {
                detailPluginID = plugin.id
            }
            .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .ghost, minHeight: 30))
        } else {
            switch state {
            case .notInstalled, .failed:
                Button {
                    Task { await packageManager.install(plugin: plugin) }
                } label: {
                    Label(localizer.t("安装", en: "Install"), systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .secondary, minHeight: 30))
            case .downloading, .installing:
                ProgressView().controlSize(.small)
            case .installed:
                Button {
                    openPlugin(plugin.id)
                } label: {
                    Label(localizer.t("在主界面打开", en: "Open in Workspace"), systemImage: "arrow.up.forward.app.fill")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 30))
            case let .updateAvailable(_, targetVersion, _):
                Button {
                    Task { await packageManager.install(plugin: plugin) }
                } label: {
                    Text(localizer.t("更新到 \(targetVersion)", en: "Update to \(targetVersion)"))
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 30))
            }
        }
    }

    private func installationVersionLine(
        _ plugin: TraceFencePluginDescriptor,
        state: TraceFencePluginInstallationState
    ) -> some View {
        let text: String
        let color: Color
        switch state {
        case let .installed(version, _, restartRequired):
            text = restartRequired
                ? localizer.t("已安装 v\(version) · 重启后生效", en: "Installed v\(version) · restart required")
                : localizer.t("已安装 v\(version)", en: "Installed v\(version)")
            color = restartRequired ? Theme.Colors.warning : Theme.Colors.success
        case let .updateAvailable(installedVersion, targetVersion, _):
            text = localizer.t("v\(installedVersion) → v\(targetVersion)", en: "v\(installedVersion) → v\(targetVersion)")
            color = Theme.Colors.accent
        case let .failed(message, installedVersion):
            text = installedVersion == nil ? message : "v\(installedVersion!) · \(message)"
            color = Theme.Colors.warning
        case .downloading:
            text = localizer.t("正在下载并验证", en: "Downloading and verifying")
            color = Theme.Colors.info
        case .installing:
            text = localizer.t("正在安装", en: "Installing")
            color = Theme.Colors.info
        case .notInstalled:
            text = plugin.delivery == .builtIn
                ? localizer.t("随 TraceFence 提供", en: "Provided by TraceFence")
                : localizer.t("未安装 · 最新 v\(plugin.version)", en: "Not installed · latest v\(plugin.version)")
            color = Theme.Colors.textTertiary
        }
        return Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    private func pluginIcon(_ plugin: TraceFencePluginDescriptor, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(plugin.featured ? Theme.Colors.accent.opacity(0.13) : Theme.Colors.elevatedCardBg)
            Image(systemName: plugin.systemImage)
                .font(.system(size: size * 0.43, weight: .semibold))
                .foregroundStyle(plugin.featured ? Theme.Colors.accent : Theme.Colors.textSecondary)
        }
        .frame(width: size, height: size)
    }

    private func entitlementBadge(_ plugin: TraceFencePluginDescriptor) -> some View {
        let state = entitlementService.accessState(pluginID: plugin.id)
        let title: String
        let color: Color
        switch state {
        case .free:
            title = localizer.t("可直接使用", en: "Ready", zhHant: "可直接使用", ja: "利用可能", ko: "사용 가능", mt: "Ready")
            color = Theme.Colors.success
        case .allAccess:
            title = localizer.t("订阅已包含", en: "Included", zhHant: "訂閱已包含", ja: "含まれています", ko: "구독에 포함", mt: "Included")
            color = Theme.Colors.accent
        case .licensed:
            title = localizer.t("已单独购买", en: "Purchased", zhHant: "已單獨購買", ja: "購入済み", ko: "구매 완료", mt: "Purchased")
            color = Theme.Colors.success
        case let .trial(expiresAt):
            let hours = max(1, Int(ceil(expiresAt.timeIntervalSinceNow / 3600)))
            title = localizer.t("试用 \(hours)h", en: "Trial \(hours)h")
            color = Theme.Colors.info
        case .locked:
            title = plugin.standaloneOfferID.flatMap { catalogService.catalog.offer(id: $0)?.displayPrice }
                ?? localizer.t("需授权", en: "License")
            color = Theme.Colors.textSecondary
        }
        return Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.11))
            .clipShape(Capsule())
    }

    private func emptyState(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(title)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text(detail)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
        .cardStyle()
    }

    private var downloadablePlugins: [TraceFencePluginDescriptor] {
        catalogService.catalog.plugins.filter { $0.delivery == .package }
    }

    private var categories: [String] {
        Array(Set(downloadablePlugins.map(\.category))).sorted()
    }

    private var filteredDiscoveryPlugins: [TraceFencePluginDescriptor] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return downloadablePlugins.filter { plugin in
            let categoryMatches = selectedCategory == "all" || plugin.category == selectedCategory
            let queryMatches = query.isEmpty
                || plugin.localizedName().lowercased().contains(query)
                || plugin.localizedSummary().lowercased().contains(query)
                || plugin.category.lowercased().contains(query)
            return categoryMatches && queryMatches
        }
        .sorted { lhs, rhs in
            if lhs.featured != rhs.featured { return lhs.featured && !rhs.featured }
            return lhs.localizedName().localizedCaseInsensitiveCompare(rhs.localizedName()) == .orderedAscending
        }
    }

    private var libraryPlugins: [TraceFencePluginDescriptor] {
        catalogService.catalog.plugins.filter { plugin in
            packageManager.state(for: plugin).installedVersion != nil || hasAccess(plugin)
        }
        .sorted { lhs, rhs in
            let lhsInstalled = packageManager.state(for: lhs).installedVersion != nil
            let rhsInstalled = packageManager.state(for: rhs).installedVersion != nil
            if lhsInstalled != rhsInstalled { return lhsInstalled && !rhsInstalled }
            return lhs.localizedName().localizedCaseInsensitiveCompare(rhs.localizedName()) == .orderedAscending
        }
    }

    private var updatePlugins: [TraceFencePluginDescriptor] {
        downloadablePlugins.filter {
            if case .updateAvailable = packageManager.state(for: $0) { return true }
            return false
        }
    }

    private func hasAccess(_ plugin: TraceFencePluginDescriptor) -> Bool {
        switch entitlementService.accessState(pluginID: plugin.id) {
        case .locked: false
        case .free, .allAccess, .licensed, .trial: true
        }
    }

    private func isCompatible(_ plugin: TraceFencePluginDescriptor) -> Bool {
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let systemVersion = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
        return catalogService.catalog.isCompatible(
            plugin,
            hostVersion: TraceFencePluginPackageManager.hostVersion
        ) && systemVersion.compare(
            plugin.minimumSystemVersion,
            options: .numeric
        ) != .orderedAscending
    }

    private func localizedCategory(_ category: String) -> String {
        switch category {
        case "Audio": localizer.t("音频", en: "Audio")
        case "Display": localizer.t("显示", en: "Display")
        case "Monitoring": localizer.t("监控", en: "Monitoring")
        case "Productivity": localizer.t("效率", en: "Productivity")
        case "Storage": localizer.t("存储", en: "Storage")
        case "System": localizer.t("系统", en: "System")
        default: category
        }
    }
}

private struct TraceFencePluginDetailView: View {
    @EnvironmentObject private var localizer: Localizer
    @Environment(\.dismiss) private var dismiss

    let plugin: TraceFencePluginDescriptor
    let catalog: TraceFenceMarketplaceCatalog
    @ObservedObject var entitlementService: TraceFencePluginEntitlementService
    @ObservedObject var packageManager: TraceFencePluginPackageManager
    let openSubscription: () -> Void
    let openRuntime: () -> Void

    @State private var licenseKey = ""
    @State private var showingUninstallConfirmation = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.lg)
                            .fill(Theme.Colors.accent.opacity(0.13))
                        Image(systemName: plugin.systemImage)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Theme.Colors.accent)
                    }
                    .frame(width: 70, height: 70)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(plugin.localizedName())
                            .font(Theme.Font.title2Bold)
                        Text(plugin.localizedSummary())
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                actionCard
                requirementsCard
                permissionCard
                managementCard
            }
            .padding(Theme.Spacing.xxl)
        }
        .confirmationDialog(
            localizer.t("卸载 \(plugin.localizedName())？", en: "Uninstall \(plugin.localizedName())?"),
            isPresented: $showingUninstallConfirmation
        ) {
            Button(localizer.t("卸载插件", en: "Uninstall Plugin"), role: .destructive) {
                Task { await packageManager.uninstall(pluginID: plugin.id) }
            }
            Button(localizer.cancel, role: .cancel) {}
        } message: {
            Text(localizer.t(
                "插件程序会被移除；插件数据目录会保留，便于以后重新安装。",
                en: "The plugin code will be removed. Its data directory is retained for a future reinstall."
            ))
        }
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(accessTitle)
                        .font(Theme.Font.bodyMedium)
                    Text(statusDetail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                detailPrimaryAction
            }

            if case .locked = entitlementService.accessState(pluginID: plugin.id), !plugin.isFree {
                Divider().overlay(Theme.Colors.separator)
                HStack(spacing: Theme.Spacing.sm) {
                    if let trialHours = plugin.trialHours {
                        Button(localizer.t("试用 \(trialHours) 小时", en: "Try for \(trialHours) hours")) {
                            entitlementService.beginTrial(pluginID: plugin.id)
                        }
                    }
                    if plugin.standaloneOfferID != nil {
                        Button(localizer.t("单独购买", en: "Buy Separately")) {
                            entitlementService.openCheckout(pluginID: plugin.id)
                        }
                    }
                    if plugin.includedInAllAccess {
                        Button(localizer.t("通过 Standard 获取", en: "Get with Standard")) {
                            dismiss()
                            openSubscription()
                        }
                    }
                }
                if plugin.standaloneOfferID != nil {
                    HStack(spacing: Theme.Spacing.sm) {
                        TextField(localizer.t("输入插件 License Key", en: "Enter plugin license key"), text: $licenseKey)
                            .textFieldStyle(.roundedBorder)
                        Button(localizer.t("兑换", en: "Redeem")) {
                            Task {
                                await entitlementService.activate(pluginID: plugin.id, licenseKey: licenseKey)
                            }
                        }
                        .disabled(licenseKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }

            if case let .failed(message, _) = packageManager.state(for: plugin) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var detailPrimaryAction: some View {
        let state = packageManager.state(for: plugin)
        if plugin.delivery == .builtIn {
            Text(localizer.t("系统组件", en: "System Component"))
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
        } else if case .locked = entitlementService.accessState(pluginID: plugin.id) {
            Text(plugin.standaloneOfferID.flatMap { catalog.offer(id: $0)?.displayPrice } ?? "Standard")
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.Colors.accent)
        } else {
            switch state {
            case .notInstalled, .failed:
                Button {
                    Task { await packageManager.install(plugin: plugin) }
                } label: {
                    Label(localizer.t("安装", en: "Install"), systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 34))
            case .downloading, .installing:
                ProgressView().controlSize(.small)
            case .installed:
                Button(action: openRuntime) {
                    Label(localizer.t("在主界面打开", en: "Open in Workspace"), systemImage: "arrow.up.forward.app.fill")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 34))
            case let .updateAvailable(_, targetVersion, _):
                Button {
                    Task { await packageManager.install(plugin: plugin) }
                } label: {
                    Label(localizer.t("更新到 \(targetVersion)", en: "Update to \(targetVersion)"), systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 34))
            }
        }
    }

    private var requirementsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(localizer.t("版本与兼容性", en: "Version & Compatibility"), systemImage: "checkmark.seal.fill")
                .font(Theme.Font.bodyMedium)
            metadataRow(localizer.t("插件版本", en: "Plugin version"), plugin.version)
            metadataRow(localizer.t("TraceFence 最低版本", en: "Minimum TraceFence"), plugin.minimumHostVersion)
            metadataRow(localizer.t("macOS 最低版本", en: "Minimum macOS"), plugin.minimumSystemVersion)
            metadataRow(localizer.t("商业类型", en: "Pricing"), pricingDescription)
            metadataRow(localizer.t("显示位置", en: "Placement"), placementDescription)
            if plugin.delivery == .package {
                metadataRow("PluginKit ABI", "v\(plugin.pluginKitVersion)")
                if let size = plugin.package?.sizeBytes {
                    metadataRow(localizer.t("下载大小", en: "Download size"), ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                }
                metadataRow(localizer.t("更新通道", en: "Update channel"), localizer.t("TraceFence 自有独立 Release", en: "TraceFence-owned independent release"))
            }
        }
        .cardStyle()
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Label(localizer.t("权限与数据", en: "Permissions & Data"), systemImage: "hand.raised.fill")
                .font(Theme.Font.bodyMedium)
            if plugin.permissions.isEmpty {
                Label(localizer.t("不需要额外系统权限", en: "No additional system permission required"), systemImage: "checkmark.circle.fill")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.success)
            } else {
                ForEach(plugin.permissions, id: \.self) { permission in
                    Label(permissionName(permission), systemImage: "lock.shield")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.warning)
                }
            }
            Text(localizer.t(
                "插件数据、缓存和临时文件按插件 ID 分开保存；卸载不会误删用户数据。",
                en: "Plugin data, caches, and temporary files are isolated by plugin ID; uninstalling does not silently erase user data."
            ))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .cardStyle()
    }

    @ViewBuilder
    private var managementCard: some View {
        if let record = packageManager.record(pluginID: plugin.id) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Label(localizer.t("已安装版本管理", en: "Installed Version Management"), systemImage: "shippingbox.fill")
                        .font(Theme.Font.bodyMedium)
                    Spacer()
                    Toggle(localizer.t("启用", en: "Enabled"), isOn: Binding(
                        get: { record.enabled },
                        set: { packageManager.setEnabled($0, pluginID: plugin.id) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                HStack(spacing: Theme.Spacing.sm) {
                    Button(localizer.t("在访达中显示", en: "Reveal in Finder")) {
                        packageManager.reveal(pluginID: plugin.id)
                    }
                    if let previousVersion = record.previousVersion {
                        Button(localizer.t("回退到 v\(previousVersion)", en: "Roll Back to v\(previousVersion)")) {
                            Task { await packageManager.rollback(pluginID: plugin.id) }
                        }
                    }
                    Spacer()
                    Button(localizer.t("卸载", en: "Uninstall"), role: .destructive) {
                        showingUninstallConfirmation = true
                    }
                }
            }
            .cardStyle()
        }
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }

    private var accessTitle: String {
        switch entitlementService.accessState(pluginID: plugin.id) {
        case .free: localizer.t("免费插件", en: "Free plugin")
        case .allAccess: localizer.t("Standard 已包含", en: "Included with Standard")
        case .licensed: localizer.t("已单独购买", en: "Purchased")
        case .trial: localizer.t("试用中", en: "Trial active")
        case .locked: localizer.t("选择获取方式", en: "Choose how to get this plugin")
        }
    }

    private var pricingDescription: String {
        if plugin.isFree {
            return localizer.t("免费", en: "Free", zhHant: "免費", ja: "無料", ko: "무료", mt: "Free")
        }
        if let offerID = plugin.standaloneOfferID,
           let offer = catalog.offer(id: offerID) {
            return localizer.t(
                "收费 · Standard 或 \(offer.displayPrice) 单独购买",
                en: "Paid · Standard or \(offer.displayPrice) separately",
                zhHant: "收費 · Standard 或 \(offer.displayPrice) 單獨購買",
                ja: "有料 · Standard または \(offer.displayPrice) で個別購入",
                ko: "유료 · Standard 또는 \(offer.displayPrice) 별도 구매",
                mt: "Paid · Standard or \(offer.displayPrice) separately"
            )
        }
        return localizer.t(
            "收费 · Standard",
            en: "Paid · Standard",
            zhHant: "收費 · Standard",
            ja: "有料 · Standard",
            ko: "유료 · Standard",
            mt: "Paid · Standard"
        )
    }

    private var placementDescription: String {
        var values: [String] = []
        if plugin.supportsOverview { values.append(localizer.t("概览", en: "Overview")) }
        if plugin.supportsPluginTab { values.append(localizer.t("插件 Tab", en: "Plugins")) }
        if plugin.supportsMenuBarPluginTab { values.append(localizer.t("菜单栏插件 Tab", en: "Menu Bar Plugins")) }
        return values.isEmpty ? localizer.t("系统固定页面", en: "Fixed system page") : values.joined(separator: " · ")
    }

    private var statusDetail: String {
        let state = packageManager.state(for: plugin)
        switch state {
        case .notInstalled: return localizer.t("最新版本 v\(plugin.version)，尚未安装", en: "Latest v\(plugin.version), not installed")
        case let .downloading(version): return localizer.t("正在下载并校验 v\(version)", en: "Downloading and verifying v\(version)")
        case let .installing(version): return localizer.t("正在原子安装 v\(version)", en: "Atomically installing v\(version)")
        case let .installed(version, _, restartRequired): return restartRequired
            ? localizer.t("v\(version) 已安装，重启后完全生效", en: "v\(version) installed; restart required")
            : localizer.t("v\(version) 已安装并可用", en: "v\(version) installed and ready")
        case let .updateAvailable(installed, target, _): return localizer.t("已安装 v\(installed)，可更新至 v\(target)", en: "v\(installed) installed; v\(target) available")
        case let .failed(message, _): return message
        }
    }

    private func permissionName(_ permission: String) -> String {
        switch permission {
        case "screen-recording": localizer.t("屏幕录制", en: "Screen Recording")
        case "accessibility": localizer.t("辅助功能", en: "Accessibility")
        case "input-monitoring", "inputMonitoring", "inputmonitoring": localizer.t(
            "输入监控",
            en: "Input Monitoring",
            zhHant: "輸入監控",
            ja: "入力監視",
            ko: "입력 모니터링",
            mt: "Monitoraġġ tal-Input"
        )
        case "microphone": localizer.t("麦克风", en: "Microphone")
        case "calendar", "calendarFullAccess", "calendarfullaccess", "calendar-full-access": localizer.t(
            "日历",
            en: "Calendar",
            zhHant: "行事曆",
            ja: "カレンダー",
            ko: "캘린더",
            mt: "Kalendarju"
        )
        case "automation": localizer.t(
            "自动化控制",
            en: "Automation",
            zhHant: "自動化控制",
            ja: "オートメーション",
            ko: "자동화",
            mt: "Awtomazzjoni"
        )
        case "contacts": localizer.t("通讯录", en: "Contacts")
        case "full-disk-access": localizer.t("完全磁盘访问", en: "Full Disk Access")
        default: permission.replacingOccurrences(of: "-", with: " ").capitalized
        }
    }
}
