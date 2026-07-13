import Foundation
import Darwin

struct TraceFenceAgentCoreStatus {
    let connected: Bool
    let coreVersion: String?
    let coreBuild: Int?
    let protocolVersion: Int?
    let adapters: [[String: Any]]
    let update: [String: Any]
    let message: String

    var payload: [String: Any] {
        [
            "connected": connected,
            "coreVersion": coreVersion ?? "",
            "coreBuild": coreBuild ?? 0,
            "protocolVersion": protocolVersion ?? 0,
            "adapters": adapters,
            "update": update,
            "message": message
        ]
    }
}

struct TraceFenceAgentCoreSessionSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let agentType: String
    let project: String
    let cwd: String
    let title: String
    let phase: String
    let statusLineText: String
    let lastToolName: String
    let lastToolStatus: String
    let lastActivityAt: Date
    let startedAt: Date
    let scheduledTask: Bool
    let controlAvailable: Bool

    init?(payload: [String: Any]) {
        guard let id = payload["id"] as? String, !id.isEmpty else { return nil }

        self.id = id
        agentType = payload["agentType"] as? String ?? payload["adapterId"] as? String ?? "Agent"
        project = payload["project"] as? String ?? ""
        cwd = payload["cwd"] as? String ?? ""
        title = payload["title"] as? String ?? ""
        phase = payload["phase"] as? String ?? "idle"
        statusLineText = payload["statusLineText"] as? String ?? ""
        lastToolName = payload["lastToolName"] as? String ?? ""
        lastToolStatus = payload["lastToolStatus"] as? String ?? ""
        scheduledTask = payload["scheduledTask"] as? Bool ?? false
        controlAvailable = payload["controlAvailable"] as? Bool ?? false

        let started = Self.parseDate(payload["startedAt"] as? String) ?? .distantPast
        startedAt = started
        lastActivityAt = Self.parseDate(payload["lastActivityAt"] as? String) ?? started
    }

    var isActive: Bool {
        ["processing", "compacting", "waitingApproval", "waitingInput"].contains(phase)
    }

    var needsAttention: Bool {
        ["waitingApproval", "waitingInput", "error", "interrupted"].contains(phase)
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}

@MainActor
final class TraceFenceAgentCoreClient {
    static let shared = TraceFenceAgentCoreClient()

    private let socketPath = NSHomeDirectory() + "/Library/Application Support/TraceFence/Core/agent-core.sock"
    private var coreProcess: Process?
    private(set) var status = TraceFenceAgentCoreStatus(
        connected: false,
        coreVersion: nil,
        coreBuild: nil,
        protocolVersion: nil,
        adapters: [],
        update: [:],
        message: "TraceFence Agent Core 未安装。"
    )

    private init() {}

    func refresh() async -> TraceFenceAgentCoreStatus {
        if coreProcess?.isRunning != true {
            startIfInstalled()
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        if let response = await request(method: "health") {
            let adapters = response["adapters"] as? [[String: Any]] ?? []
            status = TraceFenceAgentCoreStatus(
                connected: true,
                coreVersion: response["coreVersion"] as? String,
                coreBuild: response["coreBuild"] as? Int,
                protocolVersion: response["protocolVersion"] as? Int,
                adapters: adapters,
                update: response["update"] as? [String: Any] ?? [:],
                message: "TraceFence Agent Core 已连接。"
            )
            return status
        }

        startIfInstalled()
        try? await Task.sleep(nanoseconds: 250_000_000)
        if let response = await request(method: "health") {
            let adapters = response["adapters"] as? [[String: Any]] ?? []
            status = TraceFenceAgentCoreStatus(
                connected: true,
                coreVersion: response["coreVersion"] as? String,
                coreBuild: response["coreBuild"] as? Int,
                protocolVersion: response["protocolVersion"] as? Int,
                adapters: adapters,
                update: response["update"] as? [String: Any] ?? [:],
                message: "TraceFence Agent Core 已连接。"
            )
        } else {
            status = TraceFenceAgentCoreStatus(
                connected: false,
                coreVersion: nil,
                coreBuild: nil,
                protocolVersion: nil,
                adapters: [],
                update: [:],
                message: "未连接 Agent Core；当前使用 macOS App 内置兼容能力。"
            )
        }
        return status
    }

    func request(method: String, params: [String: Any] = [:]) async -> [String: Any]? {
        var result = await send(method: method, params: params)
        if result == nil {
            startIfInstalled()
            try? await Task.sleep(nanoseconds: 250_000_000)
            result = await send(method: method, params: params)
        }
        if let result {
            updateStatus(from: result)
        }
        return result
    }

    func listSessions() async -> [[String: Any]]? {
        await request(method: "listSessions")?["sessions"] as? [[String: Any]]
    }

    func sessionSnapshots() async -> [TraceFenceAgentCoreSessionSnapshot] {
        let summaryPayloads = await request(method: "listSessionSummaries")?["sessions"] as? [[String: Any]]
        let payloads: [[String: Any]]
        if let summaryPayloads {
            payloads = summaryPayloads
        } else {
            payloads = await listSessions() ?? []
        }
        return payloads.compactMap(TraceFenceAgentCoreSessionSnapshot.init(payload:))
    }

    func control(_ params: [String: Any]) async -> [String: Any]? {
        await request(method: "control", params: params)
    }

    func checkForUpdates() async -> TraceFenceAgentCoreStatus {
        guard let accepted = await request(method: "checkForUpdates", params: ["force": true]),
              accepted["accepted"] as? Bool == true else {
            return await refresh()
        }

        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let response = await request(method: "updateStatus"),
                  let update = response["update"] as? [String: Any] else { continue }
            let state = update["state"] as? String ?? ""
            if !["checking", "downloading", "installing"].contains(state) {
                break
            }
        }
        return await refresh()
    }

