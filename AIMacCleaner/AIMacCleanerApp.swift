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
    @StateObject private var iOSRemoteGatewayService = IOSRemoteControlGatewayService.shared
    @StateObject private var providerQuotaService = ProviderQuotaService()
    @StateObject private var captureShelfService = CaptureShelfService.shared
    @StateObject private var artifactSidecarController = ArtifactSidecarController.shared
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
        Task { @MainActor in
            IOSRemoteControlGatewayService.shared.startConfiguredIfNeeded()
            if TraceFenceDistributionPolicy.currentChannel.isDirect {
                _ = await TraceFenceAgentCoreClient.shared.refresh()
            }
        }
    }

    @MainActor
    private func startEntitledServices() {
        overviewStore.startBackgroundRefresh()
        appDelegate.initializeAgentCenterServices()
        iOSRemoteGatewayService.startConfiguredIfNeeded()
    }

    @MainActor
    private func stopEntitledServices() {
        monitorEnabled = false
        operationMonitorEnabled = false
        service.stopMonitoring()
        service.stopOperationMonitor()
        overviewStore.stopBackgroundRefresh()
        appDelegate.cleanupAgentCenterServices()
        iOSRemoteGatewayService.stop()
    }

    var body: some Scene {
        Window("TraceFence", id: "main") {
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
                    appDelegate.adoptOverviewStore(overviewStore)
                    service.localizer = localizer
                    iOSRemoteGatewayService.configure(
                        scannerService: service,
                        sessionStore: appDelegate.sessionStore,
                        hookServer: appDelegate.hookServer,
                        overviewStore: overviewStore
                    )
                    appDelegate.configureAgentCenterContext(
                        sessionsViewModel: sessionsViewModel,
                        agentRegistry: agentRegistry,
                        conversationWatcher: conversationWatcher,
                        localizer: localizer
                    )
                    captureShelfService.start()
                    providerQuotaService.start()
                    if SandboxPaths.isDirectDistribution {
                        artifactSidecarController.start()
                    }
                    AgentGeoMirrorService.shared.refreshEnabledProfileInBackground()
                    AgentGeoMirrorProfileServer.shared.syncWithDefaults()
                    NSApp.setActivationPolicy(.regular)
                    if TraceFenceDistributionPolicy.currentChannel.isDirect {
                        startEntitledServices()
                    }
                    Task { @MainActor in
                        await TraceFenceEntitlementPolicy.refresh()
                        guard TraceFenceEntitlementPolicy.canUseProFeatures else {
                            if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                                stopEntitledServices()
                            }
                            return
                        }
                        startEntitledServices()
                        if monitorEnabled {
                            service.startMonitoring()
                        }
                        if operationMonitorEnabled {
                            service.ensureAgentGuardDataPipeline()
                        }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [updateService] in
#if DEBUG
                        guard !ProcessInfo.processInfo.arguments.contains("--tracefence-capture-ui-test") else { return }
#endif
                        guard networkMode == "internet", TraceFenceDistributionPolicy.currentChannel.isDirect else { return }
                        Task { await updateService.checkForUpdates() }
                    }
                    menuBarController.configure(
                        service: service,
                        quotaService: providerQuotaService,
                        captureService: captureShelfService,
                        localizer: localizer,
                        isEnabled: menuBarMonitorEnabled
                    )
                    appDelegate.setupGlobalShortcutsIfNeeded()
                }
                .onChange(of: menuBarMonitorEnabled) { newValue in
                    menuBarController.setEnabled(newValue)
                }
                .onReceive(NotificationCenter.default.publisher(for: .traceFenceEntitlementDidChange)) { notification in
                    let isActive = notification.userInfo?["canUseProFeatures"] as? Bool == true
                    if isActive {
                        startEntitledServices()
                    } else {
                        stopEntitledServices()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    guard TraceFenceDistributionPolicy.currentChannel.isAppStore else { return }
                    Task { await AppStoreSubscriptionService.shared.refreshEntitlements() }
                }
                .alert(item: $updateService.cliUpdateAlert) { alert in
                    Alert(
                        title: Text(alert.title),
                        message: Text(alert.message),
                        dismissButton: .default(Text(alert.dismissTitle)) {
                            updateService.dismissCLIUpdateAlert()
                        }
                    )
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView(
                initialTab: TraceFenceDistributionPolicy.currentChannel.isAppStore ? .license : .features
            )
            .environmentObject(service)
            .environmentObject(localizer)
            .environmentObject(licenseService)
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
    private var shortcutPressObserver: NSObjectProtocol?
    private var shortcutChangeObserver: NSObjectProtocol?
    private var sessionsVM: SessionsViewModel?
    private weak var agentRegistryContext: AgentRegistry?
    private weak var conversationWatcherContext: ConversationWatcher?
    private weak var localizerContext: Localizer?
    private var didPresentInitialLaunchSurface = false
    private var didRequestLaunchReopen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        terminateDuplicateTraceFenceInstances()
        IOSRemoteControlGatewayService.shared.startConfiguredIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.setupWindowDelegate()
            self?.ensureLaunchSurfaceVisible(reason: "launch")
            self?.scheduleLaunchSurfaceRetry(attempt: 1)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.bootstrapRemoteGatewayContext(reason: "launch")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            self?.bootstrapRemoteGatewayContext(reason: "launch-retry")
        }
#if DEBUG
        let launchArguments = ProcessInfo.processInfo.arguments
        if launchArguments.contains("--tracefence-capture-e2e-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                CaptureShelfService.shared.captureSelectedRegionToClipboard()
            }
        } else if launchArguments.contains("--tracefence-capture-ui-test") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                CaptureShelfService.shared.presentSelectionOverlayForUITest()
            }
        }
