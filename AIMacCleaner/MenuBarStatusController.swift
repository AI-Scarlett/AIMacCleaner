import AppKit
import Combine
import Darwin
import ObjectiveC.runtime
import SwiftUI

/// A menu-bar panel must be able to become key even though it deliberately
/// does not activate the whole app. Otherwise AppKit consumes the first click
/// to focus the panel before SwiftUI's tab button can receive it.
private final class MenuBarPopoverPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Preserve the first click all the way through the AppKit/SwiftUI bridge.
private final class MenuBarFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

enum MenuBarStatusStyle: String, CaseIterable, Identifiable {
    case minimal
    case classic
    case detailed

    var id: String { rawValue }
}

enum MenuBarQuotaDisplayMode: String, CaseIterable, Identifiable {
    case remaining
    case used

    var id: String { rawValue }
}

enum MenuBarPrimaryMetric: String, CaseIterable, Identifiable {
    case tightest
    case fiveHour
    case weekly
    case fable
    case todayTokens

    var id: String { rawValue }
}

enum MenuBarStatusPreferences {
    static let styleKey = "traceFence.menuBar.statusStyle"
    static let quotaDisplayModeKey = "traceFence.menuBar.quotaDisplayMode"
    static let primaryMetricKey = "traceFence.menuBar.primaryMetric"
    static let showResetCountdownKey = "traceFence.menuBar.showResetCountdown"
}

enum TouchBarQuotaPreferences {
    static let enabledKey = "traceFence.touchBar.quotaEnabled"
    static let persistentKey = "traceFence.touchBar.persistent"
    static let autoSwitchKey = "traceFence.touchBar.autoSwitch"
}

/// The four colors always describe *remaining* quota. Keeping this mapping in
/// one host-level type prevents the menu bar title, the popover card, and a
/// later touch-surface implementation from disagreeing about the same value.
enum MenuBarQuotaColorBand: String, CaseIterable, Equatable {
    case critical
    case low
    case moderate
    case healthy

    static func band(for remainingPercent: Double) -> MenuBarQuotaColorBand {
        switch max(0, min(100, remainingPercent)) {
        case ..<20: return .critical
        case ..<50: return .low
        case ..<70: return .moderate
        default: return .healthy
        }
    }

    var color: Color {
        switch self {
        case .critical: return Theme.Colors.danger
        case .low: return .orange
        case .moderate: return .yellow
        case .healthy: return Theme.Colors.success
        }
    }

    var statusItemColor: NSColor {
        switch self {
        case .critical: return .systemRed
        case .low: return .systemOrange
        case .moderate: return .systemYellow
        case .healthy: return .systemGreen
        }
    }
}

/// Pure quota-presentation rules shared by the menu-bar label and its popover.
/// A snapshot, rather than a flattened quota window, is the selection unit so
/// a user always sees one Agent at a time.
enum MenuBarQuotaPresentation {
    static func displayableSnapshots(from snapshots: [ProviderQuotaSnapshot]) -> [ProviderQuotaSnapshot] {
        snapshots
            .filter { snapshot in
                !snapshot.isSetupNotice && (
                    !snapshot.windows.isEmpty
                        || snapshot.resetCredits != nil
                        || snapshot.credits != nil
                        || snapshot.errorMessage != nil
                )
            }
            .sorted { lhs, rhs in
                let nameOrder = lhs.providerName.localizedCaseInsensitiveCompare(rhs.providerName)
                if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
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

    static func preferredSnapshotID(
        in snapshots: [ProviderQuotaSnapshot],
        frontmostApplicationText: String,
        fallbackID: String?
    ) -> String? {
        let foregroundKey = providerKey(for: frontmostApplicationText)
        if !foregroundKey.isEmpty,
           let foreground = snapshots.first(where: { providerKey(for: $0.providerName) == foregroundKey }) {
            return foreground.id
        }
        if let fallbackID, snapshots.contains(where: { $0.id == fallbackID }) {
            return fallbackID
        }
        return snapshots.first?.id
    }

    static func cycledSnapshotID(
        in snapshots: [ProviderQuotaSnapshot],
        currentID: String?,
        offset: Int
    ) -> String? {
        guard !snapshots.isEmpty else { return nil }
        let currentIndex = currentID.flatMap { id in
            snapshots.firstIndex(where: { $0.id == id })
        } ?? 0
        let index = (currentIndex + offset % snapshots.count + snapshots.count) % snapshots.count
        return snapshots[index].id
    }

    static func colorBand(for snapshot: ProviderQuotaSnapshot) -> MenuBarQuotaColorBand? {
        let allowanceWindows = snapshot.windows.filter(\.isAllowanceWindow)
        let relevantWindows = allowanceWindows.isEmpty ? snapshot.windows : allowanceWindows
        return relevantWindows.map(\.remainingPercent).min().map { remaining in
            MenuBarQuotaColorBand.band(for: remaining)
        }
    }

    static func displayName(for snapshot: ProviderQuotaSnapshot) -> String {
        switch providerKey(for: snapshot.providerName) {
        case "codex": return "Codex"
        case "claude": return "Claude"
        case "grok": return "Grok"
        case "cursor": return "Cursor"
        case "gemini": return "Gemini"
        case "deepseek": return "DeepSeek"
        case "minimax": return "MiniMax"
        case "antigravity": return "Antigravity"
        default: return snapshot.providerName
        }
    }

#if DEBUG
    static func debugSelfTestFailures() -> [String] {
        var failures: [String] = []
        let expectedBands: [(Double, MenuBarQuotaColorBand)] = [
            (0, .critical), (19.99, .critical),
            (20, .low), (49.99, .low),
            (50, .moderate), (69.99, .moderate),
            (70, .healthy), (100, .healthy)
        ]
        for (value, expected) in expectedBands where MenuBarQuotaColorBand.band(for: value) != expected {
            failures.append("quota color threshold failed at \(value)%")
        }

        let now = Date()
        let codex = ProviderQuotaSnapshot(
            id: "codex", providerName: "Codex", planName: nil, accountLabel: nil, credits: nil,
            windows: [], resetCredits: nil, updatedAt: now, source: "test", errorMessage: "test",
            setupHint: nil, isSetupNotice: false
        )
        let claude = ProviderQuotaSnapshot(
            id: "claude", providerName: "Claude", planName: nil, accountLabel: nil, credits: nil,
            windows: [], resetCredits: nil, updatedAt: now, source: "test", errorMessage: "test",
            setupHint: nil, isSetupNotice: false
        )
        let snapshots = [claude, codex]
        if preferredSnapshotID(
            in: snapshots,
            frontmostApplicationText: "com.openai.codex Codex",
            fallbackID: "claude"
        ) != "codex" {
            failures.append("frontmost Codex did not select the Codex snapshot")
        }
        if cycledSnapshotID(in: snapshots, currentID: "claude", offset: -1) != "codex" {
            failures.append("previous Agent did not wrap around")
        }
        if cycledSnapshotID(in: snapshots, currentID: "codex", offset: 1) != "claude" {
            failures.append("next Agent did not wrap around")
        }
        return failures
    }
#endif
}

/// Shared selection state for the real menu-bar status item and popover. It is
/// deliberately independent from the Quota Monitor plugin's optional BTT path.
@MainActor
final class MenuBarQuotaSelectionController: ObservableObject {
    enum Selection: Equatable {
        case automatic
        case manual(String)
    }

    static let shared = MenuBarQuotaSelectionController()

    @Published private(set) var selection: Selection = .automatic
    @Published private(set) var selectedSnapshotID: String?

    private var snapshots: [ProviderQuotaSnapshot] = []
    private var activationObserver: NSObjectProtocol?

    var selectedSnapshot: ProviderQuotaSnapshot? {
        selectedSnapshotID.flatMap { id in snapshots.first(where: { $0.id == id }) }
    }

    var isAutomaticSelection: Bool {
        if case .automatic = selection { return true }
        return false
    }

    var position: (current: Int, total: Int)? {
        guard let selectedSnapshotID,
              let index = snapshots.firstIndex(where: { $0.id == selectedSnapshotID }) else { return nil }
        return (index + 1, snapshots.count)
    }

    private init() {
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resolveSelection()
            }
        }
    }

