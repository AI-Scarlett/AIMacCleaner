import Foundation
import Network
import Darwin

private let protocolVersion = 1
private let coreVersion = "1.6.4"
private let coreBuild = 1604
private let maxCachedCodexSessions = 120
private let maxScannedRolloutFiles = 100
private let maxCoreRequestBytes = 512 * 1024

private struct CoreRequest: Decodable {
    let id: String?
    let method: String
    let params: [String: AnyDecodable]
}

private struct CoreResponse: Encodable {
    let id: String?
    let ok: Bool
    let result: [String: AnyEncodable]?
    let error: String?
}

private struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { value = NSNull(); return }
        if let value = try? container.decode(Bool.self) { self.value = value; return }
        if let value = try? container.decode(Int.self) { self.value = value; return }
        if let value = try? container.decode(Double.self) { self.value = value; return }
        if let value = try? container.decode(String.self) { self.value = value; return }
        if let value = try? container.decode([AnyDecodable].self) {
            self.value = value.map(\.value)
            return
        }
        if let value = try? container.decode([String: AnyDecodable].self) {
            self.value = value.mapValues(\.value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }
}

private struct AnyEncodable: Encodable {
    let value: Any

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let value as Bool:
            try container.encode(value)
        case let value as Int:
            try container.encode(value)
        case let value as Int64:
            try container.encode(value)
        case let value as Double:
            try container.encode(value)
        case let value as String:
            try container.encode(value)
        case let value as [Any]:
            try container.encode(value.map(AnyEncodable.init))
        case let value as [String: Any]:
            try container.encode(value.mapValues(AnyEncodable.init))
        default:
            try container.encode(String(describing: value))
        }
    }
}

private struct AdapterManifest: Decodable {
    let id: String
    let version: String
    let displayName: String
    let executable: String?
    let arguments: [String]?
    let transport: String?
    let minimumCoreProtocol: Int?
    let capabilities: [String]
}

private struct LoadedAdapter {
    let manifest: AdapterManifest
    let manifestURL: URL
}

private struct AdapterInvocationResult {
    let ok: Bool
    let result: [String: Any]
    let error: String?
}

private final class AdapterOutputCapture: @unchecked Sendable {
    private let limit: Int
    private let lock = NSLock()
    private var value = Data()
    private var exceededLimit = false

    init(limit: Int) {
        self.limit = limit
    }

    func drain(_ handle: FileHandle) {
        while true {
            let chunk = handle.readData(ofLength: 64 * 1_024)
            if chunk.isEmpty { break }
            lock.lock()
            let available = max(0, limit + 1 - value.count)
            if available > 0 { value.append(chunk.prefix(available)) }
            if value.count > limit || chunk.count > available { exceededLimit = true }
            lock.unlock()
        }
    }

    func snapshot() -> (data: Data, exceededLimit: Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (value, exceededLimit)
    }
}

private final class ExternalAdapterRunner {
    private let coreDirectory: URL
    private let defaultTimeout: TimeInterval = 20
    private let maxResponseBytes = 4 * 1_024 * 1_024

    init(coreDirectory: URL) {
        self.coreDirectory = coreDirectory.standardizedFileURL
    }

    func isOperational(_ adapter: LoadedAdapter) -> Bool {
        executableURL(for: adapter) != nil
    }

    func invoke(_ adapter: LoadedAdapter, method: String, params: [String: Any]) -> AdapterInvocationResult {
        guard let executableURL = executableURL(for: adapter) else {
            return AdapterInvocationResult(ok: false, result: [:], error: "adapter_executable_unavailable")
        }

        let request: [String: Any] = [
            "protocolVersion": protocolVersion,
            "adapterId": adapter.manifest.id,
            "method": method,
            "params": params
        ]
        guard var requestData = try? JSONSerialization.data(withJSONObject: request) else {
            return AdapterInvocationResult(ok: false, result: [:], error: "adapter_request_encoding_failed")
        }
        requestData.append(0x0A)

        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executableURL
        process.arguments = adapter.manifest.arguments ?? []
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let finished = DispatchSemaphore(value: 0)
        let readers = DispatchGroup()
        let capturedOutput = AdapterOutputCapture(limit: maxResponseBytes)
        let capturedErrors = AdapterOutputCapture(limit: 256 * 1_024)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                capturedOutput.drain(output.fileHandleForReading)
                readers.leave()
            }
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                capturedErrors.drain(errors.fileHandleForReading)
                readers.leave()
            }
            try input.fileHandleForWriting.write(contentsOf: requestData)
            try input.fileHandleForWriting.close()
        } catch {
            return AdapterInvocationResult(ok: false, result: [:], error: "adapter_launch_failed:\(error.localizedDescription)")
        }

        let timeout = method == "control" ? 75 : defaultTimeout
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            if finished.wait(timeout: .now() + 1) == .timedOut {
                _ = Darwin.kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 1)
            }
            _ = readers.wait(timeout: .now() + 2)
            return AdapterInvocationResult(ok: false, result: [:], error: "adapter_timeout")
        }

        _ = readers.wait(timeout: .now() + 2)
        let stdout = capturedOutput.snapshot()
        let stderr = capturedErrors.snapshot()
        guard !stdout.exceededLimit,
              let object = try? JSONSerialization.jsonObject(with: stdout.data) as? [String: Any] else {
            let detail = String(data: stderr.data, encoding: .utf8) ?? ""
            if stdout.exceededLimit {
                return AdapterInvocationResult(ok: false, result: [:], error: "adapter_response_too_large")
            }
            return AdapterInvocationResult(ok: false, result: [:], error: detail.isEmpty ? "adapter_invalid_response" : detail)
        }
        let ok = object["ok"] as? Bool ?? true
        let result = object["result"] as? [String: Any] ?? object
        return AdapterInvocationResult(ok: ok, result: result, error: object["error"] as? String)
    }

    private func executableURL(for adapter: LoadedAdapter) -> URL? {
        guard let executable = adapter.manifest.executable?.trimmingCharacters(in: .whitespacesAndNewlines),
              !executable.isEmpty,
              (adapter.manifest.minimumCoreProtocol ?? protocolVersion) <= protocolVersion else { return nil }

        let candidate = executable.hasPrefix("/")
            ? URL(fileURLWithPath: executable)
            : adapter.manifestURL.deletingLastPathComponent().appendingPathComponent(executable)
        let standardized = candidate.standardizedFileURL
        let allowedRoot = coreDirectory.path.hasSuffix("/") ? coreDirectory.path : coreDirectory.path + "/"
        guard standardized.path.hasPrefix(allowedRoot),
              FileManager.default.isExecutableFile(atPath: standardized.path),
              let attributes = try? FileManager.default.attributesOfItem(atPath: standardized.path),
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o002 == 0 else { return nil }
        return standardized
    }
}

private struct RolloutFileCacheEntry {
    let fileSize: Int
    let modifiedAt: TimeInterval
    let session: [String: Any]
}

private enum CodexAutomationScheduleReader {
    private static let dayCodes: [String: Int] = [
        "SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7
    ]

