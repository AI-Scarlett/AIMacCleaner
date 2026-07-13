import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case overview
    case monitor
    case sessions
    case approvals
    case settings

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .overview: return language.text(zh: "总览", en: "Overview", zhHant: "總覽", ja: "概要", ko: "개요", mt: "Ħarsa")
        case .monitor: return language.text(zh: "监控", en: "Monitor", zhHant: "監控", ja: "監視", ko: "모니터", mt: "Monitora")
        case .sessions: return language.text(zh: "会话", en: "Sessions", zhHant: "工作階段", ja: "セッション", ko: "세션", mt: "Sessj.")
        case .approvals: return language.text(zh: "确认", en: "Approvals", zhHant: "審批", ja: "承認", ko: "승인", mt: "Approva")
        case .settings: return language.text(zh: "设置", en: "Settings", zhHant: "設定", ja: "設定", ko: "설정", mt: "Issettjar")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.50percent"
        case .monitor: return "list.bullet.rectangle"
        case .sessions: return "bubble.left.and.text.bubble.right"
        case .approvals: return "checkmark.shield"
        case .settings: return "gearshape"
        }
    }
}

private struct DeferredView<Content: View>: View {
    private let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
    }
}

struct AppShellView: View {
    @EnvironmentObject private var store: ConnectionStore
    @State private var selectedTab: AppTab
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.english.rawValue

    init() {
        var initialTab = AppTab.overview
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "-TraceFenceUITestTab"),
           arguments.indices.contains(flagIndex + 1),
           let requestedTab = AppTab(rawValue: arguments[flagIndex + 1]) {
            initialTab = requestedTab
        }
#endif
        _selectedTab = State(initialValue: initialTab)
    }

    private var language: AppLanguage {
        AppLanguage.fromStoredValue(languageRaw)
    }

    private var pendingApprovals: [PendingApprovalSummary] {
        store.agentControl?.pendingApprovals ?? []
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DeferredView {
                    DashboardView(selectedTab: $selectedTab)
                        .traceFenceConnectionStatus { selectedTab = .settings }
                }
            }
            .tabItem { Label(AppTab.overview.title(language), systemImage: AppTab.overview.icon) }
            .tag(AppTab.overview)

            NavigationStack {
                DeferredView {
                    AgentMonitorView()
                        .traceFenceConnectionStatus { selectedTab = .settings }
                }
            }
            .tabItem { Label(AppTab.monitor.title(language), systemImage: AppTab.monitor.icon) }
            .tag(AppTab.monitor)

            NavigationStack {
                DeferredView {
                    RealtimeSessionsView()
                        .traceFenceConnectionStatus { selectedTab = .settings }
                }
            }
            .tabItem { Label(AppTab.sessions.title(language), systemImage: AppTab.sessions.icon) }
            .tag(AppTab.sessions)

            NavigationStack {
                DeferredView {
                    ConfirmationsView()
                        .traceFenceConnectionStatus { selectedTab = .settings }
                }
            }
            .tabItem { Label(AppTab.approvals.title(language), systemImage: AppTab.approvals.icon) }
            .badge(pendingApprovals.count)
            .tag(AppTab.approvals)

            NavigationStack {
                DeferredView {
                    SentinelSettingsView(selectedTab: $selectedTab)
                        .traceFenceConnectionStatus { selectedTab = .settings }
                }
            }
            .tabItem { Label(AppTab.settings.title(language), systemImage: AppTab.settings.icon) }
            .tag(AppTab.settings)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let feedback = store.actionFeedback {
                    ConnectionActionFeedbackBanner(feedback: feedback) {
                        store.dismissActionFeedback(id: feedback.id)
                    }
                }
                if selectedTab != .approvals, let approval = pendingApprovals.first {
                    GlobalApprovalBanner(approval: approval, additionalCount: pendingApprovals.count - 1) {
                        selectedTab = .approvals
                    }
                }
            }
        }
        .environment(\.locale, language.locale ?? .autoupdatingCurrent)
        .environment(\.appLanguage, language)
        .onAppear(perform: consumePendingNotificationDestination)
        .onReceive(NotificationCenter.default.publisher(for: .traceFenceOpenApprovals)) { _ in
            selectedTab = .approvals
        }
        .onReceive(NotificationCenter.default.publisher(for: .traceFenceOpenSessions)) { _ in
            selectedTab = .sessions
        }
        .task(id: store.actionFeedback?.id) {
            guard let feedback = store.actionFeedback, feedback.tone != .progress else { return }
            let delay: UInt64 = feedback.tone == .failure ? 5_000_000_000 : 2_600_000_000
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            store.dismissActionFeedback(id: feedback.id)
        }
    }

    private func consumePendingNotificationDestination() {
        let defaults = UserDefaults.standard
        guard let destination = defaults.string(forKey: TraceFenceNotificationCoordinator.pendingDestinationKey) else { return }
        defaults.removeObject(forKey: TraceFenceNotificationCoordinator.pendingDestinationKey)
        selectedTab = destination == "approvals" ? .approvals : .sessions
    }
}

