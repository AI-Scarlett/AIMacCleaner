import Foundation
import Darwin

let universalAdapterVersion = "1.1.0"
let universalProtocolVersion = 1

enum AdapterControlKind: String {
    case resumableCLI
    case newTaskCLI
    case openClawCLI
    case miniMaxOpenCode
    case monitorOnly
}

struct UniversalAdapterProfile {
    let id: String
    let displayName: String
    let commandCandidates: [String]
    let dataRoots: [String]
    let applicationNames: [String]
    let controlKind: AdapterControlKind
    let supportsApprovalHook: Bool
    let documentationURL: String

    static let all: [UniversalAdapterProfile] = [
        .init(
            id: "grok",
            displayName: "Grok CLI",
            commandCandidates: ["grok"],
            dataRoots: ["~/.grok"],
            applicationNames: [],
            controlKind: .resumableCLI,
            supportsApprovalHook: true,
            documentationURL: "https://docs.x.ai/build/cli/reference"
        ),
        .init(
            id: "qwen",
            displayName: "Qwen Code",
            commandCandidates: ["qwen"],
            dataRoots: ["~/.qwen"],
            applicationNames: [],
            controlKind: .resumableCLI,
            supportsApprovalHook: true,
            documentationURL: "https://qwenlm.github.io/qwen-code-docs/"
        ),
        .init(
            id: "cursor",
            displayName: "Cursor Agent",
            commandCandidates: ["cursor-agent"],
            dataRoots: ["~/.cursor", "~/Library/Application Support/Cursor"],
            applicationNames: ["Cursor"],
            controlKind: .resumableCLI,
            supportsApprovalHook: true,
            documentationURL: "https://docs.cursor.com/en/cli/overview"
        ),
        .init(
            id: "trae",
            displayName: "Trae",
            commandCandidates: [],
            dataRoots: ["~/.trae", "~/.trae-cn", "~/Library/Application Support/Trae", "~/Library/Application Support/Trae CN"],
            applicationNames: ["Trae", "Trae CN"],
            controlKind: .monitorOnly,
            supportsApprovalHook: false,
            documentationURL: "https://www.trae.ai/"
        ),
        .init(
            id: "codebuddy",
            displayName: "CodeBuddy",
            commandCandidates: [],
            dataRoots: ["~/.codebuddy", "~/Library/Application Support/CodeBuddy", "~/Library/Application Support/CodeBuddy CN"],
            applicationNames: ["CodeBuddy", "CodeBuddy CN"],
            controlKind: .monitorOnly,
            supportsApprovalHook: false,
            documentationURL: "https://www.codebuddy.ai/"
        ),
        .init(
            id: "openclaw",
            displayName: "OpenClaw",
            commandCandidates: ["openclaw"],
            dataRoots: ["~/.openclaw"],
            applicationNames: ["OpenClaw"],
            controlKind: .openClawCLI,
            supportsApprovalHook: false,
            documentationURL: "https://docs.openclaw.ai/cli"
        ),
        .init(
            id: "hermes",
            displayName: "Hermes Agent",
            commandCandidates: ["hermes"],
            dataRoots: ["~/.hermes"],
            applicationNames: ["Hermes", "Hermes Agent"],
            controlKind: .resumableCLI,
            supportsApprovalHook: false,
            documentationURL: "https://hermes-agent.nousresearch.com/docs/"
        ),
        .init(
            id: "minimax",
            displayName: "MiniMax Code",
            commandCandidates: ["minimax", "mavis"],
            dataRoots: ["~/.minimax", "~/.mavis", "~/Library/Application Support/MiniMax"],
            applicationNames: ["MiniMax Code", "MiniMax"],
            controlKind: .miniMaxOpenCode,
            supportsApprovalHook: false,
            documentationURL: "https://agent.minimax.io/docs/user-guide"
        ),
        .init(
            id: "gemini",
            displayName: "Gemini CLI",
            commandCandidates: ["gemini"],
            dataRoots: ["~/.gemini"],
            applicationNames: [],
            controlKind: .resumableCLI,
            supportsApprovalHook: true,
            documentationURL: "https://geminicli.com/docs/cli/"
        ),
        .init(
            id: "opencode",
            displayName: "OpenCode",
            commandCandidates: ["opencode"],
            dataRoots: ["~/.local/share/opencode", "~/.config/opencode", "~/.opencode"],
            applicationNames: ["OpenCode"],
            controlKind: .resumableCLI,
            supportsApprovalHook: false,
            documentationURL: "https://opencode.ai/docs/server/"
        ),
        .init(
            id: "kiro",
            displayName: "Kiro CLI",
            commandCandidates: ["kiro-cli", "kiro"],
            dataRoots: ["~/.kiro"],
            applicationNames: ["Kiro"],
            controlKind: .resumableCLI,
            supportsApprovalHook: false,
            documentationURL: "https://kiro.dev/docs/cli/"
        ),
        .init(
            id: "aider",
            displayName: "Aider",
            commandCandidates: ["aider"],
            dataRoots: ["~/.aider", "~/.aider.conf.yml"],
            applicationNames: [],
            controlKind: .newTaskCLI,
            supportsApprovalHook: false,
            documentationURL: "https://aider.chat/docs/scripting.html"
        ),
        .init(
            id: "amp",
            displayName: "Amp",
            commandCandidates: ["amp"],
            dataRoots: ["~/.config/amp", "~/.amp"],
            applicationNames: [],
            controlKind: .newTaskCLI,
            supportsApprovalHook: false,
            documentationURL: "https://ampcode.com/manual"
        ),
        .init(
            id: "goose",
            displayName: "Goose",
            commandCandidates: ["goose"],
            dataRoots: ["~/.config/goose", "~/.local/share/goose", "~/Library/Application Support/Block/goose"],
            applicationNames: ["Goose"],
            controlKind: .newTaskCLI,
            supportsApprovalHook: false,
            documentationURL: "https://block.github.io/goose/"
        ),
        .init(
            id: "copilot",
            displayName: "GitHub Copilot CLI",
            commandCandidates: ["copilot", "github-copilot-cli"],
            dataRoots: ["~/.config/github-copilot"],
            applicationNames: [],
            controlKind: .newTaskCLI,
            supportsApprovalHook: false,
            documentationURL: "https://docs.github.com/en/copilot"
        ),
        .init(
            id: "droid",
            displayName: "Factory / Droid",
            commandCandidates: ["droid"],
            dataRoots: ["~/.factory"],
            applicationNames: ["Droid", "Factory"],
            controlKind: .newTaskCLI,
            supportsApprovalHook: false,
            documentationURL: "https://docs.factory.ai/"
        )
    ]

