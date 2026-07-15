import Foundation

enum TraceFenceAccessEndpointKind: String, Codable, Equatable {
    case local
    case bonjour
    case vpn
    case ddns
    case tunnel
    case manual
    case lastKnown
}

struct TraceFenceAccessEndpoint: Codable, Identifiable, Equatable {
    var id: UUID
    var url: String
    var label: String
    var kind: TraceFenceAccessEndpointKind
    var lastSucceededAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        url: String,
        label: String,
        kind: TraceFenceAccessEndpointKind,
        lastSucceededAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.url = url
        self.label = label
        self.kind = kind
        self.lastSucceededAt = lastSucceededAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case label
        case kind
        case lastSucceededAt
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        url = try container.decode(String.self, forKey: .url)
        label = try container.decodeIfPresent(String.self, forKey: .label) ?? "连接地址"
        kind = try container.decodeIfPresent(TraceFenceAccessEndpointKind.self, forKey: .kind) ?? .manual
        lastSucceededAt = Self.decodeFlexibleDate(container, key: .lastSucceededAt)
        createdAt = Self.decodeFlexibleDate(container, key: .createdAt) ?? Date()
    }

    private static func decodeFlexibleDate(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> Date? {
        if let date = try? container.decode(Date.self, forKey: key) {
            return date
        }
        if let text = try? container.decode(String.self, forKey: key) {
            return ISO8601DateFormatter().date(from: text)
        }
        return nil
    }
}

