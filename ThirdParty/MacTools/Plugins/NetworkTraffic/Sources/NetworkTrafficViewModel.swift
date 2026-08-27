import AppKit
import Foundation
import MacToolsPluginKit

@MainActor
final class NetworkTrafficViewModel: ObservableObject {
    private enum StorageKey {
        static let mode = "captureMode"
        static let selectedInterface = "selectedInterface"
        static let bpfFilter = "bpfFilter"
        static let favoriteHosts = "favoriteHosts"
        static let blacklistHosts = "blacklistHosts"
        static let alertSound = "alertSound"
    }

    static let allInterfacesID = "*"

    @Published private(set) var interfaces: [NetworkTrafficInterface] = []
    @Published private(set) var captureState: NetworkTrafficCaptureState = .idle
    @Published private(set) var connections: [NetworkTrafficConnection] = []
    @Published private(set) var history: [NetworkTrafficRatePoint] = []
    @Published private(set) var alerts: [NetworkTrafficAlert] = []
    @Published private(set) var totalReceivedBytes: UInt64 = 0
    @Published private(set) var totalSentBytes: UInt64 = 0
    @Published private(set) var totalPackets: UInt64 = 0
    @Published private(set) var retainedRawBytes = 0
    @Published private(set) var rawFramesWereTruncated = false
    @Published private(set) var lastError: String?
    @Published var selectedInterfaceID: String
    @Published var captureMode: NetworkTrafficCaptureMode
    @Published var bpfFilter: String
    @Published var searchText = ""
    @Published var protocolFilter: NetworkTrafficProtocol = .all
    @Published var alertSoundEnabled: Bool

    var onStateChange: (() -> Void)?

    private let storage: PluginStorage
    private let nettopMonitor: NetworkTrafficNettopMonitor
    private let pcapWorker: NetworkTrafficPcapWorker
    private var connectionMap: [String: NetworkTrafficConnection] = [:]
    private var rawFrames: [NetworkTrafficRawFrame] = []
    private var favoriteHosts: Set<String>
    private var blacklistHosts: Set<String>
    private var lastAlertDates: [String: Date] = [:]
    private var pendingReceivedBytes: UInt64 = 0
    private var pendingSentBytes: UInt64 = 0
    private var rateTimer: Timer?
    private var generation = 0

    init(
        storage: PluginStorage = UserDefaultsPluginStorage(pluginID: "network-traffic"),
        nettopMonitor: NetworkTrafficNettopMonitor = NetworkTrafficNettopMonitor(),
        pcapWorker: NetworkTrafficPcapWorker = NetworkTrafficPcapWorker()
    ) {
        self.storage = storage
        self.nettopMonitor = nettopMonitor
        self.pcapWorker = pcapWorker
        self.captureMode = NetworkTrafficCaptureMode(rawValue: storage.string(forKey: StorageKey.mode) ?? "")
            ?? .safeSockets
        self.selectedInterfaceID = storage.string(forKey: StorageKey.selectedInterface) ?? Self.allInterfacesID
        self.bpfFilter = storage.string(forKey: StorageKey.bpfFilter) ?? ""
        self.favoriteHosts = Set(storage.stringArray(forKey: StorageKey.favoriteHosts) ?? [])
        self.blacklistHosts = Set(storage.stringArray(forKey: StorageKey.blacklistHosts) ?? [])
        self.alertSoundEnabled = storage.object(forKey: StorageKey.alertSound) == nil
            ? true
            : storage.bool(forKey: StorageKey.alertSound)
    }

    deinit {
        nettopMonitor.stop()
        pcapWorker.stop()
    }

    var isRunning: Bool {
        if case .running = captureState { return true }
        return false
    }

    var currentReceivedRate: UInt64 { history.last?.receivedBytesPerSecond ?? 0 }
    var currentSentRate: UInt64 { history.last?.sentBytesPerSecond ?? 0 }
    var canExportPCAP: Bool { !rawFrames.isEmpty }
    var blacklistCount: Int { blacklistHosts.count }
    var favoritesCount: Int { favoriteHosts.count }

