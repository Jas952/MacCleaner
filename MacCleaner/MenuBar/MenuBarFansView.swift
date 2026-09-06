import SwiftUI

struct MenuBarFansView: View {
    @ObservedObject var model: FanPanelModel
    private let accent = Color(red: 0.13, green: 0.48, blue: 0.66)

    var body: some View {
        GeometryReader { geometry in
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment:.leading,spacing:4) {
                        Text("COOLING / CONTROL").font(.system(size:9,weight:.semibold,design:.monospaced)).tracking(1.6).foregroundStyle(.secondary)
                        Text("Fan control").font(.system(size:21,weight:.semibold,design:.rounded))
                    }
                    Spacer()

                }
                if model.fans.isEmpty {
                    VStack(spacing:8) {
                        Image(systemName:"fanblades").font(.system(size:32,weight:.ultraLight))
                        Text("Waiting for fan telemetry").font(.system(size:12))
                    }.foregroundStyle(.secondary).frame(maxWidth:.infinity,minHeight:260)
                } else {
                    HStack(alignment:.top,spacing:10) {
                        ForEach(model.fans.prefix(2)) { fan in
                            FanChannelCard(fan:fan,model:model,compact:false,accent:fan.id == 0 ? accent : Color(red:0.68,green:0.43,blue:0.23))
                        }
                    }.frame(maxHeight: .infinity)
                }
                FanTemperatureResponseView(
                    sensors: model.temperatureSensors,
                    samples: model.temperatureHistory,
                    events: model.timelineEvents
                )
                .frame(height: 86)
            }.padding(.horizontal,16).padding(.top,20).padding(.bottom,12)
                .frame(
                    width: max(0, geometry.size.width),
                    height: max(0, geometry.size.height)
                )
                .overlay(alignment: .top) {
                    if model.shouldOfferControlAccess {
                        FanControlAccessOverlay(model: model, accent: accent)
                            .padding(.top, 64)
                            .padding(.horizontal, 16)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.18), value: model.shouldOfferControlAccess)
        }
        .background(Color(nsColor:.windowBackgroundColor))
    }
}

private struct FanControlAccessOverlay: View {
    @ObservedObject var model: FanPanelModel
    let accent: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 25, height: 25)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text("Enable local control")
                    .font(.system(size: 10, weight: .semibold))
                Text("Administrator approval required")
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            Button(model.busy ? "Waiting…" : "Enable") { model.install() }
                .buttonStyle(FanPanelButtonStyle(accent: accent, emphasized: true))
                .disabled(model.busy)
        }
        .frame(maxWidth: .infinity)
        .padding(9)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09))
        }
        .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
    }
}

private struct FanTemperatureResponseView: View {
    let sensors: [SensorReading]
    let samples: [FanTemperatureSample]
    let events: [FanTimelineEvent]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Rectangle().fill(Color.primary.opacity(0.075)).frame(height: 1)
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("THERMAL SENSORS")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    if sensors.isEmpty {
                        Text("Waiting for readings")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            LazyVStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(sensors.enumerated()), id: \.element.id) { index, sensor in
                                    HStack(spacing: 5) {
                                        Circle().fill(FanTemperaturePalette.color(index)).frame(width: 4, height: 4)
                                        Text(sensor.name)
                                            .font(.system(size: 8, weight: .medium))
                                            .lineLimit(1)
                                        Spacer(minLength: 2)
                                        Text(String(format: "%.1f°", sensor.value))
                                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                            .monospacedDigit()
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: 142, alignment: .leading)

                FanTemperatureChart(sensors: Array(sensors.prefix(4)), samples: samples, events: events)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .padding(.top, 3)
            }
            .frame(height: 62)
            .padding(.horizontal, 10)
            .padding(.top, 3)
            .padding(.bottom, 6)
        }
    }
}

private struct FanTemperatureChart: View {
    let sensors: [SensorReading]
    let samples: [FanTemperatureSample]
    let events: [FanTimelineEvent]
    @State private var viewportEnd: Int?
    @State private var jumpedEventIndex: Int?
    @GestureState private var dragTranslation: CGFloat = 0
    private let windowCount = 60

