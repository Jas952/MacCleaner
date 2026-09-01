import SwiftUI

struct MenuBarProcessHistoryView: View {
    @ObservedObject private var historyStore = ProcessHistoryStore.shared
    @State private var metric: ProcessGraphMetric = .cpu
    @State private var interval: ProcessGraphInterval = .thirtyMinutes
    @State private var scaleMode: ProcessGraphScaleMode = .linear
    @State private var hidesMinorProcesses = true
    @State private var hover: ProcessGraphHover?

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--debug-process-history-memory") { _metric = State(initialValue: .memory) }
        if arguments.contains("--debug-process-history-energy") { _metric = State(initialValue: .energy) }
        if arguments.contains("--debug-process-history-four-hours") { _interval = State(initialValue: .fourHours) }
        #endif
    }

    private var samples: [ProcessGraphSample] {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--debug-process-history-single") {
            return Array(ProcessGraphPreview.samples.suffix(1))
        }
        if !arguments.contains("--debug-process-history-real"),
           arguments.contains(where: { $0.hasPrefix("--debug-process-history-") }) {
            return ProcessGraphPreview.samples
        }
        #endif
        return historyStore.samples
    }

    private var currentProcesses: [ProcessGraphPoint] {
        let cutoff = Date().addingTimeInterval(-interval.duration)
        return samples.last(where: { $0.date >= cutoff })?.processes
            .filter { !hidesMinorProcesses || !metric.isMinor(metric.value(for: $0)) }
            .sorted { metric.value(for: $0) > metric.value(for: $1) } ?? []
    }

    private var dominant: ProcessGraphPoint? { currentProcesses.first }
    private var dominantShare: Double {
        guard let dominant else { return 0 }
        return min(max(metric.value(for: dominant) / metric.systemCapacity, 0), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            metricPicker
            dominantStrip
            ZStack(alignment: .topLeading) {
                ProcessHistoryChart(
                    samples: samples,
                    metric: metric,
                    interval: interval,
                    scaleMode: scaleMode,
                    hidesMinorProcesses: hidesMinorProcesses,
                    hover: $hover
                )
                if let hover {
                    tooltip(hover)
                        .position(x: min(max(hover.location.x, 104), 312), y: max(hover.location.y - 38, 30))
                        .allowsHitTesting(false)
                }

                intervalPicker
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.10)) }
            .animation(.easeOut(duration: 0.32), value: samples.last?.date)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .onChange(of: metric) { _ in hover = nil }
        .onChange(of: interval) { _ in hover = nil }
        .onChange(of: scaleMode) { _ in hover = nil }
        .onChange(of: hidesMinorProcesses) { _ in hover = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Process history").font(.system(size: 15, weight: .semibold))
            Text("\(metric.axisTitle) · \(scaleMode.title) scale")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
    }

    private var metricPicker: some View {
        HStack(spacing: 4) {
            ForEach(ProcessGraphMetric.allCases) { item in
                Button { metric = item } label: {
                    Label(item.title, systemImage: item.icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(metric == item ? Color.white : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 31)
                        .background(metric == item ? Color.accentBlue : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(metric == item ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
    }

    private var intervalPicker: some View {
        HStack(spacing: 6) {
            Button {
                scaleMode = scaleMode == .linear ? .logarithmic : .linear
            } label: {
                Image(systemName: scaleMode.icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(scaleMode == .logarithmic ? Color.accentBlue : Color.secondary.opacity(0.72))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(scaleMode.title) scale")
            .accessibilityLabel("Use logarithmic scale")
            .accessibilityValue(scaleMode == .logarithmic ? "On" : "Off")

            Button {
                hidesMinorProcesses.toggle()
            } label: {
                Image(systemName: hidesMinorProcesses ? "eye.slash" : "eye")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(hidesMinorProcesses ? Color.accentBlue : Color.secondary.opacity(0.72))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(hidesMinorProcesses ? "Show minor processes" : "Hide minor processes")
            .accessibilityLabel("Hide minor processes")
            .accessibilityValue(hidesMinorProcesses ? "On" : "Off")

            ForEach(ProcessGraphInterval.allCases) { item in
                Button {
                    interval = item
                } label: {
                    Image(systemName: item.icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(interval == item ? Color.accentBlue : Color.secondary.opacity(0.72))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.title)
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(interval == item ? .isSelected : [])
            }
        }
    }

    private var dominantStrip: some View {
        HStack(spacing: 9) {
            if let dominant {
                ProcessIconView(commandLine: dominant.executablePath, size: 28)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(dominant.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(Int((dominantShare * 100).rounded()))% of total")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.08))
                            Capsule().fill(metric.tint.opacity(0.9)).frame(width: geometry.size.width * dominantShare)
                        }
                    }
                    .frame(height: 5)
                    Text("\(metric.formatted(metric.value(for: dominant))) · \(dominant.instanceCount) process\(dominant.instanceCount == 1 ? "" : "es")")
                        .font(.system(size: 7.5, design: .monospaced)).foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "hourglass").frame(width: 28, height: 28)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 7))
                Text("Collecting process samples").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: .infinity, minHeight: 50)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(Color.primary.opacity(0.08)) }
    }

    private func tooltip(_ hover: ProcessGraphHover) -> some View {
        HStack(spacing: 8) {
            ProcessIconView(commandLine: hover.process.executablePath, size: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(hover.process.name).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                HStack(spacing: 5) {
                    Text(metric.formatted(hover.value)).font(.system(size: 9, weight: .bold, design: .monospaced))
                    Text(hover.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 9).frame(height: 40)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(hover.color.opacity(0.48)) }
        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
    }
}

enum ProcessGraphInterval: TimeInterval, CaseIterable, Identifiable {
    case thirtyMinutes = 1800
    case fourHours = 14400
    var id: TimeInterval { rawValue }
    var duration: TimeInterval { rawValue }
    var title: String { self == .thirtyMinutes ? "30 min" : "4 hours" }
    var icon: String { self == .thirtyMinutes ? "clock" : "clock.arrow.circlepath" }
}

enum ProcessGraphScaleMode: String, CaseIterable, Identifiable {
    case linear
    case logarithmic

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var icon: String { self == .linear ? "chart.xyaxis.line" : "function" }

    func normalized(_ value: Double, upperBound: Double, softening: Double) -> Double {
        guard upperBound > 0 else { return 0 }
        let clamped = min(max(value, 0), upperBound)
        switch self {
        case .linear:
            return clamped / upperBound
        case .logarithmic:
            let safeSoftening = max(softening, 0.000_001)
            return log1p(clamped / safeSoftening) / log1p(upperBound / safeSoftening)
        }
    }

    func value(atNormalizedPosition position: Double, upperBound: Double, softening: Double) -> Double {
        let clamped = min(max(position, 0), 1)
        switch self {
        case .linear:
            return upperBound * clamped
        case .logarithmic:
            let safeSoftening = max(softening, 0.000_001)
            return safeSoftening * expm1(clamped * log1p(upperBound / safeSoftening))
        }
    }
}

enum ProcessGraphMetric: String, CaseIterable, Identifiable {
    case cpu, memory, energy
    var id: String { rawValue }
    var title: String { rawValue == "cpu" ? "CPU" : rawValue.capitalized }
    var icon: String { self == .cpu ? "cpu" : (self == .memory ? "memorychip" : "bolt.fill") }
    var logicalProcessorCount: Double {
        Double(max(1, Foundation.ProcessInfo.processInfo.processorCount))
    }
    var systemCapacity: Double {
        switch self {
        case .memory:
            return max(1, Double(Foundation.ProcessInfo.processInfo.physicalMemory) / 1_073_741_824)
        case .cpu, .energy:
            return 100
        }
    }
    var minorThreshold: Double { systemCapacity * 0.01 }
    var scaleSoftening: Double { self == .memory ? 0.02 : 0.25 }
    var axisTitle: String {
        switch self {
        case .cpu: return "Y · total CPU capacity (\(Int(logicalProcessorCount)) cores = 100%)"
        case .memory: return "Y · process memory / \(formatted(systemCapacity)) total"
        case .energy: return "Y · relative activity / total CPU capacity"
        }
    }
    var tint: Color { self == .cpu ? .accentGreen : (self == .memory ? .accentPurple : .orange) }
    func value(for process: ProcessGraphPoint) -> Double {
        switch self {
        case .memory:
            return Double(process.memoryBytes) / 1_073_741_824
        case .cpu, .energy:
            // `ps` reports 100% per fully occupied logical CPU. Dividing by
            // the processor count turns it into a share of the whole Mac.
            return min(max(process.cpu / logicalProcessorCount, 0), systemCapacity)
        }
    }
    func isMinor(_ value: Double) -> Bool { value < minorThreshold }
    func formatted(_ value: Double) -> String {
        if self != .memory { return String(format: "%.1f%%", value) }
        return value >= 1 ? String(format: "%.2f GB", value) : String(format: "%.0f MB", value * 1024)
    }
    func axisValue(_ value: Double) -> String {
        self == .memory ? String(format: "%.1f", value) : String(format: "%.0f%%", value)
    }
}

private struct ProcessGraphHover {
    let process: ProcessGraphPoint
    let value: Double
    let color: Color
    let date: Date
    let location: CGPoint
}

struct ProcessChartSample {
    let date: Date
    let processes: [String: ProcessGraphPoint]
}

struct ProcessChartValuePoint {
    let date: Date
    let value: Double
}

struct ProcessHistoryChartData {
    let timelineStart: Date
    let timelineEnd: Date
    let samples: [ProcessChartSample]
    let series: [ProcessGraphPoint]
    let segmentsByProcessID: [String: [[ProcessChartValuePoint]]]
    let bridgesByProcessID: [String: [[ProcessChartValuePoint]]]
    let identities: [String]
    let yUpperBound: Double

    init(
        samples source: [ProcessGraphSample],
        metric: ProcessGraphMetric,
        interval: ProcessGraphInterval,
        hidesMinorProcesses: Bool,
        now: Date = Date()
    ) {
        let start = now.addingTimeInterval(-interval.duration)
        timelineEnd = now
        timelineStart = start

        let filtered = source.filter { $0.date >= start && $0.date <= now.addingTimeInterval(60) }
        let indexedSamples = filtered.map { sample in
            ProcessChartSample(
                date: sample.date,
                processes: ProcessGraphSample.indexedProcesses(sample.processes)
            )
        }
        if indexedSamples.count > 180 {
            let step = max(1, indexedSamples.count / 180)
            var decimated = Swift.stride(from: 0, to: indexedSamples.count, by: step).map { indexedSamples[$0] }
            if decimated.last?.date != indexedSamples.last?.date, let last = indexedSamples.last { decimated.append(last) }
            samples = decimated
        } else {
            samples = indexedSamples
        }

        struct Stats {
            var point: ProcessGraphPoint
            var accumulatedValue: Double
            var sampleCount: Int
            var peakValue: Double
        }
        var stats: [String: Stats] = [:]
        for sample in indexedSamples {
            for process in sample.processes.values {
                let value = metric.value(for: process)
                var item = stats[process.id] ?? Stats(point: process, accumulatedValue: 0, sampleCount: 0, peakValue: 0)
                item.point = process
                item.accumulatedValue += value
                item.sampleCount += 1
                item.peakValue = max(item.peakValue, value)
                stats[process.id] = item
            }
        }

        let minimumPresence = min(8, max(3, indexedSamples.count / 24))
        let stable = stats.values
            .filter {
                $0.sampleCount >= minimumPresence
                    && (!hidesMinorProcesses || !metric.isMinor($0.peakValue))
            }
            .sorted {
                if $0.accumulatedValue == $1.accumulatedValue { return $0.sampleCount > $1.sampleCount }
                return $0.accumulatedValue > $1.accumulatedValue
            }
        let latestIdentities = Set(indexedSamples.last?.processes.keys.map { $0 } ?? [])
        let recent = stats.values
            .filter {
                latestIdentities.contains($0.point.id)
                    && (!hidesMinorProcesses || !metric.isMinor($0.peakValue))
            }
            .sorted { metric.value(for: $0.point) > metric.value(for: $1.point) }
        let fallback = stats.values
            .filter { !hidesMinorProcesses || !metric.isMinor($0.peakValue) }
            .sorted { $0.accumulatedValue > $1.accumulatedValue }
        var ranked: [Stats] = []
        var rankedIdentities = Set<String>()
        for item in recent + (stable.isEmpty ? fallback : stable) {
            if rankedIdentities.insert(item.point.id).inserted {
                ranked.append(item)
            }
        }
        let visibleSeriesLimit = hidesMinorProcesses ? 4 : 6
        series = ranked.prefix(visibleSeriesLimit).map(\.point)
        identities = stats.keys.sorted()

        var preparedSegments: [String: [[ProcessChartValuePoint]]] = [:]
        var preparedBridges: [String: [[ProcessChartValuePoint]]] = [:]
        for process in series {
            let processSegments = Self.makeSegments(
                processID: process.id,
                samples: indexedSamples,
                metric: metric,
                interval: interval,
                timelineStart: start
            )
            preparedSegments[process.id] = processSegments
            preparedBridges[process.id] = Self.makeBridges(
                between: processSegments,
                samples: indexedSamples,
                processID: process.id,
                bucketDuration: interval.duration / Double(interval == .fourHours ? 72 : 90),
                maximumGap: interval == .fourHours ? 30 * 60 : 15 * 60
            )
        }
        segmentsByProcessID = preparedSegments
        bridgesByProcessID = preparedBridges
        yUpperBound = metric.systemCapacity
    }

    private static func makeSegments(
        processID: String,
        samples: [ProcessChartSample],
        metric: ProcessGraphMetric,
        interval: ProcessGraphInterval,
        timelineStart: Date
    ) -> [[ProcessChartValuePoint]] {
        let bucketCount = interval == .fourHours ? 72 : 90
        let bucketDuration = interval.duration / Double(bucketCount)
        var buckets: [Int: [Double]] = [:]
        for sample in samples {
            guard let process = sample.processes[processID] else { continue }
            let elapsed = sample.date.timeIntervalSince(timelineStart)
            guard elapsed >= 0, elapsed <= interval.duration + 60 else { continue }
            let bucket = min(bucketCount - 1, max(0, Int(elapsed / bucketDuration)))
            buckets[bucket, default: []].append(metric.value(for: process))
        }
        guard !buckets.isEmpty else { return [] }

        let bucketed = buckets.keys.sorted().map { bucket -> (Int, ProcessChartValuePoint) in
            let values = buckets[bucket] ?? []
            let date = timelineStart.addingTimeInterval((Double(bucket) + 0.5) * bucketDuration)
            return (bucket, ProcessChartValuePoint(date: date, value: median(values)))
        }

        var groups: [[(Int, ProcessChartValuePoint)]] = []
        for item in bucketed {
            if let previousBucket = groups.last?.last?.0, item.0 - previousBucket <= 2 {
                groups[groups.count - 1].append(item)
            } else {
                groups.append([item])
            }
        }

        let minimumBuckets = interval == .fourHours ? 2 : 3
        return groups.compactMap { group in
            guard group.count >= minimumBuckets || bucketed.count < minimumBuckets else { return nil }
            let points = group.map(\.1)
            return interval == .fourHours ? smoothed(points) : points
        }
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func smoothed(_ points: [ProcessChartValuePoint]) -> [ProcessChartValuePoint] {
        guard points.count >= 3 else { return points }
        return points.indices.map { index in
            let lower = max(points.startIndex, index - 1)
            let upper = min(points.index(before: points.endIndex), index + 1)
            let neighbors = points[lower...upper]
            let average = neighbors.reduce(0) { $0 + $1.value } / Double(neighbors.count)
            return ProcessChartValuePoint(date: points[index].date, value: average)
        }
    }

    private static func makeBridges(
        between segments: [[ProcessChartValuePoint]],
        samples: [ProcessChartSample],
        processID: String,
        bucketDuration: TimeInterval,
        maximumGap: TimeInterval
    ) -> [[ProcessChartValuePoint]] {
        guard segments.count > 1 else { return [] }
        return zip(segments, segments.dropFirst()).compactMap { previous, next in
            guard let from = previous.last, let to = next.first else { return nil }
            let gap = to.date.timeIntervalSince(from.date)
            guard gap > 0, gap <= maximumGap else { return nil }
            let inset = min(bucketDuration, gap / 3)
            let collectedWhileProcessWasMissing = samples.contains { sample in
                sample.date > from.date.addingTimeInterval(inset)
                    && sample.date < to.date.addingTimeInterval(-inset)
                    && sample.processes[processID] == nil
            }
            guard !collectedWhileProcessWasMissing else { return nil }
            return [from, to]
        }
    }
}

private struct ProcessHistoryChart: View {
    let samples: [ProcessGraphSample]
    let metric: ProcessGraphMetric
    let interval: ProcessGraphInterval
    let scaleMode: ProcessGraphScaleMode
    let hidesMinorProcesses: Bool
    @Binding var hover: ProcessGraphHover?
    private let chartData: ProcessHistoryChartData

    init(
        samples: [ProcessGraphSample],
        metric: ProcessGraphMetric,
        interval: ProcessGraphInterval,
        scaleMode: ProcessGraphScaleMode,
        hidesMinorProcesses: Bool,
        hover: Binding<ProcessGraphHover?>
    ) {
        self.samples = samples
        self.metric = metric
        self.interval = interval
        self.scaleMode = scaleMode
        self.hidesMinorProcesses = hidesMinorProcesses
        _hover = hover
        chartData = ProcessHistoryChartData(
            samples: samples,
            metric: metric,
            interval: interval,
            hidesMinorProcesses: hidesMinorProcesses
        )
    }

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let plot = plotRect(size), upper = chartData.yUpperBound
                drawGrid(context: &context, plot: plot)
                drawSeries(context: &context, plot: plot, upper: upper)
                drawHover(context: &context, plot: plot, upper: upper)
                drawAxes(context: &context, plot: plot, upper: upper)
                if chartData.samples.count < 2 {
                    if chartData.samples.isEmpty {
                        context.draw(Text("Collecting process samples…").font(.system(size: 9)).foregroundColor(.secondary), at: CGPoint(x: plot.midX, y: plot.midY))
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { updateHover($0, size: geometry.size) }
            .help("Dashed lines bridge short periods when no process samples were collected")
        }
    }

    private func plotRect(_ size: CGSize) -> CGRect {
        CGRect(x: 43, y: 18, width: max(1, size.width - 56), height: max(1, size.height - 46))
    }
    private func x(_ date: Date, _ plot: CGRect) -> CGFloat {
        plot.minX + CGFloat(min(max(date.timeIntervalSince(chartData.timelineStart) / interval.duration, 0), 1)) * plot.width
    }
    private func y(_ value: Double, _ upper: Double, _ plot: CGRect) -> CGFloat {
        let normalized = scaleMode.normalized(value, upperBound: upper, softening: metric.scaleSoftening)
        return plot.maxY - CGFloat(normalized) * plot.height
    }

    private func drawSeries(context: inout GraphicsContext, plot: CGRect, upper: Double) {
        for (index, process) in chartData.series.enumerated().reversed() {
            let color = processColor(process.id, index), selected = hover?.process.id == process.id
            for bridge in chartData.bridgesByProcessID[process.id] ?? [] {
                let points = bridge.map { CGPoint(x: x($0.date, plot), y: y($0.value, upper, plot)) }
                guard points.count == 2 else { continue }
                var path = Path()
                path.move(to: points[0])
                path.addLine(to: points[1])
                context.stroke(
                    path,
                    with: .color(color.opacity(selected ? 0.62 : 0.34)),
                    style: StrokeStyle(lineWidth: selected ? 1.8 : 1.05, lineCap: .round, dash: [4, 4])
                )
            }
            for values in chartData.segmentsByProcessID[process.id] ?? [] {
                let points = values.map { CGPoint(x: x($0.date, plot), y: y($0.value, upper, plot)) }
                if let point = points.first, points.count == 1 {
                    context.fill(
                        Path(ellipseIn: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)),
                        with: .color(color.opacity(0.95))
                    )
                    continue
                }
                guard points.count > 1 else { continue }
                let line = smoothPath(points)
                var area = line
                if let first = points.first, let last = points.last {
                    area.addLine(to: CGPoint(x: last.x, y: plot.maxY)); area.addLine(to: CGPoint(x: first.x, y: plot.maxY)); area.closeSubpath()
                }
                context.drawLayer { layer in
                    if selected { layer.addFilter(.shadow(color: color.opacity(0.42), radius: 5)) }
                    if interval == .thirtyMinutes {
                        layer.fill(area, with: .linearGradient(
                            Gradient(colors: [color.opacity(selected ? 0.18 : 0.055), color.opacity(0.003)]),
                            startPoint: CGPoint(x: plot.midX, y: plot.minY), endPoint: CGPoint(x: plot.midX, y: plot.maxY)
                        ))
                    }
                    layer.stroke(line, with: .color(color.opacity(hover == nil || selected ? 0.94 : 0.20)),
                                 style: StrokeStyle(lineWidth: selected ? 2.35 : 1.25, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }

    private func smoothPath(_ points: [CGPoint]) -> Path {
        var path = Path(); guard let first = points.first else { return path }; path.move(to: first)
        guard points.count > 1 else { return path }
        for index in 1..<(points.count - 1) {
            let next = points[index + 1], current = points[index]
            path.addQuadCurve(to: CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2), control: current)
        }
        if let last = points.last { path.addLine(to: last) }
        return path
    }

    private func drawGrid(context: inout GraphicsContext, plot: CGRect) {
        context.fill(Path(roundedRect: plot.insetBy(dx: -7, dy: -7), cornerRadius: 12), with: .color(Color.primary.opacity(0.018)))
        for index in 0...4 {
            let f = CGFloat(index) / 4
            var h = Path(); h.move(to: CGPoint(x: plot.minX, y: plot.minY + plot.height * f)); h.addLine(to: CGPoint(x: plot.maxX, y: plot.minY + plot.height * f))
            context.stroke(h, with: .color(Color.primary.opacity(index == 4 ? 0.15 : 0.07)), lineWidth: 0.7)
            var v = Path(); v.move(to: CGPoint(x: plot.minX + plot.width * f, y: plot.minY)); v.addLine(to: CGPoint(x: plot.minX + plot.width * f, y: plot.maxY))
            context.stroke(v, with: .color(Color.primary.opacity(0.05)), lineWidth: 0.7)
        }
    }

    private func drawAxes(context: inout GraphicsContext, plot: CGRect, upper: Double) {
        for index in 0...4 {
            let f = Double(index) / 4
            let axisValue = scaleMode.value(
                atNormalizedPosition: 1 - f,
                upperBound: upper,
                softening: metric.scaleSoftening
            )
            context.draw(Text(metric.axisValue(axisValue)).font(.system(size: 6.5, design: .monospaced)).foregroundColor(.secondary),
                         at: CGPoint(x: 21, y: plot.minY + plot.height * CGFloat(f)))
            let date = chartData.timelineStart.addingTimeInterval(interval.duration * f)
            context.draw(Text(index == 4 ? "Now" : date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 6.5, weight: index == 4 ? .semibold : .regular, design: .monospaced)).foregroundColor(.secondary),
                         at: CGPoint(x: plot.minX + plot.width * CGFloat(f), y: plot.maxY + 14),
                         anchor: index == 0 ? .leading : (index == 4 ? .trailing : .center))
        }
    }

    private func drawHover(context: inout GraphicsContext, plot: CGRect, upper: Double) {
        guard let hover else { return }
        let px = x(hover.date, plot), py = y(hover.value, upper, plot)
        var marker = Path(); marker.move(to: CGPoint(x: px, y: plot.minY)); marker.addLine(to: CGPoint(x: px, y: plot.maxY))
        context.stroke(marker, with: .color(Color.primary.opacity(0.34)), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
        context.fill(Path(ellipseIn: CGRect(x: px - 4, y: py - 4, width: 8, height: 8)), with: .color(Color(nsColor: .windowBackgroundColor)))
        context.stroke(Path(ellipseIn: CGRect(x: px - 4, y: py - 4, width: 8, height: 8)), with: .color(hover.color), lineWidth: 2)
    }

    private func updateHover(_ phase: HoverPhase, size: CGSize) {
        guard case .active(let location) = phase else { hover = nil; return }
        let plot = plotRect(size)
        guard plot.insetBy(dx: -5, dy: -7).contains(location), !chartData.samples.isEmpty else { hover = nil; return }
        let target = chartData.timelineStart.addingTimeInterval(Double((location.x - plot.minX) / plot.width) * interval.duration)
        let upper = chartData.yUpperBound
        let maximumTimeDistance: TimeInterval = interval == .fourHours ? 300 : 45
        let candidates = chartData.series.enumerated().compactMap { index, process -> (ProcessGraphPoint, ProcessChartValuePoint, Color, CGFloat)? in
            let points = (chartData.segmentsByProcessID[process.id] ?? []).flatMap { $0 }
            guard let point = points.min(by: {
                abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target))
            }), abs(point.date.timeIntervalSince(target)) <= maximumTimeDistance else { return nil }
            return (process, point, processColor(process.id, index), abs(y(point.value, upper, plot) - location.y))
        }
        guard let nearest = candidates.min(by: { $0.3 < $1.3 }), nearest.3 <= 14 else { hover = nil; return }
        hover = ProcessGraphHover(
            process: nearest.0,
            value: nearest.1.value,
            color: nearest.2,
            date: nearest.1.date,
            location: location
        )
    }

    private func processColor(_ identity: String, _ fallback: Int) -> Color {
        let palette: [Color] = [.accentPurple, .accentGreen, .accentBlue, .orange, .pink, .cyan]
        return palette[(chartData.identities.firstIndex(of: identity) ?? fallback) % palette.count]
    }
}

#if DEBUG
private enum ProcessGraphPreview {
    static let samples: [ProcessGraphSample] = {
        let end = Date()
        let processes = [
            ("chrome", "Google Chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", 26),
            ("chatgpt", "ChatGPT", "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT", 14),
            ("telegram", "Telegram", "/Applications/Telegram.app/Contents/MacOS/Telegram", 2),
            ("steam", "Steam", "/Applications/Steam.app/Contents/MacOS/steam_osx", 8),
            ("windowserver", "WindowServer", "/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer", 1)
        ]
        return (0...240).map { sampleIndex in
            let phase = Double(sampleIndex) / 240
            let date = end.addingTimeInterval(-ProcessHistoryStore.retentionInterval * (1 - phase))
            var points = processes.enumerated().map { index, process in
                let wave = sin(phase * .pi * Double(5 + index) + Double(index) * 0.8)
                let pulse = exp(-pow((phase - (0.24 + Double(index) * 0.12)) * 7.5, 2))
                let cpu = max(1, Double(28 - index * 4) + wave * Double(9 - index) + pulse * Double(24 - index * 2))
                let memoryGB = max(0.18, 3.8 - Double(index) * 0.65 + wave * 0.28 + pulse * 0.8)
                return ProcessGraphPoint(id: process.0, pid: Int32(1_000 + index), name: process.1, executablePath: process.2,
                                         cpu: cpu, memoryBytes: UInt64(memoryGB * 1_073_741_824), instanceCount: process.3)
            }
            // A two-sample helper spike verifies that transient processes do
            // not become isolated chart fragments in debug visual QA.
            if sampleIndex == 226 || sampleIndex == 227 {
                points.append(ProcessGraphPoint(
                    id: "transient-helper",
                    pid: 9_999,
                    name: "Transient Helper",
                    executablePath: "/usr/bin/true",
                    cpu: 260,
                    memoryBytes: 80 * 1_024 * 1_024,
                    instanceCount: 1
                ))
            }
            return ProcessGraphSample(date: date, processes: points)
        }
    }()
}
#endif
