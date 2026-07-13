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
                return PaletteSpec(
                    backgroundLight: c(0.918, 0.984, 0.984), backgroundDark: c(0.038, 0.075, 0.082),
                    surfaceLight: c(0.970, 1.000, 1.000), surfaceDark: c(0.063, 0.118, 0.128),
                    sidebarLight: c(0.875, 0.976, 0.965, 0.96), sidebarDark: c(0.047, 0.102, 0.108, 0.96),
                    cardLight: c(1, 1, 1, 0.78), cardDark: c(0.078, 0.145, 0.156, 0.82),
                    elevatedLight: c(1, 1, 1, 0.88), elevatedDark: c(0.095, 0.172, 0.184, 0.90),
                    hoverLight: c(0.13, 0.78, 0.84, 0.10), hoverDark: c(0.13, 0.78, 0.84, 0.16),
                    separatorLight: c(0.06, 0.34, 0.38, 0.14), separatorDark: c(0.42, 0.92, 0.90, 0.16),
                    textPrimaryLight: c(0.063, 0.145, 0.173), textPrimaryDark: c(0.905, 0.984, 0.980),
                    textSecondaryLight: c(0.333, 0.443, 0.478), textSecondaryDark: c(0.650, 0.790, 0.805),
                    textTertiaryLight: c(0.494, 0.596, 0.624), textTertiaryDark: c(0.455, 0.610, 0.630),
                    accent: Color(red: 0.129, green: 0.784, blue: 0.839),
                    success: Color(red: 0.204, green: 0.851, blue: 0.565),
                    info: Color(red: 0.294, green: 0.639, blue: 1.000),
                    purple: Color(red: 0.455, green: 0.416, blue: 0.930),
                    teal: Color(red: 0.114, green: 0.780, blue: 0.490),
                    cyan: Color(red: 0.129, green: 0.784, blue: 0.839),
                    shadow: Color(red: 0.067, green: 0.431, blue: 0.471)
                )
            case .rose:
                return PaletteSpec(
                    backgroundLight: c(1.000, 0.940, 0.972), backgroundDark: c(0.110, 0.044, 0.078),
                    surfaceLight: c(1.000, 0.982, 0.992), surfaceDark: c(0.150, 0.068, 0.112),
                    sidebarLight: c(1.000, 0.914, 0.956, 0.96), sidebarDark: c(0.125, 0.052, 0.095, 0.96),
                    cardLight: c(1, 1, 1, 0.80), cardDark: c(0.180, 0.078, 0.128, 0.84),
                    elevatedLight: c(1, 1, 1, 0.90), elevatedDark: c(0.212, 0.092, 0.148, 0.90),
                    hoverLight: c(0.94, 0.26, 0.55, 0.10), hoverDark: c(0.96, 0.32, 0.62, 0.18),
                    separatorLight: c(0.54, 0.12, 0.30, 0.14), separatorDark: c(1.00, 0.54, 0.75, 0.18),
                    textPrimaryLight: c(0.180, 0.071, 0.112), textPrimaryDark: c(1.000, 0.916, 0.956),
                    textSecondaryLight: c(0.500, 0.300, 0.390), textSecondaryDark: c(0.860, 0.650, 0.760),
                    textTertiaryLight: c(0.650, 0.440, 0.535), textTertiaryDark: c(0.690, 0.475, 0.590),
                    accent: Color(red: 0.933, green: 0.267, blue: 0.553),
                    success: Color(red: 0.184, green: 0.792, blue: 0.525),
                    info: Color(red: 0.550, green: 0.500, blue: 1.000),
                    purple: Color(red: 0.702, green: 0.365, blue: 0.930),
                    teal: Color(red: 0.116, green: 0.720, blue: 0.620),
                    cyan: Color(red: 0.250, green: 0.760, blue: 0.900),
                    shadow: Color(red: 0.560, green: 0.120, blue: 0.320)
                )
            case .shield:
                return PaletteSpec(
                    backgroundLight: c(0.915, 0.950, 1.000), backgroundDark: c(0.018, 0.038, 0.080),
                    surfaceLight: c(0.974, 0.986, 1.000), surfaceDark: c(0.038, 0.067, 0.125),
                    sidebarLight: c(0.888, 0.930, 1.000, 0.96), sidebarDark: c(0.027, 0.055, 0.110, 0.96),
                    cardLight: c(1, 1, 1, 0.80), cardDark: c(0.050, 0.082, 0.148, 0.84),
                    elevatedLight: c(1, 1, 1, 0.92), elevatedDark: c(0.065, 0.102, 0.180, 0.90),
                    hoverLight: c(0.286, 0.416, 0.686, 0.12), hoverDark: c(0.320, 0.520, 1.000, 0.18),
                    separatorLight: c(0.120, 0.240, 0.500, 0.15), separatorDark: c(0.520, 0.700, 1.000, 0.20),
                    textPrimaryLight: c(0.048, 0.095, 0.170), textPrimaryDark: c(0.910, 0.950, 1.000),
                    textSecondaryLight: c(0.310, 0.420, 0.585), textSecondaryDark: c(0.660, 0.760, 0.900),
                    textTertiaryLight: c(0.490, 0.585, 0.720), textTertiaryDark: c(0.455, 0.555, 0.720),
                    accent: Color(red: 0.286, green: 0.416, blue: 0.686),
                    success: Color(red: 0.392, green: 0.610, blue: 1.000),
                    info: Color(red: 0.250, green: 0.520, blue: 1.000),
                    purple: Color(red: 0.455, green: 0.500, blue: 0.960),
                    teal: Color(red: 0.290, green: 0.620, blue: 0.930),
                    cyan: Color(red: 0.392, green: 0.610, blue: 1.000),
                    shadow: Color(red: 0.065, green: 0.130, blue: 0.330)
                )
            case .porcelain:
                return PaletteSpec(
                    backgroundLight: c(0.997, 0.998, 1.000), backgroundDark: c(0.045, 0.049, 0.060),
                    surfaceLight: c(1.000, 1.000, 1.000), surfaceDark: c(0.072, 0.078, 0.094),
                    sidebarLight: c(0.982, 0.986, 0.994, 0.98), sidebarDark: c(0.058, 0.064, 0.080, 0.96),
                    cardLight: c(1, 1, 1, 0.96), cardDark: c(0.094, 0.102, 0.122, 0.88),
                    elevatedLight: c(1, 1, 1, 0.99), elevatedDark: c(0.118, 0.128, 0.150, 0.94),
                    hoverLight: c(0.110, 0.155, 0.235, 0.045), hoverDark: c(0.760, 0.820, 0.900, 0.10),
                    separatorLight: c(0.125, 0.160, 0.220, 0.105), separatorDark: c(0.720, 0.780, 0.860, 0.14),
                    textPrimaryLight: c(0.052, 0.070, 0.100), textPrimaryDark: c(0.940, 0.948, 0.962),
                    textSecondaryLight: c(0.310, 0.360, 0.430), textSecondaryDark: c(0.690, 0.730, 0.790),
                    textTertiaryLight: c(0.520, 0.570, 0.640), textTertiaryDark: c(0.475, 0.525, 0.595),
                    accent: Color(red: 0.286, green: 0.416, blue: 0.686),
                    success: Color(red: 0.392, green: 0.610, blue: 1.000),
                    info: Color(red: 0.250, green: 0.520, blue: 1.000),
                    purple: Color(red: 0.470, green: 0.510, blue: 0.920),
                    teal: Color(red: 0.355, green: 0.525, blue: 0.850),
                    cyan: Color(red: 0.392, green: 0.610, blue: 1.000),
                    shadow: Color(red: 0.110, green: 0.145, blue: 0.220)
                )
            }
        }

        static func statusColor(for value: Double, thresholds: (warn: Double, danger: Double) = (0.7, 0.85)) -> Color {
            if value > thresholds.danger { return danger }
            if value > thresholds.warn { return warning }
            return success
        }
    }

    enum Gradients {
        static var accent: LinearGradient { LinearGradient(
            colors: [Colors.accent, Colors.info],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ) }
        static var hero: LinearGradient { LinearGradient(
            colors: [Colors.accent, Colors.info],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ) }
        static var success: LinearGradient { LinearGradient(
            colors: [Colors.accent.opacity(0.82), Colors.info.opacity(0.62)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ) }
        static var danger: LinearGradient { LinearGradient(
            colors: [Color.red.opacity(0.7), Color.orange.opacity(0.5)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ) }
        static var sidebar: LinearGradient { LinearGradient(
            colors: [
                Colors.elevatedCardBg.opacity(0.88),
                Colors.sidebarBg.opacity(0.96),
                Colors.accent.opacity(0.035)
            ],
            startPoint: .top, endPoint: .bottom
        ) }
        static var appBackground: LinearGradient { LinearGradient(
            colors: [
                Colors.surface,
                Colors.background,
                Colors.accent.opacity(0.035)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ) }
        static var glassStroke: LinearGradient { LinearGradient(
            colors: [
                Color.white.opacity(0.92),
                Colors.accent.opacity(0.18),
                Colors.separator.opacity(0.64)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        ) }
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
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 22
        static let xxl: CGFloat = 28
    }

    enum Shadow {
        static var smColor: Color { Colors.shadowTint.opacity(0.08) }
        static let smRadius: CGFloat = 4
        static let smY: CGFloat = 2
        static var mdColor: Color { Colors.shadowTint.opacity(0.11) }
        static let mdRadius: CGFloat = 8
        static let mdY: CGFloat = 4
        static var lgColor: Color { Colors.shadowTint.opacity(0.16) }
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
        static let expandedWidth: CGFloat = 258
        static let collapsedWidth: CGFloat = 64
        static let iconSize: CGFloat = 20
        static let itemHeight: CGFloat = 46
        static let itemRadius: CGFloat = 16
    }

    enum Card {
        static let padding: CGFloat = 16
        static let minHeight: CGFloat = 80
    }
}

struct AgentGuardMark: View {
    var size: CGFloat = 34
    var showGlow = true

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(Theme.Gradients.hero)
            RoundedRectangle(cornerRadius: size * 0.28)
                .stroke(Color.white.opacity(0.34), lineWidth: 1)
            Image(nsImage: MenuBarShieldEyeTemplateImage.shared)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.white)
                .frame(width: size * 0.58, height: size * 0.58)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: showGlow ? Theme.Colors.accent.opacity(0.24) : .clear, radius: size * 0.36, y: size * 0.12)
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
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: minHeight)
            .background(background(configuration.isPressed))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.md)
                    .stroke(strokeColor, lineWidth: 1)
            )
            .shadow(color: shadowColor(configuration.isPressed), radius: configuration.isPressed ? 4 : 14, y: configuration.isPressed ? 1 : 6)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch variant {
        case .primary, .danger: return .white
        case .secondary, .ghost: return color
        }
    }

    private var strokeColor: Color {
        switch variant {
        case .primary, .danger: return Color.white.opacity(0.28)
        case .secondary: return color.opacity(0.34)
        case .ghost: return color.opacity(0.18)
        }
    }

    private func shadowColor(_ pressed: Bool) -> Color {
        guard !pressed else { return .clear }
        switch variant {
        case .primary, .secondary, .danger: return color.opacity(0.18)
        case .ghost: return .clear
        }
    }

    @ViewBuilder
    private func background(_ pressed: Bool) -> some View {
        switch variant {
        case .primary:
            Theme.Gradients.accent
                .overlay(color.opacity(pressed ? 0.12 : 0))
        case .danger:
            Theme.Gradients.danger
                .overlay(color.opacity(pressed ? 0.12 : 0))
        case .secondary:
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(.ultraThinMaterial)
                .overlay(color.opacity(pressed ? 0.18 : 0.11))
        case .ghost:
            RoundedRectangle(cornerRadius: Theme.Radius.md)
                .fill(pressed ? color.opacity(0.12) : Theme.Colors.elevatedCardBg.opacity(0.62))
        }
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
            .background(Theme.Colors.elevatedCardBg)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: showShadow ? Theme.Shadow.lgColor : .clear, radius: showShadow ? 18 : 0, y: showShadow ? 8 : 0)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.Gradients.glassStroke, lineWidth: 1)
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
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.Gradients.hero)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
                    .shadow(color: Theme.Colors.accent.opacity(0.16), radius: 9, y: 4)

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
            .background(Theme.Colors.elevatedCardBg)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: Theme.Shadow.lgColor, radius: 16, y: 8)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Theme.Gradients.glassStroke, lineWidth: 1)
            )
    }

    func fadeTransition() -> some View {
        self.transition(.opacity.combined(with: .scale(scale: 0.96)))
    }

    func appCanvas() -> some View {
        self.background(
            ZStack {
                Theme.Gradients.appBackground
                Circle()
                    .fill(Theme.Colors.accent.opacity(0.055))
                    .frame(width: 420, height: 420)
                    .blur(radius: 70)
                    .offset(x: -260, y: -240)
                Circle()
                    .fill(Theme.Colors.info.opacity(0.045))
                    .frame(width: 360, height: 360)
                    .blur(radius: 65)
                    .offset(x: 360, y: 250)
            }
        )
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
