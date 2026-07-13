import Foundation

final class CoreUpdateCoordinator {
    private let coreDirectory: URL
    private let socketPath: String
    private let currentVersion: String
    private let currentBuild: Int
    private let queue = DispatchQueue(label: "com.tracefence.agent-core.updates", qos: .utility)
    private let stateLock = NSLock()
    private var updateProcess: Process?
    private var timer: DispatchSourceTimer?

    init(coreDirectory: URL, socketPath: String, currentVersion: String, currentBuild: Int) {
        self.coreDirectory = coreDirectory
        self.socketPath = socketPath
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
    }

    func start() {
        guard timer == nil, updaterConfiguration()?["enabled"] as? Bool == true else { return }
        let configured = updaterConfiguration()?["checkIntervalSeconds"] as? NSNumber
        let interval = max(15 * 60, configured?.doubleValue ?? 6 * 60 * 60)
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + 30, repeating: interval, leeway: .seconds(30))
        source.setEventHandler { [weak self] in _ = self?.launchUpdateCheck(force: false) }
        source.resume()
        timer = source
    }

    func status() -> [String: Any] {
        let statusURL = coreDirectory.appendingPathComponent("update-status.json")
        var value: [String: Any] = [:]
        if let data = try? Data(contentsOf: statusURL),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            value = object
        }
        value["updaterInstalled"] = FileManager.default.isExecutableFile(atPath: updaterURL.path)
        value["configured"] = updaterConfiguration() != nil
        value["running"] = isRunning
        value["currentVersion"] = currentVersion
        value["currentBuild"] = currentBuild
        return value
    }

    func requestCheck(force: Bool) -> [String: Any] {
        guard FileManager.default.isExecutableFile(atPath: updaterURL.path) else {
            return ["accepted": false, "error": "core_updater_not_installed"]
        }
        guard FileManager.default.fileExists(atPath: configurationURL.path) else {
            return ["accepted": false, "error": "core_update_not_configured"]
        }
        queue.async { [weak self] in _ = self?.launchUpdateCheck(force: force) }
        return ["accepted": true, "running": true]
    }

    private var updaterURL: URL {
        coreDirectory.appendingPathComponent("TraceFenceAgentCoreUpdater")
    }

    private var configurationURL: URL {
        coreDirectory.appendingPathComponent("update-config.json")
    }

    private var isRunning: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return updateProcess?.isRunning == true
    }

    @discardableResult
    private func launchUpdateCheck(force: Bool) -> Bool {
        stateLock.lock()
        if updateProcess?.isRunning == true {
            stateLock.unlock()
            return false
        }

        let process = Process()
        process.executableURL = updaterURL
        var arguments = [
            "check-and-install",
            "--config", configurationURL.path,
            "--install-root", coreDirectory.path,
            "--socket", socketPath,
            "--current-version", currentVersion,
            "--current-build", String(currentBuild)
        ]
        if force { arguments.append("--force") }
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finished in
            guard let self else { return }
            self.stateLock.lock()
            if self.updateProcess === finished { self.updateProcess = nil }
            self.stateLock.unlock()
        }
        do {
            try process.run()
            updateProcess = process
            stateLock.unlock()
            return true
        } catch {
            updateProcess = nil
            stateLock.unlock()
            return false
        }
    }

    private func updaterConfiguration() -> [String: Any]? {
        guard let data = try? Data(contentsOf: configurationURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}
