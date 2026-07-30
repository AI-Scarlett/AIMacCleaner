import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Full dashboard

enum AgentUsageInsightsMode: Equatable {
    case tokenAnalytics
    case projectMonitor
}

@MainActor
struct AgentUsageInsightsView: View {
    @EnvironmentObject private var localizer: Localizer
    @ObservedObject private var service: AgentUsageInsightsService
    let mode: AgentUsageInsightsMode

    @State private var projectPeriod: AgentUsageProjectPeriod = .last7Days
    @State private var fixedTimeZoneIdentifier: String
    @State private var alert: AgentUsageDashboardAlert?

    init(mode: AgentUsageInsightsMode = .tokenAnalytics, service: AgentUsageInsightsService? = nil) {
        let resolvedService = service ?? AgentUsageInsightsService.shared
        self.service = resolvedService
        self.mode = mode
        switch resolvedService.timeZoneMode {
        case let .fixed(identifier):
            _fixedTimeZoneIdentifier = State(initialValue: identifier)
        case .system, .utc:
            _fixedTimeZoneIdentifier = State(initialValue: TimeZone.current.identifier)
        }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            dashboardHeader
            loadStateBanner
            if mode == .tokenAnalytics {
                tokenOverview
                valueOverview
                activitySection
                usageRankingSection
                modelAndSessionSection
                preferencesAndDiagnostics
            } else {
                projectUsageSection
                taskBoardSection
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.lg)
        .onAppear {
            syncFixedTimeZone()
            service.startScheduling()
        }
        .onChange(of: service.timeZoneMode) { _ in
            syncFixedTimeZone()
        }
        .alert(item: $alert) { value in
            switch value.kind {
            case .clearCaches:
                return Alert(
                    title: Text(localizer.t("清除用量缓存？", en: "Clear usage caches?")),
                    message: Text(localizer.t(
                        "只会删除 TraceFence 的派生统计缓存，不会修改任何 Agent 的会话、任务、日志或数据库。随后会立即重新扫描。",
                        en: "Only TraceFence's derived analytics caches will be removed. Agent sessions, tasks, logs, and databases are never changed. A new scan will start immediately."
                    )),
                    primaryButton: .destructive(Text(localizer.t("清除并重扫", en: "Clear & Rescan"))) {
                        service.clearCaches()
                    },
                    secondaryButton: .cancel()
                )
            case .notice:
                return Alert(
                    title: Text(value.title),
                    message: Text(value.message),
                    dismissButton: .default(Text(localizer.t("好", en: "OK")))
                )
            }
        }
    }

    // MARK: Header and scan state

    private var dashboardHeader: some View {
        CardView(padding: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Theme.Radius.md)
                            .fill(Theme.Gradients.accent)
                        Image(systemName: "chart.xyaxis.line")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(dashboardTitle)
                            .font(Theme.Font.title2Bold)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(dashboardSubtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    Spacer(minLength: Theme.Spacing.md)

                    statusBadge

                    Button {
                        performScanAction()
                    } label: {
                        Label(scanActionTitle, systemImage: scanActionIcon)
                    }
                    .buttonStyle(BrandButtonStyle(variant: .secondary, minHeight: 30))
                    .help(scanActionHelp)
                }

                Divider().overlay(Theme.Colors.separator)

                HStack(spacing: Theme.Spacing.sm) {
                    Text(localizer.t("可信 Token 来源", en: "Trusted token sources"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    ForEach(AgentUsageScope.allCases) { scope in
                        scopeButton(scope)
                    }

                    Spacer()

                    Label(
                        localizer.t("统计时区：", en: "Statistics time zone: ") + service.snapshot.timeZoneIdentifier,
                        systemImage: "globe"
                    )
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                }
            }
        }
    }

    private var statusBadge: some View {
        let presentation = loadStatePresentation
        return HStack(spacing: 6) {
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .tint(presentation.color)
            } else {
                Circle()
                    .fill(presentation.color)
                    .frame(width: 7, height: 7)
            }
            Text(presentation.title)
                .font(Theme.Font.captionMedium)
                .lineLimit(1)
        }
        .foregroundStyle(presentation.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(presentation.color.opacity(0.1))
        .clipShape(Capsule())
    }

