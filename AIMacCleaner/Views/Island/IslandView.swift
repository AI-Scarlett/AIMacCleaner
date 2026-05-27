import SwiftUI

struct IslandView: View {
    @EnvironmentObject var viewModel: IslandViewModel
    @EnvironmentObject var localizer: Localizer

    var body: some View {
        Group {
            switch viewModel.displayLevel {
            case .compact:
                compactView
            case .hover:
                hoverView
            case .expanded:
                expandedView
            case .detail:
                detailView
            }
        }
        .background {
            RoundedRectangle(cornerRadius: viewModel.displayLevel.cornerRadius)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: viewModel.displayLevel.cornerRadius)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewModel.displayLevel)
    }

    private var compactView: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.lastAgentIcon.isEmpty ? "terminal.fill" : viewModel.lastAgentIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)

                if let session = viewModel.currentSession {
                    Circle()
                        .fill(phaseDotColor(session.phase))
                        .frame(width: 6, height: 6)
                        .opacity(viewModel.blinking ? 1 : 0.6)
                        .animation(viewModel.blinking ? .easeInOut(duration: 0.6).repeatForever() : .default, value: viewModel.blinking)

                    Text(viewModel.lastStatusText)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    Text("AgentGuard Ready")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let session = viewModel.currentSession, session.phase.needsAttention {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: viewModel.displayLevel.islandWidth, height: viewModel.displayLevel.islandHeight)
        .onTapGesture {
            viewModel.show(level: .expanded)
        }
    }

    private var hoverView: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: viewModel.lastAgentIcon.isEmpty ? "terminal.fill" : viewModel.lastAgentIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)

                Circle()
                    .fill(viewModel.currentSession.map { phaseDotColor($0.phase) } ?? .secondary)
                    .frame(width: 6, height: 6)
                    .opacity(viewModel.blinking ? 1 : 0.6)
                    .animation(viewModel.blinking ? .easeInOut(duration: 0.6).repeatForever() : .default, value: viewModel.blinking)

                VStack(alignment: .leading, spacing: 2) {
                    if let session = viewModel.currentSession {
                        Text(session.project)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                    Text(viewModel.lastStatusText)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                if let session = viewModel.currentSession, session.phase.needsAttention {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                Button(action: { viewModel.show(level: .expanded) }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: viewModel.displayLevel.islandWidth, height: viewModel.displayLevel.islandHeight)
    }

    private var expandedView: some View {
        VStack(spacing: 0) {
            expandedHeader

            Divider()
                .opacity(0.3)

            if let overlay = viewModel.activeApprovalOverlay,
               let session = viewModel.activeApprovalSession {
                VStack(spacing: 0) {
                    approvalQueueHeader(overlay: overlay)

                    switch overlay.kind {
                    case .permission:
                        if let perm = session.pendingPermission {
                            PermissionSheetView(permission: perm, session: session) { decision in
                                viewModel.respondToPermission(decision)
                            }
                        }
                    case .question:
                        if let question = session.pendingQuestion {
                            QuestionSheetView(question: question, session: session) { answer in
                                viewModel.respondToQuestion(answer)
                            }
                        }
                    case .plan:
                        if let plan = session.pendingPlan {
                            PlanApprovalSheetView(plan: plan, session: session) { mode, message in
                                viewModel.respondToPlan(mode: mode, message: message)
                            }
                        }
                    }
                }
            } else {
                recentEventsList
            }
        }
        .frame(width: viewModel.displayLevel.islandWidth, height: viewModel.displayLevel.islandHeight)
    }

    private var detailView: some View {
        VStack(spacing: 0) {
            detailHeader

            Divider()
                .opacity(0.3)

            if let session = viewModel.sessionToDetail {
                SessionDetailContentView(session: session)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.3.group")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary.opacity(0.5))
                    Text("No session selected")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: viewModel.displayLevel.islandWidth, height: viewModel.displayLevel.islandHeight)
    }

    private var expandedHeader: some View {
        HStack(spacing: 8) {
            if let session = viewModel.currentSession {
                Image(systemName: viewModel.lastAgentIcon.isEmpty ? "terminal.fill" : viewModel.lastAgentIcon)
                    .font(.system(size: 13))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 1) {
                    Text(session.project)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(session.agentType)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: { viewModel.show(level: .detail) }) {
                Image(systemName: "rectangle.expand.vertical")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Show session detail")

            Button(action: { viewModel.togglePin() }) {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(viewModel.isPinned ? .blue : .secondary)
            }
            .buttonStyle(.plain)
            .help("Pin island")

            Button(action: { viewModel.dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func approvalQueueHeader(overlay: IslandApprovalOverlay) -> some View {
        HStack(spacing: 8) {
            Label(approvalKindTitle(overlay.kind), systemImage: approvalKindIcon(overlay.kind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(approvalKindColor(overlay.kind))

            if viewModel.approvalQueueCount > 1 {
                Text("1 / \(viewModel.approvalQueueCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.primary.opacity(0.06))
                    .cornerRadius(5)
            }

            if let next = viewModel.nextApprovalTitle {
                Text("\(localizer.agentApprovalNext): \(next)")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: { viewModel.showApprovalSessionList() }) {
                Image(systemName: "rectangle.3.group")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(localizer.agentApprovalShowSessions)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(approvalKindColor(overlay.kind).opacity(0.08))
    }

    private func approvalKindTitle(_ kind: IslandApprovalKind) -> String {
        switch kind {
        case .permission: return localizer.agentCenterPermission
        case .question: return localizer.agentCenterQuestion
        case .plan: return localizer.agentCenterPlan
        }
    }

    private func approvalKindIcon(_ kind: IslandApprovalKind) -> String {
        switch kind {
        case .permission: return "hand.raised.fill"
        case .question: return "questionmark.bubble.fill"
        case .plan: return "list.clipboard.fill"
        }
    }

    private func approvalKindColor(_ kind: IslandApprovalKind) -> Color {
        switch kind {
        case .permission: return .orange
        case .question: return .purple
        case .plan: return .cyan
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 8) {
            Button(action: { viewModel.show(level: .expanded) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if let session = viewModel.sessionToDetail {
                VStack(alignment: .leading, spacing: 1) {
                    Text(session.project)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Session Detail")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: { viewModel.togglePin() }) {
                Image(systemName: viewModel.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11))
                    .foregroundStyle(viewModel.isPinned ? .blue : .secondary)
            }
            .buttonStyle(.plain)

            Button(action: { viewModel.dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var recentEventsList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(Array(viewModel.recentEvents.reversed().enumerated()), id: \.offset) { _, event in
                    eventRow(event)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                        .id(event.sessionId)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .onChange(of: viewModel.recentEvents.count) { _ in
                if let last = viewModel.recentEvents.last {
                    withAnimation { proxy.scrollTo(last.sessionId, anchor: .bottom) }
                }
            }
        }
    }

    private func eventRow(_ event: AgentHookEvent) -> some View {
        HStack(spacing: 8) {
            Image(systemName: eventIcon(event))
                .font(.system(size: 10))
                .foregroundStyle(eventColor(event))
                .frame(width: 16)

            Text(eventDescription(event))
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            Text(timeAgo(event))
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func eventIcon(_ event: AgentHookEvent) -> String {
        switch event {
        case .sessionStart: return "play.fill"
        case .sessionEnd: return "stop.fill"
        case .processing: return "arrow.trianglehead.2.clockwise"
        case .toolUse: return "wrench.fill"
        case .permissionRequest: return "hand.raised.fill"
        case .askQuestion: return "questionmark.bubble.fill"
        case .planApproval: return "list.clipboard.fill"
        case .taskComplete: return "checkmark.circle.fill"
        case .assistantResponseComplete: return "bubble.left.fill"
        case .agentError: return "xmark.octagon.fill"
        case .interrupt: return "pause.circle.fill"
        case .tokenUsage: return "chart.bar.fill"
        case .rateLimitUpdate: return "gauge.with.dots.needle.33percent"
        case .notification: return "bell.fill"
        case .subagentStart: return "person.badge.plus"
        case .subagentStop: return "person.badge.minus"
        case .shellExecutionStart: return "terminal.fill"
        case .shellExecutionEnd: return "terminal"
        case .mcpExecutionStart: return "server.rack"
        case .mcpExecutionEnd: return "server.rack"
        case .agentResponse: return "bubble.left.and.bubble.right.fill"
        case .agentThought: return "lightbulb.fill"
        }
    }

    private func eventColor(_ event: AgentHookEvent) -> Color {
        switch event {
        case .sessionStart: return .blue
        case .sessionEnd: return .secondary
        case .processing: return .blue
        case .toolUse: return .green
        case .permissionRequest: return .orange
        case .askQuestion: return .purple
        case .planApproval: return .cyan
        case .taskComplete: return .green
        case .assistantResponseComplete: return .blue
        case .agentError: return .red
        case .interrupt: return .orange
        case .tokenUsage: return .teal
        case .rateLimitUpdate: return .orange
        case .notification: return .yellow
        case .subagentStart, .subagentStop: return .indigo
        case .shellExecutionStart, .shellExecutionEnd: return .gray
        case .mcpExecutionStart, .mcpExecutionEnd: return .purple
        case .agentResponse: return .blue
        case .agentThought: return .yellow
        }
    }

    private func eventDescription(_ event: AgentHookEvent) -> String {
        switch event {
        case .sessionStart(_, let project, _, _, let agentType):
            return "\(agentType) started in \(project)"
        case .sessionEnd:
            return "Session ended"
        case .processing(_, let desc):
            return desc
        case .toolUse(_, let toolName, _, _, let status):
            return "\(status == "running" ? "🔧" : "✓") \(toolName)"
        case .permissionRequest(_, let toolName, _, _):
            return "Permission needed: \(toolName)"
        case .askQuestion(_, let question, _, _, _, _, _):
            return question
        case .planApproval(_, let title, _, _):
            return "Plan: \(title)"
        case .taskComplete(_, let summary):
            return "✓ \(summary.prefix(60))"
        case .agentError(_, let message):
            return "Error: \(message.prefix(60))"
        case .tokenUsage(_, let input, let output, _, _):
            return "Tokens: \(input.formatted())↑ \(output.formatted())↓"
        case .rateLimitUpdate(_, let usage, _, _, _, _, _, _, _, _, _, _):
            return "API usage: \(Int(usage))%"
        case .subagentStart(_, _, let name, _, _, _):
            return "Subagent: \(name ?? "unknown")"
        case .subagentStop(_, _, let status, let name, _, _, _, _):
            return "Subagent \(name ?? "") \(status)"
        case .shellExecutionStart(_, let command, _):
            return "$ \(command.prefix(60))"
        case .shellExecutionEnd(_, let command, let code, _, _, let duration):
            return "$ \(command.prefix(40)) [\(code ?? 0)] \(duration)ms"
        default:
            return "Unknown event"
        }
    }

    private func timeAgo(_ event: AgentHookEvent) -> String {
        return ""
    }

    private func phaseDotColor(_ phase: SessionPhase) -> Color {
        switch phase {
        case .ready: return .blue
        case .idle: return .secondary
        case .processing: return .green
        case .waitingApproval: return .orange
        case .waitingInput: return .purple
        case .compacting: return .cyan
        case .done: return .green
        case .error: return .red
        case .interrupted: return .orange
        }
    }
}
