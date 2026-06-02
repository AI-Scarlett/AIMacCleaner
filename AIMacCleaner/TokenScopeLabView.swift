import SwiftUI
import Charts
import Foundation
import AppKit
import Security

struct TokenScopeLabView: View {
    @EnvironmentObject private var localizer: Localizer
    @StateObject private var store = TokenScopeStore()
    @State private var selectedRange: TokenScopeRange = .week
    @State private var selectedTab: TokenScopeTab = .overview
    @State private var showingProviderAuth = false

    private var summary: TokenScopeSummary {
        store.summary(for: selectedRange)
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "chart.xyaxis.line",
                title: localizer.tokenScopeTitle,
                subtitle: localizer.tokenScopeSubtitle,
                color: Theme.Colors.teal
            ) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button(action: syncNow) {
                        Label(store.isScanning ? localizer.tokenScopeScanning : localizer.tokenScopeSyncNow, systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isScanning)

                    Button(action: selectFolder) {
                        Label(localizer.tokenScopeSelectDataFolder, systemImage: "folder.badge.gearshape")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.isScanning)

                    Button {
                        showingProviderAuth = true
                    } label: {
                        Label(localizer.tokenScopeProviderAuth, systemImage: "key.horizontal.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    TokenScopeStatusStrip(
                        summary: summary,
                        store: store,
                        selectedRange: $selectedRange,
                        localizer: localizer
                    )

                    TokenScopeTabBar(selectedTab: $selectedTab, localizer: localizer)

                    Group {
                        switch selectedTab {
                        case .overview:
                            TokenScopeOverviewPanel(summary: summary, range: selectedRange, localizer: localizer)
                        case .projects:
                            TokenScopeProjectsPanel(projects: summary.projects, localizer: localizer)
                        case .models:
                            TokenScopeModelsPanel(models: summary.models, localizer: localizer)
                        case .sessions:
                            TokenScopeSessionsPanel(sessions: summary.sessions, localizer: localizer)
                        case .sources:
                            TokenScopeSourcesPanel(sources: store.sources, localizer: localizer)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.vertical, Theme.Spacing.lg)
            }
            .background(Theme.Colors.background)
        }
        .onAppear {
            store.startAutoRefresh()
        }
        .onDisappear {
            store.stopAutoRefresh()
        }
        .sheet(isPresented: $showingProviderAuth) {
            TokenScopeProviderAuthView(store: store, localizer: localizer) {
                selectFolder()
            }
        }
    }

    private func syncNow() {
        store.scanDefaultRoots()
    }

    private func selectFolder() {
        store.selectDataFolders(localizer: localizer)
    }
}

// MARK: - Screen Sections

private struct TokenScopeSourceRail: View {
    let sources: [TokenScopeSourceStatus]
    let localizer: Localizer

    private var sortedSources: [TokenScopeSourceStatus] {
        sources.sorted {
            if $0.records == $1.records { return $0.name < $1.name }
            return $0.records > $1.records
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(localizer.tokenScopeSources)
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(localizer.tokenScopeRealDataSources)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.lg)

            VStack(spacing: Theme.Spacing.xs) {
                ForEach(sortedSources) { source in
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: source.state.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(source.state.color)
                            .frame(width: 24, height: 24)
                            .background(source.state.color.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text(source.name)
                                    .font(Theme.Font.captionMedium)
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(source.records)")
                                    .font(Theme.Font.captionMedium)
                                    .foregroundStyle(source.records > 0 ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                            }

                            Text("\(source.scannedFiles) \(localizer.tokenScopeFiles) · \(source.state.label(localizer))")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(source.records > 0 ? Theme.Colors.background.opacity(0.75) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                }
            }
            .padding(.horizontal, Theme.Spacing.md)

            Spacer(minLength: Theme.Spacing.lg)
        }
    }
}

private struct TokenScopeStatusStrip: View {
    let summary: TokenScopeSummary
    @ObservedObject var store: TokenScopeStore
    @Binding var selectedRange: TokenScopeRange
    let localizer: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(statusText, systemImage: statusIcon)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(statusColor)

                    Text(statusDetail)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: Theme.Spacing.lg)

                Picker("", selection: $selectedRange) {
                    ForEach(TokenScopeRange.allCases, id: \.self) { range in
                        Text(range.label(localizer)).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 5), spacing: Theme.Spacing.md) {
                TokenScopeMetricTile(icon: "sum", title: localizer.tokenScopeTotalTokens, value: TokenScopeFormat.tokens(summary.totals.total), color: Theme.Colors.teal)
                TokenScopeMetricTile(icon: "arrow.down.circle.fill", title: localizer.tokenScopeInputTokens, value: TokenScopeFormat.tokens(summary.totals.input), color: Theme.Colors.info)
                TokenScopeMetricTile(icon: "arrow.up.circle.fill", title: localizer.tokenScopeOutputTokens, value: TokenScopeFormat.tokens(summary.totals.output), color: Theme.Colors.success)
                TokenScopeMetricTile(icon: "memorychip.fill", title: localizer.tokenScopeCacheTokens, value: TokenScopeFormat.tokens(summary.totals.cacheTotal), color: Theme.Colors.purple)
                TokenScopeMetricTile(icon: "dollarsign.circle.fill", title: localizer.tokenScopeEstimatedSpend, value: TokenScopeFormat.currency(summary.totals.cost), color: Theme.Colors.warning)
            }
        }
        .cardStyle()
    }

    private var statusText: String {
        if store.isScanning { return localizer.tokenScopeScanning }
        return store.hasRealData ? localizer.tokenScopeLocalData : localizer.tokenScopeNoRealData
    }

    private var statusDetail: String {
        if store.isScanning { return localizer.tokenScopeScanningDetail }
        if store.hasRealData {
            return localizer.tokenScopeLoadedSummary(recordCount: store.recordCount, sourceCount: store.activeSourceCount, tokenText: TokenScopeFormat.tokens(summary.totals.total))
        }
        if store.scanCompleted { return localizer.tokenScopeNoData }
        return localizer.tokenScopeIntro
    }

    private var statusIcon: String {
        if store.isScanning { return "arrow.triangle.2.circlepath" }
        return store.hasRealData ? "checkmark.seal.fill" : "lock.open.fill"
    }

    private var statusColor: Color {
        if store.isScanning { return Theme.Colors.info }
        return store.hasRealData ? Theme.Colors.success : Theme.Colors.warning
    }
}

private struct TokenScopeSourceStrip: View {
    let sources: [TokenScopeSourceStatus]
    let localizer: Localizer

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.md), count: 3), spacing: Theme.Spacing.md) {
            ForEach(sources) { source in
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: source.state.icon)
                        .foregroundStyle(source.state.color)
                        .frame(width: 28, height: 28)
                        .background(source.state.color.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(source.name)
                                .font(Theme.Font.captionMedium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Spacer()
                            Text(source.state.label(localizer))
                                .font(Theme.Font.caption)
                                .foregroundStyle(source.state.color)
                        }
                        Text(source.path)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                        Text("\(source.records) \(localizer.tokenScopeRecords) · \(source.scannedFiles) \(localizer.tokenScopeFiles)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
                .padding(Theme.Spacing.md)
                .background(Theme.Colors.sidebarBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
        }
    }
}

private struct TokenScopeTabBar: View {
    @Binding var selectedTab: TokenScopeTab
    let localizer: Localizer

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(TokenScopeTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.label(localizer), systemImage: tab.icon)
                            .font(Theme.Font.captionMedium)
                            .lineLimit(1)
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .background(selectedTab == tab ? Theme.Colors.teal.opacity(0.12) : Color.clear)
                            .foregroundStyle(selectedTab == tab ? Theme.Colors.teal : Theme.Colors.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Theme.Spacing.xs)
        .background(Theme.Colors.sidebarBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }
}

private struct TokenScopeOverviewPanel: View {
    let summary: TokenScopeSummary
    let range: TokenScopeRange
    let localizer: Localizer
    @State private var hoverDate: Date?
    @State private var trendMode: TokenScopeTrendMode = .token

    private var trendPoints: [TokenScopeTrendPoint] {
        switch trendMode {
        case .token:
            return tokenTrendPoints
        case .agent:
            return agentTrendPoints
        }
    }

    private var tokenTrendPoints: [TokenScopeTrendPoint] {
        summary.buckets.flatMap { bucket in
            [
                TokenScopeTrendPoint(date: bucket.date, label: bucket.label, type: localizer.tokenScopeInputTokens, value: bucket.input, color: Theme.Colors.info),
                TokenScopeTrendPoint(date: bucket.date, label: bucket.label, type: localizer.tokenScopeOutputTokens, value: bucket.output, color: Theme.Colors.success),
                TokenScopeTrendPoint(date: bucket.date, label: bucket.label, type: localizer.tokenScopeCacheTokens, value: bucket.cacheTotal, color: Theme.Colors.purple)
            ]
        }
    }

    private var agentTrendPoints: [TokenScopeTrendPoint] {
        summary.agentBuckets.map { bucket in
            TokenScopeTrendPoint(date: bucket.date, label: bucket.label, type: bucket.sourceName, value: bucket.totals.total, color: bucket.color)
        }
    }

    private var hoverPoints: [TokenScopeTrendPoint] {
        guard let hoverDate else { return [] }
        return trendPoints
            .filter { abs($0.date.timeIntervalSince(hoverDate)) < 1 }
            .sorted { trendSortIndex($0.type) < trendSortIndex($1.type) }
    }

    private var xDomain: ClosedRange<Date> {
        let first = summary.buckets.first?.date ?? Date()
        let last = summary.buckets.last?.date ?? Date()
        if first == last {
            let start = Calendar.current.date(byAdding: .hour, value: -1, to: first) ?? first
            let end = Calendar.current.date(byAdding: .hour, value: 1, to: last) ?? last
            return start...end
        }
        return first...last
    }

    private var legendDomain: [String] {
        Array(Set(trendPoints.map(\.type))).sorted { lhs, rhs in
            trendSortIndex(lhs) == trendSortIndex(rhs) ? lhs < rhs : trendSortIndex(lhs) < trendSortIndex(rhs)
        }
    }

    private var legendRange: [Color] {
        legendDomain.map { type in trendPoints.first(where: { $0.type == type })?.color ?? Theme.Colors.textSecondary }
    }

    private var yMax: Int {
        max(1, trendPoints.map(\.value).max() ?? 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .center, spacing: Theme.Spacing.md) {
                    TokenScopeSectionTitle(icon: "chart.line.uptrend.xyaxis", title: localizer.tokenScopeUsageTrend, subtitle: trendMode.subtitle(localizer))
                    Spacer()
                    Picker("", selection: $trendMode) {
                        ForEach(TokenScopeTrendMode.allCases, id: \.self) { mode in
                            Text(mode.label(localizer)).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
                TokenScopeTrendHoverBar(points: hoverPoints, localizer: localizer)

                Chart {
                    ForEach(trendPoints) { point in
                        LineMark(
                            x: .value(localizer.tokenScopeDate, point.date),
                            y: .value(point.type, point.value)
                        )
                        .foregroundStyle(by: .value(localizer.tokenScopeModels, point.type))
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        if hoverPoints.contains(where: { $0.id == point.id }) {
                            PointMark(
                                x: .value(localizer.tokenScopeDate, point.date),
                                y: .value(point.type, point.value)
                            )
                            .foregroundStyle(by: .value(localizer.tokenScopeModels, point.type))
                            .symbolSize(42)
                        }
                    }

                    if let hoverDate {
                        RuleMark(x: .value(localizer.tokenScopeDate, hoverDate))
                            .foregroundStyle(Theme.Colors.textSecondary.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartForegroundStyleScale(
                    domain: legendDomain,
                    range: legendRange
                )
                .chartXScale(domain: xDomain)
                .chartYScale(domain: 0...yMax)
                .chartLegend(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.15))
                        AxisValueLabel().font(.system(size: 9))
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: range.axisComponent, count: range.axisStride)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5)).foregroundStyle(Color.primary.opacity(0.15))
                        AxisValueLabel(anchor: .top) {
                            if let date = value.as(Date.self) {
                                Text(range.axisLabel(date))
                                    .font(.system(size: 9))
                            }
                        }
                    }
                }
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let location):
                                    let plotFrame = geometry[proxy.plotAreaFrame]
                                    let x = location.x - plotFrame.origin.x
                                    guard x >= 0, x <= plotFrame.width,
                                          let date: Date = proxy.value(atX: x) else {
                                        hoverDate = nil
                                        return
                                    }
                                    hoverDate = nearestTrendDate(to: date)
                                case .ended:
                                    hoverDate = nil
                                }
                            }
                    }
                }
                .frame(height: 280)
            }
            .cardStyle()

            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    TokenScopeSectionTitle(icon: "folder.fill", title: localizer.tokenScopeProjects, subtitle: localizer.tokenScopeProjectAttribution)
                    if summary.projects.isEmpty {
                        TokenScopeEmptyInline(text: localizer.tokenScopeEmptyRecords)
                    } else {
                        ForEach(summary.projects.prefix(5)) { project in
                            TokenScopeRankRow(title: project.name, subtitle: project.path, value: TokenScopeFormat.tokens(project.totals.total), progress: Double(project.totals.total) / Double(max(summary.projects.first?.totals.total ?? 1, 1)), color: project.color)
                        }
                    }
                }
                .cardStyle()

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    TokenScopeSectionTitle(icon: "cpu.fill", title: localizer.tokenScopeTopModels, subtitle: localizer.tokenScopeByCost)
                    if summary.models.isEmpty {
                        TokenScopeEmptyInline(text: localizer.tokenScopeEmptyRecords)
                    } else {
                        ForEach(summary.models.prefix(5)) { model in
                            TokenScopeRankRow(title: model.model, subtitle: model.provider, value: TokenScopeFormat.currency(model.cost), progress: model.cost / max(summary.models.first?.cost ?? 1, 1), color: model.color)
                        }
                    }
                }
                .cardStyle()
            }

            TokenScopeTableCard(title: localizer.tokenScopeSessions, subtitle: localizer.tokenScopeSessionDetail, icon: "list.bullet.rectangle.fill", headers: [localizer.tokenScopeTotalTokens, localizer.tokenScopeEstimatedSpend, localizer.tokenScopeModels]) {
                if summary.sessions.isEmpty {
                    TokenScopeEmptyInline(text: localizer.tokenScopeEmptyRecords)
                } else {
                    ForEach(summary.sessions.prefix(8)) { session in
                        TokenScopeDataRow(icon: "bubble.left.and.text.bubble.right", color: session.color, title: session.title, subtitle: session.project, columns: [TokenScopeFormat.tokens(session.totals.total), TokenScopeFormat.currency(session.totals.cost), session.model])
                    }
                }
            }
        }
    }

    private func nearestTrendDate(to date: Date) -> Date? {
        summary.buckets.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }?.date
    }

    private func trendSortIndex(_ type: String) -> Int {
        switch type {
        case localizer.tokenScopeInputTokens: return 0
        case localizer.tokenScopeOutputTokens: return 1
        case localizer.tokenScopeCacheTokens: return 2
        default: return 3
        }
    }
}

