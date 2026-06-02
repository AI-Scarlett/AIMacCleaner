import SwiftUI
import AppKit
import Combine
import Darwin

@main
struct AIMacCleanerApp: App {
    @StateObject private var service = ScannerService()
    @StateObject private var localizer = Localizer()
    @StateObject private var agentRegistry = AgentRegistry()
    @StateObject private var islandViewModel = IslandViewModel()
    @StateObject private var sessionsViewModel = SessionsViewModel()
    @StateObject private var conversationWatcher = ConversationWatcher()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("monitorEnabled") private var monitorEnabled = false
    @AppStorage("operationMonitorEnabled") private var operationMonitorEnabled = false
    @AppStorage("sensorMonitorEnabled") private var sensorMonitorEnabled = false
    @AppStorage("menuBarMonitorEnabled") private var menuBarMonitorEnabled = true
    @AppStorage("quitBehavior") private var quitBehavior: String = "quitAll"
    @AppStorage("agentCenterIntegrationEnabled") private var agentCenterIntegrationEnabled = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
                .environmentObject(localizer)
                .environmentObject(agentRegistry)
                .environmentObject(islandViewModel)
                .environmentObject(sessionsViewModel)
                .environmentObject(conversationWatcher)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    appDelegate.service = service
                    service.localizer = localizer
                    appDelegate.configureAgentCenterContext(
                        islandViewModel: islandViewModel,
                        sessionsViewModel: sessionsViewModel,
                        agentRegistry: agentRegistry,
                        conversationWatcher: conversationWatcher,
                        localizer: localizer
                    )
                    NSApp.setActivationPolicy(.regular)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [service] in
                        if monitorEnabled { service.startMonitoring() }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        if agentCenterIntegrationEnabled {
                            appDelegate.initializeAgentCenterServices()
                        }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .agentCenterShouldInitialize)) { _ in
                    guard agentCenterIntegrationEnabled else { return }
                    appDelegate.initializeAgentCenterServices()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 700)

        MenuBarExtra {
            if menuBarMonitorEnabled {
                MenuBarMonitor(service: service)
                    .environmentObject(localizer)
                    .environmentObject(islandViewModel)
            } else {
                Text(localizer.menuBarMonitorClosed)
                    .padding()
            }
        } label: {
            menuBarLabel
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if let disk = service.diskInfo {
            HStack(spacing: 3) {
                MenuBarShieldEyeIcon()
                Text(String(format: "%.0f%%", 100.0 - disk.usedPct))
            }
        } else {
            MenuBarShieldEyeIcon()
        }
    }
}

struct MenuBarShieldEyeIcon: View {
    var color: Color = .primary

    var body: some View {
        Image(nsImage: MenuBarShieldEyeTemplateImage.shared)
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .frame(width: 18, height: 18)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
}

enum MenuBarShieldEyeTemplateImage {
    static let shared: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let shield = NSBezierPath()
        shield.move(to: NSPoint(x: 9, y: 16.2))
        shield.curve(to: NSPoint(x: 14.6, y: 12.7),
                     controlPoint1: NSPoint(x: 10.9, y: 14.8),
                     controlPoint2: NSPoint(x: 12.4, y: 13.5))
        shield.curve(to: NSPoint(x: 15.0, y: 11.8),
                     controlPoint1: NSPoint(x: 14.9, y: 12.6),
                     controlPoint2: NSPoint(x: 15.0, y: 12.3))
        shield.line(to: NSPoint(x: 15.0, y: 7.2))
        shield.curve(to: NSPoint(x: 9, y: 1.5),
                     controlPoint1: NSPoint(x: 15.0, y: 4.5),
                     controlPoint2: NSPoint(x: 12.9, y: 2.6))
        shield.curve(to: NSPoint(x: 3.0, y: 7.2),
                     controlPoint1: NSPoint(x: 5.1, y: 2.6),
                     controlPoint2: NSPoint(x: 3.0, y: 4.5))
        shield.line(to: NSPoint(x: 3.0, y: 11.8))
        shield.curve(to: NSPoint(x: 3.4, y: 12.7),
                     controlPoint1: NSPoint(x: 3.0, y: 12.3),
                     controlPoint2: NSPoint(x: 3.1, y: 12.6))
        shield.curve(to: NSPoint(x: 9, y: 16.2),
                     controlPoint1: NSPoint(x: 5.6, y: 13.5),
                     controlPoint2: NSPoint(x: 7.1, y: 14.8))
        shield.lineWidth = 2.2
        shield.lineJoinStyle = .round
        shield.lineCapStyle = .round
        NSColor.black.setFill()
        shield.stroke()

        let eye = NSBezierPath()
        eye.move(to: NSPoint(x: 4.2, y: 9.0))
        eye.curve(to: NSPoint(x: 13.8, y: 9.0),
                  controlPoint1: NSPoint(x: 6.3, y: 12.8),
                  controlPoint2: NSPoint(x: 11.7, y: 12.8))
        eye.curve(to: NSPoint(x: 4.2, y: 9.0),
                  controlPoint1: NSPoint(x: 11.7, y: 5.2),
                  controlPoint2: NSPoint(x: 6.3, y: 5.2))
        eye.close()
        NSColor.black.setFill()
        eye.fill()

