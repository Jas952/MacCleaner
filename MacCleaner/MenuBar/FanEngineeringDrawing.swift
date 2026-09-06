import SwiftUI

/// Schematic centrifugal blower, not a measured drawing of a particular part.
/// Animation indicates rotation only; RPM comes from hardware telemetry.
struct FanEngineeringDrawing: View {
    let rpm: Int
    let maximum: Int
    let channel: Int
    let accent: Color
    var height: CGFloat = 156
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var motion = FanRotorMotion()
    private var running: Bool { rpm > 0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: reduceMotion || rpm <= 0)) { time in
            Canvas { ctx, size in
                draw(context: &ctx, size: size, time: time.date)
            }
        }
        .frame(height: height)
        .accessibilityLabel("Fan \(channel + 1) schematic, \(rpm) RPM")
    }
    private func draw(context: inout GraphicsContext, size: CGSize, time: Date) {
        var ctx = context
                let unit = min(size.width / 180, size.height / 156)
                ctx.translateBy(x: (size.width - 180 * unit) / 2, y: 0)
                ctx.scaleBy(x: unit, y: unit)
                let center = CGPoint(x: 90, y: 76)
                let ink = Color.primary.opacity(0.58)
                let faint = Color.primary.opacity(0.1)
                let measuredFraction = min(1, max(0, Double(rpm) / Double(max(1, maximum))))
                let sample = reduceMotion
                    ? FanRotorSample(phase: 0, fraction: measuredFraction)
                    : motion.sample(at: time, rpm: rpm, maximum: maximum)
                let rotation = sample.phase
                let visuallyRunning = sample.fraction > 0.002
                func line(_ points: [CGPoint], _ color: Color, _ width: CGFloat = 0.6, dash: [CGFloat] = []) {
                    var p = Path(); p.addLines(points)
                    ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dash))
                }
                func point(_ radius: Double, _ angle: Double) -> CGPoint {
                    CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                }
                for x in stride(from: 6, through: 178, by: 8) {
                    for y in stride(from: 4, through: 152, by: 8) {
                        ctx.fill(Path(ellipseIn: CGRect(x: Double(x), y: Double(y), width: 0.8, height: 0.8)), with: .color(faint))
                    }
                }
                // Center lines and machined housing / mounting lugs.
                line([CGPoint(x: 8, y: 76), CGPoint(x: 174, y: 76)], faint, dash: [4, 3])
                line([CGPoint(x: 90, y: 5), CGPoint(x: 90, y: 144)], faint, dash: [4, 3])
                let housing = CGRect(x: 28, y: 14, width: 124, height: 124)
                ctx.stroke(Path(roundedRect: housing, cornerRadius: 22), with: .color(ink), lineWidth: 1)
                ctx.stroke(Path(roundedRect: housing.insetBy(dx: 4, dy: 4), cornerRadius: 19), with: .color(faint), lineWidth: 0.6)
                for x in [38.0, 142.0] {
                    for y in [24.0, 128.0] {
                        ctx.stroke(Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(ink), lineWidth: 0.6)
                        line([CGPoint(x: x - 1.5, y: y), CGPoint(x: x + 1.5, y: y)], ink)
                    }
                }
                for r in [48.0, 53.0, 57.0] {
                    ctx.stroke(Path(ellipseIn: CGRect(x: 90-r, y: 76-r, width: 2*r, height: 2*r)), with: .color(r == 53 ? ink : faint), lineWidth: 0.7)
                }
                // Dense swept blades: genuine centrifugal-fan visual vocabulary.
                for blade in 0..<32 {
                    let angle = Double(blade) * .pi * 2 / 32 + rotation
                    var path = Path()
                    path.move(to: point(17, angle))
                    path.addQuadCurve(to: point(47, angle + 0.48), control: point(36, angle + 0.07))
                    path.addLine(to: point(47, angle + 0.56))
                    path.addQuadCurve(to: point(19, angle + 0.16), control: point(32, angle + 0.29))
                    path.closeSubpath()
                    ctx.fill(path, with: .color(accent.opacity(visuallyRunning ? 0.17 : 0.07)))
                    ctx.stroke(path, with: .color(accent.opacity(0.55)), lineWidth: 0.55)
                }
                ctx.fill(Path(ellipseIn: CGRect(x: 75, y: 61, width: 30, height: 30)), with: .color(Color(nsColor: .windowBackgroundColor)))
                ctx.stroke(Path(ellipseIn: CGRect(x: 75, y: 61, width: 30, height: 30)), with: .color(ink), lineWidth: 0.8)
                ctx.stroke(Path(ellipseIn: CGRect(x: 84, y: 70, width: 12, height: 12)), with: .color(accent), lineWidth: 1.2)
                line([CGPoint(x: 85, y: 76), CGPoint(x: 95, y: 76)], ink)
                line([CGPoint(x: 90, y: 71), CGPoint(x: 90, y: 81)], ink)
                // Exhaust duct, cooling fins, and flow direction.
                for y in stride(from: 45, through: 107, by: 5) {
                    line([CGPoint(x: 149, y: y), CGPoint(x: 161, y: y)], ink)
                }
                for y in [57.0, 76.0, 95.0] {
                    line([CGPoint(x: 163, y: y), CGPoint(x: 174, y: y)], accent.opacity(visuallyRunning ? 0.7 : 0.2))
                    line([CGPoint(x: 171, y: y-2), CGPoint(x: 174, y: y), CGPoint(x: 171, y: y+2)], accent.opacity(0.5))
                }
                // Outer calibrated arc shows measured speed fraction.
                let fraction = sample.fraction
                for tick in 0..<25 {
                    let angle = .pi * 0.7 + Double(tick) / 24 * .pi * 1.6
                    line([point(60, angle), point(tick % 6 == 0 ? 64 : 62, angle)], Double(tick)/24 <= fraction ? accent : faint, tick % 6 == 0 ? 1 : 0.65)
                }
                line([CGPoint(x: 28, y: 146), CGPoint(x: 152, y: 146)], ink)
                for x in [28.0,152.0] { line([CGPoint(x:x,y:143),CGPoint(x:x,y:149)],ink) }
                ctx.draw(Text("F0\(channel + 1) · RADIAL BLOWER").font(.system(size: 6, weight: .medium, design: .monospaced)).foregroundColor(.secondary), at: CGPoint(x: 90, y: 153))
    }

}