    static func sessions(now: Date = Date()) -> [[String: Any]] {
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".codex/automations", isDirectory: true)
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return directories.compactMap { directory in
            let definitionURL = directory.appendingPathComponent("automation.toml")
            guard let text = try? String(contentsOf: definitionURL, encoding: .utf8),
                  stringValue("status", in: text)?.uppercased() == "ACTIVE",
                  let id = stringValue("id", in: text), !id.isEmpty,
                  let rule = stringValue("rrule", in: text), !rule.isEmpty else { return nil }

            let createdAtMilliseconds = numberValue("created_at", in: text) ?? now.timeIntervalSince1970 * 1_000
            let createdAt = Date(timeIntervalSince1970: createdAtMilliseconds > 4_000_000_000
                ? createdAtMilliseconds / 1_000
                : createdAtMilliseconds)
            guard let nextRun = nextOccurrence(rule: rule, after: now, startingAt: createdAt) else { return nil }

            let name = stringValue("name", in: text) ?? id
            let cwd = stringArrayValue("cwds", in: text)?.first ?? ""
            let project = cwd.isEmpty ? "" : URL(fileURLWithPath: cwd).lastPathComponent
            return [
                "id": "automation|\(id)",
                "preview": name,
                "cwd": cwd,
                "project": project,
                "sourcePath": definitionURL.path,
                "createdAt": createdAt.timeIntervalSince1970 * 1_000,
                "updatedAt": nextRun.timeIntervalSince1970 * 1_000,
                "nextRunAt": nextRun.timeIntervalSince1970 * 1_000,
                "phase": "scheduled",
                "lastResponse": "",
                "lastUserMessage": "",
                "model": stringValue("model", in: text) ?? "Codex",
                "source": "codex-automation",
                "controlAvailable": false,
                "controlMode": "display_only",
                "controlReason": "scheduled_task",
                "contextAvailable": false,
                "scheduledTask": true,
                "scheduleId": id,
                "scheduleRule": rule,
                "requests": []
            ]
        }
        .sorted { ($0["nextRunAt"] as? Double ?? 0) < ($1["nextRunAt"] as? Double ?? 0) }
    }

    private static func stringValue(_ key: String, in text: String) -> String? {
        let pattern = "(?m)^\\s*\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*(\"(?:\\\\.|[^\"])*\")\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let data = String(text[range]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(String.self, from: data)
    }

    private static func stringArrayValue(_ key: String, in text: String) -> [String]? {
        let pattern = "(?m)^\\s*\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*(\\[[^\\n]*\\])\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text),
              let data = String(text[range]).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String].self, from: data)
    }

    private static func numberValue(_ key: String, in text: String) -> Double? {
        let pattern = "(?m)^\\s*\(NSRegularExpression.escapedPattern(for: key))\\s*=\\s*([0-9]+(?:\\.[0-9]+)?)\\s*$"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return Double(text[range])
    }

    private static func nextOccurrence(rule: String, after now: Date, startingAt start: Date) -> Date? {
        let fields = Dictionary(uniqueKeysWithValues: rule.split(separator: ";").compactMap { component -> (String, String)? in
            let pair = component.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            return (pair[0].uppercased(), pair[1].uppercased())
        })
        guard let frequency = fields["FREQ"] else { return nil }
        let interval = max(1, Int(fields["INTERVAL"] ?? "1") ?? 1)
        let calendar = Calendar.autoupdatingCurrent
        let minutes = integerList(fields["BYMINUTE"], fallback: [calendar.component(.minute, from: start)])
        let seconds = integerList(fields["BYSECOND"], fallback: [0])
        let until = fields["UNTIL"].flatMap(parseUntil)

        func accepted(_ candidate: Date) -> Bool {
            candidate > now && candidate >= start && (until == nil || candidate <= until!)
        }

        if frequency == "MINUTELY" {
            let origin = calendar.dateInterval(of: .minute, for: start)?.start ?? start
            let base = calendar.dateInterval(of: .minute, for: now)?.start ?? now
            for offset in 0..<(60 * 24 * 31) {
                guard let minute = calendar.date(byAdding: .minute, value: offset, to: base) else { continue }
                let distance = calendar.dateComponents([.minute], from: origin, to: minute).minute ?? 0
                guard distance >= 0, distance % interval == 0 else { continue }
                for second in seconds {
                    guard let candidate = calendar.date(bySetting: .second, value: second, of: minute), accepted(candidate) else { continue }
                    return candidate
                }
            }
            return nil
        }

        if frequency == "HOURLY" {
            let origin = calendar.dateInterval(of: .hour, for: start)?.start ?? start
            let base = calendar.dateInterval(of: .hour, for: now)?.start ?? now
            for offset in 0..<(24 * 366) {
                guard let hour = calendar.date(byAdding: .hour, value: offset, to: base) else { continue }
                let distance = calendar.dateComponents([.hour], from: origin, to: hour).hour ?? 0
                guard distance >= 0, distance % interval == 0 else { continue }
                for minute in minutes {
                    for second in seconds {
                        var components = calendar.dateComponents([.year, .month, .day, .hour], from: hour)
                        components.minute = minute
                        components.second = second
                        guard let candidate = calendar.date(from: components), accepted(candidate) else { continue }
                        return candidate
                    }
                }
            }
            return nil
        }

        let hours = integerList(fields["BYHOUR"], fallback: [calendar.component(.hour, from: start)])
        let weekdays = Set((fields["BYDAY"] ?? "").split(separator: ",").compactMap { token in
            dayCodes[String(token.suffix(2))]
        })
        let monthDays = Set(integerList(fields["BYMONTHDAY"], fallback: [calendar.component(.day, from: start)]))
        let originDay = calendar.startOfDay(for: start)
        let baseDay = calendar.startOfDay(for: now)

        for dayOffset in 0..<(366 * 5) {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: baseDay) else { continue }
            let dayDistance = calendar.dateComponents([.day], from: originDay, to: day).day ?? 0
            guard dayDistance >= 0 else { continue }

            switch frequency {
            case "DAILY":
                guard dayDistance % interval == 0,
                      weekdays.isEmpty || weekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            case "WEEKLY":
                let startWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start ?? originDay
                let candidateWeek = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
                let weekDistance = calendar.dateComponents([.weekOfYear], from: startWeek, to: candidateWeek).weekOfYear ?? 0
                let allowedWeekdays = weekdays.isEmpty ? [calendar.component(.weekday, from: start)] : weekdays
                guard weekDistance >= 0, weekDistance % interval == 0,
                      allowedWeekdays.contains(calendar.component(.weekday, from: day)) else { continue }
            case "MONTHLY":
                let monthDistance = calendar.dateComponents([.month], from: start, to: day).month ?? 0
                guard monthDistance >= 0, monthDistance % interval == 0,
                      monthDays.contains(calendar.component(.day, from: day)) else { continue }
            default:
                return nil
            }

            for hour in hours.sorted() {
                for minute in minutes.sorted() {
                    for second in seconds.sorted() {
                        var components = calendar.dateComponents([.year, .month, .day], from: day)
                        components.hour = hour
                        components.minute = minute
                        components.second = second
                        guard let candidate = calendar.date(from: components), accepted(candidate) else { continue }
                        return candidate
                    }
                }
            }
        }
        return nil
    }

    private static func integerList(_ value: String?, fallback: [Int]) -> [Int] {
        guard let value else { return fallback }
        let values = value.split(separator: ",").compactMap { Int($0) }
        return values.isEmpty ? fallback : values
    }

    private static func parseUntil(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = value.hasSuffix("Z") ? "yyyyMMdd'T'HHmmss'Z'" : "yyyyMMdd'T'HHmmss"
        return formatter.date(from: value)
    }
}

