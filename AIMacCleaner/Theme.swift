import SwiftUI
import AppKit

enum AppColorPalette: String, CaseIterable {
    case aurora
    case rose
    case shield
    case porcelain
}

enum Theme {
    enum Colors {
        private struct PaletteSpec {
            let backgroundLight: NSColor
            let backgroundDark: NSColor
            let surfaceLight: NSColor
            let surfaceDark: NSColor
            let sidebarLight: NSColor
            let sidebarDark: NSColor
            let cardLight: NSColor
            let cardDark: NSColor
            let elevatedLight: NSColor
            let elevatedDark: NSColor
            let hoverLight: NSColor
            let hoverDark: NSColor
            let separatorLight: NSColor
            let separatorDark: NSColor
            let textPrimaryLight: NSColor
            let textPrimaryDark: NSColor
            let textSecondaryLight: NSColor
            let textSecondaryDark: NSColor
            let textTertiaryLight: NSColor
            let textTertiaryDark: NSColor
            let accent: Color
            let success: Color
            let info: Color
            let purple: Color
            let teal: Color
            let cyan: Color
            let shadow: Color
        }

        static var background: Color { adaptive(\.backgroundLight, \.backgroundDark) }
        static var surface: Color { adaptive(\.surfaceLight, \.surfaceDark) }
        static var sidebarBg: Color { adaptive(\.sidebarLight, \.sidebarDark) }
        static var cardBg: Color { adaptive(\.cardLight, \.cardDark) }
        static var elevatedCardBg: Color { adaptive(\.elevatedLight, \.elevatedDark) }
        static var cardHover: Color { adaptive(\.hoverLight, \.hoverDark) }
        static var separator: Color { adaptive(\.separatorLight, \.separatorDark) }
        static var textPrimary: Color { adaptive(\.textPrimaryLight, \.textPrimaryDark) }
        static var textSecondary: Color { adaptive(\.textSecondaryLight, \.textSecondaryDark) }
        static var textTertiary: Color { adaptive(\.textTertiaryLight, \.textTertiaryDark) }

        static var accent: Color { current.accent }
        static var success: Color { current.success }
        static let warning = Color(red: 0.941, green: 0.663, blue: 0.227)
        static let danger = Color(red: 0.957, green: 0.396, blue: 0.396)
        static var info: Color { current.info }
        static var purple: Color { current.purple }
        static var teal: Color { current.teal }
        static var cyan: Color { current.cyan }
        static var ink: Color { Color(nsColor: current.textPrimaryLight) }
        static var shadowTint: Color { current.shadow }

        static var selectedPalette: AppColorPalette {
            AppColorPalette(rawValue: UserDefaults.standard.string(forKey: "colorPalette") ?? "") ?? .porcelain
        }

        private static var current: PaletteSpec {
            palette(for: selectedPalette)
        }

        private static let auroraPalette = makePalette(for: .aurora)
        private static let rosePalette = makePalette(for: .rose)
        private static let shieldPalette = makePalette(for: .shield)
        private static let porcelainPalette = makePalette(for: .porcelain)

