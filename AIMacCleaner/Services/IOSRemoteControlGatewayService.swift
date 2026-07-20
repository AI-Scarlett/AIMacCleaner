import Foundation
import Network
import Security
import Darwin

@MainActor
final class IOSRemoteControlGatewayService: ObservableObject {
    static let shared = IOSRemoteControlGatewayService()
    static let enabledKey = "traceFenceIOSRemoteGatewayEnabled"
    static let portKey = "traceFenceIOSRemoteGatewayPort"
    static let tokenKey = "traceFenceIOSRemoteGatewayToken"
    static let keepMacAwakeKey = "traceFenceIOSRemoteKeepMacAwake"
    static let backgroundCorePort = 17896
    private static let maxHTTPRequestBytes = 256 * 1_024
    private static let maxRemoteSessions = 50
    private static let maxRemoteAllSessions = 80

    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage = "Remote API is off."
    @Published private(set) var endpoint = ""
    @Published private(set) var lastRequestSummary = ""
    @Published private(set) var isKeepingMacAwake = false

    private weak var scannerService: ScannerService?
    private weak var sessionStore: SessionStore?
    private weak var hookServer: HookServer?
    private weak var overviewStore: AgentMonitorOverviewStore?
    private var ownedOverviewStore: AgentMonitorOverviewStore?
    private var listener: NWListener?
    private var listeningPort: Int?
    private var processTableCache: (timestamp: Date, table: [Int: TraceFenceProcessSnapshot])?
    private let listenerQueue = DispatchQueue(label: "com.tracefence.ios-remote-gateway")
    private let pathMonitor = NWPathMonitor()
    private let pathMonitorQueue = DispatchQueue(label: "com.tracefence.ios-remote-gateway.path")
    private let defaultPort = 17895
    private var keepAwakeProcess: Process?
    private var lastAgentCoreConfigData: Data?
    private var didReconcileAgentCorePairingToken = false
    private var listenerRetryTask: Task<Void, Never>?
    private var listenerRetryAttempt = 0