private struct TokenScopeProjectsPanel: View {
    let projects: [TokenScopeProjectSummary]
    let localizer: Localizer

    var body: some View {
        TokenScopeTableCard(title: localizer.tokenScopeProjects, subtitle: localizer.tokenScopeProjectAttribution, icon: "folder.fill", headers: [localizer.tokenScopeTotalTokens, localizer.tokenScopeEstimatedSpend, localizer.tokenScopeTopModels]) {
            if projects.isEmpty {
                TokenScopeEmptyInline(text: localizer.tokenScopeEmptyRecords)
            } else {
                ForEach(projects) { project in
                    TokenScopeDataRow(icon: "folder", color: project.color, title: project.name, subtitle: project.path, columns: [TokenScopeFormat.tokens(project.totals.total), TokenScopeFormat.currency(project.totals.cost), project.topModel])
                }
            }
        }
    }
}

private struct TokenScopeModelsPanel: View {
    let models: [TokenScopeModelSummary]
    let localizer: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            TokenScopeTableCard(title: localizer.tokenScopeModels, subtitle: localizer.tokenScopeTokenBreakdown, icon: "cpu.fill", headers: [localizer.tokenScopeInputTokens, localizer.tokenScopeOutputTokens, localizer.tokenScopeCacheTokens, localizer.tokenScopeEstimatedSpend]) {
                if models.isEmpty {
                    TokenScopeEmptyInline(text: localizer.tokenScopeEmptyRecords)
                } else {
                    ForEach(models) { model in
                        TokenScopeDataRow(
                            icon: "cpu",
                            color: model.color,
                            title: model.displayName,
                            subtitle: model.provider,
                            columns: [
                                TokenScopeFormat.tokens(model.totals.input),
                                TokenScopeFormat.tokens(model.totals.output),
                                TokenScopeFormat.tokens(model.totals.cacheTotal),
                                TokenScopeFormat.currency(model.cost)
                            ]
                        )
                    }
                }
            }
        }
    }
}

private struct TokenScopeSessionsPanel: View {
    let sessions: [TokenScopeSessionSummary]
    let localizer: Localizer

    var body: some View {
        TokenScopeTableCard(title: localizer.tokenScopeSessions, subtitle: localizer.tokenScopeSessionDetail, icon: "list.bullet.rectangle.fill", headers: [localizer.tokenScopeTotalTokens, localizer.tokenScopeEstimatedSpend, localizer.tokenScopeModels]) {
            if sessions.isEmpty {
                TokenScopeEmptyInline(text: localizer.tokenScopeEmptyRecords)
            } else {
                ForEach(sessions) { session in
                    TokenScopeDataRow(icon: "bubble.left.and.text.bubble.right", color: session.color, title: session.title, subtitle: session.project, columns: [TokenScopeFormat.tokens(session.totals.total), TokenScopeFormat.currency(session.totals.cost), session.model])
                }
            }
        }
    }
}

private struct TokenScopeSourcesPanel: View {
    let sources: [TokenScopeSourceStatus]
    let localizer: Localizer

    var body: some View {
        TokenScopeTableCard(title: localizer.tokenScopeSources, subtitle: localizer.tokenScopeRealDataSources, icon: "externaldrive.connected.to.line.below.fill", headers: [localizer.status, localizer.tokenScopeFiles, localizer.tokenScopeRecords]) {
            ForEach(sources) { source in
                TokenScopeDataRow(icon: source.state.icon, color: source.state.color, title: source.name, subtitle: source.path, columns: [source.state.label(localizer), "\(source.scannedFiles)", "\(source.records)"])
            }
        }
    }
}

private struct TokenScopeProviderAuthView: View {
    @ObservedObject var store: TokenScopeStore
    let localizer: Localizer
    let authorizeFolder: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedProvider: TokenScopeProvider = .openAI
    @State private var credential = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: "key.horizontal.fill")
                    .foregroundStyle(Theme.Colors.teal)
                    .frame(width: 36, height: 36)
                    .background(Theme.Colors.teal.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

                VStack(alignment: .leading, spacing: 3) {
                    Text(localizer.tokenScopeProviderAuth)
                        .font(Theme.Font.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.tokenScopeProviderAuthDesc)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colors.textSecondary)
            }
            .padding(Theme.Spacing.lg)

            Divider()

            HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    ForEach(TokenScopeProvider.allCases, id: \.self) { provider in
                        Button {
                            selectedProvider = provider
                            credential = ""
                        } label: {
                            HStack(spacing: Theme.Spacing.sm) {
                                Image(systemName: provider.icon)
                                    .frame(width: 24)
                                    .foregroundStyle(provider.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(provider.displayName)
                                        .font(Theme.Font.captionMedium)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                    Text(store.providerCredentialStatus(provider, localizer: localizer))
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(store.hasProviderCredential(provider) ? Theme.Colors.success : Theme.Colors.textSecondary)
                                }
                                Spacer()
                                if selectedProvider == provider {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Theme.Colors.teal)
                                }
                            }
                            .padding(Theme.Spacing.sm)
                            .background(selectedProvider == provider ? Theme.Colors.teal.opacity(0.08) : Theme.Colors.sidebarBg)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 220)

                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    TokenScopeSectionTitle(
                        icon: selectedProvider.icon,
                        title: selectedProvider.displayName,
                        subtitle: selectedProvider.authDescription(localizer)
                    )

                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text(localizer.tokenScopeAPIKey)
                            .font(Theme.Font.captionMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        SecureField(selectedProvider.placeholder, text: $credential)
                            .textFieldStyle(.roundedBorder)
                        Text(localizer.tokenScopeAPIKeyPrivacy)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    HStack(spacing: Theme.Spacing.sm) {
                        Button {
                            store.saveProviderCredential(credential, for: selectedProvider)
                            credential = ""
                        } label: {
                            Label(localizer.save, systemImage: "key.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(credential.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button {
                            store.deleteProviderCredential(for: selectedProvider)
                            credential = ""
                        } label: {
                            Label(localizer.deleteOps, systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!store.hasProviderCredential(selectedProvider))

                        Spacer()

                        Button {
                            authorizeFolder()
                        } label: {
                            Label(localizer.tokenScopeSelectDataFolder, systemImage: "folder.badge.gearshape")
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    Label(localizer.tokenScopeOAuthPolicyNote, systemImage: "safari.fill")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }
            }
            .padding(Theme.Spacing.lg)
        }
        .frame(width: 720, height: 520)
    }
}

// MARK: - Components

private struct TokenScopeMetricTile: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 30, height: 30)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            Text(value)
                .font(Theme.Font.title2Bold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.background.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

private struct TokenScopeSectionTitle: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .foregroundStyle(Theme.Colors.teal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.subheadlineMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }
}

private struct TokenScopeRankRow: View {
    let title: String
    let subtitle: String
    let value: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(subtitle)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(value)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(color)
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(color)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

private struct TokenScopeTrendPoint: Identifiable {
    let date: Date
    let label: String
    let type: String
    let value: Int
    let color: Color

    var id: String { "\(label)-\(type)" }
}

private enum TokenScopeTrendMode: CaseIterable {
    case token
    case agent

    func label(_ localizer: Localizer) -> String {
        switch self {
        case .token: localizer.tokenScopeTrendByToken
        case .agent: localizer.tokenScopeTrendByAgent
        }
    }

    func subtitle(_ localizer: Localizer) -> String {
        switch self {
        case .token: localizer.tokenScopeTokenBreakdown
        case .agent: localizer.tokenScopeAgentTokenTrend
        }
    }
}

private struct TokenScopeTrendHoverBar: View {
    let points: [TokenScopeTrendPoint]
    let localizer: Localizer

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let date = points.first?.date {
                Text(TokenScopeFormat.dayLabel(date))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(minWidth: 54, alignment: .leading)
            } else {
                Text(" ")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(minWidth: 54, alignment: .leading)
            }

            ForEach(points) { point in
                HStack(spacing: 4) {
                    Circle()
                        .fill(point.color)
                        .frame(width: 6, height: 6)
                    Text(point.type)
                        .font(.system(size: 9))
                    Text(TokenScopeFormat.tokens(point.value))
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.Colors.background.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }

            if points.isEmpty {
                HStack(spacing: Theme.Spacing.sm) {
                    legendDot(localizer.tokenScopeInputTokens, color: Theme.Colors.info)
                    legendDot(localizer.tokenScopeOutputTokens, color: Theme.Colors.success)
                    legendDot(localizer.tokenScopeCacheTokens, color: Theme.Colors.purple)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(height: 24)
    }

    private func legendDot(_ title: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

private enum TokenScopeTableLayout {
    static let firstColumnWidth: CGFloat = 300
    static let columnWidth: CGFloat = 116
    static let rowIconWidth: CGFloat = 28
    static let rowSpacing: CGFloat = Theme.Spacing.md
    static let horizontalPadding: CGFloat = Theme.Spacing.md * 2

    static func minWidth(columnCount: Int) -> CGFloat {
        firstColumnWidth + CGFloat(columnCount) * columnWidth + rowIconWidth + rowSpacing + horizontalPadding
    }
}

private struct TokenScopeTableCard<Content: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let headers: [String]
    let content: Content

    init(title: String, subtitle: String, icon: String, headers: [String], @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.headers = headers
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            TokenScopeSectionTitle(icon: icon, title: title, subtitle: subtitle)

            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack {
                        Text(title)
                            .frame(width: TokenScopeTableLayout.firstColumnWidth + TokenScopeTableLayout.rowIconWidth + TokenScopeTableLayout.rowSpacing, alignment: .center)
                        ForEach(headers, id: \.self) { header in
                            Text(header)
                                .multilineTextAlignment(.center)
                                .frame(width: TokenScopeTableLayout.columnWidth, alignment: .center)
                        }
                    }
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)

                    content
                }
                .frame(minWidth: max(680, TokenScopeTableLayout.minWidth(columnCount: headers.count)))
            }
            .background(Theme.Colors.background.opacity(0.45))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        }
        .cardStyle()
    }
}

private struct TokenScopeDataRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let columns: [String]

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: TokenScopeTableLayout.firstColumnWidth, alignment: .leading)
            .help("\(title)\n\(subtitle)")

            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                Text(column)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
                    .frame(width: TokenScopeTableLayout.columnWidth, alignment: .leading)
                    .help(column)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.Colors.separator.opacity(0.45))
                .frame(height: 0.5)
        }
    }
}

private struct TokenScopeEmptyInline: View {
    let text: String

    var body: some View {
        Text(text)
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Spacing.md)
    }
}

// MARK: - Store

private final class TokenScopeStore: ObservableObject {
    @Published private(set) var records: [TokenScopeUsageRecord] = []
    @Published private var summaries: [TokenScopeRange: TokenScopeSummary] = TokenScopeRange.emptySummaries
    @Published private(set) var sources: [TokenScopeSourceStatus]
    @Published private(set) var isScanning = false
    @Published private(set) var scanCompleted = false
    @Published private(set) var authorizedProviders: Set<TokenScopeProvider> = []

    private let scanner = TokenScopeScanner()
    private let bookmarkStore = TokenScopeBookmarkStore()
    private let scanQueue = DispatchQueue(label: "com.aimaccleaner.tokenscope.scan", qos: .utility)
    private var generation = 0
    private var autoRefreshTimer: Timer?
    private var scanInFlight = false