    func sync(snapshots source: [ProviderQuotaSnapshot]) {
        snapshots = MenuBarQuotaPresentation.displayableSnapshots(from: source)
        resolveSelection()
    }

    func selectPrevious() {
        select(offset: -1)
    }

    func selectNext() {
        select(offset: 1)
    }

    func resumeAutomaticSelection() {
        if !isAutomaticSelection {
            selection = .automatic
        }
        resolveSelection()
    }

    private func select(offset: Int) {
        guard let id = MenuBarQuotaPresentation.cycledSnapshotID(
            in: snapshots,
            currentID: selectedSnapshotID,
            offset: offset
        ) else { return }
        if selection != .manual(id) {
            selection = .manual(id)
        }
        setSelectedSnapshotID(id)
    }

    private func resolveSelection() {
        guard !snapshots.isEmpty else {
            if case .manual = selection { selection = .automatic }
            setSelectedSnapshotID(nil)
            return
        }

        let resolvedID: String?
        switch selection {
        case let .manual(id) where snapshots.contains(where: { $0.id == id }):
            resolvedID = id
        case .manual:
            selection = .automatic
            resolvedID = MenuBarQuotaPresentation.preferredSnapshotID(
                in: snapshots,
                frontmostApplicationText: frontmostApplicationText(),
                fallbackID: selectedSnapshotID
            )
        case .automatic:
            resolvedID = MenuBarQuotaPresentation.preferredSnapshotID(
                in: snapshots,
                frontmostApplicationText: frontmostApplicationText(),
                fallbackID: selectedSnapshotID
            )
        }
        setSelectedSnapshotID(resolvedID)
    }

    private func setSelectedSnapshotID(_ id: String?) {
        guard selectedSnapshotID != id else { return }
        selectedSnapshotID = id
    }

    private func frontmostApplicationText() -> String {
        let app = NSWorkspace.shared.frontmostApplication
        return [app?.localizedName, app?.bundleIdentifier]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}

@MainActor
final class MenuBarStatusController: NSObject, ObservableObject, NSWindowDelegate {
    private weak var appDelegate: AppDelegate?
    private weak var service: ScannerService?
    private weak var quotaService: ProviderQuotaService?
    private weak var usageInsightsService: AgentUsageInsightsService?
    private weak var captureService: CaptureShelfService?
    private weak var localizer: Localizer?
    private let quotaSelection = MenuBarQuotaSelectionController.shared
    private var statusItem: NSStatusItem?
    private var popoverPanel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var labelRefreshWorkItem: DispatchWorkItem?
    private var singleClickWorkItem: DispatchWorkItem?
    private var heartbeatTimer: Timer?
    private var globalDismissMonitor: Any?
    private var localDismissMonitor: Any?
    private var isEnabled = false
    private var didAutoOpenPopoverForUITest = false
#if DEBUG
    private var didRunMainConsoleSelfTest = false
#endif

    func configure(
        appDelegate: AppDelegate,
        service: ScannerService,
        quotaService: ProviderQuotaService,
        usageInsightsService: AgentUsageInsightsService,
        captureService: CaptureShelfService,
        localizer: Localizer,
        isEnabled: Bool
    ) {
        self.appDelegate = appDelegate
        self.service = service
        self.quotaService = quotaService
        self.usageInsightsService = usageInsightsService
        self.captureService = captureService
        self.localizer = localizer
        quotaSelection.sync(snapshots: quotaService.snapshots)
        bindPublishersIfNeeded()
        setEnabled(isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            ensureStatusItem()
            updateButtonLabel()
            autoOpenPopoverForUITestIfNeeded()
        } else {
            closePopover()
            removeStatusItem()
        }
    }

    private func autoOpenPopoverForUITestIfNeeded() {
        let launchArguments = ProcessInfo.processInfo.arguments
        let shouldRunMainConsoleSelfTest = launchArguments.contains("--tracefence-menu-console-self-test")
        let shouldKeepPanelOnlyForUITest = launchArguments.contains("--tracefence-menu-ui-preview")
        guard !didAutoOpenPopoverForUITest,
              launchArguments.contains("--tracefence-open-menu-bar") ||
                shouldRunMainConsoleSelfTest ||
                shouldKeepPanelOnlyForUITest else { return }
        didAutoOpenPopoverForUITest = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            guard let self else { return }
            self.showPopover()
#if DEBUG
            if shouldKeepPanelOnlyForUITest {
                NSApp.setActivationPolicy(.accessory)
                let hideMainWindows = {
                    for window in NSApp.windows where !window.isFloatingPanel && window.title == "TraceFence" {
                        window.orderOut(nil)
                    }
                }
                hideMainWindows()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                    hideMainWindows()
                    if !NSApp.windows.contains(where: {
                        ($0.isFloatingPanel || $0.title == "TraceFence Menu Preview") && $0.isVisible
                    }) {
                        self?.showPopover()
                    }
                }
            }
            if shouldRunMainConsoleSelfTest {
                self.runMainConsoleSelfTest()
            }
#endif
        }
    }