    var body: some View {
        GeometryReader { geometry in
            let pixelsPerSample = max(2, geometry.size.width / CGFloat(windowCount - 1))
            let baseEnd = min(max(0, viewportEnd ?? samples.count - 1), max(0, samples.count - 1))
            let end = min(max(0, baseEnd - Int(dragTranslation / pixelsPerSample)), max(0, samples.count - 1))
            let start = max(0, end - windowCount + 1)
            let visible = samples.isEmpty ? [] : Array(samples[start...end])
            let values = visible.flatMap { sample in sensors.compactMap { sample.values[$0.id] } }
            let low = values.min() ?? 20
            let high = values.max() ?? 100
            let lower = max(0, floor((low - 6) / 5) * 5)
            let upper = max(lower + 20, ceil((high + 6) / 5) * 5)
            let span = max(1, upper - lower)

            Canvas { context, size in
                for row in 0...3 {
                    let y = size.height * CGFloat(row) / 3
                    var grid = Path(); grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(grid, with: .color(Color.primary.opacity(0.055)), style: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                }
                guard visible.count > 1, let firstDate = visible.first?.date, let lastDate = visible.last?.date else { return }
                let duration = max(1, lastDate.timeIntervalSince(firstDate))
                for event in events where event.date >= firstDate && event.date <= lastDate {
                    let x = size.width * CGFloat(event.date.timeIntervalSince(firstDate) / duration)
                    var marker = Path(); marker.move(to: CGPoint(x: x, y: 0)); marker.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(marker, with: .color(FanTemperaturePalette.eventColor(event.kind).opacity(0.72)), style: StrokeStyle(lineWidth: 0.8, dash: [2, 2]))
                }
                for (sensorIndex, sensor) in sensors.enumerated() {
                    var path = Path(); var hasPoint = false
                    for sample in visible {
                        guard let value = sample.values[sensor.id] else { continue }
                        let x = size.width * CGFloat(sample.date.timeIntervalSince(firstDate) / duration)
                        let fraction = min(1, max(0, (value - lower) / span))
                        let point = CGPoint(x: x, y: size.height * CGFloat(1 - fraction))
                        if hasPoint { path.addLine(to: point) } else { path.move(to: point); hasPoint = true }
                    }
                    context.stroke(path, with: .color(FanTemperaturePalette.color(sensorIndex).opacity(0.9)), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                }
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 3)
                .updating($dragTranslation) { value, state, _ in state = value.translation.width }
                .onEnded { value in
                    viewportEnd = min(max(0, baseEnd - Int(value.translation.width / pixelsPerSample)), max(0, samples.count - 1))
                    if viewportEnd == samples.count - 1 { viewportEnd = nil }
                    jumpedEventIndex = nil
                })
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 3) {
                    Button { jumpToPreviousEvent(from: end) } label: {
                        Image(systemName: "backward.end.fill").frame(width: 17, height: 17)
                    }
                    .buttonStyle(FanChartCornerButtonStyle())
                    .disabled(previousActivationIndex(from: end) == nil)
                    .help("Previous fan activation")
                    if viewportEnd != nil {
                        Button { viewportEnd = nil; jumpedEventIndex = nil } label: {
                            Image(systemName: "forward.end.fill").frame(width: 17, height: 17)
                        }
                        .buttonStyle(FanChartCornerButtonStyle())
                        .help("Return to live temperatures")
                    }
                }
                .font(.system(size: 7, weight: .bold))
                .padding(2)
            }
        }
        .accessibilityLabel("Temperature history for the last 60 seconds")
    }

    private func previousActivationIndex(from end: Int) -> Int? {
        guard !samples.isEmpty else { return nil }
        let cutoff = jumpedEventIndex.map { events[$0].date } ?? samples[min(end, samples.count - 1)].date
        return events.indices.last { events[$0].kind == .enabled && events[$0].date < cutoff.addingTimeInterval(-0.05) }
    }

    private func jumpToPreviousEvent(from end: Int) {
        guard let eventIndex = previousActivationIndex(from: end), !samples.isEmpty else { return }
        jumpedEventIndex = eventIndex
        let eventDate = events[eventIndex].date
        let nearest = samples.indices.min { abs(samples[$0].date.timeIntervalSince(eventDate)) < abs(samples[$1].date.timeIntervalSince(eventDate)) } ?? 0
        viewportEnd = min(samples.count - 1, nearest + 5)
    }
}

private struct FanChartCornerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
            .opacity(configuration.isPressed ? 0.55 : 0.92)
    }
}