private struct ConnectionStatusToolbarModifier: ViewModifier {
    var openSettings: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarLeading) {
                GlobalConnectionStatusButton(openSettings: openSettings)
            }
        }
    }
}

private extension View {
    func traceFenceConnectionStatus(openSettings: @escaping () -> Void) -> some View {
        modifier(ConnectionStatusToolbarModifier(openSettings: openSettings))
    }
}

private struct GlobalConnectionStatusButton: View {
    @EnvironmentObject private var store: ConnectionStore
    @Environment(\.appLanguage) private var language
    var openSettings: () -> Void

    private var isBusy: Bool {
        if case .loading = store.state { return true }
        return false
    }

    private var label: String {
        if isBusy {
            return store.status == nil
                ? language.text(zh: "连接中", en: "Connecting", zhHant: "連線中", ja: "接続中", ko: "연결 중", mt: "Qed jikkonnettja")
                : language.text(zh: "同步中", en: "Syncing", zhHant: "同步中", ja: "同期中", ko: "동기화 중", mt: "Qed jissinkronizza")
        }
        if case .failed = store.state {
            return language.text(zh: "连接失败", en: "Offline", zhHant: "連線失敗", ja: "接続失敗", ko: "연결 실패", mt: "Mhux konness")
        }
        if store.status != nil {
            return language.text(zh: "在线", en: "Online", zhHant: "在線", ja: "接続済", ko: "온라인", mt: "Online")
        }
        return store.connection == nil
            ? language.text(zh: "未配对", en: "Not paired", zhHant: "未配對", ja: "未ペアリング", ko: "페어링 안 됨", mt: "Mhux imqabbad")
            : language.text(zh: "待连接", en: "Ready", zhHant: "待連線", ja: "接続待ち", ko: "연결 대기", mt: "Lest")
    }

    private var color: Color {
        if isBusy { return TraceFenceDesign.warning }
        if case .failed = store.state { return TraceFenceDesign.danger }
        if store.status != nil { return TraceFenceDesign.success }
        return TraceFenceDesign.secondary
    }

    var body: some View {
        Button {
            if store.connection == nil {
                openSettings()
            } else {
                Task { await store.reconnectFromUser() }
            }
        } label: {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(color)
                        .frame(width: 12, height: 12)
                } else {
                    Circle()
                        .fill(color)
                        .frame(width: 9, height: 9)
                }
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .frame(minWidth: 58, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .accessibilityLabel(label)
        .accessibilityHint(store.connection == nil
            ? language.text(zh: "打开连接设置", en: "Open connection settings", zhHant: "開啟連線設定", ja: "接続設定を開く", ko: "연결 설정 열기", mt: "Iftaħ is-settings tal-konnessjoni")
            : language.text(zh: "重新连接 Mac", en: "Reconnect to Mac", zhHant: "重新連線 Mac", ja: "Mac に再接続", ko: "Mac에 다시 연결", mt: "Erġa' qabbad mal-Mac"))
    }
}

private struct ConnectionActionFeedbackBanner: View {
    @Environment(\.appLanguage) private var language
    var feedback: ConnectionActionFeedback
    var dismiss: () -> Void

