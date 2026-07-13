import Foundation
import Darwin

enum AgentPTYRuntimeError: LocalizedError {
    case targetNotFound
    case commandNotInstalled(String)
    case launchFailed(String)
    case sessionNotFound
    case writeFailed
    case signalFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .targetNotFound:
            return "TraceFence does not know this Agent launch target."
        case .commandNotInstalled(let command):
            return "\(command) is not installed or is not executable from TraceFence."
        case .launchFailed(let reason):
            return "Could not start the Agent PTY session: \(reason)"
        case .sessionNotFound:
            return "The TraceFence PTY session is no longer running."
        case .writeFailed:
            return "TraceFence could not write the instruction to the Agent terminal."
        case .signalFailed(let signal):
            return "TraceFence could not send signal \(signal) to the Agent process group."
        }
    }
}

struct AgentPTYLaunchTargetSnapshot: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let commandName: String
    let installed: Bool
    let icon: String
    let note: String
}

struct AgentPTYSessionSnapshot: Identifiable, Codable, Equatable {
    let id: String
    let targetId: String
    let displayName: String
    let commandName: String
    let pid: Int
    let cwd: String
    let phase: String
    let startedAt: Date
    let lastActivityAt: Date
    let outputTail: String
    let exitCode: Int?
    let controlMode: String
    let canInterrupt: Bool
    let canResume: Bool
}

struct AgentPTYControlResult {
    let ok: Bool
    let signalSent: Bool
    let instructionDelivered: Bool
    let deliveryMode: String
    let controlledPids: [Int]
    let message: String
}

@MainActor
final class AgentPTYRuntimeService: ObservableObject {
    static let shared = AgentPTYRuntimeService()

    @Published private(set) var sessions: [AgentPTYSessionSnapshot] = []

    private var runtimes: [String: AgentPTYSessionRuntime] = [:]
    private let outputLimit = 24_000

    private init() {}

    var launchTargets: [AgentPTYLaunchTargetSnapshot] {
        ([CLIAgentLaunchTarget.shell] + CLIAgentLaunchTarget.supported).map { target in
            let installed = target.id == CLIAgentLaunchTarget.shell.id || AgentIntegrationCatalog.commandURL(target.commandName) != nil
            return AgentPTYLaunchTargetSnapshot(
                id: target.id,
                displayName: target.displayName,
                commandName: target.commandName,
                installed: installed,
                icon: target.icon,
                note: installed
                    ? "TraceFence can launch and own this CLI through a PTY."
                    : "\(target.commandName) was not found on this Mac."
            )
        }
    }

    var visibleSessions: [AgentPTYSessionSnapshot] {
        sessions.filter { $0.phase != "done" || Date().timeIntervalSince($0.lastActivityAt) < 600 }
    }