        private static func adaptive(_ light: KeyPath<PaletteSpec, NSColor>, _ dark: KeyPath<PaletteSpec, NSColor>) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .aqua])
                let palette = self.current
                return match == .darkAqua ? palette[keyPath: dark] : palette[keyPath: light]
            })
        }

        private static func c(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
            NSColor(red: red, green: green, blue: blue, alpha: alpha)
        }

        private static func palette(for palette: AppColorPalette) -> PaletteSpec {
            switch palette {
            case .aurora: return auroraPalette
            case .rose: return rosePalette
            case .shield: return shieldPalette
            case .porcelain: return porcelainPalette
            }
        }

        private static func makePalette(for palette: AppColorPalette) -> PaletteSpec {
            switch palette {
            case .aurora:
                return neutralPalette(
                    accent: Color(red: 0.165, green: 0.620, blue: 0.650),
                    info: Color(red: 0.235, green: 0.490, blue: 0.790),
                    purple: Color(red: 0.430, green: 0.390, blue: 0.780),
                    teal: Color(red: 0.160, green: 0.570, blue: 0.470),
                    cyan: Color(red: 0.165, green: 0.620, blue: 0.650)
                )
            case .rose:
                return neutralPalette(
                    accent: Color(red: 0.790, green: 0.310, blue: 0.490),
                    info: Color(red: 0.460, green: 0.420, blue: 0.760),
                    purple: Color(red: 0.610, green: 0.350, blue: 0.740),
                    teal: Color(red: 0.220, green: 0.550, blue: 0.500),
                    cyan: Color(red: 0.250, green: 0.570, blue: 0.690)
                )
            case .shield:
                return neutralPalette(
                    accent: Color(red: 0.247, green: 0.400, blue: 0.710),
                    info: Color(red: 0.220, green: 0.470, blue: 0.790),
                    purple: Color(red: 0.410, green: 0.430, blue: 0.760),
                    teal: Color(red: 0.220, green: 0.500, blue: 0.650),
                    cyan: Color(red: 0.250, green: 0.520, blue: 0.720)
                )
            case .porcelain:
                return neutralPalette(
                    accent: Color(red: 0.322, green: 0.455, blue: 0.741),
                    info: Color(red: 0.220, green: 0.470, blue: 0.790),
                    purple: Color(red: 0.430, green: 0.420, blue: 0.760),
                    teal: Color(red: 0.210, green: 0.500, blue: 0.450),
                    cyan: Color(red: 0.240, green: 0.520, blue: 0.680)
                )
            }
        }

        /// Theme choices intentionally affect only the brand accent. Shared
        /// surfaces remain neutral so every native view and every plugin keeps
        /// the same hierarchy in light and dark appearance.
        private static func neutralPalette(
            accent: Color,
            info: Color,
            purple: Color,
            teal: Color,
            cyan: Color
        ) -> PaletteSpec {
            PaletteSpec(
                backgroundLight: c(0.965, 0.969, 0.976), backgroundDark: c(0.067, 0.075, 0.094),
                surfaceLight: c(0.973, 0.976, 0.984), surfaceDark: c(0.071, 0.078, 0.098),
                sidebarLight: c(0.945, 0.953, 0.965), sidebarDark: c(0.094, 0.102, 0.122),
                cardLight: c(1.000, 1.000, 1.000), cardDark: c(0.102, 0.114, 0.137),
                elevatedLight: c(1.000, 1.000, 1.000), elevatedDark: c(0.125, 0.137, 0.165),
                hoverLight: c(0.925, 0.933, 0.953), hoverDark: c(0.165, 0.180, 0.212),
                separatorLight: c(0.875, 0.890, 0.914), separatorDark: c(0.188, 0.204, 0.239),
                textPrimaryLight: c(0.122, 0.141, 0.188), textPrimaryDark: c(0.949, 0.957, 0.973),
                textSecondaryLight: c(0.424, 0.455, 0.502), textSecondaryDark: c(0.682, 0.706, 0.749),
                textTertiaryLight: c(0.541, 0.573, 0.620), textTertiaryDark: c(0.522, 0.553, 0.600),
                accent: accent,
                success: Color(red: 0.157, green: 0.663, blue: 0.420),
                info: info,
                purple: purple,
                teal: teal,
                cyan: cyan,
                shadow: Color.black
            )
        }

        static func statusColor(for value: Double, thresholds: (warn: Double, danger: Double) = (0.7, 0.85)) -> Color {
            if value > thresholds.danger { return danger }
            if value > thresholds.warn { return warning }
            return success
        }
    }

    enum Gradients {
        // Compatibility aliases for existing surfaces. They intentionally use
        // solid styles now, avoiding unnecessary gradient layers while the UI
        // keeps one consistent visual hierarchy.
        static var accent: Color { Colors.accent }
        static var hero: Color { Colors.accent }
        static var success: Color { Colors.success }
        static var danger: Color { Colors.danger }
        static var sidebar: Color { Colors.sidebarBg }
        static var appBackground: Color { Colors.background }
        static var glassStroke: Color { Colors.separator }
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
        static let md: CGFloat = 8
        static let lg: CGFloat = 10
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 14
    }

    enum Shadow {
        static var smColor: Color { Colors.shadowTint.opacity(0.035) }
        static let smRadius: CGFloat = 2
        static let smY: CGFloat = 1
        static var mdColor: Color { Colors.shadowTint.opacity(0.055) }
        static let mdRadius: CGFloat = 4
        static let mdY: CGFloat = 2
        static var lgColor: Color { Colors.shadowTint.opacity(0.075) }
        static let lgRadius: CGFloat = 7
        static let lgY: CGFloat = 3
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
        static let title2Bold = SwiftUI.Font.title2.weight(.semibold)
        static let largeTitle = SwiftUI.Font.largeTitle.weight(.semibold)
    }

    enum Sidebar {
        static let expandedWidth: CGFloat = 220
        static let collapsedWidth: CGFloat = 62
        static let iconSize: CGFloat = 16
        static let itemHeight: CGFloat = 36
        static let itemRadius: CGFloat = 8
    }

    enum Card {
        static let padding: CGFloat = 16
        static let minHeight: CGFloat = 80
    }
}