    static func profile(id: String) -> UniversalAdapterProfile? {
        all.first { $0.id == id }
    }

    var commandURL: URL? {
        for candidate in commandCandidates {
            if candidate.hasPrefix("/") {
                let url = URL(fileURLWithPath: candidate)
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
                continue
            }
            for directory in Self.commandSearchDirectories {
                let url = directory.appendingPathComponent(candidate)
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
        }
        return nil
    }

    var dataPresent: Bool {
        dataRoots.contains { FileManager.default.fileExists(atPath: expandPath($0)) }
    }

    var applicationPresent: Bool {
        applicationNames.contains { name in
            FileManager.default.fileExists(atPath: "/Applications/\(name).app")
                || FileManager.default.fileExists(atPath: expandPath("~/Applications/\(name).app"))
        }
    }

    var installed: Bool {
        commandURL != nil || applicationPresent || dataPresent
    }

    var supportsDirectControl: Bool {
        switch controlKind {
        case .monitorOnly:
            return false
        case .miniMaxOpenCode:
            return commandURL != nil || applicationPresent
        default:
            return commandURL != nil
        }
    }

    private static var commandSearchDirectories: [URL] {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let environmentPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) }
        let known = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
            home.appendingPathComponent(".local/bin").path,
            home.appendingPathComponent(".grok/bin").path,
            home.appendingPathComponent(".qwen/bin").path,
            home.appendingPathComponent(".cursor/bin").path,
            home.appendingPathComponent(".minimax/bin").path,
            home.appendingPathComponent(".opencode/bin").path,
            home.appendingPathComponent(".bun/bin").path,
            home.appendingPathComponent(".cargo/bin").path,
            home.appendingPathComponent(".npm-global/bin").path,
            home.appendingPathComponent("bin").path
        ].map { URL(fileURLWithPath: $0, isDirectory: true) }
        var seen = Set<String>()
        return (environmentPaths + known).filter { seen.insert($0.standardizedFileURL.path).inserted }
    }
}