    init() {
        sources = scanner.defaultSourceStatuses()
        authorizedProviders = TokenScopeProviderCredentialStore.authorizedProviders()
    }

    var hasRealData: Bool { !records.isEmpty }
    var recordCount: Int { records.count }
    var activeSourceCount: Int { sources.filter { $0.records > 0 }.count }

    func summary(for range: TokenScopeRange) -> TokenScopeSummary {
        summaries[range] ?? TokenScopeSummary(records: [], range: range)
    }

    func scanDefaultRoots() {
        scan(roots: scanRoots(), showProgress: true)
    }

    func startAutoRefresh() {
        guard autoRefreshTimer == nil else { return }
        scan(roots: scanRoots(), showProgress: false)
        autoRefreshTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.scan(roots: self.scanRoots(), showProgress: false)
        }
    }

    func stopAutoRefresh() {
        autoRefreshTimer?.invalidate()
        autoRefreshTimer = nil
    }

    func selectDataFolders(localizer: Localizer) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = localizer.tokenScopeSelectDataFolder
        panel.prompt = localizer.tokenScopeSelectDataFolder
        guard panel.runModal() == .OK else { return }
        bookmarkStore.save(panel.urls)
        scan(roots: scanRoots(), showProgress: true)
    }

    func hasProviderCredential(_ provider: TokenScopeProvider) -> Bool {
        authorizedProviders.contains(provider)
    }

    func providerCredentialStatus(_ provider: TokenScopeProvider, localizer: Localizer) -> String {
        hasProviderCredential(provider) ? localizer.tokenScopeCredentialSaved : localizer.tokenScopeNotAuthorized
    }

    func saveProviderCredential(_ credential: String, for provider: TokenScopeProvider) {
        let trimmed = credential.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        TokenScopeProviderCredentialStore.save(trimmed, for: provider)
        authorizedProviders = TokenScopeProviderCredentialStore.authorizedProviders()
    }

    func deleteProviderCredential(for provider: TokenScopeProvider) {
        TokenScopeProviderCredentialStore.delete(provider)
        authorizedProviders = TokenScopeProviderCredentialStore.authorizedProviders()
    }

    private func scanRoots() -> [URL] {
        uniqueRoots(scanner.defaultRoots() + bookmarkStore.restore())
    }

    private func uniqueRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func scan(roots: [URL], showProgress: Bool) {
        guard !scanInFlight else { return }
        scanInFlight = true
        generation += 1
        let currentGeneration = generation
        if showProgress {
            isScanning = true
            scanCompleted = false
        }

        scanQueue.async {
            let result = self.scanner.scan(roots: roots)
            DispatchQueue.main.async {
                guard currentGeneration == self.generation else {
                    self.scanInFlight = false
                    self.isScanning = false
                    return
                }
                self.records = result.records
                self.summaries = TokenScopeRange.cachedSummaries(for: result.records)
                self.sources = result.sources
                self.scanCompleted = true
                self.isScanning = false
                self.scanInFlight = false
            }
        }
    }
}

private final class TokenScopeBookmarkStore {
    private let path = SandboxPaths.shared.tokenScopeBookmarksPath

    func restore() -> [URL] {
        var isStale = false
        var refreshed: [String: Data] = [:]
        let stored = readMergedBookmarks()
        let urls = stored.compactMap { originalPath, data -> URL? in
            do {
                let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                if isStale, let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                    refreshed[url.path] = bookmark
                } else {
                    refreshed[originalPath] = data
                }
                return url
            } catch {
                return nil
            }
        }
        if refreshed.count != stored.count || refreshed.keys.sorted() != stored.keys.sorted() {
            write(refreshed)
        }
        return urls
    }

    func save(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        var bookmarks = read()
        for url in urls {
            do {
                let bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                bookmarks[url.path] = bookmark
            } catch {
                print("[TokenScope] Failed to create bookmark for \(url.path): \(error)")
            }
        }
        write(bookmarks)
    }

    private func read() -> [String: Data] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
            return [:]
        }
        return bookmarks
    }

    private func readMergedBookmarks() -> [String: Data] {
        var merged = read()
        for bookmarkPath in [SandboxPaths.shared.bookmarksPath, SandboxPaths.shared.scanBookmarksPath] {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: bookmarkPath)),
                  let bookmarks = try? JSONDecoder().decode([String: Data].self, from: data) else {
                continue
            }
            for (path, data) in bookmarks where merged[path] == nil {
                merged[path] = data
            }
        }
        return merged
    }

    private func write(_ bookmarks: [String: Data]) {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
}

// MARK: - Domain Models

private enum TokenScopeSource: String, CaseIterable {
    case claude
    case codex
    case piAgent
    case gemini
    case codeBuddy
    case hermes
    case qClaw
    case openClaw
    case trae
    case cursor
    case qoder
    case cline
    case aider
    case copilot
    case qwen
    case kimi
    case deepSeek
    case openCode

    var name: String {
        switch self {
        case .claude: "Claude Code"
        case .codex: "Codex"
        case .piAgent: "Pi Agent"
        case .gemini: "Gemini CLI"
        case .codeBuddy: "CodeBuddy"
        case .hermes: "Hermes"
        case .qClaw: "QClaw"
        case .openClaw: "OpenClaw"
        case .trae: "Trae"
        case .cursor: "Cursor"
        case .qoder: "Qoder"
        case .cline: "Cline"
        case .aider: "Aider"
        case .copilot: "GitHub Copilot"
        case .qwen: "Qwen"
        case .kimi: "Kimi"
        case .deepSeek: "DeepSeek"
        case .openCode: "OpenCode"
        }
    }

    var defaultPaths: [String] {
        switch self {
        case .claude: ["~/.claude/projects"]
        case .codex: ["~/.codex/sessions", "~/.codex/archived_sessions"]
        case .piAgent: ["~/.pi/agent/sessions"]
        case .gemini: ["~/.gemini"]
        case .codeBuddy: [
            "~/.codebuddy/projects",
            "~/.codebuddycn/projects",
            "~/.codybuddycn/projects",
            "~/Library/Application Support/CodeBuddy",
            "~/Library/Application Support/CodeBuddyCN",
            "~/Library/Application Support/CodeBuddy CN",
            "~/Library/Application Support/CodyBuddyCN"
        ]
        case .hermes: ["~/.hermes/sessions", "~/.hermes/memories"]
        case .qClaw: ["~/.qclaw/agents"]
        case .openClaw: ["~/.openclaw", "~/Library/Application Support/OpenClaw"]
        case .trae: [
            "~/.trae",
            "~/.trae-cn",
            "~/Library/Application Support/Trae",
            "~/Library/Application Support/TraeCN",
            "~/Library/Application Support/Trae CN"
        ]
        case .cursor: [
            "~/.cursor",
            "~/Library/Application Support/Cursor/User/workspaceStorage",
            "~/Library/Application Support/Cursor/User/globalStorage",
            "~/Library/Application Support/Cursor/User/History"
        ]
        case .qoder: ["~/.qoder", "~/.qoderwork", "~/Library/Application Support/Qoder"]
        case .cline: ["~/.cline", "~/Library/Application Support/Code/User/globalStorage/saoudrizwan.claude-dev", "~/Library/Application Support/Cursor/User/globalStorage/saoudrizwan.claude-dev"]
        case .aider: ["~/.aider"]
        case .copilot: ["~/.config/github-copilot", "~/Library/Application Support/Code/User/globalStorage/github.copilot-chat", "~/Library/Application Support/Cursor/User/globalStorage/github.copilot-chat"]
        case .qwen: ["~/.qwen"]
        case .kimi: ["~/.kimi"]
        case .deepSeek: ["~/.deepseek"]
        case .openCode: ["~/.opencode"]
        }
    }
}

private enum TokenScopeProvider: String, CaseIterable {
    case openAI
    case anthropic
    case google
    case deepSeek
    case qwen
    case openRouter

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .anthropic: "Anthropic"
        case .google: "Google Gemini"
        case .deepSeek: "DeepSeek"
        case .qwen: "Qwen"
        case .openRouter: "OpenRouter"
        }
    }

    var icon: String {
        switch self {
        case .openAI: "sparkles"
        case .anthropic: "a.circle.fill"
        case .google: "g.circle.fill"
        case .deepSeek: "waveform.path.ecg"
        case .qwen: "q.circle.fill"
        case .openRouter: "point.3.connected.trianglepath.dotted"
        }
    }

    var color: Color {
        switch self {
        case .openAI: Theme.Colors.teal
        case .anthropic: Theme.Colors.warning
        case .google: Theme.Colors.info
        case .deepSeek: Theme.Colors.success
        case .qwen: Theme.Colors.purple
        case .openRouter: Theme.Colors.textSecondary
        }
    }

    var placeholder: String {
        switch self {
        case .openAI: "sk-..."
        case .anthropic: "sk-ant-..."
        case .google: "AIza..."
        case .deepSeek: "sk-..."
        case .qwen: "sk-..."
        case .openRouter: "sk-or-..."
        }
    }

    func authDescription(_ localizer: Localizer) -> String {
        switch self {
        case .openAI:
            return localizer.tokenScopeOpenAIAuthDesc
        case .anthropic:
            return localizer.tokenScopeAnthropicAuthDesc
        case .google:
            return localizer.tokenScopeGoogleAuthDesc
        case .deepSeek:
            return localizer.tokenScopeDeepSeekAuthDesc
        case .qwen:
            return localizer.tokenScopeQwenAuthDesc
        case .openRouter:
            return localizer.tokenScopeOpenRouterAuthDesc
        }
    }
}

private enum TokenScopeProviderCredentialStore {
    private static let service = "com.aimaccleaner.app.tokenscope.provider"

    static func hasCredential(for provider: TokenScopeProvider) -> Bool {
        load(provider) != nil
    }

    static func authorizedProviders() -> Set<TokenScopeProvider> {
        Set(TokenScopeProvider.allCases.filter(hasCredential))
    }

    static func save(_ credential: String, for provider: TokenScopeProvider) {
        let data = Data(credential.utf8)
        var query = baseQuery(provider)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    static func load(_ provider: TokenScopeProvider) -> String? {
        var query = baseQuery(provider)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    static func delete(_ provider: TokenScopeProvider) {
        SecItemDelete(baseQuery(provider) as CFDictionary)
    }

    private static func baseQuery(_ provider: TokenScopeProvider) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
    }
}

private struct TokenScopeUsageRecord: Identifiable, Hashable {
    let id: String
    let source: TokenScopeSource
    let timestamp: Date
    let sessionID: String
    let projectPath: String
    let model: String
    let title: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let reasoningTokens: Int
    let costUSD: Double?
    let sourcePath: String

    var totalTokens: Int {
        inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens + reasoningTokens
    }

    var estimatedCost: Double {
        costUSD ?? TokenScopePricing.estimate(
            model: model,
            input: inputTokens,
            output: outputTokens,
            cacheRead: cacheReadTokens,
            cacheWrite: cacheCreationTokens
        )
    }

    var projectName: String {
        let expanded = (projectPath as NSString).expandingTildeInPath
        let name = URL(fileURLWithPath: expanded).lastPathComponent
        return name.isEmpty ? "Unknown" : name
    }
}

private struct TokenScopeTokenTotals: Hashable {
    var input = 0
    var output = 0
    var cacheCreation = 0
    var cacheRead = 0
    var reasoning = 0
    var cost = 0.0

    var cacheTotal: Int { cacheCreation + cacheRead }
    var total: Int { input + output + cacheCreation + cacheRead + reasoning }

    mutating func add(_ record: TokenScopeUsageRecord) {
        input += record.inputTokens
        output += record.outputTokens
        cacheCreation += record.cacheCreationTokens
        cacheRead += record.cacheReadTokens
        reasoning += record.reasoningTokens
        cost += record.estimatedCost
    }
}

private struct TokenScopeDaySummary: Identifiable {
    let id: String
    let date: Date
    let label: String
    let totals: TokenScopeTokenTotals

    var input: Int { totals.input }
    var output: Int { totals.output }
    var cacheTotal: Int { totals.cacheTotal }
}

private struct TokenScopeAgentDaySummary: Identifiable {
    let id: String
    let date: Date
    let label: String
    let sourceName: String
    let totals: TokenScopeTokenTotals
    let color: Color
}

private struct TokenScopeProjectSummary: Identifiable {
    let id: String
    let name: String
    let path: String
    let totals: TokenScopeTokenTotals
    let topModel: String
    let color: Color
}

private struct TokenScopeModelSummary: Identifiable {
    let id: String
    let provider: String
    let model: String
    let totals: TokenScopeTokenTotals
    let color: Color

    var cost: Double { totals.cost }
    var displayName: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? TokenScopeModelName.unknown : model
    }
    var mixText: String {
        "\(TokenScopeFormat.tokens(totals.input))/\(TokenScopeFormat.tokens(totals.output))/\(TokenScopeFormat.tokens(totals.cacheTotal))"
    }
}