struct TraceFenceConnection: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var endpoint: String
    var token: String
    var channelHint: String?
    var bonjourHostName: String?
    var bonjourServiceName: String?
    var localHostName: String?
    var localAddresses: [String]
    var accessEndpoints: [TraceFenceAccessEndpoint]
    var lastResolvedEndpoint: String?
    var importedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "我的 Mac",
        endpoint: String,
        token: String,
        channelHint: String? = nil,
        bonjourHostName: String? = nil,
        bonjourServiceName: String? = nil,
        localHostName: String? = nil,
        localAddresses: [String] = [],
        accessEndpoints: [TraceFenceAccessEndpoint] = [],
        lastResolvedEndpoint: String? = nil,
        importedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.endpoint = endpoint
        self.token = token
        self.channelHint = channelHint
        self.bonjourHostName = bonjourHostName
        self.bonjourServiceName = bonjourServiceName
        self.localHostName = localHostName
        self.localAddresses = localAddresses
        self.accessEndpoints = accessEndpoints
        self.lastResolvedEndpoint = lastResolvedEndpoint
        self.importedAt = importedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case endpoint
        case token
        case channelHint
        case bonjourHostName
        case bonjourServiceName
        case localHostName
        case localAddresses
        case accessEndpoints
        case lastResolvedEndpoint
        case importedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "我的 Mac"
        endpoint = try container.decode(String.self, forKey: .endpoint)
        token = try container.decode(String.self, forKey: .token)
        channelHint = try container.decodeIfPresent(String.self, forKey: .channelHint)
        bonjourHostName = try container.decodeIfPresent(String.self, forKey: .bonjourHostName)
        bonjourServiceName = try container.decodeIfPresent(String.self, forKey: .bonjourServiceName)
        localHostName = try container.decodeIfPresent(String.self, forKey: .localHostName)
        localAddresses = try container.decodeIfPresent([String].self, forKey: .localAddresses) ?? []
        accessEndpoints = try container.decodeIfPresent([TraceFenceAccessEndpoint].self, forKey: .accessEndpoints) ?? []
        lastResolvedEndpoint = try container.decodeIfPresent(String.self, forKey: .lastResolvedEndpoint)
        importedAt = try container.decodeIfPresent(Date.self, forKey: .importedAt) ?? Date()
    }

    var maskedToken: String {
        guard token.count > 10 else { return "已保存".tfLocalized }
        return "\(token.prefix(6))...\(token.suffix(4))"
    }

    var candidateEndpoints: [String] {
        var endpointText = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !endpointText.contains("://") {
            endpointText = "http://\(endpointText)"
        }

        guard let primaryComponents = URLComponents(string: endpointText) else {
            return [endpoint]
        }
        let scheme = primaryComponents.scheme ?? "http"
        let port = primaryComponents.port ?? (scheme == "https" ? 443 : 17895)
        let primaryHost = primaryComponents.host ?? ""
        let localHosts = [bonjourHostName, localHostName, bonjourServiceName]
            .compactMap { $0 }
            .flatMap { host -> [String] in
                guard !host.isEmpty else { return [] }
                if host.contains(".") || host.contains(":") { return [host] }
                return [host, "\(host).local"]
            } + localAddresses
        let orderedHosts = primaryHost.tfIsPrivateNetworkHost
            ? localHosts + [primaryHost]
            : [primaryHost] + localHosts

        var candidates: [String] = []
        for endpoint in prioritizedAccessEndpoints {
            let normalized = Self.normalizedEndpoint(endpoint.url)
            guard !normalized.isEmpty, !candidates.contains(normalized) else { continue }
            candidates.append(normalized)
        }
        for host in orderedHosts where !host.isEmpty {
            var components = URLComponents()
            components.scheme = scheme
            components.host = host
            components.port = port
            guard let value = components.string, !candidates.contains(value) else { continue }
            candidates.append(value)
        }
        if !candidates.contains(endpointText) {
            candidates.append(endpointText)
        }

        let standardCandidates = candidates
        var coreCandidates = standardCandidates.filter { endpoint in
            URLComponents(string: endpoint)?.port == 17896
        }
        for endpoint in standardCandidates {
            guard var components = URLComponents(string: endpoint),
                  components.scheme == "http",
                  let host = components.host,
                  host.tfIsPrivateNetworkHost,
                  components.port != 17896 else { continue }
            components.port = 17896
            guard let coreEndpoint = components.string,
                  !coreCandidates.contains(coreEndpoint) else { continue }
            coreCandidates.append(coreEndpoint)
        }
        return coreCandidates + standardCandidates.filter { !coreCandidates.contains($0) }
    }

    var prioritizedAccessEndpoints: [TraceFenceAccessEndpoint] {
        accessEndpoints.sorted { lhs, rhs in
            switch (lhs.lastSucceededAt, rhs.lastSucceededAt) {
            case let (l?, r?) where l != r:
                return l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return priority(lhs.kind) < priority(rhs.kind)
            }
        }
    }

    mutating func rememberSuccessfulEndpoint(_ endpoint: String, kind: TraceFenceAccessEndpointKind = .lastKnown, label: String = "上次成功") {
        let normalized = Self.normalizedEndpoint(endpoint)
        guard !normalized.isEmpty else { return }
        lastResolvedEndpoint = normalized
        self.endpoint = normalized
        if let index = accessEndpoints.firstIndex(where: { Self.normalizedEndpoint($0.url) == normalized }) {
            accessEndpoints[index].lastSucceededAt = Date()
        } else {
            accessEndpoints.append(TraceFenceAccessEndpoint(
                url: normalized,
                label: label,
                kind: kind,
                lastSucceededAt: Date()
            ))
        }
        accessEndpoints = Array(prioritizedAccessEndpoints.prefix(16))
    }

    mutating func mergeLocalAddresses(_ addresses: [String], port: Int) {
        for address in addresses where !address.isEmpty {
            if !localAddresses.contains(address) {
                localAddresses.append(address)
            }
            var components = URLComponents()
            components.scheme = "http"
            components.host = address
            components.port = port
            guard let url = components.string else { continue }
            addAccessEndpoint(url: url, label: "局域网地址", kind: .local)
        }
        localAddresses = Array(NSOrderedSet(array: localAddresses)) as? [String] ?? localAddresses
    }

    mutating func addAccessEndpoint(url: String, label: String, kind: TraceFenceAccessEndpointKind) {
        let normalized = Self.normalizedEndpoint(url)
        guard !normalized.isEmpty else { return }
        if accessEndpoints.contains(where: { Self.normalizedEndpoint($0.url) == normalized }) {
            return
        }
        accessEndpoints.append(TraceFenceAccessEndpoint(url: normalized, label: label, kind: kind))
    }

    private static func normalizedEndpoint(_ endpoint: String) -> String {
        var text = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "" }
        if !text.contains("://") {
            text = "http://\(text)"
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }

    private func priority(_ kind: TraceFenceAccessEndpointKind) -> Int {
        switch kind {
        case .lastKnown: return 0
        case .bonjour: return 1
        case .vpn: return 2
        case .tunnel: return 3
        case .ddns: return 4
        case .local: return 5
        case .manual: return 6
        }
    }
}

