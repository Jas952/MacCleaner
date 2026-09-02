import SwiftUI

struct MacBookThermalZone {
    var id: String { reading.id }
    var shortTitle: String { reading.name }
    let componentID: String
    let reading: SensorReading
    let center: CGPoint
    let radius: CGSize
    /// Animation changes only this value; `reading.value` remains the live sample.
    var temperature: Double
    let color: Color
}

struct MacBookThermalField {
    let zones: [MacBookThermalZone]
    let components: [MacBookComponent]
    let layoutName: String
    let fanRPMs: [String: Int]
    let sensorCount: Int

    init(thermal: ThermalInfo, fans: [FanInfo], modelIdentifier: String) {
        let isAir = modelIdentifier.hasPrefix("MacBookAir")
            || ["Mac14,2", "Mac15,12", "Mac15,13"].contains(modelIdentifier)
        let layout = MacBookComponentLayout(isAir: isAir)
        components = layout.components
        layoutName = layout.name
        // Missing telemetry is not the same as an idle fan.
        fanRPMs = fans.reduce(into: [:]) { result, fan in
            guard fan.id == 0 || fan.id == 1 else { return }
            result[fan.id == 0 ? "fan-left" : "fan-right"] = max(0, fan.actualRPM)
        }
        var seen = Set<String>()
        let readings = thermal.sensors.filter {
            $0.value.isFinite && $0.value > 1 && $0.value < 130 && seen.insert($0.id).inserted
        }.sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        sensorCount = readings.count
        zones = readings.compactMap { reading in
            let raw = reading.sourceID.lowercased()
            let name = reading.name.lowercased()
            let slot = Self.slot(for: reading.sourceID)
            let componentID: String
            let center: CGPoint
            let radius: CGSize
            let color: Color
            // These are region anchors on the unchanged component layout, not
            // claims about the physical location of individual die sensors.
            switch reading.category {
            case .cpuCore:
                componentID = "logic-board"
                center = CGPoint(x: 0.38 + Double(slot % 5) * 0.032, y: 0.18 + Double(slot / 5) * 0.035)
                radius = CGSize(width: 0.055, height: 0.05)
                color = .accentRed
            case .soc:
                componentID = "logic-board"
                if raw.contains("gpu") || name.contains("gpu") {
                    center = CGPoint(x: 0.55, y: 0.22)
                    radius = CGSize(width: 0.10, height: 0.09)
                    color = .accentPurple
                } else {
                    center = CGPoint(x: 0.52 + Double(slot % 4) * 0.042, y: 0.27 + Double(slot / 4) * 0.02)
                    radius = CGSize(width: 0.065, height: 0.05)
                    color = .accentAmber
                }
            case .storage:
                componentID = layout.components.contains(where: { $0.id == "storage" }) ? "storage" : "logic-board"
                center = CGPoint(x: 0.65, y: 0.22)
                radius = CGSize(width: 0.11, height: 0.10)
                color = .accentBlue
            case .battery:
                componentID = "battery-pack"
                center = CGPoint(x: 0.50, y: 0.66)
                radius = CGSize(width: 0.42, height: 0.28)
                color = .accentGreen
            case .airflow:
                if !isAir && (raw.contains("left") || name.contains("left")) {
                    componentID = "fan-left"
                } else if !isAir && (raw.contains("right") || name.contains("right")) {
                    componentID = "fan-right"
                } else {
                    componentID = "vent"
                }
                let frame = layout.components.first(where: { $0.id == componentID })!.frame
                center = CGPoint(x: frame.midX, y: frame.midY)
                radius = CGSize(width: max(0.13, frame.width / 2), height: 0.13)
                color = .accentBlue
            case .other:
                // Retain unlocated readings in Fans; don't assign them to a
                // component merely because a neighbouring chip is warm.
                return nil
            }
            return MacBookThermalZone(componentID: componentID, reading: reading,
                center: center, radius: radius, temperature: reading.value, color: color)
        }
    }

