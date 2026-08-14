import AppKit
import Foundation

protocol CodexProcessMonitoring: Sendable {
    func isCodexRunning() -> Bool
    func waitUntilCodexStops() async throws
    func fileHasOpenHandle(_ url: URL) -> Bool
}

struct CodexProcessMonitor: CodexProcessMonitoring {
    func isCodexRunning() -> Bool {
        let hasDesktopApp = NSWorkspace.shared.runningApplications.contains { application in
            let identifier = application.bundleIdentifier?.lowercased() ?? ""
            let path = application.bundleURL?.path.lowercased() ?? ""
            return identifier == "com.openai.chat" || path.hasSuffix("/chatgpt.app")
        }
        return hasDesktopApp || processMatches("/Applications/ChatGPT.app/Contents/Resources/codex.*app-server")
    }

    func waitUntilCodexStops() async throws {
        while isCodexRunning() {
            if Task.isCancelled { throw CodexMediaCleanupError.cancelled }
            try await Task.sleep(for: .seconds(2))
        }
        // The app process can disappear just before the app-server child closes
        // its last rollout descriptor. Give the process tree a short drain window.
        try await Task.sleep(for: .seconds(2))
        if isCodexRunning() {
            try await waitUntilCodexStops()
        }
    }

    func fileHasOpenHandle(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        if !FileManager.default.isExecutableFile(atPath: process.executableURL!.path) {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/lsof")
        }
        process.arguments = ["-n", "--", url.path]
        process.standardOutput = Pipe()
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            // Fail closed when lsof itself cannot run.
            return true
        }
    }

    private func processMatches(_ pattern: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", pattern]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}
