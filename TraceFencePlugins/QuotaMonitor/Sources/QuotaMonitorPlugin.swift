import AppKit
import Combine
import Foundation
import MacToolsPluginKit
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
        return [QuotaMonitorPlugin(
            engineURL: engineURL,
            localization: localization,
            touchBarExporter: TouchBarQuotaSnapshotExporter()
        )]
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
        static let enableTouchBar = "quota-monitor-enable-touch-bar"
        static let disableTouchBar = "quota-monitor-disable-touch-bar"
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
    private let touchBarExporter: TouchBarQuotaSnapshotExporter
    private let touchBarController = QuotaTouchBarController()
    private var serviceChangeCancellable: AnyCancellable?
    private var isExpanded = false
    private var isActive = false

    fileprivate init(
        engineURL: URL?,
        localization: PluginLocalization,
        touchBarExporter: TouchBarQuotaSnapshotExporter
    ) {
        self.service = ProviderQuotaService(
            providerEngineURL: engineURL,
            requiresExplicitProviderEngine: true
        )
        self.localization = localization
        self.touchBarExporter = touchBarExporter
        self.metadata = Self.makeMetadata(localization: localization)
        touchBarController.onStateChange = { [weak self] in
            self?.onStateChange?()
        }
        serviceChangeCancellable = service.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.touchBarController.receive(snapshots: self?.service.snapshots ?? [])
                self?.exportTouchBarSnapshot()
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
                defaultValue: "读取 Codex、Claude、Grok 等 Provider 的额度与重置时间；菜单栏界面由 TraceFence 保持不变。"
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
            )
        ]
        if touchBarController.isProvisioned {
            controls.append(PluginPanelControl(
                id: ControlID.enableTouchBar,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: localization.string("touchbar.section", defaultValue: "BetterTouchTool（可选）"),
                actionTitle: localization.string(
                    "touchbar.action.update",
                    defaultValue: "更新 Touch Bar 额度显示"
                ),
                actionIconSystemName: "rectangle.on.rectangle",
                isEnabled: !touchBarController.isUpdating
            ))
            controls.append(PluginPanelControl(
                id: ControlID.disableTouchBar,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: nil,
                actionTitle: localization.string(
                    "touchbar.action.disable",
                    defaultValue: "移除 Touch Bar 额度控件"
                ),
                actionIconSystemName: "trash",
                isEnabled: !touchBarController.isUpdating
            ))
        } else {
            controls.append(PluginPanelControl(
                id: ControlID.enableTouchBar,
                kind: .actionRow,
                options: [],
                selectedOptionID: nil,
                dateValue: nil,
                minimumDate: nil,
                displayedComponents: nil,
                datePickerStyle: nil,
                sectionTitle: localization.string("touchbar.section", defaultValue: "BetterTouchTool（可选）"),
                actionTitle: localization.string(
                    "touchbar.action.enable",
                    defaultValue: "启用 BetterTouchTool Touch Bar（可选，需要允许控制）"
                ),
                actionIconSystemName: "touchbar",
                isEnabled: !touchBarController.isUpdating
            ))
        }

        let detail = isExpanded ? PluginPanelDetail(controls: controls) : nil

        return PluginPanelState(
            subtitle: subtitle,
            isOn: service.isRefreshing,
            isExpanded: isExpanded,
            isEnabled: true,
            isVisible: true,
            detail: detail,
            errorMessage: touchBarController.errorMessage
        )
    }

    func activate(context: PluginRuntimeContext) {
        isActive = true
        touchBarController.activate(snapshots: service.snapshots)
        exportTouchBarSnapshot()
    }

    func deactivate(reason: PluginDeactivationReason) {
        isActive = false
        service.stop()
        touchBarController.deactivate(removeWidgets: reason == .disabled || reason == .uninstalling)
        touchBarExporter.removeSnapshot()
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
        case let .invokeAction(controlID) where controlID == ControlID.enableTouchBar:
            touchBarController.enable(snapshots: service.snapshots)
            onStateChange?()
        case let .invokeAction(controlID) where controlID == ControlID.disableTouchBar:
            touchBarController.disable()
            onStateChange?()
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

    func startQuotaMonitoring() {
        service.start()
    }

    func stopQuotaMonitoring() {
        service.stop()
    }

    func refreshQuotaMonitoring(force: Bool) {
        service.refresh(force: force)
    }

    func quotaMonitoringRefreshCooldownRemaining() -> TimeInterval {
        service.refreshCooldownRemaining()
    }

    private func exportTouchBarSnapshot() {
        guard isActive else { return }
        touchBarExporter.writeSnapshot(
            snapshots: service.snapshots,
            isRefreshing: service.isRefreshing,
            lastRefreshDate: service.lastRefreshDate
        )
    }
}

