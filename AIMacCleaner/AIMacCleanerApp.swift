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
    @StateObject private var marketplaceCatalogService = TraceFenceMarketplaceCatalogService.shared
    @StateObject private var pluginEntitlementService = TraceFencePluginEntitlementService.shared
    @StateObject private var updateService = DirectUpdateService.shared
    @StateObject private var iOSRemoteGatewayService = IOSRemoteControlGatewayService.shared
    @StateObject private var providerQuotaService = ProviderQuotaService()
    @StateObject private var agentUsageInsightsService = AgentUsageInsightsService.shared
    @StateObject private var captureShelfService = CaptureShelfService.shared
    @StateObject private var artifactSidecarController = ArtifactSidecarController.shared
    @StateObject private var menuBarController = MenuBarStatusController()
    @StateObject private var touchBarQuotaController = TouchBarQuotaController()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("monitorEnabled") private var monitorEnabled = false
    @AppStorage("operationMonitorEnabled") private var operationMonitorEnabled = false
    @AppStorage("sensorMonitorEnabled") private var sensorMonitorEnabled = false
    @AppStorage("menuBarMonitorEnabled") private var menuBarMonitorEnabled = true
    @AppStorage("quitBehavior") private var quitBehavior: String = "quitAll"
    @AppStorage("networkMode") private var networkMode = "internet"
    @AppStorage("automaticUpdateChecksEnabled") private var automaticUpdateChecksEnabled = true

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--tracefence-quota-self-test") {
            let failures = ProviderQuotaService.debugQuotaSelfTestFailures()
            let payload: [String: Any] = [
                "succeeded": failures.isEmpty,
                "failures": failures
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(failures.isEmpty ? 0 : 2)
        }
        if ProcessInfo.processInfo.arguments.contains("--tracefence-touchbar-self-test") {
            let failures = TouchBarQuotaController.debugSelfTestFailures()
            let payload: [String: Any] = [
                "succeeded": failures.isEmpty,
                "touchBarCapableMac": TouchBarQuotaController.isTouchBarCapableMac,
                "failures": failures
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(failures.isEmpty ? 0 : 2)
        }
        if ProcessInfo.processInfo.arguments.contains("--tracefence-claude-quota-probe") {
            let result = ProviderQuotaService.debugClaudeDesktopQuotaProbe()
            let windows: [[String: Any]] = (result.snapshot?.windows ?? []).map { window in
                [
                    "id": window.id,
                    "title": window.title,
                    "usedPercent": window.usedPercent,
                    "windowMinutes": window.windowMinutes as Any? ?? NSNull(),
                    "hasResetDate": window.resetsAt != nil
                ]
            }
            let payload: [String: Any] = [
                "succeeded": result.snapshot != nil,
                "provider": result.snapshot?.providerName as Any? ?? NSNull(),
                "source": result.snapshot?.source as Any? ?? NSNull(),
                "diagnostic": result.diagnostic as Any? ?? NSNull(),
                "windows": windows
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(result.snapshot == nil ? 2 : 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--tracefence-provider-quota-probe") {
            let snapshots: [[String: Any]] = ProviderQuotaService.debugProviderQuotaProbe().map { snapshot in
                [
                    "id": snapshot.id,
                    "provider": snapshot.providerName,
                    "source": snapshot.source,
                    "readable": snapshot.quotaReadSucceeded,
                    "windows": snapshot.windows.map { window in
                        [
                            "id": window.id,
                            "title": window.title,
                            "usedPercent": window.usedPercent,
                            "windowMinutes": window.windowMinutes as Any? ?? NSNull(),
                            "hasResetDate": window.resetsAt != nil
                        ]
                    }
                ]
            }
            if let data = try? JSONSerialization.data(withJSONObject: ["snapshots": snapshots], options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(0)
        }
        if ProcessInfo.processInfo.arguments.contains("--tracefence-menubar-tab-probe") {
            let failures = MenuBarMonitor.debugTabSelectionSelfTestFailures()
            let payload: [String: Any] = [
                "menuBarTabSelfTestFailures": failures,
                "succeeded": failures.isEmpty
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(failures.isEmpty ? 0 : 2)
        }
        if ProcessInfo.processInfo.arguments.contains("--tracefence-agent-usage-probe")
            || ProcessInfo.processInfo.arguments.contains("--tracefence-agent-usage-complete-probe") {
            let completePendingBackfill = ProcessInfo.processInfo.arguments.contains("--tracefence-agent-usage-complete-probe")
            let probe = AgentUsageInsightsService.debugRunLocalUsageProbe(
                timeout: 180,
                completePendingBackfill: completePendingBackfill
            )
            let quotaFailures = ProviderQuotaService.debugQuotaSelfTestFailures()
            let taskCatalogFailures = ArtifactShelfService.debugTaskCatalogSelfTestFailures()
            let menuBarTabFailures = MenuBarMonitor.debugTabSelectionSelfTestFailures()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(probe) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            if !quotaFailures.isEmpty || !taskCatalogFailures.isEmpty || !menuBarTabFailures.isEmpty,
               let data = try? JSONSerialization.data(withJSONObject: [
                   "quotaSelfTestFailures": quotaFailures,
                   "taskCatalogSelfTestFailures": taskCatalogFailures,
                   "menuBarTabSelfTestFailures": menuBarTabFailures
               ], options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(
                probe.succeeded
                    && probe.selfTestFailures.isEmpty
                    && quotaFailures.isEmpty
                    && taskCatalogFailures.isEmpty
                    && menuBarTabFailures.isEmpty
                    ? 0
                    : 2
            )
        }
        if ProcessInfo.processInfo.arguments.contains("--tracefence-pricing-probe") {
            let report = AgentUsagePricingCatalogUpdateService.debugRunRemoteProbe()
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if let data = try? encoder.encode(report) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(report.status == .failed ? 2 : 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--tracefence-pricing-self-test") {
            var failures = AgentUsageInsightsService.debugUsageInsightsSelfTestFailures()
            if let fixturePath = ProcessInfo.processInfo.environment["TRACEFENCE_PRICING_FIXTURE_PATH"] {
                do {
                    let data = try Data(contentsOf: URL(fileURLWithPath: fixturePath))
                    _ = try AgentUsageRemotePricingCatalog.decodeAndValidate(data)
                } catch {
                    failures.append("pricing fixture validation failed: \(error.localizedDescription)")
                }
            }
            let payload: [String: Any] = [
                "succeeded": failures.isEmpty,
                "failures": failures,
                "revision": AgentUsageRemotePricingCatalog.revisionSignature
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(failures.isEmpty ? 0 : 2)
        }
        if ProcessInfo.processInfo.arguments.contains("--tracefence-marketplace-self-test") {
            var failures: [String] = []
            let arguments = ProcessInfo.processInfo.arguments
            if let catalogIndex = arguments.firstIndex(of: "--catalog"),
               let signatureIndex = arguments.firstIndex(of: "--signature"),
               catalogIndex + 1 < arguments.count,
               signatureIndex + 1 < arguments.count {
                do {
                    let catalog = try Data(contentsOf: URL(fileURLWithPath: arguments[catalogIndex + 1]))
                    let signature = try Data(contentsOf: URL(fileURLWithPath: arguments[signatureIndex + 1]))
                    failures = TraceFenceMarketplaceCatalogRuntime.debugSelfTestFailures(
                        catalogData: catalog,
                        signatureData: signature
                    )
                } catch {
                    failures.append(error.localizedDescription)
                }
            } else {
                failures.append("Pass --catalog and --signature fixture paths.")
            }
            let payload: [String: Any] = ["succeeded": failures.isEmpty, "failures": failures]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                FileHandle.standardOutput.write(data)
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
            Darwin.exit(failures.isEmpty ? 0 : 2)
        }
#endif
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
        Task { @MainActor in
            guard TraceFenceDistributionPolicy.currentChannel.isDirect else { return }
            let pricingReport = await AgentUsagePricingCatalogUpdateService.shared.refreshIfNeeded()
            if pricingReport.catalogChanged {
                AgentUsageInsightsService.shared.applyPricingCatalogUpdate()
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

    private var shouldStartUsageInsightsAtLaunch: Bool {
        let defaults = UserDefaults.standard
        let style = defaults.string(forKey: MenuBarStatusPreferences.styleKey)
            .flatMap(MenuBarStatusStyle.init(rawValue:)) ?? .classic
        let metric = defaults.string(forKey: MenuBarStatusPreferences.primaryMetricKey)
            .flatMap(MenuBarPrimaryMetric.init(rawValue:)) ?? .tightest
        guard style != .minimal else { return false }
        return style == .detailed || metric == .todayTokens
    }

    var body: some Scene {
        WindowGroup("TraceFence", id: "main") {
            ContentView(overviewStore: overviewStore)
                .environmentObject(service)
                .environmentObject(localizer)
                .environmentObject(agentRegistry)
                .environmentObject(sessionsViewModel)
                .environmentObject(conversationWatcher)
                .environmentObject(licenseService)
                .environmentObject(marketplaceCatalogService)
                .environmentObject(pluginEntitlementService)
                .environmentObject(updateService)
                .environmentObject(providerQuotaService)
                .environmentObject(agentUsageInsightsService)
                .environmentObject(captureShelfService)
                .background(MainWindowOpenActionBridge(appDelegate: appDelegate))
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
                    agentUsageInsightsService.setApplicationActive(NSApp.isActive)
                    if shouldStartUsageInsightsAtLaunch {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            agentUsageInsightsService.startScheduling()
                        }
                    }
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
                        guard automaticUpdateChecksEnabled,
                              networkMode == "internet",
                              TraceFenceDistributionPolicy.currentChannel.isDirect else { return }
                        Task { await updateService.checkForUpdates() }
                    }
                    menuBarController.configure(
                        appDelegate: appDelegate,
                        service: service,
                        quotaService: providerQuotaService,
                        usageInsightsService: agentUsageInsightsService,
                        captureService: captureShelfService,
                        localizer: localizer,
                        isEnabled: menuBarMonitorEnabled
                    )
                    touchBarQuotaController.configure(
                        quotaService: providerQuotaService,
                        overviewStore: overviewStore,
                        appDelegate: appDelegate,
                        localizer: localizer
                    )
                    appDelegate.setupGlobalShortcutsIfNeeded()
                }
                .onChange(of: menuBarMonitorEnabled) { newValue in
                    menuBarController.setEnabled(newValue)
                }
                .onReceive(NotificationCenter.default.publisher(for: .traceFenceEntitlementDidChange)) { notification in
                    if let isActive = notification.userInfo?["canUseProFeatures"] as? Bool {
                        if isActive {
                            startEntitledServices()
                        } else {
                            stopEntitledServices()
                        }
                        return
                    }
                    if notification.userInfo?["pluginID"] as? String == "tracefence.ios-remote" {
                        if TraceFenceEntitlementPolicy.canUsePlugin("tracefence.ios-remote") {
                            iOSRemoteGatewayService.startConfiguredIfNeeded()
                        } else {
                            iOSRemoteGatewayService.stop()
                        }
                    }
                    if notification.userInfo?["pluginID"] as? String == "tracefence.token-usage" {
                        if TraceFenceEntitlementPolicy.canUsePlugin("tracefence.token-usage") {
                            if shouldStartUsageInsightsAtLaunch {
                                agentUsageInsightsService.startScheduling()
                            }
                        } else {
                            agentUsageInsightsService.stopScheduling()
                        }
                    }
                    if notification.userInfo?["pluginID"] as? String == "tracefence.agent-guard",
                       !TraceFenceEntitlementPolicy.canUsePlugin("tracefence.agent-guard") {
                        operationMonitorEnabled = false
                        service.stopOperationMonitor()
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    agentUsageInsightsService.setApplicationActive(true)
                    guard TraceFenceDistributionPolicy.currentChannel.isAppStore else { return }
                    Task { await AppStoreSubscriptionService.shared.refreshEntitlements() }
                }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                    agentUsageInsightsService.setApplicationActive(false)
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

        Settings {
            SettingsView(
                initialTab: TraceFenceDistributionPolicy.currentChannel.isAppStore ? .license : .features
            )
            .environmentObject(service)
            .environmentObject(localizer)
            .environmentObject(licenseService)
            .environmentObject(agentUsageInsightsService)
        }
    }
}

private struct MainWindowOpenActionBridge: View {
    @Environment(\.openWindow) private var openWindow
    let appDelegate: AppDelegate

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                appDelegate.installMainWindowOpenAction(openWindow)
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
    static let traceFenceMainWindowLevelChanged = Notification.Name("traceFenceMainWindowLevelChanged")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
    private var openMainWindowAction: OpenWindowAction?
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
    private var mainWindowPresentationGeneration: UInt64 = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        let pluginSelfTestArguments = ProcessInfo.processInfo.arguments
        if pluginSelfTestArguments.contains("--tracefence-quota-plugin-probe") {
            Task { @MainActor in
                let service = ProviderQuotaService()
                service.start()
                let deadline = Date().addingTimeInterval(60)
                while service.lastRefreshDate == nil, Date() < deadline {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
                let providers = service.snapshots.map { snapshot in
                    [
                        "provider": snapshot.providerName,
                        "readable": snapshot.quotaReadSucceeded,
                        "windowCount": snapshot.windows.count
                    ] as [String: Any]
                }
                let succeeded = service.isQuotaPluginInstalled
                    && service.lastRefreshDate != nil
                    && !service.isRefreshing
                service.stop()
                let payload: [String: Any] = [
                    "succeeded": succeeded,
                    "pluginInstalled": service.isQuotaPluginInstalled,
                    "refreshCompleted": service.lastRefreshDate != nil,
                    "providers": providers,
                    "error": service.quotaPluginErrorMessage as Any? ?? NSNull()
                ]
                if let data = try? JSONSerialization.data(
                    withJSONObject: payload,
                    options: [.prettyPrinted, .sortedKeys]
                ) {
                    FileHandle.standardOutput.write(data)
                    FileHandle.standardOutput.write(Data("\n".utf8))
                }
                Darwin.exit(succeeded ? 0 : 2)
            }
            return
        }
        if pluginSelfTestArguments.contains("--tracefence-plugin-runtime-self-test") {
            Task { @MainActor in
                await TraceFencePluginRuntimeSelfTest.run(arguments: pluginSelfTestArguments)
            }
            return
        }
#endif
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
        TraceFencePluginRuntimeHost.shared.shutdown()
        AgentUsageInsightsService.shared.stopScheduling()
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
        NotificationCenter.default.removeObserver(
            self,
            name: .traceFenceMainWindowLevelChanged,
            object: nil
        )
        ArtifactSidecarController.shared.stop()
        ArtifactShelfService.shared.stop()
        cleanupAgentCenterServices()
        service?.operationMonitor.saveRecords()
        service?.guardFeature.saveHourlyStats()
        service?.guardFeature.saveAlerts()
        service?.guardFeature.saveCommandRules()
    }

    @MainActor
    private func setupWindowDelegate() {
        NotificationCenter.default.removeObserver(
            self,
            name: .traceFenceMainWindowLevelChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowLevelPreferenceDidChange(_:)),
            name: .traceFenceMainWindowLevelChanged,
            object: nil
        )
        reconcileMainWindows()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mainWindowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @MainActor
    func installMainWindowOpenAction(_ action: OpenWindowAction) {
        openMainWindowAction = action
    }

    @MainActor
    @discardableResult
    func presentMainWindow(reason: String) -> Bool {
        mainWindowPresentationGeneration &+= 1
        let generation = mainWindowPresentationGeneration
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)

        reconcileMainWindows()
        if let window = bestMainWindow() {
            show(window: window, reason: reason)
            return true
        }

        guard let openMainWindowAction else {
            if requestNativeMainWindowCreation(reason: reason) {
                scheduleMainWindowPresentationRetry(
                    reason: reason,
                    generation: generation,
                    attempt: 1
                )
                return true
            }
            ensureLaunchSurfaceVisible(reason: reason)
            return false
        }

        mainWindow = nil
        openMainWindowAction(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        scheduleMainWindowPresentationRetry(
            reason: reason,
            generation: generation,
            attempt: 1
        )
        return true
    }

    @MainActor
    private func scheduleMainWindowPresentationRetry(
        reason: String,
        generation: UInt64,
        attempt: Int
    ) {
        guard generation == mainWindowPresentationGeneration, attempt <= 10 else { return }
        let delay = min(0.08 + (Double(attempt) * 0.05), 0.35)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self,
                  generation == self.mainWindowPresentationGeneration else { return }

            self.reconcileMainWindows()
            if let window = self.bestMainWindow() {
                self.show(window: window, reason: reason)
                return
            }

            if attempt == 4 {
                _ = self.requestNativeMainWindowCreation(reason: "\(reason)-retry")
            }
            self.scheduleMainWindowPresentationRetry(
                reason: reason,
                generation: generation,
                attempt: attempt + 1
            )
        }
    }

    @MainActor
    private func requestNativeMainWindowCreation(reason: String) -> Bool {
        let commandMask = NSEvent.ModifierFlags.command
        let menuItem = NSApp.mainMenu?.items
            .compactMap(\.submenu)
            .flatMap(\.items)
            .first { item in
                item.isEnabled &&
                    item.keyEquivalent.lowercased() == "n" &&
                    item.keyEquivalentModifierMask.contains(commandMask) &&
                    item.action != nil
            }

        guard let menuItem, let action = menuItem.action else {
            print("[TraceFence] Native new-window action unavailable via \(reason)")
            return false
        }

        let dispatched = NSApp.sendAction(action, to: menuItem.target, from: menuItem)
        if dispatched {
            NSApp.activate(ignoringOtherApps: true)
            print("[TraceFence] Requested native SwiftUI window via \(reason)")
        }
        return dispatched
    }

    @MainActor
    @objc private func mainWindowLevelPreferenceDidChange(_ notification: Notification) {
        guard let window = bestMainWindow() else { return }
        applyPreferredMainWindowLevel(to: window)
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
        let windows = NSApp.windows
        if let mainWindow,
           windows.contains(where: { $0 === mainWindow }),
           isTraceFenceMainWindow(mainWindow) {
            return mainWindow
        }

        mainWindow = nil
        return windows.first(where: isTraceFenceMainWindow)
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
        applyPreferredMainWindowLevel(to: canonical)

        for duplicate in candidates where duplicate !== canonical {
            print("[TraceFence] Closing duplicate main window number=\(duplicate.windowNumber)")
            duplicate.delegate = nil
            duplicate.orderOut(nil)
            duplicate.close()
        }
    }

    @MainActor
    private func show(window: NSWindow, reason: String) {
        applyPreferredMainWindowLevel(to: window)
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

    @MainActor
    private func applyPreferredMainWindowLevel(to window: NSWindow) {
        let staysOnTop = UserDefaults.standard.bool(forKey: "mainWindowAlwaysOnTop")
        window.level = staysOnTop ? .floating : .normal
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        !presentMainWindow(reason: "reopen")
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