struct TraceFencePairingPayload: Decodable {
    var version: Int?
    var service: String?
    var endpoint: String
    var token: String
    var port: Int?
    var channel: String?
    var noBackend: Bool?
    var localHostName: String?
    var bonjourHostName: String?
    var bonjourServiceName: String?
    var localAddresses: [String]?
    var accessEndpoints: [TraceFenceAccessEndpoint]?
    var requirements: [TraceFenceConnectivityRequirement]?
}

struct TraceFenceConnectivityRequirement: Codable, Identifiable, Equatable {
    var mode: String
    var requirement: String
    var securityNote: String

    var id: String { mode }
}

struct TraceFenceStatusResponse: Decodable, Equatable {
    var ok: Bool
    var version: Int?
    var app: AppMetadata?
    var gateway: GatewayMetadata?
    var subscription: SubscriptionMetadata?
    var system: SystemMetadata?
    var connectivity: ConnectivityMetadata?
    var agentCore: AgentCoreMetadata?
    var command: String?

    struct AppMetadata: Decodable, Equatable {
        var name: String?
        var version: String?
        var build: String?
    }

    struct GatewayMetadata: Decodable, Equatable {
        var running: Bool?
        var endpoint: String?
        var port: Int?
        var lastRequest: String?
    }

    struct SubscriptionMetadata: Decodable, Equatable {
        var channel: String?
        var tier: String?
        var active: Bool?
        var enhanced: Bool?
    }

    struct SystemMetadata: Decodable, Equatable {
        var monitoring: Bool?
        var disk: DiskMetadata?
        var hardware: HardwareMetadata?
    }

    struct DiskMetadata: Decodable, Equatable {
        var totalGB: Double?
        var usedGB: Double?
        var freeGB: Double?
        var usedPercent: Double?
    }

    struct HardwareMetadata: Decodable, Equatable {
        var cpuUsage: Double?
        var memoryPressure: Double?
        var processCount: Int?
        var uptimeSeconds: Int64?
    }

    struct ConnectivityMetadata: Decodable, Equatable {
        var noBackend: Bool?
        var localAddresses: [String]?
        var modes: [TraceFenceConnectivityMode]?
    }

    struct AgentCoreMetadata: Decodable, Equatable {
        var connected: Bool?
        var coreVersion: String?
        var protocolVersion: Int?
        var adapters: [AgentCoreAdapterMetadata]?
        var message: String?
    }

    struct AgentCoreAdapterMetadata: Decodable, Equatable, Identifiable {
        var id: String
        var version: String?
        var displayName: String?
        var capabilities: [String]?
        var operational: Bool?
        var authenticated: Bool?
        var cliVersion: String?
        var transport: String?
        var desktopDetected: Bool?
        var installed: Bool?
        var applicationInstalled: Bool?
        var commandInstalled: Bool?
        var dataPresent: Bool?
        var controlAvailable: Bool?
        var message: String?

        var isInstalledForSessionDisplay: Bool {
            if applicationInstalled == true || commandInstalled == true || desktopDetected == true || controlAvailable == true {
                return true
            }
            if id.lowercased() == "codex" {
                return operational == true
            }
            return false
        }
    }

    struct TraceFenceConnectivityMode: Decodable, Equatable, Identifiable {
        var title: String
        var requirement: String
        var securityNote: String

        var id: String { title }
    }
}

struct TraceFenceAgentControlResponse: Decodable, Equatable {
    var ok: Bool
    var version: Int?
    var generatedAt: String?
    var operationId: String?
    var operationStatus: String?
    var acknowledgedAt: String?
    var summary: Summary
    var controlPlane: TraceFenceControlPlaneSummary?
    var launchTargets: [AgentLaunchTargetSummary]?
    var sessions: [AgentSessionSummary]
    var allSessions: [AgentSessionSummary]?
    var pendingApprovals: [PendingApprovalSummary]
    var recentEvents: [AgentEventSummary]
    var command: String?
    var message: String?

    struct Summary: Decodable, Equatable {
        var sessionCount: Int
        var activeSessionCount: Int
        var pendingApprovalCount: Int
        var processingCount: Int
        var interruptedCount: Int
    }
}

struct AgentSessionPageResponse: Decodable, Equatable {
    var ok: Bool
    var version: Int?
    var generatedAt: String?
    var sessions: [AgentSessionSummary]
    var projects: [AgentProjectSummary]?
    var totalCount: Int
    var nextCursor: String?
    var hasMore: Bool
}

struct AgentProjectSummary: Decodable, Equatable, Identifiable {
    var name: String
    var count: Int

