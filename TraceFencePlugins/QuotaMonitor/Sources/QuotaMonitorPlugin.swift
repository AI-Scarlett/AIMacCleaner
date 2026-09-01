import AppKit
import Combine
import Darwin
import Foundation
import MacToolsPluginKit
import ObjectiveC.runtime
import SwiftUI

public final class QuotaMonitorPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        QuotaMonitorPluginProvider(context: context)
    }
}

@MainActor
private struct QuotaMonitorPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        let localization = PluginLocalization(bundle: context.resourceBundle)
        let engineURL = context.resourceBundle.url(
            forResource: "codexbar",
            withExtension: nil,
            subdirectory: "Helpers"
        )
        return [QuotaMonitorPlugin(engineURL: engineURL, localization: localization)]
    }
}

@MainActor
final class QuotaMonitorPlugin: MacToolsPlugin, PluginPrimaryPanel,
    PluginQuotaMonitoring, PluginRuntimeLocalizationRefreshing {
    private enum ControlID {
        static let refresh = "quota-monitor-refresh"
        static let previousProvider = "quota-monitor-previous-provider"
        static let nextProvider = "quota-monitor-next-provider"
        static let automaticProvider = "quota-monitor-automatic-provider"
        static let toggleTouchBar = "quota-monitor-toggle-touch-bar"
        static let cleanLegacyTouchBar = "quota-monitor-clean-legacy-touch-bar"
    }

    private(set) var metadata: PluginMetadata
    let primaryPanelDescriptor = PluginPrimaryPanelDescriptor(
        controlStyle: .disclosure,
        menuActionBehavior: .keepPresented
    )

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?

    private let service: ProviderQuotaService
    private let localization: PluginLocalization
    private let touchBarController = QuotaTouchBarController()
    private var serviceChangeCancellable: AnyCancellable?
    private var isExpanded = false

    fileprivate init(engineURL: URL?, localization: PluginLocalization) {
        self.service = ProviderQuotaService(
            providerEngineURL: engineURL,
            requiresExplicitProviderEngine: true
        )
        self.localization = localization
        self.metadata = Self.makeMetadata(localization: localization)
        touchBarController.onStateChange = { [weak self] in
            self?.onStateChange?()
        }
        serviceChangeCancellable = service.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.touchBarController.receive(snapshots: self?.service.snapshots ?? [])
                self?.onStateChange?()
            }
        }
    }

    private static func makeMetadata(localization: PluginLocalization) -> PluginMetadata {
        PluginMetadata(
            id: "quota-monitor",
            title: localization.string("metadata.title", defaultValue: "额度监控"),
            iconName: "waveform.path.ecg.rectangle",
            iconTint: Color(nsColor: .systemBlue),
            order: 30,
            defaultDescription: localization.string(
                "metadata.description",
                defaultValue: "读取 Codex、Claude、Grok 等 Provider 的额度与重置时间。Touch Bar 由此插件独立显示。"
            )
        )
    }

    func refreshLocalization() {
        metadata = Self.makeMetadata(localization: localization)
        onStateChange?()
    }

    var primaryPanelState: PluginPanelState {
        let readable = service.snapshots.filter(\.quotaReadSucceeded)
        let subtitle: String
        if service.isRefreshing, service.snapshots.isEmpty {
            subtitle = localization.string("panel.refreshing", defaultValue: "正在读取 Provider 额度…")
        } else if let summary = touchBarController.panelSummary {
            subtitle = summary
        } else if readable.isEmpty {
            subtitle = localization.string("panel.waiting", defaultValue: "等待首次额度读取")
        } else {
            subtitle = localization.format(
                "panel.providersFormat",
                defaultValue: "%lld 个 Provider 已更新",
                Int64(readable.count)
            )
        }

        var controls: [PluginPanelControl] = [
            PluginPanelControl(
                id: ControlID.refresh,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: service.isRefreshing
                    ? localization.string("action.refreshing", defaultValue: "刷新中…")
                    : localization.string("action.refresh", defaultValue: "刷新额度"),
                actionIconSystemName: "arrow.clockwise",
                isEnabled: !service.isRefreshing && service.refreshCooldownRemaining() <= 0
            ),
            PluginPanelControl(
                id: ControlID.previousProvider,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: localization.string("panel.agentSection", defaultValue: "当前显示"),
                actionTitle: localization.string("panel.previousAgent", defaultValue: "查看上一个 Agent"),
                actionIconSystemName: "chevron.left",
                isEnabled: touchBarController.hasQuotaProviders
            ),
            PluginPanelControl(
                id: ControlID.nextProvider,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: localization.string("panel.nextAgent", defaultValue: "查看下一个 Agent"),
                actionIconSystemName: "chevron.right",
                isEnabled: touchBarController.hasQuotaProviders
            ),
            PluginPanelControl(
                id: ControlID.automaticProvider,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: localization.string("panel.followActiveAgent", defaultValue: "恢复跟随当前 Agent"),
                actionIconSystemName: "scope",
                isEnabled: touchBarController.hasQuotaProviders
            ),
            PluginPanelControl(
                id: ControlID.toggleTouchBar,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: localization.string("touchbar.section", defaultValue: "Touch Bar"),
                actionTitle: touchBarController.isVisible
                    ? localization.string("touchbar.action.hide", defaultValue: "隐藏 Touch Bar 额度显示")
                    : localization.string("touchbar.action.show", defaultValue: "显示 Touch Bar 额度监控"),
                actionIconSystemName: touchBarController.isVisible ? "xmark.rectangle" : "touchbar",
                isEnabled: !touchBarController.isUpdating
            )
        ]

        if touchBarController.hasLegacyBetterTouchToolWidgets {
            controls.append(PluginPanelControl(
                id: ControlID.cleanLegacyTouchBar,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: localization.string("touchbar.legacySection", defaultValue: "旧版迁移"),
                actionTitle: localization.string(
                    "touchbar.action.cleanLegacy",
                    defaultValue: "清理本插件创建的旧版 BetterTouchTool 控件"
                ),
                actionIconSystemName: "trash",
                isEnabled: !touchBarController.isUpdating
            ))
        }

        return PluginPanelState(
            subtitle: subtitle,
            isOn: service.isRefreshing,
            isExpanded: isExpanded,
            isEnabled: true,
            isVisible: true,
            detail: isExpanded ? PluginPanelDetail(controls: controls) : nil,
            errorMessage: touchBarController.errorMessage
        )
    }

    func activate(context: PluginRuntimeContext) {
        touchBarController.activate(snapshots: service.snapshots)
    }

    func deactivate(reason: PluginDeactivationReason) {
        service.stop()
        touchBarController.deactivate(disablePreference: reason == .disabled || reason == .uninstalling)
    }

    func refresh() {
        service.refresh()
    }

    func handleAction(_ action: PluginPanelAction) {
        switch action {
        case let .setDisclosureExpanded(value):
            isExpanded = value
            onStateChange?()
        case let .invokeAction(controlID) where controlID == ControlID.refresh:
            service.refresh(force: true)
        case let .invokeAction(controlID) where controlID == ControlID.previousProvider:
            touchBarController.selectPreviousProvider()
        case let .invokeAction(controlID) where controlID == ControlID.nextProvider:
            touchBarController.selectNextProvider()
        case let .invokeAction(controlID) where controlID == ControlID.automaticProvider:
            touchBarController.resumeAutomaticSelection()
        case let .invokeAction(controlID) where controlID == ControlID.toggleTouchBar:
            touchBarController.toggleVisibility()
        case let .invokeAction(controlID) where controlID == ControlID.cleanLegacyTouchBar:
            touchBarController.removeLegacyBetterTouchToolWidgets()
        case .invokeAction, .setSwitch, .setSelection, .setNavigationSelection,
             .clearNavigationSelection, .setDate, .setSlider:
            break
        }
    }

    var quotaSnapshotPayload: Data? {
        try? JSONEncoder().encode(service.snapshots)
    }

    var quotaMonitoringIsRefreshing: Bool { service.isRefreshing }
    var quotaMonitoringLastRefreshDate: Date? { service.lastRefreshDate }
    var quotaMonitoringLastRefreshRequestedDate: Date? { service.lastRefreshRequestedDate }

    func startQuotaMonitoring() { service.start() }
    func stopQuotaMonitoring() { service.stop() }
    func refreshQuotaMonitoring(force: Bool) { service.refresh(force: force) }
    func quotaMonitoringRefreshCooldownRemaining() -> TimeInterval { service.refreshCooldownRemaining() }
}

