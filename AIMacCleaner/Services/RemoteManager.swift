import Foundation

actor RemoteManager {
    private var hosts: [RemoteHost] = []
    private var activeSessions: [RemoteSessionState] = []
    private var config: RemoteConfig = RemoteConfig()
    private var alerts: [AgentGuardAlert] = []

    private let hostsPath = NSHomeDirectory() + "/.aimaccleaner_remote_hosts.json"
    private let configPath = NSHomeDirectory() + "/.aimaccleaner_remote_config.json"
    private let alertsPath = NSHomeDirectory() + "/.aimaccleaner_remote_alerts.json"

    weak var hookServer: HookServer?

    init() {
        Task {
            await loadHosts()
            await loadConfig()
            await loadAlerts()
        }
    }

    func setup(hookServer: HookServer) {
        self.hookServer = hookServer
    }

    func getHosts() -> [RemoteHost] {
        hosts
    }

    func getActiveSessions() -> [RemoteSessionState] {
        activeSessions.filter { $0.isActive }
    }

    func getAlerts() -> [AgentGuardAlert] {
        alerts.sorted { $0.timestamp > $1.timestamp }
    }

    func addHost(_ host: RemoteHost) {
        guard !hosts.contains(where: { $0.id == host.id }) else { return }
        var newHost = host
        newHost.lastConnected = Date()
        hosts.append(newHost)
        saveHosts()
    }

    func removeHost(_ id: String) {
        hosts.removeAll { $0.id == id }
        saveHosts()
    }

    func connectToHost(_ hostId: String) async throws -> RemoteSessionState {
        guard hosts.contains(where: { $0.id == hostId }) else {
            throw RemoteError.sshConnectionFailed
        }

        let sessionId = UUID().uuidString
        let session = RemoteSessionState(
            id: sessionId,
            remoteHostId: hostId,
            localSessionId: UUID().uuidString,
            connectedAt: Date(),
            bridgePid: nil,
            tunnelActive: false
        )
        activeSessions.append(session)

        return session
    }

    func disconnectSession(_ sessionId: String) {
        if let idx = activeSessions.firstIndex(where: { $0.id == sessionId }) {
            activeSessions[idx].disconnectedAt = Date()
            activeSessions[idx].tunnelActive = false
        }
    }

    func evalSecurity(_ host: RemoteHost, event: AgentHookEvent) -> SecurityVerdict {
        switch config.securityLevel {
        case .permissive:
            return .safe
        case .standard:
            if config.trustedHosts.contains(host.id) {
                return .safe
            }
            if let fingerprint = host.fingerprint, !fingerprint.isEmpty {
                return .safe
            }
            return .suspicious
        case .strict:
            if config.trustedHosts.contains(host.id) {
                if hostHasValidFingerprint(host) {
                    return .safe
                }
                return .suspicious
            }
            return .dangerous
        }
    }

    func forwardEventToRemote(_ event: AgentHookEvent, session: RemoteSessionState) {
        guard session.tunnelActive else { return }
    }

    func createAlert(hostId: String, verdict: SecurityVerdict, message: String, detail: String?) {
        let alert = AgentGuardAlert(
            id: UUID().uuidString,
            remoteHostId: hostId,
            timestamp: Date(),
            verdict: verdict,
            message: message,
            detail: detail
        )
        alerts.insert(alert, at: 0)
        if alerts.count > 200 {
            alerts = Array(alerts.prefix(200))
        }
        saveAlerts()
    }

    func dismissAlert(_ id: String) {
        if let idx = alerts.firstIndex(where: { $0.id == id }) {
            alerts[idx].dismissed = true
            saveAlerts()
        }
    }

    func updateConfig(_ newConfig: RemoteConfig) {
        config = newConfig
        saveConfig()
    }

    func getConfig() -> RemoteConfig {
        config
    }

    func trustHost(_ hostId: String) {
        if !config.trustedHosts.contains(hostId) {
            config.trustedHosts.append(hostId)
            saveConfig()
        }
    }

    func untrustHost(_ hostId: String) {
        config.trustedHosts.removeAll { $0 == hostId }
        saveConfig()
    }

    private func hostHasValidFingerprint(_ host: RemoteHost) -> Bool {
        guard let fp = host.fingerprint, !fp.isEmpty else { return false }
        return fp.count >= 32
    }

    private func loadHosts() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: hostsPath)),
              let decoded = try? JSONDecoder().decode([RemoteHost].self, from: data) else { return }
        hosts = decoded
    }

    private func saveHosts() {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        try? data.write(to: URL(fileURLWithPath: hostsPath))
    }

    private func loadConfig() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let decoded = try? JSONDecoder().decode(RemoteConfig.self, from: data) else { return }
        config = decoded
    }

    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: URL(fileURLWithPath: configPath))
    }

    private func loadAlerts() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: alertsPath)),
              let decoded = try? JSONDecoder().decode([AgentGuardAlert].self, from: data) else { return }
        alerts = decoded
    }

    private func saveAlerts() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        try? data.write(to: URL(fileURLWithPath: alertsPath))
    }
}