struct ManagedJob: Codable {
    var id: String
    var adapterId: String
    var nativeSessionId: String
    var title: String
    var cwd: String
    var pid: Int32
    var outputPath: String
    var createdAt: Double
    var updatedAt: Double
    var phase: String
    var lastInstruction: String
}

struct PendingHookApproval: Codable {
    var requestId: String
    var adapterId: String
    var sessionId: String
    var cwd: String
    var eventName: String
    var toolName: String
    var toolInput: String
    var command: String
    var createdAt: Double
}

enum UniversalAdapterError: LocalizedError {
    case invalidRequest
    case unsupportedAdapter
    case unsupportedMethod(String)
    case controlUnavailable(String)
    case sessionUnavailable
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "invalid_request"
        case .unsupportedAdapter: return "unsupported_adapter"
        case .unsupportedMethod(let method): return "unsupported_method:\(method)"
        case .controlUnavailable(let reason): return reason
        case .sessionUnavailable: return "session_unavailable"
        case .launchFailed(let reason): return "launch_failed:\(reason)"
        }
    }
}

func expandPath(_ path: String) -> String {
    if path == "~" { return NSHomeDirectory() }
    if path.hasPrefix("~/") { return NSHomeDirectory() + String(path.dropFirst()) }
    return NSString(string: path).expandingTildeInPath
}

func coreDirectoryURL() -> URL {
    URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Application Support/TraceFence/Core", isDirectory: true)
}

func universalStateDirectoryURL() -> URL {
    coreDirectoryURL().appendingPathComponent("universal", isDirectory: true)
}

func unixTime(_ value: Any?) -> Double {
    if let value = value as? Double { return value > 9_999_999_999 ? value / 1_000 : value }
    if let value = value as? Int { return unixTime(Double(value)) }
    if let value = value as? Int64 { return unixTime(Double(value)) }
    if let value = value as? NSNumber { return unixTime(value.doubleValue) }
    if let value = value as? String {
        if let number = Double(value) { return unixTime(number) }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date.timeIntervalSince1970 }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: value) { return date.timeIntervalSince1970 }
    }
    return 0
}

func jsonObject(_ data: Data) -> [String: Any]? {
    try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

func jsonString(_ value: Any, limit: Int = 8_000) -> String {
    let text: String
    if let value = value as? String {
        text = value
    } else if JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8) {
        text = value
    } else {
        text = String(describing: value)
    }
    return text.count > limit ? String(text.prefix(limit)) : text
}

func extractedText(_ value: Any?) -> String {
    guard let value else { return "" }
    if let text = value as? String { return text }
    if let values = value as? [Any] {
        return values.compactMap { item -> String? in
            if let text = item as? String { return text }
            if let object = item as? [String: Any] {
                return object["text"] as? String
                    ?? object["content"] as? String
                    ?? object["value"] as? String
            }
            return nil
        }.joined()
    }
    if let object = value as? [String: Any] {
        return extractedText(object["text"] ?? object["content"] ?? object["parts"])
    }
    return ""
}

func processIsAlive(_ pid: Int32) -> Bool {
    guard pid > 0 else { return false }
    if kill(pid, 0) == 0 { return true }
    return errno == EPERM
}

func writeJSONResponse(ok: Bool, result: [String: Any] = [:], error: String? = nil) {
    var response: [String: Any] = ["ok": ok]
    if !result.isEmpty { response["result"] = result }
    if let error { response["error"] = error }
    guard let data = try? JSONSerialization.data(withJSONObject: response, options: [.withoutEscapingSlashes]) else {
        FileHandle.standardOutput.write(Data("{\"ok\":false,\"error\":\"response_encoding_failed\"}\n".utf8))
        return
    }
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data([0x0A]))
}
