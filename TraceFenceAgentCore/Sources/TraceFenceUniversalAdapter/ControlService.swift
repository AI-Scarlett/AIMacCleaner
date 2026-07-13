import Foundation
import Darwin

final class ControlService {
    private let profile: UniversalAdapterProfile
    private let store: AdapterStateStore
    private let discovery: SessionDiscovery

    init(profile: UniversalAdapterProfile, store: AdapterStateStore, discovery: SessionDiscovery) {
        self.profile = profile
        self.store = store
        self.discovery = discovery
    }

    func control(_ params: [String: Any]) throws -> [String: Any] {
        let action = string(params["action"]).lowercased()
        switch action {
        case "approval":
            return try resolveApproval(params)
        case "interrupt", "terminate", "stop":
            return try interrupt(params)
        case "instruction", "resume", "steer", "start", "launch":
            return try sendInstruction(params)
        default:
            throw UniversalAdapterError.controlUnavailable("unsupported_control_action:\(action)")
        }
    }

    private func resolveApproval(_ params: [String: Any]) throws -> [String: Any] {
        let requestId = string(params["requestId"])
        guard !requestId.isEmpty else { throw UniversalAdapterError.invalidRequest }
        let allow = bool(params["allow"])
        let answer = params["answer"] as? String

        if store.pendingApprovals(adapterId: profile.id).contains(where: { $0.requestId == requestId }) {
            store.writeDecision(requestId: requestId, allow: allow, answer: answer)
            return [
                "command": allow ? "approval_approved" : "approval_denied",
                "message": allow ? "Approval sent to \(profile.displayName)." : "Request denied in \(profile.displayName)."
            ]
        }

        let sessionId = requestedSessionId(params)
        if let target = nativeOpenCodeTarget(sessionId: sessionId) {
            let response = allow ? "once" : "reject"
            _ = try openCodeRequest(
                target: target,
                method: "POST",
                path: "/session/\(urlPath(target.sessionId))/permissions/\(urlPath(requestId))",
                body: ["response": response, "remember": false]
            )
            return [
                "command": allow ? "approval_approved" : "approval_denied",
                "message": allow ? "Approval sent to \(profile.displayName)." : "Request denied in \(profile.displayName)."
            ]
        }

        throw UniversalAdapterError.controlUnavailable("approval_request_not_active")
    }

    private func interrupt(_ params: [String: Any]) throws -> [String: Any] {
        let sessionId = requestedSessionId(params)
        guard !sessionId.isEmpty else { throw UniversalAdapterError.invalidRequest }

        if var job = store.job(adapterId: profile.id, sessionId: sessionId), processIsAlive(job.pid) {
            signalInterrupt(pid: job.pid)
            job.phase = "interrupted"
            job.updatedAt = Date().timeIntervalSince1970
            store.save(job)
            return [
                "command": "interrupt",
                "message": "Interrupt delivered to the real \(profile.displayName) process.",
                "pid": Int(job.pid)
            ]
        }

        if let target = nativeOpenCodeTarget(sessionId: sessionId) {
            _ = try openCodeRequest(
                target: target,
                method: "POST",
                path: "/session/\(urlPath(target.sessionId))/abort",
                body: [:]
            )
            return [
                "command": "interrupt",
                "message": "Interrupt delivered through the \(profile.displayName) control plane."
            ]
        }

        throw UniversalAdapterError.controlUnavailable("session_not_running")
    }