    @ViewBuilder
    private var loadStateBanner: some View {
        switch service.state {
        case .idle:
            AgentUsageMessageBanner(
                icon: "clock",
                color: Theme.Colors.textTertiary,
                title: localizer.t("等待本地扫描", en: "Waiting for local scan"),
                detail: localizer.t("打开此页面后会自动开始读取可用的本地用量来源。", en: "Available local usage sources are scanned automatically when this view opens.")
            )
        case .loading:
            scanProgressBanner
        case .paused:
            if let backfill = service.backfillStatus {
                backfillStatusBanner(backfill)
            } else {
                AgentUsageMessageBanner(
                    icon: "pause.circle.fill",
                    color: Theme.Colors.warning,
                    title: localizer.t("扫描已暂停", en: "Scan paused"),
                    detail: localizer.t("已保留上次快照；点击“继续补全”后从本地缓存继续。", en: "The previous snapshot is preserved. Continue backfill resumes from the local cache.")
                )
            }
        case let .partial(message):
            if let backfill = service.backfillStatus {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    backfillStatusBanner(backfill)
                    if let warning = service.snapshot.diagnostics.first(where: {
                        $0.severity != .info && !AgentUsageDiagnosticPresentation.isBackfill($0)
                    }) {
                        AgentUsageMessageBanner(
                            icon: "exclamationmark.triangle.fill",
                            color: Theme.Colors.warning,
                            title: localizer.t("其它数据诊断", en: "Other data diagnostic"),
                            detail: AgentUsageDiagnosticPresentation.message(warning, localizer: localizer)
                        )
                    }
                }
            } else {
                let warning = service.snapshot.diagnostics.first(where: { $0.severity != .info })
                AgentUsageMessageBanner(
                    icon: "exclamationmark.triangle.fill",
                    color: Theme.Colors.warning,
                    title: localizer.t("数据不完整", en: "Partial data"),
                    detail: warning.map {
                        AgentUsageDiagnosticPresentation.message($0, localizer: localizer)
                    } ?? message
                )
            }
        case let .failed(message, previous):
            AgentUsageMessageBanner(
                icon: "xmark.octagon.fill",
                color: Theme.Colors.danger,
                title: previous == nil
                    ? localizer.t("读取失败", en: "Scan failed")
                    : localizer.t("刷新失败，继续显示上次数据", en: "Refresh failed — showing previous data"),
                detail: message
            )
        case .ready:
            if let backfill = service.backfillStatus {
                backfillStatusBanner(backfill)
            } else if service.snapshot.diagnostics.contains(where: { $0.severity != .info }) {
                AgentUsageMessageBanner(
                    icon: "info.circle.fill",
                    color: Theme.Colors.info,
                    title: localizer.t("扫描已完成，但有诊断信息", en: "Scan completed with diagnostics"),
                    detail: localizer.t("可在页面底部查看数据来源状态。", en: "Review source status at the bottom of this page.")
                )
            }
        }
    }

    private var scanProgressBanner: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.Colors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(scanPhaseTitle(service.progress.phase))
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        if service.progress.total > 0 {
                            Text("\(service.progress.current) / \(service.progress.total)")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    Text(localizedProgressMessage)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Spacer()
                if let source = service.progress.currentSource, !source.isEmpty {
                    Label(redactedSourceLabel(source), systemImage: "doc.text")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 300, alignment: .trailing)
                        .help(source)
                }
            }

            if let fraction = service.progress.fractionCompleted {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.Colors.accent)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.Colors.accent)
            }

            if let backfill = service.backfillStatus {
                backfillMetrics(backfill, compact: true)
            }

            if case let .loading(previous) = service.state, previous != nil {
                Text(localizer.t("扫描期间继续显示上一次完整快照。", en: "The last complete snapshot remains visible while scanning."))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.accent.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(Theme.Colors.accent.opacity(0.18), lineWidth: 1)
        )
    }

    private func backfillStatusBanner(_ status: AgentUsageBackfillStatus) -> some View {
        let presentation = backfillStatusPresentation(status)
        return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: presentation.icon)
                    .foregroundStyle(presentation.color)
                Text(presentation.title)
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if let completedAt = status.completedAt {
                    Label(
                        localizer.t("结束于 ", en: "Ended ")
                            + AgentUsageFormat.time(completedAt, timeZoneIdentifier: service.snapshot.timeZoneIdentifier),
                        systemImage: "clock"
                    )
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            Text(backfillEndReasonText(status))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            backfillMetrics(status, compact: false)
        }
        .padding(Theme.Spacing.md)
        .background(presentation.color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .stroke(presentation.color.opacity(0.2), lineWidth: 1)
        )
    }

    private func backfillMetrics(_ status: AgentUsageBackfillStatus, compact: Bool) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: compact ? 105 : 118), spacing: 8)],
            alignment: .leading,
            spacing: 6
        ) {
            backfillMetric(
                localizer.t("已检查", en: "Checked"),
                "\(status.checkedSessions) / \(status.totalSessions)"
            )
            backfillMetric(localizer.t("本轮待处理", en: "Pending at start"), "\(status.pendingAtStart)")
            backfillMetric(localizer.t("本轮已读取", en: "Advanced"), "\(status.advancedThisRun)")
            backfillMetric(localizer.t("完整补全", en: "Completed"), "\(status.completedThisRun)")
            backfillMetric(localizer.t("剩余", en: "Remaining"), "\(status.remainingSessions)")
            backfillMetric(localizer.t("本轮跳过", en: "Skipped"), "\(status.skippedThisRun)")
            backfillMetric(localizer.t("本轮失败", en: "Failed"), "\(status.failedThisRun)")
            if status.excludedByInventoryLimit > 0 {
                backfillMetric(localizer.t("明细范围外", en: "Outside detail range"), "\(status.excludedByInventoryLimit)")
            }
            if status.aggregateOnlyHistorySessions > 0 {
                backfillMetric(localizer.t("仅总量历史", en: "Aggregate-only history"), "\(status.aggregateOnlyHistorySessions)")
            }
        }
    }

    private func backfillMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func backfillStatusPresentation(_ status: AgentUsageBackfillStatus) -> (title: String, icon: String, color: Color) {
        switch status.stage {
        case .inventory:
            return (localizer.t("正在检查本机会话范围", en: "Checking local session inventory"), "list.bullet.clipboard", Theme.Colors.accent)
        case .restoringCache:
            return (localizer.t("正在核对本地明细缓存", en: "Checking local detail cache"), "externaldrive", Theme.Colors.accent)
        case .fillingHistory:
            return (localizer.t("正在补全本机历史明细", en: "Backfilling local history"), "arrow.down.doc", Theme.Colors.accent)
        case .finalizing:
            return (localizer.t("正在确认本轮结果", en: "Finalizing this pass"), "checklist", Theme.Colors.accent)
        case .paused:
            return (localizer.t("本机明细扫描已暂停", en: "Local detail scan paused"), "pause.circle.fill", Theme.Colors.warning)
        case .failed:
            return (localizer.t("本机明细扫描失败", en: "Local detail scan failed"), "xmark.octagon.fill", Theme.Colors.danger)
        case .completed:
            if status.hasRemainingWork {
                return (localizer.t("本轮扫描已结束，仍有待补全", en: "Pass finished with detail remaining"), "exclamationmark.triangle.fill", Theme.Colors.warning)
            }
            return (localizer.t("当前明细范围已全部扫描", en: "Current detail range fully scanned"), "checkmark.circle.fill", Theme.Colors.success)
        }
    }

    private func backfillEndReasonText(_ status: AgentUsageBackfillStatus) -> String {
        guard let reason = status.endReason else {
            return localizer.t("正在本机检查范围并读取未缓存的会话明细。", en: "TraceFence is checking the local inventory and reading uncached session detail.")
        }
        switch reason {
        case .allEligibleSessionsScanned:
            if status.aggregateOnlyHistorySessions > 0 {
                return localizer.t("当前可补全范围已全部扫完；另有 \(status.aggregateOnlyHistorySessions) 个较早会话按 SQLite 全时间总量统计，不冒充已解析明细。", en: "The current backfillable range is complete. \(status.aggregateOnlyHistorySessions) older sessions remain represented by SQLite all-time totals and are not presented as parsed detail.")
            }
            return localizer.t("已检查当前全部可补全会话，没有剩余本机明细。", en: "Every currently eligible session was checked and no local detail remains to backfill.")
        case .timeBudgetReached:
            return localizer.t("本轮响应时间额度已到，仍有 \(status.remainingSessions) 个会话待补；点击“继续补全”会从缓存位置继续。", en: "This pass reached its responsiveness time budget with \(status.remainingSessions) sessions remaining. Continue backfill resumes from the cache.")
        case .readBudgetReached:
            return localizer.t("本轮本地读取额度已到，仍有 \(status.remainingSessions) 个会话待补；可继续下一轮。", en: "This pass reached its local read budget with \(status.remainingSessions) sessions remaining. Another pass can continue.")
        case .runLimitReached:
            return localizer.t("本轮有 \(status.remainingSessions) 个会话未处理完，可继续补全。", en: "This pass left \(status.remainingSessions) sessions unfinished. Continue backfill to resume.")
        case .inventoryLimitReached:
            return localizer.t("当前 2,000 个会话的明细已扫完；有 \(status.excludedByInventoryLimit) 个会话超出明细范围，另有 \(status.aggregateOnlyHistorySessions) 个较早会话仅纳入 SQLite 全时间总量，不冒充已解析明细。", en: "Detail is complete for the current 2,000-session inventory. \(status.excludedByInventoryLimit) sessions are outside that detail limit, and \(status.aggregateOnlyHistorySessions) older sessions remain represented only by SQLite all-time totals, not parsed detail.")
        case .pausedByUser:
            return localizer.t("扫描已按要求暂停，上次快照和已写入的本地缓存保留。", en: "The scan is paused. The previous snapshot and committed local cache progress are preserved.")
        case .scanFailed:
            return localizer.t("本轮遇到读取失败，已保留可用快照；点击“重试”重新检查。", en: "This pass encountered read failures. The usable snapshot is preserved; choose Retry to scan again.")
        }
    }

    // MARK: Token and value overview

    private var tokenOverview: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionTitle(
                localizer.t("Token 概览", en: "Token overview"),
                subtitle: localizer.t(
                    "四个分项互不重复；总量遵循来源累计口径，缺少分项的历史量单列为“未拆分”。",
                    en: "Breakdown fields do not overlap. Aggregate-only history is shown separately as Unattributed."
                ),
                icon: "number"
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: Theme.Spacing.md)], spacing: Theme.Spacing.md) {
                AgentUsageTokenCard(
                    title: localizer.t("今天", en: "Today"),
                    icon: "sun.max.fill",
                    color: Theme.Colors.accent,
                    totals: service.snapshot.today,
                    detailedTotal: nil,
                    localizer: localizer
                )
                AgentUsageTokenCard(
                    title: localizer.t("最近 7 天", en: "Last 7 days"),
                    icon: "calendar.badge.clock",
                    color: Theme.Colors.info,
                    totals: service.snapshot.last7Days,
                    detailedTotal: nil,
                    localizer: localizer
                )
                AgentUsageTokenCard(
                    title: localizer.t("本月", en: "This month"),
                    icon: "calendar",
                    color: Theme.Colors.purple,
                    totals: service.snapshot.currentMonth,
                    detailedTotal: nil,
                    localizer: localizer
                )
                AgentUsageTokenCard(
                    title: localizer.t("全部时间", en: "All time"),
                    icon: "infinity",
                    color: Theme.Colors.teal,
                    totals: service.snapshot.allTime,
                    detailedTotal: service.snapshot.allTimeDetailed.total,
                    localizer: localizer
                )
            }
        }
    }

    private var valueOverview: some View {
        CardView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    sectionTitle(
                        localizer.t("API 等值估算", en: "API-equivalent estimate"),
                        subtitle: localizer.t("按已识别模型的公开参考单价估算，不代表账单或订阅价值。", en: "Estimated from reference API prices for recognized models; this is not a bill or subscription valuation."),
                        icon: "dollarsign.circle"
                    )
                    Spacer()
                    if service.snapshot.estimatedAPIValueUSD.isEstimate {
                        Text(localizer.t("估算", en: "ESTIMATE"))
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Theme.Colors.warning)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.Colors.warning.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.md)], spacing: Theme.Spacing.sm) {
                    valueMetric(localizer.t("今天", en: "Today"), service.snapshot.estimatedAPIValueUSD.todayUSD)
                    valueMetric(localizer.t("最近 7 天", en: "Last 7 days"), service.snapshot.estimatedAPIValueUSD.last7DaysUSD)
                    valueMetric(localizer.t("本月", en: "This month"), service.snapshot.estimatedAPIValueUSD.currentMonthUSD)
                    valueMetric(localizer.t("全部时间（已解析）", en: "All time (parsed)"), service.snapshot.estimatedAPIValueUSD.allTimeUSD)
                }

                if !service.snapshot.estimatedAPIValueUSD.unknownModels.isEmpty {
                    Label(
                        localizer.t("以下模型未计价：", en: "Unpriced models: ")
                            + service.snapshot.estimatedAPIValueUSD.unknownModels.prefix(6).joined(separator: ", "),
                        systemImage: "info.circle"
                    )
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(2)
                }
            }
        }
    }

    private func valueMetric(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(AgentUsageFormat.currency(value))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.cardBg.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    // MARK: Activity

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionTitle(
                localizer.t("活动趋势", en: "Activity trends"),
                subtitle: localizer.t("180 天日历热力图与最近两周趋势。", en: "180-day calendar heatmap and recent two-week trend."),
                icon: "waveform.path.ecg"
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 430), spacing: Theme.Spacing.md)], spacing: Theme.Spacing.md) {
                dailyHeatmapCard
                sevenDayTrendCard
            }
        }
    }

    private var dailyHeatmapCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizer.t("每日活跃度 · 180 天", en: "Daily activity · 180 days"))
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.t("颜色越深，Token 用量越高", en: "Darker cells represent higher token usage"))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Spacer()
                    Text(AgentUsageFormat.tokens(service.snapshot.dailyBuckets.reduce(Int64(0)) { partial, bucket in
                        AgentUsageFormat.saturatingAdd(partial, bucket.tokens.total)
                    }))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.accent)
                    .monospacedDigit()
                }

                if service.snapshot.dailyBuckets.isEmpty {
                    emptyState(localizer.t("还没有日历数据", en: "No calendar data yet"), icon: "calendar.badge.exclamationmark")
                } else {
                    AgentUsageDailyHeatmap(
                        buckets: service.snapshot.dailyBuckets,
                        thresholds: dailyHeatmapThresholds,
                        timeZone: service.snapshot.timeZoneIdentifier,
                        localizer: localizer
                    )
                }
            }
        }
    }

    private var sevenDayTrendCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizer.t("最近 7 天对比", en: "7-day comparison"))
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.t("浅色为前 7 天，主色为当前 7 天", en: "Muted bars are the previous 7 days; accent bars are the current 7 days"))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Spacer()
                    comparisonBadge
                }

                let buckets = Array(service.snapshot.dailyBuckets.suffix(14))
                if buckets.isEmpty {
                    emptyState(localizer.t("还没有趋势数据", en: "No trend data yet"), icon: "chart.bar.xaxis")
                } else {
                    Chart {
                        ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                            BarMark(
                                x: .value("Day", bucket.date, unit: .day),
                                y: .value("Tokens", bucket.tokens.total)
                            )
                            .foregroundStyle(index >= max(0, buckets.count - 7)
                                             ? Theme.Colors.accent
                                             : Theme.Colors.textTertiary.opacity(0.28))
                            .cornerRadius(2)
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: 2)) { value in
                            AxisGridLine().foregroundStyle(Theme.Colors.separator.opacity(0.35))
                            AxisValueLabel(format: .dateTime.month(.twoDigits).day(.twoDigits))
                                .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            AxisGridLine().foregroundStyle(Theme.Colors.separator.opacity(0.45))
                            AxisValueLabel {
                                if let amount = value.as(Int64.self) {
                                    Text(AgentUsageFormat.tokens(amount))
                                }
                            }
                            .foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                    .frame(height: 190)
                }

                HStack(spacing: Theme.Spacing.lg) {
                    comparisonMetric(
                        localizer.t("当前 7 天", en: "Current 7 days"),
                        service.snapshot.previous7DayComparison.current.total,
                        Theme.Colors.accent
                    )
                    comparisonMetric(
                        localizer.t("前 7 天", en: "Previous 7 days"),
                        service.snapshot.previous7DayComparison.previous.total,
                        Theme.Colors.textSecondary
                    )
                }
            }
        }
    }

    private var comparisonBadge: some View {
        let comparison = service.snapshot.previous7DayComparison
        let text: String
        let color: Color
        let icon: String
        if comparison.isNewActivity {
            text = localizer.t("新增活跃", en: "New activity")
            color = Theme.Colors.success
            icon = "sparkles"
        } else if let change = comparison.changePercent {
            text = String(format: "%+.1f%%", change)
            color = change > 0 ? Theme.Colors.success : (change < 0 ? Theme.Colors.warning : Theme.Colors.textSecondary)
            icon = change > 0 ? "arrow.up.right" : (change < 0 ? "arrow.down.right" : "minus")
        } else {
            text = "—"
            color = Theme.Colors.textSecondary
            icon = "minus"
        }
        return Label(text, systemImage: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    private func comparisonMetric(_ title: String, _ total: Int64, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(Theme.Font.caption).foregroundStyle(Theme.Colors.textTertiary)
                Text(AgentUsageFormat.tokens(total))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: Rankings

    private var usageRankingSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionTitle(
                localizer.t("工具与 Skill 使用", en: "Tool & Skill usage"),
                subtitle: localizer.t("按调用次数汇总本地 Agent 能力使用。", en: "Local Agent capabilities summarized by invocation count."),
                icon: "list.number"
            )

            toolsAndSkillsCard
        }
    }

    private var projectUsageSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionTitle(
                localizer.t("项目用量", en: "Project usage"),
                subtitle: localizer.t("项目归因与任务状态统一放在 Agent 监控。", en: "Project attribution and task state are unified in Agent Monitor."),
                icon: "folder.badge.gearshape"
            )

            projectRankingCard
        }
    }

    private var projectRankingCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Text(localizer.t("项目排行", en: "Projects"))
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    HStack(spacing: 2) {
                        projectPeriodButton(.last7Days, title: localizer.t("7 天", en: "7 days"))
                        projectPeriodButton(.allTime, title: localizer.t("全部", en: "All time"))
                    }
                    .padding(2)
                    .background(Theme.Colors.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }

                let projects = selectedProjects
                if projects.isEmpty {
                    emptyState(localizer.t("还没有项目统计", en: "No project statistics yet"), icon: "folder")
                } else {
                    let maximum = max(Int64(1), projects.map(\.tokens.total).max() ?? 1)
                    VStack(spacing: 0) {
                        ForEach(Array(projects.prefix(10).enumerated()), id: \.element.id) { index, project in
                            AgentUsageProjectRow(
                                rank: index + 1,
                                project: project,
                                maximum: maximum,
                                localizer: localizer
                            )
                            if index < min(projects.count, 10) - 1 {
                                Divider().overlay(Theme.Colors.separator.opacity(0.55))
                            }
                        }
                    }
                }
            }
        }
    }

    private var toolsAndSkillsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(localizer.t("工具与 Skills", en: "Tools & Skills"))
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                    rankingColumn(
                        title: localizer.t("工具 TOP", en: "Top tools"),
                        icon: "hammer.fill",
                        rows: Array(service.snapshot.topTools.prefix(8)).map {
                            AgentUsageRankingRowData(
                                id: $0.id,
                                title: $0.name,
                                subtitle: $0.category,
                                value: localizer.t("\($0.callCount) 次", en: "\($0.callCount) calls")
                            )
                        }
                    )

                    Divider().overlay(Theme.Colors.separator)

                    rankingColumn(
                        title: localizer.t("Skill TOP", en: "Top Skills"),
                        icon: "bolt.fill",
                        rows: Array(service.snapshot.topSkills.prefix(8)).map {
                            AgentUsageRankingRowData(
                                id: $0.id,
                                title: $0.name,
                                subtitle: localizer.t("\($0.sessionCount) 个会话", en: "\($0.sessionCount) sessions"),
                                value: localizer.t("\($0.loadCount) 次", en: "\($0.loadCount) loads")
                            )
                        }
                    )
                }
            }
        }
    }

    private var modelAndSessionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionTitle(
                localizer.t("模型与会话归因", en: "Model & session attribution"),
                subtitle: localizer.t(
                    "模型与会话只归因已解析明细；未拆分历史量不会被猜测到模型或会话。",
                    en: "Models and sessions use parsed records only; unattributed history is never guessed."
                ),
                icon: "cpu"
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 430), spacing: Theme.Spacing.md)], spacing: Theme.Spacing.md) {
                modelRankingCard
                recentSessionsCard
            }
        }
    }

    private var modelRankingCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(localizer.t("模型排行", en: "Models"))
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if service.snapshot.modelRankings.isEmpty {
                    emptyState(localizer.t("暂无模型归因", en: "No model attribution yet"), icon: "cpu")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(service.snapshot.modelRankings.prefix(12).enumerated()), id: \.element.id) { index, model in
                            HStack(spacing: Theme.Spacing.sm) {
                                Text("\(index + 1)")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(index < 3 ? Theme.Colors.accent : Theme.Colors.textTertiary)
                                    .frame(width: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(model.model)
                                        .font(Theme.Font.captionMedium)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .lineLimit(1)
                                    Text("\(localizedScope(model.scope)) · \(model.sessionCount) " + localizer.t("个会话", en: "sessions"))
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(AgentUsageFormat.tokens(model.tokens.total))
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                    Text(modelPriceText(model))
                                        .font(.system(size: 9, design: .rounded))
                                        .foregroundStyle(modelPriceIsIncomplete(model) ? Theme.Colors.warning : Theme.Colors.textTertiary)
                                }
                            }
                            .padding(.vertical, 7)
                            if index < min(service.snapshot.modelRankings.count, 12) - 1 {
                                Divider().overlay(Theme.Colors.separator.opacity(0.5))
                            }
                        }
                    }
                }
            }
        }
    }

    private func modelPriceIsIncomplete(_ model: AgentUsageModelUsage) -> Bool {
        service.snapshot.estimatedAPIValueUSD.unknownModels.contains(model.model)
    }

    private func modelPriceText(_ model: AgentUsageModelUsage) -> String {
        guard modelPriceIsIncomplete(model) else {
            return AgentUsageFormat.currency(model.estimatedAPIValueUSD)
        }
        if model.estimatedAPIValueUSD > 0 {
            return localizer.t(
                "部分计价 \(AgentUsageFormat.currency(model.estimatedAPIValueUSD))",
                en: "Partial \(AgentUsageFormat.currency(model.estimatedAPIValueUSD))"
            )
        }
        return localizer.t("价格未知", en: "Price unavailable")
    }

    private var recentSessionsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text(localizer.t("最近会话", en: "Recent sessions"))
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if service.snapshot.recentSessions.isEmpty {
                    emptyState(localizer.t("暂无会话归因", en: "No session attribution yet"), icon: "list.bullet.rectangle")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(service.snapshot.recentSessions.prefix(12).enumerated()), id: \.element.id) { index, session in
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: "bubble.left.and.text.bubble.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.Colors.info)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.projectName)
                                        .font(Theme.Font.captionMedium)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                        .lineLimit(1)
                                    Text("\(localizedScope(session.scope)) · \(session.model)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.Colors.textTertiary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(AgentUsageFormat.tokens(session.tokens.total))
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .monospacedDigit()
                                    if let date = session.lastActiveAt {
                                        Text(AgentUsageFormat.relative(date))
                                            .font(.system(size: 9))
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                    }
                                }
                            }
                            .padding(.vertical, 7)
                            .help(session.fullProjectPath)
                            if index < min(service.snapshot.recentSessions.count, 12) - 1 {
                                Divider().overlay(Theme.Colors.separator.opacity(0.5))
                            }
                        }
                    }
                }
            }
        }
    }

    private func rankingColumn(title: String, icon: String, rows: [AgentUsageRankingRowData]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(title, systemImage: icon)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
            if rows.isEmpty {
                Text(localizer.t("暂无数据", en: "No data"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 90, alignment: .center)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    HStack(spacing: Theme.Spacing.sm) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(index < 3 ? Theme.Colors.accent : Theme.Colors.textTertiary)
                            .frame(width: 16)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title)
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            Text(row.subtitle)
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Text(row.value)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: Task board

    private var taskBoardSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            sectionTitle(
                localizer.t("今日任务板", en: "Today's task board"),
                subtitle: localizer.t("四列状态来自本机可识别的 Agent 任务元数据。", en: "Four status columns from locally recognizable Agent task metadata."),
                icon: "rectangle.3.group"
            )

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 205), spacing: Theme.Spacing.md)], alignment: .leading, spacing: Theme.Spacing.md) {
                taskColumn(
                    category: .active,
                    title: localizer.t("进行中", en: "Active"),
                    icon: "play.circle.fill",
                    color: Theme.Colors.accent,
                    tasks: service.snapshot.tasks.active
                )
                taskColumn(
                    category: .pending,
                    title: localizer.t("待处理", en: "Pending"),
                    icon: "pause.circle.fill",
                    color: Theme.Colors.warning,
                    tasks: service.snapshot.tasks.pending
                )
                taskColumn(
                    category: .scheduled,
                    title: localizer.t("已计划", en: "Scheduled"),
                    icon: "calendar.badge.clock",
                    color: Theme.Colors.info,
                    tasks: service.snapshot.tasks.scheduled
                )
                taskColumn(
                    category: .done,
                    title: localizer.t("已完成", en: "Done"),
                    icon: "checkmark.circle.fill",
                    color: Theme.Colors.success,
                    tasks: service.snapshot.tasks.done
                )
            }
        }
    }

    private func taskColumn(
        category: AgentUsageTaskCategory,
        title: String,
        icon: String,
        color: Color,
        tasks: [AgentUsageTaskItem]
    ) -> some View {
        CardView(padding: Theme.Spacing.md, showShadow: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack(spacing: 7) {
                    Image(systemName: icon).foregroundStyle(color)
                    Text(title)
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Text("\(tasks.count)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.1))
                        .clipShape(Capsule())
                }

                if tasks.isEmpty {
                    Text(localizer.t("暂无任务", en: "No tasks"))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 68, alignment: .center)
                } else {
                    ForEach(tasks.prefix(6)) { task in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(task.title)
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(2)
                            HStack(spacing: 5) {
                                Text(task.scope.displayName)
                                if let project = task.project, !project.isEmpty {
                                    Text("•")
                                    Text(project).lineLimit(1)
                                }
                                Spacer(minLength: 2)
                                if let tokens = task.tokens {
                                    Text(AgentUsageFormat.tokens(tokens))
                                        .monospacedDigit()
                                }
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        }
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(color.opacity(0.055))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    // MARK: Preferences, diagnostics, export

    private var preferencesAndDiagnostics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 430), spacing: Theme.Spacing.md)], alignment: .leading, spacing: Theme.Spacing.md) {
            timeZoneAndDataCard
            diagnosticsCard
        }
    }

    private var timeZoneAndDataCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                sectionTitle(
                    localizer.t("统计与数据", en: "Statistics & data"),
                    subtitle: localizer.t("所有日期边界在一次扫描中使用同一时区。", en: "Every date boundary in a scan uses the same time zone."),
                    icon: "slider.horizontal.3"
                )

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text(localizer.t("统计时区", en: "Statistics time zone"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    HStack(spacing: 4) {
                        timeZoneModeButton(.system, title: localizer.t("系统", en: "System"))
                        timeZoneModeButton(.utc, title: "UTC")
                        timeZoneModeButton(.fixed, title: localizer.t("固定 IANA", en: "Fixed IANA"))
                    }
                    .padding(3)
                    .background(Theme.Colors.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                    if currentTimeZoneKind == .fixed {
                        HStack(spacing: Theme.Spacing.sm) {
                            TextField("Asia/Shanghai", text: $fixedTimeZoneIdentifier)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11, design: .monospaced))
                                .onSubmit { applyFixedTimeZone() }
                            Menu {
                                ForEach(AgentUsageCommonTimeZone.allCases) { zone in
                                    Button(zone.rawValue) {
                                        fixedTimeZoneIdentifier = zone.rawValue
                                        applyFixedTimeZone()
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .menuStyle(.borderlessButton)
                            .frame(width: 24)
                            Button(localizer.t("应用", en: "Apply")) {
                                applyFixedTimeZone()
                            }
                            .buttonStyle(BrandButtonStyle(variant: .secondary, minHeight: 26))
                            .disabled(TimeZone(identifier: fixedTimeZoneIdentifier) == nil)
                        }
                        if TimeZone(identifier: fixedTimeZoneIdentifier) == nil {
                            Label(localizer.t("请输入有效的 IANA 时区标识符。", en: "Enter a valid IANA time-zone identifier."), systemImage: "exclamationmark.circle")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.danger)
                        }
                    }
                }

                Divider().overlay(Theme.Colors.separator)

                HStack(spacing: Theme.Spacing.sm) {
                    if SandboxPaths.isSandboxed {
                        Button {
                            authorizeUsageDataFolders()
                        } label: {
                            Label(localizer.t("授权数据目录", en: "Authorize data folders"), systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(BrandButtonStyle(variant: .secondary, minHeight: 30))
                    }

                    Button {
                        exportRedactedJSON()
                    } label: {
                        Label(localizer.t("导出脱敏 JSON", en: "Export redacted JSON"), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(BrandButtonStyle(variant: .secondary, minHeight: 30))

                    Button {
                        alert = AgentUsageDashboardAlert(kind: .clearCaches, title: "", message: "")
                    } label: {
                        Label(localizer.t("清缓存并重扫", en: "Clear cache & rescan"), systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .secondary, minHeight: 30))

                    Spacer()
                }

                Text(localizer.t(
                    "脱敏导出不包含完整项目路径、任务标题、Skill 路径或诊断来源。",
                    en: "Redacted exports omit full project paths, task titles, Skill paths, and diagnostic sources."
                ))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var diagnosticsCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    sectionTitle(
                        localizer.t("数据诊断", en: "Data diagnostics"),
                        subtitle: localizer.t("仅显示来源状态，不展示会话正文。", en: "Shows source status only, never transcript content."),
                        icon: "stethoscope"
                    )
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(localizer.t("\(service.snapshot.parsedFileCount) 个文件", en: "\(service.snapshot.parsedFileCount) files"))
                        Text(localizer.t("\(service.snapshot.tokenEventCount) 个 Token 事件", en: "\(service.snapshot.tokenEventCount) token events"))
                    }
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                }

                HStack(spacing: Theme.Spacing.sm) {
                    diagnosticPill(
                        title: localizer.t("质量", en: "Quality"),
                        value: sourceQualityTitle(service.snapshot.sourceQuality),
                        color: sourceQualityColor(service.snapshot.sourceQuality)
                    )
                    diagnosticPill(
                        title: localizer.t("生成时间", en: "Generated"),
                        value: AgentUsageFormat.time(service.snapshot.generatedAt, timeZoneIdentifier: service.snapshot.timeZoneIdentifier),
                        color: Theme.Colors.info
                    )
                }

                if !service.snapshot.sourceSummaries.isEmpty {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(service.snapshot.sourceSummaries) { source in
                            sourceSummaryPill(source)
                        }
                        Spacer()
                    }
                }

                Label {
                    Text(localizer.t(
                        "只有提供原生 Token 计数、稳定事件 ID 和真实时间戳，并通过一致性校验的来源才会计入。Cursor、Trae、CodeBuddy、Qoder 等仍在 Agent 监控显示活动；未提供可信 Token 时不会估算。",
                        en: "Only sources with native token counters, stable event IDs, real timestamps, and consistent totals are included. Cursor, Trae, CodeBuddy, Qoder, and others remain visible in Agent Monitor; TraceFence never estimates tokens when trustworthy counters are unavailable."
                    ))
                } icon: {
                    Image(systemName: "checkmark.shield")
                }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

                if service.snapshot.diagnostics.isEmpty {
                    Label(localizer.t("没有发现数据源问题", en: "No source issues detected"), systemImage: "checkmark.circle.fill")
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.success)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                } else {
                    VStack(spacing: 0) {
                        ForEach(service.snapshot.diagnostics.prefix(12)) { diagnostic in
                            AgentUsageDiagnosticRow(diagnostic: diagnostic, localizer: localizer)
                            if diagnostic.id != service.snapshot.diagnostics.prefix(12).last?.id {
                                Divider().overlay(Theme.Colors.separator.opacity(0.5))
                            }
                        }
                    }
                }
            }
        }
    }

    private func diagnosticPill(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(Theme.Colors.textTertiary)
            Text(value).font(Theme.Font.captionMedium).foregroundStyle(color).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func sourceSummaryPill(_ source: AgentUsageSourceSummary) -> some View {
        let color: Color
        if !source.available || source.sourceQuality == .unavailable {
            color = Theme.Colors.textTertiary
        } else {
            color = source.partial ? Theme.Colors.warning : Theme.Colors.success
        }
        return VStack(alignment: .leading, spacing: 2) {
            Text(localizedScope(source.scope))
                .font(Theme.Font.captionMedium)
                .foregroundStyle(color)
            Text(localizer.t(
                "\(source.parsedFileCount) 文件 · \(source.tokenEventCount) 事件",
                en: "\(source.parsedFileCount) files · \(source.tokenEventCount) events"
            ))
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    // MARK: Helpers

    private func sectionTitle(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Colors.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private func scopeButton(_ scope: AgentUsageScope) -> some View {
        let selected = service.scope == scope
        return Button {
            service.scope = scope
        } label: {
            Text(localizedScope(scope))
                .font(Theme.Font.captionMedium)
                .foregroundStyle(selected ? .white : Theme.Colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selected ? Theme.Colors.accent : Theme.Colors.cardBg)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func projectPeriodButton(_ period: AgentUsageProjectPeriod, title: String) -> some View {
        let selected = projectPeriod == period
        return Button(title) { projectPeriod = period }
            .font(Theme.Font.captionMedium)
            .foregroundStyle(selected ? .white : Theme.Colors.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(selected ? Theme.Colors.accent : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .buttonStyle(.plain)
    }

    private func timeZoneModeButton(_ kind: AgentUsageTimeZoneKind, title: String) -> some View {
        let selected = currentTimeZoneKind == kind
        return Button(title) {
            switch kind {
            case .system:
                service.timeZoneMode = .system
            case .utc:
                service.timeZoneMode = .utc
            case .fixed:
                if TimeZone(identifier: fixedTimeZoneIdentifier) == nil {
                    fixedTimeZoneIdentifier = TimeZone.current.identifier
                }
                service.timeZoneMode = .fixed(identifier: fixedTimeZoneIdentifier)
            }
        }
        .font(Theme.Font.captionMedium)
        .foregroundStyle(selected ? .white : Theme.Colors.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(selected ? Theme.Colors.accent : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .buttonStyle(.plain)
    }

    private func emptyState(_ title: String, icon: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(title)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }

    private var isLoading: Bool {
        if case .loading = service.state { return true }
        return false
    }

    private var hasPendingBackfill: Bool {
        if let backfill = service.backfillStatus {
            return backfill.remainingSessions > 0
        }
        return service.snapshot.diagnostics.contains(where: AgentUsageDiagnosticPresentation.isBackfill)
    }

    private var scanNeedsRetry: Bool {
        if case .failed = service.state { return true }
        return service.backfillStatus?.endReason == .scanFailed
    }

    private var scanActionTitle: String {
        if isLoading { return localizer.t("暂停", en: "Pause") }
        if scanNeedsRetry { return localizer.t("重试", en: "Retry") }
        if hasPendingBackfill { return localizer.t("继续补全", en: "Continue backfill") }
        return localizer.t("刷新", en: "Refresh")
    }

    private var scanActionIcon: String {
        if isLoading { return "pause.fill" }
        if scanNeedsRetry { return "arrow.counterclockwise" }
        return "arrow.clockwise"
    }

    private var scanActionHelp: String {
        if isLoading {
            return localizer.t("暂停本轮本地扫描并保留已写入的缓存", en: "Pause this local pass and preserve committed cache progress")
        }
        if scanNeedsRetry {
            return localizer.t("重试上次失败的本地扫描", en: "Retry the failed local scan")
        }
        if hasPendingBackfill {
            return localizer.t("从本地缓存位置继续补全剩余会话", en: "Resume remaining sessions from the local cache")
        }
        return localizer.t("重新读取本地用量数据", en: "Read local usage data again")
    }

    private func performScanAction() {
        if isLoading {
            service.pauseScan()
        } else if scanNeedsRetry {
            service.retryScan()
        } else if hasPendingBackfill {
            service.continueBackfill()
        } else {
            service.refresh(force: true)
        }
    }

    private var localizedProgressMessage: String {
        let current = service.progress.current
        let total = service.progress.total
        let count = total > 0 ? " · \(current) / \(total)" : ""
        switch service.progress.phase {
        case .idle:
            return localizer.t("TraceFence 正在准备本机扫描…", en: "TraceFence is preparing the local scan…")
        case .readingCodexDatabase:
            return localizer.t("TraceFence 正在本机读取 Codex 索引\(count)", en: "TraceFence is reading the local Codex index\(count)")
        case .scanningCodexSessions:
            return localizer.t("TraceFence 正在本机解析 Codex 会话\(count)", en: "TraceFence is scanning local Codex sessions\(count)")
        case .scanningClaudeTranscripts:
            return localizer.t("TraceFence 正在本机解析 Claude Code 会话\(count)", en: "TraceFence is scanning local Claude Code sessions\(count)")
        case .readingOpenCodeDatabase:
            return localizer.t("TraceFence 正在本机读取 OpenCode / MiniMax 原生 Token\(count)", en: "TraceFence is reading native OpenCode / MiniMax tokens\(count)")
        case .scanningOpenClawSessions:
            return localizer.t("TraceFence 正在本机解析 OpenClaw / QClaw 原生 Token\(count)", en: "TraceFence is scanning native OpenClaw / QClaw tokens\(count)")
        case .readingTasks:
            return localizer.t("TraceFence 正在本机读取 Agent 任务状态\(count)", en: "TraceFence is reading local Agent task state\(count)")
        case .aggregating:
            return localizer.t("TraceFence 正在合并并去重可信来源\(count)", en: "TraceFence is merging and deduplicating trusted sources\(count)")
        case .completed:
            return localizer.t("TraceFence 本机扫描完成", en: "TraceFence local scan complete")
        case .failed:
            return localizer.t("TraceFence 本机扫描失败", en: "TraceFence local scan failed")
        }
    }

    private var loadStatePresentation: (title: String, color: Color) {
        switch service.state {
        case .idle:
            return (localizer.t("待扫描", en: "Idle"), Theme.Colors.textTertiary)
        case .loading:
            return (localizer.t("正在扫描", en: "Scanning"), Theme.Colors.accent)
        case .paused:
            return (localizer.t("已暂停", en: "Paused"), Theme.Colors.warning)
        case .ready:
            return (localizer.t("已更新", en: "Up to date"), Theme.Colors.success)
        case .partial:
            if hasPendingBackfill {
                return (localizer.t("本机待续补", en: "Local backfill pending"), Theme.Colors.warning)
            }
            return (localizer.t("部分来源无明细", en: "Some sources lack detail"), Theme.Colors.warning)
        case .failed:
            return (localizer.t("读取失败", en: "Failed"), Theme.Colors.danger)
        }
    }

    private var selectedProjects: [AgentUsageProjectUsage] {
        switch projectPeriod {
        case .last7Days: return service.snapshot.projectRankings7Days
        case .allTime: return service.snapshot.projectRankingsAllTime
        }
    }

    private var dashboardTitle: String {
        switch mode {
        case .tokenAnalytics:
            return localizer.t("统一 Token 与用量", en: "Unified Token & Usage")
        case .projectMonitor:
            return localizer.t("项目用量与任务", en: "Project Usage & Tasks")
        }
    }

    private var dashboardSubtitle: String {
        switch mode {
        case .tokenAnalytics:
            return localizer.t(
                "概览与本页共用 Codex、Claude Code、OpenCode / MiniMax、OpenClaw / QClaw 的可信本机计数；不会上传会话内容。",
                en: "Overview and this page share trusted local counters from Codex, Claude Code, OpenCode / MiniMax, and OpenClaw / QClaw. Session content never leaves this Mac."
            )
        case .projectMonitor:
            return localizer.t(
                "按项目查看 Token 归因和 Agent 任务状态；统计口径与 Token 与用量页面一致。",
                en: "Review project attribution and Agent task state using the same totals as Token & Usage."
            )
        }
    }

    private var currentTimeZoneKind: AgentUsageTimeZoneKind {
        switch service.timeZoneMode {
        case .system: return .system
        case .utc: return .utc
        case .fixed: return .fixed
        }
    }

    private var dailyHeatmapThresholds: [Int64] {
        let values = service.snapshot.dailyBuckets.map(\.tokens.total).filter { $0 > 0 }.sorted()
        guard !values.isEmpty else { return [1, 10, 100, 1_000] }
        func percentile(_ fraction: Double) -> Int64 {
            let index = min(values.count - 1, max(0, Int(Double(values.count - 1) * fraction)))
            return max(1, values[index])
        }
        return [percentile(0.20), percentile(0.45), percentile(0.70), percentile(0.90)]
    }

    private func localizedScope(_ scope: AgentUsageScope) -> String {
        switch scope {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .openCode: return "OpenCode / MiniMax"
        case .openClaw: return "OpenClaw / QClaw"
        case .combined: return localizer.t("全部可信来源", en: "All trusted sources")
        }
    }

    private func scanPhaseTitle(_ phase: AgentUsageScanPhase) -> String {
        switch phase {
        case .idle: return localizer.t("准备扫描", en: "Preparing scan")
        case .readingCodexDatabase: return localizer.t("读取 Codex 索引", en: "Reading Codex index")
        case .scanningCodexSessions: return localizer.t("解析 Codex 会话", en: "Scanning Codex sessions")
        case .scanningClaudeTranscripts: return localizer.t("解析 Claude Code 会话", en: "Scanning Claude Code sessions")
        case .readingOpenCodeDatabase: return localizer.t("读取 OpenCode / MiniMax 原生计数", en: "Reading OpenCode / MiniMax counters")
        case .scanningOpenClawSessions: return localizer.t("解析 OpenClaw / QClaw 会话", en: "Scanning OpenClaw / QClaw sessions")
        case .readingTasks: return localizer.t("读取任务状态", en: "Reading task status")
        case .aggregating: return localizer.t("汇总统计", en: "Aggregating statistics")
        case .completed: return localizer.t("扫描完成", en: "Scan complete")
        case .failed: return localizer.t("扫描失败", en: "Scan failed")
        }
    }

    private func sourceQualityTitle(_ quality: AgentUsageSourceQuality) -> String {
        switch quality {
        case .detailed: return localizer.t("详细", en: "Detailed")
        case .approximate: return localizer.t("近似", en: "Approximate")
        case .mixed: return localizer.t("混合", en: "Mixed")
        case .unavailable: return localizer.t("不可用", en: "Unavailable")
        }
    }

    private func sourceQualityColor(_ quality: AgentUsageSourceQuality) -> Color {
        switch quality {
        case .detailed: return Theme.Colors.success
        case .approximate, .mixed: return Theme.Colors.warning
        case .unavailable: return Theme.Colors.danger
        }
    }

    private func redactedSourceLabel(_ source: String) -> String {
        let url = URL(fileURLWithPath: source)
        let name = url.lastPathComponent
        return name.isEmpty ? source : name
    }

    private func syncFixedTimeZone() {
        if case let .fixed(identifier) = service.timeZoneMode {
            fixedTimeZoneIdentifier = identifier
        }
    }

    private func applyFixedTimeZone() {
        guard TimeZone(identifier: fixedTimeZoneIdentifier) != nil else { return }
        service.timeZoneMode = .fixed(identifier: fixedTimeZoneIdentifier)
    }

    private func exportRedactedJSON() {
        do {
            let data = try service.exportJSON()
            let panel = NSSavePanel()
            panel.title = localizer.t("导出脱敏用量数据", en: "Export redacted usage data")
            panel.nameFieldStringValue = "tracefence-agent-usage-\(AgentUsageFormat.fileDate(Date())).json"
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try data.write(to: url, options: .atomic)
            alert = AgentUsageDashboardAlert(
                kind: .notice,
                title: localizer.t("导出完成", en: "Export complete"),
                message: url.path
            )
        } catch {
            alert = AgentUsageDashboardAlert(
                kind: .notice,
                title: localizer.t("导出失败", en: "Export failed"),
                message: error.localizedDescription
            )
        }
    }

    private func authorizeUsageDataFolders() {
        let panel = NSOpenPanel()
        panel.title = localizer.t("授权 Agent 数据目录", en: "Authorize Agent data folders")
        panel.message = localizer.t(
            "请选择 ~/.codex、~/.claude、~/.qclaw、~/.openclaw、~/.minimax、~/.local/share/opencode，或包含它们的用户主目录。TraceFence 只读取本地用量元数据。",
            en: "Choose a supported Agent data folder, or the home folder that contains them. TraceFence reads local usage metadata only."
        )
        panel.prompt = localizer.t("授权", en: "Authorize")
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.showsHiddenFiles = true
        panel.directoryURL = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
        guard panel.runModal() == .OK else { return }

        let bookmarkURL = URL(fileURLWithPath: SandboxPaths.shared.tokenScopeBookmarksPath)
        var bookmarks: [String: Data] = [:]
        if let data = try? Data(contentsOf: bookmarkURL),
           let existing = try? JSONDecoder().decode([String: Data].self, from: data) {
            bookmarks = existing
        }

        do {
            for url in panel.urls {
                let bookmark = try url.bookmarkData(
                    options: .withSecurityScope,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                bookmarks[url.standardizedFileURL.path] = bookmark
            }
            let data = try JSONEncoder().encode(bookmarks)
            try FileManager.default.createDirectory(
                at: bookmarkURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try data.write(to: bookmarkURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bookmarkURL.path)
            service.refresh(force: true)
        } catch {
            alert = AgentUsageDashboardAlert(
                kind: .notice,
                title: localizer.t("授权保存失败", en: "Could not save authorization"),
                message: error.localizedDescription
            )
        }
    }
}

// MARK: - Compact menu bar summary

@MainActor
struct AgentUsageRuntimeSummaryView: View {
    @EnvironmentObject private var localizer: Localizer
    @ObservedObject private var service: AgentUsageInsightsService

    init(service: AgentUsageInsightsService? = nil) {
        self.service = service ?? AgentUsageInsightsService.shared
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Theme.Gradients.hero)
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 34, height: 34)
                .shadow(color: Theme.Colors.accent.opacity(0.22), radius: 7, y: 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(localizer.t("实时 Token 用量", en: "Live Token Usage", zhHant: "即時 Token 用量", ja: "リアルタイム Token 使用量", ko: "실시간 Token 사용량", mt: "Live Token Usage"))
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("\(localizedScope)  ·  \(statusText)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(statusText.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(statusColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(statusColor.opacity(0.09))
                .clipShape(Capsule())

                Menu {
                    ForEach(AgentUsageScope.allCases) { scope in
                        Button {
                            service.scope = scope
                        } label: {
                            if service.scope == scope {
                                Label(scopeTitle(scope), systemImage: "checkmark")
                            } else {
                                Text(scopeTitle(scope))
                            }
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.Colors.textPrimary.opacity(0.045))
                        .clipShape(Circle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)

                Button {
                    service.refresh(force: true)
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Theme.Colors.textPrimary.opacity(0.045))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .help(localizer.t("刷新用量", en: "Refresh usage"))
            }

            if isLoading {
                compactProgress
            } else if case let .failed(message, _) = service.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.danger)
                    .lineLimit(2)
            }

            HStack(spacing: Theme.Spacing.sm) {
                compactMetric(
                    title: localizer.t("今天", en: "Today"),
                    value: AgentUsageFormat.tokens(service.snapshot.today.total),
                    detail: AgentUsageFormat.currency(service.snapshot.estimatedAPIValueUSD.todayUSD),
                    color: Theme.Colors.accent
                )
                compactMetric(
                    title: localizer.t("7 天", en: "7 days"),
                    value: AgentUsageFormat.tokens(service.snapshot.last7Days.total),
                    detail: comparisonText,
                    color: Theme.Colors.info
                )
            }

            HStack(spacing: Theme.Spacing.sm) {
                tokenChip("IN", service.snapshot.today.input, Theme.Colors.info)
                tokenChip("CACHE", service.snapshot.today.cached, Theme.Colors.teal)
                tokenChip("OUT", service.snapshot.today.output, Theme.Colors.purple)
                tokenChip("THINK", service.snapshot.today.reasoning, Theme.Colors.warning)
            }

            HStack(spacing: 5) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 8, weight: .semibold))
                Text(localizer.t("本地缓存", en: "Local cache", zhHant: "本機快取", ja: "ローカルキャッシュ", ko: "로컬 캐시", mt: "Local cache"))
                Text("·")
                Text(AgentUsageFormat.time(service.snapshot.generatedAt, timeZoneIdentifier: service.snapshot.timeZoneIdentifier))
            }
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(Theme.Spacing.md)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(Theme.Colors.elevatedCardBg.opacity(0.82))
                LinearGradient(
                    colors: [Theme.Colors.accent.opacity(0.10), .clear, Theme.Colors.purple.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Theme.Gradients.glassStroke, lineWidth: 1)
        }
        .shadow(color: Theme.Colors.shadowTint.opacity(0.08), radius: 9, y: 4)
        .onAppear { service.startScheduling() }
    }

    private var compactProgress: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini).tint(Theme.Colors.accent)
                Text(scanPhaseTitle)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                if service.progress.total > 0 {
                    Text("\(service.progress.current)/\(service.progress.total)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            if let fraction = service.progress.fractionCompleted {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    .tint(Theme.Colors.accent)
            } else {
                ProgressView().progressViewStyle(.linear).tint(Theme.Colors.accent)
            }
            HStack(spacing: 4) {
                Text(service.progress.message)
                    .lineLimit(1)
                if let source = service.progress.currentSource, !source.isEmpty {
                    Text("•")
                    Text(URL(fileURLWithPath: source).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(Theme.Colors.textTertiary)
        }
        .padding(8)
        .background(Theme.Colors.accent.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func compactMetric(title: String, value: String, detail: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(Theme.Font.caption).foregroundStyle(Theme.Colors.textTertiary)
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func tokenChip(_ label: String, _ value: Int64, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(AgentUsageFormat.tokens(value))
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(color.opacity(0.055))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var statusText: String {
        switch service.state {
        case .idle: return localizer.t("待更新", en: "Pending")
        case .loading: return localizer.t("扫描中", en: "Scanning")
        case .paused: return localizer.t("已暂停", en: "Paused")
        case .ready: return localizer.t("缓存就绪", en: "Cached")
        case .partial: return localizer.t("部分数据", en: "Partial")
        case .failed: return localizer.t("异常", en: "Issue")
        }
    }

    private var statusColor: Color {
        switch service.state {
        case .idle: return Theme.Colors.textTertiary
        case .loading: return Theme.Colors.accent
        case .paused: return Theme.Colors.warning
        case .ready: return Theme.Colors.success
        case .partial: return Theme.Colors.warning
        case .failed: return Theme.Colors.danger
        }
    }

    private var comparisonText: String {
        let comparison = service.snapshot.previous7DayComparison
        if comparison.isNewActivity { return localizer.t("新增活跃", en: "New activity") }
        if let change = comparison.changePercent { return String(format: "%+.1f%%", change) }
        return AgentUsageFormat.currency(service.snapshot.estimatedAPIValueUSD.last7DaysUSD)
    }

    private var localizedScope: String { scopeTitle(service.scope) }

    private func scopeTitle(_ scope: AgentUsageScope) -> String {
        switch scope {
        case .codex: return "Codex"
        case .claude: return "Claude Code"
        case .openCode: return "OpenCode / MiniMax"
        case .openClaw: return "OpenClaw / QClaw"
        case .combined: return localizer.t("全部可信来源", en: "All trusted sources")
        }
    }

    private var isLoading: Bool {
        if case .loading = service.state { return true }
        return false
    }

    private var scanPhaseTitle: String {
        switch service.progress.phase {
        case .idle: return localizer.t("准备扫描", en: "Preparing")
        case .readingCodexDatabase: return localizer.t("读取 Codex 索引", en: "Reading Codex index")
        case .scanningCodexSessions: return localizer.t("解析 Codex 会话", en: "Scanning Codex sessions")
        case .scanningClaudeTranscripts: return localizer.t("解析 Claude 会话", en: "Scanning Claude sessions")
        case .readingOpenCodeDatabase: return localizer.t("读取 OpenCode / MiniMax", en: "Reading OpenCode / MiniMax")
        case .scanningOpenClawSessions: return localizer.t("解析 OpenClaw / QClaw", en: "Scanning OpenClaw / QClaw")
        case .readingTasks: return localizer.t("读取任务", en: "Reading tasks")
        case .aggregating: return localizer.t("汇总统计", en: "Aggregating")
        case .completed: return localizer.t("扫描完成", en: "Complete")
        case .failed: return localizer.t("扫描失败", en: "Failed")
        }
    }
}

// MARK: - Supporting views

private struct AgentUsageTokenCard: View {
    let title: String
    let icon: String
    let color: Color
    let totals: AgentUsageTokenTotals
    let detailedTotal: Int64?
    let localizer: Localizer

    var body: some View {
        CardView(padding: Theme.Spacing.md, showShadow: false) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(color)
                    Spacer()
                }
                Text(AgentUsageFormat.tokens(totals.total))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .monospacedDigit()
                Text(exactTokenCaption)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .help(exactTokenCaption)
                if unattributedTotal > 0 {
                    VStack(alignment: .leading, spacing: 5) {
                        breakdown(
                            localizer.t("可拆分明细", en: "Parsed detail"),
                            resolvedDetailedTotal,
                            Theme.Colors.success
                        )
                        breakdown(
                            localizer.t("历史未拆分", en: "Unattributed history"),
                            unattributedTotal,
                            Theme.Colors.warning
                        )
                        ProgressView(value: detailCoverage)
                            .progressViewStyle(.linear)
                            .tint(Theme.Colors.success)
                            .help(String(format: localizer.t("明细覆盖 %.1f%%", en: "Detail coverage %.1f%%"), detailCoverage * 100))
                        Text(localizer.t("可拆分明细构成", en: "Parsed detail breakdown"))
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    Divider().overlay(Theme.Colors.separator.opacity(0.7))
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 5) {
                    breakdown(localizer.t("非缓存输入", en: "Uncached input"), uncachedInput, Theme.Colors.info)
                    breakdown(localizer.t("缓存输入", en: "Cached input"), cachedInput, Theme.Colors.teal)
                    breakdown(localizer.t("普通输出", en: "Standard output"), standardOutput, Theme.Colors.purple)
                    breakdown(localizer.t("推理输出", en: "Reasoning output"), reasoningOutput, Theme.Colors.warning)
                }
                if detailedUnclassifiedTotal > 0 {
                    breakdown(
                        localizer.t("明细未分类", en: "Unclassified detail"),
                        detailedUnclassifiedTotal,
                        Theme.Colors.textTertiary
                    )
                }
            }
        }
    }

    private var resolvedDetailedTotal: Int64 {
        min(totals.total, max(0, detailedTotal ?? totals.total))
    }

    private var exactTokenCaption: String {
        let exact = AgentUsageTokenFormatter.exactString(totals.total)
        return localizer.t(
            "\(exact) Token · B = 十亿",
            en: "\(exact) tokens · B = billion",
            zhHant: "\(exact) Token · B = 十億",
            ja: "\(exact) トークン · B = 10億",
            ko: "\(exact) 토큰 · B = 10억",
            mt: "\(exact) tokens · B = billion"
        )
    }

    private var unattributedTotal: Int64 {
        max(0, totals.total - resolvedDetailedTotal)
    }

    private var cachedInput: Int64 {
        min(max(0, totals.cached), max(0, totals.input))
    }

    private var uncachedInput: Int64 {
        max(0, totals.input - cachedInput)
    }

    private var reasoningOutput: Int64 {
        min(max(0, totals.reasoning), max(0, totals.output))
    }

    private var standardOutput: Int64 {
        max(0, totals.output - reasoningOutput)
    }

    private var categorizedDetailedTotal: Int64 {
        let inputs = AgentUsageFormat.saturatingAdd(uncachedInput, cachedInput)
        let outputs = AgentUsageFormat.saturatingAdd(standardOutput, reasoningOutput)
        return AgentUsageFormat.saturatingAdd(inputs, outputs)
    }

    private var detailedUnclassifiedTotal: Int64 {
        max(0, resolvedDetailedTotal - categorizedDetailedTotal)
    }

    private var detailCoverage: Double {
        guard totals.total > 0 else { return 1 }
        return min(1, max(0, Double(resolvedDetailedTotal) / Double(totals.total)))
    }

    private func breakdown(_ label: String, _ value: Int64, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).foregroundStyle(Theme.Colors.textTertiary)
            Spacer(minLength: 2)
            Text(AgentUsageFormat.tokens(value)).foregroundStyle(Theme.Colors.textSecondary).monospacedDigit()
        }
        .font(.system(size: 9))
    }
}

private struct AgentUsageMessageBanner: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Font.captionMedium).foregroundStyle(Theme.Colors.textPrimary)
                Text(detail).font(Theme.Font.caption).foregroundStyle(Theme.Colors.textSecondary).textSelection(.enabled)
            }
            Spacer()
        }
        .padding(Theme.Spacing.md)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(color.opacity(0.18), lineWidth: 1))
    }
}

private struct AgentUsageDailyHeatmap: View {
    let buckets: [AgentUsageDailyBucket]
    let thresholds: [Int64]
    let timeZone: String
    let localizer: Localizer

    private let rows = Array(repeating: GridItem(.fixed(11), spacing: 3), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(alignment: .top, spacing: 6) {
                VStack(alignment: .trailing, spacing: 0) {
                    dayLabel(localizer.t("日", en: "S"), row: 0)
                    dayLabel("", row: 1)
                    dayLabel(localizer.t("二", en: "T"), row: 2)
                    dayLabel("", row: 3)
                    dayLabel(localizer.t("四", en: "T"), row: 4)
                    dayLabel("", row: 5)
                    dayLabel(localizer.t("六", en: "S"), row: 6)
                }
                .padding(.top, 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: rows, alignment: .top, spacing: 3) {
                        ForEach(Array(cells.enumerated()), id: \.offset) { _, bucket in
                            if let bucket {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(color(for: bucket.tokens.total))
                                    .frame(width: 11, height: 11)
                                    .help(helpText(for: bucket))
                            } else {
                                Color.clear.frame(width: 11, height: 11)
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }

            HStack(spacing: 4) {
                Spacer()
                Text(localizer.t("少", en: "Less"))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.textTertiary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(legendColor(level))
                        .frame(width: 10, height: 10)
                }
                Text(localizer.t("多", en: "More"))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var cells: [AgentUsageDailyBucket?] {
        guard let first = buckets.first else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        let weekday = calendar.component(.weekday, from: first.date)
        return Array(repeating: nil, count: max(0, weekday - 1)) + buckets.map(Optional.some)
    }

    private func dayLabel(_ text: String, row: Int) -> some View {
        Text(text)
            .font(.system(size: 8))
            .foregroundStyle(Theme.Colors.textTertiary)
            .frame(width: 10, height: 14)
    }

    private func color(for value: Int64) -> Color {
        guard value > 0 else { return Theme.Colors.separator.opacity(0.38) }
        let level: Int
        if value <= threshold(0) { level = 1 }
        else if value <= threshold(1) { level = 2 }
        else if value <= threshold(2) { level = 3 }
        else { level = 4 }
        return legendColor(level)
    }

    private func legendColor(_ level: Int) -> Color {
        switch level {
        case 0: return Theme.Colors.separator.opacity(0.38)
        case 1: return Theme.Colors.accent.opacity(0.22)
        case 2: return Theme.Colors.accent.opacity(0.42)
        case 3: return Theme.Colors.accent.opacity(0.68)
        default: return Theme.Colors.accent
        }
    }

    private func threshold(_ index: Int) -> Int64 {
        guard thresholds.indices.contains(index) else { return Int64.max }
        return thresholds[index]
    }

    private func helpText(for bucket: AgentUsageDailyBucket) -> String {
        "\(AgentUsageFormat.day(bucket.date, timeZoneIdentifier: timeZone)): \(AgentUsageFormat.tokens(bucket.tokens.total)) tokens · \(AgentUsageFormat.currency(bucket.estimatedAPIValueUSD))"
    }
}

private struct AgentUsageProjectRow: View {
    let rank: Int
    let project: AgentUsageProjectUsage
    let maximum: Int64
    let localizer: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Theme.Spacing.sm) {
                Text("\(rank)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(rank <= 3 ? Theme.Colors.accent : Theme.Colors.textTertiary)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(project.name)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Text(localizer.t("\(project.sessionCount) 个会话", en: "\(project.sessionCount) sessions"))
                        if let date = project.lastActiveAt {
                            Text("•")
                            Text(AgentUsageFormat.relative(date))
                        }
                    }
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.Colors.textTertiary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(AgentUsageFormat.tokens(project.tokens.total))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .monospacedDigit()
                    Text(AgentUsageFormat.currency(project.estimatedAPIValueUSD))
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Colors.separator.opacity(0.45))
                    Capsule()
                        .fill(Theme.Colors.accent.opacity(0.72))
                        .frame(width: geometry.size.width * CGFloat(Double(project.tokens.total) / Double(maximum)))
                }
            }
            .frame(height: 3)
        }
        .padding(.vertical, 7)
        .help(project.fullPath)
    }
}

private enum AgentUsageDiagnosticPresentation {
    static func isBackfill(_ diagnostic: AgentUsageDiagnostic) -> Bool {
        diagnostic.code == "codex_scan_bounded" || diagnostic.code == "codex_backfill_bounded"
    }

    static func message(_ diagnostic: AgentUsageDiagnostic, localizer: Localizer) -> String {
        let count = leadingCount(diagnostic.message)
        switch diagnostic.code {
        case "codex_scan_bounded":
            return localizer.t(
                "\(count ?? "部分") 个较大或尚未缓存的 Codex 会话正在渐进补全；为保持界面流畅，本轮仅处理了有界数据。后续刷新会继续读取。",
                en: diagnostic.message
            )
        case "codex_backfill_bounded":
            return localizer.t(
                "Codex 历史超过 2,000 个会话的本地补全上限；当前优先读取最新会话，全历史总量仍来自本地索引。",
                en: diagnostic.message
            )
        case "codex_old_history_aggregated":
            return localizer.t(
                "\(count ?? "部分") 个较早的 Codex 任务仅提供全历史汇总，不重放完整转录。",
                en: diagnostic.message
            )
        case "codex_cache_write_failed":
            return localizer.t("Codex 用量缓存无法保存；下次刷新可能更慢。", en: diagnostic.message)
        case "codex_state_unavailable":
            return localizer.t("Codex 本地状态索引当前不可用。", en: diagnostic.message)
        case "codex_state_read_failed":
            return localizer.t("无法读取 Codex 本地状态索引。", en: diagnostic.message)
        case "codex_detailed_usage_rejected":
            return localizer.t("详细 Codex 用量明显异常，已拒绝该明细并保留可信汇总。", en: diagnostic.message)
        case "codex_rollout_rejected":
            return localizer.t("部分 Codex 会话文件不在允许范围内，已跳过。", en: diagnostic.message)
        case "codex_session_parse_partial":
            return localizer.t("部分 Codex 会话记录无法完整解析；其余数据仍可用。", en: diagnostic.message)
        case "codex_sources_missing":
            return localizer.t("未找到可读取的 Codex 本地用量来源。", en: diagnostic.message)
        case "claude_projects_missing":
            return localizer.t("未找到可读取的 Claude Code 项目记录。", en: diagnostic.message)
        case "claude_cache_write_failed":
            return localizer.t("Claude Code 用量缓存无法保存；下次刷新可能更慢。", en: diagnostic.message)
        case "claude_transcript_parse_partial":
            return localizer.t("部分 Claude Code 转录无法完整解析；其余数据仍可用。", en: diagnostic.message)
        case "claude_transcripts_empty":
            return localizer.t("Claude Code 转录中暂未发现可用记录。", en: diagnostic.message)
        case "claude_usage_empty":
            return localizer.t("Claude Code 本地记录中暂未发现 Token 用量。", en: diagnostic.message)
        case "opencode_sources_missing":
            return localizer.t("未找到 OpenCode / MiniMax 原生 Token 数据库；该来源未计入总量。", en: diagnostic.message)
        case "opencode_usage_empty":
            return localizer.t("已检测到 OpenCode / MiniMax，但数据库暂未写入非零原生 Token。", en: diagnostic.message)
        case "opencode_mirror_deduplicated":
            return localizer.t("MiniMax 与 OpenCode 的同一批 turn 已按原生 ID 去重，只计一次。", en: diagnostic.message)
        case "opencode_usage_inconsistent":
            return localizer.t("部分 OpenCode / MiniMax 原生计数未通过分项与总量一致性检查，已跳过。", en: diagnostic.message)
        case "opencode_database_read_failed":
            return localizer.t("部分 OpenCode / MiniMax 数据库当前无法读取。", en: diagnostic.message)
        case "openclaw_sessions_missing":
            return localizer.t("未找到 OpenClaw / QClaw 原生会话用量文件；该来源未计入总量。", en: diagnostic.message)
        case "openclaw_usage_empty":
            return localizer.t("已检测到 OpenClaw / QClaw 会话，但暂未发现非零原生 message.usage。", en: diagnostic.message)
        case "openclaw_events_deduplicated":
            return localizer.t("OpenClaw / QClaw 镜像事件已按原生事件 ID 去重，只计一次。", en: diagnostic.message)
        case "openclaw_usage_inconsistent":
            return localizer.t("部分 OpenClaw / QClaw 原生计数缺少稳定 ID、时间或未通过总量一致性检查，已跳过。", en: diagnostic.message)
        case "openclaw_session_parse_partial":
            return localizer.t("部分 OpenClaw / QClaw 会话文件无法完整解析；其余可信记录仍可用。", en: diagnostic.message)
        case "usage_bookmark_required":
            return localizer.t("需要重新授权本地目录，才能继续读取该用量来源。", en: diagnostic.message)
        case "usage_bookmark_unavailable":
            return localizer.t("已保存的本地目录授权当前不可用。", en: diagnostic.message)
        case "usage_bookmark_partial":
            return localizer.t("部分本地目录授权不可用；已继续读取其余来源。", en: diagnostic.message)
        default:
            return diagnostic.message
        }
    }

    static func backfillExplanation(_ diagnostic: AgentUsageDiagnostic, localizer: Localizer) -> String {
        let count = leadingCount(diagnostic.message) ?? "部分"
        return localizer.t(
            "由 TraceFence 应用内的本机扫描器执行，不是 Codex、Claude 或云端 Agent。当前剩余 \(count) 个 Codex 会话待补全；保持 TraceFence 运行会按计划继续，退出应用后暂停，下次启动从缓存续读。全部时间 Token 总量已可用；历史模型、项目和会话归因仍在补全。",
            en: "TraceFence's in-app local scanner performs this work—not Codex, Claude, or a cloud agent. \(count) Codex sessions remain. It continues while TraceFence is running, pauses when the app exits, and resumes from its cache next launch. The all-time token total is already available; historical model, project, and session attribution is still being filled in."
        )
    }

    private static func leadingCount(_ message: String) -> String? {
        guard let first = message.split(separator: " ").first,
              Int(first) != nil else { return nil }
        return String(first)
    }
}

private struct AgentUsageDiagnosticRow: View {
    let diagnostic: AgentUsageDiagnostic
    let localizer: Localizer

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(diagnostic.code)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                    if let scope = diagnostic.scope {
                        Text(scope.displayName)
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                Text(AgentUsageDiagnosticPresentation.message(diagnostic, localizer: localizer))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .textSelection(.enabled)
                if let source = diagnostic.source, !source.isEmpty {
                    Text(URL(fileURLWithPath: source).lastPathComponent)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                        .help(source)
                }
            }
            Spacer()
        }
        .padding(.vertical, 7)
    }

    private var icon: String {
        switch diagnostic.severity {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    private var color: Color {
        switch diagnostic.severity {
        case .info: return Theme.Colors.info
        case .warning: return Theme.Colors.warning
        case .error: return Theme.Colors.danger
        }
    }
}

// MARK: - Local helpers

private enum AgentUsageProjectPeriod {
    case last7Days
    case allTime
}

private enum AgentUsageTimeZoneKind {
    case system
    case utc
    case fixed
}

private enum AgentUsageCommonTimeZone: String, CaseIterable, Identifiable {
    case shanghai = "Asia/Shanghai"
    case tokyo = "Asia/Tokyo"
    case singapore = "Asia/Singapore"
    case london = "Europe/London"
    case berlin = "Europe/Berlin"
    case newYork = "America/New_York"
    case losAngeles = "America/Los_Angeles"

    var id: String { rawValue }
}

private struct AgentUsageRankingRowData {
    let id: String
    let title: String
    let subtitle: String
    let value: String
}

private struct AgentUsageDashboardAlert: Identifiable {
    enum Kind {
        case clearCaches
        case notice
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let message: String
}

private enum AgentUsageFormat {
    static func tokens(_ value: Int64) -> String {
        AgentUsageTokenFormatter.string(value)
    }

    static func currency(_ value: Double) -> String {
        if value >= 1_000 { return String(format: "$%.0f", value) }
        if value >= 100 { return String(format: "$%.1f", value) }
        return String(format: "$%.2f", value)
    }

    static func time(_ date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func day(_ date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func fileDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    static func saturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
        let (value, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int64.max : value
    }
}
