import Foundation
import UserNotifications
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
    var commandBlacklistEnabled: Bool = true
    var commandWhitelistEnabled: Bool = false
}

struct CommandRule: Identifiable, Codable {
    let id: String
    var pattern: String
    var isRegex: Bool
    var severity: GuardAlert.AlertSeverity
    var note: String

    init(pattern: String, isRegex: Bool = false, severity: GuardAlert.AlertSeverity = .critical, note: String = "") {
        self.id = UUID().uuidString
        self.pattern = pattern
        self.isRegex = isRegex
        self.severity = severity
        self.note = note
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
    @Published var commandBlacklist: [CommandRule] = []
    @Published var commandWhitelist: [CommandRule] = []

    private let alertsPath = NSHomeDirectory() + "/.aimaccleaner_alerts.json"
    private let alertRulePath = NSHomeDirectory() + "/.aimaccleaner_alert_rule.json"
    private let protectedDirsPath = NSHomeDirectory() + "/.aimaccleaner_protected_dirs.json"
    private let lifecyclePath = NSHomeDirectory() + "/.aimaccleaner_lifecycle.json"
    private let hourlyStatsPath = NSHomeDirectory() + "/.aimaccleaner_hourly_stats.json"
    private let blacklistPath = NSHomeDirectory() + "/.aimaccleaner_cmd_blacklist.json"
    private let whitelistPath = NSHomeDirectory() + "/.aimaccleaner_cmd_whitelist.json"
    private let maxAlerts = 500
    private let maxLifecycleEvents = 1000
    private let maxHourlyStats = 168

    private var recentDeleteEvents: [Date] = []
    private var recentModifyEvents: [Date] = []
    private var lastAlertTimes: [String: Date] = [:]
    private var knownPids: Set<pid_t> = []

    weak var localizer: Localizer?

    init() {
        loadAlerts()
        loadAlertRule()
        loadProtectedDirs()
        loadLifecycleEvents()
        loadHourlyStats()
        loadCommandBlacklist()
        loadCommandWhitelist()
        if commandBlacklist.isEmpty {
            commandBlacklist = CommandRule.defaultBlacklist
            saveCommandBlacklist()
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
        guard alertRule.processLaunchAlertEnabled else { return }

        let newPids = currentPids.subtracting(knownPids)
        let exitedPids = knownPids.subtracting(currentPids)

        for pid in newPids {
            guard let comm = pidCommMap[pid] else { continue }
            let args = pidArgsMap[pid] ?? ""
            let ppid = ppidMap[pid] ?? 0
            let agentName = resolveAgentName(comm: comm, args: args, ppid: ppid, pidCommMap: pidCommMap, pidArgsMap: pidArgsMap, ppidMap: ppidMap, agentKeywords: agentKeywords)

            guard agentName != (localizer?.systemProcess ?? "System Process") else { continue }

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

        for pid in exitedPids {
            let comm = "PID:\(pid)"
            let event = ProcessLifecycleEvent(
                id: UUID().uuidString,
                timestamp: Date(),
                eventType: .exit,
                pid: pid,
                ppid: 0,
                comm: comm,
                args: "",
                agentName: "—"
            )
            processLifecycleEvents.insert(event, at: 0)
        }

        if processLifecycleEvents.count > maxLifecycleEvents {
            processLifecycleEvents = Array(processLifecycleEvents.prefix(maxLifecycleEvents))
        }

        knownPids = currentPids
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
            }
            hourlyStats.append(stats)
        }

        if hourlyStats.count > maxHourlyStats {
            hourlyStats.sort { $0.hour < $1.hour }
            hourlyStats = Array(hourlyStats.suffix(maxHourlyStats))
        }
    }

    // MARK: - F37 Export

    func exportRecordsAsCSV(records: [OperationRecord]) -> String {
        var lines = ["ID,Timestamp,Agent,Operation,Path,Detail,FileSize,ProcessName,ToolInfo"]
        let formatter = ISO8601DateFormatter()
        for r in records {
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
        guard let data = try? encoder.encode(records) else { return "[]" }
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
        let filtered = records.filter { $0.timestamp >= startTime && $0.timestamp <= endTime }
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
        switch alert.severity {
        case .critical:
            content.sound = .defaultCritical
        case .warning:
            content.sound = .default
        case .info:
            content.sound = nil
        }

        let request = UNNotificationRequest(
            identifier: "agentguard_\(alert.alertType.rawValue)_\(alert.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[AgentWatch] Notification error: \(error.localizedDescription)")
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

    // MARK: - Command Blacklist/Whitelist

    func checkCommandBlacklist(command: String, agentName: String) {
        guard alertRule.commandBlacklistEnabled else { return }
        let cmdLower = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for rule in commandBlacklist {
            let matched: Bool
            if rule.isRegex {
                matched = (try? Regex(rule.pattern).firstMatch(in: cmdLower)) != nil
            } else {
                matched = cmdLower.contains(rule.pattern.lowercased())
            }
            if matched {
                let key = "cmd_blacklist_\(rule.id)"
                if shouldFireAlert(key: key) {
                    let alert = GuardAlert(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        alertType: .sensitiveContent,
                        severity: rule.severity,
                        title: localizer?.commandBlacklistAlertTitle ?? "Blacklisted Command Detected",
                        message: String(format: localizer?.commandBlacklistAlertMsg ?? "Agent %@ executed blacklisted command: %@", agentName, rule.pattern),
                        agentName: agentName,
                        targetPath: command,
                        detail: rule.note.isEmpty ? "Pattern: \(rule.pattern)" : rule.note
                    )
                    fireAlert(alert)
                }
                return
            }
        }
    }

    func isCommandWhitelisted(command: String) -> Bool {
        guard alertRule.commandWhitelistEnabled, !commandWhitelist.isEmpty else { return true }
        let cmdLower = command.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for rule in commandWhitelist {
            if rule.isRegex {
                if (try? Regex(rule.pattern).firstMatch(in: cmdLower)) != nil { return true }
            } else {
                if cmdLower.contains(rule.pattern.lowercased()) { return true }
            }
        }
        return false
    }

    func addBlacklistRule(pattern: String, isRegex: Bool = false, severity: GuardAlert.AlertSeverity = .critical, note: String = "") {
        let rule = CommandRule(pattern: pattern, isRegex: isRegex, severity: severity, note: note)
        commandBlacklist.append(rule)
        saveCommandBlacklist()
    }

    func removeBlacklistRule(id: String) {
        commandBlacklist.removeAll { $0.id == id }
        saveCommandBlacklist()
    }

    func addWhitelistRule(pattern: String, isRegex: Bool = false, note: String = "") {
        let rule = CommandRule(pattern: pattern, isRegex: isRegex, severity: .info, note: note)
        commandWhitelist.append(rule)
        saveCommandWhitelist()
    }

    func removeWhitelistRule(id: String) {
        commandWhitelist.removeAll { $0.id == id }
        saveCommandWhitelist()
    }

    // MARK: - Persistence

    private func loadAlerts() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: alertsPath)),
              let decoded = try? JSONDecoder().decode([GuardAlert].self, from: data) else { return }
        alerts = decoded
    }