    private init() {
        UserDefaults.standard.register(defaults: [Self.keepMacAwakeKey: true])
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "traceFenceIOSRemoteGatewayLastServiceInit")
        refreshEndpoint()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in
                self?.refreshNetworkEndpoint()
            }
        }
        pathMonitor.start(queue: pathMonitorQueue)
        if UserDefaults.standard.bool(forKey: Self.enabledKey) {
            DispatchQueue.main.async { [weak self] in
                self?.startConfiguredIfNeeded()
            }
        }
    }

    func configure(
        scannerService: ScannerService?,
        sessionStore: SessionStore? = nil,
        hookServer: HookServer? = nil,
        overviewStore: AgentMonitorOverviewStore? = nil
    ) {
        self.scannerService = scannerService
        if let sessionStore {
            self.sessionStore = sessionStore
        }
        if let hookServer {
            self.hookServer = hookServer
        }
        if let overviewStore {
            if let ownedOverviewStore, ownedOverviewStore !== overviewStore {
                ownedOverviewStore.stopBackgroundRefresh()
                self.ownedOverviewStore = nil
            }
            self.overviewStore = overviewStore
        }
        if UserDefaults.standard.bool(forKey: Self.enabledKey) {
            start(port: configuredPort)
        } else {
            refreshEndpoint()
        }
    }

    func startConfiguredIfNeeded() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "traceFenceIOSRemoteGatewayLastBootstrap")
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        UserDefaults.standard.set(enabled, forKey: "traceFenceIOSRemoteGatewayLastEnabledRead")
        guard enabled else {
            refreshEndpoint()
            return
        }
        start(port: configuredPort)
    }

    func setEnabled(_ enabled: Bool, port: Int? = nil) {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if let port {
            UserDefaults.standard.set(Self.normalizedPort(port), forKey: Self.portKey)
        }

        if enabled {
            listenerRetryAttempt = 0
            start(port: port ?? configuredPort)
        } else {
            stop()
        }
        syncAgentCoreRemoteGatewayConfig()
    }

    func setKeepMacAwake(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Self.keepMacAwakeKey)
        updateKeepAwakeState()
    }

    func restart(port: Int) {
        let normalized = Self.normalizedPort(port)
        UserDefaults.standard.set(normalized, forKey: Self.portKey)
        listenerRetryAttempt = 0
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else {
            refreshEndpoint()
            return
        }
        start(port: normalized)
    }

    func stop() {
        listenerRetryTask?.cancel()
        listenerRetryTask = nil
        listenerRetryAttempt = 0
        listener?.cancel()
        listener = nil
        listeningPort = nil
        isRunning = false
        statusMessage = "Remote API is off."
        stopKeepingMacAwake()
        refreshEndpoint()
        syncAgentCoreRemoteGatewayConfig()
    }

    func rotatePairingToken() {
        // A user-requested reset must replace the shared Core token instead of
        // adopting it again during the following config sync.
        didReconcileAgentCorePairingToken = true
        UserDefaults.standard.set(Self.randomToken(), forKey: Self.tokenKey)
        syncAgentCoreRemoteGatewayConfig()
        if isRunning {
            start(port: configuredPort)
        } else {
            refreshEndpoint()
        }
    }

    func refreshNetworkEndpoint() {
        let previousEndpoint = endpoint
        refreshEndpoint()
        guard isRunning, endpoint != previousEndpoint else { return }
        statusMessage = "Remote API is listening on \(endpoint)."
    }

    var configuredPort: Int {
        let stored = UserDefaults.standard.integer(forKey: Self.portKey)
        return stored > 0 ? Self.normalizedPort(stored) : defaultPort
    }

    var keepMacAwakeEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.keepMacAwakeKey)
    }

    var pairingPayloadText: String {
        let payload: [String: Any] = [
            "version": 1,
            "service": "TraceFence iOS Remote Control",
            "endpoint": endpoint,
            "token": currentToken,
            "port": configuredPort,
            "backgroundCorePort": Self.backgroundCorePort,
            "channel": TraceFenceDistributionPolicy.currentChannel.rawValue,
            "noBackend": true,
            "localHostName": ProcessInfo.processInfo.hostName,
            "bonjourHostName": Self.bonjourHostName,
            "bonjourServiceName": Self.bonjourServiceName,
            "localAddresses": localAddresses(),
            "accessEndpoints": pairingAccessEndpoints(),
            "requirements": TraceFenceRemoteAccessMode.allCases.map { mode in
                [
                    "mode": mode.title,
                    "requirement": mode.requirement,
                    "securityNote": mode.securityNote
                ]
            }
        ]
        return Self.prettyJSONString(payload)
    }

    var compactPairingPayloadText: String {
        let token = currentToken
        let host = localAddresses().first ?? "127.0.0.1"
        if let compactToken = Self.base32Token(fromHex: token) {
            var components = URLComponents()
            components.scheme = "TF"
            components.host = Self.urlComponentsHost(host)
            if configuredPort != defaultPort {
                components.port = configuredPort
            }
            components.path = "/\(compactToken)"
            if let compactURL = components.string {
                return compactURL
            }
        }

        // Kept only as a defensive fallback for a legacy, non-hex token stored
        // by an older build. Current tokens always use 32 random bytes.
        return Self.compactJSONString([
            "endpoint": Self.httpEndpoint(host: host, port: configuredPort),
            "token": token
        ])
    }

    private func start(port: Int) {
        if TraceFenceDistributionPolicy.currentChannel.isAppStore,
           !AppStoreSubscriptionService.shared.canUseProFeatures {
            stop()
            return
        }
        let normalized = Self.normalizedPort(port)
        UserDefaults.standard.set(normalized, forKey: Self.portKey)
        UserDefaults.standard.set(normalized, forKey: "traceFenceIOSRemoteGatewayLastStartPort")
        _ = currentToken
        syncAgentCoreRemoteGatewayConfig()
        updateKeepAwakeState()

        if listener != nil, listeningPort == normalized {
            refreshEndpoint()
            return
        }

        listener?.cancel()
        listener = nil
        listeningPort = nil

        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(normalized)) else {
            statusMessage = "Invalid remote API port."
            isRunning = false
            refreshEndpoint()
            return
        }

        do {
            let parameters = NWParameters.tcp
            // Website and App Store builds have different bundle identifiers and
            // may briefly coexist during an upgrade. Never let two processes share
            // the pairing port: SO_REUSEPORT would load-balance requests across
            // listeners with different tokens and cause intermittent 401 responses.
            parameters.allowLocalEndpointReuse = false
            let newListener = try NWListener(using: parameters, on: nwPort)
            newListener.service = NWListener.Service(
                name: Self.bonjourServiceName,
                type: "_tracefence._tcp"
            )
            newListener.stateUpdateHandler = { [weak self, weak newListener] state in
                Task { @MainActor in
                    guard
                        let self,
                        let newListener,
                        self.listener === newListener
                    else {
                        return
                    }
                    self.handleListenerState(state)
                }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }
            listener = newListener
            listeningPort = normalized
            refreshEndpoint()
            newListener.start(queue: listenerQueue)
        } catch {
            UserDefaults.standard.set(error.localizedDescription, forKey: "traceFenceIOSRemoteGatewayLastStartError")
            isRunning = false
            statusMessage = "Could not start remote API: \(error.localizedDescription)"
            refreshEndpoint()
            scheduleListenerRetry(port: normalized)
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            listenerRetryTask?.cancel()
            listenerRetryTask = nil
            listenerRetryAttempt = 0
            UserDefaults.standard.set("ready", forKey: "traceFenceIOSRemoteGatewayLastListenerState")
            isRunning = true
            statusMessage = "Remote API is listening on \(endpoint)."
        case .failed(let error):
            UserDefaults.standard.set("failed: \(error.localizedDescription)", forKey: "traceFenceIOSRemoteGatewayLastListenerState")
            isRunning = false
            let failedPort = listeningPort ?? configuredPort
            listener?.cancel()
            listener = nil
            listeningPort = nil
            statusMessage = "Remote API failed: \(error.localizedDescription). Retrying…"
            scheduleListenerRetry(port: failedPort)
        case .cancelled:
            UserDefaults.standard.set("cancelled", forKey: "traceFenceIOSRemoteGatewayLastListenerState")
            isRunning = false
            listener = nil
            listeningPort = nil
            statusMessage = "Remote API is off."
        default:
            break
        }
    }

    private func scheduleListenerRetry(port: Int) {
        guard UserDefaults.standard.bool(forKey: Self.enabledKey) else { return }
        listenerRetryTask?.cancel()
        let attempt = listenerRetryAttempt
        listenerRetryAttempt += 1
        let delays: [UInt64] = [500_000_000, 1_000_000_000, 2_000_000_000, 4_000_000_000, 8_000_000_000, 15_000_000_000]
        let delay = delays[min(attempt, delays.count - 1)]
        listenerRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard
                !Task.isCancelled,
                let self,
                UserDefaults.standard.bool(forKey: Self.enabledKey),
                self.listener == nil,
                self.configuredPort == port
            else { return }
            self.listenerRetryTask = nil
            self.start(port: port)
        }
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: listenerQueue)
        receiveRequest(on: connection, buffer: "")
    }

    private func receiveRequest(on connection: NWConnection, buffer: String) {
        let maxRequestBytes = Self.maxHTTPRequestBytes
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data, let chunk = String(data: data, encoding: .utf8) {
                nextBuffer += chunk
            }

            guard nextBuffer.utf8.count <= maxRequestBytes else {
                Task { @MainActor in
                    self.sendJSON(["ok": false, "error": "request_too_large"], status: 413, connection: connection)
                }
                return
            }

            if RemoteHTTPRequest.hasCompleteRequest(nextBuffer) || isComplete {
                Task { @MainActor in
                    self.route(rawRequest: nextBuffer, connection: connection)
                }
            } else {
                Task { @MainActor in
                    self.receiveRequest(on: connection, buffer: nextBuffer)
                }
            }
        }
    }

    private func route(rawRequest: String, connection: NWConnection) {
        guard let request = RemoteHTTPRequest(raw: rawRequest) else {
            sendJSON(["ok": false, "error": "bad_request"], status: 400, connection: connection)
            return
        }

        if request.method == "OPTIONS" {
            sendJSON(["ok": true], status: 204, connection: connection)
            return
        }

        if request.path == "/v1/health" {
            sendJSON(["ok": true, "service": "TraceFence iOS Remote Control", "version": 1], status: 200, connection: connection)
            return
        }

        guard isAuthorized(request.headers) else {
            sendJSON(["ok": false, "error": "unauthorized"], status: 401, connection: connection)
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/v1/status"):
            lastRequestSummary = "Status requested at \(Self.timeString())"
            sendJSON(statusPayload(), status: 200, connection: connection)
        case ("GET", "/v1/agents"):
            Task {
                self.lastRequestSummary = "Agents requested at \(Self.timeString())"
                let body = await self.agentControlPayload()
                self.sendJSON(body, status: 200, connection: connection)
            }
        case ("GET", "/v1/events"):
            Task {
                self.lastRequestSummary = "Events requested at \(Self.timeString())"
                let body = await self.eventsPayload()
                self.sendJSON(body, status: 200, connection: connection)
            }
        case ("GET", "/v1/approvals"):
            Task {
                self.lastRequestSummary = "Approvals requested at \(Self.timeString())"
                let body = await self.approvalsPayload()
                self.sendJSON(body, status: 200, connection: connection)
            }
        case ("POST", "/v1/approvals/approve"):
            handleApprovalDecision(request: request, allow: true, connection: connection)
        case ("POST", "/v1/approvals/deny"):
            handleApprovalDecision(request: request, allow: false, connection: connection)
        case ("POST", "/v1/sessions/interrupt"):
            handleSessionCommand(request: request, command: .interrupt, connection: connection)
        case ("POST", "/v1/sessions/resume"):
            handleSessionCommand(request: request, command: .resume, connection: connection)
        case ("POST", "/v1/sessions/terminate"):
            handleSessionCommand(request: request, command: .terminate, connection: connection)
        case ("POST", "/v1/sessions/launch"):
            handleSessionLaunch(request: request, connection: connection)
        case ("POST", "/v1/sessions/relaunch"):
            handleSessionRelaunch(request: request, connection: connection)
        case ("POST", "/v1/monitor/start"):
            handleMonitorCommand(start: true, connection: connection)
        case ("POST", "/v1/monitor/stop"):
            handleMonitorCommand(start: false, connection: connection)
        default:
            sendJSON(["ok": false, "error": "not_found"], status: 404, connection: connection)
        }
    }

    private func handleApprovalDecision(request: RemoteHTTPRequest, allow: Bool, connection: NWConnection) {
        guard canUseRemoteControl else {
            sendJSON([
                "ok": false,
                "error": "subscription_required",
                "message": "Remote approval requires an active TraceFence subscription."
            ], status: 402, connection: connection)
            return
        }

        if let approvalId = request.jsonBody["approvalId"] as? String, approvalId.hasPrefix("codex|") {
            guard supportsExternalControlPlane else {
                sendJSON([
                    "ok": false,
                    "error": "distribution_limited",
                    "message": "Native Codex control is available in the TraceFence website build. The Mac App Store build supports Hook approvals."
                ], status: 403, connection: connection)
                return
            }
            Task {
                let answer = self.firstString(in: request.jsonBody, keys: ["answer", "reason"])
                let result = await CodexControlPlaneService.shared.resolveApproval(
                    id: approvalId,
                    allow: allow,
                    answer: answer
                )
                self.lastRequestSummary = "\(allow ? "Approved" : "Denied") Codex request at \(Self.timeString())"
                let body = await self.agentControlPayload(extra: self.codexResultPayload(result, sessionId: nil))
                self.sendJSON(body, status: 200, connection: connection)
            }
            return
        }

        guard let approvalRef = approvalRef(from: request.jsonBody) else {
            sendJSON(["ok": false, "error": "missing_approval"], status: 400, connection: connection)
            return
        }

        Task {
            let message = await self.resolveApproval(approvalRef, allow: allow, body: request.jsonBody)
            self.lastRequestSummary = "\(allow ? "Approved" : "Denied") \(approvalRef.kind) at \(Self.timeString())"
            let body = await self.agentControlPayload(extra: [
                "command": allow ? "approval_approved" : "approval_denied",
                "message": message
            ])
            self.sendJSON(body, status: 200, connection: connection)
        }
    }

    private enum SessionCommand: Equatable {
        case interrupt
        case resume
        case terminate

        var responseName: String {
            switch self {
            case .interrupt: return "session_interrupt"
            case .resume: return "session_resume"
            case .terminate: return "session_terminate"
            }
        }
    }

    private func handleSessionCommand(request: RemoteHTTPRequest, command: SessionCommand, connection: NWConnection) {
        guard canUseRemoteControl else {
            sendJSON([
                "ok": false,
                "error": "subscription_required",
                "message": "Remote session control requires an active TraceFence subscription."
            ], status: 402, connection: connection)
            return
        }

        guard let sessionId = request.jsonBody["sessionId"] as? String, !sessionId.isEmpty else {
            sendJSON(["ok": false, "error": "missing_session"], status: 400, connection: connection)
            return
        }

        Task {
            let instruction = self.continuationInstruction(from: request.jsonBody)
            let result = await self.applySessionCommand(command, sessionId: sessionId, instruction: instruction)
            self.lastRequestSummary = "\(result["command"] as? String ?? "Session command") at \(Self.timeString())"
            let body = await self.agentControlPayload(extra: result)
            self.sendJSON(body, status: 200, connection: connection)
        }
    }

    private func handleSessionLaunch(request: RemoteHTTPRequest, connection: NWConnection) {
        guard canUseRemoteControl else {
            sendJSON([
                "ok": false,
                "error": "subscription_required",
                "message": "Launching a controllable Agent session requires an active TraceFence subscription."
            ], status: 402, connection: connection)
            return
        }

        guard supportsExternalControlPlane else {
            sendJSON([
                "ok": false,
                "error": "distribution_limited",
                "message": "Launching CLI/PTY sessions is not available in the sandboxed Mac App Store build."
            ], status: 403, connection: connection)
            return
        }

        guard let targetId = request.jsonBody["targetId"] as? String, !targetId.isEmpty else {
            sendJSON(["ok": false, "error": "missing_target", "message": "Missing Agent launch target."], status: 400, connection: connection)
            return
        }

        let cwd = request.jsonBody["cwd"] as? String
        let instruction = continuationInstruction(from: request.jsonBody)
        do {
            let session = try AgentPTYRuntimeService.shared.launch(
                targetId: targetId,
                cwd: cwd,
                initialInstruction: instruction
            )
            lastRequestSummary = "Launched \(session.displayName) controlled session at \(Self.timeString())"
            Task {
                let body = await self.agentControlPayload(extra: [
                    "ok": true,
                    "command": "session_launch",
                    "sessionId": ptyRemoteId(session.id),
                    "message": "TraceFence 已在 Mac 上创建一个可远程控制的 Agent 会话。"
                ])
                self.sendJSON(body, status: 200, connection: connection)
            }
        } catch {
            sendJSON([
                "ok": false,
                "error": "launch_failed",
                "message": error.localizedDescription
            ], status: 400, connection: connection)
        }
    }

    private func handleSessionRelaunch(request: RemoteHTTPRequest, connection: NWConnection) {
        guard canUseRemoteControl else {
            sendJSON([
                "ok": false,
                "error": "subscription_required",
                "message": "Launching a controllable continuation requires an active TraceFence subscription."
            ], status: 402, connection: connection)
            return
        }

        guard supportsExternalControlPlane else {
            sendJSON([
                "ok": false,
                "error": "distribution_limited",
                "message": "Task takeover through a local CLI/PTY is not available in the sandboxed Mac App Store build."
            ], status: 403, connection: connection)
            return
        }

        guard let sessionId = request.jsonBody["sessionId"] as? String, !sessionId.isEmpty else {
            sendJSON(["ok": false, "error": "missing_session", "message": "Missing Agent session."], status: 400, connection: connection)
            return
        }

        Task {
            let instruction = self.continuationInstruction(from: request.jsonBody)
            if let threadId = self.codexThreadId(from: sessionId) {
                let text = instruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let result = await CodexControlPlaneService.shared.sendInstruction(
                    threadId: threadId,
                    instruction: text.isEmpty ? "请继续执行这个任务。" : text
                )
                self.lastRequestSummary = "Codex instruction at \(Self.timeString())"
                let body = await self.agentControlPayload(extra: self.codexResultPayload(result, sessionId: sessionId))
                self.sendJSON(body, status: 200, connection: connection)
                return
            }
            let targetId = (request.jsonBody["targetId"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = await self.relaunchSession(
                sessionId: sessionId,
                requestedTargetId: targetId?.isEmpty == false ? targetId : nil,
                instruction: instruction,
                requestBody: request.jsonBody
            )
            self.lastRequestSummary = "\(result["command"] as? String ?? "Session relaunch") at \(Self.timeString())"
            let body = await self.agentControlPayload(extra: result)
            self.sendJSON(body, status: 200, connection: connection)
        }
    }

    private func handleMonitorCommand(start: Bool, connection: NWConnection) {
        guard canUseRemoteControl else {
            sendJSON([
                "ok": false,
                "error": "subscription_required",
                "message": "Remote control requires an active TraceFence subscription."
            ], status: 402, connection: connection)
            return
        }

        if start {
            scannerService?.startMonitoring()
            UserDefaults.standard.set(true, forKey: "monitorEnabled")
        } else {
            scannerService?.stopMonitoring()
            UserDefaults.standard.set(false, forKey: "monitorEnabled")
        }

        lastRequestSummary = "\(start ? "Start" : "Stop") monitoring at \(Self.timeString())"
        sendJSON(statusPayload(extra: ["command": start ? "monitor_start" : "monitor_stop"]), status: 200, connection: connection)
    }

    private var canUseRemoteControl: Bool {
        if TraceFenceDistributionPolicy.currentChannel.isAppStore {
            return AppStoreSubscriptionService.shared.canUseProFeatures
        }
        return DirectLicenseService.shared.canUseProFeatures || DirectLicenseService.shared.isTrialActive
    }

    private var supportsExternalControlPlane: Bool {
        TraceFenceDistributionPolicy.currentChannel.isDirect
    }

    private func isAuthorized(_ headers: [String: String]) -> Bool {
        guard let authorization = headers["authorization"] else { return false }
        let prefix = "bearer "
        let normalized = authorization.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.lowercased().hasPrefix(prefix) else { return false }
        let provided = String(normalized.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        return provided == currentToken
    }

    private func statusPayload(extra: [String: Any] = [:]) -> [String: Any] {
        var body: [String: Any] = [
            "ok": true,
            "version": 1,
            "app": [
                "name": Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "TraceFence",
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
            ],
            "gateway": [
                "running": isRunning,
                "endpoint": endpoint,
                "port": configuredPort,
                "lastRequest": lastRequestSummary,
                "keepingMacAwake": isKeepingMacAwake,
                "backgroundCorePort": Self.backgroundCorePort
            ],
            "subscription": subscriptionPayload(),
            "system": systemPayload(),
            "agentControl": controlPlanePayload(),
            "agentCore": TraceFenceAgentCoreClient.shared.status.payload,
            "connectivity": [
                "noBackend": true,
                "localAddresses": localAddresses(),
                "accessEndpoints": pairingAccessEndpoints(),
                "modes": TraceFenceRemoteAccessMode.allCases.map { mode in
                    [
                        "title": mode.title,
                        "requirement": mode.requirement,
                        "securityNote": mode.securityNote
                    ]
                }
            ]
        ]
        for (key, value) in extra {
            body[key] = value
        }
        return body
    }

    private func controlPlanePayload() -> [String: Any] {
        [
            "available": true,
            "codexNative": supportsExternalControlPlane && CodexControlPlaneService.shared.isAvailable,
            "hookSessions": sessionStore != nil,
            "monitorSessions": overviewStore != nil || ownedOverviewStore != nil,
            "truthModel": "capability_negotiated",
            "controlModes": [
                [
                    "id": "codex_native",
                    "title": "Codex native control",
                    "available": supportsExternalControlPlane && CodexControlPlaneService.shared.isAvailable,
                    "description": "TraceFence uses Codex app-server and Desktop owner IPC to list real projects and sessions, start or steer turns, interrupt work, and answer approval requests."
                ],
                [
                    "id": "tracefence_pty",
                    "title": "TraceFence controlled session",
                    "available": supportsExternalControlPlane,
                    "description": "TraceFence starts and owns the controllable agent runtime, can send instructions, and can pause or resume the process group."
                ],
                [
                    "id": "tracefence_relaunch",
                    "title": "Task takeover",
                    "available": supportsExternalControlPlane,
                    "description": "TraceFence can take over an observed task with a known local agent target and continue it in a controllable session."
                ],
                [
                    "id": "hook_question",
                    "title": "Hook waiting input",
                    "available": sessionStore != nil,
                    "description": "TraceFence can answer a waiting Agent continuation when the Agent bridge is actively blocked on a question."
                ],
                [
                    "id": "hook_approval",
                    "title": "Hook approval",
                    "available": sessionStore != nil,
                    "description": "TraceFence can approve or deny permission and plan requests that are routed through HookServer."
                ],
                [
                    "id": "process_group",
                    "title": "Process control",
                    "available": supportsExternalControlPlane,
                    "description": "TraceFence can pause or resume a safe process group when the session is bound to a live terminal process."
                ],
                [
                    "id": "display_only",
                    "title": "Observation only",
                    "available": true,
                    "description": "Log, database, GUI-app, and stale session snapshots are visible but not remotely controllable."
                ]
            ],
            "limitations": [
                "TraceFence cannot generically rewrite an Agent conversation state or model context by PID.",
                "Codex/ChatGPT has native conversation control. Other desktop agents still require Hook, terminal, or their own API integration.",
                "The Mac App Store build exposes Hook-based approvals and waiting-input replies, but does not launch external CLI/PTY runtimes or signal arbitrary process groups.",
                "Internet remote control has no TraceFence cloud relay; users must provide LAN, VPN, tailnet, port forwarding, or a user-owned tunnel."
            ],
            "endpoints": [
                "GET /v1/agents",
                "GET /v1/events",
                "GET /v1/approvals",
                "POST /v1/approvals/approve",
                "POST /v1/approvals/deny",
                "POST /v1/sessions/launch",
                "POST /v1/sessions/relaunch",
                "POST /v1/sessions/interrupt",
                "POST /v1/sessions/resume",
                "POST /v1/sessions/terminate"
            ]
        ]
    }

    private func resolvedOverviewStore() -> AgentMonitorOverviewStore {
        if let overviewStore {
            return overviewStore
        }
        if let ownedOverviewStore {
            return ownedOverviewStore
        }
        let store = AgentMonitorOverviewStore()
        ownedOverviewStore = store
        return store
    }

    private func agentControlPayload(extra: [String: Any] = [:]) async -> [String: Any] {
        let sessions = await sessionStore?.getAllSessions() ?? []
        let monitorStore = resolvedOverviewStore()
        let codexSessions: [CodexSessionSnapshot] = supportsExternalControlPlane
            ? await CodexControlPlaneService.shared.sessionSnapshots()
            : []
        let codexIds = Set(codexSessions.map(\.id))
        let monitorSessions = monitorStore.sessions.filter { !codexIds.contains($0.sessionId) }
        let ptySessions: [AgentPTYSessionSnapshot] = supportsExternalControlPlane
            ? AgentPTYRuntimeService.shared.visibleSessions
            : []
        let desktopSessions = supportsExternalControlPlane ? desktopAgentPayloads() : []
        let ptySessionPayloads = ptySessions.map(ptySessionPayload(_:))
        let codexSessionPayloads = codexSessions.map(codexSessionPayload(_:))
        let activeSessions = sessions.filter { $0.phase.isActive || $0.phase.needsAttention }
        let activeMonitorSessions = monitorSessions.filter(isMonitorSessionVisible(_:))
        let codexApprovals = supportsExternalControlPlane ? CodexControlPlaneService.shared.approvalSnapshots() : []
        let approvals = approvalSnapshots(from: sessions) + codexApprovals.map { codexApprovalPayload($0, sessions: codexSessions) }
        let prioritizedPayloads = desktopSessions + ptySessionPayloads + codexSessionPayloads + activeSessions.map(sessionPayload(_:)) + activeMonitorSessions.map(monitorSessionPayload(_:))
        let allPayloads = desktopSessions + ptySessionPayloads + codexSessionPayloads + sessions.map(sessionPayload(_:)) + monitorSessions.map(monitorSessionPayload(_:))
        let sessionPayloads = Array(prioritizedPayloads.prefix(Self.maxRemoteSessions))
        let allSessionPayloads = Array(allPayloads.prefix(Self.maxRemoteAllSessions))
        let ptyProcessingCount = ptySessions.filter { $0.phase == "processing" }.count
        let ptyInterruptedCount = ptySessions.filter { $0.phase == "interrupted" }.count
        var body: [String: Any] = [
            "ok": true,
            "version": 1,
            "generatedAt": Self.isoDate(Date()),
            "summary": [
                "sessionCount": desktopSessions.count + codexSessions.count + sessions.count + monitorSessions.count + ptySessions.count,
                "activeSessionCount": desktopSessions.count + codexSessions.filter { $0.phase == "processing" }.count + activeSessions.count + activeMonitorSessions.count + ptySessions.filter { $0.phase != "done" }.count,
                "pendingApprovalCount": approvals.count,
                "processingCount": desktopSessions.count + codexSessions.filter { $0.phase == "processing" }.count + sessions.filter { $0.phase == .processing }.count + activeMonitorSessions.filter { monitorSessionPhase($0) == "processing" }.count + ptyProcessingCount,
                "interruptedCount": codexSessions.filter { $0.phase == "interrupted" }.count + sessions.filter { $0.phase == .interrupted }.count + activeMonitorSessions.filter { monitorSessionPhase($0) == "interrupted" }.count + ptyInterruptedCount
            ],
            "sessions": sessionPayloads,
            "allSessions": allSessionPayloads,
            "truncated": [
                "sessions": sessionPayloads.count < prioritizedPayloads.count,
                "allSessions": allSessionPayloads.count < allPayloads.count,
                "sessionLimit": Self.maxRemoteSessions,
                "allSessionLimit": Self.maxRemoteAllSessions
            ],
            "launchTargets": supportsExternalControlPlane ? AgentPTYRuntimeService.shared.launchTargets.map(ptyLaunchTargetPayload(_:)) : [],
            "pendingApprovals": approvals,
            "controlPlane": controlPlanePayload(),
            "recentEvents": (codexEventSnapshots(from: codexSessions, limit: 24) + ptyEventSnapshots(from: ptySessions, limit: 24) + eventSnapshots(from: sessions, limit: 24) + monitorEventSnapshots(from: monitorSessions, limit: 24))
                .sorted { ($0["timestamp"] as? String ?? "") > ($1["timestamp"] as? String ?? "") }
                .prefix(24)
                .map { $0 }
        ]
        for (key, value) in extra {
            body[key] = value
        }
        return body
    }

    private func eventsPayload() async -> [String: Any] {
        let sessions = await sessionStore?.getAllSessions() ?? []
        let monitorStore = resolvedOverviewStore()
        let codexSessions: [CodexSessionSnapshot] = supportsExternalControlPlane
            ? await CodexControlPlaneService.shared.sessionSnapshots()
            : []
        let codexIds = Set(codexSessions.map(\.id))
        let monitorSessions = monitorStore.sessions.filter { !codexIds.contains($0.sessionId) }
        let ptySessions: [AgentPTYSessionSnapshot] = supportsExternalControlPlane
            ? AgentPTYRuntimeService.shared.visibleSessions
            : []
        return [
            "ok": true,
            "version": 1,
            "generatedAt": Self.isoDate(Date()),
            "events": (codexEventSnapshots(from: codexSessions, limit: 100) + ptyEventSnapshots(from: ptySessions, limit: 100) + eventSnapshots(from: sessions, limit: 100) + monitorEventSnapshots(from: monitorSessions, limit: 100))
                .sorted { ($0["timestamp"] as? String ?? "") > ($1["timestamp"] as? String ?? "") }
                .prefix(100)
                .map { $0 }
        ]
    }

    private func approvalsPayload() async -> [String: Any] {
        let sessions = await sessionStore?.getAllSessions() ?? []
        let codexSessions: [CodexSessionSnapshot] = supportsExternalControlPlane
            ? CodexControlPlaneService.shared.latestSessionSnapshots()
            : []
        let codexApprovals = supportsExternalControlPlane ? CodexControlPlaneService.shared.approvalSnapshots() : []
        return [
            "ok": true,
            "version": 1,
            "generatedAt": Self.isoDate(Date()),
            "pendingApprovals": approvalSnapshots(from: sessions) + codexApprovals.map {
                codexApprovalPayload($0, sessions: codexSessions)
            }
        ]
    }

    private func ptyLaunchTargetPayload(_ target: AgentPTYLaunchTargetSnapshot) -> [String: Any] {
        [
            "id": target.id,
            "displayName": target.displayName,
            "commandName": target.commandName,
            "installed": target.installed,
            "icon": target.icon,
            "note": target.note,
            "controlMode": "tracefence_pty"
        ]
    }

    private func desktopAgentPayloads() -> [[String: Any]] {
        let table = currentProcessTable()
        let rootProcesses = table.values
            .filter { process in
                process.command.contains("/Applications/Claude.app/Contents/MacOS/Claude")
                    || process.command.contains("/Applications/Cursor.app/Contents/MacOS/")
                    || process.command.contains("/Applications/Trae.app/Contents/MacOS/")
            }
            .sorted { $0.command < $1.command }

        return rootProcesses.compactMap { process in
            if process.command.contains("/Applications/Claude.app/") {
                return desktopAgentPayload(
                    id: "claude-desktop",
                    agentName: "Claude Desktop",
                    project: "Claude",
                    pid: process.pid,
                    targetId: installedPTYLaunchTarget(id: "claude")?.id,
                    targetName: installedPTYLaunchTarget(id: "claude")?.displayName,
                    note: "Claude Desktop 没有暴露 TraceFence 可调用的本地会话控制接口；TraceFence 可以监控它，并在本机安装 claude CLI 时接管到 Claude Code 可控会话。"
                )
            }
            if process.command.contains("/Applications/Cursor.app/") {
                return desktopAgentPayload(
                    id: "cursor-desktop",
                    agentName: "Cursor Desktop",
                    project: "Cursor",
                    pid: process.pid,
                    targetId: installedPTYLaunchTarget(id: "cursor-agent")?.id,
                    targetName: installedPTYLaunchTarget(id: "cursor-agent")?.displayName,
                    note: "Cursor Desktop 当前只作为桌面进程监控；如安装 cursor-agent，可接管到 TraceFence 可控 CLI 会话。"
                )
            }
            if process.command.contains("/Applications/Trae.app/") {
                return desktopAgentPayload(
                    id: "trae-desktop",
                    agentName: "Trae Desktop",
                    project: "Trae",
                    pid: process.pid,
                    targetId: nil,
                    targetName: nil,
                    note: "Trae Desktop 当前只作为桌面进程监控；需要对应 CLI 或 Hook bridge 才能远程插入指令。"
                )
            }
            return nil
        }
    }

    private func desktopAgentPayload(
        id: String,
        agentName: String,
        project: String,
        pid: Int,
        targetId: String?,
        targetName: String?,
        note: String
    ) -> [String: Any] {
        let canRelaunch = targetId?.isEmpty == false
        let instruction = """
        请接管我在 \(project) 桌面端打开的任务。

        你无法直接读取桌面 App 当前对话，请先询问我需要继续的具体目标，或根据我随后从 iPhone 发送的新指令开始执行。
        """
        return [
            "id": "desktop|\(id)|\(pid)",
            "agentType": agentName,
            "engineLabel": "Desktop App",
            "project": project,
            "cwd": SandboxPaths.realHomeDirectory,
            "terminal": "macOS Desktop",
            "phase": "processing",
            "startedAt": Self.isoDate(Date()),
            "lastActivityAt": Self.isoDate(Date()),
            "durationSeconds": 0,
            "title": "\(agentName) 正在运行",
            "lastToolName": "Desktop app",
            "lastToolTarget": project,
            "lastToolStatus": "running",
            "lastResponse": note,
            "lastThought": note,
            "statusLineText": note,
            "pid": pid,
            "canInterrupt": false,
            "canResume": false,
            "canTerminate": false,
            "resumeRequiresInstruction": true,
            "resumeNote": note,
            "controlMode": "display_only",
            "controlAvailable": false,
            "controlReason": "desktop_app_without_control_api",
            "controlLimitations": [
                note,
                "要真正发送指令，请使用“接管/启动可控会话”，TraceFence 会创建自己拥有的 CLI/PTY 会话。"
            ],
            "deliveryModes": canRelaunch ? ["tracefence_pty"] : [],
            "canRelaunch": canRelaunch,
            "relaunchControlMode": canRelaunch ? "tracefence_relaunch" : "",
            "relaunchTargetId": targetId ?? "",
            "relaunchTargetName": targetName ?? "",
            "relaunchInstruction": instruction,
            "relaunchNote": canRelaunch
                ? "TraceFence 会启动 \(targetName ?? "CLI Agent")，创建一个真正可暂停、恢复、发送指令的受控会话。"
                : "这台 Mac 尚未安装可接管的 CLI Agent。",
            "source": "desktopProcess",
            "sourcePath": project,
            "tokens": ["input": 0, "output": 0, "cacheRead": 0, "cacheCreate": 0],
            "activeTools": [],
            "tasks": [[
                "id": "desktop-\(id)-process",
                "name": "\(agentName) desktop process",
                "status": "running"
            ]],
            "subagents": []
        ]
    }

    private func codexSessionPayload(_ session: CodexSessionSnapshot) -> [String: Any] {
        let projectName = URL(fileURLWithPath: session.cwd).lastPathComponent
        let project = projectName.isEmpty ? session.cwd : projectName
        let isRunning = session.phase == "processing"
        let isInterrupted = session.phase == "interrupted"
        let usesAgentCore = session.source == "agent-core" || TraceFenceAgentCoreClient.shared.status.connected
        let controlMode = usesAgentCore ? "tracefence_agent_core" : "codex_native"
        let controlReason = usesAgentCore ? "tracefence_agent_core" : "codex_app_server"
        let deliveryModes = usesAgentCore
            ? ["tracefence_agent_core", "codex_desktop_ipc"]
            : ["codex_app_server", "codex_desktop_ipc"]
        return [
            "id": codexRemoteId(session.id),
            "agentType": "Codex",
            "engineLabel": session.model,
            "project": project,
            "cwd": session.cwd,
            "terminal": "Mac Codex/ChatGPT",
            "phase": session.phase,
            "startedAt": Self.isoDate(session.createdAt),
            "lastActivityAt": Self.isoDate(session.updatedAt),
            "durationSeconds": max(0, Int(Date().timeIntervalSince(session.createdAt))),
            "title": session.preview,
            "lastToolName": isRunning ? "Codex 正在执行" : "Codex 会话",
            "lastToolTarget": session.cwd,
            "lastToolStatus": session.phase,
            "lastResponse": String(session.lastResponse.suffix(1_200)),
            "lastThought": "",
            "statusLineText": isRunning ? "正在 Mac 上执行" : (isInterrupted ? "已中断，可发送新指令" : "可从 iPhone 发送新指令"),
            "canInterrupt": isRunning,
            "canResume": true,
            "canTerminate": isRunning,
            "resumeRequiresInstruction": true,
            "resumeNote": isRunning
                ? "发送的内容会插入当前 Codex turn；也可以先中断，再发送新的后续指令。"
                : "发送指令会在这个真实 Codex 会话中创建新 turn，并同步显示在 Mac 客户端。",
            "controlMode": controlMode,
            "controlAvailable": true,
            "controlReason": controlReason,
            "controlLimitations": [
                usesAgentCore
                    ? "TraceFence Agent Core 通过 Mac 本机桌面 IPC 控制真实会话，不会创建替代 Shell 会话。"
                    : "TraceFence 通过 Mac 本机 Codex app-server 控制真实会话，不会创建替代 Shell 会话。",
                "Mac 和 iPhone 断网时，已提交到 Mac 的任务仍可继续，但新的远程操作需要恢复连接。"
            ],
            "deliveryModes": deliveryModes,
            "canRelaunch": false,
            "source": "codexNative",
            "sourcePath": session.sourcePath,
            "tokens": ["input": 0, "output": 0, "cacheRead": 0, "cacheCreate": 0],
            "activeTools": isRunning ? [[
                "id": "\(session.id)-turn",
                "toolName": "Codex turn",
                "status": "running",
                "startedAt": Self.isoDate(session.updatedAt),
                "completedAt": "",
                "toolInput": String(session.lastUserMessage.suffix(500))
            ]] : [],
            "tasks": session.lastUserMessage.isEmpty ? [] : [[
                "id": "\(session.id)-instruction",
                "name": String(session.lastUserMessage.suffix(500)),
                "status": session.phase
            ]],
            "subagents": []
        ]
    }

    private func codexApprovalPayload(
        _ approval: CodexApprovalSnapshot,
        sessions: [CodexSessionSnapshot]
    ) -> [String: Any] {
        let session = sessions.first { $0.id == approval.threadId }
        let cwd = session?.cwd ?? ""
        let projectName = URL(fileURLWithPath: cwd).lastPathComponent
        let project = projectName.isEmpty ? (session?.preview ?? "Codex") : projectName
        return [
            "id": approval.id,
            "kind": approval.kind,
            "sessionId": codexRemoteId(approval.threadId),
            "agentType": "Codex",
            "project": project,
            "title": approval.title,
            "detail": approval.detail,
            "options": approval.options,
            "descriptions": approval.descriptions,
            "permissions": approval.permissions,
            "sourceLabel": "Codex app-server",
            "requestedAt": Self.isoDate(approval.requestedAt),
            "risk": approval.kind == "permission" ? "high" : "medium",
            "requiresTextAnswer": approval.requiresTextAnswer
        ]
    }

    private func ptySessionPayload(_ session: AgentPTYSessionSnapshot) -> [String: Any] {
        [
            "id": ptyRemoteId(session.id),
            "agentType": session.displayName,
            "engineLabel": "TraceFence 可控会话",
            "project": URL(fileURLWithPath: session.cwd).lastPathComponent.isEmpty ? session.cwd : URL(fileURLWithPath: session.cwd).lastPathComponent,
            "cwd": session.cwd,
            "terminal": "TraceFence 可控会话",
            "phase": session.phase,
            "startedAt": Self.isoDate(session.startedAt),
            "lastActivityAt": Self.isoDate(session.lastActivityAt),
            "durationSeconds": Int(Date().timeIntervalSince(session.startedAt)),
            "title": "\(session.displayName) · 可控会话",
            "lastToolName": session.phase == "interrupted" ? "已暂停任务" : "可控会话",
            "lastToolTarget": session.commandName,
            "lastToolStatus": session.phase,
            "lastResponse": String(session.outputTail.suffix(500)),
            "lastThought": String(session.outputTail.suffix(500)),
            "statusLineText": session.exitCode.map { "Exited \($0)" } ?? "pid \(session.pid)",
            "pid": session.pid,
            "canInterrupt": session.canInterrupt,
            "canResume": session.canResume,
            "canTerminate": session.phase != "done",
            "resumeRequiresInstruction": session.canResume,
            "resumeNote": session.canResume
                ? "请输入下一步指令；TraceFence 会发送给可控会话，并恢复 Agent 进程组。"
                : "这是由 TraceFence 创建的可控 Agent 会话，可被真实暂停、恢复和终止。",
            "controlMode": session.controlMode,
            "controlAvailable": session.canInterrupt || session.canResume,
            "controlReason": "tracefence_owned_pty",
            "controlLimitations": [
                "该控制只覆盖通过 TraceFence 创建的可控 Agent 会话。",
                "指令会发送给会话输入流；Agent 是否立即采纳取决于当前提示状态。"
            ],
            "deliveryModes": ["pty", "signal"],
            "source": "tracefencePTY",
            "sourcePath": session.cwd,
            "tokens": [
                "input": 0,
                "output": 0,
                "cacheRead": 0,
                "cacheCreate": 0
            ],
            "activeTools": [[
                "id": "\(session.id)-pty",
                "toolName": "TraceFence 可控会话",
                "status": session.phase,
                "startedAt": Self.isoDate(session.startedAt),
                "completedAt": "",
                "toolInput": String(session.outputTail.suffix(500))
            ]],
            "tasks": [[
                "id": "\(session.id)-runtime",
                "name": "TraceFence 可控运行时",
                "status": session.phase
            ]],
            "subagents": []
        ]
    }

    private func sessionPayload(_ session: SessionState) -> [String: Any] {
        let control = hookSessionControlCapability(session)
        let tools: [[String: Any]] = session.activeTools.suffix(6).map { tool in
            [
                "id": tool.id,
                "toolName": tool.toolName,
                "status": tool.status,
                "startedAt": Self.isoDate(tool.startedAt),
                "completedAt": tool.completedAt.map(Self.isoDate(_:)) ?? "",
                "toolInput": String((tool.toolInput ?? "").prefix(500))
            ]
        }
        let tasks: [[String: Any]] = session.tasks.map {
            ["id": $0.id, "name": $0.name, "status": $0.status]
        }
        let subagents: [[String: Any]] = session.subagents.map { subagent in
            [
                "id": subagent.id,
                "name": subagent.name ?? subagent.agentId,
                "agentType": subagent.agentType ?? "",
                "description": subagent.description,
                "status": subagent.status,
                "startedAt": Self.isoDate(subagent.startedAt),
                "completedAt": subagent.completedAt.map(Self.isoDate(_:)) ?? ""
            ]
        }
        var payload: [String: Any] = [
            "id": session.id,
            "agentType": session.agentType,
            "engineLabel": session.engineLabel ?? "",
            "project": session.project,
            "cwd": session.cwd,
            "terminal": session.terminal,
            "phase": session.phase.rawValue,
            "startedAt": Self.isoDate(session.startedAt),
            "lastActivityAt": Self.isoDate(sessionLastActivity(session)),
            "durationSeconds": Int(session.duration),
            "title": session.sessionTitle ?? session.description ?? session.lastUserMessage ?? session.project,
            "lastToolName": session.lastToolName ?? "",
            "lastToolTarget": session.lastToolTarget ?? "",
            "lastToolStatus": session.lastToolStatus ?? "",
            "lastResponse": String((session.lastResponse ?? "").prefix(500)),
            "lastThought": String((session.lastThought ?? "").prefix(500)),
            "statusLineText": session.statusLineText ?? "",
            "canInterrupt": control.canInterrupt && session.phase != .interrupted && session.phase != .done,
            "canResume": control.canResume,
            "canTerminate": control.canInterrupt && session.phase != .done,
            "resumeRequiresInstruction": control.resumeRequiresInstruction,
            "resumeNote": control.note,
            "controlMode": control.mode,
            "controlAvailable": control.available,
            "controlReason": control.reason,
            "controlLimitations": control.limitations,
            "deliveryModes": control.deliveryModes,
            "source": "hookSession",
            "tokens": [
                "input": session.tokens.input,
                "output": session.tokens.output,
                "cacheRead": session.tokens.cacheRead,
                "cacheCreate": session.tokens.cacheCreate
            ],
            "activeTools": tools,
            "tasks": tasks,
            "subagents": subagents
        ]
        payload["pid"] = session.pid.map { Int($0) } ?? NSNull()
        if supportsExternalControlPlane, let relaunch = relaunchPlan(for: session) {
            payload.merge(relaunchPayload(relaunch), uniquingKeysWith: { _, new in new })
        } else {
            payload["canRelaunch"] = false
        }
        return payload
    }

    private func monitorSessionPayload(_ session: AgentMonitorSessionSnapshot) -> [String: Any] {
        let phase = monitorSessionPhase(session)
        let title = session.currentTask.isEmpty ? (session.projectName.isEmpty ? session.agentName : session.projectName) : session.currentTask
        let control = monitorSessionControlCapability(session, phase: phase)
        var payload: [String: Any] = [
            "id": monitorSessionRemoteId(session),
            "agentType": session.agentName,
            "engineLabel": session.model,
            "project": session.projectName.isEmpty ? session.projectPath : session.projectName,
            "cwd": session.projectPath,
            "terminal": "",
            "phase": phase,
            "startedAt": session.instructionDate.map(Self.isoDate(_:)) ?? "",
            "lastActivityAt": session.latestActivity.map(Self.isoDate(_:)) ?? "",
            "durationSeconds": 0,
            "title": title,
            "lastToolName": session.runningToolCount > 0 ? "Agent tool running" : "",
            "lastToolTarget": session.sourcePath,
            "lastToolStatus": session.status,
            "lastResponse": session.currentTask,
            "lastThought": session.currentTask,
            "statusLineText": "\(session.status) · \(session.model)",
            "pid": session.pid.map { Int($0) } ?? NSNull(),
            "canInterrupt": control.canInterrupt && phase != "interrupted" && phase != "done",
            "canResume": control.canResume,
            "canTerminate": control.canInterrupt && phase != "done",
            "resumeRequiresInstruction": control.resumeRequiresInstruction,
            "resumeNote": control.note,
            "controlMode": control.mode,
            "controlAvailable": control.available,
            "controlReason": control.reason,
            "controlLimitations": control.limitations,
            "deliveryModes": control.deliveryModes,
            "tokens": [
                "input": session.tokens.input,
                "output": session.tokens.output,
                "cacheRead": session.tokens.cacheRead,
                "cacheCreate": 0
            ],
            "activeTools": session.toolCount > 0 ? [[
                "id": "\(session.id)-tools",
                "toolName": session.runningToolCount > 0 ? "Running tools" : "Recorded tools",
                "status": session.runningToolCount > 0 ? "running" : "observed",
                "startedAt": session.instructionDate.map(Self.isoDate(_:)) ?? "",
                "completedAt": "",
                "toolInput": "tools=\(session.toolCount), running=\(session.runningToolCount)"
            ]] : [],
            "tasks": session.currentTask.isEmpty ? [] : [[
                "id": "\(session.id)-task",
                "name": session.currentTask,
                "status": session.status
            ]],
            "subagents": [],
            "source": "agentMonitor",
            "sourcePath": session.sourcePath,
            "ports": session.ports,
            "memoryMB": session.memoryMB ?? NSNull(),
            "contextPercent": session.contextPercent,
            "contextWindow": session.contextWindow,
            "turnCount": session.turnCount
        ]
        if supportsExternalControlPlane, let relaunch = relaunchPlan(for: session, title: title) {
            payload.merge(relaunchPayload(relaunch), uniquingKeysWith: { _, new in new })
        } else {
            payload["canRelaunch"] = false
        }
        return payload
    }

    private func approvalSnapshots(from sessions: [SessionState]) -> [[String: Any]] {
        sessions.flatMap { session -> [[String: Any]] in
            var approvals: [[String: Any]] = []
            if let permission = session.pendingPermission {
                approvals.append([
                    "id": approvalId(kind: "permission", sessionId: session.id, toolName: permission.toolName),
                    "kind": "permission",
                    "sessionId": session.id,
                    "agentType": session.agentType,
                    "project": session.project,
                    "title": permission.toolName,
                    "detail": permission.diff ?? permission.toolInput,
                    "options": permission.options ?? [],
                    "sourceLabel": permission.sourceLabel ?? permission.source ?? "",
                    "requestedAt": Self.isoDate(sessionLastActivity(session)),
                    "risk": riskLevel(for: permission.toolName, detail: permission.diff ?? permission.toolInput),
                    "requiresTextAnswer": false
                ])
            }
            if let question = session.pendingQuestion {
                approvals.append([
                    "id": approvalId(kind: "question", sessionId: session.id, toolName: nil),
                    "kind": "question",
                    "sessionId": session.id,
                    "agentType": session.agentType,
                    "project": session.project,
                    "title": question.header ?? "Agent question",
                    "detail": question.question,
                    "options": question.options,
                    "descriptions": question.descriptions,
                    "requestedAt": Self.isoDate(sessionLastActivity(session)),
                    "risk": "medium",
                    "requiresTextAnswer": question.isTextReply
                ])
            }
            if let plan = session.pendingPlan {
                approvals.append([
                    "id": approvalId(kind: "plan", sessionId: session.id, toolName: nil),
                    "kind": "plan",
                    "sessionId": session.id,
                    "agentType": session.agentType,
                    "project": session.project,
                    "title": plan.title,
                    "detail": plan.content,
                    "permissions": plan.permissions,
                    "requestedAt": Self.isoDate(sessionLastActivity(session)),
                    "risk": plan.permissions.isEmpty ? "medium" : "high",
                    "requiresTextAnswer": false
                ])
            }
            return approvals
        }
    }

    private func eventSnapshots(from sessions: [SessionState], limit: Int) -> [[String: Any]] {
        var events: [[String: Any]] = []
        for session in sessions {
            if let tool = session.activeTools.last {
                events.append([
                    "id": "\(session.id)-tool-\(tool.id)",
                    "sessionId": session.id,
                    "agentType": session.agentType,
                    "project": session.project,
                    "type": "tool",
                    "title": tool.toolName,
                    "detail": tool.toolInput ?? session.lastToolTarget ?? "",
                    "status": tool.status,
                    "timestamp": Self.isoDate(tool.completedAt ?? tool.startedAt)
                ])
            }
            for approval in session.approvalHistory.suffix(5) {
                events.append([
                    "id": approval.id,
                    "sessionId": session.id,
                    "agentType": session.agentType,
                    "project": session.project,
                    "type": approval.kind,
                    "title": approval.title,
                    "detail": approval.detail,
                    "status": approval.isPending ? "pending" : "resolved",
                    "timestamp": Self.isoDate(approval.resolvedAt ?? approval.requestedAt)
                ])
            }
            if let response = session.lastResponse, !response.isEmpty {
                events.append([
                    "id": "\(session.id)-response",
                    "sessionId": session.id,
                    "agentType": session.agentType,
                    "project": session.project,
                    "type": "response",
                    "title": "Agent response",
                    "detail": String(response.prefix(500)),
                    "status": session.phase.rawValue,
                    "timestamp": Self.isoDate(sessionLastActivity(session))
                ])
            }
        }
        return events
            .sorted { ($0["timestamp"] as? String ?? "") > ($1["timestamp"] as? String ?? "") }
            .prefix(limit)
            .map { $0 }
    }

    private func ptyEventSnapshots(from sessions: [AgentPTYSessionSnapshot], limit: Int) -> [[String: Any]] {
        sessions
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
            .prefix(limit)
            .map { session in
                [
                    "id": "\(session.id)-pty-\(Int(session.lastActivityAt.timeIntervalSince1970))",
                    "sessionId": ptyRemoteId(session.id),
                    "agentType": session.displayName,
                    "project": URL(fileURLWithPath: session.cwd).lastPathComponent,
                    "type": "pty",
                    "title": session.phase == "interrupted" ? "Agent 已暂停" : "Agent 活动",
                    "detail": String(session.outputTail.suffix(500)),
                    "status": session.phase,
                    "timestamp": Self.isoDate(session.lastActivityAt)
                ]
            }
    }

    private func codexEventSnapshots(from sessions: [CodexSessionSnapshot], limit: Int) -> [[String: Any]] {
        sessions
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { session in
                let projectName = URL(fileURLWithPath: session.cwd).lastPathComponent
                return [
                    "id": "\(session.id)-codex-\(Int(session.updatedAt.timeIntervalSince1970))",
                    "sessionId": codexRemoteId(session.id),
                    "agentType": "Codex",
                    "project": projectName.isEmpty ? session.cwd : projectName,
                    "type": "codex",
                    "title": session.phase == "processing" ? "Codex 正在执行" : "Codex 会话更新",
                    "detail": String((session.lastResponse.isEmpty ? session.lastUserMessage : session.lastResponse).suffix(500)),
                    "status": session.phase,
                    "timestamp": Self.isoDate(session.updatedAt)
                ]
            }
    }

    private func monitorEventSnapshots(from sessions: [AgentMonitorSessionSnapshot], limit: Int) -> [[String: Any]] {
        sessions
            .filter(isMonitorSessionVisible(_:))
            .sorted { ($0.latestActivity ?? .distantPast) > ($1.latestActivity ?? .distantPast) }
            .prefix(limit)
            .map { session in
                [
                    "id": "\(monitorSessionRemoteId(session))-event",
                    "sessionId": monitorSessionRemoteId(session),
                    "agentType": session.agentName,
                    "project": session.projectName.isEmpty ? session.projectPath : session.projectName,
                    "type": "monitor",
                    "title": session.currentTask.isEmpty ? session.status : session.currentTask,
                    "detail": session.sourcePath,
                    "status": session.status,
                    "timestamp": Self.isoDate(session.latestActivity ?? session.instructionDate ?? Date())
                ]
            }
    }

    private func ptyRemoteId(_ sessionId: String) -> String {
        "pty|\(sessionId)"
    }

    private func codexRemoteId(_ threadId: String) -> String {
        "codex|\(threadId)"
    }

    private func codexThreadId(from remoteId: String) -> String? {
        guard remoteId.hasPrefix("codex|") else { return nil }
        let value = String(remoteId.dropFirst("codex|".count))
        return value.isEmpty ? nil : value
    }

    private func ptySessionId(from remoteId: String) -> String? {
        guard remoteId.hasPrefix("pty|") else { return nil }
        let raw = String(remoteId.dropFirst("pty|".count))
        return raw.isEmpty ? nil : raw
    }

    private func isMonitorSessionVisible(_ session: AgentMonitorSessionSnapshot) -> Bool {
        if ["Thinking", "Executing", "Waiting", "Paused"].contains(session.status) {
            return true
        }
        if !session.currentTask.isEmpty && session.status != "History" && session.status != "Done" {
            return true
        }
        if session.pid != nil && session.status != "Done" {
            return true
        }
        return false
    }

    private func monitorSessionPhase(_ session: AgentMonitorSessionSnapshot) -> String {
        switch session.status {
        case "Thinking", "Executing":
            return "processing"
        case "Waiting":
            return "waitingInput"
        case "Paused":
            return "interrupted"
        case "Done":
            return "done"
        case "History":
            return session.pid == nil ? "idle" : "processing"
        default:
            return session.currentTask.isEmpty ? "idle" : "processing"
        }
    }

    private func hookSessionControlCapability(_ session: SessionState) -> TraceFenceSessionControlCapability {
        if session.phase == .done {
            return TraceFenceSessionControlCapability(
                mode: "display_only",
                available: false,
                canInterrupt: false,
                canResume: false,
                resumeRequiresInstruction: false,
                note: "此 Hook 会话已经结束，只能查看历史记录。",
                reason: "session_done",
                limitations: ["Agent 已完成或已清理，TraceFence 没有可继续的运行时会话。"],
                deliveryModes: []
            )
        }

        if session.pendingQuestion != nil {
            return TraceFenceSessionControlCapability(
                mode: "hook_question",
                available: true,
                canInterrupt: false,
                canResume: true,
                resumeRequiresInstruction: true,
                note: "请输入回复或下一步指令；TraceFence 会通过 HookServer continuation 送回等待中的 Agent。",
                reason: "hook_waiting_input",
                limitations: ["此能力只在 Agent bridge 正在等待问题回复时有效。"],
                deliveryModes: ["hook_question"]
            )
        }

        if session.pendingPermission != nil || session.pendingPlan != nil {
            return TraceFenceSessionControlCapability(
                mode: "hook_approval",
                available: true,
                canInterrupt: false,
                canResume: false,
                resumeRequiresInstruction: false,
                note: "此会话正在等待审批，请在待审批操作中批准或拒绝；这条路径会真正恢复等待中的 Agent。",
                reason: "hook_waiting_approval",
                limitations: ["审批类任务需要使用批准/拒绝按钮，不通过继续按钮注入指令。"],
                deliveryModes: ["hook_approval"]
            )
        }

        guard supportsExternalControlPlane else {
            return TraceFenceSessionControlCapability(
                mode: "display_only",
                available: false,
                canInterrupt: false,
                canResume: false,
                resumeRequiresInstruction: false,
                note: "Mac App Store 沙盒版仅对等待输入和 Hook 审批提供远程操作。",
                reason: "app_store_sandbox",
                limitations: ["外部 CLI/PTY 与进程信号控制仅在官网版提供。"],
                deliveryModes: []
            )
        }

        if let pid = session.pid,
           let target = processControlTarget(rootPID: Int(pid), sessionLabel: session.agentType, sourcePath: session.cwd) {
            let canInterrupt = session.phase != .interrupted && session.phase != .done
            let canResume = session.phase == .interrupted
            let hasTTY = target.ttyPath != nil
            return TraceFenceSessionControlCapability(
                mode: target.mode,
                available: canInterrupt || canResume || hasTTY,
                canInterrupt: canInterrupt,
                canResume: canResume,
                resumeRequiresInstruction: false,
                note: hasTTY
                    ? "TraceFence 找到了可控终端进程；可执行进程组暂停/恢复，新指令会尝试写入该终端。"
                    : "TraceFence 找到了可控进程；可执行进程级暂停/恢复，但不能保证注入新的 Agent 指令。",
                reason: "live_process_bound",
                limitations: [
                    "SIGSTOP/SIGCONT 只能暂停或恢复本地进程，不能修改模型上下文。",
                    "只有 TraceFence 识别为安全归属的 Agent 进程或进程组会被控制。"
                ],
                deliveryModes: hasTTY ? ["signal", "tty"] : ["signal"]
            )
        }

        let hasPID = session.pid != nil
        return TraceFenceSessionControlCapability(
            mode: "display_only",
            available: false,
            canInterrupt: false,
            canResume: false,
            resumeRequiresInstruction: false,
            note: hasPID
                ? "TraceFence 有 Hook 会话记录，但没有找到可安全控制的终端进程或进程组。"
                : "此 Hook 会话没有上报运行时 pid/tty；只能显示状态和审批事件。",
            reason: hasPID ? "unsafe_or_unknown_process" : "runtime_not_reported",
            limitations: [
                "需要 Agent bridge 上报 pid/tty，或通过 TraceFence 创建可控会话，才能进行真实远程控制。"
            ],
            deliveryModes: []
        )
    }

    private func monitorSessionControlCapability(
        _ session: AgentMonitorSessionSnapshot,
        phase: String
    ) -> TraceFenceSessionControlCapability {
        guard phase != "done" else {
            return TraceFenceSessionControlCapability(
                mode: "display_only",
                available: false,
                canInterrupt: false,
                canResume: false,
                resumeRequiresInstruction: false,
                note: "此任务已经结束，只能查看历史记录。",
                reason: "session_done",
                limitations: ["这是历史记录，不是仍在运行的 Agent runtime。"],
                deliveryModes: []
            )
        }

        guard supportsExternalControlPlane else {
            return TraceFenceSessionControlCapability(
                mode: "display_only",
                available: false,
                canInterrupt: false,
                canResume: false,
                resumeRequiresInstruction: false,
                note: "Mac App Store 沙盒版可以监控此任务，但不能向外部进程发送暂停、恢复或终止信号。",
                reason: "app_store_sandbox",
                limitations: ["外部进程与 CLI/PTY 控制仅在官网版提供。"],
                deliveryModes: []
            )
        }

        guard let target = processControlTarget(for: session) else {
            let note: String
            let reason: String
            if session.pid == nil {
                note = "此任务来自日志或数据库快照，TraceFence 没有关联到仍在运行的可控进程。"
                reason = "snapshot_without_runtime"
            } else {
                note = "TraceFence 只能监控此任务，当前没有找到可安全控制的终端进程或 Hook bridge。"
                reason = "unsafe_or_unknown_process"
            }
            return TraceFenceSessionControlCapability(
                mode: "display_only",
                available: false,
                canInterrupt: false,
                canResume: false,
                resumeRequiresInstruction: false,
                note: note,
                reason: reason,
                limitations: [
                    "监控快照不等于可控运行时。",
                    "需要 Hook bridge、TraceFence 可控会话或 Agent API 才能插入指令。"
                ],
                deliveryModes: []
            )
        }

        let canInterrupt = phase != "interrupted"
        let canResume = phase == "interrupted" || (phase == "waitingInput" && target.ttyPath != nil)
        let requiresInstruction = phase == "waitingInput"
        let note: String
        if requiresInstruction {
            note = target.ttyPath == nil
                ? "此任务看起来在等待输入，但没有可写入终端；TraceFence 只能监控，不能可靠继续。"
                : "请输入下一步指令。TraceFence 会写入该会话终端，并恢复可控进程组。"
        } else {
            note = "此会话有可控进程目标；TraceFence 会对进程组/子进程执行暂停、恢复或终止。"
        }
        return TraceFenceSessionControlCapability(
            mode: target.mode,
            available: canInterrupt || canResume,
            canInterrupt: canInterrupt,
            canResume: canResume,
            resumeRequiresInstruction: requiresInstruction,
            note: note,
            reason: "live_process_bound",
            limitations: [
                "此路径只能控制进程执行状态，不能直接修改 Agent 的模型上下文。",
                "等待输入的任务必须有可写入终端才能从 iOS 发送新指令。"
            ],
            deliveryModes: target.ttyPath == nil ? ["signal"] : ["signal", "tty"]
        )
    }

    private func monitorSessionRemoteId(_ session: AgentMonitorSessionSnapshot) -> String {
        "monitor|\(session.id)|\(monitorSessionSourceFragment(session))"
    }

    private func monitorSessionRef(from remoteId: String) -> (id: String, sourceFragment: String?)? {
        guard remoteId.hasPrefix("monitor|") else { return nil }
        let raw = String(remoteId.dropFirst("monitor|".count))
        guard !raw.isEmpty else { return nil }
        guard let separator = raw.lastIndex(of: "|") else {
            return (raw, nil)
        }
        let id = String(raw[..<separator])
        let fragment = String(raw[raw.index(after: separator)...])
        guard !id.isEmpty, !fragment.isEmpty else {
            return (raw, nil)
        }
        return (id, fragment)
    }

    private func monitorSessionSourceFragment(_ session: AgentMonitorSessionSnapshot) -> String {
        let seed = [
            session.sourcePath,
            session.projectPath,
            session.projectName,
            session.agentName
        ].joined(separator: "|")
        return Self.stableIDFragment(seed)
    }

    private func continuationInstruction(from body: [String: Any]) -> String? {
        for key in ["instruction", "message", "answer", "prompt"] {
            if let value = body[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func relaunchPayload(_ plan: TraceFenceSessionRelaunchPlan) -> [String: Any] {
        [
            "canRelaunch": true,
            "relaunchControlMode": "tracefence_relaunch",
            "relaunchTargetId": plan.target.id,
            "relaunchTargetName": plan.target.displayName,
            "relaunchInstruction": plan.instruction,
            "relaunchNote": plan.note
        ]
    }

    private func relaunchPlan(for session: SessionState) -> TraceFenceSessionRelaunchPlan? {
        let seed = session.lastUserMessage ?? session.sessionTitle ?? session.description ?? session.project
        return relaunchPlan(
            agentName: session.agentType,
            sourcePath: session.cwd,
            model: session.engineLabel,
            title: seed,
            projectName: session.project,
            cwd: session.cwd
        )
    }

    private func relaunchPlan(for session: AgentMonitorSessionSnapshot, title: String) -> TraceFenceSessionRelaunchPlan? {
        relaunchPlan(
            agentName: session.agentName,
            sourcePath: session.sourcePath,
            model: session.model,
            title: title,
            projectName: session.projectName.isEmpty ? session.projectPath : session.projectName,
            cwd: session.projectPath
        )
    }

    private func relaunchPlan(
        agentName: String,
        sourcePath: String,
        model: String?,
        title: String,
        projectName: String,
        cwd: String
    ) -> TraceFenceSessionRelaunchPlan? {
        guard let target = preferredRelaunchTarget(
            agentName: agentName,
            sourcePath: sourcePath,
            model: model,
            title: title
        ) else {
            return nil
        }
        guard let instruction = relaunchInstruction(
            seed: title,
            agentName: agentName,
            projectName: projectName,
            sourcePath: sourcePath
        ) else {
            return nil
        }

        return TraceFenceSessionRelaunchPlan(
            target: target,
            instruction: instruction,
            cwd: relaunchWorkingDirectory(cwd),
            note: "TraceFence 会在 Mac 上打开一个新的可控会话承接此任务，随后可以从 iPhone 发送新指令。"
        )
    }

    private func relaunchInstruction(
        seed: String,
        agentName: String,
        projectName: String,
        sourcePath: String
    ) -> String? {
        let task = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard task.count >= 8 else { return nil }
        let lower = task.lowercased()
        let weakTitles = [
            "codex session",
            "claude code session",
            "agent session",
            "history",
            "done",
            "idle"
        ]
        guard !weakTitles.contains(where: { lower == $0 }) else { return nil }

        var lines = [
            "请继续处理以下 TraceFence 在 Mac 上监控到的 \(agentName) 任务。",
            "",
            "原任务：",
            task
        ]
        let project = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !project.isEmpty {
            lines.append("")
            lines.append("项目：\(project)")
        }
        if !sourcePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("来源：\(sourcePath)")
        }
        lines.append("")
        lines.append("请先检查当前目录和已有变更，再继续执行。")
        return lines.joined(separator: "\n")
    }

    private func preferredRelaunchTarget(
        agentName: String,
        sourcePath: String,
        model: String?,
        title: String
    ) -> AgentPTYLaunchTargetSnapshot? {
        let text = "\(agentName) \(sourcePath) \(model ?? "") \(title)".lowercased()
        let candidates: [String]
        if text.contains("codex") {
            candidates = ["codex"]
        } else if text.contains("claude") {
            candidates = ["claude"]
        } else if text.contains("qwen") {
            candidates = ["qwen"]
        } else if text.contains("grok") {
            candidates = ["grok"]
        } else if text.contains("gemini") {
            candidates = ["gemini"]
        } else if text.contains("cursor") {
            candidates = ["cursor-agent"]
        } else if text.contains("opencode") || text.contains("open-code") {
            candidates = ["opencode"]
        } else if text.contains("aider") {
            candidates = ["aider"]
        } else if text.contains("amp") {
            candidates = ["amp"]
        } else if text.contains("goose") {
            candidates = ["goose"]
        } else {
            candidates = []
        }
        return candidates.compactMap(installedPTYLaunchTarget(id:)).first
    }

    private func installedPTYLaunchTarget(id: String) -> AgentPTYLaunchTargetSnapshot? {
        AgentPTYRuntimeService.shared.launchTargets.first { $0.id == id && $0.installed }
    }

    private func relaunchWorkingDirectory(_ cwd: String) -> String {
        let trimmed = cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return SandboxPaths.realHomeDirectory }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory) else {
            return SandboxPaths.realHomeDirectory
        }
        if isDirectory.boolValue {
            return trimmed
        }
        return URL(fileURLWithPath: trimmed).deletingLastPathComponent().path
    }

    private func relaunchSession(
        sessionId: String,
        requestedTargetId: String?,
        instruction: String?,
        requestBody: [String: Any] = [:]
    ) async -> [String: Any] {
        if ptySessionId(from: sessionId) != nil {
            return [
                "ok": false,
                "command": "session_relaunch",
                "sessionId": sessionId,
                "error": "already_controllable",
                "message": "此任务已经是 TraceFence 可控会话，请直接发送指令。"
            ]
        }

        let fallbackPlan = fallbackRelaunchPlan(from: requestBody, requestedTargetId: requestedTargetId)
        if let monitorRef = monitorSessionRef(from: sessionId) {
            let store = resolvedOverviewStore()
            guard let session = store.sessions.first(where: { session in
                guard session.id == monitorRef.id else { return false }
                guard let sourceFragment = monitorRef.sourceFragment else { return true }
                return monitorSessionSourceFragment(session) == sourceFragment
            }) else {
                if let fallbackPlan {
                    return launchRelaunchSession(
                        originalSessionId: sessionId,
                        plan: fallbackPlan,
                        requestedTargetId: requestedTargetId,
                        instruction: instruction
                    )
                }
                return [
                    "ok": false,
                    "command": "session_relaunch",
                    "error": "session_not_found",
                    "sessionId": sessionId,
                    "message": "此任务快照已刷新或不可用，请刷新后重试。"
                ]
            }
            let title = session.currentTask.isEmpty ? (session.projectName.isEmpty ? session.agentName : session.projectName) : session.currentTask
            guard let plan = relaunchPlan(for: session, title: title) ?? fallbackPlan else {
                return relaunchUnavailableResponse(sessionId: sessionId)
            }
            return launchRelaunchSession(
                originalSessionId: sessionId,
                plan: plan,
                requestedTargetId: requestedTargetId,
                instruction: instruction
            )
        }

        guard let session = await sessionStore?.getSession(sessionId) else {
            if let fallbackPlan {
                return launchRelaunchSession(
                    originalSessionId: sessionId,
                    plan: fallbackPlan,
                    requestedTargetId: requestedTargetId,
                    instruction: instruction
                )
            }
            return [
                "ok": false,
                "command": "session_relaunch",
                "error": "session_not_found",
                "sessionId": sessionId,
                "message": "此任务会话已结束或不可用，请刷新后重试。"
            ]
        }
        guard let plan = relaunchPlan(for: session) ?? fallbackPlan else {
            return relaunchUnavailableResponse(sessionId: sessionId)
        }
        return launchRelaunchSession(
            originalSessionId: sessionId,
            plan: plan,
            requestedTargetId: requestedTargetId,
            instruction: instruction
        )
    }

    private func relaunchUnavailableResponse(sessionId: String) -> [String: Any] {
        [
            "ok": false,
            "command": "session_relaunch",
            "sessionId": sessionId,
            "error": "relaunch_unavailable",
            "message": "此任务没有可识别且已安装的本地 Agent 目标，无法接管。"
        ]
    }

    private func fallbackRelaunchPlan(from body: [String: Any], requestedTargetId: String?) -> TraceFenceSessionRelaunchPlan? {
        let agentName = firstString(in: body, keys: ["agentType", "agentName"]) ?? "Agent"
        let sourcePath = firstString(in: body, keys: ["sourcePath", "lastToolTarget"]) ?? ""
        let model = firstString(in: body, keys: ["engineLabel", "model"])
        let title = firstString(in: body, keys: ["title", "displayTitle", "lastResponse", "lastThought"]) ?? ""
        let projectName = firstString(in: body, keys: ["project", "projectName"]) ?? ""
        let cwd = firstString(in: body, keys: ["cwd", "workingDirectory", "projectPath"]) ?? projectName
        let target = requestedTargetId.flatMap(installedPTYLaunchTarget(id:))
            ?? firstString(in: body, keys: ["relaunchTargetId"]).flatMap(installedPTYLaunchTarget(id:))
            ?? preferredRelaunchTarget(agentName: agentName, sourcePath: sourcePath, model: model, title: title)
        guard let target else { return nil }

        let instruction = firstString(in: body, keys: ["relaunchInstruction"])
            ?? relaunchInstruction(seed: title, agentName: agentName, projectName: projectName, sourcePath: sourcePath)
        guard let instruction, !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        return TraceFenceSessionRelaunchPlan(
            target: target,
            instruction: instruction,
            cwd: relaunchWorkingDirectory(cwd),
            note: "TraceFence 会在 Mac 上打开一个新的可控会话承接此任务，随后可以从 iPhone 发送新指令。"
        )
    }

    private func firstString(in body: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = body[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func launchRelaunchSession(
        originalSessionId: String,
        plan: TraceFenceSessionRelaunchPlan,
        requestedTargetId: String?,
        instruction: String?
    ) -> [String: Any] {
        let selectedTargetId = requestedTargetId ?? plan.target.id
        guard let target = installedPTYLaunchTarget(id: selectedTargetId) else {
            return [
                "ok": false,
                "command": "session_relaunch",
                "sessionId": originalSessionId,
                "error": "target_not_installed",
                "message": "这台 Mac 上没有安装 \(selectedTargetId)，无法接管。"
            ]
        }

        let instructionText = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialInstruction = instructionText?.isEmpty == false ? instructionText! : plan.instruction
        do {
            let session = try AgentPTYRuntimeService.shared.launch(
                targetId: target.id,
                cwd: plan.cwd,
                initialInstruction: initialInstruction
            )
            return [
                "ok": true,
                "command": "session_relaunch",
                "sessionId": originalSessionId,
                "launchedSessionId": ptyRemoteId(session.id),
                "relaunchTargetId": target.id,
                "relaunchTargetName": target.displayName,
                "instructionAccepted": !initialInstruction.isEmpty,
                "instructionDelivered": !initialInstruction.isEmpty,
                "deliveryMode": "pty",
                "controlMode": "tracefence_pty",
                "controlAvailable": true,
                "controlReason": "tracefence_owned_pty",
                "message": "TraceFence 已接管任务并创建一个可远程控制的会话。"
            ]
        } catch {
            return [
                "ok": false,
                "command": "session_relaunch",
                "sessionId": originalSessionId,
                "error": "relaunch_failed",
                "message": error.localizedDescription
            ]
        }
    }

    private func approvalRef(from body: [String: Any]) -> ApprovalRef? {
        if let id = body["approvalId"] as? String {
            return parseApprovalId(id)
        }
        guard let kind = body["kind"] as? String,
              let sessionId = body["sessionId"] as? String else {
            return nil
        }
        return ApprovalRef(kind: kind, sessionId: sessionId, toolName: body["toolName"] as? String)
    }

    private func resolveApproval(_ approval: ApprovalRef, allow: Bool, body: [String: Any]) async -> String {
        switch approval.kind {
        case "permission":
            guard let toolName = approval.toolName, !toolName.isEmpty else {
                return "Missing permission tool name."
            }
            let decision: PermissionDecision = allow
                ? .allow
                : .deny(reason: body["reason"] as? String ?? "Denied from TraceFence Sentinel")
            await hookServer?.respondToPermission(sessionId: approval.sessionId, toolName: toolName, decision: decision)
            await sessionStore?.setPendingPermission(approval.sessionId, nil)
            await sessionStore?.updatePhase(approval.sessionId, phase: allow ? .processing : .interrupted)
            return allow ? "Permission approved." : "Permission denied."
        case "question":
            let answer = (body["answer"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = allow ? "Continue" : "Denied from TraceFence Sentinel"
            await hookServer?.respondToQuestion(sessionId: approval.sessionId, answer: answer?.isEmpty == false ? answer! : fallback)
            await sessionStore?.setPendingQuestion(approval.sessionId, nil)
            await sessionStore?.updatePhase(approval.sessionId, phase: allow ? .processing : .interrupted)
            return allow ? "Question answered." : "Question denied."
        case "plan":
            await hookServer?.respondToPlan(
                sessionId: approval.sessionId,
                mode: allow ? "accept" : "cancel",
                message: allow ? nil : (body["reason"] as? String ?? "Denied from TraceFence Sentinel")
            )
            await sessionStore?.setPendingPlan(approval.sessionId, nil)
            await sessionStore?.updatePhase(approval.sessionId, phase: allow ? .processing : .interrupted)
            return allow ? "Plan approved." : "Plan denied."
        default:
            return "Unsupported approval type."
        }
    }

    private func applySessionCommand(_ command: SessionCommand, sessionId: String, instruction: String?) async -> [String: Any] {
        if let threadId = codexThreadId(from: sessionId) {
            guard supportsExternalControlPlane else {
                return distributionLimitedCommandPayload(command, sessionId: sessionId)
            }
            let result: CodexControlResult
            switch command {
            case .interrupt, .terminate:
                result = await CodexControlPlaneService.shared.interrupt(threadId: threadId)
            case .resume:
                let text = instruction?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                result = await CodexControlPlaneService.shared.sendInstruction(
                    threadId: threadId,
                    instruction: text.isEmpty ? "请继续执行这个任务。" : text
                )
            }
            return codexResultPayload(result, sessionId: sessionId)
        }

        if let ptyId = ptySessionId(from: sessionId) {
            guard supportsExternalControlPlane else {
                return distributionLimitedCommandPayload(command, sessionId: sessionId)
            }
            return applyPTYSessionCommand(command, sessionId: ptyId, remoteSessionId: sessionId, instruction: instruction)
        }

        if let monitorRef = monitorSessionRef(from: sessionId) {
            guard supportsExternalControlPlane else {
                return distributionLimitedCommandPayload(command, sessionId: sessionId)
            }
            return applyMonitorSessionCommand(
                command,
                monitorId: monitorRef.id,
                sourceFragment: monitorRef.sourceFragment,
                remoteSessionId: sessionId,
                instruction: instruction
            )
        }

        guard let session = await sessionStore?.getSession(sessionId) else {
            return ["ok": false, "error": "session_not_found", "sessionId": sessionId]
        }

        switch command {
        case .interrupt:
            guard supportsExternalControlPlane else {
                return distributionLimitedCommandPayload(command, sessionId: sessionId)
            }
            let controlResult = session.pid.flatMap { pid in
                applyProcessControl(
                    rootPID: Int(pid),
                    command: .interrupt,
                    instruction: nil,
                    sessionLabel: session.agentType,
                    sourcePath: session.cwd
                )
            }
            await sessionStore?.updateSession(sessionId) { state in
                if controlResult?.ok == true {
                    state.phase = .interrupted
                }
                state.description = controlResult?.message ?? "TraceFence Sentinel 请求中断，但此 Hook 会话没有可控进程 id。"
            }
            return [
                "ok": controlResult?.ok ?? false,
                "command": "session_interrupt",
                "sessionId": sessionId,
                "signalSent": controlResult?.signalSent ?? false,
                "controlledPids": controlResult?.controlledPids ?? [],
                "failedPids": controlResult?.failedPids ?? [],
                "controlMode": controlResult?.controlMode ?? "none",
                "controlAvailable": controlResult?.ok ?? false,
                "controlReason": controlResult?.ok == true ? "command_applied" : "runtime_not_controllable",
                "controlLimitations": controlResult?.ok == true ? [] : [
                    "此 Hook 会话没有可安全控制的运行时 pid/tty。",
                    "需要 Agent bridge 上报运行时信息，或通过 TraceFence 创建可控会话。"
                ],
                "message": controlResult?.message ?? "此 Hook 会话没有可控进程 id；请确认 Agent bridge 已上报运行时 pid。"
            ]
        case .terminate:
            guard supportsExternalControlPlane else {
                return distributionLimitedCommandPayload(command, sessionId: sessionId)
            }
            let controlResult = session.pid.flatMap { pid in
                applyProcessControl(
                    rootPID: Int(pid),
                    command: .terminate,
                    instruction: nil,
                    sessionLabel: session.agentType,
                    sourcePath: session.cwd
                )
            }
            await sessionStore?.updateSession(sessionId) { state in
                if controlResult?.ok == true {
                    state.phase = .done
                }
                state.description = controlResult?.message ?? "TraceFence Sentinel 请求终止任务，但此 Hook 会话没有可控进程 id。"
            }
            return [
                "ok": controlResult?.ok ?? false,
                "command": command.responseName,
                "sessionId": sessionId,
                "signalSent": controlResult?.signalSent ?? false,
                "controlledPids": controlResult?.controlledPids ?? [],
                "failedPids": controlResult?.failedPids ?? [],
                "controlMode": controlResult?.controlMode ?? "none",
                "controlAvailable": controlResult?.ok ?? false,
                "controlReason": controlResult?.ok == true ? "command_applied" : "runtime_not_controllable",
                "controlLimitations": controlResult?.ok == true ? [] : [
                    "此 Hook 会话没有可安全终止的运行时 pid/tty。",
                    "需要 Agent bridge 上报运行时信息，或通过 TraceFence 创建可控会话。"
                ],
                "message": controlResult?.message ?? "此 Hook 会话没有可控进程 id；请确认 Agent bridge 已上报运行时 pid。"
            ]
        case .resume:
            let instructionText = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
            let hasInstruction = instructionText?.isEmpty == false
            var instructionDelivered = false
            if hasInstruction, session.pendingQuestion != nil, let instructionText, let hookServer {
                await hookServer.respondToQuestion(sessionId: sessionId, answer: instructionText)
                await sessionStore?.setPendingQuestion(sessionId, nil)
                instructionDelivered = true
            }
            let controlResult = supportsExternalControlPlane ? session.pid.flatMap { pid in
                applyProcessControl(
                    rootPID: Int(pid),
                    command: .resume,
                    instruction: instructionDelivered ? nil : instructionText,
                    sessionLabel: session.agentType,
                    sourcePath: session.cwd
                )
            } : nil
            await sessionStore?.updateSession(sessionId) { state in
                if instructionDelivered || controlResult?.ok == true {
                    state.phase = .processing
                }
                if let instructionText, !instructionText.isEmpty {
                    state.lastUserMessage = instructionText
                }
                state.description = instructionDelivered
                    ? "TraceFence Sentinel 已把回复送回等待中的 Hook 会话。"
                    : (controlResult?.message ?? "TraceFence Sentinel 收到继续请求，但此 Hook 会话没有可控进程 id。")
            }
            return [
                "ok": instructionDelivered || controlResult?.ok == true,
                "command": "session_resume",
                "sessionId": sessionId,
                "instructionAccepted": hasInstruction,
                "instructionDelivered": instructionDelivered || controlResult?.instructionDelivered == true,
                "deliveryMode": instructionDelivered ? "hook_question" : (controlResult?.deliveryMode ?? (hasInstruction ? "recorded" : "none")),
                "signalSent": controlResult?.signalSent ?? false,
                "controlledPids": controlResult?.controlledPids ?? [],
                "failedPids": controlResult?.failedPids ?? [],
                "controlMode": controlResult?.controlMode ?? "none",
                "controlAvailable": instructionDelivered || controlResult?.ok == true,
                "controlReason": instructionDelivered ? "hook_question_answered" : (controlResult?.ok == true ? "command_applied" : "runtime_not_controllable"),
                "controlLimitations": instructionDelivered || controlResult?.ok == true ? [] : [
                    "TraceFence 没有 Hook continuation、可写终端或可控进程组来承载这条指令。"
                ],
                "message": instructionDelivered
                    ? "已把回复发送给等待中的 Agent。"
                    : (controlResult?.message ?? "此 Hook 会话没有可控进程 id；请确认 Agent bridge 已上报运行时 pid。")
            ]
        }
    }

    private func distributionLimitedCommandPayload(_ command: SessionCommand, sessionId: String) -> [String: Any] {
        [
            "ok": false,
            "error": "distribution_limited",
            "command": command.responseName,
            "sessionId": sessionId,
            "instructionDelivered": false,
            "controlAvailable": false,
            "controlMode": "display_only",
            "controlReason": "app_store_sandbox",
            "message": "This action requires external CLI/PTY or process control and is available only in the TraceFence website build."
        ]
    }

    private func codexResultPayload(_ result: CodexControlResult, sessionId: String?) -> [String: Any] {
        var payload: [String: Any] = [
            "ok": result.ok,
            "command": result.command,
            "instructionDelivered": result.ok,
            "deliveryMode": result.controlMode,
            "controlMode": result.controlMode,
            "controlAvailable": true,
            "controlReason": result.ok ? "codex_command_applied" : "codex_command_failed",
            "message": result.message
        ]
        if let sessionId {
            payload["sessionId"] = sessionId
        }
        if !result.ok {
            payload["error"] = "codex_command_failed"
        }
        return payload
    }

    private func applyPTYSessionCommand(
        _ command: SessionCommand,
        sessionId: String,
        remoteSessionId: String,
        instruction: String?
    ) -> [String: Any] {
        do {
            let result: AgentPTYControlResult
            let commandName: String
            switch command {
            case .interrupt:
                result = try AgentPTYRuntimeService.shared.interrupt(sessionId: sessionId)
                commandName = command.responseName
            case .resume:
                result = try AgentPTYRuntimeService.shared.resume(sessionId: sessionId, instruction: instruction)
                commandName = command.responseName
            case .terminate:
                result = try AgentPTYRuntimeService.shared.terminate(sessionId: sessionId)
                commandName = command.responseName
            }
            return [
                "ok": result.ok,
                "command": commandName,
                "sessionId": remoteSessionId,
                "instructionAccepted": instruction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                "instructionDelivered": result.instructionDelivered,
                "deliveryMode": result.deliveryMode,
                "signalSent": result.signalSent,
                "controlledPids": result.controlledPids,
                "failedPids": [],
                "controlMode": "tracefence_pty",
                "controlAvailable": true,
                "controlReason": "tracefence_owned_pty",
                "message": result.message
            ]
        } catch {
            return [
                "ok": false,
                "command": command.responseName,
                "sessionId": remoteSessionId,
                "instructionAccepted": instruction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
                "instructionDelivered": false,
                "deliveryMode": "none",
                "signalSent": false,
                "controlledPids": [],
                "failedPids": [],
                "controlMode": "tracefence_pty",
                "controlAvailable": false,
                "controlReason": "pty_command_failed",
                "controlLimitations": [
                    "TraceFence 找不到这个可控会话运行时，或进程组已经退出。"
                ],
                "message": error.localizedDescription
            ]
        }
    }

    private func applyMonitorSessionCommand(
        _ command: SessionCommand,
        monitorId: String,
        sourceFragment: String?,
        remoteSessionId: String,
        instruction: String?
    ) -> [String: Any] {
        let store = resolvedOverviewStore()
        guard let index = store.sessions.firstIndex(where: { session in
            guard session.id == monitorId else { return false }
            guard let sourceFragment else { return true }
            return monitorSessionSourceFragment(session) == sourceFragment
        }) else {
            return ["ok": false, "error": "session_not_found", "sessionId": remoteSessionId]
        }

        let session = store.sessions[index]
        let instructionText = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInstruction = instructionText?.isEmpty == false
        let nextStatus: String
        let commandName: String
        switch command {
        case .interrupt:
            nextStatus = "Paused"
            commandName = command.responseName
        case .resume:
            nextStatus = "Executing"
            commandName = command.responseName
        case .terminate:
            nextStatus = "Terminated"
            commandName = command.responseName
        }

        guard let target = processControlTarget(for: session) else {
            let message: String
            if session.pid == nil {
                message = "此任务只是监控快照，没有关联到仍在运行的可控进程。"
            } else {
                message = "TraceFence 找到了任务记录，但没有找到可安全控制的终端进程或进程组。"
            }
            return [
                "ok": false,
                "command": commandName,
                "sessionId": remoteSessionId,
                "instructionAccepted": hasInstruction,
                "instructionDelivered": false,
                "deliveryMode": hasInstruction ? "recorded" : "none",
                "signalSent": false,
                "controlledPids": [],
                "failedPids": [],
                "controlMode": "display_only",
                "controlAvailable": false,
                "controlReason": session.pid == nil ? "snapshot_without_runtime" : "unsafe_or_unknown_process",
                "controlLimitations": [
                    "监控快照不等于可控运行时。",
                    "需要 Hook bridge、TraceFence 可控会话或 Agent API 才能暂停/恢复。"
                ],
                "message": message
            ]
        }

        if command == .resume,
           monitorSessionPhase(session) == "waitingInput",
           target.ttyPath == nil {
            return [
                "ok": false,
                "command": commandName,
                "sessionId": remoteSessionId,
                "instructionAccepted": hasInstruction,
                "instructionDelivered": false,
                "deliveryMode": hasInstruction ? "recorded" : "none",
                "signalSent": false,
                "controlledPids": [],
                "failedPids": [],
                "controlMode": target.mode,
                "controlAvailable": false,
                "controlReason": "waiting_input_without_tty",
                "controlLimitations": [
                    "该任务看起来在等待输入，但 TraceFence 没有可写入的终端或 Hook continuation。",
                    "需要通过 TraceFence 创建可控会话，或安装可上报 tty/pid 的 Hook bridge。"
                ],
                "message": "无法继续：此任务需要输入，但当前没有可写入的 Agent 终端。"
            ]
        }

        let controlResult = applyProcessControl(
            target: target,
            command: command,
            instruction: command == .resume ? instructionText : nil
        )

        if controlResult.ok || hasInstruction {
            store.sessions[index] = updatedMonitorSession(
                session,
                status: controlResult.ok ? nextStatus : session.status,
                currentTask: instructionText
            )
        }

        return [
            "ok": controlResult.ok,
            "command": commandName,
            "sessionId": remoteSessionId,
            "instructionAccepted": hasInstruction,
            "instructionDelivered": controlResult.instructionDelivered,
            "deliveryMode": controlResult.deliveryMode,
            "signalSent": controlResult.signalSent,
            "controlledPids": controlResult.controlledPids,
            "failedPids": controlResult.failedPids,
            "controlMode": controlResult.controlMode,
            "controlAvailable": controlResult.ok,
            "controlReason": controlResult.ok ? "command_applied" : "command_failed",
            "message": controlResult.message
        ]
    }

    private func updatedMonitorSession(_ session: AgentMonitorSessionSnapshot, status: String, currentTask: String? = nil) -> AgentMonitorSessionSnapshot {
        AgentMonitorSessionSnapshot(
            id: session.id,
            agentName: session.agentName,
            pid: session.pid,
            sessionId: session.sessionId,
            status: status,
            projectName: session.projectName,
            projectPath: session.projectPath,
            model: session.model,
            tokens: session.tokens,
            contextPercent: session.contextPercent,
            contextWindow: session.contextWindow,
            turnCount: session.turnCount,
            currentTask: currentTask?.isEmpty == false ? currentTask! : session.currentTask,
            toolCount: session.toolCount,
            runningToolCount: session.runningToolCount,
            childCount: session.childCount,
            ports: session.ports,
            memoryMB: session.memoryMB,
            latestActivity: Date(),
            instructionDate: session.instructionDate,
            sourcePath: session.sourcePath
        )
    }

    private func applyProcessControl(
        rootPID: Int,
        command: SessionCommand,
        instruction: String?,
        sessionLabel: String,
        sourcePath: String
    ) -> TraceFenceProcessControlResult {
        guard let target = processControlTarget(
            rootPID: rootPID,
            sessionLabel: sessionLabel,
            sourcePath: sourcePath
        ) else {
            return TraceFenceProcessControlResult(
                ok: false,
                signalSent: false,
                controlledPids: [],
                failedPids: [],
                controlMode: "none",
                instructionDelivered: false,
                deliveryMode: instruction?.isEmpty == false ? "recorded" : "none",
                message: "TraceFence 没有找到可安全控制的 Agent 进程。"
            )
        }
        return applyProcessControl(target: target, command: command, instruction: instruction)
    }

    private func applyProcessControl(
        target: TraceFenceProcessControlTarget,
        command: SessionCommand,
        instruction: String?
    ) -> TraceFenceProcessControlResult {
        let signal: Int32
        switch command {
        case .interrupt:
            signal = SIGSTOP
        case .resume:
            signal = SIGCONT
        case .terminate:
            signal = SIGTERM
        }
        let instructionText = instruction?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasInstruction = instructionText?.isEmpty == false

        var instructionDelivered = false
        var deliveryMode = "none"
        if command == .resume, hasInstruction, let instructionText {
            if let ttyPath = target.ttyPath, sendInstructionToTTYPath(ttyPath, instruction: instructionText) {
                instructionDelivered = true
                deliveryMode = "tty"
            } else {
                deliveryMode = "recorded"
            }
        }

        var controlledPids: [Int] = []
        var failedPids: [Int] = []
        if let pgid = target.pgid, target.mode == "process_group" {
            if Darwin.kill(pid_t(-pgid), signal) == 0 {
                controlledPids = target.targetPids
            } else {
                let fallback = signalPids(target.targetPids, signal: signal)
                controlledPids = fallback.sent
                failedPids = fallback.failed
            }
        } else {
            let result = signalPids(target.targetPids, signal: signal)
            controlledPids = result.sent
            failedPids = result.failed
        }

        let signalSent = !controlledPids.isEmpty
        let ok = signalSent || instructionDelivered
        let signalVerb: String
        switch command {
        case .interrupt: signalVerb = "暂停"
        case .resume: signalVerb = "恢复"
        case .terminate: signalVerb = "终止"
        }
        let message: String
        if ok {
            if instructionDelivered && signalSent {
                message = "已写入新指令，并对 \(controlledPids.count) 个 Agent 进程发送 \(signalName(signal))。"
            } else if instructionDelivered {
                message = "已把新指令写入 Agent 终端。"
            } else {
                message = "已对 \(controlledPids.count) 个 Agent 进程发送 \(signalName(signal))，执行\(signalVerb)。"
            }
        } else if hasInstruction {
            message = "已收到指令，但没有可写入的终端或可控制的进程；该任务需要 Hook bridge 或 Agent 原生远程控制接口。"
        } else {
            message = "没有可控制的 Agent 进程；该任务可能只是日志/数据库监控快照，或属于无法逐任务控制的桌面 App。"
        }

        return TraceFenceProcessControlResult(
            ok: ok,
            signalSent: signalSent,
            controlledPids: controlledPids,
            failedPids: failedPids,
            controlMode: target.mode,
            instructionDelivered: instructionDelivered,
            deliveryMode: deliveryMode,
            message: message
        )
    }

    private func signalPids(_ pids: [Int], signal: Int32) -> (sent: [Int], failed: [Int]) {
        var sent: [Int] = []
        var failed: [Int] = []
        for pid in pids {
            if Darwin.kill(pid_t(pid), signal) == 0 {
                sent.append(pid)
            } else {
                failed.append(pid)
            }
        }
        return (sent, failed)
    }

    private func signalName(_ signal: Int32) -> String {
        switch signal {
        case SIGSTOP: return "SIGSTOP"
        case SIGCONT: return "SIGCONT"
        case SIGTERM: return "SIGTERM"
        default: return "signal \(signal)"
        }
    }

    private func processControlTarget(for session: AgentMonitorSessionSnapshot) -> TraceFenceProcessControlTarget? {
        guard let pid = session.pid else { return nil }
        return processControlTarget(
            rootPID: pid,
            sessionLabel: session.agentName,
            sourcePath: session.sourcePath
        )
    }

    private func processControlTarget(
        rootPID: Int,
        sessionLabel: String,
        sourcePath: String
    ) -> TraceFenceProcessControlTarget? {
        let table = currentProcessTable()
        guard let root = table[rootPID],
              isControllableAgentProcess(root, sessionLabel: sessionLabel, sourcePath: sourcePath) else {
            return nil
        }

        let children = childrenMap(from: table)
        let descendants = descendantPids(of: rootPID, children: children)
        let groupPids = table.values
            .filter { $0.pgid == root.pgid }
            .map(\.pid)
        let groupIsSafe = root.pgid > 1 && !groupPids.contains(where: { pid in
            guard let process = table[pid] else { return true }
            return isUnsafeToSignal(process)
        })

        let rawPids: [Int]
        let pgid: Int?
        let mode: String
        if groupIsSafe, root.hasTTY || groupPids.count > 1 {
            rawPids = groupPids
            pgid = root.pgid
            mode = "process_group"
        } else {
            rawPids = [rootPID] + descendants
            pgid = nil
            mode = descendants.isEmpty ? "single_process" : "process_tree"
        }

        let targetPids = Array(Set(rawPids))
            .filter { pid in
                guard let process = table[pid] else { return false }
                return !isUnsafeToSignal(process)
            }
            .sorted()
        guard !targetPids.isEmpty else { return nil }

        return TraceFenceProcessControlTarget(
            rootPID: rootPID,
            targetPids: targetPids,
            pgid: pgid,
            mode: mode,
            ttyPath: ttyPath(from: root),
            command: root.command
        )
    }

    private func currentProcessTable() -> [Int: TraceFenceProcessSnapshot] {
        if let cache = processTableCache,
           Date().timeIntervalSince(cache.timestamp) < 1.5 {
            return cache.table
        }

        let output = shellOutput(
            "/bin/ps",
            ["-ww", "-axo", "pid=,ppid=,pgid=,stat=,tty=,command="],
            timeout: 2
        )
        var table: [Int: TraceFenceProcessSnapshot] = [:]
        for line in output.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
            guard parts.count >= 6,
                  let pid = Int(parts[0]),
                  let ppid = Int(parts[1]),
                  let pgid = Int(parts[2]) else {
                continue
            }
            table[pid] = TraceFenceProcessSnapshot(
                pid: pid,
                ppid: ppid,
                pgid: pgid,
                stat: String(parts[3]),
                tty: String(parts[4]),
                command: String(parts[5])
            )
        }
        processTableCache = (Date(), table)
        return table
    }

    private func childrenMap(from table: [Int: TraceFenceProcessSnapshot]) -> [Int: [Int]] {
        var children: [Int: [Int]] = [:]
        for process in table.values {
            children[process.ppid, default: []].append(process.pid)
        }
        return children
    }

    private func descendantPids(of pid: Int, children: [Int: [Int]]) -> [Int] {
        var result: [Int] = []
        var stack = children[pid] ?? []
        var seen: Set<Int> = []
        while let next = stack.popLast() {
            guard seen.insert(next).inserted else { continue }
            result.append(next)
            stack.append(contentsOf: children[next] ?? [])
        }
        return result
    }

    private func isControllableAgentProcess(
        _ process: TraceFenceProcessSnapshot,
        sessionLabel: String,
        sourcePath: String
    ) -> Bool {
        guard !isUnsafeToSignal(process) else { return false }
        let command = process.command.lowercased()
        let source = sourcePath.lowercased()

        if process.hasTTY {
            return true
        }

        if source.hasSuffix(".sqlite") || source.hasSuffix(".db") || source.hasSuffix(".vscdb") {
            return false
        }

        if command.contains("/applications/codex.app/") ||
            command.contains("/applications/claude.app/") ||
            command.contains("/applications/cursor.app/") ||
            command.contains("/applications/trae.app/") {
            return false
        }

        if isKnownHelperProcess(command) {
            return false
        }

        let label = sessionLabel.lowercased()
        let cliMarkers = [
            "codex exec", "/codex ", " claude ", "/claude ",
            "opencode", "open-code", "aider", "gemini",
            "qoder", "codebuddy", "minimax", "mavis"
        ]
        return cliMarkers.contains { command.contains($0) || label.contains($0.trimmingCharacters(in: .whitespaces)) }
    }

    private func isUnsafeToSignal(_ process: TraceFenceProcessSnapshot) -> Bool {
        let command = process.command.lowercased()
        let currentPID = Int(ProcessInfo.processInfo.processIdentifier)
        if process.pid <= 1 || process.pid == currentPID {
            return true
        }
        if command.contains("/applications/tracefence.app/") ||
            command.contains("/aimaccleaner") ||
            command == "launchd" ||
            command.contains("loginwindow") ||
            command.contains("windowserver") {
            return true
        }
        return false
    }

    private func isKnownHelperProcess(_ command: String) -> Bool {
        let helpers = [
            "crashpad", "renderer", "--type=", "node_repl",
            "skycomputeruseclient", "xcodebuildmcp", "mcp",
            "bare-modifier-monitor", "squirrel.framework", "shipit"
        ]
        return helpers.contains { command.contains($0) }
    }

    private func ttyPath(from process: TraceFenceProcessSnapshot) -> String? {
        guard process.hasTTY else { return nil }
        return process.tty.hasPrefix("/") ? process.tty : "/dev/\(process.tty)"
    }

    private func shellOutput(_ executable: String, _ arguments: [String], timeout: TimeInterval = 2) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("tracefence-process-\(UUID().uuidString).out")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)

        guard let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return ""
        }
        let nullHandle = try? FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
        process.standardOutput = outputHandle
        process.standardError = nullHandle ?? Pipe()

        defer {
            try? outputHandle.close()
            try? nullHandle?.close()
            try? FileManager.default.removeItem(at: outputURL)
        }

        do {
            try process.run()
        } catch {
            return ""
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.05)
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        try? outputHandle.synchronize()

        guard let data = try? Data(contentsOf: outputURL) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func sendInstructionToProcessTTY(pid: Int, instruction: String) -> Bool {
        guard let ttyPath = controllingTTYPath(for: pid) else { return false }
        return sendInstructionToTTYPath(ttyPath, instruction: instruction)
    }

    private func sendInstructionToTTYPath(_ ttyPath: String, instruction: String) -> Bool {
        let payload = instruction.hasSuffix("\n") ? instruction : instruction + "\n"
        guard let data = payload.data(using: .utf8) else { return false }
        let fd = open(ttyPath, O_WRONLY | O_NONBLOCK)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let written = data.withUnsafeBytes { buffer -> Int in
            guard let baseAddress = buffer.baseAddress else { return -1 }
            return write(fd, baseAddress, data.count)
        }
        return written == data.count
    }

    private func controllingTTYPath(for pid: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", "\(pid)", "-o", "tty="]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let tty = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !tty.isEmpty, tty != "??", tty != "-" else { return nil }
        return tty.hasPrefix("/") ? tty : "/dev/\(tty)"
    }

    private func approvalId(kind: String, sessionId: String, toolName: String?) -> String {
        [kind, sessionId, toolName ?? ""].joined(separator: "|")
    }

    private func parseApprovalId(_ id: String) -> ApprovalRef? {
        let parts = id.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else { return nil }
        return ApprovalRef(kind: parts[0], sessionId: parts[1], toolName: parts.count > 2 && !parts[2].isEmpty ? parts[2] : nil)
    }

    private func sessionLastActivity(_ session: SessionState) -> Date {
        let toolDate = session.activeTools.last?.completedAt ?? session.activeTools.last?.startedAt
        let approvalDate = session.approvalHistory.last?.resolvedAt ?? session.approvalHistory.last?.requestedAt
        return [toolDate, approvalDate, session.endedAt, session.startedAt]
            .compactMap { $0 }
            .max() ?? session.startedAt
    }

    private func riskLevel(for toolName: String, detail: String) -> String {
        let text = "\(toolName) \(detail)".lowercased()
        if text.contains("delete") || text.contains("remove") || text.contains("rm ") || text.contains("sudo") {
            return "critical"
        }
        if text.contains("write") || text.contains("edit") || text.contains("shell") || text.contains("bash") || text.contains("exec") {
            return "high"
        }
        return "medium"
    }

    private func subscriptionPayload() -> [String: Any] {
        if TraceFenceDistributionPolicy.currentChannel.isAppStore {
            return [
                "channel": TraceFenceDistributionPolicy.currentChannel.rawValue,
                "tier": AppStoreSubscriptionService.shared.isSubscribed ? TraceFenceSubscriptionTier.appStoreStandard.rawValue : TraceFenceSubscriptionTier.none.rawValue,
                "active": AppStoreSubscriptionService.shared.isSubscribed
            ]
        }

        return [
            "channel": TraceFenceDistributionPolicy.currentChannel.rawValue,
            "tier": DirectLicenseService.shared.currentTier.rawValue,
            "active": DirectLicenseService.shared.canUseProFeatures || DirectLicenseService.shared.isTrialActive,
            "enhanced": false
        ]
    }

    private func systemPayload() -> [String: Any] {
        var payload: [String: Any] = [
            "monitoring": scannerService?.isMonitoring ?? false
        ]
        if let disk = scannerService?.diskInfo {
            payload["disk"] = [
                "totalGB": disk.totalGb,
                "usedGB": disk.usedGb,
                "freeGB": disk.freeGb,
                "usedPercent": disk.usedPct
            ]
        }
        if let hardware = scannerService?.hardwareInfo {
            payload["hardware"] = [
                "cpuUsage": hardware.cpuUsage,
                "memoryPressure": hardware.memoryPressurePct,
                "processCount": hardware.processCount,
                "uptimeSeconds": hardware.uptimeSeconds
            ]
        }
        return payload
    }

    private func sendJSON(_ body: [String: Any], status: Int, connection: NWConnection) {
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [])) ?? Data()
        let reason = Self.reasonPhrase(for: status)
        let headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: application/json; charset=utf-8",
            "Content-Length: \(data.count)",
            "Connection: close",
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Headers: Authorization, Content-Type",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "",
            ""
        ].joined(separator: "\r\n")

        var response = Data(headers.utf8)
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private var currentToken: String {
        if !didReconcileAgentCorePairingToken {
            didReconcileAgentCorePairingToken = true
            if let sharedToken = agentCorePairingToken() {
                // Direct and App Store builds have different bundle identifiers,
                // but the independently installed Agent Core is shared. Preserve
                // an existing phone pairing when the user switches channels.
                UserDefaults.standard.set(sharedToken, forKey: Self.tokenKey)
                return sharedToken
            }
        }
        if let token = UserDefaults.standard.string(forKey: Self.tokenKey), token.count >= 32 {
            return token
        }
        let token = Self.randomToken()
        UserDefaults.standard.set(token, forKey: Self.tokenKey)
        return token
    }

    private func syncAgentCoreRemoteGatewayConfig() {
        let subscription = subscriptionPayload()
        let payload: [String: Any] = [
            "port": Self.backgroundCorePort,
            "token": currentToken,
            "enabled": UserDefaults.standard.bool(forKey: Self.enabledKey),
            "controlAllowed": UserDefaults.standard.bool(forKey: Self.enabledKey) && canUseRemoteControl,
            "channel": subscription["channel"] as? String ?? TraceFenceDistributionPolicy.currentChannel.rawValue,
            "tier": subscription["tier"] as? String ?? TraceFenceSubscriptionTier.none.rawValue
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else { return }

        let configURL = agentCoreRemoteGatewayConfigURL
        let directory = configURL.deletingLastPathComponent()
        if data == lastAgentCoreConfigData, FileManager.default.fileExists(atPath: configURL.path) {
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: configURL, options: .atomic)
            chmod(configURL.path, S_IRUSR | S_IWUSR)
            lastAgentCoreConfigData = data
        } catch {
            // App Store sandbox builds may only use a separately installed Core configuration.
        }
    }

    private var agentCoreRemoteGatewayConfigURL: URL {
        URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
            .appendingPathComponent("Library/Application Support/TraceFence/Core/remote-gateway.json")
    }

    private func agentCorePairingToken() -> String? {
        guard
            let data = try? Data(contentsOf: agentCoreRemoteGatewayConfigURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let token = object["token"] as? String,
            Self.isValidPairingToken(token)
        else { return nil }
        return token
    }

    private static func isValidPairingToken(_ token: String) -> Bool {
        token.utf8.count == 64 && token.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (65...70).contains(byte) || (97...102).contains(byte)
        }
    }

    private func updateKeepAwakeState() {
        let shouldKeepAwake = UserDefaults.standard.bool(forKey: Self.enabledKey)
            && UserDefaults.standard.bool(forKey: Self.keepMacAwakeKey)
        if shouldKeepAwake {
            startKeepingMacAwake()
        } else {
            stopKeepingMacAwake()
        }
    }

    private func startKeepingMacAwake() {
        guard keepAwakeProcess?.isRunning != true else {
            isKeepingMacAwake = true
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-i", "-w", String(ProcessInfo.processInfo.processIdentifier)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.keepAwakeProcess === process else { return }
                self.keepAwakeProcess = nil
                self.isKeepingMacAwake = false
            }
        }
        do {
            try process.run()
            keepAwakeProcess = process
            isKeepingMacAwake = true
        } catch {
            keepAwakeProcess = nil
            isKeepingMacAwake = false
        }
    }

    private func stopKeepingMacAwake() {
        keepAwakeProcess?.terminationHandler = nil
        if keepAwakeProcess?.isRunning == true {
            keepAwakeProcess?.terminate()
        }
        keepAwakeProcess = nil
        isKeepingMacAwake = false
    }

    private func refreshEndpoint() {
        let address = localAddresses().first ?? "127.0.0.1"
        endpoint = Self.httpEndpoint(host: address, port: configuredPort)
    }

    private func pairingAccessEndpoints() -> [[String: Any]] {
        let port = configuredPort
        var endpoints: [[String: Any]] = []

        func append(_ url: String, label: String, kind: String) {
            let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if endpoints.contains(where: { ($0["url"] as? String) == trimmed }) { return }
            endpoints.append([
                "url": trimmed,
                "label": label,
                "kind": kind,
                "createdAt": Self.isoDate(Date())
            ])
        }

        append(endpoint, label: "Current LAN endpoint", kind: "local")
        append(Self.httpEndpoint(host: Self.bonjourHostName, port: port), label: "Bonjour / .local", kind: "bonjour")
        append(Self.httpEndpoint(host: Self.bonjourHostName, port: Self.backgroundCorePort), label: "Background Agent Core", kind: "bonjour")
        for address in localAddresses() {
            append(Self.httpEndpoint(host: address, port: port), label: "LAN address", kind: "local")
            append(Self.httpEndpoint(host: address, port: Self.backgroundCorePort), label: "Background Agent Core", kind: "local")
        }
        return endpoints
    }

    private func localAddresses() -> [String] {
        var candidates: [(score: Int, interface: String, address: String)] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return [] }
        defer { freeifaddrs(interfaces) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard let address = current.pointee.ifa_addr else { continue }
            let family = address.pointee.sa_family
            guard family == UInt8(AF_INET) || family == UInt8(AF_INET6) else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(address.pointee.sa_len)
            let result = getnameinfo(address, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            guard result == 0 else { continue }
            let value = String(cString: host)
            guard !value.hasPrefix("fe80:"), value != "::1" else { continue }
            guard !value.hasPrefix("169.254.") else { continue }
            let interface = String(cString: current.pointee.ifa_name)
            if !candidates.contains(where: { $0.address == value }) {
                candidates.append((
                    score: Self.localAddressScore(interface: interface, address: value, family: family),
                    interface: interface,
                    address: value
                ))
            }
        }
        return candidates
            .sorted {
                if $0.score != $1.score { return $0.score < $1.score }
                if $0.interface != $1.interface { return $0.interface < $1.interface }
                return $0.address < $1.address
            }
            .map(\.address)
    }

    private static func localAddressScore(interface: String, address: String, family: UInt8) -> Int {
        let octets = address.split(separator: ".")
        let secondOctet = octets.count > 1 ? Int(octets[1]) : nil
        let isIPv4 = family == UInt8(AF_INET)
        let isPrivateIPv4 = address.hasPrefix("10.")
            || address.hasPrefix("192.168.")
            || (address.hasPrefix("172.") && secondOctet.map { (16...31).contains($0) } == true)
        let isTunnel = interface.hasPrefix("utun")

        if isIPv4, interface == "en0", isPrivateIPv4 { return 0 }
        if isIPv4, interface.hasPrefix("en"), isPrivateIPv4 { return 10 }
        if isIPv4, isPrivateIPv4, !isTunnel { return 20 }
        if isIPv4, !isTunnel { return 30 }
        if isIPv4 { return 40 }
        if interface.hasPrefix("en") { return 50 }
        return 60
    }

    private static func normalizedPort(_ port: Int) -> Int {
        min(65_535, max(1_024, port))
    }

    private static func randomToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return bytes.map { String(format: "%02x", $0) }.joined()
        }
        return UUID().uuidString.replacingOccurrences(of: "-", with: "") + UUID().uuidString.replacingOccurrences(of: "-", with: "")
    }

    private static func base32Token(fromHex value: String) -> String? {
        guard value.count == 64 else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(32)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }

        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        var output = [UInt8]()
        output.reserveCapacity(52)
        var buffer: UInt16 = 0
        var bitCount = 0
        for byte in bytes {
            buffer = (buffer << 8) | UInt16(byte)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                output.append(alphabet[Int((buffer >> bitCount) & 0x1f)])
            }
            buffer = bitCount == 0 ? 0 : buffer & UInt16((1 << bitCount) - 1)
        }
        if bitCount > 0 {
            output.append(alphabet[Int((buffer << (5 - bitCount)) & 0x1f)])
        }
        return String(decoding: output, as: UTF8.self)
    }

    private static func stableIDFragment(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%016llx", hash)
    }

    private static func prettyJSONString(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private static func compactJSONString(_ value: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private static func httpEndpoint(host: String, port: Int) -> String {
        var components = URLComponents()
        components.scheme = "http"
        components.host = urlComponentsHost(host)
        components.port = port
        return components.string ?? "http://\(urlComponentsHost(host)):\(port)"
    }

    private static func urlComponentsHost(_ host: String) -> String {
        guard host.contains(":"), !host.hasPrefix("[") else { return host }
        return "[\(host)]"
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 402: return "Payment Required"
        case 413: return "Payload Too Large"
        case 404: return "Not Found"
        default: return "OK"
        }
    }

    private static func timeString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    private static var bonjourServiceName: String {
        let host = ProcessInfo.processInfo.hostName
        return host.hasSuffix(".local") ? String(host.dropLast(".local".count)) : host
    }

    private static var bonjourHostName: String {
        let serviceName = bonjourServiceName
        return serviceName.hasSuffix(".local") ? serviceName : "\(serviceName).local"
    }

    private static func isoDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

private struct ApprovalRef {
    let kind: String
    let sessionId: String
    let toolName: String?
}

private struct TraceFenceSessionRelaunchPlan {
    let target: AgentPTYLaunchTargetSnapshot
    let instruction: String
    let cwd: String
    let note: String
}

private struct TraceFenceProcessSnapshot {
    let pid: Int
    let ppid: Int
    let pgid: Int
    let stat: String
    let tty: String
    let command: String

    var isStopped: Bool {
        stat.uppercased().contains("T")
    }

    var hasTTY: Bool {
        !tty.isEmpty && tty != "??" && tty != "-"
    }
}

private struct TraceFenceProcessControlTarget {
    let rootPID: Int
    let targetPids: [Int]
    let pgid: Int?
    let mode: String
    let ttyPath: String?
    let command: String
}

private struct TraceFenceProcessControlResult {
    let ok: Bool
    let signalSent: Bool
    let controlledPids: [Int]
    let failedPids: [Int]
    let controlMode: String
    let instructionDelivered: Bool
    let deliveryMode: String
    let message: String
}

private struct TraceFenceSessionControlCapability {
    let mode: String
    let available: Bool
    let canInterrupt: Bool
    let canResume: Bool
    let resumeRequiresInstruction: Bool
    let note: String
    let reason: String
    let limitations: [String]
    let deliveryModes: [String]
}

private struct RemoteHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: String
    let jsonBody: [String: Any]

    init?(raw: String) {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let headerEnd = normalized.range(of: "\n\n")
        let headerText = headerEnd.map { String(normalized[..<$0.lowerBound]) } ?? normalized
        body = headerEnd.map { String(normalized[$0.upperBound...]) } ?? ""
        let lines = headerText.components(separatedBy: "\n")
        guard let firstLine = lines.first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        method = parts[0].uppercased()
        let rawPath = String(parts[1])
        path = rawPath.components(separatedBy: "?").first ?? rawPath

        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() {
            guard !line.isEmpty else { break }
            let headerParts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard headerParts.count == 2 else { continue }
            let key = headerParts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = headerParts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            parsedHeaders[key] = value
        }
        headers = parsedHeaders

        if let data = body.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            jsonBody = parsed
        } else {
            jsonBody = [:]
        }
    }

    static func hasCompleteRequest(_ raw: String) -> Bool {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        guard let headerEnd = normalized.range(of: "\n\n") else { return false }
        let headerText = String(normalized[..<headerEnd.lowerBound])
        let body = String(normalized[headerEnd.upperBound...])
        let lines = headerText.components(separatedBy: "\n")
        let contentLength = lines.dropFirst().compactMap { line -> Int? in
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "content-length" else {
                return nil
            }
            return Int(parts[1].trimmingCharacters(in: .whitespacesAndNewlines))
        }.first ?? 0
        return body.utf8.count >= contentLength
    }
}
