import Foundation
import UserNotifications

extension Notification.Name {
    static let traceFenceOpenApprovals = Notification.Name("TraceFenceOpenApprovals")
    static let traceFenceOpenSessions = Notification.Name("TraceFenceOpenSessions")
}

enum TraceFenceNotificationPermission: Equatable {
    case unknown
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    var canNotify: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: return true
        case .unknown, .notDetermined, .denied: return false
        }
    }
}

final class TraceFenceNotificationCoordinator: NSObject, UNUserNotificationCenterDelegate {
    static let shared = TraceFenceNotificationCoordinator()
    static let pendingDestinationKey = "TraceFenceIOS.pendingNotificationDestination"

    private let center = UNUserNotificationCenter.current()
    private let seenKey = "TraceFenceIOS.seenNotificationEvents.v1"
    private var configured = false
    private var seenOrder: [String]
    private var seen: Set<String>

    private override init() {
        let stored = UserDefaults.standard.stringArray(forKey: seenKey) ?? []
        seenOrder = stored
        seen = Set(stored)
        super.init()
    }

    func configure() {
        guard !configured else { return }
        configured = true
        center.delegate = self
    }

    func permission() async -> TraceFenceNotificationPermission {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    func requestPermission() async -> TraceFenceNotificationPermission {
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return await permission()
    }

    func scheduleTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = localized(
            zh: "TraceFence 通知已开启",
            en: "TraceFence notifications are ready",
            zhHant: "TraceFence 通知已開啟",
            ja: "TraceFence の通知を利用できます",
            ko: "TraceFence 알림이 준비됨",
            mt: "In-notifiki ta' TraceFence huma lesti"
        )
        content.body = localized(
            zh: "新的 Agent 回复、权限确认和任务完成状态会在这里提醒你。",
            en: "New agent replies, approval requests, and task completion updates will appear here.",
            zhHant: "新的 Agent 回覆、權限確認及工作完成狀態會在此提醒你。",
            ja: "Agent の新しい返信、承認リクエスト、タスク完了をここで通知します。",
            ko: "새 Agent 응답, 승인 요청 및 작업 완료 상태를 여기에서 알려드립니다.",
            mt: "Tweġibiet ġodda, talbiet għall-approvazzjoni u kompiti lesti jidhru hawn."
        )
        content.sound = .default
        content.userInfo = ["destination": "sessions"]
        schedule(content, identifier: "tracefence-notification-test")
    }

    func consume(
        previous: TraceFenceAgentControlResponse?,
        current: TraceFenceAgentControlResponse
    ) {
        configure()
        let approvals = current.pendingApprovals
        setBadgeCount(approvals.count)

        let previousApprovalIds = Set(previous?.pendingApprovals.map(\.id) ?? [])
        for approval in approvals where previous == nil || !previousApprovalIds.contains(approval.id) {
            let eventId = "approval:\(approval.id)"
            guard markSeen(eventId) else { continue }
            scheduleApproval(approval, badge: approvals.count)
        }

        guard let previous else { return }
        let oldSessions = Dictionary(uniqueKeysWithValues: notificationSessions(previous).map { ($0.id, $0) })
        let newSessions = Dictionary(uniqueKeysWithValues: notificationSessions(current).map { ($0.id, $0) })

        for (id, oldSession) in oldSessions {
            if let newSession = newSessions[id] {
                if isRunning(oldSession.phase), isCompleted(newSession.phase) {
                    let eventId = "task-completed:\(id):\(newSession.lastActivityAt ?? newSession.phase)"
                    guard markSeen(eventId) else { continue }
                    scheduleSessionEvent(
                        session: newSession,
                        title: localized(
                            zh: "任务已完成",
                            en: "Task completed",
                            zhHant: "工作已完成",
                            ja: "タスクが完了しました",
                            ko: "작업 완료",
                            mt: "Il-kompitu tlesta"
                        ),
                        prefix: "task",
                        badge: approvals.count
                    )
                    continue
                }

                let oldResponse = oldSession.lastResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let newResponse = newSession.lastResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !newResponse.isEmpty, newResponse != oldResponse else { continue }
                let eventId = "message:\(id):\(newSession.lastActivityAt ?? ""):\(String(newResponse.suffix(160)))"
                guard markSeen(eventId) else { continue }
                scheduleSessionEvent(
                    session: newSession,
                    title: localized(
                        zh: "Agent 有新回复",
                        en: "New agent reply",
                        zhHant: "Agent 有新回覆",
                        ja: "Agent から新しい返信があります",
                        ko: "Agent의 새 응답",
                        mt: "Tweġiba ġdida mill-Agent"
                    ),
                    prefix: "message",
                    badge: approvals.count
                )
            } else if isRunning(oldSession.phase) {
                let eventId = "session-ended:\(id):\(oldSession.lastActivityAt ?? oldSession.phase)"
                guard markSeen(eventId) else { continue }
                scheduleSessionEvent(
                    session: oldSession,
                    title: localized(
                        zh: "会话已结束",
                        en: "Session ended",
                        zhHant: "工作階段已結束",
                        ja: "セッションが終了しました",
                        ko: "세션 종료",
                        mt: "Is-sessjoni ntemmet"
                    ),
                    prefix: "session",
                    badge: approvals.count
                )
            }
        }
    }