    var filteredConnections: [NetworkTrafficConnection] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return connections.filter { connection in
            guard protocolFilter == .all || connection.protocolKind == protocolFilter else { return false }
            guard !query.isEmpty else { return true }
            return [
                connection.local.displayText,
                connection.remote.displayText,
                connection.processName,
                connection.serviceName,
                connection.interfaceName,
                connection.state
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    var topHosts: [(host: String, bytes: UInt64, connections: Int)] {
        var values: [String: (UInt64, Int)] = [:]
        for connection in connections {
            let current = values[connection.remote.host] ?? (0, 0)
            values[connection.remote.host] = (current.0 + connection.totalBytes, current.1 + 1)
        }
        return values
            .map { (host: $0.key, bytes: $0.value.0, connections: $0.value.1) }
            .sorted { $0.bytes > $1.bytes }
            .prefix(8)
            .map { $0 }
    }

    var topProcesses: [(name: String, bytes: UInt64)] {
        var values: [String: UInt64] = [:]
        for connection in connections {
            guard let processName = connection.processName, !processName.isEmpty else { continue }
            values[processName, default: 0] += connection.totalBytes
        }
        return values
            .map { (name: $0.key, bytes: $0.value) }
            .sorted { $0.bytes > $1.bytes }
            .prefix(8)
            .map { $0 }
    }

    func refreshInterfaces() {
        do {
            interfaces = try NetworkTrafficPcapWorker.interfaces()
            if selectedInterfaceID != Self.allInterfacesID,
               !interfaces.contains(where: { $0.id == selectedInterfaceID }) {
                selectedInterfaceID = Self.allInterfacesID
                storage.set(selectedInterfaceID, forKey: StorageKey.selectedInterface)
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        notifyStateChanged()
    }

    func setCaptureMode(_ value: NetworkTrafficCaptureMode) {
        guard !captureState.isActive else { return }
        captureMode = value
        if value == .rawPackets, selectedInterfaceID == Self.allInterfacesID {
            selectedInterfaceID = interfaces.first(where: { $0.isUp && !$0.isLoopback })?.id
                ?? interfaces.first?.id
                ?? Self.allInterfacesID
        }
        persistConfiguration()
    }

    func setSelectedInterface(_ id: String) {
        guard !captureState.isActive else { return }
        selectedInterfaceID = id
        persistConfiguration()
    }

    func setBPFFilter(_ value: String) {
        bpfFilter = String(value.prefix(1_024))
        storage.set(bpfFilter, forKey: StorageKey.bpfFilter)
    }

    func setAlertSoundEnabled(_ value: Bool) {
        alertSoundEnabled = value
        storage.set(value, forKey: StorageKey.alertSound)
    }

    func startCapture() {
        guard !captureState.isActive else { return }
        lastError = nil
        captureState = .starting
        generation += 1
        let currentGeneration = generation
        persistConfiguration()
        startRateTimer()

        switch captureMode {
        case .safeSockets:
            do {
                try nettopMonitor.start(
                    sampleHandler: { [weak self] sample in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == currentGeneration else { return }
                            self.ingest(sample: sample)
                        }
                    },
                    failureHandler: { [weak self] message in
                        Task { @MainActor [weak self] in
                            guard let self, self.generation == currentGeneration else { return }
                            self.fail(message)
                        }
                    }
                )
                captureState = .running
            } catch {
                fail(error.localizedDescription)
            }
        case .rawPackets:
            guard selectedInterfaceID != Self.allInterfacesID else {
                fail("原始抓包必须选择一个具体网卡。")
                return
            }
            pcapWorker.startLive(
                interfaceName: selectedInterfaceID,
                filter: bpfFilter.trimmingCharacters(in: .whitespacesAndNewlines),
                started: { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == currentGeneration else { return }
                        self.captureState = .running
                        self.notifyStateChanged()
                    }
                },
                frameHandler: { [weak self] frame in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == currentGeneration else { return }
                        self.ingest(frame: frame)
                    }
                },
                completion: { [weak self] result in
                    Task { @MainActor [weak self] in
                        guard let self, self.generation == currentGeneration else { return }
                        switch result {
                        case .success:
                            if self.captureState.isActive { self.captureState = .idle }
                        case let .failure(error):
                            self.fail(Self.rawCaptureMessage(error.localizedDescription))
                        }
                        self.stopRateTimer()
                        self.notifyStateChanged()
                    }
                }
            )
        }
        notifyStateChanged()
    }

    func stopCapture() {
        guard captureState.isActive else { return }
        generation += 1
        nettopMonitor.stop()
        pcapWorker.stop()
        captureState = .idle
        stopRateTimer()
        flushRatePoint()
        notifyStateChanged()
    }

    func importPCAP(from url: URL) {
        stopCapture()
        clearTraffic(keepingAlerts: true)
        generation += 1
        let currentGeneration = generation
        captureState = .importing
        lastError = nil

        pcapWorker.importFile(
            url: url,
            frameHandler: { [weak self] frame in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    self.ingest(frame: frame)
                }
            },
            completion: { [weak self] result in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == currentGeneration else { return }
                    self.captureState = .idle
                    if case let .failure(error) = result {
                        self.lastError = error.localizedDescription
                    } else if case let .success(count) = result,
                              count > NetworkTrafficLimits.maximumRawFrames {
                        self.rawFramesWereTruncated = true
                    }
                    self.rebuildConnectionList()
                    self.notifyStateChanged()
                }
            }
        )
        notifyStateChanged()
    }

    func exportPCAP(to url: URL) throws {
        let data = try NetworkTrafficPCAPWriter.data(frames: rawFrames)
        try data.write(to: url, options: .atomic)
    }

    func importBlacklist(from text: String) {
        let entries = NetworkTrafficNettopParser.parseBlacklist(text)
        blacklistHosts = Set(entries.map { $0.lowercased() })
        storage.set(Array(blacklistHosts).sorted(), forKey: StorageKey.blacklistHosts)
        refreshFlags()
    }

    func clearBlacklist() {
        blacklistHosts.removeAll()
        storage.set([], forKey: StorageKey.blacklistHosts)
        refreshFlags()
    }

    func toggleFavorite(host: String) {
        let key = host.lowercased()
        if favoriteHosts.contains(key) {
            favoriteHosts.remove(key)
        } else {
            favoriteHosts.insert(key)
        }
        storage.set(Array(favoriteHosts).sorted(), forKey: StorageKey.favoriteHosts)
        refreshFlags()
    }

    func clearTraffic(keepingAlerts: Bool = false) {
        connectionMap.removeAll(keepingCapacity: true)
        connections.removeAll(keepingCapacity: true)
        history.removeAll(keepingCapacity: true)
        rawFrames.removeAll(keepingCapacity: true)
        retainedRawBytes = 0
        rawFramesWereTruncated = false
        totalReceivedBytes = 0
        totalSentBytes = 0
        totalPackets = 0
        pendingReceivedBytes = 0
        pendingSentBytes = 0
        if !keepingAlerts { alerts.removeAll(keepingCapacity: true) }
        notifyStateChanged()
    }

    func dismissAlert(_ id: UUID) {
        alerts.removeAll { $0.id == id }
        notifyStateChanged()
    }

    private func ingest(sample: NetworkTrafficSocketSample) {
        if selectedInterfaceID != Self.allInterfacesID,
           sample.interfaceName != selectedInterfaceID {
            return
        }
        mergeConnection(
            protocolKind: sample.protocolKind,
            local: sample.local,
            remote: sample.remote,
            interfaceName: sample.interfaceName,
            processName: sample.processName,
            state: sample.state,
            receivedBytes: sample.receivedBytes,
            sentBytes: sample.sentBytes,
            packetIncrement: 0
        )
    }

    private func ingest(frame: NetworkTrafficRawFrame) {
        retain(frame: frame)
        guard let packet = NetworkTrafficPacketDecoder.decode(data: frame.data, linkType: frame.linkType) else {
            totalPackets += 1
            return
        }

        let byteCount = UInt64(frame.originalLength)
        let sourceIsLocal = NetworkTrafficHostClassifier.isLocal(packet.source.host)
        let destinationIsLocal = NetworkTrafficHostClassifier.isLocal(packet.destination.host)
        let local: NetworkTrafficEndpoint
        let remote: NetworkTrafficEndpoint
        let receivedBytes: UInt64
        let sentBytes: UInt64

        if sourceIsLocal && !destinationIsLocal {
            local = packet.source
            remote = packet.destination
            receivedBytes = 0
            sentBytes = byteCount
        } else {
            local = packet.destination
            remote = packet.source
            receivedBytes = byteCount
            sentBytes = 0
        }

        mergeConnection(
            protocolKind: packet.protocolKind,
            local: local,
            remote: remote,
            interfaceName: selectedInterfaceID == Self.allInterfacesID ? nil : selectedInterfaceID,
            processName: nil,
            state: nil,
            receivedBytes: receivedBytes,
            sentBytes: sentBytes,
            packetIncrement: 1,
            serviceName: packet.serviceName
        )
    }

    private func mergeConnection(
        protocolKind: NetworkTrafficProtocol,
        local: NetworkTrafficEndpoint,
        remote: NetworkTrafficEndpoint,
        interfaceName: String?,
        processName: String?,
        state: String?,
        receivedBytes: UInt64,
        sentBytes: UInt64,
        packetIncrement: UInt64,
        serviceName: String? = nil
    ) {
        let id = [
            protocolKind.rawValue,
            local.displayText,
            remote.displayText,
            interfaceName ?? "",
            processName ?? ""
        ].joined(separator: "|")
        let now = Date()
        let favorite = favoriteHosts.contains(remote.host.lowercased())
        let blacklisted = blacklistHosts.contains(remote.host.lowercased())

        if var connection = connectionMap[id] {
            connection.receivedBytes &+= receivedBytes
            connection.sentBytes &+= sentBytes
            connection.packetCount &+= packetIncrement
            connection.lastSeen = now
            connection.state = state ?? connection.state
            connection.serviceName = serviceName ?? connection.serviceName
            connection.isFavorite = favorite
            connection.isBlacklisted = blacklisted
            connectionMap[id] = connection
        } else {
            connectionMap[id] = NetworkTrafficConnection(
                id: id,
                protocolKind: protocolKind,
                local: local,
                remote: remote,
                interfaceName: interfaceName,
                processName: processName,
                serviceName: serviceName ?? NetworkTrafficServiceCatalog.name(
                    sourcePort: local.port,
                    destinationPort: remote.port
                ),
                state: state,
                receivedBytes: receivedBytes,
                sentBytes: sentBytes,
                packetCount: packetIncrement,
                firstSeen: now,
                lastSeen: now,
                isFavorite: favorite,
                isBlacklisted: blacklisted
            )
        }

        totalReceivedBytes &+= receivedBytes
        totalSentBytes &+= sentBytes
        totalPackets &+= packetIncrement
        pendingReceivedBytes &+= receivedBytes
        pendingSentBytes &+= sentBytes
        if blacklisted { createBlacklistAlertIfNeeded(host: remote.host, processName: processName) }
        rebuildConnectionList()
    }

    private func rebuildConnectionList() {
        if connectionMap.count > NetworkTrafficLimits.maximumConnections {
            let retained = connectionMap.values
                .sorted { $0.lastSeen > $1.lastSeen }
                .prefix(NetworkTrafficLimits.maximumConnections)
            connectionMap = Dictionary(uniqueKeysWithValues: retained.map { ($0.id, $0) })
        }
        connections = connectionMap.values.sorted {
            if $0.isBlacklisted != $1.isBlacklisted { return $0.isBlacklisted && !$1.isBlacklisted }
            if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
            if $0.totalBytes != $1.totalBytes { return $0.totalBytes > $1.totalBytes }
            return $0.lastSeen > $1.lastSeen
        }
        notifyStateChanged()
    }

    private func retain(frame: NetworkTrafficRawFrame) {
        guard frame.data.count <= NetworkTrafficLimits.maximumRawBytes else {
            rawFramesWereTruncated = true
            return
        }
        rawFrames.append(frame)
        retainedRawBytes += frame.data.count
        while rawFrames.count > NetworkTrafficLimits.maximumRawFrames
            || retainedRawBytes > NetworkTrafficLimits.maximumRawBytes {
            rawFramesWereTruncated = true
            let removed = rawFrames.removeFirst()
            retainedRawBytes -= removed.data.count
        }
    }

    private func refreshFlags() {
        for (id, var connection) in connectionMap {
            connection.isFavorite = favoriteHosts.contains(connection.remote.host.lowercased())
            connection.isBlacklisted = blacklistHosts.contains(connection.remote.host.lowercased())
            connectionMap[id] = connection
        }
        rebuildConnectionList()
    }

    private func createBlacklistAlertIfNeeded(host: String, processName: String?) {
        let key = host.lowercased()
        let now = Date()
        if let lastDate = lastAlertDates[key], now.timeIntervalSince(lastDate) < 60 { return }
        lastAlertDates[key] = now
        let processText = processName.map { "（\($0)）" } ?? ""
        alerts.insert(NetworkTrafficAlert(
            date: now,
            host: host,
            message: "检测到黑名单主机连接 \(host)\(processText)"
        ), at: 0)
        if alerts.count > NetworkTrafficLimits.maximumAlerts {
            alerts.removeLast(alerts.count - NetworkTrafficLimits.maximumAlerts)
        }
        if alertSoundEnabled { NSSound.beep() }
    }

    private func startRateTimer() {
        rateTimer?.invalidate()
        rateTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.flushRatePoint() }
        }
    }

    private func stopRateTimer() {
        rateTimer?.invalidate()
        rateTimer = nil
    }

    private func flushRatePoint() {
        guard pendingReceivedBytes > 0 || pendingSentBytes > 0 || captureState.isActive else { return }
        history.append(NetworkTrafficRatePoint(
            date: Date(),
            receivedBytesPerSecond: pendingReceivedBytes,
            sentBytesPerSecond: pendingSentBytes
        ))
        pendingReceivedBytes = 0
        pendingSentBytes = 0
        if history.count > NetworkTrafficLimits.maximumHistoryPoints {
            history.removeFirst(history.count - NetworkTrafficLimits.maximumHistoryPoints)
        }
        notifyStateChanged()
    }

    private func persistConfiguration() {
        storage.set(captureMode.rawValue, forKey: StorageKey.mode)
        storage.set(selectedInterfaceID, forKey: StorageKey.selectedInterface)
        storage.set(bpfFilter, forKey: StorageKey.bpfFilter)
    }

    private func fail(_ message: String) {
        nettopMonitor.stop()
        pcapWorker.stop()
        stopRateTimer()
        lastError = message
        captureState = .failed(message)
        notifyStateChanged()
    }

    private func notifyStateChanged() {
        onStateChange?()
    }

    private static func rawCaptureMessage(_ message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("permission denied") || lowercased.contains("cannot open bpf") {
            return "macOS 拒绝访问 BPF 抓包设备。插件不会把 TraceFence 以 root 运行或修改 /dev/bpf 权限；可改用“安全连接”模式，或导入现有 PCAP 文件分析。"
        }
        return message
    }
}
