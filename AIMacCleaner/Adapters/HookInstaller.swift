import Foundation

enum HookInstallHealth {
    case healthy
    case installed
    case notInstalled
    case error
    case settingsCorrupted
}

enum HookInstallerError: LocalizedError {
    case invalidJSON(URL)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let url):
            return "TraceFence did not modify \(url.path) because it is not a valid JSON object. Repair the file and try again; the existing settings were preserved."
        }
    }
}

actor HookInstaller {
    private let blockStart = "# [AGENTGUARD-START]"
    private let blockEnd = "# [AGENTGUARD-END]"
    private let marker = "agentguard-bridge"
    private let coreClaudeMarker = "TraceFenceClaudeAdapter"
    private let fallbackBridgeMarker = "# AgentGuard fallback bridge v4"

    func ensureBridgeBinary() throws -> String {
        let home = agentRealHomeURL()
        let destDir = home.appendingPathComponent(".agentguard/bin")
        let destPath = destDir.appendingPathComponent("agentguard-bridge")

        if isCurrentBridge(at: destPath) {
            return destPath.path
        }

        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: destPath.path) {
            try FileManager.default.removeItem(at: destPath)
        }

        let resourceURL: URL? = Bundle.main.url(forResource: "agentguard-bridge", withExtension: nil)
                ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/agentguard-bridge")
        guard let url = resourceURL, FileManager.default.fileExists(atPath: url.path) else {
            let pwd = FileManager.default.currentDirectoryPath
            let devBridge = URL(fileURLWithPath: pwd).appendingPathComponent("agentguard-bridge")
            if FileManager.default.fileExists(atPath: devBridge.path) {
                try FileManager.default.copyItem(at: devBridge, to: destPath)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath.path)
                return destPath.path
            }
            try writeFallbackBridge(to: destPath)
            return destPath.path
        }

        try FileManager.default.copyItem(at: url, to: destPath)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath.path)
        return destPath.path
    }

    private func writeFallbackBridge(to destPath: URL) throws {
        let script = [
            "#!/bin/sh",
            fallbackBridgeMarker,
            "log_dir=\"${HOME}/.agentguard\"",
            "log_file=\"${log_dir}/bridge.log\"",
            "socket=\"${AGENTGUARD_SOCKET:-\(AgentHookSocket.path)}\"",
            "payload=\"$(cat)\"",
            "if [ -z \"$payload\" ]; then",
            "  exit 0",
            "fi",
            "",
            "mkdir -p \"$log_dir\" 2>/dev/null || true",
            "agent_pid=\"${PPID:-}\"",
            "tty_path=\"$(tty 2>/dev/null || true)\"",
            "if [ \"$tty_path\" = \"not a tty\" ]; then",
            "  tty_path=\"\"",
            "fi",
            "",
            "enriched_payload=\"$payload\"",
            "if command -v python3 >/dev/null 2>&1; then",
            "  enriched_payload=\"$(AGENTGUARD_PAYLOAD=\"$payload\" AGENTGUARD_PARENT_PID=\"$agent_pid\" AGENTGUARD_TTY=\"$tty_path\" python3 - <<'PY'",
            "import json",
            "import os",
            "import sys",
            "",
            "payload = os.environ.get('AGENTGUARD_PAYLOAD', '')",
            "try:",
            "    event = json.loads(payload)",
            "except Exception:",
            "    print(payload)",
            "    sys.exit(0)",
            "",
            "if isinstance(event, dict):",
            "    parent_pid = os.environ.get('AGENTGUARD_PARENT_PID', '')",
            "    tty = os.environ.get('AGENTGUARD_TTY', '')",
            "    if parent_pid.isdigit():",
            "        event.setdefault('pid', int(parent_pid))",
            "        event.setdefault('process_id', int(parent_pid))",
            "    if tty:",
            "        event.setdefault('tty', tty)",
            "        event.setdefault('terminal', tty)",
            "    if os.environ.get('AGENTGUARD_AGENT'):",
            "        event.setdefault('source_label', os.environ['AGENTGUARD_AGENT'])",
            "    if os.environ.get('AGENTGUARD_ENGINE_ID'):",
            "        event.setdefault('engine_id', os.environ['AGENTGUARD_ENGINE_ID'])",
            "    print(json.dumps(event, separators=(',', ':')))",
            "else:",
            "    print(payload)",
            "PY",
            "  )\" || enriched_payload=\"$payload\"",
            "fi",
            "",
            "if command -v nc >/dev/null 2>&1 && printf '%s\\n' \"$enriched_payload\" | nc -U -w 2 \"$socket\" >/dev/null 2>&1; then",
            "  exit 0",
            "fi",
            "",
            "printf '%s AgentGuard bridge failed to deliver event to %s\\n' \"$(date '+%Y-%m-%d %H:%M:%S')\" \"$socket\" >> \"$log_file\" 2>/dev/null || true",
            "exit 1",
            ""
        ].joined(separator: "\n")
        try script.write(to: destPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destPath.path)
    }

    private func isCurrentBridge(at path: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path.path) else { return false }
        guard let content = try? String(contentsOf: path, encoding: .utf8) else {
            return true
        }
        return !content.hasPrefix("#!/bin/sh") || content.contains(fallbackBridgeMarker)
    }

    private func yamlDoubleQuoted(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "\\": escaped += "\\\\"
            case "\"": escaped += "\\\""
            case "\n": escaped += "\\n"
            case "\r": escaped += "\\r"
            case "\t": escaped += "\\t"
            default: escaped.append(character)
            }
        }
        return "\"\(escaped)\""
    }

    func shellQuote(_ value: String) -> String {
        if value.isEmpty { return "''" }
        if value.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "/._-:=@".contains($0)) }) {
            return value
        }
        return "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    func hookCommand(bridgePath: String, label: String, agentId: String) -> String {
        let env = "/usr/bin/env"
        let socket = "AGENTGUARD_SOCKET=\(shellQuote(AgentHookSocket.path))"
        let agLabel = "AGENTGUARD_AGENT=\(shellQuote(label))"
        let agId = "AGENTGUARD_ENGINE_ID=\(shellQuote(agentId))"
        let bridge = shellQuote(bridgePath)
        return "\(env) \(socket) \(agLabel) \(agId) \(bridge)"
    }

    func injectJSONHooks(at configPath: URL, events: [HookEventDescriptor], hookCommand: String) throws {
        var config = try readJSON(at: configPath)
        var (hooks, preservedHooks) = partitionHooks(in: config)

        for event in events {
            var entries = hooks[event.name] ?? []
            entries.removeAll { entry in
                entryContainsAgentGuardCommand(entry)
            }
            entries.append(jsonHookEntry(for: event, hookCommand: hookCommand))
            hooks[event.name] = entries
        }

        config["hooks"] = mergeHooks(hooks, preserved: preservedHooks)
        try writeJSON(config, at: configPath)
    }

    func removeJSONHooks(at configPath: URL) throws {
        var config = try readJSON(at: configPath)
        var (hooks, preservedHooks) = partitionHooks(in: config)
        guard !hooks.isEmpty else { return }

        for (eventName, var entries) in hooks {
            entries.removeAll { entry in
                entryContainsAgentGuardCommand(entry)
            }
            if entries.isEmpty {
                hooks.removeValue(forKey: eventName)
            } else {
                hooks[eventName] = entries
            }
        }

        config["hooks"] = mergeHooks(hooks, preserved: preservedHooks)
        try writeJSON(config, at: configPath)
    }

    func injectYAMLHooks(at configPath: URL, events: [HookEventDescriptor], hookCommand: String) throws {
        var content = (try? String(contentsOf: configPath, encoding: .utf8)) ?? ""
        content = stripSentinelBlock(from: content)

        var lines = [blockStart, "hooks:"]
        for event in events {
            lines.append("  \(event.name):")
            lines.append("    - command: \(yamlDoubleQuoted(hookCommand))")
        }
        lines.append(blockEnd)

        let result = content.trimmingCharacters(in: .whitespacesAndNewlines) + "\n" + lines.joined(separator: "\n")
        try atomicWrite(result, to: configPath)
    }

    func removeYAMLHooks(at configPath: URL) throws {
        guard FileManager.default.fileExists(atPath: configPath.path) else { return }
        let content = try String(contentsOf: configPath, encoding: .utf8)
        guard content.contains(marker) else { return }
        let stripped = stripSentinelBlock(from: content)
        try atomicWrite(stripped, to: configPath)
    }

    func checkHealth(at configPath: URL) -> HookInstallHealth {
        guard FileManager.default.fileExists(atPath: configPath.path) else { return .notInstalled }
        guard let content = try? String(contentsOf: configPath, encoding: .utf8) else { return .settingsCorrupted }
        if content.contains(marker) || content.contains(coreClaudeMarker) {
            guard bridgeExecutableExists(in: content) else { return .installed }
            if requiresNestedCommandHooks(configPath), hasLegacyFlatAgentGuardHooks(content) {
                return .installed
            }
            return .healthy
        }
        return .notInstalled
    }

    private func bridgeExecutableExists(in content: String) -> Bool {
        if content.contains(coreClaudeMarker) {
            let coreAdapter = agentRealHomeURL()
                .appendingPathComponent("Library/Application Support/TraceFence/Core/adapters/TraceFenceClaudeAdapter")
            if FileManager.default.isExecutableFile(atPath: coreAdapter.path) { return true }
        }
        let pattern = #"(/[^\s"']*agentguard-bridge)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return isCurrentBridge(at: agentRealHomeURL().appendingPathComponent(".agentguard/bin/agentguard-bridge"))
        }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = regex.matches(in: content, range: range)
        if matches.isEmpty {
            return isCurrentBridge(at: agentRealHomeURL().appendingPathComponent(".agentguard/bin/agentguard-bridge"))
        }
        return matches.contains { match in
            guard let pathRange = Range(match.range(at: 1), in: content) else { return false }
            let path = String(content[pathRange]).replacingOccurrences(of: "\\/", with: "/")
            return isCurrentBridge(at: URL(fileURLWithPath: path))
        }
    }

    private func readJSON(at path: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: path.path) else { return [:] }
        let data = try Data(contentsOf: path)
        guard !data.isEmpty,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HookInstallerError.invalidJSON(path)
        }
        return json
    }

    private func partitionHooks(in config: [String: Any]) -> (managed: [String: [[String: Any]]], preserved: [String: Any]) {
        let rawHooks = config["hooks"] as? [String: Any] ?? [:]
        var managed: [String: [[String: Any]]] = [:]
        for (event, value) in rawHooks {
            if let entries = value as? [[String: Any]] {
                managed[event] = entries
            }
        }
        return (managed, rawHooks.filter { managed[$0.key] == nil })
    }

    private func mergeHooks(
        _ managed: [String: [[String: Any]]],
        preserved: [String: Any]
    ) -> [String: Any]? {
        var merged = preserved
        for (event, entries) in managed where !entries.isEmpty {
            merged[event] = entries
        }
        return merged.isEmpty ? nil : merged
    }

    private func jsonHookEntry(for event: HookEventDescriptor, hookCommand: String) -> [String: Any] {
        guard let matcher = event.matcher else {
            return ["command": hookCommand]
        }

        var commandHook: [String: Any] = [
            "type": "command",
            "command": hookCommand,
        ]
        if let timeout = event.timeout {
            commandHook["timeout"] = Int(timeout)
        }
        return [
            "matcher": matcher,
            "hooks": [commandHook],
        ]
    }

    private func entryContainsAgentGuardCommand(_ entry: [String: Any]) -> Bool {
        if let cmd = entry["command"] as? String, cmd.contains(marker) || cmd.contains(coreClaudeMarker) {
            return true
        }
        if let nestedHooks = entry["hooks"] as? [[String: Any]] {
            return nestedHooks.contains { hook in
                guard let command = hook["command"] as? String else { return false }
                return command.contains(marker) || command.contains(coreClaudeMarker)
            }
        }
        return false
    }

    private func requiresNestedCommandHooks(_ configPath: URL) -> Bool {
        let path = configPath.path
        return path.contains("/.claude/") || path.contains("/.qoder/") || path.contains("/.kimi/")
    }

    private func hasLegacyFlatAgentGuardHooks(_ content: String) -> Bool {
        guard let data = content.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: [[String: Any]]] else {
            return false
        }

        for entries in hooks.values {
            for entry in entries {
                if let command = entry["command"] as? String, command.contains(marker) {
                    return true
                }
            }
        }
        return false
    }

    private func writeJSON(_ json: [String: Any], at path: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
        try atomicWrite(String(data: data, encoding: .utf8) ?? "{}", to: path)
    }

    private func stripSentinelBlock(from content: String) -> String {
        var result = ""
        var inside = false
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == blockStart { inside = true; continue }
            if trimmed == blockEnd { inside = false; continue }
            if !inside { result += line + "\n" }
        }
        return result
    }

    private func atomicWrite(_ content: String, to path: URL) throws {
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: path.path) {
            let backupPath = path.appendingPathExtension("agentguard.bak")
            if !FileManager.default.fileExists(atPath: backupPath.path) {
                // Keep the first known-good pre-TraceFence configuration as the
                // recovery copy instead of overwriting it on every hook refresh.
                try FileManager.default.copyItem(at: path, to: backupPath)
            }
        }
        let tmpPath = path.appendingPathExtension("tmp")
        try content.write(to: tmpPath, atomically: true, encoding: .utf8)
        if FileManager.default.fileExists(atPath: path.path) {
            _ = try FileManager.default.replaceItemAt(path, withItemAt: tmpPath)
        } else {
            try FileManager.default.moveItem(at: tmpPath, to: path)
        }
    }
}