private final class CodexDesktopAdapter {
    private let lock = NSLock()
    private var sessions: [String: [String: Any]] = [:]
    private var observerStarted = false
    private var rolloutCache: [[String: Any]] = []
    private var rolloutScanInProgress = false
    private var lastRolloutScanAt = Date.distantPast
    private var automationCache: [[String: Any]] = []
    private var lastAutomationScanAt = Date.distantPast
    private let rolloutQueue = DispatchQueue(label: "com.tracefence.agent-core.codex-rollouts", qos: .utility)
    private var rolloutFileCache: [String: RolloutFileCacheEntry] = [:]
    private let appServer = CodexAppServerBridge()

    func start() {
        lock.lock()
        guard !observerStarted else {
            lock.unlock()
            return
        }
        observerStarted = true
        lock.unlock()
        appServer.warmUp()
        scheduleRolloutScan(force: true)
        Thread.detachNewThread { [weak self] in
            Thread.current.name = "TraceFence Codex Desktop Observer"
            self?.observeLoop()
        }
    }

    var isOperational: Bool {
        appServer.isAvailable
    }

    func listSessions() -> [[String: Any]] {
        scheduleRolloutScan()
        lock.lock()
        mergeRolloutSessionsLocked(rolloutCache)
        if Date().timeIntervalSince(lastAutomationScanAt) >= 30 {
            automationCache = CodexAutomationScheduleReader.sessions()
            lastAutomationScanAt = Date()
        }
        for id in sessions.keys {
            if let activeTurnId = appServer.activeTurnId(for: id) {
                let rolloutTurnId = sessions[id]?["latestTurnId"] as? String
                let rolloutPhase = sessions[id]?["phase"] as? String ?? "idle"
                if rolloutTurnId == activeTurnId,
                   ["idle", "done", "interrupted"].contains(rolloutPhase) {
                    appServer.clearActiveTurn(threadId: id, expectedTurnId: activeTurnId)
                    sessions[id]?.removeValue(forKey: "activeTurnId")
                } else {
                    sessions[id]?["phase"] = "processing"
                    sessions[id]?["activeTurnId"] = activeTurnId
                }
            }
            let nativeRequests = appServer.pendingRequests(for: id)
            let existing = appServer.hasLiveApprovalStream
                ? []
                : (sessions[id]?["requests"] as? [[String: Any]] ?? []).filter {
                    $0["source"] as? String != "app-server"
                }
            sessions[id]?["requests"] = existing + nativeRequests
            if !nativeRequests.isEmpty {
                sessions[id]?["phase"] = nativeRequests.contains {
                    $0["method"] as? String == "item/tool/requestUserInput"
                } ? "waitingInput" : "waitingApproval"
            }
        }
        pruneSessionsLocked()
        defer { lock.unlock() }
        return (Array(sessions.values) + automationCache).sorted {
            let left = ($0["updatedAt"] as? Double) ?? 0
            let right = ($1["updatedAt"] as? Double) ?? 0
            return left > right
        }
    }

    private func scheduleRolloutScan(force: Bool = false) {
        lock.lock()
        let isDue = force || Date().timeIntervalSince(lastRolloutScanAt) >= 10
        guard isDue, !rolloutScanInProgress else {
            lock.unlock()
            return
        }
        rolloutScanInProgress = true
        lock.unlock()

        rolloutQueue.async { [weak self] in
            guard let self else { return }
            let rows = autoreleasepool { self.scanRolloutSessions() }
            self.lock.lock()
            self.rolloutCache = rows
            self.lastRolloutScanAt = Date()
            self.rolloutScanInProgress = false
            self.mergeRolloutSessionsLocked(rows)
            self.pruneSessionsLocked()
            self.lock.unlock()
        }
    }

    private func mergeRolloutSessionsLocked(_ rows: [[String: Any]]) {
        for row in rows {
            guard let id = row["id"] as? String else { continue }
            var merged = row
            if let existing = sessions[id] {
                if let activeTurnId = existing["activeTurnId"] { merged["activeTurnId"] = activeTurnId }
                if let requests = existing["requests"] as? [[String: Any]], !requests.isEmpty {
                    merged["requests"] = requests
                }
            }
            sessions[id] = merged
        }
    }

