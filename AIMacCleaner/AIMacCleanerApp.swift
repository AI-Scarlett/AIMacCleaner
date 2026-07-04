import SwiftUI
import AppKit
import Darwin

@main
struct AIMacCleanerApp: App {
    @StateObject private var service = ScannerService()
    @StateObject private var localizer = Localizer()
    @StateObject private var agentRegistry = AgentRegistry()
    @StateObject private var sessionsViewModel = SessionsViewModel()
    @StateObject private var conversationWatcher = ConversationWatcher()
    @StateObject private var overviewStore = AgentMonitorOverviewStore()
    @StateObject private var licenseService = DirectLicenseService.shared
    @StateObject private var updateService = DirectUpdateService.shared
    @StateObject private var providerQuotaService = ProviderQuotaService()
    @StateObject private var captureShelfService = CaptureShelfService.shared
    @StateObject private var menuBarController = MenuBarStatusController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("monitorEnabled") private var monitorEnabled = false
    @AppStorage("operationMonitorEnabled") private var operationMonitorEnabled = false
    @AppStorage("sensorMonitorEnabled") private var sensorMonitorEnabled = false
    @AppStorage("menuBarMonitorEnabled") private var menuBarMonitorEnabled = true
    @AppStorage("quitBehavior") private var quitBehavior: String = "quitAll"
    @AppStorage("networkMode") private var networkMode = "internet"

    init() {
        let defaults = UserDefaults.standard
        let palette = defaults.string(forKey: "colorPalette")
        if palette == nil || palette == AppColorPalette.aurora.rawValue {
            defaults.set(AppColorPalette.porcelain.rawValue, forKey: "colorPalette")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(overviewStore: overviewStore)
                .environmentObject(service)
                .environmentObject(localizer)
                .environmentObject(agentRegistry)
                .environmentObject(sessionsViewModel)
                .environmentObject(conversationWatcher)
                .environmentObject(licenseService)
                .environmentObject(updateService)
                .environmentObject(captureShelfService)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    appDelegate.service = service
                    appDelegate.overviewStore = overviewStore
                    service.localizer = localizer
                    appDelegate.configureAgentCenterContext(
                        sessionsViewModel: sessionsViewModel,
                        agentRegistry: agentRegistry,
                        conversationWatcher: conversationWatcher,
                        localizer: localizer
                    )
                    overviewStore.startBackgroundRefresh()
                    providerQuotaService.start()
                    captureShelfService.start()
                    NSApp.setActivationPolicy(.regular)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [service, licenseService] in
                        licenseService.refreshTrialState()
                        if monitorEnabled, licenseService.canUseProFeatures {
                            service.startMonitoring()
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [updateService] in
                        guard networkMode == "internet" else { return }
                        Task { await updateService.checkForUpdates() }
                    }
                    menuBarController.configure(
                        service: service,
                        quotaService: providerQuotaService,
                        captureService: captureShelfService,
                        localizer: localizer,
                        isEnabled: menuBarMonitorEnabled
                    )
                }
                .onChange(of: menuBarMonitorEnabled) { newValue in
                    menuBarController.setEnabled(newValue)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 700)
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
    private var fallbackWindow: NSWindow?
    private var fallbackService: ScannerService?
    private var fallbackLocalizer: Localizer?
    private var fallbackAgentRegistry: AgentRegistry?
    private var fallbackSessionsViewModel: SessionsViewModel?
    private var fallbackConversationWatcher: ConversationWatcher?
    private var fallbackOverviewStore: AgentMonitorOverviewStore?
    private var forceTerminateOnce = false
    var service: ScannerService?
    var overviewStore: AgentMonitorOverviewStore?
    var hookServer: HookServer?
    var sessionStore: SessionStore?
    var soundEngine: SoundEngine?
    var webhookNotifier: WebhookNotifier?
    var remoteManager: RemoteManager?
    var globalShortcutService: GlobalShortcutService?
    var networkMonitor: NetworkMonitor?
    var bridgeBinary: BridgeBinary?
    private var sessionsVM: SessionsViewModel?
    private weak var agentRegistryContext: AgentRegistry?
    private weak var conversationWatcherContext: ConversationWatcher?
    private weak var localizerContext: Localizer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        terminateDuplicateTraceFenceInstances()
        DispatchQueue.main.async { [weak self] in
            self?.setupWindowDelegate()
            self?.ensureLaunchSurfaceVisible(reason: "launch")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            self?.ensureLaunchSurfaceVisible(reason: "launch-retry-1")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.ensureLaunchSurfaceVisible(reason: "launch-retry-2")
        }
    }