    private init(zones: [MacBookThermalZone], components: [MacBookComponent], layoutName: String,
                 fanRPMs: [String: Int], sensorCount: Int) {
        self.zones = zones
        self.components = components
        self.layoutName = layoutName
        self.fanRPMs = fanRPMs
        self.sensorCount = sensorCount
    }

    private static func slot(for key: String) -> Int {
        if let number = key.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap(Int.init).first {
            return max(0, number - 1) % 20
        }
        // Stable across launches and changes to the active sensor roster.
        return key.utf8.reduce(0) { ($0 * 31 + Int($1)) % 20 }
    }

    var maximumTemperature: Double { zones.map(\.reading.value).max() ?? 0 }
    var activeSensorCount: Int { sensorCount }
    var hasFanTelemetry: Bool { !fanRPMs.isEmpty }
    var hasActiveFans: Bool { fanRPMs.values.contains { $0 > 0 } }
    var fanStatusText: String {
        components.filter { $0.kind == .fan }.map { component in
            let side = component.id == "fan-left" ? "L" : "R"
            return "\(side) \(fanRPMs[component.id].map(String.init) ?? "—")"
        }.joined(separator: " · ") + " RPM"
    }

    func readings(for componentID: String) -> [SensorReading] {
        zones.filter { $0.componentID == componentID }.map(\.reading)
    }

    func nearestZone(x: Double, y: Double) -> MacBookThermalZone? {
        zones.min {
            hypot(x - $0.center.x, y - $0.center.y) < hypot(x - $1.center.x, y - $1.center.y)
        }
    }

    func fanRPM(for componentID: String) -> Int { fanRPMs[componentID] ?? 0 }

    /// Sensor-anchored spatial interpolation. The coolest measured reading is
    /// the visual baseline, NOT an invented ambient/case temperature. Gaussian
    /// influence spreads smoothly; inverse-distance weights preserve anchors.
    func temperature(x: Double, y: Double) -> Double {
        guard let baseline = zones.map(\.temperature).min() else { return 0 }
        var numerator = 0.0
        var denominator = 0.0
        var uncovered = 1.0
        var anchorTotal = 0.0
        var anchorCount = 0
        for zone in zones {
            let dx = (x - zone.center.x) / zone.radius.width
            let dy = (y - zone.center.y) / zone.radius.height
            let distanceSquared = dx * dx + dy * dy
            if distanceSquared < 1e-12 {
                anchorTotal += zone.temperature
                anchorCount += 1
            }
            let influence = exp(-distanceSquared * 1.7)
            let weight = influence / max(distanceSquared, 1e-12)
            numerator += (zone.temperature - baseline) * weight
            denominator += weight
            uncovered *= 1 - influence
        }
        // Coincident region anchors represent several real readings: their
        // mean shapes the mesh, while hover keeps each original reading.
        if anchorCount > 0 { return anchorTotal / Double(anchorCount) }
        guard denominator > 1e-12 else { return baseline }
        return baseline + numerator / denominator * (1 - uncovered)
    }

    var temperatureCeiling: Double {
        max(95, ceil((zones.map(\.temperature).max() ?? 0) / 10) * 10)
    }

    func height(for temperature: Double) -> Double {
        guard temperature > 0 else { return 0 }
        return min(max((temperature - 25) / (temperatureCeiling - 25), 0), 1)
    }

    func interpolated(to target: MacBookThermalField, progress: Double) -> MacBookThermalField {
        let eased = min(max(progress, 0), 1)
        let source = Dictionary(uniqueKeysWithValues: zones.map { ($0.id, $0.temperature) })
        let blended = target.zones.map { zone -> MacBookThermalZone in
            var result = zone
            let start = source[zone.id] ?? zone.temperature
            result.temperature = start + (zone.temperature - start) * eased
            return result
        }
        return MacBookThermalField(zones: blended, components: target.components,
            layoutName: target.layoutName, fanRPMs: target.fanRPMs, sensorCount: target.sensorCount)
    }

    func color(for temperature: Double) -> Color { ThermalColorScale.color(for: temperature) }
}
