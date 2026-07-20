import AppKit
import Combine
import Foundation
import ImageIO
import UniformTypeIdentifiers

@MainActor
final class ColorPickerService: ObservableObject {
    struct Sample: Identifiable {
        let id = UUID()
        let color: NSColor
        let hex: String
    }

    static let shared = ColorPickerService()
    @Published private(set) var color: NSColor?
    @Published private(set) var hex = "—"
    @Published private(set) var history: [Sample] = []

    func sample() {
        NSColorSampler().show { [weak self] sampled in
            guard let sampled, let rgb = sampled.usingColorSpace(.sRGB) else { return }
            Task { @MainActor in
                let hex = String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
                self?.color = rgb
                self?.hex = hex
                if self?.history.first?.hex != hex {
                    self?.history.insert(Sample(color: rgb, hex: hex), at: 0)
                    if let count = self?.history.count, count > 8 {
                        self?.history.removeLast(count - 8)
                    }
                }
            }
        }
    }

    func copyHex() {
        guard hex != "—" else { return }
        copy(hex)
    }

    func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }

    var rgbDescription: String {
        guard let color else { return "—" }
        return String(format: "RGB %.0f, %.0f, %.0f", color.redComponent * 255, color.greenComponent * 255, color.blueComponent * 255)
    }

    var hsbDescription: String {
        guard let color else { return "—" }
        return String(format: "HSB %.0f°, %.0f%%, %.0f%%", color.hueComponent * 360, color.saturationComponent * 100, color.brightnessComponent * 100)
    }
}

@MainActor
final class MediaCompressorService: ObservableObject {
    struct Result: Identifiable {
        let id = UUID()
        let source: URL
        let output: URL?
        let originalBytes: Int64
        let candidateBytes: Int64

        var savedBytes: Int64 { output == nil ? 0 : max(0, originalBytes - candidateBytes) }
        var savingsPercent: Double {
            guard originalBytes > 0, output != nil else { return 0 }
            return Double(savedBytes) / Double(originalBytes)
        }
    }

    @Published private(set) var results: [Result] = []
    @Published private(set) var isWorking = false
    @Published private(set) var errorMessage: String?
    var quality = 0.72
    var removeMetadata = true

    func chooseAndCompress() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.jpeg, .png, .heic, .gif]
        guard panel.runModal() == .OK else { return }
        compress(panel.urls)
    }

    private func compress(_ urls: [URL]) {
        isWorking = true
        errorMessage = nil
        let quality = quality
        let removeMetadata = removeMetadata
        Task { [weak self] in
            let outcome = await Task.detached(priority: .userInitiated) {
                var outputResults: [Result] = []
                var failures: [String] = []
                for url in urls {
                    do { outputResults.append(try Self.compressFile(url, quality: quality, removeMetadata: removeMetadata)) }
                    catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
                }
                return (outputResults, failures)
            }.value
            self?.results = outcome.0
            self?.isWorking = false
            self?.errorMessage = outcome.1.isEmpty ? nil : outcome.1.joined(separator: "\n")
        }
    }

    nonisolated static func compressFile(_ url: URL, quality: Double, removeMetadata: Bool) throws -> Result {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let type = CGImageSourceGetType(source) else { throw CocoaError(.fileReadCorruptFile) }
        let stem = url.deletingPathExtension().lastPathComponent
        let output = availableOutputURL(beside: url, stem: stem)
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)-\(output.lastPathComponent)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, type, CGImageSourceGetCount(source), nil) else { throw CocoaError(.fileWriteUnknown) }
        let count = CGImageSourceGetCount(source)
        for index in 0..<count {
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            var properties = removeMetadata ? [:] : (CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:])
            properties[kCGImageDestinationLossyCompressionQuality] = quality
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        let original = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        let candidate = (try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0

        // ImageIO can make already-optimized PNG/GIF files larger. Never keep a
        // result that is not a real reduction; the original remains untouched.
        guard candidate > 0, candidate < original else {
            return Result(source: url, output: nil, originalBytes: original, candidateBytes: candidate)
        }

        try FileManager.default.moveItem(at: temporary, to: output)
        return Result(source: url, output: output, originalBytes: original, candidateBytes: candidate)
    }

    nonisolated private static func availableOutputURL(beside source: URL, stem: String) -> URL {
        let directory = source.deletingLastPathComponent()
        let ext = source.pathExtension
        var index = 1
        var candidate = directory.appendingPathComponent("\(stem)-compressed.\(ext)")
        while FileManager.default.fileExists(atPath: candidate.path) {
            index += 1
            candidate = directory.appendingPathComponent("\(stem)-compressed-\(index).\(ext)")
        }
        return candidate
    }
}

