import Foundation

enum AgentHookEvent {
    case sessionStart(sessionId: String, project: String, cwd: String, terminal: String, agentType: String)
    case sessionEnd(sessionId: String)
    case processing(sessionId: String, description: String)
    case toolUse(sessionId: String, toolName: String, toolInput: String, toolTarget: String?, status: String)
    case permissionRequest(sessionId: String, toolName: String, diff: String?, options: [String]?)
    case askQuestion(sessionId: String, question: String, options: [String], descriptions: [String], header: String?, multiSelect: Bool, questions: [QuestionItem])
    case planApproval(sessionId: String, title: String, content: String, permissions: [String])
    case taskComplete(sessionId: String, summary: String)
    case assistantResponseComplete(sessionId: String, text: String)
    case agentError(sessionId: String, message: String)
    case interrupt(sessionId: String)
    case tokenUsage(sessionId: String, input: UInt64, output: UInt64, cacheRead: UInt64, cacheCreate: UInt64)
    case rateLimitUpdate(sessionId: String, fiveHourUsage: Double, fiveHourRemaining: String, sevenDayUsage: Double, sevenDayRemaining: String, statusLineText: String?, totalInputTokens: UInt64?, totalOutputTokens: UInt64?, contextWindowSize: UInt64?, contextUsedPct: Double?, lastMainAgentAt: Int64?, cacheTtlMs: Int64?)
    case notification(sessionId: String, message: String, status: String?)
    case subagentStart(sessionId: String, agentId: String, name: String?, description: String, agentType: String?, transcriptPath: String?)
    case subagentStop(sessionId: String, agentId: String, status: String, name: String?, agentType: String?, transcriptPath: String?, agentTranscriptPath: String?, lastAssistantMessage: String?)
    case shellExecutionStart(sessionId: String, command: String, cwd: String)
    case shellExecutionEnd(sessionId: String, command: String, exitCode: Int32?, stdout: String?, stderr: String?, durationMs: UInt64)
    case mcpExecutionStart(sessionId: String, serverName: String, toolName: String, arguments: String)
    case mcpExecutionEnd(sessionId: String, serverName: String, toolName: String, result: String?, error: String?, durationMs: UInt64)
    case agentResponse(sessionId: String, content: String, contentType: String)
    case agentThought(sessionId: String, thought: String)