    private var color: Color {
        switch feedback.tone {
        case .progress: return TraceFenceDesign.accent
        case .success: return TraceFenceDesign.success
        case .failure: return TraceFenceDesign.danger
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            if feedback.tone == .progress {
                ProgressView()
                    .controlSize(.small)
                    .tint(color)
            } else {
                Image(systemName: feedback.tone == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(color)
            }
            Text(feedback.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(TraceFenceDesign.text)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TraceFenceDesign.secondary)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(language.text(zh: "关闭提示", en: "Dismiss", zhHant: "關閉提示", ja: "閉じる", ko: "닫기", mt: "Agħlaq"))
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(color.opacity(0.10))
        .overlay(alignment: .bottom) { Divider() }
    }
}

private struct GlobalApprovalBanner: View {
    @Environment(\.appLanguage) private var language
    var approval: PendingApprovalSummary
    var additionalCount: Int
    var open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 11) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(TraceFenceDesign.warning)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(language.text(
                            zh: "等待命令确认",
                            en: "Approval required",
                            zhHant: "等待命令確認",
                            ja: "コマンドの承認待ち",
                            ko: "명령 승인 대기",
                            mt: "Approvazzjoni meħtieġa"
                        ))
                        .font(.subheadline.weight(.semibold))
                        if additionalCount > 0 {
                            Text("+\(additionalCount)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(TraceFenceDesign.warning)
                        }
                    }
                    Text("\(approval.agentDisplayName) · \(approval.displayTitle)")
                        .font(.caption)
                        .foregroundStyle(TraceFenceDesign.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TraceFenceDesign.secondary)
            }
            .padding(.leading, 96)
            .padding(.trailing, 14)
            .frame(minHeight: 54)
            .background(TraceFenceDesign.warning.opacity(0.11))
            .overlay(alignment: .bottom) {
                Divider()
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(language.text(
            zh: "打开确认页面",
            en: "Open approvals",
            zhHant: "開啟審批頁面",
            ja: "承認画面を開きます",
            ko: "승인 화면 열기",
            mt: "Iftaħ l-approvazzjonijiet"
        ))
    }
}

struct AuthenticatedAppRoot: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var security: AppSecurityController
    @EnvironmentObject private var store: ConnectionStore
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.english.rawValue

    private var language: AppLanguage {
        AppLanguage.fromStoredValue(languageRaw)
    }

    var body: some View {
        Group {
            if security.isUnlocked {
                AppShellView()
            } else {
                AppLockedView(language: language)
            }
        }
        .environment(\.locale, language.locale ?? .autoupdatingCurrent)
        .environment(\.appLanguage, language)
        .task {
            await unlockIfNeeded()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                security.lock()
                store.setAccessAuthorized(false)
            case .active:
                Task { await unlockIfNeeded() }
            default:
                break
            }
        }
        .onChange(of: security.isUnlocked) { _, unlocked in
            store.setAccessAuthorized(unlocked)
        }
    }

    private func unlockIfNeeded() async {
        await security.unlock()
        store.setAccessAuthorized(security.isUnlocked)
    }
}

private struct AppLockedView: View {
    @EnvironmentObject private var security: AppSecurityController
    let language: AppLanguage

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 54, weight: .semibold))
                .foregroundStyle(TraceFenceDesign.accent)

            VStack(spacing: 8) {
                Text("TraceFence Sentinel")
                    .font(.title.bold())
                Text(language.text(
                    zh: "Agent 会话和远程控制已锁定",
                    en: "Agent sessions and remote controls are locked",
                    zhHant: "Agent 工作階段及遠端控制已鎖定",
                    ja: "Agent セッションとリモート操作はロックされています",
                    ko: "Agent 세션 및 원격 제어가 잠겨 있습니다",
                    mt: "Is-sessjonijiet u l-kontrolli remoti huma msakkra"
                ))
                .font(.subheadline)
                .foregroundStyle(TraceFenceDesign.secondary)
                .multilineTextAlignment(.center)
            }

            Button {
                Task { await security.unlock() }
            } label: {
                Label(
                    security.isAuthenticating
                        ? language.text(zh: "正在验证", en: "Authenticating", zhHant: "正在驗證", ja: "認証中", ko: "인증 중", mt: "Qed Jawtentika")
                        : language.text(
                            zh: "使用 \(security.method.title(language)) 解锁",
                            en: "Unlock with \(security.method.title(language))",
                            zhHant: "使用 \(security.method.title(language)) 解鎖",
                            ja: "\(security.method.title(language)) でロック解除",
                            ko: "\(security.method.title(language))(으)로 잠금 해제",
                            mt: "Iftaħ b'\(security.method.title(language))"
                        ),
                    systemImage: security.method.icon
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(security.isAuthenticating)

            if let errorMessage = security.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(TraceFenceDesign.danger)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: 440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TraceFenceDesign.background.ignoresSafeArea())
    }
}