private enum FanTemperaturePalette {
    private static let colors: [Color] = [
        Color(red: 0.13, green: 0.48, blue: 0.66),
        Color(red: 0.68, green: 0.43, blue: 0.23),
        Color(red: 0.42, green: 0.58, blue: 0.34),
        Color(red: 0.55, green: 0.40, blue: 0.66)
    ]
    static func color(_ index: Int) -> Color { colors[index % colors.count] }
    static func eventColor(_ kind: FanTimelineEventKind) -> Color {
        switch kind {
        case .enabled: return .green
        case .disabled, .stopped: return .secondary
        case .manual: return colors[0]
        case .automatic: return colors[2]
        case .rpmIncrease: return .orange
        }
    }
}

private struct FanChannelCard: View {
    let fan: FanInfo
    @ObservedObject var model: FanPanelModel
    let compact: Bool
    let accent: Color
    @State private var draft: Double = 0
    @State private var dragging = false
    @State private var autoHovered = false
    @State private var manualHovered = false
    private var displayedMode: Int? { model.displayedMode(for: fan) }
    private var controlEnabled: Bool { model.ready && model.isControlEnabled(for: fan) }
    private var manual: Bool { controlEnabled && displayedMode == 1 }
    private var manualConfirmed: Bool { controlEnabled && fan.mode == 1 }
    private var automatic: Bool { controlEnabled && (displayedMode == 0 || displayedMode == 3) }
    private var powerColor: Color { controlEnabled && model.ready ? .green : .secondary }
    private var available: Bool { model.ready && model.boostSeconds == 0 }
    private var range: ClosedRange<Double> { Double(max(1,fan.minRPM))...Double(max(fan.minRPM+1,fan.maxRPM)) }

