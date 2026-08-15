import Darwin
import Foundation

/// The host has already waited for Codex to stop before launching each worker.
/// Re-checking the global desktop process inside the child would reject every
/// fixture (and can race with a newly launched UI), while the per-file lsof
/// guard must remain fail-closed immediately before replacement.
private struct WorkerFileProcessMonitor: CodexProcessMonitoring {
    private let underlying = CodexProcessMonitor()

    func isCodexRunning() -> Bool { false }
    func waitUntilCodexStops() async throws {}
    func fileHasOpenHandle(_ url: URL) -> Bool {
        underlying.fileHasOpenHandle(url)
    }
}

struct TraceFenceCodexMediaWorker {
    static func main() {
        _ = setpriority(PRIO_PROCESS, 0, 10)
        do {
            let arguments = try parseArguments(CommandLine.arguments.dropFirst())
            guard let operation = CodexMediaOperation(rawValue: arguments.operation) else {
                throw WorkerArgumentError.invalidValue("operation")
            }
            let configuration = CodexMediaCleanupConfiguration(
                codexHome: URL(fileURLWithPath: arguments.codexHome, isDirectory: true),
                supportDirectory: URL(fileURLWithPath: arguments.supportDirectory, isDirectory: true),
                includeArchivedSessions: true
            )
            let engine = CodexMediaRepairEngine(processMonitor: WorkerFileProcessMonitor())
            let result = try autoreleasepool {
                try engine.repairFile(
                    URL(fileURLWithPath: arguments.file),
                    operation: operation,
                    configuration: configuration,
                    backupRoot: URL(fileURLWithPath: arguments.backupRoot, isDirectory: true)
                )
            }
            try emit(CodexMediaWorkerResponse(result: result, error: nil))
        } catch {
            try? emit(CodexMediaWorkerResponse(result: nil, error: error.localizedDescription))
            fputs("TraceFence Codex media worker: \(error.localizedDescription)\n", stderr)
            exit(2)
        }
    }

    private struct Arguments {
        let file: String
        let operation: String
        let codexHome: String
        let supportDirectory: String
        let backupRoot: String
    }

    private enum WorkerArgumentError: LocalizedError {
        case missingValue(String)
        case invalidValue(String)

        var errorDescription: String? {
            switch self {
            case let .missingValue(name): "Missing worker argument: \(name)"
            case let .invalidValue(name): "Invalid worker argument: \(name)"
            }
        }
    }

    private static func parseArguments<S: Sequence>(_ values: S) throws -> Arguments
    where S.Element == String {
        let input = Array(values)
        var parsed: [String: String] = [:]
        var index = 0
        while index < input.count {
            let key = input[index]
            guard key.hasPrefix("--"), index + 1 < input.count else {
                throw WorkerArgumentError.invalidValue(key)
            }
            parsed[String(key.dropFirst(2))] = input[index + 1]
            index += 2
        }

        func required(_ key: String) throws -> String {
            guard let value = parsed[key], !value.isEmpty else {
                throw WorkerArgumentError.missingValue(key)
            }
            return value
        }
        return try Arguments(
            file: required("file"),
            operation: required("operation"),
            codexHome: required("codex-home"),
            supportDirectory: required("support-directory"),
            backupRoot: required("backup-root")
        )
    }

    private static func emit(_ response: CodexMediaWorkerResponse) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(response)
        data.append(0x0A)
        try FileHandle.standardOutput.write(contentsOf: data)
    }
}

TraceFenceCodexMediaWorker.main()
