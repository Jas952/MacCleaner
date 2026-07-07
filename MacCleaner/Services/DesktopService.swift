import Foundation
import AppKit
import SwiftUI
import QuickLookUI

// MARK: - Models

enum DesktopFileCategory: String, CaseIterable, Hashable {
    case screenshot  = "Screenshots"
    case image       = "Images"
    case document    = "Documents"
    case archive     = "Archives"
    case video       = "Videos"
    case audio       = "Audio"
    case code        = "Code"
    case other       = "Other"

    var icon: String {
        switch self {
        case .screenshot: return "camera.viewfinder"
        case .image:      return "photo"
        case .document:   return "doc.text"
        case .archive:    return "archivebox"
        case .video:      return "film"
        case .audio:      return "music.note"
        case .code:       return "chevron.left.forwardslash.chevron.right"
        case .other:      return "doc"
        }
    }

    var color: Color {
        switch self {
        case .screenshot: return .purple
        case .image:      return .blue
        case .document:   return .orange
        case .archive:    return .brown
        case .video:      return .pink
        case .audio:      return .green
        case .code:       return .cyan
        case .other:      return .gray
        }
    }

    static func classify(_ url: URL) -> DesktopFileCategory {
        let ext = url.pathExtension.lowercased()
        let name = url.deletingPathExtension().lastPathComponent.lowercased()

        // Screenshots heuristic: name starts with "screenshot" or "screen shot" or "снимок экрана"
        if name.hasPrefix("screenshot") || name.hasPrefix("screen shot") ||
           name.hasPrefix("снимок экрана") || name.hasPrefix("capture") {
            return .screenshot
        }
        switch ext {
        case "png", "jpg", "jpeg", "heic", "gif", "bmp", "tiff", "webp": return .image
        case "pdf", "doc", "docx", "txt", "rtf", "pages", "key", "numbers",
             "xls", "xlsx", "ppt", "pptx", "csv", "md": return .document
        case "zip", "rar", "7z", "tar", "gz", "dmg", "pkg", "iso": return .archive
        case "mp4", "mov", "avi", "mkv", "m4v", "wmv", "flv": return .video
        case "mp3", "aac", "wav", "flac", "m4a", "ogg": return .audio
        case "swift", "py", "js", "ts", "html", "css", "json", "xml",
             "sh", "rb", "go", "rs", "cpp", "c", "h": return .code
        default: return .other
        }
    }
}

enum DesktopSortOrder: String, CaseIterable {
    case name        = "Name"
    case size        = "Size"
    case dateAdded   = "Date Added"
    case dateModified = "Date Modified"
    case kind        = "Kind"
}

struct DesktopFile: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let name: String
    let ext: String
    let size: UInt64
    let dateAdded: Date
    let dateModified: Date
    let category: DesktopFileCategory
    var isDirectory: Bool = false
    var position: CGPoint = .zero

    // isSelected хранится отдельно в DesktopService.selectedIDs
    // чтобы мутация выборки не перестраивала весь ForEach
    var isSelected: Bool = false  // проставляется в displayedFiles через selectedIDs

    init(url: URL, name: String, ext: String, size: UInt64,
         dateAdded: Date, dateModified: Date, category: DesktopFileCategory) {
        self.id = UUID()
        self.url = url; self.name = name; self.ext = ext; self.size = size
        self.dateAdded = dateAdded; self.dateModified = dateModified; self.category = category
    }

    static func == (lhs: DesktopFile, rhs: DesktopFile) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var formattedSize: String { ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file) }
    var displayName: String { ext.isEmpty ? name : "\(name).\(ext)" }
}

// MARK: - Service

enum DesktopViewMode: String, CaseIterable {
    case grid    = "Grid"
    case list    = "List"
    case columns = "Columns"

    var icon: String {
        switch self {
        case .grid:    return "square.grid.2x2"
        case .list:    return "list.bullet"
        case .columns: return "rectangle.split.3x1"
        }
    }
}