    private func terminateDuplicateTraceFenceInstances() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) where app.processIdentifier != currentPID {
            print("[TraceFence] Terminating duplicate TraceFence instance pid=\(app.processIdentifier)")
            app.terminate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                if !app.isTerminated {
                    print("[TraceFence] Force terminating duplicate TraceFence instance pid=\(app.processIdentifier)")
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
            if window.title.contains("AgentWatch") || window.title.contains("AgentGuard") || window.title.contains("TraceFence") || window.className.contains("Window") {
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

    @MainActor
    private func ensureLaunchSurfaceVisible(reason: String) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)

        if let window = bestMainWindow() {
            mainWindow = window
            window.delegate = WindowDelegate.shared
            show(window: window, reason: reason)
            return
        }

        createFallbackMainWindow(reason: reason)
    }

    @MainActor
    private func bestMainWindow() -> NSWindow? {
        if let mainWindow, mainWindow.contentView != nil {
            return mainWindow
        }

        return NSApp.windows.first { window in
            guard window.contentView != nil,
                  !window.isFloatingPanel,
                  !window.isMiniaturized,
                  window.canBecomeMain else {
                return false
            }
            return true
        }
    }

    @MainActor
    private func show(window: NSWindow, reason: String) {
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("[TraceFence] Launch surface visible via \(reason)")
    }

    @MainActor
    private func createFallbackMainWindow(reason: String) {
        if let fallbackWindow {
            mainWindow = fallbackWindow
            show(window: fallbackWindow, reason: "\(reason)-existing-fallback")
            return
        }

        let service = self.service ?? fallbackService ?? ScannerService()
        let localizer = localizerContext ?? fallbackLocalizer ?? Localizer()
        let agentRegistry = agentRegistryContext ?? fallbackAgentRegistry ?? AgentRegistry()
        let sessionsViewModel = sessionsVM ?? fallbackSessionsViewModel ?? SessionsViewModel()
        let conversationWatcher = conversationWatcherContext ?? fallbackConversationWatcher ?? ConversationWatcher()
        let overviewStore = self.overviewStore ?? fallbackOverviewStore ?? AgentMonitorOverviewStore()

        fallbackService = service
        fallbackLocalizer = localizer
        fallbackAgentRegistry = agentRegistry
        fallbackSessionsViewModel = sessionsViewModel
        fallbackConversationWatcher = conversationWatcher
        fallbackOverviewStore = overviewStore

        self.service = service
        self.overviewStore = overviewStore
        service.localizer = localizer
        overviewStore.startBackgroundRefresh()
        configureAgentCenterContext(
            sessionsViewModel: sessionsViewModel,
            agentRegistry: agentRegistry,
            conversationWatcher: conversationWatcher,
            localizer: localizer
        )

        let rootView = ContentView(overviewStore: overviewStore)
            .environmentObject(service)
            .environmentObject(localizer)
            .environmentObject(agentRegistry)
            .environmentObject(sessionsViewModel)
            .environmentObject(conversationWatcher)
            .environmentObject(DirectLicenseService.shared)
            .environmentObject(DirectUpdateService.shared)
            .frame(minWidth: 960, minHeight: 640)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TraceFence"
        window.contentView = NSHostingView(rootView: rootView)
        window.delegate = WindowDelegate.shared
        window.setFrameAutosaveName("TraceFenceMainWindow")

        fallbackWindow = window
        mainWindow = window
        show(window: window, reason: "\(reason)-fallback")

    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        if let window = mainWindow {
            window.makeKeyAndOrderFront(nil)
        } else if let window = sender.windows.first(where: { !$0.title.isEmpty && $0.className.contains("Window") }) {
            mainWindow = window
            window.makeKeyAndOrderFront(nil)
        } else {
            Task { @MainActor in
                self.ensureLaunchSurfaceVisible(reason: "reopen")
            }
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
        sessionsViewModel: SessionsViewModel,
        agentRegistry: AgentRegistry,
        conversationWatcher: ConversationWatcher,
        localizer: Localizer
    ) {
        sessionsVM = sessionsViewModel
        agentRegistryContext = agentRegistry
        conversationWatcherContext = conversationWatcher
        localizerContext = localizer
    }

    @MainActor
    func initializeAgentCenterServices() {
        guard let sessionsViewModel = sessionsVM,
              let agentRegistry = agentRegistryContext,
              let conversationWatcher = conversationWatcherContext else { return }

        if hookServer != nil {
            return
        }

        let server = HookServer()
        let store = SessionStore()
        let sound = SoundEngine()
        let webhook = WebhookNotifier()
        let remote = RemoteManager()
        let bridge = BridgeBinary()

        hookServer = server
        sessionStore = store
        soundEngine = sound
        webhookNotifier = webhook
        remoteManager = remote
        bridgeBinary = bridge

        Task {
            await remote.setup(hookServer: server)
        }

        sessionsViewModel.setup(sessionStore: store)
        conversationWatcher.setupExternalApprovalBridge(sessionStore: store)

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
                sessionsViewModel.startObserving()

                let conversationDirs = ConversationWatcher.buildConversationDirectories(
                    from: AgentIntegrationProfile.allProfiles
                )
                if !conversationDirs.isEmpty {
                    conversationWatcher.startWatching(directories: conversationDirs)
                }

                print("[TraceFence] Agent Center services initialized")
            } catch {
                print("[TraceFence] Failed to start HookServer: \(error)")
            }
        }

        setupGlobalShortcuts()
        setupNetworkMonitoring()
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
            await shortcutService.register(action: .showSessions) { [weak self] in
                self?.mainWindow?.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
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
                print("[TraceFence] Network event: \(event)")
            }
        }
    }

    @MainActor
    func cleanupAgentCenterServices() {
        Task {
            await hookServer?.stop()
        }
        sessionsVM?.stopObserving()
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
