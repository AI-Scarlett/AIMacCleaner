import SwiftUI

struct SessionDetailContentView: View {
    @EnvironmentObject var localizer: Localizer
    let session: SessionState

    @State private var selectedTab: DetailTab = .overview

    enum DetailTab: CaseIterable {
        case overview
        case tools
        case subagents
        case events

        var icon: String {
            switch self {
            case .overview: return "info.circle"
            case .tools: return "wrench"
            case .subagents: return "person.2"
            case .events: return "list.bullet"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        HStack(spacing: 4) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 10))
                            Text(tab.title(localizer))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(selectedTab == tab ? .blue : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? .blue.opacity(0.08) : .clear)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)

            Divider()
                .padding(.top, 4)

            ScrollView {
                switch selectedTab {
                case .overview:
                    overviewTab
                case .tools:
                    toolsTab
                case .subagents:
                    subagentsTab
                case .events:
                    eventsTab
                }
            }
        }
    }

    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Group {
                detailRow(icon: "folder", label: localizer.agentProject, value: session.project)
                detailRow(icon: "terminal", label: localizer.agentLabel, value: session.agentType)
                detailRow(icon: "clock", label: localizer.agentDuration, value: durationString)
                detailRow(icon: "circle.dashed", label: localizer.agentPhase, value: phaseLabel(session.phase))

                if let desc = session.description {
                    detailRow(icon: "text.alignleft", label: localizer.status, value: desc)
                }
            }

            Divider()
                .padding(.vertical, 4)

            Text(localizer.agentTokenUsage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                tokenBadge(label: localizer.agentTokenInput, value: session.tokens.input, color: .blue)
                tokenBadge(label: localizer.agentTokenOutput, value: session.tokens.output, color: .green)
                tokenBadge(label: localizer.agentTokenCacheRead, value: session.tokens.cacheRead, color: .orange)
                tokenBadge(label: localizer.agentTokenCacheCreate, value: session.tokens.cacheCreate, color: .purple)
            }

            if let rateLimits = session.rateLimits {
                Divider()
                    .padding(.vertical, 4)

                Text(localizer.agentRateLimits)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                VStack(spacing: 6) {
                    rateLimitBar(label: "5h", value: rateLimits.fiveHourUsage, remaining: rateLimits.fiveHourRemaining)
                    rateLimitBar(label: "7d", value: rateLimits.sevenDayUsage, remaining: rateLimits.sevenDayRemaining)
                }
            }

            if let ctx = session.contextWindow {
                Divider()
                    .padding(.vertical, 4)

                Text(localizer.agentContextWindow)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)

                VStack(spacing: 4) {
                    detailRow(icon: "doc.text", label: localizer.agentTotalInput, value: ctx.totalInputTokens.formatted())
                    detailRow(icon: "doc.plaintext", label: localizer.agentTotalOutput, value: ctx.totalOutputTokens.formatted())
                    detailRow(icon: "rectangle.stack", label: localizer.agentWindowSize, value: ctx.contextWindowSize.formatted())
                    if let pct = ctx.usedPercentage {
                        ProgressView(value: pct / 100)
                            .tint(pct > 80 ? .red : pct > 60 ? .orange : .green)
                        Text(localizer.agentContextUsed(Int(pct)))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
    }

    private var toolsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.activeTools.isEmpty {
                Text(localizer.agentNoToolExecutions)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(session.activeTools.reversed()) { tool in
                    HStack(spacing: 8) {
                        Image(systemName: tool.status == "success" ? "checkmark.circle.fill" : tool.status == "error" ? "xmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundStyle(tool.status == "success" ? .green : tool.status == "error" ? .red : .blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(tool.toolName)
                                .font(.system(size: 11, weight: .medium))
                            if let input = tool.toolInput, !input.isEmpty {
                                Text(input.prefix(80))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Spacer()

                        if let completed = tool.completedAt {
                            Text(timeAgo(from: completed))
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(8)
                    .background(.primary.opacity(0.03))
                    .cornerRadius(6)

                    if tool.id != session.activeTools.first?.id {
                        Divider()
                            .opacity(0.3)
                    }
                }
            }
        }
        .padding(14)
    }

    private var subagentsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if session.subagents.isEmpty {
                Text(localizer.agentNoSubagents)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(session.subagents) { sub in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: sub.status == "completed" ? "person.fill.checkmark" : "person.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(sub.status == "completed" ? .green : .blue)

                            Text(sub.name ?? sub.agentId)
                                .font(.system(size: 11, weight: .medium))

                            Spacer()

                            PillBadge(text: sub.status, color: sub.status == "completed" ? .green : .blue)
                        }

                        Text(sub.description.prefix(100))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if let msg = sub.lastAssistantMessage {
                            Text(msg.prefix(120))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                                .padding(.top, 2)
                        }
                    }
                    .padding(8)
                    .background(.primary.opacity(0.03))
                    .cornerRadius(6)
                }
            }
        }
        .padding(14)
    }

    private var eventsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizer.agentRawEventsHint)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        }
        .padding(14)
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
    }

    private func tokenBadge(label: String, value: UInt64, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value.formatted())
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .cornerRadius(6)
    }

    private func rateLimitBar(label: String, value: Double, remaining: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            ProgressView(value: value / 100)
                .tint(value > 80 ? .red : value > 60 ? .orange : .green)

            Text(remaining.isEmpty ? "\(Int(value))%" : remaining)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var durationString: String {
        let d = session.duration
        if d < 60 { return localizer.agentSeconds(Int(d)) }
        if d < 3600 { return "\(localizer.agentMinutes(Int(d / 60))) \(localizer.agentSeconds(Int(d.truncatingRemainder(dividingBy: 60))))" }
        return "\(localizer.agentHours(Int(d / 3600))) \(localizer.agentMinutes(Int(d.truncatingRemainder(dividingBy: 3600) / 60)))"
    }

    private func timeAgo(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return localizer.agentAgo(localizer.agentSeconds(Int(interval))) }
        if interval < 3600 { return localizer.agentAgo(localizer.agentMinutes(Int(interval / 60))) }
        if interval < 86400 { return localizer.agentAgo(localizer.agentHours(Int(interval / 3600))) }
        return localizer.agentAgo(localizer.agentDays(Int(interval / 86400)))
    }

    private func phaseLabel(_ phase: SessionPhase) -> String {
        switch phase {
        case .ready: return localizer.agentPhaseReady
        case .idle: return localizer.agentPhaseIdle
        case .processing: return localizer.agentPhaseProcessing
        case .waitingApproval: return localizer.agentCenterPending
        case .waitingInput: return localizer.agentCenterQuestion
        case .compacting: return localizer.agentPhaseCompacting
        case .done: return localizer.agentPhaseDone
        case .error: return localizer.agentPhaseError
        case .interrupted: return localizer.agentPhaseInterrupted
        }
    }
}

private extension SessionDetailContentView.DetailTab {
    func title(_ localizer: Localizer) -> String {
        switch self {
        case .overview: return localizer.agentDetailOverview
        case .tools: return localizer.agentDetailTools
        case .subagents: return localizer.agentDetailSubagents
        case .events: return localizer.agentDetailEvents
        }
    }
}