        NSGraphicsContext.current?.compositingOperation = .clear
        NSBezierPath(ovalIn: NSRect(x: 6.4, y: 6.4, width: 5.2, height: 5.2)).fill()

        NSGraphicsContext.current?.compositingOperation = .sourceOver
        NSColor.black.setStroke()
        let prompt = NSBezierPath()
        prompt.move(to: NSPoint(x: 7.7, y: 10.4))
        prompt.line(to: NSPoint(x: 9.4, y: 9.0))
        prompt.line(to: NSPoint(x: 7.7, y: 7.6))
        prompt.lineWidth = 1.15
        prompt.lineCapStyle = .round
        prompt.lineJoinStyle = .round
        prompt.stroke()

        let underscore = NSBezierPath()
        underscore.move(to: NSPoint(x: 9.9, y: 7.4))
        underscore.line(to: NSPoint(x: 11.5, y: 7.4))
        underscore.lineWidth = 1.15
        underscore.lineCapStyle = .round
        underscore.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}

extension Notification.Name {
    static let agentCenterShouldInitialize = Notification.Name("agentCenterShouldInitialize")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var forceTerminateOnce = false
    var service: ScannerService?
    var hookServer: HookServer?
    var sessionStore: SessionStore?
    var soundEngine: SoundEngine?
    var webhookNotifier: WebhookNotifier?
    var remoteManager: RemoteManager?
    var displayController: DisplayController?
    var globalShortcutService: GlobalShortcutService?
    var networkMonitor: NetworkMonitor?
    var islandWindowController: IslandWindowController?
    var bridgeBinary: BridgeBinary?
    private var islandVM: IslandViewModel?
    private var sessionsVM: SessionsViewModel?
    private weak var agentRegistryContext: AgentRegistry?
    private weak var conversationWatcherContext: ConversationWatcher?
    private weak var localizerContext: Localizer?
    private var islandCancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        terminateDuplicateAgentGuardInstances()
        DispatchQueue.main.async { [weak self] in
            self?.setupWindowDelegate()
        }
    }