@MainActor
final class AudioCapabilityReportService: ObservableObject {
    struct Device: Identifiable {
        let name: String
        let manufacturer: String
        let outputChannels: Int
        let sampleRate: Int
        let transport: String
        let isDefaultOutput: Bool

        var id: String { "\(name)-\(manufacturer)-\(transport)" }
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    var processTapAPISupported: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0)
        )
    }

    var defaultOutput: Device? {
        devices.first(where: \.isDefaultOutput)
    }

    var virtualOutputCount: Int {
        devices.filter { $0.transport.localizedCaseInsensitiveContains("virtual") }.count
    }

    func refresh() {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task { [weak self] in
            let outcome: Result<[Device], Error> = await Task.detached(priority: .userInitiated) {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                process.arguments = ["SPAudioDataType", "-json"]
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    guard process.terminationStatus == 0 else {
                        throw NSError(
                            domain: "MacCleaner.AudioReport",
                            code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: "system_profiler could not read the current audio routes."]
                        )
                    }
                    return .success(try Self.parseDevices(data))
                } catch {
                    return .failure(error)
                }
            }.value
            guard let self else { return }
            self.isLoading = false
            switch outcome {
            case .success(let devices): self.devices = devices
            case .failure(let error): self.errorMessage = error.localizedDescription
            }
        }
    }

    nonisolated private static func parseDevices(_ data: Data) throws -> [Device] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let groups = root["SPAudioDataType"] as? [[String: Any]] ?? []
        let items = groups.flatMap { $0["_items"] as? [[String: Any]] ?? [] }
        return items.compactMap { item in
            guard let name = item["_name"] as? String,
                  let outputs = item["coreaudio_device_output"] as? Int,
                  outputs > 0 else { return nil }
            let rawTransport = item["coreaudio_device_transport"] as? String ?? "unknown"
            let transport = rawTransport
                .replacingOccurrences(of: "coreaudio_device_type_", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .capitalized
            return Device(
                name: name,
                manufacturer: item["coreaudio_device_manufacturer"] as? String ?? "Unknown",
                outputChannels: outputs,
                sampleRate: item["coreaudio_device_srate"] as? Int ?? 0,
                transport: transport,
                isDefaultOutput: item["coreaudio_default_audio_output_device"] as? String == "spaudio_yes"
            )
        }
    }
}

@MainActor
final class HomebrewService: ObservableObject {
    struct Package: Identifiable, Hashable {
        let name: String
        let kind: String
        let currentVersion: String
        var id: String { "\(kind):\(name)" }
    }

    @Published private(set) var executable: URL?
    @Published private(set) var output = "Run an audit to inspect Homebrew."
    @Published private(set) var isWorking = false
    @Published private(set) var packages: [Package] = []
    @Published var selectedNames: Set<String> = []

    init() { executable = Self.locateBrew() }

    func audit() { run(["outdated", "--json=v2"], parseAudit: true) }
    func cleanupDryRun() { run(["cleanup", "--dry-run"]) }
    func cleanup() { run(["cleanup"]) }
    func upgradeSelected() {
        let names = packages.filter { selectedNames.contains($0.id) }.map(\.name)
        guard !names.isEmpty else { return }
        run(["upgrade"] + names)
    }

    func toggle(_ package: Package) {
        if selectedNames.contains(package.id) { selectedNames.remove(package.id) }
        else { selectedNames.insert(package.id) }
    }

