import Foundation

struct LaunchControlCommandResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String

    var combinedOutput: String {
        [standardOutput, standardError]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

protocol LaunchControlCommandRunning: Sendable {
    func runLaunchctl(arguments: [String]) throws -> LaunchControlCommandResult
}

struct ProcessLaunchControlCommandRunner: LaunchControlCommandRunning {
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 2) {
        self.timeout = timeout
    }

    func runLaunchctl(arguments: [String]) throws -> LaunchControlCommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let completion = DispatchSemaphore(value: 0)
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { _ in
            completion.signal()
        }

        try process.run()
        let deadline = DispatchTime.now() + timeout
        if completion.wait(timeout: deadline) == .timedOut {
            process.terminate()
            _ = completion.wait(timeout: .now() + 0.5)
            if process.isRunning {
                process.interrupt()
            }
        }

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let error = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        return LaunchControlCommandResult(
            exitCode: process.terminationStatus,
            standardOutput: output,
            standardError: error
        )
    }
}
