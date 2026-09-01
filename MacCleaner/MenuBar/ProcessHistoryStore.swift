import Combine
import Foundation

struct ProcessGraphPoint: Codable, Equatable, Identifiable {
    let id: String
    let pid: Int32
    let name: String
    let executablePath: String
    let cpu: Double
    let memoryBytes: UInt64
    let instanceCount: Int

    init(_ node: ProcessNode) {
        let executablePath = Self.executablePath(from: node.commandLine, fallback: node.name)
        id = node.name + "|" + executablePath
        pid = node.id
        name = node.name
        self.executablePath = executablePath
        cpu = node.cpuUsage
        memoryBytes = node.memoryBytes
        instanceCount = node.instanceCount
    }

    init(
        id: String,
        pid: Int32,
        name: String,
        executablePath: String,
        cpu: Double,
        memoryBytes: UInt64,
        instanceCount: Int
    ) {
        self.id = id
        self.pid = pid
        self.name = name
        self.executablePath = executablePath
        self.cpu = cpu
        self.memoryBytes = memoryBytes
        self.instanceCount = instanceCount
    }

    private static func executablePath(from commandLine: String, fallback: String) -> String {
        let trimmed = commandLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        if trimmed.first == "\"", let closingQuote = trimmed.dropFirst().firstIndex(of: "\"") {
            return String(trimmed[trimmed.index(after: trimmed.startIndex)..<closingQuote])
        }
        return trimmed.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? fallback
    }
}

struct ProcessGraphSample: Codable, Equatable {
    let date: Date
    let processes: [ProcessGraphPoint]

    func process(id: String) -> ProcessGraphPoint? {
        processes.first { $0.id == id }
    }

    static func indexedProcesses(_ processes: [ProcessGraphPoint]) -> [String: ProcessGraphPoint] {
        processes.reduce(into: [:]) { indexed, process in
            guard let existing = indexed[process.id] else {
                indexed[process.id] = process
                return
            }
            indexed[process.id] = ProcessGraphPoint(
                id: existing.id,
                pid: existing.pid,
                name: existing.name,
                executablePath: existing.executablePath,
                cpu: existing.cpu + process.cpu,
                memoryBytes: existing.memoryBytes &+ process.memoryBytes,
                instanceCount: existing.instanceCount + process.instanceCount
            )
        }
    }

    static func mergingDuplicateProcesses(date: Date, processes: [ProcessGraphPoint]) -> ProcessGraphSample {
        ProcessGraphSample(
            date: date,
            processes: indexedProcesses(processes).values.sorted { $0.id < $1.id }
        )
    }
}

@MainActor
final class ProcessHistoryStore: ObservableObject {
    static let shared = ProcessHistoryStore(storageURL: defaultStorageURL)
    nonisolated static let retentionInterval: TimeInterval = 4 * 60 * 60
    nonisolated static let maximumSamples = 1_000

    @Published private(set) var samples: [ProcessGraphSample]

    private let storageURL: URL
    private let persistenceQueue = DispatchQueue(label: "com.maccleaner.process-history", qos: .utility)
    private var samplesSincePersistence = 0

    init(storageURL: URL, now: Date = Date()) {
        self.storageURL = storageURL
        samples = Self.load(from: storageURL, now: now)
    }

    func record(nodes: [ProcessNode], at date: Date = Date()) {
        guard !nodes.isEmpty else { return }
        let grouped = ProcessAggregator.aggregate(nodes)
        let points = ProcessGraphSample.indexedProcesses(grouped.map(ProcessGraphPoint.init)).values
            .sorted {
                max($0.cpu, Double($0.memoryBytes) / 80_000_000)
                    > max($1.cpu, Double($1.memoryBytes) / 80_000_000)
            }
            .prefix(16)
        append(ProcessGraphSample(date: date, processes: Array(points)), now: date)
    }

    func append(_ sample: ProcessGraphSample, now: Date = Date()) {
        let sample = ProcessGraphSample.mergingDuplicateProcesses(
            date: sample.date,
            processes: sample.processes
        )
        let cutoff = now.addingTimeInterval(-Self.retentionInterval)
        guard sample.date >= cutoff, sample.date <= now.addingTimeInterval(60) else {
            samples = samples.filter { $0.date >= cutoff && $0.date <= now.addingTimeInterval(60) }
            persist(samples)
            return
        }
        var retained = samples.filter { $0.date >= cutoff && $0.date <= now.addingTimeInterval(60) }

        if let last = retained.last, sample.date.timeIntervalSince(last.date) < 10 {
            retained[retained.count - 1] = sample
        } else {
            retained.append(sample)
        }

        retained.sort { $0.date < $1.date }
        if retained.count > Self.maximumSamples {
            retained.removeFirst(retained.count - Self.maximumSamples)
        }
        samples = retained
        samplesSincePersistence += 1
        // A full four-hour archive is intentionally written at most once per
        // minute while graphs are open. The published in-memory timeline still
        // updates for every sample, so drawing stays live without constant I/O.
        if samplesSincePersistence >= 4 || retained.count == 1 {
            samplesSincePersistence = 0
            persist(retained)
        }
    }

    func flushPersistenceForTesting() {
        persist(samples)
        persistenceQueue.sync {}
    }

    private func persist(_ snapshot: [ProcessGraphSample]) {
        let url = storageURL
        persistenceQueue.async {
            do {
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let archive = Archive(version: 1, samples: snapshot)
                let data = try JSONEncoder().encode(archive)
                try data.write(to: url, options: .atomic)
            } catch {
                // History is optional telemetry; a failed write must not disturb monitoring.
            }
        }
    }

    private static func load(from url: URL, now: Date) -> [ProcessGraphSample] {
        guard let data = try? Data(contentsOf: url),
              let archive = try? JSONDecoder().decode(Archive.self, from: data),
              archive.version == 1 else { return [] }
        let cutoff = now.addingTimeInterval(-retentionInterval)
        return Array(
            archive.samples
                .filter { $0.date >= cutoff && $0.date <= now.addingTimeInterval(60) }
                .sorted { $0.date < $1.date }
                .suffix(maximumSamples)
        ).map {
            ProcessGraphSample.mergingDuplicateProcesses(date: $0.date, processes: $0.processes)
        }
    }

    private static var defaultStorageURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root.appendingPathComponent("MacCleaner/process-history-v1.json")
    }

    private struct Archive: Codable {
        let version: Int
        let samples: [ProcessGraphSample]
    }
}