    private func send(method: String, params: [String: Any]) async -> [String: Any]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: Self.sendSync(
                    socketPath: self.socketPath,
                    method: method,
                    params: params
                ))
            }
        }
    }

    private func updateStatus(from response: [String: Any]) {
        let adapters = response["adapters"] as? [[String: Any]] ?? status.adapters
        status = TraceFenceAgentCoreStatus(
            connected: true,
            coreVersion: response["coreVersion"] as? String ?? status.coreVersion,
            coreBuild: response["coreBuild"] as? Int ?? status.coreBuild,
            protocolVersion: response["protocolVersion"] as? Int ?? status.protocolVersion,
            adapters: adapters,
            update: response["update"] as? [String: Any] ?? status.update,
            message: "TraceFence Agent Core 已连接。"
        )
    }

    private func startIfInstalled() {
        guard coreProcess?.isRunning != true,
              let executable = Self.coreExecutableURL() else { return }

        if FileManager.default.fileExists(atPath: Self.launchAgentPath) {
            Self.kickstartLaunchAgent()
            return
        }
        if FileManager.default.fileExists(atPath: socketPath) {
            return
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = ["--socket", socketPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            coreProcess = process
        } catch {
            coreProcess = nil
        }
    }

    private static func coreExecutableURL() -> URL? {
        let candidates = [
            NSHomeDirectory() + "/Library/Application Support/TraceFence/Core/TraceFenceAgentCore",
            "/Library/Application Support/TraceFence/Core/TraceFenceAgentCore",
            "/usr/local/libexec/TraceFenceAgentCore",
            "/opt/homebrew/libexec/TraceFenceAgentCore"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }

    nonisolated private static var launchAgentPath: String {
        NSHomeDirectory() + "/Library/LaunchAgents/com.tracefence.agent-core.plist"
    }

    nonisolated private static func kickstartLaunchAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = ["kickstart", "gui/\(getuid())/com.tracefence.agent-core"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    nonisolated private static func sendSync(socketPath: String, method: String, params: [String: Any]) -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: socketPath) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var timeout = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { return nil }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { destination in
                _ = pathBytes.withUnsafeBufferPointer { source in
                    memcpy(destination, source.baseAddress, pathBytes.count)
                }
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return nil }

        let request: [String: Any] = [
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: request) else { return nil }
        data.append(0x0A)
        guard writeAll(data, fd: fd) else { return nil }

        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while !response.contains(0x0A) {
            let count = Darwin.read(fd, &buffer, buffer.count)
            guard count > 0 else { return nil }
            response.append(contentsOf: buffer.prefix(count))
        }
        guard let newline = response.firstIndex(of: 0x0A) else { return nil }
        let line = response.prefix(upTo: newline)
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["ok"] as? Bool == true else { return nil }
        return object["result"] as? [String: Any]
    }

    nonisolated private static func writeAll(_ data: Data, fd: Int32) -> Bool {
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
}
