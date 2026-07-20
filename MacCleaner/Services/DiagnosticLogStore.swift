import Foundation

enum DiagnosticLogLevel: String, Codable, CaseIterable, Identifiable {
    case info, warning, error

    var id: String { rawValue }
    var title: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }
}

struct DiagnosticLogEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let level: DiagnosticLogLevel
    let category: String
    let message: String
    let metadata: [String: String]

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        level: DiagnosticLogLevel,
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
        self.metadata = metadata
    }
}

@MainActor
final class DiagnosticLogStore: ObservableObject {
    static let shared = DiagnosticLogStore()

    @Published private(set) var entries: [DiagnosticLogEntry] = []
    @Published var retentionDays: Int {
        didSet {
            prune()
            save()
        }
    }

    private let maximumEntries = 2_000
    private let fileManager = FileManager.default
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let storageURL: URL

    private init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("MacCleaner", isDirectory: true)
        storageURL = appSupport.appendingPathComponent("diagnostic-logs.json")
        retentionDays = UserDefaults.standard.object(forKey: "DiagnosticLogRetentionDays") as? Int ?? 30
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        load()
        prune()
    }

    var count: Int { entries.count }

    func append(
        level: DiagnosticLogLevel = .info,
        category: String,
        message: String,
        metadata: [String: String] = [:]
    ) {
        entries.append(DiagnosticLogEntry(level: level, category: category, message: message, metadata: metadata))
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        save()
    }

    func clear() {
        entries.removeAll()
        try? fileManager.removeItem(at: storageURL)
    }

    func exportJSON(to destination: URL) throws {
        try encoder.encode(entries).write(to: destination, options: .atomic)
    }

    func exportCSV(to destination: URL) throws {
        var lines = ["date,level,category,message,metadata"]
        lines.append(contentsOf: entries.map { entry in
            [
                ISO8601DateFormatter().string(from: entry.date),
                entry.level.rawValue,
                entry.category,
                entry.message,
                entry.metadata.keys.sorted().map { "\($0)=\(entry.metadata[$0] ?? "")" }.joined(separator: ";")
            ].map(Self.csvField).joined(separator: ",")
        })
        try lines.joined(separator: "\n").data(using: .utf8)!.write(to: destination, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? decoder.decode([DiagnosticLogEntry].self, from: data) else { return }
        entries = decoded
    }

    private func prune() {
        let cutoff = Date().addingTimeInterval(-Double(max(1, retentionDays)) * 86_400)
        entries.removeAll { $0.date < cutoff }
        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
        UserDefaults.standard.set(retentionDays, forKey: "DiagnosticLogRetentionDays")
        save()
    }

    private func save() {
        guard let data = try? encoder.encode(entries) else { return }
        try? fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: storageURL, options: .atomic)
    }

    private static func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