@MainActor
private final class QuotaTouchBarController {
    private enum Selection {
        case automatic
        case manual(String)
    }

    private enum Preference {
        static let visibleKey = "com.tracefence.plugin.quota-monitor.native-touch-bar.visible"
    }

    private let renderer = NativeQuotaTouchBarRenderer()
    private var snapshots: [ProviderQuotaSnapshot] = []
    private var selection: Selection = .automatic
    private var selectedProviderID: String?
    private var activationObserver: NSObjectProtocol?
    private var isActive = false

    private(set) var isUpdating = false
    private(set) var errorMessage: String?
    var onStateChange: (() -> Void)?

    var isVisible: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Preference.visibleKey) == nil {
            defaults.set(true, forKey: Preference.visibleKey)
            return true
        }
        return defaults.bool(forKey: Preference.visibleKey)
    }

    var hasQuotaProviders: Bool { !QuotaTouchBarDisplay.items(from: snapshots).isEmpty }
    var hasLegacyBetterTouchToolWidgets: Bool { LegacyBetterTouchToolWidgetCleanup.hasOwnedWidgetState }
    var panelSummary: String? {
        guard hasQuotaProviders else { return nil }
        return displayState().summary
    }

    func activate(snapshots: [ProviderQuotaSnapshot]) {
        isActive = true
        self.snapshots = snapshots
        startObserving()
        // A pre-1.0.9 widget is a visible remnant of this plugin, so make one
        // best-effort cleanup attempt during the migration. Failure stays
        // non-fatal and leaves the explicit panel action available.
        LegacyBetterTouchToolWidgetCleanup.removeOwnedWidgetsIfPossible()
        refreshDisplay()
    }

    func deactivate(disablePreference: Bool) {
        isActive = false
        stopObserving()
        renderer.tearDown()
        if disablePreference {
            setVisible(false)
        }
    }

    func receive(snapshots: [ProviderQuotaSnapshot]) {
        self.snapshots = snapshots
        guard isActive else { return }
        refreshDisplay()
    }

    func toggleVisibility() {
        setVisible(!isVisible)
        refreshDisplay()
    }

    func selectPreviousProvider() {
        cycleProvider(offset: -1)
        refreshDisplay()
    }

    func selectNextProvider() {
        cycleProvider(offset: 1)
        refreshDisplay()
    }

    func resumeAutomaticSelection() {
        selection = .automatic
        refreshDisplay()
    }

    func removeLegacyBetterTouchToolWidgets() {
        beginUpdate()
        defer { finishUpdate() }
        do {
            try LegacyBetterTouchToolWidgetCleanup.removeOwnedWidgets()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: Preference.visibleKey)
        if !visible { renderer.hide() }
    }

    private func beginUpdate() {
        isUpdating = true
        errorMessage = nil
        onStateChange?()
    }

    private func finishUpdate() {
        isUpdating = false
        onStateChange?()
    }

    private func startObserving() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDisplay() }
        }
    }

    private func stopObserving() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    private func cycleProvider(offset: Int) {
        let items = QuotaTouchBarDisplay.items(from: snapshots)
        guard !items.isEmpty else { return }
        let currentIndex = selectedProviderID.flatMap { id in
            items.firstIndex(where: { $0.id == id })
        } ?? 0
        let nextIndex = (currentIndex + offset + items.count) % items.count
        selection = .manual(items[nextIndex].id)
        selectedProviderID = items[nextIndex].id
    }

    private func refreshDisplay() {
        let display = displayState()
        guard isActive, isVisible else {
            if !isVisible { renderer.hide() }
            onStateChange?()
            return
        }
        do {
            try renderer.show(
                display,
                onPrevious: { [weak self] in self?.selectPreviousProvider() },
                onNext: { [weak self] in self?.selectNextProvider() },
                onAutomatic: { [weak self] in self?.resumeAutomaticSelection() },
                onControlStripToggle: { [weak self] in self?.toggleVisibility() },
                onClose: { [weak self] in
                    self?.setVisible(false)
                    self?.onStateChange?()
                }
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        onStateChange?()
    }

    private func displayState() -> QuotaTouchBarDisplay.State {
        let items = QuotaTouchBarDisplay.items(from: snapshots)
        guard !items.isEmpty else {
            selectedProviderID = nil
            return .unavailable()
        }

        let manuallySelected: QuotaTouchBarDisplay.Item?
        switch selection {
        case let .manual(id):
            manuallySelected = items.first(where: { $0.id == id })
            if manuallySelected == nil { selection = .automatic }
        case .automatic:
            manuallySelected = nil
        }

        let resolved: QuotaTouchBarDisplay.Item
        if let manuallySelected {
            resolved = manuallySelected
        } else if let foreground = items.first(where: {
            $0.providerKey == QuotaTouchBarDisplay.providerKey(for: frontmostApplicationText())
        }) {
            resolved = foreground
        } else if let prior = selectedProviderID.flatMap({ id in items.first(where: { $0.id == id }) }) {
            resolved = prior
        } else {
            resolved = items.min(by: { $0.lowestRemaining < $1.lowestRemaining }) ?? items[0]
        }
        selectedProviderID = resolved.id
        return .quota(item: resolved, isAutomatic: isAutomaticSelection)
    }

    private var isAutomaticSelection: Bool {
        if case .automatic = selection { return true }
        return false
    }

    private func frontmostApplicationText() -> String {
        let app = NSWorkspace.shared.frontmostApplication
        return [app?.localizedName, app?.bundleIdentifier]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

private enum QuotaTouchBarDisplay {
    struct Item: Equatable {
        let id: String
        let providerKey: String
        let providerName: String
        let providerAbbreviation: String
        let fiveHourRemaining: Int?
        let weeklyRemaining: Int?
        let lowestRemaining: Int
    }

    struct State: Equatable {
        let providerName: String
        let providerAbbreviation: String
        let fiveHourRemaining: Int?
        let weeklyRemaining: Int?
        let isAutomatic: Bool
        let isUnavailable: Bool

        var summary: String {
            guard !isUnavailable else { return "暂无额度数据" }
            let fiveHour = fiveHourRemaining.map(String.init) ?? "—"
            let weekly = weeklyRemaining.map(String.init) ?? "—"
            let mode = isAutomatic ? "自动跟随" : "手动选择"
            return "\(providerName) · 5h \(fiveHour)% · 周 \(weekly)% · \(mode)"
        }

        static func unavailable() -> State {
            State(
                providerName: "额度",
                providerAbbreviation: "—",
                fiveHourRemaining: nil,
                weeklyRemaining: nil,
                isAutomatic: true,
                isUnavailable: true
            )
        }

        static func quota(item: Item, isAutomatic: Bool) -> State {
            State(
                providerName: item.providerName,
                providerAbbreviation: item.providerAbbreviation,
                fiveHourRemaining: item.fiveHourRemaining,
                weeklyRemaining: item.weeklyRemaining,
                isAutomatic: isAutomatic,
                isUnavailable: false
            )
        }
    }

    static func items(from snapshots: [ProviderQuotaSnapshot]) -> [Item] {
        snapshots.compactMap { snapshot in
            guard !snapshot.isSetupNotice else { return nil }
            let allowanceWindows = snapshot.windows.filter { window in
                window.kind == .fiveHour
                    || window.kind == .weekly
                    || (window.kind == .extra && window.windowMinutes == 10_080)
            }
            guard !allowanceWindows.isEmpty else { return nil }
            let fiveHour = allowanceWindows
                .filter { $0.kind == .fiveHour }
                .map(\.remainingPercent)
                .min()
            let weekly = allowanceWindows
                .filter { $0.kind == .weekly || ($0.kind == .extra && $0.windowMinutes == 10_080) }
                .map(\.remainingPercent)
                .min()
            let lowest = allowanceWindows.map(\.remainingPercent).min() ?? 0
            let key = providerKey(for: snapshot.providerName)
            return Item(
                id: snapshot.id,
                providerKey: key,
                providerName: sanitizedProviderName(key),
                providerAbbreviation: providerAbbreviation(key),
                fiveHourRemaining: fiveHour.map { Int($0.rounded()) },
                weeklyRemaining: weekly.map { Int($0.rounded()) },
                lowestRemaining: Int(lowest.rounded())
            )
        }
        .sorted { lhs, rhs in
            if lhs.providerName != rhs.providerName {
                return lhs.providerName.localizedCaseInsensitiveCompare(rhs.providerName) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    static func providerKey(for text: String) -> String {
        let normalized = text.lowercased()
        if normalized.contains("codex") || normalized.contains("openai") { return "codex" }
        if normalized.contains("claude") || normalized.contains("anthropic") { return "claude" }
        if normalized.contains("grok") || normalized.contains("xai") { return "grok" }
        if normalized.contains("deepseek") || normalized.contains("dsh") { return "deepseek" }
        if normalized.contains("gemini") || normalized.contains("google") { return "gemini" }
        if normalized.contains("cursor") { return "cursor" }
        if normalized.contains("minimax") { return "minimax" }
        if normalized.contains("antigravity") { return "antigravity" }
        return normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first(where: { !$0.isEmpty }) ?? ""
    }

    static func meterColor(for remaining: Int?) -> NSColor {
        guard let remaining else { return .systemGray }
        switch remaining {
        case ..<20: return NSColor(red: 0.93, green: 0.27, blue: 0.31, alpha: 1)
        case ..<50: return NSColor(red: 0.96, green: 0.49, blue: 0.12, alpha: 1)
        case ..<70: return NSColor(red: 0.98, green: 0.78, blue: 0.16, alpha: 1)
        default: return NSColor(red: 0.24, green: 0.82, blue: 0.42, alpha: 1)
        }
    }

    private static func sanitizedProviderName(_ key: String) -> String {
        switch key {
        case "codex": return "GPT"
        case "claude": return "Claude"
        case "grok": return "Grok"
        case "cursor": return "Cursor"
        case "gemini": return "Gemini"
        case "deepseek": return "DeepSeek"
        case "minimax": return "MiniMax"
        case "antigravity": return "Antigravity"
        default: return "Provider"
        }
    }

    private static func providerAbbreviation(_ key: String) -> String {
        switch key {
        case "codex": return "GPT"
        case "claude": return "Claude"
        case "grok": return "Grok"
        case "cursor": return "Cursor"
        case "gemini": return "Gemini"
        case "deepseek": return "DeepSeek"
        case "minimax": return "MiniMax"
        case "antigravity": return "Antigravity"
        default: return "AI"
        }
    }
}

/// A plugin-owned renderer. It uses no BTT configuration, Apple Event, or
/// TraceFence menu-bar controller. The persistent Control Strip button is the
/// entry point; the full dashboard is a system-modal Touch Bar shown only
/// while the user wants to inspect it.
@MainActor
private final class NativeQuotaTouchBarRenderer: NSObject, NSTouchBarDelegate {
    private enum ItemID {
        static let content = NSTouchBarItem.Identifier("com.tracefence.plugin.quota-monitor.leading-content")
        static let controlStrip = NSTouchBarItem.Identifier("com.tracefence.plugin.quota-monitor.control-strip")
    }

    private enum RendererError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return "此 Mac 未提供可用的原生 Touch Bar 主显示区。"
            }
        }
    }

    private var touchBar: NSTouchBar?
    private var contentItem: NSCustomTouchBarItem?
    private var controlStripItem: NSCustomTouchBarItem?
    private var controlStripButton: NSButton?
    private var view: QuotaControlStripView?
    private var onControlStripToggle: (() -> Void)?
    private var isControlStripRegistered = false
    private var isPresented = false

    func show(
        _ state: QuotaTouchBarDisplay.State,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onAutomatic: @escaping () -> Void,
        onControlStripToggle: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) throws {
        if touchBar == nil { try register() }
        self.onControlStripToggle = onControlStripToggle
        updateControlStripButton(with: state)
        view?.update(
            state: state,
            onPrevious: onPrevious,
            onNext: onNext,
            onAutomatic: onAutomatic,
            onClose: onClose
        )
        guard let touchBar else { throw RendererError.unavailable }
        if !isPresented {
            guard Self.presentSystemModalTouchBar(
                touchBar,
                systemTrayItemIdentifier: ItemID.controlStrip
            ) else {
                throw RendererError.unavailable
            }
            isPresented = true
        }
    }

    func hide() {
        if isPresented, let touchBar {
            Self.dismissSystemModalTouchBar(touchBar)
        }
        isPresented = false
    }

    func tearDown() {
        hide()
        if isControlStripRegistered, let controlStripItem {
            Self.setControlStripPresence(for: ItemID.controlStrip, present: false)
            Self.removeSystemTrayItem(controlStripItem)
        }
        isControlStripRegistered = false
        touchBar = nil
        contentItem = nil
        controlStripItem = nil
        controlStripButton = nil
        view = nil
        onControlStripToggle = nil
    }

    private func register() throws {
        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = NSTouchBar.CustomizationIdentifier(
            "com.tracefence.plugin.quota-monitor.leading"
        )
        // This is a full dashboard, not a small card followed by empty space.
        // System-modal presentation temporarily replaces the active app's
        // main Touch Bar; the separate Control Strip button remains available.
        bar.defaultItemIdentifiers = [ItemID.content]
        bar.customizationAllowedItemIdentifiers = [ItemID.content]

        let item = NSCustomTouchBarItem(identifier: ItemID.content)
        let surface = QuotaControlStripView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 30))
        item.view = surface

        let button = NSButton(
            image: NSImage(
                systemSymbolName: "gauge.medium",
                accessibilityDescription: "额度监控"
            ) ?? NSImage(),
            target: self,
            action: #selector(controlStripPressed)
        )
        button.bezelStyle = .rounded
        button.imagePosition = .imageOnly
        button.focusRingType = .none
        button.toolTip = "显示额度监控"
        button.setAccessibilityLabel("显示额度监控")

        let controlStripItem = NSCustomTouchBarItem(identifier: ItemID.controlStrip)
        controlStripItem.view = button
        guard Self.addSystemTrayItem(controlStripItem),
              Self.setControlStripPresence(for: ItemID.controlStrip, present: true)
        else {
            Self.removeSystemTrayItem(controlStripItem)
            throw RendererError.unavailable
        }

        touchBar = bar
        contentItem = item
        self.controlStripItem = controlStripItem
        controlStripButton = button
        view = surface
        isControlStripRegistered = true
    }

    func touchBar(
        _ touchBar: NSTouchBar,
        makeItemForIdentifier identifier: NSTouchBarItem.Identifier
    ) -> NSTouchBarItem? {
        guard identifier == ItemID.content else { return nil }
        return contentItem
    }

    private static func addSystemTrayItem(_ item: NSTouchBarItem) -> Bool {
        let selector = NSSelectorFromString("addSystemTrayItem:")
        guard let method = class_getClassMethod(NSTouchBarItem.self, selector) else { return false }
        typealias Function = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        function(NSTouchBarItem.self, selector, item)
        return true
    }

    private static func removeSystemTrayItem(_ item: NSTouchBarItem) {
        let selector = NSSelectorFromString("removeSystemTrayItem:")
        guard let method = class_getClassMethod(NSTouchBarItem.self, selector) else { return }
        typealias Function = @convention(c) (AnyClass, Selector, NSTouchBarItem) -> Void
        let function = unsafeBitCast(method_getImplementation(method), to: Function.self)
        function(NSTouchBarItem.self, selector, item)
    }

    private static func setControlStripPresence(
        for identifier: NSTouchBarItem.Identifier,
        present: Bool
    ) -> Bool {
        let framework = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
        guard let handle = dlopen(framework, RTLD_LAZY | RTLD_LOCAL) else { return false }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else {
            return false
        }
        typealias SetPresence = @convention(c) (NSString, Int8) -> Void
        let setPresence = unsafeBitCast(symbol, to: SetPresence.self)
        setPresence(identifier.rawValue as NSString, present ? 1 : 0)
        return true
    }

    private static func presentSystemModalTouchBar(
        _ touchBar: NSTouchBar,
        systemTrayItemIdentifier identifier: NSTouchBarItem.Identifier
    ) -> Bool {
        configureSystemModalCloseBox()
        let selector = NSSelectorFromString("presentSystemModalTouchBar:placement:systemTrayItemIdentifier:")
        guard let method = class_getClassMethod(NSTouchBar.self, selector) else { return false }
        typealias PresentFunction = @convention(c) (
            AnyClass,
            Selector,
            NSTouchBar,
            Int64,
            NSString?
        ) -> Void
        let present = unsafeBitCast(method_getImplementation(method), to: PresentFunction.self)
        // `1` is the leading system-modal placement used by the former working
        // implementation. The content order above keeps our item on the left.
        present(NSTouchBar.self, selector, touchBar, 1, identifier.rawValue as NSString)
        return true
    }

    private static func dismissSystemModalTouchBar(_ touchBar: NSTouchBar) {
        let selector = NSSelectorFromString("dismissSystemModalTouchBar:")
        let touchBarClass: AnyObject = NSTouchBar.self
        guard touchBarClass.responds(to: selector) else { return }
        _ = touchBarClass.perform(selector, with: touchBar)
    }

    private static func configureSystemModalCloseBox() {
        let framework = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
        guard let handle = dlopen(framework, RTLD_LAZY | RTLD_LOCAL) else { return }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        typealias ConfigureCloseBox = @convention(c) (Int8) -> Void
        let configure = unsafeBitCast(symbol, to: ConfigureCloseBox.self)
        // The plugin owns the visible × control. Suppressing the system one
        // avoids the macOS 26 zero-width layout failure.
        configure(0)
    }

    private func updateControlStripButton(with state: QuotaTouchBarDisplay.State) {
        guard let controlStripButton else { return }
        let lowest = [state.fiveHourRemaining, state.weeklyRemaining]
            .compactMap { $0 }
            .min()
        controlStripButton.contentTintColor = QuotaTouchBarDisplay.meterColor(for: lowest)
        let label: String
        if state.isUnavailable {
            label = "显示额度监控"
        } else {
            let fiveHour = state.fiveHourRemaining.map(String.init) ?? "—"
            let weekly = state.weeklyRemaining.map(String.init) ?? "—"
            label = "显示 " + state.providerName + " 额度：5 小时 " + fiveHour + "% ，周额度 " + weekly + "%"
        }
        controlStripButton.toolTip = label
        controlStripButton.setAccessibilityLabel(label)
    }

    @objc private func controlStripPressed() {
        onControlStripToggle?()
    }
}

@MainActor
private final class QuotaControlStripView: NSView {
    private var state = QuotaTouchBarDisplay.State.unavailable()
    private var onPrevious: (() -> Void)?
    private var onNext: (() -> Void)?
    private var onAutomatic: (() -> Void)?
    private var onClose: (() -> Void)?
    private let previousButton = NSButton(title: "‹", target: nil, action: nil)
    private let nextButton = NSButton(title: "›", target: nil, action: nil)
    private let automaticButton = NSButton(title: "自动", target: nil, action: nil)
    private let closeButton = NSButton(title: "×", target: nil, action: nil)

    override var intrinsicContentSize: NSSize {
        NSSize(width: 1_000, height: 30)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.group)
        configure(button: previousButton, action: #selector(previousPressed))
        configure(button: nextButton, action: #selector(nextPressed))
        configure(button: automaticButton, action: #selector(automaticPressed))
        configure(button: closeButton, action: #selector(closePressed))
        previousButton.toolTip = "上一个 Agent"
        nextButton.toolTip = "下一个 Agent"
        automaticButton.toolTip = "恢复自动跟随"
        closeButton.toolTip = "关闭额度仪表盘并恢复默认 Touch Bar"
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        state: QuotaTouchBarDisplay.State,
        onPrevious: @escaping () -> Void,
        onNext: @escaping () -> Void,
        onAutomatic: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.state = state
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onAutomatic = onAutomatic
        self.onClose = onClose
        automaticButton.contentTintColor = state.isAutomatic ? .systemBlue : .secondaryLabelColor
        automaticButton.font = NSFont.systemFont(ofSize: 11, weight: state.isAutomatic ? .semibold : .regular)
        setAccessibilityLabel("\(state.summary)。‹/› 切换，自动恢复跟随，× 关闭。")
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let width = max(bounds.width, intrinsicContentSize.width)
        previousButton.frame = NSRect(x: 6, y: 2, width: 30, height: 26)
        nextButton.frame = NSRect(x: 148, y: 2, width: 30, height: 26)
        automaticButton.frame = NSRect(x: 184, y: 3, width: 62, height: 24)
        closeButton.frame = NSRect(x: width - 38, y: 2, width: 32, height: 26)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dashboard = bounds.insetBy(dx: 2, dy: 2)
        NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
        NSBezierPath(roundedRect: dashboard, xRadius: 7, yRadius: 7).fill()

        drawText(state.providerName, in: NSRect(x: 40, y: 7, width: 104, height: 18), color: .white, size: 13, weight: .bold)
        drawText(state.isAutomatic ? "跟随中" : "手动", in: NSRect(x: 250, y: 8, width: 42, height: 16), color: state.isAutomatic ? .systemBlue : .secondaryLabelColor, size: 9, weight: .medium)

        let availableWidth = max(420, bounds.width - 308)
        let gaugeWidth = floor((availableWidth - 16) / 2)
        drawGauge(label: "5 小时", remaining: state.fiveHourRemaining, rect: NSRect(x: 300, y: 3, width: gaugeWidth, height: 24))
        drawGauge(label: "周额度", remaining: state.weeklyRemaining, rect: NSRect(x: 316 + gaugeWidth, y: 3, width: gaugeWidth, height: 24))
    }

    private func configure(button: NSButton, action: Selector) {
        button.target = self
        button.action = action
        button.isBordered = false
        button.bezelStyle = .inline
        button.focusRingType = .none
        button.font = NSFont.systemFont(ofSize: 17, weight: .medium)
        button.contentTintColor = .white
        button.setButtonType(.momentaryPushIn)
        addSubview(button)
    }

    @objc private func previousPressed() { onPrevious?() }
    @objc private func nextPressed() { onNext?() }
    @objc private func automaticPressed() { onAutomatic?() }
    @objc private func closePressed() { onClose?() }

    private func drawGauge(label: String, remaining: Int?, rect: NSRect) {
        let labelWidth: CGFloat = 46
        let valueWidth: CGFloat = 42
        let track = NSRect(
            x: rect.minX + labelWidth + 8,
            y: rect.minY + 8,
            width: max(72, rect.width - labelWidth - valueWidth - 16),
            height: 9
        )
        drawText(label, in: NSRect(x: rect.minX, y: rect.minY + 6, width: labelWidth, height: 15), color: .secondaryLabelColor, size: 10, weight: .medium)
        NSColor(calibratedWhite: 0.26, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 4.5, yRadius: 4.5).fill()
        if let remaining {
            let ratio = min(1, max(0, CGFloat(remaining) / 100))
            let fill = NSRect(x: track.minX, y: track.minY, width: max(4, track.width * ratio), height: track.height)
            QuotaTouchBarDisplay.meterColor(for: remaining).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 4.5, yRadius: 4.5).fill()
        }
        let value = remaining.map { "\($0)%" } ?? "—"
        drawText(value, in: NSRect(x: track.maxX + 5, y: rect.minY + 6, width: valueWidth - 5, height: 15), color: .white, size: 11, weight: .semibold)
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        color: NSColor,
        size: CGFloat,
        weight: NSFont.Weight = .regular
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byClipping
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }
}

/// A one-time migration hook for controls created by plugin versions up to
/// 1.0.8. It knows only UUIDs that this plugin persisted itself, validates the
/// UUID syntax before acting, and never reads or alters any other BTT rule.
private enum LegacyBetterTouchToolWidgetCleanup {
    private struct State: Decodable {
        let schemaVersion: Int
        let previousUUID: String?
        let displayUUID: String?
        let nextUUID: String?

        var ownedUUIDs: [String] {
            [previousUUID, displayUUID, nextUUID].compactMap { value in
                guard let value, UUID(uuidString: value) != nil else { return nil }
                return value
            }
        }
    }

    private enum CleanupError: LocalizedError {
        case automationUnavailable

        var errorDescription: String? {
            switch self {
            case .automationUnavailable:
                return "无法清理旧版 BetterTouchTool 控件。请启动 BetterTouchTool，并在系统设置中允许 TraceFence 自动化后重试。"
            }
        }
    }

    private static let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TraceFence/TouchBar/quota-touch-bar-btt-state.json")

    static var hasOwnedWidgetState: Bool { !(loadState()?.ownedUUIDs.isEmpty ?? true) }

    static func removeOwnedWidgets() throws {
        guard let state = loadState(), !state.ownedUUIDs.isEmpty else { return }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.hegenberg.BetterTouchTool") != nil else {
            try? FileManager.default.removeItem(at: stateURL)
            return
        }
        for uuid in state.ownedUUIDs {
            guard runDelete(uuid: uuid) else { throw CleanupError.automationUnavailable }
        }
        try? FileManager.default.removeItem(at: stateURL)
    }

    static func removeOwnedWidgetsIfPossible() {
        try? removeOwnedWidgets()
    }

    private static func loadState() -> State? {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(State.self, from: data),
              state.schemaVersion == 1
        else {
            return nil
        }
        return state
    }

    private static func runDelete(uuid: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = [
            "-l", "AppleScript",
            "-e", "on run argv\n tell application id \\\"com.hegenberg.BetterTouchTool\\\" to delete_trigger (item 1 of argv)\nend run",
            uuid
        ]
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
