import Foundation
import Security

struct AgentSessionContextSnapshot: Equatable {
    var session: AgentSessionSummary
    var messages: [AgentContextMessage] = []
    var totalCount = 0
    var nextCursor: String?
    var hasMore = false
    var truncated = false
    var warning: String?
    var isLoading = false
    var error: String?
}

struct ConnectionActionFeedback: Identifiable, Equatable {
    enum Tone: Equatable {
        case progress
        case success
        case failure
    }

    let id = UUID()
    var tone: Tone
    var message: String
}

struct RemoteActionQueueItem: Identifiable, Equatable {
    enum State: String, Equatable {
        case queued
        case sending
        case succeeded
        case failed

        var isActive: Bool { self == .queued || self == .sending }
    }

    let id: UUID
    var deduplicationKey: String
    var targetId: String
    var title: String
    var state: State
    var message: String
    var queuedAt: Date
    var updatedAt: Date
    var attempts: Int
}

private enum ConnectionFeedbackCopy {
    static var verifying: String { text("正在验证 Mac 连接", "Verifying the Mac connection", "正在驗證 Mac 連線", "Mac 接続を確認中", "Mac 연결 확인 중", "Qed tiġi vverifikata l-konnessjoni tal-Mac") }
    static var connected: String { text("Mac 连接成功", "Mac connected", "Mac 連線成功", "Mac に接続しました", "Mac 연결됨", "Il-Mac ġie konness") }
    static var connectFailed: String { text("Mac 连接失败", "Mac connection failed", "Mac 連線失敗", "Mac 接続に失敗しました", "Mac 연결 실패", "Il-konnessjoni tal-Mac falliet") }
    static var refreshInProgress: String { text("刷新正在进行中", "Refresh already in progress", "正在重新整理", "更新中です", "이미 새로 고치는 중", "L-aġġornament għadu għaddej") }
    static var refreshingData: String { text("正在刷新 Mac 数据", "Refreshing Mac data", "正在重新整理 Mac 資料", "Mac データを更新中", "Mac 데이터 새로 고치는 중", "Qed tiġi aġġornata d-data tal-Mac") }
    static var refreshFailed: String { text("刷新失败", "Refresh failed", "重新整理失敗", "更新に失敗しました", "새로 고침 실패", "L-aġġornament falla") }
    static var reconnecting: String { text("正在重新连接 Mac", "Reconnecting to Mac", "正在重新連線 Mac", "Mac に再接続中", "Mac에 다시 연결 중", "Qed terġa' tikkonnettja mal-Mac") }
    static var reconnected: String { text("已重新连接 Mac", "Reconnected to Mac", "已重新連線 Mac", "Mac に再接続しました", "Mac에 다시 연결됨", "Erġajt ikkonnettjajt mal-Mac") }
    static var reconnectFailed: String { text("重新连接失败", "Reconnection failed", "重新連線失敗", "再接続に失敗しました", "다시 연결 실패", "Il-konnessjoni mill-ġdid falliet") }
    static var refreshingSessions: String { text("正在刷新会话", "Refreshing sessions", "正在重新整理工作階段", "セッションを更新中", "세션 새로 고치는 중", "Qed jiġu aġġornati s-sessjonijiet") }
    static var refreshingContext: String { text("正在刷新会话内容", "Refreshing session content", "正在重新整理工作階段內容", "セッション内容を更新中", "세션 내용 새로 고치는 중", "Qed jiġi aġġornat il-kontenut tas-sessjoni") }
    static var contextRefreshed: String { text("会话内容已刷新", "Session content refreshed", "工作階段內容已重新整理", "セッション内容を更新しました", "세션 내용 새로 고침 완료", "Il-kontenut tas-sessjoni ġie aġġornat") }
    static var actionCompleted: String { text("Mac 已接受操作", "The Mac accepted the action", "Mac 已接受操作", "Mac が操作を受け付けました", "Mac에서 작업을 수락했습니다", "Il-Mac aċċetta l-azzjoni") }
    static var actionFailed: String { text("Mac 未执行这次操作", "The Mac did not perform the action", "Mac 未執行這次操作", "Mac は操作を実行しませんでした", "Mac에서 작업을 실행하지 않았습니다", "Il-Mac ma wettaqx l-azzjoni") }

    private static func text(_ zh: String, _ en: String, _ zhHant: String, _ ja: String, _ ko: String, _ mt: String) -> String {
        AppLanguage.current.text(zh: zh, en: en, zhHant: zhHant, ja: ja, ko: ko, mt: mt)
    }
}