    var id: String { name }
}

struct AgentSessionContextResponse: Decodable, Equatable {
    var ok: Bool
    var version: Int?
    var generatedAt: String?
    var session: AgentSessionSummary
    var messages: [AgentContextMessage]
    var totalCount: Int
    var nextCursor: String?
    var hasMore: Bool
    var truncated: Bool?
    var warning: String?
}

struct AgentContextMessage: Decodable, Equatable, Identifiable {
    var id: String
    var role: String
    var kind: String
    var text: String
    var timestamp: String?
    var toolName: String?
    var status: String?
    var turnId: String?
}

struct AgentConversationTurn: Equatable, Identifiable {
    var id: String
    var messages: [AgentContextMessage]

    static func group(_ messages: [AgentContextMessage]) -> [AgentConversationTurn] {
        var turns: [AgentConversationTurn] = []
        var currentId: String?

        for message in messages {
            let explicitId = message.turnId?.trimmingCharacters(in: .whitespacesAndNewlines)
            let startsTask = message.kind == "event" && message.text == "task_started"
            let currentHasUser = turns.last?.messages.contains(where: { $0.role == "user" }) == true
            let startsUserTurn = message.role == "user" && currentHasUser

            if let explicitId, !explicitId.isEmpty {
                if explicitId != currentId {
                    currentId = explicitId
                    turns.append(AgentConversationTurn(id: explicitId, messages: []))
                }
            } else if currentId == nil || startsTask || startsUserTurn {
                let derivedId = "derived:\(message.id)"
                currentId = derivedId
                turns.append(AgentConversationTurn(id: derivedId, messages: []))
            }

            if turns.isEmpty {
                let derivedId = "derived:\(message.id)"
                currentId = derivedId
                turns.append(AgentConversationTurn(id: derivedId, messages: []))
            }
            turns[turns.count - 1].messages.append(message)
        }
        return turns
    }
}

struct TraceFenceControlPlaneSummary: Decodable, Equatable {
    var available: Bool?
    var hookSessions: Bool?
    var monitorSessions: Bool?
    var truthModel: String?
    var controlModes: [TraceFenceControlModeSummary]?
    var limitations: [String]?
    var endpoints: [String]?
}

struct TraceFenceControlModeSummary: Decodable, Equatable, Identifiable {
    var id: String
    var title: String?
    var available: Bool?
    var description: String?
}

struct AgentLaunchTargetSummary: Decodable, Equatable, Identifiable {
    var id: String
    var displayName: String
    var commandName: String
    var installed: Bool
    var icon: String?
    var note: String?
    var controlMode: String?

    var controlConsoleName: String {
        let title = displayName.tfSanitizedConsoleName
        return title.isEmpty ? "本地 Agent".tfLocalized : title
    }
}

private extension String {
    var tfIsPrivateNetworkHost: Bool {
        if hasPrefix("10.") || hasPrefix("192.168.") || hasSuffix(".local") {
            return true
        }
        let octets = split(separator: ".")
        if octets.count == 4, octets[0] == "172", let second = Int(octets[1]) {
            return (16...31).contains(second)
        }
        if octets.count == 4, octets[0] == "100", let second = Int(octets[1]) {
            return (64...127).contains(second)
        }
        return false
    }

