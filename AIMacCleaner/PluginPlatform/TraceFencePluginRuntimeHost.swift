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
        for (pluginID, record) in packageManager.records {
            if let session = sessions[pluginID] {
                states[pluginID] = session.version == record.activeVersion
                    ? .active
                    : .restartRequired
            } else {
                states[pluginID] = record.enabled ? .idle : .disabled
            }
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
        guard record.enabled else {
            states[pluginID] = .disabled
            return
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

    func uninstallCompletely(pluginID: String) async {
        deactivate(pluginID: pluginID, reason: .uninstalling)
        states[pluginID] = .unavailable
        await packageManager.uninstall(pluginID: pluginID, purgeData: true)
        states[pluginID] = packageManager.record(pluginID: pluginID) == nil
            ? .unavailable
            : .failed("The plugin could not be completely removed.")
    }

    func refresh(pluginID: String) {
        guard let plugin = sessions[pluginID]?.plugin else { return }
        plugin.refresh()
        objectWillChange.send()
    }

    func refreshLocalization() {
        for session in sessions.values {
            (session.plugin as? any PluginRuntimeLocalizationRefreshing)?.refreshLocalization()
        }
        objectWillChange.send()
    }

    func handlePrimaryAction(pluginID: String, action: PluginPanelAction) {
        guard let primaryPanel = sessions[pluginID]?.plugin.primaryPanel else { return }
        primaryPanel.handleAction(action)
        objectWillChange.send()
    }

    func componentView(
        pluginID: String,
        dismiss: @escaping () -> Void = {},
        isPanelVisible: Bool = true
    ) -> AnyView? {
        guard let component = sessions[pluginID]?.plugin.componentPanel else { return nil }
        return component.makeView(
            context: PluginComponentContext(
                pluginID: pluginID,
                dismiss: dismiss,
                isPanelVisible: isPanelVisible
            )
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
    @Environment(\.colorScheme) private var inheritedColorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @ObservedObject var runtimeHost: TraceFencePluginRuntimeHost
    @ObservedObject private var packageManager = TraceFencePluginPackageManager.shared
    @ObservedObject private var catalogService = TraceFenceMarketplaceCatalogService.shared
    @ObservedObject private var pluginLocaleSource = PluginRuntimeLocalization.source
    let pluginID: String
    var presentation: TraceFencePluginRuntimePresentation = .workspace
    var onClose: (() -> Void)?
    var openInWorkspace: (() -> Void)?
    @AppStorage(TraceFencePluginDisplayPreferences.mainTabPluginIDsKey)
    private var mainTabPluginIDsJSON = TraceFencePluginDisplayPreferences.defaultMainTabPluginIDsJSON
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("colorPalette") private var colorPalette = AppColorPalette.porcelain.rawValue
    @State private var selectedSurface: Surface = .main
    @State private var visiblePanelSurface: PluginPanelSurface?
    @State private var didResolveDefaultSurface = false
    @State private var loadingTimedOut = false
    @State private var loadingWatchdog: Task<Void, Never>?

    private enum Surface: String {
        case main
        case component
        case settings
    }

    private var preferredPluginColorScheme: ColorScheme? {
        switch appearanceMode {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    private var resolvedPluginColorScheme: ColorScheme {
        preferredPluginColorScheme ?? inheritedColorScheme
    }

    private var pluginComponentTheme: PluginComponentTheme {
        // Reading the palette-backed AppStorage value makes every installed
        // plugin redraw immediately when TraceFence changes skins.
        _ = colorPalette
        return PluginComponentTheme(
            surfaces: .init(
                panel: Theme.Colors.background,
                card: Theme.Colors.cardBg,
                nested: Theme.Colors.elevatedCardBg,
                nestedMuted: Theme.Colors.cardBg.opacity(resolvedPluginColorScheme == .dark ? 0.62 : 0.72),
                chip: Theme.Colors.cardHover,
                control: Theme.Colors.elevatedCardBg,
                controlHover: Theme.Colors.cardHover,
                track: Theme.Colors.separator.opacity(0.72),
                backplate: Theme.Colors.surface
            ),
            text: .init(
                primary: Theme.Colors.textPrimary,
                secondary: Theme.Colors.textSecondary,
                tertiary: Theme.Colors.textTertiary,
                disabled: Theme.Colors.textTertiary.opacity(0.55)
            ),
            status: .init(
                success: Theme.Colors.success,
                warning: Theme.Colors.warning,
                critical: Theme.Colors.danger,
                informational: Theme.Colors.info
            ),
            dataSeries: .init(
                primary: Theme.Colors.accent,
                secondary: Theme.Colors.info,
                tertiary: Theme.Colors.success,
                quaternary: Theme.Colors.purple,
                quinary: Theme.Colors.teal,
                senary: Theme.Colors.cyan
            ),
            interaction: .init(
                selectionOpacity: colorSchemeContrast == .increased ? 0.24 : 0.16,
                emphasisOpacity: colorSchemeContrast == .increased ? 0.14 : 0.09,
                subtleTintOpacity: colorSchemeContrast == .increased ? 0.14 : 0.08
            )
        )
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
                disabledPluginMessage
            case .idle, .loading:
                runtimeLoadingView
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
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Plugin workspaces are type-erased when they cross the bundle boundary.
        // Changing Locale alone does not rebuild an already-created AnyView, so
        // give the rendered subtree a new identity whenever TraceFence changes
        // language. The host view's own @State (selected surface, visibility)
        // stays intact while every plugin gets fresh localized descriptors and
        // content without requiring a restart.
        .id("\(pluginID)-locale-\(pluginLocaleSource.revision)")
        .environment(\.locale, pluginLocaleSource.locale)
        .environment(\.pluginComponentTheme, pluginComponentTheme)
        .tint(Theme.Colors.accent)
        .preferredColorScheme(preferredPluginColorScheme)
        .onAppear {
            launchPlugin()
        }
        .onChange(of: pluginLocaleSource.revision) { _ in
            runtimeHost.refreshLocalization()
        }
        .onChange(of: runtimeHost.state(pluginID: pluginID)) { state in
            if state == .active {
                stopLoadingWatchdog()
                resolveDefaultSurfaceIfNeeded()
                updateVisiblePanelSurface()
            } else if case .failed = state {
                stopLoadingWatchdog()
            } else {
                hideVisiblePanelSurface()
            }
        }
        .onChange(of: selectedSurface) { _ in
            updateVisiblePanelSurface()
        }
        .onDisappear {
            stopLoadingWatchdog()
            hideVisiblePanelSurface()
        }
    }

    private var runtimeLoadingView: some View {
        VStack(spacing: Theme.Spacing.md) {
            if loadingTimedOut {
                Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.Colors.warning)
                Text(localizer.t("插件启动时间过长", en: "Plugin startup is taking too long"))
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(localizer.t(
                    "可以重新尝试；其他页面和插件不会受影响。",
                    en: "You can retry without affecting other pages or plugins."
                ))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                Button {
                    launchPlugin()
                } label: {
                    Label(localizer.t("重新启动插件", en: "Retry Plugin"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(BrandButtonStyle(
                    color: Theme.Colors.accent,
                    variant: .secondary,
                    minHeight: 34
                ))
            } else {
                ProgressView()
                    .controlSize(.large)
                Text(localizer.t("正在启动插件…", en: "Starting plugin…"))
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .background(Theme.Colors.background.opacity(0.22))
    }

    private var disabledPluginMessage: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "pause.circle")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(localizer.t("插件已停用", en: "Plugin disabled"))
                .font(Theme.Font.bodyMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button {
                runtimeHost.setEnabled(true, pluginID: pluginID)
                launchPlugin()
            } label: {
                Label(localizer.t("启用插件", en: "Enable Plugin"), systemImage: "play.circle.fill")
            }
            .buttonStyle(BrandButtonStyle(
                color: Theme.Colors.accent,
                variant: .secondary,
                minHeight: 34
            ))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Spacing.xxl)
    }

    /// Opening from `.task` is unsafe here because refreshing an observed
    /// package manager can rebuild this view and cancel the task before
    /// `runtimeHost.open` runs. `onAppear` executes this short MainActor
    /// sequence atomically and the package records are already refreshed by
    /// the workspace/store owner.
    private func launchPlugin() {
        loadingTimedOut = false
        stopLoadingWatchdog()
        PluginRuntimeLocalization.source.setPreference(localizer.language.rawValue)
        runtimeHost.synchronizeWithInstalledPlugins()
        runtimeHost.open(pluginID: pluginID)
        runtimeHost.refreshLocalization()
        resolveDefaultSurfaceIfNeeded()

        switch runtimeHost.state(pluginID: pluginID) {
        case .idle, .loading:
            startLoadingWatchdog()
        default:
            break
        }
    }

    private func startLoadingWatchdog() {
        loadingWatchdog?.cancel()
        loadingWatchdog = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            switch runtimeHost.state(pluginID: pluginID) {
            case .idle, .loading:
                loadingTimedOut = true
            default:
                break
            }
        }
    }

    private func stopLoadingWatchdog() {
        loadingWatchdog?.cancel()
        loadingWatchdog = nil
    }

    @ViewBuilder
    private var activePlugin: some View {
        if let plugin = runtimeHost.plugin(pluginID: pluginID) {
            switch presentation {
            case .workspace:
                workspacePlugin(plugin)
            case .menuBar:
                menuBarPlugin(plugin)
            }
        }
    }

    private func workspacePlugin(_ plugin: any MacToolsPlugin) -> some View {
        VStack(spacing: 0) {
            workspaceHeader(plugin)
            Divider().overlay(Theme.Colors.separator)
            workspaceSurface(plugin)
                .id("\(pluginID)-\(selectedSurface.rawValue)")
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func menuBarPlugin(_ plugin: any MacToolsPlugin) -> some View {
        VStack(spacing: 0) {
            compactHeader(plugin)
            Divider().overlay(Theme.Colors.separator)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    if catalogDescriptor?.menuBarMode == .status,
                       let component = plugin.componentPanel {
                        compactComponentStatus(component.componentPanelState)
                    } else if let primary = plugin.primaryPanel {
                        primaryPanel(primary)
                    } else if let component = plugin.componentPanel {
                        compactComponentStatus(component.componentPanelState)
                    } else {
                        runtimeMessage(
                            icon: "macwindow",
                            title: localizer.t(
                                "这个插件需要在桌面端使用",
                                en: "This plugin is available in the desktop workspace"
                            )
                        )
                    }

                    if plugin.componentPanel != nil || plugin.settingsPage != nil,
                       let openInWorkspace {
                        Button(action: openInWorkspace) {
                            Label(
                                localizer.t("在桌面打开完整内容", en: "Open Full View on Desktop"),
                                systemImage: "macwindow"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(BrandButtonStyle(
                            color: Theme.Colors.accent,
                            variant: .secondary,
                            minHeight: 34
                        ))
                    }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .clipped()
    }

    private func workspaceHeader(_ plugin: any MacToolsPlugin) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: plugin.metadata.iconName)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(plugin.metadata.iconTint)
                .frame(width: 42, height: 42)
                .background(plugin.metadata.iconTint.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.md))

            VStack(alignment: .leading, spacing: 4) {
                Text(catalogDescriptor?.localizedName() ?? plugin.metadata.title)
                    .font(Theme.Font.title2Bold)
                    .lineLimit(1)
                Text(catalogDescriptor?.localizedSummary() ?? plugin.metadata.defaultDescription)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                placementBadges
            }

            Spacer(minLength: Theme.Spacing.md)

            if availableSurfaces(for: plugin).count > 1 {
                Picker("", selection: $selectedSurface) {
                    ForEach(availableSurfaces(for: plugin), id: \.rawValue) { surface in
                        Text(surfaceLabel(surface, plugin: plugin)).tag(surface)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: CGFloat(availableSurfaces(for: plugin).count) * 86)
            }

            runtimeButtons
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.elevatedCardBg.opacity(0.42))
    }

    private func compactHeader(_ plugin: any MacToolsPlugin) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: plugin.metadata.iconName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(plugin.metadata.iconTint)
                .frame(width: 32, height: 32)
                .background(plugin.metadata.iconTint.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
            VStack(alignment: .leading, spacing: 2) {
                Text(catalogDescriptor?.localizedName() ?? plugin.metadata.title)
                    .font(Theme.Font.bodyMedium)
                    .lineLimit(1)
                HStack(spacing: Theme.Spacing.xs) {
                    Text(menuBarModeLabel)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                    if let descriptor = catalogDescriptor {
                        TraceFencePluginPricingBadge(plugin: descriptor, compact: true)
                    }
                }
            }
            Spacer()
            runtimeButtons
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var runtimeButtons: some View {
        if let descriptor = catalogDescriptor {
            switch packageManager.state(for: descriptor) {
            case let .updateAvailable(_, targetVersion, _):
                Button {
                    installAvailableUpdate()
                } label: {
                    Label("v\(targetVersion)", systemImage: "arrow.down.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(Theme.Colors.accent)
                }
                .buttonStyle(.borderless)
                .help(localizer.t("直接更新此插件到 v\(targetVersion)", en: "Update this plugin directly to v\(targetVersion)"))
            case .downloading, .installing:
                ProgressView()
                    .controlSize(.small)
                    .help(localizer.t("正在更新插件", en: "Updating plugin"))
            default:
                Button {
                    checkThisPluginForUpdates()
                } label: {
                    Image(systemName: "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .disabled(catalogService.isRefreshing)
                .help(localizer.t("检查此插件更新", en: "Check This Plugin for Updates"))
            }
        }

        if showsMainTabPin, catalogDescriptor?.supportsPluginTab == true {
            Button {
                toggleMainTabPin()
            } label: {
                Image(systemName: isPinnedToMainTab ? "pin.fill" : "pin")
                    .foregroundStyle(isPinnedToMainTab ? Theme.Colors.accent : Theme.Colors.textSecondary)
            }
            .buttonStyle(.borderless)
            .help(isPinnedToMainTab
                ? localizer.t("从主 Tab 移除", en: "Remove from Main Tabs")
                : localizer.t("固定到主 Tab", en: "Pin to Main Tabs"))
        }

        Button {
            runtimeHost.refresh(pluginID: pluginID)
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.borderless)
        .help(localizer.t("刷新插件", en: "Refresh Plugin"))

        if let onClose {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .buttonStyle(.borderless)
            .help(localizer.t("关闭插件", en: "Close Plugin"))
        }
    }

    /// Keeps lifecycle actions next to the installed tool. The store remains
    /// the discovery and first-install surface, but is no longer required for
    /// routine updates.
    private func checkThisPluginForUpdates() {
        Task { @MainActor in
            await catalogService.refresh(force: true)
            packageManager.refresh(catalog: catalogService.catalog)
            runtimeHost.synchronizeWithInstalledPlugins()
        }
    }

    private func installAvailableUpdate() {
        Task { @MainActor in
            await catalogService.refresh(force: true)
            packageManager.refresh(catalog: catalogService.catalog)
            guard let plugin = catalogService.catalog.plugin(id: pluginID) else { return }
            await packageManager.install(plugin: plugin)
            runtimeHost.synchronizeWithInstalledPlugins()
        }
    }

    private var showsMainTabPin: Bool {
        switch presentation {
        case .workspace: true
        case .menuBar: false
        }
    }

    private var isPinnedToMainTab: Bool {
        TraceFencePluginDisplayPreferences.mainTabPluginIDs(from: mainTabPluginIDsJSON).contains(pluginID)
    }

    private func toggleMainTabPin() {
        var values = TraceFencePluginDisplayPreferences.mainTabPluginIDs(from: mainTabPluginIDsJSON)
        if let index = values.firstIndex(of: pluginID) {
            values.remove(at: index)
        } else {
            values.append(pluginID)
        }
        mainTabPluginIDsJSON = TraceFencePluginDisplayPreferences.encodedMainTabPluginIDs(values)
    }

    @ViewBuilder
    private var placementBadges: some View {
        HStack(spacing: Theme.Spacing.xs) {
            placementBadge(
                localizer.t("桌面", en: "Desktop"),
                systemImage: "macwindow"
            )
            if let menuBarMode = catalogDescriptor?.menuBarMode {
                placementBadge(
                    menuBarMode == .quickControl
                        ? localizer.t("菜单栏控制", en: "Menu Control")
                        : localizer.t("菜单栏状态", en: "Menu Status"),
                    systemImage: "menubar.rectangle"
                )
            } else {
                placementBadge(
                    localizer.t("仅桌面", en: "Desktop Only"),
                    systemImage: "rectangle.slash"
                )
            }
            if let descriptor = catalogDescriptor {
                TraceFencePluginPricingBadge(plugin: descriptor, compact: true)
            }
        }
    }

    private func placementBadge(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(Theme.Colors.textTertiary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Theme.Colors.cardBg.opacity(0.78), in: Capsule())
    }

    @ViewBuilder
    private func workspaceSurface(_ plugin: any MacToolsPlugin) -> some View {
        switch selectedSurface {
        case .settings:
            if let page = runtimeHost.settingsPage(pluginID: pluginID) {
                settingsSurface(plugin: plugin, page: page)
            } else {
                runtimeMessage(
                    icon: "gearshape",
                    title: localizer.t("这个插件没有可配置项目", en: "This plugin has no configurable settings")
                )
            }
        case .component:
            if let component = runtimeHost.componentView(
                pluginID: pluginID,
                dismiss: onClose ?? {},
                isPanelVisible: true
            ) {
                ScrollView(.vertical) {
                    component
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(Theme.Spacing.xl)
                }
                .scrollIndicators(.visible)
            } else {
                fallbackWorkspaceSurface(plugin)
            }
        case .main:
            if let primary = plugin.primaryPanel {
                ScrollView(.vertical) {
                    primaryPanel(primary)
                        .padding(Theme.Spacing.xl)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
            } else {
                fallbackWorkspaceSurface(plugin)
            }
        }
    }

    @ViewBuilder
    private func fallbackWorkspaceSurface(_ plugin: any MacToolsPlugin) -> some View {
        if let component = runtimeHost.componentView(
            pluginID: pluginID,
            dismiss: onClose ?? {},
            isPanelVisible: true
        ) {
            ScrollView(.vertical) {
                component
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(Theme.Spacing.xl)
            }
        } else if let page = runtimeHost.settingsPage(pluginID: pluginID) {
            settingsSurface(plugin: plugin, page: page)
        } else {
            runtimeMessage(
                icon: "slider.horizontal.3",
                title: localizer.t("这个插件暂时没有可用界面", en: "This plugin has no available interface")
            )
        }
    }

    @ViewBuilder
    private func settingsSurface(plugin: any MacToolsPlugin, page: PluginSettingsPage) -> some View {
        let settingsView = TraceFencePluginSettingsView(
            pluginID: pluginID,
            plugin: plugin,
            page: page,
            runtimeHost: runtimeHost
        )
        if pageUsesHostScrolling(page) {
            ScrollView(.vertical) {
                settingsView
                    .padding(Theme.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.visible)
        } else {
            settingsView
                .padding(Theme.Spacing.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func compactComponentStatus(_ state: PluginComponentState) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Circle()
                    .fill(state.isActive ? Theme.Colors.success : Theme.Colors.textTertiary)
                    .frame(width: 8, height: 8)
                Text(state.isActive
                    ? localizer.t("状态正常", en: "Active")
                    : localizer.t("等待运行", en: "Waiting"))
                    .font(Theme.Font.captionMedium)
                Spacer()
                Text(localizer.t("状态摘要", en: "Status Summary"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Text(state.subtitle)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let error = state.errorMessage, !error.isEmpty {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.warning)
            }
        }
        .cardStyle()
    }

    private var catalogDescriptor: TraceFencePluginDescriptor? {
        TraceFenceMarketplaceCatalogRuntime.plugin(id: pluginID)
    }

    private var menuBarModeLabel: String {
        switch catalogDescriptor?.menuBarMode {
        case .quickControl:
            return localizer.t("菜单栏快捷控制", en: "Menu Bar Quick Control")
        case .status:
            return localizer.t("菜单栏状态摘要", en: "Menu Bar Status Summary")
        case nil:
            return localizer.t("桌面端插件", en: "Desktop Plugin")
        }
    }

    private func availableSurfaces(for plugin: any MacToolsPlugin) -> [Surface] {
        var result: [Surface] = []
        if plugin.primaryPanel != nil { result.append(.main) }
        if plugin.componentPanel != nil { result.append(.component) }
        if plugin.settingsPage != nil { result.append(.settings) }
        return result
    }

    private func surfaceLabel(_ surface: Surface, plugin: any MacToolsPlugin) -> String {
        switch surface {
        case .main:
            return localizer.t("快捷控制", en: "Control")
        case .component:
            return localizer.t("数据面板", en: "Dashboard")
        case .settings:
            if let page = plugin.settingsPage, case .workspace = page.body {
                return localizer.t("完整工具", en: "Full Tool")
            }
            return localizer.t("设置", en: "Settings")
        }
    }

    private func resolveDefaultSurfaceIfNeeded() {
        guard !didResolveDefaultSurface,
              let plugin = runtimeHost.plugin(pluginID: pluginID) else { return }
        let preferred: Surface
        switch presentation {
        case .menuBar:
            preferred = catalogDescriptor?.menuBarMode == .status ? .component : .main
        case .workspace:
            switch catalogDescriptor?.workspaceLanding {
            case .quickControl:
                preferred = .main
            case .dataPanel:
                preferred = .component
            case .workspace, .settings:
                preferred = .settings
            case nil:
                preferred = fallbackDefaultSurface(for: plugin)
            }
        }
        let available = availableSurfaces(for: plugin)
        selectedSurface = available.contains(preferred)
            ? preferred
            : (available.first ?? .settings)
        didResolveDefaultSurface = true
    }

    private func fallbackDefaultSurface(for plugin: any MacToolsPlugin) -> Surface {
        if plugin.componentPanel != nil { return .component }
        if let page = plugin.settingsPage, case .workspace = page.body { return .settings }
        if plugin.primaryPanel != nil { return .main }
        return .settings
    }

    private func pageUsesHostScrolling(_ page: PluginSettingsPage) -> Bool {
        switch page.body {
        case .form:
            return true
        case let .workspace(workspace):
            switch workspace.scrolling {
            case .host: return true
            case .selfManaged: return false
            }
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
        catalogDescriptor?.localizedName()
            ?? runtimeHost.plugin(pluginID: pluginID)?.metadata.title
            ?? localizer.t("插件", en: "Plugin")
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
    @AppStorage(TraceFencePluginDisplayPreferences.mainTabPluginIDsKey)
    private var mainTabPluginIDsJSON = TraceFencePluginDisplayPreferences.defaultMainTabPluginIDsJSON
    @State private var searchText = ""
    @State private var pluginPendingCompleteUninstall: TraceFencePluginDescriptor?

    var body: some View {
        HStack(spacing: 0) {
            pluginRail
                .frame(width: 286)
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
        .confirmationDialog(
            completeUninstallTitle,
            isPresented: Binding(
                get: { pluginPendingCompleteUninstall != nil },
                set: { if !$0 { pluginPendingCompleteUninstall = nil } }
            )
        ) {
            if let plugin = pluginPendingCompleteUninstall {
                Button(localizer.t("完全卸载", en: "Uninstall Completely"), role: .destructive) {
                    Task { @MainActor in
                        await runtimeHost.uninstallCompletely(pluginID: plugin.id)
                        if selectedPluginID == plugin.id { selectedPluginID = nil }
                        pluginPendingCompleteUninstall = nil
                    }
                }
            }
            Button(localizer.cancel, role: .cancel) {
                pluginPendingCompleteUninstall = nil
            }
        } message: {
            Text(localizer.t(
                "将删除插件程序、全部插件数据、缓存、临时文件和本机插件设置。已购买的授权仍会保留，之后可以重新安装。",
                en: "This removes the plugin code, all plugin data, caches, temporary files, and local plugin settings. Purchased access is retained so the plugin can be installed again."
            ))
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
        let isMainTab = mainTabPluginIDs.contains(plugin.id)
        let supportsMenuBar = plugin.supportsMenuBarQuickPanel
        let isEnabled = packageManager.record(pluginID: plugin.id)?.enabled ?? false
        let installationState = packageManager.state(for: plugin)
        let installedVersion = installationState.installedVersion ?? plugin.version
        return HStack(spacing: Theme.Spacing.sm) {
            Button {
                selectedPluginID = plugin.id
            } label: {
                HStack(spacing: Theme.Spacing.sm) {
                    Image(systemName: plugin.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? .white : Theme.Colors.accent)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                                .fill(isSelected ? AnyShapeStyle(Theme.Gradients.hero) : AnyShapeStyle(Theme.Colors.accent.opacity(0.10)))
                        )
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(plugin.localizedName())
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .layoutPriority(1)
                            Spacer(minLength: 2)
                            TraceFencePluginPricingBadge(plugin: plugin, compact: true)
                                .fixedSize()
                        }
                        HStack(spacing: 5) {
                            Text("v\(installedVersion)")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .fixedSize(horizontal: true, vertical: false)
                            if case .updateAvailable = installationState {
                                compactRailStatus(
                                    localizer.t("可更新", en: "Update"),
                                    color: Theme.Colors.accent,
                                    icon: "arrow.down.circle.fill"
                                )
                            }
                            if !isEnabled {
                                compactRailStatus(
                                    localizer.t("已停用", en: "Disabled"),
                                    color: Theme.Colors.warning,
                                    icon: "pause.circle.fill"
                                )
                            }
                            Spacer(minLength: 0)
                            if isMainTab {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(Theme.Colors.accent)
                                    .help(localizer.t("已固定到主 Tab", en: "Pinned to Main Tabs"))
                            }
                            if isPinned {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(Theme.Colors.warning)
                                    .help(localizer.t("已固定到菜单栏", en: "Pinned to Menu Bar"))
                            }
                        }
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .layoutPriority(1)

            Menu {
                Button {
                    runtimeHost.setEnabled(!isEnabled, pluginID: plugin.id)
                } label: {
                    Label(
                        isEnabled
                            ? localizer.t("停用插件", en: "Disable Plugin")
                            : localizer.t("启用插件", en: "Enable Plugin"),
                        systemImage: isEnabled ? "pause.circle" : "play.circle"
                    )
                }
                if case let .updateAvailable(_, targetVersion, _) = packageManager.state(for: plugin) {
                    Button {
                        Task { @MainActor in
                            await packageManager.install(plugin: plugin)
                            runtimeHost.synchronizeWithInstalledPlugins()
                        }
                    } label: {
                        Label(
                            localizer.t("更新到 v\(targetVersion)", en: "Update to v\(targetVersion)"),
                            systemImage: "arrow.down.circle"
                        )
                    }
                }
                Divider()
                Button {
                    toggleMainTab(plugin.id)
                } label: {
                    Label(
                        isMainTab
                            ? localizer.t("从主 Tab 移除", en: "Remove from Main Tabs")
                            : localizer.t("固定到主 Tab", en: "Pin to Main Tabs"),
                        systemImage: isMainTab ? "pin.slash" : "pin"
                    )
                }
                if supportsMenuBar {
                    Button {
                        togglePinned(plugin.id)
                    } label: {
                        Label(
                            isPinned
                                ? localizer.t("从菜单栏移除", en: "Remove from Menu Bar")
                                : localizer.t("固定到菜单栏", en: "Pin to Menu Bar"),
                            systemImage: isPinned ? "star.slash" : "star"
                        )
                    }
                }
                Divider()
                Button {
                    packageManager.reveal(pluginID: plugin.id)
                } label: {
                    Label(localizer.t("在访达中显示", en: "Reveal in Finder"), systemImage: "folder")
                }
                Divider()
                Button(role: .destructive) {
                    pluginPendingCompleteUninstall = plugin
                } label: {
                    Label(localizer.t("完全卸载…", en: "Uninstall Completely…"), systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 28, height: 34)
                    .background(Theme.Colors.elevatedCardBg.opacity(0.72), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(localizer.t("管理插件", en: "Manage Plugin"))
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(isSelected
                    ? Theme.Colors.accent.opacity(0.10)
                    : Theme.Colors.elevatedCardBg.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(isSelected ? Theme.Colors.accent.opacity(0.30) : Color.clear, lineWidth: 1)
        )
    }

    private func compactRailStatus(_ title: String, color: Color, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
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
                    "从左侧打开已安装插件。图钉固定到主 Tab；星标固定到菜单栏快捷区。",
                    en: "Open an installed plugin from the left. Use the pin for Main Tabs and the star for the menu-bar quick area."
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
        catalogService.catalog.plugins.filter {
            $0.supportsPluginTab && packageManager.records[$0.id] != nil
        }
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

    private var mainTabPluginIDs: Set<String> {
        Set(TraceFencePluginDisplayPreferences.mainTabPluginIDs(from: mainTabPluginIDsJSON))
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

    private func toggleMainTab(_ pluginID: String) {
        var values = TraceFencePluginDisplayPreferences.mainTabPluginIDs(from: mainTabPluginIDsJSON)
        if let index = values.firstIndex(of: pluginID) {
            values.remove(at: index)
        } else {
            values.append(pluginID)
        }
        mainTabPluginIDsJSON = TraceFencePluginDisplayPreferences.encodedMainTabPluginIDs(values)
    }

    private func selectFirstPluginIfNeeded() {
        guard let selectedPluginID else { return }
        if packageManager.records[selectedPluginID] == nil
            || catalogService.catalog.plugin(id: selectedPluginID)?.supportsPluginTab != true {
            self.selectedPluginID = nil
        }
    }

    private var completeUninstallTitle: String {
        guard let plugin = pluginPendingCompleteUninstall else {
            return localizer.t("完全卸载插件？", en: "Uninstall plugin completely?")
        }
        return localizer.t(
            "完全卸载 \(plugin.localizedName())？",
            en: "Uninstall \(plugin.localizedName()) completely?"
        )
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
        if !plugin.permissionRequirements.isEmpty {
            Label(
                localizer.t(
                    "系统权限由 TraceFence 主应用统一管理，所有插件共用已有授权，不会为插件重复申请。",
                    en: "System permissions are managed by the TraceFence app and shared by all plugins; plugins do not request a separate grant.",
                    zhHant: "系統權限由 TraceFence 主應用程式統一管理，所有外掛共用現有授權，不會為外掛重複申請。",
                    ja: "システム権限は TraceFence アプリが一元管理し、すべてのプラグインで共有します。プラグインごとの再承認は不要です。",
                    ko: "시스템 권한은 TraceFence 앱이 통합 관리하며 모든 플러그인이 기존 권한을 공유합니다. 플러그인별로 다시 승인하지 않습니다.",
                    mt: "Il-permessi tas-sistema huma ġestiti mill-app TraceFence u kondiviżi mill-plugins kollha; m’hemmx awtorizzazzjoni separata għal kull plugin."
                ),
                systemImage: "checkmark.shield"
            )
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.sm)

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
                        ? localizer.t("TraceFence 已授权", en: "TraceFence Granted")
                        : localizer.t("授权 TraceFence", en: "Grant TraceFence Access")) {
                        runtimeHost.handlePermissionAction(pluginID: pluginID, permissionID: requirement.id)
                    }
                    .disabled(state.isGranted)
                }
                .cardStyle()
            }
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
        var disableSucceeded = false
        var purgeSucceeded = false

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
                    presentation: descriptor.presentation,
                    placements: descriptor.placements,
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
            } else if pluginID == ProviderQuotaService.pluginID,
                      let quotaMonitor = runtimePlugin as? any PluginQuotaMonitoring {
                let payloadIsDecodable: Bool
                if let payload = quotaMonitor.quotaSnapshotPayload {
                    payloadIsDecodable = (try? JSONDecoder().decode(
                        [ProviderQuotaSnapshot].self,
                        from: payload
                    )) != nil
                } else {
                    payloadIsDecodable = false
                }
                actionSucceeded = payloadIsDecodable
            } else {
                actionSucceeded = usableSurface
            }
        } else {
            failures.append("Plugin runtime loading failed: \(String(describing: runtime.state(pluginID: pluginID)))")
        }
        if !usableSurface { failures.append("The plugin has no host-renderable primary, component, or settings surface.") }
        if !actionSucceeded { failures.append("The plugin interaction self-test failed.") }

        runtime.setEnabled(false, pluginID: pluginID)
        let disabledWithoutSession = runtime.state(pluginID: pluginID) == .disabled
            && runtime.plugin(pluginID: pluginID) == nil
        runtime.openForTesting(pluginID: pluginID)
        let remainedDisabledWhenOpened = runtime.state(pluginID: pluginID) == .disabled
            && manager.record(pluginID: pluginID)?.enabled == false
        runtime.setEnabled(true, pluginID: pluginID)
        runtime.openForTesting(pluginID: pluginID)
        let reenabled = runtime.state(pluginID: pluginID) == .active
        disableSucceeded = disabledWithoutSession && remainedDisabledWhenOpened && reenabled
        if !disableSucceeded {
            failures.append("Plugin disable/enable lifecycle failed.")
        }

        let pluginOwnedRoots = [
            TraceFencePluginPackageManager.dataDirectory,
            TraceFencePluginPackageManager.cachesDirectory,
            TraceFencePluginPackageManager.temporaryDirectory
        ].map { $0.appendingPathComponent(pluginID, isDirectory: true) }
        for root in pluginOwnedRoots {
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try? Data("purge-sentinel".utf8).write(to: root.appendingPathComponent("sentinel"), options: .atomic)
        }

        let defaultsSuiteName = "TraceFencePluginRuntimeSelfTest.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuiteName)!
        defaults.set("[\"\(pluginID)\",\"tracefence.tools.keep\"]", forKey: TraceFencePluginDisplayPreferences.pinnedPluginIDsKey)
        defaults.set("[\"\(pluginID)\"]", forKey: TraceFencePluginDisplayPreferences.mainTabPluginIDsKey)
        UserDefaultsPluginStorage(pluginID: pluginID, userDefaults: defaults).set("sentinel", forKey: "purge")
        UserDefaultsPluginStorage.removeAllValues(pluginID: pluginID, userDefaults: defaults)
        TraceFencePluginDisplayPreferences.remove(pluginID: pluginID, userDefaults: defaults)
        let scopedDefaultsPurged = UserDefaultsPluginStorage(
            pluginID: pluginID,
            userDefaults: defaults
        ).string(forKey: "purge") == nil
        let displayPreferencesPurged = !TraceFencePluginDisplayPreferences.pinnedPluginIDs(
            from: defaults.string(forKey: TraceFencePluginDisplayPreferences.pinnedPluginIDsKey) ?? "[]"
        ).contains(pluginID) && !TraceFencePluginDisplayPreferences.mainTabPluginIDs(
            from: defaults.string(forKey: TraceFencePluginDisplayPreferences.mainTabPluginIDsKey) ?? "[]"
        ).contains(pluginID)
        defaults.removePersistentDomain(forName: defaultsSuiteName)

        await runtime.uninstallCompletely(pluginID: pluginID)
        removed = manager.record(pluginID: pluginID) == nil
        if !removed { failures.append("Plugin uninstall failed.") }
        purgeSucceeded = pluginOwnedRoots.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) }
            && scopedDefaultsPurged
            && displayPreferencesPurged
        if !purgeSucceeded {
            failures.append("Complete uninstall left plugin-owned data or settings behind.")
        }

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
            removed: removed,
            disableSucceeded: disableSucceeded,
            purgeSucceeded: purgeSucceeded
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
        removed: Bool = false,
        disableSucceeded: Bool = false,
        purgeSucceeded: Bool = false
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
            "disableSucceeded": disableSucceeded,
            "purgeSucceeded": purgeSucceeded,
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