    func control(_ params: [String: Any]) -> (ok: Bool, result: [String: Any], error: String?) {
        guard let threadId = (params["threadId"] as? String) ?? (params["conversationId"] as? String), !threadId.isEmpty else {
            return (false, [:], "missing_thread_id")
        }

        let action = params["action"] as? String ?? "instruction"
        switch action {
        case "interrupt":
            let native = appServer.interrupt(threadId: threadId)
            if native.ok { return native }
            return sendControl(
                method: "thread-follower-interrupt-turn",
                version: 2,
                params: ["conversationId": threadId],
                successMessage: "中断请求已发送给 Mac 上当前打开的 Codex 任务.",
                fallbackError: native.error
            )
        case "approval":
            let native = appServer.resolveApproval(params)
            if native.ok || native.error != "approval_not_owned_by_app_server" { return native }
            return approval(params, threadId: threadId)
        case "instruction", "start", "steer":
            let text = (params["instruction"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return (false, [:], "missing_instruction") }
            let native = appServer.sendInstruction(threadId: threadId, instruction: text)
            if native.ok { return native }
            let isActive = isProcessing(threadId: threadId)
            let shouldSteer = action == "steer" || (action == "instruction" && isActive)
            return sendControl(
                method: shouldSteer ? "thread-follower-steer-turn" : "thread-follower-start-turn",
                version: 1,
                params: shouldSteer
                    ? [
                        "conversationId": threadId,
                        "input": [["type": "text", "text": text, "text_elements": []]]
                    ]
                    : [
                        "conversationId": threadId,
                        "turnStartParams": ["input": [["type": "text", "text": text, "text_elements": []]]]
                    ],
                successMessage: shouldSteer
                    ? "新指令已插入 Mac 上当前打开的 Codex 任务。"
                    : "指令已交给 Mac 上当前打开的 Codex 会话。",
                fallbackError: native.error
            )
        default:
            return (false, [:], "unsupported_control_action:\(action)")
        }
    }

    private func approval(_ params: [String: Any], threadId: String) -> (ok: Bool, result: [String: Any], error: String?) {
        guard let requestId = params["requestId"] else { return (false, [:], "missing_request_id") }
        let method = params["approvalMethod"] as? String ?? params["method"] as? String ?? ""
        let allow = params["allow"] as? Bool ?? false
        let requestMethod: String
        let requestParams: [String: Any]
        switch method {
        case "item/commandExecution/requestApproval":
            requestMethod = "thread-follower-command-approval-decision"
            requestParams = ["conversationId": threadId, "requestId": requestId, "decision": allow ? "accept" : "decline"]
        case "item/fileChange/requestApproval":
            requestMethod = "thread-follower-file-approval-decision"
            requestParams = ["conversationId": threadId, "requestId": requestId, "decision": allow ? "accept" : "decline"]
        case "item/permissions/requestApproval":
            requestMethod = "thread-follower-permissions-request-approval-response"
            requestParams = [
                "conversationId": threadId,
                "requestId": requestId,
                "response": [
                    "permissions": allow ? (params["requestedPermissions"] as? [String: Any] ?? [:]) : [:],
                    "scope": "turn"
                ]
            ]
        case "item/tool/requestUserInput":
            requestMethod = "thread-follower-submit-user-input"
            let text = params["answer"] as? String ?? ""
            let questionIds = params["questionIds"] as? [String] ?? []
            let defaults = params["questionDefaults"] as? [String: String] ?? [:]
            var answers: [String: Any] = [:]
            for questionId in questionIds {
                let value = text.isEmpty ? (defaults[questionId] ?? "") : text
                answers[questionId] = ["answers": [value]]
            }
            requestParams = [
                "conversationId": threadId,
                "requestId": requestId,
                "response": ["answers": answers]
            ]
        default:
            return (false, [:], "unsupported_approval_method:\(method)")
        }
        return sendControl(method: requestMethod, version: 1, params: requestParams, successMessage: allow ? "已确认 Mac 上的 Codex 请求，任务会继续执行。" : "已拒绝 Mac 上的 Codex 请求。")
    }

    private func isProcessing(threadId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return sessions[threadId]?["phase"] as? String == "processing"
    }

    private func sendControl(
        method: String,
        version: Int,
        params: [String: Any],
        successMessage: String,
        fallbackError: String? = nil
    ) -> (ok: Bool, result: [String: Any], error: String?) {
        guard let socket = Self.socketPath() else {
            return (false, [:], "no-client-found: Codex Desktop IPC socket was not discovered")
        }
        guard let fd = Self.connect(socketPath: socket, timeout: 5) else {
            let code = errno
            return (false, [:], "no-client-found: Codex Desktop IPC connection failed (errno \(code): \(String(cString: strerror(code))))")
        }
        defer { close(fd) }

        let initializeId = UUID().uuidString
        let initialize: [String: Any] = [
            "type": "request",
            "requestId": initializeId,
            "sourceClientId": "initializing-client",
            "version": 0,
            "method": "initialize",
            "params": ["clientType": "tracefence"],
            "timeoutMs": 3_000
        ]
        guard Self.writeFrame(initialize, fd: fd) else {
            return (false, [:], "Codex Desktop 初始化请求写入失败")
        }
        guard let initialized = Self.readResponse(requestId: initializeId, fd: fd) else {
            return (false, [:], "Codex Desktop 初始化没有返回响应")
        }
        guard initialized["resultType"] as? String == "success",
              let clientId = (initialized["result"] as? [String: Any])?["clientId"] as? String else {
            return (false, [:], Self.readableError(initialized) ?? "Codex Desktop 初始化失败")
        }

        let request: [String: Any] = [
            "type": "request",
            "requestId": UUID().uuidString,
            "sourceClientId": clientId,
            "version": version,
            "method": method,
            "params": params,
            "timeoutMs": 5_000
        ]
        guard Self.writeFrame(request, fd: fd) else { return (false, [:], "Codex Desktop 请求写入失败") }
        guard let response = Self.readResponse(requestId: request["requestId"] as! String, fd: fd) else {
            return (false, [:], fallbackError ?? "Codex Desktop did not acknowledge the control request.")
        }
        guard response["resultType"] as? String == "success" else {
            return (false, [:], Self.readableError(response) ?? String(describing: response))
        }
        return (true, ["command": method, "message": successMessage, "controlMode": "tracefence_agent_core"], nil)
    }

    private func observeLoop() {
        while true {
            let connected = autoreleasepool { observeConnection() }
            Thread.sleep(forTimeInterval: connected ? 1 : 3)
        }
    }

    private func observeConnection() -> Bool {
        guard let socket = Self.socketPath(), let fd = Self.connect(socketPath: socket, timeout: nil) else {
            return false
        }
        defer { close(fd) }
        let initialize: [String: Any] = [
            "type": "request",
            "requestId": UUID().uuidString,
            "sourceClientId": "initializing-client",
            "version": 0,
            "method": "initialize",
            "params": ["clientType": "tracefence-observer"],
            "timeoutMs": 3_000
        ]
        guard Self.writeFrame(initialize, fd: fd), Self.readFrame(fd: fd) != nil else {
            return false
        }
        while autoreleasepool(invoking: {
            guard let frame = Self.readFrame(fd: fd) else { return false }
            guard frame["type"] as? String == "broadcast",
                  frame["method"] as? String == "thread-stream-state-changed",
                  let params = frame["params"] as? [String: Any],
                  let change = params["change"] as? [String: Any],
                  change["type"] as? String == "snapshot",
                  let state = change["conversationState"] as? [String: Any],
                  let snapshot = Self.sessionSnapshot(from: state),
                  let id = snapshot["id"] as? String else { return true }
            lock.lock()
            sessions[id] = snapshot
            pruneSessionsLocked()
            lock.unlock()
            return true
        }) {}
        return true
    }

    private func pruneSessionsLocked() {
        guard sessions.count > maxCachedCodexSessions else { return }
        let retained = sessions.values
            .sorted {
                let left = ($0["updatedAt"] as? Double) ?? 0
                let right = ($1["updatedAt"] as? Double) ?? 0
                return left > right
            }
            .prefix(maxCachedCodexSessions)
        sessions = Dictionary(uniqueKeysWithValues: retained.compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return (id, row)
        })
    }

    private static func sessionSnapshot(from state: [String: Any]) -> [String: Any]? {
        guard let id = state["id"] as? String else { return nil }
        let requests = state["requests"] as? [[String: Any]] ?? []
        let methods = requests.compactMap { $0["method"] as? String }
        let runtimeType = (state["threadRuntimeStatus"] as? [String: Any])?["type"] as? String
        let phase: String
        if methods.contains("item/tool/requestUserInput") {
            phase = "waitingInput"
        } else if methods.contains(where: { $0.hasPrefix("item/") }) {
            phase = "waitingApproval"
        } else if runtimeType == "active" {
            phase = "processing"
        } else {
            phase = "idle"
        }
        let date = state["updatedAt"] as? Double ?? state["recencyAt"] as? Double ?? Date().timeIntervalSince1970
        var snapshot: [String: Any] = [
            "id": id,
            "preview": (state["title"] as? String)?.isEmpty == false ? (state["title"] as! String) : "Codex 会话",
            "cwd": state["cwd"] as? String ?? "",
            "sourcePath": state["rolloutPath"] as? String ?? "",
            "createdAt": state["createdAt"] ?? date,
            "updatedAt": date,
            "phase": phase,
            "lastResponse": "",
            "lastUserMessage": "",
            "model": state["latestModel"] as? String ?? "Codex",
            "source": "agent-core",
            "requests": requests
        ]
        if let activeTurnId = (state["threadRuntimeStatus"] as? [String: Any])?["activeTurnId"] as? String {
            snapshot["activeTurnId"] = activeTurnId
        }
        return snapshot
    }