    var tfSanitizedConsoleName: String {
        var text = self
        text = text.replacingOccurrences(of: "CLI Shell", with: "本地会话".tfLocalized)
        text = text.replacingOccurrences(of: "Shell · 可控会话", with: "本地会话".tfLocalized)
        text = text.replacingOccurrences(of: "PTY controlled", with: "可控会话".tfLocalized)
        text = text.replacingOccurrences(of: "PTY", with: "可控会话".tfLocalized)
        if text.hasPrefix("CLI ") {
            text = String(text.dropFirst("CLI ".count))
        }
        text = text.replacingOccurrences(of: " CLI", with: "")
        text = text.replacingOccurrences(of: " Code", with: "")
        text = text.replacingOccurrences(of: "  ", with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct AgentSessionSummary: Decodable, Equatable, Identifiable {
    var id: String
    var adapterId: String?
    var agentType: String
    var engineLabel: String?
    var project: String
    var cwd: String
    var terminal: String?
    var phase: String
    var startedAt: String?
    var lastActivityAt: String?
    var durationSeconds: Int?
    var title: String?
    var lastToolName: String?
    var lastToolTarget: String?
    var lastToolStatus: String?
    var lastResponse: String?
    var lastThought: String?
    var statusLineText: String?
    var pid: Int?
    var canInterrupt: Bool?
    var canResume: Bool?
    var canTerminate: Bool?
    var resumeRequiresInstruction: Bool?
    var resumeNote: String?
    var controlMode: String?
    var controlAvailable: Bool?
    var controlReason: String?
    var controlLimitations: [String]?
    var deliveryModes: [String]?
    var canRelaunch: Bool?
    var relaunchControlMode: String?
    var relaunchTargetId: String?
    var relaunchTargetName: String?
    var relaunchInstruction: String?
    var relaunchNote: String?
    var source: String?
    var sourcePath: String?
    var contextAvailable: Bool?
    var tokens: TokenSummary?
    var activeTools: [AgentToolSummary]?
    var tasks: [AgentTaskSummary]?
    var subagents: [SubagentSummary]?
    var scheduledTask: Bool?
    var scheduleId: String?
    var scheduleRule: String?
    var nextRunAt: String?

    var agentDisplayName: String {
        sanitizedConsoleText(agentType)
    }

    var displayTitle: String {
        let rawTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = rawTitle?.isEmpty == false ? rawTitle! : project
        return sanitizedConsoleText(text).tfLocalized
    }

    var phaseTitle: String {
        switch phase {
        case "ready": return "就绪".tfLocalized
        case "idle": return "空闲".tfLocalized
        case "processing": return "执行中".tfLocalized
        case "waitingApproval": return "待审批".tfLocalized
        case "waitingInput": return "待回复".tfLocalized
        case "compacting": return "整理上下文".tfLocalized
        case "done": return "已完成".tfLocalized
        case "error": return "异常".tfLocalized
        case "interrupted": return "已暂停".tfLocalized
        case "scheduled": return "下次执行".tfLocalized
        default: return phase
        }
    }

    var isScheduledTask: Bool {
        scheduledTask == true
    }

    var isHistoricalScheduledRun: Bool {
        guard !isScheduledTask else { return false }
        let text = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.hasPrefix("Automation:")
    }

    var needsAttention: Bool {
        phase == "waitingApproval" || phase == "waitingInput" || phase == "error" || phase == "interrupted"
    }

    var canSendContinuation: Bool {
        if canResume == true {
            return true
        }
        if controlMode == "tracefence_pty", controlAvailable == true, phase != "done" {
            return true
        }
        if isCodexNative, controlAvailable == true, phase == "processing" {
            return true
        }
        return false
    }

    var canStartContinuation: Bool {
        canRelaunch == true && relaunchTargetId?.isEmpty == false
    }

    var continuationLaunchTargetTitle: String {
        relaunchTargetName?.isEmpty == false ? relaunchTargetName!.tfLocalized : "可控 Agent".tfLocalized
    }

    var continuationControlTitle: String {
        let title = continuationLaunchTargetTitle.tfSanitizedConsoleName
        return title.isEmpty ? "可控会话".tfLocalized : title
    }

    var continuationLaunchInstruction: String {
        if let relaunchInstruction, !relaunchInstruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return relaunchInstruction
        }
        return title?.isEmpty == false ? title! : project
    }

    var isDisplayOnly: Bool {
        controlMode == "display_only" || controlAvailable == false
    }

    var isCodexNative: Bool {
        controlMode == "codex_native" || controlMode == "codex_desktop_owner" || controlMode == "tracefence_agent_core"
    }

    var controlModeTitle: String {
        switch controlMode {
        case "codex_native": return "Codex 原生控制".tfLocalized
        case "codex_desktop_owner": return "Codex 桌面控制".tfLocalized
        case "tracefence_pty": return "可控会话".tfLocalized
        case "hook_question": return "Hook 回复".tfLocalized
        case "hook_approval": return "Hook 审批".tfLocalized
        case "process_group": return "进程组控制".tfLocalized
        case "process_tree": return "进程树控制".tfLocalized
        case "single_process": return "进程控制".tfLocalized
        case "display_only": return "仅监控".tfLocalized
        case .some(let mode) where !mode.isEmpty: return mode
        default: return "能力未知".tfLocalized
        }
    }

    var primaryControlNote: String {
        if canStartContinuation, let relaunchNote, !relaunchNote.isEmpty {
            return relaunchNote.tfLocalized
        }
        if isDisplayOnly {
            return "此任务来自监控快照，Mac 端没有可控运行时。".tfLocalized
        }
        if let resumeNote, !resumeNote.isEmpty {
            return resumeNote.tfLocalized
        }
        if let first = controlLimitations?.first, !first.isEmpty {
            return first.tfLocalized
        }
        return "Mac 端已声明此任务可远程控制。".tfLocalized
    }

    private func sanitizedConsoleText(_ text: String) -> String {
        let cleaned = text.tfSanitizedConsoleName
        return cleaned.isEmpty ? "本地会话".tfLocalized : cleaned
    }
}

struct PresentedSessionProjectGroup: Identifiable {
    var id: String
    var name: String
    var sessions: [AgentSessionSummary]
    var sortDate: Date
}

struct PresentedSessionAgentGroup: Identifiable {
    var id: String
    var name: String
    var projects: [PresentedSessionProjectGroup]
    var sortDate: Date

    var sessionCount: Int {
        projects.reduce(0) { $0 + $1.sessions.count }
    }
}

enum AgentSessionPresentationPolicy {
    static func visibleSessions(
        _ sessions: [AgentSessionSummary],
        adapters: [TraceFenceStatusResponse.AgentCoreAdapterMetadata]?,
        now: Date = Date()
    ) -> [AgentSessionSummary] {
        let installed = installedAdapterIDs(adapters)
        let hasInstallationMetadata = adapters?.isEmpty == false
        let cutoff = now.addingTimeInterval(-3 * 24 * 60 * 60)
        var latestProjectSession: [String: AgentSessionSummary] = [:]
        var recentNoProject: [AgentSessionSummary] = []
        var nextScheduledTask: [String: AgentSessionSummary] = [:]

        for session in sessions {
            if hasInstallationMetadata, !installed.contains(session.normalizedAdapterID) {
                continue
            }
            if session.isHistoricalScheduledRun {
                continue
            }
            if session.isScheduledTask {
                guard let nextRun = session.nextRunDate, nextRun > now else { continue }
                let scheduleKey = session.scheduleId?.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = (scheduleKey?.isEmpty == false ? scheduleKey! : session.id).lowercased()
                if let existing = nextScheduledTask[key] {
                    if presentationSort(session, existing) { nextScheduledTask[key] = session }
                } else {
                    nextScheduledTask[key] = session
                }
                continue
            }

            guard let project = projectIdentity(for: session) else {
                if let activity = session.activityDate, activity >= cutoff {
                    recentNoProject.append(session)
                }
                continue
            }

            let key = "\(session.normalizedAdapterID)|\(project.key)"
            if let existing = latestProjectSession[key] {
                if presentationSort(session, existing) { latestProjectSession[key] = session }
            } else {
                latestProjectSession[key] = session
            }
        }

        return (Array(latestProjectSession.values) + recentNoProject + Array(nextScheduledTask.values))
            .sorted(by: presentationSort)
    }

    static func installedSessions(
        _ sessions: [AgentSessionSummary],
        adapters: [TraceFenceStatusResponse.AgentCoreAdapterMetadata]?
    ) -> [AgentSessionSummary] {
        let installed = installedAdapterIDs(adapters)
        guard adapters?.isEmpty == false else { return sessions }
        return sessions.filter { installed.contains($0.normalizedAdapterID) }
    }

    static func groups(_ sessions: [AgentSessionSummary]) -> [PresentedSessionAgentGroup] {
        let byAgent = Dictionary(grouping: sessions) { $0.normalizedAdapterID }
        return byAgent.compactMap { adapterID, agentSessions -> PresentedSessionAgentGroup? in
            guard let newest = agentSessions.sorted(by: presentationSort).first else { return nil }
            let byProject = Dictionary(grouping: agentSessions) { session -> String in
                projectIdentity(for: session)?.key ?? "no-project"
            }
            let projects = byProject.map { key, projectSessions -> PresentedSessionProjectGroup in
                let sorted = projectSessions.sorted(by: presentationSort)
                let name = projectIdentity(for: sorted[0])?.name ?? "无项目".tfLocalized
                return PresentedSessionProjectGroup(
                    id: "\(adapterID)|\(key)",
                    name: name,
                    sessions: sorted,
                    sortDate: groupSortDate(sorted)
                )
            }
            .sorted { left, right in
                if left.sortDate != right.sortDate { return left.sortDate > right.sortDate }
                return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
            }
            return PresentedSessionAgentGroup(
                id: adapterID,
                name: newest.agentDisplayName,
                projects: projects,
                sortDate: groupSortDate(agentSessions)
            )
        }
        .sorted { left, right in
            if left.sortDate != right.sortDate { return left.sortDate > right.sortDate }
            return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }
    }

    static func presentationSort(_ lhs: AgentSessionSummary, _ rhs: AgentSessionSummary) -> Bool {
        if lhs.isScheduledTask != rhs.isScheduledTask {
            return !lhs.isScheduledTask
        }
        if lhs.isScheduledTask, rhs.isScheduledTask {
            return (lhs.nextRunDate ?? .distantFuture) < (rhs.nextRunDate ?? .distantFuture)
        }
        let left = lhs.activityDate ?? .distantPast
        let right = rhs.activityDate ?? .distantPast
        if left != right { return left > right }
        return lhs.id < rhs.id
    }

    private static func installedAdapterIDs(
        _ adapters: [TraceFenceStatusResponse.AgentCoreAdapterMetadata]?
    ) -> Set<String> {
        Set((adapters ?? []).filter(\.isInstalledForSessionDisplay).map { $0.id.lowercased() })
    }

    private static func projectIdentity(for session: AgentSessionSummary) -> (key: String, name: String)? {
        let cwd = session.cwd.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = session.project.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cwd.isEmpty, cwd != "/" {
            let standardized = URL(fileURLWithPath: cwd).standardizedFileURL.path
            let components = standardized.split(separator: "/")
            let isUserHome = components.count == 2 && components[0] == "Users"
            let isGenericTemporaryDirectory = ["/tmp", "/private/tmp", "/var/tmp"].contains(standardized)
            if isUserHome || isGenericTemporaryDirectory {
                return nil
            }
            let fallback = URL(fileURLWithPath: standardized).lastPathComponent
            let name = project.isEmpty || project.caseInsensitiveCompare(session.agentType) == .orderedSame
                ? fallback
                : project
            if !name.isEmpty {
                return ("cwd:\(standardized.lowercased())", name)
            }
        }
        guard !project.isEmpty,
              project.caseInsensitiveCompare(session.agentType) != .orderedSame,
              project.caseInsensitiveCompare(session.agentDisplayName) != .orderedSame else { return nil }
        return ("project:\(project.lowercased())", project)
    }

    private static func groupSortDate(_ sessions: [AgentSessionSummary]) -> Date {
        let regular = sessions.compactMap { $0.isScheduledTask ? nil : $0.activityDate }.max()
        return regular ?? sessions.compactMap(\.nextRunDate).min() ?? .distantPast
    }
}

extension AgentSessionSummary {
    var normalizedAdapterID: String {
        if let adapterId, !adapterId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return adapterId.lowercased()
        }
        let value = agentType.lowercased()
        if value.contains("claude") { return "claude" }
        if value.contains("codex") || value == "gpt" { return "codex" }
        if value.contains("cursor") { return "cursor" }
        if value.contains("grok") { return "grok" }
        if value.contains("qwen") { return "qwen" }
        return value.replacingOccurrences(of: " ", with: "-")
    }

    var activityDate: Date? {
        Self.parseSessionDate(lastActivityAt) ?? Self.parseSessionDate(startedAt)
    }

    var nextRunDate: Date? {
        Self.parseSessionDate(nextRunAt)
    }

    private static func parseSessionDate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: value) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
    }
}

