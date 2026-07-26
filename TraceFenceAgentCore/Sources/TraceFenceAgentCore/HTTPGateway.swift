import Foundation
import Network
import CryptoKit
import Darwin

final class AgentCoreHTTPGateway {
    typealias ControlResult = (ok: Bool, result: [String: Any], error: String?)

    private struct Config: Decodable {
        var port: Int
        var token: String
        var enabled: Bool?
        var controlAllowed: Bool?
        var channel: String?
        var tier: String?
    }

    private struct Request {
        var method: String
        var target: String
        var path: String
        var query: [String: String]
        var headers: [String: String]
        var body: [String: Any]
        var bodyData: Data
    }

    private struct PendingApprovalRecord {
        var threadId: String
        var requestId: Any
        var method: String
        var params: [String: Any]
    }

    private struct CompletedOperation {
        var command: String
        var message: String
        var acknowledgedAt: String
        var completedAt: Date
    }

    private let configPath: String
    private let coreVersion: String
    private let protocolVersion: Int
    private let sessionsProvider: () -> [[String: Any]]
    private let adaptersProvider: () -> [[String: Any]]
    private let controlHandler: ([String: Any]) -> ControlResult
    private let contextHandler: ([String: Any]) -> ControlResult
    private let queue = DispatchQueue(label: "com.tracefence.agent-core.http")
    private let contextQueue = DispatchQueue(
        label: "com.tracefence.agent-core.http.context",
        qos: .userInitiated,
        attributes: .concurrent
    )
    private let maxRequestBytes = 256 * 1_024
    private let requestClockSkew: TimeInterval = 5 * 60
    private let contextReader = SessionContextReader()
    private var listener: NWListener?
    private var pendingApprovals: [String: PendingApprovalRecord] = [:]
    private var resolvedApprovalIds: [String: Date] = [:]
    private var completedOperations: [String: CompletedOperation] = [:]
    private var acceptedRequestNonces: [String: Date] = [:]

    init(
        configPath: String,
        coreVersion: String,
        protocolVersion: Int,
        sessions: @escaping () -> [[String: Any]],
        adapters: @escaping () -> [[String: Any]],
        control: @escaping ([String: Any]) -> ControlResult,
        context: @escaping ([String: Any]) -> ControlResult
    ) {
        self.configPath = configPath
        self.coreVersion = coreVersion
        self.protocolVersion = protocolVersion
        sessionsProvider = sessions
        adaptersProvider = adapters
        controlHandler = control
        contextHandler = context
    }

    func start() throws {
        guard let config = loadConfig(),
              let port = NWEndpoint.Port(rawValue: UInt16(config.port)) else {
            throw NSError(domain: "TraceFenceAgentCore.HTTP", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Missing or invalid remote gateway configuration."
            ])
        }