#if DEBUG
    private func runMainConsoleSelfTest() {
        guard !didRunMainConsoleSelfTest else { return }
        didRunMainConsoleSelfTest = true

        for window in NSApp.windows where !window.isFloatingPanel && window.title == "TraceFence" {
            window.orderOut(nil)
        }
        NSApp.setActivationPolicy(.accessory)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.openMainWindow(reason: "menu-bar-self-test")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                let mainWindowVisible = NSApp.windows.contains { window in
                    !window.isFloatingPanel && window.title == "TraceFence" && window.isVisible
                }
                let popoverClosed = !NSApp.windows.contains { $0.isFloatingPanel && $0.isVisible }
                let activationRestored = NSApp.activationPolicy() == .regular
                let succeeded = mainWindowVisible && popoverClosed && activationRestored
                let payload: [String: Any] = [
                    "succeeded": succeeded,
                    "mainWindowVisible": mainWindowVisible,
                    "popoverClosed": popoverClosed,
                    "activationRestored": activationRestored
                ]
                if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data("\n".utf8))
                }
                Darwin.exit(succeeded ? 0 : 2)
            }
        }
    }
#endif

    private func bindPublishersIfNeeded() {
        guard cancellables.isEmpty else { return }

        quotaService?.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleButtonLabelRefresh()
                }
            }
            .store(in: &cancellables)

        quotaService?.$snapshots
            .sink { [weak self] snapshots in
                self?.quotaSelection.sync(snapshots: snapshots)
            }
            .store(in: &cancellables)

        quotaSelection.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleButtonLabelRefresh()
                }
            }
            .store(in: &cancellables)

        usageInsightsService?.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleButtonLabelRefresh()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.startUsageInsightsIfRequiredByMenuBar()
                    self?.scheduleButtonLabelRefresh()
                }
            }
            .store(in: &cancellables)

        localizer?.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleButtonLabelRefresh()
                }
            }
            .store(in: &cancellables)
    }

    private func startUsageInsightsIfRequiredByMenuBar() {
        let defaults = UserDefaults.standard
        let style = defaults.string(forKey: MenuBarStatusPreferences.styleKey)
            .flatMap(MenuBarStatusStyle.init(rawValue:)) ?? .classic
        let metric = defaults.string(forKey: MenuBarStatusPreferences.primaryMetricKey)
            .flatMap(MenuBarPrimaryMetric.init(rawValue:)) ?? .tightest
        guard style != .minimal, style == .detailed || metric == .todayTokens else { return }
        usageInsightsService?.startScheduling()
    }

    private func ensureStatusItem() {
        guard isEnabled else { return }
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        configureStatusButton()
        startHeartbeat()
    }

    private func configureStatusButton() {
        guard let button = statusItem?.button else {
            rebuildStatusItem()
            return
        }
        button.image = MenuBarShieldEyeTemplateImage.shared.copy() as? NSImage
        button.image?.isTemplate = true
        button.imagePosition = .imageLeft
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        button.toolTip = "TraceFence"
    }

    private func rebuildStatusItem() {
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureStatusButton()
        updateButtonLabel()
    }

    private func removeStatusItem() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func startHeartbeat() {
        guard heartbeatTimer == nil else { return }
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.repairStatusItemIfNeeded()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func repairStatusItemIfNeeded() {
        guard isEnabled else { return }
        guard let button = statusItem?.button else {
            rebuildStatusItem()
            return
        }
        if button.target == nil || button.action == nil {
            configureStatusButton()
        }
        updateButtonLabel()
    }

    private func scheduleButtonLabelRefresh() {
        guard isEnabled else { return }
        labelRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.updateButtonLabel()
        }
        labelRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func updateButtonLabel() {
        guard isEnabled else { return }
        ensureStatusItem()
        guard let button = statusItem?.button else { return }

        let title = currentStatusTitle().map { " \($0)" } ?? ""
        let titleColor: NSColor
        if let snapshot = quotaSelection.selectedSnapshot,
           let band = MenuBarQuotaPresentation.colorBand(for: snapshot) {
            titleColor = band.statusItemColor
        } else {
            titleColor = .labelColor
        }
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: titleColor
            ]
        )
    }

    private func currentStatusTitle() -> String? {
        let defaults = UserDefaults.standard
        let style = defaults.string(forKey: MenuBarStatusPreferences.styleKey)
            .flatMap(MenuBarStatusStyle.init(rawValue:)) ?? .classic
        guard style != .minimal else { return nil }

        let displayMode = defaults.string(forKey: MenuBarStatusPreferences.quotaDisplayModeKey)
            .flatMap(MenuBarQuotaDisplayMode.init(rawValue:)) ?? .remaining
        let primaryMetric = defaults.string(forKey: MenuBarStatusPreferences.primaryMetricKey)
            .flatMap(MenuBarPrimaryMetric.init(rawValue:)) ?? .tightest
        quotaSelection.sync(snapshots: quotaService?.snapshots ?? [])
        guard let selectedSnapshot = quotaSelection.selectedSnapshot else {
            if let disk = service?.diskInfo {
                return String(format: "%.0f%%", 100.0 - disk.usedPct)
            }
            return nil
        }
        let windows = selectedSnapshot.windows.filter(\.isAllowanceWindow)
        let staleSuffix = selectedSnapshot.isStale && !windows.isEmpty ? " ~" : ""
        let providerName = MenuBarQuotaPresentation.displayName(for: selectedSnapshot)

        if style == .detailed {
            var parts: [String] = [providerName]
            if let fiveHour = tightestWindow(kind: .fiveHour, in: windows) {
                parts.append(formatQuota(fiveHour, displayMode: displayMode))
            }
            if let weekly = tightestWindow(kind: .weekly, in: windows) {
                parts.append(formatQuota(weekly, displayMode: displayMode))
            }
            for scopedWeekly in windows
                .filter(\.isScopedWeeklyAllowanceWindow)
                .sorted(by: { $0.remainingPercent < $1.remainingPercent }) {
                parts.append(formatQuota(scopedWeekly, displayMode: displayMode))
            }
            if let today = usageInsightsService?.snapshot(for: .combined).today.total, today > 0 {
                parts.append("T \(Self.compactCount(today))")
            }
            let showResetCountdown = defaults.object(forKey: MenuBarStatusPreferences.showResetCountdownKey) == nil
                ? true
                : defaults.bool(forKey: MenuBarStatusPreferences.showResetCountdownKey)
            if showResetCountdown,
               let reset = windows.compactMap(\.resetsAt).filter({ $0 > Date() }).min() {
                parts.append(Self.compactCountdown(to: reset))
            }
            return parts.joined(separator: " · ") + staleSuffix
        } else if let value = compactMetric(primaryMetric, windows: windows, displayMode: displayMode) {
            return "\(providerName) \(value)\(staleSuffix)"
        }
        return providerName + staleSuffix
    }

    private func compactMetric(
        _ metric: MenuBarPrimaryMetric,
        windows: [ProviderQuotaWindow],
        displayMode: MenuBarQuotaDisplayMode
    ) -> String? {
        switch metric {
        case .tightest:
            return windows.min(by: { $0.remainingPercent < $1.remainingPercent })
                .map { formatQuota($0, displayMode: displayMode) }
        case .fiveHour:
            return tightestWindow(kind: .fiveHour, in: windows)
                .map { formatQuota($0, displayMode: displayMode) }
        case .weekly:
            return windows
                .filter { $0.kind == .weekly || $0.isScopedWeeklyAllowanceWindow }
                .min { $0.remainingPercent < $1.remainingPercent }
                .map { formatQuota($0, displayMode: displayMode) }
        case .fable:
            return windows
                .first { $0.id == "claude-weekly-fable" }
                .map { formatQuota($0, displayMode: displayMode) }
        case .todayTokens:
            guard let total = usageInsightsService?.snapshot(for: .combined).today.total, total > 0 else { return nil }
            return "T \(Self.compactCount(total))"
        }
    }

    private func tightestWindow(
        kind: ProviderQuotaWindow.Kind,
        in windows: [ProviderQuotaWindow]
    ) -> ProviderQuotaWindow? {
        windows.filter { $0.kind == kind }
            .min { $0.remainingPercent < $1.remainingPercent }
    }

    private func formatQuota(
        _ window: ProviderQuotaWindow,
        displayMode: MenuBarQuotaDisplayMode
    ) -> String {
        let percent = displayMode == .remaining ? window.remainingPercent : window.usedPercent
        let suffix = displayMode == .remaining ? "" : " " + localized("已用", en: "used")
        let title: String
        switch window.kind {
        case .fiveHour: title = "5h"
        case .weekly: title = "7d"
        case .monthly: title = "30d"
        case .extra: title = window.scopedWeeklyAllowanceDisplayName ?? window.title
        }
        return "\(title) \(Int(percent.rounded()))%\(suffix)"
    }

    private static func compactCount(_ value: Int64) -> String {
        AgentUsageTokenFormatter.string(value)
    }

    private static func compactCountdown(to date: Date) -> String {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        if minutes >= 1_440 { return "\(minutes / 1_440)d" }
        if minutes >= 60 { return "\(minutes / 60)h\(minutes % 60)m" }
        return "\(minutes)m"
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard isEnabled else { return }
        repairStatusItemIfNeeded()
        let event = NSApp.currentEvent
        if event?.type == .rightMouseDown || (event?.clickCount ?? 1) >= 2 {
            singleClickWorkItem?.cancel()
            showEmergencyMenu()
            return
        }

        singleClickWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.popoverPanel?.isVisible == true {
                self.closePopover()
            } else {
                self.showPopover()
            }
        }
        singleClickWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func showPopover() {
        guard let service, let quotaService, let usageInsightsService, let captureService, let localizer else { return }
        guard let button = statusItem?.button else {
            rebuildStatusItem()
            return
        }

        closePopover()

        let panelSize = NSSize(width: 520, height: 640)
        let isMenuUIPreview = ProcessInfo.processInfo.arguments.contains("--tracefence-menu-ui-preview")
        let hostingView = MenuBarFirstMouseHostingView(
            rootView: MenuBarMonitor(
                service: service,
                quotaService: quotaService,
                usageInsightsService: usageInsightsService,
                captureService: captureService,
                quotaSelection: quotaSelection,
                openMainConsole: { [weak self] in
                    self?.openMainWindow(reason: "menu-bar-popover")
                }
            )
                .environmentObject(localizer)
        )
        hostingView.frame = NSRect(origin: .zero, size: panelSize)
        hostingView.wantsLayer = true
        hostingView.layer?.cornerRadius = 26
        hostingView.layer?.cornerCurve = .continuous
        hostingView.layer?.masksToBounds = true

        let panel = MenuBarPopoverPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: isMenuUIPreview ? [.titled, .closable] : [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        if isMenuUIPreview {
            panel.title = "TraceFence Menu Preview"
        }
        panel.delegate = self
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = !isMenuUIPreview
        panel.becomesKeyOnlyIfNeeded = false
        panel.level = isMenuUIPreview ? .normal : .statusBar
        panel.collectionBehavior = isMenuUIPreview
            ? [.fullScreenAuxiliary]
            : [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        if isMenuUIPreview {
            panel.center()
        } else {
            panel.setFrameOrigin(panelOrigin(for: button, panelSize: panelSize))
        }

        self.popoverPanel = panel
        panel.makeKeyAndOrderFront(nil)
        if !isMenuUIPreview {
            installDismissMonitors(anchor: button)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            quotaService.start()
            captureService.start()
        }
    }

    private func closePopover() {
        singleClickWorkItem?.cancel()
        removeDismissMonitors()
        popoverPanel?.orderOut(nil)
        popoverPanel?.delegate = nil
        popoverPanel?.contentView = nil
        popoverPanel = nil
    }

    func windowWillClose(_ notification: Notification) {
        removeDismissMonitors()
        popoverPanel?.delegate = nil
        popoverPanel?.contentView = nil
        popoverPanel = nil
    }

    private func installDismissMonitors(anchor: NSStatusBarButton) {
        removeDismissMonitors()

        globalDismissMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            Task { @MainActor in
                if event.type == .keyDown, event.keyCode != 53 {
                    return
                }
                self?.closePopover()
            }
        }

        localDismissMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self, weak anchor] event in
            guard let self else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 {
                    self.closePopover()
                    return nil
                }
                return event
            }

            if self.eventIsInsidePopover(event) || self.eventIsInsideStatusButton(event, anchor: anchor) {
                return event
            }

            self.closePopover()
            return event
        }
    }

    private func removeDismissMonitors() {
        if let globalDismissMonitor {
            NSEvent.removeMonitor(globalDismissMonitor)
            self.globalDismissMonitor = nil
        }
        if let localDismissMonitor {
            NSEvent.removeMonitor(localDismissMonitor)
            self.localDismissMonitor = nil
        }
    }

    private func eventIsInsidePopover(_ event: NSEvent) -> Bool {
        guard let popoverPanel else { return false }
        return event.window === popoverPanel
    }

    private func eventIsInsideStatusButton(_ event: NSEvent, anchor: NSStatusBarButton?) -> Bool {
        guard let anchor, event.window === anchor.window else { return false }
        let point = anchor.convert(event.locationInWindow, from: nil)
        return anchor.bounds.contains(point)
    }

    private func panelOrigin(for button: NSStatusBarButton, panelSize: NSSize) -> NSPoint {
        guard let buttonWindow = button.window else {
            return NSScreen.main.map { screen in
                NSPoint(
                    x: screen.visibleFrame.midX - panelSize.width / 2,
                    y: screen.visibleFrame.maxY - panelSize.height - 8
                )
            } ?? .zero
        }

        let buttonFrameInWindow = button.convert(button.bounds, to: nil)
        let buttonFrameOnScreen = buttonWindow.convertToScreen(buttonFrameInWindow)
        let screenFrame = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        let horizontalPadding: CGFloat = 8
        let verticalPadding: CGFloat = 6
        let proposedX = buttonFrameOnScreen.midX - panelSize.width / 2
        let x = min(
            max(proposedX, screenFrame.minX + horizontalPadding),
            screenFrame.maxX - panelSize.width - horizontalPadding
        )
        let proposedY = buttonFrameOnScreen.minY - panelSize.height - verticalPadding
        let fallbackY = buttonFrameOnScreen.maxY + verticalPadding
        let y = proposedY >= screenFrame.minY + verticalPadding ? proposedY : min(fallbackY, screenFrame.maxY - panelSize.height - verticalPadding)
        return NSPoint(x: x, y: y)
    }

    private func showEmergencyMenu() {
        closePopover()
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false

        let openItem = NSMenuItem(title: localized("打开 TraceFence", en: "Open TraceFence"), action: #selector(openMainWindowFromMenu), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let repairItem = NSMenuItem(title: localized("刷新菜单栏", en: "Refresh Menu Bar"), action: #selector(repairMenuBarFromMenu), keyEquivalent: "")
        repairItem.target = self
        menu.addItem(repairItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: localized("退出 TraceFence", en: "Quit TraceFence"), action: #selector(quitFromMenu), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        let forceQuitItem = NSMenuItem(title: localized("强制退出", en: "Force Quit"), action: #selector(forceQuitFromMenu), keyEquivalent: "")
        forceQuitItem.target = self
        menu.addItem(forceQuitItem)

        menu.popUp(positioning: nil, at: NSPoint(x: button.bounds.midX, y: button.bounds.minY), in: button)
    }

    @objc private func openMainWindowFromMenu() {
        openMainWindow(reason: "menu-bar")
    }

    private func openMainWindow(reason: String) {
        closePopover()
        appDelegate?.presentMainWindow(reason: reason)
    }

    @objc private func repairMenuBarFromMenu() {
        closePopover()
        rebuildStatusItem()
    }

    @objc private func quitFromMenu() {
        closePopover()
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.requestMenuBarQuit()
        } else {
            NSApp.terminate(nil)
        }
    }

    @objc private func forceQuitFromMenu() {
        Darwin.exit(0)
    }

    private func localized(_ zh: String, en: String) -> String {
        localizer?.t(zh, en: en, zhHant: zh, ja: en, ko: en, mt: en) ?? zh
    }
}

