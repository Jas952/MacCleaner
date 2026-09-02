import AppKit
import SwiftUI

struct MenuBarGraphsView: View {
    let monitor: SystemMonitor
    @State private var mode: MenuBarGraphMode = .history
    @State private var surfaceHasLoaded = false

    init(monitor: SystemMonitor) {
        self.monitor = monitor
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--debug-thermal-") }) {
            _mode = State(initialValue: .surface)
            _surfaceHasLoaded = State(initialValue: true)
        }
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            graphPicker
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            ZStack {
                MenuBarProcessHistoryView()
                    .opacity(mode == .history ? 1 : 0)
                    .allowsHitTesting(mode == .history)
                    .accessibilityHidden(mode != .history)

                if surfaceHasLoaded {
                    MenuBarThermalSurfaceView(monitor: monitor, isActive: mode == .surface)
                        .opacity(mode == .surface ? 1 : 0)
                        .allowsHitTesting(mode == .surface)
                        .accessibilityHidden(mode != .surface)
                } else if mode == .surface {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(MenuBarGraphBackdrop())
        .onAppear {
            monitor.setConsumer(.graphs, active: true)
            if !monitor.processNodes.isEmpty {
                ProcessHistoryStore.shared.record(nodes: monitor.processNodes)
            }
            // Give the chart its lightweight process snapshot first. Sensors
            // and battery can follow without keeping the history placeholder up.
            monitor.refresh(forceProcesses: true)
            monitor.refresh(forceSensors: true, forceBattery: true)
        }
        .onDisappear {
            monitor.setConsumer(.graphs, active: false)
        }
    }

    private var graphPicker: some View {
        HStack(spacing: 4) {
            ForEach(MenuBarGraphMode.allCases) { item in
                Button {
                    selectMode(item)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: item.icon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(item.title)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(mode == item ? Color.white : Color.secondary)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        mode == item ? Color.accentBlue : Color.clear,
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(mode == item ? .isSelected : [])
            }
        }
        .padding(3)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08))
        }
    }

    private func selectMode(_ item: MenuBarGraphMode) {
        guard mode != item else { return }
        mode = item
        guard item == .surface, !surfaceHasLoaded else { return }
        Task { @MainActor in
            // Let SwiftUI commit the selected button immediately; the heavier
            // Canvas is mounted on the next run-loop turn and then retained.
            await Task.yield()
            surfaceHasLoaded = true
        }
    }
}

private enum MenuBarGraphMode: String, CaseIterable, Identifiable {
    case history
    case surface

    var id: String { rawValue }
    var title: String { self == .history ? "Processes" : "Thermal surface" }
    var icon: String { self == .history ? "waveform.path.ecg" : "square.3.layers.3d" }
}

private struct MenuBarTemperatureHistoryView: View {
    @ObservedObject var monitor: SystemMonitor
    @State private var visibleSeries: Set<ThermalSeries> = Set(ThermalSeries.allCases)

    private var samples: [ThermalPlotSample] {
        let history = monitor.thermalHistory.map {
            ThermalPlotSample(date: $0.date, cpu: $0.cpu, soc: $0.soc, gpu: $0.gpu, battery: $0.battery)
        }
        if history.count > 1 { return history }

        let now = Date()
        let current = ThermalPlotSample(
            date: now,
            cpu: monitor.thermal.cpuTemp,
            soc: monitor.thermal.socTemp,
            gpu: monitor.thermal.gpuTemp,
            battery: monitor.thermal.batteryTemp
        )
        return [current.offset(by: -1), current]
    }

    private var visibleValues: [Double] {
        ThermalSeries.allCases
            .filter(visibleSeries.contains)
            .flatMap { series in samples.map { series.value(in: $0) } }
            .filter { $0 > 0 }
    }

    private var yBounds: ClosedRange<Double> {
        guard let minimum = visibleValues.min(), let maximum = visibleValues.max() else { return 20...100 }
        let lower = max(0, floor((minimum - 8) / 10) * 10)
        let upper = max(lower + 30, ceil((maximum + 8) / 10) * 10)
        return lower...upper
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Temperature history")
                        .font(.system(size: 15, weight: .semibold))
                    Text(historyCaption)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("°C")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.thinMaterial, in: Capsule())
            }

            legend

            MenuBarThermalLineChart(
                samples: samples,
                visibleSeries: visibleSeries,
                yBounds: yBounds
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.09))
            }

            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                Text("Samples are collected locally while MacCleaner is running.")
            }
            .font(.system(size: 9))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private var legend: some View {
        HStack(spacing: 7) {
            ForEach(ThermalSeries.allCases) { series in
                Button {
                    if visibleSeries.contains(series) {
                        if visibleSeries.count > 1 { visibleSeries.remove(series) }
                    } else {
                        visibleSeries.insert(series)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(series.color)
                            .frame(width: 6, height: 6)
                            .shadow(color: series.color.opacity(visibleSeries.contains(series) ? 0.7 : 0), radius: 3)
                        Text(series.title)
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(visibleSeries.contains(series) ? Color.primary : Color.secondary.opacity(0.55))
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(Color.primary.opacity(visibleSeries.contains(series) ? 0.065 : 0.025), in: Capsule())
                }
                .buttonStyle(.plain)
                .help("Show or hide \(series.title)")
            }
        }
    }

    private var historyCaption: String {
        guard let first = samples.first?.date, let last = samples.last?.date else { return "Waiting for sensor data" }
        let duration = max(0, last.timeIntervalSince(first))
        if duration < 60 { return "Last \(max(1, Int(duration))) sec · \(samples.count) samples" }
        return "Last \(Int(duration / 60)) min · \(samples.count) samples"
    }
}

private struct MenuBarThermalLineChart: View {
    let samples: [ThermalPlotSample]
    let visibleSeries: Set<ThermalSeries>
    let yBounds: ClosedRange<Double>

    var body: some View {
        Canvas { context, size in
            let plot = CGRect(x: 38, y: 20, width: max(1, size.width - 52), height: max(1, size.height - 48))
            drawBackground(context: &context, size: size)
            drawGrid(context: &context, plot: plot)

            for series in ThermalSeries.allCases where visibleSeries.contains(series) {
                drawSeries(series, context: &context, plot: plot)
            }

            drawAxisLabels(context: &context, plot: plot)
        }
        .background(Color(red: 0.035, green: 0.065, blue: 0.085))
    }

    private func drawBackground(context: inout GraphicsContext, size: CGSize) {
        let glow = Path(ellipseIn: CGRect(x: size.width * 0.48, y: -size.height * 0.15, width: size.width * 0.75, height: size.height * 0.8))
        context.fill(
            glow,
            with: .radialGradient(
                Gradient(colors: [Color.accentBlue.opacity(0.16), .clear]),
                center: CGPoint(x: size.width * 0.76, y: size.height * 0.18),
                startRadius: 0,
                endRadius: size.width * 0.38
            )
        )
    }

    private func drawGrid(context: inout GraphicsContext, plot: CGRect) {
        for index in 0...4 {
            let fraction = CGFloat(index) / 4
            var line = Path()
            line.move(to: CGPoint(x: plot.minX, y: plot.minY + plot.height * fraction))
            line.addLine(to: CGPoint(x: plot.maxX, y: plot.minY + plot.height * fraction))
            context.stroke(line, with: .color(.white.opacity(index == 4 ? 0.13 : 0.075)), lineWidth: 0.8)
        }
        for index in 0...5 {
            let fraction = CGFloat(index) / 5
            var line = Path()
            line.move(to: CGPoint(x: plot.minX + plot.width * fraction, y: plot.minY))
            line.addLine(to: CGPoint(x: plot.minX + plot.width * fraction, y: plot.maxY))
            context.stroke(line, with: .color(.white.opacity(0.055)), lineWidth: 0.8)
        }
    }