private struct TokenScopeSessionSummary: Identifiable {
    let id: String
    let title: String
    let project: String
    let model: String
    let totals: TokenScopeTokenTotals
    let color: Color
}

private struct TokenScopeSummary {
    private let sourceRecords: [TokenScopeUsageRecord]
    let days: [TokenScopeDaySummary]
    let agentDays: [TokenScopeAgentDaySummary]
    let buckets: [TokenScopeDaySummary]
    let agentBuckets: [TokenScopeAgentDaySummary]
    let projects: [TokenScopeProjectSummary]
    let models: [TokenScopeModelSummary]
    let sessions: [TokenScopeSessionSummary]
    let totals: TokenScopeTokenTotals

    init(records: [TokenScopeUsageRecord], range: TokenScopeRange = .month) {
        sourceRecords = records
        let palette = TokenScopePalette.colors
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var allTotals = TokenScopeTokenTotals()
        records.forEach { allTotals.add($0) }
        totals = allTotals

        let computedDays = TokenScopeRange.month.makeBuckets(records: records, calendar: calendar, now: today)
        days = computedDays

        let activeSources = Array(Set(records.map(\.source))).sorted { $0.name < $1.name }
        let computedAgentDays = activeSources.flatMap { source in
            let sourceBuckets = TokenScopeRange.month.makeBuckets(records: records.filter { $0.source == source }, calendar: calendar, now: today)
            return sourceBuckets.map { day in
                return TokenScopeAgentDaySummary(
                    id: "\(TokenScopeFormat.isoDay(day.date))-\(source.rawValue)",
                    date: day.date,
                    label: day.label,
                    sourceName: source.name,
                    totals: day.totals,
                    color: palette[abs(source.rawValue.hashValue) % palette.count]
                )
            }
        }
        agentDays = computedAgentDays
        let computedBuckets = range.makeBuckets(records: records)
        buckets = computedBuckets
        let computedAgentBuckets = activeSources.flatMap { source in
            let sourceBuckets = range.makeBuckets(records: records.filter { $0.source == source })
            return sourceBuckets.map { bucket in
                return TokenScopeAgentDaySummary(
                    id: "\(bucket.id)-\(source.rawValue)",
                    date: bucket.date,
                    label: bucket.label,
                    sourceName: source.name,
                    totals: bucket.totals,
                    color: palette[abs(source.rawValue.hashValue) % palette.count]
                )
            }
        }
        agentBuckets = computedAgentBuckets

        projects = Dictionary(grouping: records, by: \.projectPath)
            .map { path, projectRecords in
                var projectTotals = TokenScopeTokenTotals()
                projectRecords.forEach { projectTotals.add($0) }
                let topModel = Dictionary(grouping: projectRecords, by: \.model)
                    .max { $0.value.count < $1.value.count }?.key ?? "Unknown"
                return TokenScopeProjectSummary(
                    id: path,
                    name: projectRecords.first?.projectName ?? URL(fileURLWithPath: path).lastPathComponent,
                    path: TokenScopeFormat.path(path),
                    totals: projectTotals,
                    topModel: topModel,
                    color: palette[abs(path.hashValue) % palette.count]
                )
            }
            .sorted { $0.totals.total == $1.totals.total ? $0.totals.cost > $1.totals.cost : $0.totals.total > $1.totals.total }

        models = Dictionary(grouping: records, by: \.model)
            .map { model, modelRecords in
                var modelTotals = TokenScopeTokenTotals()
                modelRecords.forEach { modelTotals.add($0) }
                let provider = modelRecords.first?.source.name ?? "Unknown"
                return TokenScopeModelSummary(
                    id: model,
                    provider: provider,
                    model: model,
                    totals: modelTotals,
                    color: palette[abs(model.hashValue) % palette.count]
                )
            }
            .sorted { $0.totals.total == $1.totals.total ? $0.cost > $1.cost : $0.totals.total > $1.totals.total }

        sessions = Dictionary(grouping: records, by: \.sessionID)
            .map { sessionID, sessionRecords in
                var sessionTotals = TokenScopeTokenTotals()
                sessionRecords.forEach { sessionTotals.add($0) }
                let latest = sessionRecords.max { $0.timestamp < $1.timestamp }
                return TokenScopeSessionSummary(
                    id: sessionID,
                    title: latest?.title ?? sessionID,
                    project: latest?.projectName ?? "Unknown",
                    model: latest?.model ?? "Unknown",
                    totals: sessionTotals,
                    color: palette[abs(sessionID.hashValue) % palette.count]
                )
            }
            .sorted { $0.totals.total > $1.totals.total }
    }

    func filtered(range: TokenScopeRange) -> TokenScopeSummary {
        let cutoff = range.cutoffDate()
        return TokenScopeSummary(records: sourceRecords.filter { $0.timestamp >= cutoff }, range: range)
    }

    private init(days: [TokenScopeDaySummary], agentDays: [TokenScopeAgentDaySummary], buckets: [TokenScopeDaySummary], agentBuckets: [TokenScopeAgentDaySummary], projects: [TokenScopeProjectSummary], models: [TokenScopeModelSummary], sessions: [TokenScopeSessionSummary], totals: TokenScopeTokenTotals) {
        self.sourceRecords = []
        self.days = days
        self.agentDays = agentDays
        self.buckets = buckets
        self.agentBuckets = agentBuckets
        self.projects = projects
        self.models = models
        self.sessions = sessions
        self.totals = totals
    }
}

private struct TokenScopeSourceStatus: Identifiable {
    let id: TokenScopeSource
    let source: TokenScopeSource
    let path: String
    let scannedFiles: Int
    let records: Int
    let readable: Bool

    var name: String { source.name }

    var state: TokenScopeSourceState {
        if records > 0 { return .active }
        if readable { return .empty }
        return .needsPermission
    }
}

private enum TokenScopeSourceState {
    case active
    case empty
    case needsPermission

    var icon: String {
        switch self {
        case .active: "checkmark.circle.fill"
        case .empty: "tray.fill"
        case .needsPermission: "lock.trianglebadge.exclamationmark.fill"
        }
    }

    var color: Color {
        switch self {
        case .active: Theme.Colors.success
        case .empty: Theme.Colors.textTertiary
        case .needsPermission: Theme.Colors.warning
        }
    }

    func label(_ localizer: Localizer) -> String {
        switch self {
        case .active: localizer.tokenScopeActive
        case .empty: localizer.tokenScopeNoRecords
        case .needsPermission: localizer.tokenScopeNeedsPermission
        }
    }
}

private enum TokenScopeRange: CaseIterable, Hashable {
    case today
    case week
    case month

    var days: Int {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        }
    }

    func label(_ localizer: Localizer) -> String {
        switch self {
        case .today: localizer.todayLabel
        case .week: localizer.tokenScopeSevenDays
        case .month: localizer.tokenScopeThirtyDays
        }
    }

    var axisComponent: Calendar.Component {
        self == .today ? .hour : .day
    }

    var axisStride: Int {
        switch self {
        case .today: 3
        case .week: 1
        case .month: 3
        }
    }

    func cutoffDate(calendar: Calendar = .current, now: Date = Date()) -> Date {
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -days + 1, to: today) ?? today
    }

    func axisLabel(_ date: Date) -> String {
        switch self {
        case .today:
            return TokenScopeFormat.hourLabel(date)
        case .week, .month:
            return TokenScopeFormat.dayLabel(date)
        }
    }

    func makeBuckets(records: [TokenScopeUsageRecord], calendar: Calendar = .current, now: Date = Date()) -> [TokenScopeDaySummary] {
        let bucketDates = bucketDates(calendar: calendar, now: now)
        let bucketSet = Set(bucketDates)
        var totalsByDate: [Date: TokenScopeTokenTotals] = [:]

        for record in records {
            guard let bucket = bucketStart(for: record.timestamp, calendar: calendar),
                  bucketSet.contains(bucket) else {
                continue
            }
            totalsByDate[bucket, default: TokenScopeTokenTotals()].add(record)
        }

        return bucketDates.map { date in
            TokenScopeDaySummary(
                id: self == .today ? TokenScopeFormat.isoHour(date) : TokenScopeFormat.isoDay(date),
                date: date,
                label: self == .today ? TokenScopeFormat.hourLabel(date) : TokenScopeFormat.dayLabel(date),
                totals: totalsByDate[date] ?? TokenScopeTokenTotals()
            )
        }
    }

    func contains(_ timestamp: Date, in bucketDate: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .today:
            return calendar.component(.year, from: timestamp) == calendar.component(.year, from: bucketDate)
                && calendar.component(.month, from: timestamp) == calendar.component(.month, from: bucketDate)
                && calendar.component(.day, from: timestamp) == calendar.component(.day, from: bucketDate)
                && calendar.component(.hour, from: timestamp) == calendar.component(.hour, from: bucketDate)
        case .week, .month:
            return calendar.isDate(timestamp, inSameDayAs: bucketDate)
        }
    }

    private func bucketDates(calendar: Calendar, now: Date) -> [Date] {
        switch self {
        case .today:
            let today = calendar.startOfDay(for: now)
            return (0..<24).map { calendar.date(byAdding: .hour, value: $0, to: today) ?? today }
        case .week, .month:
            let today = calendar.startOfDay(for: now)
            return (0..<days).reversed().map { calendar.date(byAdding: .day, value: -$0, to: today) ?? today }
        }
    }

    private func bucketStart(for date: Date, calendar: Calendar) -> Date? {
        switch self {
        case .today:
            return calendar.dateInterval(of: .hour, for: date)?.start
        case .week, .month:
            return calendar.startOfDay(for: date)
        }
    }

    static var emptySummaries: [TokenScopeRange: TokenScopeSummary] {
        cachedSummaries(for: [])
    }

    static func cachedSummaries(for records: [TokenScopeUsageRecord]) -> [TokenScopeRange: TokenScopeSummary] {
        Dictionary(uniqueKeysWithValues: allCases.map { range in
            let cutoff = range.cutoffDate()
            let scopedRecords = records.filter { $0.timestamp >= cutoff }
            return (range, TokenScopeSummary(records: scopedRecords, range: range))
        })
    }
}

private enum TokenScopeTab: CaseIterable {
    case overview
    case projects
    case models
    case sessions
    case sources

    var icon: String {
        switch self {
        case .overview: "chart.bar.xaxis"
        case .projects: "folder.fill"
        case .models: "cpu.fill"
        case .sessions: "list.bullet.rectangle.fill"
        case .sources: "externaldrive.connected.to.line.below.fill"
        }
    }

    func label(_ localizer: Localizer) -> String {
        switch self {
        case .overview: localizer.tokenScopeOverview
        case .projects: localizer.tokenScopeProjects
        case .models: localizer.tokenScopeModels
        case .sessions: localizer.tokenScopeSessions
        case .sources: localizer.tokenScopeSources
        }
    }
}

// MARK: - Scanner

private struct TokenScopeScanResult {
    let records: [TokenScopeUsageRecord]
    let sources: [TokenScopeSourceStatus]
}

private struct TokenScopeFileFingerprint: Equatable {
    let size: Int
    let modifiedAt: TimeInterval

    init?(file: URL) {
        guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        size = values.fileSize ?? 0
        modifiedAt = values.contentModificationDate?.timeIntervalSince1970 ?? 0
    }
}

private struct TokenScopeFileCacheEntry {
    let fingerprint: TokenScopeFileFingerprint
    let records: [TokenScopeUsageRecord]
}

private final class TokenScopeScanner {
    private let fileManager = FileManager.default
    private let maxFilesPerSource = 80
    private let maxVisitedItemsPerSource = 1200
    private let maxDirectoryDepth = 10
    private let maxBytesPerFile = 4 * 1024 * 1024
    private let maxCodexBytesPerFile = 256 * 1024 * 1024
    private let fileCacheLock = NSLock()
    private var fileCache: [String: TokenScopeFileCacheEntry] = [:]

    func defaultRoots() -> [URL] {
        let builtInRoots = TokenScopeSource.allCases.flatMap { $0.defaultPaths }.map(expandedURL)
        return uniqueRoots(builtInRoots + codexHomePaths().map(expandedURL))
    }

    func defaultSourceStatuses() -> [TokenScopeSourceStatus] {
        TokenScopeSource.allCases.map {
            let readablePaths = $0.defaultPaths.filter { fileManager.isReadableFile(atPath: expandedURL($0).path) }
            return TokenScopeSourceStatus(id: $0, source: $0, path: readablePaths.first ?? $0.defaultPaths.first ?? "", scannedFiles: 0, records: 0, readable: !readablePaths.isEmpty)
        }
    }