/// Website-build Touch Bar surface for the quota monitor plugin.
///
/// The controller only consumes `ProviderQuotaService`'s existing snapshots. It
/// never reads provider credentials or starts a second polling loop. The public
/// `NSWindow.touchBar` path remains available while TraceFence is frontmost;
/// the direct build can additionally keep the compact surface visible while an
/// Agent app is active.
@MainActor
final class TouchBarQuotaController: NSObject, ObservableObject, NSTouchBarDelegate {
    private enum ItemID {
        static let strip = NSTouchBarItem.Identifier("com.tracefence.touchbar.quota.strip")
        static let provider = NSTouchBarItem.Identifier("com.tracefence.touchbar.provider")
        static let primary = NSTouchBarItem.Identifier("com.tracefence.touchbar.primary")
        static let secondary = NSTouchBarItem.Identifier("com.tracefence.touchbar.secondary")
        static let refresh = NSTouchBarItem.Identifier("com.tracefence.touchbar.refresh")
    }

    private struct Candidate {
        let id: String
        let providerKey: String
        let snapshot: ProviderQuotaSnapshot

        var lowestRemaining: Double {
            snapshot.windows
                .filter(\.isAllowanceWindow)
                .map(\.remainingPercent)
                .min() ?? 101
        }
    }

    private weak var quotaService: ProviderQuotaService?
    private weak var overviewStore: AgentMonitorOverviewStore?
    private weak var appDelegate: AppDelegate?
    private weak var localizer: Localizer?
    private var cancellables: Set<AnyCancellable> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var heartbeatTimer: Timer?
    private var refreshWorkItem: DispatchWorkItem?
    private var touchBar: NSTouchBar?
    private var stripItem: NSCustomTouchBarItem?
    private var stripButton: NSButton?
    private var systemTrayRegistered = false
    private weak var attachedWindow: NSWindow?
    private var providerButton: NSButton?
    private var primaryButton: NSButton?
    private var secondaryButton: NSButton?
    private var refreshButton: NSButton?
    private var selectedCandidateID: String?
    private var manualCandidateID: String?
    private var systemModalPresented = false

