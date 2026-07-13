import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: ConnectionStore
    @Binding var selectedTab: AppTab

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.connection == nil {
                    EmptyConnectionView(
                        action: { selectedTab = .settings },
                        demoAction: { store.enableReviewDemo() }
                    )
                } else {
                    connectionCard
                    stateMessage
                    agentCommandCenter
                    overviewShortcuts
                    macControlCard
                    systemCards
                }
            }
            .padding(16)
        }
        .background(TraceFenceDesign.background.ignoresSafeArea())
        .navigationTitle("总览")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshFromUser() }
                } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(store.connection == nil || store.isRefreshing)
            }
        }
        .refreshable {
            await store.refreshFromUser()
        }
        .task {
            if store.connection != nil {
                await store.refreshIfStale()
            }
        }
    }

    private var overviewShortcuts: some View {
        TFCard {
            SectionTitle(title: "控制入口", systemImage: "square.grid.2x2.fill")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                overviewButton("Agent 监控", "waveform.path.ecg", TraceFenceDesign.accent) {
                    selectedTab = .monitor
                }
                overviewButton("实时会话", "bubble.left.and.text.bubble.right.fill", TraceFenceDesign.success) {
                    selectedTab = .sessions
                }
                overviewButton("确认与告警", "checkmark.shield.fill", TraceFenceDesign.warning) {
                    selectedTab = .approvals
                }
                overviewButton("连接设置", "network", Color.indigo) {
                    selectedTab = .settings
                }
            }
        }
    }

    private func overviewButton(_ title: String, _ systemImage: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Text(title.tfLocalized)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    private var connectionCard: some View {
        TFCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(TraceFenceDesign.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 5) {
                    Text((store.connection?.name ?? "我的 Mac").tfLocalized)
                        .font(.headline)
                        .foregroundStyle(TraceFenceDesign.text)
                    Text(store.connection?.endpoint ?? "")
                        .font(.footnote.monospaced())
                        .foregroundStyle(TraceFenceDesign.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let lastResolved = store.connection?.lastResolvedEndpoint {
                        Text(AppLanguage.current.text(
                            zh: "当前通道 \(lastResolved)",
                            en: "Current route: \(lastResolved)",
                            zhHant: "目前路徑：\(lastResolved)",
                            ja: "現在の経路: \(lastResolved)",
                            ko: "현재 경로: \(lastResolved)",
                            mt: "Rotta attwali: \(lastResolved)"
                        ))
                            .font(.caption.monospaced())
                            .foregroundStyle(TraceFenceDesign.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let lastUpdated = store.lastUpdated {
                        Text(AppLanguage.current.text(
                            zh: "上次同步 \(lastUpdated.tfShortTimeText)",
                            en: "Last synced at \(lastUpdated.tfShortTimeText)",
                            zhHant: "上次同步：\(lastUpdated.tfShortTimeText)",
                            ja: "最終同期: \(lastUpdated.tfShortTimeText)",
                            ko: "마지막 동기화: \(lastUpdated.tfShortTimeText)",
                            mt: "L-aħħar sinkronizzazzjoni: \(lastUpdated.tfShortTimeText)"
                        ))
                            .font(.caption)
                            .foregroundStyle(TraceFenceDesign.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    if let running = store.status?.gateway?.running {
                        StatusBadge(
                            text: running ? "API 在线" : "API 关闭",
                            color: running ? TraceFenceDesign.success : TraceFenceDesign.warning,
                            systemImage: running ? "checkmark.circle.fill" : "pause.circle.fill"
                        )
                    }
                    if let connected = store.status?.agentCore?.connected {
                        StatusBadge(
                            text: connected ? "Core 在线" : "Core 未连接",
                            color: connected ? TraceFenceDesign.accent : TraceFenceDesign.warning,
                            systemImage: connected ? "bolt.horizontal.circle.fill" : "bolt.horizontal.circle"
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var stateMessage: some View {
        switch store.state {
        case .idle, .loaded:
            EmptyView()
        case .loading(let message):
            TFCard {
                HStack {
                    ProgressView()
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(TraceFenceDesign.secondary)
                }
            }
        case .failed(let message):
            TFCard {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(TraceFenceDesign.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var agentCommandCenter: some View {
        let summary = store.agentControl?.summary
        return TFCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bolt.shield.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(TraceFenceDesign.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 6) {
                    Text("实时 Agent 控制台")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(TraceFenceDesign.text)
                    Text("iPhone 作为 TraceFence 控制台使用：监控所有 Agent 任务，在会话里发送新指令、暂停、终止，在确认里处理审批和告警。")
                        .font(.subheadline)
                        .foregroundStyle(TraceFenceDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                MetricTile(
                    title: "待审批",
                    value: "\(summary?.pendingApprovalCount ?? 0)",
                    systemImage: "hand.raised.fill",
                    color: (summary?.pendingApprovalCount ?? 0) > 0 ? TraceFenceDesign.warning : TraceFenceDesign.success
                )
                MetricTile(
                    title: "执行中",
                    value: "\(summary?.processingCount ?? 0)",
                    systemImage: "bubble.left.and.text.bubble.right.fill",
                    color: TraceFenceDesign.accent
                )
                MetricTile(
                    title: "活跃会话",
                    value: "\(summary?.activeSessionCount ?? 0)",
                    systemImage: "waveform.path.ecg",
                    color: Color.indigo
                )
                MetricTile(
                    title: "已暂停",
                    value: "\(summary?.interruptedCount ?? 0)",
                    systemImage: "pause.circle.fill",
                    color: TraceFenceDesign.warning
                )
            }
        }
    }

    private var macControlCard: some View {
        let monitoring = store.status?.system?.monitoring ?? false
        return TFCard {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mac 监控")
                        .font(.headline)
                        .foregroundStyle(TraceFenceDesign.text)
                    Text((monitoring ? "Mac 正在记录 Agent 操作和系统状态。" : "可以从 iPhone 启动 Mac 监控。").tfLocalized)
                        .font(.subheadline)
                        .foregroundStyle(TraceFenceDesign.secondary)
                }
                Spacer()
                StatusBadge(
                    text: monitoring ? "监控中" : "未开启",
                    color: monitoring ? TraceFenceDesign.success : TraceFenceDesign.warning,
                    systemImage: monitoring ? "record.circle.fill" : "pause.circle"
                )
            }

            HStack(spacing: 12) {
                Button {
                    Task { await store.setMonitoring(true) }
                } label: {
                    Label("启动", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(monitoring)

                Button {
                    Task { await store.setMonitoring(false) }
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(TraceFenceDesign.danger)
                .disabled(!monitoring)
            }
            .controlSize(.large)
        }
    }

    private var systemCards: some View {
        let disk = store.status?.system?.disk
        let hardware = store.status?.system?.hardware
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricTile(title: "磁盘已用", value: disk?.usedPercent?.tfPercentText ?? "--", systemImage: "internaldrive.fill", color: TraceFenceDesign.accent)
            MetricTile(title: "剩余空间", value: disk?.freeGB?.tfGigabyteText ?? "--", systemImage: "externaldrive.badge.checkmark", color: TraceFenceDesign.success)
            MetricTile(title: "CPU", value: hardware?.cpuUsage?.tfPercentText ?? "--", systemImage: "cpu.fill", color: Color.indigo)
            MetricTile(title: "内存压力", value: hardware?.memoryPressure?.tfPercentText ?? "--", systemImage: "memorychip.fill", color: TraceFenceDesign.warning)
        }
    }
}

private enum AgentMonitorFilter: String, CaseIterable, Identifiable {
    case all
    case attention
    case controllable
    case observed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部".tfLocalized
        case .attention: return "待处理".tfLocalized
        case .controllable: return "可控".tfLocalized
        case .observed: return "仅监控".tfLocalized
        }
    }
}

private struct PendingSessionDestructiveControl: Identifiable {
    let id = UUID()
    var session: AgentSessionSummary
    var command: AgentSessionCommand
}

struct AgentMonitorView: View {
    @EnvironmentObject private var store: ConnectionStore
    @State private var filter: AgentMonitorFilter = .all
    @State private var searchText = ""
    @State private var continuationSession: AgentSessionSummary?
    @State private var continuationInstruction = ""
    @State private var relaunchSession: AgentSessionSummary?
    @State private var relaunchInstruction = ""
    @State private var pendingDestructiveControl: PendingSessionDestructiveControl?
    private let maxRenderedSessions = 80

    private var allSessions: [AgentSessionSummary] {
        store.presentedSessions
    }

    private var filteredSessions: [AgentSessionSummary] {
        let scoped: [AgentSessionSummary]
        switch filter {
        case .all:
            scoped = allSessions
        case .attention:
            scoped = allSessions.filter { $0.needsAttention || $0.canStartContinuation }
        case .controllable:
            scoped = allSessions.filter { $0.controlAvailable == true || $0.canStartContinuation || $0.canSendContinuation }
        case .observed:
            scoped = allSessions.filter { $0.isDisplayOnly && !$0.canStartContinuation }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return scoped }
        return scoped.filter { session in
            [
                session.displayTitle,
                session.project,
                session.cwd,
                session.agentDisplayName,
                session.lastToolName,
                session.lastToolTarget,
                session.lastResponse,
                session.lastThought
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    private var agentGroups: [PresentedSessionAgentGroup] {
        AgentSessionPresentationPolicy.groups(filteredSessions)
    }

    private var displayedAgentGroups: [PresentedSessionAgentGroup] {
        var remaining = maxRenderedSessions
        var groups: [PresentedSessionAgentGroup] = []
        for agent in agentGroups where remaining > 0 {
            var projects: [PresentedSessionProjectGroup] = []
            for project in agent.projects where remaining > 0 {
                let sessions = Array(project.sessions.prefix(remaining))
                guard !sessions.isEmpty else { continue }
                projects.append(PresentedSessionProjectGroup(
                    id: project.id,
                    name: project.name,
                    sessions: sessions,
                    sortDate: project.sortDate
                ))
                remaining -= sessions.count
            }
            guard !projects.isEmpty else { continue }
            groups.append(PresentedSessionAgentGroup(
                id: agent.id,
                name: agent.name,
                projects: projects,
                sortDate: agent.sortDate
            ))
        }
        return groups
    }

    private var hiddenFilteredSessionCount: Int {
        max(0, filteredSessions.count - displayedAgentGroups.reduce(0) { $0 + $1.sessionCount })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.connection == nil {
                    EmptyConnectionView {}
                } else {
                    stateMessage
                    monitorSummary
                    TFCard {
                        SectionTitle(title: "Agent 任务监控", systemImage: "waveform.path.ecg")
                        connectionLine
                        searchField
                        Picker("任务范围", selection: $filter) {
                            ForEach(AgentMonitorFilter.allCases) { item in
                                Text(item.title).tag(item)
                            }
                        }
                        .pickerStyle(.segmented)

                        if filteredSessions.isEmpty {
                            EmptyInlineState(
                                icon: "tray",
                                title: "没有符合条件的任务",
                                detail: "刷新后，Mac 已发现的 Agent 任务会按能力出现在这里。"
                            )
                        } else {
                            LazyVStack(spacing: 14) {
                                ForEach(displayedAgentGroups) { agent in
                                    VStack(alignment: .leading, spacing: 12) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "cpu.fill")
                                                .foregroundStyle(TraceFenceDesign.accent)
                                            Text(agent.name)
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(TraceFenceDesign.text)
                                                .lineLimit(1)
                                            Spacer()
                                            Text("\(agent.sessionCount)")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(TraceFenceDesign.secondary)
                                        }
                                        ForEach(agent.projects) { project in
                                            VStack(alignment: .leading, spacing: 9) {
                                                HStack(spacing: 7) {
                                                    Image(systemName: "folder.fill")
                                                        .foregroundStyle(TraceFenceDesign.secondary)
                                                    Text(project.name)
                                                        .font(.caption.weight(.semibold))
                                                        .foregroundStyle(TraceFenceDesign.secondary)
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)
                                                    Spacer()
                                                }
                                                ForEach(project.sessions) { session in
                                                    AgentSessionRow(
                                                        session: session,
                                                        interrupt: {
                                                            pendingDestructiveControl = PendingSessionDestructiveControl(
                                                                session: session,
                                                                command: .interrupt
                                                            )
                                                        },
                                                        resume: {
                                                            continuationInstruction = ""
                                                            continuationSession = session
                                                        },
                                                        relaunch: {
                                                            relaunchInstruction = session.continuationLaunchInstruction
                                                            relaunchSession = session
                                                        },
                                                        terminate: {
                                                            pendingDestructiveControl = PendingSessionDestructiveControl(
                                                                session: session,
                                                                command: .terminate
                                                            )
                                                        }
                                                    )
                                                }
                                            }
                                            .padding(.leading, 14)
                                        }
                                    }
                                }
                                if hiddenFilteredSessionCount > 0 {
                                    Text(AppLanguage.current.text(
                                        zh: "还有 \(hiddenFilteredSessionCount) 个任务未渲染，可用搜索或筛选缩小范围。",
                                        en: "\(hiddenFilteredSessionCount) more tasks are hidden. Search or filter to narrow the list.",
                                        zhHant: "尚有 \(hiddenFilteredSessionCount) 個任務未顯示，可使用搜尋或篩選縮小範圍。",
                                        ja: "ほかに \(hiddenFilteredSessionCount) 件のタスクが非表示です。検索またはフィルターで絞り込めます。",
                                        ko: "\(hiddenFilteredSessionCount)개의 작업이 더 숨겨져 있습니다. 검색 또는 필터로 범위를 좁히세요.",
                                        mt: "Hemm \(hiddenFilteredSessionCount) kompiti oħra moħbija. Uża t-tiftix jew il-filtru."
                                    ))
                                        .font(.caption)
                                        .foregroundStyle(TraceFenceDesign.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.top, 4)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(TraceFenceDesign.background.ignoresSafeArea())
        .navigationTitle("Agent 监控")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshFromUser() }
                } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(store.connection == nil || store.isRefreshing)
            }
        }
        .refreshable {
            await store.refreshFromUser()
        }
        .sheet(item: $continuationSession, onDismiss: {
            continuationInstruction = ""
        }) { session in
            ContinueSessionSheet(
                session: session,
                instruction: $continuationInstruction,
                submit: { instruction in
                    continuationSession = nil
                    continuationInstruction = ""
                    Task {
                        await store.controlSession(session, command: .resume, instruction: instruction)
                    }
                }
            )
        }
        .sheet(item: $relaunchSession, onDismiss: {
            relaunchInstruction = ""
        }) { session in
            RelaunchSessionSheet(
                session: session,
                instruction: $relaunchInstruction,
                submit: { instruction in
                    relaunchSession = nil
                    relaunchInstruction = ""
                    Task {
                        await store.relaunchSession(session, instruction: instruction)
                    }
                }
            )
        }
        .alert(
            destructiveAlertTitle,
            isPresented: Binding(
                get: { pendingDestructiveControl != nil },
                set: { if !$0 { pendingDestructiveControl = nil } }
            ),
            presenting: pendingDestructiveControl
        ) { pending in
            Button(destructiveConfirmTitle(pending.command), role: .destructive) {
                pendingDestructiveControl = nil
                Task {
                    await store.controlSession(pending.session, command: pending.command)
                }
            }
            Button("取消".tfLocalized, role: .cancel) {
                pendingDestructiveControl = nil
            }
        } message: { pending in
            Text(destructiveAlertMessage(pending))
        }
        .task {
            if store.connection != nil {
                await store.refreshIfStale()
            }
        }
    }

    private var destructiveAlertTitle: String {
        AppLanguage.current.text(
            zh: "确认中断这个任务？",
            en: "Interrupt this task?",
            zhHant: "確認中斷此任務？",
            ja: "このタスクを中断しますか？",
            ko: "이 작업을 중단할까요?",
            mt: "Tinterrompi dan il-kompitu?"
        )
    }

    private func destructiveConfirmTitle(_ command: AgentSessionCommand) -> String {
        if command == .terminate {
            return AppLanguage.current.text(zh: "确认终止", en: "Terminate", zhHant: "確認終止", ja: "終了する", ko: "종료", mt: "Temm")
        }
        return AppLanguage.current.text(zh: "确认中断", en: "Interrupt", zhHant: "確認中斷", ja: "中断する", ko: "중단", mt: "Interrompi")
    }

    private func destructiveAlertMessage(_ pending: PendingSessionDestructiveControl) -> String {
        let title = pending.session.displayTitle
        if pending.command == .terminate {
            return AppLanguage.current.text(
                zh: "“\(title)”将被终止，当前正在执行的命令和未完成输出会停止。此操作不能自动恢复。",
                en: "\"\(title)\" will be terminated. Its running command and unfinished output will stop, and it cannot be resumed automatically.",
                zhHant: "「\(title)」將被終止，目前執行中的命令及未完成輸出會停止。此操作無法自動恢復。",
                ja: "「\(title)」を終了します。実行中のコマンドと未完了の出力は停止し、自動では再開できません。",
                ko: "‘\(title)’ 작업을 종료합니다. 실행 중인 명령과 완료되지 않은 출력이 중지되며 자동으로 재개할 수 없습니다.",
                mt: "\"\(title)\" se jintemm. Il-kmand u l-output mhux lest jieqfu u ma jistgħux jitkomplew awtomatikament."
            )
        }
        return AppLanguage.current.text(
            zh: "“\(title)”当前执行会立即中断，正在运行的工具命令可能只完成一部分。之后仍可发送新指令继续。",
            en: "\"\(title)\" will be interrupted immediately. A running tool command may stop partway through. You can send a new instruction afterward.",
            zhHant: "「\(title)」目前執行會立即中斷，正在執行的工具命令可能只完成一部分。之後仍可傳送新指令繼續。",
            ja: "「\(title)」の実行を直ちに中断します。実行中のツールコマンドが途中で停止する場合があります。その後、新しい指示で続行できます。",
            ko: "‘\(title)’의 현재 실행을 즉시 중단합니다. 실행 중인 도구 명령이 일부만 완료될 수 있습니다. 이후 새 지시를 보내 계속할 수 있습니다.",
            mt: "L-eżekuzzjoni ta' \"\(title)\" se tiġi interrotta minnufih. Kmand ta' għodda jista' jieqaf nofs triq. Tista' tibgħat struzzjoni ġdida wara."
        )
    }

    private var monitorSummary: some View {
        let count = allSessions.count
        let controllable = allSessions.filter { $0.controlAvailable == true || $0.canStartContinuation }.count
        let attention = allSessions.filter { $0.needsAttention || $0.canStartContinuation }.count
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            MetricTile(title: "全部任务", value: "\(count)", systemImage: "list.bullet.rectangle", color: TraceFenceDesign.accent)
            MetricTile(title: "可操作", value: "\(controllable)", systemImage: "hand.tap.fill", color: TraceFenceDesign.success)
            MetricTile(title: "需关注", value: "\(attention)", systemImage: "exclamationmark.triangle.fill", color: TraceFenceDesign.warning)
        }
    }

    private var connectionLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(store.status?.gateway?.running == true ? TraceFenceDesign.success : TraceFenceDesign.warning)
                .frame(width: 8, height: 8)
            Image(systemName: "laptopcomputer")
                .foregroundStyle(TraceFenceDesign.secondary)
            Text((store.connection?.name ?? "Mac").tfLocalized)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TraceFenceDesign.text)
                .lineLimit(1)
            Text(store.connection?.endpoint ?? "")
                .font(.caption)
                .foregroundStyle(TraceFenceDesign.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(TraceFenceDesign.secondary)
            TextField("搜索任务、项目、会话", text: $searchText)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(TraceFenceDesign.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private var stateMessage: some View {
        switch store.state {
        case .idle, .loaded:
            EmptyView()
        case .loading(let message):
            TFCard {
                HStack {
                    ProgressView()
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(TraceFenceDesign.secondary)
                }
            }
        case .failed(let message):
            TFCard {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(TraceFenceDesign.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private enum SessionCatalogScope: String, CaseIterable, Identifiable {
    case all
    case active
    case attention

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .all:
            return language.text(zh: "全部", en: "All", zhHant: "全部", ja: "すべて", ko: "전체", mt: "Kollha")
        case .active:
            return language.text(zh: "进行中", en: "Active", zhHant: "進行中", ja: "実行中", ko: "진행 중", mt: "Attivi")
        case .attention:
            return language.text(zh: "待处理", en: "Attention", zhHant: "待處理", ja: "要対応", ko: "처리 필요", mt: "Pendenti")
        }
    }
}

struct RealtimeSessionsView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var store: ConnectionStore
    @State private var searchText = ""
    @State private var scope: SessionCatalogScope = .all
    @State private var launchTarget: AgentLaunchTargetSummary?
    @State private var launchInstruction = ""

    private var sessions: [AgentSessionSummary] {
        let scoped = store.presentedSessions.filter { session in
            switch scope {
            case .all:
                return true
            case .active:
                return !["idle", "done", "scheduled"].contains(session.phase)
            case .attention:
                return session.needsAttention || session.canStartContinuation
            }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return scoped }
        return scoped.filter { session in
            [
                session.displayTitle,
                session.project,
                session.cwd,
                session.agentDisplayName,
                session.engineLabel,
                session.lastResponse
            ]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains(query) }
        }
    }

    private var agentGroups: [PresentedSessionAgentGroup] {
        AgentSessionPresentationPolicy.groups(sessions)
    }

    private var launchTargets: [AgentLaunchTargetSummary] {
        store.agentControl?.launchTargets?.filter(\.installed) ?? []
    }

    private var taskKey: String {
        store.connection?.id.uuidString ?? "none"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.connection == nil {
                    EmptyConnectionView {}
                } else {
                    catalogHeader

                    if case .failed(let error) = store.state, sessions.isEmpty {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline)
                            .foregroundStyle(TraceFenceDesign.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if sessions.isEmpty, store.isRefreshing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text(language.text(
                                zh: "正在读取 Mac 上的全部 Agent 会话",
                                en: "Loading all Agent sessions from the Mac",
                                zhHant: "正在讀取 Mac 上的全部 Agent 工作階段",
                                ja: "Mac 上のすべての Agent セッションを読み込み中",
                                ko: "Mac의 모든 Agent 세션을 불러오는 중",
                                mt: "Qed jittellgħu s-sessjonijiet kollha tal-Agent mill-Mac"
                            ))
                            .font(.subheadline)
                            .foregroundStyle(TraceFenceDesign.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 28)
                    } else if sessions.isEmpty {
                        EmptyInlineState(
                            icon: "bubble.left.and.text.bubble.right",
                            title: language.text(zh: "没有找到会话", en: "No sessions found", zhHant: "找不到工作階段", ja: "セッションが見つかりません", ko: "세션을 찾을 수 없음", mt: "Ma nstabet ebda sessjoni"),
                            detail: language.text(
                                zh: "调整搜索或筛选；Mac Core 会列出已发现的 Codex、Claude 和其他 Agent 会话。",
                                en: "Change the search or filter. Mac Core lists discovered Codex, Claude, and other Agent sessions.",
                                zhHant: "調整搜尋或篩選；Mac Core 會列出已發現的 Codex、Claude 及其他 Agent 工作階段。",
                                ja: "検索またはフィルターを変更してください。Mac Core は検出した Codex、Claude、その他の Agent セッションを表示します。",
                                ko: "검색 또는 필터를 변경하세요. Mac Core는 발견한 Codex, Claude 및 기타 Agent 세션을 표시합니다.",
                                mt: "Ibdel it-tiftix jew il-filtru. Mac Core juri s-sessjonijiet misjuba ta' Codex, Claude u Agents oħra."
                            )
                        )
                    } else {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(agentGroups) { agent in
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "cpu.fill")
                                            .foregroundStyle(TraceFenceDesign.accent)
                                        Text(agent.name)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(TraceFenceDesign.text)
                                            .lineLimit(1)
                                        Spacer()
                                        Text("\(agent.sessionCount)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(TraceFenceDesign.secondary)
                                    }
                                    ForEach(agent.projects) { project in
                                        VStack(alignment: .leading, spacing: 8) {
                                            HStack(spacing: 7) {
                                                Image(systemName: "folder.fill")
                                                    .foregroundStyle(TraceFenceDesign.secondary)
                                                Text(project.name)
                                                    .font(.caption.weight(.semibold))
                                                    .foregroundStyle(TraceFenceDesign.secondary)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)
                                            }
                                            ForEach(project.sessions) { session in
                                                if session.isScheduledTask {
                                                    SessionCatalogRow(session: session)
                                                } else {
                                                    NavigationLink {
                                                        SessionContextView(initialSession: session)
                                                    } label: {
                                                        SessionCatalogRow(session: session)
                                                    }
                                                    .buttonStyle(.plain)
                                                }
                                            }
                                        }
                                        .padding(.leading, 14)
                                    }
                                }
                            }
                        }
                    }

                    if !launchTargets.isEmpty {
                        Divider()
                            .padding(.vertical, 4)
                        SectionTitle(title: "新建可控会话", systemImage: "plus.rectangle.on.rectangle")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(launchTargets) { target in
                                Button {
                                    launchInstruction = ""
                                    launchTarget = target
                                } label: {
                                    Label(target.controlConsoleName.tfLocalized, systemImage: "plus.circle.fill")
                                        .font(.subheadline.weight(.semibold))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }
                                .buttonStyle(.bordered)
                                .tint(TraceFenceDesign.accent)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(TraceFenceDesign.background.ignoresSafeArea())
        .navigationTitle(language.text(zh: "会话", en: "Sessions", zhHant: "工作階段", ja: "セッション", ko: "세션", mt: "Sessjonijiet"))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: language.text(zh: "搜索项目、会话或内容", en: "Search projects, sessions, or content", zhHant: "搜尋專案、工作階段或內容", ja: "プロジェクト、セッション、内容を検索", ko: "프로젝트, 세션 또는 내용 검색", mt: "Fittex proġetti, sessjonijiet jew kontenut")
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await store.refreshFromUser()
                    }
                } label: {
                    if store.isRefreshing || store.sessionCatalogLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .help(language.text(zh: "刷新会话", en: "Refresh sessions", zhHant: "重新整理工作階段", ja: "セッションを更新", ko: "세션 새로 고침", mt: "Aġġorna s-Sessjonijiet"))
                .disabled(store.connection == nil || store.isRefreshing || store.sessionCatalogLoading)
            }
        }
        .refreshable {
            await store.refreshFromUser()
        }
        .sheet(item: $launchTarget, onDismiss: {
            launchInstruction = ""
        }) { target in
            LaunchAgentSheet(
                target: target,
                instruction: $launchInstruction,
                submit: { instruction in
                    launchTarget = nil
                    launchInstruction = ""
                    Task {
                        await store.launchSession(target, instruction: instruction)
                        await store.loadSessionCatalog(reset: true, query: searchText, scope: scope.rawValue)
                    }
                }
            )
        }
        .task(id: taskKey) {
            guard store.connection != nil else { return }
            await store.refreshIfStale()
        }
    }

    private var catalogHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(
                    language.text(zh: "全部 Agent 会话", en: "All Agent Sessions", zhHant: "全部 Agent 工作階段", ja: "すべての Agent セッション", ko: "모든 Agent 세션", mt: "Is-Sessjonijiet Kollha tal-Agent"),
                    systemImage: "bubble.left.and.text.bubble.right.fill"
                )
                .font(.headline)
                Spacer()
                Text("\(sessions.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(TraceFenceDesign.secondary)
            }
            Picker(
                language.text(zh: "会话范围", en: "Session scope", zhHant: "工作階段範圍", ja: "セッション範囲", ko: "세션 범위", mt: "Ambitu tas-Sessjoni"),
                selection: $scope
            ) {
                ForEach(SessionCatalogScope.allCases) { item in
                    Text(item.title(language)).tag(item)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private struct SessionCatalogRow: View {
    @Environment(\.appLanguage) private var language
    var session: AgentSessionSummary

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle()
                .fill(sessionPhaseColor(session.phase))
                .frame(width: 10, height: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 5) {
                Text(session.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TraceFenceDesign.text)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 6) {
                    Text("\(session.agentDisplayName) · \(session.phaseTitle)")
                        .font(.caption)
                        .foregroundStyle(sessionPhaseColor(session.phase))
                        .lineLimit(1)
                    if session.contextAvailable == true {
                        Image(systemName: "text.alignleft")
                            .font(.caption)
                            .foregroundStyle(TraceFenceDesign.secondary)
                            .accessibilityLabel(language.text(zh: "可查看上下文", en: "Context available", zhHant: "可查看上下文", ja: "コンテキストあり", ko: "컨텍스트 사용 가능", mt: "Kuntest disponibbli"))
                    }
                }
                if session.isScheduledTask, let nextRunText {
                    Label(nextRunText, systemImage: "calendar.badge.clock")
                        .font(.caption)
                        .foregroundStyle(TraceFenceDesign.secondary)
                } else if let response = session.lastResponse, !response.isEmpty {
                    Text(response)
                        .font(.caption)
                        .foregroundStyle(TraceFenceDesign.secondary)
                        .lineLimit(2)
                }
            }
            Image(systemName: session.isScheduledTask ? "calendar" : "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(TraceFenceDesign.secondary.opacity(0.7))
                .padding(.top, 5)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(sessionPhaseColor(session.phase).opacity(0.065))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    private var nextRunText: String? {
        guard let date = session.nextRunDate else { return nil }
        let value = date.formatted(date: .abbreviated, time: .shortened)
        return language.text(
            zh: "下次执行：\(value)",
            en: "Next run: \(value)",
            zhHant: "下次執行：\(value)",
            ja: "次回実行: \(value)",
            ko: "다음 실행: \(value)",
            mt: "Eżekuzzjoni li jmiss: \(value)"
        )
    }
}

private enum SessionInstructionMode: String, CaseIterable, Identifiable {
    case append
    case interruptThenChange

    var id: String { rawValue }

    func title(_ language: AppLanguage) -> String {
        switch self {
        case .append:
            return language.text(zh: "追加指令", en: "Add instruction", zhHant: "追加指令", ja: "指示を追加", ko: "지시 추가", mt: "Żid Struzzjoni")
        case .interruptThenChange:
            return language.text(zh: "中断后更改", en: "Interrupt & change", zhHant: "中斷後更改", ja: "中断して変更", ko: "중단 후 변경", mt: "Interrompi u Ibdel")
        }
    }
}

private enum PendingContextDestructiveAction: Identifiable {
    case interruptOnly
    case interruptAndSend(String)

    var id: String {
        switch self {
        case .interruptOnly: return "interrupt"
        case .interruptAndSend: return "interrupt-and-send"
        }
    }
}

private struct SessionContextView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var store: ConnectionStore
    let initialSession: AgentSessionSummary
    @State private var instruction = ""
    @State private var instructionMode: SessionInstructionMode = .append
    @State private var isSubmitting = false
    @State private var pendingDestructiveAction: PendingContextDestructiveAction?
    @State private var visibleTurnCount = 3

    private var snapshot: AgentSessionContextSnapshot? {
        store.sessionContexts[initialSession.id]
    }

    private var session: AgentSessionSummary {
        snapshot?.session ?? initialSession
    }

    private var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var queuedAction: RemoteActionQueueItem? {
        store.latestRemoteAction(forSessionId: session.id)
    }

    private var conversationTurns: [AgentConversationTurn] {
        AgentConversationTurn.group(snapshot?.messages ?? [])
    }

    private var visibleTurns: [AgentConversationTurn] {
        Array(conversationTurns.suffix(max(3, visibleTurnCount)))
    }

    private func conversationTurnTitle(_ turn: AgentConversationTurn) -> String {
        guard let index = conversationTurns.firstIndex(where: { $0.id == turn.id }) else {
            return language.text(zh: "会话轮次", en: "Conversation turn", zhHant: "工作階段輪次", ja: "会話ターン", ko: "대화 turn", mt: "Turn tal-konversazzjoni")
        }
        let distance = conversationTurns.count - index - 1
        switch distance {
        case 0:
            return language.text(zh: "当前一轮", en: "Current turn", zhHant: "目前一輪", ja: "現在のターン", ko: "현재 turn", mt: "It-turn attwali")
        case 1:
            return language.text(zh: "上一轮", en: "Previous turn", zhHant: "上一輪", ja: "前のターン", ko: "이전 turn", mt: "It-turn preċedenti")
        default:
            return language.text(
                zh: "前 \(distance) 轮",
                en: "\(distance) turns ago",
                zhHant: "前 \(distance) 輪",
                ja: "\(distance) ターン前",
                ko: "\(distance)개 turn 전",
                mt: "\(distance) turns ilu"
            )
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                sessionHeader

                if conversationTurns.count > visibleTurnCount || snapshot?.hasMore == true {
                    Button {
                        Task {
                            if conversationTurns.count <= visibleTurnCount, snapshot?.hasMore == true {
                                await store.loadSessionContext(session, older: true)
                            }
                            visibleTurnCount += 3
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if snapshot?.isLoading == true { ProgressView() }
                            Label(
                                language.text(zh: "再看前面三轮", en: "Show three earlier turns", zhHant: "再看前面三輪", ja: "さらに前の 3 ターンを表示", ko: "이전 3개 turn 더 보기", mt: "Uri tliet turns preċedenti oħra"),
                                systemImage: "arrow.up.circle"
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(snapshot?.isLoading == true)
                }

                if let error = snapshot?.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(TraceFenceDesign.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if snapshot?.messages.isEmpty != false, snapshot?.isLoading == true {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(language.text(zh: "正在读取会话上下文", en: "Loading session context", zhHant: "正在讀取工作階段上下文", ja: "セッションのコンテキストを読み込み中", ko: "세션 컨텍스트 불러오는 중", mt: "Qed jittella' l-kuntest tas-sessjoni"))
                            .foregroundStyle(TraceFenceDesign.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 36)
                } else if snapshot?.messages.isEmpty != false {
                    EmptyInlineState(
                        icon: "doc.text.magnifyingglass",
                        title: language.text(zh: "还没有可读上下文", en: "No readable context yet", zhHant: "尚無可讀上下文", ja: "読み取れるコンテキストはまだありません", ko: "읽을 수 있는 컨텍스트가 아직 없음", mt: "Għad m'hemmx kuntest li jista' jinqara"),
                        detail: language.text(
                            zh: "实时会话可能尚未写入 transcript；执行一次交互后再刷新。",
                            en: "A live session may not have written its transcript yet. Refresh after the next interaction.",
                            zhHant: "即時工作階段可能尚未寫入 transcript；互動一次後再重新整理。",
                            ja: "ライブセッションはまだ transcript を書き込んでいない可能性があります。次の操作後に更新してください。",
                            ko: "실시간 세션이 아직 transcript를 기록하지 않았을 수 있습니다. 다음 상호작용 후 새로 고침하세요.",
                            mt: "Sessjoni live tista' tkun għadha ma kitbitx it-transcript. Aġġorna wara l-interazzjoni li jmiss."
                        )
                    )
                } else {
                    if snapshot?.truncated == true {
                        Label(
                            language.text(zh: "此超长会话仅保留最近 5000 条上下文记录。", en: "This very long session is limited to its latest 5,000 context records.", zhHant: "此超長工作階段僅保留最近 5,000 條上下文記錄。", ja: "非常に長いセッションのため、最新 5,000 件のコンテキストのみ表示します。", ko: "매우 긴 세션이므로 최근 5,000개 컨텍스트 기록만 표시합니다.", mt: "Din is-sessjoni twila hija limitata għall-aħħar 5,000 rekord tal-kuntest."),
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(TraceFenceDesign.warning)
                    }
                    HStack {
                        Label(
                            language.text(zh: "最近三轮会话", en: "Recent three turns", zhHant: "最近三輪工作階段", ja: "直近 3 ターン", ko: "최근 3개 turn", mt: "L-aħħar tliet turns"),
                            systemImage: "clock.arrow.circlepath"
                        )
                        .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(visibleTurns.count) / \(conversationTurns.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(TraceFenceDesign.secondary)
                    }
                    ForEach(visibleTurns) { turn in
                        ConversationTurnSection(turn: turn, title: conversationTurnTitle(turn))
                    }
                }
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .background(TraceFenceDesign.background.ignoresSafeArea())
        .navigationTitle(session.project.isEmpty ? session.agentDisplayName : session.project)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            instructionComposer
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshSessionContextFromUser(session) }
                } label: {
                    if snapshot?.isLoading == true {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(snapshot?.isLoading == true)
                .help(language.text(zh: "刷新上下文", en: "Refresh context", zhHant: "重新整理上下文", ja: "コンテキストを更新", ko: "컨텍스트 새로 고침", mt: "Aġġorna l-Kuntest"))

                if session.canInterrupt == true {
                    Button(role: .destructive) {
                        pendingDestructiveAction = .interruptOnly
                    } label: {
                        Image(systemName: "stop.fill")
                    }
                    .disabled(queuedAction?.state.isActive == true)
                    .help(language.text(zh: "中断当前任务", en: "Interrupt current task", zhHant: "中斷目前任務", ja: "現在のタスクを中断", ko: "현재 작업 중단", mt: "Interrompi l-kompitu attwali"))
                }
            }
        }
        .task {
            await store.loadSessionContext(initialSession)
        }
        .alert(
            contextInterruptTitle,
            isPresented: Binding(
                get: { pendingDestructiveAction != nil },
                set: { if !$0 { pendingDestructiveAction = nil } }
            ),
            presenting: pendingDestructiveAction
        ) { action in
            Button(contextInterruptConfirmTitle(action), role: .destructive) {
                pendingDestructiveAction = nil
                switch action {
                case .interruptOnly:
                    performInterruptOnly()
                case .interruptAndSend(let text):
                    performInstruction(text, interruptFirst: true)
                }
            }
            Button(language.text(zh: "取消", en: "Cancel", zhHant: "取消", ja: "キャンセル", ko: "취소", mt: "Ikkanċella"), role: .cancel) {
                pendingDestructiveAction = nil
            }
        } message: { action in
            Text(contextInterruptMessage(action))
        }
    }

    private var sessionHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(sessionPhaseColor(session.phase))
                    .frame(width: 11, height: 11)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .font(.headline)
                        .foregroundStyle(TraceFenceDesign.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(session.agentDisplayName) · \(session.phaseTitle)")
                        .font(.subheadline)
                        .foregroundStyle(sessionPhaseColor(session.phase))
                }
                Spacer()
            }
            if !session.cwd.isEmpty {
                Label(session.cwd, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(TraceFenceDesign.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            HStack(spacing: 12) {
                if let engine = session.engineLabel, !engine.isEmpty {
                    Label(engine, systemImage: "cpu")
                }
                if let total = snapshot?.totalCount, total > 0 {
                    Label("\(total)", systemImage: "text.alignleft")
                }
            }
            .font(.caption)
            .foregroundStyle(TraceFenceDesign.secondary)
        }
        .padding(.bottom, 4)
    }

    private var instructionComposer: some View {
        VStack(spacing: 10) {
            if let queuedAction {
                RemoteActionInlineStatus(action: queuedAction)
            }

            if session.phase == "processing" {
                Picker(
                    language.text(zh: "指令方式", en: "Instruction mode", zhHant: "指令方式", ja: "指示モード", ko: "지시 방식", mt: "Mod tal-Istruzzjoni"),
                    selection: $instructionMode
                ) {
                    ForEach(SessionInstructionMode.allCases) { mode in
                        Text(mode.title(language)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    language.text(zh: "输入下一步指令或修正要求", en: "Enter the next instruction or correction", zhHant: "輸入下一步指令或修正要求", ja: "次の指示または修正内容を入力", ko: "다음 지시 또는 수정 요청 입력", mt: "Daħħal l-istruzzjoni jew il-korrezzjoni li jmiss"),
                    text: $instruction,
                    axis: .vertical
                )
                .lineLimit(1...6)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button {
                    submitInstruction()
                } label: {
                    if isSubmitting {
                        ProgressView()
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .disabled(trimmedInstruction.isEmpty || isSubmitting || queuedAction?.state.isActive == true || session.controlAvailable != true)
                .accessibilityLabel(language.text(zh: "发送指令", en: "Send instruction", zhHant: "傳送指令", ja: "指示を送信", ko: "지시 보내기", mt: "Ibgħat Struzzjoni"))
            }

            Text(composerExplanation)
                .font(.caption2)
                .foregroundStyle(TraceFenceDesign.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
        .overlay(alignment: .top) { Divider() }
    }

    private var composerExplanation: String {
        if session.controlAvailable != true {
            return language.text(zh: "此会话当前只能查看，Mac Core 未声明可控运行时。", en: "This session is currently read-only because Mac Core did not report a controllable runtime.", zhHant: "此工作階段目前只能查看，Mac Core 未宣告可控執行階段。", ja: "Mac Core が制御可能なランタイムを報告していないため、このセッションは読み取り専用です。", ko: "Mac Core가 제어 가능한 런타임을 보고하지 않아 현재 이 세션은 읽기 전용입니다.", mt: "Din is-sessjoni bħalissa hija qari biss għax Mac Core ma rrapportax runtime kontrollabbli.")
        }
        if session.phase != "processing" {
            return language.text(zh: "发送后会在这个真实会话中开始新的 turn。", en: "Sending starts a new turn in this real session.", zhHant: "傳送後會在此真實工作階段中開始新的 turn。", ja: "送信すると、この実セッションで新しい turn が開始されます。", ko: "보내면 이 실제 세션에서 새 turn이 시작됩니다.", mt: "Meta tibgħat, jibda turn ġdid f'din is-sessjoni reali.")
        }
        switch instructionMode {
        case .append:
            return language.text(zh: "保留当前任务，并把内容插入正在执行的 turn。", en: "Keep the current task and steer the running turn with this instruction.", zhHant: "保留目前任務，並把內容插入正在執行的 turn。", ja: "現在のタスクを維持し、実行中の turn にこの指示を挿入します。", ko: "현재 작업을 유지하고 실행 중인 turn에 이 지시를 삽입합니다.", mt: "Żomm il-kompitu attwali u daħħal l-istruzzjoni fit-turn li għaddej.")
        case .interruptThenChange:
            return language.text(zh: "先中断当前 turn，再用这条指令开始新的 turn。", en: "Interrupt the current turn first, then start a new turn with this instruction.", zhHant: "先中斷目前 turn，再用此指令開始新的 turn。", ja: "現在の turn を中断し、この指示で新しい turn を開始します。", ko: "현재 turn을 먼저 중단한 뒤 이 지시로 새 turn을 시작합니다.", mt: "L-ewwel interrompi t-turn attwali, imbagħad ibda turn ġdid b'din l-istruzzjoni.")
        }
    }

    private func submitInstruction() {
        let text = trimmedInstruction
        guard !text.isEmpty, !isSubmitting else { return }
        if session.phase == "processing", instructionMode == .interruptThenChange {
            pendingDestructiveAction = .interruptAndSend(text)
            return
        }
        performInstruction(text, interruptFirst: false)
    }

    private func performInstruction(_ text: String, interruptFirst: Bool) {
        isSubmitting = true
        Task {
            if interruptFirst {
                let interrupted = await store.controlSession(session, command: .interrupt)
                guard interrupted else {
                    isSubmitting = false
                    return
                }
            }
            let succeeded = await store.controlSession(session, command: .resume, instruction: text)
            if succeeded {
                instruction = ""
                try? await Task.sleep(for: .seconds(1))
                await store.loadSessionContext(session, force: true)
            }
            isSubmitting = false
        }
    }

    private func performInterruptOnly() {
        Task {
            await store.controlSession(session, command: .interrupt)
            try? await Task.sleep(for: .seconds(1))
            await store.loadSessionContext(session, force: true)
        }
    }

    private var contextInterruptTitle: String {
        language.text(
            zh: "确认中断这个会话？",
            en: "Interrupt this session?",
            zhHant: "確認中斷此工作階段？",
            ja: "このセッションを中断しますか？",
            ko: "이 세션을 중단할까요?",
            mt: "Tinterrompi din is-sessjoni?"
        )
    }

    private func contextInterruptConfirmTitle(_ action: PendingContextDestructiveAction) -> String {
        switch action {
        case .interruptOnly:
            return language.text(zh: "确认中断", en: "Interrupt", zhHant: "確認中斷", ja: "中断する", ko: "중단", mt: "Interrompi")
        case .interruptAndSend:
            return language.text(zh: "中断并发送", en: "Interrupt & Send", zhHant: "中斷並傳送", ja: "中断して送信", ko: "중단 후 보내기", mt: "Interrompi u Ibgħat")
        }
    }

    private func contextInterruptMessage(_ action: PendingContextDestructiveAction) -> String {
        switch action {
        case .interruptOnly:
            return language.text(
                zh: "“\(session.displayTitle)”当前执行会立即停止，正在运行的工具命令可能只完成一部分。确认后仍可发送新指令继续。",
                en: "\"\(session.displayTitle)\" will stop immediately. A running tool command may finish only partially. You can send a new instruction afterward.",
                zhHant: "「\(session.displayTitle)」目前執行會立即停止，正在執行的工具命令可能只完成一部分。確認後仍可傳送新指令繼續。",
                ja: "「\(session.displayTitle)」の実行を直ちに停止します。実行中のツールコマンドが一部だけ完了する場合があります。その後、新しい指示で続行できます。",
                ko: "‘\(session.displayTitle)’의 현재 실행이 즉시 중지됩니다. 실행 중인 도구 명령이 일부만 완료될 수 있습니다. 이후 새 지시로 계속할 수 있습니다.",
                mt: "L-eżekuzzjoni ta' \"\(session.displayTitle)\" tieqaf minnufih. Kmand ta' għodda jista' jitlesta biss parzjalment. Tista' tibgħat struzzjoni ġdida wara."
            )
        case .interruptAndSend:
            return language.text(
                zh: "将先中断“\(session.displayTitle)”当前 turn，再用你输入的内容开始新 turn。中断前正在运行的命令不会继续。",
                en: "The current turn in \"\(session.displayTitle)\" will be interrupted before your instruction starts a new turn. Its running command will not continue.",
                zhHant: "將先中斷「\(session.displayTitle)」目前 turn，再用你輸入的內容開始新 turn。中斷前正在執行的命令不會繼續。",
                ja: "「\(session.displayTitle)」の現在の turn を中断してから、入力した内容で新しい turn を開始します。中断前のコマンドは続行されません。",
                ko: "‘\(session.displayTitle)’의 현재 turn을 중단한 뒤 입력한 내용으로 새 turn을 시작합니다. 중단 전 실행 중인 명령은 계속되지 않습니다.",
                mt: "It-turn attwali f'\"\(session.displayTitle)\" jiġi interrott qabel tibda turn ġdid bl-istruzzjoni tiegħek. Il-kmand li kien għaddej ma jkomplix."
            )
        }
    }
}

private struct ConversationTurnSection: View {
    var turn: AgentConversationTurn
    var title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TraceFenceDesign.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                Rectangle()
                    .fill(TraceFenceDesign.secondary.opacity(0.2))
                    .frame(height: 1)
            }
            ForEach(turn.messages) { message in
                ContextMessageRow(message: message)
            }
        }
        .id(turn.id)
    }
}

private struct ContextMessageRow: View {
    @Environment(\.appLanguage) private var language
    var message: AgentContextMessage
    @State private var expanded = false

    private var isUser: Bool { message.role == "user" }
    private var isTool: Bool { message.role == "tool" }
    private var isEvent: Bool { message.kind == "event" }

    var body: some View {
        if isEvent {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(TraceFenceDesign.secondary.opacity(0.25))
                    .frame(height: 1)
                Label(eventTitle, systemImage: eventIcon)
                    .font(.caption)
                    .foregroundStyle(TraceFenceDesign.secondary)
                    .fixedSize()
                Rectangle()
                    .fill(TraceFenceDesign.secondary.opacity(0.25))
                    .frame(height: 1)
            }
            .padding(.vertical, 4)
        } else {
            HStack(alignment: .top, spacing: 8) {
                if isUser { Spacer(minLength: 34) }
                if !isUser {
                    Image(systemName: isTool ? "wrench.and.screwdriver.fill" : "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isTool ? TraceFenceDesign.warning : TraceFenceDesign.accent)
                        .frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(roleTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(TraceFenceDesign.secondary)
                        if let time = formattedTime {
                            Text(time)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(TraceFenceDesign.secondary.opacity(0.8))
                        }
                    }
                    Text(message.text.isEmpty ? roleTitle : message.text)
                        .font(isTool ? .caption.monospaced() : .subheadline)
                        .foregroundStyle(TraceFenceDesign.text)
                        .lineLimit(expanded ? nil : 24)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if message.text.count > 1_200 {
                        Button(expanded
                            ? language.text(zh: "收起", en: "Collapse", zhHant: "收合", ja: "折りたたむ", ko: "접기", mt: "Agħlaq")
                            : language.text(zh: "展开全文", en: "Show full text", zhHant: "展開全文", ja: "全文を表示", ko: "전체 텍스트 보기", mt: "Uri t-Test Kollu")) {
                                expanded.toggle()
                            }
                            .font(.caption.weight(.semibold))
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(messageBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if !isUser { Spacer(minLength: 24) }
            }
        }
    }

    private var roleTitle: String {
        if isUser {
            return language.text(zh: "你", en: "You", zhHant: "你", ja: "あなた", ko: "사용자", mt: "Int")
        }
        if isTool {
            let fallback = message.kind == "toolResult"
                ? language.text(zh: "工具结果", en: "Tool result", zhHant: "工具結果", ja: "ツール結果", ko: "도구 결과", mt: "Riżultat tal-Għodda")
                : language.text(zh: "工具调用", en: "Tool call", zhHant: "工具呼叫", ja: "ツール呼び出し", ko: "도구 호출", mt: "Sejħa tal-Għodda")
            return message.toolName?.isEmpty == false ? message.toolName! : fallback
        }
        return language.text(zh: "Agent", en: "Agent", zhHant: "Agent", ja: "Agent", ko: "Agent", mt: "Agent")
    }

    private var eventTitle: String {
        switch message.text {
        case "task_started":
            return language.text(zh: "任务开始", en: "Task started", zhHant: "任務開始", ja: "タスク開始", ko: "작업 시작", mt: "Il-kompitu beda")
        case "task_complete":
            return language.text(zh: "任务完成", en: "Task completed", zhHant: "任務完成", ja: "タスク完了", ko: "작업 완료", mt: "Il-kompitu tlesta")
        case "turn_aborted":
            return language.text(zh: "任务已中断", en: "Task interrupted", zhHant: "任務已中斷", ja: "タスク中断", ko: "작업 중단됨", mt: "Il-kompitu ġie interrott")
        case "context_compacted":
            return language.text(zh: "上下文已整理", en: "Context compacted", zhHant: "上下文已整理", ja: "コンテキストを整理", ko: "컨텍스트 정리됨", mt: "Il-kuntest ġie mqassar")
        default:
            return message.text
        }
    }

    private var eventIcon: String {
        switch message.text {
        case "task_complete": return "checkmark.circle.fill"
        case "turn_aborted": return "stop.circle.fill"
        case "context_compacted": return "arrow.triangle.2.circlepath"
        default: return "play.circle.fill"
        }
    }

    private var messageBackground: Color {
        if isUser { return TraceFenceDesign.accent.opacity(0.12) }
        if isTool { return TraceFenceDesign.warning.opacity(0.10) }
        return Color.black.opacity(0.045)
    }

    private var formattedTime: String? {
        guard let timestamp = message.timestamp,
              let date = ISO8601DateFormatter().date(from: timestamp) else { return nil }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private func sessionPhaseColor(_ phase: String) -> Color {
    switch phase {
    case "waitingApproval", "waitingInput": return TraceFenceDesign.warning
    case "interrupted", "error": return TraceFenceDesign.danger
    case "processing", "compacting": return TraceFenceDesign.success
    default: return TraceFenceDesign.accent
    }
}

struct ConfirmationsView: View {
    @EnvironmentObject private var store: ConnectionStore
    @State private var approvalAnswers: [String: String] = [:]

    private var approvals: [PendingApprovalSummary] {
        store.agentControl?.pendingApprovals ?? []
    }

    private var alertSessions: [AgentSessionSummary] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return store.installedAgentSessions.filter { session in
            guard (session.activityDate ?? .distantPast) >= cutoff else { return false }
            let actionable = session.canStartContinuation ||
                (session.phase == "waitingInput" && session.canSendContinuation) ||
                (["error", "interrupted"].contains(session.phase) && session.canSendContinuation)
            if actionable { return true }
            let isNonActionableAlert = session.needsAttention ||
                session.controlReason == "unsafe_or_unknown_process" ||
                session.controlReason == "snapshot_without_runtime"
            return isNonActionableAlert
        }
        .sorted(by: AgentSessionPresentationPolicy.presentationSort)
    }

    private var alertEvents: [AgentEventSummary] {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        return (store.agentControl?.recentEvents ?? []).filter { event in
            guard (event.timestampDate ?? .distantPast) >= cutoff else { return false }
            return event.status == "pending" ||
                event.type == "permission" ||
                event.type == "plan" ||
                event.type == "question"
        }
        .sorted { ($0.timestampDate ?? .distantPast) > ($1.timestampDate ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if store.connection == nil {
                    EmptyConnectionView {}
                } else {
                    if !store.remoteActionQueue.isEmpty {
                        TFCard {
                            HStack {
                                SectionTitle(title: "操作队列", systemImage: "tray.full.fill")
                                Spacer()
                                Button {
                                    store.clearCompletedRemoteActions()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(TraceFenceDesign.secondary)
                                .accessibilityLabel("清除已完成操作".tfLocalized)
                            }
                            VStack(spacing: 8) {
                                ForEach(Array(store.remoteActionQueue.reversed().prefix(10))) { action in
                                    RemoteActionQueueRow(action: action)
                                }
                            }
                        }
                    }

                    TFCard {
                        SectionTitle(title: "命令确认", systemImage: "checkmark.shield.fill")
                        if approvals.isEmpty {
                            EmptyInlineState(
                                icon: "checkmark.seal.fill",
                                title: "当前没有待确认命令",
                                detail: "权限请求、计划确认和等待回复会集中出现在这里。"
                            )
                        } else {
                            VStack(spacing: 12) {
                                ForEach(approvals) { approval in
                                    ApprovalRow(
                                        approval: approval,
                                        action: store.remoteAction(forApprovalId: approval.id),
                                        answer: Binding(
                                            get: { approvalAnswers[approval.id] ?? "" },
                                            set: { approvalAnswers[approval.id] = $0 }
                                        ),
                                        approve: {
                                            Task {
                                                await store.resolveApproval(
                                                    approval,
                                                    allow: true,
                                                    answer: approvalAnswers[approval.id]
                                                )
                                            }
                                        },
                                        deny: {
                                            Task {
                                                await store.resolveApproval(
                                                    approval,
                                                    allow: false,
                                                    answer: approvalAnswers[approval.id]
                                                )
                                            }
                                        }
                                    )
                                }
                            }
                        }
                    }

                    TFCard {
                        SectionTitle(title: "告警", systemImage: "exclamationmark.triangle.fill")
                        let alerts = alertSessions
                        if alerts.isEmpty && alertEvents.isEmpty {
                            EmptyInlineState(
                                icon: "bell.slash.fill",
                                title: "当前没有告警",
                                detail: "等待输入、可接管任务、受限控制和待处理事件会出现在这里。"
                            )
                        } else {
                            VStack(spacing: 10) {
                                ForEach(Array(alerts.prefix(16))) { session in
                                    AgentAlertRow(session: session)
                                }
                                ForEach(Array(alertEvents.prefix(12))) { event in
                                    TimelineRow(event: event)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(TraceFenceDesign.background.ignoresSafeArea())
        .navigationTitle("确认")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.refreshFromUser() }
                } label: {
                    if store.isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(store.connection == nil || store.isRefreshing)
            }
        }
        .refreshable {
            await store.refreshFromUser()
        }
        .task {
            if store.connection != nil {
                await store.refreshIfStale()
            }
        }
    }
}

private struct SectionTitle: View {
    var title: String
    var systemImage: String

    var body: some View {
        Label(title.tfLocalized, systemImage: systemImage)
            .font(.headline)
            .foregroundStyle(TraceFenceDesign.text)
    }
}

private struct ApprovalRow: View {
    @Environment(\.appLanguage) private var language
    var approval: PendingApprovalSummary
    var action: RemoteActionQueueItem?
    @Binding var answer: String
    var approve: () -> Void
    var deny: () -> Void

    private var isActionLocked: Bool {
        guard let action else { return false }
        return action.state.isActive || action.state == .succeeded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: approvalIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(riskColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(approval.kindTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(riskColor)
                        Text(approval.riskTitle)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(riskColor)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(riskColor.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text(approval.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TraceFenceDesign.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(approval.agentDisplayName) · \(approval.projectDisplayName)")
                        .font(.caption)
                        .foregroundStyle(TraceFenceDesign.secondary)
                }
            }

            if let command = approval.displayCommand {
                ApprovalInformationBlock(
                    title: language.text(zh: "将要执行", en: "Will run", zhHant: "將要執行", ja: "実行する内容", ko: "실행할 명령", mt: "Se jitħaddem"),
                    icon: "terminal.fill",
                    value: command,
                    monospaced: true
                )
            }

            if let directory = approval.displayWorkingDirectory {
                ApprovalInformationBlock(
                    title: language.text(zh: "工作目录", en: "Working directory", zhHant: "工作目錄", ja: "作業ディレクトリ", ko: "작업 디렉터리", mt: "Direttorju tax-xogħol"),
                    icon: "folder.fill",
                    value: directory,
                    monospaced: true
                )
            }

            if !displayTargetPaths.isEmpty {
                ApprovalInformationBlock(
                    title: language.text(zh: "影响位置", en: "Affected locations", zhHant: "影響位置", ja: "対象の場所", ko: "영향 위치", mt: "Postijiet affettwati"),
                    icon: "doc.badge.ellipsis",
                    value: displayTargetPaths.joined(separator: "\n"),
                    monospaced: true
                )
            }

            if let reason = approval.displayReason {
                ApprovalInformationBlock(
                    title: language.text(zh: "请求原因", en: "Reason", zhHant: "請求原因", ja: "理由", ko: "요청 이유", mt: "Raġuni"),
                    icon: "text.bubble.fill",
                    value: reason,
                    monospaced: false
                )
            }

            if let permissions = approval.permissions, !permissions.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Label(
                        language.text(zh: "新增权限", en: "Additional access", zhHant: "新增權限", ja: "追加アクセス", ko: "추가 권한", mt: "Aċċess addizzjonali"),
                        systemImage: "key.fill"
                    )
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TraceFenceDesign.secondary)
                    ForEach(permissions, id: \.self) { permission in
                        Text(permission.tfLocalized)
                            .font(.caption)
                            .foregroundStyle(TraceFenceDesign.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(10)
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if let options = approval.options, !options.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text(language.text(zh: "可选回复", en: "Suggested replies", zhHant: "可選回覆", ja: "返信候補", ko: "추천 답변", mt: "Tweġibiet issuġġeriti"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(TraceFenceDesign.secondary)
                    ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                        Button {
                            answer = option
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option)
                                    .font(.caption.weight(.semibold))
                                if let descriptions = approval.descriptions,
                                   descriptions.indices.contains(index),
                                   !descriptions[index].isEmpty {
                                    Text(descriptions[index])
                                        .font(.caption2)
                                        .foregroundStyle(TraceFenceDesign.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .padding(9)
                        .background(TraceFenceDesign.accent.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .disabled(isActionLocked)
                    }
                }
            }

            TextField(
                approval.kind == "question" ? "回复 Agent" : "拒绝后发送替代指令（可选）",
                text: $answer,
                axis: .vertical
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(2...4)
            .disabled(isActionLocked)

            if let action {
                RemoteActionInlineStatus(action: action)
            }

            if !isActionLocked {
                HStack(spacing: 10) {
                    Button(action: approve) {
                        Label("批准并继续", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: deny) {
                        Label(
                            approval.kind != "question" && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "拒绝并改指令"
                                : "拒绝",
                            systemImage: "xmark.circle.fill"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(TraceFenceDesign.danger)
                }
            }
        }
        .padding(12)
        .background(riskColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var displayTargetPaths: [String] {
        let directory = approval.displayWorkingDirectory
        return (approval.targetPaths ?? []).filter { path in
            let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed != directory
        }
    }

    private var approvalIcon: String {
        switch approval.kind {
        case "question": return "questionmark.bubble.fill"
        case "plan": return "list.clipboard.fill"
        default: return "hand.raised.fill"
        }
    }

    private var riskColor: Color {
        switch approval.risk {
        case "critical": return TraceFenceDesign.danger
        case "high": return TraceFenceDesign.warning
        default: return TraceFenceDesign.accent
        }
    }
}

private struct RemoteActionQueueRow: View {
    @Environment(\.appLanguage) private var language
    var action: RemoteActionQueueItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            stateIcon
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(action.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TraceFenceDesign.text)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text(stateTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stateColor)
                }
                Text(action.message)
                    .font(.caption)
                    .foregroundStyle(TraceFenceDesign.secondary)
                    .lineLimit(3)
                HStack(spacing: 8) {
                    Text(action.updatedAt.tfShortTimeText)
                    if action.attempts > 1 {
                        Text(language.text(
                            zh: "第 \(action.attempts) 次尝试",
                            en: "Attempt \(action.attempts)",
                            zhHant: "第 \(action.attempts) 次嘗試",
                            ja: "\(action.attempts) 回目",
                            ko: "\(action.attempts)번째 시도",
                            mt: "Tentattiv \(action.attempts)"
                        ))
                    }
                    Spacer(minLength: 4)
                    Text("ID \(action.id.uuidString.prefix(8).lowercased())")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(TraceFenceDesign.secondary.opacity(0.8))
            }
        }
        .padding(10)
        .background(stateColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @ViewBuilder
    private var stateIcon: some View {
        if action.state == .sending {
            ProgressView().controlSize(.small).tint(stateColor)
        } else {
            Image(systemName: stateSystemImage)
                .foregroundStyle(stateColor)
        }
    }

    private var stateTitle: String {
        switch action.state {
        case .queued: return language.text(zh: "已排队", en: "Queued", zhHant: "已排隊", ja: "待機中", ko: "대기 중", mt: "Fil-kju")
        case .sending: return language.text(zh: "发送中", en: "Sending", zhHant: "傳送中", ja: "送信中", ko: "전송 중", mt: "Qed jintbagħat")
        case .succeeded: return language.text(zh: "Mac 已确认", en: "Confirmed", zhHant: "Mac 已確認", ja: "Mac 確認済み", ko: "Mac 확인 완료", mt: "Ikkonfermat")
        case .failed: return language.text(zh: "失败，可重试", en: "Failed, retry", zhHant: "失敗，可重試", ja: "失敗、再試行可", ko: "실패, 재시도 가능", mt: "Falla, erġa' pprova")
        }
    }

    private var stateColor: Color {
        switch action.state {
        case .queued, .sending: return TraceFenceDesign.warning
        case .succeeded: return TraceFenceDesign.success
        case .failed: return TraceFenceDesign.danger
        }
    }

    private var stateSystemImage: String {
        switch action.state {
        case .queued: return "clock.fill"
        case .sending: return "arrow.up.circle.fill"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }
}

private struct RemoteActionInlineStatus: View {
    var action: RemoteActionQueueItem

    var body: some View {
        RemoteActionQueueRow(action: action)
    }
}

private struct ApprovalInformationBlock: View {
    var title: String
    var icon: String
    var value: String
    var monospaced: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(TraceFenceDesign.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(value)
                    .font(monospaced ? .system(.caption, design: .monospaced) : .caption)
                    .foregroundStyle(TraceFenceDesign.text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: monospaced, vertical: true)
                    .frame(maxWidth: monospaced ? nil : .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct LaunchAgentSheet: View {
    @Environment(\.dismiss) private var dismiss
    var target: AgentLaunchTargetSummary
    @Binding var instruction: String
    var submit: (String) -> Void

    private var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(target.controlConsoleName.tfLocalized)
                        .font(.headline)
                        .foregroundStyle(TraceFenceDesign.text)
                    Text("Mac 可控会话")
                        .font(.subheadline)
                        .foregroundStyle(TraceFenceDesign.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("会话指令")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TraceFenceDesign.text)
                    TextEditor(text: $instruction)
                        .frame(minHeight: 140)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if instruction.isEmpty {
                                Text("可留空，创建后也可以继续发送新指令")
                                    .font(.subheadline)
                                    .foregroundStyle(TraceFenceDesign.secondary.opacity(0.7))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                if let note = target.note, !note.isEmpty {
                    Label(note.tfLocalized, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(TraceFenceDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(18)
            .background(TraceFenceDesign.background.ignoresSafeArea())
            .navigationTitle("新建会话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("新建") {
                        submit(trimmedInstruction)
                    }
                    .disabled(!target.installed)
                }
            }
        }
    }
}

private struct ContinueSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var session: AgentSessionSummary
    @Binding var instruction: String
    var submit: (String) -> Void

    private var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.displayTitle)
                        .font(.headline)
                        .foregroundStyle(TraceFenceDesign.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(session.agentDisplayName) · \(session.phaseTitle)")
                        .font(.subheadline)
                        .foregroundStyle(TraceFenceDesign.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("发送指令")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TraceFenceDesign.text)
                    TextEditor(text: $instruction)
                        .frame(minHeight: 150)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if instruction.isEmpty {
                                Text("输入要发送给 Agent 的下一步要求、回复或修正说明")
                                    .font(.subheadline)
                                    .foregroundStyle(TraceFenceDesign.secondary.opacity(0.7))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                if let note = session.resumeNote, !note.isEmpty {
                    Label(note.tfLocalized, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(TraceFenceDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(18)
            .background(TraceFenceDesign.background.ignoresSafeArea())
            .navigationTitle("发送指令")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送") {
                        submit(trimmedInstruction)
                    }
                    .disabled(trimmedInstruction.isEmpty)
                }
            }
        }
    }
}

private struct RelaunchSessionSheet: View {
    @Environment(\.dismiss) private var dismiss
    var session: AgentSessionSummary
    @Binding var instruction: String
    var submit: (String) -> Void

    private var trimmedInstruction: String {
        instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(session.displayTitle)
                        .font(.headline)
                        .foregroundStyle(TraceFenceDesign.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(AppLanguage.current.text(
                        zh: "\(session.agentDisplayName) -> \(session.continuationControlTitle) 可控会话",
                        en: "\(session.agentDisplayName) -> controlled \(session.continuationControlTitle) session",
                        zhHant: "\(session.agentDisplayName) -> \(session.continuationControlTitle) 可控工作階段",
                        ja: "\(session.agentDisplayName) -> \(session.continuationControlTitle) 制御セッション",
                        ko: "\(session.agentDisplayName) -> \(session.continuationControlTitle) 제어 세션",
                        mt: "\(session.agentDisplayName) -> sessjoni kontrollabbli \(session.continuationControlTitle)"
                    ))
                        .font(.subheadline)
                        .foregroundStyle(TraceFenceDesign.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("发送指令")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TraceFenceDesign.text)
                    TextEditor(text: $instruction)
                        .frame(minHeight: 190)
                        .padding(8)
                        .scrollContentBackground(.hidden)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if instruction.isEmpty {
                                Text("输入要交给这个任务的下一步指令")
                                    .font(.subheadline)
                                    .foregroundStyle(TraceFenceDesign.secondary.opacity(0.7))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                if let note = session.relaunchNote, !note.isEmpty {
                    Label(note.tfLocalized, systemImage: "arrow.triangle.2.circlepath.circle")
                        .font(.caption)
                        .foregroundStyle(TraceFenceDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(18)
            .background(TraceFenceDesign.background.ignoresSafeArea())
            .navigationTitle("接管任务")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("接管并发送") {
                        submit(trimmedInstruction)
                    }
                    .disabled(trimmedInstruction.isEmpty || !session.canStartContinuation)
                }
            }
        }
    }
}

private struct AgentSessionRow: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var store: ConnectionStore
    var session: AgentSessionSummary
    var interrupt: () -> Void
    var resume: () -> Void
    var relaunch: () -> Void
    var terminate: () -> Void

    private var queuedAction: RemoteActionQueueItem? {
        store.latestRemoteAction(forSessionId: session.id)
    }

    private var actionInFlight: Bool {
        queuedAction?.state.isActive == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(phaseColor)
                    .frame(width: 11, height: 11)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TraceFenceDesign.text)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Text("\(session.agentDisplayName) · \(session.phaseTitle)")
                            .font(.caption)
                            .foregroundStyle(phaseColor)
                        if session.isScheduledTask {
                            StatusBadge(
                                text: "定时任务".tfLocalized,
                                color: TraceFenceDesign.accent,
                                systemImage: "calendar.badge.clock"
                            )
                        } else {
                            StatusBadge(
                                text: session.controlModeTitle,
                                color: controlColor,
                                systemImage: controlIcon
                            )
                        }
                    }
                    if let tool = session.lastToolName, !tool.isEmpty {
                        Text(toolLine(tool))
                            .font(.caption)
                            .foregroundStyle(TraceFenceDesign.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                if let pid = session.pid {
                    Text("pid \(pid)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(TraceFenceDesign.secondary)
                }
            }

            if let thought = session.lastThought, !thought.isEmpty {
                Text(thought)
                    .font(.caption)
                    .foregroundStyle(TraceFenceDesign.secondary)
                    .lineLimit(3)
            } else if let response = session.lastResponse, !response.isEmpty {
                Text(response)
                    .font(.caption)
                    .foregroundStyle(TraceFenceDesign.secondary)
                    .lineLimit(3)
            }

            if session.isScheduledTask, let nextRunText {
                Label(nextRunText, systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TraceFenceDesign.accent)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Label(session.primaryControlNote, systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(controlColor)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let queuedAction {
                RemoteActionInlineStatus(action: queuedAction)
            }

            if let limitations = session.controlLimitations, !limitations.isEmpty, session.isDisplayOnly, !session.isScheduledTask {
                Text(limitations.prefix(2).map(\.tfLocalized).joined(separator: "\n"))
                    .font(.caption2)
                    .foregroundStyle(TraceFenceDesign.secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if session.canStartContinuation, !session.isScheduledTask {
                Button(action: relaunch) {
                    Label("接管并发送指令", systemImage: "arrow.triangle.2.circlepath")
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(TraceFenceDesign.accent)
                .disabled(actionInFlight)
            }

            if !session.isScheduledTask, !session.isDisplayOnly {
                HStack(spacing: 10) {
                    Button(action: interrupt) {
                        Label((session.isCodexNative ? "中断" : "暂停").tfLocalized, systemImage: session.isCodexNative ? "stop.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(TraceFenceDesign.danger)
                    .disabled(session.canInterrupt != true || actionInFlight)

                    Button(action: resume) {
                        Label(
                            session.canSendContinuation
                                ? (session.isCodexNative && session.phase == "processing" ? "插入指令" : "发送指令").tfLocalized
                                : "只读".tfLocalized,
                            systemImage: session.canSendContinuation ? "text.bubble.fill" : "eye.fill"
                        )
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!session.canSendContinuation || actionInFlight)

                    if !session.isCodexNative {
                        Button(action: terminate) {
                            Label("终止", systemImage: "xmark.octagon.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(TraceFenceDesign.danger)
                        .disabled(session.canTerminate != true || actionInFlight)
                    }
                }
            }
        }
        .padding(12)
        .background(phaseColor.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func toolLine(_ tool: String) -> String {
        let localizedTool = tool.tfLocalized
        if let target = session.lastToolTarget, !target.isEmpty {
            return "\(localizedTool) · \(target)"
        }
        return localizedTool
    }

    private var nextRunText: String? {
        guard let date = session.nextRunDate else { return nil }
        let value = date.formatted(date: .abbreviated, time: .shortened)
        return language.text(
            zh: "下次执行：\(value)",
            en: "Next run: \(value)",
            zhHant: "下次執行：\(value)",
            ja: "次回実行: \(value)",
            ko: "다음 실행: \(value)",
            mt: "Eżekuzzjoni li jmiss: \(value)"
        )
    }

    private var controlColor: Color {
        switch session.controlMode {
        case "codex_native", "codex_desktop_owner": return TraceFenceDesign.success
        case "tracefence_pty": return TraceFenceDesign.success
        case "hook_question", "hook_approval": return TraceFenceDesign.success
        case "process_group", "process_tree", "single_process": return TraceFenceDesign.accent
        case "display_only": return TraceFenceDesign.secondary
        default:
            return session.controlAvailable == true ? TraceFenceDesign.accent : TraceFenceDesign.secondary
        }
    }

    private var controlIcon: String {
        switch session.controlMode {
        case "codex_native", "codex_desktop_owner": return "terminal.fill"
        case "tracefence_pty": return "bubble.left.and.text.bubble.right.fill"
        case "hook_question": return "text.bubble.fill"
        case "hook_approval": return "hand.raised.fill"
        case "process_group", "process_tree", "single_process": return "gearshape.2.fill"
        case "display_only": return "eye.fill"
        default: return "questionmark.circle"
        }
    }

    private var phaseColor: Color {
        switch session.phase {
        case "waitingApproval", "waitingInput": return TraceFenceDesign.warning
        case "interrupted", "error": return TraceFenceDesign.danger
        case "processing", "compacting": return TraceFenceDesign.success
        default: return TraceFenceDesign.accent
        }
    }
}

private struct TimelineRow: View {
    var event: AgentEventSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title.tfLocalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TraceFenceDesign.text)
                    .lineLimit(1)
                Text("\(event.agentDisplayName) · \(event.project) · \(event.status.tfLocalized)")
                    .font(.caption2)
                    .foregroundStyle(TraceFenceDesign.secondary)
                    .lineLimit(1)
                if !event.detail.isEmpty {
                    Text(event.detail.tfLocalized)
                        .font(.caption2)
                        .foregroundStyle(TraceFenceDesign.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
    }

    private var icon: String {
        switch event.type {
        case "permission", "plan": return "hand.raised.fill"
        case "question": return "questionmark.bubble.fill"
        case "tool": return "wrench.and.screwdriver.fill"
        default: return "waveform.path.ecg"
        }
    }

    private var color: Color {
        event.status == "pending" ? TraceFenceDesign.warning : TraceFenceDesign.accent
    }
}

private struct AgentAlertRow: View {
    var session: AgentSessionSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color)
                    Text(session.phaseTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.12))
                        .clipShape(Capsule())
                }

                Text(session.displayTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TraceFenceDesign.text)
                    .lineLimit(2)

                Text(session.primaryControlNote)
                    .font(.caption2)
                    .foregroundStyle(TraceFenceDesign.secondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var title: String {
        if session.canStartContinuation { return "可接管任务".tfLocalized }
        switch session.phase {
        case "waitingApproval": return "等待确认".tfLocalized
        case "waitingInput": return "等待指令".tfLocalized
        case "interrupted": return "已暂停".tfLocalized
        case "error": return "异常".tfLocalized
        default:
            if session.controlReason == "unsafe_or_unknown_process" { return "受限控制".tfLocalized }
            if session.controlReason == "snapshot_without_runtime" { return "仅可监控".tfLocalized }
            return "需要关注".tfLocalized
        }
    }

    private var icon: String {
        if session.canStartContinuation { return "arrow.triangle.2.circlepath.circle.fill" }
        switch session.phase {
        case "waitingApproval": return "checkmark.shield.fill"
        case "waitingInput": return "text.bubble.fill"
        case "interrupted": return "pause.circle.fill"
        case "error": return "exclamationmark.triangle.fill"
        default: return "bell.badge.fill"
        }
    }

    private var color: Color {
        switch session.phase {
        case "error": return TraceFenceDesign.danger
        case "interrupted": return TraceFenceDesign.warning
        default:
            return session.canStartContinuation ? TraceFenceDesign.accent : TraceFenceDesign.warning
        }
    }
}

private struct EmptyInlineState: View {
    var icon: String
    var title: String
    var detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(TraceFenceDesign.success)
            Text(title.tfLocalized)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(TraceFenceDesign.text)
            Text(detail.tfLocalized)
                .font(.caption)
                .foregroundStyle(TraceFenceDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.black.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