    private func run(_ arguments: [String], parseAudit: Bool = false) {
        guard let executable, !isWorking else { return }
        isWorking = true
        output = "Running brew \(arguments.joined(separator: " "))…"
        Task { [weak self] in
            let outcome: Result<String, Error> = await Task.detached(priority: .userInitiated) {
                let process = Process()
                let pipe = Pipe()
                process.executableURL = executable
                process.arguments = arguments
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                    process.waitUntilExit()
                    return .success(String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "")
                } catch { return .failure(error) }
            }.value
            guard let self else { return }
            self.isWorking = false
            switch outcome {
            case .success(let text):
                self.output = text.isEmpty ? "Homebrew found no items requiring attention." : text
                if parseAudit, let parsed = Self.parseOutdated(Data(text.utf8)) {
                    self.packages = parsed
                    self.selectedNames = self.selectedNames.filter { id in parsed.contains { $0.id == id } }
                }
            case .failure(let error): self.output = error.localizedDescription
            }
        }
    }

    nonisolated private static func locateBrew() -> URL? {
        ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].map(URL.init(fileURLWithPath:)).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    nonisolated private static func parseOutdated(_ data: Data) -> [Package]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var result: [Package] = []
        for (key, kind) in [("formulae", "Formula"), ("casks", "Cask")] {
            for item in root[key] as? [[String: Any]] ?? [] {
                guard let name = item["name"] as? String else { continue }
                let version = item["current_version"] as? String
                    ?? (item["installed_versions"] as? [String])?.joined(separator: ", ")
                    ?? "outdated"
                result.append(Package(name: name, kind: kind, currentVersion: version))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

@MainActor
final class ShelfStore: ObservableObject {
    final class ItemProviderBox: @unchecked Sendable {
        let value: NSItemProvider
        init(_ value: NSItemProvider) { self.value = value }
    }

    struct Item: Identifiable {
        enum Storage: Equatable { case sessionCopy, temporary }
        let id = UUID()
        let title: String
        let subtitle: String
        let storage: Storage
        let providerBox: ItemProviderBox
        let storedURL: URL?
        var provider: NSItemProvider { providerBox.value }
    }

    static let shared = ShelfStore()
    @Published private(set) var items: [Item] = []
    private let sessionDirectory: URL
    private var terminationObserver: NSObjectProtocol?

    private init() {
        sessionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleaner-DropShelf-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.cleanupSessionStorage() }
        }
    }

    var sessionCopyCount: Int { items.filter { $0.storage == .sessionCopy }.count }
    var temporaryCount: Int { items.filter { $0.storage == .temporary }.count }

    func accept(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            let providerBox = ItemProviderBox(provider)
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { [weak self] value, _ in
                    let url = Self.resolveURL(value)
                    guard let url else { return }
                    // Keep the user's source out of every later drag. Shelf
                    // owns a session copy and exports a disposable copy of it
                    // for each destination, so a destination move can never
                    // move or invalidate the original file.
                    guard let directory = self?.sessionDirectory else { return }
                    Task.detached(priority: .userInitiated) {
                        guard let storedURL = Self.copyIntoSession(url, directory: directory) else { return }
                        await MainActor.run {
                            ShelfStore.shared.items.append(Item(
                                title: url.lastPathComponent,
                                subtitle: "Session copy · original unchanged",
                                storage: .sessionCopy,
                                providerBox: ItemProviderBox(Self.makeFileProvider(for: storedURL)),
                                storedURL: storedURL
                            ))
                        }
                    }
                }
            } else if provider.canLoadObject(ofClass: NSImage.self) {
                let suggestedName = provider.suggestedName
                provider.loadObject(ofClass: NSImage.self) { [weak self] value, _ in
                    guard let image = value as? NSImage else { return }
                    let dimensions = "\(Int(image.size.width)) × \(Int(image.size.height))"
                    Task { @MainActor in
                        self?.items.append(Item(title: suggestedName ?? "Image", subtitle: "Image · \(dimensions) · original formats", storage: .temporary, providerBox: providerBox, storedURL: nil))
                    }
                }
            } else if provider.canLoadObject(ofClass: NSString.self) {
                let suggestedName = provider.suggestedName
                provider.loadObject(ofClass: NSString.self) { [weak self] value, _ in
                    guard let text = value as? String else { return }
                    let textProvider = Self.makeTextProvider(text, suggestedName: suggestedName)
                    Task { @MainActor in self?.items.append(Item(title: String(text.prefix(80)), subtitle: "Temporary text · original formats", storage: .temporary, providerBox: ItemProviderBox(textProvider), storedURL: nil)) }
                }
            } else {
                items.append(Item(title: provider.suggestedName ?? "Dropped item", subtitle: "Temporary item", storage: .temporary, providerBox: providerBox, storedURL: nil))
            }
        }
        return !providers.isEmpty
    }

    func remove(_ item: Item) {
        if let storedURL = item.storedURL { removeStoredItem(at: storedURL) }
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items.forEach { if let storedURL = $0.storedURL { removeStoredItem(at: storedURL) } }
        items.removeAll()
    }

    func pasteFromClipboard() {
        let payload = PasteboardPayload(pasteboard: .general)
        _ = accept(payload.makeItemProviders())
    }

    func dragProvider(for item: Item) -> NSItemProvider {
        guard let storedURL = item.storedURL else { return item.provider }
        // Build a new disposable export for every drag. A destination such as
        // Telegram may move the handed-off URL instead of copying it; a fresh
        // provider keeps the Shelf session copy available for later drags.
        return Self.makeFileProvider(for: storedURL)
    }

    /// Places a disposable export on the system pasteboard. This is a
    /// destination-agnostic fallback for apps (including some Telegram
    /// builds) that do not accept an `NSItemProvider` drag, but do accept a
    /// file URL pasted with Cmd+V.
    func copyForPaste(_ item: Item) {
        if let storedURL = item.storedURL,
           let exportURL = Self.makeExportCopy(of: storedURL) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([exportURL as NSURL])
            return
        }

        // Clipboard images are intentionally kept as session-only objects,
        // so materialize the image directly into the system pasteboard.
        if item.provider.canLoadObject(ofClass: NSImage.self) {
            item.provider.loadObject(ofClass: NSImage.self) { value, _ in
                guard let image = value as? NSImage else { return }
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                }
            }
        } else if item.provider.canLoadObject(ofClass: NSString.self) {
            item.provider.loadObject(ofClass: NSString.self) { value, _ in
                guard let text = value as? NSString else { return }
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([text])
                }
            }
        }
    }

    private func cleanupSessionStorage() {
        try? FileManager.default.removeItem(at: sessionDirectory)
        if let terminationObserver { NotificationCenter.default.removeObserver(terminationObserver) }
    }

    private func removeStoredItem(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    nonisolated private static func resolveURL(_ value: NSSecureCoding?) -> URL? {
        if let url = value as? URL { return url }
        if let url = value as? NSURL { return url as URL }
        if let data = value as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let path = value as? NSString { return URL(fileURLWithPath: path as String) }
        return nil
    }

    nonisolated private static func copyIntoSession(_ sourceURL: URL, directory: URL) -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else { return nil }
        let itemDirectory = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try fileManager.createDirectory(at: itemDirectory, withIntermediateDirectories: true)
            let destination = itemDirectory.appendingPathComponent(sourceURL.lastPathComponent)
            try fileManager.copyItem(at: sourceURL, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: itemDirectory)
            return nil
        }
    }

    nonisolated private static func makeFileProvider(for storedURL: URL) -> NSItemProvider {
        guard let objectExportURL = makeExportCopy(of: storedURL) else {
            return NSItemProvider()
        }
        // Use the canonical macOS file URL provider so Finder, Telegram and
        // other destinations negotiate the same public.file-url payload.
        let provider = NSItemProvider(object: objectExportURL as NSURL)
        provider.suggestedName = storedURL.lastPathComponent
        return provider
    }

    nonisolated private static func makeExportCopy(of storedURL: URL) -> URL? {
        let exportDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacCleaner-DropShelf-Export-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
            let exportURL = exportDirectory.appendingPathComponent(storedURL.lastPathComponent)
            try FileManager.default.copyItem(at: storedURL, to: exportURL)
            return exportURL
        } catch {
            try? FileManager.default.removeItem(at: exportDirectory)
            return nil
        }
    }

    nonisolated private static func makeTextProvider(_ text: String, suggestedName: String?) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(text.utf8)
        provider.suggestedName = suggestedName
        provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}
