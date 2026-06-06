import Foundation
@preconcurrency import UserNotifications
import AppKit

struct GuardAlert: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let alertType: AlertType
    let severity: AlertSeverity
    let title: String
    let message: String
    let agentName: String
    let targetPath: String
    let detail: String
    var isRead: Bool = false

    enum AlertType: String, Codable {
        case batchDelete = "batch_delete"
        case batchModify = "batch_modify"
        case sensitiveFile = "sensitive_file"
        case sensitiveContent = "sensitive_content"
        case protectedDir = "protected_dir"
        case processLaunch = "process_launch"
        case processExit = "process_exit"
    }

    enum AlertSeverity: String, Codable {
        case info = "info"
        case warning = "warning"
        case critical = "critical"

        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "xmark.octagon.fill"
            }
        }

        var color: String {
            switch self {
            case .info: return "blue"
            case .warning: return "orange"
            case .critical: return "red"
            }
        }
    }
}

struct AlertRule: Codable {
    var batchDeleteThreshold: Int = 5
    var batchModifyThreshold: Int = 10
    var batchTimeWindowSeconds: Double = 30.0
    var sensitiveFileDetectionEnabled: Bool = true
    var sensitiveContentDetectionEnabled: Bool = true
    var processLaunchAlertEnabled: Bool = true
    var protectedDirAlertEnabled: Bool = true
    var doNotDisturbEnabled: Bool = false
    var doNotDisturbStartHour: Int = 23
    var doNotDisturbEndHour: Int = 7
    var notificationEnabled: Bool = true
    var alertCooldownSeconds: Double = 60.0
    var commandGuardEnabled: Bool = true
}

struct CommandRule: Identifiable, Codable {
    let id: String
    var pattern: String
    var isRegex: Bool
    var listType: ListType
    var commandDesc: String
    var consequence: String
    var source: Source
    var totalCallCount: Int
    var todayCallCount: Int
    var lastCalledBy: String

    enum ListType: String, Codable {
        case blacklist = "blacklist"
        case whitelist = "whitelist"
        case unclassified = "unclassified"
    }

    enum Source: String, Codable {
        case `default` = "default"
        case discovered = "discovered"
        case custom = "custom"
    }

    init(pattern: String, isRegex: Bool = false, listType: ListType = .unclassified, commandDesc: String = "", consequence: String = "", source: Source = .custom, totalCallCount: Int = 0, todayCallCount: Int = 0, lastCalledBy: String = "") {
        self.id = UUID().uuidString
        self.pattern = pattern
        self.isRegex = isRegex
        self.listType = listType
        self.commandDesc = commandDesc
        self.consequence = consequence
        self.source = source
        self.totalCallCount = totalCallCount
        self.todayCallCount = todayCallCount
        self.lastCalledBy = lastCalledBy
    }

    enum CodingKeys: String, CodingKey {
        case id
        case pattern
        case isRegex
        case listType
        case commandDesc
        case consequence
        case source
        case totalCallCount
        case todayCallCount
        case lastCalledBy
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        pattern = try container.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        isRegex = try container.decodeIfPresent(Bool.self, forKey: .isRegex) ?? false
        listType = try container.decodeIfPresent(ListType.self, forKey: .listType) ?? .unclassified
        commandDesc = try container.decodeIfPresent(String.self, forKey: .commandDesc) ?? ""
        consequence = try container.decodeIfPresent(String.self, forKey: .consequence) ?? ""
        source = try container.decodeIfPresent(Source.self, forKey: .source) ?? .custom
        totalCallCount = try container.decodeIfPresent(Int.self, forKey: .totalCallCount) ?? 0
        todayCallCount = try container.decodeIfPresent(Int.self, forKey: .todayCallCount) ?? 0
        lastCalledBy = try container.decodeIfPresent(String.self, forKey: .lastCalledBy) ?? ""
    }
}

struct SensitiveFileRule {
    let namePatterns: [String]
    let pathPatterns: [String]
    let contentPatterns: [String]
    let description: String

    static let allRules: [SensitiveFileRule] = [
        SensitiveFileRule(
            namePatterns: [".env", ".env.local", ".env.production", ".env.staging"],
            pathPatterns: [],
            contentPatterns: ["sk-", "pk_", "API_KEY", "SECRET", "PASSWORD"],
            description: "Environment variable files"
        ),
        SensitiveFileRule(
            namePatterns: ["id_rsa", "id_ed25519", "id_ecdsa", "*.pem", "*.key", "*.p12", "*.pfx", "*.jks"],
            pathPatterns: [".ssh/"],
            contentPatterns: ["BEGIN RSA PRIVATE KEY", "BEGIN PRIVATE KEY", "BEGIN CERTIFICATE"],
            description: "Private keys and certificates"
        ),
        SensitiveFileRule(
            namePatterns: ["credentials", "credentials.json", "service-account*.json", "*.credentials"],
            pathPatterns: [],
            contentPatterns: ["client_secret", "client_id", "\"type\": \"service_account\""],
            description: "Cloud service credentials"
        ),
        SensitiveFileRule(
            namePatterns: [".npmrc", ".pypirc", ".gem/credentials", ".dockercfg"],
            pathPatterns: [],
            contentPatterns: ["_authToken", "_password"],
            description: "Package manager auth tokens"
        ),
        SensitiveFileRule(
            namePatterns: ["*.keystore", "keystore.jks", "google-services.json", "GoogleService-Info.plist"],
            pathPatterns: [],
            contentPatterns: [],
            description: "Mobile app secrets"
        ),
    ]
}

struct ProcessLifecycleEvent: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let eventType: EventType
    let pid: Int32
    let ppid: Int32
    let comm: String
    let args: String
    let agentName: String

    enum EventType: String, Codable {
        case launch = "launch"
        case exit = "exit"
    }
}

struct HourlyStats: Identifiable, Codable {
    let id: String
    let hour: Date
    var createCount: Int = 0
    var modifyCount: Int = 0
    var deleteCount: Int = 0
    var readCount: Int = 0
    var moveCount: Int = 0
    var renameCount: Int = 0
    var executeCount: Int = 0
}

struct AuditReport {
    let generatedAt: Date
    let startTime: Date
    let endTime: Date
    let totalOperations: Int
    let agentBreakdown: [String: Int]
    let operationTypeBreakdown: [String: Int]
    let alertCount: Int
    let criticalAlertCount: Int
    let topTargetPaths: [String]
    let summary: String
}

@MainActor
class AgentGuardFeature: ObservableObject {
    @Published var alerts: [GuardAlert] = []
    @Published var alertRule: AlertRule = AlertRule()
    @Published var protectedDirs: [String] = []
    @Published var processLifecycleEvents: [ProcessLifecycleEvent] = []
    @Published var hourlyStats: [HourlyStats] = []
    @Published var commandRules: [CommandRule] = []

    private var alertsPath: String { SandboxPaths.shared.alertsPath }
    private var alertRulePath: String { SandboxPaths.shared.alertRulePath }
    private var protectedDirsPath: String { SandboxPaths.shared.protectedDirsPath }
    private var lifecyclePath: String { SandboxPaths.shared.lifecyclePath }
    private var hourlyStatsPath: String { SandboxPaths.shared.hourlyStatsPath }
    private var commandRulesPath: String { SandboxPaths.shared.cmdRulesPath }
    private let maxAlerts = 500
    private let maxLifecycleEvents = 1000
    private let maxHourlyStats = 168

