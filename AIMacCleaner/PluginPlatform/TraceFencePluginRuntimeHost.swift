import Foundation
import MacToolsPluginKit
import Security
import SwiftUI
import CryptoKit

@MainActor
final class TraceFencePluginRuntimeHost: ObservableObject {
    static let shared = TraceFencePluginRuntimeHost()

    @Published private(set) var states: [String: TraceFencePluginRuntimeState] = [:]

    private struct Session {
        let version: String
        let bundle: Bundle
        let provider: any PluginProvider
        let plugin: any MacToolsPlugin
    }

    private var sessions: [String: Session] = [:]
    private let packageManager = TraceFencePluginPackageManager.shared

    private init() {
        synchronizeWithInstalledPlugins()
    }

    func synchronizeWithInstalledPlugins() {
        for (pluginID, record) in packageManager.records where sessions[pluginID] == nil {
            states[pluginID] = record.enabled ? .idle : .disabled
        }
    }

    func state(pluginID: String) -> TraceFencePluginRuntimeState {
        states[pluginID] ?? .unavailable
    }

    func plugin(pluginID: String) -> (any MacToolsPlugin)? {
        sessions[pluginID]?.plugin
    }

    func open(pluginID: String) {
        open(pluginID: pluginID, enforceEntitlement: true)
    }

#if DEBUG
    func openForTesting(pluginID: String) {
        open(pluginID: pluginID, enforceEntitlement: false)
    }
#endif

    private func open(pluginID: String, enforceEntitlement: Bool) {
        guard !enforceEntitlement || TraceFenceEntitlementPolicy.canUsePlugin(pluginID) else {
            states[pluginID] = .failed("This plugin is not owned by the current account.")
            return
        }
        guard let record = packageManager.record(pluginID: pluginID),
              let packageURL = packageManager.activePackageURL(pluginID: pluginID) else {
            states[pluginID] = .unavailable
            return
        }
        if let session = sessions[pluginID] {
            states[pluginID] = session.version == record.activeVersion ? .active : .restartRequired
            return
        }
        if !record.enabled {
            packageManager.setEnabled(true, pluginID: pluginID)
        }

        states[pluginID] = .loading
        do {
            let session = try load(
                catalogPluginID: pluginID,
                version: record.activeVersion,
                packageURL: packageURL
            )
            sessions[pluginID] = session
            states[pluginID] = .active
        } catch {
            states[pluginID] = .failed(error.localizedDescription)
        }
    }

    func setEnabled(_ enabled: Bool, pluginID: String) {
        packageManager.setEnabled(enabled, pluginID: pluginID)
        if enabled {
            states[pluginID] = sessions[pluginID] == nil ? .idle : .active
        } else {
            deactivate(pluginID: pluginID, reason: .disabled)
            states[pluginID] = .disabled
        }
    }

    func refresh(pluginID: String) {
        guard let plugin = sessions[pluginID]?.plugin else { return }
        plugin.refresh()
        objectWillChange.send()
    }

    func handlePrimaryAction(pluginID: String, action: PluginPanelAction) {
        guard let primaryPanel = sessions[pluginID]?.plugin.primaryPanel else { return }
        primaryPanel.handleAction(action)
        objectWillChange.send()
    }

    func componentView(pluginID: String) -> AnyView? {
        guard let component = sessions[pluginID]?.plugin.componentPanel else { return nil }
        return component.makeView(
            context: PluginComponentContext(pluginID: pluginID, dismiss: {}, isPanelVisible: true)
        )
    }

    func setSurfaceVisible(pluginID: String, surface: PluginPanelSurface, visible: Bool) {
        guard let lifecycle = sessions[pluginID]?.plugin as? any PluginPanelSurfaceLifecycleHandling else {
            return
        }
        if visible {
            lifecycle.panelSurfaceDidBecomeVisible(surface)
        } else {
            lifecycle.panelSurfaceDidBecomeHidden(surface)
        }
    }

    func settingsPage(pluginID: String) -> PluginSettingsPage? {
        sessions[pluginID]?.plugin.settingsPage
    }

    func handleSettingsAction(pluginID: String, action: PluginSettingsAction) {
        guard let plugin = sessions[pluginID]?.plugin else { return }
        plugin.handleSettingsAction(action)
        objectWillChange.send()
    }

    func handlePermissionAction(pluginID: String, permissionID: String) {
        guard let plugin = sessions[pluginID]?.plugin else { return }
        plugin.handlePermissionAction(id: permissionID)
        objectWillChange.send()
    }

    func shutdown() {
        for pluginID in Array(sessions.keys) {
            deactivate(pluginID: pluginID, reason: .hostShutdown)
        }
    }

    private func deactivate(pluginID: String, reason: PluginDeactivationReason) {
        guard let session = sessions.removeValue(forKey: pluginID) else { return }
        session.plugin.deactivate(reason: reason)
        session.plugin.onStateChange = nil
        session.plugin.requestPermissionGuidance = nil
        session.plugin.shortcutBindingResolver = nil
    }