struct SentinelSettingsView: View {
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var store: ConnectionStore
    @EnvironmentObject private var security: AppSecurityController
    @Binding var selectedTab: AppTab
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.english.rawValue
    @State private var showPairing = false
    @State private var showPrivacy = false
    @State private var notificationPermission = TraceFenceNotificationPermission.unknown
    @State private var isUpdatingNotificationPermission = false

    private var language: AppLanguage {
        AppLanguage.fromStoredValue(languageRaw)
    }

    private func localizedText(_ key: String) -> Text {
        Text(verbatim: language.localized(key))
    }

    private var notificationStatusTitle: String {
        switch notificationPermission {
        case .unknown:
            return language.text(zh: "正在读取", en: "Checking", zhHant: "正在讀取", ja: "確認中", ko: "확인 중", mt: "Qed jiġi vverifikat")
        case .notDetermined:
            return language.text(zh: "尚未授权", en: "Not requested", zhHant: "尚未授權", ja: "未設定", ko: "요청하지 않음", mt: "Għadu mhux mitlub")
        case .denied:
            return language.text(zh: "已关闭", en: "Disabled", zhHant: "已關閉", ja: "無効", ko: "꺼짐", mt: "Mitfi")
        case .authorized:
            return language.text(zh: "已允许", en: "Allowed", zhHant: "已允許", ja: "許可済み", ko: "허용됨", mt: "Permess")
        case .provisional:
            return language.text(zh: "静默通知", en: "Quiet delivery", zhHant: "靜默通知", ja: "静かな通知", ko: "조용히 전달", mt: "Kunsinna siekta")
        case .ephemeral:
            return language.text(zh: "临时允许", en: "Temporary", zhHant: "暫時允許", ja: "一時的", ko: "임시 허용", mt: "Temporanju")
        }
    }

    private var notificationStatusColor: Color {
        notificationPermission.canNotify ? TraceFenceDesign.success : (notificationPermission == .denied ? TraceFenceDesign.danger : TraceFenceDesign.warning)
    }

    private var notificationStatusIcon: String {
        notificationPermission.canNotify ? "bell.badge.fill" : (notificationPermission == .denied ? "bell.slash.fill" : "bell.badge")
    }

    private var notificationActionTitle: String {
        notificationPermission == .denied
            ? language.text(zh: "打开系统通知设置", en: "Open Notification Settings", zhHant: "開啟系統通知設定", ja: "通知設定を開く", ko: "알림 설정 열기", mt: "Iftaħ is-Settings tan-Notifiki")
            : language.text(zh: "允许消息通知", en: "Allow Notifications", zhHant: "允許訊息通知", ja: "通知を許可", ko: "알림 허용", mt: "Ippermetti n-Notifiki")
    }

