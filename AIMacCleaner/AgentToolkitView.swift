import SwiftUI
import AppKit

struct AgentToolkitView: View {
    @EnvironmentObject private var localizer: Localizer
    @StateObject private var model = AgentToolkitModel()
    @State private var pendingAction: AgentProcessAction?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            specialistGrid
            actionBar
            diagnosticSummary
            if !model.aiSummary.isEmpty {
                aiSummaryCard
            }
            diagnosticGroups

            if !model.isSandboxed {
                runningAgents
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .onAppear {
            model.runDiagnostics()
        }
        .alert(
            localizer.t(
                "确认进程操作",
                en: "Confirm Process Action",
                zhHant: "確認程序操作",
                ja: "プロセス操作を確認",
                ko: "프로세스 작업 확인",
                mt: "Confirm Process Action"
            ),
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }
            ),
            presenting: pendingAction
        ) { action in
            Button(action.buttonTitle(localizer), role: action.isDestructive ? .destructive : nil) {
                model.perform(action)
                pendingAction = nil
            }
            Button(localizer.cancel, role: .cancel) {
                pendingAction = nil
            }
        } message: { action in
            Text(action.confirmation(localizer))
        }
    }

    private var specialistGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md)
        ], spacing: Theme.Spacing.md) {
            specialistCard(
                icon: "archivebox.fill",
                title: localizer.t("会话管家", en: "Session Keeper", zhHant: "會話管家", ja: "セッション管理", ko: "세션 관리자", mt: "Session Keeper"),
                detail: localizer.t("备份用户选择的 Agent 会话，不包含凭证。", en: "Back up user-selected agent sessions without credentials.", zhHant: "備份使用者選擇的 Agent 會話，不包含憑證。", ja: "選択した Agent セッションを認証情報なしでバックアップします。", ko: "사용자가 선택한 Agent 세션을 자격 증명 없이 백업합니다.", mt: "Back up user-selected agent sessions without credentials."),
                color: Theme.Colors.info
            )
            specialistCard(
                icon: "stethoscope",
                title: localizer.t("健康诊断", en: "Health Doctor", zhHant: "健康診斷", ja: "ヘルス診断", ko: "상태 진단", mt: "Health Doctor"),
                detail: localizer.t("检查授权目录、会话完整性、磁盘和运行状态。", en: "Check authorized folders, session integrity, storage, and runtime health.", zhHant: "檢查授權目錄、會話完整性、磁碟與執行狀態。", ja: "許可フォルダ、セッション整合性、容量、実行状態を確認します。", ko: "승인된 폴더, 세션 무결성, 저장 공간 및 실행 상태를 확인합니다.", mt: "Check authorized folders, session integrity, storage, and runtime health."),
                color: Theme.Colors.success
            )
            specialistCard(
                icon: "chart.xyaxis.line",
                title: localizer.t("用量分析师", en: "Usage Analyst", zhHant: "用量分析師", ja: "使用量アナリスト", ko: "사용량 분석가", mt: "Usage Analyst"),
                detail: localizer.t("结合现有 Token 与会话数据发现异常趋势。", en: "Use existing token and session data to surface unusual trends.", zhHant: "結合現有 Token 與會話資料發現異常趨勢。", ja: "既存の Token とセッションデータから異常傾向を見つけます。", ko: "기존 토큰 및 세션 데이터에서 비정상 추세를 찾습니다.", mt: "Use existing token and session data to surface unusual trends."),
                color: Theme.Colors.purple
            )
            specialistCard(
                icon: "checkmark.shield.fill",
                title: localizer.t("安全审计员", en: "Safety Auditor", zhHant: "安全稽核員", ja: "安全監査", ko: "보안 감사자", mt: "Safety Auditor"),
                detail: localizer.t("只验证配置和凭证状态，不读取或展示密钥内容。", en: "Validate configuration and credential state without reading or showing secrets.", zhHant: "只驗證設定與憑證狀態，不讀取或顯示金鑰內容。", ja: "設定と認証状態のみ確認し、秘密情報は読み取り・表示しません。", ko: "설정 및 자격 증명 상태만 확인하며 비밀 값은 읽거나 표시하지 않습니다.", mt: "Validate configuration and credential state without reading or showing secrets."),
                color: Theme.Colors.warning
            )
        }
    }

    private func specialistCard(icon: String, title: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text(detail)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Colors.separator, lineWidth: 1)
        }
    }

    private var actionBar: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Button {
                model.chooseAndBackUpSessions(localizer: localizer)
            } label: {
                Label(
                    localizer.t("手动备份会话", en: "Back Up Sessions", zhHant: "手動備份會話", ja: "セッションをバックアップ", ko: "세션 백업", mt: "Back Up Sessions"),
                    systemImage: "externaldrive.badge.plus"
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.Colors.accent)
            .disabled(model.isWorking)

            Button {
                model.runDiagnostics()
            } label: {
                Label(
                    localizer.t("重新诊断", en: "Run Diagnostics", zhHant: "重新診斷", ja: "再診断", ko: "다시 진단", mt: "Run Diagnostics"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(.bordered)
            .disabled(model.isWorking)

            Button {
                model.generateAISummary(localizer: localizer)
            } label: {
                Label(
                    localizer.t("AI 分析", en: "AI Analysis", zhHant: "AI 分析", ja: "AI 分析", ko: "AI 분석", mt: "AI Analysis"),
                    systemImage: "apple.intelligence"
                )
            }
            .buttonStyle(.bordered)
            .disabled(model.isWorking || model.isAnalyzing || model.items.isEmpty)

            if model.isWorking || model.isAnalyzing {
                ProgressView()
                    .controlSize(.small)
                Text(model.isAnalyzing
                    ? localizer.t("正在生成本地诊断摘要...", en: "Generating an on-device diagnostic summary...", zhHant: "正在產生本機診斷摘要...", ja: "オンデバイス診断要約を生成中...", ko: "온디바이스 진단 요약 생성 중...", mt: "Generating an on-device diagnostic summary...")
                    : model.progressText)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if !model.lastMessage.isEmpty {
                Image(systemName: model.lastOperationSucceeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(model.lastOperationSucceeded ? Theme.Colors.success : Theme.Colors.warning)
                Text(model.lastMessage)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            Label(
                model.isSandboxed
                    ? localizer.t("App Store 安全模式", en: "App Store Safe Mode", zhHant: "App Store 安全模式", ja: "App Store セーフモード", ko: "App Store 안전 모드", mt: "App Store Safe Mode")
                    : localizer.t("官网增强模式", en: "Direct Advanced Mode", zhHant: "官網增強模式", ja: "直販拡張モード", ko: "직접 배포 고급 모드", mt: "Direct Advanced Mode"),
                systemImage: model.isSandboxed ? "lock.shield.fill" : "bolt.shield.fill"
            )
            .font(Theme.Font.captionMedium)
            .foregroundStyle(model.isSandboxed ? Theme.Colors.success : Theme.Colors.warning)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.elevatedCardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var aiSummaryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Label(
                    localizer.t("Apple Intelligence 诊断摘要", en: "Apple Intelligence Diagnostic Summary", zhHant: "Apple Intelligence 診斷摘要", ja: "Apple Intelligence 診断要約", ko: "Apple Intelligence 진단 요약", mt: "Apple Intelligence Diagnostic Summary"),
                    systemImage: "apple.intelligence"
                )
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(localizer.t("仅处理状态摘要", en: "Status summary only", zhHant: "僅處理狀態摘要", ja: "状態要約のみ処理", ko: "상태 요약만 처리", mt: "Status summary only"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Text(model.aiSummary)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Spacing.lg)
        .background(Theme.Colors.accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Colors.accent.opacity(0.22), lineWidth: 1)
        }
    }

    private var diagnosticSummary: some View {
        HStack(spacing: Theme.Spacing.md) {
            diagnosticMetric(
                value: "\(model.healthyCount)",
                title: localizer.t("正常", en: "Healthy", zhHant: "正常", ja: "正常", ko: "정상", mt: "Healthy"),
                icon: "checkmark.circle.fill",
                color: Theme.Colors.success
            )
            diagnosticMetric(
                value: "\(model.warningCount)",
                title: localizer.t("需关注", en: "Needs Attention", zhHant: "需關注", ja: "要確認", ko: "확인 필요", mt: "Needs Attention"),
                icon: "exclamationmark.triangle.fill",
                color: Theme.Colors.warning
            )
            diagnosticMetric(
                value: "\(model.sessionFileCount)",
                title: localizer.t("会话文件", en: "Session Files", zhHant: "會話檔案", ja: "セッションファイル", ko: "세션 파일", mt: "Session Files"),
                icon: "doc.text.fill",
                color: Theme.Colors.info
            )
            diagnosticMetric(
                value: "\(model.runningAgents.count)",
                title: localizer.t("运行实例", en: "Running Agents", zhHant: "執行實例", ja: "実行中 Agent", ko: "실행 중 Agent", mt: "Running Agents"),
                icon: "waveform.path.ecg",
                color: Theme.Colors.accent
            )
        }
    }

    private func diagnosticMetric(value: String, title: String, icon: String, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private var diagnosticGroups: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(localizer.t("诊断结果", en: "Diagnostic Results", zhHant: "診斷結果", ja: "診断結果", ko: "진단 결과", mt: "Diagnostic Results"))
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ForEach(model.items) { item in
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: item.status.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(item.status.color)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(diagnosticTitle(item))
                            .font(Theme.Font.bodyMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(diagnosticDetail(item))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    Text(diagnosticGroup(item))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
        }
    }

    private func diagnosticGroup(_ item: AgentDiagnosticItem) -> String {
        switch item.kind {
        case .access:
            localizer.t("授权", en: "Access", zhHant: "授權", ja: "アクセス", ko: "접근", mt: "Access")
        case .sessions, .consistency:
            localizer.t("会话", en: "Sessions", zhHant: "會話", ja: "セッション", ko: "세션", mt: "Sessions")
        case .storage:
            localizer.t("存储", en: "Storage", zhHant: "儲存空間", ja: "ストレージ", ko: "저장 공간", mt: "Storage")
        case .privacy:
            localizer.t("隐私", en: "Privacy", zhHant: "隱私", ja: "プライバシー", ko: "개인정보", mt: "Privacy")
        case .mode:
            localizer.t("模式", en: "Mode", zhHant: "模式", ja: "モード", ko: "모드", mt: "Mode")
        }
    }

    private func diagnosticTitle(_ item: AgentDiagnosticItem) -> String {
        switch item.kind {
        case .access(let count, _):
            return count == 0
                ? localizer.t("尚未授权 Agent 数据目录", en: "No agent data folders authorized", zhHant: "尚未授權 Agent 資料目錄", ja: "Agent データフォルダが許可されていません", ko: "승인된 Agent 데이터 폴더가 없습니다", mt: "No agent data folders authorized")
                : localizer.t("已授权 \(count) 个 Agent 数据目录", en: "\(count) agent data folders authorized", zhHant: "已授權 \(count) 個 Agent 資料目錄", ja: "\(count) 個の Agent データフォルダを許可済み", ko: "\(count)개의 Agent 데이터 폴더가 승인됨", mt: "\(count) agent data folders authorized")
        case .sessions(let count):
            return count > 0
                ? localizer.t("会话记录可正常读取", en: "Session records are readable", zhHant: "會話記錄可正常讀取", ja: "セッション記録を読み取れます", ko: "세션 기록을 정상적으로 읽을 수 있음", mt: "Session records are readable")
                : localizer.t("未发现可读取的会话记录", en: "No readable session records found", zhHant: "未發現可讀取的會話記錄", ja: "読み取り可能なセッション記録がありません", ko: "읽을 수 있는 세션 기록이 없습니다", mt: "No readable session records found")
        case .consistency(let unreadable):
            return unreadable == 0
                ? localizer.t("会话数据源一致性正常", en: "Session sources are consistent", zhHant: "會話資料來源一致性正常", ja: "セッションデータソースは正常です", ko: "세션 데이터 소스가 정상임", mt: "Session sources are consistent")
                : localizer.t("\(unreadable) 个数据源无法遍历", en: "\(unreadable) sources could not be enumerated", zhHant: "\(unreadable) 個資料來源無法遍歷", ja: "\(unreadable) 個のデータソースを確認できません", ko: "\(unreadable)개의 데이터 소스를 탐색할 수 없음", mt: "\(unreadable) sources could not be enumerated")
        case .storage(let freeGB):
            return freeGB >= 5
                ? localizer.t("文件系统容量正常", en: "File system capacity is healthy", zhHant: "檔案系統容量正常", ja: "ファイルシステム容量は正常です", ko: "파일 시스템 용량이 정상임", mt: "File system capacity is healthy")
                : localizer.t("可用存储空间偏低", en: "Available storage is low", zhHant: "可用儲存空間偏低", ja: "空き容量が少なくなっています", ko: "사용 가능한 저장 공간이 부족함", mt: "Available storage is low")
        case .privacy:
            return localizer.t("凭证安全诊断", en: "Credential-safe diagnostics", zhHant: "憑證安全診斷", ja: "認証情報を保護する診断", ko: "자격 증명 보호 진단", mt: "Credential-safe diagnostics")
        case .mode(let sandboxed):
            return sandboxed
                ? localizer.t("App Store 沙盒已启用", en: "App Store sandbox is active", zhHant: "App Store 沙盒已啟用", ja: "App Store サンドボックスが有効です", ko: "App Store 샌드박스가 활성화됨", mt: "App Store sandbox is active")
                : localizer.t("官网版增强控制可用", en: "Direct advanced controls are available", zhHant: "官網版增強控制可用", ja: "直販版の拡張操作を利用できます", ko: "직접 배포 고급 제어를 사용할 수 있음", mt: "Direct advanced controls are available")
        }
    }

    private func diagnosticDetail(_ item: AgentDiagnosticItem) -> String {
        switch item.kind {
        case .access(let count, let paths):
            return count == 0
                ? localizer.t("请在备份时选择会话目录，或从 TraceFence 重新授权数据源。", en: "Choose session folders during backup or re-authorize data sources from TraceFence.", zhHant: "請在備份時選擇會話目錄，或從 TraceFence 重新授權資料來源。", ja: "バックアップ時にセッションフォルダを選ぶか、TraceFence から再許可してください。", ko: "백업 시 세션 폴더를 선택하거나 TraceFence에서 데이터 소스를 다시 승인하세요.", mt: "Choose session folders during backup or re-authorize data sources from TraceFence.")
                : paths.joined(separator: "\n")
        case .sessions(let count):
            return count > 0
                ? localizer.t("已检查 \(count) 个会话文件。", en: "\(count) session files checked.", zhHant: "已檢查 \(count) 個會話檔案。", ja: "\(count) 個のセッションファイルを確認しました。", ko: "\(count)개의 세션 파일을 확인했습니다.", mt: "\(count) session files checked.")
                : localizer.t("请授权 Agent 使用的 sessions 或 conversations 目录。", en: "Authorize the sessions or conversations folder used by your agent.", zhHant: "請授權 Agent 使用的 sessions 或 conversations 目錄。", ja: "Agent が使用する sessions または conversations フォルダを許可してください。", ko: "Agent가 사용하는 sessions 또는 conversations 폴더를 승인하세요.", mt: "Authorize the sessions or conversations folder used by your agent.")
        case .consistency(let unreadable):
            return unreadable == 0
                ? localizer.t("未检测到无法读取的已授权数据源。", en: "No unreadable authorized source was detected.", zhHant: "未偵測到無法讀取的已授權資料來源。", ja: "読み取れない許可済みデータソースはありません。", ko: "읽을 수 없는 승인된 데이터 소스가 없습니다.", mt: "No unreadable authorized source was detected.")
                : localizer.t("目录可能已移动，或访问授权已经失效。", en: "The source may have moved or its permission may have expired.", zhHant: "目錄可能已移動，或存取授權已經失效。", ja: "フォルダが移動したか、アクセス許可が期限切れの可能性があります。", ko: "폴더가 이동했거나 접근 권한이 만료되었을 수 있습니다.", mt: "The source may have moved or its permission may have expired.")
        case .storage(let freeGB):
            return localizer.t(
                String(format: "可用于备份和 Agent 会话的空间为 %.1f GB。", freeGB),
                en: String(format: "%.1f GB available for backups and agent sessions.", freeGB),
                zhHant: String(format: "可用於備份與 Agent 會話的空間為 %.1f GB。", freeGB),
                ja: String(format: "バックアップと Agent セッションに %.1f GB 使用できます。", freeGB),
                ko: String(format: "백업 및 Agent 세션에 %.1f GB를 사용할 수 있습니다.", freeGB),
                mt: String(format: "%.1f GB available for backups and agent sessions.", freeGB)
            )
        case .privacy:
            return localizer.t("TraceFence 只检查凭证文件是否存在，不读取、复制或展示任何密钥内容。", en: "TraceFence checks whether credential files exist, but does not read, copy, or display secret values.", zhHant: "TraceFence 只檢查憑證檔案是否存在，不讀取、複製或顯示任何金鑰內容。", ja: "TraceFence は認証ファイルの存在のみ確認し、秘密値を読み取り・コピー・表示しません。", ko: "TraceFence는 자격 증명 파일의 존재 여부만 확인하며 비밀 값을 읽거나 복사하거나 표시하지 않습니다.", mt: "TraceFence checks whether credential files exist, but does not read, copy, or display secret values.")
        case .mode(let sandboxed):
            return sandboxed
                ? localizer.t("只检查用户明确授权的文件；进程终止和配置修复功能已禁用。", en: "Only user-authorized files are inspected. Process termination and configuration repair are disabled.", zhHant: "只檢查使用者明確授權的檔案；程序終止與設定修復功能已停用。", ja: "ユーザーが許可したファイルのみ確認し、プロセス終了と設定修復は無効です。", ko: "사용자가 명시적으로 승인한 파일만 검사하며 프로세스 종료 및 설정 복구는 비활성화됩니다.", mt: "Only user-authorized files are inspected. Process termination and configuration repair are disabled.")
                : localizer.t("本机进程控制已经开放，并且每次操作都需要明确确认。", en: "Local process controls are available and always require explicit confirmation.", zhHant: "本機程序控制已經開放，而且每次操作都需要明確確認。", ja: "ローカルプロセス操作を利用でき、毎回明示的な確認が必要です。", ko: "로컬 프로세스 제어를 사용할 수 있으며 매번 명시적인 확인이 필요합니다.", mt: "Local process controls are available and always require explicit confirmation.")
        }
    }

    private var runningAgents: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text(localizer.t("进程控制", en: "Process Control", zhHant: "程序控制", ja: "プロセス制御", ko: "프로세스 제어", mt: "Process Control"))
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Text(localizer.t("仅官网版 · 每次操作均需确认", en: "Direct build only · every action requires confirmation", zhHant: "僅官網版 · 每次操作均需確認", ja: "直販版のみ・操作ごとに確認", ko: "직접 배포 버전 전용 · 매 작업 확인", mt: "Direct build only · every action requires confirmation"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            if model.runningAgents.isEmpty {
                Text(localizer.t("当前未发现运行中的受支持 Agent。", en: "No supported running agents were found.", zhHant: "目前未發現執行中的支援 Agent。", ja: "対応する実行中 Agent は見つかりませんでした。", ko: "현재 실행 중인 지원 Agent가 없습니다.", mt: "No supported running agents were found."))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.md)
            } else {
                ForEach(model.runningAgents) { process in
                    HStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "terminal.fill")
                            .foregroundStyle(Theme.Colors.accent)
                            .frame(width: 28, height: 28)
                            .background(Theme.Colors.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(process.name)
                                .font(Theme.Font.bodyMedium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("PID \(process.pid) · \(process.command)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(localizer.t("关闭", en: "Quit", zhHant: "關閉", ja: "終了", ko: "종료", mt: "Quit")) {
                            pendingAction = .terminate(process)
                        }
                        .buttonStyle(.bordered)

                        Button(localizer.t("强制关闭", en: "Force Quit", zhHant: "強制關閉", ja: "強制終了", ko: "강제 종료", mt: "Force Quit")) {
                            pendingAction = .forceTerminate(process)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.Colors.danger)

                        if process.bundleURL != nil {
                            Button(localizer.t("重启", en: "Restart", zhHant: "重新啟動", ja: "再起動", ko: "재시작", mt: "Restart")) {
                                pendingAction = .restart(process)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.Colors.accent)
                        }
                    }
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }
        }
    }
}

private struct AgentDiagnosticItem: Identifiable {
    enum Kind {
        case access(count: Int, paths: [String])
        case sessions(count: Int)
        case consistency(unreadable: Int)
        case storage(freeGB: Double)
        case privacy
        case mode(sandboxed: Bool)
    }

    enum Status {
        case healthy
        case warning
        case info

        var icon: String {
            switch self {
            case .healthy: "checkmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .healthy: Theme.Colors.success
            case .warning: Theme.Colors.warning
            case .info: Theme.Colors.info
            }
        }
    }

    let id = UUID()
    let kind: Kind
    let status: Status
}

private struct AgentBackupResult {
    let success: Bool
    let copied: Int
    let folderName: String
    let errorDescription: String?
}

private struct AgentRunningProcess: Identifiable {
    let id: Int32
    let pid: Int32
    let name: String
    let command: String
    let bundleIdentifier: String?
    let bundleURL: URL?
}

private enum AgentProcessAction {
    case terminate(AgentRunningProcess)
    case forceTerminate(AgentRunningProcess)
    case restart(AgentRunningProcess)

    var process: AgentRunningProcess {
        switch self {
        case .terminate(let process), .forceTerminate(let process), .restart(let process):
            process
        }
    }

    var isDestructive: Bool {
        if case .forceTerminate = self { return true }
        return false
    }

    func buttonTitle(_ localizer: Localizer) -> String {
        switch self {
        case .terminate:
            localizer.t("确认关闭", en: "Confirm Quit", zhHant: "確認關閉", ja: "終了を確認", ko: "종료 확인", mt: "Confirm Quit")
        case .forceTerminate:
            localizer.t("强制关闭", en: "Force Quit", zhHant: "強制關閉", ja: "強制終了", ko: "강제 종료", mt: "Force Quit")
        case .restart:
            localizer.t("确认重启", en: "Confirm Restart", zhHant: "確認重新啟動", ja: "再起動を確認", ko: "재시작 확인", mt: "Confirm Restart")
        }
    }

    func confirmation(_ localizer: Localizer) -> String {
        switch self {
        case .terminate:
            localizer.t("将向 \(process.name) 发送正常退出请求。未保存的 Agent 工作可能受到影响。", en: "TraceFence will ask \(process.name) to quit. Unsaved agent work may be affected.", zhHant: "將向 \(process.name) 傳送正常退出請求。未儲存的 Agent 工作可能受到影響。", ja: "\(process.name) に通常終了を要求します。未保存の作業に影響する場合があります。", ko: "\(process.name)에 정상 종료를 요청합니다. 저장되지 않은 작업이 영향을 받을 수 있습니다.", mt: "TraceFence will ask \(process.name) to quit. Unsaved agent work may be affected.")
        case .forceTerminate:
            localizer.t("将立即强制关闭 \(process.name)。未保存内容可能丢失。", en: "\(process.name) will be force quit immediately. Unsaved content may be lost.", zhHant: "將立即強制關閉 \(process.name)。未儲存內容可能遺失。", ja: "\(process.name) を直ちに強制終了します。未保存の内容は失われる可能性があります。", ko: "\(process.name)을 즉시 강제 종료합니다. 저장되지 않은 내용이 손실될 수 있습니다.", mt: "\(process.name) will be force quit immediately. Unsaved content may be lost.")
        case .restart:
            localizer.t("将关闭并重新打开 \(process.name)。请先保存正在进行的工作。", en: "\(process.name) will quit and reopen. Save ongoing work first.", zhHant: "將關閉並重新開啟 \(process.name)。請先儲存進行中的工作。", ja: "\(process.name) を終了して再度開きます。進行中の作業を保存してください。", ko: "\(process.name)을 종료한 후 다시 엽니다. 진행 중인 작업을 먼저 저장하세요.", mt: "\(process.name) will quit and reopen. Save ongoing work first.")
        }
    }
}

@MainActor
private final class AgentToolkitModel: ObservableObject {
    @Published var items: [AgentDiagnosticItem] = []
    @Published var runningAgents: [AgentRunningProcess] = []
    @Published var sessionFileCount = 0
    @Published var isWorking = false
    @Published var progressText = ""
    @Published var lastMessage = ""
    @Published var lastOperationSucceeded = true
    @Published var aiSummary = ""
    @Published var isAnalyzing = false

    let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

    var healthyCount: Int { items.filter { $0.status == .healthy }.count }
    var warningCount: Int { items.filter { $0.status == .warning }.count }

    func runDiagnostics() {
        guard !isWorking else { return }
        isWorking = true
        progressText = "..."
        lastMessage = ""

        let roots = authorizedRoots()
        let sandboxed = isSandboxed
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.buildDiagnostics(roots: roots, sandboxed: sandboxed)
            let processes = sandboxed ? [] : Self.discoverRunningAgents()
            DispatchQueue.main.async {
                self.items = result.items
                self.sessionFileCount = result.sessionCount
                self.runningAgents = processes
                self.progressText = ""
                self.lastOperationSucceeded = true
                self.lastMessage = result.message
                self.isWorking = false
            }
        }
    }

    func chooseAndBackUpSessions(localizer: Localizer) {
        let sourcePanel = NSOpenPanel()
        sourcePanel.title = localizer.t("选择 Agent 会话目录", en: "Choose Agent Session Folders", zhHant: "選擇 Agent 會話目錄", ja: "Agent セッションフォルダを選択", ko: "Agent 세션 폴더 선택", mt: "Choose Agent Session Folders")
        sourcePanel.message = localizer.t("只会复制会话记录；auth、token、密钥和配置文件会被排除。", en: "Only session records are copied. Auth, token, key, and configuration files are excluded.", zhHant: "只會複製會話記錄；auth、token、金鑰與設定檔會被排除。", ja: "セッション記録のみコピーし、認証・トークン・鍵・設定ファイルは除外します。", ko: "세션 기록만 복사하며 인증, 토큰, 키 및 설정 파일은 제외합니다.", mt: "Only session records are copied. Auth, token, key, and configuration files are excluded.")
        sourcePanel.canChooseFiles = false
        sourcePanel.canChooseDirectories = true
        sourcePanel.allowsMultipleSelection = true
        sourcePanel.canCreateDirectories = false

        guard sourcePanel.runModal() == .OK, !sourcePanel.urls.isEmpty else { return }

        let destinationPanel = NSOpenPanel()
        destinationPanel.title = localizer.t("选择备份保存位置", en: "Choose Backup Destination", zhHant: "選擇備份儲存位置", ja: "バックアップ先を選択", ko: "백업 저장 위치 선택", mt: "Choose Backup Destination")
        destinationPanel.canChooseFiles = false
        destinationPanel.canChooseDirectories = true
        destinationPanel.allowsMultipleSelection = false
        destinationPanel.canCreateDirectories = true
        destinationPanel.prompt = localizer.t("备份到这里", en: "Back Up Here", zhHant: "備份到這裡", ja: "ここにバックアップ", ko: "여기에 백업", mt: "Back Up Here")

        guard destinationPanel.runModal() == .OK, let destination = destinationPanel.url else { return }

        isWorking = true
        progressText = localizer.t("正在备份会话...", en: "Backing up sessions...", zhHant: "正在備份會話...", ja: "セッションをバックアップ中...", ko: "세션 백업 중...", mt: "Backing up sessions...")
        let sources = sourcePanel.urls
        let language = localizer.language
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Self.backUpSessionFiles(sources: sources, destination: destination)
            DispatchQueue.main.async {
                self.isWorking = false
                self.progressText = ""
                self.lastOperationSucceeded = result.success
                if result.success {
                    self.lastMessage = Self.localized(
                        language: language,
                        "已将 \(result.copied) 个会话文件备份到 \(result.folderName)。",
                        en: "\(result.copied) session files backed up to \(result.folderName).",
                        zhHant: "已將 \(result.copied) 個會話檔案備份到 \(result.folderName)。",
                        ja: "\(result.copied) 個のセッションファイルを \(result.folderName) にバックアップしました。",
                        ko: "\(result.copied)개의 세션 파일을 \(result.folderName)에 백업했습니다.",
                        mt: "\(result.copied) session files backed up to \(result.folderName)."
                    )
                } else {
                    self.lastMessage = Self.localized(
                        language: language,
                        "备份失败：\(result.errorDescription ?? "-")",
                        en: "Backup failed: \(result.errorDescription ?? "-")",
                        zhHant: "備份失敗：\(result.errorDescription ?? "-")",
                        ja: "バックアップに失敗しました：\(result.errorDescription ?? "-")",
                        ko: "백업 실패: \(result.errorDescription ?? "-")",
                        mt: "Backup failed: \(result.errorDescription ?? "-")"
                    )
                }
                self.runDiagnostics()
            }
        }
    }

    func generateAISummary(localizer: Localizer) {
        guard !items.isEmpty, !isAnalyzing else { return }
        isAnalyzing = true
        aiSummary = ""
        let languageName = localizer.language.displayName
        let warningCount = self.warningCount
        let healthyCount = self.healthyCount
        let sessionCount = sessionFileCount
        let runningCount = runningAgents.count
        let mode = isSandboxed ? "App Store sandbox" : "direct advanced"

        Task {
            do {
                let result = try await AppleIntelligenceService.generate(
                    instructions: "You are TraceFence's on-device agent health specialist. Give a concise, calm diagnostic summary. Never invent missing facts. Do not request or expose credentials. Respond in \(languageName).",
                    prompt: "Health checks: \(healthyCount) healthy, \(warningCount) warnings. Readable session files: \(sessionCount). Running supported agents: \(runningCount). Product mode: \(mode). Explain the current state and provide at most three prioritized next steps. No session content or secret values are included.",
                    maximumResponseTokens: 500
                )
                aiSummary = result.content
            } catch {
                aiSummary = localizer.t(
                    "当前无法使用 Apple Intelligence。结构化诊断结果仍然有效，你可以根据黄色项目逐项处理。",
                    en: "Apple Intelligence is unavailable right now. The structured diagnostic results are still valid; review the warning items one by one.",
                    zhHant: "目前無法使用 Apple Intelligence。結構化診斷結果仍然有效，你可以依照黃色項目逐項處理。",
                    ja: "現在 Apple Intelligence を利用できません。構造化診断結果は有効です。警告項目を順番に確認してください。",
                    ko: "현재 Apple Intelligence를 사용할 수 없습니다. 구조화된 진단 결과는 여전히 유효하므로 경고 항목을 하나씩 확인하세요.",
                    mt: "Apple Intelligence is unavailable right now. The structured diagnostic results are still valid; review the warning items one by one."
                )
            }
            isAnalyzing = false
        }
    }

    func perform(_ action: AgentProcessAction) {
        guard !isSandboxed else { return }
        let process = action.process
        let runningApplication = NSRunningApplication(processIdentifier: process.pid)

        switch action {
        case .terminate:
            if runningApplication?.terminate() != true {
                Darwin.kill(process.pid, SIGTERM)
            }
        case .forceTerminate:
            if runningApplication?.forceTerminate() != true {
                Darwin.kill(process.pid, SIGKILL)
            }
        case .restart:
            guard let bundleURL = process.bundleURL else { return }
            if runningApplication?.terminate() != true {
                Darwin.kill(process.pid, SIGTERM)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            self.runDiagnostics()
        }
    }

    private func authorizedRoots() -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        let bookmarkFiles = [
            SandboxPaths.shared.bookmarksPath,
            SandboxPaths.shared.scanBookmarksPath,
            SandboxPaths.shared.tokenScopeBookmarksPath
        ]

        for file in bookmarkFiles {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: file)),
                  let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else { continue }
            for (_, bookmark) in bookmarks {
                var stale = false
                guard let url = try? URL(
                    resolvingBookmarkData: bookmark,
                    options: .withSecurityScope,
                    relativeTo: nil,
                    bookmarkDataIsStale: &stale
                ), seen.insert(url.standardizedFileURL.path).inserted else { continue }
                urls.append(url)
            }
        }

        if !isSandboxed {
            let home = SandboxPaths.realHomeDirectory
            let candidates = [
                "\(home)/.codex/sessions",
                "\(home)/.codex/archived_sessions",
                "\(home)/.claude/projects",
                "\(home)/.cursor",
                "\(home)/.gemini",
                "\(home)/.config/opencode"
            ]
            for path in candidates where FileManager.default.fileExists(atPath: path) {
                if seen.insert(path).inserted {
                    urls.append(URL(fileURLWithPath: path, isDirectory: true))
                }
            }
        }
        return urls
    }

    nonisolated private static func buildDiagnostics(roots: [URL], sandboxed: Bool) -> (items: [AgentDiagnosticItem], sessionCount: Int, message: String) {
        var result: [AgentDiagnosticItem] = []
        let accessibleRoots = roots.filter { $0.startAccessingSecurityScopedResource() || FileManager.default.isReadableFile(atPath: $0.path) }
        defer {
            accessibleRoots.forEach { $0.stopAccessingSecurityScopedResource() }
        }
        let inspectionRoots = scopedInspectionRoots(from: accessibleRoots, sandboxed: sandboxed)

        result.append(AgentDiagnosticItem(
            kind: .access(count: accessibleRoots.count, paths: Array(accessibleRoots.map(\.path).prefix(3))),
            status: accessibleRoots.isEmpty ? .warning : .healthy
        ))

        var sessionCount = 0
        var unreadableCount = 0
        var inspectedFileCount = 0
        let inspectionLimit = 8_000
        let deadline = Date().addingTimeInterval(5)
        let skippedDirectoryNames: Set<String> = [
            ".git", "node_modules", "cache", "caches", "tmp", "temp",
            "extensions", "plugins", "vendor", "deriveddata", "browser"
        ]
        for root in inspectionRoots {
            if Date() >= deadline { break }
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey],
                options: [.skipsPackageDescendants]
            ) else {
                unreadableCount += 1
                continue
            }
            for case let url as URL in enumerator {
                if Date() >= deadline { break }
                if inspectedFileCount >= inspectionLimit { break }
                let relativePath = url.path.dropFirst(min(root.path.count + 1, url.path.count))
                let depth = relativePath.split(separator: "/").count
                if depth > 8 {
                    enumerator.skipDescendants()
                    continue
                }

                let resourceValues = try? url.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    if skippedDirectoryNames.contains(url.lastPathComponent.lowercased()) {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                inspectedFileCount += 1
                if isSessionRecord(url) {
                    sessionCount += 1
                }
            }
            if inspectedFileCount >= inspectionLimit { break }
        }
        let timedOut = Date() >= deadline || inspectedFileCount >= inspectionLimit

        result.append(AgentDiagnosticItem(
            kind: .sessions(count: sessionCount),
            status: sessionCount > 0 ? .healthy : .warning
        ))

        result.append(AgentDiagnosticItem(
            kind: .consistency(unreadable: unreadableCount),
            status: unreadableCount == 0 ? .healthy : .warning
        ))

        let homeURL = URL(fileURLWithPath: SandboxPaths.realHomeDirectory)
        let capacity = try? homeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        let freeGB = Double(capacity ?? 0) / 1_073_741_824
        result.append(AgentDiagnosticItem(
            kind: .storage(freeGB: freeGB),
            status: freeGB >= 5 ? .healthy : .warning
        ))

        result.append(AgentDiagnosticItem(
            kind: .privacy,
            status: .healthy
        ))

        result.append(AgentDiagnosticItem(
            kind: .mode(sandboxed: sandboxed),
            status: .info
        ))

        let message: String
        if timedOut {
            message = "已先完成 Agent 相关目录的快速诊断，剩余深层文件会在下次授权更具体目录后继续检查。"
        } else if sessionCount > 0 {
            message = "诊断完成，已发现 \(sessionCount) 个会话文件。"
        } else if accessibleRoots.isEmpty {
            message = "诊断完成：还没有授权 Agent 数据目录。"
        } else {
            message = "诊断完成：已授权目录可访问，但未发现会话文件。"
        }
        return (result, sessionCount, message)
    }

    nonisolated private static func scopedInspectionRoots(from roots: [URL], sandboxed: Bool) -> [URL] {
        let fm = FileManager.default
        var scoped: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL) {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted,
                  fm.fileExists(atPath: standardized.path) else { return }
            scoped.append(standardized)
        }

        let agentRelativePaths = [
            ".codex/sessions",
            ".codex/archived_sessions",
            ".claude/projects",
            ".cursor",
            ".gemini",
            ".config/opencode",
            "Library/Application Support/Claude",
            "Library/Application Support/Cursor"
        ]

        for root in roots {
            let path = root.standardizedFileURL.path
            if isLikelyAgentContainer(path) {
                add(root)
            }

            for relativePath in agentRelativePaths {
                add(root.appendingPathComponent(relativePath, isDirectory: true))
            }
        }

        if scoped.isEmpty, !sandboxed {
            for root in roots {
                add(root)
            }
        }

        return scoped
    }

    nonisolated private static func isLikelyAgentContainer(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.contains("/.codex")
            || lower.contains("/.claude")
            || lower.contains("/.cursor")
            || lower.contains("/.gemini")
            || lower.contains("/opencode")
            || lower.contains("/sessions")
            || lower.contains("/conversations")
            || lower.contains("/transcripts")
    }

    nonisolated private static func backUpSessionFiles(sources: [URL], destination: URL) -> AgentBackupResult {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let backupRoot = destination.appendingPathComponent("TraceFence-Sessions-\(formatter.string(from: Date()))", isDirectory: true)
        let destinationAccess = destination.startAccessingSecurityScopedResource()
        defer {
            if destinationAccess { destination.stopAccessingSecurityScopedResource() }
        }

        do {
            try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
            var copied = 0
            var skipped = 0
            var manifestSources: [String] = []

            for source in sources {
                let sourceAccess = source.startAccessingSecurityScopedResource()
                defer {
                    if sourceAccess { source.stopAccessingSecurityScopedResource() }
                }
                manifestSources.append(source.path)
                let sourceDestination = backupRoot
                    .appendingPathComponent(safeFileName(source.lastPathComponent.isEmpty ? "sessions" : source.lastPathComponent), isDirectory: true)
                try FileManager.default.createDirectory(at: sourceDestination, withIntermediateDirectories: true)

                guard let enumerator = FileManager.default.enumerator(
                    at: source,
                    includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsPackageDescendants]
                ) else {
                    skipped += 1
                    continue
                }

                for case let fileURL as URL in enumerator {
                    guard isSessionRecord(fileURL), !isSensitive(fileURL) else {
                        skipped += 1
                        continue
                    }
                    let relative = fileURL.path.replacingOccurrences(of: source.path + "/", with: "")
                    let target = sourceDestination.appendingPathComponent(relative)
                    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    if FileManager.default.fileExists(atPath: target.path) {
                        try FileManager.default.removeItem(at: target)
                    }
                    try FileManager.default.copyItem(at: fileURL, to: target)
                    copied += 1
                }
            }

            let manifest: [String: Any] = [
                "product": "TraceFence",
                "created_at": ISO8601DateFormatter().string(from: Date()),
                "sources": manifestSources,
                "session_files": copied,
                "excluded_entries": skipped,
                "credentials_included": false
            ]
            let manifestData = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            try manifestData.write(to: backupRoot.appendingPathComponent("manifest.json"), options: .atomic)
            return AgentBackupResult(success: true, copied: copied, folderName: backupRoot.lastPathComponent, errorDescription: nil)
        } catch {
            try? FileManager.default.removeItem(at: backupRoot)
            return AgentBackupResult(success: false, copied: 0, folderName: backupRoot.lastPathComponent, errorDescription: error.localizedDescription)
        }
    }

    nonisolated private static func discoverRunningAgents() -> [AgentRunningProcess] {
        let keywords = ["codex", "claude", "cursor", "windsurf", "gemini", "opencode", "trae", "kiro"]
        var processes: [Int32: AgentRunningProcess] = [:]

        for application in NSWorkspace.shared.runningApplications {
            guard application.activationPolicy == .regular else { continue }
            let name = application.localizedName ?? ""
            let bundleIdentifier = application.bundleIdentifier ?? ""
            let haystack = "\(name) \(bundleIdentifier)".lowercased()
            guard keywords.contains(where: haystack.contains) else { continue }
            processes[application.processIdentifier] = AgentRunningProcess(
                id: application.processIdentifier,
                pid: application.processIdentifier,
                name: name.isEmpty ? bundleIdentifier : name,
                command: bundleIdentifier,
                bundleIdentifier: application.bundleIdentifier,
                bundleURL: application.bundleURL
            )
        }

        return processes.values.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    nonisolated private static func isSessionRecord(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let ext = url.pathExtension.lowercased()
        let supportedExtensions = Set(["jsonl", "json", "sqlite", "sqlite3", "db", "txt", "md"])
        guard supportedExtensions.contains(ext) else { return false }
        if path.contains("/.codex/sessions/")
            || path.contains("/.codex/archived_sessions/")
            || path.contains("/.claude/projects/")
            || path.contains("/.cursor/")
            || path.contains("/.gemini/")
            || path.contains("/.config/opencode/") {
            return true
        }
        return path.contains("/session")
            || path.contains("/conversation")
            || path.contains("/transcript")
            || path.contains("/trajectory")
            || path.contains("/chat")
            || url.lastPathComponent.lowercased() == "entries.json"
    }

    nonisolated private static func isSensitive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        let sensitiveTerms = ["auth", "credential", "secret", "token", "api_key", "apikey", "keychain", "config.toml", ".env"]
        return sensitiveTerms.contains(where: name.contains)
    }

    nonisolated private static func safeFileName(_ value: String) -> String {
        value.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
    }

    nonisolated private static func localized(
        language: AppLanguage,
        _ zh: String,
        en: String,
        zhHant: String,
        ja: String,
        ko: String,
        mt: String
    ) -> String {
        switch language {
        case .simplifiedChinese: zh
        case .traditionalChinese: zhHant
        case .japanese: ja
        case .korean: ko
        case .maltese: mt
        case .english: en
        }
    }
}