    private func load(
        catalogPluginID: String,
        version: String,
        packageURL: URL
    ) throws -> Session {
        let manifestURL = packageURL.appendingPathComponent("plugin.json", isDirectory: false)
        let manifest = try JSONDecoder().decode(
            TraceFencePluginManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        guard manifest.version == version,
              manifest.pluginKitVersion == PluginKitCompatibility.currentVersion,
              catalogPluginID == "tracefence.tools.\(manifest.id)",
              let factoryName = manifest.factoryClass else {
            throw RuntimeError.incompatibleManifest
        }
        let bundleURL = packageURL.appendingPathComponent(manifest.bundleRelativePath, isDirectory: true)
        guard let descriptor = TraceFenceMarketplaceCatalogRuntime.plugin(id: catalogPluginID)?.package else {
            throw RuntimeError.missingCatalogDescriptor
        }
        try Self.validateCodeSignature(
            bundleURL,
            expectedIdentifier: descriptor.bundleIdentifier,
            expectedTeamIdentifier: descriptor.teamIdentifier
        )
        guard let bundle = Bundle(url: bundleURL) else { throw RuntimeError.unreadableBundle }
        try bundle.loadAndReturnError()
        guard let factory = NSClassFromString(factoryName) as? MacToolsPluginBundleFactory.Type else {
            throw RuntimeError.missingFactory(factoryName)
        }

        let support = Self.pluginDirectory(root: TraceFencePluginPackageManager.dataDirectory, id: catalogPluginID)
        let cache = Self.pluginDirectory(root: TraceFencePluginPackageManager.cachesDirectory, id: catalogPluginID)
        let temporary = Self.pluginDirectory(root: TraceFencePluginPackageManager.temporaryDirectory, id: catalogPluginID)
        let context = PluginRuntimeContext(
            pluginID: manifest.id,
            resourceBundle: bundle,
            storage: UserDefaultsPluginStorage(pluginID: catalogPluginID),
            supportDirectory: support,
            cacheDirectory: cache,
            temporaryDirectory: temporary
        )
        let provider = try factory.makeProvider(context: context)
        let plugins = provider.makePlugins()
        guard plugins.count == 1, let plugin = plugins.first, plugin.metadata.id == manifest.id else {
            throw RuntimeError.invalidPluginIdentity
        }
        plugin.onStateChange = { [weak self] in self?.objectWillChange.send() }
        plugin.requestPermissionGuidance = { permissionID in
            NotificationCenter.default.post(
                name: .traceFencePluginPermissionGuidanceRequested,
                object: nil,
                userInfo: ["pluginID": catalogPluginID, "permissionID": permissionID]
            )
        }
        plugin.activate(context: context)
        return Session(version: version, bundle: bundle, provider: provider, plugin: plugin)
    }

    private static func pluginDirectory(root: URL, id: String) -> URL {
        let url = root.appendingPathComponent(id, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func validateCodeSignature(
        _ url: URL,
        expectedIdentifier: String,
        expectedTeamIdentifier: String
    ) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess,
              let code else { throw RuntimeError.invalidCodeSignature }
        var validationError: Unmanaged<CFError>?
        guard SecStaticCodeCheckValidityWithErrors(
            code,
            SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate),
            nil,
            &validationError
        ) == errSecSuccess else {
            if let validationError {
                throw validationError.takeRetainedValue()
            }
            throw RuntimeError.invalidCodeSignature
        }
        var signingInfo: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &signingInfo) == errSecSuccess,
              let info = signingInfo as? [String: Any],
              info[kSecCodeInfoIdentifier as String] as? String == expectedIdentifier,
              info[kSecCodeInfoTeamIdentifier as String] as? String == expectedTeamIdentifier else {
            throw RuntimeError.invalidCodeSignature
        }
    }

    private enum RuntimeError: LocalizedError {
        case incompatibleManifest
        case missingCatalogDescriptor
        case unreadableBundle
        case missingFactory(String)
        case invalidPluginIdentity
        case invalidCodeSignature

        var errorDescription: String? {
            switch self {
            case .incompatibleManifest: "The installed plugin manifest is incompatible with this host."
            case .missingCatalogDescriptor: "The signed catalog no longer contains this plugin package."
            case .unreadableBundle: "The installed plugin bundle cannot be opened."
            case let .missingFactory(name): "The plugin entry factory is unavailable: \(name)"
            case .invalidPluginIdentity: "The plugin runtime identity does not match its package."
            case .invalidCodeSignature: "The installed plugin no longer has a trusted TraceFence signature."
            }
        }
    }
}

enum TraceFencePluginRuntimePresentation {
    case workspace
    case menuBar
}

struct TraceFencePluginRuntimeView: View {
    @EnvironmentObject private var localizer: Localizer
    @ObservedObject var runtimeHost: TraceFencePluginRuntimeHost
    let pluginID: String
    var presentation: TraceFencePluginRuntimePresentation = .workspace
    var onClose: (() -> Void)?
    @State private var selectedSurface: Surface = .main
    @State private var visiblePanelSurface: PluginPanelSurface?

    private enum Surface: String {
        case main
        case component
        case settings
    }