class DesktopService: ObservableObject {
    @Published var files: [DesktopFile] = []
    @Published var selectedIDs: Set<UUID> = []   // отдельно от files — не триггерит ForEach
    @Published var isScanning = false
    @Published var wallpaperImage: NSImage? = nil
    @Published var sortOrder: DesktopSortOrder = .dateAdded
    @Published var groupByCategory = false
    @Published var filterCategory: DesktopFileCategory? = nil
    @Published var searchQuery = ""
    @Published var totalSize: UInt64 = 0
    @Published var viewMode: DesktopViewMode = .grid
    // Рекурсивный подсчёт всего Desktop — не зависит от текущей папки
    @Published var desktopTotalCount: Int = 0
    @Published var desktopTotalSize: UInt64 = 0
    @Published var desktopCategorySummary: [(DesktopFileCategory, Int, UInt64)] = []
    @Published var desktopRecursiveFiles: [DesktopFile] = []
    // Screen resolution used when positions were captured
    @Published var screenSize: CGSize = NSScreen.main.map { $0.frame.size } ?? CGSize(width: 1440, height: 900)

    // Navigation
    @Published var currentURL: URL
    private var history: [URL] = []
    private var forwardStack: [URL] = []

    let desktopURL: URL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!

    var canGoBack: Bool    { !history.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var isAtDesktop: Bool  { currentURL == desktopURL }

    var breadcrumbs: [URL] {
        var parts: [URL] = []
        var url = currentURL
        while url.path != desktopURL.deletingLastPathComponent().path {
            parts.insert(url, at: 0)
            let parent = url.deletingLastPathComponent()
            if parent == url { break }
            url = parent
        }
        return parts
    }

    init() {
        self.currentURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    }

    // MARK: - Рекурсивный подсчёт всего Desktop

    func scanDesktopSummary() {
        let root = desktopURL
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey, .isHiddenKey, .addedToDirectoryDateKey, .contentModificationDateKey]
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { return }

            var totalCount = 0
            var totalSize: UInt64 = 0
            var byCat: [DesktopFileCategory: (Int, UInt64)] = [:]
            var recursiveFiles: [DesktopFile] = []

            while let url = enumerator.nextObject() as? URL {
                let res = try? url.resourceValues(forKeys: Set(keys))
                guard res?.isDirectory != true else { continue }  // только файлы
                let size = UInt64(res?.fileSize ?? 0)
                let cat = DesktopFileCategory.classify(url)
                let added = res?.addedToDirectoryDate ?? Date()
                let modified = res?.contentModificationDate ?? Date()
                let file = DesktopFile(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    ext: url.pathExtension.lowercased(),
                    size: size,
                    dateAdded: added,
                    dateModified: modified,
                    category: cat
                )
                recursiveFiles.append(file)
                totalCount += 1
                totalSize += size
                let prev = byCat[cat] ?? (0, 0)
                byCat[cat] = (prev.0 + 1, prev.1 + size)
            }

            let summary = DesktopFileCategory.allCases.compactMap { cat -> (DesktopFileCategory, Int, UInt64)? in
                guard let (cnt, sz) = byCat[cat], cnt > 0 else { return nil }
                return (cat, cnt, sz)
            }.sorted { $0.2 > $1.2 }

            let finalTotalCount = totalCount
            let finalTotalSize = totalSize
            let finalSummary = summary
            let finalRecursiveFiles = recursiveFiles

            await MainActor.run {
                self.desktopTotalCount = finalTotalCount
                self.desktopTotalSize = finalTotalSize
                self.desktopCategorySummary = finalSummary
                self.desktopRecursiveFiles = finalRecursiveFiles
            }
        }
    }

    // Computed filtered + sorted list — isSelected читается из selectedIDs
    var displayedFiles: [DesktopFile] {
        var result = filterCategory == nil ? files : desktopRecursiveFiles

        if let cat = filterCategory {
            result = result.filter { !$0.isDirectory && $0.category == cat }
        }
        if !searchQuery.isEmpty {
            result = result.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) }
        }

        switch sortOrder {
        case .name:         result.sort { $0.name.lowercased() < $1.name.lowercased() }
        case .size:         result.sort { $0.size > $1.size }
        case .dateAdded:    result.sort { $0.dateAdded > $1.dateAdded }
        case .dateModified: result.sort { $0.dateModified > $1.dateModified }
        case .kind:         result.sort { $0.category.rawValue < $1.category.rawValue }
        }

        return result
    }

    var groupedFiles: [(DesktopFileCategory, [DesktopFile])] {
        let sorted = displayedFiles
        var dict: [DesktopFileCategory: [DesktopFile]] = [:]
        for f in sorted { dict[f.category, default: []].append(f) }
        return DesktopFileCategory.allCases.compactMap { cat in
            guard let arr = dict[cat], !arr.isEmpty else { return nil }
            return (cat, arr)
        }
    }

    var categorySummary: [(DesktopFileCategory, Int, UInt64)] {
        var result: [(DesktopFileCategory, Int, UInt64)] = []
        for cat in DesktopFileCategory.allCases {
            let catFiles = desktopRecursiveFiles.filter { !$0.isDirectory && $0.category == cat }
            if !catFiles.isEmpty {
                result.append((cat, catFiles.count, catFiles.reduce(0) { $0 + $1.size }))
            }
        }
        return result.sorted { $0.2 > $1.2 }
    }

    func navigate(to url: URL) {
        history.append(currentURL)
        forwardStack.removeAll()
        currentURL = url
        searchQuery = ""
        filterCategory = nil
        scanCurrentDirectory()
    }

    func goBack() {
        guard let prev = history.popLast() else { return }
        forwardStack.append(currentURL)
        currentURL = prev
        scanCurrentDirectory()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        history.append(currentURL)
        currentURL = next
        scanCurrentDirectory()
    }

    func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        guard parent != currentURL else { return }
        navigate(to: parent)
    }

    func scanCurrentDirectory() {
        scan(url: currentURL)
    }

    @discardableResult
    func createFolder(named name: String) -> Bool {
        let newURL = currentURL.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: false)
            scanCurrentDirectory()
            return true
        } catch { return false }
    }

    func moveItems(_ items: [DesktopFile], to destination: URL) {
        let fm = FileManager.default
        for item in items {
            let dest = destination.appendingPathComponent(item.url.lastPathComponent)
            try? fm.moveItem(at: item.url, to: dest)
        }
        scanCurrentDirectory()
    }

    func duplicate(_ file: DesktopFile) {
        let fm = FileManager.default
        let ext = file.url.pathExtension
        let base = file.url.deletingPathExtension().lastPathComponent
        let suffix = ext.isEmpty ? " copy" : ""
        var dest = file.url.deletingLastPathComponent()
            .appendingPathComponent(base + " copy")
            .appendingPathExtension(ext)
        var n = 2
        while fm.fileExists(atPath: dest.path) {
            dest = file.url.deletingLastPathComponent()
                .appendingPathComponent("\(base) copy \(n)")
                .appendingPathExtension(ext)
            n += 1
        }
        let _ = suffix
        try? fm.copyItem(at: file.url, to: dest)
        scanCurrentDirectory()
    }

    func scan() {
        scan(url: desktopURL)
    }

    private func scan(url: URL) {
        isScanning = true
        // Capture screen size on MainActor before going off-thread
        let screenSz = NSScreen.main?.frame.size ?? CGSize(width: 1440, height: 900)
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            let keys: [URLResourceKey] = [.fileSizeKey, .addedToDirectoryDateKey, .contentModificationDateKey, .isDirectoryKey, .isHiddenKey]

            guard let contents = try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles]
            ) else {
                await MainActor.run { self.isScanning = false }
                return
            }

            var result: [DesktopFile] = []
            var total: UInt64 = 0
            var col = 0
            var row = 0
            let iconsPerCol = max(1, Int(screenSz.height / 90))

            for url in contents {
                let res = try? url.resourceValues(forKeys: Set(keys))
                let isDir = res?.isDirectory ?? false
                let size = UInt64(res?.fileSize ?? 0)
                let added = res?.addedToDirectoryDate ?? Date()
                let modified = res?.contentModificationDate ?? Date()
                let cat = DesktopFileCategory.classify(url)

                // Use xattr fallback + grid default (AppleScript called separately for Canvas)
                let pos = Self.readFinderPosition(url: url, screenSize: screenSz)
                    ?? CGPoint(
                        x: screenSz.width - 80 - CGFloat(col) * 90,
                        y: screenSz.height - 60 - CGFloat(row) * 90
                    )

                row += 1
                if row >= iconsPerCol { row = 0; col += 1 }

                var file = DesktopFile(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    ext: isDir ? "" : url.pathExtension.lowercased(),
                    size: isDir ? 0 : size,
                    dateAdded: added,
                    dateModified: modified,
                    category: cat
                )
                file.isDirectory = isDir
                file.position = pos
                result.append(file)
                total += file.size
            }

            let wallpaper = await Self.loadWallpaper()

            let finalFiles = result
            let finalTotal = total

            await MainActor.run {
                self.files = finalFiles
                self.totalSize = finalTotal
                self.wallpaperImage = wallpaper
                self.screenSize = screenSz
                self.isScanning = false
            }
        }
    }

    func showInFinder(url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // Called explicitly when Canvas tab opens — loads real Finder positions without blocking regular scan
    func loadCanvasPositions() {
        Task.detached(priority: .background) {
            let positions = Self.readAllFinderPositions(in: self.desktopURL)
            guard !positions.isEmpty else { return }
            await MainActor.run {
                self.files = self.files.map { f in
                    var copy = f
                    if let pt = positions[f.url.path] { copy.position = pt }
                    return copy
                }
            }
        }
    }

    // Read ALL Finder icon positions in one AppleScript call — much more reliable than xattr
    static func readAllFinderPositions(in folder: URL) -> [String: CGPoint] {
        let folderPath = folder.path
        let script = """
        set result to {}
        tell application "Finder"
            try
                set f to POSIX file "\(folderPath)" as alias
                set itemList to every item of folder f
                repeat with anItem in itemList
                    set p to position of anItem
                    set posStr to (item 1 of p as text) & "," & (item 2 of p as text)
                    set result to result & {(POSIX path of (anItem as alias)) & "|" & posStr}
                end repeat
            end try
        end tell
        return result
        """
        var positions: [String: CGPoint] = [:]
        var err: NSDictionary?
        guard let s = NSAppleScript(source: script) else { return positions }
        let desc = s.executeAndReturnError(&err)
        guard err == nil else { return positions }
        let count = desc.numberOfItems
        for i in 1...max(1, count) {
            guard i <= count,
                  let item = desc.atIndex(i)?.stringValue else { continue }
            let parts = item.components(separatedBy: "|")
            guard parts.count == 2 else { continue }
            let path = parts[0]
            let coords = parts[1].components(separatedBy: ",")
            guard coords.count == 2,
                  let x = Double(coords[0].trimmingCharacters(in: .whitespaces)),
                  let y = Double(coords[1].trimmingCharacters(in: .whitespaces)) else { continue }
            positions[path] = CGPoint(x: x, y: y)
        }
        return positions
    }

    // Read Finder icon position from com.apple.FinderInfo xattr (fallback)
    // Finder stores position in the 16 bytes of FinderInfo at offset 0 (FndrFileInfo: fdLocation)
    private static func readFinderPosition(url: URL, screenSize: CGSize) -> CGPoint? {
        let path = url.path
        let attrName = "com.apple.FinderInfo"
        let bufLen = 32
        var buf = [UInt8](repeating: 0, count: bufLen)
        let result = getxattr(path, attrName, &buf, bufLen, 0, 0)
        guard result == bufLen else { return nil }
        // Bytes 0-1: fdLocation.v (vertical, top-down), 2-3: fdLocation.h (horizontal)
        let v = Int16(bigEndian: buf.withUnsafeBytes { $0.load(fromByteOffset: 0, as: Int16.self) })
        let h = Int16(bigEndian: buf.withUnsafeBytes { $0.load(fromByteOffset: 2, as: Int16.self) })
        guard h != 0 || v != 0 else { return nil }
        // Finder uses screen coordinates (0,0 = top-left of screen)
        let x = CGFloat(h)
        let y = CGFloat(v)
        // Clamp to a sane range
        guard x > 0, y > 0, x < screenSize.width * 2, y < screenSize.height * 2 else { return nil }
        return CGPoint(x: x, y: y)
    }

    // Local-only position update (no AppleScript) — used during drag
    func updatePositionLocal(id: UUID, to point: CGPoint) {
        guard let idx = files.firstIndex(where: { $0.id == id }) else { return }
        files[idx].position = point
    }

    // Write position back via AppleScript — call explicitly via Apply button
    func updatePosition(id: UUID, to point: CGPoint) {
        guard let idx = files.firstIndex(where: { $0.id == id }) else { return }
        files[idx].position = point
        let filePath = files[idx].url.path
        let x = Int(point.x)
        let y = Int(point.y)
        let script = """
        tell application "Finder"
            set position of (POSIX file "\(filePath)" as alias) to {\(x), \(y)}
        end tell
        """
        Task.detached(priority: .utility) {
            var err: NSDictionary?
            if let s = NSAppleScript(source: script) { s.executeAndReturnError(&err) }
        }
    }

    private static func loadWallpaper() async -> NSImage? {
        guard let screen = NSScreen.main,
              let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let img = NSImage(contentsOf: url) else { return nil }
        return img
    }

    // MARK: - Actions

    func trash(files toDelete: [DesktopFile], completion: @escaping (Int) -> Void) {
        Task.detached(priority: .utility) {
            var count = 0
            for f in toDelete {
                if (try? FileManager.default.trashItem(at: f.url, resultingItemURL: nil)) != nil {
                    count += 1
                }
            }
            let deleted = toDelete.map { $0.id }
            let finalCount = count
            await MainActor.run {
                self.files.removeAll { deleted.contains($0.id) }
                self.totalSize = self.files.reduce(0) { $0 + $1.size }
                completion(finalCount)
                self.scanDesktopSummary()
            }
        }
    }

    func open(_ file: DesktopFile) {
        NSWorkspace.shared.open(file.url)
    }

    func showInFinder(_ file: DesktopFile) {
        showInFinder(url: file.url)
    }

    func autoOrganize(completion: @escaping (Int) -> Void) {
        Task.detached(priority: .utility) {
            let fm = FileManager.default
            var moved = 0

            let toOrganize = await MainActor.run {
                self.files.filter { $0.category != .other || !$0.ext.isEmpty }
            }

            for file in toOrganize {
                let folderName = file.category.rawValue
                let destFolder = self.desktopURL.appendingPathComponent(folderName)

                // Create folder if needed
                if !fm.fileExists(atPath: destFolder.path) {
                    try? fm.createDirectory(at: destFolder, withIntermediateDirectories: true)
                }

                let dest = destFolder.appendingPathComponent(file.url.lastPathComponent)
                guard !fm.fileExists(atPath: dest.path) else { continue }

                do {
                    try fm.moveItem(at: file.url, to: dest)
                    moved += 1
                } catch {
                    print("Move failed: \(error)")
                }
            }

            let finalMoved = moved
            await MainActor.run {
                self.scan()
                self.scanDesktopSummary()
                completion(finalMoved)
            }
        }
    }

    func rename(_ file: DesktopFile, to newName: String) -> Bool {
        let newURL = file.url.deletingLastPathComponent()
            .appendingPathComponent(newName)
            .appendingPathExtension(file.ext)
        do {
            try FileManager.default.moveItem(at: file.url, to: newURL)
            if let idx = files.firstIndex(where: { $0.id == file.id }) {
                files[idx] = DesktopFile(
                    url: newURL, name: newName, ext: file.ext,
                    size: file.size, dateAdded: file.dateAdded, dateModified: Date(),
                    category: file.category
                )
            }
            return true
        } catch {
            return false
        }
    }

    var selectedFiles: [DesktopFile] { files.filter { selectedIDs.contains($0.id) } }

    func toggleSelect(id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    func selectAll()   { selectedIDs = Set(files.map { $0.id }) }
    func deselectAll() { selectedIDs.removeAll() }

    func selectByCategories(_ cats: [DesktopFileCategory]) {
        selectedIDs = Set(files.filter { cats.contains($0.category) }.map { $0.id })
    }

    // MARK: - Image Metadata

    func readImageMetadata(for file: DesktopFile) -> ImageMetadata? {
        guard let src = CGImageSourceCreateWithURL(file.url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }

        let width  = props[kCGImagePropertyPixelWidth]  as? Int
        let height = props[kCGImagePropertyPixelHeight] as? Int
        let dpi    = props[kCGImagePropertyDPIWidth]    as? Double
        let depth  = props[kCGImagePropertyDepth]       as? Int
        let colorModel = props[kCGImagePropertyColorModel] as? String

        var dateTaken: String? = nil
        var camera: String? = nil
        var lens: String? = nil
        var iso: Int? = nil
        var fNumber: Double? = nil
        var exposureTime: Double? = nil
        var focalLength: Double? = nil
        var gpsLat: Double? = nil
        var gpsLon: Double? = nil

        if let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any] {
            dateTaken    = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            iso          = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
            fNumber      = exif[kCGImagePropertyExifFNumber]         as? Double
            exposureTime = exif[kCGImagePropertyExifExposureTime]    as? Double
            focalLength  = exif[kCGImagePropertyExifFocalLength]     as? Double
            lens         = exif[kCGImagePropertyExifLensModel]       as? String
        }
        if let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            let make  = tiff[kCGImagePropertyTIFFMake]  as? String
            let model = tiff[kCGImagePropertyTIFFModel] as? String
            camera = [make, model].compactMap { $0 }.joined(separator: " ").isEmpty ? nil
                   : [make, model].compactMap { $0 }.joined(separator: " ")
        }
        if let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            gpsLat = gps[kCGImagePropertyGPSLatitude]  as? Double
            gpsLon = gps[kCGImagePropertyGPSLongitude] as? Double
        }

        return ImageMetadata(
            width: width, height: height, dpi: dpi, colorDepth: depth,
            colorModel: colorModel, dateTaken: dateTaken,
            camera: camera, lens: lens,
            iso: iso, fNumber: fNumber, exposureTime: exposureTime,
            focalLength: focalLength,
            gpsLatitude: gpsLat, gpsLongitude: gpsLon
        )
    }
}

// MARK: - Image Metadata Model

struct ImageMetadata {
    var width: Int?
    var height: Int?
    var dpi: Double?
    var colorDepth: Int?
    var colorModel: String?
    var dateTaken: String?
    var camera: String?
    var lens: String?
    var iso: Int?
    var fNumber: Double?
    var exposureTime: Double?
    var focalLength: Double?
    var gpsLatitude: Double?
    var gpsLongitude: Double?

    var resolution: String? {
        guard let w = width, let h = height else { return nil }
        return "\(w) × \(h) px"
    }
    var fNumberFormatted: String? {
        guard let f = fNumber else { return nil }
        return String(format: "ƒ/%.1f", f)
    }
    var exposureFormatted: String? {
        guard let e = exposureTime else { return nil }
        if e >= 1 { return String(format: "%.1f s", e) }
        let denom = Int(1.0 / e + 0.5)
        return "1/\(denom) s"
    }
    var focalLengthFormatted: String? {
        guard let f = focalLength else { return nil }
        return String(format: "%.0f mm", f)
    }
    var gpsFormatted: String? {
        guard let lat = gpsLatitude, let lon = gpsLongitude else { return nil }
        return String(format: "%.5f°, %.5f°", lat, lon)
    }
}
