import AppKit
import Foundation
import MacToolsPluginKit

/// Shared presentation of quota snapshots for Touch Bar and the screen-edge rail.
enum QuotaDisplay {
    struct Metric: Equatable {
        let id: String
        let title: String
        let remaining: Int
        let sortOrder: Int
        let resetsAt: Date?
    }

    struct Item: Equatable {
        let id: String
        let providerKey: String
        let providerName: String
        let metrics: [Metric]
        let lowestRemaining: Int
    }

    struct State: Equatable {
        let providerID: String
        let providerName: String
        let metrics: [Metric]
        let selectedMetricIndex: Int
        let isAutomatic: Bool
        let isUnavailable: Bool

        var currentMetric: Metric? {
            guard metrics.indices.contains(selectedMetricIndex) else { return nil }
            return metrics[selectedMetricIndex]
        }

        var metricCount: Int { metrics.count }
        var metricPageText: String { "\(selectedMetricIndex + 1)/\(max(1, metricCount))" }
        var lowestRemaining: Int? { metrics.map(\.remaining).min() }

        func summary(localization: PluginLocalization) -> String {
            guard !isUnavailable else {
                return localization.string("touchbar.unavailable", defaultValue: "No quota data")
            }
            let mode = localization.string(
                isAutomatic ? "touchbar.mode.automatic" : "touchbar.mode.manual",
                defaultValue: isAutomatic ? "Automatic follow" : "Manual lock"
            )
            if let metric = currentMetric {
                return localization.format(
                    "touchbar.summary.metric",
                    defaultValue: "%@ · %@ %lld%% · %@ · %@",
                    providerName,
                    metric.title,
                    Int64(metric.remaining),
                    metricPageText,
                    mode
                )
            }
            return localization.format(
                "touchbar.summary.provider",
                defaultValue: "%@ · %@",
                providerName,
                mode
            )
        }

        static func unavailable() -> State {
            State(
                providerID: "",
                providerName: "Quota",
                metrics: [],
                selectedMetricIndex: 0,
                isAutomatic: true,
                isUnavailable: true
            )
        }

        static func quota(item: Item, metricIndex: Int, isAutomatic: Bool) -> State {
            State(
                providerID: item.id,
                providerName: item.providerName,
                metrics: item.metrics,
                selectedMetricIndex: metricIndex,
                isAutomatic: isAutomatic,
                isUnavailable: false
            )
        }
    }

    static func items(from snapshots: [ProviderQuotaSnapshot], localization: PluginLocalization) -> [Item] {
        snapshots.compactMap { snapshot in
            guard !snapshot.isSetupNotice else { return nil }
            let metrics = makeMetrics(from: snapshot.windows, localization: localization)
            guard !metrics.isEmpty else { return nil }
            let key = providerKey(for: snapshot.providerName)
            return Item(
                id: snapshot.id,
                providerKey: key,
                providerName: sanitizedProviderName(key),
                metrics: metrics,
                lowestRemaining: metrics.map(\.remaining).min() ?? 0
            )
        }
        .sorted { lhs, rhs in
            if lhs.providerName != rhs.providerName {
                return lhs.providerName.localizedCaseInsensitiveCompare(rhs.providerName) == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    static func providerKey(for text: String) -> String {
        let normalized = text.lowercased()
        if normalized.contains("codex") || normalized.contains("openai") { return "codex" }
        if normalized.contains("claude") || normalized.contains("anthropic") { return "claude" }
        if normalized.contains("grok") || normalized.contains("xai") { return "grok" }
        if normalized.contains("deepseek") || normalized.contains("dsh") { return "deepseek" }
        if normalized.contains("antigravity") { return "antigravity" }
        if normalized.contains("cursor") { return "cursor" }
        if normalized.contains("minimax") { return "minimax" }
        if normalized.contains("gemini") || normalized.contains("google") { return "gemini" }
        if normalized.contains("kimi") || normalized.contains("moonshot") { return "kimi" }
        if normalized.contains("copilot") { return "copilot" }
        if normalized.contains("zai") || normalized.contains("zhipu") || normalized.contains("glm") { return "zai" }
        if normalized.contains("command code") || normalized.contains("commandcode") { return "commandcode" }
        if normalized.contains("kiro") { return "kiro" }
        if normalized.contains("factory") || normalized.contains("droid") { return "factory" }
        if normalized.contains("opencode") { return "opencode" }
        return normalized
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .first(where: { !$0.isEmpty }) ?? ""
    }

    static func meterColor(for remaining: Int?) -> NSColor {
        guard let remaining else { return .systemGray }
        switch remaining {
        case ..<20: return NSColor(red: 0.93, green: 0.27, blue: 0.31, alpha: 1)
        case ..<50: return NSColor(red: 0.96, green: 0.49, blue: 0.12, alpha: 1)
        case ..<70: return NSColor(red: 0.98, green: 0.78, blue: 0.16, alpha: 1)
        default: return NSColor(red: 0.24, green: 0.82, blue: 0.42, alpha: 1)
        }
    }

    private static func makeMetrics(
        from windows: [ProviderQuotaWindow],
        localization: PluginLocalization
    ) -> [Metric] {
        windows
            .map { window in
                Metric(
                    id: window.id,
                    title: metricTitle(for: window, localization: localization),
                    remaining: Int(window.remainingPercent.rounded()),
                    sortOrder: metricSortOrder(for: window.kind),
                    resetsAt: window.resetsAt
                )
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                if lhs.title != rhs.title { return lhs.title < rhs.title }
                return lhs.id < rhs.id
            }
    }

    private static func metricTitle(
        for window: ProviderQuotaWindow,
        localization: PluginLocalization
    ) -> String {
        let providerTitle = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !providerTitle.isEmpty { return providerTitle }

        switch window.kind {
        case .fiveHour:
            return localization.string("touchbar.metric.fiveHour", defaultValue: "5-hour quota")
        case .weekly:
            return localization.string("touchbar.metric.weekly", defaultValue: "Weekly quota")
        case .monthly:
            return localization.string("touchbar.metric.monthly", defaultValue: "Monthly quota")
        case .extra:
            return localization.string("touchbar.metric.extra", defaultValue: "Additional quota")
        }
    }

    private static func metricSortOrder(for kind: ProviderQuotaWindow.Kind) -> Int {
        switch kind {
        case .fiveHour: return 0
        case .weekly: return 1
        case .monthly: return 2
        case .extra: return 3
        }
    }

    static func sanitizedProviderName(_ key: String) -> String {
        switch key {
        case "codex": return "GPT"
        case "claude": return "Claude"
        case "grok": return "Grok"
        case "cursor": return "Cursor"
        case "gemini": return "Gemini"
        case "deepseek": return "DeepSeek"
        case "minimax": return "MiniMax"
        case "antigravity": return "Antigravity"
        case "kimi": return "Kimi"
        case "copilot": return "Copilot"
        case "zai": return "Z.ai"
        case "commandcode": return "Command"
        case "kiro": return "Kiro"
        case "factory": return "Factory"
        case "kilo": return "Kilo"
        case "opencode", "opencodego": return "OpenCode"
        default: return "Provider"
        }
    }
}