        let parameters = NWParameters.tcp
        // A stale Core process must fail visibly instead of sharing the gateway
        // port with a replacement that may be using a different pairing token.
        parameters.allowLocalEndpointReuse = false
        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self, Self.isPrivateRemoteEndpoint(connection.endpoint) else {
                connection.cancel()
                return
            }
            self.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                fputs("TraceFenceAgentCore HTTP listener failed: \(error)\n", stderr)
            }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            var next = buffer
            if let data { next.append(data) }
            guard next.count <= maxRequestBytes else {
                sendJSON(["ok": false, "error": "request_too_large"], status: 413, on: connection)
                return
            }
            if let request = parseRequest(next) {
                route(request, on: connection)
            } else if isComplete {
                sendJSON(["ok": false, "error": "invalid_request"], status: 400, on: connection)
            } else {
                receive(on: connection, buffer: next)
            }
        }
    }

    private func parseRequest(_ data: Data) -> Request? {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerRange = data.range(of: separator),
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let first = lines.first else { return nil }
        let parts = first.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let index = line.firstIndex(of: ":") else { continue }
            let key = line[..<index].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: index)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = headerRange.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let bodyData = data[bodyStart..<(bodyStart + contentLength)]
        let body = contentLength > 0
            ? ((try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:])
            : [:]
        let target = parts[1]
        let components = URLComponents(string: "http://tracefence.local\(target)")
        let path = components?.path ?? target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? target
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            if let value = item.value { query[item.name] = value }
        }
        return Request(
            method: parts[0].uppercased(),
            target: target,
            path: path,
            query: query,
            headers: headers,
            body: body,
            bodyData: Data(bodyData)
        )
    }

    private func route(_ request: Request, on connection: NWConnection) {
        if request.path == "/v1/health" {
            sendJSON([
                "ok": true,
                "version": 2,
                "authentication": "hmac-sha256-v1",
                "service": "TraceFence Agent Core Remote Gateway",
                "coreVersion": coreVersion
            ], status: 200, on: connection)
            return
        }

        guard let config = loadConfig(), isAuthorized(request, token: config.token) else {
            sendJSON(["ok": false, "error": "unauthorized", "message": "Invalid pairing token."], status: 401, on: connection)
            return
        }
        guard config.enabled != false else {
            sendJSON(["ok": false, "error": "remote_gateway_disabled", "message": "Mac 端远程控制服务已关闭。"], status: 503, on: connection)
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/v1/status"):
            sendJSON(statusPayload(config: config), status: 200, on: connection)
        case ("GET", "/v1/agents"):
            sendJSON(agentsPayload(), status: 200, on: connection)
        case ("GET", "/v1/sessions"):
            sendJSON(sessionCatalogPayload(query: request.query), status: 200, on: connection)
        case ("POST", "/v1/sessions/context"):
            let body = request.body
            contextQueue.async { [weak self] in
                self?.sendSessionContext(body, on: connection)
            }
        case ("POST", "/v1/monitor/start"), ("POST", "/v1/monitor/stop"):
            sendJSON(statusPayload(config: config), status: 200, on: connection)
        case ("POST", "/v1/sessions/resume"):
            guard ensureControlAllowed(config, on: connection) else { return }
            controlSession(request.body, action: "instruction", on: connection)
        case ("POST", "/v1/sessions/interrupt"), ("POST", "/v1/sessions/terminate"):
            guard ensureControlAllowed(config, on: connection) else { return }
            controlSession(request.body, action: "interrupt", on: connection)
        case ("POST", "/v1/approvals/approve"):
            guard ensureControlAllowed(config, on: connection) else { return }
            resolveApproval(request.body, allow: true, on: connection)
        case ("POST", "/v1/approvals/deny"):
            guard ensureControlAllowed(config, on: connection) else { return }
            resolveApproval(request.body, allow: false, on: connection)
        case ("POST", "/v1/sessions/launch"), ("POST", "/v1/sessions/relaunch"):
            sendJSON([
                "ok": false,
                "error": "unsupported_by_background_core",
                "message": "请先打开 Mac 版 TraceFence，再创建或接管新的可控会话。"
            ], status: 409, on: connection)
        default:
            sendJSON(["ok": false, "error": "not_found"], status: 404, on: connection)
        }
    }

    private func ensureControlAllowed(_ config: Config, on connection: NWConnection) -> Bool {
        guard config.controlAllowed == true else {
            sendJSON([
                "ok": false,
                "error": "subscription_required",
                "message": "远程控制需要 Mac 端有效订阅或试用。"
            ], status: 402, on: connection)
            return false
        }
        return true
    }

    private func controlSession(_ body: [String: Any], action: String, on connection: NWConnection) {
        if replayCompletedOperation(body, on: connection) { return }
        guard let remoteId = body["sessionId"] as? String,
              let sessionId = decodedSessionId(remoteId) else {
            sendJSON(["ok": false, "error": "missing_session"], status: 400, on: connection)
            return
        }
        var params: [String: Any] = [
            "threadId": sessionId,
            "sessionId": sessionId,
            "action": action
        ]
        if sessionId.hasPrefix("adapter|") {
            let parts = sessionId.split(separator: "|", maxSplits: 2).map(String.init)
            if parts.count == 3 { params["adapterId"] = parts[1] }
        }
        if let instruction = body["instruction"] as? String, !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            params["instruction"] = instruction
        }
        let result = controlHandler(params)
        guard result.ok else {
            sendJSON(["ok": false, "error": result.error ?? "control_failed", "message": result.error ?? "Control failed."], status: 409, on: connection)
            return
        }
        var payload = agentsPayload()
        payload["command"] = result.result["command"] as? String ?? action
        payload["message"] = result.result["message"] as? String ?? "控制指令已交给 Mac 上的真实 Agent 会话。"
        acknowledgeOperation(body, payload: &payload)
        sendJSON(payload, status: 200, on: connection)
    }

    private func resolveApproval(_ body: [String: Any], allow: Bool, on connection: NWConnection) {
        if replayCompletedOperation(body, on: connection) { return }
        guard let approvalId = body["approvalId"] as? String,
              let approval = pendingApprovals[approvalId] else {
            sendJSON(["ok": false, "error": "approval_not_found"], status: 404, on: connection)
            return
        }
        var params: [String: Any] = [
            "threadId": approval.threadId,
            "action": "approval",
            "requestId": approval.requestId,
            "approvalMethod": approval.method,
            "allow": allow
        ]
        if let permissions = approval.params["permissions"] as? [String: Any] {
            params["requestedPermissions"] = permissions
        }
        if let questions = approval.params["questions"] as? [[String: Any]] {
            let ids = questions.compactMap { $0["id"] as? String }
            let defaults: [String: String] = Dictionary(uniqueKeysWithValues: questions.compactMap { question -> (String, String)? in
                guard let id = question["id"] as? String else { return nil }
                return (id, question["default"] as? String ?? "")
            })
            params["questionIds"] = ids
            params["questionDefaults"] = defaults
        }
        if let answer = body["answer"] as? String { params["answer"] = answer }

        let result = controlHandler(params)
        guard result.ok else {
            sendJSON(["ok": false, "error": result.error ?? "approval_failed", "message": result.error ?? "Approval failed."], status: 409, on: connection)
            return
        }
        pendingApprovals.removeValue(forKey: approvalId)
        resolvedApprovalIds[approvalId] = Date()
        var payload = agentsPayload()
        payload["command"] = allow ? "approval_approved" : "approval_denied"
        payload["message"] = result.result["message"] as? String ?? (allow ? "已批准 Agent 请求。" : "已拒绝 Agent 请求。")
        acknowledgeOperation(body, payload: &payload)
        sendJSON(payload, status: 200, on: connection)
    }

    private func replayCompletedOperation(_ body: [String: Any], on connection: NWConnection) -> Bool {
        guard let operationId = normalizedOperationId(body) else { return false }
        pruneCompletedOperations()
        guard let completed = completedOperations[operationId] else { return false }
        var payload = agentsPayload()
        payload["operationId"] = operationId
        payload["operationStatus"] = "succeeded"
        payload["acknowledgedAt"] = completed.acknowledgedAt
        payload["command"] = completed.command
        payload["message"] = completed.message
        sendJSON(payload, status: 200, on: connection)
        return true
    }

    private func acknowledgeOperation(_ body: [String: Any], payload: inout [String: Any]) {
        guard let operationId = normalizedOperationId(body) else { return }
        let acknowledgedAt = ISO8601DateFormatter().string(from: Date())
        let command = payload["command"] as? String ?? "completed"
        let message = payload["message"] as? String ?? "Operation completed."
        payload["operationId"] = operationId
        payload["operationStatus"] = "succeeded"
        payload["acknowledgedAt"] = acknowledgedAt
        completedOperations[operationId] = CompletedOperation(
            command: command,
            message: message,
            acknowledgedAt: acknowledgedAt,
            completedAt: Date()
        )
        pruneCompletedOperations()
    }

    private func normalizedOperationId(_ body: [String: Any]) -> String? {
        guard let value = body["operationId"] as? String else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : String(normalized.prefix(96))
    }

    private func pruneCompletedOperations() {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        completedOperations = completedOperations.filter { $0.value.completedAt >= cutoff }
        guard completedOperations.count > 200 else { return }
        let overflow = completedOperations
            .sorted { $0.value.completedAt < $1.value.completedAt }
            .prefix(completedOperations.count - 200)
        for entry in overflow {
            completedOperations.removeValue(forKey: entry.key)
        }
    }

    private func statusPayload(config: Config) -> [String: Any] {
        let addresses = localAddresses()
        return [
            "ok": true,
            "version": 2,
            "authentication": "hmac-sha256-v1",
            "app": ["name": "TraceFence Agent Core", "version": coreVersion, "build": coreVersion],
            "gateway": ["running": config.enabled != false, "endpoint": "", "port": config.port, "lastRequest": "background-core"],
            "subscription": [
                "channel": config.channel ?? "direct",
                "tier": config.tier ?? "directStandard",
                "active": config.controlAllowed == true,
                "enhanced": false
            ],
            "system": ["monitoring": true],
            "agentCore": [
                "connected": true,
                "coreVersion": coreVersion,
                "protocolVersion": protocolVersion,
                "adapters": adaptersProvider(),
                "message": "TraceFence Agent Core 已作为常驻服务连接。"
            ],
            "connectivity": [
                "noBackend": true,
                "localAddresses": addresses,
                "accessEndpoints": addresses.map { address in
                    [
                        "url": address.contains(":")
                            ? "http://[\(address)]:\(config.port)"
                            : "http://\(address):\(config.port)",
                        "label": address.hasPrefix("100.") ? "Tailnet address" : "Local address",
                        "kind": address.hasPrefix("100.") ? "vpn" : "local"
                    ]
                }
            ]
        ]
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
            let result = getnameinfo(
                address,
                socklen_t(address.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }
            let value = String(cString: host)
            guard !value.hasPrefix("fe80:"), value != "::1", !value.hasPrefix("169.254.") else { continue }
            let interface = String(cString: current.pointee.ifa_name)
            guard !candidates.contains(where: { $0.address == value }) else { continue }
            candidates.append((
                score: Self.localAddressScore(interface: interface, address: value, family: family),
                interface: interface,
                address: value
            ))
        }

        return candidates.sorted {
            if $0.score != $1.score { return $0.score < $1.score }
            if $0.interface != $1.interface { return $0.interface < $1.interface }
            return $0.address < $1.address
        }.map(\.address)
    }

    private static func localAddressScore(interface: String, address: String, family: UInt8) -> Int {
        let octets = address.split(separator: ".")
        let secondOctet = octets.count > 1 ? Int(octets[1]) : nil
        let isIPv4 = family == UInt8(AF_INET)
        let isPrivateIPv4 = address.hasPrefix("10.")
            || address.hasPrefix("192.168.")
            || (address.hasPrefix("172.") && secondOctet.map { (16...31).contains($0) } == true)
            || (address.hasPrefix("100.") && secondOctet.map { (64...127).contains($0) } == true)
        let isTunnel = interface.hasPrefix("utun")

        if isIPv4, address.hasPrefix("100."), secondOctet.map({ (64...127).contains($0) }) == true { return 0 }
        if isIPv4, interface == "en0", isPrivateIPv4 { return 10 }
        if isIPv4, interface.hasPrefix("en"), isPrivateIPv4 { return 20 }
        if isIPv4, isPrivateIPv4, !isTunnel { return 30 }
        if isIPv4, !isTunnel { return 40 }
        if isIPv4 { return 50 }
        if interface.hasPrefix("en") { return 60 }
        return 70
    }

    private func agentsPayload() -> [String: Any] {
        let tombstoneCutoff = Date().addingTimeInterval(-60)
        resolvedApprovalIds = resolvedApprovalIds.filter { $0.value >= tombstoneCutoff }
        let rawSessions = sessionsProvider()
        var refreshedApprovals: [String: PendingApprovalRecord] = [:]
        var sessions: [[String: Any]] = []
        var approvals: [[String: Any]] = []

        for raw in rawSessions {
            guard let rawId = raw["id"] as? String else { continue }
            let remoteId = encodedSessionId(rawId)
            sessions.append(sessionPayload(raw, remoteId: remoteId))
            for request in raw["requests"] as? [[String: Any]] ?? [] {
                guard let method = request["method"] as? String,
                      let requestId = request["requestId"] ?? request["id"] else { continue }
                let id = stableApprovalId(threadId: rawId, method: method, requestId: requestId)
                if resolvedApprovalIds[id] != nil { continue }
                let params = request["params"] as? [String: Any] ?? [:]
                refreshedApprovals[id] = PendingApprovalRecord(
                    threadId: rawId,
                    requestId: requestId,
                    method: method,
                    params: params
                )
                approvals.append(approvalPayload(
                    id: id,
                    sessionId: remoteId,
                    method: method,
                    params: params,
                    rawSession: raw,
                    source: request["source"] as? String
                ))
            }
        }
        pendingApprovals = refreshedApprovals

        let activeCount = sessions.filter { ($0["phase"] as? String).map { $0 != "idle" && $0 != "done" } == true }.count
        let processingCount = sessions.filter { $0["phase"] as? String == "processing" }.count
        let interruptedCount = sessions.filter { $0["phase"] as? String == "interrupted" }.count
        return [
            "ok": true,
            "version": 1,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "summary": [
                "sessionCount": sessions.count,
                "activeSessionCount": activeCount,
                "pendingApprovalCount": approvals.count,
                "processingCount": processingCount,
                "interruptedCount": interruptedCount
            ],
            "controlPlane": [
                "available": true,
                "hookSessions": false,
                "monitorSessions": true,
                "truthModel": "agent_core_adapter",
                "controlModes": [],
                "limitations": ["创建新 PTY 会话需要打开 Mac 版 TraceFence。"],
                "endpoints": ["agent-core-background"]
            ],
            "launchTargets": [],
            "sessions": sessions,
            "pendingApprovals": approvals,
            "recentEvents": []
        ]
    }

    private func sessionCatalogPayload(query: [String: String]) -> [String: Any] {
        let search = (query["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let scope = query["scope"] ?? "all"
        let requestedLimit = Int(query["limit"] ?? "") ?? 40
        let limit = min(max(requestedLimit, 20), 80)
        let requestedCursor = Int(query["cursor"] ?? "") ?? 0

        let filtered = sessionsProvider().compactMap { raw -> (raw: [String: Any], payload: [String: Any])? in
            guard let rawId = raw["id"] as? String else { return nil }
            let payload = sessionPayload(raw, remoteId: encodedSessionId(rawId))
            let phase = payload["phase"] as? String ?? "idle"
            let isAttention = ["waitingApproval", "waitingInput", "interrupted", "error"].contains(phase)
            let isActive = !["idle", "done"].contains(phase)
            let isControllable = payload["controlAvailable"] as? Bool == true
            switch scope {
            case "active" where !isActive:
                return nil
            case "attention" where !isAttention:
                return nil
            case "controllable" where !isControllable:
                return nil
            default:
                break
            }

            if !search.isEmpty {
                let searchable = [
                    payload["title"], payload["project"], payload["cwd"], payload["agentType"],
                    payload["engineLabel"], payload["lastResponse"]
                ]
                .compactMap { $0 as? String }
                .joined(separator: "\n")
                .lowercased()
                guard searchable.contains(search) else { return nil }
            }
            return (raw, payload)
        }

        let cursor = min(max(requestedCursor, 0), filtered.count)
        let end = min(cursor + limit, filtered.count)
        let page = cursor < end ? filtered[cursor..<end].map { $0.payload } : []
        let projects = Dictionary(grouping: filtered) { row in
            row.payload["project"] as? String ?? ""
        }
        .map { name, rows in ["name": name, "count": rows.count] as [String: Any] }
        .sorted {
            let left = $0["name"] as? String ?? ""
            let right = $1["name"] as? String ?? ""
            return left.localizedCaseInsensitiveCompare(right) == .orderedAscending
        }

        var response: [String: Any] = [
            "ok": true,
            "version": 2,
            "generatedAt": ISO8601DateFormatter().string(from: Date()),
            "sessions": page,
            "projects": projects,
            "totalCount": filtered.count,
            "hasMore": end < filtered.count
        ]
        if end < filtered.count { response["nextCursor"] = String(end) }
        return response
    }

    private func sendSessionContext(_ body: [String: Any], on connection: NWConnection) {
        guard let remoteId = body["sessionId"] as? String,
              let sessionId = decodedSessionId(remoteId) else {
            sendJSON(["ok": false, "error": "missing_session"], status: 400, on: connection)
            return
        }
        guard let raw = sessionsProvider().first(where: { $0["id"] as? String == sessionId }) else {
            sendJSON(["ok": false, "error": "session_not_found", "message": "The Agent session is no longer available."], status: 404, on: connection)
            return
        }

        let adapterId = raw["adapterId"] as? String ?? (sessionId.hasPrefix("adapter|claude|") ? "claude" : "codex")
        let sourcePath = raw["sourcePath"] as? String ?? ""
        let session = sessionPayload(raw, remoteId: remoteId)
        let cursor = body["cursor"] as? String
        let turnLimit: Int?
        if let number = body["turnLimit"] as? NSNumber {
            turnLimit = number.intValue
        } else if let text = body["turnLimit"] as? String {
            turnLimit = Int(text)
        } else {
            turnLimit = nil
        }
        let limit: Int
        if let number = body["limit"] as? NSNumber {
            limit = number.intValue
        } else if let text = body["limit"] as? String {
            limit = Int(text) ?? 80
        } else {
            limit = 80
        }

        if !["codex", "claude"].contains(adapterId) {
            var contextParams: [String: Any] = [
                "adapterId": adapterId,
                "sessionId": sessionId,
                "limit": limit
            ]
            if let cursor { contextParams["cursor"] = cursor }
            if let turnLimit { contextParams["turnLimit"] = turnLimit }
            let result = contextHandler(contextParams)
            guard result.ok else {
                sendJSON(["ok": false, "error": result.error ?? "context_unavailable", "message": result.error ?? "Context unavailable."], status: 422, on: connection)
                return
            }
            var response = result.result
            response["ok"] = true
            response["version"] = 2
            response["generatedAt"] = ISO8601DateFormatter().string(from: Date())
            response["session"] = session
            sendJSON(response, status: 200, on: connection)
            return
        }

        guard contextReader.contextAvailable(sourcePath: sourcePath) else {
            sendJSON([
                "ok": true,
                "version": 2,
                "generatedAt": ISO8601DateFormatter().string(from: Date()),
                "session": session,
                "messages": [],
                "totalCount": 0,
                "hasMore": false,
                "truncated": false,
                "warning": "This live Agent session has not written a readable local transcript yet."
            ], status: 200, on: connection)
            return
        }

        do {
            let page = try contextReader.page(
                sourcePath: sourcePath,
                adapterId: adapterId,
                cursor: cursor,
                requestedLimit: limit,
                requestedTurnLimit: turnLimit
            )
            var response: [String: Any] = [
                "ok": true,
                "version": 2,
                "generatedAt": ISO8601DateFormatter().string(from: Date()),
                "session": session,
                "messages": page.messages,
                "totalCount": page.totalCount,
                "hasMore": page.hasMore,
                "truncated": page.truncated
            ]
            if let nextCursor = page.nextCursor { response["nextCursor"] = nextCursor }
            sendJSON(response, status: 200, on: connection)
        } catch {
            sendJSON([
                "ok": false,
                "error": "context_unavailable",
                "message": error.localizedDescription
            ], status: 422, on: connection)
        }
    }

    private func sessionPayload(_ raw: [String: Any], remoteId: String) -> [String: Any] {
        let phase = raw["phase"] as? String ?? "idle"
        let cwd = raw["cwd"] as? String ?? ""
        let adapterId = raw["adapterId"] as? String ?? "codex"
        let agentType = raw["agentType"] as? String ?? (adapterId == "codex" ? "Codex" : adapterId)
        let projectName = URL(fileURLWithPath: cwd).lastPathComponent
        let project = projectName.isEmpty ? (cwd.isEmpty ? agentType : cwd) : projectName
        let isRunning = phase == "processing"
        let controlAvailable = raw["controlAvailable"] as? Bool ?? true
        let controlMode = raw["controlMode"] as? String ?? (controlAvailable ? "tracefence_agent_core" : "display_only")
        let sourcePath = raw["sourcePath"] as? String ?? ""
        let contextAvailable = raw["contextAvailable"] as? Bool ?? contextReader.contextAvailable(sourcePath: sourcePath)
        let scheduledTask = raw["scheduledTask"] as? Bool == true
        var payload: [String: Any] = [
            "id": remoteId,
            "adapterId": adapterId,
            "agentType": agentType,
            "engineLabel": limited(raw["model"] as? String ?? "", to: 160),
            "project": limited(raw["project"] as? String ?? project, to: 240),
            "cwd": limited(cwd, to: 1_024),
            "terminal": "TraceFence Agent Core",
            "phase": phase,
            "startedAt": dateString(raw["createdAt"]),
            "lastActivityAt": dateString(raw["updatedAt"]),
            "durationSeconds": 0,
            "title": limited(raw["preview"] as? String ?? "\(agentType) 会话", to: 320),
            "lastToolName": scheduledTask ? "等待下次定时执行" : (isRunning ? "\(agentType) 正在执行" : "\(agentType) 会话"),
            "lastToolTarget": limited(cwd, to: 1_024),
            "lastToolStatus": phase,
            "lastResponse": limited(raw["lastResponse"] as? String ?? "", to: 1_000),
            "lastThought": "",
            "statusLineText": scheduledTask ? "等待下一个执行周期" : (isRunning ? "正在 Mac 上执行" : "可从 iPhone 发送新指令"),
            "canInterrupt": isRunning && controlAvailable,
            "canResume": controlAvailable,
            "canTerminate": isRunning && controlAvailable,
            "resumeRequiresInstruction": true,
            "resumeNote": isRunning
                ? "发送的内容会插入当前 Agent turn；也可以先中断，再发送新的后续指令。"
                : "发送指令会在这个真实 Agent 会话中创建新 turn。",
            "controlMode": controlMode,
            "controlAvailable": controlAvailable,
            "controlReason": raw["controlReason"] as? String ?? (controlAvailable ? "background_agent_core" : "adapter_read_only"),
            "controlLimitations": [
                "TraceFence Agent Core 是独立常驻服务，可在 Mac App 窗口关闭或屏幕锁定后继续控制真实会话。",
                "Mac 进入系统睡眠或断网后，新的远程操作仍需等待网络恢复。"
            ],
            "deliveryModes": controlAvailable ? [controlMode] : [],
            "canRelaunch": false,
            "source": "agent-core-background",
            "sourcePath": limited(sourcePath, to: 2_048),
            "contextAvailable": contextAvailable,
            "tokens": ["input": 0, "output": 0, "cacheRead": 0, "cacheCreate": 0],
            "activeTools": [],
            "tasks": [],
            "subagents": []
        ]
        if scheduledTask {
            payload["scheduledTask"] = true
            payload["scheduleId"] = raw["scheduleId"] as? String ?? ""
            payload["scheduleRule"] = raw["scheduleRule"] as? String ?? ""
            if let nextRunAt = raw["nextRunAt"] {
                payload["nextRunAt"] = dateString(nextRunAt)
            }
        }
        return payload
    }

    private func approvalPayload(
        id: String,
        sessionId: String,
        method: String,
        params: [String: Any],
        rawSession: [String: Any],
        source: String?
    ) -> [String: Any] {
        let reason = readableApprovalText(params["reason"] ?? params["message"], limit: 4_000)
        var kind = "permission"
        var actionType = "permission"
        var title = "Agent 权限请求"
        var detail = reason
        var command = ""
        var workingDirectory = readableApprovalText(params["cwd"], limit: 2_048)
        var targetPaths: [String] = []
        var options: [String] = []
        var descriptions: [String] = []
        var permissions: [String] = []
        var requiresTextAnswer = false

        switch method {
        case "item/commandExecution/requestApproval":
            actionType = "command"
            title = "执行命令"
            command = readableApprovalText(params["command"], limit: 8_000)
            permissions = approvalPermissionLabels(params["additionalPermissions"])
            if !workingDirectory.isEmpty { targetPaths = [workingDirectory] }
            if detail.isEmpty { detail = "Agent 请求在 Mac 上执行这条命令。" }
        case "item/fileChange/requestApproval":
            actionType = "fileChange"
            title = "修改文件"
            let grantRoot = readableApprovalText(params["grantRoot"], limit: 2_048)
            targetPaths = approvalTargetPaths(params, fallback: grantRoot)
            if workingDirectory.isEmpty { workingDirectory = grantRoot }
            if detail.isEmpty { detail = "Agent 请求修改项目文件。" }
        case "item/permissions/requestApproval":
            actionType = source == "claude-hook" ? "tool" : "permission"
            let requestedTitle = readableApprovalText(params["title"], limit: 240)
            title = requestedTitle.isEmpty
                ? (source == "claude-hook" ? "使用工具" : "提升任务权限")
                : requestedTitle
            command = readableApprovalText(params["command"], limit: 8_000)
            permissions = approvalPermissionLabels(params["permissions"])
            if detail.isEmpty {
                detail = source == "claude-hook"
                    ? "Claude Code 请求使用这个工具。"
                    : "Agent 请求额外系统权限。"
            }
        case "item/tool/requestUserInput":
            kind = "question"
            actionType = "question"
            requiresTextAnswer = true
            let questions = params["questions"] as? [[String: Any]] ?? []
            let firstHeader = questions.compactMap { readableNonemptyString($0["header"], limit: 240) }.first
            title = firstHeader ?? "Agent 提问"
            let questionText = questions.compactMap { readableNonemptyString($0["question"], limit: 2_000) }
            detail = questionText.isEmpty ? (reason.isEmpty ? "Agent 正在等待你的回复。" : reason) : questionText.joined(separator: "\n\n")
            if let firstOptions = questions.first?["options"] as? [[String: Any]] {
                options = firstOptions.compactMap { readableNonemptyString($0["label"], limit: 240) }
                descriptions = firstOptions.compactMap { readableNonemptyString($0["description"], limit: 1_000) }
            }
        default:
            kind = "plan"
            actionType = "plan"
            title = readableNonemptyString(params["title"], limit: 240) ?? "Agent 计划确认"
            if detail.isEmpty {
                detail = readableApprovalText(params["message"], limit: 4_000)
            }
            if detail.isEmpty { detail = "Agent 正在等待你的确认。" }
        }

        var payload: [String: Any] = [
            "id": id,
            "kind": kind,
            "actionType": actionType,
            "approvalMethod": method,
            "sessionId": sessionId,
            "agentType": rawSession["agentType"] as? String
                ?? ((rawSession["adapterId"] as? String) == "claude" ? "Claude Code" : "Codex"),
            "project": rawSession["project"] as? String ?? rawSession["cwd"] as? String ?? "Agent",
            "title": title,
            "detail": detail,
            "options": options,
            "descriptions": descriptions,
            "permissions": permissions,
            "targetPaths": targetPaths,
            "sourceLabel": source == "claude-hook"
                ? "Claude Code Permission Hook"
                : (source == "app-server"
                    ? "Codex app-server"
                    : (source == "universal-hook" ? "TraceFence Agent Adapter" : "TraceFence Agent Core")),
            "requestedAt": approvalRequestedAt(params),
            "risk": method.contains("commandExecution") ? "high" : "medium",
            "requiresTextAnswer": requiresTextAnswer
        ]
        if !command.isEmpty { payload["command"] = command }
        if !workingDirectory.isEmpty { payload["workingDirectory"] = workingDirectory }
        if !reason.isEmpty { payload["reason"] = reason }
        return payload
    }

    private func readableNonemptyString(_ value: Any?, limit: Int) -> String? {
        let text = readableApprovalText(value, limit: limit)
        return text.isEmpty ? nil : text
    }

    private func readableApprovalText(_ value: Any?, limit: Int) -> String {
        guard let value else { return "" }
        let raw: String
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = trimmed.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data),
               JSONSerialization.isValidJSONObject(object),
               let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
               let decoded = String(data: pretty, encoding: .utf8) {
                raw = decoded
            } else {
                raw = text
            }
        } else if let values = value as? [String] {
            raw = values.joined(separator: " ")
        } else if JSONSerialization.isValidJSONObject(value),
                  let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
                  let text = String(data: data, encoding: .utf8) {
            raw = text
        } else {
            raw = String(describing: value)
        }

        let cleaned = raw.unicodeScalars.filter { scalar in
            scalar == "\n" || scalar == "\t" || !CharacterSet.controlCharacters.contains(scalar)
        }
        .map(String.init)
        .joined()
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(limit))
    }

    private func approvalTargetPaths(_ params: [String: Any], fallback: String) -> [String] {
        var paths: [String] = []
        for key in ["path", "filePath", "grantRoot", "cwd"] {
            if let value = readableNonemptyString(params[key], limit: 2_048), !paths.contains(value) {
                paths.append(value)
            }
        }
        if paths.isEmpty, !fallback.isEmpty { paths.append(fallback) }
        return paths
    }

    private func approvalPermissionLabels(_ value: Any?) -> [String] {
        if let values = value as? [String] {
            return values.map { readableApprovalText($0, limit: 1_000) }.filter { !$0.isEmpty }
        }
        if let values = value as? [Any] {
            return values.map { readableApprovalText($0, limit: 1_000) }.filter { !$0.isEmpty }
        }
        guard let dictionary = value as? [String: Any], !dictionary.isEmpty else { return [] }
        var labels: [String] = []
        if let network = dictionary["network"] as? [String: Any], network["enabled"] as? Bool == true {
            labels.append("访问网络")
        }
        if dictionary["fileSystem"] != nil || dictionary["filesystem"] != nil {
            labels.append("访问工作区外文件")
        }
        if labels.isEmpty {
            labels.append(readableApprovalText(dictionary, limit: 2_000))
        }
        return labels.filter { !$0.isEmpty }
    }

    private func approvalRequestedAt(_ params: [String: Any]) -> String {
        guard let number = params["startedAtMs"] as? NSNumber else {
            return ISO8601DateFormatter().string(from: Date())
        }
        let raw = number.doubleValue
        let timestamp = raw > 9_999_999_999 ? raw / 1_000 : raw
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func encodedSessionId(_ rawId: String) -> String {
        rawId.hasPrefix("adapter|") ? rawId : "core|codex|\(rawId)"
    }

    private func stableApprovalId(threadId: String, method: String, requestId: Any) -> String {
        let requestKey: String
        if let value = requestId as? String {
            requestKey = value
        } else if let value = requestId as? NSNumber {
            requestKey = value.stringValue
        } else {
            requestKey = String(describing: requestId)
        }
        let digest = SHA256.hash(data: Data("\(threadId)\u{0}\(method)\u{0}\(requestKey)".utf8))
        let suffix = digest.prefix(12).map { String(format: "%02x", $0) }.joined()
        return "core-approval-\(suffix)"
    }

    private func limited(_ value: String, to limit: Int) -> String {
        value.count <= limit ? value : String(value.suffix(limit))
    }

    private func decodedSessionId(_ remoteId: String) -> String? {
        if remoteId.hasPrefix("adapter|") { return remoteId }
        let prefix = "core|codex|"
        if remoteId.hasPrefix(prefix) { return String(remoteId.dropFirst(prefix.count)) }
        let legacyPrefix = "codex|"
        if remoteId.hasPrefix(legacyPrefix) { return String(remoteId.dropFirst(legacyPrefix.count)) }
        return remoteId.isEmpty ? nil : remoteId
    }

    private func dateString(_ value: Any?) -> String {
        let timestamp: TimeInterval
        if let number = value as? NSNumber {
            timestamp = number.doubleValue > 4_000_000_000 ? number.doubleValue / 1_000 : number.doubleValue
        } else {
            timestamp = Date().timeIntervalSince1970
        }
        return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
    }

    private func stringify(_ value: Any) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return String(describing: value) }
        return String(text.prefix(2_000))
    }

    private func loadConfig() -> Config? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let config = try? JSONDecoder().decode(Config.self, from: data),
              (1024...65_535).contains(config.port),
              config.token.count >= 32 else { return nil }
        return config
    }

    private func isAuthorized(_ request: Request, token: String) -> Bool {
        guard let timestamp = request.headers["x-tracefence-timestamp"],
              let timestampValue = TimeInterval(timestamp),
              abs(Date().timeIntervalSince1970 - timestampValue) <= requestClockSkew,
              let nonce = request.headers["x-tracefence-nonce"],
              nonce.count >= 16,
              nonce.count <= 128,
              let providedSignature = request.headers["x-tracefence-signature"] else {
            return false
        }

        let bodyDigest = SHA256.hash(data: request.bodyData)
            .map { String(format: "%02x", $0) }
            .joined()
        let canonical = [request.method, request.target, timestamp, nonce, bodyDigest]
            .joined(separator: "\n")
        let expected = HMAC<SHA256>.authenticationCode(
            for: Data(canonical.utf8),
            using: SymmetricKey(data: Data(token.utf8))
        ).map { String(format: "%02x", $0) }.joined()
        guard constantTimeEqual(providedSignature.lowercased(), expected) else { return false }

        let now = Date()
        acceptedRequestNonces = acceptedRequestNonces.filter { $0.value > now }
        guard acceptedRequestNonces[nonce] == nil else { return false }
        acceptedRequestNonces[nonce] = now.addingTimeInterval(requestClockSkew)
        return true
    }

    private func constantTimeEqual(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        let count = max(left.count, right.count)
        var difference = UInt64(left.count ^ right.count)
        for index in 0..<count {
            let leftByte = index < left.count ? left[index] : 0
            let rightByte = index < right.count ? right[index] : 0
            difference |= UInt64(leftByte ^ rightByte)
        }
        return difference == 0
    }

    private static func isPrivateRemoteEndpoint(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        var value = String(describing: host).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if let zone = value.firstIndex(of: "%") {
            value = String(value[..<zone])
        }
        if value == "localhost" || value == "::1" { return true }
        if value.hasPrefix("fe80:") || value.hasPrefix("fc") || value.hasPrefix("fd") { return true }
        if value.hasPrefix("::ffff:") {
            value = String(value.dropFirst("::ffff:".count))
        }
        let octets = value.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (octets[0], octets[1]) {
        case (10, _), (127, _), (169, 254), (192, 168):
            return true
        case (172, 16...31), (100, 64...127):
            return true
        default:
            return false
        }
    }

    private func sendJSON(_ body: [String: Any], status: Int, on connection: NWConnection) {
        let data = (try? JSONSerialization.data(withJSONObject: body)) ?? Data("{\"ok\":false}".utf8)
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 402: reason = "Payment Required"
        case 404: reason = "Not Found"
        case 409: reason = "Conflict"
        case 413: reason = "Payload Too Large"
        case 503: reason = "Service Unavailable"
        default: reason = "Error"
        }
        var response = Data("HTTP/1.1 \(status) \(reason)\r\n".utf8)
        response.append(Data("Content-Type: application/json; charset=utf-8\r\n".utf8))
        response.append(Data("Content-Length: \(data.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }
}