    static var isTouchBarCapableMac: Bool {
        // Custom NSTouchBar content repeatedly corrupts the XR drawable on
        // macOS 26 (SLSHMDGetDrawable error 1000), including via public AppKit.
        // Keep the hardware's system controls intact and use menu-bar quota.
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26 else {
            return false
        }
        let models: Set<String> = [
            "MacBookPro13,2", "MacBookPro13,3",
            "MacBookPro14,2", "MacBookPro14,3",
            "MacBookPro15,1", "MacBookPro15,2", "MacBookPro15,3", "MacBookPro15,4",
            "MacBookPro16,1", "MacBookPro16,2", "MacBookPro16,3", "MacBookPro16,4",
            "MacBookPro17,1"
        ]
        return models.contains(hardwareModel())
    }

    func configure(
        quotaService: ProviderQuotaService,
        overviewStore: AgentMonitorOverviewStore,
        appDelegate: AppDelegate,
        localizer: Localizer
    ) {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect,
              Self.isTouchBarCapableMac else {
            stop()
            return
        }
        self.quotaService = quotaService
        self.overviewStore = overviewStore
        self.appDelegate = appDelegate
        self.localizer = localizer
        bindIfNeeded()
        applyPreferences()
    }

    func stop() {
        refreshWorkItem?.cancel()
        refreshWorkItem = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { workspaceCenter.removeObserver($0) }
        workspaceObservers.removeAll()
        dismissPersistentTouchBar()
        unregisterSystemTrayItem()
        if attachedWindow?.touchBar === touchBar {
            attachedWindow?.touchBar = nil
        }
        attachedWindow = nil
        touchBar = nil
        stripItem = nil
        stripButton = nil
        providerButton = nil
        primaryButton = nil
        secondaryButton = nil
        refreshButton = nil
        cancellables.removeAll()
    }

