import SwiftUI

enum Theme {
    enum Colors {
        static let background = Color(nsColor: .windowBackgroundColor)
        static let sidebarBg = Color(nsColor: .controlBackgroundColor)
        static let cardBg = Color(nsColor: .controlBackgroundColor)
        static let cardHover = Color.primary.opacity(0.04)
        static let separator = Color(nsColor: .separatorColor)
        static let textPrimary = Color.primary
        static let textSecondary = Color.secondary
        static let textTertiary = Color.secondary.opacity(0.6)

        static let accent = Color.accentColor
        static let success = Color.green
        static let warning = Color.orange
        static let danger = Color.red
        static let info = Color.blue
        static let purple = Color.purple
        static let teal = Color.teal
        static let cyan = Color.cyan

        static func statusColor(for value: Double, thresholds: (warn: Double, danger: Double) = (0.7, 0.85)) -> Color {
            if value > thresholds.danger { return danger }
            if value > thresholds.warn { return warning }
            return success
        }
    }

    enum Gradients {
        static let accent = LinearGradient(
            colors: [Color.blue.opacity(0.8), Color.purple.opacity(0.6)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let success = LinearGradient(
            colors: [Color.green.opacity(0.7), Color.teal.opacity(0.5)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let danger = LinearGradient(
            colors: [Color.red.opacity(0.7), Color.orange.opacity(0.5)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        static let sidebar = LinearGradient(
            colors: [Color.blue.opacity(0.03), Color.purple.opacity(0.02)],
            startPoint: .top, endPoint: .bottom
        )
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 6
        static let md: CGFloat = 10
        static let lg: CGFloat = 14
        static let xl: CGFloat = 20
    }

    enum Shadow {
        static let smColor = Color.black.opacity(0.06)
        static let smRadius: CGFloat = 4
        static let smY: CGFloat = 2
        static let mdColor = Color.black.opacity(0.08)
        static let mdRadius: CGFloat = 8
        static let mdY: CGFloat = 4
        static let lgColor = Color.black.opacity(0.1)
        static let lgRadius: CGFloat = 16
        static let lgY: CGFloat = 8
    }

    enum Font {
        static let caption = SwiftUI.Font.caption2
        static let captionMedium = SwiftUI.Font.caption2.weight(.medium)
        static let body = SwiftUI.Font.body
        static let bodyMedium = SwiftUI.Font.body.weight(.medium)
        static let subheadline = SwiftUI.Font.subheadline
        static let subheadlineMedium = SwiftUI.Font.subheadline.weight(.medium)
        static let headline = SwiftUI.Font.headline
        static let title2 = SwiftUI.Font.title2
        static let title2Bold = SwiftUI.Font.title2.weight(.bold)
        static let largeTitle = SwiftUI.Font.largeTitle.weight(.bold)
    }

    enum Sidebar {
        static let expandedWidth: CGFloat = 200
        static let collapsedWidth: CGFloat = 64
        static let iconSize: CGFloat = 20
        static let itemHeight: CGFloat = 40
        static let itemRadius: CGFloat = 10
    }

    enum Card {
        static let padding: CGFloat = 16
        static let minHeight: CGFloat = 80
    }
}

struct CardView<Content: View>: View {
    let content: Content
    var padding: CGFloat = Theme.Card.padding
    var cornerRadius: CGFloat = Theme.Radius.md
    var showShadow: Bool = true

    init(padding: CGFloat = Theme.Card.padding, cornerRadius: CGFloat = Theme.Radius.md, showShadow: Bool = true, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.cornerRadius = cornerRadius
        self.showShadow = showShadow
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(Theme.Colors.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: showShadow ? .black.opacity(0.06) : .clear, radius: showShadow ? 6 : 0, y: showShadow ? 2 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }
}

struct StatCardView: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let subtitle: String?
    var trend: TrendDirection = .none

    enum TrendDirection {
        case up, down, none
        var color: Color {
            switch self {
            case .up: return .green
            case .down: return .red
            case .none: return .secondary
            }
        }
        var icon: String? {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .none: return nil
            }
        }
    }

    var body: some View {
        CardView {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(iconColor)
                    .frame(width: 44, height: 44)
                    .background(iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Text(value)
                        .font(Theme.Font.title2Bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }

                Spacer()

                if let trendIcon = trend.icon {
                    Image(systemName: trendIcon)
                        .font(.caption)
                        .foregroundStyle(trend.color)
                }
            }
        }
    }
}

struct ProgressRing: View {
    let progress: Double
    let lineWidth: CGFloat
    let size: CGFloat
    let color: Color
    let bgColor: Color
    var showLabel: Bool = true

    init(progress: Double, lineWidth: CGFloat = 8, size: CGFloat = 80, color: Color? = nil, bgColor: Color = Color.primary.opacity(0.08), showLabel: Bool = true) {
        self.progress = min(max(progress, 0), 1)
        self.lineWidth = lineWidth
        self.size = size
        self.color = color ?? Theme.Colors.statusColor(for: progress)
        self.bgColor = bgColor
        self.showLabel = showLabel
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(bgColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(duration: 0.6), value: progress)
            if showLabel {
                Text("\(Int(progress * 100))%")
                    .font(.system(size: size * 0.22, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
        }
        .frame(width: size, height: size)
    }
}

struct PillBadge: View {
    let text: String
    let color: Color
    var size: PillSize = .small

    enum PillSize {
        case small, medium
        var font: SwiftUI.Font {
            switch self {
            case .small: return .caption2
            case .medium: return .caption
            }
        }
        var hPadding: CGFloat {
            switch self {
            case .small: return 6
            case .medium: return 8
            }
        }
        var vPadding: CGFloat {
            switch self {
            case .small: return 2
            case .medium: return 4
            }
        }
    }

    var body: some View {
        Text(text)
            .font(size.font.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, size.hPadding)
            .padding(.vertical, size.vPadding)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct SectionHeader: View {
    let title: String
    let icon: String?
    let action: (() -> Void)?

    init(title: String, icon: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let icon = icon {
                Image(systemName: icon)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Text(title)
                .font(Theme.Font.subheadlineMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            if let action = action {
                Button(action: action) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct DashboardGrid<Content: View>: View {
    let columns: [GridItem]
    let content: Content
    var spacing: CGFloat = Theme.Spacing.md

    init(columns: Int = 2, spacing: CGFloat = Theme.Spacing.md, @ViewBuilder content: () -> Content) {
        self.columns = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            content
        }
    }
}

extension View {
    func cardStyle(padding: CGFloat = Theme.Card.padding, cornerRadius: CGFloat = Theme.Radius.md) -> some View {
        self
            .padding(padding)
            .background(Theme.Colors.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }

    func fadeTransition() -> some View {
        self.transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct ArrangeResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> ArrangeResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            rowHeight = max(rowHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX - spacing)
        }

        return ArrangeResult(
            positions: positions,
            size: CGSize(width: maxX, height: currentY + rowHeight)
        )
    }
}