    private var recentDeleteEvents: [Date] = []
    private var recentModifyEvents: [Date] = []
    private var lastAlertTimes: [String: Date] = [:]
    private var knownPids: Set<pid_t> = []
    private var knownAgentPids: [pid_t: String] = [:]
    private var lastStatsSaveTime: Date = .distantPast
    private var alertRuleSaveTask: Task<Void, Never>?
    private var commandRegexCache: [String: Regex<AnyRegexOutput>] = [:]
    private var failedRegexRuleIds: Set<String> = []

    private static let commandRuleDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    weak var localizer: Localizer?

    init() {
        loadAlerts()
        loadAlertRule()
        loadProtectedDirs()
        loadLifecycleEvents()
        loadHourlyStats()
        loadCommandRules()
        if commandRules.isEmpty {
            commandRules = CommandRule.defaultRules
            saveCommandRules()
        }
    }

    // MARK: - F25/F26 Batch Operation Alert

    func checkBatchOperation(record: OperationRecord) {
        let now = Date()
        let window = alertRule.batchTimeWindowSeconds

        switch record.operationType {
        case .delete:
            recentDeleteEvents.append(now)
            recentDeleteEvents = recentDeleteEvents.filter { now.timeIntervalSince($0) < window }
            if recentDeleteEvents.count >= alertRule.batchDeleteThreshold {
                let key = "batch_delete_\(record.agentName)"
                if shouldFireAlert(key: key) {
                    let alert = GuardAlert(
                        id: UUID().uuidString,
                        timestamp: now,
                        alertType: .batchDelete,
                        severity: .critical,
                        title: localizer?.batchDeleteAlertTitle ?? "Batch Delete Alert",
                        message: String(format: localizer?.batchDeleteAlertMsg ?? "%d files deleted in %.0fs by %@", recentDeleteEvents.count, window, record.agentName),
                        agentName: record.agentName,
                        targetPath: record.targetPath,
                        detail: "\(recentDeleteEvents.count) deletions in \(Int(window))s window"
                    )
                    fireAlert(alert)
                    recentDeleteEvents.removeAll()
                }
            }
        case .modify:
            recentModifyEvents.append(now)
            recentModifyEvents = recentModifyEvents.filter { now.timeIntervalSince($0) < window }
            if recentModifyEvents.count >= alertRule.batchModifyThreshold {
                let key = "batch_modify_\(record.agentName)"
                if shouldFireAlert(key: key) {
                    let alert = GuardAlert(
                        id: UUID().uuidString,
                        timestamp: now,
                        alertType: .batchModify,
                        severity: .warning,
                        title: localizer?.batchModifyAlertTitle ?? "Batch Modify Alert",
                        message: String(format: localizer?.batchModifyAlertMsg ?? "%d files modified in %.0fs by %@", recentModifyEvents.count, window, record.agentName),
                        agentName: record.agentName,
                        targetPath: record.targetPath,
                        detail: "\(recentModifyEvents.count) modifications in \(Int(window))s window"
                    )
                    fireAlert(alert)
                    recentModifyEvents.removeAll()
                }
            }
        default:
            break
        }
    }

    // MARK: - F28/F29 Sensitive File Detection

    func checkSensitiveFile(record: OperationRecord) {
        guard alertRule.sensitiveFileDetectionEnabled else { return }
        let path = record.targetPath.lowercased()
        let fileName = (record.targetPath as NSString).lastPathComponent.lowercased()

        for rule in SensitiveFileRule.allRules {
            var matched = false
            var matchDetail = ""

            for pattern in rule.namePatterns {
                if pattern.hasPrefix("*") {
                    let ext = String(pattern.dropFirst())
                    if fileName.hasSuffix(ext) {
                        matched = true
                        matchDetail = "Filename matches \(pattern)"
                        break
                    }
                } else if fileName == pattern.lowercased() || fileName.hasPrefix(pattern.lowercased()) {
                    matched = true
                    matchDetail = "Filename matches \(pattern)"
                    break
                }
            }

            if !matched {
                for pattern in rule.pathPatterns {
                    if path.contains(pattern.lowercased()) {
                        matched = true
                        matchDetail = "Path contains \(pattern)"
                        break
                    }
                }
            }

            if matched {
                let key = "sensitive_file_\(record.targetPath)"
                if shouldFireAlert(key: key) {
                    let alert = GuardAlert(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        alertType: .sensitiveFile,
                        severity: .critical,
                        title: localizer?.sensitiveFileAlertTitle ?? "Sensitive File Access",
                        message: String(format: localizer?.sensitiveFileAlertMsg ?? "Agent %@ accessed sensitive file: %@", record.agentName, (record.targetPath as NSString).lastPathComponent),
                        agentName: record.agentName,
                        targetPath: record.targetPath,
                        detail: "\(matchDetail) (\(rule.description))"
                    )
                    fireAlert(alert)
                }
                return
            }
        }

        if alertRule.sensitiveContentDetectionEnabled {
            checkSensitiveContent(record: record)
        }
    }

    private func checkSensitiveContent(record: OperationRecord) {
        guard record.operationType == .create || record.operationType == .modify else { return }
        let expanded = NSString(string: record.targetPath).expandingTildeInPath

        let textExtensions: Set<String> = ["txt", "md", "json", "yaml", "yml", "toml", "ini", "cfg", "conf", "env", "sh", "bash", "zsh", "py", "js", "ts", "rb", "go", "rs", "java", "xml", "html", "css", "sql", "log"]
        let ext = (record.targetPath as NSString).pathExtension.lowercased()
        guard textExtensions.contains(ext) || ext.isEmpty else { return }

        guard let content = try? String(contentsOfFile: expanded, encoding: .utf8) else { return }
        let contentLower = content.lowercased()
        let limitedContent = String(contentLower.prefix(50000))

        let sensitivePatterns: [(String, String)] = [
            ("sk-", "OpenAI API Key"),
            ("pk_", "Stripe API Key"),
            ("AKIA", "AWS Access Key"),
            ("AIza", "Google API Key"),
            ("ghp_", "GitHub Token"),
            ("gho_", "GitHub OAuth Token"),
            ("github_pat_", "GitHub PAT"),
            ("xoxb-", "Slack Bot Token"),
            ("xoxp-", "Slack User Token"),
            ("hooks.slack.com/services/t", "Slack Webhook"),
            ("-----begin rsa private key-----", "RSA Private Key"),
            ("-----begin private key-----", "Private Key"),
            ("-----begin ec private key-----", "EC Private Key"),
            ("\"type\": \"service_account\"", "GCP Service Account"),
            ("aws_secret_access_key", "AWS Secret Key"),
            ("api_key", "API Key reference"),
            ("secret_key", "Secret Key reference"),
            ("private_key", "Private Key reference"),
            ("password", "Password reference"),
        ]

        for (pattern, desc) in sensitivePatterns {
            if limitedContent.contains(pattern.lowercased()) {
                let key = "sensitive_content_\(record.targetPath)"
                if shouldFireAlert(key: key) {
                    let alert = GuardAlert(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        alertType: .sensitiveContent,
                        severity: .critical,
                        title: localizer?.sensitiveContentAlertTitle ?? "Sensitive Content Detected",
                        message: String(format: localizer?.sensitiveContentAlertMsg ?? "Agent %@ modified file containing %@", record.agentName, desc),
                        agentName: record.agentName,
                        targetPath: record.targetPath,
                        detail: "Found \(desc) pattern in content"
                    )
                    fireAlert(alert)
                }
                return
            }
        }
    }

