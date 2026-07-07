import SwiftUI

// MARK: - Theme Manager

@MainActor
final class ThemeManager: ObservableObject {
    static let shared = ThemeManager()
    
    @AppStorage("appTheme") var currentTheme: AppTheme = .system
    @Published var effectiveColorScheme: ColorScheme = .light
    
    private init() {
        updateEffectiveScheme()
    }
    
    func updateEffectiveScheme() {
        switch currentTheme {
        case .light:
            effectiveColorScheme = .light
        case .dark:
            effectiveColorScheme = .dark
        case .system:
            effectiveColorScheme = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
        }
    }
    
    func toggleTheme() {
        switch currentTheme {
        case .light:
            currentTheme = .dark
        case .dark:
            currentTheme = .system
        case .system:
            currentTheme = .light
        }
        updateEffectiveScheme()
    }
}

enum AppTheme: String, CaseIterable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"
}

// MARK: - Color Palette (Raycast / Linear style)

extension ShapeStyle where Self == Color {
    static var textPrimary: Color   { Color(red: 0.12, green: 0.14, blue: 0.16) }
    static var textSecondary: Color { Color(red: 0.45, green: 0.48, blue: 0.52) }
    static var textTertiary: Color  { Color(red: 0.60, green: 0.63, blue: 0.67) }
    static var accent: Color        { Color(hex: "#3b82f6") }
    static var accentGreen: Color   { Color(hex: "#22c55e") }
    static var accentRed: Color     { Color(hex: "#ef4444") }
    static var accentAmber: Color   { Color(hex: "#f59e0b") }
    static var accentPurple: Color  { Color(hex: "#8b5cf6") }
    static var surfacePrimary: Color   { Color(red: 0.96, green: 0.97, blue: 0.98) }
    static var surfaceSecondary: Color { Color.white }
    static var surfaceElevated: Color  { Color.white }
    static var borderSubtle: Color  { Color.black.opacity(0.06) }
    static var borderDefault: Color { Color.black.opacity(0.11) }
    
    // Light theme colors
    static var textPrimaryLight: Color   { Color(red: 0.12, green: 0.14, blue: 0.16) }
    static var textSecondaryLight: Color { Color(red: 0.45, green: 0.48, blue: 0.52) }
    static var textTertiaryLight: Color  { Color(red: 0.60, green: 0.63, blue: 0.67) }
    static var surfaceLight: Color      { Color(red: 0.96, green: 0.97, blue: 0.98) }
    static var surfaceCardLight: Color { Color.white }
    static var borderLight: Color      { Color.black.opacity(0.06) }
    static var shadowLight: Color      { Color.black.opacity(0.04) }
    static var shadowMedium: Color     { Color.black.opacity(0.08) }
    static var accentBlue: Color        { Color(red: 0.25, green: 0.55, blue: 0.95) }
}

extension Color {
    static let textPrimary   = Color(red: 0.12, green: 0.14, blue: 0.16)
    static let textSecondary = Color(red: 0.45, green: 0.48, blue: 0.52)
    static let textTertiary  = Color(red: 0.60, green: 0.63, blue: 0.67)
    static let accent        = Color(hex: "#3b82f6")
    static let accentGreen   = Color(hex: "#22c55e")
    static let accentRed     = Color(hex: "#ef4444")
    static let accentAmber   = Color(hex: "#f59e0b")
    static let accentPurple  = Color(hex: "#8b5cf6")
    static let surfacePrimary   = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let surfaceSecondary = Color.white
    static let surfaceElevated  = Color.white
    static let borderSubtle  = Color.black.opacity(0.06)
    static let borderDefault = Color.black.opacity(0.11)

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int         & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Card Modifier

struct SurfaceCard: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.surfaceSecondary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.borderSubtle, lineWidth: 1)
            )
    }
}

extension View {
    func surfaceCard(padding: CGFloat = 16) -> some View {
        modifier(SurfaceCard(padding: padding))
    }
}

// MARK: - Minimal Progress Bar

struct MiniBar: View {
    let value: Double
    var color: Color = .accent
    var height: CGFloat = 3
    @State private var animated: Double = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.white.opacity(0.06)).frame(height: height)
                Rectangle()
                    .fill(color)
                    .frame(width: max(0, min(geo.size.width, geo.size.width * animated)), height: height)
            }
            .clipShape(Capsule())
        }
        .frame(height: height)
        .onAppear { withAnimation(.easeOut(duration: 0.8)) { animated = value } }
        .onChange(of: value) { v in withAnimation(.easeOut(duration: 0.4)) { animated = v } }
    }
}

// MARK: - Sparkline (no fill, just line)

struct Sparkline: View {
    let values: [Double]
    var color: Color = .accent
    var lineWidth: CGFloat = 1.5

