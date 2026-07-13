import Foundation

struct UniversalHookInstaller {
    let profile: UniversalAdapterProfile
    let executablePath: String
    private let fileManager = FileManager.default

    func install() throws -> [String: Any] {
        switch profile.id {
        case "grok":
            return try installGrokHook()
        case "qwen":
            return try installQwenHook()
        case "gemini":
            return try installGeminiHook()
        case "cursor":
            return try installCursorHook()
        default:
            return [
                "installed": false,
                "message": "\(profile.displayName) is detected, but TraceFence does not install an unverified hook format."
            ]
        }
    }

    private func installGrokHook() throws -> [String: Any] {
        let directory = URL(fileURLWithPath: expandPath("~/.grok/hooks"), isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent("tracefence.json")
        let command = "\(shellQuote(executablePath)) --hook --adapter grok"
        let object: [String: Any] = [
            "hooks": [
                "PreToolUse": [[
                    "matcher": "*",
                    "hooks": [[
                        "type": "command",
                        "command": command,
                        "timeout": 21_600
                    ]]
                ]]
            ]
        ]
        try writeJSONObject(object, to: destination)
        return ["installed": true, "path": destination.path, "message": "Grok remote approval hook installed."]
    }

    private func installQwenHook() throws -> [String: Any] {
        let destination = URL(fileURLWithPath: expandPath("~/.qwen/settings.json"))
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var root = readJSONObject(destination)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks = removeTraceFenceAndLegacyEntries(hooks)
        let command = "\(shellQuote(executablePath)) --hook --adapter qwen"
        hooks["PreToolUse"] = appendHookGroup(
            hooks["PreToolUse"],
            group: [
                "matcher": "*",
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": 21_600,
                    "name": "TraceFence Sentinel remote approval"
                ]]
            ]
        )
        root["hooks"] = hooks
        root.removeValue(forKey: "disableAllHooks")
        try backupIfNeeded(destination)
        try writeJSONObject(root, to: destination)
        return ["installed": true, "path": destination.path, "message": "Qwen Code remote approval hook installed."]
    }

    private func installGeminiHook() throws -> [String: Any] {
        let destination = URL(fileURLWithPath: expandPath("~/.gemini/settings.json"))
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var root = readJSONObject(destination)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks = removeTraceFenceAndLegacyEntries(hooks)
        let command = "\(shellQuote(executablePath)) --hook --adapter gemini"
        hooks["BeforeTool"] = appendHookGroup(
            hooks["BeforeTool"],
            group: [
                "matcher": ".*",
                "sequential": true,
                "hooks": [[
                    "type": "command",
                    "command": command,
                    "timeout": 21_600_000,
                    "name": "TraceFence Sentinel remote approval"
                ]]
            ]
        )
        root["hooks"] = hooks
        try backupIfNeeded(destination)
        try writeJSONObject(root, to: destination)
        return ["installed": true, "path": destination.path, "message": "Gemini CLI remote approval hook installed."]
    }

    private func installCursorHook() throws -> [String: Any] {
        let destination = URL(fileURLWithPath: expandPath("~/.cursor/hooks.json"))
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        var root = readJSONObject(destination)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        hooks = removeTraceFenceAndLegacyEntries(hooks)
        let command = "\(shellQuote(executablePath)) --hook --adapter cursor"
        var entries = hooks["preToolUse"] as? [[String: Any]] ?? []
        entries.append([
            "command": command,
            "matcher": "*",
            "timeout": 21_600,
            "failClosed": true
        ])
        hooks["preToolUse"] = entries
        root["version"] = 1
        root["hooks"] = hooks
        try backupIfNeeded(destination)
        try writeJSONObject(root, to: destination)
        return ["installed": true, "path": destination.path, "message": "Cursor Agent remote approval gate installed."]
    }

    private func appendHookGroup(_ current: Any?, group: [String: Any]) -> [[String: Any]] {
        var groups = current as? [[String: Any]] ?? []
        groups.append(group)
        return groups
    }

    private func removeTraceFenceAndLegacyEntries(_ hooks: [String: Any]) -> [String: Any] {
        var cleaned: [String: Any] = [:]
        for (event, rawGroups) in hooks {
            let groups = rawGroups as? [[String: Any]] ?? []
            let filtered = groups.compactMap { group -> [String: Any]? in
                if containsManagedCommand(group) { return nil }
                if var nested = group["hooks"] as? [[String: Any]] {
                    nested.removeAll(where: containsManagedCommand)
                    if nested.isEmpty { return nil }
                    var value = group
                    value["hooks"] = nested
                    return value
                }
                return group
            }
            if !filtered.isEmpty { cleaned[event] = filtered }
        }
        return cleaned
    }

    private func containsManagedCommand(_ object: [String: Any]) -> Bool {
        guard let command = object["command"] as? String else { return false }
        return command.contains("TraceFenceUniversalAdapter") || command.contains("agentguard-bridge")
    }

    private func readJSONObject(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url), let object = jsonObject(data) else { return [:] }
        return object
    }

    private func writeJSONObject(_ object: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func backupIfNeeded(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let backup = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).tracefence-backup")
        guard !fileManager.fileExists(atPath: backup.path) else { return }
        try fileManager.copyItem(at: url, to: backup)
    }

    private func shellQuote(_ value: String) -> String {
        if value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "/._-:=@".contains($0)) }) { return value }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
