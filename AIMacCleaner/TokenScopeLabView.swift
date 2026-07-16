import SwiftUI

/// The single Token and usage entry point.
///
/// The former TokenScope scanner maintained a second cache, file cap, token
/// arithmetic rule and time-range implementation. That made identical periods
/// disagree with Overview and Usage Insights. All visible totals now come from
/// `AgentUsageInsightsService`; project and task-oriented views live in Agent
/// Monitor instead of being repeated here.
@MainActor
struct TokenScopeLabView: View {
    @EnvironmentObject private var localizer: Localizer

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "chart.xyaxis.line",
                title: localizer.tokenScopeTitle,
                subtitle: localizer.tokenScopeSubtitle,
                color: Theme.Colors.accent
            )

            ScrollView {
                AgentUsageInsightsView(mode: .tokenAnalytics)
                    .environmentObject(localizer)
            }
            .background(Theme.Colors.sidebarBg.opacity(0.24))
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}