struct TokenSummary: Decodable, Equatable {
    var input: UInt64?
    var output: UInt64?
    var cacheRead: UInt64?
    var cacheCreate: UInt64?
}

struct AgentToolSummary: Decodable, Equatable, Identifiable {
    var id: String
    var toolName: String
    var status: String
    var startedAt: String?
    var completedAt: String?
    var toolInput: String?
}

struct AgentTaskSummary: Decodable, Equatable, Identifiable {
    var id: String
    var name: String
    var status: String
}

struct SubagentSummary: Decodable, Equatable, Identifiable {
    var id: String
    var name: String
    var agentType: String?
    var description: String
    var status: String
    var startedAt: String?
    var completedAt: String?
}

struct PendingApprovalSummary: Decodable, Equatable, Identifiable {
    var id: String
    var kind: String
    var actionType: String?
    var approvalMethod: String?
    var sessionId: String
    var agentType: String
    var project: String
    var title: String
    var detail: String
    var command: String?
    var workingDirectory: String?
    var targetPaths: [String]?
    var reason: String?
    var options: [String]?
    var descriptions: [String]?
    var permissions: [String]?
    var sourceLabel: String?
    var requestedAt: String?
    var risk: String?
    var requiresTextAnswer: Bool?

    var agentDisplayName: String {
        let cleaned = agentType.tfSanitizedConsoleName
        return cleaned.isEmpty ? "Agent" : cleaned
    }

