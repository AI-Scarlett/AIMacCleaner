import SwiftUI
import UserNotifications

@main
struct AIMacCleanerApp: App {
    @StateObject private var service = ScannerService()
    @StateObject private var localizer = Localizer()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @AppStorage("monitorEnabled") private var monitorEnabled = true
    @AppStorage("operationMonitorEnabled") private var operationMonitorEnabled = true
    @AppStorage("sensorMonitorEnabled") private var sensorMonitorEnabled = true
    @AppStorage("menuBarMonitorEnabled") private var menuBarMonitorEnabled = true
    @AppStorage("quitBehavior") private var quitBehavior: String = "quitAll"

    init() {
        DispatchQueue.global(qos: .background).async {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
                .environmentObject(localizer)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.5) { [service] in
                        if monitorEnabled { service.startMonitoring() }
                        if operationMonitorEnabled { service.startOperationMonitor() }
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await service.checkForUpdates()
                    }
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
                Text("菜单栏监控已关闭")
                    .padding()
            }
        } label: {
            if menuBarMonitorEnabled {
                menuBarLabel
            } else {
                Image(systemName: "internaldrive")
            }
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarLabel: some View {
        if let disk = service.diskInfo {
            HStack(spacing: 3) {
                Image(systemName: disk.usedPct > 90 ? "internaldrive.fill" : "internaldrive")
                Text(String(format: "%.0f%%", 100.0 - disk.usedPct))
            }
        } else {
            Image(systemName: "internaldrive")
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        DispatchQueue.main.async { [weak self] in
            self?.setupWindowDelegate()
        }
    }

    private func setupWindowDelegate() {
        for window in NSApp.windows {
            window.delegate = WindowDelegate.shared
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            for window in NSApp.windows where window.delegate == nil {
                window.delegate = WindowDelegate.shared
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let behavior = UserDefaults.standard.string(forKey: "quitBehavior") ?? "quitAll"
        if behavior == "quitAppOnly" {
            sender.unhide(nil)
            sender.setActivationPolicy(.regular)
            for window in sender.windows {
                if window.isVisible || window.isMiniaturized {
                    if window.isMiniaturized { window.deminiaturize(nil) }
                    window.makeKeyAndOrderFront(nil)
                }
            }
        } else {
            if !flag || sender.windows.allSatisfy({ !$0.isVisible }) {
                for window in sender.windows {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            sender.setActivationPolicy(.regular)
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        let behavior = UserDefaults.standard.string(forKey: "quitBehavior") ?? "quitAll"
        return behavior == "quitAll"
    }
}

class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let behavior = UserDefaults.standard.string(forKey: "quitBehavior") ?? "quitAll"
        if behavior == "quitAppOnly" {
            sender.orderOut(nil)
            NSApp.setActivationPolicy(.accessory)
            return false
        }
        return true
    }
}
