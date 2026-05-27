import SwiftUI
import AppKit

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
                    NSApp.setActivationPolicy(.regular)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [service] in
                        if monitorEnabled { service.startMonitoring() }
                        UserDefaults.standard.set(true, forKey: "operationMonitorEnabled")
                        service.ensureAgentGuardDataPipeline()
                    }
                    if agentCenterIntegrationEnabled {
                        appDelegate.initializeAgentCenterServices(
                            islandViewModel: islandViewModel,
                            sessionsViewModel: sessionsViewModel,
                            agentRegistry: agentRegistry,
                            conversationWatcher: conversationWatcher,
                            localizer: localizer
                        )
                    }
                }
                .onDisappear {
                    appDelegate.cleanupAgentCenterServices()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 700)

        MenuBarExtra {
            if menuBarMonitorEnabled {
                MenuBarMonitor(service: service)
                    .environmentObject(localizer)
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
    var body: some View {
        ZStack {
            MenuBarShieldShape()
                .stroke(style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                .frame(width: 15, height: 16)

            MenuBarEyeShape()
                .stroke(style: StrokeStyle(lineWidth: 1.45, lineCap: .round, lineJoin: .round))
                .frame(width: 10.5, height: 6.8)
                .offset(y: -0.4)

            Circle()
                .frame(width: 2.3, height: 2.3)
                .offset(y: -0.4)
        }
        .foregroundStyle(.primary.opacity(0.86))
        .frame(width: 17, height: 17)
        .accessibilityHidden(true)
    }
}

struct MenuBarShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.08)
        let rightShoulder = CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.27)
        let rightSide = CGPoint(x: rect.maxX - rect.width * 0.16, y: rect.minY + rect.height * 0.62)
        let bottom = CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.06)
        let leftSide = CGPoint(x: rect.minX + rect.width * 0.16, y: rect.minY + rect.height * 0.62)
        let leftShoulder = CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.27)

        path.move(to: top)
        path.addCurve(to: rightShoulder,
                      control1: CGPoint(x: rect.midX + rect.width * 0.16, y: rect.minY + rect.height * 0.18),
                      control2: CGPoint(x: rect.maxX - rect.width * 0.25, y: rect.minY + rect.height * 0.26))
        path.addCurve(to: rightSide,
                      control1: CGPoint(x: rect.maxX - rect.width * 0.05, y: rect.minY + rect.height * 0.34),
                      control2: CGPoint(x: rect.maxX - rect.width * 0.06, y: rect.minY + rect.height * 0.53))
        path.addCurve(to: bottom,
                      control1: CGPoint(x: rect.maxX - rect.width * 0.22, y: rect.minY + rect.height * 0.77),
                      control2: CGPoint(x: rect.midX + rect.width * 0.17, y: rect.maxY - rect.height * 0.12))
        path.addCurve(to: leftSide,
                      control1: CGPoint(x: rect.midX - rect.width * 0.17, y: rect.maxY - rect.height * 0.12),
                      control2: CGPoint(x: rect.minX + rect.width * 0.22, y: rect.minY + rect.height * 0.77))
        path.addCurve(to: leftShoulder,
                      control1: CGPoint(x: rect.minX + rect.width * 0.06, y: rect.minY + rect.height * 0.53),
                      control2: CGPoint(x: rect.minX + rect.width * 0.05, y: rect.minY + rect.height * 0.34))
        path.addCurve(to: top,
                      control1: CGPoint(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.26),
                      control2: CGPoint(x: rect.midX - rect.width * 0.16, y: rect.minY + rect.height * 0.18))
        return path
    }
}

struct MenuBarEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                      control1: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.minY),
                      control2: CGPoint(x: rect.maxX - rect.width * 0.26, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                      control1: CGPoint(x: rect.maxX - rect.width * 0.26, y: rect.maxY),
                      control2: CGPoint(x: rect.minX + rect.width * 0.26, y: rect.maxY))
        return path
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.setupWindowDelegate()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
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

    @MainActor
    func initializeAgentCenterServices(
        islandViewModel: IslandViewModel,
        sessionsViewModel: SessionsViewModel,
        agentRegistry: AgentRegistry,
        conversationWatcher: ConversationWatcher,
        localizer: Localizer
    ) {
        guard hookServer == nil else { return }

        islandVM = islandViewModel
        sessionsVM = sessionsViewModel

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

        Task {
            if let guardFeature = service?.guardFeature {
                await server.setup(sessionStore: store, soundEngine: sound, guardFeature: guardFeature)
            }
        }

        display.setup(islandViewModel: islandViewModel, localizer: localizer)

        let windowCtrl = IslandWindowController(
            displayController: display,
            islandViewModel: islandViewModel,
            localizer: localizer
        )
        islandWindowController = windowCtrl

        islandViewModel.setup(hookServer: server, sessionStore: store)
        sessionsViewModel.setup(sessionStore: store)

        agentRegistry.setHookInstaller(HookInstaller())

        Task {
            agentRegistry.refreshAllStatuses()
        }

        Task {
            do {
                try await server.start()
                islandViewModel.startObserving()
                sessionsViewModel.startObserving()

                display.showIsland()

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
    }
}

class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let quitBehavior = UserDefaults.standard.string(forKey: "quitBehavior") ?? "quitAll"
        if quitBehavior == "quitAppKeepMenu" {
            sender.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
            return false
        }
        sender.orderOut(nil)
        return false
    }
}
