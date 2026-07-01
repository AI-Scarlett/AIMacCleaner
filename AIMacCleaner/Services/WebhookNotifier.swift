import Foundation

struct WebhookConfig: Codable {
    var enabled: Bool = false
    var url: String = ""
    var secret: String?
    var eventFilter: [String] = []
    var retryCount: Int = 3
    var retryDelayMs: UInt64 = 1000
    var timeoutSeconds: Double = 10
}

struct WebhookPayload: Codable {
    var event: String
    var sessionId: String
    var timestamp: String
    var agent: String?
    var data: [String: String]
}

actor WebhookNotifier {
    private var config: WebhookConfig = WebhookConfig()
    private let configPath = NSHomeDirectory() + "/.tracefence_webhook_config.json"
    private var session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
        Task { await loadConfig() }
    }

    func notify(for event: AgentHookEvent) {
        guard config.enabled, !config.url.isEmpty else { return }
        guard let url = URL(string: config.url) else { return }

        let eventName = eventName(for: event)
        if !config.eventFilter.isEmpty && !config.eventFilter.contains(eventName) {
            return
        }

        let payload = buildPayload(for: event)

        Task {
            await sendPayload(payload, to: url, retryCount: config.retryCount)
        }
    }

    func updateConfig(_ newConfig: WebhookConfig) {
        config = newConfig
        saveConfig()
    }

    func getConfig() -> WebhookConfig {
        config
    }

    private func sendPayload(_ payload: WebhookPayload, to url: URL, retryCount: Int) async {
        guard let body = try? JSONEncoder().encode(payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("TraceFence/3.1", forHTTPHeaderField: "User-Agent")
        request.httpBody = body

        if let secret = config.secret, !secret.isEmpty {
            let signature = hmacSHA256(body: body, secret: secret)
            request.setValue(signature, forHTTPHeaderField: "X-TraceFence-Signature")
        }

        for attempt in 0...retryCount {
            do {
                let (_, response) = try await session.data(for: request)
                if let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    return
                }
            } catch {
                if attempt < retryCount {
                    try? await Task.sleep(nanoseconds: config.retryDelayMs * 1_000_000)
                }
            }
        }
    }

    private func buildPayload(for event: AgentHookEvent) -> WebhookPayload {
        let formatter = ISO8601DateFormatter()
        var data: [String: String] = [:]

        switch event {
        case .sessionStart(_, let project, let cwd, _, let agentType):
            data = ["project": project, "cwd": cwd, "agent": agentType]
        case .sessionEnd:
            data = [:]
        case .toolUse(_, let toolName, _, let toolTarget, let status):
            data = ["tool": toolName, "status": status]
            if let target = toolTarget { data["target"] = target }
        case .permissionRequest(_, let toolName, let diff, _):
            data = ["tool": toolName]
            if let d = diff { data["diff"] = d }
        case .askQuestion(_, let question, _, _, _, _, _):
            data = ["question": question]
        case .planApproval(_, let title, let content, _):
            data = ["title": title, "content": content.prefix(500).description]
        case .taskComplete(_, let summary):
            data = ["summary": summary]
        case .agentError(_, let message):
            data = ["message": message]
        case .tokenUsage(_, let input, let output, _, _):
            data = ["input_tokens": "\(input)", "output_tokens": "\(output)"]
        case .shellExecutionStart(_, let command, _):
            data = ["command": command]
        case .subagentStart(_, let agentId, let name, _, _, _):
            data = ["agent_id": agentId]
            if let n = name { data["name"] = n }
        default:
            data = [:]
        }

        return WebhookPayload(
            event: eventName(for: event),
            sessionId: event.sessionId,
            timestamp: formatter.string(from: Date()),
            agent: nil,
            data: data
        )
    }

    private func eventName(for event: AgentHookEvent) -> String {
        switch event {
        case .sessionStart: return "session_start"
        case .sessionEnd: return "session_end"
        case .processing: return "processing"
        case .toolUse: return "tool_use"
        case .permissionRequest: return "permission_request"
        case .askQuestion: return "ask_question"
        case .planApproval: return "plan_approval"
        case .taskComplete: return "task_complete"
        case .assistantResponseComplete: return "response"
        case .agentError: return "error"
        case .interrupt: return "interrupt"
        case .tokenUsage: return "token_usage"
        case .rateLimitUpdate: return "rate_limit_update"
        case .notification: return "notification"
        case .subagentStart: return "subagent_start"
        case .subagentStop: return "subagent_stop"
        case .shellExecutionStart: return "shell_start"
        case .shellExecutionEnd: return "shell_end"
        case .mcpExecutionStart: return "mcp_start"
        case .mcpExecutionEnd: return "mcp_end"
        case .agentResponse: return "agent_response"
        case .agentThought: return "agent_thought"
        }
    }

    private func hmacSHA256(body: Data, secret: String) -> String {
        return "sha256=none"
    }

    private func loadConfig() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let decoded = try? JSONDecoder().decode(WebhookConfig.self, from: data) else { return }
        config = decoded
    }

    private func saveConfig() {
        guard let data = try? JSONEncoder().encode(config) else { return }
        try? data.write(to: URL(fileURLWithPath: configPath))
    }
}
