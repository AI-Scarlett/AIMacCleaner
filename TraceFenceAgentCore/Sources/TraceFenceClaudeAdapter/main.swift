import CryptoKit
import Darwin
import Foundation

private let adapterVersion = "1.0.3"
private let maxRequestBytes = 512 * 1_024
private let maxResponseBytes = 8 * 1_024 * 1_024
private let maxProcessOutputBytes = 8 * 1_024 * 1_024
private let maxProcessErrorBytes = 2 * 1_024 * 1_024
private let maxSessionFiles = 100
private let maxSessionFileBytes: Int64 = 50 * 1_024 * 1_024
private let sessionCacheLifetime: TimeInterval = 60
private let healthCacheLifetime: TimeInterval = 30
private let claudeEnvironmentService = "com.tracefence.adapter.claude.environment.v2"
private let claudeEnvironmentKeys = [
    "ANTHROPIC_AUTH_TOKEN",
    "ANTHROPIC_API_KEY",
    "ANTHROPIC_BASE_URL",
    "ANTHROPIC_MODEL",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL",
    "ANTHROPIC_DEFAULT_OPUS_MODEL",
    "ANTHROPIC_DEFAULT_SONNET_MODEL"
]

private var claudeEnvironmentFileURL: URL {
    URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Application Support/TraceFence/Core/claude-environment.json")
}

private final class StoredClaudeEnvironment {
    private let lock = NSLock()
    private var cached: [String: String]?

    func values() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        if let cached { return cached }
        guard let data = try? Data(contentsOf: claudeEnvironmentFileURL),
              let values = try? JSONDecoder().decode([String: String].self, from: data) else {
            cached = [:]
            return [:]
        }
        let allowed = values.filter { claudeEnvironmentKeys.contains($0.key) && !$0.value.isEmpty }
        cached = allowed
        return allowed
    }
}

private let storedClaudeEnvironment = StoredClaudeEnvironment()
private final class ClaudeEnvironmentPolicy {
    private let lock = NSLock()
    private var useStoredEnvironment = true

    func setUseStoredEnvironment(_ value: Bool) {
        lock.lock()
        useStoredEnvironment = value
        lock.unlock()
    }

    func shouldUseStoredEnvironment() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return useStoredEnvironment
    }
}

private let claudeEnvironmentPolicy = ClaudeEnvironmentPolicy()

private struct ProcessResult {
    let status: Int32
    let output: String
    let error: String
    let timedOut: Bool
}

private final class BoundedProcessBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private let limit: Int
    private var data = Data()
    private(set) var truncated = false

    init(limit: Int) {
        self.limit = max(1, limit)
        data.reserveCapacity(min(limit, 64 * 1_024))
    }

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit - data.count)
        if remaining > 0 { data.append(chunk.prefix(remaining)) }
        if chunk.count > remaining { truncated = true }
    }

    func text() -> String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct BackgroundAgent {
    let id: String
    let sessionId: String
    let cwd: String
    let name: String
    let state: String
    let status: String
    let startedAt: Double
    let pid: Int?

    var isActive: Bool {
        ["working", "busy", "starting", "running"].contains(state.lowercased())
            || ["working", "busy", "starting", "running"].contains(status.lowercased())
    }
}

private struct PendingHook {
    let id: String
    let fd: Int32
    let event: [String: Any]
    let createdAt: Date
}

private final class LockedState {
    private let lock = NSLock()
    private var pendingHooks: [String: PendingHook] = [:]
    private var recentEventsBySession: [String: [String: Any]] = [:]
    private var providerError: String?

    func addPending(_ hook: PendingHook) {
        lock.lock()
        pendingHooks[hook.id] = hook
        lock.unlock()
    }

    func removePending(id: String) -> PendingHook? {
        lock.lock()
        defer { lock.unlock() }
        return pendingHooks.removeValue(forKey: id)
    }

    func pendingSnapshot() -> [PendingHook] {
        lock.lock()
        defer { lock.unlock() }
        return Array(pendingHooks.values)
    }

    func remember(event: [String: Any], sessionId: String) {
        guard !sessionId.isEmpty else { return }
        lock.lock()
        recentEventsBySession[sessionId] = event
        if recentEventsBySession.count > 200 {
            recentEventsBySession.removeValue(forKey: recentEventsBySession.keys.first!)
        }
        lock.unlock()
    }

    func setProviderError(_ value: String?) {
        lock.lock()
        providerError = value
        lock.unlock()
    }

    func providerErrorSnapshot() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return providerError
    }
}

private final class ClaudeAdapterDaemon {
    private let rpcSocketPath: String
    private let hookSocketPath: String
    private let state = LockedState()
    private let fileManager = FileManager.default
    private let sessionCacheLock = NSLock()
    private var cachedBaseSessions: [[String: Any]] = []
    private var sessionCacheUpdatedAt = Date.distantPast
    private var sessionRefreshInProgress = false
    private let healthCacheLock = NSLock()
    private var cachedHealthPayload: [String: Any]?
    private var healthCacheUpdatedAt = Date.distantPast
    private var rpcListener: Int32 = -1
    private var hookListener: Int32 = -1

    init(rpcSocketPath: String, hookSocketPath: String) {
        self.rpcSocketPath = rpcSocketPath
        self.hookSocketPath = hookSocketPath
    }