/// Integrates a proportional visual speed so telemetry changes accelerate and coast
/// instead of resetting the blade angle or snapping between running and stopped.
private final class FanRotorMotion {
    private var lastDate: Date?
    private var displayedFraction = 0.0
    private var phase = 0.0

    func sample(at date: Date, rpm: Int, maximum: Int) -> FanRotorSample {
        guard let lastDate else {
            self.lastDate = date
            displayedFraction = min(1, max(0, Double(rpm) / Double(max(1, maximum))))
            return FanRotorSample(phase: phase, fraction: displayedFraction)
        }
        let delta = min(0.15, max(0, date.timeIntervalSince(lastDate)))
        self.lastDate = date
        let target = min(1, max(0, Double(rpm) / Double(max(1, maximum))))
        // A blower takes time to overcome inertia and coasts after power changes.
        // The longer response also bridges one-second SMC telemetry samples.
        let response = target > displayedFraction ? 0.9 : 0.65
        displayedFraction += (target - displayedFraction) * (1 - exp(-response * delta))
        // Keep the repeated 32-blade pattern below its aliasing threshold so it
        // moves continuously instead of appearing to jump between blade slots.
        let revolutionsPerSecond = displayedFraction < 0.002 ? 0 : 0.08 + displayedFraction * 0.42
        phase = (phase + revolutionsPerSecond * delta * .pi * 2).truncatingRemainder(dividingBy: .pi * 2)
        return FanRotorSample(phase: phase, fraction: displayedFraction)
    }
}

private struct FanRotorSample {
    let phase: Double
    let fraction: Double
}

struct FanTechnicalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let active: Bool
    let accent: Color
    let label: String
    let editing: (Bool) -> Void
    let commit: () -> Void
    @FocusState private var focused: Bool
    @State private var dragging = false
    private var fraction: Double { min(1, max(0, (value-range.lowerBound) / max(1, range.upperBound-range.lowerBound))) }

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width - 18)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08)).frame(height: 5)
                    .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .padding(.horizontal, 9)
                Capsule().fill(LinearGradient(colors: [accent.opacity(0.3),accent], startPoint: .leading,endPoint: .trailing))
                    .frame(width: max(2, width * fraction), height: 5).offset(x: 9)
                HStack(spacing: 0) {
                    ForEach(0..<13) { n in
                        Rectangle().fill(Color.primary.opacity(n % 3 == 0 ? 0.3 : 0.12))
                            .frame(width: 1, height: n % 3 == 0 ? 5 : 3)
                        if n < 12 { Spacer(minLength: 0) }
                    }
                }.padding(.horizontal,9).offset(y: 13)
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(colors: [Color(nsColor: .controlBackgroundColor),Color(nsColor: .windowBackgroundColor)],startPoint:.top,endPoint:.bottom))
                    .frame(width:18,height:25)
                    .overlay(RoundedRectangle(cornerRadius:5).stroke(focused ? accent : accent.opacity(0.65),lineWidth:focused ? 2 : 1))
                    .overlay(HStack(spacing:2) { ForEach(0..<3) { _ in Capsule().fill(accent.opacity(0.6)).frame(width:1,height:9) } })
                    .shadow(color:.black.opacity(0.12),radius:2,y:1)
                    .offset(x:width*fraction)
            }
            .frame(maxHeight:.infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance:0).onChanged { gesture in
                guard active else { return }
                if !dragging { dragging = true; editing(true) }
                focused = true
                let f = min(1,max(0,(gesture.location.x-9)/width))
                let raw = range.lowerBound+f*(range.upperBound-range.lowerBound)
                value = min(range.upperBound,max(range.lowerBound,(raw/50).rounded()*50))
            }.onEnded { _ in
                guard dragging else { return }; dragging=false; editing(false); commit()
            })
        }
        .frame(height:32)
        .opacity(active ? 1 : 0.22)
        .focusable(active)
        .focused($focused)
        .fanSliderFocusEffectHidden()
        .onMoveCommand { direction in
            guard active else { return }
            if direction == .left || direction == .right {
                value = min(range.upperBound,max(range.lowerBound,value + (direction == .right ? 100 : -100)))
                commit()
            }
        }
        .accessibilityElement(children:.ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int(value)) RPM\(active ? "" : ", select Manual to adjust")")
        .accessibilityAdjustableAction { direction in
            guard active else { return }
            value = min(range.upperBound,max(range.lowerBound,value + (direction == .increment ? 100 : -100)))
            commit()
        }
    }
}

private extension View {
    @ViewBuilder
    func fanSliderFocusEffectHidden() -> some View {
        if #available(macOS 14.0, *) {
            focusEffectDisabled()
        } else {
            self
        }
    }
}
