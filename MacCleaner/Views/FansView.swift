import SwiftUI

// MARK: - Realistic Fan Component

struct RealisticFanView: View {
    let rpm: Int
    let size: CGFloat
    var isStatic: Bool = false

    @State private var isSpinning = false

    private static let bladeCount = 7

    private var period: Double {
        guard rpm > 0 else { return 2.0 }
        return 60.0 / Double(rpm)
    }

    private var speedFraction: Double { Double(rpm) / 6800.0 }
    private var blurOpacity: Double { min(speedFraction * 1.3, 0.82) }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.22), Color(white: 0.13)],
                        center: .init(x: 0.4, y: 0.35),
                        startRadius: size * 0.1,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color(white: 0.45), Color(white: 0.18)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: size * 0.03
                        )
                )
                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 4)

            if rpm > 0 {
                FanRotorView(bladeCount: Self.bladeCount, size: size,
                             rotation: isSpinning ? 360 : 0)
            } else {
                FanRotorView(bladeCount: Self.bladeCount, size: size,
                             rotation: 0)
            }

            FanHubView(size: size)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .onAppear { beginSpin() }
        .onChange(of: rpm) { _ in
            isSpinning = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { beginSpin() }
        }
    }

    private func beginSpin() {
        guard rpm > 0 && !isStatic else { return }
        withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
            isSpinning = true
        }
    }
}

// MARK: - Fan Rotor (blades)

struct FanRotorView: View {
    let bladeCount: Int
    let size: CGFloat
    var isStatic: Bool = false
    let rotation: Double

    var body: some View {
        Canvas { ctx, sz in
            let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let r = sz.width / 2
            let innerR = r * 0.14    // hub radius
            let outerR = r * 0.84   // blade tip radius

            ctx.translateBy(x: center.x, y: center.y)

            for i in 0..<bladeCount {
                let baseAngle = rotation + Double(i) * 360.0 / Double(bladeCount)
                let rad = baseAngle * .pi / 180.0

                var bladePath = Path()
                // Blade is a swept airfoil shape drawn in local coords
                // Root point (near hub)
                let rootAngleSpread: Double = 0.38  // radians of spread at root
                let tipAngleSpread: Double  = 0.22

                let rootLeft  = rad - rootAngleSpread / 2
                let rootRight = rad + rootAngleSpread / 2
                let tipLeft   = rad + 1.2 - tipAngleSpread / 2
                let tipRight  = rad + 1.2 + tipAngleSpread / 2

                let p0 = CGPoint(x: cos(rootLeft)  * innerR, y: sin(rootLeft)  * innerR)
                let p1 = CGPoint(x: cos(rootRight) * innerR, y: sin(rootRight) * innerR)
                let p2 = CGPoint(x: cos(tipRight)  * outerR, y: sin(tipRight)  * outerR)
                let p3 = CGPoint(x: cos(tipLeft)   * outerR, y: sin(tipLeft)   * outerR)

                // Control points for the curved leading/trailing edges
                let midR = (innerR + outerR) * 0.52
                let midAngleL = rad + 0.6 - 0.18
                let midAngleR = rad + 0.6 + 0.18
                let cp1 = CGPoint(x: cos(midAngleL) * midR, y: sin(midAngleL) * midR)
                let cp2 = CGPoint(x: cos(midAngleR) * midR, y: sin(midAngleR) * midR)

                bladePath.move(to: p0)
                bladePath.addQuadCurve(to: p3, control: cp1)
                bladePath.addLine(to: p2)
                bladePath.addQuadCurve(to: p1, control: cp2)
                bladePath.closeSubpath()

                // Gradient: lighter on leading edge (highlight), darker on trailing
                let brightness = 0.52 + 0.22 * cos(rad)
                let bladeColor = Color(white: brightness, opacity: 0.92)
                let shadowColor = Color(white: max(0.1, brightness - 0.22), opacity: 0.7)

                ctx.fill(bladePath, with: .linearGradient(
                    Gradient(colors: [bladeColor, shadowColor]),
                    startPoint: CGPoint(x: cos(rad - 0.5) * innerR, y: sin(rad - 0.5) * innerR),
                    endPoint:   CGPoint(x: cos(rad + 0.8) * outerR, y: sin(rad + 0.8) * outerR)
                ))

                // Thin highlight stroke on leading edge
                var edgePath = Path()
                edgePath.move(to: p0)
                edgePath.addQuadCurve(to: p3, control: cp1)
                ctx.stroke(edgePath, with: .color(.white.opacity(0.15)), lineWidth: 0.6)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Fan Hub

struct FanHubView: View {
    let size: CGFloat
    var isStatic: Bool = false

    var body: some View {
        ZStack {
            // Outer hub ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.55), Color(white: 0.28)],
                        center: .init(x: 0.35, y: 0.35),
                        startRadius: 0,
                        endRadius: size * 0.09
                    )
                )
                .frame(width: size * 0.2, height: size * 0.2)
                .overlay(Circle().strokeBorder(Color(white: 0.6), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)

            // Inner cap / screw
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.75), Color(white: 0.35)],
                        center: .init(x: 0.3, y: 0.3),
                        startRadius: 0,
                        endRadius: size * 0.04
                    )
                )
                .frame(width: size * 0.09, height: size * 0.09)

            // Screw slot line
            Rectangle()
                .fill(Color(white: 0.2, opacity: 0.8))
                .frame(width: size * 0.06, height: size * 0.012)
                .rotationEffect(.degrees(45))
        }
    }
}