    func scan(roots: [URL]) -> TokenScopeScanResult {
        var records: [TokenScopeUsageRecord] = []
        var statuses: [TokenScopeSourceStatus] = []

        for root in roots {
            let source = source(for: root)
            let didStart = root.startAccessingSecurityScopedResource()
            defer {
                if didStart { root.stopAccessingSecurityScopedResource() }
            }

            let files = candidateFiles(root: root, source: source)
            let sourceRecords = files.flatMap { parse(file: $0, source: source, root: root) }
            records.append(contentsOf: sourceRecords)
            if sourceRecords.isEmpty {
                statuses.append(TokenScopeSourceStatus(
                    id: source,
                    source: source,
                    path: TokenScopeFormat.path(root.path),
                    scannedFiles: files.count,
                    records: 0,
                    readable: fileManager.isReadableFile(atPath: root.path)
                ))
            } else {
                for (actualSource, groupedRecords) in Dictionary(grouping: sourceRecords, by: \.source) {
                    let sourceFileCount = Set(groupedRecords.map(\.sourcePath)).count
                    statuses.append(TokenScopeSourceStatus(
                        id: actualSource,
                        source: actualSource,
                        path: TokenScopeFormat.path(root.path),
                        scannedFiles: sourceFileCount,
                        records: groupedRecords.count,
                        readable: fileManager.isReadableFile(atPath: root.path)
                    ))
                }
            }
        }

        return TokenScopeScanResult(records: dedupe(records), sources: mergeStatuses(statuses))
    }

    private func candidateFiles(root: URL, source: TokenScopeSource) -> [URL] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        var visited = 0

        for case let url as URL in enumerator {
            visited += 1
            if visited > maxVisitedItemsPerSource { break }
            if directoryDepth(of: url, relativeTo: root) > maxDirectoryDepth {
                enumerator.skipDescendants()
                continue
            }
            if shouldSkip(url) {
                enumerator.skipDescendants()
                continue
            }
            let ext = url.pathExtension.lowercased()
            let allowed = allowedExtensions(for: source).contains(ext)
            guard allowed else { continue }

            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            if let size = values?.fileSize, size > maxBytes(for: source) { continue }
            files.append(url)
        }