    private func drawSeries(_ series: ThermalSeries, context: inout GraphicsContext, plot: CGRect) {
        let values = samples.map { series.value(in: $0) }
        let valid = values.enumerated().filter { $0.element > 0 }
        guard valid.count > 1 else { return }

        let points = valid.map { index, value in
            CGPoint(
                x: plot.minX + CGFloat(index) / CGFloat(max(1, samples.count - 1)) * plot.width,
                y: yPosition(value, plot: plot)
            )
        }
        let line = smoothPath(points)

        var fill = line
        if let first = points.first, let last = points.last {
            fill.addLine(to: CGPoint(x: last.x, y: plot.maxY))
            fill.addLine(to: CGPoint(x: first.x, y: plot.maxY))
            fill.closeSubpath()
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [series.color.opacity(0.26), series.color.opacity(0.015)]),
                    startPoint: CGPoint(x: plot.midX, y: plot.minY),
                    endPoint: CGPoint(x: plot.midX, y: plot.maxY)
                )
            )
        }

        context.drawLayer { layer in
            layer.addFilter(.shadow(color: series.color.opacity(0.55), radius: 5))
            layer.stroke(line, with: .color(series.color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        }

        if let last = points.last {
            context.fill(Path(ellipseIn: CGRect(x: last.x - 3, y: last.y - 3, width: 6, height: 6)), with: .color(series.color))
            context.stroke(Path(ellipseIn: CGRect(x: last.x - 5, y: last.y - 5, width: 10, height: 10)), with: .color(series.color.opacity(0.3)), lineWidth: 2)
        }
    }

    private func drawAxisLabels(context: inout GraphicsContext, plot: CGRect) {
        for index in 0...4 {
            let fraction = Double(index) / 4
            let value = yBounds.upperBound - fraction * (yBounds.upperBound - yBounds.lowerBound)
            context.draw(
                Text(String(format: "%.0f°", value))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.48)),
                at: CGPoint(x: 18, y: plot.minY + plot.height * CGFloat(fraction))
            )
        }

        context.draw(
            Text("earlier").font(.system(size: 8)).foregroundColor(.white.opacity(0.38)),
            at: CGPoint(x: plot.minX + 18, y: plot.maxY + 15)
        )
        context.draw(
            Text("now").font(.system(size: 8, weight: .semibold)).foregroundColor(.white.opacity(0.62)),
            at: CGPoint(x: plot.maxX - 10, y: plot.maxY + 15)
        )
    }

    private func yPosition(_ value: Double, plot: CGRect) -> CGFloat {
        let fraction = (value - yBounds.lowerBound) / max(1, yBounds.upperBound - yBounds.lowerBound)
        return plot.maxY - CGFloat(min(max(fraction, 0), 1)) * plot.height
    }

    private func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            let midpoint = CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2)
            path.addQuadCurve(to: midpoint, control: previous)
            if index == points.count - 1 {
                path.addQuadCurve(to: current, control: current)
            }
        }
        return path
    }
}

private struct MenuBarThermalSurfaceView: View {
    @ObservedObject var monitor: SystemMonitor
    let isActive: Bool
    @StateObject private var animator = ThermalSurfaceAnimator()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var layerSeparation = 0.0
    @State private var azimuth = -38.0
    @State private var elevation = 34.0
    @State private var zoom = 1.0
    @State private var surfaceOpacity = 1.0
    @State private var componentsOnly = false
    @State private var realisticBaseMix = 0.0
    @State private var zoomExpanded = false
    @State private var externalDisplay = ExternalDisplaySnapshot.current
    @State private var hoveredCell: ThermalSurfaceCellID?
    @State private var hoveredComponentID: String?
    @State private var hoverLocation: CGPoint?
    @State private var separationTask: Task<Void, Never>?
    @State private var isTransitioning = false
    @GestureState private var dragOffset: CGSize = .zero