    private func sendInstruction(_ params: [String: Any]) throws -> [String: Any] {
        let instruction = string(params["instruction"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty else { throw UniversalAdapterError.controlUnavailable("instruction_required") }
        let requestedId = requestedSessionId(params)

        if let target = nativeOpenCodeTarget(sessionId: requestedId) {
            _ = try openCodeRequest(
                target: target,
                method: "POST",
                path: "/session/\(urlPath(target.sessionId))/prompt_async",
                body: ["parts": [["type": "text", "text": instruction]]]
            )
            return [
                "command": "instruction",
                "message": "Instruction inserted into the live \(profile.displayName) session."
            ]
        }

        guard let executable = profile.commandURL else {
            throw UniversalAdapterError.controlUnavailable(unavailableMessage())
        }

        if let active = store.job(adapterId: profile.id, sessionId: requestedId), processIsAlive(active.pid) {
            signalInterrupt(pid: active.pid)
            waitForExit(pid: active.pid, timeout: 2)
        }

        let existing = existingSession(id: requestedId)
        if let existing, existing["controlAvailable"] as? Bool == false {
            let reason = string(existing["controlError"] ?? existing["controlReason"])
            throw UniversalAdapterError.controlUnavailable(reason.isEmpty ? "session_control_unavailable" : reason)
        }
        let resume = shouldResume(existing: existing)
        let nativeId = nativeSessionId(requested: requestedId, resume: resume)
        let cwd = workingDirectory(params: params, existing: existing)
        let arguments = try commandArguments(
            instruction: instruction,
            nativeSessionId: nativeId,
            resume: resume,
            cwd: cwd
        )
        let jobId = nativeId.isEmpty ? UUID().uuidString.lowercased() : nativeId
        let outputURL = store.outputPath(adapterId: profile.id, sessionId: jobId)
        let process = try launch(executable: executable, arguments: arguments, cwd: cwd, outputURL: outputURL)
        let now = Date().timeIntervalSince1970
        let title = String(instruction.prefix(160))
        let job = ManagedJob(
            id: jobId,
            adapterId: profile.id,
            nativeSessionId: nativeId,
            title: title,
            cwd: cwd,
            pid: process.processIdentifier,
            outputPath: outputURL.path,
            createdAt: now,
            updatedAt: now,
            phase: "processing",
            lastInstruction: instruction
        )
        store.save(job)
        return [
            "command": "instruction",
            "message": resume
                ? "Resumed the real \(profile.displayName) session with the new instruction."
                : "Started a real \(profile.displayName) task.",
            "sessionId": nativeId,
            "pid": Int(process.processIdentifier)
        ]
    }

    private func commandArguments(
        instruction: String,
        nativeSessionId: String,
        resume: Bool,
        cwd: String
    ) throws -> [String] {
        switch profile.id {
        case "grok":
            var arguments = ["--cwd", cwd, "--output-format", "streaming-json", "--permission-mode", "default"]
            arguments += resume ? ["--resume", nativeSessionId] : ["--session-id", nativeSessionId]
            arguments += ["-p", instruction]
            return arguments
        case "qwen":
            var arguments = ["--chat-recording", "--approval-mode", "default", "--output-format", "stream-json"]
            arguments += resume ? ["--resume", nativeSessionId] : ["--session-id", nativeSessionId]
            arguments.append(instruction)
            return arguments
        case "cursor":
            var arguments = ["-p", "--force", "--output-format", "stream-json"]
            if resume { arguments += ["--resume", nativeSessionId] }
            arguments.append(instruction)
            return arguments
        case "openclaw":
            return ["agent", "--session-key", nativeSessionId, "--message", instruction, "--json"]
        case "gemini":
            var arguments = ["--output-format", "stream-json", "--approval-mode", "default"]
            if resume { arguments += ["--resume", nativeSessionId] }
            arguments += ["-p", instruction]
            return arguments
        case "opencode":
            var arguments = ["run", "--format", "json"]
            if resume { arguments += ["--session", nativeSessionId] }
            arguments.append(instruction)
            return arguments
        case "kiro":
            var arguments = ["chat", "--no-interactive"]
            if resume { arguments += ["--resume-id", nativeSessionId] }
            arguments.append(instruction)
            return arguments
        case "hermes":
            var arguments = ["chat", "--quiet"]
            if resume { arguments += ["--resume", nativeSessionId] }
            arguments += ["-q", instruction]
            return arguments
        case "aider":
            return ["--message", instruction]
        case "amp":
            return ["-x", instruction]
        case "goose":
            return ["run", "--text", instruction]
        case "copilot":
            var arguments: [String] = []
            if resume { arguments += ["--resume", nativeSessionId] }
            arguments += ["-p", instruction]
            return arguments
        case "droid":
            var arguments = ["exec"]
            if resume { arguments += ["--session-id", nativeSessionId] }
            arguments.append(instruction)
            return arguments
        default:
            throw UniversalAdapterError.controlUnavailable("control_not_implemented_for_\(profile.id)")
        }
    }

    private func launch(executable: URL, arguments: [String], cwd: String, outputURL: URL) throws -> Process {
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        guard let output = try? FileHandle(forWritingTo: outputURL) else {
            throw UniversalAdapterError.launchFailed("output_unavailable")
        }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        environment["TRACEFENCE_MANAGED_AGENT"] = "1"
        process.environment = environment
        do {
            try process.run()
            _ = setpgid(process.processIdentifier, process.processIdentifier)
            try? output.close()
            return process
        } catch {
            try? output.close()
            throw UniversalAdapterError.launchFailed(error.localizedDescription)
        }
    }

    private func existingSession(id: String) -> [String: Any]? {
        guard !id.isEmpty else { return nil }
        return discovery.sessions().first { string($0["id"]) == id }
    }

    private func nativeSessionId(requested: String, resume: Bool) -> String {
        if resume, !requested.isEmpty { return requested }
        switch profile.id {
        case "grok", "qwen": return UUID().uuidString.lowercased()
        case "openclaw": return requested.isEmpty ? "tracefence-\(UUID().uuidString.lowercased())" : requested
        default: return requested.isEmpty ? "tracefence-\(UUID().uuidString.lowercased())" : requested
        }
    }

    private func shouldResume(existing: [String: Any]?) -> Bool {
        guard let existing, existing["controlAvailable"] as? Bool != false else { return false }
        if string(existing["controlReason"]) == "managed_agent_process" {
            return ["grok", "qwen", "openclaw"].contains(profile.id)
        }
        return true
    }

    private func workingDirectory(params: [String: Any], existing: [String: Any]?) -> String {
        let candidates = [
            string(params["cwd"]),
            string(params["workingDirectory"]),
            string(existing?["cwd"]),
            NSHomeDirectory()
        ]
        for path in candidates where !path.isEmpty {
            var directory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &directory), directory.boolValue { return path }
        }
        return NSHomeDirectory()
    }

    private func requestedSessionId(_ params: [String: Any]) -> String {
        string(params["sessionId"] ?? params["threadId"])
    }

    private func signalInterrupt(pid: Int32) {
        if kill(-pid, SIGINT) != 0 { _ = kill(pid, SIGINT) }
    }

    private func waitForExit(pid: Int32, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, processIsAlive(pid) { usleep(100_000) }
    }

    private func unavailableMessage() -> String {
        if profile.applicationPresent {
            return "\(profile.id)_desktop_has_no_supported_local_control_api_install_cli"
        }
        if profile.dataPresent { return "\(profile.id)_history_found_but_controllable_runtime_missing" }
        return "\(profile.id)_not_installed"
    }

    private struct OpenCodeTarget {
        let port: Int
        let sessionId: String
    }

    private func nativeOpenCodeTarget(sessionId: String) -> OpenCodeTarget? {
        guard ["minimax", "opencode"].contains(profile.id), !sessionId.isEmpty,
              let row = discovery.sessions().first(where: { string($0["id"]) == sessionId }),
              let port = int(row["port"]), port > 0,
              row["phase"] as? String == "processing" else { return nil }
        let frameworkId = string(row["frameworkSessionId"])
        return OpenCodeTarget(port: port, sessionId: frameworkId.isEmpty ? sessionId : frameworkId)
    }

    private func openCodeRequest(
        target: OpenCodeTarget,
        method: String,
        path: String,
        body: [String: Any]
    ) throws -> Data {
        guard let url = URL(string: "http://127.0.0.1:\(target.port)\(path)") else {
            throw UniversalAdapterError.controlUnavailable("invalid_local_control_endpoint")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !body.isEmpty { request.httpBody = try JSONSerialization.data(withJSONObject: body) }

        let semaphore = DispatchSemaphore(value: 0)
        var resultData = Data()
        var resultResponse: URLResponse?
        var resultError: Error?
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 8
        let session = URLSession(configuration: configuration)
        session.dataTask(with: request) { data, response, error in
            resultData = data ?? Data()
            resultResponse = response
            resultError = error
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + 10) == .success else {
            session.invalidateAndCancel()
            throw UniversalAdapterError.controlUnavailable("local_control_timeout")
        }
        session.finishTasksAndInvalidate()
        if let resultError { throw UniversalAdapterError.controlUnavailable("local_control_failed:\(resultError.localizedDescription)") }
        guard let response = resultResponse as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
            let detail = String(data: resultData, encoding: .utf8) ?? ""
            throw UniversalAdapterError.controlUnavailable("local_control_rejected:\(detail.prefix(240))")
        }
        return resultData
    }

    private func urlPath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    private func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    private func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func bool(_ value: Any?) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        if let value = value as? String { return ["true", "1", "yes", "allow"].contains(value.lowercased()) }
        return false
    }
}