    static func parse(from raw: [String: Any]) -> AgentHookEvent? {
        guard let eventName = raw["event"] as? String else { return nil }
        let sessionId = stringValue(raw, keys: ["session_id", "sessionId", "conversation_id", "conversationId", "id"])
        let cwd = stringValue(raw, keys: ["cwd", "working_directory", "workingDirectory", "project_path", "projectPath"])
        let project = cwd.split(separator: "/").last.map(String.init) ?? cwd
        let tty = stringValue(raw, keys: ["tty", "terminal"])
        let agent = stringValue(raw, keys: ["agent", "source_label", "sourceLabel", "provider"], fallback: "unknown")
        let toolName = stringValue(raw, keys: ["tool", "tool_name", "toolName", "name"])
        let toolInput = stringValue(raw, keys: ["tool_input", "toolInput", "input", "arguments", "args"])
        let status = stringValue(raw, keys: ["status"])

        switch eventName {
        case "SessionStart", "session_start":
            return .sessionStart(sessionId: sessionId, project: project, cwd: cwd, terminal: tty, agentType: agent)
        case "SessionEnd", "session_end":
            return .sessionEnd(sessionId: sessionId)
        case "UserPromptSubmit", "user_prompt_submit":
            let desc = raw["description"] as? String ?? "Processing user input"
            return .processing(sessionId: sessionId, description: desc)
        case "PreToolUse", "pre_tool_use":
            return .toolUse(sessionId: sessionId, toolName: toolName, toolInput: toolInput, toolTarget: extractToolTarget(toolName: toolName, toolInput: toolInput), status: "running")
        case "PostToolUse", "post_tool_use":
            return .toolUse(sessionId: sessionId, toolName: toolName, toolInput: toolInput, toolTarget: extractToolTarget(toolName: toolName, toolInput: toolInput), status: "success")
        case "PostToolUseFailure", "post_tool_use_failure", "PermissionDenied", "permission_denied":
            return .toolUse(sessionId: sessionId, toolName: toolName, toolInput: toolInput, toolTarget: extractToolTarget(toolName: toolName, toolInput: toolInput), status: "error")
        case "PermissionRequest", "permission_request":
            let diff = raw["diff"] as? String
            let options = raw["options"] as? [String]
            return .permissionRequest(sessionId: sessionId, toolName: toolName, diff: diff, options: options)
        case "AskQuestion", "ask_question":
            let question = raw["question"] as? String ?? ""
            let options = raw["options"] as? [String] ?? []
            let descriptions = raw["descriptions"] as? [String] ?? []
            let header = raw["header"] as? String
            let multiSelect = raw["multi_select"] as? Bool ?? raw["multiSelect"] as? Bool ?? false
            let questions = parseQuestions(from: raw)
            return .askQuestion(sessionId: sessionId, question: question, options: options, descriptions: descriptions, header: header, multiSelect: multiSelect, questions: questions)
        case "PlanApproval", "plan_approval":
            let title = raw["plan_title"] as? String ?? raw["planTitle"] as? String ?? "Plan"
            let content = raw["plan_content"] as? String ?? raw["planContent"] as? String ?? raw["plan"] as? String ?? ""
            let permissions = (raw["requested_permissions"] as? [String]) ?? (raw["allowedPrompts"] as? [String]) ?? []
            return .planApproval(sessionId: sessionId, title: title, content: content, permissions: permissions)
        case "TaskComplete", "task_complete":
            let summary = raw["summary"] as? String ?? "Task completed"
            return .taskComplete(sessionId: sessionId, summary: summary)
        case "AssistantResponseComplete", "assistant_response_complete":
            let text = raw["text"] as? String ?? ""
            return .assistantResponseComplete(sessionId: sessionId, text: text)
        case "Error", "error":
            let message = raw["message"] as? String ?? ""
            return .agentError(sessionId: sessionId, message: message)
        case "Interrupt", "interrupt":
            return .interrupt(sessionId: sessionId)
        case "TokenUsage", "token_usage":
            let input = raw["input"] as? UInt64 ?? raw["input_tokens"] as? UInt64 ?? 0
            let output = raw["output"] as? UInt64 ?? raw["output_tokens"] as? UInt64 ?? 0
            let cacheRead = raw["cache_read"] as? UInt64 ?? 0
            let cacheCreate = raw["cache_create"] as? UInt64 ?? 0
            return .tokenUsage(sessionId: sessionId, input: input, output: output, cacheRead: cacheRead, cacheCreate: cacheCreate)
        case "RateLimitsUpdate", "StatusLineUpdate", "rate_limits_update", "status_line_update":
            let rateLimits = raw["rateLimits"] as? [String: Any] ?? raw["rate_limits"] as? [String: Any] ?? [:]
            let fiveHour = rateLimits["fiveHour"] as? [String: Any] ?? rateLimits["five_hour"] as? [String: Any] ?? [:]
            let sevenDay = rateLimits["sevenDay"] as? [String: Any] ?? rateLimits["seven_day"] as? [String: Any] ?? [:]
            let fiveHourUsage = fiveHour["used_percent"] as? Double ?? fiveHour["usedPercent"] as? Double ?? 0
            let fiveHourRemaining = fiveHour["remaining"] as? String ?? fiveHour["remaining_label"] as? String ?? ""
            let sevenDayUsage = sevenDay["used_percent"] as? Double ?? sevenDay["usedPercent"] as? Double ?? 0
            let sevenDayRemaining = sevenDay["remaining"] as? String ?? sevenDay["remaining_label"] as? String ?? ""
            let statusLineText = raw["status_line_text"] as? String ?? raw["statusLineText"] as? String
            let totalInput = raw["total_input_tokens"] as? UInt64 ?? raw["totalInputTokens"] as? UInt64
            let totalOutput = raw["total_output_tokens"] as? UInt64 ?? raw["totalOutputTokens"] as? UInt64
            let ctxWindowSize = raw["context_window_size"] as? UInt64 ?? raw["contextWindowSize"] as? UInt64
            let ctxUsedPct = raw["context_used_percentage"] as? Double ?? raw["contextUsedPercentage"] as? Double
            let lastMainAt = raw["last_main_agent_at"] as? Int64 ?? raw["lastMainAgentAt"] as? Int64
            let cacheTtl = raw["cache_ttl_ms"] as? Int64 ?? raw["cacheTtlMs"] as? Int64
            return .rateLimitUpdate(sessionId: sessionId, fiveHourUsage: fiveHourUsage, fiveHourRemaining: fiveHourRemaining, sevenDayUsage: sevenDayUsage, sevenDayRemaining: sevenDayRemaining, statusLineText: statusLineText, totalInputTokens: totalInput, totalOutputTokens: totalOutput, contextWindowSize: ctxWindowSize, contextUsedPct: ctxUsedPct, lastMainAgentAt: lastMainAt, cacheTtlMs: cacheTtl)
        case "Notification", "notification":
            let message = raw["message"] as? String ?? ""
            let notifStatus = raw["status"] as? String
            return .notification(sessionId: sessionId, message: message, status: notifStatus)
        case "SubagentStart", "subagent_start":
            let agentId = raw["agent_id"] as? String ?? raw["agentId"] as? String ?? ""
            let name = raw["name"] as? String
            let desc = raw["description"] as? String ?? ""
            let agentType = raw["agent_type"] as? String ?? raw["agentType"] as? String
            let path = raw["transcript_path"] as? String ?? raw["transcriptPath"] as? String
            return .subagentStart(sessionId: sessionId, agentId: agentId, name: name, description: desc, agentType: agentType, transcriptPath: path)
        case "SubagentStop", "SubagentEnd", "subagent_stop", "subagent_end":
            let agentId = raw["agent_id"] as? String ?? raw["agentId"] as? String ?? ""
            let subStatus = status.isEmpty ? "completed" : status
            let name = raw["name"] as? String
            let agentType = raw["agent_type"] as? String ?? raw["agentType"] as? String
            let path = raw["transcript_path"] as? String ?? raw["transcriptPath"] as? String
            let agentPath = raw["agent_transcript_path"] as? String ?? raw["agentTranscriptPath"] as? String
            let lastMsg = raw["last_assistant_message"] as? String ?? raw["lastAssistantMessage"] as? String
            return .subagentStop(sessionId: sessionId, agentId: agentId, status: subStatus, name: name, agentType: agentType, transcriptPath: path, agentTranscriptPath: agentPath, lastAssistantMessage: lastMsg)
        case "ShellExecutionStart", "shell_execution_start":
            let command = raw["command"] as? String ?? ""
            return .shellExecutionStart(sessionId: sessionId, command: command, cwd: cwd)
        case "ShellExecutionEnd", "shell_execution_end":
            let command = raw["command"] as? String ?? ""
            let exitCode = raw["exit_code"] as? Int32 ?? raw["exitCode"] as? Int32
            let stdout = raw["stdout"] as? String
            let stderr = raw["stderr"] as? String
            let duration = raw["duration_ms"] as? UInt64 ?? raw["durationMs"] as? UInt64 ?? 0
            return .shellExecutionEnd(sessionId: sessionId, command: command, exitCode: exitCode, stdout: stdout, stderr: stderr, durationMs: duration)
        case "MCPExecutionStart", "mcp_execution_start":
            let server = raw["server_name"] as? String ?? raw["serverName"] as? String ?? ""
            let mcpTool = raw["tool_name"] as? String ?? raw["toolName"] as? String ?? ""
            let args = raw["arguments"] as? String ?? ""
            return .mcpExecutionStart(sessionId: sessionId, serverName: server, toolName: mcpTool, arguments: args)
        case "MCPExecutionEnd", "mcp_execution_end":
            let server = raw["server_name"] as? String ?? raw["serverName"] as? String ?? ""
            let mcpTool = raw["tool_name"] as? String ?? raw["toolName"] as? String ?? ""
            let result = raw["result"] as? String
            let error = raw["error"] as? String
            let duration = raw["duration_ms"] as? UInt64 ?? raw["durationMs"] as? UInt64 ?? 0
            return .mcpExecutionEnd(sessionId: sessionId, serverName: server, toolName: mcpTool, result: result, error: error, durationMs: duration)
        case "AgentResponse", "agent_response":
            let content = raw["content"] as? String ?? ""
            let contentType = raw["content_type"] as? String ?? raw["contentType"] as? String ?? "text"
            return .agentResponse(sessionId: sessionId, content: content, contentType: contentType)
        case "AgentThought", "agent_thought":
            let thought = raw["thought"] as? String ?? ""
            return .agentThought(sessionId: sessionId, thought: thought)
        default:
            return nil
        }
    }