    var projectDisplayName: String {
        let name = URL(fileURLWithPath: project).lastPathComponent
        return name.isEmpty ? project : name
    }

    var displayTitle: String {
        let language = AppLanguage.current
        switch actionType {
        case "command":
            return language.text(zh: "执行命令", en: "Run command", zhHant: "執行命令", ja: "コマンドを実行", ko: "명령 실행", mt: "Ħaddem kmand")
        case "fileChange":
            return language.text(zh: "修改文件", en: "Modify files", zhHant: "修改檔案", ja: "ファイルを変更", ko: "파일 수정", mt: "Ibdel fajls")
        case "permission":
            return language.text(zh: "提升任务权限", en: "Grant additional access", zhHant: "提高工作權限", ja: "追加権限を許可", ko: "추가 권한 부여", mt: "Agħti aċċess addizzjonali")
        case "tool":
            return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? language.text(zh: "使用工具", en: "Use tool", zhHant: "使用工具", ja: "ツールを使用", ko: "도구 사용", mt: "Uża għodda")
                : title
        case "question":
            return title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? language.text(zh: "Agent 提问", en: "Agent question", zhHant: "Agent 提問", ja: "Agent からの質問", ko: "Agent 질문", mt: "Mistoqsija tal-Agent")
                : title
        case "plan":
            return language.text(zh: "确认 Agent 计划", en: "Confirm agent plan", zhHant: "確認 Agent 計畫", ja: "Agent プランを確認", ko: "Agent 계획 확인", mt: "Ikkonferma l-pjan tal-Agent")
        default:
            return title
        }
    }