    private func saveAlerts() {
        guard let data = try? JSONEncoder().encode(alerts) else { return }
        try? data.write(to: URL(fileURLWithPath: alertsPath))
    }

    private func loadAlertRule() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: alertRulePath)),
              let decoded = try? JSONDecoder().decode(AlertRule.self, from: data) else { return }
        alertRule = decoded
    }

    func saveAlertRule() {
        guard let data = try? JSONEncoder().encode(alertRule) else { return }
        try? data.write(to: URL(fileURLWithPath: alertRulePath))
    }

    private func loadProtectedDirs() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: protectedDirsPath)),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else { return }
        protectedDirs = decoded
    }

    private func saveProtectedDirs() {
        guard let data = try? JSONEncoder().encode(protectedDirs) else { return }
        try? data.write(to: URL(fileURLWithPath: protectedDirsPath))
    }

    private func loadLifecycleEvents() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: lifecyclePath)),
              let decoded = try? JSONDecoder().decode([ProcessLifecycleEvent].self, from: data) else { return }
        processLifecycleEvents = decoded
        knownPids = Set(decoded.filter { $0.eventType == .launch }.map { $0.pid })
    }

    func saveLifecycleEvents() {
        guard let data = try? JSONEncoder().encode(processLifecycleEvents) else { return }
        try? data.write(to: URL(fileURLWithPath: lifecyclePath))
    }

    private func loadHourlyStats() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: hourlyStatsPath)),
              let decoded = try? JSONDecoder().decode([HourlyStats].self, from: data) else { return }
        hourlyStats = decoded
    }

    func saveHourlyStats() {
        guard let data = try? JSONEncoder().encode(hourlyStats) else { return }
        try? data.write(to: URL(fileURLWithPath: hourlyStatsPath))
    }

    private func loadCommandBlacklist() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: blacklistPath)),
              let decoded = try? JSONDecoder().decode([CommandRule].self, from: data) else { return }
        commandBlacklist = decoded
    }

    func saveCommandBlacklist() {
        guard let data = try? JSONEncoder().encode(commandBlacklist) else { return }
        try? data.write(to: URL(fileURLWithPath: blacklistPath))
    }

    private func loadCommandWhitelist() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: whitelistPath)),
              let decoded = try? JSONDecoder().decode([CommandRule].self, from: data) else { return }
        commandWhitelist = decoded
    }

    func saveCommandWhitelist() {
        guard let data = try? JSONEncoder().encode(commandWhitelist) else { return }
        try? data.write(to: URL(fileURLWithPath: whitelistPath))
    }
}

extension CommandRule {
    static let defaultBlacklist: [CommandRule] = [
        CommandRule(pattern: "rm -rf /", severity: .critical, note: "Recursive root delete"),
        CommandRule(pattern: "rm -rf ~", severity: .critical, note: "Recursive home delete"),
        CommandRule(pattern: "rm -rf ~/", severity: .critical, note: "Recursive home directory delete"),
        CommandRule(pattern: "mkfs", severity: .critical, note: "Filesystem format"),
        CommandRule(pattern: "dd if=", severity: .critical, note: "Raw disk write"),
        CommandRule(pattern: ":(){ :|:& };:", severity: .critical, note: "Fork bomb"),
        CommandRule(pattern: "chmod -R 777 /", severity: .critical, note: "Recursive permission change on root"),
        CommandRule(pattern: "chown -R", severity: .warning, note: "Recursive ownership change"),
        CommandRule(pattern: "curl | sh", severity: .warning, note: "Pipe remote script to shell"),
        CommandRule(pattern: "curl | bash", severity: .warning, note: "Pipe remote script to bash"),
        CommandRule(pattern: "wget | sh", severity: .warning, note: "Download and execute script"),
        CommandRule(pattern: "> /dev/sd", severity: .critical, note: "Write directly to disk device"),
        CommandRule(pattern: "sudo rm", severity: .warning, note: "Sudo delete"),
        CommandRule(pattern: "launchctl unload", severity: .warning, note: "Unload launch daemon"),
        CommandRule(pattern: "killall", severity: .info, note: "Kill all processes by name"),
    ]
}