@MainActor
final class ConnectionStore: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading(String)
        case loaded
        case failed(String)
    }

    @Published private(set) var connection: TraceFenceConnection?
    @Published private(set) var status: TraceFenceStatusResponse?
    @Published private(set) var agentControl: TraceFenceAgentControlResponse?
    @Published private(set) var sessionCatalog: [AgentSessionSummary] = []
    @Published private(set) var sessionCatalogTotal = 0
    @Published private(set) var sessionCatalogHasMore = false
    @Published private(set) var sessionCatalogLoading = false
    @Published private(set) var sessionCatalogError: String?
    @Published private(set) var sessionContexts: [String: AgentSessionContextSnapshot] = [:]
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isRefreshing = false
    @Published private(set) var actionFeedback: ConnectionActionFeedback?
    @Published private(set) var remoteActionQueue: [RemoteActionQueueItem] = []
    @Published private(set) var demoMode = false

    private let client: TraceFenceRemoteClient
    private let storageKey = "TraceFenceIOS.savedConnection.v1"
    private let pairingTokenKeychainService = "com.tracefence.sentinel.pairing"
    private let pairingTokenKeychainAccount = "saved-mac-token"
    private var bonjourResolver: TraceFenceBonjourResolver?
    private var discoveredBonjourEndpoints: [String] = []
    private var refreshTask: Task<Void, Never>?
    private var lastRefreshStartedAt: Date?
    private let softRefreshInterval: TimeInterval = 20
    private var isAccessAuthorized = false
    private var sessionCatalogCursor: String?
    private var sessionCatalogRequestKey = ""
    private let notifications = TraceFenceNotificationCoordinator.shared

    var presentedSessions: [AgentSessionSummary] {
        AgentSessionPresentationPolicy.visibleSessions(
            agentControl?.allSessions ?? agentControl?.sessions ?? [],
            adapters: status?.agentCore?.adapters
        )
    }

    var installedAgentSessions: [AgentSessionSummary] {
        AgentSessionPresentationPolicy.installedSessions(
            agentControl?.allSessions ?? agentControl?.sessions ?? [],
            adapters: status?.agentCore?.adapters
        )
    }

    init(client: TraceFenceRemoteClient = .live) {
        self.client = client
        load()
#if DEBUG
        configureUITestConnectionIfRequested()
#endif
    }

    deinit {
        refreshTask?.cancel()
        bonjourResolver?.stop()
    }

    func connectWithPairingText(_ text: String) async {
        guard requireAuthorizedAccess() else { return }
        demoMode = false
        announce(.progress, ConnectionFeedbackCopy.verifying)
        do {
            let connection = try parsePairingText(text)
            resetRemoteSnapshotForNewPairing()
            save(connection)
            let connected = await refresh()
            announce(
                connected ? .success : .failure,
                connected ? ConnectionFeedbackCopy.connected : currentFailureMessage(fallback: ConnectionFeedbackCopy.connectFailed)
            )
        } catch {
            state = .failed(error.localizedDescription)
            announce(.failure, error.localizedDescription)
        }
    }

    func connectManually(endpoint: String, token: String) async {
        guard requireAuthorizedAccess() else { return }
        demoMode = false
        let trimmedEndpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEndpoint.isEmpty, !trimmedToken.isEmpty else {
            state = .failed("请填写 Mac 地址和配对密钥。".tfLocalized)
            announce(.failure, "请填写 Mac 地址和配对密钥。".tfLocalized)
            return
        }
        announce(.progress, ConnectionFeedbackCopy.verifying)
        let normalized = normalizedEndpoint(trimmedEndpoint)
        resetRemoteSnapshotForNewPairing()
        save(TraceFenceConnection(
            endpoint: normalized,
            token: trimmedToken,
            accessEndpoints: [
                TraceFenceAccessEndpoint(url: normalized, label: "手动地址".tfLocalized, kind: .manual)
            ]
        ))
        let connected = await refresh()
        announce(
            connected ? .success : .failure,
            connected ? ConnectionFeedbackCopy.connected : currentFailureMessage(fallback: ConnectionFeedbackCopy.connectFailed)
        )
    }

    @discardableResult
    func refresh(force: Bool = true, showLoading: Bool = true) async -> Bool {
        guard isAccessAuthorized else { return false }
        if demoMode {
            state = .loaded
            lastUpdated = Date()
            return true
        }
        guard !isRefreshing else { return false }
        guard let connection else {
            state = .idle
            status = nil
            return false
        }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < softRefreshInterval {
            return true
        }
        if !force, let lastRefreshStartedAt, Date().timeIntervalSince(lastRefreshStartedAt) < 5 {
            return true
        }

        isRefreshing = true
        lastRefreshStartedAt = Date()
        defer { isRefreshing = false }
        if showLoading {
            state = .loading("正在连接 Mac".tfLocalized)
        }
        do {
            let (resolvedConnection, response) = try await resolveReachableConnection(connection)
            if resolvedConnection != connection {
                save(resolvedConnection)
            }
            let control = try await client.fetchAgentControl(resolvedConnection)
            status = response
            applyAgentControl(control)
            if sessionCatalog.isEmpty {
                let discovered = control.allSessions ?? control.sessions
                sessionCatalog = discovered
                sessionCatalogTotal = discovered.count
            }
            lastUpdated = Date()
            state = .loaded
            return true
        } catch {
            state = .failed(error.localizedDescription)
            return false
        }
    }

    func refreshFromUser() async {
        guard connection != nil else {
            announce(.failure, "请先配对一台 Mac。".tfLocalized)
            return
        }
        guard !isRefreshing else {
            announce(.progress, ConnectionFeedbackCopy.refreshInProgress)
            return
        }
        announce(.progress, ConnectionFeedbackCopy.refreshingData)
        let succeeded = await refresh(force: true, showLoading: true)
        announce(
            succeeded ? .success : .failure,
            succeeded
                ? AppLanguage.current.text(
                    zh: "刷新完成 · \(Date().tfShortTimeText)",
                    en: "Refreshed · \(Date().tfShortTimeText)",
                    zhHant: "重新整理完成 · \(Date().tfShortTimeText)",
                    ja: "更新完了 · \(Date().tfShortTimeText)",
                    ko: "새로 고침 완료 · \(Date().tfShortTimeText)",
                    mt: "Aġġornat · \(Date().tfShortTimeText)"
                )
                : currentFailureMessage(fallback: ConnectionFeedbackCopy.refreshFailed)
        )
    }

    func reconnectFromUser() async {
        guard connection != nil else {
            announce(.failure, "请先配对一台 Mac。".tfLocalized)
            return
        }
        guard !isRefreshing else {
            announce(.progress, "正在连接 Mac".tfLocalized)
            return
        }
        announce(.progress, ConnectionFeedbackCopy.reconnecting)
        let succeeded = await refresh(force: true, showLoading: true)
        announce(
            succeeded ? .success : .failure,
            succeeded ? ConnectionFeedbackCopy.reconnected : currentFailureMessage(fallback: ConnectionFeedbackCopy.reconnectFailed)
        )
    }

    func refreshSessionCatalogFromUser(query: String = "", scope: String = "all") async {
        announce(.progress, ConnectionFeedbackCopy.refreshingSessions)
        let connected = await refresh(force: true, showLoading: true)
        guard connected else {
            announce(.failure, currentFailureMessage(fallback: ConnectionFeedbackCopy.refreshFailed))
            return
        }
        await loadSessionCatalog(reset: true, query: query, scope: scope)
        if let sessionCatalogError {
            announce(.failure, sessionCatalogError)
        } else {
            announce(.success, AppLanguage.current.text(
                zh: "会话已刷新 · \(sessionCatalog.count) 项",
                en: "Sessions refreshed · \(sessionCatalog.count)",
                zhHant: "工作階段已重新整理 · \(sessionCatalog.count) 項",
                ja: "セッション更新完了 · \(sessionCatalog.count) 件",
                ko: "세션 새로 고침 완료 · \(sessionCatalog.count)개",
                mt: "Sessjonijiet aġġornati · \(sessionCatalog.count)"
            ))
        }
    }

    func refreshSessionContextFromUser(_ session: AgentSessionSummary) async {
        announce(.progress, ConnectionFeedbackCopy.refreshingContext)
        await loadSessionContext(session, force: true)
        if let error = sessionContexts[session.id]?.error {
            announce(.failure, error)
        } else {
            announce(.success, ConnectionFeedbackCopy.contextRefreshed)
        }
    }

    func dismissActionFeedback(id: UUID) {
        guard actionFeedback?.id == id else { return }
        actionFeedback = nil
    }

    var activeRemoteActionCount: Int {
        remoteActionQueue.filter { $0.state.isActive }.count
    }

    func remoteAction(forApprovalId approvalId: String) -> RemoteActionQueueItem? {
        remoteActionQueue.last { $0.deduplicationKey == "approval:\(approvalId)" }
    }

    func latestRemoteAction(forSessionId sessionId: String) -> RemoteActionQueueItem? {
        remoteActionQueue.last { $0.targetId == sessionId }
    }

    func clearCompletedRemoteActions() {
        remoteActionQueue.removeAll { !$0.state.isActive }
    }

    func refreshIfStale() async {
        await refresh(force: false, showLoading: false)
    }

    func loadSessionCatalog(reset: Bool, query: String = "", scope: String = "all") async {
        guard requireAuthorizedAccess() else { return }
        guard let connection else {
            sessionCatalogError = "请先配对一台 Mac。".tfLocalized
            return
        }

        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestKey = "\(scope)\u{0}\(normalizedQuery.lowercased())"
        if reset || requestKey != sessionCatalogRequestKey {
            sessionCatalogRequestKey = requestKey
            sessionCatalog = []
            sessionCatalogTotal = 0
            sessionCatalogCursor = nil
            sessionCatalogHasMore = false
            sessionCatalogError = nil
        }
        guard !sessionCatalogLoading else { return }
        if !reset, !sessionCatalogHasMore, !sessionCatalog.isEmpty { return }

        sessionCatalogLoading = true
        let expectedKey = requestKey
        let cursor = sessionCatalogCursor
        defer {
            if sessionCatalogRequestKey == expectedKey { sessionCatalogLoading = false }
        }

        do {
            let activeConnection = try await currentReachableConnection(connection)
            let response = try await client.fetchSessions(
                activeConnection,
                cursor,
                normalizedQuery,
                scope,
                40
            )
            guard sessionCatalogRequestKey == expectedKey else { return }
            if cursor == nil {
                sessionCatalog = response.sessions
            } else {
                sessionCatalog = mergedSessions(sessionCatalog, response.sessions)
            }
            sessionCatalogTotal = response.totalCount
            sessionCatalogCursor = response.nextCursor
            sessionCatalogHasMore = response.hasMore
            sessionCatalogError = nil
        } catch {
            guard sessionCatalogRequestKey == expectedKey else { return }
            let fallback = filteredFallbackSessions(query: normalizedQuery, scope: scope)
            if !fallback.isEmpty {
                sessionCatalog = fallback
                sessionCatalogTotal = fallback.count
                sessionCatalogCursor = nil
                sessionCatalogHasMore = false
                sessionCatalogError = nil
            } else {
                sessionCatalogError = error.localizedDescription
            }
        }
    }

    func loadSessionContext(_ session: AgentSessionSummary, older: Bool = false, force: Bool = false) async {
        guard requireAuthorizedAccess() else { return }
        guard let connection else { return }

        var snapshot = sessionContexts[session.id] ?? AgentSessionContextSnapshot(session: session)
        if snapshot.isLoading { return }
        if older, !snapshot.hasMore { return }
        if !older, !force, !snapshot.messages.isEmpty { return }
        snapshot.isLoading = true
        snapshot.error = nil
        sessionContexts[session.id] = snapshot

        do {
            let activeConnection = try await currentReachableConnection(connection)
            let response = try await client.fetchSessionContext(
                activeConnection,
                session.id,
                older ? snapshot.nextCursor : nil,
                120
            )
            var updated = sessionContexts[session.id] ?? snapshot
            updated.session = response.session
            if older {
                updated.messages = mergedContextMessages(response.messages, updated.messages)
            } else {
                updated.messages = response.messages
            }
            updated.totalCount = response.totalCount
            updated.nextCursor = response.nextCursor
            updated.hasMore = response.hasMore
            updated.truncated = response.truncated == true
            updated.warning = response.warning
            updated.isLoading = false
            updated.error = nil
            sessionContexts[session.id] = updated
        } catch {
            var updated = sessionContexts[session.id] ?? snapshot
            updated.isLoading = false
            updated.error = error.localizedDescription
            sessionContexts[session.id] = updated
        }
    }

    func setMonitoring(_ enabled: Bool) async {
        guard requireAuthorizedAccess() else { return }
        guard let connection else {
            state = .failed("请先配对一台 Mac。".tfLocalized)
            return
        }

        let loadingMessage = (enabled ? "正在启动 Mac 监控" : "正在停止 Mac 监控").tfLocalized
        state = .loading(loadingMessage)
        announce(.progress, loadingMessage)
        do {
            let activeConnection = try await currentReachableConnection(connection)
            let response = try await client.setMonitoring(activeConnection, enabled)
            let control = try await client.fetchAgentControl(activeConnection)
            status = response
            applyAgentControl(control)
            lastUpdated = Date()
            state = .loaded
            announce(.success, ConnectionFeedbackCopy.actionCompleted)
        } catch {
            state = .failed(error.localizedDescription)
            announce(.failure, error.localizedDescription)
        }
    }

    @discardableResult
    func resolveApproval(_ approval: PendingApprovalSummary, allow: Bool, answer: String? = nil) async -> Bool {
        guard requireAuthorizedAccess() else { return false }
        guard let connection else {
            state = .failed("请先配对一台 Mac。".tfLocalized)
            announce(.failure, "请先配对一台 Mac。".tfLocalized)
            return false
        }

        let queueTitle = AppLanguage.current.text(
            zh: "\(allow ? "批准" : "拒绝") · \(approval.displayTitle)",
            en: "\(allow ? "Approve" : "Deny") · \(approval.displayTitle)",
            zhHant: "\(allow ? "批准" : "拒絕") · \(approval.displayTitle)",
            ja: "\(allow ? "承認" : "拒否") · \(approval.displayTitle)",
            ko: "\(allow ? "승인" : "거부") · \(approval.displayTitle)",
            mt: "\(allow ? "Approva" : "Irrifjuta") · \(approval.displayTitle)"
        )
        guard let queuedAction = enqueueRemoteAction(
            key: "approval:\(approval.id)",
            targetId: approval.id,
            title: queueTitle,
            blockAfterSuccess: true
        ) else { return false }
        guard await waitForRemoteActionTurn(queuedAction) else { return false }

        let loadingMessage = (allow ? "正在批准 Agent 操作" : "正在拒绝 Agent 操作").tfLocalized
        state = .loading(loadingMessage)
        announce(.progress, loadingMessage)
        do {
            let activeConnection = try await currentReachableConnection(connection)
            let response = try await client.resolveApproval(activeConnection, approval.id, allow, answer, queuedAction)
            applyAgentControl(response)
            mergeCatalogUpdates(response.allSessions ?? response.sessions)
            status = try? await client.fetchStatus(activeConnection)
            lastUpdated = Date()
            let message = response.message?.tfLocalized ?? (response.ok ? ConnectionFeedbackCopy.actionCompleted : "Mac 端没有接受这次审批操作。".tfLocalized)
            state = response.ok ? .loaded : .failed(message)
            finishRemoteAction(queuedAction, succeeded: response.ok, message: message)
            announce(response.ok ? .success : .failure, message)
            return response.ok
        } catch {
            state = .failed(error.localizedDescription)
            finishRemoteAction(queuedAction, succeeded: false, message: error.localizedDescription)
            announce(.failure, error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func controlSession(_ session: AgentSessionSummary, command: AgentSessionCommand, instruction: String? = nil) async -> Bool {
        guard requireAuthorizedAccess() else { return false }
        guard let connection else {
            state = .failed("请先配对一台 Mac。".tfLocalized)
            announce(.failure, "请先配对一台 Mac。".tfLocalized)
            return false
        }


        let actionName: String
        switch command {
        case .interrupt: actionName = session.isCodexNative ? "中断".tfLocalized : "暂停".tfLocalized
        case .resume: actionName = "发送指令".tfLocalized
        case .terminate: actionName = "终止".tfLocalized
        }
        let commandKey: String
        switch command {
        case .interrupt: commandKey = "interrupt"
        case .resume: commandKey = "resume"
        case .terminate: commandKey = "terminate"
        }
        guard let queuedAction = enqueueRemoteAction(
            key: "session:\(session.id):\(commandKey)",
            targetId: session.id,
            title: "\(actionName) · \(session.displayTitle)"
        ) else { return false }
        guard await waitForRemoteActionTurn(queuedAction) else { return false }

        let hasInstruction = instruction?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        switch command {
        case .interrupt:
            state = .loading("正在暂停 Agent 任务".tfLocalized)
        case .resume:
            state = .loading((hasInstruction ? "正在发送指令" : "正在恢复 Agent 任务").tfLocalized)
        case .terminate:
            state = .loading("正在终止 Agent 任务".tfLocalized)
        }
        if case .loading(let message) = state { announce(.progress, message) }
        do {
            let activeConnection = try await currentReachableConnection(connection)
            let response = try await client.controlSession(activeConnection, session.id, command, instruction, queuedAction)
            applyAgentControl(response)
            mergeCatalogUpdates(response.allSessions ?? response.sessions)
            status = try? await client.fetchStatus(activeConnection)
            lastUpdated = Date()
            let message = response.message?.tfLocalized ?? (response.ok ? ConnectionFeedbackCopy.actionCompleted : "Mac 端没有执行这次远程控制。".tfLocalized)
            state = response.ok ? .loaded : .failed(message)
            finishRemoteAction(queuedAction, succeeded: response.ok, message: message)
            announce(response.ok ? .success : .failure, message)
            return response.ok
        } catch {
            state = .failed(error.localizedDescription)
            finishRemoteAction(queuedAction, succeeded: false, message: error.localizedDescription)
            announce(.failure, error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func launchSession(_ target: AgentLaunchTargetSummary, instruction: String? = nil) async -> Bool {
        guard requireAuthorizedAccess() else { return false }
        guard let connection else {
            state = .failed("请先配对一台 Mac。".tfLocalized)
            return false
        }
        guard target.installed else {
            state = .failed(AppLanguage.current.text(
                zh: "\(target.controlConsoleName) 没有在这台 Mac 上安装，无法创建会话。",
                en: "\(target.controlConsoleName) is not installed on this Mac, so a session cannot be created.",
                zhHant: "此 Mac 未安裝 \(target.controlConsoleName)，因此無法建立工作階段。",
                ja: "この Mac には \(target.controlConsoleName) がインストールされていないため、セッションを作成できません。",
                ko: "이 Mac에 \(target.controlConsoleName)이(가) 설치되어 있지 않아 세션을 만들 수 없습니다.",
                mt: "\(target.controlConsoleName) mhuwiex installat fuq dan il-Mac, għalhekk ma tistax tinħoloq sessjoni."
            ))
            return false
        }

        guard let queuedAction = enqueueRemoteAction(
            key: "launch:\(target.id)",
            targetId: target.id,
            title: AppLanguage.current.text(
                zh: "新建 · \(target.controlConsoleName)",
                en: "New session · \(target.controlConsoleName)",
                zhHant: "新增 · \(target.controlConsoleName)",
                ja: "新規 · \(target.controlConsoleName)",
                ko: "새 세션 · \(target.controlConsoleName)",
                mt: "Sessjoni ġdida · \(target.controlConsoleName)"
            )
        ) else { return false }
        guard await waitForRemoteActionTurn(queuedAction) else { return false }

        state = .loading(AppLanguage.current.text(
            zh: "正在创建 \(target.controlConsoleName) 会话",
            en: "Creating a \(target.controlConsoleName) session",
            zhHant: "正在建立 \(target.controlConsoleName) 工作階段",
            ja: "\(target.controlConsoleName) セッションを作成中",
            ko: "\(target.controlConsoleName) 세션 생성 중",
            mt: "Qed tinħoloq sessjoni \(target.controlConsoleName)"
        ))
        if case .loading(let message) = state { announce(.progress, message) }
        do {
            let activeConnection = try await currentReachableConnection(connection)
            let response = try await client.launchSession(activeConnection, target.id, instruction, queuedAction)
            applyAgentControl(response)
            mergeCatalogUpdates(response.allSessions ?? response.sessions)
            status = try? await client.fetchStatus(activeConnection)
            lastUpdated = Date()
            let message = response.message?.tfLocalized ?? (response.ok ? ConnectionFeedbackCopy.actionCompleted : "Mac 端没有创建这个会话。".tfLocalized)
            state = response.ok ? .loaded : .failed(message)
            finishRemoteAction(queuedAction, succeeded: response.ok, message: message)
            announce(response.ok ? .success : .failure, message)
            return response.ok
        } catch {
            state = .failed(error.localizedDescription)
            finishRemoteAction(queuedAction, succeeded: false, message: error.localizedDescription)
            announce(.failure, error.localizedDescription)
            return false
        }
    }

    @discardableResult
    func relaunchSession(_ session: AgentSessionSummary, instruction: String? = nil) async -> Bool {
        guard requireAuthorizedAccess() else { return false }
        guard let connection else {
            state = .failed("请先配对一台 Mac。".tfLocalized)
            return false
        }
        guard session.canStartContinuation else {
            state = .failed("这个任务没有可接管的 Agent 目标。".tfLocalized)
            return false
        }

        guard let queuedAction = enqueueRemoteAction(
            key: "relaunch:\(session.id)",
            targetId: session.id,
            title: "\("接管任务".tfLocalized) · \(session.displayTitle)"
        ) else { return false }
        guard await waitForRemoteActionTurn(queuedAction) else { return false }

        state = .loading(AppLanguage.current.text(
            zh: "正在接管 \(session.continuationControlTitle)",
            en: "Taking over \(session.continuationControlTitle)",
            zhHant: "正在接管 \(session.continuationControlTitle)",
            ja: "\(session.continuationControlTitle) を引き継ぎ中",
            ko: "\(session.continuationControlTitle) 인계 중",
            mt: "Qed jieħu l-kontroll ta' \(session.continuationControlTitle)"
        ))
        if case .loading(let message) = state { announce(.progress, message) }
        do {
            let activeConnection = try await currentReachableConnection(connection)
            let response = try await client.relaunchSession(
                activeConnection,
                session,
                instruction,
                queuedAction
            )
            applyAgentControl(response)
            mergeCatalogUpdates(response.allSessions ?? response.sessions)
            status = try? await client.fetchStatus(activeConnection)
            lastUpdated = Date()
            let message = response.message?.tfLocalized ?? (response.ok ? ConnectionFeedbackCopy.actionCompleted : "Mac 端没有接管这个任务。".tfLocalized)
            state = response.ok ? .loaded : .failed(message)
            finishRemoteAction(queuedAction, succeeded: response.ok, message: message)
            announce(response.ok ? .success : .failure, message)
            return response.ok
        } catch {
            state = .failed(error.localizedDescription)
            finishRemoteAction(queuedAction, succeeded: false, message: error.localizedDescription)
            announce(.failure, error.localizedDescription)
            return false
        }
    }

    func clearConnection() {
        UserDefaults.standard.removeObject(forKey: storageKey)
        deletePairingToken()
        connection = nil
        status = nil
        agentControl = nil
        sessionCatalog = []
        sessionCatalogTotal = 0
        sessionCatalogHasMore = false
        sessionCatalogLoading = false
        sessionCatalogError = nil
        sessionCatalogCursor = nil
        sessionCatalogRequestKey = ""
        sessionContexts = [:]
        lastUpdated = nil
        state = .idle
        actionFeedback = nil
        remoteActionQueue = []
        demoMode = false
        notifications.clearBadge()
    }

    func enableReviewDemo() {
        let now = ISO8601DateFormatter().string(from: Date())
        let statusJSON = """
        {
          "ok": true,
          "version": 2,
          "app": {"name": "TraceFence Agent Core", "version": "1.6.4", "build": "1604"},
          "gateway": {"running": true, "endpoint": "demo://local-mac", "port": 17896, "lastRequest": "review-demo"},
          "subscription": {"channel": "appStore", "tier": "standard", "active": true, "enhanced": false},
          "system": {
            "monitoring": true,
            "disk": {"totalGB": 494.4, "usedGB": 286.1, "freeGB": 208.3, "usedPercent": 57.9},
            "hardware": {"cpuUsage": 18.0, "memoryPressure": 31.0, "processCount": 412, "uptimeSeconds": 86400}
          },
          "connectivity": {"noBackend": true, "localAddresses": ["demo://local-mac"], "modes": []},
          "agentCore": {
            "connected": true,
            "coreVersion": "1.6.4",
            "protocolVersion": 1,
            "message": "Read-only App Review demo",
            "adapters": [
              {"id": "codex", "displayName": "Codex", "operational": true, "controlAvailable": true},
              {"id": "claude", "displayName": "Claude Code", "operational": true, "applicationInstalled": true, "controlAvailable": true},
              {"id": "grok", "displayName": "Grok CLI", "operational": true, "commandInstalled": true, "controlAvailable": true}
            ]
          }
        }
        """
        let controlJSON = """
        {
          "ok": true,
          "version": 2,
          "generatedAt": "\(now)",
          "summary": {"sessionCount": 3, "activeSessionCount": 1, "pendingApprovalCount": 1, "processingCount": 1, "interruptedCount": 0},
          "sessions": [
            {"id": "demo-codex", "adapterId": "codex", "agentType": "Codex", "project": "TraceFence", "cwd": "/Users/demo/Projects/TraceFence", "phase": "processing", "startedAt": "\(now)", "lastActivityAt": "\(now)", "title": "Prepare the next release", "lastToolName": "xcodebuild", "lastToolStatus": "running", "statusLineText": "Running on the paired Mac", "controlMode": "display_only", "controlAvailable": false, "controlReason": "review_demo", "contextAvailable": false},
            {"id": "demo-claude", "adapterId": "claude", "agentType": "Claude Code", "project": "Documentation", "cwd": "/Users/demo/Projects/Documentation", "phase": "idle", "startedAt": "\(now)", "lastActivityAt": "\(now)", "title": "Review technical documentation", "lastToolName": "Read", "lastToolStatus": "completed", "statusLineText": "Ready for another instruction", "controlMode": "display_only", "controlAvailable": false, "controlReason": "review_demo", "contextAvailable": false},
            {"id": "demo-grok", "adapterId": "grok", "agentType": "Grok CLI", "project": "Research", "cwd": "/Users/demo/Projects/Research", "phase": "done", "startedAt": "\(now)", "lastActivityAt": "\(now)", "title": "Summarize release feedback", "lastToolName": "Search", "lastToolStatus": "completed", "statusLineText": "Completed", "controlMode": "display_only", "controlAvailable": false, "controlReason": "review_demo", "contextAvailable": false}
          ],
          "allSessions": [
            {"id": "demo-codex", "adapterId": "codex", "agentType": "Codex", "project": "TraceFence", "cwd": "/Users/demo/Projects/TraceFence", "phase": "processing", "startedAt": "\(now)", "lastActivityAt": "\(now)", "title": "Prepare the next release", "lastToolName": "xcodebuild", "lastToolStatus": "running", "statusLineText": "Running on the paired Mac", "controlMode": "display_only", "controlAvailable": false, "controlReason": "review_demo", "contextAvailable": false},
            {"id": "demo-claude", "adapterId": "claude", "agentType": "Claude Code", "project": "Documentation", "cwd": "/Users/demo/Projects/Documentation", "phase": "idle", "startedAt": "\(now)", "lastActivityAt": "\(now)", "title": "Review technical documentation", "lastToolName": "Read", "lastToolStatus": "completed", "statusLineText": "Ready for another instruction", "controlMode": "display_only", "controlAvailable": false, "controlReason": "review_demo", "contextAvailable": false},
            {"id": "demo-grok", "adapterId": "grok", "agentType": "Grok CLI", "project": "Research", "cwd": "/Users/demo/Projects/Research", "phase": "done", "startedAt": "\(now)", "lastActivityAt": "\(now)", "title": "Summarize release feedback", "lastToolName": "Search", "lastToolStatus": "completed", "statusLineText": "Completed", "controlMode": "display_only", "controlAvailable": false, "controlReason": "review_demo", "contextAvailable": false}
          ],
          "pendingApprovals": [
            {"id": "demo-approval", "kind": "permission", "actionType": "command", "sessionId": "demo-codex", "agentType": "Codex", "project": "/Users/demo/Projects/TraceFence", "title": "Run command", "detail": "Review demo request", "command": "xcodebuild -scheme TraceFence", "workingDirectory": "/Users/demo/Projects/TraceFence", "reason": "The agent needs permission before running the build.", "requestedAt": "\(now)", "risk": "medium", "requiresTextAnswer": false}
          ],
          "recentEvents": []
        }
        """

        let decoder = JSONDecoder()
        guard let statusData = statusJSON.data(using: .utf8),
              let controlData = controlJSON.data(using: .utf8),
              let demoStatus = try? decoder.decode(TraceFenceStatusResponse.self, from: statusData),
              let demoControl = try? decoder.decode(TraceFenceAgentControlResponse.self, from: controlData) else {
            state = .failed("无法载入只读演示。".tfLocalized)
            return
        }

        demoMode = true
        connection = TraceFenceConnection(
            name: AppLanguage.current.text(zh: "只读演示 Mac", en: "Read-only Demo Mac", zhHant: "唯讀示範 Mac", ja: "読み取り専用デモ Mac", ko: "읽기 전용 데모 Mac", mt: "Mac Demo Read-only"),
            endpoint: "demo://local-mac",
            token: "review-demo"
        )
        status = demoStatus
        agentControl = demoControl
        sessionCatalog = demoControl.allSessions ?? demoControl.sessions
        sessionCatalogTotal = sessionCatalog.count
        sessionCatalogHasMore = false
        sessionContexts = [:]
        lastUpdated = Date()
        state = .loaded
        actionFeedback = ConnectionActionFeedback(
            tone: .success,
            message: AppLanguage.current.text(zh: "已进入只读演示", en: "Read-only demo opened", zhHant: "已進入唯讀示範", ja: "読み取り専用デモを開きました", ko: "읽기 전용 데모가 열렸습니다", mt: "Infetaħ id-demo read-only")
        )
    }

    func setAccessAuthorized(_ authorized: Bool) {
        guard isAccessAuthorized != authorized else { return }
        isAccessAuthorized = authorized
        if authorized {
            notifications.configure()
            startBonjourDiscovery()
            startAutomaticRefresh()
            Task { await refresh(force: true, showLoading: connection != nil) }
        } else {
            refreshTask?.cancel()
            refreshTask = nil
            bonjourResolver?.stop()
            bonjourResolver = nil
            discoveredBonjourEndpoints = []
            isRefreshing = false
        }
    }

    private func announce(_ tone: ConnectionActionFeedback.Tone, _ message: String) {
        actionFeedback = ConnectionActionFeedback(tone: tone, message: message)
    }

    private func enqueueRemoteAction(
        key: String,
        targetId: String,
        title: String,
        blockAfterSuccess: Bool = false
    ) -> UUID? {
        if let existing = remoteActionQueue.last(where: { item in
            item.deduplicationKey == key && (item.state.isActive || (blockAfterSuccess && item.state == .succeeded))
        }) {
            announce(existing.state == .succeeded ? .success : .progress, existing.message)
            return nil
        }

        if let failedIndex = remoteActionQueue.lastIndex(where: { $0.deduplicationKey == key && $0.state == .failed }) {
            var retry = remoteActionQueue.remove(at: failedIndex)
            retry.state = .queued
            retry.message = AppLanguage.current.text(
                zh: "已重新进入操作队列",
                en: "Added back to the action queue",
                zhHant: "已重新加入操作佇列",
                ja: "操作キューに再追加しました",
                ko: "작업 대기열에 다시 추가됨",
                mt: "Reġa' ddaħħal fil-kju tal-azzjonijiet"
            )
            retry.updatedAt = Date()
            retry.attempts += 1
            remoteActionQueue.append(retry)
            announce(.progress, retry.message)
            return retry.id
        }

        let now = Date()
        let id = UUID()
        remoteActionQueue.append(RemoteActionQueueItem(
            id: id,
            deduplicationKey: key,
            targetId: targetId,
            title: title,
            state: .queued,
            message: AppLanguage.current.text(
                zh: "已进入操作队列",
                en: "Added to the action queue",
                zhHant: "已加入操作佇列",
                ja: "操作キューに追加しました",
                ko: "작업 대기열에 추가됨",
                mt: "Miżjud fil-kju tal-azzjonijiet"
            ),
            queuedAt: now,
            updatedAt: now,
            attempts: 1
        ))
        trimRemoteActionQueue()
        announce(.progress, remoteActionQueue.last?.message ?? title)
        return id
    }

    private func waitForRemoteActionTurn(_ id: UUID) async -> Bool {
        while !Task.isCancelled {
            guard let index = remoteActionQueue.firstIndex(where: { $0.id == id }) else { return false }
            guard let firstActive = remoteActionQueue.first(where: { $0.state.isActive }) else { return false }
            if firstActive.id == id {
                if remoteActionQueue[index].state == .queued {
                    remoteActionQueue[index].state = .sending
                    remoteActionQueue[index].message = AppLanguage.current.text(
                        zh: "正在发送到 Mac",
                        en: "Sending to Mac",
                        zhHant: "正在傳送到 Mac",
                        ja: "Mac に送信中",
                        ko: "Mac으로 보내는 중",
                        mt: "Qed jintbagħat lill-Mac"
                    )
                    remoteActionQueue[index].updatedAt = Date()
                    announce(.progress, remoteActionQueue[index].message)
                    await Task.yield()
                }
                return true
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        finishRemoteAction(
            id,
            succeeded: false,
            message: AppLanguage.current.text(
                zh: "操作已取消，可重试",
                en: "Action cancelled; you can retry",
                zhHant: "操作已取消，可重試",
                ja: "操作はキャンセルされました。再試行できます",
                ko: "작업이 취소되었습니다. 다시 시도할 수 있습니다",
                mt: "L-azzjoni ġiet ikkanċellata; tista' terġa' tipprova"
            )
        )
        return false
    }

    private func finishRemoteAction(_ id: UUID, succeeded: Bool, message: String) {
        guard let index = remoteActionQueue.firstIndex(where: { $0.id == id }) else { return }
        remoteActionQueue[index].state = succeeded ? .succeeded : .failed
        remoteActionQueue[index].message = message
        remoteActionQueue[index].updatedAt = Date()
    }

    private func trimRemoteActionQueue() {
        guard remoteActionQueue.count > 50 else { return }
        while remoteActionQueue.count > 50,
              let index = remoteActionQueue.firstIndex(where: { !$0.state.isActive }) {
            remoteActionQueue.remove(at: index)
        }
    }

    private func currentFailureMessage(fallback: String) -> String {
        if case .failed(let message) = state, !message.isEmpty { return message }
        return fallback
    }

    private func requireAuthorizedAccess() -> Bool {
        if demoMode {
            state = .loaded
            announce(.failure, AppLanguage.current.text(
                zh: "只读演示不会向任何 Mac 发送操作。",
                en: "The read-only demo does not send actions to any Mac.",
                zhHant: "唯讀示範不會向任何 Mac 傳送操作。",
                ja: "読み取り専用デモは Mac に操作を送信しません。",
                ko: "읽기 전용 데모는 Mac에 작업을 보내지 않습니다.",
                mt: "Id-demo read-only ma jibgħat ebda azzjoni lil Mac."
            ))
            return false
        }
        guard isAccessAuthorized else {
            state = .failed(AppLanguage.current.text(
                zh: "请先使用 Face ID、Touch ID 或设备密码解锁。",
                en: "Unlock with Face ID, Touch ID, or the device passcode first.",
                zhHant: "請先使用 Face ID、Touch ID 或裝置密碼解鎖。",
                ja: "先に Face ID、Touch ID、またはデバイスのパスコードでロックを解除してください。",
                ko: "먼저 Face ID, Touch ID 또는 기기 암호로 잠금을 해제하세요.",
                mt: "L-ewwel iftaħ b'Face ID, Touch ID jew il-kodiċi tal-apparat."
            ))
            return false
        }
        return true
    }

    private func mergeCatalogUpdates(_ updates: [AgentSessionSummary]) {
        guard !sessionCatalog.isEmpty, !updates.isEmpty else { return }
        sessionCatalog = mergedSessions(sessionCatalog, updates)
    }

    private func applyAgentControl(_ response: TraceFenceAgentControlResponse) {
        let previous = agentControl
        agentControl = response
        notifications.consume(previous: previous, current: response)
    }

    private func mergedSessions(_ existing: [AgentSessionSummary], _ incoming: [AgentSessionSummary]) -> [AgentSessionSummary] {
        var byId = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        var order = existing.map(\.id)
        for session in incoming {
            if byId[session.id] == nil { order.append(session.id) }
            byId[session.id] = session
        }
        return order.compactMap { byId[$0] }
    }

    private func mergedContextMessages(_ older: [AgentContextMessage], _ current: [AgentContextMessage]) -> [AgentContextMessage] {
        var seen = Set<String>()
        return (older + current).filter { seen.insert($0.id).inserted }
    }

    private func filteredFallbackSessions(query: String, scope: String) -> [AgentSessionSummary] {
        let all = agentControl?.allSessions ?? agentControl?.sessions ?? []
        let needle = query.lowercased()
        return all.filter { session in
            let inScope: Bool
            switch scope {
            case "active":
                inScope = session.phase != "idle" && session.phase != "done"
            case "attention":
                inScope = session.needsAttention
            case "controllable":
                inScope = session.controlAvailable == true
            default:
                inScope = true
            }
            guard inScope, !needle.isEmpty else { return inScope }
            return [
                session.displayTitle,
                session.project,
                session.cwd,
                session.agentDisplayName,
                session.engineLabel,
                session.lastResponse
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(needle) }
        }
    }

    func parsePairingText(_ text: String) throws -> TraceFenceConnection {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("tf://") {
            return try parseCompactPairingURL(trimmed)
        }
        guard let data = trimmed.data(using: .utf8) else {
            throw PairingError.invalidText
        }
        let payload = try JSONDecoder().decode(TraceFencePairingPayload.self, from: data)
        let endpoint = normalizedEndpoint(payload.endpoint)
        let port = payload.port ?? URLComponents(string: endpoint)?.port ?? 17895
        var connection = TraceFenceConnection(
            name: payload.service?.replacingOccurrences(of: " iOS Remote Control", with: "") ?? "我的 Mac".tfLocalized,
            endpoint: endpoint,
            token: payload.token,
            channelHint: payload.channel,
            bonjourHostName: payload.bonjourHostName,
            bonjourServiceName: payload.bonjourServiceName,
            localHostName: payload.localHostName,
            localAddresses: payload.localAddresses ?? [],
            accessEndpoints: payload.accessEndpoints ?? []
        )
        connection.addAccessEndpoint(url: endpoint, label: "扫码地址".tfLocalized, kind: endpoint.tfIsPrivateNetworkEndpoint ? .local : .manual)
        if let bonjourHostName = payload.bonjourHostName ?? payload.bonjourServiceName ?? payload.localHostName {
            connection.addAccessEndpoint(url: "http://\(bonjourHostName):\(port)", label: "Bonjour", kind: .bonjour)
        }
        connection.mergeLocalAddresses(payload.localAddresses ?? [], port: port)
        connection.accessEndpoints = Array(connection.prioritizedAccessEndpoints.prefix(16))
        return connection
    }

    private func parseCompactPairingURL(_ text: String) throws -> TraceFenceConnection {
        guard let components = URLComponents(string: text),
              components.scheme?.lowercased() == "tf",
              let host = components.host,
              !host.isEmpty else {
            throw PairingError.invalidText
        }
        let encodedToken = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let token = Self.hexToken(fromBase32: encodedToken) else {
            throw PairingError.invalidText
        }
        let port = components.port ?? 17_895
        guard (1...65_535).contains(port) else {
            throw PairingError.invalidText
        }

        var endpointComponents = URLComponents()
        endpointComponents.scheme = "http"
        endpointComponents.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        endpointComponents.port = port
        guard let endpointText = endpointComponents.string else {
            throw PairingError.invalidText
        }
        let endpoint = normalizedEndpoint(endpointText)
        var connection = TraceFenceConnection(
            name: "TraceFence",
            endpoint: endpoint,
            token: token
        )
        connection.addAccessEndpoint(
            url: endpoint,
            label: "扫码地址".tfLocalized,
            kind: endpoint.tfIsPrivateNetworkEndpoint ? .local : .manual
        )
        connection.accessEndpoints = Array(connection.prioritizedAccessEndpoints.prefix(16))
        return connection
    }

    private static func hexToken(fromBase32 value: String) -> String? {
        guard value.count == 52 else { return nil }
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        let lookup = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, UInt16($0.offset)) })
        var output = [UInt8]()
        output.reserveCapacity(32)
        var buffer: UInt16 = 0
        var bitCount = 0
        for character in value.uppercased().utf8 {
            guard let bits = lookup[character] else { return nil }
            buffer = (buffer << 5) | bits
            bitCount += 5
            if bitCount >= 8 {
                bitCount -= 8
                output.append(UInt8((buffer >> bitCount) & 0xff))
            }
            buffer = bitCount == 0 ? 0 : buffer & UInt16((1 << bitCount) - 1)
        }
        guard output.count == 32, buffer == 0 else { return nil }
        return output.map { String(format: "%02x", $0) }.joined()
    }

    private func currentReachableConnection(_ connection: TraceFenceConnection) async throws -> TraceFenceConnection {
        let (resolvedConnection, response) = try await resolveReachableConnection(connection)
        status = response
        if resolvedConnection != self.connection {
            save(resolvedConnection)
        }
        return resolvedConnection
    }

    private func connectionPort(_ connection: TraceFenceConnection) -> Int {
        URLComponents(string: connection.endpoint)?.port
            ?? connection.accessEndpoints.compactMap { URLComponents(string: $0.url)?.port }.first
            ?? 17895
    }

    private func discoveredEndpoints(port: Int) -> [String] {
        discoveredBonjourEndpoints.map { endpoint in
            guard URLComponents(string: endpoint)?.port == nil,
                  var components = URLComponents(string: endpoint) else { return endpoint }
            components.port = port
            return components.string ?? endpoint
        }
    }

    private func updatedConnection(
        from original: TraceFenceConnection,
        endpoint: String,
        status: TraceFenceStatusResponse
    ) -> TraceFenceConnection {
        var resolved = original
        let kind: TraceFenceAccessEndpointKind = endpoint.tfIsBonjourEndpoint ? .bonjour : (endpoint.tfIsPrivateNetworkEndpoint ? .local : .lastKnown)
        resolved.rememberSuccessfulEndpoint(endpoint, kind: kind)
        resolved.mergeLocalAddresses(status.connectivity?.localAddresses ?? [], port: status.gateway?.port ?? connectionPort(resolved))
        return resolved
    }

    private func migrateLoadedConnection(_ decoded: TraceFenceConnection) -> TraceFenceConnection {
        var migrated = decoded
        let port = connectionPort(decoded)
        migrated.addAccessEndpoint(url: decoded.endpoint, label: "已保存地址".tfLocalized, kind: decoded.endpoint.tfIsPrivateNetworkEndpoint ? .local : .manual)
        if let last = decoded.lastResolvedEndpoint {
            migrated.addAccessEndpoint(url: last, label: "上次成功".tfLocalized, kind: .lastKnown)
        }
        if let bonjour = decoded.bonjourHostName ?? decoded.bonjourServiceName ?? decoded.localHostName {
            migrated.addAccessEndpoint(url: "http://\(bonjour):\(port)", label: "Bonjour", kind: .bonjour)
        }
        migrated.mergeLocalAddresses(decoded.localAddresses, port: port)
        migrated.accessEndpoints = Array(migrated.prioritizedAccessEndpoints.prefix(16))
        return migrated
    }

    private func save(_ connection: TraceFenceConnection) {
        self.connection = connection
        if !connection.token.isEmpty {
            _ = storePairingToken(connection.token)
        }
        var metadata = connection
        metadata.token = ""
        if let data = try? JSONEncoder().encode(metadata) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func resetRemoteSnapshotForNewPairing() {
        status = nil
        agentControl = nil
        sessionCatalog = []
        sessionCatalogTotal = 0
        sessionCatalogHasMore = false
        sessionCatalogLoading = false
        sessionCatalogError = nil
        sessionCatalogCursor = nil
        sessionCatalogRequestKey = ""
        sessionContexts = [:]
        lastUpdated = nil
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              var decoded = try? JSONDecoder().decode(TraceFenceConnection.self, from: data) else {
            return
        }
        var token = loadPairingToken()
        if !decoded.token.isEmpty {
            // Migrate pairing data written by older builds out of UserDefaults.
            if storePairingToken(decoded.token) {
                token = decoded.token
            } else {
                // Preserve the legacy record until Keychain accepts the secure
                // replacement; deleting it here would silently unpair the Mac.
                connection = migrateLoadedConnection(decoded)
                return
            }
        }
        guard let token, !token.isEmpty else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }
        decoded.token = token
        let migrated = migrateLoadedConnection(decoded)
        save(migrated)
    }

    private func loadPairingToken() -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: pairingTokenKeychainService,
            kSecAttrAccount: pairingTokenKeychainAccount,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty else {
            return nil
        }
        return token
    }

    @discardableResult
    private func storePairingToken(_ token: String) -> Bool {
        guard let data = token.data(using: .utf8), !data.isEmpty else { return false }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: pairingTokenKeychainService,
            kSecAttrAccount: pairingTokenKeychainAccount
        ]
        let update: [CFString: Any] = [kSecValueData: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        guard updateStatus == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData] = data
        item[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    private func deletePairingToken() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: pairingTokenKeychainService,
            kSecAttrAccount: pairingTokenKeychainAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func resolveReachableConnection(
        _ original: TraceFenceConnection
    ) async throws -> (TraceFenceConnection, TraceFenceStatusResponse) {
        let port = connectionPort(original)
        let discoveredEndpoints = discoveredEndpoints(port: port)
        let candidates = Array((discoveredEndpoints + original.candidateEndpoints)
            .reduce(into: [String]()) { values, endpoint in
                if !values.contains(endpoint) { values.append(endpoint) }
            }
            .prefix(16))

        let outcome = await withTaskGroup(of: EndpointProbeResult.self, returning: EndpointProbeResult?.self) { group in
            for endpoint in candidates {
                group.addTask { @MainActor [client] in
                    do {
                        return EndpointProbeResult(
                            endpoint: endpoint,
                            // Probe exactly the endpoint attributed to this task.
                            // The normal client deliberately performs endpoint
                            // failover, which would otherwise report a fallback
                            // Core success as a foreground gateway success.
                            status: try await client.probeStatus(original, endpoint),
                            error: nil
                        )
                    } catch {
                        return EndpointProbeResult(endpoint: endpoint, status: nil, error: error)
                    }
                }
            }

            var firstFailure: EndpointProbeResult?
            var authenticationFailure: EndpointProbeResult?
            while let result = await group.next() {
                if result.status != nil {
                    group.cancelAll()
                    return result
                }
                if firstFailure == nil {
                    firstFailure = result
                }
                if let error = result.error as? TraceFenceRemoteClientError,
                   case .httpStatus(let status, _) = error,
                   status == 401 || status == 402 {
                    // Other candidates may be the same Mac's foreground app or
                    // background Core gateway and can already have the fresh token.
                    // Preserve the auth error for reporting only if every candidate
                    // fails instead of turning endpoint race timing into disconnects.
                    if authenticationFailure == nil || status == 402 {
                        authenticationFailure = result
                    }
                }
            }
            return authenticationFailure ?? firstFailure
        }

        if let outcome, let status = outcome.status {
            return (updatedConnection(from: original, endpoint: outcome.endpoint, status: status), status)
        }
        throw outcome?.error ?? TraceFenceRemoteClientError.unreachable(candidates, nil)
    }

    private func startBonjourDiscovery() {
        guard isAccessAuthorized, bonjourResolver == nil else { return }
        let resolver = TraceFenceBonjourResolver { [weak self] endpoints in
            Task { @MainActor in
                guard let self else { return }
                let changed = endpoints != self.discoveredBonjourEndpoints
                self.discoveredBonjourEndpoints = endpoints
                if changed, self.connection != nil {
                    await self.refresh(force: false, showLoading: false)
                }
            }
        }
        resolver.start()
        bonjourResolver = resolver
    }

    private func startAutomaticRefresh() {
        guard isAccessAuthorized, refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard !Task.isCancelled, let self, self.connection != nil else { continue }
                await self.refresh(force: false, showLoading: false)
            }
        }
    }

    private func normalizedEndpoint(_ endpoint: String) -> String {
        var text = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.contains("://") {
            text = "http://\(text)"
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }

#if DEBUG
    private func configureUITestConnectionIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let endpointIndex = arguments.firstIndex(of: "-TraceFenceUITestMockEndpoint"),
              arguments.indices.contains(endpointIndex + 1) else { return }
        let endpoint = normalizedEndpoint(arguments[endpointIndex + 1])
        let token: String
        if let tokenIndex = arguments.firstIndex(of: "-TraceFenceUITestMockToken"),
           arguments.indices.contains(tokenIndex + 1) {
            token = arguments[tokenIndex + 1]
        } else {
            token = "tracefence-ui-test-token"
        }
        connection = TraceFenceConnection(
            name: "TraceFence UI Test Mac",
            endpoint: endpoint,
            token: token,
            accessEndpoints: [
                TraceFenceAccessEndpoint(url: endpoint, label: "UI Test", kind: .manual)
            ]
        )
    }
#endif
}

private struct EndpointProbeResult {
    let endpoint: String
    let status: TraceFenceStatusResponse?
    let error: Error?
}

private final class TraceFenceBonjourResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    private let browser = NetServiceBrowser()
    private var services: [String: NetService] = [:]
    private let onChange: ([String]) -> Void

    init(onChange: @escaping ([String]) -> Void) {
        self.onChange = onChange
        super.init()
        browser.delegate = self
    }

    func start() {
        browser.searchForServices(ofType: "_tracefence._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        services.values.forEach { $0.stop() }
        services.removeAll()
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        let key = "\(service.name)|\(service.type)|\(service.domain)"
        services[key] = service
        service.delegate = self
        service.resolve(withTimeout: 4)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        let key = "\(service.name)|\(service.type)|\(service.domain)"
        services.removeValue(forKey: key)
        publish()
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        publish()
    }

    private func publish() {
        let endpoints = services.values.compactMap { service -> String? in
            guard let host = service.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
                  !host.isEmpty,
                  service.port > 0 else { return nil }
            var components = URLComponents()
            components.scheme = "http"
            components.host = host
            components.port = service.port
            return components.string
        }
        let unique = endpoints.reduce(into: [String]()) { values, endpoint in
            if !values.contains(endpoint) { values.append(endpoint) }
        }
        onChange(unique)
    }
}

private extension String {
    var tfIsPrivateNetworkEndpoint: Bool {
        guard let host = URLComponents(string: self)?.host else { return false }
        return host.tfIsPrivateNetworkHostForConnectionStore
    }

    var tfIsBonjourEndpoint: Bool {
        guard let host = URLComponents(string: self)?.host else { return false }
        return host.hasSuffix(".local")
    }

    var tfIsPrivateNetworkHostForConnectionStore: Bool {
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
}

enum PairingError: LocalizedError {
    case invalidText

    var errorDescription: String? {
        switch self {
        case .invalidText:
            return "配对内容不是有效文本。请从 Mac 端复制完整的 iOS 配对信息。".tfLocalized
        }
    }
}