    var body: some View {
        VStack(alignment:.leading,spacing:0) {
            HStack {
                Text(String(format:"F%02d",fan.id+1)).font(.system(size:10,weight:.bold,design:.monospaced)).foregroundStyle(accent)
                Spacer()
                Text(fan.id == 0 ? "LEFT" : "RIGHT").font(.system(size:8,weight:.semibold,design:.monospaced)).tracking(1).foregroundStyle(.secondary)
            }.padding(.horizontal,12).padding(.top,12)
            FanEngineeringDrawing(rpm:fan.actualRPM,maximum:fan.maxRPM,channel:fan.id,accent:accent,height:compact ? 124 : 164)
                .padding(.horizontal,4)
            HStack(alignment:.firstTextBaseline,spacing:5) {
                Text("\(fan.actualRPM)").font(.system(size:29,weight:.medium,design:.monospaced)).monospacedDigit().tracking(-1.5)
                Text("RPM").font(.system(size:8,weight:.medium,design:.monospaced)).foregroundStyle(.secondary)
            }.frame(maxWidth:.infinity)
            HStack(spacing:5) {
                Circle().fill(manual ? accent : powerColor).frame(width:4,height:4)
                Text(!controlEnabled ? "CONTROL OFF" : displayedMode == nil ? "MODE UNAVAILABLE" : manual ? "MANUAL TARGET" : fan.actualRPM == 0 ? "AUTO · STOPPED" : "MACOS AUTO")
                    .font(.system(size:7,weight:.semibold,design:.monospaced)).tracking(0.5)
            }.frame(maxWidth:.infinity).padding(.top,4).padding(.bottom,14)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height:1)
            VStack(alignment:.leading,spacing:10) {
                HStack(spacing:6) {
                    Button { model.toggleControl(for: fan) } label: {
                        Image(systemName:"power").font(.system(size:11,weight:.semibold))
                            .frame(width:28,height:28)
                            .foregroundStyle(controlEnabled && model.ready ? Color.white : Color.secondary)
                            .background(controlEnabled && model.ready ? Color.green.opacity(autoHovered ? 0.95 : 0.8) : Color.primary.opacity(autoHovered ? 0.1 : 0.04),in:RoundedRectangle(cornerRadius:7))
                            .overlay(RoundedRectangle(cornerRadius:7).stroke(powerColor.opacity(0.3),lineWidth:0.6))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!available)
                        .onHover { autoHovered = $0 }
                        .animation(.easeOut(duration: 0.14), value: autoHovered)
                        .animation(.easeOut(duration: 0.18), value: controlEnabled)
                        .help(controlEnabled ? "Turn off MacCleaner control and return fan \(fan.id+1) to macOS." : "Enable MacCleaner control for fan \(fan.id+1).")
                        .accessibilityLabel("MacCleaner control for fan \(fan.id+1)")
                        .accessibilityValue(controlEnabled ? "On" : "Off")
                    Button {
                        if manual { model.automatic(fan) }
                        else { model.manual(fan,rpm:Int(draft)) }
                    } label: {
                        HStack(spacing:5) {
                            ZStack {
                                RoundedRectangle(cornerRadius:3).stroke(manual ? accent : Color.secondary.opacity(0.5),lineWidth:1).frame(width:12,height:12)
                                if manual { Image(systemName:"checkmark").font(.system(size:8,weight:.bold)).foregroundStyle(accent) }
                            }
                            Text("MANUAL").font(.system(size:8,weight:.bold,design:.monospaced)).tracking(0.5)
                        }.frame(maxWidth:.infinity,minHeight:28)
                            .foregroundStyle(manual ? accent : Color.secondary)
                            .background(manual ? accent.opacity(manualHovered ? 0.14 : 0.07) : Color.primary.opacity(manualHovered ? 0.055 : 0),in:RoundedRectangle(cornerRadius:7))
                            .overlay(RoundedRectangle(cornerRadius:7).stroke(manualHovered ? accent.opacity(0.32) : Color.primary.opacity(0.09),lineWidth:0.6))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!available || !controlEnabled)
                        .onHover { manualHovered = $0 }
                        .animation(.easeOut(duration: 0.14), value: manualHovered)
                        .animation(.easeOut(duration: 0.18), value: manual)
                        .accessibilityLabel("Manual control for fan \(fan.id+1)")
                        .accessibilityValue(manual ? "On" : "Off")
                }
                HStack(alignment:.firstTextBaseline) {
                    Text("SETPOINT").font(.system(size:7,weight:.medium,design:.monospaced)).foregroundStyle(.secondary)
                    Spacer(minLength:0)
                    Text("\(Int(draft))").font(.system(size:13,weight:.semibold,design:.monospaced)).foregroundStyle(manual ? accent : Color.secondary)
                }.opacity(manualConfirmed ? 1 : 0.35)
                FanTechnicalSlider(value:$draft,range:range,active:manualConfirmed && available,accent:accent,label:"Fan \(fan.id+1) target RPM",editing:{dragging=$0}) {
                    model.manual(fan,rpm:Int(draft))
                }.padding(.top,-5)
                HStack {
                    Text("\(fan.minRPM)")
                    Spacer()
                    Text("\(fan.maxRPM)")
                }.font(.system(size:8,design:.monospaced)).foregroundStyle(.secondary).opacity(manualConfirmed ? 0.8 : 0.3)
            }.padding(12)
        }
        .frame(maxWidth:.infinity)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor:.controlBackgroundColor).opacity(0.65),in:RoundedRectangle(cornerRadius:14))
        .overlay(RoundedRectangle(cornerRadius:14).stroke(Color.primary.opacity(0.09),lineWidth:0.7))
        .onAppear { syncDraft() }
        .onChange(of:fan.targetRPM) { target in
            if !dragging { draft=min(range.upperBound,max(range.lowerBound,Double(target))) }
        }
    }
    private func syncDraft() { draft=min(range.upperBound,max(range.lowerBound,Double(fan.targetRPM))) }
}

struct FanPanelButtonStyle: ButtonStyle {
    let accent: Color
    var emphasized = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration) -> some View {
        configuration.label
            .font(.system(size:10,weight:.semibold))
            .padding(.horizontal,11).padding(.vertical,9)
            .foregroundStyle(emphasized ? Color.white : accent)
            .background {
                RoundedRectangle(cornerRadius:8)
                    .fill(LinearGradient(colors:emphasized ? [accent.opacity(0.85),accent] : [accent.opacity(0.05),accent.opacity(0.1)],startPoint:.top,endPoint:.bottom))
            }
            .overlay(RoundedRectangle(cornerRadius:8).stroke(emphasized ? Color.white.opacity(0.17) : accent.opacity(0.25),lineWidth:0.7))
            .shadow(color:accent.opacity(emphasized ? 0.15 : 0),radius:3,y:2)
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