    private static func stringValue(_ raw: [String: Any], keys: [String], fallback: String = "") -> String {
        for key in keys {
            if let value = raw[key] as? String, !value.isEmpty { return value }
            if let value = raw[key],
               JSONSerialization.isValidJSONObject(value),
               let data = try? JSONSerialization.data(withJSONObject: value),
               let string = String(data: data, encoding: .utf8),
               !string.isEmpty {
                return string
            }
        }
        return fallback
    }

    private static func extractToolTarget(toolName: String, toolInput: String) -> String? {
        guard let data = toolInput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["file_path"] as? String
            ?? json["filePath"] as? String
            ?? json["path"] as? String
            ?? json["command"] as? String
    }

    static func parseQuestions(from raw: [String: Any]) -> [QuestionItem] {
        guard let questionsArray = raw["questions"] as? [[String: Any]] else { return [] }
        return questionsArray.compactMap { q in
            guard let text = q["question"] as? String else { return nil }
            let options = (q["options"] as? [[String: Any]])?.compactMap { opt -> QuestionOption? in
                guard let label = opt["label"] as? String else { return nil }
                return QuestionOption(label: label, description: opt["description"] as? String)
            } ?? []
            return QuestionItem(
                id: q["id"] as? String,
                question: text,
                header: q["header"] as? String,
                options: options,
                multiSelect: q["multiSelect"] as? Bool ?? false
            )
        }
    }