    // MARK: - F30 Protected Directory

    func checkProtectedDir(record: OperationRecord) {
        guard alertRule.protectedDirAlertEnabled else { return }
        guard record.operationType == .delete || record.operationType == .modify else { return }

        let expanded = NSString(string: record.targetPath).expandingTildeInPath.lowercased()
        for dir in protectedDirs {
            let dirExpanded = NSString(string: dir).expandingTildeInPath.lowercased()
            if expanded.hasPrefix(dirExpanded) {
                let key = "protected_dir_\(record.targetPath)"
                if shouldFireAlert(key: key) {
                    let alert = GuardAlert(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        alertType: .protectedDir,
                        severity: .warning,
                        title: localizer?.protectedDirAlertTitle ?? "Protected Directory Access",
                        message: String(format: localizer?.protectedDirAlertMsg ?? "Agent %@ %@ file in protected directory", record.agentName, record.operationType.rawValue),
                        agentName: record.agentName,
                        targetPath: record.targetPath,
                        detail: "Protected dir: \(dir)"
                    )
                    fireAlert(alert)
                }
                return
            }
        }
    }

    // MARK: - F04 Process Lifecycle

    func checkProcessLifecycle(currentPids: Set<pid_t>, pidCommMap: [pid_t: String], pidArgsMap: [pid_t: String], ppidMap: [pid_t: pid_t], agentKeywords: [(String, [String])]) {
        if knownPids.isEmpty {
            knownPids = currentPids
            for pid in currentPids {
                if let comm = pidCommMap[pid] {
                    let args = pidArgsMap[pid] ?? ""
                    let lowerAll = (comm + " " + args).lowercased()
                    for (displayName, kws) in agentKeywords {
                        for kw in kws {
                            if lowerAll.contains(kw) {
                                knownAgentPids[pid] = displayName
                                break
                            }
                        }
                        if knownAgentPids[pid] != nil { break }
                    }
                }
            }
            return
        }

        let newPids = currentPids.subtracting(knownPids)
        let exitedPids = knownPids.subtracting(currentPids)

        for pid in newPids {
            guard let comm = pidCommMap[pid] else { continue }
            let args = pidArgsMap[pid] ?? ""
            let ppid = ppidMap[pid] ?? 0
            let agentName = resolveAgentName(comm: comm, args: args, ppid: ppid, pidCommMap: pidCommMap, pidArgsMap: pidArgsMap, ppidMap: ppidMap, agentKeywords: agentKeywords)

            let lowerAll = (comm + " " + args).lowercased()
            let isAgent = agentKeywords.contains { _, kws in kws.contains { lowerAll.contains($0) } }
            guard isAgent else { continue }

            knownAgentPids[pid] = agentName

            let event = ProcessLifecycleEvent(
                id: UUID().uuidString,
                timestamp: Date(),
                eventType: .launch,
                pid: pid,
                ppid: ppid,
                comm: comm,
                args: String(args.prefix(200)),
                agentName: agentName
            )
            processLifecycleEvents.insert(event, at: 0)

            if alertRule.processLaunchAlertEnabled {
                let key = "process_launch_\(agentName)"
                if shouldFireAlert(key: key) {
                    let alert = GuardAlert(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        alertType: .processLaunch,
                        severity: .info,
                        title: localizer?.processLaunchAlertTitle ?? "Agent Process Launched",
                        message: String(format: localizer?.processLaunchAlertMsg ?? "%@ started (PID: %d)", agentName, pid),
                        agentName: agentName,
                        targetPath: comm,
                        detail: "PPID: \(ppid) Comm: \(comm)"
                    )
                    fireAlert(alert)
                }
            }
        }

        for pid in exitedPids {
            guard let agentName = knownAgentPids[pid] else { continue }
            knownAgentPids.removeValue(forKey: pid)
            let comm = pidCommMap[pid] ?? "PID:\(pid)"
            let event = ProcessLifecycleEvent(
                id: UUID().uuidString,
                timestamp: Date(),
                eventType: .exit,
                pid: pid,
                ppid: ppidMap[pid] ?? 0,
                comm: comm,
                args: "",
                agentName: agentName
            )
            processLifecycleEvents.insert(event, at: 0)
        }

        if processLifecycleEvents.count > maxLifecycleEvents {
            processLifecycleEvents = Array(processLifecycleEvents.prefix(maxLifecycleEvents))
        }

        knownPids = currentPids
        saveLifecycleEvents()
    }

    private func resolveAgentName(comm: String, args: String, ppid: pid_t, pidCommMap: [pid_t: String], pidArgsMap: [pid_t: String], ppidMap: [pid_t: pid_t], agentKeywords: [(String, [String])]) -> String {
        let combined = (comm + " " + args).lowercased()
        for (displayName, keywords) in agentKeywords {
            for kw in keywords {
                if combined.contains(kw) {
                    return displayName
                }
            }
        }
        return (comm as NSString).lastPathComponent
    }

    // MARK: - F36 Hourly Stats

    func recordStats(_ record: OperationRecord) {
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: record.timestamp)?.start ?? record.timestamp
        let hourKey = ISO8601DateFormatter().string(from: hourStart)

        if let idx = hourlyStats.firstIndex(where: { $0.id == hourKey }) {
            switch record.operationType {
            case .create: hourlyStats[idx].createCount += 1
            case .modify: hourlyStats[idx].modifyCount += 1
            case .delete: hourlyStats[idx].deleteCount += 1
            case .read: hourlyStats[idx].readCount += 1
            case .move: hourlyStats[idx].moveCount += 1
            case .rename: hourlyStats[idx].renameCount += 1
            case .execute: hourlyStats[idx].executeCount += 1
            }
        } else {
            var stats = HourlyStats(id: hourKey, hour: hourStart)
            switch record.operationType {
            case .create: stats.createCount = 1
            case .modify: stats.modifyCount = 1
            case .delete: stats.deleteCount = 1
            case .read: stats.readCount = 1
            case .move: stats.moveCount = 1
            case .rename: stats.renameCount = 1
            case .execute: stats.executeCount = 1
            }
            hourlyStats.append(stats)
        }

        if hourlyStats.count > maxHourlyStats {
            hourlyStats.sort { $0.hour < $1.hour }
            hourlyStats = Array(hourlyStats.suffix(maxHourlyStats))
        }