    var body: some View {
        Group {
            switch runtimeHost.state(pluginID: pluginID) {
            case .unavailable:
                runtimeMessage(
                    icon: "shippingbox",
                    title: localizer.t("插件尚未安装", en: "Plugin not installed")
                )
            case .disabled:
                runtimeMessage(
                    icon: "pause.circle",
                    title: localizer.t("插件已停用", en: "Plugin disabled")
                )
            case .idle, .loading:
                ProgressView(localizer.t("正在启动插件…", en: "Starting plugin…"))
            case .active:
                activePlugin
            case let .failed(message):
                runtimeMessage(icon: "exclamationmark.triangle", title: message)
            case .restartRequired:
                runtimeMessage(
                    icon: "arrow.clockwise.circle",
                    title: localizer.t("请重启 TraceFence 以切换插件版本", en: "Restart TraceFence to switch plugin versions")
                )
            }
        }
        .task {
            runtimeHost.open(pluginID: pluginID)
        }
        .onChange(of: runtimeHost.state(pluginID: pluginID)) { state in
            if state == .active {
                updateVisiblePanelSurface()
            } else {
                hideVisiblePanelSurface()
            }
        }
        .onChange(of: selectedSurface) { _ in
            updateVisiblePanelSurface()
        }
        .onDisappear {
            hideVisiblePanelSurface()
        }
    }

    @ViewBuilder
    private var activePlugin: some View {
        if let plugin = runtimeHost.plugin(pluginID: pluginID) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: plugin.metadata.iconName)
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(plugin.metadata.iconTint)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(plugin.metadata.title)
                            .font(Theme.Font.title2Bold)
                        Text(plugin.metadata.defaultDescription)
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    if presentation == .workspace,
                       [plugin.primaryPanel != nil, plugin.componentPanel != nil, plugin.settingsPage != nil]
                        .filter({ $0 }).count > 1 {
                        Picker("", selection: $selectedSurface) {
                            if plugin.primaryPanel != nil {
                                Text(localizer.t("使用", en: "Use")).tag(Surface.main)
                            }
                            if plugin.componentPanel != nil {
                                Text(localizer.t("面板", en: "Panel")).tag(Surface.component)
                            }
                            if plugin.settingsPage != nil {
                                Text(localizer.t("设置", en: "Settings")).tag(Surface.settings)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    Button {
                        runtimeHost.refresh(pluginID: pluginID)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    if let onClose {
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .buttonStyle(.borderless)
                        .help(localizer.t("关闭插件", en: "Close Plugin"))
                    }
                }

                if selectedSurface == .settings || (plugin.primaryPanel == nil && plugin.componentPanel == nil) {
                    if let page = runtimeHost.settingsPage(pluginID: pluginID) {
                        TraceFencePluginSettingsView(
                            pluginID: pluginID,
                            plugin: plugin,
                            page: page,
                            runtimeHost: runtimeHost
                        )
                    } else {
                        runtimeMessage(
                            icon: "gearshape",
                            title: localizer.t("这个插件没有可配置项目", en: "This plugin has no configurable settings")
                        )
                    }
                } else if selectedSurface == .component,
                          let component = runtimeHost.componentView(pluginID: pluginID) {
                    component
                } else if let primary = plugin.primaryPanel {
                    primaryPanel(primary)
                } else if let component = runtimeHost.componentView(pluginID: pluginID) {
                    component
                } else {
                    runtimeMessage(
                        icon: "slider.horizontal.3",
                        title: localizer.t("请在插件设置中配置", en: "Configure this plugin in Settings")
                    )
                }
            }
            .padding(presentation == .menuBar ? Theme.Spacing.lg : Theme.Spacing.xxl)
        }
    }

    private func updateVisiblePanelSurface() {
        guard runtimeHost.state(pluginID: pluginID) == .active else { return }
        let target: PluginPanelSurface?
        switch selectedSurface {
        case .main:
            target = runtimeHost.plugin(pluginID: pluginID)?.primaryPanel == nil ? nil : .primary
        case .component:
            target = runtimeHost.plugin(pluginID: pluginID)?.componentPanel == nil ? nil : .component
        case .settings:
            target = nil
        }
        guard target != visiblePanelSurface else { return }
        hideVisiblePanelSurface()
        if let target {
            runtimeHost.setSurfaceVisible(pluginID: pluginID, surface: target, visible: true)
            visiblePanelSurface = target
        }
    }

    private func hideVisiblePanelSurface() {
        guard let visiblePanelSurface else { return }
        runtimeHost.setSurfaceVisible(pluginID: pluginID, surface: visiblePanelSurface, visible: false)
        self.visiblePanelSurface = nil
    }

    @ViewBuilder
    private func primaryPanel(_ panel: any PluginPrimaryPanel) -> some View {
        let state = panel.primaryPanelState
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(state.subtitle)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            switch panel.primaryPanelDescriptor.controlStyle {
            case .button:
                Button(panel.primaryPanelDescriptor.buttonTitle ?? localizer.t("运行", en: "Run")) {
                    runtimeHost.handlePrimaryAction(
                        pluginID: pluginID,
                        action: .invokeAction(controlID: "execute")
                    )
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 40))
                .disabled(!state.isEnabled)
            case .switch:
                Toggle(isOn: Binding(
                    get: { state.isOn },
                    set: { runtimeHost.handlePrimaryAction(pluginID: pluginID, action: .setSwitch($0)) }
                )) {
                    Text(pluginTitle)
                }
                .toggleStyle(.switch)
                .disabled(!state.isEnabled)
            case .disclosure:
                Button {
                    runtimeHost.handlePrimaryAction(
                        pluginID: pluginID,
                        action: .setDisclosureExpanded(!state.isExpanded)
                    )
                } label: {
                    Label(
                        state.isExpanded ? localizer.t("收起", en: "Collapse") : localizer.t("展开", en: "Expand"),
                        systemImage: state.isExpanded ? "chevron.up" : "chevron.down"
                    )
                }
            }
            if state.isExpanded, let detail = state.detail {
                Divider().overlay(Theme.Colors.separator)
                ForEach(detail.primaryControls) { control in
                    TraceFencePluginPanelControlView(
                        control: control,
                        fallbackSwitchState: state.isOn,
                        action: { runtimeHost.handlePrimaryAction(pluginID: pluginID, action: $0) }
                    )
                }
                if let secondary = detail.secondaryPanel {
                    Divider().overlay(Theme.Colors.separator)
                    Text(secondary.title)
                        .font(Theme.Font.bodyMedium)
                    ForEach(secondary.controls) { control in
                        TraceFencePluginPanelControlView(
                            control: control,
                            fallbackSwitchState: state.isOn,
                            action: { runtimeHost.handlePrimaryAction(pluginID: pluginID, action: $0) }
                        )
                    }
                }
            }
            if let error = state.errorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        .cardStyle()
    }

    private var pluginTitle: String {
        runtimeHost.plugin(pluginID: pluginID)?.metadata.title ?? localizer.t("插件", en: "Plugin")
    }

    private func runtimeMessage(icon: String, title: String) -> some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(title)
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }
}

