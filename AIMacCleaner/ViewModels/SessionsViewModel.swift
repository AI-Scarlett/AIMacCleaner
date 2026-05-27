import SwiftUI
import Combine

@MainActor
class SessionsViewModel: ObservableObject {
    @Published var sessions: [SessionState] = []
    @Published var selectedSessionId: String?
    @Published var searchText: String = ""
    @Published var filterPhase: SessionPhase?
    @Published var sortOrder: SortOrder = .newest
    @Published var rawEvents: [RawHookEvent] = []

    enum SortOrder: String, CaseIterable {
        case newest = "Newest"
        case oldest = "Oldest"
        case mostTokens = "Most Tokens"
        case longestDuration = "Longest"
    }

    weak var sessionStore: SessionStore?
    private var observerId: UUID?

    func setup(sessionStore: SessionStore) {
        self.sessionStore = sessionStore
    }

    func startObserving() {
        Task { [weak self] in
            guard let self = self, let store = self.sessionStore else { return }
            self.observerId = await store.observe { [weak self] all in
                self?.sessions = all
            }
        }
    }

    func stopObserving() {
        if let id = observerId, let store = sessionStore {
            Task { await store.removeObserver(id) }
            observerId = nil
        }
    }

    var filteredSessions: [SessionState] {
        var result = sessions

        if let phase = filterPhase {
            result = result.filter { $0.phase == phase }
        }

        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter {
                $0.project.lowercased().contains(query) ||
                $0.agentType.lowercased().contains(query) ||
                ($0.description?.lowercased().contains(query) ?? false) ||
                ($0.lastToolName?.lowercased().contains(query) ?? false) ||
                $0.cwd.lowercased().contains(query)
            }
        }

        switch sortOrder {
        case .newest:
            result.sort { $0.startedAt > $1.startedAt }
        case .oldest:
            result.sort { $0.startedAt < $1.startedAt }
        case .mostTokens:
            result.sort { ($0.tokens.input + $0.tokens.output) > ($1.tokens.input + $1.tokens.output) }
        case .longestDuration:
            result.sort { $0.duration > $1.duration }
        }

        return result
    }

    var activeSessionCount: Int {
        sessions.filter { $0.phase.isActive }.count
    }

    var totalTokens: TokenUsage {
        sessions.reduce(TokenUsage()) { acc, s in
            TokenUsage(
                input: acc.input + s.tokens.input,
                output: acc.output + s.tokens.output,
                cacheRead: acc.cacheRead + s.tokens.cacheRead,
                cacheCreate: acc.cacheCreate + s.tokens.cacheCreate
            )
        }
    }

    func selectSession(_ id: String) {
        selectedSessionId = id
    }

    func selectedSession() -> SessionState? {
        guard let id = selectedSessionId else { return nil }
        return sessions.first { $0.id == id }
    }

    func loadRawEvents(for sessionId: String) async {
        guard let server = (NSApp.delegate as? AppDelegate)?.hookServer else { return }
        rawEvents = await server.getRawEvents(for: sessionId)
    }

    func phaseIcon(_ phase: SessionPhase) -> String {
        switch phase {
        case .ready: return "antenna.radiowaves.left.and.right"
        case .idle: return "circle.dashed"
        case .processing: return "gear"
        case .waitingApproval: return "hand.raised.fill"
        case .waitingInput: return "questionmark.bubble.fill"
        case .compacting: return "arrow.triangle.merge"
        case .done: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        case .interrupted: return "stop.circle.fill"
        }
    }

    func phaseColor(_ phase: SessionPhase) -> Color {
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

    func durationString(_ session: SessionState) -> String {
        let d = session.duration
        if d < 60 { return "\(Int(d))s" }
        if d < 3600 { return "\(Int(d / 60))m \(Int(d.truncatingRemainder(dividingBy: 60)))s" }
        return String(format: "%dh %dm", Int(d / 3600), Int(d.truncatingRemainder(dividingBy: 3600) / 60))
    }
}