    private var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: TouchBarQuotaPreferences.enabledKey)
    }

    private var shouldPersist: Bool {
        // Public AppKit only exposes an application's Touch Bar while that app
        // is frontmost. The private global Control Strip path corrupts the XR
        // drawable on macOS 26.5, so never enter it in production.
        false
    }

    private var shouldAutoSwitch: Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: TouchBarQuotaPreferences.autoSwitchKey) == nil { return true }
        return defaults.bool(forKey: TouchBarQuotaPreferences.autoSwitchKey)
    }

    private func bindIfNeeded() {
        guard cancellables.isEmpty else { return }

        quotaService?.objectWillChange
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)
        overviewStore?.objectWillChange
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)
        localizer?.objectWillChange
            .sink { [weak self] _ in self?.scheduleRefresh() }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyPreferences() }
            }
            .store(in: &cancellables)

        let workspaceCenter = NSWorkspace.shared.notificationCenter
        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                if self?.shouldAutoSwitch == true {
                    self?.manualCandidateID = nil
                }
                self?.refreshDisplay()
            }
        })

        workspaceObservers.append(workspaceCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.bundleIdentifier == "com.apple.controlstrip" else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self?.reassertSystemTrayPresence()
            }
        })

        for name in [
            NSWorkspace.didWakeNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ] {
            workspaceObservers.append(workspaceCenter.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self?.reassertSystemTrayPresence()
                }
            })
        }

        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDisplay() }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    private func scheduleRefresh() {
        refreshWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in self?.refreshDisplay() }
        refreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func applyPreferences() {
        guard isEnabled else {
            dismissPersistentTouchBar()
            unregisterSystemTrayItem()
            if attachedWindow?.touchBar === touchBar {
                attachedWindow?.touchBar = nil
            }
            return
        }
        ensureTouchBar()
        attachToMainWindow()
        refreshDisplay()
        if shouldPersist {
            registerSystemTrayItemIfAvailable()
        } else {
            dismissPersistentTouchBar()
            unregisterSystemTrayItem()
        }
    }

    private func ensureTouchBar() {
        guard touchBar == nil else { return }
        let bar = NSTouchBar()
        bar.delegate = self
        bar.customizationIdentifier = NSTouchBar.CustomizationIdentifier("com.tracefence.touchbar.quota")
        bar.defaultItemIdentifiers = [
            ItemID.provider,
            .fixedSpaceSmall,
            ItemID.primary,
            .fixedSpaceSmall,
            ItemID.secondary,
            .flexibleSpace,
            ItemID.refresh
        ]
        bar.customizationAllowedItemIdentifiers = [
            ItemID.provider, ItemID.primary, ItemID.secondary, ItemID.refresh
        ]
        touchBar = bar
    }

    /// Install a compact, always-visible Control Strip item. A registered item
    /// is required on current TouchBarServer builds; presenting a modal bar
    /// without one may be accepted by the service but never reach the panel.
    private func registerSystemTrayItemIfAvailable() {
#if TRACEFENCE_DIRECT_TOUCH_BAR
        guard shouldPersist else { return }
        if !systemTrayRegistered {
            let item = NSCustomTouchBarItem(identifier: ItemID.strip)
            let button = NSButton(title: "TF —", target: self, action: #selector(openTouchBarDetails))
            button.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
            button.bezelStyle = .texturedRounded
            button.contentTintColor = .white
            button.setAccessibilityLabel(localized("TraceFence 剩余额度", en: "TraceFence remaining quota"))
            button.translatesAutoresizingMaskIntoConstraints = true
            button.frame = NSRect(x: 0, y: 0, width: 88, height: 30)
            item.view = button

            guard Self.addSystemTrayItem(item) else { return }
            stripItem = item
            stripButton = button
            systemTrayRegistered = true
        }
        Self.setControlStripPresence(true, identifier: ItemID.strip)
#endif
    }

    private func unregisterSystemTrayItem() {
#if TRACEFENCE_DIRECT_TOUCH_BAR
        guard systemTrayRegistered, let registeredItem = stripItem else { return }
        Self.setControlStripPresence(false, identifier: ItemID.strip)
        Self.removeSystemTrayItem(registeredItem)
#endif
        systemTrayRegistered = false
        stripItem = nil
        stripButton = nil
    }

    private func reassertSystemTrayPresence() {
#if TRACEFENCE_DIRECT_TOUCH_BAR
        guard isEnabled, shouldPersist else { return }
        registerSystemTrayItemIfAvailable()
        refreshDisplay()
#endif
    }

    private func attachToMainWindow() {
        guard let touchBar else { return }
        let mainWindow = NSApp.windows.first {
            !$0.isFloatingPanel && $0.title == "TraceFence"
        } ?? NSApp.mainWindow
        guard let mainWindow else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard self?.isEnabled == true else { return }
                self?.attachToMainWindow()
            }
            return
        }
        if attachedWindow !== mainWindow {
            if attachedWindow?.touchBar === touchBar { attachedWindow?.touchBar = nil }
            attachedWindow = mainWindow
        }
        mainWindow.touchBar = touchBar
    }

    func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
        switch identifier {
        case ItemID.provider:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = makeButton(width: 112, action: #selector(cycleProvider))
            button.contentTintColor = .systemBlue
            providerButton = button
            item.view = button
            return item
        case ItemID.primary:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = makeButton(width: 106)
            primaryButton = button
            item.view = button
            return item
        case ItemID.secondary:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = makeButton(width: 106)
            secondaryButton = button
            item.view = button
            return item
        case ItemID.refresh:
            let item = NSCustomTouchBarItem(identifier: identifier)
            let button = NSButton(image: NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh quota") ?? NSImage(), target: self, action: #selector(refreshQuota))
            button.bezelStyle = .texturedRounded
            button.toolTip = "Refresh quota"
            refreshButton = button
            item.view = button
            return item
        default:
            return nil
        }
    }

    private func makeButton(width: CGFloat, action: Selector? = nil) -> NSButton {
        let button = NSButton(title: "—", target: action == nil ? nil : self, action: action)
        button.bezelStyle = .texturedRounded
        button.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: width).isActive = true
        return button
    }

    private func refreshDisplay() {
        guard isEnabled else { return }
        ensureTouchBar()
        attachToMainWindow()
        let candidates = quotaCandidates()
        guard let selected = chooseCandidate(from: candidates) else {
            selectedCandidateID = nil
            providerButton?.title = quotaUnavailableTitle()
            providerButton?.toolTip = quotaService?.quotaPluginErrorMessage
            primaryButton?.title = quotaService?.isRefreshing == true
                ? localized("正在刷新…", en: "Refreshing…")
                : localized("暂无额度", en: "No quota")
            secondaryButton?.title = localized("打开 TraceFence", en: "Open TraceFence")
            refreshButton?.isEnabled = quotaService?.isQuotaPluginInstalled == true
            updateStripButton(title: quotaService?.isRefreshing == true ? "TF …" : "TF —")
            if shouldPersist { registerSystemTrayItemIfAvailable() }
            return
        }

        selectedCandidateID = selected.id
        let snapshot = selected.snapshot
        providerButton?.title = snapshot.providerName + (snapshot.isStale ? " ~" : "")
        providerButton?.toolTip = snapshot.accountLabel

        let windows = displayWindows(for: snapshot)
        primaryButton?.title = windows.indices.contains(0)
            ? format(windows[0], displayMode: displayMode)
            : creditTitle(for: snapshot)
        secondaryButton?.title = windows.indices.contains(1)
            ? format(windows[1], displayMode: displayMode)
            : resetTitle(for: windows.first)
        refreshButton?.isEnabled = quotaService?.isRefreshing != true
        let tightest = snapshot.windows
            .filter(\.isAllowanceWindow)
            .min { $0.remainingPercent < $1.remainingPercent }
        let percent = tightest.map {
            displayMode == .remaining ? $0.remainingPercent : $0.usedPercent
        }
        let provider = Self.providerAbbreviation(snapshot.providerName)
        updateStripButton(title: percent.map { "\(provider) \(Int($0.rounded()))%" } ?? "\(provider) —")
        if shouldPersist { registerSystemTrayItemIfAvailable() }
    }

    private func updateStripButton(title: String) {
        registerSystemTrayItemIfAvailable()
        stripButton?.title = title
        stripButton?.toolTip = localized("点击查看并切换 Agent 额度", en: "View and switch Agent quotas")
    }

    private var displayMode: MenuBarQuotaDisplayMode {
        UserDefaults.standard.string(forKey: MenuBarStatusPreferences.quotaDisplayModeKey)
            .flatMap(MenuBarQuotaDisplayMode.init(rawValue:)) ?? .remaining
    }

    private func quotaCandidates() -> [Candidate] {
        (quotaService?.snapshots ?? [])
            .filter { !$0.isSetupNotice && ($0.quotaReadSucceeded || !$0.windows.isEmpty || $0.credits != nil) }
            .map {
                Candidate(id: $0.id, providerKey: Self.providerKey(for: $0.providerName), snapshot: $0)
            }
            .sorted {
                if $0.snapshot.providerName != $1.snapshot.providerName {
                    return $0.snapshot.providerName.localizedCaseInsensitiveCompare($1.snapshot.providerName) == .orderedAscending
                }
                return $0.id < $1.id
            }
    }

    private func chooseCandidate(from candidates: [Candidate]) -> Candidate? {
        guard !candidates.isEmpty else { return nil }
        if let manualCandidateID,
           let manual = candidates.first(where: { $0.id == manualCandidateID }) {
            return manual
        }

        if shouldAutoSwitch {
            let frontmost = NSWorkspace.shared.frontmostApplication
            let foregroundText = [frontmost?.localizedName, frontmost?.bundleIdentifier]
                .compactMap { $0 }
                .joined(separator: " ")
            let foregroundKey = Self.providerKey(for: foregroundText)
            if !foregroundKey.isEmpty,
               let foreground = candidates.first(where: { $0.providerKey == foregroundKey }) {
                return foreground
            }

            let now = Date()
            let activeSession = overviewStore?.sessions
                .filter { AgentMonitorSessionLiveness.isActive($0, now: now) }
                .sorted {
                    let lhs = [$0.latestActivity, $0.instructionDate].compactMap { $0 }.max() ?? .distantPast
                    let rhs = [$1.latestActivity, $1.instructionDate].compactMap { $0 }.max() ?? .distantPast
                    return lhs > rhs
                }
                .first
            if let activeSession {
                let activeKey = Self.providerKey(for: activeSession.agentName)
                if let active = candidates.first(where: { $0.providerKey == activeKey }) {
                    return active
                }
            }
        }

        if let selectedCandidateID,
           let previous = candidates.first(where: { $0.id == selectedCandidateID }) {
            return previous
        }
        return candidates.min { $0.lowestRemaining < $1.lowestRemaining }
    }

    private func displayWindows(for snapshot: ProviderQuotaSnapshot) -> [ProviderQuotaWindow] {
        let windows = snapshot.windows.filter(\.isAllowanceWindow)
        var result: [ProviderQuotaWindow] = []
        if let fiveHour = windows.filter({ $0.kind == .fiveHour }).min(by: { $0.remainingPercent < $1.remainingPercent }) {
            result.append(fiveHour)
        }
        if let weekly = windows.filter({ $0.kind == .weekly }).min(by: { $0.remainingPercent < $1.remainingPercent }) {
            result.append(weekly)
        }
        let scoped = windows
            .filter(\.isScopedWeeklyAllowanceWindow)
            .sorted { lhs, rhs in
                if lhs.id == "claude-weekly-fable" { return true }
                if rhs.id == "claude-weekly-fable" { return false }
                return lhs.remainingPercent < rhs.remainingPercent
            }
        for window in scoped where result.count < 2 {
            result.append(window)
        }
        if result.isEmpty {
            result = Array(windows.sorted { $0.remainingPercent < $1.remainingPercent }.prefix(2))
        }
        return Array(result.prefix(2))
    }

    private func creditTitle(for snapshot: ProviderQuotaSnapshot) -> String {
        guard let credits = snapshot.credits else { return localized("额度可用", en: "Quota ready") }
        return String(format: localized("余额 %.1f", en: "Balance %.1f"), credits)
    }

    private func resetTitle(for window: ProviderQuotaWindow?) -> String {
        guard let reset = window?.resetsAt, reset > Date() else {
            return localized("点击切换 Agent", en: "Tap to switch")
        }
        let minutes = max(0, Int(reset.timeIntervalSinceNow / 60))
        let prefix = localized("重置", en: "Reset")
        if minutes >= 1_440 { return "\(prefix) \(minutes / 1_440)d" }
        if minutes >= 60 { return "\(prefix) \(minutes / 60)h" }
        return "\(prefix) \(minutes)m"
    }

    private func quotaUnavailableTitle() -> String {
        guard let quotaService else { return localized("额度监控", en: "Quota monitor") }
        if quotaService.quotaPluginNeedsInstallation { return localized("安装额度插件", en: "Install quota plugin") }
        if quotaService.quotaPluginNeedsEnablement { return localized("启用额度插件", en: "Enable quota plugin") }
        return localized("额度监控", en: "Quota monitor")
    }

    @objc private func cycleProvider() {
        let candidates = quotaCandidates()
        guard !candidates.isEmpty else {
            appDelegate?.presentMainWindow(reason: "touch-bar-quota")
            return
        }
        let currentID = selectedCandidateID ?? manualCandidateID
        let nextIndex: Int
        if let currentID, let index = candidates.firstIndex(where: { $0.id == currentID }) {
            nextIndex = candidates.index(after: index) == candidates.endIndex ? candidates.startIndex : candidates.index(after: index)
        } else {
            nextIndex = candidates.startIndex
        }
        manualCandidateID = candidates[nextIndex].id
        selectedCandidateID = manualCandidateID
        refreshDisplay()
    }

    @objc private func refreshQuota() {
        quotaService?.refresh(force: true)
        refreshButton?.isEnabled = false
        scheduleRefresh()
    }

    private func format(_ window: ProviderQuotaWindow, displayMode: MenuBarQuotaDisplayMode) -> String {
        Self.format(window, displayMode: displayMode, language: localizer?.language ?? .english)
    }

    private static func format(
        _ window: ProviderQuotaWindow,
        displayMode: MenuBarQuotaDisplayMode,
        language: AppLanguage
    ) -> String {
        let percent = displayMode == .remaining ? window.remainingPercent : window.usedPercent
        let rounded = Int(percent.rounded())
        switch language {
        case .simplifiedChinese, .traditionalChinese:
            return "\(window.shortTitle) \(displayMode == .remaining ? "余" : "用")\(rounded)%"
        case .japanese:
            return "\(window.shortTitle) \(displayMode == .remaining ? "残" : "使用")\(rounded)%"
        case .korean:
            return "\(window.shortTitle) \(displayMode == .remaining ? "잔여" : "사용") \(rounded)%"
        case .english, .maltese:
            return "\(window.shortTitle) \(rounded)% \(displayMode == .remaining ? "left" : "used")"
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
        return normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .first ?? ""
    }

    private static func providerAbbreviation(_ name: String) -> String {
        switch providerKey(for: name) {
        case "codex": return "C"
        case "claude": return "Cl"
        case "grok": return "G"
        case "deepseek": return "DSH"
        case "gemini": return "Ge"
        case "cursor": return "Cu"
        case "minimax": return "MM"
        default: return String(name.prefix(2))
        }
    }

    static func debugSelfTestFailures() -> [String] {
        var failures: [String] = []
        if providerKey(for: "com.openai.codex") != "codex" { failures.append("Codex bundle alias failed") }
        if providerKey(for: "Claude Code") != "claude" { failures.append("Claude alias failed") }
        if providerKey(for: "DeepSeek Harness") != "deepseek" { failures.append("DSH alias failed") }
        let window = ProviderQuotaWindow(
            id: "primary", kind: .fiveHour, title: "5 hour", usedPercent: 31.4,
            resetsAt: nil, windowMinutes: 300
        )
        if format(window, displayMode: .remaining, language: .simplifiedChinese) != "5h 余69%" {
            failures.append("remaining quota formatting failed")
        }
        return failures
    }

    private static func hardwareModel() -> String {
        var size: size_t = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return "" }
        return String(cString: buffer)
    }

    private func localized(_ zh: String, en: String) -> String {
        localizer?.t(zh, en: en, zhHant: zh, ja: en, ko: en, mt: en) ?? en
    }

    @objc private func openTouchBarDetails() {
#if TRACEFENCE_DIRECT_TOUCH_BAR
        guard shouldPersist, let touchBar else { return }
        systemModalPresented = Self.presentSystemModalTouchBar(
            touchBar,
            systemTrayItemIdentifier: ItemID.strip
        )
        Self.setControlStripPresence(true, identifier: ItemID.strip)
#endif
    }