    var sessionId: String {
        switch self {
        case .sessionStart(let id, _, _, _, _): return id
        case .sessionEnd(let id): return id
        case .processing(let id, _): return id
        case .toolUse(let id, _, _, _, _): return id
        case .permissionRequest(let id, _, _, _): return id
        case .askQuestion(let id, _, _, _, _, _, _): return id
        case .planApproval(let id, _, _, _): return id
        case .taskComplete(let id, _): return id
        case .assistantResponseComplete(let id, _): return id
        case .agentError(let id, _): return id
        case .interrupt(let id): return id
        case .tokenUsage(let id, _, _, _, _): return id
        case .rateLimitUpdate(let id, _, _, _, _, _, _, _, _, _, _, _): return id
        case .notification(let id, _, _): return id
        case .subagentStart(let id, _, _, _, _, _): return id
        case .subagentStop(let id, _, _, _, _, _, _, _): return id
        case .shellExecutionStart(let id, _, _): return id
        case .shellExecutionEnd(let id, _, _, _, _, _): return id
        case .mcpExecutionStart(let id, _, _, _): return id
        case .mcpExecutionEnd(let id, _, _, _, _, _): return id
        case .agentResponse(let id, _, _): return id
        case .agentThought(let id, _): return id
        }
    }
}

struct QuestionItem: Codable, Sendable {
    var id: String?
    var question: String
    var header: String?
    var options: [QuestionOption]
    var multiSelect: Bool
}

struct QuestionOption: Codable, Sendable {
    var label: String
    var description: String?
}

struct PermissionDecision {
    var decision: String
    var reason: String?
    var always: Bool?
    var updatedPermissions: [[String: AnyCodable]]? = nil

    static let allow = PermissionDecision(decision: "allow")
    static let deny = PermissionDecision(decision: "deny", reason: "Blocked by TraceFence")
    static func deny(reason: String?) -> PermissionDecision {
        PermissionDecision(decision: "deny", reason: reason?.isEmpty == false ? reason : "Blocked by TraceFence")
    }
    static func allowAlways(reason: String?) -> PermissionDecision {
        PermissionDecision(decision: "allow", reason: reason, always: true)
    }
    static let openExternal = PermissionDecision(decision: "external_open")
    static let externalHandled = PermissionDecision(decision: "external_handled")
}

struct PermissionResponse: Codable {
    var decision: String
    var reason: String?
    var always: Bool?
    var hookSpecificOutput: HookSpecificPermissionOutput?
    var permissionDecision: String?
    var permissionDecisionReason: String?
}

struct QuestionResponse: Codable {
    var answer: String
}

struct PlanResponse: Codable {
    var mode: String
    var message: String?
}

struct HookSpecificPermissionOutput: Codable {
    var hookEventName: String
    var decision: HookPermissionDecision
}

struct HookPermissionDecision: Codable {
    var behavior: String
    var message: String?
    var updatedPermissions: [[String: AnyCodable]]?
}

struct AnyCodable: Codable {
    var value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        case let codable as AnyCodable:
            try codable.encode(to: encoder)
        default:
            try container.encode(String(describing: value))
        }
    }
}