#endif
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
        NotificationCenter.default.removeObserver(
            self,
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
        if let shortcutPressObserver {
            NotificationCenter.default.removeObserver(shortcutPressObserver)
            self.shortcutPressObserver = nil
        }
        if let shortcutChangeObserver {
            NotificationCenter.default.removeObserver(shortcutChangeObserver)
            self.shortcutChangeObserver = nil
        }
        Task { @MainActor in
            ArtifactSidecarController.shared.stop()
            ArtifactShelfService.shared.stop()
            cleanupAgentCenterServices()
        }
        service?.operationMonitor.saveRecords()
        service?.guardFeature.saveHourlyStats()
        service?.guardFeature.saveAlerts()
        service?.guardFeature.saveCommandRules()
    }

    @MainActor
    private func setupWindowDelegate() {
        reconcileMainWindows()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @MainActor
    @objc private func mainWindowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              isTraceFenceMainWindow(window) else {
            return
        }
        reconcileMainWindows(preferred: window)
    }

    @MainActor
    private func ensureLaunchSurfaceVisible(reason: String) {
        if reason.hasPrefix("launch-retry"), didPresentInitialLaunchSurface {
            return
        }

        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)

        reconcileMainWindows()
        if let window = bestMainWindow() {
            mainWindow = window
            window.delegate = WindowDelegate.shared
            show(window: window, reason: reason)
            return
        }

        print("[TraceFence] Main window not ready via \(reason); waiting for SwiftUI scene")
    }

    @MainActor
    private func scheduleLaunchSurfaceRetry(attempt: Int) {
        guard !didPresentInitialLaunchSurface, attempt <= 16 else { return }
        let delay = min(0.25 + (Double(attempt) * 0.08), 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.didPresentInitialLaunchSurface else { return }
            self.ensureLaunchSurfaceVisible(reason: "launch-retry-\(attempt)")
            if attempt == 4 {
                self.requestApplicationReopen()
            }
            self.scheduleLaunchSurfaceRetry(attempt: attempt + 1)
        }
    }

    @MainActor
    private func requestApplicationReopen() {
        guard !didRequestLaunchReopen, !didPresentInitialLaunchSurface else { return }
        didRequestLaunchReopen = true

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.createsNewApplicationInstance = false
        NSWorkspace.shared.openApplication(
            at: Bundle.main.bundleURL,
            configuration: configuration
        ) { _, error in
            if let error {
                print("[TraceFence] Could not request main scene reopen: \(error.localizedDescription)")
            }
        }
    }

    @MainActor
    private func bestMainWindow() -> NSWindow? {
        if let mainWindow, isTraceFenceMainWindow(mainWindow) {
            return mainWindow
        }

        return NSApp.windows.first(where: isTraceFenceMainWindow)
    }

    private func isTraceFenceMainWindow(_ window: NSWindow) -> Bool {
        window.contentView != nil &&
            !window.isFloatingPanel &&
            window.canBecomeMain &&
            window.styleMask.contains(.titled) &&
            window.level < .screenSaver &&
            window.title == "TraceFence"
    }

    @MainActor
    private func reconcileMainWindows(preferred: NSWindow? = nil) {
        let candidates = NSApp.windows.filter(isTraceFenceMainWindow)
        guard !candidates.isEmpty else { return }

        let canonical = preferred.flatMap { preferred in
            candidates.first(where: { $0 === preferred })
        } ?? candidates.first(where: \.isKeyWindow)
            ?? candidates.first(where: \.isMainWindow)
            ?? mainWindow.flatMap { current in
                candidates.first(where: { $0 === current })
            }
            ?? candidates[0]

        mainWindow = canonical
        canonical.delegate = WindowDelegate.shared
        canonical.isRestorable = false

        for duplicate in candidates where duplicate !== canonical {
            print("[TraceFence] Closing duplicate main window number=\(duplicate.windowNumber)")
            duplicate.delegate = nil
            duplicate.orderOut(nil)
            duplicate.close()
        }
    }

    @MainActor
    private func show(window: NSWindow, reason: String) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if reason.hasPrefix("launch") {
            didPresentInitialLaunchSurface = true
        }
        print("[TraceFence] Launch surface visible via \(reason)")
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

    @MainActor
    func adoptOverviewStore(_ store: AgentMonitorOverviewStore) {
        if let previous = overviewStore, previous !== store {
            previous.stopBackgroundRefresh()
        }
        if let fallback = fallbackOverviewStore, fallback !== store {
            fallback.stopBackgroundRefresh()
        }
        fallbackOverviewStore = nil
        overviewStore = store
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
    private func bootstrapRemoteGatewayContext(reason: String) {
        let service = self.service ?? fallbackService ?? ScannerService()
        let overviewStore = self.overviewStore ?? fallbackOverviewStore ?? AgentMonitorOverviewStore()
        let sessionsViewModel = sessionsVM ?? fallbackSessionsViewModel ?? SessionsViewModel()
        let agentRegistry = agentRegistryContext ?? fallbackAgentRegistry ?? AgentRegistry()
        let conversationWatcher = conversationWatcherContext ?? fallbackConversationWatcher ?? ConversationWatcher()
        let localizer = localizerContext ?? fallbackLocalizer ?? Localizer()

        self.service = service
        self.overviewStore = overviewStore
        fallbackService = service
        fallbackOverviewStore = overviewStore
        fallbackSessionsViewModel = sessionsViewModel
        fallbackAgentRegistry = agentRegistry
        fallbackConversationWatcher = conversationWatcher
        fallbackLocalizer = localizer

        service.localizer = localizer
        let mayRunEntitledServices = TraceFenceDistributionPolicy.currentChannel.isDirect
            || AppStoreSubscriptionService.shared.canUseProFeatures
        if mayRunEntitledServices {
            overviewStore.startBackgroundRefresh()
            overviewStore.refreshRealtime()
        } else {
            overviewStore.stopBackgroundRefresh()
        }
        configureAgentCenterContext(
            sessionsViewModel: sessionsViewModel,
            agentRegistry: agentRegistry,
            conversationWatcher: conversationWatcher,
            localizer: localizer
        )
        IOSRemoteControlGatewayService.shared.configure(
            scannerService: service,
            sessionStore: sessionStore,
            hookServer: hookServer,
            overviewStore: overviewStore
        )
        if mayRunEntitledServices {
            initializeAgentCenterServices()
        } else {
            IOSRemoteControlGatewayService.shared.stop()
        }
        print("[TraceFence] Remote gateway context bootstrapped via \(reason)")
    }

    @MainActor
    func initializeAgentCenterServices() {
        guard TraceFenceDistributionPolicy.currentChannel.isDirect
                || AppStoreSubscriptionService.shared.canUseProFeatures else {
            cleanupAgentCenterServices()
            return
        }
        guard let sessionsViewModel = sessionsVM,
              let agentRegistry = agentRegistryContext,
              let conversationWatcher = conversationWatcherContext else { return }

        if hookServer != nil {
            if let store = sessionStore {
                sessionsViewModel.setup(sessionStore: store)
                conversationWatcher.setupExternalApprovalBridge(sessionStore: store)
            }
            IOSRemoteControlGatewayService.shared.configure(
                scannerService: service,
                sessionStore: sessionStore,
                hookServer: hookServer,
                overviewStore: overviewStore
            )
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
        IOSRemoteControlGatewayService.shared.configure(
            scannerService: service,
            sessionStore: store,
            hookServer: server,
            overviewStore: overviewStore
        )

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

        Task { [weak self] in
            do {
                guard self?.hookServer === server else { return }
                await server.setup(
                    sessionStore: store,
                    soundEngine: sound,
                    guardFeature: self?.service?.guardFeature,
                    scannerService: self?.service
                )
                guard self?.hookServer === server else { return }
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

        setupGlobalShortcutsIfNeeded()
        setupNetworkMonitoring()
    }

    @MainActor
    func refreshAgentStatusesIfReady() {
        guard let agentRegistry = agentRegistryContext else { return }
        agentRegistry.refreshAllStatuses()
    }

    @MainActor
    func setupGlobalShortcutsIfNeeded() {
        guard globalShortcutService == nil else { return }
        let shortcutService = GlobalShortcutService()
        globalShortcutService = shortcutService

        shortcutPressObserver = NotificationCenter.default.addObserver(
            forName: .traceFenceHotKeyPressed,
            object: nil,
            queue: .main
        ) { [weak shortcutService] notification in
            guard let id = notification.object as? Int else { return }
            Task {
                await shortcutService?.handleHotKeyPressed(id: id)
            }
        }

        shortcutChangeObserver = NotificationCenter.default.addObserver(
            forName: .traceFenceShortcutsChanged,
            object: nil,
            queue: .main
        ) { [weak shortcutService] _ in
            Task {
                await shortcutService?.reloadShortcutsAndRegister()
            }
        }

        Task {
            await shortcutService.register(action: .showSessions) { [weak self] in
                self?.ensureLaunchSurfaceVisible(reason: "shortcut")
            }

            await shortcutService.register(action: .captureSelectedRegion) {
                CaptureShelfService.shared.captureSelectedRegionToClipboard()
            }

            await shortcutService.register(action: .captureFullScreen) {
                CaptureShelfService.shared.captureVisibleScreenToClipboard()
            }

            await shortcutService.register(action: .toggleScreenRecording) {
                CaptureShelfService.shared.toggleScreenRecording()
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
        let activeHookServer = hookServer
        let activeNetworkMonitor = networkMonitor
        hookServer = nil
        sessionStore = nil
        soundEngine = nil
        webhookNotifier = nil
        remoteManager = nil
        networkMonitor = nil
        Task {
            await activeHookServer?.stop()
            await activeNetworkMonitor?.stopMonitoring()
        }
        sessionsVM?.stopObserving()
        conversationWatcherContext?.stopWatching()
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
