import Foundation
import Network

enum NetworkChangeEvent {
    case becameAvailable(interface: String)
    case becameUnavailable
    case interfaceChanged(from: String?, to: String?)
    case remoteHostReachable(host: String)
    case remoteHostUnreachable(host: String)
}

actor NetworkMonitor {
    private var pathMonitor: NWPathMonitor?
    private var isMonitoring = false
    private var currentInterface: String?
    private var isAvailable = false

    weak var remoteManager: RemoteManager?
    weak var webhookNotifier: WebhookNotifier?

    private var monitoredHosts: [String] = []
    private var hostTimers: [String: Timer] = [:]
    private var onChangeCallback: (@MainActor (NetworkChangeEvent) -> Void)?

    func setup(remoteManager: RemoteManager, webhookNotifier: WebhookNotifier) {
        self.remoteManager = remoteManager
        self.webhookNotifier = webhookNotifier
    }

    func startMonitoring(onChange: @MainActor @escaping (NetworkChangeEvent) -> Void) {
        guard !isMonitoring else { return }
        isMonitoring = true
        onChangeCallback = onChange

        pathMonitor = NWPathMonitor()
        pathMonitor?.pathUpdateHandler = { [weak self] path in
            Task { await self?.handlePathUpdate(path) }
        }

        pathMonitor?.start(queue: .global(qos: .background))
    }

    func stopMonitoring() {
        isMonitoring = false
        pathMonitor?.cancel()
        pathMonitor = nil
        hostTimers.values.forEach { $0.invalidate() }
        hostTimers.removeAll()
    }

    func monitorRemoteHost(_ host: String) {
        guard !monitoredHosts.contains(host) else { return }
        monitoredHosts.append(host)
        checkHostReachability(host)
    }

    func stopMonitoringRemoteHost(_ host: String) {
        monitoredHosts.removeAll { $0 == host }
        hostTimers[host]?.invalidate()
        hostTimers.removeValue(forKey: host)
    }

    private func handlePathUpdate(_ path: NWPath) async {
        let wasAvailable = isAvailable
        let previousInterface = currentInterface

        isAvailable = path.status == .satisfied

        let availableInterfaces = path.availableInterfaces
        currentInterface = availableInterfaces.first?.name

        if isAvailable && !wasAvailable {
            await onChangeCallback?(.becameAvailable(interface: currentInterface ?? "unknown"))
        } else if !isAvailable && wasAvailable {
            await onChangeCallback?(.becameUnavailable)
        } else if currentInterface != previousInterface {
            await onChangeCallback?(.interfaceChanged(from: previousInterface, to: currentInterface))
        }

        if isAvailable && wasAvailable {
            for host in monitoredHosts {
                checkHostReachability(host)
            }
        }
    }

    private func checkHostReachability(_ host: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "1", "-t", "3", host]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let isReachable = process.terminationStatus == 0
            Task { @MainActor in
                let event: NetworkChangeEvent = isReachable
                    ? .remoteHostReachable(host: host)
                    : .remoteHostUnreachable(host: host)
                await self.onChangeCallback?(event)
            }
        } catch {
            Task { @MainActor in
                await self.onChangeCallback?(.remoteHostUnreachable(host: host))
            }
        }
    }
}