struct AgentGuardMark: View {
    var size: CGFloat = 34
    var showGlow = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(Theme.Colors.accent)
            Image(nsImage: MenuBarShieldEyeTemplateImage.shared)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
                .frame(width: size * 0.58, height: size * 0.58)
        }
        .frame(width: size, height: size)
        .shadow(color: showGlow ? Theme.Shadow.smColor : .clear, radius: Theme.Shadow.smRadius, y: Theme.Shadow.smY)
    }
}

struct BrandButtonStyle: ButtonStyle {
    enum Variant {
        case primary, secondary, ghost, danger
    }

    var color: Color = Theme.Colors.accent
    var variant: Variant = .primary
    var minHeight: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Font.captionMedium)
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: minHeight)
            .background(background(configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(color: shadowColor(configuration.isPressed), radius: Theme.Shadow.smRadius, y: Theme.Shadow.smY)
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary, .danger: return .white
        case .secondary, .ghost: return color
        }
    }

    private var strokeColor: Color {
        switch variant {
        case .primary, .danger: return Color.clear
        case .secondary: return Theme.Colors.separator
        case .ghost: return Color.clear
        }
    }

    private func shadowColor(_ pressed: Bool) -> Color {
        guard !pressed else { return .clear }
        switch variant {
        case .primary, .danger: return Theme.Shadow.smColor
        case .secondary: return Theme.Shadow.smColor
        case .ghost: return .clear
        }
    }

    @ViewBuilder
    private func background(_ pressed: Bool) -> some View {
        switch variant {
        case .primary:
            color.opacity(pressed ? 0.82 : 1)
        case .danger:
            color.opacity(pressed ? 0.82 : 1)
        case .secondary:
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(pressed ? Theme.Colors.cardHover : Theme.Colors.cardBg)
        case .ghost:
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(pressed ? Theme.Colors.cardHover : Color.clear)
        }
    }
}

struct CardView<Content: View>: View {
    let content: Content
    var padding: CGFloat = Theme.Card.padding
    var cornerRadius: CGFloat = Theme.Radius.md
    var showShadow: Bool = false

    init(padding: CGFloat = Theme.Card.padding, cornerRadius: CGFloat = Theme.Radius.md, showShadow: Bool = false, @ViewBuilder content: () -> Content) {
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
            .shadow(color: showShadow ? Theme.Shadow.smColor : .clear, radius: showShadow ? Theme.Shadow.smRadius : 0, y: showShadow ? Theme.Shadow.smY : 0)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.Colors.separator, lineWidth: 1)
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
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 40, height: 40)
                    .background(iconColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .truncationMode(.tail)
                    Text(value)
                        .font(Theme.Font.title2Bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer()

                if let trendIcon = trend.icon {
                    Image(systemName: trendIcon)
                        .font(.caption)
                        .foregroundStyle(trend.color)
                }
            }
            .frame(minHeight: 68)
        }
    }
}

struct CompactStatItem: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 28, height: 28)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                Text(value)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
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
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.Colors.separator, lineWidth: 1)
            )
    }

    func fadeTransition() -> some View {
        self.transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    func appCanvas() -> some View {
        self.background(Theme.Colors.background)
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
