import Foundation
import CryptoKit
import Security
import os

private enum WebhookURLPolicy {
    static func allows(_ url: URL?) -> Bool {
        guard let url,
              url.scheme?.lowercased() == "https",
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }

        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") {
            return false
        }
        var unwrapped = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if unwrapped.hasPrefix("::ffff:") {
            unwrapped = String(unwrapped.dropFirst("::ffff:".count))
        }
        if unwrapped == "::" || unwrapped == "::1" || unwrapped.hasPrefix("fe80:") || unwrapped.hasPrefix("fc") || unwrapped.hasPrefix("fd") || unwrapped.hasPrefix("ff") {
            return false
        }
        if unwrapped.allSatisfy(\.isNumber) || unwrapped.hasPrefix("0x") {
            return false
        }
        let octets = unwrapped.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4 {
            guard octets.allSatisfy({ (0...255).contains($0) }) else { return false }
            switch (octets[0], octets[1]) {
            case (0, _), (10, _), (127, _), (169, 254), (192, 168):
                return false
            case (100, 64...127), (172, 16...31), (198, 18...19):
                return false
            case (224...255, _):
                return false
            default:
                break
            }
        }
        return true
    }
}

private final class WebhookSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(WebhookURLPolicy.allows(request.url) ? request : nil)
    }
}

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
    private static let log = Logger(subsystem: "com.tracefence.app", category: "webhook")
    private var config: WebhookConfig = WebhookConfig()
    private let configPath = NSHomeDirectory() + "/.tracefence_webhook_config.json"
    private let keychainService = "com.tracefence.webhook"
    private let keychainAccount = "hmac-secret"
    private let sessionDelegate: WebhookSessionDelegate
    private var session: URLSession

    private var allowsKeychainAccess: Bool {
        !ProcessInfo.processInfo.arguments.contains("--tracefence-ui-preview") &&
            Bundle.main.bundleIdentifier != "com.tracefence.uipreview"
    }

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        let delegate = WebhookSessionDelegate()
        sessionDelegate = delegate
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        Task { await loadConfig() }
    }

    func notify(for event: AgentHookEvent) {
        guard config.enabled, !config.url.isEmpty else { return }
        guard let url = URL(string: config.url), WebhookURLPolicy.allows(url) else { return }

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
        var candidate = newConfig
        if let secret = newConfig.secret?.trimmingCharacters(in: .whitespacesAndNewlines), !secret.isEmpty {
            guard storeSecret(secret) else { return }
            candidate.secret = secret
        } else {
            deleteSecret()
            candidate.secret = nil
        }
        config = candidate
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
                // The same backoff below applies to transport and HTTP failures.
            }
            if attempt < retryCount {
                let multiplier = UInt64(1 << min(attempt, 5))
                try? await Task.sleep(nanoseconds: config.retryDelayMs * 1_000_000 * multiplier)
            }
        }
        Self.log.error("Webhook delivery failed after \(retryCount + 1) attempts")
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
        let key = SymmetricKey(data: Data(secret.utf8))
        let signature = HMAC<SHA256>.authenticationCode(for: body, using: key)
        return "sha256=" + signature.map { String(format: "%02x", $0) }.joined()
    }

    private func loadConfig() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
              let decoded = try? JSONDecoder().decode(WebhookConfig.self, from: data) else { return }
        config = decoded
        if let legacySecret = decoded.secret?.trimmingCharacters(in: .whitespacesAndNewlines), !legacySecret.isEmpty {
            guard storeSecret(legacySecret) else { return }
        }
        config.secret = loadSecret() ?? decoded.secret
        if decoded.secret?.isEmpty == false {
            saveConfig()
        }
    }

    private func saveConfig() {
        var metadata = config
        metadata.secret = nil
        guard let data = try? JSONEncoder().encode(metadata) else { return }
        let url = URL(fileURLWithPath: configPath)
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func loadSecret() -> String? {
        guard allowsKeychainAccess else { return nil }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let secret = String(data: data, encoding: .utf8),
              !secret.isEmpty else { return nil }
        return secret
    }

    @discardableResult
    private func storeSecret(_ secret: String) -> Bool {
        guard allowsKeychainAccess else { return false }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        let attributes: [CFString: Any] = [kSecValueData: Data(secret.utf8)]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData] = Data(secret.utf8)
        item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private func deleteSecret() {
        guard allowsKeychainAccess else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: keychainService,
            kSecAttrAccount: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