        let now = Date()
        if now.timeIntervalSince(lastStatsSaveTime) > 30 {
            saveHourlyStats()
            lastStatsSaveTime = now
        }
    }

    func rebuildAnalytics(from records: [OperationRecord]) {
        let existingRules = commandRules
        hourlyStats = []
        lastStatsSaveTime = .distantFuture
        commandRules = existingRules.map { rule in
            var reset = rule
            reset.totalCallCount = 0
            reset.todayCallCount = 0
            reset.lastCalledBy = ""
            return reset
        }

        for record in records.sorted(by: { $0.timestamp < $1.timestamp }) {
            recordStats(record)
            guard record.operationType == .execute else { continue }
            let command = record.detail.isEmpty ? record.targetPath : record.detail
            _ = recordObservedCommand(command: command, agentName: record.agentName, timestamp: record.timestamp, shouldSave: false)
        }

        lastStatsSaveTime = .distantPast
        saveHourlyStats()
        saveCommandRules()
    }

    // MARK: - F37 Export

    private func isAuditableAgentRecord(_ record: OperationRecord) -> Bool {
        let name = record.agentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == "—" { return false }
        if name == (localizer?.systemProcess ?? "System Process") || name.localizedCaseInsensitiveContains("system process") { return false }
        let nonAgentToolNames: Set<String> = [
            "Node.js", "Python", "npm", "npx", "Yarn", "pnpm", "Cargo", "Rust",
            "Deno", "Bun", "Go", "Swift", "Java", "Gradle", "Maven", "Make",
            "CMake", "Xcode", "Git", "Docker", "pip", "pip3", "Clang",
            "rsync", "cp", "mv", "rm", "zip", "tar", "mkdir"
        ]
        return !nonAgentToolNames.contains(name)
    }

    func exportRecordsAsCSV(records: [OperationRecord]) -> String {
        var lines = ["ID,Timestamp,Agent,Operation,Path,Detail,FileSize,ProcessName,ToolInfo"]
        let formatter = ISO8601DateFormatter()
        for r in records.filter(isAuditableAgentRecord) {
            let fields = [
                r.id,
                formatter.string(from: r.timestamp),
                r.agentName,
                r.operationType.rawValue,
                r.targetPath.replacingOccurrences(of: ",", with: ";"),
                r.detail.replacingOccurrences(of: ",", with: ";").replacingOccurrences(of: "\n", with: " "),
                "\(r.fileSize)",
                r.processName ?? "",
                r.toolInfo ?? ""
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    func exportRecordsAsJSON(records: [OperationRecord]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records.filter(isAuditableAgentRecord)) else { return "[]" }
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    func exportAlertsAsCSV() -> String {
        var lines = ["ID,Timestamp,Type,Severity,Title,Message,Agent,Path,Detail"]
        let formatter = ISO8601DateFormatter()
        for a in alerts {
            let fields = [
                a.id,
                formatter.string(from: a.timestamp),
                a.alertType.rawValue,
                a.severity.rawValue,
                a.title.replacingOccurrences(of: ",", with: ";"),
                a.message.replacingOccurrences(of: ",", with: ";"),
                a.agentName,
                a.targetPath.replacingOccurrences(of: ",", with: ";"),
                a.detail.replacingOccurrences(of: ",", with: ";")
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    func saveExport(content: String, filename: String) -> Bool {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [.commaSeparatedText, .json]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
        return true
    }

    // MARK: - F38 Audit Report

    func generateAuditReport(records: [OperationRecord], startTime: Date, endTime: Date) -> AuditReport {
        let filtered = records.filter { isAuditableAgentRecord($0) && $0.timestamp >= startTime && $0.timestamp <= endTime }
        let periodAlerts = alerts.filter { $0.timestamp >= startTime && $0.timestamp <= endTime }

        var agentBreakdown: [String: Int] = [:]
        var opTypeBreakdown: [String: Int] = [:]
        var pathCounts: [String: Int] = [:]

        for r in filtered {
            agentBreakdown[r.agentName, default: 0] += 1
            opTypeBreakdown[r.operationType.rawValue, default: 0] += 1
            let dir = (r.targetPath as NSString).deletingLastPathComponent
            pathCounts[dir, default: 0] += 1
        }

        let topPaths = pathCounts.sorted { $0.value > $1.value }.prefix(10).map { $0.key }
        let criticalCount = periodAlerts.filter { $0.severity == .critical }.count

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let summary = """
        Audit Period: \(formatter.string(from: startTime)) ~ \(formatter.string(from: endTime))
        Total Operations: \(filtered.count)
        Unique Agents: \(agentBreakdown.count)
        Alerts: \(periodAlerts.count) (\(criticalCount) critical)
        Most Active Agent: \(agentBreakdown.sorted { $0.value > $1.value }.first?.key ?? "N/A")
        Most Affected Path: \(topPaths.first ?? "N/A")
        """

        return AuditReport(
            generatedAt: Date(),
            startTime: startTime,
            endTime: endTime,
            totalOperations: filtered.count,
            agentBreakdown: agentBreakdown,
            operationTypeBreakdown: opTypeBreakdown,
            alertCount: periodAlerts.count,
            criticalAlertCount: criticalCount,
            topTargetPaths: topPaths,
            summary: summary
        )
    }

    // MARK: - F40/F41/F42 Notification

    private func fireAlert(_ alert: GuardAlert) {
        alerts.insert(alert, at: 0)
        if alerts.count > maxAlerts {
            alerts = Array(alerts.prefix(maxAlerts))
        }
        saveAlerts()

        if alertRule.notificationEnabled && !isDoNotDisturb() {
            sendNotification(alert)
        }
    }

    private func shouldFireAlert(key: String) -> Bool {
        let now = Date()
        if let lastTime = lastAlertTimes[key], now.timeIntervalSince(lastTime) < alertRule.alertCooldownSeconds {
            return false
        }
        lastAlertTimes[key] = now
        return true
    }

    private func isDoNotDisturb() -> Bool {
        guard alertRule.doNotDisturbEnabled else { return false }
        let hour = Calendar.current.component(.hour, from: Date())
        let start = alertRule.doNotDisturbStartHour
        let end = alertRule.doNotDisturbEndHour
        if start > end {
            return hour >= start || hour < end
        } else {
            return hour >= start && hour < end
        }
    }

    private func sendNotification(_ alert: GuardAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.message
        content.sound = alert.severity == .info ? nil : .default

        let request = UNNotificationRequest(
            identifier: "agentguard_\(alert.alertType.rawValue)_\(alert.id)",
            content: content,
            trigger: nil
        )

        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request) { error in
                    if let error = error {
                        print("[AgentWatch] Notification error: \(error.localizedDescription)")
                    }
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, error in
                    if let error = error {
                        print("[AgentWatch] Notification authorization error: \(error.localizedDescription)")
                    }
                    guard granted else { return }
                    center.add(request) { error in
                        if let error = error {
                            print("[AgentWatch] Notification error: \(error.localizedDescription)")
                        }
                    }
                }
            default:
                break
            }
        }
    }

    // MARK: - Protected Directory Management

    func addProtectedDir(_ path: String) {
        let expanded = NSString(string: path).expandingTildeInPath
        guard !protectedDirs.contains(expanded) else { return }
        protectedDirs.append(expanded)
        saveProtectedDirs()
    }

    func removeProtectedDir(_ path: String) {
        protectedDirs.removeAll { $0 == path }
        saveProtectedDirs()
    }

    // MARK: - Alert Management

    func markAlertRead(_ id: String) {
        if let idx = alerts.firstIndex(where: { $0.id == id }) {
            alerts[idx].isRead = true
            saveAlerts()
        }
    }

    func markAllAlertsRead() {
        for i in alerts.indices { alerts[i].isRead = true }
        saveAlerts()
    }

    func clearAlerts() {
        alerts.removeAll()
        saveAlerts()
    }

    var unreadAlertCount: Int {
        alerts.filter { !$0.isRead }.count
    }

    var criticalAlertCount: Int {
        alerts.filter { $0.severity == .critical }.count
    }

    // MARK: - Command Guard

    var blacklistRules: [CommandRule] {
        commandRules.filter { $0.listType == .blacklist }
    }

    var whitelistRules: [CommandRule] {
        commandRules.filter { $0.listType == .whitelist }
    }

    var unclassifiedRules: [CommandRule] {
        commandRules.filter { $0.listType == .unclassified }
    }

    enum CommandCheckResult {
        case allowed
        case blocked(CommandRule)
        case warning(CommandRule)
        case unknown
    }

    func checkCommand(command: String, agentName: String, timestamp: Date = Date(), shouldSave: Bool = true) -> CommandCheckResult {
        guard alertRule.commandGuardEnabled else { return .allowed }
        let cmdLower = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmdLower.isEmpty else { return .allowed }

        for i in commandRules.indices where commandRules[i].listType == .blacklist {
            if matchCommand(cmdLower, rule: commandRules[i]) {
                incrementRuleCount(at: i, agentName: agentName, timestamp: timestamp, shouldSave: shouldSave)
                let rule = commandRules[i]
                let key = "cmd_blacklist_\(rule.id)"
                if shouldSave && shouldFireAlert(key: key) {
                    let alert = GuardAlert(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        alertType: .sensitiveContent,
                        severity: .critical,
                        title: localizer?.commandBlacklistAlertTitle ?? "Blacklisted Command Blocked",
                        message: String(format: localizer?.commandBlacklistAlertMsg ?? "Agent %@ attempted blacklisted command: %@", agentName, rule.pattern),
                        agentName: agentName,
                        targetPath: command,
                        detail: rule.consequence.isEmpty ? "Pattern: \(rule.pattern)" : rule.consequence
                    )
                    fireAlert(alert)
                }
                return .blocked(rule)
            }
        }

        for i in commandRules.indices where commandRules[i].listType == .whitelist {
            if matchCommand(cmdLower, rule: commandRules[i]) {
                incrementRuleCount(at: i, agentName: agentName, timestamp: timestamp, shouldSave: shouldSave)
                return .allowed
            }
        }

        for i in commandRules.indices where commandRules[i].listType == .unclassified {
            if matchCommand(cmdLower, rule: commandRules[i]) {
                incrementRuleCount(at: i, agentName: agentName, timestamp: timestamp, shouldSave: shouldSave)
                let rule = commandRules[i]
                let key = "cmd_unclassified_\(rule.id)"
                if shouldSave && shouldFireAlert(key: key) {
                    let alert = GuardAlert(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        alertType: .sensitiveContent,
                        severity: .warning,
                        title: localizer?.commandUnclassifiedAlertTitle ?? "Unclassified Command",
                        message: String(format: localizer?.commandUnclassifiedAlertMsg ?? "Agent %@ executed unclassified command: %@", agentName, rule.pattern),
                        agentName: agentName,
                        targetPath: command,
                        detail: rule.consequence.isEmpty ? "Pattern: \(rule.pattern)" : rule.consequence
                    )
                    fireAlert(alert)
                }
                return .warning(rule)
            }
        }

        return .unknown
    }

    @discardableResult
    func recordObservedCommand(command: String, agentName: String, timestamp: Date = Date(), shouldSave: Bool = true) -> CommandCheckResult {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .allowed }
        let result = checkCommand(command: trimmed, agentName: agentName, timestamp: timestamp, shouldSave: shouldSave)
        if case .unknown = result {
            discoverCommand(pattern: normalizedCommandPattern(trimmed), agentName: agentName, shouldSave: shouldSave)
            if let idx = commandRules.firstIndex(where: { $0.pattern == normalizedCommandPattern(trimmed) }) {
                incrementRuleCount(at: idx, agentName: agentName, timestamp: timestamp, shouldSave: shouldSave)
            }
        }
        return result
    }

    func checkAgentEvent(_ event: AgentHookEvent) {
        let agentName = agentName(for: event)
        let now = Date()

        switch event {
        case .toolUse(_, let toolName, let toolInput, let toolTarget, _):
            let target = toolTarget ?? toolInput
            let record = OperationRecord(
                id: "hook_\(event.sessionId)_\(now.timeIntervalSince1970)",
                timestamp: now,
                agentName: agentName,
                operationType: operationTypeForHookTool(toolName: toolName, target: target, input: toolInput),
                targetPath: target.isEmpty ? toolName : target,
                detail: toolInput,
                fileSize: 0,
                processName: toolName,
                toolInfo: event.sessionId
            )
            checkBatchOperation(record: record)
            checkSensitiveFile(record: record)
            checkProtectedDir(record: record)
            recordStats(record)
            if record.operationType == .execute {
                _ = recordObservedCommand(command: record.detail.isEmpty ? record.targetPath : record.detail, agentName: agentName, timestamp: now)
            }

        case .shellExecutionStart(_, let command, let cwd):
            _ = recordObservedCommand(command: command, agentName: agentName, timestamp: now)
            let record = OperationRecord(
                id: "hook_shell_\(event.sessionId)_\(now.timeIntervalSince1970)",
                timestamp: now,
                agentName: agentName,
                operationType: .execute,
                targetPath: cwd.isEmpty ? command : cwd,
                detail: command,
                fileSize: 0,
                processName: "shell",
                toolInfo: event.sessionId
            )
            recordStats(record)

        case .mcpExecutionStart(_, let serverName, let toolName, let arguments):
            let record = OperationRecord(
                id: "hook_mcp_\(event.sessionId)_\(now.timeIntervalSince1970)",
                timestamp: now,
                agentName: agentName,
                operationType: .execute,
                targetPath: "\(serverName).\(toolName)",
                detail: arguments,
                fileSize: 0,
                processName: toolName,
                toolInfo: event.sessionId
            )
            recordStats(record)

        default:
            break
        }
    }

    private func agentName(for event: AgentHookEvent) -> String {
        if case .sessionStart(_, _, _, _, let agentType) = event {
            let trimmed = agentType.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Agent Center" : trimmed
        }
        return "Agent Center"
    }

    private func operationTypeForHookTool(toolName: String, target: String, input: String) -> OperationRecord.OperationType {
        let tool = toolName.lowercased()
        let combined = "\(toolName) \(target) \(input)".lowercased()
        let terms = commandTerms(in: combined)

        if tool.contains("delete") || tool.contains("remove") || tool.contains("trash") || tool == "rm" ||
            terms.contains("delete") || terms.contains("remove") || terms.contains("trash") || terms.contains("rm") || terms.contains("unlink") {
            return .delete
        }
        if tool.contains("read") || tool.contains("grep") || tool.contains("search") || tool.contains("glob") ||
            terms.contains("read") || terms.contains("grep") || terms.contains("rg") || terms.contains("search") || terms.contains("glob") || terms.contains("cat") || terms.contains("ls") || terms.contains("view") {
            return .read
        }
        if tool.contains("write") || tool.contains("create") || tool == "touch" || tool == "mkdir" ||
            terms.contains("write") || terms.contains("create") || terms.contains("touch") || terms.contains("mkdir") || terms.contains("new") {
            return .create
        }
        if tool.contains("rename") || terms.contains("rename") {
            return .rename
        }
        if tool.contains("move") || tool == "mv" || terms.contains("move") || terms.contains("mv") {
            return .move
        }
        if terms.contains("chmod") || terms.contains("chown") || terms.contains("edit") || terms.contains("patch") {
            return .modify
        }
        if tool.contains("bash") || tool.contains("shell") || tool.contains("command") || tool.contains("execute") ||
            terms.contains("bash") || terms.contains("shell") || terms.contains("command") || terms.contains("execute") || terms.contains("exec") {
            return .execute
        }
        return .modify
    }

    private func commandTerms(in text: String) -> Set<String> {
        Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init))
    }

    private func incrementRuleCount(at index: Int, agentName: String, timestamp: Date = Date(), shouldSave: Bool = true) {
        commandRules[index].totalCallCount += 1
        let isToday = Calendar.current.isDateInToday(timestamp)
        let callDateStr = Self.commandRuleDayFormatter.string(from: timestamp)
        let lastDateStr = commandRules[index].lastCalledBy.isEmpty ? "" : String(commandRules[index].lastCalledBy.split(separator: "|").first ?? "")
        if isToday {
            if callDateStr == lastDateStr {
                commandRules[index].todayCallCount += 1
            } else {
                commandRules[index].todayCallCount = 1
            }
        }
        let safeAgentName = agentName.replacingOccurrences(of: "|", with: "/")
        commandRules[index].lastCalledBy = callDateStr + "|" + safeAgentName
        if shouldSave {
            saveCommandRules()
        }
    }

    private func matchCommand(_ cmdLower: String, rule: CommandRule) -> Bool {
        if rule.isRegex {
            guard let regex = cachedRegex(for: rule) else { return false }
            return (try? regex.firstMatch(in: cmdLower)) != nil
        } else {
            return cmdLower.contains(rule.pattern.lowercased())
        }
    }

    private func cachedRegex(for rule: CommandRule) -> Regex<AnyRegexOutput>? {
        if let regex = commandRegexCache[rule.id] {
            return regex
        }
        guard !failedRegexRuleIds.contains(rule.id),
              let regex = try? Regex(rule.pattern) else {
            failedRegexRuleIds.insert(rule.id)
            return nil
        }
        commandRegexCache[rule.id] = regex
        return regex
    }

    func discoverCommand(pattern: String, agentName: String, shouldSave: Bool = true) {
        let normalized = pattern.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if commandRules.contains(where: { $0.pattern.lowercased() == normalized }) { return }

        let desc = guessCommandDescription(normalized)
        let rule = CommandRule(
            pattern: normalized,
            listType: .unclassified,
            commandDesc: desc.function,
            consequence: desc.consequence,
            source: .discovered
        )
        commandRules.append(rule)
        if shouldSave {
            saveCommandRules()
        }
    }

    private func normalizedCommandPattern(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "|;&"))
        let firstToken = trimmed.components(separatedBy: separators).first ?? trimmed
        let basename = (firstToken as NSString).lastPathComponent
        let root = basename.isEmpty ? firstToken : basename
        return root.lowercased() + " "
    }

    private func guessCommandDescription(_ cmd: String) -> (function: String, consequence: String) {
        let map: [(patterns: [String], function: String, consequence: String)] = [
            (["rm "], "Delete files", "Files may be removed; AgentGuard asks you to review first"),
            (["rm -rf", "rm -r"], "Recursive force delete", "Entire directory trees will be deleted without confirmation"),
            (["mkdir "], "Create directory", "New directory will be created"),
            (["cp ", "copy "], "Copy files", "Files will be duplicated to target location"),
            (["mv ", "move "], "Move/rename files", "Files will be moved or renamed"),
            (["chmod "], "Change file permissions", "File access permissions will be modified"),
            (["chown "], "Change file ownership", "File owner/group will be changed"),
            (["cat "], "Display file contents", "File contents will be read and displayed"),
            (["grep ", "rg ", "ag "], "Search text in files", "Will search for patterns in files"),
            (["find "], "Search for files", "Will locate files matching criteria"),
            (["curl "], "Download from URL", "Data will be fetched from a remote server"),
            (["wget "], "Download file", "File will be downloaded from the internet"),
            (["git "], "Git version control", "Repository operations will be performed"),
            (["npm ", "yarn ", "pnpm "], "Package manager", "Node.js packages will be installed/modified"),
            (["pip ", "pip3 "], "Python package manager", "Python packages will be installed/modified"),
            (["brew "], "Homebrew package manager", "macOS packages will be installed/modified"),
            (["docker "], "Docker container management", "Containers/images will be created or modified"),
            (["sudo "], "Execute with superuser privileges", "Command runs with elevated system permissions"),
            (["kill ", "killall "], "Terminate process", "Running processes will be stopped"),
            (["launchctl "], "Launch daemon control", "System services will be loaded/unloaded"),
            (["defaults "], "macOS defaults system", "System/application preferences will be modified"),
            (["ln -s", "symlink"], "Create symbolic link", "A link to another file will be created"),
            (["tar "], "Archive/extract files", "Files will be compressed or extracted"),
            (["zip ", "unzip "], "Compress/extract ZIP", "Files will be archived or extracted"),
            (["sed "], "Stream editor", "File contents will be modified in-place or streamed"),
            (["awk "], "Text processing", "Text data will be processed and transformed"),
            (["xcodebuild "], "Build Xcode project", "Project will be compiled and built"),
            (["swift "], "Run Swift", "Swift code will be compiled or executed"),
            (["python ", "python3 "], "Run Python", "Python script will be executed"),
            (["node "], "Run Node.js", "JavaScript will be executed"),
            (["sh ", "bash ", "zsh "], "Execute shell script", "Shell commands will be run"),
            (["echo "], "Print text", "Text will be output to console or file"),
            (["touch "], "Create empty file", "New empty file will be created or timestamp updated"),
            (["head ", "tail "], "View file head/tail", "Beginning or end of file will be displayed"),
            (["wc "], "Count lines/words", "File statistics will be calculated"),
            (["sort "], "Sort lines", "Lines will be sorted alphabetically or numerically"),
            (["uniq "], "Remove duplicates", "Duplicate adjacent lines will be removed"),
            (["diff "], "Compare files", "Differences between files will be shown"),
            (["ps "], "List processes", "Running processes will be displayed"),
            (["top ", "htop "], "Monitor processes", "System resource usage will be displayed"),
            (["df "], "Disk free space", "Available disk space will be shown"),
            (["du "], "Disk usage", "Directory sizes will be calculated"),
            (["which "], "Locate command", "Path to executable will be found"),
            (["env "], "Show environment", "Environment variables will be displayed"),
            (["export "], "Set environment variable", "Shell variable will be exported"),
            (["source "], "Execute script in current shell", "Script will run in current shell context"),
        ]

        for entry in map {
            for p in entry.patterns {
                if cmd.hasPrefix(p) || cmd.contains(" \(p)") {
                    return (entry.function, entry.consequence)
                }
            }
        }
        return ("Unknown command", "Effect of this command is not documented")
    }

    func localizeCommandDesc(_ desc: String, localizer: Localizer) -> String {
        let map: [String: String] = [
            "Delete files": localizer.cmdDeleteFiles,
            "Recursive force delete": localizer.cmdRecursiveDelete,
            "Files may be removed; AgentGuard asks you to review first": localizer.cmdDeleteFilesCon,
            "Entire directory trees will be deleted without confirmation": localizer.cmdRecursiveDeleteCon,
            "Create directory": localizer.cmdCreateDir,
            "New directory will be created": localizer.cmdCreateDirCon,
            "Copy files": localizer.cmdCopyFiles,
            "Files will be duplicated to target location": localizer.cmdCopyFilesCon,
            "Move/rename files": localizer.cmdMoveFiles,
            "Files will be moved or renamed": localizer.cmdMoveFilesCon,
            "Change file permissions": localizer.cmdChmod,
            "File access permissions will be modified": localizer.cmdChmodCon,
            "Change file ownership": localizer.cmdChown,
            "File owner/group will be changed": localizer.cmdChownCon,
            "Display file contents": localizer.cmdCatFile,
            "File contents will be read and displayed": localizer.cmdCatFileCon,
            "Search text in files": localizer.cmdSearchText,
            "Will search for patterns in files": localizer.cmdSearchTextCon,
            "Search for files": localizer.cmdSearchFiles,
            "Will locate files matching criteria": localizer.cmdSearchFilesCon,
            "Download from URL": localizer.cmdDownload,
            "Data will be fetched from a remote server": localizer.cmdDownloadCon,
            "Download file": localizer.cmdDownloadFile,
            "File will be downloaded from the internet": localizer.cmdDownloadFileCon,
            "Git version control": localizer.cmdGit,
            "Repository operations will be performed": localizer.cmdGitCon,
            "Package manager": localizer.cmdPkgMgr,
            "Node.js packages will be installed/modified": localizer.cmdNodePkgCon,
            "Python packages will be installed/modified": localizer.cmdPyPkgCon,
            "Homebrew package manager": localizer.cmdBrew,
            "macOS packages will be installed/modified": localizer.cmdBrewCon,
            "Docker container management": localizer.cmdDocker,
            "Containers/images will be created or modified": localizer.cmdDockerCon,
            "Execute with superuser privileges": localizer.cmdSudo,
            "Command runs with elevated system permissions": localizer.cmdSudoCon,
            "Terminate process": localizer.cmdKill,
            "Running processes will be stopped": localizer.cmdKillCon,
            "Launch daemon control": localizer.cmdLaunchctl,
            "System services will be loaded/unloaded": localizer.cmdLaunchctlCon,
            "macOS defaults system": localizer.cmdDefaults,
            "System/application preferences will be modified": localizer.cmdDefaultsCon,
            "Create symbolic link": localizer.cmdSymlink,
            "A link to another file will be created": localizer.cmdSymlinkCon,
            "Archive/extract files": localizer.cmdArchive,
            "Files will be compressed or extracted": localizer.cmdArchiveCon,
            "Compress/extract ZIP": localizer.cmdZip,
            "Files will be archived or extracted": localizer.cmdZipCon,
            "Stream editor": localizer.cmdSed,
            "File contents will be modified in-place or streamed": localizer.cmdSedCon,
            "Text processing": localizer.cmdAwk,
            "Text data will be processed and transformed": localizer.cmdAwkCon,
            "Build Xcode project": localizer.cmdXcode,
            "Project will be compiled and built": localizer.cmdXcodeCon,
            "Run Swift": localizer.cmdSwift,
            "Swift code will be compiled or executed": localizer.cmdSwiftCon,
            "Run Python": localizer.cmdPython,
            "Python script will be executed": localizer.cmdPythonCon,
            "Run Node.js": localizer.cmdNode,
            "JavaScript will be executed": localizer.cmdNodeCon,
            "Execute shell script": localizer.cmdShell,
            "Shell commands will be run": localizer.cmdShellCon,
            "Print text": localizer.cmdEcho,
            "Text will be output to console or file": localizer.cmdEchoCon,
            "Create empty file": localizer.cmdTouch,
            "New empty file will be created or timestamp updated": localizer.cmdTouchCon,
            "View file head/tail": localizer.cmdHeadTail,
            "Beginning or end of file will be displayed": localizer.cmdHeadTailCon,
            "Count lines/words": localizer.cmdWc,
            "File statistics will be calculated": localizer.cmdWcCon,
            "Sort lines": localizer.cmdSort,
            "Lines will be sorted alphabetically or numerically": localizer.cmdSortCon,
            "Remove duplicates": localizer.cmdUniq,
            "Duplicate adjacent lines will be removed": localizer.cmdUniqCon,
            "Compare files": localizer.cmdDiff,
            "Differences between files will be shown": localizer.cmdDiffCon,
            "Safe operation": localizer.cmdSafe,
            "Read-only operation": localizer.cmdReadOnly,
            "List directory contents": localizer.cmdListDir,
            "Locate command path": localizer.cmdLocate,
            "List processes": localizer.cmdListProc,
            "Disk free space": localizer.cmdDiskFree,
            "Disk usage": localizer.cmdDiskUsage,
            "Standard repository operations (commit, push, pull, etc.)": localizer.cmdGitCon,
            "Installs or manages Node.js dependencies": localizer.cmdNodePkgCon,
            "Installs or manages Python packages": localizer.cmdPyPkgCon,
            "Installs or manages macOS software packages": localizer.cmdBrewCon,
        ]
        return map[desc] ?? desc
    }

    func moveCommandToBlacklist(id: String) {
        if let idx = commandRules.firstIndex(where: { $0.id == id }) {
            commandRules[idx].listType = .blacklist
            objectWillChange.send()
            saveCommandRules()
        }
    }

    func moveCommandToWhitelist(id: String) {
        if let idx = commandRules.firstIndex(where: { $0.id == id }) {
            commandRules[idx].listType = .whitelist
            objectWillChange.send()
            saveCommandRules()
        }
    }

    func moveCommandToUnclassified(id: String) {
        if let idx = commandRules.firstIndex(where: { $0.id == id }) {
            commandRules[idx].listType = .unclassified
            objectWillChange.send()
            saveCommandRules()
        }
    }

    func addCommandRule(pattern: String, listType: CommandRule.ListType, commandDesc: String = "", consequence: String = "") {
        let rule = CommandRule(pattern: pattern, listType: listType, commandDesc: commandDesc, consequence: consequence, source: .custom)
        commandRules.append(rule)
        saveCommandRules()
    }

    func removeCommandRule(id: String) {
        commandRules.removeAll { $0.id == id }
        commandRegexCache.removeValue(forKey: id)
        failedRegexRuleIds.remove(id)
        saveCommandRules()
    }

    // MARK: - Persistence

    private func loadAlerts() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: alertsPath)),
              let decoded = try? JSONDecoder().decode([GuardAlert].self, from: data) else { return }
        alerts = decoded
    }

    func saveAlerts() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        writeAtomically(data, to: alertsPath)
    }

    private func loadAlertRule() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: alertRulePath)),
              let decoded = try? JSONDecoder().decode(AlertRule.self, from: data) else { return }
        alertRule = decoded
    }

    func saveAlertRule() {
        alertRuleSaveTask?.cancel()
        alertRuleSaveTask = nil
        persistAlertRule()
    }

    func scheduleSaveAlertRule(after delay: TimeInterval = 0.3) {
        alertRuleSaveTask?.cancel()
        let nanoseconds = UInt64(delay * 1_000_000_000)
        alertRuleSaveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.alertRuleSaveTask = nil
            self?.persistAlertRule()
        }
    }

    private func persistAlertRule() {
        guard let data = try? JSONEncoder().encode(alertRule) else { return }
        writeAtomically(data, to: alertRulePath)
    }

    private func loadProtectedDirs() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: protectedDirsPath)),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        protectedDirs = decoded
    }

    private func saveProtectedDirs() {
        guard let data = try? JSONEncoder().encode(protectedDirs) else { return }
        writeAtomically(data, to: protectedDirsPath)
    }

    private func loadLifecycleEvents() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: lifecyclePath)),
              let decoded = try? JSONDecoder().decode([ProcessLifecycleEvent].self, from: data) else { return }
        processLifecycleEvents = decoded
        knownPids = Set(decoded.filter { $0.eventType == .launch }.map { $0.pid })
        for event in decoded where event.eventType == .launch {
            knownAgentPids[event.pid] = event.agentName
        }
    }

    func saveLifecycleEvents() {
        guard let data = try? JSONEncoder().encode(processLifecycleEvents) else { return }
        writeAtomically(data, to: lifecyclePath)
    }

    private func loadHourlyStats() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: hourlyStatsPath)),
              let decoded = try? JSONDecoder().decode([HourlyStats].self, from: data) else { return }
        hourlyStats = decoded
    }

    func saveHourlyStats() {
        guard let data = try? JSONEncoder().encode(hourlyStats) else { return }
        writeAtomically(data, to: hourlyStatsPath)
    }

    private func loadCommandRules() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: commandRulesPath)),
              let decoded = try? JSONDecoder().decode([CommandRule].self, from: data) else { return }
        commandRules = decoded
    }

    func saveCommandRules() {
        guard let data = try? JSONEncoder().encode(commandRules) else { return }
        writeAtomically(data, to: commandRulesPath)
    }

    private func writeAtomically(_ data: Data, to path: String) {
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}

