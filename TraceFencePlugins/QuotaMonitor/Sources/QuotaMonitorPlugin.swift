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
    private let touchBarController: QuotaTouchBarController
    private var serviceChangeCancellable: AnyCancellable?
    private var isExpanded = false

    fileprivate init(engineURL: URL?, localization: PluginLocalization) {
        self.service = ProviderQuotaService(
            providerEngineURL: engineURL,
            requiresExplicitProviderEngine: true
        )
        self.localization = localization
        self.touchBarController = QuotaTouchBarController(localization: localization)
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
        touchBarController.refreshLocalization()
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

    private let localization: PluginLocalization
    private let renderer: NativeQuotaTouchBarRenderer
    private var snapshots: [ProviderQuotaSnapshot] = []
    private var selection: Selection = .automatic
    private var selectedProviderID: String?
    private var selectedMetricIndexByProviderID: [String: Int] = [:]
    private var workspaceObservers: [NSObjectProtocol] = []
    private var isActive = false

    private(set) var isUpdating = false
    private(set) var errorMessage: String?
    var onStateChange: (() -> Void)?

    init(localization: PluginLocalization) {
        self.localization = localization
        self.renderer = NativeQuotaTouchBarRenderer(localization: localization)
    }

    var isVisible: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Preference.visibleKey) == nil {
            defaults.set(true, forKey: Preference.visibleKey)
            return true
        }
        return defaults.bool(forKey: Preference.visibleKey)
    }

    var hasQuotaProviders: Bool { !QuotaTouchBarDisplay.items(from: snapshots, localization: localization).isEmpty }
    var hasLegacyBetterTouchToolWidgets: Bool { LegacyBetterTouchToolWidgetCleanup.hasOwnedWidgetState }
    var panelSummary: String? {
        guard hasQuotaProviders else { return nil }
        return displayState().summary(localization: localization)
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

    func refreshLocalization() {
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

    private func cycleMetric() {
        let state = displayState()
        guard !state.isUnavailable, state.metricCount > 1 else { return }
        selectedMetricIndexByProviderID[state.providerID] = (state.selectedMetricIndex + 1) % state.metricCount
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
        guard workspaceObservers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshDisplay() }
        })
        // TouchBarServer / ControlStrip can be relaunched independently of the
        // host. Reassert our plugin-owned entry without reopening the dashboard.
        workspaceObservers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == "com.apple.controlstrip" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                Task { @MainActor in self?.renderer.reassertControlStripPresence() }
            }
        })
        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            workspaceObservers.append(center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    Task { @MainActor in self?.renderer.reassertControlStripPresence() }
                }
            })
        }
    }

    private func stopObserving() {
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
    }

    private func cycleProvider(offset: Int) {
        let items = QuotaTouchBarDisplay.items(from: snapshots, localization: localization)
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
        guard isActive else { return }

        // Register the Control Strip entry even while the dashboard is hidden.
        // Otherwise a close followed by a host restart would leave no native way
        // to open the quota display again.
        do {
            try renderer.prepareControlStrip(
                display,
                onControlStripToggle: { [weak self] in self?.toggleVisibility() }
            )
        } catch {
            errorMessage = error.localizedDescription
            onStateChange?()
            return
        }

        guard isVisible else {
            renderer.hide()
            onStateChange?()
            return
        }

        do {
            try renderer.show(
                display,
                onProviderCycle: { [weak self] in self?.selectNextProvider() },
                onMetricCycle: { [weak self] in self?.cycleMetric() },
                onAutomatic: { [weak self] in self?.resumeAutomaticSelection() },
                onHide: { [weak self] in
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
        let items = QuotaTouchBarDisplay.items(from: snapshots, localization: localization)
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
        let savedIndex = selectedMetricIndexByProviderID[resolved.id] ?? 0
        let metricIndex = min(max(0, savedIndex), max(0, resolved.metrics.count - 1))
        selectedMetricIndexByProviderID[resolved.id] = metricIndex
        return .quota(item: resolved, metricIndex: metricIndex, isAutomatic: isAutomaticSelection)
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
    struct Metric: Equatable {
        let id: String
        let title: String
        let remaining: Int
        let sortOrder: Int
    }

    struct Item: Equatable {
        let id: String
        let providerKey: String
        let providerName: String
        let metrics: [Metric]
        let lowestRemaining: Int
    }

    struct State: Equatable {
        let providerID: String
        let providerName: String
        let metrics: [Metric]
        let selectedMetricIndex: Int
        let isAutomatic: Bool
        let isUnavailable: Bool

        var currentMetric: Metric? {
            guard metrics.indices.contains(selectedMetricIndex) else { return nil }
            return metrics[selectedMetricIndex]
        }

        var metricCount: Int { metrics.count }
        var metricPageText: String { "\(selectedMetricIndex + 1)/\(max(1, metricCount))" }
        var lowestRemaining: Int? { metrics.map(\.remaining).min() }

        func summary(localization: PluginLocalization) -> String {
            guard !isUnavailable else {
                return localization.string("touchbar.unavailable", defaultValue: "No quota data")
            }
            let mode = localization.string(
                isAutomatic ? "touchbar.mode.automatic" : "touchbar.mode.manual",
                defaultValue: isAutomatic ? "Automatic follow" : "Manual lock"
            )
            if let metric = currentMetric {
                return localization.format(
                    "touchbar.summary.metric",
                    defaultValue: "%@ · %@ %lld%% · %@ · %@",
                    providerName,
                    metric.title,
                    Int64(metric.remaining),
                    metricPageText,
                    mode
                )
            }
            return localization.format(
                "touchbar.summary.provider",
                defaultValue: "%@ · %@",
                providerName,
                mode
            )
        }

        static func unavailable() -> State {
            State(
                providerID: "",
                providerName: "Quota",
                metrics: [],
                selectedMetricIndex: 0,
                isAutomatic: true,
                isUnavailable: true
            )
        }

        static func quota(item: Item, metricIndex: Int, isAutomatic: Bool) -> State {
            State(
                providerID: item.id,
                providerName: item.providerName,
                metrics: item.metrics,
                selectedMetricIndex: metricIndex,
                isAutomatic: isAutomatic,
                isUnavailable: false
            )
        }
    }

    static func items(from snapshots: [ProviderQuotaSnapshot], localization: PluginLocalization) -> [Item] {
        snapshots.compactMap { snapshot in
            guard !snapshot.isSetupNotice else { return nil }
            let metrics = makeMetrics(from: snapshot.windows, localization: localization)
            guard !metrics.isEmpty else { return nil }
            let key = providerKey(for: snapshot.providerName)
            return Item(
                id: snapshot.id,
                providerKey: key,
                providerName: sanitizedProviderName(key),
                metrics: metrics,
                lowestRemaining: metrics.map(\.remaining).min() ?? 0
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

    private static func makeMetrics(
        from windows: [ProviderQuotaWindow],
        localization: PluginLocalization
    ) -> [Metric] {
        // Keep the Provider's real window name intact. If several windows share
        // the same kind, the page counter differentiates them; adding “2/3” to
        // labels corrupts names such as “周额度”.
        windows
            .map { window in
                Metric(
                    id: window.id,
                    title: metricTitle(for: window, localization: localization),
                    remaining: Int(window.remainingPercent.rounded()),
                    sortOrder: metricSortOrder(for: window.kind)
                )
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.id < rhs.id
            }
    }

    private static func metricTitle(
        for window: ProviderQuotaWindow,
        localization: PluginLocalization
    ) -> String {
        // The source already supplies names such as “Current week (Opus)” and
        // distinct five-hour windows. Use that exact title so Touch Bar pages
        // match the detailed quota popup instead of flattening all of them to
        // the generic “5小时额度”.
        let providerTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !providerTitle.isEmpty { return providerTitle }

        // Fallbacks apply only to malformed/legacy payloads with no title.
        switch window.kind {
        case .fiveHour:
            return localization.string("touchbar.metric.fiveHour", defaultValue: "5-hour quota")
        case .weekly:
            return localization.string("touchbar.metric.weekly", defaultValue: "Weekly quota")
        case .monthly:
            return localization.string("touchbar.metric.monthly", defaultValue: "Monthly quota")
        case .extra:
            return localization.string("touchbar.metric.extra", defaultValue: "Additional quota")
        }
    }

    private static func metricSortOrder(for kind: ProviderQuotaWindow.Kind) -> Int {
        switch kind {
        case .fiveHour: return 0
        case .weekly: return 1
        case .monthly: return 2
        case .extra: return 3
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
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case let .unavailable(message):
                return message
            }
        }
    }

    private var touchBar: NSTouchBar?
    private let localization: PluginLocalization
    private var contentItem: NSCustomTouchBarItem?
    private var controlStripItem: NSCustomTouchBarItem?
    private var controlStripButton: NSButton?
    private var view: QuotaControlStripView?
    private var onControlStripToggle: (() -> Void)?
    private var isControlStripRegistered = false
    private var isPresented = false

    init(localization: PluginLocalization) {
        self.localization = localization
        super.init()
    }

    func prepareControlStrip(
        _ state: QuotaTouchBarDisplay.State,
        onControlStripToggle: @escaping () -> Void
    ) throws {
        if touchBar == nil { try register() }
        self.onControlStripToggle = onControlStripToggle
        reassertControlStripPresence()
        updateControlStripButton(with: state)
    }

    /// Keep the launcher in the system Control Strip after the dashboard is
    /// dismissed. This is a separate surface from the system-modal dashboard.
    func reassertControlStripPresence() {
        guard isControlStripRegistered else { return }
        _ = Self.setControlStripPresence(for: ItemID.controlStrip, present: true)
    }

    func show(
        _ state: QuotaTouchBarDisplay.State,
        onProviderCycle: @escaping () -> Void,
        onMetricCycle: @escaping () -> Void,
        onAutomatic: @escaping () -> Void,
        onHide: @escaping () -> Void
    ) throws {
        view?.update(
            state: state,
            onProviderCycle: onProviderCycle,
            onMetricCycle: onMetricCycle,
            onAutomatic: onAutomatic,
            onHide: onHide
        )
        guard let touchBar else { throw unavailableError() }
        if !isPresented {
            guard Self.presentSystemModalTouchBar(
                touchBar,
                systemTrayItemIdentifier: ItemID.controlStrip
            ) else {
                throw unavailableError()
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
            _ = Self.setControlStripPresence(for: ItemID.controlStrip, present: false)
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
        bar.defaultItemIdentifiers = [ItemID.content]
        bar.customizationAllowedItemIdentifiers = [ItemID.content]

        let item = NSCustomTouchBarItem(identifier: ItemID.content)
        // Reserve a compact leading region. The right-side system Control Strip
        // stays macOS-owned instead of being painted over by this plugin.
        let surface = QuotaControlStripView(
            frame: NSRect(x: 0, y: 0, width: 680, height: 30),
            localization: localization
        )
        item.view = surface

        let openTitle = t("touchbar.controlStrip.open", "Open AI quota monitor")
        let image = NSImage(
            systemSymbolName: "sparkles",
            accessibilityDescription: openTitle
        )?.withSymbolConfiguration(.init(pointSize: 15, weight: .semibold)) ?? NSImage()
        image.isTemplate = true
        let button = NSButton(image: image, target: self, action: #selector(controlStripPressed))
        button.bezelStyle = .rounded
        button.imagePosition = .imageOnly
        button.focusRingType = .none
        // A Control Strip item needs an explicit non-zero surface. An intrinsic
        // NSButton-only view can be registered yet stay invisible after the
        // system-modal dashboard has been dismissed.
        button.translatesAutoresizingMaskIntoConstraints = true
        button.frame = NSRect(x: 0, y: 0, width: 42, height: 30)
        button.toolTip = openTitle
        button.setAccessibilityLabel(openTitle)

        let controlStripItem = NSCustomTouchBarItem(identifier: ItemID.controlStrip)
        controlStripItem.customizationLabel = t("touchbar.controlStrip.label", "Quota Monitor")
        controlStripItem.view = button
        guard Self.addSystemTrayItem(controlStripItem),
              Self.setControlStripPresence(for: ItemID.controlStrip, present: true)
        else {
            Self.removeSystemTrayItem(controlStripItem)
            throw unavailableError()
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
        // `1` is the leading system-modal placement. Keeping our custom item
        // narrow makes room for the native Control Strip at the right edge.
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
        controlStripButton.contentTintColor = QuotaTouchBarDisplay.meterColor(for: state.lowestRemaining)
        let label: String
        if state.isUnavailable {
            label = t("touchbar.controlStrip.open", "Open AI quota monitor")
        } else {
            let metrics = state.metrics
                .map { "\($0.title) \($0.remaining)%" }
                .joined(separator: "，")
            label = localization.format(
                "touchbar.controlStrip.openProviderFormat",
                defaultValue: "Open %@ AI quota monitor: %@",
                state.providerName,
                metrics
            )
        }
        controlStripButton.toolTip = label
        controlStripButton.setAccessibilityLabel(label)
    }

    @objc private func controlStripPressed() {
        onControlStripToggle?()
    }

    private func t(_ key: String, _ defaultValue: String) -> String {
        localization.string(key, defaultValue: defaultValue)
    }

    private func unavailableError() -> RendererError {
        .unavailable(t(
            "touchbar.error.unavailable",
            "This Mac does not provide a native Touch Bar main area."
        ))
    }
}

@MainActor
private final class QuotaControlStripView: NSView {
    private let localization: PluginLocalization
    private var state = QuotaTouchBarDisplay.State.unavailable()
    private var onProviderCycle: (() -> Void)?
    private var onMetricCycle: (() -> Void)?
    private var onAutomatic: (() -> Void)?
    private var onHide: (() -> Void)?

    // These are SF Symbols with direct semantics: cycle Agent, follow/lock
    // selection, advance quota window, and close the dashboard. We deliberately
    // do not substitute unofficial Provider logos for the actual product name.
    private let providerCycleButton = NSButton(title: "", target: nil, action: nil)
    private let modeButton = NSButton(title: "", target: nil, action: nil)
    private let metricCycleButton = NSButton(title: "", target: nil, action: nil)
    private let hideButton = NSButton(title: "", target: nil, action: nil)

    override var intrinsicContentSize: NSSize {
        NSSize(width: 680, height: 30)
    }

    init(frame frameRect: NSRect, localization: PluginLocalization) {
        self.localization = localization
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityRole(.group)
        configure(button: providerCycleButton, action: #selector(providerCyclePressed), fontSize: 13)
        configure(button: modeButton, action: #selector(modePressed), fontSize: 11)
        configure(button: metricCycleButton, action: #selector(metricCyclePressed), fontSize: 11)
        configure(button: hideButton, action: #selector(hidePressed), fontSize: 11)

        providerCycleButton.toolTip = t("touchbar.providerCycle.tooltip", "Cycle to the next Agent and lock its display")
        hideButton.toolTip = t("touchbar.hide.tooltip", "Hide quota display and restore the default Touch Bar; reopen it from the AI icon")
        hideButton.setAccessibilityLabel(t("touchbar.hide", "Hide quota display"))
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        state: QuotaTouchBarDisplay.State,
        onProviderCycle: @escaping () -> Void,
        onMetricCycle: @escaping () -> Void,
        onAutomatic: @escaping () -> Void,
        onHide: @escaping () -> Void
    ) {
        self.state = state
        self.onProviderCycle = onProviderCycle
        self.onMetricCycle = onMetricCycle
        self.onAutomatic = onAutomatic
        self.onHide = onHide

        let providerImage = NSImage(
            systemSymbolName: "arrow.triangle.2.circlepath",
            accessibilityDescription: t("touchbar.providerCycle.accessibility", "Cycle Agent")
        )
        providerImage?.isTemplate = true
        providerCycleButton.image = providerImage
        providerCycleButton.imagePosition = .imageOnly
        providerCycleButton.contentTintColor = .secondaryLabelColor
        providerCycleButton.setAccessibilityLabel(localization.format(
            "touchbar.providerCycle.accessibilityFormat",
            defaultValue: "Cycle Agent; currently %@",
            state.providerName
        ))

        let localizedModeTitle = modeTitle
        let modeImage = NSImage(
            systemSymbolName: state.isAutomatic ? "scope" : "pin.fill",
            accessibilityDescription: localizedModeTitle
        )
        modeImage?.isTemplate = true
        modeButton.image = modeImage
        modeButton.title = localizedModeTitle
        modeButton.imagePosition = .imageLeading
        modeButton.contentTintColor = state.isAutomatic ? .secondaryLabelColor : .systemOrange
        modeButton.isEnabled = !state.isAutomatic
        modeButton.toolTip = state.isAutomatic
            ? t("touchbar.mode.automatic.tooltip", "Following the active Agent; use the cycle icon to inspect another Agent")
            : t("touchbar.mode.manual.tooltip", "Select to resume following the active Agent")
        modeButton.setAccessibilityLabel(modeButton.toolTip ?? modeButton.title)

        metricCycleButton.isHidden = state.metricCount <= 1
        metricCycleButton.title = "\(state.metricPageText) ›"
        metricCycleButton.toolTip = t("touchbar.metricCycle.tooltip", "Show next quota window; loops back after the last")
        metricCycleButton.setAccessibilityLabel(metricCycleButton.toolTip ?? t("touchbar.metricCycle.accessibility", "Show next quota window"))

        let hideTitle = t("touchbar.hide", "Hide quota display")
        let hideImage = NSImage(
            systemSymbolName: "eye.slash",
            accessibilityDescription: hideTitle
        )?.withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        hideImage?.isTemplate = true
        hideButton.image = hideImage
        hideButton.title = ""
        hideButton.imagePosition = .imageOnly
        setAccessibilityLabel(localization.format(
            "touchbar.group.accessibilityFormat",
            defaultValue: "%@. %@ %@ %@",
            state.summary(localization: localization),
            t("touchbar.providerCycle.tooltip", "Cycle to the next Agent and lock its display"),
            state.metricCount > 1 ? t("touchbar.metricCycle.tooltip", "Show next quota window; loops back after the last") : "",
            t("touchbar.hide.tooltip", "Hide quota display and restore the default Touch Bar; reopen it from the AI icon")
        ))

        needsLayout = true
        needsDisplay = true
    }

    private var providerNameWidth: CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        let measured = ceil((state.providerName as NSString).size(withAttributes: [.font: font]).width) + 4
        return min(98, max(30, measured))
    }

    private var modeTitle: String {
        t(
            state.isAutomatic ? "touchbar.mode.automatic" : "touchbar.mode.manual",
            state.isAutomatic ? "Automatic follow" : "Manual lock"
        )
    }

    private var modeButtonWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: 11, weight: .medium)
        let textWidth = ceil((modeTitle as NSString).size(withAttributes: [.font: font]).width)
        // Include the leading SF Symbol plus the image/title gap. This must use
        // the localized title, not a Chinese-sized constant: “Automatic follow”
        // and German/Arabic strings need more room than “自动跟随”.
        return min(132, max(76, textWidth + 27))
    }

    private var modeButtonX: CGFloat { 38 + providerNameWidth + 4 }
    private var dividerX: CGFloat { modeButtonX + modeButtonWidth + 6 }
    private var metricX: CGFloat { dividerX + 10 }

    override func layout() {
        super.layout()
        let width = bounds.width
        providerCycleButton.frame = NSRect(x: 4, y: 2, width: 30, height: 26)
        // The mode sits immediately after the actual Provider name width, not
        // after a fixed empty badge. GPT therefore does not get Claude-sized
        // whitespace before “手动锁定”.
        modeButton.frame = NSRect(x: modeButtonX, y: 3, width: modeButtonWidth, height: 24)
        hideButton.frame = NSRect(x: width - 27, y: 4, width: 22, height: 22)
        if state.metricCount > 1 {
            metricCycleButton.frame = NSRect(x: width - 92, y: 3, width: 52, height: 24)
        } else {
            metricCycleButton.frame = .zero
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let width = bounds.width
        let textColor = NSColor.labelColor
        let secondary = NSColor.secondaryLabelColor

        drawText(
            state.providerName,
            in: NSRect(x: 38, y: 0, width: providerNameWidth, height: bounds.height),
            color: textColor,
            size: 12,
            weight: .semibold,
            alignment: .natural
        )
        drawDivider(at: dividerX)

        let metricRight = state.metricCount > 1 ? width - 100 : width - 34
        if let metric = state.currentMetric {
            drawGauge(
                metric,
                in: NSRect(x: metricX, y: 3, width: max(150, metricRight - metricX), height: 24),
                secondary: secondary
            )
        } else {
            drawText(
                t("touchbar.unavailable", "No quota data"),
                in: NSRect(x: metricX, y: 0, width: 180, height: bounds.height),
                color: secondary,
                size: 11
            )
        }
    }

    private func configure(button: NSButton, action: Selector, fontSize: CGFloat) {
        button.target = self
        button.action = action
        button.isBordered = false
        button.bezelStyle = .inline
        button.focusRingType = .none
        button.font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        button.contentTintColor = .labelColor
        button.setButtonType(.momentaryPushIn)
        addSubview(button)
    }

    @objc private func providerCyclePressed() { onProviderCycle?() }
    @objc private func modePressed() { onAutomatic?() }
    @objc private func metricCyclePressed() { onMetricCycle?() }
    @objc private func hidePressed() { onHide?() }

    private func drawDivider(at x: CGFloat) {
        NSColor.separatorColor.withAlphaComponent(0.48).setFill()
        NSBezierPath(rect: NSRect(x: x, y: 7, width: 1, height: 16)).fill()
    }

    private func drawGauge(_ metric: QuotaTouchBarDisplay.Metric, in rect: NSRect, secondary: NSColor) {
        let valueWidth: CGFloat = 42
        let labelWidth = metricTitleWidth(
            for: metric.title,
            availableMetricWidth: rect.width,
            valueWidth: valueWidth
        )
        let track = NSRect(
            x: rect.minX + labelWidth + 8,
            y: rect.midY - 4,
            width: max(70, rect.width - labelWidth - valueWidth - 16),
            height: 8
        )
        // Window titles remain real names. Short titles use a larger single line;
        // only titles that need it become smaller and wrap automatically.
        drawMetricTitle(
            metric.title,
            in: NSRect(x: rect.minX, y: rect.minY, width: labelWidth, height: rect.height),
            color: secondary
        )
        NSColor(calibratedWhite: 0.25, alpha: 1).setFill()
        NSBezierPath(roundedRect: track, xRadius: 4, yRadius: 4).fill()
        let ratio = min(1, max(0, CGFloat(metric.remaining) / 100))
        if ratio > 0 {
            let fill = NSRect(x: track.minX, y: track.minY, width: track.width * ratio, height: track.height)
            QuotaTouchBarDisplay.meterColor(for: metric.remaining).setFill()
            NSBezierPath(roundedRect: fill, xRadius: 4, yRadius: 4).fill()
        }
        drawText(
            "\(metric.remaining)%",
            in: NSRect(x: track.maxX + 5, y: rect.minY, width: valueWidth - 5, height: rect.height),
            color: .labelColor,
            size: 11,
            weight: .semibold,
            alignment: .right
        )
    }

    private func metricTitleWidth(
        for text: String,
        availableMetricWidth: CGFloat,
        valueWidth: CGFloat
    ) -> CGFloat {
        let minimumWidth: CGFloat = 78
        // Preserve at least a 70pt meter. A longer Provider-supplied title can
        // use more of the spacious left label area, but never consumes the bar.
        let maximumWidth = max(
            minimumWidth,
            min(116, availableMetricWidth - valueWidth - 16 - 70)
        )
        let preferredFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let preferredWidth = ceil((text as NSString).size(withAttributes: [.font: preferredFont]).width)
        // Reserve enough room for up to two natural lines at the preferred size.
        return min(maximumWidth, max(minimumWidth, ceil(preferredWidth / 2)))
    }

    private func drawMetricTitle(_ text: String, in rect: NSRect, color: NSColor) {
        let preferredFont = NSFont.systemFont(ofSize: 12, weight: .medium)
        let preferredWidth = ceil((text as NSString).size(withAttributes: [.font: preferredFont]).width)
        let preferredLineHeight = lineHeight(for: preferredFont)

        // The normal state is one 12pt line, vertically centered. No manual
        // newline is introduced and no tail ellipsis is used for quota names.
        if preferredWidth <= rect.width {
            drawMetricTitle(
                text,
                font: preferredFont,
                lineBreakMode: .byClipping,
                in: centeredRect(width: rect.width, height: preferredLineHeight, within: rect),
                color: color
            )
            return
        }

        // Only when the preferred title does not fit: reduce the type gradually
        // and let AppKit wrap at natural character/word boundaries. The first
        // size whose complete measured text fits wins, so it remains centered.
        for pointSize: CGFloat in stride(from: 11, through: 8, by: -1) {
            let font = NSFont.systemFont(ofSize: pointSize, weight: .medium)
            let paragraph = titleParagraph(lineHeight: lineHeight(for: font), lineBreakMode: .byWordWrapping)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
            let title = NSAttributedString(string: text, attributes: attributes)
            let measured = title.boundingRect(
                with: NSSize(width: rect.width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            ).integral
            guard measured.height <= rect.height else { continue }
            title.draw(
                with: centeredRect(width: rect.width, height: measured.height, within: rect),
                options: [.usesLineFragmentOrigin, .usesFontLeading]
            )
            return
        }

        // An unusually long external title still wraps rather than receiving an
        // invented suffix or an ellipsis. Its available Touch Bar area limits
        // visible lines, while the actual name remains untouched.
        let fallbackFont = NSFont.systemFont(ofSize: 8, weight: .medium)
        drawMetricTitle(
            text,
            font: fallbackFont,
            lineBreakMode: .byWordWrapping,
            in: rect,
            color: color,
            lineHeight: lineHeight(for: fallbackFont)
        )
    }

    private func drawMetricTitle(
        _ text: String,
        font: NSFont,
        lineBreakMode: NSLineBreakMode,
        in rect: NSRect,
        color: NSColor,
        lineHeight: CGFloat? = nil
    ) {
        let paragraph = titleParagraph(
            lineHeight: lineHeight ?? self.lineHeight(for: font),
            lineBreakMode: lineBreakMode
        )
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
    }

    private func titleParagraph(lineHeight: CGFloat, lineBreakMode: NSLineBreakMode) -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .natural
        paragraph.lineBreakMode = lineBreakMode
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        return paragraph
    }

    private func lineHeight(for font: NSFont) -> CGFloat {
        ceil(font.ascender - font.descender + font.leading)
    }

    private func centeredRect(width: CGFloat, height: CGFloat, within rect: NSRect) -> NSRect {
        NSRect(x: rect.minX, y: rect.midY - height / 2, width: width, height: height)
    }

    private func t(_ key: String, _ defaultValue: String) -> String {
        localization.string(key, defaultValue: defaultValue)
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        color: NSColor,
        size: CGFloat,
        weight: NSFont.Weight = .regular,
        alignment: NSTextAlignment = .center
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        let font = attributes[.font] as! NSFont
        let drawRect = centeredRect(
            width: rect.width,
            height: min(rect.height, lineHeight(for: font)),
            within: rect
        )
        (text as NSString).draw(
            with: drawRect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes,
            context: nil
        )
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