    func clearBadge() {
        setBadgeCount(0)
    }

    private func scheduleApproval(_ approval: PendingApprovalSummary, badge: Int) {
        let content = UNMutableNotificationContent()
        content.title = localized(
            zh: "Agent 正在等待确认",
            en: "Agent approval required",
            zhHant: "Agent 正在等待確認",
            ja: "Agent の承認が必要です",
            ko: "Agent 승인이 필요합니다",
            mt: "L-Agent qed jistenna approvazzjoni"
        )
        let summary = approval.displayCommand ?? approval.displayReason ?? approval.displayTitle
        content.body = "\(approval.agentDisplayName) · \(approval.projectDisplayName)\n\(String(summary.prefix(220)))"
        content.sound = .default
        content.badge = NSNumber(value: badge)
        content.threadIdentifier = approval.sessionId
        content.userInfo = ["destination": "approvals", "approvalId": approval.id]
        schedule(content, identifier: "approval-\(approval.id)")
    }

    private func scheduleSessionEvent(
        session: AgentSessionSummary,
        title: String,
        prefix: String,
        badge: Int
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        let response = session.lastResponse?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = response?.isEmpty == false ? String(response!.prefix(220)) : session.phaseTitle
        content.body = "\(session.agentDisplayName) · \(session.displayTitle)\n\(detail)"
        content.sound = .default
        content.badge = NSNumber(value: badge)
        content.threadIdentifier = session.id
        content.userInfo = ["destination": "sessions", "sessionId": session.id]
        schedule(content, identifier: "\(prefix)-\(session.id)-\(UUID().uuidString)")
    }

    private func schedule(_ content: UNMutableNotificationContent, identifier: String) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    private func setBadgeCount(_ count: Int) {
        center.setBadgeCount(count) { _ in }
    }

    private func markSeen(_ id: String) -> Bool {
        guard seen.insert(id).inserted else { return false }
        seenOrder.append(id)
        if seenOrder.count > 500 {
            seenOrder.removeFirst(seenOrder.count - 500)
            seen = Set(seenOrder)
        }
        UserDefaults.standard.set(seenOrder, forKey: seenKey)
        return true
    }

    private func notificationSessions(_ response: TraceFenceAgentControlResponse) -> [AgentSessionSummary] {
        response.allSessions ?? response.sessions
    }

    private func isRunning(_ phase: String) -> Bool {
        ["processing", "compacting", "waitingApproval", "waitingInput"].contains(phase)
    }

    private func isCompleted(_ phase: String) -> Bool {
        phase == "done" || phase == "idle"
    }

    private func localized(
        zh: String,
        en: String,
        zhHant: String,
        ja: String,
        ko: String,
        mt: String
    ) -> String {
        AppLanguage.current.text(zh: zh, en: en, zhHant: zhHant, ja: ja, ko: ko, mt: mt)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let destination = response.notification.request.content.userInfo["destination"] as? String
        let name: Notification.Name = destination == "approvals" ? .traceFenceOpenApprovals : .traceFenceOpenSessions
        if let destination {
            UserDefaults.standard.set(destination, forKey: Self.pendingDestinationKey)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: name, object: nil)
        }
        completionHandler()
    }
}
