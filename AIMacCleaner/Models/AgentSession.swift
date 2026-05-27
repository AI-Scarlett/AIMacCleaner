import Foundation

enum SessionPhase: String, Codable, CaseIterable, Sendable {
    case ready
    case idle
    case processing
    case waitingApproval
    case waitingInput
    case compacting
    case done
    case error
    case interrupted

    var needsAttention: Bool {
        switch self {
        case .waitingApproval, .waitingInput, .error: return true
        default: return false
        }
    }

    var isActive: Bool {
        switch self {
        case .processing, .waitingApproval, .waitingInput, .compacting: return true
        default: return false
        }
    }

    func canTransitionTo(_ next: SessionPhase) -> Bool {
        switch (self, next) {
        case (_, .ready), (_, .idle): return true
        case (.ready, .processing), (.ready, .waitingApproval), (.ready, .compacting), (.ready, .done): return true
        case (.idle, .processing), (.idle, .waitingApproval), (.idle, .compacting): return true
        case (.processing, .waitingApproval), (.processing, .waitingInput), (.processing, .done), (.processing, .error), (.processing, .interrupted), (.processing, .compacting): return true
        case (.waitingApproval, .processing): return true
        case (.waitingInput, .processing): return true
        case (.compacting, .processing): return true
        case (.done, .processing): return true
        case (.error, .processing): return true
        case (.interrupted, .processing): return true
        default: return false
        }
    }
}

struct TokenUsage: Codable, Sendable {
    var input: UInt64 = 0
    var output: UInt64 = 0
    var cacheRead: UInt64 = 0
    var cacheCreate: UInt64 = 0
}

struct RateLimitInfo: Codable, Sendable {
    var fiveHourUsage: Double
    var fiveHourRemaining: String
    var sevenDayUsage: Double
    var sevenDayRemaining: String
    var provider: String?
    var providerLabel: String?
    var source: String?
    var updatedAt: Int64?
    var windows: [UsageRateWindow] = []
}

struct UsageRateWindow: Codable, Sendable {
    var id: String
    var title: String
    var usedPercent: Double
    var remainingPercent: Double?
    var remainingLabel: String?
    var resetsAt: String?
    var windowMinutes: Int64?
}

struct ContextWindowInfo: Codable, Sendable {
    var totalInputTokens: UInt64
    var totalOutputTokens: UInt64
    var contextWindowSize: UInt64
    var usedPercentage: Double?
}

struct PendingPermission: Codable, Sendable {
    var toolUseId: String?
    var toolName: String
    var toolInput: String
    var diff: String?
    var options: [String]?
}

struct PendingQuestion: Codable, Sendable {
    var question: String
    var options: [String]
    var descriptions: [String]
    var header: String?
    var multiSelect: Bool
    var questions: [QuestionItem]
    var toolUseId: String?
    var source: String?
    var responseMode: String?
}

struct PendingPlan: Codable, Sendable {
    var title: String
    var content: String
    var permissions: [String]
}

struct SubagentInfo: Codable, Identifiable, Sendable {
    var id: String { agentId }
    var agentId: String
    var name: String?
    var agentType: String?
    var description: String
    var transcriptPath: String?
    var agentTranscriptPath: String?
    var lastAssistantMessage: String?
    var startedAt: Date
    var completedAt: Date?
    var status: String
    var tools: [String] = []
}

struct TaskInfo: Codable, Identifiable, Sendable {
    var id: String
    var name: String
    var status: String
}

struct ToolResult: Codable, Identifiable, Sendable {
    var id: String { toolUseId }
    var toolUseId: String
    var toolName: String
    var status: String
    var startedAt: Date
    var completedAt: Date?
    var error: String?
    var toolInput: String?
}

struct SessionState: Codable, Identifiable, Sendable {
    var id: String
    var agentType: String
    var engineLabel: String?
    var engineConfigRoot: String?
    var project: String
    var cwd: String
    var terminal: String
    var phase: SessionPhase = .ready
    var startedAt: Date
    var endedAt: Date?
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }
    var tokens: TokenUsage = TokenUsage()
    var rateLimits: RateLimitInfo?
    var statusLineText: String?
    var contextWindow: ContextWindowInfo?
    var lastMainAgentAt: Int64?
    var cacheTtlMs: Int64?
    var pendingPermission: PendingPermission?
    var pendingQuestion: PendingQuestion?
    var pendingPlan: PendingPlan?
    var lastToolName: String?
    var lastToolTarget: String?
    var lastToolStatus: String?
    var description: String?
    var sessionTitle: String?
    var remoteHostId: String?
    var remoteHostName: String?
    var pid: UInt32?
    var tty: String?
    var termProgram: String?
    var termBundleId: String?
    var subagents: [SubagentInfo] = []
    var activeTools: [ToolResult] = []
    var tasks: [TaskInfo] = []
    var lastUserMessage: String?
    var lastResponse: String?
    var lastThought: String?
    var isYoloMode: Bool = false

    var hasUnfinishedTasks: Bool {
        tasks.contains { $0.status != "completed" }
    }
}

struct RawHookEvent: Codable, Sendable {
    var seq: UInt64
    var timestampMs: UInt64
    var sessionId: String
    var agent: String?
    var eventName: String
    var raw: String
}

struct DetectedTool: Codable, Identifiable, Sendable {
    var id: String { agentId }
    var agentId: String
    var binary: String
    var path: String
    var displayName: String
}

enum AdapterStatus: String, Codable, CaseIterable, Sendable {
    case active
    case installed
    case available
    case unavailable
}

enum AgentError: Error {
    case unknownAgent(String)
    case unexpectedAgent(String)
    case unhandledEvent(String)
    case hookInstallFailed(String)
    case hookUninstallFailed(String)
    case settingsCorrupted(String)
}

enum RemoteError: Error {
    case sshConnectionFailed
    case bridgeDeployFailed
    case tunnelFailed(String)
}