    private func scanRolloutSessions() -> [[String: Any]] {
        let root = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let isoFormatter = ISO8601DateFormatter()
        var candidates: [(url: URL, modifiedAt: Date, fileSize: Int)] = []
        for case let url as URL in enumerator where url.pathExtension == "jsonl" {
            guard let attributes = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let modifiedAt = attributes.contentModificationDate,
                  let fileSize = attributes.fileSize else { continue }
            candidates.append((url, modifiedAt, fileSize))
        }

        var result: [[String: Any]] = []
        var selectedPaths = Set<String>()
        for candidate in candidates.sorted(by: { $0.modifiedAt > $1.modifiedAt }).prefix(maxScannedRolloutFiles) {
            let url = candidate.url
            let modifiedAt = candidate.modifiedAt
            selectedPaths.insert(url.path)
            if let cached = rolloutFileCache[url.path],
               cached.fileSize == candidate.fileSize,
               cached.modifiedAt == modifiedAt.timeIntervalSince1970 {
                result.append(cached.session)
                continue
            }
            guard let segments = Self.readRolloutSegments(from: url) else { continue }
            var sessionId: String?
            var cwd = ""
            var createdAt = modifiedAt
            var model = "Codex"
            var lastUserMessage = ""
            var lastResponse = ""
            var phase = "idle"
            var latestTurnId: String?

            for segment in segments {
                for line in segment.split(whereSeparator: \.isNewline) {
                    guard let data = line.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = object["type"] as? String,
                          let payload = object["payload"] as? [String: Any] else { continue }
                    if type == "session_meta" {
                        sessionId = (payload["id"] as? String) ?? (payload["session_id"] as? String)
                        cwd = payload["cwd"] as? String ?? cwd
                        model = payload["model"] as? String ?? model
                        if let timestamp = object["timestamp"] as? String,
                           let date = isoFormatter.date(from: timestamp) {
                            createdAt = date
                        }
                    } else if type == "turn_context" {
                        model = payload["model"] as? String ?? model
                        if let turnId = payload["turn_id"] as? String ?? payload["turnId"] as? String {
                            latestTurnId = turnId
                        }
                    } else if type == "event_msg", let eventType = payload["type"] as? String {
                        let turnId = payload["turn_id"] as? String ?? payload["turnId"] as? String
                        switch eventType {
                        case "task_started":
                            latestTurnId = turnId ?? latestTurnId
                            phase = "processing"
                        case "task_complete":
                            latestTurnId = turnId ?? latestTurnId
                            phase = "idle"
                        case "turn_aborted":
                            latestTurnId = turnId ?? latestTurnId
                            phase = "interrupted"
                        default:
                            break
                        }
                    } else if type == "response_item",
                              let role = payload["role"] as? String,
                              let content = payload["content"] as? [[String: Any]] {
                        let text = content.compactMap { item in
                            item["text"] as? String ?? item["input_text"] as? String ?? item["output_text"] as? String
                        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                        if role == "user", !text.isEmpty {
                            lastUserMessage = String(text.suffix(1_200))
                        } else if role == "assistant", !text.isEmpty {
                            lastResponse = String(text.suffix(1_200))
                        }
                    }
                }
            }

            if sessionId == nil {
                let name = url.deletingPathExtension().lastPathComponent
                let candidate = String(name.suffix(36))
                if UUID(uuidString: candidate) != nil { sessionId = candidate }
            }
            guard let sessionId else { continue }
            let preview = lastUserMessage.isEmpty ? "Codex 会话" : String(lastUserMessage.prefix(120))
            var session: [String: Any] = [
                "id": sessionId,
                "preview": preview,
                "cwd": cwd,
                "sourcePath": url.path,
                "createdAt": createdAt.timeIntervalSince1970 * 1_000,
                "updatedAt": modifiedAt.timeIntervalSince1970 * 1_000,
                "phase": phase,
                "lastResponse": lastResponse,
                "lastUserMessage": lastUserMessage,
                "model": model,
                "source": "agent-core",
                "requests": []
            ]
            if let latestTurnId { session["latestTurnId"] = latestTurnId }
            rolloutFileCache[url.path] = RolloutFileCacheEntry(
                fileSize: candidate.fileSize,
                modifiedAt: modifiedAt.timeIntervalSince1970,
                session: session
            )
            result.append(session)
        }
        rolloutFileCache = rolloutFileCache.filter { selectedPaths.contains($0.key) }
        return result
    }

    private static func readRolloutSegments(from url: URL) -> [String]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        let head = handle.readData(ofLength: 64 * 1_024)
        _ = try? handle.seekToEnd()
        let size = handle.offsetInFile
        let tailOffset = size > 128 * 1_024 ? size - 128 * 1_024 : 0
        try? handle.seek(toOffset: tailOffset)
        let tail = handle.readDataToEndOfFile()
        try? handle.close()
        let headText = String(data: head, encoding: .utf8) ?? ""
        let tailText = String(data: tail, encoding: .utf8) ?? ""
        return [headText, tailText]
    }

    private static func socketPath() -> String? {
        let uid = getuid()
        let socketName = "ipc-\(uid).sock"
        var directories: [URL] = []

        if let userTemporaryDirectory = darwinUserTemporaryDirectory() {
            directories.append(userTemporaryDirectory.appendingPathComponent("codex-ipc", isDirectory: true))
        }
        directories.append(
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("codex-ipc", isDirectory: true)
        )
        directories.append(URL(fileURLWithPath: "/private/tmp/codex-ipc", isDirectory: true))
        directories.append(URL(fileURLWithPath: "/tmp/codex-ipc", isDirectory: true))
        directories.append(contentsOf: fallbackUserTemporaryDirectories().map {
            $0.appendingPathComponent("codex-ipc", isDirectory: true)
        })

        var visited = Set<String>()
        for directory in directories where visited.insert(directory.standardizedFileURL.path).inserted {
            let candidate = directory.appendingPathComponent(socketName, isDirectory: false)
            if isSocketOwnedByCurrentUser(candidate, uid: uid) {
                return candidate.path
            }
        }
        return nil
    }