    var body: some View {
        Form {
            Section {
                if let connection = store.connection {
                    LabeledContent {
                        Text(verbatim: connection.name.tfLocalized)
                    } label: {
                        localizedText("当前 Mac")
                    }
                    LabeledContent {
                        Text(verbatim: connection.endpoint)
                    } label: {
                        localizedText("地址")
                    }
                    if let activeEndpoint = connection.lastResolvedEndpoint {
                        LabeledContent {
                            Text(verbatim: activeEndpoint)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } label: {
                            Text(language.text(zh: "当前通道", en: "Active route", zhHant: "目前通道", ja: "現在の経路", ko: "현재 경로", mt: "Rotta Attiva"))
                        }
                    }
                    if let lastUpdated = store.lastUpdated {
                        LabeledContent {
                            Text(lastUpdated, style: .relative)
                        } label: {
                            Text(language.text(zh: "上次刷新", en: "Last refresh", zhHant: "上次重新整理", ja: "最終更新", ko: "마지막 새로 고침", mt: "L-aħħar Aġġornament"))
                        }
                    }
                    if let status = store.status {
                        Label(
                            status.app?.name == "TraceFence Agent Core"
                                ? language.localized("已连接常驻 Agent Core")
                                : language.localized("已连接 Mac App"),
                            systemImage: "checkmark.circle.fill"
                        )
                        .foregroundStyle(TraceFenceDesign.success)
                    } else if case .failed(let message) = store.state {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(TraceFenceDesign.danger)
                    }
                } else {
                    Text(language.localized("尚未连接 Mac。"))
                        .foregroundStyle(TraceFenceDesign.secondary)
                }
                Button {
                    Task { await store.reconnectFromUser() }
                } label: {
                    HStack(spacing: 8) {
                        if store.isRefreshing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text(language.localized(store.isRefreshing ? "正在连接 Mac" : "立即重连"))
                    }
                }
                .disabled(store.connection == nil || store.isRefreshing)
                Button {
                    Task {
                        let authorized = await security.authorizeSensitiveAction(
                            reason: language.text(
                                zh: "验证身份后连接或更换受控 Mac。",
                                en: "Authenticate to pair or change the controlled Mac.",
                                zhHant: "驗證身分後配對或更換受控 Mac。",
                                ja: "認証して制御対象の Mac をペアリングまたは変更します。",
                                ko: "인증 후 제어할 Mac을 페어링하거나 변경합니다.",
                                mt: "Awtentika biex tqabbad jew tibdel il-Mac ikkontrollat."
                            )
                        )
                        guard authorized else { return }
                        showPairing = true
                    }
                } label: {
                    Label(language.localized("连接或更换 Mac"), systemImage: "network")
                }
                .disabled(security.isAuthenticating)
                if let errorMessage = security.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(TraceFenceDesign.danger)
                }
                Text(language.text(
                    zh: "Mac 仅锁屏时仍可连接；系统睡眠、合盖、关机或断网后无法连接。开启 Mac 配对弹窗里的“锁屏时保持远程可用”可阻止自动睡眠。",
                    en: "A locked Mac remains reachable. System sleep, a closed lid, shutdown, or a network outage disconnects it. Enable Keep Remote Access Available While Locked in the Mac pairing panel to prevent automatic sleep.",
                    zhHant: "Mac 只鎖定螢幕時仍可連線；系統睡眠、闔蓋、關機或斷網後將無法連線。請在 Mac 配對面板開啟「鎖定時保持遠端可用」以防止自動睡眠。",
                    ja: "Mac は画面ロック中でも接続できます。スリープ、画面を閉じる、電源オフ、ネットワーク切断時は接続できません。Mac のペアリング画面で「ロック中もリモートアクセスを維持」を有効にしてください。",
                    ko: "Mac은 화면이 잠겨 있어도 연결할 수 있습니다. 시스템 잠자기, 덮개 닫힘, 종료 또는 네트워크 끊김 상태에서는 연결할 수 없습니다. Mac 페어링 화면에서 ‘잠금 중 원격 접근 유지’를 켜세요.",
                    mt: "Mac imsakkar jibqa' aċċessibbli. Sleep, għatu magħluq, shutdown jew qtugħ tan-network iwaqqfu l-konnessjoni. Attiva Keep Remote Access Available While Locked fil-pannell tal-pairing."
                ))
                .font(.footnote)
                .foregroundStyle(TraceFenceDesign.secondary)
                Text(language.text(
                    zh: "通过互联网连接时，Mac 和 iPhone 必须同时加入同一个 Tailscale/Tailnet 或你自己的 VPN；只在 Mac 上安装无法建立远程链路。",
                    en: "For internet access, both the Mac and iPhone must join the same Tailscale tailnet or your own VPN. Installing it only on the Mac does not create a remote route.",
                    zhHant: "透過互聯網連線時，Mac 和 iPhone 必須同時加入相同的 Tailscale/Tailnet 或你自己的 VPN；只在 Mac 安裝無法建立遠端路徑。",
                    ja: "インターネット経由では、Mac と iPhone の両方を同じ Tailscale/Tailnet または自分の VPN に参加させる必要があります。Mac だけにインストールしてもリモート経路は作成されません。",
                    ko: "인터넷으로 연결하려면 Mac과 iPhone 모두 동일한 Tailscale/Tailnet 또는 자체 VPN에 참여해야 합니다. Mac에만 설치하면 원격 경로가 만들어지지 않습니다.",
                    mt: "Għal aċċess bl-internet, il-Mac u l-iPhone għandhom ikunu fl-istess Tailscale tailnet jew VPN tiegħek. Installazzjoni fuq il-Mac biss ma toħloqx rotta remota."
                ))
                .font(.footnote)
                .foregroundStyle(TraceFenceDesign.secondary)
            } header: {
                localizedText("连接")
            }

            Section {
                Picker(selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { item in
                        Text(verbatim: item.title(in: language)).tag(item.rawValue)
                    }
                } label: {
                    localizedText("显示语言")
                }
            } header: {
                localizedText("语言")
            }

            Section {
                Label(notificationStatusTitle, systemImage: notificationStatusIcon)
                    .foregroundStyle(notificationStatusColor)

                if !notificationPermission.canNotify {
                    Button {
                        if notificationPermission == .denied {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        } else {
                            isUpdatingNotificationPermission = true
                            Task {
                                notificationPermission = await TraceFenceNotificationCoordinator.shared.requestPermission()
                                isUpdatingNotificationPermission = false
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isUpdatingNotificationPermission {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: notificationPermission == .denied ? "gear" : "bell.badge")
                            }
                            Text(notificationActionTitle)
                        }
                    }
                    .disabled(isUpdatingNotificationPermission)
                } else {
                    Button {
                        TraceFenceNotificationCoordinator.shared.scheduleTestNotification()
                    } label: {
                        Label(
                            language.text(zh: "发送测试通知", en: "Send Test Notification", zhHant: "傳送測試通知", ja: "テスト通知を送信", ko: "테스트 알림 보내기", mt: "Ibgħat Notifika ta' Test"),
                            systemImage: "bell.and.waves.left.and.right"
                        )
                    }
                }

                Text(language.text(
                    zh: "审批请求、Agent 新回复和任务完成会触发本地通知。TraceFence 没有中转后端，因此 App 被系统完全挂起或退出后无法接收 APNs 实时推送；重新打开或保持连接时会立即同步遗漏状态。",
                    en: "Approval requests, new agent replies, and task completion trigger local notifications. TraceFence has no relay backend, so APNs cannot deliver real-time updates while the app is fully suspended or terminated; reopening or staying connected immediately catches up missed state.",
                    zhHant: "審批請求、Agent 新回覆及工作完成會觸發本機通知。TraceFence 沒有中轉後端，因此 App 被系統完全暫停或結束後無法接收 APNs 即時推送；重新開啟或保持連線時會立即同步遺漏狀態。",
                    ja: "承認リクエスト、Agent の新しい返信、タスク完了時にローカル通知を送ります。TraceFence には中継バックエンドがないため、App が完全に停止または終了している間は APNs のリアルタイム配信はできません。再起動または接続維持時に未取得の状態を同期します。",
                    ko: "승인 요청, Agent의 새 응답 및 작업 완료 시 로컬 알림을 보냅니다. TraceFence에는 중계 백엔드가 없으므로 App이 완전히 일시 중지되거나 종료된 동안에는 APNs 실시간 푸시를 받을 수 없습니다. 다시 열거나 연결을 유지하면 누락된 상태를 즉시 동기화합니다.",
                    mt: "Talbiet għall-approvazzjoni, tweġibiet ġodda u kompiti lesti joħolqu notifiki lokali. TraceFence m'għandux relay backend, għalhekk APNs ma jistax iwassal aġġornamenti live meta l-app tkun sospiża jew magħluqa; meta terġa' tiftaħ jew tibqa' konnessa, l-istat jintlaħaq minnufih."
                ))
                .font(.footnote)
                .foregroundStyle(TraceFenceDesign.secondary)
            } header: {
                Text(language.text(zh: "消息通知", en: "Notifications", zhHant: "訊息通知", ja: "通知", ko: "알림", mt: "Notifiki"))
            }

            if let adapters = store.status?.agentCore?.adapters, !adapters.isEmpty {
                Section {
                    ForEach(adapters) { adapter in
                        let ready = adapter.operational == true && adapter.authenticated != false
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 8) {
                                Image(systemName: ready ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(ready ? TraceFenceDesign.success : TraceFenceDesign.warning)
                                Text(adapter.displayName ?? adapter.id)
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(ready
                                     ? language.localized("可用")
                                     : language.localized("需要处理"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(ready ? TraceFenceDesign.success : TraceFenceDesign.warning)
                            }
                            if let version = adapter.cliVersion, !version.isEmpty {
                                Text(version)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(TraceFenceDesign.secondary)
                            }
                            if let message = adapter.message, !message.isEmpty {
                                Text(message.tfLocalized)
                                    .font(.caption)
                                    .foregroundStyle(TraceFenceDesign.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    Text(language.text(
                        zh: "TraceFence Agent Core 与每个 Agent 适配器独立升级。Codex 依赖官方独立 CLI 的 app-server；Claude 远程控制依赖已登录的 Claude Code CLI。",
                        en: "TraceFence Agent Core and each agent adapter update independently. Codex uses the official standalone CLI app-server; Claude remote control requires a signed-in Claude Code CLI.",
                        zhHant: "TraceFence Agent Core 與各 Agent 轉接器可獨立升級。Codex 使用官方獨立 CLI 的 app-server；Claude 遠端控制需要已登入的 Claude Code CLI。",
                        ja: "TraceFence Agent Core と各 Agent アダプターは個別に更新できます。Codex は公式スタンドアロン CLI の app-server を使用し、Claude のリモート制御にはログイン済みの Claude Code CLI が必要です。",
                        ko: "TraceFence Agent Core와 각 Agent 어댑터는 독립적으로 업데이트됩니다. Codex는 공식 독립형 CLI app-server를 사용하며 Claude 원격 제어에는 로그인된 Claude Code CLI가 필요합니다.",
                        mt: "TraceFence Agent Core u kull adapter jiġu aġġornati separatament. Codex juża l-app-server uffiċjali; Claude jeħtieġ Claude Code CLI illoggjat."
                    ))
                    .font(.footnote)
                    .foregroundStyle(TraceFenceDesign.secondary)
                } header: {
                    localizedText("Agent 连接器")
                }
            }

            Section {
                Label(
                    language.text(
                        zh: "当前设备使用 \(security.method.title(language))。打开 App、从后台返回以及连接或更换 Mac 时都必须验证。",
                        en: "This device uses \(security.method.title(language)). Authentication is required when opening the app, returning from the background, and pairing or changing a Mac.",
                        zhHant: "目前裝置使用 \(security.method.title(language))。開啟 App、從背景返回，以及配對或更換 Mac 時都必須驗證。",
                        ja: "このデバイスでは \(security.method.title(language)) を使用します。App を開くとき、バックグラウンドから戻るとき、Mac をペアリングまたは変更するときに認証が必要です。",
                        ko: "이 기기는 \(security.method.title(language))을 사용합니다. App 실행, 백그라운드 복귀, Mac 페어링 또는 변경 시 인증이 필요합니다.",
                        mt: "Dan l-apparat juża \(security.method.title(language)). L-awtentikazzjoni hija meħtieġa meta tiftaħ l-app, terġa' lura mill-isfond, jew tqabbad Mac."
                    ),
                    systemImage: "lock.shield"
                )
                Button {
                    store.setAccessAuthorized(false)
                    security.lock()
                } label: {
                    Label(language.localized("立即锁定"), systemImage: "lock.fill")
                }
            } header: {
                localizedText("安全")
            }

            Section {
                Button {
                    showPrivacy = true
                } label: {
                    Label(language.localized("隐私协议"), systemImage: "hand.raised")
                }
                Text(language.text(
                    zh: "TraceFence Sentinel 不使用 TraceFence 后端中转。iPhone 会直接连接你配对的 Mac；配对密钥仅保存在本机。",
                    en: "TraceFence Sentinel does not use a TraceFence relay backend. Your iPhone connects directly to the paired Mac; the pairing token is stored locally.",
                    zhHant: "TraceFence Sentinel 不使用 TraceFence 後端轉送。iPhone 會直接連接已配對的 Mac；配對權杖只儲存在本機。",
                    ja: "TraceFence Sentinel は TraceFence の中継バックエンドを使用しません。iPhone はペアリングした Mac に直接接続し、ペアリングトークンはデバイス内に保存されます。",
                    ko: "TraceFence Sentinel은 TraceFence 중계 백엔드를 사용하지 않습니다. iPhone이 페어링된 Mac에 직접 연결하며 페어링 토큰은 기기에만 저장됩니다.",
                    mt: "TraceFence Sentinel ma jużax relay backend. L-iPhone jikkonnettja direttament mal-Mac u t-token tal-pairing jinżamm lokalment."
                ))
                .font(.footnote)
                .foregroundStyle(TraceFenceDesign.secondary)
            } header: {
                localizedText("隐私")
            }
        }
        .navigationTitle(Text(verbatim: language.localized("设置")))
        .scrollContentBackground(.hidden)
        .background(TraceFenceDesign.background.ignoresSafeArea())
        .sheet(isPresented: $showPairing) {
            NavigationStack {
                PairingView(selectedTab: $selectedTab)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(language.localized("完成")) {
                                showPairing = false
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPrivacy) {
            NavigationStack {
                PrivacyPolicyView(language: language)
            }
        }
        .task {
            notificationPermission = await TraceFenceNotificationCoordinator.shared.permission()
        }
    }
}

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss
    let language: AppLanguage

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(language.localized("隐私协议"))
                    .font(.largeTitle.bold())
                Text(language.text(
                    zh: "TraceFence Sentinel 用于从 iPhone 监控和控制你自己 Mac 上的 TraceFence Agent 控制面。",
                    en: "TraceFence Sentinel lets you monitor and control the TraceFence agent control plane on your own Mac from your iPhone.",
                    zhHant: "TraceFence Sentinel 讓你從 iPhone 監控及控制自己 Mac 上的 TraceFence Agent 控制層。",
                    ja: "TraceFence Sentinel を使うと、iPhone から自分の Mac 上の TraceFence Agent 制御プレーンを監視・操作できます。",
                    ko: "TraceFence Sentinel을 사용하면 iPhone에서 자신의 Mac에 있는 TraceFence Agent 제어 영역을 모니터링하고 제어할 수 있습니다.",
                    mt: "TraceFence Sentinel jippermettilek timmonitorja u tikkontrolla l-Agent control plane fuq il-Mac tiegħek mill-iPhone."
                ))
                Text(language.text(
                    zh: "我们不会提供云端中转服务。配对信息、访问地址和令牌保存在你的设备上。控制请求只会发送到你配对的 Mac 或你自己配置的网络入口。",
                    en: "We do not provide a cloud relay. Pairing information, endpoints, and tokens are stored on your device. Control requests are sent only to your paired Mac or to a network endpoint you configure.",
                    zhHant: "我們不提供雲端轉送服務。配對資料、連線位址及權杖儲存在你的裝置上。控制請求只會傳送到已配對的 Mac 或你自行設定的網路入口。",
                    ja: "クラウド中継は提供しません。ペアリング情報、接続先、トークンはデバイス内に保存され、制御リクエストはペアリングした Mac または自分で設定したネットワーク接続先にのみ送信されます。",
                    ko: "클라우드 중계 서비스를 제공하지 않습니다. 페어링 정보, 엔드포인트 및 토큰은 기기에 저장되며 제어 요청은 페어링된 Mac 또는 직접 구성한 네트워크 엔드포인트로만 전송됩니다.",
                    mt: "Aħna ma nipprovdux cloud relay. L-informazzjoni tal-pairing, l-endpoints u t-tokens jinżammu fuq l-apparat tiegħek u jintbagħtu biss lill-Mac imqabbad."
                ))
                Text(language.text(
                    zh: "应用会请求相机权限用于扫描配对二维码，会请求本地网络权限用于连接同一网络中的 Mac。TraceFence Sentinel 不会出售个人数据。",
                    en: "The app requests camera access to scan pairing QR codes and local network access to reach your Mac on the same network. TraceFence Sentinel does not sell personal data.",
                    zhHant: "App 會要求相機權限以掃描配對 QR Code，並要求區域網路權限以連接同一網路中的 Mac。TraceFence Sentinel 不會出售個人資料。",
                    ja: "ペアリング QR コードのスキャンにカメラ権限、同じネットワーク上の Mac への接続にローカルネットワーク権限を使用します。TraceFence Sentinel は個人データを販売しません。",
                    ko: "페어링 QR 코드 스캔을 위해 카메라 권한을, 동일 네트워크의 Mac 연결을 위해 로컬 네트워크 권한을 요청합니다. TraceFence Sentinel은 개인 데이터를 판매하지 않습니다.",
                    mt: "L-app titlob aċċess għall-kamera biex tiskennja l-QR u aċċess għan-network lokali biex tilħaq il-Mac. TraceFence Sentinel ma jbigħx data personali."
                ))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(Text(verbatim: language.localized("隐私协议")))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(language.localized("关闭")) { dismiss() }
            }
        }
    }
}
