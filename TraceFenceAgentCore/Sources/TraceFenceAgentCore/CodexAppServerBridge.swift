import Foundation

final class CodexAppServerBridge {
    private final class PendingResponse {
        let semaphore = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var result: [String: Any]?
        private var error: Error?

        func succeed(_ result: [String: Any]) {
            lock.lock()
            self.result = result
            lock.unlock()
            semaphore.signal()
        }

        func fail(_ error: Error) {
            lock.lock()
            self.error = error
            lock.unlock()
            semaphore.signal()
        }

        func value() throws -> [String: Any] {
            lock.lock()
            defer { lock.unlock() }
            if let error { throw error }
            return result ?? [:]
        }
    }

    private struct PendingApproval {
        let requestId: Any
        let method: String
        let params: [String: Any]
    }

    private enum BridgeError: LocalizedError {
        case executableMissing
        case notRunning
        case connection(String)
        case timeout(String)
        case server(String)
        case invalidResponse(String)

        var errorDescription: String? {
            switch self {
            case .executableMissing:
                return "Codex executable was not found."
            case .notRunning:
                return "Codex app-server is not running."
            case .connection(let detail):
                return "Codex Adapter connection failed: \(detail)"
            case .timeout(let method):
                return "Codex app-server timed out while handling \(method)."
            case .server(let detail):
                return detail
            case .invalidResponse(let method):
                return "Codex app-server returned an invalid response for \(method)."
            }
        }
    }

    private let lifecycleLock = NSLock()
    private let stateLock = NSLock()
    private let writeLock = NSLock()
    private var socket: UnixWebSocketClient?
    private var connected = false
    private var nextRequestId = 0
    private var pendingResponses: [Int: PendingResponse] = [:]
    private var initialized = false
    private var activeTurns: [String: String] = [:]
    private var pendingApprovals: [String: PendingApproval] = [:]

    var isAvailable: Bool {
        Self.codexExecutableURL() != nil && FileManager.default.fileExists(atPath: Self.daemonSocketPath)
    }

