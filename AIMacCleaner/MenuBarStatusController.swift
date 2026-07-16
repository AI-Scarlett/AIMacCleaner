import AppKit
import Combine
import Darwin
import SwiftUI

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
    case todayTokens

    var id: String { rawValue }
}

enum MenuBarStatusPreferences {
    static let styleKey = "traceFence.menuBar.statusStyle"
    static let quotaDisplayModeKey = "traceFence.menuBar.quotaDisplayMode"
    static let primaryMetricKey = "traceFence.menuBar.primaryMetric"
    static let showResetCountdownKey = "traceFence.menuBar.showResetCountdown"
}

@MainActor
final class MenuBarStatusController: NSObject, ObservableObject, NSWindowDelegate {
    private weak var service: ScannerService?
    private weak var quotaService: ProviderQuotaService?
    private weak var usageInsightsService: AgentUsageInsightsService?
    private weak var captureService: CaptureShelfService?
    private weak var localizer: Localizer?
    private var statusItem: NSStatusItem?
    private var popoverPanel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private var labelRefreshWorkItem: DispatchWorkItem?
    private var singleClickWorkItem: DispatchWorkItem?
    private var heartbeatTimer: Timer?
    private var globalDismissMonitor: Any?
    private var localDismissMonitor: Any?
    private var isEnabled = false

    func configure(
        service: ScannerService,
        quotaService: ProviderQuotaService,
        usageInsightsService: AgentUsageInsightsService,
        captureService: CaptureShelfService,
        localizer: Localizer,
        isEnabled: Bool
    ) {
        self.service = service
        self.quotaService = quotaService
        self.usageInsightsService = usageInsightsService
        self.captureService = captureService
        self.localizer = localizer
        bindPublishersIfNeeded()
        setEnabled(isEnabled)
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        if enabled {
            ensureStatusItem()
            updateButtonLabel()
        } else {
            closePopover()
            removeStatusItem()
        }
    }

    private func bindPublishersIfNeeded() {
        guard cancellables.isEmpty else { return }

        quotaService?.objectWillChange
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
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
                .foregroundColor: NSColor.labelColor
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
        let windows = quotaService?.snapshots
            .filter { !$0.isSetupNotice }
            .flatMap(\.windows)
            .filter { ["primary", "secondary", "tertiary"].contains($0.id) } ?? []
        let staleSuffix = quotaService?.snapshots.contains(where: {
            $0.isStale && $0.windows.contains(where: { ["primary", "secondary", "tertiary"].contains($0.id) })
        }) == true ? " ~" : ""

        if style == .detailed {
            var parts: [String] = []
            if let fiveHour = tightestWindow(kind: .fiveHour, in: windows) {
                parts.append(formatQuota(fiveHour, displayMode: displayMode))
            }
            if let weekly = tightestWindow(kind: .weekly, in: windows) {
                parts.append(formatQuota(weekly, displayMode: displayMode))
            }
            if let today = usageInsightsService?.snapshot.today.total, today > 0 {
                parts.append("T \(Self.compactCount(today))")
            }
            let showResetCountdown = defaults.object(forKey: MenuBarStatusPreferences.showResetCountdownKey) == nil
                ? true
                : defaults.bool(forKey: MenuBarStatusPreferences.showResetCountdownKey)
            if showResetCountdown,
               let reset = windows.compactMap(\.resetsAt).filter({ $0 > Date() }).min() {
                parts.append(Self.compactCountdown(to: reset))
            }
            if !parts.isEmpty { return parts.joined(separator: " · ") + staleSuffix }
        } else if let value = compactMetric(primaryMetric, windows: windows, displayMode: displayMode) {
            return value + staleSuffix
        }
        if let disk = service?.diskInfo {
            return String(format: "%.0f%%", 100.0 - disk.usedPct)
        }
        return nil
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
            return tightestWindow(kind: .weekly, in: windows)
                .map { formatQuota($0, displayMode: displayMode) }
        case .todayTokens:
            guard let total = usageInsightsService?.snapshot.today.total, total > 0 else { return nil }
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
        case .extra: title = window.title
        }
        return "\(title) \(Int(percent.rounded()))%\(suffix)"
    }

    private static func compactCount(_ value: Int64) -> String {
        switch value {
        case 1_000_000_000...:
            return String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", Double(value) / 1_000)
        default:
            return "\(value)"
        }
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
        let hostingView = NSHostingView(
            rootView: MenuBarMonitor(service: service, quotaService: quotaService, usageInsightsService: usageInsightsService, captureService: captureService)
                .environmentObject(localizer)
        )
        hostingView.frame = NSRect(origin: .zero, size: panelSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.delegate = self
        panel.contentView = hostingView
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.setFrameOrigin(panelOrigin(for: button, panelSize: panelSize))

        self.popoverPanel = panel
        panel.orderFrontRegardless()
        installDismissMonitors(anchor: button)
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
        closePopover()
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.presentMainWindow(reason: "menu-bar")
        }
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