        return Array(files.sorted {
            let lhs = ((try? $0.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
            let rhs = ((try? $1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? .distantPast
            return lhs > rhs
        }.prefix(maxFilesPerSource))
    }

    private func directoryDepth(of url: URL, relativeTo root: URL) -> Int {
        let rootComponents = root.standardizedFileURL.pathComponents.count
        return max(url.standardizedFileURL.pathComponents.count - rootComponents, 0)
    }

    private func parse(file: URL, source: TokenScopeSource, root: URL) -> [TokenScopeUsageRecord] {
        if let cached = cachedRecords(for: file) {
            return cached
        }

        let parsed: [TokenScopeUsageRecord]
        switch source {
        case .claude:
            parsed = TokenScopeClaudeAdapter.parse(file: file, source: claudeCompatibleSource(for: file))
        case .codex, .piAgent:
            parsed = TokenScopeCodexAdapter.parse(file: file, sessionsRoot: root, source: source)
        case .gemini:
            parsed = TokenScopeGeminiAdapter.parse(file: file)
        case .codeBuddy:
            if file.pathExtension.lowercased() == "vscdb" {
                parsed = TokenScopeCodeBuddyStateAdapter.parse(file: file)
            } else {
                parsed = TokenScopeClaudeAdapter.parse(file: file, source: .codeBuddy)
            }
        case .trae:
            if file.pathExtension.lowercased() == "vscdb" {
                parsed = TokenScopeTraeStateAdapter.parse(file: file, root: root)
            } else {
                parsed = TokenScopeGenericAdapter.parse(file: file, source: source, root: root)
            }
        case .hermes, .qClaw, .openClaw, .cursor, .qoder, .cline, .aider, .copilot, .qwen, .kimi, .deepSeek, .openCode:
            parsed = TokenScopeGenericAdapter.parse(file: file, source: source, root: root)
        }

        cache(records: parsed, for: file)
        return parsed
    }

    private func source(for root: URL) -> TokenScopeSource {
        let path = root.path.lowercased()
        if path.contains("codebuddy") || path.contains("codybuddy") { return .codeBuddy }
        if path.contains("cursor") { return .cursor }
        if path.contains("qoder") { return .qoder }
        if path.contains("cline") || path.contains("claude-dev") { return .cline }
        if path.contains("aider") { return .aider }
        if path.contains("copilot") { return .copilot }
        if path.contains("qwen") { return .qwen }
        if path.contains("kimi") { return .kimi }
        if path.contains("deepseek") { return .deepSeek }
        if path.contains("opencode") { return .openCode }
        if path.contains(".pi/agent") || path.contains("/pi/agent") { return .piAgent }
        if path.contains("hermes") { return .hermes }
        if path.contains("qclaw") { return .qClaw }
        if path.contains("openclaw") { return .openClaw }
        if path.contains("trae") { return .trae }
        if path.contains(".gemini") { return .gemini }
        if path.contains(".claude") { return .claude }
        return .codex
    }

    private func claudeCompatibleSource(for file: URL) -> TokenScopeSource {
        let path = file.path.lowercased()
        if path.contains("codebuddy") || path.contains("codybuddy") { return .codeBuddy }
        if path.contains("cursor") { return .cursor }
        if path.contains("qoder") { return .qoder }
        if path.contains("cline") || path.contains("claude-dev") { return .cline }
        if path.contains("aider") { return .aider }
        if path.contains("copilot") { return .copilot }
        if path.contains("qwen") { return .qwen }
        if path.contains("kimi") { return .kimi }
        if path.contains("deepseek") { return .deepSeek }
        if path.contains("opencode") { return .openCode }
        if path.contains("hermes-sandbox") || path.contains("hermes") { return .hermes }
        if path.contains("qclaw") { return .qClaw }
        if path.contains("openclaw") { return .openClaw }
        if path.contains("trae") { return .trae }
        return .claude
    }

    private func shouldSkip(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        if ["cache", "caches", "cacheddata", "cached_data", "node_modules", ".git", "deriveddata", "vendor", "plugins", "skills", "tmp", "config", "backups", "backup", "identity", "extensions", "workspace", ".auto-memory", "browser"].contains(name) {
            return true
        }
        return ["package.json", "package-lock.json", "tsconfig.json", "settings.json", "channel-defaults.json", "device.json", "device-auth.json"].contains(name)
    }

    private func allowedExtensions(for source: TokenScopeSource) -> Set<String> {
        switch source {
        case .claude, .codex, .piAgent:
            return ["jsonl"]
        case .codeBuddy:
            return ["jsonl", "vscdb"]
        case .gemini, .hermes, .qClaw, .openClaw, .trae, .cursor, .qoder, .cline, .aider, .copilot, .qwen, .kimi, .deepSeek, .openCode:
            return ["json", "jsonl", "vscdb", "log"]
        }
    }

    private func maxBytes(for source: TokenScopeSource) -> Int {
        (source == .codex || source == .piAgent) ? maxCodexBytesPerFile : maxBytesPerFile
    }

    private func cachedRecords(for file: URL) -> [TokenScopeUsageRecord]? {
        guard let fingerprint = TokenScopeFileFingerprint(file: file),
              let cached = cacheEntry(for: file),
              cached.fingerprint == fingerprint else {
            return nil
        }
        return cached.records
    }

    private func cache(records: [TokenScopeUsageRecord], for file: URL) {
        guard let fingerprint = TokenScopeFileFingerprint(file: file) else { return }
        fileCacheLock.lock()
        defer { fileCacheLock.unlock() }
        fileCache[file.path] = TokenScopeFileCacheEntry(fingerprint: fingerprint, records: records)
    }

    private func cacheEntry(for file: URL) -> TokenScopeFileCacheEntry? {
        fileCacheLock.lock()
        defer { fileCacheLock.unlock() }
        return fileCache[file.path]
    }

    private func expandedURL(_ path: String) -> URL {
        if path == "~" {
            return URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
        }
        if path.hasPrefix("~/") {
            return URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
                .appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private func codexHomePaths() -> [String] {
        guard let codexHome = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !codexHome.isEmpty else {
            return []
        }
        return [
            "\(codexHome)/sessions",
            "\(codexHome)/archived_sessions"
        ]
    }

    private func uniqueRoots(_ roots: [URL]) -> [URL] {
        var seen = Set<String>()
        return roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func dedupe(_ records: [TokenScopeUsageRecord]) -> [TokenScopeUsageRecord] {
        var seen = Set<String>()
        return records.filter { record in
            let key: String
            if record.source == .codex || record.source == .piAgent {
                key = [
                    record.source.rawValue,
                    record.sessionID,
                    record.id.components(separatedBy: ":").dropFirst(2).first ?? "",
                    record.model,
                    String(Int(record.timestamp.timeIntervalSince1970)),
                    String(record.inputTokens),
                    String(record.cacheReadTokens),
                    String(record.outputTokens),
                    String(record.reasoningTokens),
                    String(record.totalTokens)
                ].joined(separator: "|")
            } else {
                key = record.id
            }
            return seen.insert(key).inserted
        }
    }

    private func mergeStatuses(_ statuses: [TokenScopeSourceStatus]) -> [TokenScopeSourceStatus] {
        Dictionary(grouping: statuses, by: \.source)
            .map { source, grouped in
                TokenScopeSourceStatus(
                    id: source,
                    source: source,
                    path: grouped.map(\.path).joined(separator: ", "),
                    scannedFiles: grouped.reduce(0) { $0 + $1.scannedFiles },
                    records: grouped.reduce(0) { $0 + $1.records },
                    readable: grouped.contains { $0.readable }
                )
            }
            .sorted { $0.source.name < $1.source.name }
    }
}

// MARK: - Adapters

private enum TokenScopeClaudeAdapter {
    static func parse(file: URL, source: TokenScopeSource) -> [TokenScopeUsageRecord] {
        let modified = TokenScopeJSON.fileModifiedDate(file)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        let project = inferProject(from: file)

        return text.split(separator: "\n").compactMap { line in
            guard let object = TokenScopeJSON.object(String(line)) else { return nil }
            let event = normalizedEntry(object)
            guard let usage = TokenScopeUsage.fromClaudeObject(event) else { return nil }
            let timestamp = TokenScopeJSON.date(event, keys: ["timestamp"]) ?? modified
            let model = TokenScopeModelName.best(in: event) ?? TokenScopeModelName.unknown
            let messageID = TokenScopeJSON.string(event, path: ["message", "id"]) ?? TokenScopeJSON.string(event, keys: ["requestId", "request_id"]) ?? file.lastPathComponent
            let sessionID = TokenScopeJSON.string(event, keys: ["sessionId", "session_id"]) ?? file.deletingPathExtension().lastPathComponent
            return TokenScopeUsageRecord(
                id: "\(source.rawValue):\(messageID):\(usage.hashValue)",
                source: source,
                timestamp: timestamp,
                sessionID: sessionID,
                projectPath: project,
                model: model,
                title: file.deletingPathExtension().lastPathComponent,
                inputTokens: usage.input,
                outputTokens: usage.output,
                cacheCreationTokens: usage.cacheCreation,
                cacheReadTokens: usage.cacheRead,
                reasoningTokens: usage.reasoning,
                costUSD: TokenScopeJSON.double(event, keys: ["costUSD", "cost_usd"]),
                sourcePath: TokenScopeFormat.path(file.path)
            )
        }
    }

    private static func normalizedEntry(_ object: Any) -> Any {
        TokenScopeJSON.value(object, path: ["data", "message"]) ?? object
    }

    private static func inferProject(from file: URL) -> String {
        let parts = file.pathComponents
        guard let index = parts.lastIndex(of: "projects"), parts.indices.contains(index + 1) else {
            return file.deletingLastPathComponent().path
        }
        return parts[index + 1].replacingOccurrences(of: "-", with: "/")
    }
}

private enum TokenScopeCodexAdapter {
    static func parse(file: URL, sessionsRoot: URL, source: TokenScopeSource) -> [TokenScopeUsageRecord] {
        let modified = TokenScopeJSON.fileModifiedDate(file)
        var sessionID = sessionID(for: file, root: sessionsRoot)
        var records: [TokenScopeUsageRecord] = []
        var currentModel: String?
        var currentProject = inferProject(from: file, root: sessionsRoot)
        var previousTotals: TokenScopeUsage?
        var currentTurnID: String?

        scanJSONLLines(file: file) { object in
            guard let type = TokenScopeJSON.string(object, keys: ["type"]) else { return }

            if type == "session_meta" {
                sessionID = TokenScopeJSON.string(object, path: ["payload", "session_id"])
                    ?? TokenScopeJSON.string(object, path: ["payload", "sessionId"])
                    ?? TokenScopeJSON.string(object, path: ["payload", "id"])
                    ?? TokenScopeJSON.string(object, keys: ["session_id", "sessionId", "id"])
                    ?? sessionID
                currentProject = TokenScopeJSON.string(object, path: ["payload", "cwd"]) ?? currentProject
                currentModel = TokenScopeModelName.best(in: object) ?? currentModel
                return
            }

            if type == "turn_context" {
                currentModel = TokenScopeModelName.normalize(TokenScopeJSON.string(object, path: ["payload", "model"])) ?? currentModel
                currentProject = TokenScopeJSON.string(object, path: ["payload", "cwd"]) ?? currentProject
                return
            }

            guard type == "event_msg" else { return }
            let payloadType = TokenScopeJSON.string(object, path: ["payload", "type"])
            if payloadType == "task_started" {
                currentTurnID = codexTurnID(from: TokenScopeJSON.value(object, path: ["payload"]))
                return
            }

            if payloadType == "token_count" {
                guard let info = TokenScopeJSON.value(object, path: ["payload", "info"]) else { return }
                guard let usage = usageDelta(info: info, previousTotals: &previousTotals), usage.total > 0 else { return }
                let timestamp = TokenScopeJSON.date(object, keys: ["timestamp"]) ?? modified
                let model = currentModel
                    ?? TokenScopeModelName.normalize(TokenScopeJSON.string(info, keys: ["model", "model_name"]))
                    ?? TokenScopeModelName.normalize(TokenScopeJSON.string(object, path: ["payload", "model"]))
                    ?? currentModel
                    ?? "gpt-5"
                currentModel = model
                let turnID = codexTurnID(from: TokenScopeJSON.value(object, path: ["payload"])) ?? currentTurnID
                records.append(record(
                    file: file,
                    source: source,
                    sessionID: sessionID,
                    turnID: turnID,
                    project: currentProject,
                    timestamp: timestamp,
                    model: model,
                    usage: usage,
                    title: file.deletingPathExtension().lastPathComponent))
                return
            }

            if let usageObject = TokenScopeJSON.firstValue(object, paths: [["usage"], ["data", "usage"], ["result", "usage"], ["response", "usage"]]),
               let usage = TokenScopeUsage.fromCodexObject(usageObject), usage.total > 0 {
                let timestamp = TokenScopeJSON.date(object, keys: ["timestamp", "created_at", "createdAt"]) ?? modified
                let model = currentModel
                    ?? TokenScopeModelName.normalize(TokenScopeJSON.firstString(object, paths: [["model"], ["model_name"], ["data", "model"], ["data", "model_name"], ["result", "model"], ["response", "model"]]))
                    ?? "gpt-5"
                currentModel = model
                let eventProject = TokenScopeJSON.firstString(object, paths: [["cwd"], ["workdir"], ["workspace"], ["project_path"], ["data", "cwd"], ["result", "cwd"], ["response", "cwd"]]) ?? currentProject
                records.append(record(
                    file: file,
                    source: source,
                    sessionID: sessionID,
                    turnID: currentTurnID,
                    project: eventProject,
                    timestamp: timestamp,
                    model: model,
                    usage: usage,
                    title: file.deletingPathExtension().lastPathComponent))
            }
        }

        return records
    }

    private static func usageDelta(info: Any?, previousTotals: inout TokenScopeUsage?) -> TokenScopeUsage? {
        let last = TokenScopeJSON.value(info as Any, path: ["last_token_usage"]).flatMap(TokenScopeUsage.fromCodexObject)
        let total = TokenScopeJSON.value(info as Any, path: ["total_token_usage"]).flatMap(TokenScopeUsage.fromCodexObject)
        if let total, let previous = previousTotals {
            let result: TokenScopeUsage?
            if total.total < previous.total {
                result = last ?? total
            } else {
                let delta = total.delta(from: previous)
                result = delta.total > 0 ? delta : nil
            }
            previousTotals = total
            return result
        }
        if let total {
            previousTotals = total
            return total
        }
        return last
    }

    private static func record(file: URL, source: TokenScopeSource, sessionID: String, turnID: String?, project: String, timestamp: Date, model: String, usage: TokenScopeUsage, title: String) -> TokenScopeUsageRecord {
        let scopedTurnID = turnID ?? String(Int(timestamp.timeIntervalSince1970 * 1000))
        return TokenScopeUsageRecord(
            id: "\(source.rawValue):\(sessionID):\(scopedTurnID):\(model):\(usage.hashValue)",
            source: source,
            timestamp: timestamp,
            sessionID: sessionID,
            projectPath: project,
            model: model,
            title: title,
            inputTokens: usage.input,
            outputTokens: usage.output,
            cacheCreationTokens: usage.cacheCreation,
            cacheReadTokens: usage.cacheRead,
            reasoningTokens: usage.reasoning,
            costUSD: nil,
            sourcePath: TokenScopeFormat.path(file.path)
        )
    }

    private static func sessionID(for file: URL, root: URL) -> String {
        let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
        return URL(fileURLWithPath: relative).deletingPathExtension().path
    }

    private static func inferProject(from file: URL, root: URL) -> String {
        return root.path
    }

    private static func codexTurnID(from object: Any?) -> String? {
        TokenScopeJSON.string(object, keys: ["turn_id", "turnId", "id"])
            ?? TokenScopeJSON.string(object, path: ["turn", "id"])
            ?? TokenScopeJSON.string(object, path: ["payload", "turn_id"])
            ?? TokenScopeJSON.string(object, path: ["payload", "turn", "id"])
    }

    private static func scanJSONLLines(file: URL, onObject: ([String: Any]) -> Void) {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return }
        defer { try? handle.close() }

        let snapshotSize = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let maxScanBytes = 12 * 1024 * 1024
        let newline = UInt8(ascii: "\n")
        let startOffset = snapshotSize > maxScanBytes ? UInt64(snapshotSize - maxScanBytes) : 0
        if startOffset > 0 {
            try? handle.seek(toOffset: startOffset)
            var skippedBytes = 0
            while skippedBytes < 256 * 1024 {
                guard let byte = try? handle.read(upToCount: 1), !byte.isEmpty else { break }
                skippedBytes += byte.count
                if byte.first == newline { break }
            }
        }
        var remainingBytes = startOffset > 0 ? min(maxScanBytes, snapshotSize) : snapshotSize
        var buffer = Data()
        buffer.reserveCapacity(64 * 1024)

        func flush(_ line: Data) {
            guard !line.isEmpty else {
                return
            }

            let prefix = line.prefix(4096)
            guard let prefixText = String(data: prefix, encoding: .utf8) else { return }

            if prefixText.contains("\"type\":\"event_msg\""),
               prefixText.contains("\"payload\":{\"type\":\"token_count\""),
               let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
                onObject(object)
                return
            }

            guard prefixText.contains("\"type\":\"session_meta\"") || prefixText.contains("\"type\":\"turn_context\"") else {
                return
            }

            if let context = lightweightContextObject(from: line) {
                onObject(context)
            }
        }

        while remainingBytes > 0 {
            let readSize = min(256 * 1024, remainingBytes)
            guard let chunk = try? handle.read(upToCount: readSize), !chunk.isEmpty else {
                break
            }
            remainingBytes -= chunk.count

            var start = chunk.startIndex
            for index in chunk.indices where chunk[index] == newline {
                buffer.append(chunk[start..<index])
                flush(buffer)
                buffer.removeAll(keepingCapacity: true)
                start = chunk.index(after: index)
            }
            if start < chunk.endIndex {
                buffer.append(chunk[start..<chunk.endIndex])
            }
        }
        flush(buffer)
    }

    private static func lightweightContextObject(from line: Data) -> [String: Any]? {
        let sample = line.prefix(96 * 1024)
        guard let text = String(data: sample, encoding: .utf8) else { return nil }

        if text.contains("\"type\":\"session_meta\"") {
            var payload: [String: Any] = [:]
            if let id = firstJSONStringValue(for: "id", in: text) {
                payload["id"] = id
            }
            if let sessionID = firstJSONStringValue(for: "session_id", in: text) {
                payload["session_id"] = sessionID
            }
            if let cwd = firstJSONStringValue(for: "cwd", in: text) {
                payload["cwd"] = cwd
            }
            if let model = firstJSONStringValue(for: "model", in: text) {
                payload["model"] = model
            }
            return ["type": "session_meta", "payload": payload]
        }

        if text.contains("\"type\":\"turn_context\"") {
            var payload: [String: Any] = [:]
            if let turnID = firstJSONStringValue(for: "turn_id", in: text) {
                payload["turn_id"] = turnID
            }
            if let cwd = firstJSONStringValue(for: "cwd", in: text) {
                payload["cwd"] = cwd
            }
            if let model = firstJSONStringValue(for: "model", in: text) {
                payload["model"] = model
            }
            return ["type": "turn_context", "payload": payload]
        }

        return nil
    }

    private static func firstJSONStringValue(for key: String, in text: String) -> String? {
        let pattern = "\"\(NSRegularExpression.escapedPattern(for: key))\"\\s*:\\s*\"((?:[^\"\\\\]|\\\\.)*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text) else {
            return nil
        }

        let raw = String(text[range])
        let quoted = "\"\(raw)\""
        if let data = quoted.data(using: .utf8),
           let unescaped = try? JSONSerialization.jsonObject(with: data) as? String {
            return unescaped
        }
        return raw
    }
}

private enum TokenScopeGeminiAdapter {
    static func parse(file: URL) -> [TokenScopeUsageRecord] {
        let modified = TokenScopeJSON.fileModifiedDate(file)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        if file.pathExtension.lowercased() == "jsonl" {
            return text.split(separator: "\n").flatMap { line in
                TokenScopeJSON.object(String(line)).map { parseObject($0, file: file, fallbackDate: modified) } ?? []
            }
        }
        guard let object = TokenScopeJSON.object(text) else { return [] }
        return parseObject(object, file: file, fallbackDate: modified)
    }

    private static func parseObject(_ object: Any, file: URL, fallbackDate: Date) -> [TokenScopeUsageRecord] {
        if let messages = TokenScopeJSON.array(object, keys: ["messages"]) {
            return messages.flatMap { parseObject($0, file: file, fallbackDate: fallbackDate) }
        }
        if let models = TokenScopeJSON.dictionary(TokenScopeJSON.value(object, path: ["stats", "models"]) as Any) {
            return models.compactMap { model, value in
                guard let usage = TokenScopeUsage.fromGeminiObject(TokenScopeJSON.value(value, path: ["tokens"]) ?? value), usage.total > 0 else { return nil }
                return record(object: object, file: file, fallbackDate: fallbackDate, model: model, usage: usage)
            }
        }
        let tokenObject = TokenScopeJSON.value(object, path: ["tokens"]) ?? TokenScopeJSON.value(object, path: ["stats"]) ?? object
        guard let usage = TokenScopeUsage.fromGeminiObject(tokenObject), usage.total > 0 else { return [] }
        let model = TokenScopeJSON.string(object, keys: ["model", "model_name"]) ?? "Gemini"
        return [record(object: object, file: file, fallbackDate: fallbackDate, model: model, usage: usage)]
    }

    private static func record(object: Any, file: URL, fallbackDate: Date, model: String, usage: TokenScopeUsage) -> TokenScopeUsageRecord {
        let sessionID = TokenScopeJSON.string(object, keys: ["sessionId", "session_id"]) ?? file.deletingPathExtension().lastPathComponent
        let timestamp = TokenScopeJSON.date(object, keys: ["timestamp", "created_at", "startTime", "lastUpdated"]) ?? fallbackDate
        return TokenScopeUsageRecord(
            id: "gemini:\(sessionID):\(timestamp.timeIntervalSince1970):\(model):\(usage.hashValue)",
            source: .gemini,
            timestamp: timestamp,
            sessionID: sessionID,
            projectPath: TokenScopeJSON.string(object, keys: ["cwd", "workspace", "project_path"]) ?? file.deletingLastPathComponent().path,
            model: model,
            title: sessionID,
            inputTokens: usage.input,
            outputTokens: usage.output,
            cacheCreationTokens: usage.cacheCreation,
            cacheReadTokens: usage.cacheRead,
            reasoningTokens: usage.reasoning,
            costUSD: nil,
            sourcePath: TokenScopeFormat.path(file.path)
        )
    }
}

private enum TokenScopeGenericAdapter {
    static func parse(file: URL, source: TokenScopeSource, root: URL) -> [TokenScopeUsageRecord] {
        let modified = TokenScopeJSON.fileModifiedDate(file)
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return [] }
        if file.pathExtension.lowercased() == "jsonl" {
            var currentProject = inferProject(file: file, root: root)
            var currentModel: String?
            var usageRecords: [TokenScopeUsageRecord] = []
            var activityRecords: [TokenScopeUsageRecord] = []
            for line in text.split(separator: "\n") {
                guard let object = TokenScopeJSON.object(String(line)) else { continue }
                updateContext(from: object, currentProject: &currentProject, currentModel: &currentModel)
                if let record = record(from: object, file: file, source: source, root: root, fallbackDate: modified, fallbackProject: currentProject, fallbackModel: currentModel) {
                    usageRecords.append(record)
                } else if let activity = activityRecord(from: object, file: file, source: source, fallbackDate: modified, fallbackProject: currentProject, fallbackModel: currentModel) {
                    activityRecords.append(activity)
                }
            }
            return usageRecords.isEmpty ? Array(activityRecords.prefix(160)) : usageRecords
        }
        guard let object = TokenScopeJSON.object(text) else { return [] }
        if let array = object as? [Any] {
            var currentProject = inferProject(file: file, root: root)
            var currentModel: String?
            var usageRecords: [TokenScopeUsageRecord] = []
            var activityRecords: [TokenScopeUsageRecord] = []
            for item in array {
                updateContext(from: item, currentProject: &currentProject, currentModel: &currentModel)
                if let record = record(from: item, file: file, source: source, root: root, fallbackDate: modified, fallbackProject: currentProject, fallbackModel: currentModel) {
                    usageRecords.append(record)
                } else if let activity = activityRecord(from: item, file: file, source: source, fallbackDate: modified, fallbackProject: currentProject, fallbackModel: currentModel) {
                    activityRecords.append(activity)
                }
            }
            return usageRecords.isEmpty ? Array(activityRecords.prefix(160)) : usageRecords
        }
        if let messages = TokenScopeJSON.array(object, keys: ["messages", "events", "records", "sessions"]) {
            var currentProject = TokenScopeJSON.firstString(object, paths: [["cwd"], ["workspace"], ["workspacePath"], ["project_path"], ["projectPath"]]) ?? inferProject(file: file, root: root)
            var currentModel = TokenScopeModelName.best(in: object)
            var usageRecords: [TokenScopeUsageRecord] = []
            var activityRecords: [TokenScopeUsageRecord] = []
            for item in messages {
                updateContext(from: item, currentProject: &currentProject, currentModel: &currentModel)
                if let record = record(from: item, file: file, source: source, root: root, fallbackDate: modified, fallbackProject: currentProject, fallbackModel: currentModel) {
                    usageRecords.append(record)
                } else if let activity = activityRecord(from: item, file: file, source: source, fallbackDate: modified, fallbackProject: currentProject, fallbackModel: currentModel) {
                    activityRecords.append(activity)
                }
            }
            if !usageRecords.isEmpty { return usageRecords }
            if !activityRecords.isEmpty { return Array(activityRecords.prefix(160)) }
        }
        let project = TokenScopeJSON.firstString(object, paths: [["cwd"], ["workspace"], ["workspacePath"], ["project_path"], ["projectPath"]]) ?? inferProject(file: file, root: root)
        let model = TokenScopeModelName.best(in: object)
        if let usage = record(from: object, file: file, source: source, root: root, fallbackDate: modified, fallbackProject: project, fallbackModel: model) {
            return [usage]
        }
        return activityRecord(from: object, file: file, source: source, fallbackDate: modified, fallbackProject: project, fallbackModel: model).map { [$0] } ?? []
    }

    private static func updateContext(from object: Any, currentProject: inout String, currentModel: inout String?) {
        if let project = TokenScopeJSON.firstString(object, paths: [
            ["cwd"],
            ["workspace"],
            ["workspacePath"],
            ["project_path"],
            ["projectPath"],
            ["details", "cwd"],
            ["message", "cwd"]
        ]) {
            currentProject = project
        }
        if let model = TokenScopeModelName.best(in: object) {
            currentModel = model
        }
        if let snapshotModel = TokenScopeJSON.firstString(object, paths: [["data", "modelId"], ["data", "model_id"]]),
           let normalized = TokenScopeModelName.normalize(snapshotModel) {
            currentModel = normalized
        }
        if let modelID = TokenScopeJSON.string(object, keys: ["modelId", "model_id"]),
           let normalized = TokenScopeModelName.normalize(modelID) {
            currentModel = normalized
        }
    }

    private static func record(from object: Any, file: URL, source: TokenScopeSource, root: URL, fallbackDate: Date, fallbackProject: String, fallbackModel: String?) -> TokenScopeUsageRecord? {
        guard isUsageEvent(object), let usage = TokenScopeUsage.fromGenericObject(object), usage.total > 0 else { return nil }
        let timestamp = TokenScopeJSON.date(object, keys: ["timestamp", "created_at", "createdAt", "time", "date"]) ?? fallbackDate
        let sessionID = TokenScopeJSON.string(object, keys: ["sessionId", "session_id", "conversationId", "conversation_id", "id"]) ?? file.deletingPathExtension().lastPathComponent
        let model = TokenScopeModelName.best(in: object) ?? fallbackModel ?? TokenScopeModelName.unknown
        let project = TokenScopeJSON.firstString(object, paths: [["cwd"], ["workspace"], ["workspacePath"], ["project_path"], ["projectPath"], ["details", "cwd"], ["message", "cwd"]]) ?? fallbackProject
        let title = TokenScopeJSON.string(object, keys: ["title", "summary", "name"]) ?? file.deletingPathExtension().lastPathComponent
        return TokenScopeUsageRecord(
            id: "\(source.rawValue):\(sessionID):\(timestamp.timeIntervalSince1970):\(model):\(usage.hashValue)",
            source: source,
            timestamp: timestamp,
            sessionID: sessionID,
            projectPath: project,
            model: model,
            title: title,
            inputTokens: usage.input,
            outputTokens: usage.output,
            cacheCreationTokens: usage.cacheCreation,
            cacheReadTokens: usage.cacheRead,
            reasoningTokens: usage.reasoning,
            costUSD: TokenScopeJSON.firstDouble(object, paths: [["costUSD"], ["cost_usd"], ["cost"], ["usage", "cost", "total"], ["message", "usage", "cost", "total"]]),
            sourcePath: TokenScopeFormat.path(file.path)
        )
    }

    private static func activityRecord(from object: Any, file: URL, source: TokenScopeSource, fallbackDate: Date, fallbackProject: String, fallbackModel: String?) -> TokenScopeUsageRecord? {
        guard isActivityEvent(object) else { return nil }
        let timestamp = TokenScopeJSON.date(object, keys: ["timestamp", "created_at", "createdAt", "time", "date"]) ?? fallbackDate
        let sessionID = TokenScopeJSON.string(object, keys: ["sessionId", "session_id", "conversationId", "conversation_id", "id"]) ?? file.deletingPathExtension().lastPathComponent
        let model = TokenScopeModelName.best(in: object) ?? fallbackModel ?? TokenScopeModelName.unknown
        let project = TokenScopeJSON.firstString(object, paths: [["cwd"], ["workspace"], ["workspacePath"], ["project_path"], ["projectPath"], ["details", "cwd"], ["message", "cwd"]]) ?? fallbackProject
        let title = TokenScopeJSON.string(object, keys: ["title", "summary", "name", "type", "customType"]) ?? file.deletingPathExtension().lastPathComponent
        return TokenScopeUsageRecord(
            id: "\(source.rawValue):activity:\(sessionID):\(timestamp.timeIntervalSince1970):\(title)",
            source: source,
            timestamp: timestamp,
            sessionID: sessionID,
            projectPath: project,
            model: model,
            title: title,
            inputTokens: 0,
            outputTokens: 0,
            cacheCreationTokens: 0,
            cacheReadTokens: 0,
            reasoningTokens: 0,
            costUSD: nil,
            sourcePath: TokenScopeFormat.path(file.path)
        )
    }

    private static func isUsageEvent(_ object: Any) -> Bool {
        if TokenScopeJSON.firstValue(object, paths: [["usage"], ["message", "usage"], ["data", "usage"], ["result", "usage"], ["response", "usage"]]) != nil {
            return true
        }
        if let type = TokenScopeJSON.string(object, keys: ["type"])?.lowercased() {
            return ["message", "response", "assistant", "completion", "usage", "token_count"].contains(type)
        }
        return TokenScopeJSON.firstValue(object, paths: [["total_tokens"], ["totalTokens"], ["input_tokens"], ["inputTokens"], ["prompt_tokens"], ["output_tokens"], ["outputTokens"]]) != nil
    }

    private static func isActivityEvent(_ object: Any) -> Bool {
        if TokenScopeModelName.best(in: object) != nil { return true }
        if let type = TokenScopeJSON.string(object, keys: ["type"])?.lowercased() {
            return ["session", "message", "assistant", "user", "response", "request", "completion", "model_change", "custom"].contains(type)
        }
        if let customType = TokenScopeJSON.string(object, keys: ["customType"])?.lowercased() {
            return customType.contains("model") || customType.contains("session")
        }
        return TokenScopeJSON.firstValue(object, paths: [["messages"], ["events"], ["records"], ["sessions"]]) != nil
    }

    private static func inferProject(file: URL, root: URL) -> String {
        let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
        let parts = relative.split(separator: "/").map(String.init)
        if let sessionsIndex = parts.firstIndex(where: { $0 == "sessions" }), sessionsIndex > 0 {
            return root.appendingPathComponent(parts[..<sessionsIndex].joined(separator: "/")).path
        }
        if parts.count > 1, let first = parts.first {
            return root.appendingPathComponent(first).path
        }
        return root.path
    }
}

private enum TokenScopeCodeBuddyStateAdapter {
    static func parse(file: URL) -> [TokenScopeUsageRecord] {
        guard file.lastPathComponent == "codebuddy-sessions.vscdb" else { return [] }
        let rows = TokenScopeSQLiteStateReader.rows(
            file: file,
            whereClause: "key like 'session:%'"
        )
        return rows.prefix(160).compactMap { row in
            guard let object = TokenScopeJSON.object(row.value) as? [String: Any] else { return nil }
            let sessionID = TokenScopeJSON.string(object, keys: ["conversationId", "sessionId", "id"]) ?? row.key.replacingOccurrences(of: "session:", with: "")
            let timestamp = TokenScopeJSON.date(object, keys: ["updatedAt", "createdAt"]) ?? TokenScopeJSON.fileModifiedDate(file)
            return TokenScopeUsageRecord(
                id: "codeBuddy:state:\(sessionID):\(timestamp.timeIntervalSince1970)",
                source: .codeBuddy,
                timestamp: timestamp,
                sessionID: sessionID,
                projectPath: TokenScopeJSON.string(object, keys: ["cwd", "workspace", "projectPath"]) ?? file.deletingLastPathComponent().path,
                model: TokenScopeModelName.unknown,
                title: TokenScopeJSON.string(object, keys: ["title", "name"]) ?? sessionID,
                inputTokens: 0,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0,
                reasoningTokens: 0,
                costUSD: nil,
                sourcePath: TokenScopeFormat.path(file.path)
            )
        }
    }
}

private enum TokenScopeTraeStateAdapter {
    static func parse(file: URL, root: URL) -> [TokenScopeUsageRecord] {
        guard file.lastPathComponent == "state.vscdb" else { return [] }
        let rows = TokenScopeSQLiteStateReader.rows(
            file: file,
            whereClause: "key = 'icube-ai-agent-storage-input-history' or key = 'memento/icube-ai-agent-storage' or key = 'icube_session_agent_map' or key like '%ai-chat:sessionRelation:modelMap' or key like '%ai-chat:sessionRelation:globalModelMap'"
        )
        guard !rows.isEmpty else { return [] }

        let fallbackDate = TokenScopeJSON.fileModifiedDate(file)
        let project = workspaceFolder(for: file) ?? inferProject(file: file, root: root)
        var sessionIDs: [String] = []
        var sessionModels: [String: String] = [:]
        var globalModel: String?
        var titles: [String] = []

        for row in rows {
            if row.key.contains("globalModelMap"),
               let object = TokenScopeJSON.object(row.value) as? [String: Any] {
                globalModel = object.values.compactMap { TokenScopeModelName.fromTraeModelValue($0) }.first ?? globalModel
                continue
            }

            if row.key.contains("modelMap"),
               let object = TokenScopeJSON.object(row.value) as? [String: Any] {
                for (sessionID, value) in object {
                    appendUnique(sessionID, to: &sessionIDs)
                    if let model = TokenScopeModelName.fromTraeModelValue(value) {
                        sessionModels[sessionID] = model
                    }
                }
                continue
            }

            if row.key == "icube_session_agent_map",
               let object = TokenScopeJSON.object(row.value) as? [String: Any] {
                for sessionID in object.keys {
                    appendUnique(sessionID, to: &sessionIDs)
                }
                continue
            }

            if row.key == "memento/icube-ai-agent-storage",
               let object = TokenScopeJSON.object(row.value) as? [String: Any],
               let list = object["list"] as? [[String: Any]] {
                for item in list {
                    if let sessionID = TokenScopeJSON.string(item, keys: ["sessionId", "id"]) {
                        appendUnique(sessionID, to: &sessionIDs)
                    }
                }
                continue
            }

            if row.key == "icube-ai-agent-storage-input-history",
               let history = TokenScopeJSON.object(row.value) as? [[String: Any]] {
                titles = history.compactMap { TokenScopeJSON.string($0, keys: ["inputText", "query", "text"]) }
            }
        }

        if sessionIDs.isEmpty {
            sessionIDs = titles.indices.map { "trae-input-\($0)" }
        }

        return sessionIDs.prefix(160).enumerated().map { index, sessionID in
            let title = titles.indices.contains(index) ? titles[index] : sessionID
            let model = sessionModels[sessionID] ?? globalModel ?? TokenScopeModelName.unknown
            return TokenScopeUsageRecord(
                id: "trae:state:\(sessionID):\(fallbackDate.timeIntervalSince1970)",
                source: .trae,
                timestamp: fallbackDate,
                sessionID: sessionID,
                projectPath: project,
                model: model,
                title: title,
                inputTokens: 0,
                outputTokens: 0,
                cacheCreationTokens: 0,
                cacheReadTokens: 0,
                reasoningTokens: 0,
                costUSD: nil,
                sourcePath: TokenScopeFormat.path(file.path)
            )
        }
    }

    private static func appendUnique(_ value: String, to values: inout [String]) {
        guard !values.contains(value) else { return }
        values.append(value)
    }

    private static func workspaceFolder(for file: URL) -> String? {
        let workspaceFile = file.deletingLastPathComponent().appendingPathComponent("workspace.json")
        guard let text = try? String(contentsOf: workspaceFile, encoding: .utf8),
              let object = TokenScopeJSON.object(text) as? [String: Any],
              let raw = TokenScopeJSON.string(object, keys: ["folder"]) else {
            return nil
        }
        if let url = URL(string: raw), url.isFileURL {
            return url.path.removingPercentEncoding ?? url.path
        }
        return raw.removingPercentEncoding ?? raw
    }

    private static func inferProject(file: URL, root: URL) -> String {
        let relative = file.path.replacingOccurrences(of: root.path + "/", with: "")
        if let first = relative.split(separator: "/").first {
            return root.appendingPathComponent(String(first)).path
        }
        return root.path
    }
}

private enum TokenScopeSQLiteStateReader {
    struct Row {
        let key: String
        let value: String
    }

    static func rows(file: URL, whereClause: String) -> [Row] {
        guard FileManager.default.isReadableFile(atPath: file.path) else { return [] }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            file.path,
            "select json_object('key', key, 'value', cast(value as text)) from ItemTable where \(whereClause);"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        return text.split(separator: "\n").compactMap { line in
            guard let object = TokenScopeJSON.object(String(line)) as? [String: Any],
                  let key = TokenScopeJSON.string(object, keys: ["key"]),
                  let value = TokenScopeJSON.string(object, keys: ["value"]) else {
                return nil
            }
            return Row(key: key, value: value)
        }
    }
}

private struct TokenScopeUsage: Hashable {
    var input: Int
    var output: Int
    var cacheCreation: Int
    var cacheRead: Int
    var reasoning: Int
    var total: Int { input + output + cacheCreation + cacheRead + reasoning }

    func delta(from previous: TokenScopeUsage) -> TokenScopeUsage {
        TokenScopeUsage(
            input: max(0, input - previous.input),
            output: max(0, output - previous.output),
            cacheCreation: max(0, cacheCreation - previous.cacheCreation),
            cacheRead: max(0, cacheRead - previous.cacheRead),
            reasoning: max(0, reasoning - previous.reasoning)
        )
    }

    static func fromClaudeObject(_ object: Any) -> TokenScopeUsage? {
        let usage = TokenScopeJSON.value(object, path: ["message", "usage"]) ?? TokenScopeJSON.value(object, path: ["usage"])
        guard let usage else { return nil }
        let parsed = TokenScopeUsage(
            input: TokenScopeJSON.int(usage, keys: ["input_tokens", "inputTokens", "prompt_tokens"]),
            output: TokenScopeJSON.int(usage, keys: ["output_tokens", "outputTokens", "completion_tokens"]),
            cacheCreation: TokenScopeJSON.int(usage, keys: ["cache_creation_input_tokens", "cacheCreationInputTokens"]),
            cacheRead: TokenScopeJSON.int(usage, keys: ["cache_read_input_tokens", "cacheReadInputTokens"]),
            reasoning: TokenScopeJSON.int(usage, keys: ["reasoning_output_tokens", "thinking_tokens"])
        )
        return parsed.total > 0 ? parsed : nil
    }

    static func fromCodexObject(_ object: Any) -> TokenScopeUsage? {
        let rawInput = TokenScopeJSON.int(object, keys: ["input_tokens", "prompt_tokens", "inputTokens"])
        let cached = TokenScopeJSON.int(object, keys: ["cached_input_tokens", "cached_tokens", "cache_read_input_tokens"])
        let output = TokenScopeJSON.int(object, keys: ["output_tokens", "completion_tokens", "outputTokens"])
        let reasoning = TokenScopeJSON.int(object, keys: ["reasoning_output_tokens", "reasoning_tokens"])
        let total = TokenScopeJSON.int(object, keys: ["total_tokens", "totalTokens"])
        var usage = TokenScopeUsage(input: max(0, rawInput - cached), output: output, cacheCreation: TokenScopeJSON.int(object, keys: ["cache_creation_input_tokens"]), cacheRead: cached, reasoning: reasoning)
        if usage.total == 0, total > 0 {
            usage.input = total
        }
        return usage.total > 0 ? usage : nil
    }

    static func fromGeminiObject(_ object: Any) -> TokenScopeUsage? {
        let input = TokenScopeJSON.int(object, keys: ["input", "prompt", "input_tokens", "prompt_tokens"])
        let output = TokenScopeJSON.int(object, keys: ["output", "completion", "output_tokens", "completion_tokens"])
        let cached = TokenScopeJSON.int(object, keys: ["cached", "cache", "cached_tokens", "cache_read_input_tokens"])
        let reasoning = TokenScopeJSON.int(object, keys: ["thoughts", "thinking", "thoughts_tokens", "reasoning_output_tokens"])
        let total = TokenScopeJSON.int(object, keys: ["total", "total_tokens"])
        var usage = TokenScopeUsage(input: input, output: output, cacheCreation: 0, cacheRead: cached, reasoning: reasoning)
        if usage.total == 0, total > 0 {
            usage.input = total
        }
        return usage.total > 0 ? usage : nil
    }

    static func fromGenericObject(_ object: Any) -> TokenScopeUsage? {
        for parser in [fromClaudeObject, fromCodexObject, fromGeminiObject] {
            if let usage = parser(object), usage.total > 0 {
                return usage
            }
        }
        let input = TokenScopeJSON.recursiveInt(object, keys: ["input_tokens", "inputTokens", "prompt_tokens", "promptTokens", "input", "prompt"])
        let output = TokenScopeJSON.recursiveInt(object, keys: ["output_tokens", "outputTokens", "completion_tokens", "completionTokens", "output", "completion"])
        let cacheRead = TokenScopeJSON.recursiveInt(object, keys: ["cached_input_tokens", "cache_read_input_tokens", "cacheReadInputTokens", "cached_tokens", "cacheRead"])
        let cacheCreation = TokenScopeJSON.recursiveInt(object, keys: ["cache_creation_input_tokens", "cacheCreationInputTokens", "cache_write_tokens", "cacheWrite"])
        let reasoning = TokenScopeJSON.recursiveInt(object, keys: ["reasoning_output_tokens", "reasoningTokens", "thinking_tokens", "thoughts"])
        let total = TokenScopeJSON.recursiveInt(object, keys: ["total_tokens", "totalTokens", "total"])
        var usage = TokenScopeUsage(input: max(0, input - cacheRead), output: output, cacheCreation: cacheCreation, cacheRead: cacheRead, reasoning: reasoning)
        if usage.total == 0, total > 0 {
            usage.input = total
        }
        return usage.total > 0 ? usage : nil
    }
}

private enum TokenScopeModelName {
    static let unknown = "Unknown Model"
    private static let rejected: Set<String> = [
        "qclaw", "openclaw", "hermes", "trae", "codebuddy", "claude code", "codex", "gemini cli"
    ]

    static func best(in object: Any) -> String? {
        let direct = TokenScopeJSON.firstString(object, paths: [
            ["model"],
            ["model_name"],
            ["modelName"],
            ["model_id"],
            ["modelId"],
            ["message", "model"],
            ["metadata", "model"],
            ["payload", "model"],
            ["data", "model"],
            ["data", "modelId"],
            ["data", "model_id"],
            ["result", "model"],
            ["response", "model"],
            ["model", "primary"],
            ["model", "id"],
            ["model", "name"],
            ["model", "model"],
            ["agents", "defaults", "model", "primary"]
        ])
        if let normalized = normalize(direct) {
            return normalized
        }
        return nil
    }

    static func normalize(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        let lower = value.lowercased()
        if rejected.contains(lower) { return nil }
        if lower.contains("agent") || lower.contains("session") || lower.contains("workspace") {
            return nil
        }
        return String(value.prefix(120))
    }

    static func fromTraeModelValue(_ value: Any) -> String? {
        if let string = value as? String {
            return normalizeTraeModel(string)
        }
        if let object = value as? [String: Any] {
            for candidate in object.values {
                if let model = fromTraeModelValue(candidate) {
                    return model
                }
            }
        }
        return nil
    }

    private static func normalizeTraeModel(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = candidate.range(of: "//", options: .backwards) {
            candidate = String(candidate[range.upperBound...])
        } else if let range = candidate.range(of: "_-_", options: .backwards) {
            candidate = String(candidate[range.upperBound...])
        }
        candidate = candidate.replacingOccurrences(of: "_", with: "-")
        return normalize(candidate)
    }
}

// MARK: - JSON Helpers

private enum TokenScopeJSON {
    static func object(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    static func value(_ object: Any?, path: [String]) -> Any? {
        guard var current = object else { return nil }
        for key in path {
            guard let dict = current as? [String: Any], let next = dict[key] else { return nil }
            current = next
        }
        return current
    }

    static func firstValue(_ object: Any, paths: [[String]]) -> Any? {
        paths.lazy.compactMap { value(object, path: $0) }.first
    }

    static func firstString(_ object: Any, paths: [[String]]) -> String? {
        paths.lazy.compactMap { string(value(object, path: $0)) }.first
    }

    static func firstDouble(_ object: Any, paths: [[String]]) -> Double? {
        paths.lazy.compactMap { double(value(object, path: $0)) }.first
    }

    static func string(_ object: Any?, path: [String]) -> String? {
        string(value(object, path: path))
    }

    static func string(_ object: Any?, keys: [String]) -> String? {
        guard let dict = object as? [String: Any] else { return nil }
        for key in keys {
            if let value = string(dict[key]), !value.isEmpty { return value }
        }
        return nil
    }

    static func array(_ object: Any?, keys: [String]) -> [Any]? {
        guard let dict = object as? [String: Any] else { return nil }
        for key in keys {
            if let value = dict[key] as? [Any] { return value }
        }
        return nil
    }

    static func dictionary(_ object: Any?) -> [String: Any]? {
        object as? [String: Any]
    }

    static func int(_ object: Any?, keys: [String]) -> Int {
        guard let dict = object as? [String: Any] else { return 0 }
        for key in keys {
            if let value = int(dict[key]) { return value }
        }
        return 0
    }

    static func recursiveInt(_ object: Any?, keys: Set<String>) -> Int {
        guard let object else { return 0 }
        if let dict = object as? [String: Any] {
            var total = 0
            for (key, value) in dict {
                if keys.contains(key), let number = int(value) {
                    total += number
                } else {
                    total += recursiveInt(value, keys: keys)
                }
            }
            return total
        }
        if let array = object as? [Any] {
            return array.reduce(0) { $0 + recursiveInt($1, keys: keys) }
        }
        return 0
    }

    static func double(_ object: Any?, keys: [String]) -> Double? {
        guard let dict = object as? [String: Any] else { return nil }
        for key in keys {
            if let value = dict[key] as? Double { return value }
            if let value = dict[key] as? Int { return Double(value) }
            if let value = dict[key] as? String, let double = Double(value) { return double }
        }
        return nil
    }

    static func date(_ object: Any?, keys: [String]) -> Date? {
        guard let raw = string(object, keys: keys) else { return nil }
        return date(raw)
    }

    static func fileModifiedDate(_ file: URL) -> Date {
        ((try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate) ?? Date()
    }

    private static func string(_ value: Any?) -> String? {
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func double(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func date(_ raw: String) -> Date? {
        if let interval = Double(raw), interval > 1_000_000_000 {
            return Date(timeIntervalSince1970: interval > 10_000_000_000 ? interval / 1000 : interval)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

// MARK: - Formatting

private enum TokenScopeFormat {
    static func tokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000.0)
        }
        if value >= 1_000 {
            return String(format: "%.0fK", Double(value) / 1_000.0)
        }
        return "\(value)"
    }

    static func currency(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func path(_ value: String) -> String {
        let expanded = (value as NSString).expandingTildeInPath
        let home = SandboxPaths.realHomeDirectory
        if expanded.hasPrefix(home) {
            return "~" + expanded.dropFirst(home.count)
        }
        return value
    }

    static func dayLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }

    static func hourLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:00"
        return formatter.string(from: date)
    }

    static func isoDay(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func isoHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH"
        return formatter.string(from: date)
    }
}

private enum TokenScopePricing {
    static func estimate(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double {
        let lower = model.lowercased()
        let rates: (input: Double, output: Double, cacheRead: Double, cacheWrite: Double)
        if lower.contains("opus") {
            rates = (15.0, 75.0, 1.5, 18.75)
        } else if lower.contains("sonnet") || lower.contains("claude") {
            rates = (3.0, 15.0, 0.3, 3.75)
        } else if lower.contains("gpt-5") || lower.contains("codex") {
            rates = (1.25, 10.0, 0.125, 1.25)
        } else if lower.contains("gemini") {
            rates = (1.25, 5.0, 0.125, 1.25)
        } else {
            rates = (1.0, 4.0, 0.1, 1.0)
        }
        return (Double(input) * rates.input
            + Double(output) * rates.output
            + Double(cacheRead) * rates.cacheRead
            + Double(cacheWrite) * rates.cacheWrite) / 1_000_000.0
    }
}

private enum TokenScopePalette {
    static let colors: [Color] = [
        Theme.Colors.teal,
        Theme.Colors.info,
        Theme.Colors.purple,
        Theme.Colors.cyan,
        Theme.Colors.warning,
        Theme.Colors.success,
        .pink,
        .indigo
    ]
}
