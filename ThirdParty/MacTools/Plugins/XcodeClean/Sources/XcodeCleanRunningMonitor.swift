import AppKit
import Foundation

@MainActor
protocol XcodeCleanRunningMonitoring: AnyObject {
    var isXcodeRunning: Bool { get }
    var onStateChange: (() -> Void)? { get set }

    func start()
    func stop()
    func refresh()
}

@MainActor
final class XcodeCleanRunningMonitor: XcodeCleanRunningMonitoring {
    nonisolated static let xcodeBundleIdentifier = "com.apple.dt.Xcode"

    private(set) var isXcodeRunning: Bool = false
    var onStateChange: (() -> Void)?

    private var observers: [NSObjectProtocol] = []
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func start() {
        guard observers.isEmpty else { return }

        let center = workspace.notificationCenter
        let launched = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.xcodeBundleIdentifier
            else { return }
            Task { @MainActor [weak self] in self?.refresh() }
        }

        let terminated = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier == Self.xcodeBundleIdentifier
            else { return }
            Task { @MainActor [weak self] in self?.refresh() }
        }

        observers = [launched, terminated]
        refresh()
    }

    func stop() {
        for observer in observers {
            workspace.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func refresh() {
        let nextValue = workspace.runningApplications.contains { app in
            app.bundleIdentifier == Self.xcodeBundleIdentifier
        }
        guard nextValue != isXcodeRunning else { return }
        isXcodeRunning = nextValue
        onStateChange?()
    }
}