    func run() throws -> Never {
        rpcListener = try makeUnixListener(path: rpcSocketPath)
        hookListener = try makeUnixListener(path: hookSocketPath)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop(listener: self?.hookListener ?? -1, isHook: true)
        }
        refreshSessionCache(force: true)
        acceptLoop(listener: rpcListener, isHook: false)
        fatalError("Claude adapter listener stopped unexpectedly")
    }

    private func acceptLoop(listener: Int32, isHook: Bool) {
        while listener >= 0 {
            let fd = Darwin.accept(listener, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                Thread.sleep(forTimeInterval: 0.1)
                continue
            }
            DispatchQueue.global(qos: .utility).async { [weak self] in
                if isHook {
                    self?.handleHookConnection(fd)
                } else {
                    self?.handleRPCConnection(fd)
                }
            }
        }
    }

    private func handleRPCConnection(_ fd: Int32) {
        defer { close(fd) }
        guard let request = readJSONObjectLine(fd: fd, maxBytes: maxRequestBytes) else {
            _ = writeJSONObject(["ok": false, "error": "invalid_adapter_request"], fd: fd)
            return
        }
        let method = request["method"] as? String ?? ""
        let params = request["params"] as? [String: Any] ?? [:]
        let response: [String: Any]
        switch method {
        case "health":
            response = ["ok": true, "result": healthPayload()]
        case "listSessions":
            response = ["ok": true, "result": ["sessions": listSessions()]]
        case "control":
            response = control(params)
        default:
            response = ["ok": false, "error": "unsupported_adapter_method:\(method)"]
        }
        _ = writeJSONObject(response, fd: fd)
    }

    private func handleHookConnection(_ fd: Int32) {
        guard var event = readJSONObjectLine(fd: fd, maxBytes: maxRequestBytes) else {
            _ = writeJSONObject([:], fd: fd)
            close(fd)
            return
        }
        let eventName = stringValue(event, keys: ["hook_event_name", "hookEventName", "event"])
        if event["event"] == nil { event["event"] = eventName }
        let sessionId = stringValue(event, keys: ["session_id", "sessionId", "conversation_id", "conversationId"])
        state.remember(event: event, sessionId: sessionId)

        guard eventName == "PermissionRequest" || eventName == "permission_request" else {
            _ = writeJSONObject([:], fd: fd)
            close(fd)
            return
        }

        let id = pendingHookId(event: event)
        state.addPending(PendingHook(id: id, fd: fd, event: event, createdAt: Date()))
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 21_600) { [weak self] in
            guard let pending = self?.state.removePending(id: id) else { return }
            let response = Self.permissionResponse(allow: false, reason: "TraceFence approval timed out")
            _ = writeJSONObject(response, fd: pending.fd)
            close(pending.fd)
        }
    }

    private func healthPayload() -> [String: Any] {
        healthCacheLock.lock()
        defer { healthCacheLock.unlock() }
        if let cachedHealthPayload,
           Date().timeIntervalSince(healthCacheUpdatedAt) < healthCacheLifetime {
            return cachedHealthPayload
        }

        // Coalesce simultaneous menu, Core and phone health requests. Without
        // this single-flight section a cold burst can launch the same Claude
        // version/auth probes many times before the first response is cached.
        let payload = rebuildHealthPayload()
        cachedHealthPayload = payload
        healthCacheUpdatedAt = Date()
        return payload
    }

    private func rebuildHealthPayload() -> [String: Any] {
        guard let cli = claudeExecutable() else {
            return [
                "adapterVersion": adapterVersion,
                "operational": false,
                "authenticated": false,
                "desktopDetected": claudeDesktopDetected(),
                "message": "未安装 Claude Code CLI；Claude Desktop 对话没有开放本地控制 API。"
            ]
        }

        let version = runProcess(cli, ["--version"], timeout: 3).output.trimmingCharacters(in: .whitespacesAndNewlines)
        let officialAuthResult = runProcess(
            cli,
            ["auth", "status"],
            timeout: 3,
            includeStoredClaudeEnvironment: false
        )
        let officialLoggedIn = claudeAuthLoggedIn(officialAuthResult)
        let providerEnvironmentConfigured = !storedClaudeEnvironment.values().isEmpty
        claudeEnvironmentPolicy.setUseStoredEnvironment(!officialLoggedIn && providerEnvironmentConfigured)
        if officialLoggedIn { state.setProviderError(nil) }
        let authResult = officialAuthResult
        let loggedIn = claudeAuthLoggedIn(authResult) || providerEnvironmentConfigured
        refreshSessionCache()
        sessionCacheLock.lock()
        let healthSessions = cachedBaseSessions
        sessionCacheLock.unlock()
        let providerError = state.providerErrorSnapshot() ?? latestProviderFailure(in: healthSessions)
        if let providerError { state.setProviderError(providerError) }
        let authenticated = loggedIn && providerError == nil
        return [
            "adapterVersion": adapterVersion,
            "operational": true,
            "authenticated": authenticated,
            "cliVersion": version,
            "desktopDetected": claudeDesktopDetected(),
            "message": authenticated
                ? (officialLoggedIn
                    ? "Claude Code CLI 已可用于远程会话控制。"
                    : "Claude Code 自定义提供商环境已导入本机 Agent Core，可用于远程会话控制。")
                : (providerError
                    ?? "已检测到 Claude Code CLI，但当前登录无效。请在 Mac 运行 claude auth login；Claude Desktop 与 Claude Code 使用独立登录。")
        ]
    }

    private func listSessions() -> [[String: Any]] {
        refreshSessionCache()
        sessionCacheLock.lock()
        var sessions = cachedBaseSessions
        sessionCacheLock.unlock()

        let adapterProviderError = state.providerErrorSnapshot()
            ?? latestProviderFailure(in: sessions)
        if let adapterProviderError {
            for index in sessions.indices {
                sessions[index]["controlAvailable"] = false
                sessions[index]["controlReason"] = "provider_authentication_failed"
                sessions[index]["controlError"] = adapterProviderError
                let phase = sessions[index]["phase"] as? String ?? "idle"
                if phase != "processing" && !phase.hasPrefix("waiting") {
                    sessions[index]["phase"] = "error"
                }
            }
        }

        let pending = state.pendingSnapshot()
        for hook in pending {
            let sessionId = stringValue(hook.event, keys: ["session_id", "sessionId", "conversation_id", "conversationId"])
            let request = requestPayload(for: hook)
            if let index = sessions.firstIndex(where: { $0["id"] as? String == sessionId }) {
                var requests = sessions[index]["requests"] as? [[String: Any]] ?? []
                requests.append(request)
                sessions[index]["requests"] = requests
                sessions[index]["phase"] = "waitingApproval"
            } else if !sessionId.isEmpty {
                let cwd = stringValue(hook.event, keys: ["cwd", "working_directory", "workingDirectory"])
                var synthetic = sessionPayload(
                    id: sessionId,
                    cwd: cwd,
                    preview: "Claude permission request",
                    lastUserMessage: "",
                    lastResponse: "",
                    model: "Claude",
                    sourcePath: "",
                    createdAt: hook.createdAt.timeIntervalSince1970 * 1_000,
                    updatedAt: hook.createdAt.timeIntervalSince1970 * 1_000,
                    background: nil
                )
                synthetic["phase"] = "waitingApproval"
                synthetic["requests"] = [request]
                sessions.append(synthetic)
            }
        }

        return sessions.sorted {
            ($0["updatedAt"] as? Double ?? 0) > ($1["updatedAt"] as? Double ?? 0)
        }
    }

    private func latestProviderFailure(in sessions: [[String: Any]]) -> String? {
        sessions
            .sorted { ($0["updatedAt"] as? Double ?? 0) > ($1["updatedAt"] as? Double ?? 0) }
            .compactMap { ($0["lastResponse"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .flatMap(claudeProviderFailure)
    }

    private func rebuildBaseSessions() -> [[String: Any]] {
        let agents = backgroundAgents()
        let agentsBySession = Dictionary(uniqueKeysWithValues: agents.map { ($0.sessionId, $0) })
        var sessions = scanSessionFiles(backgroundAgents: agentsBySession)
        var knownIds = Set(sessions.compactMap { $0["id"] as? String })

        for agent in agents where !knownIds.contains(agent.sessionId) {
            sessions.append(sessionPayload(
                id: agent.sessionId,
                cwd: agent.cwd,
                preview: agent.name.isEmpty ? "Claude Code session" : agent.name,
                lastUserMessage: "",
                lastResponse: "",
                model: "Claude",
                sourcePath: "",
                createdAt: agent.startedAt,
                updatedAt: Date().timeIntervalSince1970 * 1_000,
                background: agent
            ))
            knownIds.insert(agent.sessionId)
        }

        let newestResponse = sessions
            .filter { session in
                guard let updatedAt = session["updatedAt"] as? Double else { return false }
                return updatedAt >= (Date().timeIntervalSince1970 - 7 * 24 * 60 * 60) * 1_000
            }
            .sorted { ($0["updatedAt"] as? Double ?? 0) > ($1["updatedAt"] as? Double ?? 0) }
            .compactMap { ($0["lastResponse"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        if let newestResponse, let failure = claudeProviderFailure(in: newestResponse) {
            state.setProviderError(failure)
        } else if newestResponse != nil {
            state.setProviderError(nil)
        }

        return sessions
    }

    private func refreshSessionCache(force: Bool = false) {
        sessionCacheLock.lock()
        let isDue = force || Date().timeIntervalSince(sessionCacheUpdatedAt) >= sessionCacheLifetime
        guard isDue, !sessionRefreshInProgress else {
            sessionCacheLock.unlock()
            return
        }
        sessionRefreshInProgress = true
        sessionCacheLock.unlock()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let rows = self.rebuildBaseSessions()
            self.sessionCacheLock.lock()
            self.cachedBaseSessions = rows
            self.sessionCacheUpdatedAt = Date()
            self.sessionRefreshInProgress = false
            self.sessionCacheLock.unlock()
        }
    }

    private func invalidateSessionCache() {
        sessionCacheLock.lock()
        sessionCacheUpdatedAt = .distantPast
        sessionCacheLock.unlock()
        healthCacheLock.lock()
        healthCacheUpdatedAt = .distantPast
        healthCacheLock.unlock()
    }

    private func scanSessionFiles(backgroundAgents: [String: BackgroundAgent]) -> [[String: Any]] {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("projects", isDirectory: true)
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var candidates: [(url: URL, modifiedAt: Date)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            if url.path.contains("CodexBar-ClaudeProbe") { continue }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modifiedAt = values.contentModificationDate else { continue }
            if let size = values.fileSize, Int64(size) > maxSessionFileBytes { continue }
            candidates.append((url, modifiedAt))
        }

        let iso = ISO8601DateFormatter()
        return candidates.sorted { $0.modifiedAt > $1.modifiedAt }.prefix(maxSessionFiles).compactMap { candidate in
            guard let segments = readSegments(candidate.url) else { return nil }
            var sessionId: String?
            var cwd = ""
            var createdAt = candidate.modifiedAt
            var foundCreatedAt = false
            var model = "Claude"
            var lastUserMessage = ""
            var lastResponse = ""
            var customTitle = ""

            for segment in segments {
                for line in segment.split(whereSeparator: \.isNewline) {
                    autoreleasepool {
                        guard let data = line.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
                        sessionId = stringValue(object, keys: ["sessionId", "session_id"], fallback: sessionId ?? "")
                        cwd = stringValue(object, keys: ["cwd", "workingDirectory"], fallback: cwd)
                        if !foundCreatedAt,
                           let timestamp = object["timestamp"] as? String,
                           let date = iso.date(from: timestamp) {
                            createdAt = min(createdAt, date)
                            foundCreatedAt = true
                        }
                        if object["type"] as? String == "custom-title" {
                            customTitle = stringValue(object, keys: ["customTitle", "title", "name"], fallback: customTitle)
                        }
                        guard let message = object["message"] as? [String: Any],
                              let role = message["role"] as? String else { return }
                        if let value = message["model"] as? String, !value.isEmpty, value != "<synthetic>" { model = value }
                        let text = extractText(message["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if role == "user", !text.isEmpty, text != "Continue from where you left off." {
                            lastUserMessage = String(text.suffix(1_200))
                        } else if role == "assistant", !text.isEmpty, text != "No response requested." {
                            lastResponse = String(text.suffix(1_200))
                        }
                    }
                }
            }

            if sessionId == nil {
                let candidateId = candidate.url.deletingPathExtension().lastPathComponent
                if UUID(uuidString: candidateId) != nil { sessionId = candidateId }
            }
            guard let id = sessionId, !id.isEmpty else { return nil }
            let preview = !customTitle.isEmpty
                ? customTitle
                : (lastUserMessage.isEmpty ? "Claude Code session" : String(lastUserMessage.prefix(120)))
            let normalizedPreview = (preview + " " + lastUserMessage).lowercased()
            if normalizedPreview.contains("conversation title generator")
                || normalizedPreview.contains("create a short title (3-5 words)") {
                return nil
            }
            return sessionPayload(
                id: id,
                cwd: cwd,
                preview: preview,
                lastUserMessage: lastUserMessage,
                lastResponse: lastResponse,
                model: model,
                sourcePath: candidate.url.path,
                createdAt: createdAt.timeIntervalSince1970 * 1_000,
                updatedAt: candidate.modifiedAt.timeIntervalSince1970 * 1_000,
                background: backgroundAgents[id]
            )
        }
    }

    private func sessionPayload(
        id: String,
        cwd: String,
        preview: String,
        lastUserMessage: String,
        lastResponse: String,
        model: String,
        sourcePath: String,
        createdAt: Double,
        updatedAt: Double,
        background: BackgroundAgent?
    ) -> [String: Any] {
        let providerFailure = claudeProviderFailure(in: lastResponse)
        let phase = background?.isActive == true ? "processing" : (providerFailure == nil ? "idle" : "error")
        var value: [String: Any] = [
            "id": id,
            "agentType": "Claude Code",
            "preview": preview,
            "cwd": cwd,
            "sourcePath": sourcePath,
            "createdAt": createdAt,
            "updatedAt": updatedAt,
            "phase": phase,
            "lastResponse": lastResponse,
            "lastUserMessage": lastUserMessage,
            "model": model,
            "source": "claude-adapter",
            "requests": [],
            "controlAvailable": providerFailure == nil
        ]
        if let providerFailure {
            value["controlReason"] = "provider_authentication_failed"
            value["controlError"] = providerFailure
        }
        if let background {
            value["jobId"] = background.id
            value["pid"] = background.pid
            value["backgroundState"] = background.state
        }
        return value
    }

    private func control(_ params: [String: Any]) -> [String: Any] {
        let sessionId = stringValue(params, keys: ["threadId", "sessionId", "conversationId"])
        guard !sessionId.isEmpty else { return ["ok": false, "error": "missing_session_id"] }
        let action = params["action"] as? String ?? "instruction"

        if action == "approval" {
            return resolveApproval(params)
        }
        guard let cli = claudeExecutable() else {
            return ["ok": false, "error": "claude_cli_not_installed"]
        }

        let agents = backgroundAgents()
        let active = agents.first { $0.sessionId == sessionId && $0.isActive }
        if action == "interrupt" {
            guard let active else {
                return ["ok": true, "result": [
                    "command": "claude_already_idle",
                    "message": "Claude Code 会话已经空闲。"
                ]]
            }
            guard stopBackgroundJob(cli: cli, jobId: active.id) else {
                return ["ok": false, "error": "claude_stop_failed"]
            }
            invalidateSessionCache()
            return ["ok": true, "result": [
                "command": "claude_stop",
                "message": "Claude Code 后台任务已停止。",
                "jobId": active.id
            ]]
        }

        let instruction = (params["instruction"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { return ["ok": false, "error": "missing_instruction"] }
        if let active {
            guard stopBackgroundJob(cli: cli, jobId: active.id) else {
                return ["ok": false, "error": "claude_stop_before_resume_failed"]
            }
        }

        let cwd = sessionWorkingDirectory(sessionId: sessionId) ?? NSHomeDirectory()
        let launched = runProcess(
            cli,
            ["--bg", "--resume", sessionId, "--permission-mode", "manual", "--name", "TraceFence Remote", instruction],
            currentDirectory: cwd,
            timeout: 7
        )
        guard launched.status == 0, !launched.timedOut else {
            return ["ok": false, "error": readableProcessError(launched, fallback: "claude_resume_failed")]
        }
        guard let jobId = parseBackgroundJobId(launched.output + "\n" + launched.error) else {
            return ["ok": false, "error": "claude_background_job_id_missing"]
        }

        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.5)
            let jobState = backgroundJobState(jobId: jobId)?.lowercased()
            let isActive = jobState.map { ["working", "busy", "starting", "running"].contains($0) } ?? true
            if !isActive { break }
        }
        let logs = runProcess(cli, ["logs", jobId], timeout: 2)
        let combinedLogs = stripANSI(logs.output + "\n" + logs.error)
        if let providerFailure = claudeProviderFailure(in: combinedLogs) {
            let stopped = stopBackgroundJob(cli: cli, jobId: jobId)
            let failure = stopped
                ? providerFailure + " TraceFence 已停止该任务。"
                : providerFailure + " TraceFence 未能确认后台任务已停止，请在 Mac 检查 Claude Code。"
            state.setProviderError(failure)
            invalidateSessionCache()
            return ["ok": false, "error": failure]
        }
        let refreshed = backgroundAgents().first { $0.id == jobId }
        invalidateSessionCache()
        return ["ok": true, "result": [
            "command": active == nil ? "claude_resume" : "claude_interrupt_and_resume",
            "message": active == nil
                ? "指令已在真实 Claude Code 后台会话中启动。"
                : "已停止当前 Claude turn，并用新指令继续执行。",
            "jobId": jobId,
            "newSessionId": refreshed?.sessionId ?? ""
        ]]
    }

    private func resolveApproval(_ params: [String: Any]) -> [String: Any] {
        let requestId = stringValue(params, keys: ["requestId"])
        guard !requestId.isEmpty, let pending = state.removePending(id: requestId) else {
            return ["ok": false, "error": "claude_approval_not_found"]
        }
        let allow = params["allow"] as? Bool ?? false
        let reason = params["answer"] as? String
        let response = Self.permissionResponse(allow: allow, reason: reason)
        let sent = writeJSONObject(response, fd: pending.fd)
        close(pending.fd)
        guard sent else { return ["ok": false, "error": "claude_approval_delivery_failed"] }
        return ["ok": true, "result": [
            "command": allow ? "claude_approval_allow" : "claude_approval_deny",
            "message": allow
                ? "已从 iPhone 批准 Claude Code 权限请求。"
                : "已从 iPhone 拒绝 Claude Code 权限请求。"
        ]]
    }

    private static func permissionResponse(allow: Bool, reason: String?) -> [String: Any] {
        var decision: [String: Any] = ["behavior": allow ? "allow" : "deny"]
        if !allow { decision["message"] = reason?.isEmpty == false ? reason! : "Denied by TraceFence Sentinel" }
        return [
            "decision": allow ? "allow" : "deny",
            "reason": reason ?? "",
            "permissionDecision": allow ? "allow" : "deny",
            "permissionDecisionReason": reason ?? "",
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decision
            ]
        ]
    }

    private func requestPayload(for hook: PendingHook) -> [String: Any] {
        let event = hook.event
        let toolName = stringValue(event, keys: ["tool_name", "toolName", "tool", "name"], fallback: "Claude Code tool")
        let input = event["tool_input"] ?? event["toolInput"] ?? event["input"] ?? [:]
        return [
            "method": "item/permissions/requestApproval",
            "requestId": hook.id,
            "source": "claude-hook",
            "params": [
                "title": toolName,
                "command": stringify(input),
                "reason": stringValue(event, keys: ["reason", "message"], fallback: "Claude Code requests permission to use \(toolName)."),
                "permissions": event["permission_suggestions"] ?? []
            ]
        ]
    }

    private func backgroundAgents() -> [BackgroundAgent] {
        guard let cli = claudeExecutable() else { return [] }
        let result = runProcess(cli, ["agents", "--all", "--json"], timeout: 5)
        guard result.status == 0,
              let data = result.output.data(using: .utf8),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return rows.compactMap { row in
            let id = row["id"] as? String ?? ""
            let sessionId = row["sessionId"] as? String ?? ""
            guard !id.isEmpty, !sessionId.isEmpty else { return nil }
            return BackgroundAgent(
                id: id,
                sessionId: sessionId,
                cwd: row["cwd"] as? String ?? "",
                name: row["name"] as? String ?? "",
                state: row["state"] as? String ?? "",
                status: row["status"] as? String ?? "",
                startedAt: (row["startedAt"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1_000,
                pid: (row["pid"] as? NSNumber)?.intValue
            )
        }
    }

    private func sessionWorkingDirectory(sessionId: String) -> String? {
        listSessions().first { $0["id"] as? String == sessionId }?["cwd"] as? String
    }

    private func backgroundJobState(jobId: String) -> String? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/jobs", isDirectory: true)
            .appendingPathComponent(jobId, isDirectory: true)
            .appendingPathComponent("state.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["state"] as? String
    }

    private func stopBackgroundJob(cli: String, jobId: String) -> Bool {
        let first = runProcess(cli, ["stop", jobId], timeout: 8)
        for _ in 0..<10 {
            if let value = backgroundJobState(jobId: jobId), !isActiveClaudeJobState(value) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        if let pid = backgroundAgents().first(where: { $0.id == jobId })?.pid {
            kill(pid_t(pid), SIGTERM)
            Thread.sleep(forTimeInterval: 0.5)
        }
        let retry = runProcess(cli, ["stop", jobId], timeout: 5)
        for _ in 0..<10 {
            if let value = backgroundJobState(jobId: jobId), !isActiveClaudeJobState(value) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return backgroundJobState(jobId: jobId) == nil
            && (first.status == 0 || retry.status == 0)
            && !first.timedOut
            && !retry.timedOut
    }

    private func readSegments(_ url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        let head = handle.readData(ofLength: 96 * 1_024)
        _ = try? handle.seekToEnd()
        let size = handle.offsetInFile
        let tailOffset = size > 256 * 1_024 ? size - 256 * 1_024 : 0
        try? handle.seek(toOffset: tailOffset)
        let tail = handle.readDataToEndOfFile()
        try? handle.close()
        return [String(data: head, encoding: .utf8) ?? "", String(data: tail, encoding: .utf8) ?? ""]
    }

    private func claudeDesktopDetected() -> Bool {
        fileManager.fileExists(atPath: "/Applications/Claude.app")
            || fileManager.fileExists(atPath: NSHomeDirectory() + "/Applications/Claude.app")
    }
}

private func installClaudeHooks(adapterPath: String, hookSocketPath: String) throws {
    let settingsURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    var settings: [String: Any] = [:]
    if FileManager.default.fileExists(atPath: settingsURL.path) {
        let data = try Data(contentsOf: settingsURL)
        guard !data.isEmpty,
              let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(
                domain: "TraceFenceClaudeAdapter",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Refusing to modify \(settingsURL.path): it is not a readable JSON object. Repair the file and install hooks again."]
            )
        }
        settings = existing
        let backupURL = settingsURL.appendingPathExtension("tracefence-backup")
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try data.write(to: backupURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        }
    }
    let existingHooks = settings["hooks"] as? [String: Any] ?? [:]
    var hooks: [String: [[String: Any]]] = [:]
    for (event, value) in existingHooks {
        if let entries = value as? [[String: Any]] {
            hooks[event] = entries
        }
    }
    let preservedHooks = existingHooks.filter { hooks[$0.key] == nil }
    let command = "/usr/bin/env TRACEFENCE_CLAUDE_HOOK_SOCKET=\(shellQuote(hookSocketPath)) \(shellQuote(adapterPath)) --hook"
    let events: [(String, Bool, Int?)] = [
        ("UserPromptSubmit", false, nil), ("PreToolUse", true, nil), ("PostToolUse", true, nil),
        ("PermissionRequest", true, 21_600), ("Notification", true, nil), ("Stop", false, nil),
        ("SubagentStop", false, nil), ("SessionStart", false, nil), ("SessionEnd", false, nil),
        ("PreCompact", false, nil)
    ]
    for (event, matcher, timeout) in events {
        var entries = hooks[event] ?? []
        entries.removeAll { entry in
            let direct = entry["command"] as? String ?? ""
            let nested = (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }.joined(separator: " ")
            let value = direct + " " + nested
            return value.contains("agentguard-bridge") || value.contains("TraceFenceClaudeAdapter")
        }
        var commandHook: [String: Any] = ["type": "command", "command": command]
        if let timeout { commandHook["timeout"] = timeout }
        // Claude Code 2.1 requires every event entry to be a hook group whose
        // `hooks` member is an array. The legacy flat `{ "command": ... }`
        // form makes the entire settings file invalid before `/usage` starts.
        entries.append(["matcher": matcher ? "*" : "", "hooks": [commandHook]])
        hooks[event] = entries
    }
    var mergedHooks = preservedHooks
    for (event, entries) in hooks {
        mergedHooks[event] = entries
    }
    settings["hooks"] = mergedHooks
    let directory = settingsURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try data.write(to: settingsURL, options: .atomic)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
}

private func runHookClient(socketPath: String) -> Int32 {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard !input.isEmpty, input.count <= maxRequestBytes,
          let fd = connectUnix(path: socketPath, timeout: 21_610) else { return 1 }
    defer { close(fd) }
    var payload = input
    if payload.last != 0x0A { payload.append(0x0A) }
    guard writeAll(payload, fd: fd), let response = readLine(fd: fd, maxBytes: maxResponseBytes) else { return 1 }
    FileHandle.standardOutput.write(response)
    FileHandle.standardOutput.write(Data([0x0A]))
    return 0
}

private func runAdapterClient(socketPath: String) -> Int32 {
    let input = FileHandle.standardInput.readDataToEndOfFile()
    guard !input.isEmpty, input.count <= maxRequestBytes,
          let fd = connectUnix(path: socketPath, timeout: 70) else {
        let error = ["ok": false, "error": "claude_adapter_daemon_unavailable"] as [String: Any]
        if let data = try? JSONSerialization.data(withJSONObject: error) { FileHandle.standardOutput.write(data) }
        return 1
    }
    defer { close(fd) }
    var payload = input
    if payload.last != 0x0A { payload.append(0x0A) }
    guard writeAll(payload, fd: fd), let response = readLine(fd: fd, maxBytes: maxResponseBytes) else { return 1 }
    FileHandle.standardOutput.write(response)
    return 0
}

private func claudeExecutable() -> String? {
    let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
    let home = NSHomeDirectory()
    let candidates = environmentPath.split(separator: ":").map(String.init) + [
        "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        home + "/.local/bin", home + "/.npm-global/bin", home + "/.bun/bin"
    ]
    for directory in candidates {
        let path = URL(fileURLWithPath: directory).appendingPathComponent("claude").path
        if FileManager.default.isExecutableFile(atPath: path) { return path }
    }
    return nil
}

private func runProcess(
    _ executable: String,
    _ arguments: [String],
    currentDirectory: String? = nil,
    timeout: TimeInterval,
    includeStoredClaudeEnvironment: Bool? = nil
) -> ProcessResult {
    let process = Process()
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    if let currentDirectory, FileManager.default.fileExists(atPath: currentDirectory) {
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory, isDirectory: true)
    }
    var environment = ProcessInfo.processInfo.environment
    environment["HOME"] = NSHomeDirectory()
    environment["NO_COLOR"] = "1"
    environment["TERM"] = "dumb"
    environment.removeValue(forKey: "FORCE_COLOR")
    let shouldIncludeStoredEnvironment = includeStoredClaudeEnvironment
        ?? claudeEnvironmentPolicy.shouldUseStoredEnvironment()
    if shouldIncludeStoredEnvironment {
        for (key, value) in storedClaudeEnvironment.values() where environment[key]?.isEmpty != false {
            environment[key] = value
        }
    }
    process.environment = environment

    let termination = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in termination.signal() }
    do {
        try process.run()
    } catch {
        return ProcessResult(status: -1, output: "", error: error.localizedDescription, timedOut: false)
    }

    let outputBuffer = BoundedProcessBuffer(limit: maxProcessOutputBytes)
    let errorBuffer = BoundedProcessBuffer(limit: maxProcessErrorBytes)
    let readers = DispatchGroup()
    readers.enter()
    DispatchQueue.global(qos: .utility).async {
        drainProcessPipe(outputPipe.fileHandleForReading, into: outputBuffer)
        readers.leave()
    }
    readers.enter()
    DispatchQueue.global(qos: .utility).async {
        drainProcessPipe(errorPipe.fileHandleForReading, into: errorBuffer)
        readers.leave()
    }

    let timedOut = termination.wait(timeout: .now() + timeout) == .timedOut
    if timedOut {
        kill(process.processIdentifier, SIGTERM)
        if termination.wait(timeout: .now() + 1) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            if termination.wait(timeout: .now() + 3) == .timedOut {
                process.waitUntilExit()
            }
        }
    }
    if readers.wait(timeout: .now() + 2) == .timedOut {
        // A descendant can inherit a pipe after the direct child exits. Close
        // our read ends so health polling cannot hang behind that descendant.
        try? outputPipe.fileHandleForReading.close()
        try? errorPipe.fileHandleForReading.close()
    }
    readers.wait()
    return ProcessResult(
        status: process.isRunning ? -1 : process.terminationStatus,
        output: outputBuffer.text(),
        error: errorBuffer.text(),
        timedOut: timedOut
    )
}

private func drainProcessPipe(_ handle: FileHandle, into buffer: BoundedProcessBuffer) {
    while true {
        do {
            let reachedEnd = try autoreleasepool { () -> Bool in
                guard let chunk = try handle.read(upToCount: 64 * 1_024), !chunk.isEmpty else { return true }
                buffer.append(chunk)
                return false
            }
            if reachedEnd { return }
        } catch {
            return
        }
    }
}

private func runProcessSelfTest() -> Int32 {
    let timeoutResult = runProcess(
        "/bin/sh",
        ["-c", "printf ready; sleep 5"],
        timeout: 0.1,
        includeStoredClaudeEnvironment: false
    )
    let outputResult = runProcess(
        "/usr/bin/yes",
        ["0123456789abcdef"],
        timeout: 0.1,
        includeStoredClaudeEnvironment: false
    )
    let failures = [
        timeoutResult.timedOut ? nil : "timeout_not_reported",
        outputResult.timedOut ? nil : "bounded_output_timeout_not_reported",
        outputResult.output.utf8.count <= maxProcessOutputBytes ? nil : "output_limit_exceeded"
    ].compactMap { $0 }
    let payload: [String: Any] = [
        "ok": failures.isEmpty,
        "failures": failures,
        "adapterVersion": adapterVersion,
        "capturedOutputBytes": outputResult.output.utf8.count
    ]
    if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0A]))
    }
    return failures.isEmpty ? 0 : 2
}