    var hasLiveApprovalStream: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return initialized && connected && socket?.isConnected == true
    }

    func warmUp() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            try? self?.ensureStarted()
        }
    }

    func activeTurnId(for threadId: String) -> String? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return activeTurns[threadId]
    }

    func clearActiveTurn(threadId: String, expectedTurnId: String) {
        stateLock.lock()
        if activeTurns[threadId] == expectedTurnId {
            activeTurns.removeValue(forKey: threadId)
        }
        stateLock.unlock()
    }

    func pendingRequests(for threadId: String) -> [[String: Any]] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return pendingApprovals.values.compactMap { approval in
            guard approval.params["threadId"] as? String == threadId else { return nil }
            return [
                "method": approval.method,
                "requestId": approval.requestId,
                "params": approval.params,
                "source": "app-server"
            ]
        }
    }

    func sendInstruction(threadId: String, instruction: String) -> (ok: Bool, result: [String: Any], error: String?) {
        do {
            try ensureStarted()
            let resumed = try request(
                method: "thread/resume",
                params: [
                    "threadId": threadId,
                    "approvalPolicy": "on-request",
                    "approvalsReviewer": "user"
                ],
                timeout: 15
            )
            let thread = resumed["thread"] as? [String: Any]
            let activeTurn = activeTurnId(for: threadId) ?? Self.activeTurnId(in: thread)
            let input: [[String: Any]] = [[
                "type": "text",
                "text": instruction,
                "text_elements": []
            ]]

            if let activeTurn {
                _ = try request(
                    method: "turn/steer",
                    params: [
                        "threadId": threadId,
                        "expectedTurnId": activeTurn,
                        "input": input
                    ],
                    timeout: 12
                )
                return (true, [
                    "command": "codex_steer",
                    "message": "新指令已插入 Mac 上正在执行的 Codex 任务。",
                    "controlMode": "codex_app_server"
                ], nil)
            }

            let started = try request(
                method: "turn/start",
                params: [
                    "threadId": threadId,
                    "input": input,
                    "approvalPolicy": "on-request",
                    "approvalsReviewer": "user"
                ],
                timeout: 15
            )
            if let turnId = (started["turn"] as? [String: Any])?["id"] as? String {
                stateLock.lock()
                activeTurns[threadId] = turnId
                stateLock.unlock()
            }
            return (true, [
                "command": "codex_start",
                "message": "指令已发送，Mac 上的 Codex 会话已经开始执行。",
                "controlMode": "codex_app_server"
            ], nil)
        } catch {
            return (false, [:], error.localizedDescription)
        }
    }

    func interrupt(threadId: String) -> (ok: Bool, result: [String: Any], error: String?) {
        do {
            try ensureStarted()
            let resumed = try request(
                method: "thread/resume",
                params: [
                    "threadId": threadId,
                    "approvalPolicy": "on-request",
                    "approvalsReviewer": "user"
                ],
                timeout: 15
            )
            let thread = resumed["thread"] as? [String: Any]
            guard let turnId = activeTurnId(for: threadId) ?? Self.activeTurnId(in: thread) else {
                return (false, [:], "该 Codex 会话当前没有正在执行的任务。")
            }
            _ = try request(
                method: "turn/interrupt",
                params: ["threadId": threadId, "turnId": turnId],
                timeout: 12
            )
            stateLock.lock()
            activeTurns.removeValue(forKey: threadId)
            pendingApprovals = pendingApprovals.filter {
                $0.value.params["threadId"] as? String != threadId
            }
            stateLock.unlock()
            return (true, [
                "command": "codex_interrupt",
                "message": "Mac 上的 Codex 任务已中断。",
                "controlMode": "codex_app_server"
            ], nil)
        } catch {
            return (false, [:], error.localizedDescription)
        }
    }

    func resolveApproval(_ params: [String: Any]) -> (ok: Bool, result: [String: Any], error: String?) {
        guard let threadId = params["threadId"] as? String,
              let requestId = params["requestId"] else {
            return (false, [:], "missing_approval_request")
        }
        let key = Self.approvalKey(threadId: threadId, requestId: requestId)
        stateLock.lock()
        let approval = pendingApprovals[key]
        let availableKeys = approval == nil ? Array(pendingApprovals.keys.prefix(8)) : []
        stateLock.unlock()
        guard let approval else {
            fputs("TraceFence Codex approval miss key=\(key) available=\(availableKeys)\n", stderr)
            return (false, [:], "approval_not_owned_by_app_server")
        }

        let allow = params["allow"] as? Bool ?? false
        let response: [String: Any]
        switch approval.method {
        case "item/commandExecution/requestApproval", "item/fileChange/requestApproval":
            response = ["decision": allow ? "accept" : "decline"]
        case "item/permissions/requestApproval":
            response = [
                "permissions": allow ? (params["requestedPermissions"] as? [String: Any] ?? approval.params["permissions"] as? [String: Any] ?? [:]) : [:],
                "scope": "turn"
            ]
        case "item/tool/requestUserInput":
            let answer = (params["answer"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let questions = approval.params["questions"] as? [[String: Any]] ?? []
            var answers: [String: Any] = [:]
            for question in questions {
                guard let id = question["id"] as? String else { continue }
                let fallback = (question["options"] as? [[String: Any]])?.first?["label"] as? String ?? ""
                answers[id] = ["answers": [answer.isEmpty ? fallback : answer]]
            }
            response = ["answers": answers]
        default:
            return (false, [:], "unsupported_approval_method:\(approval.method)")
        }

        do {
            try writeJSON(["jsonrpc": "2.0", "id": approval.requestId, "result": response])
            stateLock.lock()
            pendingApprovals.removeValue(forKey: key)
            stateLock.unlock()
            return (true, [
                "command": allow ? "codex_approval_approve" : "codex_approval_deny",
                "message": allow ? "已在 iPhone 上批准 Codex 请求，Mac 任务会继续执行。" : "已拒绝 Codex 请求。",
                "controlMode": "codex_app_server"
            ], nil)
        } catch {
            return (false, [:], error.localizedDescription)
        }
    }

    private func ensureStarted() throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }

        stateLock.lock()
        let ready = initialized && connected && socket?.isConnected == true
        stateLock.unlock()
        if ready { return }

        stopConnection()
        guard Self.codexExecutableURL() != nil else {
            throw BridgeError.executableMissing
        }

        let socket = UnixWebSocketClient(path: Self.daemonSocketPath)
        do {
            try socket.connect()
        } catch {
            throw BridgeError.connection(error.localizedDescription)
        }
        stateLock.lock()
        self.socket = socket
        connected = true
        initialized = false
        stateLock.unlock()
        Thread.detachNewThread { [weak self, weak socket] in
            Thread.current.name = "TraceFence Codex Daemon Reader"
            guard let self, let socket else { return }
            self.receiveLoop(on: socket)
        }

        do {
            _ = try requestRaw(
                method: "initialize",
                params: [
                    "clientInfo": ["name": "TraceFence Agent Core", "version": "1.2.0"],
                    "capabilities": ["experimentalApi": true]
                ],
                timeout: 10
            )
            try writeJSON(["jsonrpc": "2.0", "method": "initialized", "params": [:]])
            stateLock.lock()
            initialized = true
            stateLock.unlock()
        } catch {
            stopConnection()
            throw error
        }
    }

    private func request(method: String, params: [String: Any], timeout: TimeInterval) throws -> [String: Any] {
        try ensureStarted()
        return try requestRaw(method: method, params: params, timeout: timeout)
    }

    private func requestRaw(method: String, params: [String: Any], timeout: TimeInterval) throws -> [String: Any] {
        let pending = PendingResponse()
        stateLock.lock()
        nextRequestId += 1
        let id = nextRequestId
        pendingResponses[id] = pending
        stateLock.unlock()

        do {
            fputs("TraceFence Codex bridge -> request \(id) \(method)\n", stderr)
            try writeJSON([
                "jsonrpc": "2.0",
                "id": id,
                "method": method,
                "params": params
            ])
        } catch {
            stateLock.lock()
            pendingResponses.removeValue(forKey: id)
            stateLock.unlock()
            throw error
        }

        guard pending.semaphore.wait(timeout: .now() + timeout) == .success else {
            stateLock.lock()
            pendingResponses.removeValue(forKey: id)
            stateLock.unlock()
            fputs("TraceFence Codex bridge timeout <- request \(id) \(method)\n", stderr)
            throw BridgeError.timeout(method)
        }
        return try pending.value()
    }

    private func writeJSON(_ object: [String: Any]) throws {
        stateLock.lock()
        let socket = self.socket
        let running = connected
        stateLock.unlock()
        guard let socket, running else { throw BridgeError.notRunning }
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let text = String(data: data, encoding: .utf8) else {
            throw BridgeError.server("Codex Adapter request encoding failed.")
        }
        writeLock.lock()
        defer { writeLock.unlock() }
        try socket.sendText(text)
    }

    private func receiveLoop(on socket: UnixWebSocketClient) {
        do {
            while true {
                let text = try socket.receiveText()
                autoreleasepool {
                    guard let data = text.data(using: .utf8),
                          let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                    handleMessage(message)
                }
            }
        } catch {
            failConnection(socket, error: error)
        }
    }

    private func handleMessage(_ message: [String: Any]) {
        if message["method"] == nil, let id = Self.intId(message["id"]) {
            stateLock.lock()
            let pending = pendingResponses.removeValue(forKey: id)
            stateLock.unlock()
            fputs("TraceFence Codex bridge <- response \(id); pending=\(pending != nil)\n", stderr)
            guard let pending else { return }
            if let error = message["error"] as? [String: Any] {
                pending.fail(BridgeError.server(error["message"] as? String ?? String(describing: error)))
            } else {
                pending.succeed(message["result"] as? [String: Any] ?? [:])
            }
            return
        }

        guard let method = message["method"] as? String else { return }
        let params = message["params"] as? [String: Any] ?? [:]
        if method == "thread/status/changed" || method == "mcpServer/startupStatus/updated" {
            fputs("TraceFence Codex bridge <- event \(method)\n", stderr)
        }
        if let requestId = message["id"], method.hasPrefix("item/"),
           let threadId = params["threadId"] as? String {
            let key = Self.approvalKey(threadId: threadId, requestId: requestId)
            stateLock.lock()
            pendingApprovals[key] = PendingApproval(requestId: requestId, method: method, params: params)
            stateLock.unlock()
            fputs("TraceFence Codex approval captured key=\(key) method=\(method)\n", stderr)
            return
        }

        switch method {
        case "turn/started":
            if let threadId = params["threadId"] as? String,
               let turnId = (params["turn"] as? [String: Any])?["id"] as? String {
                stateLock.lock()
                pendingApprovals = pendingApprovals.filter {
                    $0.value.params["threadId"] as? String != threadId
                }
                activeTurns[threadId] = turnId
                stateLock.unlock()
            }
        case "turn/completed":
            if let threadId = params["threadId"] as? String {
                stateLock.lock()
                activeTurns.removeValue(forKey: threadId)
                pendingApprovals = pendingApprovals.filter {
                    $0.value.params["threadId"] as? String != threadId
                }
                stateLock.unlock()
            }
        case "thread/status/changed":
            if let threadId = params["threadId"] as? String,
               (params["status"] as? [String: Any])?["type"] as? String == "idle" {
                stateLock.lock()
                activeTurns.removeValue(forKey: threadId)
                pendingApprovals = pendingApprovals.filter {
                    $0.value.params["threadId"] as? String != threadId
                }
                stateLock.unlock()
            }
        case "serverRequest/resolved":
            if let threadId = params["threadId"] as? String,
               let requestId = params["requestId"] {
                let key = Self.approvalKey(threadId: threadId, requestId: requestId)
                stateLock.lock()
                let removed = pendingApprovals.removeValue(forKey: key) != nil
                stateLock.unlock()
                fputs("TraceFence Codex approval resolved key=\(key) removed=\(removed)\n", stderr)
            }
        case "item/completed":
            if let threadId = params["threadId"] as? String,
               let itemId = (params["item"] as? [String: Any])?["id"] as? String {
                stateLock.lock()
                pendingApprovals = pendingApprovals.filter { _, approval in
                    let approvalThreadId = approval.params["threadId"] as? String
                    let approvalItemId = approval.params["itemId"] as? String
                    return approvalThreadId != threadId || approvalItemId != itemId
                }
                stateLock.unlock()
            }
        default:
            break
        }
    }

    private func stopConnection() {
        stateLock.lock()
        let socket = self.socket
        let pending = Array(pendingResponses.values)
        pendingResponses.removeAll()
        self.socket = nil
        connected = false
        initialized = false
        activeTurns.removeAll()
        pendingApprovals.removeAll()
        stateLock.unlock()
        socket?.close()
        pending.forEach { $0.fail(BridgeError.notRunning) }
    }

    private func failConnection(_ failedSocket: UnixWebSocketClient, error: Error) {
        stateLock.lock()
        guard socket === failedSocket else {
            stateLock.unlock()
            return
        }
        let pending = Array(pendingResponses.values)
        pendingResponses.removeAll()
        socket = nil
        connected = false
        initialized = false
        activeTurns.removeAll()
        pendingApprovals.removeAll()
        stateLock.unlock()
        failedSocket.close()
        pending.forEach { $0.fail(error) }
    }

    private static func codexExecutableURL() -> URL? {
        let candidates = [
            NSHomeDirectory() + "/.codex/packages/standalone/current/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex"
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map(URL.init(fileURLWithPath:))
    }

    private static var daemonSocketPath: String {
        NSHomeDirectory() + "/.codex/app-server-control/app-server-control.sock"
    }

    private static func activeTurnId(in thread: [String: Any]?) -> String? {
        guard let thread else { return nil }
        if let status = thread["status"] as? [String: Any], status["type"] as? String == "active",
           let turnId = status["activeTurnId"] as? String {
            return turnId
        }
        let turns = thread["turns"] as? [[String: Any]] ?? []
        return turns.reversed().first(where: {
            let status = ($0["status"] as? String ?? "").lowercased()
            return status == "inprogress" || status == "in_progress" || status == "active"
        })?["id"] as? String
    }

    private static func intId(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func requestKey(_ value: Any) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return String(describing: value)
    }

    private static func approvalKey(threadId: String, requestId: Any) -> String {
        "\(threadId)|\(requestKey(requestId))"
    }
}