struct FansView: View {
    @ObservedObject var monitor: SystemMonitor

    private var hasFans: Bool { !monitor.fans.isEmpty }

    var body: some View {
        HStack(spacing: 0) {
            // ── Left: Fans panel ──────────────────────────────────
            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cooling")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text(hasFans
                         ? "\(monitor.fans.count) fans active"
                         : "Fanless Mac")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.textTertiaryLight)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)

                Rectangle().fill(Color.borderLight).frame(height: 1)

                if hasFans {
                    fansPanel
                } else {
                    fanlessPanel
                }

                Spacer(minLength: 0)
            }
            .frame(width: 380, alignment: .top)
            .background(Color.surfaceLight)

            Rectangle().fill(Color.borderLight).frame(width: 1)

            // ── Right: Chart + Sensor list ───────────────────────
            VStack(spacing: 0) {
                ThermalChartPanel(monitor: monitor)
                    .frame(height: 160)
                Rectangle().fill(Color.borderLight).frame(height: 1)
                sensorListPanel
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, 24)
        }
        .onAppear {
            monitor.setConsumer(.fans, active: true)
            monitor.refresh(forceSensors: true)
        }
        .onDisappear {
            monitor.setConsumer(.fans, active: false)
        }
    }

    // MARK: - Fans Panel

    private var fansPanel: some View {
        VStack(spacing: 0) {
            // ── Вентиляторы (фиксированная высота) ───────────────
            HStack(spacing: 0) {
                ForEach(monitor.fans) { fan in
                    VStack(spacing: 12) {
                        // Simple fan indicator
                        fanIndicatorLight(fan)

                        Text(fan.label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Color.textPrimaryLight)

                        if fan.actualRPM > 0 {
                            VStack(spacing: 2) {
                                Text("\(fan.actualRPM)")
                                    .font(.system(size: 24, weight: .bold, design: .rounded))
                                    .foregroundStyle(rpmColor(fan))
                                Text("RPM")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Color.textTertiaryLight)
                            }
                        } else {
                            Text("Auto")
                                .font(.system(size: 16))
                                .foregroundStyle(Color.textTertiaryLight)
                        }

                        HStack(spacing: 24) {
                            VStack(spacing: 2) {
                                Text("MIN").font(.system(size: 9)).foregroundStyle(Color.textTertiaryLight)
                                Text("\(fan.minRPM)").font(.system(size: 11)).foregroundStyle(Color.textSecondaryLight)
                            }
                            VStack(spacing: 2) {
                                Text("MAX").font(.system(size: 9)).foregroundStyle(Color.textTertiaryLight)
                                Text("\(fan.maxRPM)").font(.system(size: 11)).foregroundStyle(Color.textSecondaryLight)
                            }
                        }

                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.borderLight).frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(rpmColor(fan))
                                .frame(width: max(4, 120 * fan.percentOfMax), height: 6)
                                .animation(.easeInOut(duration: 0.5), value: fan.actualRPM)
                        }
                        .frame(width: 120)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white)
                            .shadow(color: Color.shadowLight, radius: 8, x: 0, y: 2)
                    )
                    .padding(.horizontal, 12)
                    
                    if fan.id == 0 && monitor.fans.count > 1 {
                        Rectangle().fill(Color.borderLight).frame(width: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)

            // ── Температурные индикаторы ──────────────────────────
            ThermalCardsGrid(monitor: monitor)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

        }
    }

    private var fanlessPanel: some View {
        VStack(spacing: 10) {
            Image(systemName: "wind").font(.system(size: 28)).foregroundStyle(Color.textTertiaryLight)
            Text("This Mac has no fans").font(.system(size: 13, weight: .medium)).foregroundStyle(Color.textSecondaryLight)
            Text("Relies on passive cooling").font(.system(size: 9)).foregroundStyle(Color.textTertiaryLight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private func rpmColor(_ fan: FanInfo) -> Color {
        let p = fan.percentOfMax
        if p > 0.85 { return .accentRed }
        if p > 0.6  { return .accentAmber }
        return .accentGreen
    }

    private func fanIndicatorLight(_ fan: FanInfo) -> some View {
        let color = rpmColor(fan)
        let isRunning = fan.actualRPM > 0
        
        return ZStack {
            // Background circle
            Circle()
                .fill(Color.surfaceLight)
                .frame(width: 72, height: 72)

            // Inner fill showing speed level
            Circle()
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [color.opacity(0.6), color.opacity(0.2)]),
                        center: .center,
                        startRadius: 0,
                        endRadius: 36
                    )
                )
                .frame(width: 72 * fan.percentOfMax, height: 72 * fan.percentOfMax)
                .animation(.easeInOut(duration: 0.5), value: fan.actualRPM)

            // Icon
            Image(systemName: isRunning ? "fanblades.fill" : "fanblades")
                .font(.system(size: 28))
                .foregroundStyle(color)
        }
        .frame(width: 72, height: 72)
    }

    // MARK: - Sensor List Panel

    private var sensorListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 2) {
                Text("Temperatures")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.textPrimaryLight)
                Text("\(monitor.thermal.sensors.count) sensors active")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.textTertiaryLight)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)

            Rectangle().fill(Color.borderLight).frame(height: 1)

            if monitor.thermal.sensors.isEmpty {
                VStack(spacing: 8) {
                    ProgressView().scaleEffect(0.8)
                    Text("Reading sensors...").font(.system(size: 9)).foregroundStyle(Color.textTertiaryLight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        let categories = SensorCategory.allCases
                        ForEach(categories, id: \.self) { cat in
                            let catSensors = monitor.thermal.sensors.filter { $0.category == cat }
                            if !catSensors.isEmpty {
                                // Category header
                                HStack {
                                    Text(cat.rawValue.uppercased())
                                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(Color.textTertiaryLight)
                                    Rectangle().fill(Color.borderLight).frame(height: 1)
                                }
                                .padding(.horizontal, 16)
                                .padding(.top, 12)
                                .padding(.bottom, 4)

                                ForEach(catSensors) { sensor in
                                    SensorRow(sensor: sensor)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.surfaceLight)
    }
}

// MARK: - Thermal Cards Grid

struct ThermalCardsGrid: View {
    @ObservedObject var monitor: SystemMonitor

    static func heatColor(_ temp: Double) -> Color {
        switch temp {
        case ..<40: return Color.accentBlue
        case ..<55: return Color.accentGreen
        case ..<70: return Color.accentAmber
        default: return Color.accentRed
        }
    }

    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            tempCard(icon: "cpu",          label: "CPU Core", temp: monitor.thermal.cpuTemp,       maxTemp: 105)
            tempCard(icon: "memorychip",   label: "SoC",      temp: monitor.thermal.socTemp,        maxTemp: 100)
            tempCard(icon: "battery.100",  label: "Battery",  temp: monitor.battery.temperature,    maxTemp: 60)
            tempCard(icon: "externaldrive",label: "SSD",      temp: ssdTemp,                        maxTemp: 80)
        }
    }

    private var ssdTemp: Double {
        monitor.thermal.sensors.first { $0.name == "SSD 0" }?.value ??
        monitor.thermal.sensors.first { $0.name == "SSD 1" }?.value ?? 0
    }

    private func tempCard(icon: String, label: String, temp: Double, maxTemp: Double) -> some View {
        let color = Self.heatColor(temp)
        let frac = min(1.0, max(0.0, temp / maxTemp))

        return VStack(spacing: 6) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(color.opacity(0.8))
                .frame(width: 48, height: 48)
                .background(color.opacity(0.12))
                .clipShape(Circle())

            // Label
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textPrimaryLight)

            // Temperature
            Text(temp > 0 ? String(format: "%.0f°", temp) : "--°")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(color)

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.borderLight)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * CGFloat(frac), height: 6)
                }
            }
            .frame(height: 6)
            .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: Color.shadowLight, radius: 8, x: 0, y: 2)
        )
    }
}