    private func terminateDuplicateAgentGuardInstances() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) where app.processIdentifier != currentPID {
            print("[AgentGuard] Terminating duplicate AgentGuard instance pid=\(app.processIdentifier)")
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !app.isTerminated {
                    print("[AgentGuard] Force terminating duplicate AgentGuard instance pid=\(app.processIdentifier)")
                    app.forceTerminate()
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        Task { @MainActor in
            cleanupAgentCenterServices()
        }
        service?.operationMonitor.saveRecords()
        service?.guardFeature.saveHourlyStats()
        service?.guardFeature.saveAlerts()
        service?.guardFeature.saveCommandRules()
    }

    private func setupWindowDelegate() {
        for window in NSApp.windows {
            if window.title.contains("AgentWatch") || window.title.contains("AgentGuard") || window.className.contains("Window") {
                mainWindow = window
            }
            window.delegate = WindowDelegate.shared
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let window = notification.object as? NSWindow {
                self?.mainWindow = window
                if window.delegate == nil {
                    window.delegate = WindowDelegate.shared
                }
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else if let window = sender.windows.first(where: { !$0.title.isEmpty && $0.className.contains("Window") }) {
            mainWindow = window
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if forceTerminateOnce {
            forceTerminateOnce = false
            return .terminateNow
        }
        let quitBehavior = UserDefaults.standard.string(forKey: "quitBehavior") ?? "quitAll"
        if quitBehavior == "quitAppOnly" || quitBehavior == "quitAppKeepMenu" {
            hideDesktopWindows()
            return .terminateCancel
        }
        return .terminateNow
    }

    @MainActor
    func requestFullQuit() {
        forceTerminateOnce = true
        service?.operationMonitor.saveRecords()
        service?.guardFeature.saveHourlyStats()
        service?.guardFeature.saveAlerts()
        cleanupAgentCenterServices()
        NSApp.terminate(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            Darwin.exit(0)
        }
    }

    @MainActor
    func requestMenuBarQuit() {
        requestFullQuit()
    }

    func configureAgentCenterContext(
        islandViewModel: IslandViewModel,
        sessionsViewModel: SessionsViewModel,
        agentRegistry: AgentRegistry,
        conversationWatcher: ConversationWatcher,
        localizer: Localizer
    ) {
        islandVM = islandViewModel
        sessionsVM = sessionsViewModel
        agentRegistryContext = agentRegistry
        conversationWatcherContext = conversationWatcher
        localizerContext = localizer
    }

    @MainActor
    func initializeAgentCenterServices() {
        guard hookServer == nil else { return }
        guard let islandViewModel = islandVM,
              let sessionsViewModel = sessionsVM,
              let agentRegistry = agentRegistryContext,
              let conversationWatcher = conversationWatcherContext,
              let localizer = localizerContext else { return }

        let server = HookServer()
        let store = SessionStore()
        let sound = SoundEngine()
        let webhook = WebhookNotifier()
        let remote = RemoteManager()
        let display = DisplayController.shared
        let bridge = BridgeBinary()

        hookServer = server
        sessionStore = store
        soundEngine = sound
        webhookNotifier = webhook
        remoteManager = remote
        displayController = display
        bridgeBinary = bridge

        Task {
            await remote.setup(hookServer: server)
        }

        display.setup(islandViewModel: islandViewModel, localizer: localizer)

        let windowCtrl = IslandWindowController(
            displayController: display,
            islandViewModel: islandViewModel,
            localizer: localizer
        )
        islandWindowController = windowCtrl
        display.attachIslandWindow(windowCtrl.createWindow())

        islandViewModel.setup(hookServer: server, sessionStore: store)
        sessionsViewModel.setup(sessionStore: store)
        conversationWatcher.setupExternalApprovalBridge(sessionStore: store)
        bindIslandDisplay(islandViewModel: islandViewModel, display: display)

        agentRegistry.setHookInstaller(HookInstaller())

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard self?.hookServer === server else { return }
            agentRegistry.refreshAllStatuses()
        }

        Task {
            do {
                await server.setup(
                    sessionStore: store,
                    soundEngine: sound,
                    guardFeature: service?.guardFeature,
                    scannerService: service
                )
                try await server.start()
                islandViewModel.startObserving()
                sessionsViewModel.startObserving()

                let conversationDirs = ConversationWatcher.buildConversationDirectories(
                    from: AgentIntegrationProfile.allProfiles
                )
                if !conversationDirs.isEmpty {
                    conversationWatcher.startWatching(directories: conversationDirs)
                }

                print("[AgentGuard] Agent Center services initialized")
            } catch {
                print("[AgentGuard] Failed to start HookServer: \(error)")
            }
        }

        setupGlobalShortcuts()
        setupNetworkMonitoring()
    }

    @MainActor
    private func bindIslandDisplay(islandViewModel: IslandViewModel, display: DisplayController) {
        islandCancellables.removeAll()

        islandViewModel.$isVisible
            .removeDuplicates()
            .sink { [weak display, weak islandViewModel] visible in
                guard let display = display else { return }
                if visible {
                    display.updateIslandFrame(level: islandViewModel?.displayLevel ?? .compact)
                    display.showIsland()
                } else {
                    display.hideIsland()
                }
            }
            .store(in: &islandCancellables)

        islandViewModel.$displayLevel
            .removeDuplicates()
            .sink { [weak display, weak islandViewModel] level in
                guard let display = display else { return }
                display.updateIslandFrame(level: level)
                if islandViewModel?.isVisible == true {
                    display.showIsland()
                }
            }
            .store(in: &islandCancellables)
    }

    @MainActor
    func refreshAgentStatusesIfReady() {
        guard let agentRegistry = agentRegistryContext else { return }
        agentRegistry.refreshAllStatuses()
    }

    private func setupGlobalShortcuts() {
        let shortcutService = GlobalShortcutService()
        globalShortcutService = shortcutService

        Task {
            await shortcutService.register(action: .toggleIsland) { [weak self] in
                if let display = self?.displayController {
                    if display.isVisible {
                        display.hideIsland()
                    } else {
                        display.showIsland()
                    }
                }
            }

            await shortcutService.register(action: .showSessions) { [weak self] in
                self?.mainWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }

            await shortcutService.register(action: .approveAll) { [weak islandVM = self.islandVM] in
                if let session = islandVM?.currentSession,
                   session.pendingPermission != nil {
                    islandVM?.respondToPermission(.allow)
                }
            }

            await shortcutService.register(action: .denyAll) { [weak islandVM = self.islandVM] in
                if let session = islandVM?.currentSession,
                   session.pendingPermission != nil {
                    islandVM?.respondToPermission(.deny)
                }
            }

            await shortcutService.registerAll()
        }
    }

    private func setupNetworkMonitoring() {
        let monitor = NetworkMonitor()
        networkMonitor = monitor

        if let remote = remoteManager, let webhook = webhookNotifier {
            Task {
                await monitor.setup(remoteManager: remote, webhookNotifier: webhook)
            }
        }

        Task {
            await monitor.startMonitoring { event in
                print("[AgentGuard] Network event: \(event)")
            }
        }
    }

    @MainActor
    func cleanupAgentCenterServices() {
        Task {
            await hookServer?.stop()
        }
        islandVM?.stopObserving()
        sessionsVM?.stopObserving()
        islandWindowController?.cleanup()
        islandCancellables.removeAll()
    }
}

private func hideDesktopWindows() {
    for window in NSApp.windows where !window.isFloatingPanel && window.level != .floating {
        window.orderOut(nil)
    }
    NSApp.setActivationPolicy(.accessory)
}

class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let quitBehavior = UserDefaults.standard.string(forKey: "quitBehavior") ?? "quitAll"
        if quitBehavior == "quitAppOnly" || quitBehavior == "quitAppKeepMenu" {
            hideDesktopWindows()
            return false
        }
        sender.orderOut(nil)
        return false
    }
}