extension CommandRule {
    static let defaultRules: [CommandRule] = [
        CommandRule(pattern: "rm -rf /", listType: .blacklist, commandDesc: "Recursive root delete", consequence: "Will delete ALL files on the entire system, making it unrecoverable", source: .default),
        CommandRule(pattern: "rm -rf ~", listType: .blacklist, commandDesc: "Recursive home delete", consequence: "Will delete ALL user files including documents, photos, and configuration", source: .default),
        CommandRule(pattern: "rm -rf ~/", listType: .blacklist, commandDesc: "Recursive home directory delete", consequence: "Will delete entire home directory tree without confirmation", source: .default),
        CommandRule(pattern: "mkfs", listType: .blacklist, commandDesc: "Format filesystem", consequence: "Will destroy all data on the target disk/partition", source: .default),
        CommandRule(pattern: "dd if=", listType: .blacklist, commandDesc: "Raw disk write", consequence: "Can overwrite disk data at the block level, causing data loss", source: .default),
        CommandRule(pattern: ":(){ :|:& };:", listType: .blacklist, commandDesc: "Fork bomb", consequence: "Will exhaust system resources, causing system freeze or crash", source: .default),
        CommandRule(pattern: "chmod -R 777 /", listType: .blacklist, commandDesc: "Recursive permission change on root", consequence: "Makes ALL system files world-readable/writable, massive security breach", source: .default),
        CommandRule(pattern: "> /dev/sd", listType: .blacklist, commandDesc: "Write directly to disk device", consequence: "Will corrupt or destroy disk data at the device level", source: .default),
        CommandRule(pattern: "chown -R", listType: .blacklist, commandDesc: "Recursive ownership change", consequence: "Changes owner of all files in directory tree, may break system", source: .default),
        CommandRule(pattern: "curl | sh", listType: .blacklist, commandDesc: "Pipe remote script to shell", consequence: "Downloads and executes untrusted code from the internet", source: .default),
        CommandRule(pattern: "curl | bash", listType: .blacklist, commandDesc: "Pipe remote script to bash", consequence: "Downloads and executes untrusted code from the internet", source: .default),
        CommandRule(pattern: "wget | sh", listType: .blacklist, commandDesc: "Download and execute script", consequence: "Downloads and runs arbitrary code without verification", source: .default),
        CommandRule(pattern: "sudo rm", listType: .blacklist, commandDesc: "Sudo delete", consequence: "Deletes files with superuser privileges, bypassing protections", source: .default),
        CommandRule(pattern: "launchctl unload", listType: .blacklist, commandDesc: "Unload launch daemon", consequence: "Stops system services, may cause system instability", source: .default),
        CommandRule(pattern: "killall", listType: .unclassified, commandDesc: "Kill all processes by name", consequence: "Terminates all processes matching the name, may cause data loss", source: .default),
        CommandRule(pattern: "git ", listType: .whitelist, commandDesc: "Git version control", consequence: "Standard repository operations (commit, push, pull, etc.)", source: .default),
        CommandRule(pattern: "npm ", listType: .whitelist, commandDesc: "Node.js package manager", consequence: "Installs or manages Node.js dependencies", source: .default),
        CommandRule(pattern: "pip ", listType: .whitelist, commandDesc: "Python package manager", consequence: "Installs or manages Python packages", source: .default),
        CommandRule(pattern: "brew ", listType: .whitelist, commandDesc: "Homebrew package manager", consequence: "Installs or manages macOS software packages", source: .default),
        CommandRule(pattern: "ls ", listType: .whitelist, commandDesc: "List directory contents", consequence: "Displays files and directories, read-only operation", source: .default),
        CommandRule(pattern: "cat ", listType: .whitelist, commandDesc: "Display file contents", consequence: "Reads and displays file content, read-only operation", source: .default),
        CommandRule(pattern: "echo ", listType: .whitelist, commandDesc: "Print text", consequence: "Outputs text to console or file, generally safe", source: .default),
        CommandRule(pattern: "grep ", listType: .whitelist, commandDesc: "Search text patterns", consequence: "Searches for patterns in files, read-only operation", source: .default),
        CommandRule(pattern: "find ", listType: .whitelist, commandDesc: "Search for files", consequence: "Locates files matching criteria, read-only operation", source: .default),
        CommandRule(pattern: "mkdir ", listType: .whitelist, commandDesc: "Create directory", consequence: "Creates a new directory, safe operation", source: .default),
        CommandRule(pattern: "touch ", listType: .whitelist, commandDesc: "Create empty file", consequence: "Creates empty file or updates timestamp, safe operation", source: .default),
        CommandRule(pattern: "cp ", listType: .whitelist, commandDesc: "Copy files", consequence: "Duplicates files to target location", source: .default),
        CommandRule(pattern: "mv ", listType: .whitelist, commandDesc: "Move/rename files", consequence: "Moves or renames files", source: .default),
        CommandRule(pattern: "which ", listType: .whitelist, commandDesc: "Locate command path", consequence: "Shows path to executable, read-only", source: .default),
        CommandRule(pattern: "ps ", listType: .whitelist, commandDesc: "List processes", consequence: "Displays running processes, read-only", source: .default),
        CommandRule(pattern: "df ", listType: .whitelist, commandDesc: "Disk free space", consequence: "Shows available disk space, read-only", source: .default),
        CommandRule(pattern: "du ", listType: .whitelist, commandDesc: "Disk usage", consequence: "Calculates directory sizes, read-only", source: .default),
    ]
}