    private static func darwinUserTemporaryDirectory() -> URL? {
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        guard confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, length) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer), isDirectory: true)
    }

    private static func fallbackUserTemporaryDirectories() -> [URL] {
        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: "/private/var/folders", isDirectory: true)
        guard let firstLevel = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var results: [URL] = []
        for first in firstLevel {
            guard let secondLevel = try? fileManager.contentsOfDirectory(
                at: first,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            results.append(contentsOf: secondLevel.map {
                $0.appendingPathComponent("T", isDirectory: true)
            })
        }
        return results
    }

    private static func isSocketOwnedByCurrentUser(_ url: URL, uid: uid_t) -> Bool {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            attributes[.type] as? FileAttributeType == .typeSocket,
            let owner = attributes[.ownerAccountID] as? NSNumber
        else { return false }
        return owner.uint32Value == uid
    }

    private static func connect(socketPath: String, timeout: TimeInterval?) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { close(fd); return nil }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { destination in
                _ = pathBytes.withUnsafeBufferPointer { source in memcpy(destination, source.baseAddress, pathBytes.count) }
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { close(fd); return nil }
        if let timeout {
            var value = timeval(tv_sec: Int(timeout), tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, socklen_t(MemoryLayout<timeval>.size))
        }
        return fd
    }

    private static func writeFrame(_ object: [String: Any], fd: Int32) -> Bool {
        guard let body = try? JSONSerialization.data(withJSONObject: object) else { return false }
        var length = UInt32(body.count).littleEndian
        let header = Data(bytes: &length, count: 4)
        return writeAll(header, fd: fd) && writeAll(body, fd: fd)
    }

    private static func readFrame(fd: Int32) -> [String: Any]? {
        guard let header = readExact(count: 4, fd: fd) else { return nil }
        let length = UInt32(header[0]) | (UInt32(header[1]) << 8) | (UInt32(header[2]) << 16) | (UInt32(header[3]) << 24)
        guard length > 0, length < 16 * 1024 * 1024, let body = readExact(count: Int(length), fd: fd) else { return nil }
        return try? JSONSerialization.jsonObject(with: body) as? [String: Any]
    }

    private static func readResponse(requestId: String, fd: Int32) -> [String: Any]? {
        while let frame = readFrame(fd: fd) {
            if frame["type"] as? String == "response",
               frame["requestId"] as? String == requestId {
                return frame
            }
        }
        return nil
    }

    private static func writeAll(_ data: Data, fd: Int32) -> Bool {
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

    private static func readExact(count: Int, fd: Int32) -> Data? {
        var data = Data(count: count)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard var pointer = raw.baseAddress else { return false }
            var remaining = count
            while remaining > 0 {
                let received = Darwin.read(fd, pointer, remaining)
                guard received > 0 else { return false }
                pointer = pointer.advanced(by: received)
                remaining -= received
            }
            return true
        }
        return ok ? data : nil
    }

    private static func readableError(_ response: [String: Any]?) -> String? {
        if let error = response?["error"] as? String { return error }
        if let error = response?["error"] as? [String: Any] { return error["message"] as? String ?? String(describing: error) }
        return nil
    }
}

private final class CoreDaemon {
    private let socketPath: String
    private let httpConfigPath: String?
    private let coreDirectory: URL
    private let queue = DispatchQueue(label: "com.tracefence.agent-core.listener")
    private var listener: NWListener?
    private let codexAdapter = CodexDesktopAdapter()
    private let externalAdapterRunner: ExternalAdapterRunner
    private let updateCoordinator: CoreUpdateCoordinator
    private var httpGateway: AgentCoreHTTPGateway?
    private let adapterSessionLock = NSLock()
    private var adapterSessionSnapshot: [[String: Any]] = []
    private let adapterRefreshQueue = DispatchQueue(label: "com.tracefence.agent-core.adapter-refresh", qos: .utility)
    private var adapterRefreshTimer: DispatchSourceTimer?
    private let adapterMetadataLock = NSLock()
    private var adapterMetadataSnapshot: [[String: Any]] = []
    private var adapterMetadataUpdatedAt = Date.distantPast
    private var externalSessionSnapshots: [String: [[String: Any]]] = [:]
    private var externalSessionUpdatedAt: [String: Date] = [:]

    init(socketPath: String, httpConfigPath: String?) {
        self.socketPath = socketPath
        self.httpConfigPath = httpConfigPath
        let directory = URL(fileURLWithPath: socketPath).deletingLastPathComponent()
        coreDirectory = directory
        externalAdapterRunner = ExternalAdapterRunner(coreDirectory: directory)
        updateCoordinator = CoreUpdateCoordinator(
            coreDirectory: directory,
            socketPath: socketPath,
            currentVersion: coreVersion,
            currentBuild: coreBuild
        )
    }

    func start() throws {
        // Adapter observation starts after the local RPC listener is online.
        let parent = URL(fileURLWithPath: socketPath).deletingLastPathComponent().path
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        unlink(socketPath)

        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                fputs("TraceFenceAgentCore listener failed: \(error)\n", stderr)
                exit(2)
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        self.listener = listener
        listener.start(queue: queue)
        codexAdapter.start()

        if let httpConfigPath {
            let gateway = AgentCoreHTTPGateway(
                configPath: httpConfigPath,
                coreVersion: coreVersion,
                protocolVersion: protocolVersion,
                sessions: { [weak self] in self?.allAdapterSessions() ?? [] },
                adapters: { [weak self] in self?.adapterMetadata() ?? [] },
                control: { [weak self] params in
                    self?.performControl(params) ?? (false, [:], "agent_core_unavailable")
                },
                context: { [weak self] params in
                    self?.performContext(params) ?? (false, [:], "agent_core_unavailable")
                }
            )
            try gateway.start()
            httpGateway = gateway
        }

        adapterRefreshQueue.async { [weak self] in self?.refreshAdapterSessions() }
        let timer = DispatchSource.makeTimerSource(queue: adapterRefreshQueue)
        timer.schedule(deadline: .now() + 5, repeating: 5, leeway: .milliseconds(750))
        timer.setEventHandler { [weak self] in self?.refreshAdapterSessions() }
        timer.resume()
        adapterRefreshTimer = timer
        updateCoordinator.start()
    }