// MARK: - Thermal Chart Panel

struct ThermalChartPanel: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var selectedSeries: Set<String> = ["CPU", "SoC", "Battery"]

    private let seriesColors: [(key: String, color: Color)] = [
        ("CPU",     .accentRed),
        ("SoC",     .accentBlue),
        ("Battery", .accentAmber),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Temperature History")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.textPrimaryLight)
                    Text(timeRangeLabel)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(Color.textTertiaryLight)
                }

                Spacer()

                // Legend toggles
                ForEach(seriesColors, id: \.key) { s in
                    Button {
                        if selectedSeries.contains(s.key) {
                            if selectedSeries.count > 1 { selectedSeries.remove(s.key) }
                        } else {
                            selectedSeries.insert(s.key)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Circle().fill(s.color)
                                .frame(width: 6, height: 6)
                                .opacity(selectedSeries.contains(s.key) ? 1 : 0.3)
                            Text(s.key)
                                .font(.mono(8))
                                .foregroundStyle(selectedSeries.contains(s.key) ? s.color : Color.textTertiaryLight)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            // Chart
            GeometryReader { geo in
                ZStack {
                    Canvas { ctx, size in
                        // Grid lines
                        drawGrid(ctx: ctx, size: size)

                        // Series lines
                        let history = monitor.thermalHistory
                        if history.count > 1 {
                            for s in seriesColors {
                                guard selectedSeries.contains(s.key) else { continue }
                                let values = history.map { point -> Double in
                                    switch s.key {
                                    case "CPU":     return point.cpu
                                    case "SoC":     return point.soc
                                    case "Battery": return point.battery
                                    default:        return 0
                                    }
                                }.filter { $0 > 0 }
                                if values.count > 1 {
                                    drawLine(ctx: ctx, size: size,
                                             values: values, color: s.color)
                                }
                            }
                        }

                        // Y-axis labels
                        drawYLabels(ctx: ctx, size: size)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(Color.surfaceLight)
    }

    // MARK: - Chart math

    private var allValues: [Double] {
        monitor.thermalHistory.flatMap { [$0.cpu, $0.soc, $0.battery] }.filter { $0 > 0 }
    }

    private var yMin: Double { max(20, (allValues.min() ?? 30) - 5) }
    private var yMax: Double { max(yMin + 20, (allValues.max() ?? 80) + 5) }

    private var timeRangeLabel: String {
        let n = monitor.thermalHistory.count
        let secs = n * 3  // 3s per sample
        if secs < 60 { return "\(secs)s history" }
        let mins = secs / 60
        return "\(mins) min history"
    }

    private func drawGrid(ctx: GraphicsContext, size: CGSize) {
        let steps = 4
        for i in 0...steps {
            let y = size.height * CGFloat(i) / CGFloat(steps)
            var p = Path()
            p.move(to: CGPoint(x: 28, y: y))
            p.addLine(to: CGPoint(x: size.width, y: y))
            ctx.stroke(p, with: .color(.white.opacity(0.05)), lineWidth: 1)
        }
    }

    private func drawYLabels(ctx: GraphicsContext, size: CGSize) {
        let steps = 4
        for i in 0...steps {
            let frac = Double(i) / Double(steps)
            let temp = yMax - frac * (yMax - yMin)
            let y = size.height * CGFloat(frac)
            let label = String(format: "%.0f°", temp)
            ctx.draw(
                Text(label).font(.system(size: 7)).foregroundColor(Color.white.opacity(0.3)),
                at: CGPoint(x: 12, y: max(6, min(y, size.height - 6)))
            )
        }
    }

    private func drawLine(ctx: GraphicsContext, size: CGSize,
                          values: [Double], color: Color) {
        let n = values.count
        let chartW = size.width - 28
        let chartX: CGFloat = 28

        var path = Path()
        var fillPath = Path()

        for (i, val) in values.enumerated() {
            let x = chartX + CGFloat(i) / CGFloat(n - 1) * chartW
            let y = size.height * CGFloat(1 - (val - yMin) / (yMax - yMin))
            let pt = CGPoint(x: x, y: max(0, min(y, size.height)))
            if i == 0 {
                path.move(to: pt)
                fillPath.move(to: CGPoint(x: x, y: size.height))
                fillPath.addLine(to: pt)
            } else {
                path.addLine(to: pt)
                fillPath.addLine(to: pt)
            }
        }

        // Fill area under line
        fillPath.addLine(to: CGPoint(x: chartX + chartW, y: size.height))
        fillPath.closeSubpath()
        ctx.fill(fillPath, with: .color(color.opacity(0.08)))

        // Line itself
        ctx.stroke(path, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

        // Current value dot
        if let lastVal = values.last {
            let x = chartX + chartW
            let y = size.height * CGFloat(1 - (lastVal - yMin) / (yMax - yMin))
            let dot = Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
            ctx.fill(dot, with: .color(color))
        }
    }
}

// MARK: - Sensor Row

struct SensorRow: View {
    let sensor: SensorReading

    private var tempColor: Color {
        if sensor.value > 90 { return .accentRed }
        if sensor.value > 75 { return .accentAmber }
        return Color.textPrimaryLight
    }

    private var barWidth: CGFloat {
        let pct = min(sensor.value / 110.0, 1.0)
        return max(2, CGFloat(pct) * 120)
    }

    private var barColor: Color {
        if sensor.value > 90 { return .accentRed }
        if sensor.value > 75 { return .accentAmber }
        if sensor.value > 55 { return .accentGreen }
        return Color.accentBlue.opacity(0.6)
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(sensor.name)
                .font(.system(size: 12))
                .foregroundStyle(Color.textSecondaryLight)
                .frame(minWidth: 160, alignment: .leading)

            // Mini bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.borderLight)
                    .frame(width: 120, height: 3)
                RoundedRectangle(cornerRadius: 2)
                    .fill(barColor)
                    .frame(width: barWidth, height: 3)
            }

            Spacer()

            Text(String(format: "%.1f °C", sensor.value))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(tempColor)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Color.surfaceLight)
        .contentShape(Rectangle())
    }
}

// MARK: - SensorCategory CaseIterable

extension SensorCategory: CaseIterable {
    static var allCases: [SensorCategory] {
        [.airflow, .cpuCore, .soc, .battery, .storage, .other]
    }
}
