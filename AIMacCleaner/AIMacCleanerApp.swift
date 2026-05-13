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
                    Task {
                        await service.checkForUpdates()
                        if service.updateAvailable {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                let alert = NSAlert()
                                alert.messageText = "发现新版本 v\(service.latestVersion)"
                                alert.informativeText = "是否立即下载更新？下载完成后将提示您退出应用进行安装。"
                                alert.addButton(withTitle: "立即下载")
                                alert.addButton(withTitle: "稍后提醒")
                                alert.alertStyle = .informational
                                let response = alert.runModal()
                                if response == .alertFirstButtonReturn {
                                    Task { await service.downloadUpdate() }
                                }
                            }
                        }
                    }
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