    var body: some View {
        Canvas { ctx, size in
            guard values.count > 1 else { return }
            let step = size.width / Double(values.count - 1)
            var path = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: Double(i) * step, y: size.height * (1.0 - v))
                i == 0 ? path.move(to: pt) : path.addLine(to: pt)
            }
            ctx.stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Dual Sparkline (with gradients)

struct DualSparkline: View {
    let topValues: [Double]
    let bottomValues: [Double]
    var topColor: Color = .accentGreen
    var bottomColor: Color = .accentBlue

    var body: some View {
        Canvas { ctx, size in
            guard topValues.count > 1, bottomValues.count > 1 else { return }
            let step = size.width / Double(topValues.count - 1)
            let midY = size.height / 2.0
            
            // Draw top
            var topPath = Path()
            topPath.move(to: CGPoint(x: 0, y: midY))
            for (i, v) in topValues.enumerated() {
                let pt = CGPoint(x: Double(i) * step, y: midY - (midY * v))
                topPath.addLine(to: pt)
            }
            topPath.addLine(to: CGPoint(x: size.width, y: midY))
            
            var topFill = topPath
            topFill.closeSubpath()
            ctx.fill(topFill, with: .linearGradient(Gradient(colors: [topColor.opacity(0.4), topColor.opacity(0.0)]), startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: midY)))
            ctx.stroke(topPath, with: .color(topColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            // Draw bottom
            var botPath = Path()
            botPath.move(to: CGPoint(x: 0, y: midY))
            for (i, v) in bottomValues.enumerated() {
                let pt = CGPoint(x: Double(i) * step, y: midY + (midY * v))
                botPath.addLine(to: pt)
            }
            botPath.addLine(to: CGPoint(x: size.width, y: midY))
            
            var botFill = botPath
            botFill.closeSubpath()
            ctx.fill(botFill, with: .linearGradient(Gradient(colors: [bottomColor.opacity(0.0), bottomColor.opacity(0.4)]), startPoint: CGPoint(x: 0, y: midY), endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(botPath, with: .color(bottomColor), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Ring (clean, no glow)

struct ThinRing: View {
    let progress: Double
    var color: Color = .accent
    var lineWidth: CGFloat = 5
    var size: CGFloat = 48
    @State private var animated: Double = 0

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.06), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: animated)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.easeOut(duration: 0.9)) { animated = progress } }
        .onChange(of: progress) { v in withAnimation(.easeOut(duration: 0.5)) { animated = v } }
    }
}

// MARK: - Mono number style

extension Font {
    static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// MARK: - Section label

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.textTertiary)
            .kerning(0.8)
    }
}

// MARK: - App Footer

struct AppFooter: View {
    let version: String
    
    var body: some View {
        HStack {
            // Version
            Text("MacCleaner v\(version)")
                .font(.system(size: 11))
                .foregroundStyle(Color.textTertiaryLight)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.surfaceLight)
        .overlay(
            Rectangle()
                .fill(Color.borderLight)
                .frame(height: 1),
            alignment: .top
        )
    }
}

// MARK: - Core Bar Chart (per-core vertical bars)

struct CoreBarChart: View {
    let usages: [Double]

    @State private var hoveredIndex: Int? = nil

    private func color(for usage: Double) -> Color {
        usage > 0.8 ? .accentRed : usage > 0.5 ? .accentAmber : .accentBlue
    }

    var body: some View {
        GeometryReader { geo in
            let count = max(1, usages.count)
            let spacing: CGFloat = max(1, min(3, geo.size.width / CGFloat(count) * 0.15))
            let barWidth = max(2, (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(Array(usages.enumerated()), id: \.offset) { idx, usage in
                    let isHovered = hoveredIndex == idx
                    let barColor = color(for: usage)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isHovered ? barColor.opacity(1.0) : barColor.opacity(0.3 + usage * 0.7))
                        .frame(width: barWidth, height: max(2, geo.size.height * CGFloat(max(0, min(1, usage)))))
                        .onHover { isHovered in
                            hoveredIndex = isHovered ? idx : nil
                        }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .topLeading) {
                if let hoveredIndex, usages.indices.contains(hoveredIndex) {
                    let x = min(
                        max(0, CGFloat(hoveredIndex) * (barWidth + spacing) - 18),
                        max(0, geo.size.width - 58)
                    )
                    Text("C\(hoveredIndex) \(String(format: "%.0f%%", usages[hoveredIndex] * 100))")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.textPrimaryLight)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(Color.borderLight, lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.12), radius: 5, y: 2)
                        .offset(x: x, y: -26)
                        .allowsHitTesting(false)
                }
            }
        }
    }
}