    private func accept(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if error != nil {
                connection.cancel()
                return
            }
            var next = buffer
            if let data { next.append(data) }
            guard next.count <= maxCoreRequestBytes else {
                self.send(CoreResponse(id: nil, ok: false, result: nil, error: "request_too_large"), on: connection)
                return
            }
            while let newline = next.firstIndex(of: 0x0A) {
                let line = Data(next[next.startIndex..<newline])
                next = newline + 1 < next.endIndex ? Data(next[(newline + 1)..<next.endIndex]) : Data()
                self.handle(line: line, on: connection)
            }
            if isComplete {
                connection.cancel()
            } else {
                self.receive(on: connection, buffer: next)
            }
        }
    }

    private func handle(line: Data, on connection: NWConnection) {
        guard let request = try? JSONDecoder().decode(CoreRequest.self, from: line) else {
            send(CoreResponse(id: nil, ok: false, result: nil, error: "invalid_request"), on: connection)
            return
        }
        let response = route(request)
        send(response, on: connection)
    }

    private func route(_ request: CoreRequest) -> CoreResponse {
        switch request.method {
        case "initialize":
            return success(request.id, [
                "protocolVersion": protocolVersion,
                "coreVersion": coreVersion,
                "service": "TraceFence Agent Core",
                "socketPath": socketPath,
                "capabilities": coreCapabilities
            ])
        case "health":
            return success(request.id, [
                "protocolVersion": protocolVersion,
                "coreVersion": coreVersion,
                "coreBuild": coreBuild,
                "ready": true,
                "adapters": adapterMetadata(),
                "update": updateCoordinator.status(),
                "capabilities": coreCapabilities
            ])
        case "capabilities":
            return success(request.id, [
                "protocolVersion": protocolVersion,
                "coreVersion": coreVersion,
                "capabilities": coreCapabilities
            ])
        case "listAdapters":
            return success(request.id, [
                "adapters": adapterMetadata()
            ])
        case "listSessions":
            return success(request.id, ["sessions": allAdapterSessions()])
        case "listSessionSummaries":
            return success(request.id, ["sessions": allAdapterSessionSummaries()])
        case "updateStatus":
            return success(request.id, ["update": updateCoordinator.status()])
        case "checkForUpdates":
            let params = request.params.mapValues(\.value)
            return success(request.id, updateCoordinator.requestCheck(force: params["force"] as? Bool ?? true))
        case "control":
            let params = request.params.mapValues(\.value)
            let result = performControl(params)
            return result.ok
                ? success(request.id, result.result)
                : CoreResponse(id: request.id, ok: false, result: nil, error: result.error ?? "control_failed")
        case "sessionContext":
            let params = request.params.mapValues(\.value)
            let result = performContext(params)
            return result.ok
                ? success(request.id, result.result)
                : CoreResponse(id: request.id, ok: false, result: nil, error: result.error ?? "context_failed")
        default:
            return CoreResponse(id: request.id, ok: false, result: nil, error: "unsupported_method:\(request.method)")
        }
    }

    private var coreCapabilities: [String] {
        [
            "adapter_manifests", "adapter_process_protocol", "version_negotiation", "local_rpc",
            "agent_projects", "agent_sessions", "agent_session_context", "agent_control", "agent_approvals",
            "independent_core_update", "atomic_core_rollback"
        ]
    }

    private func loadManifests() -> [LoadedAdapter] {
        let directory = coreDirectory
            .appendingPathComponent("adapters", isDirectory: true)
            .resolvingSymlinksInPath()
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                guard let manifest = try? JSONDecoder().decode(AdapterManifest.self, from: data) else { return nil }
                return LoadedAdapter(manifest: manifest, manifestURL: url)
            }
            .filter { ($0.manifest.minimumCoreProtocol ?? protocolVersion) <= protocolVersion }
            .sorted { $0.manifest.id < $1.manifest.id }
    }

    private func adapterMetadata() -> [[String: Any]] {
        adapterMetadataLock.lock()
        if !adapterMetadataSnapshot.isEmpty,
           Date().timeIntervalSince(adapterMetadataUpdatedAt) < 20 {
            let snapshot = adapterMetadataSnapshot
            adapterMetadataLock.unlock()
            return snapshot
        }
        let metadata = loadManifests().map { adapter in
            let isBuiltIn = adapter.manifest.id == "codex" && adapter.manifest.executable == nil
            var metadata: [String: Any] = [
                "id": adapter.manifest.id,
                "version": adapter.manifest.version,
                "displayName": adapter.manifest.displayName,
                "capabilities": adapter.manifest.capabilities,
                "transport": adapter.manifest.transport ?? (isBuiltIn ? "builtin" : "process"),
                "operational": isBuiltIn ? codexAdapter.isOperational : externalAdapterRunner.isOperational(adapter)
            ]
            if isBuiltIn {
                metadata["message"] = codexAdapter.isOperational
                    ? "Codex 官方 app-server 已连接。"
                    : "请安装官方独立 Codex CLI 并启动 app-server 服务。"
            } else if externalAdapterRunner.isOperational(adapter) {
                let health = externalAdapterRunner.invoke(adapter, method: "health", params: [:])
                if health.ok {
                    for (key, value) in health.result { metadata[key] = value }
                } else if let error = health.error {
                    metadata["message"] = error
                    metadata["operational"] = false
                }
            }
            return metadata
        }
        adapterMetadataSnapshot = metadata
        adapterMetadataUpdatedAt = Date()
        adapterMetadataLock.unlock()
        return metadata
    }

    private func allAdapterSessions() -> [[String: Any]] {
        adapterSessionLock.lock()
        let snapshot = adapterSessionSnapshot
        adapterSessionLock.unlock()
        return snapshot
    }

    private func allAdapterSessionSummaries() -> [[String: Any]] {
        allAdapterSessions().compactMap { raw in
            guard let id = raw["id"] as? String, !id.isEmpty else { return nil }
            let adapterId = raw["adapterId"] as? String ?? "codex"
            let agentType = raw["agentType"] as? String ?? (adapterId == "codex" ? "Codex" : adapterId)
            let cwd = raw["cwd"] as? String ?? ""
            let phase = raw["phase"] as? String ?? "idle"
            let scheduledTask = raw["scheduledTask"] as? Bool == true
            let isRunning = phase == "processing"
            let controlAvailable = raw["controlAvailable"] as? Bool ?? (adapterId == "codex")
            let preview = raw["preview"] as? String ?? raw["title"] as? String ?? ""
            let projectName = URL(fileURLWithPath: cwd).lastPathComponent
            let project = raw["project"] as? String ?? (projectName.isEmpty ? agentType : projectName)

            return [
                "id": adapterId == "codex" && !id.hasPrefix("core|") ? "core|codex|\(id)" : id,
                "adapterId": adapterId,
                "agentType": agentType,
                "project": project,
                "cwd": cwd,
                "title": preview,
                "phase": phase,
                "statusLineText": scheduledTask ? "等待下一个执行周期" : (isRunning ? "正在 Mac 上执行" : "会话已同步"),
                "lastToolName": scheduledTask ? "等待下次定时执行" : (isRunning ? "\(agentType) 正在执行" : "\(agentType) 会话"),
                "lastToolStatus": phase,
                "startedAt": coreSessionDateString(raw["createdAt"]),
                "lastActivityAt": coreSessionDateString(raw["updatedAt"]),
                "scheduledTask": scheduledTask,
                "controlAvailable": controlAvailable
            ]
        }
    }

    private func coreSessionDateString(_ value: Any?) -> String {
        if let text = value as? String, !text.isEmpty { return text }
        if let number = value as? NSNumber {
            let rawValue = number.doubleValue
            let timestamp = rawValue > 4_000_000_000 ? rawValue / 1_000 : rawValue
            return ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: timestamp))
        }
        return ISO8601DateFormatter().string(from: Date())
    }

    private func refreshAdapterSessions() {
        let sessions = collectAdapterSessions()
        adapterSessionLock.lock()
        adapterSessionSnapshot = sessions
        adapterSessionLock.unlock()
    }

    private func collectAdapterSessions() -> [[String: Any]] {
        var sessions = codexAdapter.listSessions().map { session -> [String: Any] in
            var value = session
            value["adapterId"] = "codex"
            return value
        }
        let metadataById = Dictionary(uniqueKeysWithValues: adapterMetadata().compactMap { value -> (String, [String: Any])? in
            guard let id = value["id"] as? String else { return nil }
            return (id, value)
        })
        let now = Date()
        let activeIds = Set(metadataById.compactMap { id, value in
            (value["operational"] as? Bool) == true ? id : nil
        })
        externalSessionSnapshots = externalSessionSnapshots.filter { activeIds.contains($0.key) }
        externalSessionUpdatedAt = externalSessionUpdatedAt.filter { activeIds.contains($0.key) }

        for adapter in loadManifests() where adapter.manifest.id != "codex" && activeIds.contains(adapter.manifest.id) {
            let metadata = metadataById[adapter.manifest.id] ?? [:]
            let tier = metadata["integrationTier"] as? String ?? "managed_headless"
            let refreshInterval: TimeInterval = tier == "monitor_only" ? 30 : 5
            let cachedAt = externalSessionUpdatedAt[adapter.manifest.id] ?? .distantPast
            if now.timeIntervalSince(cachedAt) >= refreshInterval {
                let response = externalAdapterRunner.invoke(adapter, method: "listSessions", params: [:])
                if response.ok, let rows = response.result["sessions"] as? [[String: Any]] {
                    externalSessionSnapshots[adapter.manifest.id] = rows.compactMap { row in
                        guard let rawId = row["id"] as? String, !rawId.isEmpty else { return nil }
                        var value = row
                        value["id"] = "adapter|\(adapter.manifest.id)|\(rawId)"
                        value["adapterId"] = adapter.manifest.id
                        value["source"] = "agent-core-adapter"
                        return value
                    }
                    externalSessionUpdatedAt[adapter.manifest.id] = now
                }
            }
            sessions.append(contentsOf: externalSessionSnapshots[adapter.manifest.id] ?? [])
        }
        let sorted = sessions.sorted {
            let leftWaiting = ($0["phase"] as? String)?.hasPrefix("waiting") == true
            let rightWaiting = ($1["phase"] as? String)?.hasPrefix("waiting") == true
            if leftWaiting != rightWaiting { return leftWaiting }
            return ($0["updatedAt"] as? Double ?? 0) > ($1["updatedAt"] as? Double ?? 0)
        }
        var selected: [[String: Any]] = []
        var selectedIds = Set<String>()
        func appendUnique(_ value: [String: Any]) {
            guard let id = value["id"] as? String, selectedIds.insert(id).inserted else { return }
            selected.append(value)
        }

        for value in sorted {
            let phase = value["phase"] as? String ?? ""
            if phase == "processing" || phase.hasPrefix("waiting") { appendUnique(value) }
        }
        let grouped = Dictionary(grouping: sorted) { value in
            value["adapterId"] as? String ?? value["agentType"] as? String ?? "unknown"
        }
        for adapterId in grouped.keys.sorted() {
            for value in (grouped[adapterId] ?? []).prefix(24) { appendUnique(value) }
        }
        for value in sorted where selected.count < 240 { appendUnique(value) }
        return Array(selected.prefix(240))
    }

    private func performControl(_ params: [String: Any]) -> (ok: Bool, result: [String: Any], error: String?) {
        if let adapter = externalAdapter(for: params) {
            var routedParams = params
            if let sessionId = routedParams["sessionId"] as? String ?? routedParams["threadId"] as? String,
               let parsed = parseExternalSessionId(sessionId), parsed.adapterId == adapter.manifest.id {
                routedParams["sessionId"] = parsed.sessionId
                routedParams["threadId"] = parsed.sessionId
            }
            let result = externalAdapterRunner.invoke(adapter, method: "control", params: routedParams)
            return (result.ok, result.result, result.error ?? (result.ok ? nil : "adapter_control_failed"))
        }
        return codexAdapter.control(params)
    }

    private func performContext(_ params: [String: Any]) -> (ok: Bool, result: [String: Any], error: String?) {
        guard let adapter = externalAdapter(for: params) else {
            return (false, [:], "external_adapter_context_unavailable")
        }
        var routedParams = params
        if let sessionId = routedParams["sessionId"] as? String ?? routedParams["threadId"] as? String,
           let parsed = parseExternalSessionId(sessionId), parsed.adapterId == adapter.manifest.id {
            routedParams["sessionId"] = parsed.sessionId
            routedParams["threadId"] = parsed.sessionId
        }
        let result = externalAdapterRunner.invoke(adapter, method: "sessionContext", params: routedParams)
        return (result.ok, result.result, result.error ?? (result.ok ? nil : "adapter_context_failed"))
    }

    private func externalAdapter(for params: [String: Any]) -> LoadedAdapter? {
        let explicit = params["adapterId"] as? String
        let sessionId = params["sessionId"] as? String ?? params["threadId"] as? String
        let adapterId = explicit ?? sessionId.flatMap { parseExternalSessionId($0)?.adapterId }
        guard let adapterId, adapterId != "codex" else { return nil }
        return loadManifests().first { $0.manifest.id == adapterId && externalAdapterRunner.isOperational($0) }
    }

    private func parseExternalSessionId(_ id: String) -> (adapterId: String, sessionId: String)? {
        let parts = id.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "adapter" else { return nil }
        return (String(parts[1]), String(parts[2]))
    }

    private func success(_ id: String?, _ values: [String: Any]) -> CoreResponse {
        CoreResponse(id: id, ok: true, result: values.mapValues(AnyEncodable.init), error: nil)
    }

    private func send(_ response: CoreResponse, on connection: NWConnection) {
        var object: [String: Any] = ["ok": response.ok]
        if let id = response.id { object["id"] = id }
        if let result = response.result { object["result"] = result.mapValues(\.value) }
        if let error = response.error { object["error"] = error }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else {
            let fallback = Data("{\"ok\":false,\"error\":\"response_encoding_failed\"}".utf8)
            var payload = fallback
            payload.append(0x0A)
            connection.send(content: payload, completion: .contentProcessed { _ in
                connection.cancel()
            })
            return
        }
        var payload = data
        payload.append(0x0A)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

let arguments = CommandLine.arguments
if arguments.contains("--version") {
    print(coreVersion)
    exit(0)
}
let defaultSocket = NSHomeDirectory() + "/Library/Application Support/TraceFence/Core/agent-core.sock"
let socketPath: String
if let index = arguments.firstIndex(of: "--socket"), index + 1 < arguments.count {
    socketPath = arguments[index + 1]
} else {
    socketPath = defaultSocket
}

let httpConfigPath: String?
if let index = arguments.firstIndex(of: "--http-config"), index + 1 < arguments.count {
    httpConfigPath = arguments[index + 1]
} else {
    httpConfigPath = nil
}

private let daemon = CoreDaemon(socketPath: socketPath, httpConfigPath: httpConfigPath)
do {
    try daemon.start()
    RunLoop.current.run()
} catch {
    fputs("TraceFenceAgentCore could not start: \(error)\n", stderr)
    exit(1)
}