    init(monitor: SystemMonitor, isActive: Bool) {
        self.monitor = monitor
        self.isActive = isActive
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--debug-thermal-components") || arguments.contains("--debug-thermal-hover-board") {
            _azimuth = State(initialValue: 0)
            _elevation = State(initialValue: 90)
            _zoom = State(initialValue: 0.90)
            _surfaceOpacity = State(initialValue: 0)
            _componentsOnly = State(initialValue: true)
        } else if arguments.contains("--debug-thermal-layers") {
            _layerSeparation = State(initialValue: 1)
        }
        if arguments.contains("--debug-thermal-hover-board") {
            _hoveredComponentID = State(initialValue: "logic-board")
        }
        if arguments.contains("--debug-thermal-hover-surface") {
            _hoveredCell = State(initialValue: ThermalSurfaceCellID(column: 9, row: 4))
            _hoverLocation = State(initialValue: CGPoint(x: 212, y: 150))
        }
        if arguments.contains("--debug-thermal-zoom") {
            _zoomExpanded = State(initialValue: true)
        }
        if arguments.contains("--debug-thermal-realistic") {
            _realisticBaseMix = State(initialValue: 1)
        }
        #endif
    }

    private var targetField: MacBookThermalField {
        MacBookThermalField(
            thermal: monitor.thermal,
            fans: monitor.fans,
            modelIdentifier: HardwareInfo.macModel
        )
    }

    private var field: MacBookThermalField {
        animator.displayedField ?? targetField
    }

    private var displayedAzimuth: Double {
        azimuth + Double(dragOffset.width) * 0.42
    }

    private var displayedElevation: Double {
        min(max(elevation - Double(dragOffset.height) * 0.24, 14), 90)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Thermal surface")
                        .font(.system(size: 15, weight: .semibold))
                    Text(HardwareInfo.macModelName)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                HStack(spacing: 12) {
                    metric(value: "\(field.activeSensorCount)", label: "sensors", color: .secondary)
                    metric(
                        value: field.maximumTemperature > 0 ? String(format: "%.0f°C", field.maximumTemperature) : "—",
                        label: "sensor peak",
                        color: field.color(for: field.maximumTemperature)
                    )
                }
            }
            .padding(.horizontal, 4)

            GeometryReader { geometry in
                ZStack(alignment: .topTrailing) {
                    TimelineView(.animation(
                        minimumInterval: 1 / 20,
                        paused: !isActive || (!field.hasActiveFans && !monitor.battery.isCharging) || reduceMotion
                    )) { timeline in
                        MenuBarThermalSurfaceCanvas(
                            field: field,
                            azimuth: displayedAzimuth,
                            elevation: displayedElevation,
                            layerSeparation: layerSeparation,
                            zoom: zoom,
                            realisticBaseMix: realisticBaseMix,
                            surfaceOpacity: surfaceOpacity,
                            hoveredCell: hoveredCell,
                            hoveredComponentID: hoveredComponentID,
                            battery: monitor.battery,
                            externalDisplay: externalDisplay,
                            animationTime: timeline.date.timeIntervalSinceReferenceDate,
                            reduceMotion: reduceMotion
                        )
                    }
                    .contentShape(Rectangle())
                    .gesture(rotationGesture)
                    .onContinuousHover { phase in
                        updateHover(phase, size: geometry.size)
                    }

                    ScrollWheelCapture { delta in
                        adjustZoom(by: delta)
                    }
                    .allowsHitTesting(false)

                    VStack(spacing: 6) {
                        surfaceControl(
                            icon: layerSeparation > 0.5 ? "rectangle.2.swap" : "square.3.layers.3d",
                            selected: layerSeparation > 0.5,
                            help: layerSeparation > 0.5 ? "Join component and heat layers" : "Separate component and heat layers"
                        ) {
                            toggleLayers()
                        }
                        .disabled(isTransitioning || componentsOnly)

                        surfaceControl(
                            icon: componentsOnly ? "waveform.path.ecg" : "cpu",
                            selected: componentsOnly,
                            help: componentsOnly ? "Show thermal surface" : "Inspect internal components"
                        ) {
                            toggleComponentsOnly()
                        }
                        .disabled(isTransitioning)

                        if HardwareInfo.macModel == "Mac15,6" {
                            surfaceControl(
                                icon: realisticBaseMix > 0.5 ? "square.grid.3x3" : "photo",
                                selected: realisticBaseMix > 0.5,
                                help: realisticBaseMix > 0.5 ? "Show schematic component layer" : "Show realistic component layer"
                            ) {
                                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                                    realisticBaseMix = realisticBaseMix > 0.5 ? 0 : 1
                                }
                            }
                            .disabled(isTransitioning)
                        }

                        surfaceControl(
                            icon: "arrow.counterclockwise",
                            selected: false,
                            help: "Reset viewing angle and scale"
                        ) {
                            resetViewingAngle(animated: true)
                        }
                        .disabled(isTransitioning)

                        zoomControl
                    }
                    .padding(9)

                    if componentsOnly, let hoveredComponentID,
                       let component = field.components.first(where: { $0.id == hoveredComponentID }) {
                        componentInfo(component)
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .allowsHitTesting(false)
                    } else if let hoveredCell, let hoverLocation {
                        temperatureTooltip(for: hoveredCell)
                            .position(
                                x: min(max(hoverLocation.x, 110), geometry.size.width - 110),
                                y: min(max(hoverLocation.y - 54, 50), geometry.size.height - 50)
                            )
                            .allowsHitTesting(false)
                    }

                    if field.hasFanTelemetry {
                        fanStatusBadge
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10))
            }

            VStack(spacing: 3) {
                LinearGradient(
                    colors: ThermalColorScale.legendColors,
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 6)
                .clipShape(Capsule())

                HStack {
                    Text("Cool ≤42°")
                    Spacer()
                    Text("Warm 58°")
                    Spacer()
                    Text("Hot 72°")
                    Spacer()
                    Text("Very hot ≥86°")
                }
            }
            .font(.system(size: 8, weight: .medium))
            .foregroundStyle(.secondary)

            Text("X: chassis width · Y: hinge to palm rest · Z: temperature")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("Measured sensors · Spatially interpolated surface · Component regions")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onAppear {
            animator.update(to: targetField, animated: false)
        }
        .onReceive(monitor.$thermal) { thermal in
            guard isActive else { return }
            animator.update(
                to: MacBookThermalField(thermal: thermal, fans: monitor.fans, modelIdentifier: HardwareInfo.macModel),
                animated: !reduceMotion
            )
        }
        .onReceive(monitor.$fans) { fans in
            guard isActive else { return }
            animator.update(
                to: MacBookThermalField(thermal: monitor.thermal, fans: fans, modelIdentifier: HardwareInfo.macModel),
                animated: !reduceMotion
            )
        }
        .onDisappear {
            separationTask?.cancel()
        }
        .onChange(of: isActive) { active in
            guard active else {
                separationTask?.cancel()
                return
            }
            animator.update(to: targetField, animated: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
            externalDisplay = .current
        }
    }

    private var rotationGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($dragOffset) { value, state, _ in
                if !componentsOnly && !isTransitioning {
                    state = value.translation
                }
            }
            .onEnded { value in
                guard !componentsOnly && !isTransitioning else { return }
                azimuth = normalizedAngle(azimuth + Double(value.translation.width) * 0.42)
                elevation = min(max(elevation - Double(value.translation.height) * 0.24, 14), 62)
            }
    }

    private func metric(value: String, label: String, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(value)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    private func surfaceControl(
        icon: String,
        selected: Bool,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.78))
                .frame(width: 28, height: 28)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .background(selected ? Color.accentBlue : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.primary.opacity(selected ? 0.03 : 0.10))
                }
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }

    private func normalizedAngle(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    private var zoomControl: some View {
        VStack(spacing: 6) {
            surfaceControl(
                icon: zoomExpanded ? "xmark" : "magnifyingglass",
                selected: zoomExpanded,
                help: zoomExpanded ? "Hide scale control" : "Adjust scale"
            ) {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.20)) {
                    zoomExpanded.toggle()
                }
            }

            if zoomExpanded {
                VStack(spacing: 5) {
                    Text("\(Int(zoom * 100))%")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))

                    Slider(value: $zoom, in: 0.72...1.48)
                        .controlSize(.mini)
                        .frame(width: 76)
                        .rotationEffect(.degrees(-90))
                        .frame(width: 24, height: 78)

                    Image(systemName: "minus")
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.vertical, 7)
                .frame(width: 38, height: 116)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.10))
                }
                .transition(
                    .opacity.combined(
                        with: .scale(scale: 0.96, anchor: .top)
                    )
                )
            }
        }
        .frame(width: 38, alignment: .top)
        .help("Thermal surface scale: \(Int(zoom * 100))%")
        .accessibilityLabel("Thermal surface scale")
        .accessibilityValue("\(Int(zoom * 100)) percent")
    }

    private func temperatureTooltip(for cell: ThermalSurfaceCellID) -> some View {
        let temperature = field.temperature(x: cell.normalizedX, y: cell.normalizedY)
        let nearest = field.nearestZone(x: cell.normalizedX, y: cell.normalizedY)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(field.color(for: temperature)).frame(width: 6, height: 6)
                Text(String(format: "≈%.0f°C", temperature))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                Spacer(minLength: 3)
                Text("Interpolated").font(.system(size: 8)).foregroundStyle(.secondary)
            }
            if let nearest {
                HStack {
                    Text("Nearest sensor").foregroundStyle(.secondary)
                    Spacer(minLength: 3)
                    Text(String(format: "%.1f°C", nearest.reading.value)).fontWeight(.semibold)
                }
                .font(.system(size: 9, design: .monospaced))
                Text("\(nearest.reading.source) · \(nearest.reading.sourceID)")
                    .font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(9)
        .frame(width: 208)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.10)))
    }

    private func updateHover(_ phase: HoverPhase, size: CGSize) {
        switch phase {
        case .active(let location):
            hoverLocation = location
            let projector = currentProjector(size: size)
            if componentsOnly {
                hoveredCell = nil
                hoveredComponentID = field.components.reversed().first(where: {
                    componentPath($0, projector: projector).contains(location)
                })?.id
            } else {
                hoveredComponentID = nil
                hoveredCell = thermalSurfaceQuads(field: field, projector: projector)
                    .sorted(by: { $0.depth > $1.depth })
                    .first(where: { $0.path.contains(location) })?
                    .id
            }
        case .ended:
            hoveredCell = nil
            hoveredComponentID = nil
            hoverLocation = nil
        }
    }

    private func currentProjector(size: CGSize) -> IsometricProjector {
        IsometricProjector(
            size: size,
            azimuthDegrees: displayedAzimuth,
            elevationDegrees: displayedElevation,
            layerSeparation: layerSeparation,
            zoom: zoom
        )
    }

    private func adjustZoom(by delta: CGFloat) {
        let next = min(max(zoom + Double(delta) * 0.012, 0.72), 1.48)
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.14)) {
            zoom = next
        }
    }

    private func resetViewingAngle(animated: Bool) {
        withAnimation(!animated || reduceMotion ? nil : .spring(response: 0.50, dampingFraction: 0.84)) {
            azimuth = componentsOnly ? 0 : -38
            elevation = componentsOnly ? 90 : 34
            zoom = componentsOnly ? 0.90 : 1
            zoomExpanded = false
        }
    }

    private func toggleLayers() {
        separationTask?.cancel()
        separationTask = Task { @MainActor in
            isTransitioning = true
            defer { isTransitioning = false }
            await animateCameraToDefault()
            await animateValue(from: layerSeparation, to: layerSeparation > 0.5 ? 0 : 1) { layerSeparation = $0 }
        }
    }

    private func toggleComponentsOnly() {
        separationTask?.cancel()
        separationTask = Task { @MainActor in
            isTransitioning = true
            defer { isTransitioning = false }
            if componentsOnly {
                await animateCamera(toAzimuth: -38, elevation: 34, zoom: 1)
                componentsOnly = false
                await animateValue(from: surfaceOpacity, to: 1) { surfaceOpacity = $0 }
            } else {
                if layerSeparation > 0.01 {
                    await animateValue(from: layerSeparation, to: 0) { layerSeparation = $0 }
                }
                zoomExpanded = false
                await animateCamera(toAzimuth: 0, elevation: 90, zoom: 0.90)
                await animateValue(from: surfaceOpacity, to: 0) { surfaceOpacity = $0 }
                hoveredCell = nil
                componentsOnly = true
            }
        }
    }

    @MainActor
    private func animateCameraToDefault() async {
        await animateCamera(toAzimuth: -38, elevation: 34, zoom: 1)
    }

    @MainActor
    private func animateCamera(toAzimuth targetAzimuth: Double, elevation targetElevation: Double, zoom targetZoom: Double) async {
        if reduceMotion {
            azimuth = targetAzimuth
            elevation = targetElevation
            zoom = targetZoom
            return
        }
        let startAzimuth = azimuth
        let startElevation = elevation
        let startZoom = zoom
        for frame in 1...18 {
            guard !Task.isCancelled else { return }
            let linear = Double(frame) / 18
            let eased = 1 - pow(1 - linear, 3)
            azimuth = startAzimuth + (targetAzimuth - startAzimuth) * eased
            elevation = startElevation + (targetElevation - startElevation) * eased
            zoom = startZoom + (targetZoom - startZoom) * eased
            try? await Task.sleep(nanoseconds: 18_000_000)
        }
    }

    @MainActor
    private func animateValue(from start: Double, to target: Double, update: (Double) -> Void) async {
        if reduceMotion {
            update(target)
            return
        }
        for frame in 1...26 {
            guard !Task.isCancelled else { return }
            let linear = Double(frame) / 26
            let eased = linear * linear * (3 - 2 * linear)
            update(start + (target - start) * eased)
            try? await Task.sleep(nanoseconds: 18_000_000)
        }
        update(target)
    }

    private func componentPath(_ component: MacBookComponent, projector: IsometricProjector) -> Path {
        if component.kind == .fan {
            var path = Path()
            for index in 0...28 {
                let angle = Double(index) / 28 * Double.pi * 2
                let point = projector.point(
                    x: component.frame.midX + cos(angle) * component.frame.width / 2,
                    y: component.frame.midY + sin(angle) * component.frame.height / 2,
                    height: 0.01,
                    layer: .base
                )
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
            path.closeSubpath()
            return path
        }
        let normalizedPoints = component.outline ?? [
            CGPoint(x: component.frame.minX, y: component.frame.minY),
            CGPoint(x: component.frame.maxX, y: component.frame.minY),
            CGPoint(x: component.frame.maxX, y: component.frame.maxY),
            CGPoint(x: component.frame.minX, y: component.frame.maxY)
        ]
        let points = normalizedPoints.map {
            projector.point(x: $0.x, y: $0.y, height: 0.008, layer: .base)
        }
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private func componentInfo(_ component: MacBookComponent) -> some View {
        let index = (field.components.firstIndex(where: { $0.id == component.id }) ?? 0) + 1
        let readings = field.readings(for: component.id).sorted { $0.value > $1.value }
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(component.tint).frame(width: 7, height: 7)
                Text(component.title.isEmpty ? component.kind.displayName : component.title)
                    .font(.system(size: 10, weight: .bold))
                Spacer(minLength: 8)
                Text("#\(index)").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            }
            Text(component.kind.role)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if component.kind == .fan {
                Text(field.fanRPMs[component.id].map { "\($0) RPM · Measured" } ?? "RPM unavailable")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
            } else if component.kind == .battery {
                Text("Charge \(monitor.battery.chargePercent)% · \(monitor.battery.cycleCount) cycles")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
            }
            if readings.isEmpty {
                Text("No mapped temperature sensor")
                    .font(.system(size: 8)).foregroundStyle(.secondary)
            } else {
                Text("MEASURED · \(readings.count) SENSOR\(readings.count == 1 ? "" : "S")")
                    .font(.system(size: 7, weight: .semibold)).foregroundStyle(.secondary)
                ForEach(Array(readings.prefix(3))) { reading in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(reading.name).lineLimit(1)
                            Spacer(minLength: 2)
                            Text(String(format: "%.1f°C", reading.value))
                                .fontWeight(.semibold).monospacedDigit()
                        }
                        .font(.system(size: 9))
                        Text("\(reading.source) · \(reading.sourceID)")
                            .font(.system(size: 7)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if readings.count > 3 {
                    Text("Top 3 by temperature · All readings in Fans")
                        .font(.system(size: 7)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(9)
        .frame(width: 206, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(component.tint.opacity(0.38))
        }
        .shadow(color: Color.black.opacity(0.10), radius: 8, y: 3)
    }

    private var fanStatusBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: field.hasActiveFans ? "fan.fill" : "fan")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(field.hasActiveFans ? Color.accentBlue : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(field.hasActiveFans ? "Cooling active" : "Fans idle")
                    .font(.system(size: 9, weight: .semibold))
                Text(field.fanStatusText)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(
                field.hasActiveFans ? Color.accentBlue.opacity(0.34) : Color.primary.opacity(0.10)
            )
        }
    }
}

private struct MenuBarThermalSurfaceCanvas: View {
    let field: MacBookThermalField
    var azimuth: Double
    var elevation: Double
    var layerSeparation: Double
    var zoom: Double
    var realisticBaseMix: Double
    var surfaceOpacity: Double
    let hoveredCell: ThermalSurfaceCellID?
    let hoveredComponentID: String?
    let battery: BatteryInfo
    let externalDisplay: ExternalDisplaySnapshot?
    let animationTime: TimeInterval
    let reduceMotion: Bool

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, AnimatablePair<Double, Double>>>> {
        get {
            AnimatablePair(
                azimuth,
                AnimatablePair(elevation, AnimatablePair(layerSeparation, AnimatablePair(zoom, realisticBaseMix)))
            )
        }
        set {
            azimuth = newValue.first
            elevation = newValue.second.first
            layerSeparation = newValue.second.second.first
            zoom = newValue.second.second.second.first
            realisticBaseMix = newValue.second.second.second.second
        }
    }

    var body: some View {
        Canvas { context, size in
            drawBackdrop(context: &context, size: size)
            let projector = IsometricProjector(
                size: size,
                azimuthDegrees: azimuth,
                elevationDegrees: elevation,
                layerSeparation: layerSeparation,
                zoom: zoom
            )
            drawCoordinateFrame(context: &context, projector: projector)
            drawDeck(context: &context, projector: projector)
            if realisticBaseMix < 0.999 {
                context.drawLayer { schematicLayer in
                    schematicLayer.opacity = 1 - realisticBaseMix
                    drawComponents(context: &schematicLayer, projector: projector)
                }
            }
            if realisticBaseMix > 0.001 {
                context.drawLayer { realisticLayer in
                    realisticLayer.opacity = realisticBaseMix
                    drawRealisticBase(context: &realisticLayer, projector: projector)
                }
            }
            drawChargingConnections(context: &context, projector: projector)
            if surfaceOpacity > 0.001 {
                context.drawLayer { thermalLayer in
                    thermalLayer.opacity = surfaceOpacity
                    drawBaseContours(context: &thermalLayer, projector: projector)
                    if layerSeparation > 0.02 {
                        drawLayerGuides(context: &thermalLayer, projector: projector)
                    }
                    drawSurface(context: &thermalLayer, projector: projector)
                }
                // Airflow is an operational overlay, not part of the heat mesh.
                // Draw it at full contrast so active fans remain visible over a
                // translucent surface and in light appearance.
                drawAirflow(context: &context, projector: projector)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("MacBook thermal surface, peak \(Int(field.maximumTemperature)) degrees Celsius")
    }

    private func drawBackdrop(context: inout GraphicsContext, size: CGSize) {
        let glow = Path(ellipseIn: CGRect(x: size.width * 0.12, y: size.height * 0.10, width: size.width * 0.78, height: size.height * 0.72))
        context.fill(
            glow,
            with: .radialGradient(
                Gradient(colors: [field.color(for: field.maximumTemperature).opacity(0.12), .clear]),
                center: CGPoint(x: size.width * 0.52, y: size.height * 0.42),
                startRadius: 4,
                endRadius: size.width * 0.42
            )
        )
    }

    private func drawDeck(context: inout GraphicsContext, projector: IsometricProjector) {
        let corners = [
            projector.point(x: 0, y: 0, height: 0, layer: .base),
            projector.point(x: 1, y: 0, height: 0, layer: .base),
            projector.point(x: 1, y: 1, height: 0, layer: .base),
            projector.point(x: 0, y: 1, height: 0, layer: .base)
        ]
        var deck = Path()
        deck.move(to: corners[0])
        corners.dropFirst().forEach { deck.addLine(to: $0) }
        deck.closeSubpath()
        context.fill(deck, with: .color(Color.primary.opacity(0.035)))
        context.stroke(deck, with: .color(Color.primary.opacity(0.24)), lineWidth: 1)

        var hinge = Path()
        hinge.move(to: projector.point(x: 0, y: 0, height: 0, layer: .base))
        hinge.addLine(to: projector.point(x: 1, y: 0, height: 0, layer: .base))
        context.stroke(hinge, with: .color(Color.primary.opacity(0.44)), lineWidth: 2)
    }

    private func drawComponents(context: inout GraphicsContext, projector: IsometricProjector) {
        for component in field.components {
            let selected = component.id == hoveredComponentID
            let path: Path
            if component.kind == .fan {
                path = projectedEllipse(in: component.frame, projector: projector, layer: .base)
            } else if let outline = component.outline {
                path = projectedPolygon(outline, projector: projector, layer: .base)
            } else {
                path = projectedRect(component.frame, projector: projector, layer: .base)
            }
            if selected {
                context.drawLayer { layer in
                    layer.addFilter(.shadow(color: component.tint.opacity(0.60), radius: 7))
                    layer.fill(path, with: .color(component.tint.opacity(0.38)))
                }
            } else {
                context.fill(path, with: .color(component.tint.opacity(component.kind == .trackpad ? 0.07 : 0.15)))
            }
            context.stroke(path, with: .color(component.tint.opacity(selected ? 0.95 : 0.46)), lineWidth: selected ? 1.7 : 0.7)

            if component.kind == .fan {
                drawFanBlades(component: component, context: &context, projector: projector)
            }

            let labelPoint = projector.point(
                x: component.frame.midX,
                y: component.kind == .battery ? component.frame.minY + 0.075 : component.frame.midY,
                height: 0.012,
                layer: .base
            )
            context.draw(
                Text(component.title)
                    .font(.system(size: component.kind == .battery ? 6 : 7, weight: .bold, design: .rounded))
                    .foregroundColor(.primary.opacity(component.kind == .trackpad ? 0.42 : 0.66)),
                at: labelPoint
            )
        }
    }

    private func drawRealisticBase(context: inout GraphicsContext, projector: IsometricProjector) {
        let origin = projector.point(x: 0, y: 0, height: 0.006, layer: .base)
        let xEdge = projector.point(x: 1, y: 0, height: 0.006, layer: .base)
        let yEdge = projector.point(x: 0, y: 1, height: 0.006, layer: .base)
        let transform = CGAffineTransform(
            a: xEdge.x - origin.x,
            b: xEdge.y - origin.y,
            c: yEdge.x - origin.x,
            d: yEdge.y - origin.y,
            tx: origin.x,
            ty: origin.y
        )
        let image = context.resolve(Image("thermal_realistic_m3pro"))
        context.concatenate(transform)
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    private func drawSurface(context: inout GraphicsContext, projector: IsometricProjector) {
        for quadData in thermalSurfaceQuads(field: field, projector: projector).sorted(by: { $0.depth < $1.depth }) {
            let isHovered = quadData.id == hoveredCell
            let color = field.color(for: quadData.temperature)
            context.fill(quadData.path, with: .color(color.opacity(isHovered ? 0.86 : 0.58)))
            context.stroke(
                quadData.path,
                with: .color(isHovered ? Color.primary.opacity(0.86) : Color.primary.opacity(0.20)),
                lineWidth: isHovered ? 1.45 : 0.48
            )
        }
    }

    private func drawCoordinateFrame(context: inout GraphicsContext, projector: IsometricProjector) {
        for index in 0...5 {
            let value = Double(index) / 5
            var xGrid = Path()
            xGrid.move(to: projector.point(x: value, y: 0, height: 0, layer: .base))
            xGrid.addLine(to: projector.point(x: value, y: 1, height: 0, layer: .base))
            context.stroke(xGrid, with: .color(.primary.opacity(0.075)), lineWidth: 0.55)

            var yGrid = Path()
            yGrid.move(to: projector.point(x: 0, y: value, height: 0, layer: .base))
            yGrid.addLine(to: projector.point(x: 1, y: value, height: 0, layer: .base))
            context.stroke(yGrid, with: .color(.primary.opacity(0.075)), lineWidth: 0.55)
        }

        let origin = projector.point(x: 0, y: 1, height: 0, layer: .base)
        let xEnd = projector.point(x: 1, y: 1, height: 0, layer: .base)
        let yEnd = projector.point(x: 0, y: 0, height: 0, layer: .base)
        drawAxis(from: origin, to: xEnd, title: "X · WIDTH", context: &context)
        drawAxis(from: origin, to: yEnd, title: "Y · DEPTH", context: &context)

        // In the component inspector the camera is exactly top-down, so the
        // projected Z axis collapses to one point. Omitting it prevents the
        // temperature ticks from stacking on top of each other in the corner.
        if surfaceOpacity > 0.001 {
            let zEnd = projector.point(x: 0, y: 1, height: 1, layer: .axis)
            drawAxis(from: origin, to: zEnd, title: "Z · °C", context: &context)

            for index in 1...4 {
                let value = Double(index) / 4
                let point = projector.point(x: 0, y: 1, height: value, layer: .axis)
                context.draw(
                    Text("\(Int(25 + value * (field.temperatureCeiling - 25)))°")
                        .font(.system(size: 6, weight: .medium, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.42)),
                    at: CGPoint(x: point.x - 11, y: point.y)
                )
            }
        }
    }

    private func drawAxis(from start: CGPoint, to end: CGPoint, title: String, context: inout GraphicsContext) {
        var path = Path()
        path.move(to: start)
        path.addLine(to: end)
        context.stroke(path, with: .color(.primary.opacity(0.38)), lineWidth: 0.9)
        context.draw(
            Text(title).font(.system(size: 6, weight: .bold, design: .rounded)).foregroundColor(.primary.opacity(0.58)),
            at: CGPoint(x: end.x, y: end.y - 7)
        )
    }

    private func drawBaseContours(context: inout GraphicsContext, projector: IsometricProjector) {
        for zone in field.zones {
            for scale in [0.38, 0.64, 0.92] {
                let rect = CGRect(
                    x: zone.center.x - zone.radius.width * scale,
                    y: zone.center.y - zone.radius.height * scale,
                    width: zone.radius.width * scale * 2,
                    height: zone.radius.height * scale * 2
                )
                let contour = projectedEllipse(in: rect, projector: projector, layer: .base)
                context.stroke(contour, with: .color(field.color(for: zone.temperature).opacity(0.24)), lineWidth: 0.7)
            }
        }
    }

    private func drawLayerGuides(context: inout GraphicsContext, projector: IsometricProjector) {
        for zone in field.zones {
            var guide = Path()
            guide.move(to: projector.point(x: zone.center.x, y: zone.center.y, height: 0.015, layer: .base))
            guide.addLine(to: projector.point(x: zone.center.x, y: zone.center.y, height: field.height(for: zone.temperature), layer: .surface))
            context.stroke(
                guide,
                with: .color(field.color(for: zone.temperature).opacity(0.34)),
                style: StrokeStyle(lineWidth: 0.7, dash: [3, 3])
            )
        }
    }

    private func drawFanBlades(
        component: MacBookComponent,
        context: inout GraphicsContext,
        projector: IsometricProjector
    ) {
        let center = CGPoint(x: component.frame.midX, y: component.frame.midY)
        let radius = min(component.frame.width, component.frame.height) * 0.39
        for index in 0..<6 {
            let angle = Double(index) / 6 * Double.pi * 2
            var blade = Path()
            blade.move(to: projector.point(x: center.x, y: center.y, height: 0.014, layer: .base))
            blade.addLine(to: projector.point(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius,
                height: 0.014,
                layer: .base
            ))
            context.stroke(blade, with: .color(.primary.opacity(0.28)), lineWidth: 0.65)
        }
    }

    private func drawAirflow(context: inout GraphicsContext, projector: IsometricProjector) {
        for component in field.components where component.kind == .fan {
            let rpm = field.fanRPM(for: component.id)
            guard rpm > 0 else { continue }
            let speed = min(max(Double(rpm) / 6_800, 0.15), 1)
            let cycle = reduceMotion ? 0.38 : (animationTime * (0.32 + speed * 0.72)).truncatingRemainder(dividingBy: 1)
            let centerX = component.frame.midX
            let centerY = component.frame.midY
            let plumeHeight = 0.52 + speed * 0.16

            // Animated projected cross-sections make the stream read as a
            // volume in world space instead of several lines on one plane.
            for slice in 0..<7 {
                let progress = (cycle + Double(slice) / 7).truncatingRemainder(dividingBy: 1)
                let height = 0.055 + progress * plumeHeight
                let radius = 0.030 + progress * 0.035
                let ring = airflowRing(
                    centerX: centerX,
                    centerY: centerY,
                    radius: radius,
                    height: height,
                    projector: projector
                )
                context.fill(ring, with: .color(Color.accentBlue.opacity(0.035 * (1 - progress))))
                context.stroke(
                    ring,
                    with: .color(Color.accentBlue.opacity(0.58 * (1 - progress))),
                    style: StrokeStyle(lineWidth: 1.0, lineCap: .round, dash: [2.5, 3.5], dashPhase: CGFloat(cycle * 18))
                )
            }

            // Three helical streamlines occupy different depth planes and
            // expose rotation/parallax as the user turns the thermal model.
            for lane in 0..<3 {
                var stream = Path()
                for step in 0...28 {
                    let progress = Double(step) / 28
                    let angle = progress * .pi * 4 + Double(lane) * (.pi * 2 / 3) + cycle * .pi * 2
                    let radius = 0.018 + progress * 0.025
                    let point = projector.point(
                        x: centerX + cos(angle) * radius,
                        y: centerY + sin(angle) * radius,
                        height: 0.055 + progress * plumeHeight,
                        layer: .base
                    )
                    step == 0 ? stream.move(to: point) : stream.addLine(to: point)
                }
                context.stroke(
                    stream,
                    with: .linearGradient(
                        Gradient(colors: [Color.cyan.opacity(0.82), Color.accentBlue.opacity(0.55), .clear]),
                        startPoint: projector.point(x: centerX, y: centerY, height: 0.04, layer: .base),
                        endPoint: projector.point(x: centerX, y: centerY, height: 0.72, layer: .base)
                    ),
                    style: StrokeStyle(lineWidth: lane == 1 ? 1.8 : 1.25, lineCap: .round)
                )
            }

            for particle in 0..<10 {
                let progress = (cycle + Double(particle) / 10).truncatingRemainder(dividingBy: 1)
                let angle = progress * .pi * 5 + Double(particle) * 1.7
                let radial = 0.015 + progress * 0.038
                let point = projector.point(
                    x: centerX + cos(angle) * radial,
                    y: centerY + sin(angle) * radial,
                    height: 0.075 + progress * plumeHeight,
                    layer: .base
                )
                let radius = 1.15 + CGFloat(1 - progress) * 1.25
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(Color.cyan.opacity(0.80 * (1 - progress)))
                )
            }
        }
    }

    private func airflowRing(
        centerX: Double,
        centerY: Double,
        radius: Double,
        height: Double,
        projector: IsometricProjector
    ) -> Path {
        var path = Path()
        for index in 0...24 {
            let angle = Double(index) / 24 * .pi * 2
            let point = projector.point(
                x: centerX + cos(angle) * radius,
                y: centerY + sin(angle) * radius,
                height: height,
                layer: .base
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func drawChargingConnections(context: inout GraphicsContext, projector: IsometricProjector) {
        drawPortMap(context: &context, projector: projector)
        guard battery.isPluggedIn else { return }
        let port = battery.powerPort ?? .usbCUnknown
        let portPoint = powerPortPoint(port, projector: projector)
        let cableStart = CGPoint(
            x: portPoint.x + (isLeftPort(port) ? -34 : 34),
            y: portPoint.y + 7
        )
        let accent = battery.isCharging ? Color.accentGreen : Color.accentBlue
        let phase = reduceMotion ? 0.5 : animationTime.truncatingRemainder(dividingBy: 1)
        let displayLabel: String?
        if port != .magSafe,
           let externalDisplay,
           externalDisplay.matches(powerVendorID: battery.powerVendorID) {
            displayLabel = battery.adapterWatts > 0
                ? "\(externalDisplay.compactLabel) · \(battery.adapterWatts) W"
                : externalDisplay.compactLabel
        } else {
            displayLabel = nil
        }
        let powerLabel = battery.adapterWatts > 0
            ? "\(port.displayName) · \(battery.adapterWatts) W"
            : port.displayName
        drawPowerCable(
            from: cableStart,
            to: portPoint,
            label: displayLabel ?? powerLabel,
            labelPoint: CGPoint(
                x: portPoint.x + (isLeftPort(port) ? 56 : -56),
                y: portPoint.y + 18
            ),
            accent: accent,
            phase: phase,
            context: &context
        )

        let badgePoint = CGPoint(x: portPoint.x, y: portPoint.y - 20)
        context.draw(
            Text("\(battery.isCharging ? "⚡" : "●") \(battery.chargePercent)%")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundColor(accent),
            at: badgePoint
        )
    }

    private func drawPortMap(context: inout GraphicsContext, projector: IsometricProjector) {
        let ports: [(MacBookPowerPort, String)] = [
            (.magSafe, "M"),
            (.leftUSBCTop, "C"),
            (.leftUSBCBottom, "C"),
            (.rightUSBC, "C")
        ]
        for (port, symbol) in ports {
            let point = powerPortPoint(port, projector: projector)
            let rect = CGRect(x: point.x - 4, y: point.y - 2, width: 8, height: 4)
            context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Color.primary.opacity(0.12)))
            context.stroke(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(Color.primary.opacity(0.36)), lineWidth: 0.55)
            context.draw(
                Text(symbol).font(.system(size: 4, weight: .bold)).foregroundColor(.secondary),
                at: CGPoint(x: point.x, y: point.y + 7)
            )
        }
    }

    private func powerPortPoint(_ port: MacBookPowerPort, projector: IsometricProjector) -> CGPoint {
        switch port {
        case .magSafe: return projector.point(x: 0.008, y: 0.18, height: 0.012, layer: .base)
        case .leftUSBCTop: return projector.point(x: 0.008, y: 0.31, height: 0.012, layer: .base)
        case .leftUSBCBottom: return projector.point(x: 0.008, y: 0.44, height: 0.012, layer: .base)
        case .rightUSBC: return projector.point(x: 0.992, y: 0.31, height: 0.012, layer: .base)
        case .usbCUnknown: return projector.point(x: 0.008, y: 0.31, height: 0.012, layer: .base)
        }
    }

    private func isLeftPort(_ port: MacBookPowerPort) -> Bool {
        port != .rightUSBC
    }

    private func drawPowerCable(
        from start: CGPoint,
        to end: CGPoint,
        label: String,
        labelPoint: CGPoint,
        accent: Color,
        phase: Double,
        context: inout GraphicsContext
    ) {
        var cable = Path()
        cable.move(to: start)
        cable.addQuadCurve(
            to: end,
            control: CGPoint(x: (start.x + end.x) / 2, y: max(start.y, end.y) + 8)
        )
        context.stroke(cable, with: .color(Color.primary.opacity(0.34)), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        let connector = CGRect(x: start.x - 6, y: start.y - 3, width: 12, height: 6)
        context.fill(Path(roundedRect: connector, cornerRadius: 2), with: .color(Color.primary.opacity(0.18)))
        context.stroke(Path(roundedRect: connector, cornerRadius: 2), with: .color(accent.opacity(0.72)), lineWidth: 0.8)

        if battery.isCharging {
            for ring in 0..<3 {
                let radius = CGFloat(5 + ring * 4) + CGFloat(phase * 3)
                context.stroke(
                    Path(ellipseIn: CGRect(x: end.x - radius, y: end.y - radius * 0.55, width: radius * 2, height: radius * 1.1)),
                    with: .color(Color.accentGreen.opacity(0.34 - Double(ring) * 0.08)),
                    lineWidth: 0.8
                )
            }
        }

        if battery.isCharging {
            let pulse = CGPoint(
                x: start.x + (end.x - start.x) * phase,
                y: start.y + (end.y - start.y) * phase + sin(phase * .pi) * 5
            )
            context.drawLayer { layer in
                layer.addFilter(.shadow(color: accent.opacity(0.75), radius: 4))
                layer.fill(Path(ellipseIn: CGRect(x: pulse.x - 2, y: pulse.y - 2, width: 4, height: 4)), with: .color(accent))
            }
        }
        context.draw(
            Text(label).font(.system(size: 6, weight: .semibold)).foregroundColor(.secondary),
            at: labelPoint
        )
    }

    private func projectedRect(
        _ rect: CGRect,
        projector: IsometricProjector,
        layer: IsometricLayer
    ) -> Path {
        let points = [
            projector.point(x: rect.minX, y: rect.minY, height: 0.008, layer: layer),
            projector.point(x: rect.maxX, y: rect.minY, height: 0.008, layer: layer),
            projector.point(x: rect.maxX, y: rect.maxY, height: 0.008, layer: layer),
            projector.point(x: rect.minX, y: rect.maxY, height: 0.008, layer: layer)
        ]
        var path = Path()
        path.move(to: points[0])
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }

    private func projectedEllipse(
        in rect: CGRect,
        projector: IsometricProjector,
        layer: IsometricLayer
    ) -> Path {
        var path = Path()
        for index in 0...28 {
            let angle = Double(index) / 28 * Double.pi * 2
            let point = projector.point(
                x: rect.midX + cos(angle) * rect.width / 2,
                y: rect.midY + sin(angle) * rect.height / 2,
                height: 0.01,
                layer: layer
            )
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }

    private func projectedPolygon(
        _ points: [CGPoint],
        projector: IsometricProjector,
        layer: IsometricLayer
    ) -> Path {
        var path = Path()
        for (index, point) in points.enumerated() {
            let projected = projector.point(x: point.x, y: point.y, height: 0.01, layer: layer)
            index == 0 ? path.move(to: projected) : path.addLine(to: projected)
        }
        path.closeSubpath()
        return path
    }
}

private struct ExternalDisplaySnapshot {
    let name: String
    let width: Int
    let height: Int
    let vendorID: UInt32

    var compactLabel: String { "\(name) · \(width)×\(height)" }

    func matches(powerVendorID: Int) -> Bool {
        // USB-IF and display EDID vendor identifiers use different namespaces.
        // Keep correlation deliberately narrow instead of attaching any display
        // to any charging cable. Dell: USB VID 0x413C, EDID vendor 0x10AC.
        powerVendorID == 0x413C && vendorID == 0x10AC
    }

    @MainActor
    static var current: ExternalDisplaySnapshot? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard CGDisplayIsBuiltin(displayID) == 0 else { continue }
            let pixels = screen.convertRectToBacking(screen.frame)
            return ExternalDisplaySnapshot(
                name: screen.localizedName,
                width: Int(pixels.width.rounded()),
                height: Int(pixels.height.rounded()),
                vendorID: CGDisplayVendorNumber(displayID)
            )
        }
        return nil
    }
}

private struct ThermalSurfaceCellID: Hashable {
    static let columns = 20
    static let rows = 16

    let column: Int
    let row: Int

    var normalizedX: Double { (Double(column) + 0.5) / Double(Self.columns) }
    var normalizedY: Double { (Double(row) + 0.5) / Double(Self.rows) }
}

private struct ThermalSurfaceQuad {
    let id: ThermalSurfaceCellID
    let points: [CGPoint]
    let temperature: Double
    let depth: CGFloat

    var path: Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        points.dropFirst().forEach { path.addLine(to: $0) }
        path.closeSubpath()
        return path
    }
}

private func thermalSurfaceQuads(
    field: MacBookThermalField,
    projector: IsometricProjector
) -> [ThermalSurfaceQuad] {
    guard !field.zones.isEmpty else { return [] }
    var quads: [ThermalSurfaceQuad] = []
    for row in 0..<ThermalSurfaceCellID.rows {
        for column in 0..<ThermalSurfaceCellID.columns {
            let x0 = Double(column) / Double(ThermalSurfaceCellID.columns)
            let x1 = Double(column + 1) / Double(ThermalSurfaceCellID.columns)
            let y0 = Double(row) / Double(ThermalSurfaceCellID.rows)
            let y1 = Double(row + 1) / Double(ThermalSurfaceCellID.rows)
            let temperatures = [
                field.temperature(x: x0, y: y0),
                field.temperature(x: x1, y: y0),
                field.temperature(x: x1, y: y1),
                field.temperature(x: x0, y: y1)
            ]
            let points = [
                projector.point(x: x0, y: y0, height: field.height(for: temperatures[0]), layer: .surface),
                projector.point(x: x1, y: y0, height: field.height(for: temperatures[1]), layer: .surface),
                projector.point(x: x1, y: y1, height: field.height(for: temperatures[2]), layer: .surface),
                projector.point(x: x0, y: y1, height: field.height(for: temperatures[3]), layer: .surface)
            ]
            quads.append(ThermalSurfaceQuad(
                id: ThermalSurfaceCellID(column: column, row: row),
                points: points,
                temperature: temperatures.reduce(0, +) / Double(temperatures.count),
                depth: points.map(\.y).reduce(0, +) / 4
            ))
        }
    }
    return quads
}

private struct ThermalPlotSample {
    let date: Date
    let cpu: Double
    let soc: Double
    let gpu: Double
    let battery: Double

    func offset(by seconds: TimeInterval) -> ThermalPlotSample {
        ThermalPlotSample(date: date.addingTimeInterval(seconds), cpu: cpu, soc: soc, gpu: gpu, battery: battery)
    }
}

private enum ThermalSeries: String, CaseIterable, Identifiable {
    case cpu
    case soc
    case gpu
    case battery

    var id: String { rawValue }
    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .soc: return "SoC"
        case .gpu: return "GPU"
        case .battery: return "Battery"
        }
    }
    var color: Color {
        switch self {
        case .cpu: return Color(red: 1.0, green: 0.36, blue: 0.23)
        case .soc: return Color(red: 0.26, green: 0.68, blue: 1.0)
        case .gpu: return Color(red: 0.67, green: 0.43, blue: 1.0)
        case .battery: return Color(red: 0.28, green: 0.86, blue: 0.58)
        }
    }

    func value(in sample: ThermalPlotSample) -> Double {
        switch self {
        case .cpu: return sample.cpu
        case .soc: return sample.soc
        case .gpu: return sample.gpu
        case .battery: return sample.battery
        }
    }
}

enum ThermalColorScale {
    private struct Stop {
        let temperature: Double
        let red: Double
        let green: Double
        let blue: Double
    }

    private static let stops = [
        Stop(temperature: 25, red: 0.18, green: 0.62, blue: 0.96),
        Stop(temperature: 42, red: 0.25, green: 0.82, blue: 0.62),
        Stop(temperature: 58, red: 0.98, green: 0.76, blue: 0.22),
        Stop(temperature: 72, red: 1.00, green: 0.42, blue: 0.16),
        Stop(temperature: 86, red: 0.94, green: 0.18, blue: 0.32)
    ]

    static var legendColors: [Color] {
        stops.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }

    static func status(for temperature: Double) -> String {
        switch temperature {
        case ..<42: return "Cool"
        case ..<58: return "OK"
        case ..<72: return "Warm"
        case ..<86: return "Hot"
        default: return "Very hot"
        }
    }

    static func color(for temperature: Double) -> Color {
        guard temperature > 0 else { return .secondary }
        guard let upperIndex = stops.firstIndex(where: { temperature <= $0.temperature }) else {
            let last = stops[stops.count - 1]
            return Color(red: last.red, green: last.green, blue: last.blue)
        }
        guard upperIndex > 0 else {
            let first = stops[0]
            return Color(red: first.red, green: first.green, blue: first.blue)
        }
        let lower = stops[upperIndex - 1]
        let upper = stops[upperIndex]
        let fraction = min(max((temperature - lower.temperature) / (upper.temperature - lower.temperature), 0), 1)
        return Color(
            red: lower.red + (upper.red - lower.red) * fraction,
            green: lower.green + (upper.green - lower.green) * fraction,
            blue: lower.blue + (upper.blue - lower.blue) * fraction
        )
    }
}

enum MacBookComponentKind {
    case board
    case storage
    case fan
    case battery
    case trackpad
    case speaker
    case vent

    var displayName: String {
        switch self {
        case .board: return "Logic board"
        case .storage: return "SSD storage"
        case .fan: return "Cooling fan"
        case .battery: return "Battery pack"
        case .trackpad: return "Trackpad"
        case .speaker: return "Speaker"
        case .vent: return "Exhaust vent"
        }
    }

    var role: String {
        switch self {
        case .board: return "Main board with Apple silicon, memory and power controllers."
        case .storage: return "Soldered flash storage modules on the logic board."
        case .fan: return "Moves air through the heat-sink and rear exhaust."
        case .battery: return "Integrated top-case battery pack. The projection does not claim a physical cell count."
        case .trackpad: return "Top-case projection; shown to preserve internal spatial reference."
        case .speaker: return "Speaker enclosure positioned beside the keyboard, toward the hinge."
        case .vent: return "Rear exhaust path along the display hinge."
        }
    }
}

struct MacBookComponent {
    let id: String
    let title: String
    let frame: CGRect
    let kind: MacBookComponentKind
    let tint: Color
    var outline: [CGPoint]? = nil
}

struct MacBookComponentLayout {
    let name: String
    let components: [MacBookComponent]

    init(isAir: Bool) {
        let structural: [MacBookComponent] = [
            .init(id: "vent", title: "VENT", frame: CGRect(x: 0.055, y: 0.045, width: 0.89, height: 0.035), kind: .vent, tint: .white),
            .init(id: "speaker-left", title: "", frame: CGRect(x: 0.025, y: 0.29, width: 0.070, height: 0.37), kind: .speaker, tint: .white),
            .init(id: "speaker-right", title: "", frame: CGRect(x: 0.905, y: 0.29, width: 0.070, height: 0.37), kind: .speaker, tint: .white),
            .init(
                id: "battery-pack",
                title: "BATTERY PACK",
                frame: CGRect(x: 0.105, y: 0.48, width: 0.79, height: 0.45),
                kind: .battery,
                tint: .accentGreen,
                outline: [
                    CGPoint(x: 0.105, y: 0.48),
                    CGPoint(x: 0.895, y: 0.48),
                    CGPoint(x: 0.895, y: 0.93),
                    CGPoint(x: 0.69, y: 0.93),
                    CGPoint(x: 0.69, y: 0.61),
                    CGPoint(x: 0.31, y: 0.61),
                    CGPoint(x: 0.31, y: 0.93),
                    CGPoint(x: 0.105, y: 0.93)
                ]
            ),
            .init(id: "trackpad", title: "TRACKPAD", frame: CGRect(x: 0.33, y: 0.61, width: 0.34, height: 0.29), kind: .trackpad, tint: .white)
        ]

        if isAir {
            name = "MacBook Air passive-cooling layout"
            components = [
                .init(id: "logic-board", title: "LOGIC BOARD", frame: CGRect(x: 0.23, y: 0.12, width: 0.54, height: 0.20), kind: .board, tint: .accentAmber),
                .init(id: "storage", title: "SSD", frame: CGRect(x: 0.63, y: 0.17, width: 0.09, height: 0.10), kind: .storage, tint: .accentBlue)
            ] + structural
        } else {
            name = "MacBook Pro dual-fan layout"
            components = [
                .init(id: "fan-left", title: "FAN L", frame: CGRect(x: 0.075, y: 0.105, width: 0.225, height: 0.245), kind: .fan, tint: .accentBlue),
                .init(id: "logic-board", title: "LOGIC BOARD", frame: CGRect(x: 0.275, y: 0.09, width: 0.45, height: 0.36), kind: .board, tint: .accentAmber),
                .init(id: "fan-right", title: "FAN R", frame: CGRect(x: 0.70, y: 0.105, width: 0.225, height: 0.245), kind: .fan, tint: .accentBlue)
            ] + structural
        }
    }
}

@MainActor
private final class ThermalSurfaceAnimator: ObservableObject {
    @Published private(set) var displayedField: MacBookThermalField?
    private var animationTask: Task<Void, Never>?

    deinit {
        animationTask?.cancel()
    }

    func update(to target: MacBookThermalField, animated: Bool) {
        guard let source = displayedField, animated else {
            animationTask?.cancel()
            displayedField = target
            return
        }

        animationTask?.cancel()
        animationTask = Task { @MainActor [weak self] in
            let frames = 36
            for frame in 1...frames {
                guard !Task.isCancelled else { return }
                let linear = Double(frame) / Double(frames)
                let eased = 1 - pow(1 - linear, 3)
                self?.displayedField = source.interpolated(to: target, progress: eased)
                try? await Task.sleep(nanoseconds: 33_000_000)
            }
            self?.displayedField = target
        }
    }
}

private enum IsometricLayer {
    case base
    case surface
    case axis
}

private struct IsometricProjector {
    /// Matches the uncropped chassis bounds of `thermal_realistic_m3pro`.
    /// Keeping this in world geometry prevents the reference image from being
    /// squeezed while every schematic/thermal coordinate stays normalized.
    private static let chassisAspectRatio = 900.0 / 659.0

    let size: CGSize
    let azimuthDegrees: Double
    let elevationDegrees: Double
    let layerSeparation: Double
    let zoom: Double

    func point(x: Double, y: Double, height: Double, layer: IsometricLayer) -> CGPoint {
        let azimuth = azimuthDegrees * Double.pi / 180
        let elevation = elevationDegrees * Double.pi / 180
        let worldX = (x - 0.5) * Self.chassisAspectRatio
        let worldY = y - 0.5
        let rotatedX = worldX * cos(azimuth) - worldY * sin(azimuth)
        let rotatedY = worldX * sin(azimuth) + worldY * cos(azimuth)
        let horizontalSpan = abs(Self.chassisAspectRatio * cos(azimuth)) + abs(sin(azimuth))
        let projectedDepthSpan = (
            abs(Self.chassisAspectRatio * sin(azimuth)) + abs(cos(azimuth))
        ) * max(abs(sin(elevation)), 0.18)
        let scale = min(
            size.width * 0.86 / horizontalSpan,
            size.height * 0.62 / projectedDepthSpan
        ) * zoom
        let separation: Double
        switch layer {
        case .base: separation = -layerSeparation * 0.06
        case .surface: separation = layerSeparation * 0.32
        case .axis: separation = 0
        }
        let worldZ = height * 0.44 + separation
        return CGPoint(
            x: size.width * 0.50 + CGFloat(rotatedX * scale),
            y: size.height * 0.58
                + CGFloat(rotatedY * sin(elevation) * scale)
                - CGFloat(worldZ * cos(elevation) * scale)
        )
    }
}

private struct ScrollWheelCapture: NSViewRepresentable {
    let onScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> ScrollWheelView {
        let view = ScrollWheelView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelView, context: Context) {
        nsView.onScroll = onScroll
    }

    static func dismantleNSView(_ nsView: ScrollWheelView, coordinator: ()) {
        nsView.removeMonitor()
    }
}

private final class ScrollWheelView: NSView {
    var onScroll: ((CGFloat) -> Void)?
    private var eventMonitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeMonitor()
        guard window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let location = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(location) else { return event }
            self.onScroll?(event.scrollingDeltaY)
            return event
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func removeMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
    }

    deinit {
        removeMonitor()
    }
}

private struct MenuBarGraphBackdrop: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            LinearGradient(
                colors: [Color.accentBlue.opacity(0.055), .clear, Color.accentPurple.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .allowsHitTesting(false)
    }
}