    @discardableResult
    func launch(targetId: String, cwd: String? = nil, initialInstruction: String? = nil) throws -> AgentPTYSessionSnapshot {
        guard let target = ([CLIAgentLaunchTarget.shell] + CLIAgentLaunchTarget.supported).first(where: { $0.id == targetId }) else {
            throw AgentPTYRuntimeError.targetNotFound
        }

        let commandLine: String
        if target.id == CLIAgentLaunchTarget.shell.id {
            commandLine = "exec /bin/zsh -l"
        } else {
            guard let commandURL = AgentIntegrationCatalog.commandURL(target.commandName) else {
                throw AgentPTYRuntimeError.commandNotInstalled(target.commandName)
            }
            commandLine = "exec \(Self.shellQuote(commandURL.path))"
        }

        let sessionId = "pty-\(UUID().uuidString)"
        let workingDirectory = normalizedWorkingDirectory(cwd)
        var masterFD: Int32 = -1
        let childPID = forkpty(&masterFD, nil, nil, nil)
        if childPID < 0 {
            throw AgentPTYRuntimeError.launchFailed(String(cString: strerror(errno)))
        }

        if childPID == 0 {
            chdir(workingDirectory)
            setenv("TERM", "xterm-256color", 1)
            setenv("TRACEFENCE_CONTROL_PLANE", "1", 1)
            setenv("TRACEFENCE_PTY_SESSION_ID", sessionId, 1)
            setenv("TRACEFENCE_AGENT_TARGET", target.id, 1)
            execShell(commandLine)
            _exit(127)
        }

        let fd = masterFD
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let runtime = AgentPTYSessionRuntime(
            id: sessionId,
            target: target,
            pid: Int(childPID),
            masterFD: fd,
            handle: handle,
            cwd: workingDirectory,
            startedAt: Date()
        )
        runtimes[sessionId] = runtime
        installReadHandler(for: runtime)
        refreshSnapshots()
        waitForExit(sessionId: sessionId, pid: childPID)

        if let text = initialInstruction?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 750_000_000)
                _ = try? sendInstruction(sessionId: sessionId, instruction: text)
            }
        }

        guard let snapshot = snapshot(for: runtime) else {
            throw AgentPTYRuntimeError.launchFailed("Session disappeared after launch.")
        }
        return snapshot
    }

    func interrupt(sessionId: String) throws -> AgentPTYControlResult {
        guard let runtime = runtimes[sessionId] else {
            throw AgentPTYRuntimeError.sessionNotFound
        }
        try signalProcessGroup(runtime, signal: SIGSTOP)
        runtime.phase = "interrupted"
        runtime.lastActivityAt = Date()
        refreshSnapshots()
        return AgentPTYControlResult(
            ok: true,
            signalSent: true,
            instructionDelivered: false,
            deliveryMode: "signal",
            controlledPids: [runtime.pid],
            message: "TraceFence 已暂停 PTY Agent 进程组。"
        )
    }

    func resume(sessionId: String, instruction: String?) throws -> AgentPTYControlResult {
        guard let runtime = runtimes[sessionId] else {
            throw AgentPTYRuntimeError.sessionNotFound
        }
        var delivered = false
        if let instruction = instruction?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty {
            delivered = try sendInstruction(sessionId: sessionId, instruction: instruction).instructionDelivered
        }
        try signalProcessGroup(runtime, signal: SIGCONT)
        runtime.phase = "processing"
        runtime.lastActivityAt = Date()
        refreshSnapshots()
        return AgentPTYControlResult(
            ok: true,
            signalSent: true,
            instructionDelivered: delivered,
            deliveryMode: delivered ? "pty" : "signal",
            controlledPids: [runtime.pid],
            message: delivered
                ? "TraceFence 已写入继续指令，并恢复 PTY Agent 进程组。"
                : "TraceFence 已恢复 PTY Agent 进程组。"
        )
    }

    func terminate(sessionId: String) throws -> AgentPTYControlResult {
        guard let runtime = runtimes[sessionId] else {
            throw AgentPTYRuntimeError.sessionNotFound
        }
        try signalProcessGroup(runtime, signal: SIGTERM)
        Thread.sleep(forTimeInterval: 0.2)
        var forced = false
        if Self.processIsAlive(pid_t(runtime.pid)) {
            forced = true
            _ = try? signalProcessGroup(runtime, signal: SIGKILL)
            Thread.sleep(forTimeInterval: 0.1)
        }
        runtime.phase = "done"
        runtime.lastActivityAt = Date()
        runtime.handle.readabilityHandler = nil
        try? runtime.handle.close()
        refreshSnapshots()
        return AgentPTYControlResult(
            ok: true,
            signalSent: true,
            instructionDelivered: false,
            deliveryMode: "signal",
            controlledPids: [runtime.pid],
            message: forced
                ? "TraceFence 已强制结束 PTY Agent 进程组。"
                : "TraceFence 已结束 PTY Agent 进程组。"
        )
    }

    private func sendInstruction(sessionId: String, instruction: String) throws -> AgentPTYControlResult {
        guard let runtime = runtimes[sessionId] else {
            throw AgentPTYRuntimeError.sessionNotFound
        }
        let payload = instruction.hasSuffix("\n") ? instruction : instruction + "\n"
        guard let data = payload.data(using: .utf8) else {
            throw AgentPTYRuntimeError.writeFailed
        }
        let written = data.withUnsafeBytes { buffer -> Int in
            guard let base = buffer.baseAddress else { return -1 }
            return write(runtime.masterFD, base, data.count)
        }
        guard written == data.count else {
            throw AgentPTYRuntimeError.writeFailed
        }
        runtime.lastActivityAt = Date()
        refreshSnapshots()
        return AgentPTYControlResult(
            ok: true,
            signalSent: false,
            instructionDelivered: true,
            deliveryMode: "pty",
            controlledPids: [runtime.pid],
            message: "TraceFence 已把指令写入 PTY Agent 终端。"
        )
    }

    private func signalProcessGroup(_ runtime: AgentPTYSessionRuntime, signal: Int32) throws {
        if Darwin.kill(pid_t(-runtime.pid), signal) == 0 {
            return
        }
        if Darwin.kill(pid_t(runtime.pid), signal) == 0 {
            return
        }
        throw AgentPTYRuntimeError.signalFailed(signal)
    }

    private func installReadHandler(for runtime: AgentPTYSessionRuntime) {
        runtime.handle.readabilityHandler = { [weak self, weak runtime] handle in
            let data = handle.availableData
            guard !data.isEmpty, let runtime else { return }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            Task { @MainActor in
                self?.appendOutput(text, to: runtime.id)
            }
        }
    }

    private func appendOutput(_ text: String, to sessionId: String) {
        guard let runtime = runtimes[sessionId] else { return }
        runtime.outputTail += text
        if runtime.outputTail.count > outputLimit {
            runtime.outputTail = String(runtime.outputTail.suffix(outputLimit))
        }
        runtime.lastActivityAt = Date()
        refreshSnapshots()
    }

    private func waitForExit(sessionId: String, pid: pid_t) {
        Task.detached(priority: .utility) {
            var status: Int32 = 0
            _ = waitpid(pid, &status, 0)
            let exitCode = Self.exitCode(fromWaitStatus: status)
            await MainActor.run {
                AgentPTYRuntimeService.shared.markExited(sessionId: sessionId, exitCode: exitCode)
            }
        }
    }

    private nonisolated static func exitCode(fromWaitStatus status: Int32) -> Int {
        let termination = status & 0x7f
        if termination == 0 {
            return Int((status >> 8) & 0xff)
        }
        if termination != 0x7f {
            return 128 + Int(termination)
        }
        return -1
    }

    private nonisolated static func processIsAlive(_ pid: pid_t) -> Bool {
        Darwin.kill(pid, 0) == 0
    }

    private func markExited(sessionId: String, exitCode: Int) {
        guard let runtime = runtimes[sessionId] else { return }
        runtime.phase = "done"
        runtime.exitCode = exitCode
        runtime.lastActivityAt = Date()
        runtime.handle.readabilityHandler = nil
        refreshSnapshots()
    }

    private func refreshSnapshots() {
        sessions = runtimes.values
            .compactMap(snapshot(for:))
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
    }

    private func snapshot(for runtime: AgentPTYSessionRuntime) -> AgentPTYSessionSnapshot? {
        AgentPTYSessionSnapshot(
            id: runtime.id,
            targetId: runtime.target.id,
            displayName: runtime.target.displayName,
            commandName: runtime.target.commandName,
            pid: runtime.pid,
            cwd: runtime.cwd,
            phase: runtime.phase,
            startedAt: runtime.startedAt,
            lastActivityAt: runtime.lastActivityAt,
            outputTail: runtime.outputTail,
            exitCode: runtime.exitCode,
            controlMode: "tracefence_pty",
            canInterrupt: runtime.phase == "processing",
            canResume: runtime.phase == "interrupted"
        )
    }

    private func normalizedWorkingDirectory(_ cwd: String?) -> String {
        let trimmed = cwd?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty, FileManager.default.fileExists(atPath: trimmed) {
            return trimmed
        }
        return SandboxPaths.realHomeDirectory
    }

    private static func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        if value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "/._-".contains($0)) }) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

private final class AgentPTYSessionRuntime {
    let id: String
    let target: CLIAgentLaunchTarget
    let pid: Int
    let masterFD: Int32
    let handle: FileHandle
    let cwd: String
    let startedAt: Date
    var lastActivityAt: Date
    var phase: String = "processing"
    var outputTail: String = ""
    var exitCode: Int?

    init(
        id: String,
        target: CLIAgentLaunchTarget,
        pid: Int,
        masterFD: Int32,
        handle: FileHandle,
        cwd: String,
        startedAt: Date
    ) {
        self.id = id
        self.target = target
        self.pid = pid
        self.masterFD = masterFD
        self.handle = handle
        self.cwd = cwd
        self.startedAt = startedAt
        self.lastActivityAt = startedAt
    }
}

private func execShell(_ command: String) {
    let shell = "/bin/zsh"
    let arguments = ["zsh", "-lc", command]
    var argv = arguments.map { strdup($0) }
    argv.append(nil)
    execv(shell, &argv)
}