#if TRACEFENCE_DIRECT_TOUCH_BAR
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
        present(NSTouchBar.self, selector, touchBar, 1, identifier.rawValue as NSString)
        return true
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
        _ present: Bool,
        identifier: NSTouchBarItem.Identifier
    ) {
        let framework = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
        guard let handle = dlopen(framework, RTLD_LAZY | RTLD_LOCAL) else { return }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "DFRElementSetControlStripPresenceForIdentifier") else { return }
        typealias SetPresence = @convention(c) (NSString, Int8) -> Void
        let setPresence = unsafeBitCast(symbol, to: SetPresence.self)
        setPresence(identifier.rawValue as NSString, present ? 1 : 0)
    }

    /// The default system-modal close button is injected outside our bar. On
    /// macOS 26 it can be laid out before the DFR root view receives its real
    /// width, leaving the whole surface at zero width. Disabling that injected
    /// button matches the standalone-HUD presentation contract; TraceFence's
    /// own preference switch remains the explicit way to dismiss the surface.
    private static func configureSystemModalCloseBox() {
        let framework = "/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation"
        guard let handle = dlopen(framework, RTLD_LAZY | RTLD_LOCAL) else { return }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
        typealias ConfigureCloseBox = @convention(c) (Int8) -> Void
        let configure = unsafeBitCast(symbol, to: ConfigureCloseBox.self)
        configure(0)
    }
#endif

    private func dismissPersistentTouchBar() {
#if TRACEFENCE_DIRECT_TOUCH_BAR
        guard systemModalPresented, let touchBar else { return }
        let selector = NSSelectorFromString("dismissSystemModalTouchBar:")
        let touchBarClass: AnyObject = NSTouchBar.self
        if touchBarClass.responds(to: selector) {
            _ = touchBarClass.perform(selector, with: touchBar)
        }
#endif
        systemModalPresented = false
    }
}