/// Installed plugins live in an application workspace. The store remains a
/// lifecycle surface and does not become the place users must revisit to run a
/// tool.
struct TraceFencePluginWorkspaceView: View {
    @EnvironmentObject private var localizer: Localizer

    @ObservedObject var catalogService: TraceFenceMarketplaceCatalogService
    @ObservedObject var packageManager: TraceFencePluginPackageManager
    @ObservedObject var runtimeHost: TraceFencePluginRuntimeHost
    @Binding var selectedPluginID: String?
    let openStore: () -> Void

    @AppStorage(TraceFencePluginDisplayPreferences.pinnedPluginIDsKey)
    private var pinnedPluginIDsJSON = TraceFencePluginDisplayPreferences.defaultPinnedPluginIDsJSON
    @State private var searchText = ""

    var body: some View {
        HStack(spacing: 0) {
            pluginRail
                .frame(width: 250)
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: 1)
            workspaceContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            packageManager.refresh(catalog: catalogService.catalog)
            selectFirstPluginIfNeeded()
        }
        .onChange(of: catalogService.catalog.revision) { _ in
            packageManager.refresh(catalog: catalogService.catalog)
            selectFirstPluginIfNeeded()
        }
    }

    private var pluginRail: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.t("我的插件", en: "My Plugins"))
                        .font(Theme.Font.headline)
                    Text(localizer.t("已安装 \(installedPlugins.count) 个", en: "\(installedPlugins.count) installed"))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
                Button(action: openStore) {
                    Image(systemName: "plus.app.fill")
                }
                .buttonStyle(.borderless)
                .help(localizer.t("打开插件商城", en: "Open Plugin Store"))
            }

            if installedPlugins.count > 7 {
                TextField(localizer.t("搜索已安装插件", en: "Search installed plugins"), text: $searchText)
                    .textFieldStyle(.roundedBorder)
            }

            if installedPlugins.isEmpty {
                VStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    Text(localizer.t("还没有安装插件", en: "No plugins installed"))
                        .font(Theme.Font.captionMedium)
                    Button(localizer.t("浏览插件商城", en: "Browse Plugin Store"), action: openStore)
                        .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .secondary, minHeight: 30))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Spacing.xs) {
                        ForEach(filteredInstalledPlugins) { plugin in
                            pluginRailRow(plugin)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Gradients.sidebar)
    }

    private func pluginRailRow(_ plugin: TraceFencePluginDescriptor) -> some View {
        let isSelected = selectedPluginID == plugin.id
        let isPinned = pinnedPluginIDs.contains(plugin.id)
        return HStack(spacing: Theme.Spacing.xs) {
            Button {
                selectedPluginID = plugin.id
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: plugin.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Theme.Colors.accent)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .fill(isSelected ? AnyShapeStyle(Theme.Gradients.hero) : AnyShapeStyle(Theme.Colors.accent.opacity(0.10)))
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(plugin.localizedName())
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        Text("v\(packageManager.state(for: plugin).installedVersion ?? plugin.version)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                togglePinned(plugin.id)
            } label: {
                Image(systemName: isPinned ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isPinned ? Theme.Colors.warning : Theme.Colors.textTertiary)
                    .frame(width: 24, height: 30)
            }
            .buttonStyle(.plain)
            .help(isPinned
                ? localizer.t("从快捷插件移除", en: "Remove from Quick Plugins")
                : localizer.t("固定到快捷插件", en: "Pin to Quick Plugins"))
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(isSelected ? Theme.Colors.elevatedCardBg : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(isSelected ? Theme.Colors.separator : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var workspaceContent: some View {
        if let selectedPluginID,
           packageManager.records[selectedPluginID] != nil {
            TraceFencePluginRuntimeView(
                runtimeHost: runtimeHost,
                pluginID: selectedPluginID,
                presentation: .workspace,
                onClose: { self.selectedPluginID = nil }
            )
            .id(selectedPluginID)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.xl)
                        .fill(Theme.Colors.accent.opacity(0.10))
                    Image(systemName: "puzzlepiece.extension.fill")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(Theme.Colors.accent)
                }
                .frame(width: 76, height: 76)
                Text(localizer.t("插件工作区", en: "Plugin Workspace"))
                    .font(Theme.Font.title2Bold)
                Text(localizer.t(
                    "从左侧打开已安装插件。常用插件可以点星标固定到菜单栏快捷区。",
                    en: "Open an installed plugin from the left. Star frequently used plugins to pin them to the menu-bar quick area."
                ))
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
                Button(localizer.t("打开插件商城", en: "Open Plugin Store"), action: openStore)
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .secondary, minHeight: 34))
            }
            .padding(Theme.Spacing.xxl)
        }
    }

    private var installedPlugins: [TraceFencePluginDescriptor] {
        catalogService.catalog.plugins.filter { packageManager.records[$0.id] != nil }
            .sorted { lhs, rhs in
                let lhsPinned = pinnedPluginIDs.contains(lhs.id)
                let rhsPinned = pinnedPluginIDs.contains(rhs.id)
                if lhsPinned != rhsPinned { return lhsPinned }
                return lhs.localizedName().localizedCaseInsensitiveCompare(rhs.localizedName()) == .orderedAscending
            }
    }

    private var filteredInstalledPlugins: [TraceFencePluginDescriptor] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return installedPlugins }
        return installedPlugins.filter {
            $0.localizedName().lowercased().contains(query)
                || $0.localizedSummary().lowercased().contains(query)
        }
    }

    private var pinnedPluginIDs: Set<String> {
        Set(TraceFencePluginDisplayPreferences.pinnedPluginIDs(from: pinnedPluginIDsJSON))
    }

    private func togglePinned(_ pluginID: String) {
        var values = TraceFencePluginDisplayPreferences.pinnedPluginIDs(from: pinnedPluginIDsJSON)
        if let index = values.firstIndex(of: pluginID) {
            values.remove(at: index)
        } else {
            values.append(pluginID)
        }
        pinnedPluginIDsJSON = TraceFencePluginDisplayPreferences.encodedPinnedPluginIDs(values)
    }

    private func selectFirstPluginIfNeeded() {
        guard let selectedPluginID else { return }
        if packageManager.records[selectedPluginID] == nil {
            self.selectedPluginID = nil
        }
    }
}