private func importClaudeEnvironment() -> Int32 {
    let values = Dictionary(uniqueKeysWithValues: claudeEnvironmentKeys.compactMap { key -> (String, String)? in
        guard let value = ProcessInfo.processInfo.environment[key], !value.isEmpty else { return nil }
        return (key, value)
    })
    guard !values.isEmpty else { return 0 }
    do {
        try FileManager.default.createDirectory(at: claudeEnvironmentFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(values)
        try data.write(to: claudeEnvironmentFileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: claudeEnvironmentFileURL.path)
    } catch {
        fputs("Could not store Claude environment: \(error.localizedDescription)\n", stderr)
        return 2
    }
    return 0
}

private func makeUnixListener(path: String) throws -> Int32 {
    let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    unlink(path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw POSIXError(.ENOTSOCK) }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
        close(fd)
        throw POSIXError(.ENAMETOOLONG)
    }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { destination in
            _ = pathBytes.withUnsafeBufferPointer { source in memcpy(destination, source.baseAddress, pathBytes.count) }
        }
    }
    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard bound == 0, listen(fd, 16) == 0 else {
        let code = errno
        close(fd)
        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }
    chmod(path, 0o600)
    return fd
}

private func connectUnix(path: String, timeout: TimeInterval) -> Int32? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return nil }
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = path.utf8CString
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return nil }
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: bytes.count) { destination in
            _ = bytes.withUnsafeBufferPointer { source in memcpy(destination, source.baseAddress, bytes.count) }
        }
    }
    var value = timeval(tv_sec: Int(timeout), tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
    let connected = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { close(fd); return nil }
    return fd
}

