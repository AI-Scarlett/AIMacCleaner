import SwiftUI
import UserNotifications

@main
struct AIMacCleanerApp: App {
    @StateObject private var service = ScannerService()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(service)
                .frame(minWidth: 960, minHeight: 640)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 1100, height: 700)

        MenuBarExtra {
            MenuBarMonitor(service: service)
        } label: {
            menuBarLabel
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
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows {
                window.makeKeyAndOrderFront(nil)
            }
            sender.setActivationPolicy(.regular)
        }
        return true
    }
}