private struct TraceFencePluginPanelControlView: View {
    let control: PluginPanelControl
    let fallbackSwitchState: Bool
    let action: (PluginPanelAction) -> Void

    @State private var selectionID: String
    @State private var sliderValue: Double
    @State private var dateValue: Date
    @State private var switchValue: Bool

    init(
        control: PluginPanelControl,
        fallbackSwitchState: Bool,
        action: @escaping (PluginPanelAction) -> Void
    ) {
        self.control = control
        self.fallbackSwitchState = fallbackSwitchState
        self.action = action
        _selectionID = State(initialValue: control.selectedOptionID ?? "")
        _sliderValue = State(initialValue: control.sliderValue ?? control.sliderBounds?.lowerBound ?? 0)
        _dateValue = State(initialValue: control.dateValue ?? Date())
        _switchValue = State(initialValue: fallbackSwitchState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if control.showsLeadingDivider {
                Divider().overlay(Theme.Colors.separator)
            }
            if let title = control.sectionTitle, !title.isEmpty {
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            controlBody
        }
        .disabled(!control.isEnabled)
    }

    @ViewBuilder
    private var controlBody: some View {
        switch control.kind {
        case .segmented:
            Picker("", selection: selectionBinding(navigation: false)) {
                ForEach(control.options) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        case .selectList:
            Picker("", selection: selectionBinding(navigation: false)) {
                ForEach(control.options) { option in
                    Text(option.subtitle.map { "\(option.title) · \($0)" } ?? option.title).tag(option.id)
                }
            }
            .labelsHidden()
        case .navigationList:
            VStack(spacing: Theme.Spacing.xs) {
                ForEach(control.options) { option in
                    Button {
                        selectionID = option.id
                        action(.setNavigationSelection(controlID: control.id, optionID: option.id))
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(Theme.Font.captionMedium)
                                if let subtitle = option.subtitle {
                                    Text(subtitle)
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                            Spacer()
                            if selectionID == option.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.Colors.accent)
                            } else {
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, Theme.Spacing.xs)
                }
            }
        case .slider:
            if let bounds = control.sliderBounds {
                HStack(spacing: Theme.Spacing.sm) {
                    Slider(
                        value: Binding(
                            get: { sliderValue },
                            set: {
                                sliderValue = $0
                                action(.setSlider(controlID: control.id, value: $0, phase: .changed))
                            }
                        ),
                        in: bounds,
                        step: control.sliderStep ?? max((bounds.upperBound - bounds.lowerBound) / 100, 0.001),
                        onEditingChanged: { editing in
                            if !editing {
                                action(.setSlider(controlID: control.id, value: sliderValue, phase: .ended))
                            }
                        }
                    )
                    if let valueLabel = control.valueLabel {
                        Text(valueLabel)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        case .datePicker:
            DatePicker(
                "",
                selection: Binding(
                    get: { dateValue },
                    set: {
                        dateValue = $0
                        action(.setDate(controlID: control.id, value: $0))
                    }
                ),
                in: (control.minimumDate ?? .distantPast)...,
                displayedComponents: control.displayedComponents ?? [.date, .hourAndMinute]
            )
            .labelsHidden()
        case .actionRow:
            Button {
                action(.invokeAction(controlID: control.id))
            } label: {
                Label(
                    control.actionTitle ?? "Run",
                    systemImage: control.actionIconSystemName ?? "play.fill"
                )
            }
        case .switchRow:
            Toggle(isOn: Binding(
                get: { switchValue },
                set: {
                    switchValue = $0
                    action(.setSwitch($0))
                }
            )) {
                Label(
                    control.actionTitle ?? "Enabled",
                    systemImage: control.actionIconSystemName ?? "switch.2"
                )
            }
            .toggleStyle(.switch)
        }
    }

    private func selectionBinding(navigation: Bool) -> Binding<String> {
        Binding(
            get: { selectionID },
            set: {
                selectionID = $0
                if navigation {
                    action(.setNavigationSelection(controlID: control.id, optionID: $0))
                } else {
                    action(.setSelection(controlID: control.id, optionID: $0))
                }
            }
        )
    }
}

private struct TraceFencePluginSettingsView: View {
    @EnvironmentObject private var localizer: Localizer

    let pluginID: String
    let plugin: any MacToolsPlugin
    let page: PluginSettingsPage
    @ObservedObject var runtimeHost: TraceFencePluginRuntimeHost

    private var context: PluginSettingsContext {
        PluginSettingsContext(pluginID: plugin.metadata.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if let description = page.description, !description.isEmpty {
                Text(description)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            permissionCards
            settingsBody
        }
        .onAppear { page.visibilityHandler?(true) }
        .onDisappear { page.visibilityHandler?(false) }
    }

    @ViewBuilder
    private var permissionCards: some View {
        ForEach(plugin.permissionRequirements) { requirement in
            let state = plugin.permissionState(for: requirement.id)
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: state.isGranted ? "checkmark.shield.fill" : "hand.raised.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(state.isGranted ? Theme.Colors.success : Theme.Colors.warning)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(requirement.title)
                        .font(Theme.Font.bodyMedium)
                    Text(requirement.description)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if let footnote = state.footnote, !footnote.isEmpty {
                        Text(footnote)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                Spacer()
                Button(state.isGranted
                    ? localizer.t("已授权", en: "Granted")
                    : localizer.t("前往授权", en: "Grant Access")) {
                    runtimeHost.handlePermissionAction(pluginID: pluginID, permissionID: requirement.id)
                }
                .disabled(state.isGranted)
            }
            .cardStyle()
        }
    }

    @ViewBuilder
    private var settingsBody: some View {
        switch page.body {
        case let .form(sections):
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                ForEach(sections.filter(\.isVisible)) { section in
                    settingsSection(section)
                }
            }
        case let .workspace(workspace):
            workspace.makeView(context)
        }
    }

    @ViewBuilder
    private func settingsSection(_ section: PluginSettingsSection) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            if section.title != nil || section.headerAccessory != nil {
                HStack {
                    if let title = section.title {
                        Label(title, systemImage: section.systemImage ?? "gearshape")
                            .font(Theme.Font.bodyMedium)
                    }
                    Spacer()
                    section.headerAccessory?.makeView(context)
                }
            }
            switch section.content {
            case let .rows(rows):
                ForEach(rows.filter(\.isVisible)) { row in
                    TraceFencePluginSettingsRowView(
                        row: row,
                        action: { runtimeHost.handleSettingsAction(pluginID: pluginID, action: $0) }
                    )
                    if row.id != rows.filter(\.isVisible).last?.id {
                        Divider().overlay(Theme.Colors.separator)
                    }
                }
            case let .custom(content):
                content.makeView(context)
            case let .shortcutGroup(groupID):
                shortcutGroup(groupID)
            }
            if let footer = section.footer, !footer.isEmpty {
                Text(footer)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .cardStyle()
    }

    private func shortcutGroup(_ groupID: String) -> some View {
        let definitions = plugin.shortcutDefinitions.filter { $0.settingsGroupID == groupID }
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(definitions) { definition in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(definition.settingsControlTitle ?? definition.title)
                            .font(Theme.Font.captionMedium)
                        Text(definition.description)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Spacer()
                    Text(definition.defaultBinding.map(Self.bindingText) ?? localizer.t("未设置", en: "Not set"))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private static func bindingText(_ binding: ShortcutBinding) -> String {
        "\(binding.modifiers.symbolString)\(binding.keyCode)"
    }
}

private struct TraceFencePluginSettingsRowView: View {
    let row: PluginSettingsRow
    let action: (PluginSettingsAction) -> Void

    @State private var booleanValue: Bool
    @State private var selectionID: String
    @State private var numberValue: Double
    @State private var textValue: String

    init(row: PluginSettingsRow, action: @escaping (PluginSettingsAction) -> Void) {
        self.row = row
        self.action = action
        switch row.control {
        case let .toggle(isOn):
            _booleanValue = State(initialValue: isOn)
            _selectionID = State(initialValue: "")
            _numberValue = State(initialValue: 0)
            _textValue = State(initialValue: "")
        case let .picker(selectionID, _, _):
            _booleanValue = State(initialValue: false)
            _selectionID = State(initialValue: selectionID)
            _numberValue = State(initialValue: 0)
            _textValue = State(initialValue: "")
        case let .slider(value, _, _, _):
            _booleanValue = State(initialValue: false)
            _selectionID = State(initialValue: "")
            _numberValue = State(initialValue: value)
            _textValue = State(initialValue: "")
        case let .textField(value, _, _), let .secureField(value, _, _):
            _booleanValue = State(initialValue: false)
            _selectionID = State(initialValue: "")
            _numberValue = State(initialValue: 0)
            _textValue = State(initialValue: value)
        case .action, .status:
            _booleanValue = State(initialValue: false)
            _selectionID = State(initialValue: "")
            _numberValue = State(initialValue: 0)
            _textValue = State(initialValue: "")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            if let systemImage = row.systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: 22)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if let description = row.description, !description.isEmpty {
                    Text(description)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let error = row.error, !error.isEmpty {
                    Text(error)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.danger)
                } else if let help = row.help, !help.isEmpty {
                    Text(help)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            control
        }
        .disabled(!row.isEnabled)
    }

    @ViewBuilder
    private var control: some View {
        switch row.control {
        case .toggle:
            Toggle("", isOn: Binding(
                get: { booleanValue },
                set: {
                    booleanValue = $0
                    action(.setBoolean(controlID: row.id, value: $0))
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
        case let .picker(_, options, style):
            picker(options: options, style: style)
        case let .slider(_, range, step, valueFormat):
            HStack(spacing: Theme.Spacing.sm) {
                Slider(
                    value: Binding(
                        get: { numberValue },
                        set: {
                            numberValue = $0
                            action(.setNumber(controlID: row.id, value: $0, phase: .changed))
                        }
                    ),
                    in: range,
                    step: step ?? max((range.upperBound - range.lowerBound) / 100, 0.001),
                    onEditingChanged: { editing in
                        if !editing {
                            action(.setNumber(controlID: row.id, value: numberValue, phase: .committed))
                        }
                    }
                )
                .frame(width: 150)
                if let valueFormat {
                    Text(valueFormat.text(for: numberValue))
                        .font(.system(size: 10, design: .monospaced))
                        .frame(minWidth: 40, alignment: .trailing)
                }
            }
        case let .textField(_, prompt, _):
            TextField(prompt ?? "", text: textBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
                .onSubmit { commitText() }
        case let .secureField(_, prompt, _):
            SecureField(prompt ?? "", text: textBinding)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
                .onSubmit { commitText() }
        case let .action(title, role):
            Button(role: role == .destructive ? .destructive : nil) {
                action(.invoke(controlID: row.id))
            } label: {
                Text(title)
            }
        case let .status(text, systemImage, tone, actionTitle):
            HStack(spacing: Theme.Spacing.sm) {
                Label(text, systemImage: systemImage)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(statusColor(tone))
                if let actionTitle {
                    Button(actionTitle) { action(.invoke(controlID: row.id)) }
                }
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { textValue },
            set: {
                textValue = $0
                action(.setText(controlID: row.id, value: $0, phase: .changed))
            }
        )
    }

    @ViewBuilder
    private func picker(options: [PluginSettingsOption], style: PluginSettingsPickerStyle) -> some View {
        let selection = Binding(
            get: { selectionID },
            set: {
                selectionID = $0
                action(.setSelection(controlID: row.id, optionID: $0))
            }
        )
        if style == .segmented {
            Picker("", selection: selection) {
                ForEach(options) { Text($0.title).tag($0.id) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 250)
        } else {
            Picker("", selection: selection) {
                ForEach(options) { Text($0.title).tag($0.id) }
            }
            .labelsHidden()
            .frame(width: 190)
        }
    }

    private func commitText() {
        action(.setText(controlID: row.id, value: textValue, phase: .committed))
    }

    private func statusColor(_ tone: PluginStatusTone) -> Color {
        switch tone {
        case .neutral: Theme.Colors.textSecondary
        case .positive: Theme.Colors.success
        case .caution: Theme.Colors.warning
        }
    }
}

extension Notification.Name {
    static let traceFencePluginPermissionGuidanceRequested = Notification.Name(
        "traceFencePluginPermissionGuidanceRequested"
    )
}

#if DEBUG
enum TraceFencePluginRuntimeSelfTest {
    @MainActor
    static func run(arguments: [String]) async {
        let pluginID = argumentValue("--plugin-id", arguments: arguments)
            ?? "tracefence.tools.clipboard-clear"
        var failures: [String] = []
        var installed = false
        var loaded = false
        var usableSurface = false
        var actionSucceeded = false
        var rollbackSucceeded: Bool?
        var removed = false

        guard let packageURL = argumentURL("--package", arguments: arguments) else {
            finish(arguments: arguments, pluginID: pluginID, version: nil, failures: ["Missing --package."])
        }
        if let catalogURL = argumentURL("--catalog", arguments: arguments),
           let signatureURL = argumentURL("--signature", arguments: arguments) {
            do {
                _ = try TraceFenceMarketplaceCatalogRuntime.installVerified(
                    catalogData: Data(contentsOf: catalogURL),
                    signatureData: Data(contentsOf: signatureURL)
                )
            } catch {
                failures.append("Catalog fixture failed: \(error.localizedDescription)")
            }
        }
        guard let descriptor = TraceFenceMarketplaceCatalogRuntime.plugin(id: pluginID) else {
            finish(arguments: arguments, pluginID: pluginID, version: nil, failures: failures + ["Plugin is absent from the verified catalog."])
        }

        let manager = TraceFencePluginPackageManager.shared
        if let previousPackageURL = argumentURL("--previous-package", arguments: arguments),
           let previousVersion = argumentValue("--previous-version", arguments: arguments),
           let package = descriptor.package {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: previousPackageURL.path)
                let previousSize = (attributes[.size] as? NSNumber)?.int64Value ?? -1
                let previousDescriptor = TraceFencePluginDescriptor(
                    id: descriptor.id,
                    version: previousVersion,
                    name: descriptor.name,
                    summary: descriptor.summary,
                    localizedMetadata: descriptor.localizedMetadata,
                    category: descriptor.category,
                    systemImage: descriptor.systemImage,
                    delivery: descriptor.delivery,
                    minimumHostVersion: descriptor.minimumHostVersion,
                    minimumSystemVersion: descriptor.minimumSystemVersion,
                    pluginKitVersion: descriptor.pluginKitVersion,
                    capabilities: descriptor.capabilities,
                    permissions: descriptor.permissions,
                    isFree: descriptor.isFree,
                    includedInAllAccess: descriptor.includedInAllAccess,
                    standaloneOfferID: descriptor.standaloneOfferID,
                    trialHours: descriptor.trialHours,
                    featured: descriptor.featured,
                    package: TraceFencePluginPackageDescriptor(
                        url: URL(string: "https://github.com/AI-Scarlett/TraceFence/releases/download/plugin-\(previousVersion)/fixture.zip")!,
                        sha256: try sha256(previousPackageURL),
                        sizeBytes: previousSize,
                        bundleIdentifier: package.bundleIdentifier,
                        teamIdentifier: package.teamIdentifier,
                        entryPoint: package.entryPoint
                    )
                )
                await manager.installLocalPackageForTesting(
                    plugin: previousDescriptor,
                    archiveURL: previousPackageURL
                )
                if manager.record(pluginID: pluginID)?.activeVersion != previousVersion {
                    failures.append("Previous version fixture installation failed.")
                }
            } catch {
                failures.append("Previous version fixture failed: \(error.localizedDescription)")
            }
        }
        await manager.installLocalPackageForTesting(plugin: descriptor, archiveURL: packageURL)
        installed = manager.record(pluginID: pluginID)?.activeVersion == descriptor.version
        if !installed { failures.append("Atomic package installation failed.") }

        if let previousVersion = argumentValue("--previous-version", arguments: arguments) {
            await manager.rollback(pluginID: pluginID)
            let rolledBack = manager.record(pluginID: pluginID)?.activeVersion == previousVersion
            await manager.rollback(pluginID: pluginID)
            let restored = manager.record(pluginID: pluginID)?.activeVersion == descriptor.version
            rollbackSucceeded = rolledBack && restored
            if rollbackSucceeded != true {
                failures.append("Independent plugin rollback or restore failed.")
            }
        }

        let runtime = TraceFencePluginRuntimeHost.shared
        runtime.openForTesting(pluginID: pluginID)
        loaded = runtime.state(pluginID: pluginID) == .active
        let runtimePlugin = runtime.plugin(pluginID: pluginID)
        usableSurface = runtimePlugin?.primaryPanel != nil
            || runtimePlugin?.componentPanel != nil
            || runtimePlugin?.settingsPage != nil
        if loaded {
            if pluginID == "tracefence.tools.clipboard-clear" {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("TraceFence plugin runtime test", forType: .string)
                runtime.handlePrimaryAction(
                    pluginID: pluginID,
                    action: .invokeAction(controlID: "execute")
                )
                actionSucceeded = pasteboard.pasteboardItems?.isEmpty ?? true
            } else {
                actionSucceeded = usableSurface
            }
        } else {
            failures.append("Plugin runtime loading failed: \(String(describing: runtime.state(pluginID: pluginID)))")
        }
        if !usableSurface { failures.append("The plugin has no host-renderable primary, component, or settings surface.") }
        if !actionSucceeded { failures.append("The plugin interaction self-test failed.") }

        runtime.setEnabled(false, pluginID: pluginID)
        await manager.uninstall(pluginID: pluginID)
        removed = manager.record(pluginID: pluginID) == nil
        if !removed { failures.append("Plugin uninstall failed.") }

        finish(
            arguments: arguments,
            pluginID: pluginID,
            version: descriptor.version,
            failures: failures,
            installed: installed,
            loaded: loaded,
            usableSurface: usableSurface,
            actionSucceeded: actionSucceeded,
            rollbackSucceeded: rollbackSucceeded,
            removed: removed
        )
    }

    private static func argumentURL(_ name: String, arguments: [String]) -> URL? {
        argumentValue(name, arguments: arguments).map { URL(fileURLWithPath: $0) }
    }

    private static func argumentValue(_ name: String, arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    private static func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    @MainActor
    private static func finish(
        arguments: [String],
        pluginID: String,
        version: String?,
        failures: [String],
        installed: Bool = false,
        loaded: Bool = false,
        usableSurface: Bool = false,
        actionSucceeded: Bool = false,
        rollbackSucceeded: Bool? = nil,
        removed: Bool = false
    ) -> Never {
        let payload: [String: Any] = [
            "succeeded": failures.isEmpty,
            "pluginID": pluginID,
            "pluginVersion": version as Any? ?? NSNull(),
            "installed": installed,
            "runtimeLoaded": loaded,
            "usableSurface": usableSurface,
            "actionSucceeded": actionSucceeded,
            "rollbackSucceeded": rollbackSucceeded as Any? ?? NSNull(),
            "uninstalled": removed,
            "failures": failures
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data("\n".utf8))
            if let resultURL = argumentURL("--result", arguments: arguments) {
                try? data.write(to: resultURL, options: .atomic)
            }
        }
        Darwin.exit(failures.isEmpty ? 0 : 2)
    }
}
#endif