/// Exposes only display-safe quota data for a local BetterTouchTool widget.
/// The file deliberately excludes account labels, plans, credits, credential
/// sources, diagnostic strings, tokens, cookies and provider identifiers.
private struct TouchBarQuotaSnapshotExporter {
    private static let directoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TraceFence/TouchBar", isDirectory: true)
    private static let snapshotURL = directoryURL.appendingPathComponent("quota-status.json", isDirectory: false)

    private struct Snapshot: Encodable {
        let schemaVersion = 1
        let updatedAt: Date
        let isRefreshing: Bool
        let lastRefreshAt: Date?
        let providers: [Provider]
    }

    private struct Provider: Encodable {
        let name: String
        let freshness: String
        let windows: [Window]
    }

    private struct Window: Encodable {
        let kind: String
        let remainingPercent: Int
        let resetsAt: Date?
    }

    func writeSnapshot(
        snapshots: [ProviderQuotaSnapshot],
        isRefreshing: Bool,
        lastRefreshDate: Date?
    ) {
        let providers = snapshots.compactMap { snapshot -> Provider? in
            guard !snapshot.isSetupNotice else { return nil }
            let windows = snapshot.windows.map { window in
                Window(
                    kind: window.kind.rawValue,
                    remainingPercent: Int(window.remainingPercent.rounded()),
                    resetsAt: window.resetsAt
                )
            }
            guard !windows.isEmpty else { return nil }
            return Provider(
                name: sanitizedProviderName(snapshot.providerName),
                freshness: snapshot.freshness.rawValue,
                windows: windows
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let payload = Snapshot(
            updatedAt: Date(),
            isRefreshing: isRefreshing,
            lastRefreshAt: lastRefreshDate,
            providers: providers
        )
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: Self.directoryURL,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Self.directoryURL.path)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(payload).write(to: Self.snapshotURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Self.snapshotURL.path)
        } catch {
            // The BTT surface is strictly optional; quota monitoring continues
            // normally if a local display export cannot be written.
        }
    }

    func removeSnapshot() {
        try? FileManager.default.removeItem(at: Self.snapshotURL)
    }

    private func sanitizedProviderName(_ value: String) -> String {
        let normalized = value.lowercased()
        if normalized.contains("codex") { return "Codex" }
        if normalized.contains("claude") { return "Claude" }
        if normalized.contains("grok") { return "Grok" }
        if normalized.contains("cursor") { return "Cursor" }
        if normalized.contains("gemini") { return "Gemini" }
        if normalized.contains("deepseek") { return "DeepSeek" }
        if normalized.contains("antigravity") { return "Antigravity" }
        return "Provider"
    }
}

/// Owns the small local interaction channel used by the BTT buttons. The file
/// can contain only one of three fixed command words; it is never used to pass
/// quota data, account names, credentials, paths selected by the user, or shell
/// input back into TraceFence.
private enum QuotaTouchBarStorage {
    static let directoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/TraceFence/TouchBar", isDirectory: true)
    static let commandURL = directoryURL.appendingPathComponent("quota-touch-bar-command", isDirectory: false)
    static let bridgeStateURL = directoryURL.appendingPathComponent("quota-touch-bar-btt-state.json", isDirectory: false)
}

@MainActor
private final class QuotaTouchBarController {
    private enum Selection {
        case automatic
        case manual(String)
    }

    private enum Command: String {
        case previous
        case next
        case automatic
    }

