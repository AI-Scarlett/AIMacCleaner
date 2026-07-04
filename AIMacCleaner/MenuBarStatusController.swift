import AppKit
import Combine
import Darwin
import SwiftUI

@MainActor
final class MenuBarStatusController: NSObject, ObservableObject, NSPopoverDelegate {
    private weak var service: ScannerService?
    private weak var quotaService: ProviderQuotaService?
    private weak var captureService: CaptureShelfService?
    private weak var localizer: Localizer?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
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
        captureService: CaptureShelfService,
        localizer: Localizer,
        isEnabled: Bool
    ) {
        self.service = service
        self.quotaService = quotaService
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

        localizer?.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.scheduleButtonLabelRefresh()
                }
            }
            .store(in: &cancellables)
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
        if let quota = quotaService?.menuBarSummary, !quota.isEmpty {
            return quota
        }
        if let disk = service?.diskInfo {
            return String(format: "%.0f%%", 100.0 - disk.usedPct)
        }
        return nil
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
            if self.popover?.isShown == true {
                self.closePopover()
            } else {
                self.showPopover()
            }
        }
        singleClickWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: workItem)
    }

    private func showPopover() {
        guard let service, let quotaService, let captureService, let localizer else { return }
        guard let button = statusItem?.button else {
            rebuildStatusItem()
            return
        }

        closePopover()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = NSSize(width: 520, height: 640)
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: MenuBarMonitor(service: service, quotaService: quotaService, captureService: captureService)
                .environmentObject(localizer)
        )
        self.popover = popover
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        installDismissMonitors(anchor: button)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            quotaService.start()
            captureService.start()
        }
    }

    private func closePopover() {
        singleClickWorkItem?.cancel()
        removeDismissMonitors()
        popover?.close()
        popover?.contentViewController = nil
        popover = nil
    }

    func popoverDidClose(_ notification: Notification) {
        removeDismissMonitors()
        popover?.contentViewController = nil
        popover = nil
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
        guard let popoverWindow = popover?.contentViewController?.view.window else { return false }
        return event.window === popoverWindow
    }

    private func eventIsInsideStatusButton(_ event: NSEvent, anchor: NSStatusBarButton?) -> Bool {
        guard let anchor, event.window === anchor.window else { return false }
        let point = anchor.convert(event.locationInWindow, from: nil)
        return anchor.bounds.contains(point)
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
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title.contains("TraceFence") || $0.title.contains("AgentGuard") || (!$0.title.isEmpty && $0.canBecomeMain) }) {
            window.makeKeyAndOrderFront(nil)
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
