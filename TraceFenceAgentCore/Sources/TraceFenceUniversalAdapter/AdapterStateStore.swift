import Foundation
import Darwin

final class AdapterStateStore {
    let root: URL
    private let fileManager = FileManager.default

    init() {
        root = universalStateDirectoryURL()
        try? fileManager.createDirectory(at: jobsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: approvalsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: decisionsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
    }

    var jobsDirectory: URL { root.appendingPathComponent("jobs", isDirectory: true) }
    var approvalsDirectory: URL { root.appendingPathComponent("approvals", isDirectory: true) }
    var decisionsDirectory: URL { root.appendingPathComponent("decisions", isDirectory: true) }
    var logsDirectory: URL { root.appendingPathComponent("logs", isDirectory: true) }

    func jobs(adapterId: String) -> [ManagedJob] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: jobsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url -> ManagedJob? in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  var job = try? JSONDecoder().decode(ManagedJob.self, from: data),
                  job.adapterId == adapterId else { return nil }
            if job.phase == "processing", !processIsAlive(job.pid) {
                job.phase = "done"
                job.updatedAt = max(job.updatedAt, fileModifiedAt(job.outputPath))
                save(job)
            }
            return job
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    func job(adapterId: String, sessionId: String) -> ManagedJob? {
        jobs(adapterId: adapterId).first {
            $0.id == sessionId || $0.nativeSessionId == sessionId
        }
    }

    func save(_ job: ManagedJob) {
        guard let data = try? JSONEncoder().encode(job) else { return }
        let url = jobsDirectory.appendingPathComponent(safeFileName("\(job.adapterId)-\(job.id)")).appendingPathExtension("json")
        atomicWrite(data, to: url)
    }

    func removeJob(adapterId: String, sessionId: String) {
        guard let job = job(adapterId: adapterId, sessionId: sessionId) else { return }
        let url = jobsDirectory.appendingPathComponent(safeFileName("\(job.adapterId)-\(job.id)")).appendingPathExtension("json")
        try? fileManager.removeItem(at: url)
    }

    func outputPath(adapterId: String, sessionId: String) -> URL {
        logsDirectory
            .appendingPathComponent(safeFileName("\(adapterId)-\(sessionId)"))
            .appendingPathExtension("jsonl")
    }

    func outputTail(path: String, maxBytes: Int = 64 * 1_024) -> String {
        guard let handle = try? FileHandle(forReadingFrom: URL(fileURLWithPath: path)) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        if size > UInt64(maxBytes) {
            try? handle.seek(toOffset: size - UInt64(maxBytes))
        } else {
            try? handle.seek(toOffset: 0)
        }
        let data = (try? handle.readToEnd()) ?? Data()
        let text = String(data: data, encoding: .utf8) ?? ""
        return String(text.suffix(8_000)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func pendingApprovals(adapterId: String? = nil) -> [PendingHookApproval] {
        cleanupExpiredApprovals()
        guard let urls = try? fileManager.contentsOfDirectory(at: approvalsDirectory, includingPropertiesForKeys: nil) else { return [] }
        return urls.compactMap { url -> PendingHookApproval? in
            guard url.pathExtension == "json",
                  let data = try? Data(contentsOf: url),
                  let approval = try? JSONDecoder().decode(PendingHookApproval.self, from: data),
                  adapterId == nil || approval.adapterId == adapterId else { return nil }
            return approval
        }.sorted { $0.createdAt > $1.createdAt }
    }

    func save(_ approval: PendingHookApproval) {
        guard let data = try? JSONEncoder().encode(approval) else { return }
        atomicWrite(data, to: approvalURL(requestId: approval.requestId))
    }

    func writeDecision(requestId: String, allow: Bool, answer: String? = nil) {
        var value: [String: Any] = [
            "requestId": requestId,
            "allow": allow,
            "decidedAt": Date().timeIntervalSince1970
        ]
        if let answer, !answer.isEmpty { value["answer"] = answer }
        guard let data = try? JSONSerialization.data(withJSONObject: value) else { return }
        atomicWrite(data, to: decisionURL(requestId: requestId))
    }

    func decision(requestId: String) -> (allow: Bool, answer: String?)? {
        let url = decisionURL(requestId: requestId)
        guard let data = try? Data(contentsOf: url), let object = jsonObject(data), let allow = object["allow"] as? Bool else { return nil }
        return (allow, object["answer"] as? String)
    }

    func finishApproval(requestId: String) {
        try? fileManager.removeItem(at: approvalURL(requestId: requestId))
        try? fileManager.removeItem(at: decisionURL(requestId: requestId))
    }

    private func approvalURL(requestId: String) -> URL {
        approvalsDirectory.appendingPathComponent(safeFileName(requestId)).appendingPathExtension("json")
    }

    private func decisionURL(requestId: String) -> URL {
        decisionsDirectory.appendingPathComponent(safeFileName(requestId)).appendingPathExtension("json")
    }

    private func cleanupExpiredApprovals() {
        let cutoff = Date().timeIntervalSince1970 - 24 * 60 * 60
        guard let urls = try? fileManager.contentsOfDirectory(at: approvalsDirectory, includingPropertiesForKeys: nil) else { return }
        for url in urls {
            guard let data = try? Data(contentsOf: url),
                  let approval = try? JSONDecoder().decode(PendingHookApproval.self, from: data),
                  approval.createdAt < cutoff else { continue }
            finishApproval(requestId: approval.requestId)
        }
    }

    private func atomicWrite(_ data: Data, to url: URL) {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: temp, options: .atomic)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            try fileManager.moveItem(at: temp, to: url)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            try? fileManager.removeItem(at: temp)
        }
    }

    private func safeFileName(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) || "-_.".unicodeScalars.contains(scalar) ? String(scalar) : "_"
        }.joined()
    }

    private func fileModifiedAt(_ path: String) -> Double {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path), let date = attributes[.modificationDate] as? Date else { return 0 }
        return date.timeIntervalSince1970
    }
}