private func readJSONObjectLine(fd: Int32, maxBytes: Int) -> [String: Any]? {
    guard let data = readLine(fd: fd, maxBytes: maxBytes) else { return nil }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private func readLine(fd: Int32, maxBytes: Int) -> Data? {
    var result = Data()
    var byte: UInt8 = 0
    while result.count < maxBytes {
        let count = Darwin.read(fd, &byte, 1)
        guard count > 0 else { return result.isEmpty ? nil : result }
        if byte == 0x0A { return result }
        result.append(byte)
    }
    return nil
}

private func writeJSONObject(_ object: [String: Any], fd: Int32) -> Bool {
    guard var data = try? JSONSerialization.data(withJSONObject: object) else { return false }
    data.append(0x0A)
    return writeAll(data, fd: fd)
}

private func writeAll(_ data: Data, fd: Int32) -> Bool {
    data.withUnsafeBytes { raw in
        guard var pointer = raw.baseAddress else { return false }
        var remaining = raw.count
        while remaining > 0 {
            let count = Darwin.write(fd, pointer, remaining)
            guard count > 0 else { return false }
            pointer = pointer.advanced(by: count)
            remaining -= count
        }
        return true
    }
}

private func extractText(_ value: Any?) -> String {
    if let text = value as? String { return text }
    if let rows = value as? [[String: Any]] {
        return rows.compactMap { row in
            row["text"] as? String ?? row["content"] as? String ?? row["input_text"] as? String ?? row["output_text"] as? String
        }.joined(separator: "\n")
    }
    return ""
}

private func stringValue(_ object: [String: Any], keys: [String], fallback: String = "") -> String {
    for key in keys {
        if let value = object[key] as? String, !value.isEmpty { return value }
        if let value = object[key] as? NSNumber { return value.stringValue }
    }
    return fallback
}

private func stringify(_ value: Any) -> String {
    if let value = value as? String { return value }
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
          let text = String(data: data, encoding: .utf8) else { return String(describing: value) }
    return String(text.prefix(4_000))
}

private func pendingHookId(event: [String: Any]) -> String {
    let sessionId = stringValue(event, keys: ["session_id", "sessionId", "conversation_id", "conversationId"])
    let tool = stringValue(event, keys: ["tool_name", "toolName", "tool", "name"])
    let input = stringify(event["tool_input"] ?? event["toolInput"] ?? event["input"] ?? [:])
    let nonce = stringValue(event, keys: ["uuid", "request_id", "requestId"], fallback: UUID().uuidString)
    let digest = SHA256.hash(data: Data("\(sessionId)\u{0}\(tool)\u{0}\(input)\u{0}\(nonce)".utf8))
    return "claude-hook-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
}

private func parseBackgroundJobId(_ text: String) -> String? {
    let pattern = #"backgrounded\s*[·:]\s*([0-9a-fA-F]{8})"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
          let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
          let range = Range(match.range(at: 1), in: text) else { return nil }
    return String(text[range]).lowercased()
}

private func readableProcessError(_ result: ProcessResult, fallback: String) -> String {
    if result.timedOut { return fallback + ": timeout" }
    let value = stripANSI(result.error + "\n" + result.output).trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? fallback : String(value.suffix(2_000))
}

private func claudeAuthLoggedIn(_ result: ProcessResult) -> Bool {
    guard let data = result.output.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
    return object["loggedIn"] as? Bool ?? false
}

private func claudeProviderFailure(in text: String) -> String? {
    let normalized = text.lowercased()
    if normalized.contains("authentication_failed")
        || normalized.contains("api key status is not active")
        || normalized.contains("401the api key")
        || normalized.contains("401 the api key")
        || normalized.contains("not logged in")
        || normalized.contains("run /login") {
        return "Claude Code 凭据无效。请在 Mac 登录 Claude Code 或更新 API 提供商凭据后重试。"
    }
    if normalized.contains("api error") {
        return "Claude Code 提供商请求失败。请在 Mac 检查 Claude Code 登录或 API 提供商配置后重试。"
    }
    return nil
}

private func isActiveClaudeJobState(_ value: String) -> Bool {
    ["working", "busy", "starting", "running"].contains(value.lowercased())
}

private func stripANSI(_ text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"\u001B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])"#) else { return text }
    return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
}

private func shellQuote(_ value: String) -> String {
    if value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "/._-:=@".contains($0)) }) { return value }
    return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private func argument(after flag: String, default fallback: String) -> String {
    let args = CommandLine.arguments
    guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return fallback }
    return args[index + 1]
}