    private let bridge = BetterTouchToolQuotaBridge()
    private var snapshots: [ProviderQuotaSnapshot] = []
    private var selection: Selection = .automatic
    private var selectedProviderID: String?
    private var activationObserver: NSObjectProtocol?
    private var commandTimer: Timer?
    private var isActive = false

    private(set) var isUpdating = false
    private(set) var errorMessage: String?
    var onStateChange: (() -> Void)?

    var isProvisioned: Bool { bridge.isProvisioned }
    var hasQuotaProviders: Bool { !QuotaTouchBarDisplay.items(from: snapshots).isEmpty }
    var panelSummary: String? {
        guard hasQuotaProviders else { return nil }
        return displayState().title
    }

    func activate(snapshots: [ProviderQuotaSnapshot]) {
        isActive = true
        self.snapshots = snapshots
        startObserving()
        refreshDisplay()
    }

    func deactivate(removeWidgets: Bool) {
        isActive = false
        stopObserving()
        guard removeWidgets else { return }
        disable()
    }

    func receive(snapshots: [ProviderQuotaSnapshot]) {
        self.snapshots = snapshots
        guard isActive else { return }
        refreshDisplay()
    }

    func enable(snapshots: [ProviderQuotaSnapshot]) {
        self.snapshots = snapshots
        beginUpdate()
        defer { finishUpdate() }
        do {
            try bridge.provision()
            errorMessage = nil
            startObserving()
            refreshDisplay()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func disable() {
        beginUpdate()
        defer { finishUpdate() }
        do {
            try bridge.removeOwnedWidgets()
            selection = .automatic
            selectedProviderID = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
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
        try? bridge.prepareCommandChannel()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDisplay()
            }
        }
        commandTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.consumeCommandIfNeeded()
            }
        }
    }

    private func stopObserving() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
        commandTimer?.invalidate()
        commandTimer = nil
        try? FileManager.default.removeItem(at: QuotaTouchBarStorage.commandURL)
    }

    private func consumeCommandIfNeeded() {
        guard let data = try? Data(contentsOf: QuotaTouchBarStorage.commandURL),
              data.count <= 16,
              let raw = String(data: data, encoding: .utf8),
              let command = Command(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines))
        else {
            return
        }
        try? FileManager.default.removeItem(at: QuotaTouchBarStorage.commandURL)

        switch command {
        case .previous:
            selectPreviousProvider()
        case .next:
            selectNextProvider()
        case .automatic:
            resumeAutomaticSelection()
        }
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
        guard bridge.isProvisioned else {
            onStateChange?()
            return
        }
        do {
            try bridge.updateDisplay(title: display.title, color: display.color)
            errorMessage = nil
        } catch {
            // Never surface a raw Apple Event/BTT response: it may contain an
            // unrelated BTT action definition. The actionable remediation is
            // stable and contains no private data.
            errorMessage = error.localizedDescription
        }
        onStateChange?()
    }

    private func displayState() -> QuotaTouchBarDisplay.State {
        let items = QuotaTouchBarDisplay.items(from: snapshots)
        guard !items.isEmpty else {
            selectedProviderID = nil
            return .unavailable(isRefreshing: false)
        }

        let selected: QuotaTouchBarDisplay.Item?
        switch selection {
        case let .manual(id):
            selected = items.first(where: { $0.id == id })
            if selected == nil { selection = .automatic }
        case .automatic:
            selected = nil
        }

        let resolved: QuotaTouchBarDisplay.Item
        if let selected {
            resolved = selected
        } else if let foreground = items.first(where: { item in
            item.providerKey == QuotaTouchBarDisplay.providerKey(for: frontmostApplicationText())
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
        let fiveHourRemaining: Int?
        let weeklyRemaining: Int?
        let lowestRemaining: Int
    }

    struct State: Equatable {
        let title: String
        let color: String

        static func unavailable(isRefreshing: Bool) -> State {
            State(
                title: isRefreshing ? "正在读取额度…" : "暂无额度数据",
                color: "71,76,87,255"
            )
        }

        static func quota(item: Item, isAutomatic: Bool) -> State {
            let fiveHour = item.fiveHourRemaining.map(String.init) ?? "—"
            let weekly = item.weeklyRemaining.map(String.init) ?? "—"
            let mode = isAutomatic ? "自动" : "手动"
            return State(
                title: "\(item.providerName) · 5h \(fiveHour)% · 周 \(weekly)% · \(mode)",
                color: QuotaTouchBarDisplay.color(for: item.lowestRemaining)
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
            return Item(
                id: snapshot.id,
                providerKey: providerKey(for: snapshot.providerName),
                providerName: sanitizedProviderName(snapshot.providerName),
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

    private static func sanitizedProviderName(_ value: String) -> String {
        switch providerKey(for: value) {
        case "codex": "Codex"
        case "claude": "Claude"
        case "grok": "Grok"
        case "cursor": "Cursor"
        case "gemini": "Gemini"
        case "deepseek": "DeepSeek"
        case "minimax": "MiniMax"
        case "antigravity": "Antigravity"
        default: "Provider"
        }
    }

    private static func color(for remaining: Int) -> String {
        switch remaining {
        case ...15: "190,63,70,255"
        case ...35: "182,104,35,255"
        default: "35,92,150,255"
        }
    }
}

/// BetterTouchTool remains the renderer on macOS 26. This bridge uses only
/// BTT's documented Apple Event API and records only the UUIDs of the three
/// controls it created. It never reads, edits, or exports unrelated BTT rules.
private final class BetterTouchToolQuotaBridge {
    private struct State: Codable {
        let schemaVersion: Int
        var previousUUID: String?
        var displayUUID: String?
        var nextUUID: String?

        var isComplete: Bool {
            previousUUID != nil && displayUUID != nil && nextUUID != nil
        }

        init(
            schemaVersion: Int = 1,
            previousUUID: String? = nil,
            displayUUID: String? = nil,
            nextUUID: String? = nil
        ) {
            self.schemaVersion = schemaVersion
            self.previousUUID = previousUUID
            self.displayUUID = displayUUID
            self.nextUUID = nextUUID
        }
    }

    private enum BridgeError: LocalizedError {
        case betterTouchToolNotInstalled
        case automationUnavailable
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .betterTouchToolNotInstalled:
                "未检测到 BetterTouchTool；请安装并启动它后重试。"
            case .automationUnavailable:
                "TraceFence 无法控制 BetterTouchTool。请在系统设置中允许自动化后重试。"
            case .invalidResponse:
                "BetterTouchTool 未确认创建额度控件；请重试。"
            }
        }
    }

    private var state: State?

    init() {
        state = Self.loadState()
    }

    var isProvisioned: Bool { state?.isComplete == true }

    func provision() throws {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.hegenberg.BetterTouchTool") != nil else {
            throw BridgeError.betterTouchToolNotInstalled
        }
        try prepareCommandChannel()
        var updated = state ?? State()
        if updated.previousUUID == nil {
            updated.previousUUID = try addTrigger(
                name: "TraceFence Quota · Previous",
                title: "‹",
                command: "previous",
                width: 30,
                order: 1000
            )
            try save(updated)
        }
        if updated.displayUUID == nil {
            updated.displayUUID = try addTrigger(
                name: "TraceFence Quota · Display",
                title: "额度读取中…",
                command: "automatic",
                width: 255,
                order: 1001
            )
            try save(updated)
        }
        if updated.nextUUID == nil {
            updated.nextUUID = try addTrigger(
                name: "TraceFence Quota · Next",
                title: "›",
                command: "next",
                width: 30,
                order: 1002
            )
            try save(updated)
        }
        state = updated
    }

    func updateDisplay(title: String, color: String) throws {
        guard let uuid = state?.displayUUID else { return }
        let update: [String: Any] = [
            "BTTTouchBarButtonName": title,
            "BTTTouchBarButtonColor": color,
            "BTTTouchBarButtonFontSize": 12
        ]
        try updateTrigger(uuid: uuid, json: try jsonString(update))
    }

    func removeOwnedWidgets() throws {
        guard let state else { return }
        for uuid in [state.previousUUID, state.displayUUID, state.nextUUID].compactMap({ $0 }) {
            try deleteTrigger(uuid: uuid)
        }
        try FileManager.default.removeItem(at: QuotaTouchBarStorage.bridgeStateURL)
        self.state = nil
    }

    func prepareCommandChannel() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: QuotaTouchBarStorage.directoryURL,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: QuotaTouchBarStorage.directoryURL.path
        )
        try? fileManager.removeItem(at: QuotaTouchBarStorage.commandURL)
    }

    private func addTrigger(
        name: String,
        title: String,
        command: String,
        width: Int,
        order: Int
    ) throws -> String {
        let trigger: [String: Any] = [
            "BTTTriggerType": 629,
            "BTTTriggerTypeDescription": "Touch Bar button",
            "BTTTriggerClass": "BTTTriggerTypeTouchBar",
            "BTTTriggerName": name,
            "BTTPredefinedActionType": -1,
            "BTTPredefinedActionName": "No Action",
            "BTTEnabled": 1,
            "BTTEnabled2": 1,
            "BTTOrder": order,
            "BTTActionsToExecute": [[
                "BTTPredefinedActionType": 137,
                "BTTPredefinedActionName": "Terminal Command (Background)",
                "BTTTerminalCommand": commandWriterScript(for: command)
            ]],
            "BTTTriggerConfig": [
                "BTTTouchBarButtonName": title,
                "BTTTouchBarButtonWidth": width,
                "BTTTouchBarButtonFontSize": 12,
                "BTTTouchBarButtonTextAlignment": 0,
                "BTTTouchBarFreeSpaceAfterButton": 0,
                "BTTTouchBarFreeSpaceBeforeButton": 0,
                "BTTTouchBarButtonColor": "35,92,150,255"
            ]
        ]
        let response = try runAppleScript(Self.addTriggerScript, arguments: [try jsonString(trigger)])
        let uuid = response.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UUID(uuidString: uuid) != nil else { throw BridgeError.invalidResponse }
        return uuid
    }

    private func updateTrigger(uuid: String, json: String) throws {
        _ = try runAppleScript(Self.updateTriggerScript, arguments: [uuid, json])
    }

    private func deleteTrigger(uuid: String) throws {
        _ = try runAppleScript(Self.deleteTriggerScript, arguments: [uuid])
    }

    private func commandWriterScript(for command: String) -> String {
        // `command` is an internal enum case, not user-controlled input. The
        // single-quoted path is likewise fixed by this plugin.
        "umask 077; /usr/bin/printf '%s' '\(command)' > '\(QuotaTouchBarStorage.commandURL.path)'"
    }

    private static func loadState() -> State? {
        guard let data = try? Data(contentsOf: QuotaTouchBarStorage.bridgeStateURL),
              let state = try? JSONDecoder().decode(State.self, from: data),
              state.schemaVersion == 1
        else {
            return nil
        }
        return state
    }

    private func save(_ state: State) throws {
        try prepareCommandChannel()
        let data = try JSONEncoder().encode(state)
        try data.write(to: QuotaTouchBarStorage.bridgeStateURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: QuotaTouchBarStorage.bridgeStateURL.path
        )
        self.state = state
    }

    private func jsonString(_ value: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        guard let string = String(data: data, encoding: .utf8) else { throw BridgeError.invalidResponse }
        return string
    }

    private func runAppleScript(_ source: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source, "--"] + arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw BridgeError.automationUnavailable
        }
        guard process.terminationStatus == 0 else {
            throw BridgeError.automationUnavailable
        }
        return String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private static let addTriggerScript = """
    on run argv
        tell application id "com.hegenberg.BetterTouchTool"
            return add_new_trigger (item 1 of argv)
        end tell
    end run
    """

    private static let updateTriggerScript = """
    on run argv
        tell application id "com.hegenberg.BetterTouchTool"
            return update_trigger (item 1 of argv) json (item 2 of argv)
        end tell
    end run
    """

    private static let deleteTriggerScript = """
    on run argv
        tell application id "com.hegenberg.BetterTouchTool"
            return delete_trigger (item 1 of argv)
        end tell
    end run
    """
}