final class UniversalHookBridge {
    private let profile: UniversalAdapterProfile
    private let store: AdapterStateStore

    init(profile: UniversalAdapterProfile, store: AdapterStateStore) {
        self.profile = profile
        self.store = store
    }

    func run(input: [String: Any], timeout: TimeInterval = 21_600) -> Int32 {
        let event = string(input, keys: ["hookEventName", "hook_event_name", "event", "eventName"], fallback: "PreToolUse")
        let sessionId = string(input, keys: ["sessionId", "session_id", "conversation_id"], fallback: "hook-\(UUID().uuidString.lowercased())")
        let cwd = string(input, keys: ["cwd", "workspaceRoot", "workspace_root"], fallback: "")
        let workspaceRoot = (input["workspace_roots"] as? [String])?.first ?? NSHomeDirectory()
        let tool = string(input, keys: ["toolName", "tool_name", "tool"], fallback: "Agent tool")
        let toolInput = input["toolInput"] ?? input["tool_input"] ?? input["arguments"] ?? [:]
        let command = commandText(toolInput)
        let requestId = "\(profile.id)-\(sessionId)-\(string(input, keys: ["toolUseId", "tool_use_id", "tool_call_id"], fallback: UUID().uuidString))"
        let approval = PendingHookApproval(
            requestId: requestId,
            adapterId: profile.id,
            sessionId: sessionId,
            cwd: cwd.isEmpty ? workspaceRoot : cwd,
            eventName: event,
            toolName: tool,
            toolInput: jsonString(toolInput),
            command: command,
            createdAt: Date().timeIntervalSince1970
        )
        store.save(approval)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let decision = store.decision(requestId: requestId) {
                store.finishApproval(requestId: requestId)
                emitHookDecision(allow: decision.allow, event: event)
                return decision.allow ? 0 : 2
            }
            usleep(200_000)
        }

        store.finishApproval(requestId: requestId)
        emitHookDecision(allow: false, event: event, reason: "TraceFence remote approval timed out.")
        return 2
    }

    private func emitHookDecision(allow: Bool, event: String, reason: String? = nil) {
        let message = reason ?? (allow ? "Approved from TraceFence Sentinel." : "Denied from TraceFence Sentinel.")
        let payload: [String: Any]
        switch profile.id {
        case "qwen":
            if event.lowercased().contains("permission") {
                payload = [
                    "hookSpecificOutput": [
                        "hookEventName": "PermissionRequest",
                        "decision": ["behavior": allow ? "allow" : "deny", "message": message, "interrupt": false]
                    ]
                ]
            } else {
                payload = [
                    "hookSpecificOutput": [
                        "hookEventName": "PreToolUse",
                        "permissionDecision": allow ? "allow" : "deny",
                        "permissionDecisionReason": message
                    ]
                ]
            }
        case "gemini":
            payload = ["decision": allow ? "allow" : "deny", "reason": message, "suppressOutput": true]
        case "hermes":
            payload = allow ? [:] : ["action": "block", "message": message]
        case "cursor":
            payload = ["permission": allow ? "allow" : "deny", "user_message": message]
        default:
            payload = ["decision": allow ? "allow" : "deny", "reason": message]
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload) {
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([0x0A]))
        }
        if !allow { fputs("\(message)\n", stderr) }
    }

    private func string(_ object: [String: Any], keys: [String], fallback: String) -> String {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return fallback
    }

    private func commandText(_ value: Any) -> String {
        guard let object = value as? [String: Any] else { return "" }
        for key in ["command", "cmd", "script", "path", "file_path"] {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return ""
    }
}