let coreDirectory = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Library/Application Support/TraceFence/Core", isDirectory: true)
let defaultRPCSocket = coreDirectory.appendingPathComponent("claude-adapter.sock").path
let defaultHookSocket = coreDirectory.appendingPathComponent("claude-hooks.sock").path
let arguments = CommandLine.arguments

// A menu refresh or hook client can disconnect before the daemon finishes its
// response. Treat EPIPE as a failed write instead of letting the default
// SIGPIPE disposition terminate launchd's long-running adapter process.
_ = Darwin.signal(SIGPIPE, SIG_IGN)

if arguments.contains("--self-test") {
    exit(runProcessSelfTest())
} else if arguments.contains("--import-environment") {
    exit(importClaudeEnvironment())
} else if arguments.contains("--daemon") {
    let rpcSocket = argument(after: "--socket", default: defaultRPCSocket)
    let hookSocket = argument(after: "--hook-socket", default: defaultHookSocket)
    do {
        let daemon = ClaudeAdapterDaemon(rpcSocketPath: rpcSocket, hookSocketPath: hookSocket)
        try daemon.run()
    } catch {
        fputs("TraceFenceClaudeAdapter failed: \(error)\n", stderr)
        exit(2)
    }
} else if arguments.contains("--hook") {
    let socket = ProcessInfo.processInfo.environment["TRACEFENCE_CLAUDE_HOOK_SOCKET"] ?? defaultHookSocket
    exit(runHookClient(socketPath: socket))
} else if arguments.contains("--install-hooks") {
    let hookSocket = argument(after: "--hook-socket", default: defaultHookSocket)
    do {
        try installClaudeHooks(adapterPath: URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path, hookSocketPath: hookSocket)
        exit(0)
    } catch {
        fputs("Could not install Claude Code hooks: \(error)\n", stderr)
        exit(2)
    }
} else {
    let socket = ProcessInfo.processInfo.environment["TRACEFENCE_CLAUDE_ADAPTER_SOCKET"] ?? defaultRPCSocket
    exit(runAdapterClient(socketPath: socket))
}