    var displayCommand: String? {
        nonempty(command) ?? readableLegacyValue(legacyPayload?["command"])
    }

    var displayWorkingDirectory: String? {
        nonempty(workingDirectory) ?? readableLegacyValue(legacyPayload?["cwd"])
    }

    var displayReason: String? {
        if let reason = nonempty(reason) { return reason }
        if let legacyReason = readableLegacyValue(legacyPayload?["reason"] ?? legacyPayload?["message"]) {
            return legacyReason
        }
        return legacyPayload == nil ? nonempty(detail) : nil
    }

    private var legacyPayload: [String: Any]? {
        let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return value
    }

    private func nonempty(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }

    private func readableLegacyValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let text = value as? String { return nonempty(text) }
        if let values = value as? [String] { return nonempty(values.joined(separator: " ")) }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return nonempty(text)
    }

    var kindTitle: String {
        switch kind {
        case "permission": return "操作审批".tfLocalized
        case "question": return "Agent 提问".tfLocalized
        case "plan": return "计划审批".tfLocalized
        default: return kind
        }
    }

    var riskTitle: String {
        switch risk {
        case "critical": return "高危".tfLocalized
        case "high": return "风险".tfLocalized
        case "medium": return "注意".tfLocalized
        default: return "待处理".tfLocalized
        }
    }
}

struct AgentEventSummary: Decodable, Equatable, Identifiable {
    var id: String
    var sessionId: String
    var agentType: String
    var project: String
    var type: String
    var title: String
    var detail: String
    var status: String
    var timestamp: String

    var agentDisplayName: String {
        let cleaned = agentType.tfSanitizedConsoleName
        return cleaned.isEmpty ? "Agent" : cleaned
    }

    var timestampDate: Date? {
        let standard = ISO8601DateFormatter()
        if let date = standard.date(from: timestamp) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: timestamp)
    }
}

extension TraceFenceStatusResponse.SubscriptionMetadata {
    var channelTitle: String {
        switch channel {
        case "appStore": return "上架版".tfLocalized
        case "direct": return "官网版".tfLocalized
        default: return channel ?? "未知渠道".tfLocalized
        }
    }

    var tierTitle: String {
        switch tier {
        case "appStoreStandard": return "App Store 标准订阅".tfLocalized
        case "directStandard": return "官网标准订阅".tfLocalized
        case "legacy": return "历史授权".tfLocalized
        case "none": return "未订阅".tfLocalized
        default: return tier ?? "未知方案".tfLocalized
        }
    }
}
