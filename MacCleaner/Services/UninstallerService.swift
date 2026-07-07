import Foundation
import Cocoa

// MARK: - Models

struct AppRelatedFile: Identifiable {
    let id = UUID()
    let url: URL
    let label: String
    let size: UInt64
    var isSelected: Bool = true
}

struct InstalledApp: Identifiable {
    let id = UUID()
    let name: String
    let bundleIdentifier: String
    let appPath: URL
    let appSize: UInt64
    let icon: NSImage
    var autoSelected: [AppRelatedFile]
    var needsReview: [AppRelatedFile]
    let version: String
    let lastUsed: Date?
    let installationDate: Date?

    var relatedFiles: [URL] { autoSelected.filter(\.isSelected).map(\.url) + needsReview.filter(\.isSelected).map(\.url) }
    var relatedFilesSize: UInt64 { autoSelected.reduce(0) { $0 + $1.size } }
    var reviewFilesSize: UInt64 { needsReview.reduce(0) { $0 + $1.size } }
    var selectedSize: UInt64 {
        appSize + autoSelected.filter(\.isSelected).reduce(0) { $0 + $1.size } + needsReview.filter(\.isSelected).reduce(0) { $0 + $1.size }
    }
    var totalSize: UInt64 { appSize + relatedFilesSize + reviewFilesSize }
    var isSelected: Bool = false
}

// MARK: - UninstallerService

class UninstallerService: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var isScanning = false

    func scan() {
        guard !isScanning else { return }
        DispatchQueue.main.async { self.isScanning = true }
        DispatchQueue.global(qos: .utility).async {
            let appURLs = self.findApplications()
            var results: [InstalledApp] = []
            for url in appURLs {
                if let app = self.analyzeApp(at: url) {
                    results.append(app)
                }
            }
            results.sort { $0.totalSize > $1.totalSize }
            DispatchQueue.main.async {
                self.apps = results
                self.isScanning = false
            }
        }
    }

    private func findApplications() -> [URL] {
        let fm = FileManager.default
        var urls: [URL] = []
        let searchPaths = [
            URL(fileURLWithPath: "/Applications"),
            fm.urls(for: .applicationDirectory, in: .userDomainMask).first
        ].compactMap { $0 }
        for path in searchPaths {
            guard let enumerator = fm.enumerator(at: path, includingPropertiesForKeys: [.isApplicationKey], options: [.skipsPackageDescendants, .skipsHiddenFiles]) else { continue }
            for case let fileURL as URL in enumerator {
                if let isApp = try? fileURL.resourceValues(forKeys: [.isApplicationKey]).isApplication, isApp {
                    if !fileURL.path.hasPrefix("/System") && !fileURL.path.hasPrefix("/Applications/Utilities") {
                        urls.append(fileURL)
                    }
                }
            }
        }
        return urls
    }

    private func analyzeApp(at url: URL) -> InstalledApp? {
        let name = url.deletingPathExtension().lastPathComponent
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier,
              !bundleId.hasPrefix("com.apple."),
              !Self.isProtectedApp(bundleId: bundleId, name: name) else { return nil }

        let appSize = folderSize(at: url)
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        let fm = FileManager.default
        let libraryURL = fm.urls(for: .libraryDirectory, in: .userDomainMask).first!

        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let lastUsed: Date? = {
            let res = try? url.resourceValues(forKeys: [.contentAccessDateKey])
            return Self.normalizedFileDate(res?.contentAccessDate)
        }()
        let installationDate: Date? = {
            let res = try? url.resourceValues(forKeys: [.creationDateKey])
            return Self.normalizedFileDate(res?.creationDate)
        }()

        let lowBundleId = bundleId.lowercased()
        let lowName = name.lowercased()
        var autoFiles: [AppRelatedFile] = []

        let containerPath = libraryURL.appendingPathComponent("Containers/\(bundleId)")
        if fm.fileExists(atPath: containerPath.path) {
            autoFiles.append(AppRelatedFile(url: containerPath, label: "Container", size: relatedFileSize(at: containerPath)))
        }

        let containersDir = libraryURL.appendingPathComponent("Containers")
        if fm.fileExists(atPath: containersDir.path),
           let containers = try? fm.contentsOfDirectory(atPath: containersDir.path) {
            for container in containers {
                guard container != bundleId else { continue }
                if container.lowercased().hasPrefix(lowBundleId + ".") || container.lowercased().hasPrefix(lowBundleId) {
                    let cPath = containersDir.appendingPathComponent(container)
                    autoFiles.append(AppRelatedFile(url: cPath, label: "Container", size: relatedFileSize(at: cPath)))
                }
            }
        }

        let appSupportById = libraryURL.appendingPathComponent("Application Support/\(bundleId)")
        if fm.fileExists(atPath: appSupportById.path) {
            autoFiles.append(AppRelatedFile(url: appSupportById, label: "App Support", size: relatedFileSize(at: appSupportById)))
        }

        let cachePath = libraryURL.appendingPathComponent("Caches/\(bundleId)")
        if fm.fileExists(atPath: cachePath.path) {
            autoFiles.append(AppRelatedFile(url: cachePath, label: "Cache", size: relatedFileSize(at: cachePath)))
        }

        let httpStoragePath = libraryURL.appendingPathComponent("HTTPStorages/\(bundleId)")
        if fm.fileExists(atPath: httpStoragePath.path) {
            autoFiles.append(AppRelatedFile(url: httpStoragePath, label: "HTTP Storage", size: relatedFileSize(at: httpStoragePath)))
        }

        let prefsDir = libraryURL.appendingPathComponent("Preferences")
        if fm.fileExists(atPath: prefsDir.path),
           let prefs = try? fm.contentsOfDirectory(atPath: prefsDir.path) {
            for pref in prefs {
                let lower = pref.lowercased()
                if lower.contains(lowBundleId) || lower.contains(lowName.replacingOccurrences(of: " ", with: "")) {
                    let prefPath = prefsDir.appendingPathComponent(pref)
                    autoFiles.append(AppRelatedFile(url: prefPath, label: "Preferences", size: relatedFileSize(at: prefPath)))
                }
            }
            let byHostDir = prefsDir.appendingPathComponent("ByHost")
            if fm.fileExists(atPath: byHostDir.path),
               let byHostFiles = try? fm.contentsOfDirectory(atPath: byHostDir.path) {
                for file in byHostFiles {
                    let lower = file.lowercased()
                    if lower.contains(lowBundleId) || lower.contains(lowName.replacingOccurrences(of: " ", with: "")) {
                        let filePath = byHostDir.appendingPathComponent(file)
                        autoFiles.append(AppRelatedFile(url: filePath, label: "Preferences", size: relatedFileSize(at: filePath)))
                    }
                }
            }
        }

        let savedStatePath = libraryURL.appendingPathComponent("Saved Application State/\(bundleId).savedState")
        if fm.fileExists(atPath: savedStatePath.path) {
            autoFiles.append(AppRelatedFile(url: savedStatePath, label: "Saved State", size: relatedFileSize(at: savedStatePath)))
        }

        let scriptsDir = libraryURL.appendingPathComponent("Application Scripts")
        if fm.fileExists(atPath: scriptsDir.path),
           let scripts = try? fm.contentsOfDirectory(atPath: scriptsDir.path) {
            for script in scripts {
                let lower = script.lowercased()
                if lower == lowBundleId || lower.hasPrefix(lowBundleId + ".") || lower.contains(lowBundleId) {
                    let scriptPath = scriptsDir.appendingPathComponent(script)
                    autoFiles.append(AppRelatedFile(url: scriptPath, label: "App Scripts", size: relatedFileSize(at: scriptPath)))
                }
            }
        }

        let sharedFileListDir = libraryURL.appendingPathComponent("Application Support/com.apple.sharedfilelist")
        if fm.fileExists(atPath: sharedFileListDir.path),
           let files = try? fm.contentsOfDirectory(atPath: sharedFileListDir.path) {
            for file in files {
                let lower = file.lowercased()
                if lower.contains(lowBundleId) || lower.contains(lowName.replacingOccurrences(of: " ", with: "").lowercased()) {
                    let filePath = sharedFileListDir.appendingPathComponent(file)
                    autoFiles.append(AppRelatedFile(url: filePath, label: "Shared File List", size: relatedFileSize(at: filePath)))
                }
            }
        }

        let crashReporterDir = libraryURL.appendingPathComponent("Application Support/CrashReporter")
        if fm.fileExists(atPath: crashReporterDir.path),
           let crashes = try? fm.contentsOfDirectory(atPath: crashReporterDir.path) {
            for crash in crashes {
                let lower = crash.lowercased()
                if lower.contains(lowBundleId) || lower.contains(lowName.lowercased()) {
                    let crashPath = crashReporterDir.appendingPathComponent(crash)
                    autoFiles.append(AppRelatedFile(url: crashPath, label: "Crash Report", size: relatedFileSize(at: crashPath)))
                }
            }
        }

        for (path, label) in [
            (libraryURL.appendingPathComponent("Logs/\(name)"), "Logs"),
            (libraryURL.appendingPathComponent("Logs/\(bundleId)"), "Logs"),
        ] {
            if fm.fileExists(atPath: path.path) {
                autoFiles.append(AppRelatedFile(url: path, label: label, size: relatedFileSize(at: path)))
            }
        }

        let launchAgentsDir = libraryURL.appendingPathComponent("LaunchAgents")
        if fm.fileExists(atPath: launchAgentsDir.path),
           let agents = try? fm.contentsOfDirectory(atPath: launchAgentsDir.path) {
            for agent in agents where agent.lowercased().contains(lowBundleId) {
                let agentPath = launchAgentsDir.appendingPathComponent(agent)
                autoFiles.append(AppRelatedFile(url: agentPath, label: "Launch Agent", size: relatedFileSize(at: agentPath)))
            }
        }

        let groupContainersDir = libraryURL.appendingPathComponent("Group Containers")
        if fm.fileExists(atPath: groupContainersDir.path),
           let groups = try? fm.contentsOfDirectory(atPath: groupContainersDir.path) {
            for group in groups where group.lowercased().contains(lowBundleId) {
                let groupPath = groupContainersDir.appendingPathComponent(group)
                autoFiles.append(AppRelatedFile(url: groupPath, label: "Group Container", size: relatedFileSize(at: groupPath)))
            }
        }

        let webKitPath = libraryURL.appendingPathComponent("WebKit/\(bundleId)")
        if fm.fileExists(atPath: webKitPath.path) {
            autoFiles.append(AppRelatedFile(url: webKitPath, label: "WebKit Data", size: relatedFileSize(at: webKitPath)))
        }

        var reviewFiles: [AppRelatedFile] = []

        let appSupportByName = libraryURL.appendingPathComponent("Application Support/\(name)")
        if fm.fileExists(atPath: appSupportByName.path) && appSupportByName.path != appSupportById.path {
            reviewFiles.append(AppRelatedFile(url: appSupportByName, label: "App Support", size: relatedFileSize(at: appSupportByName), isSelected: false))
        }

        let varFolders = "/private/var/folders"
        if let topDirs = try? fm.contentsOfDirectory(atPath: varFolders) {
            for top in topDirs {
                let topPath = (varFolders as NSString).appendingPathComponent(top)
                guard let subDirs = try? fm.contentsOfDirectory(atPath: topPath) else { continue }
                for sub in subDirs {
                    let cDir = (topPath as NSString).appendingPathComponent(sub + "/C")
                    guard fm.fileExists(atPath: cDir) else { continue }
                    guard let cContents = try? fm.contentsOfDirectory(atPath: cDir) else { continue }
                    for item in cContents where item.lowercased().contains(lowBundleId) {
                        let itemPath = URL(fileURLWithPath: (cDir as NSString).appendingPathComponent(item))
                        reviewFiles.append(AppRelatedFile(url: itemPath, label: "Temporary Cache", size: relatedFileSize(at: itemPath), isSelected: false))
                    }
                    let tDir = (topPath as NSString).appendingPathComponent(sub + "/T")
                    if fm.fileExists(atPath: tDir),
                       let tContents = try? fm.contentsOfDirectory(atPath: tDir) {
                        for item in tContents where item.lowercased().contains(lowBundleId) {
                            let itemPath = URL(fileURLWithPath: (tDir as NSString).appendingPathComponent(item))
                            reviewFiles.append(AppRelatedFile(url: itemPath, label: "Temporary Cache", size: relatedFileSize(at: itemPath), isSelected: false))
                        }
                    }
                }
            }
        }

        let receiptsDir = "/private/var/db/receipts"
        if fm.fileExists(atPath: receiptsDir),
           let receipts = try? fm.contentsOfDirectory(atPath: receiptsDir) {
            for receipt in receipts where receipt.lowercased().contains(lowBundleId) {
                let receiptPath = URL(fileURLWithPath: receiptsDir).appendingPathComponent(receipt)
                reviewFiles.append(AppRelatedFile(url: receiptPath, label: "Receipt", size: relatedFileSize(at: receiptPath), isSelected: false))
            }
        }

        var seenURLs = Set<String>()
        autoFiles = autoFiles.filter { seenURLs.insert($0.url.path).inserted }
        reviewFiles = reviewFiles.filter { seenURLs.insert($0.url.path).inserted }

        return InstalledApp(
            name: name, bundleIdentifier: bundleId, appPath: url, appSize: appSize, icon: icon,
            autoSelected: autoFiles, needsReview: reviewFiles,
            version: version, lastUsed: lastUsed, installationDate: installationDate
        )
    }

    private static func isProtectedApp(bundleId: String, name: String) -> Bool {
        let loweredBundleId = bundleId.lowercased()
        let loweredName = name.lowercased()

        if let mainBundleId = Bundle.main.bundleIdentifier?.lowercased(),
           loweredBundleId == mainBundleId {
            return true
        }

        return loweredBundleId.hasPrefix("com.maccleaner.") || loweredName == "maccleaner"
    }

    private static func normalizedFileDate(_ date: Date?) -> Date? {
        guard let date else { return nil }

        let earliestReliableDate = Date(timeIntervalSince1970: 946_684_800) // 2000-01-01
        let latestReliableDate = Date().addingTimeInterval(24 * 60 * 60)
        guard date >= earliestReliableDate, date <= latestReliableDate else {
            return nil
        }

        return date
    }

    private func relatedFileSize(at url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            return UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
        }

        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
    }

    // MARK: - Async parallel folder size

    func folderSize(
        at url: URL,
        maxEntries: Int = 25_000,
        maxDuration: TimeInterval = 1.5
    ) -> UInt64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            return (try? fm.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        }

        let keys: [URLResourceKey] = [.fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        let started = Date()
        var size: UInt64 = 0
        var entries = 0
        for case let fileURL as URL in enumerator {
            entries += 1
            if entries > maxEntries || (entries % 32 == 0 && Date().timeIntervalSince(started) > maxDuration) {
                break
            }
            if let values = try? fileURL.resourceValues(forKeys: Set(keys)) {
                size += UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
            }
        }
        return size
    }

    func uninstall(apps items: [InstalledApp], completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let fm = FileManager.default
            var success = true
            var pathsToTrash: [URL] = []
            var blockedRootPaths: [String] = []
            var statsInputs: [CleanupStatsRecordInput] = []

            for app in items {
                guard !Self.isProtectedApp(bundleId: app.bundleIdentifier, name: app.name) else {
                    success = false
                    continue
                }

                if !fm.isDeletableFile(atPath: app.appPath.path) {
                    blockedRootPaths.append(app.appPath.path)
                } else {
                    pathsToTrash.append(app.appPath)
                    statsInputs.append(CleanupStatsRecordInput(
                        path: app.appPath.path,
                        displayName: app.name,
                        category: .uninstall,
                        bytes: app.appSize,
                        source: "Uninstaller"
                    ))
                }
                for related in app.autoSelected.filter(\.isSelected) + app.needsReview.filter(\.isSelected) {
                    pathsToTrash.append(related.url)
                    statsInputs.append(CleanupStatsRecordInput(
                        path: related.url.path,
                        displayName: related.url.lastPathComponent,
                        category: CleanupStatsStore.inferCategory(path: related.url.path, fallback: .appSupport),
                        bytes: related.size,
                        source: "Uninstaller"
                    ))
                }
            }

            var trashedPaths: Set<String> = []
            for url in pathsToTrash {
                do {
                    try fm.trashItem(at: url, resultingItemURL: nil)
                    trashedPaths.insert(url.path)
                } catch {
                    print("Failed to trash \(url.path): \(error)")
                }
            }

            let recordedInputs = statsInputs.filter { trashedPaths.contains($0.path) }
            if !recordedInputs.isEmpty {
                DispatchQueue.main.async {
                    CleanupStatsStore.shared.record(recordedInputs)
                }
            }

            if !blockedRootPaths.isEmpty {
                print("Skipped root-owned apps that require privileged helper uninstall: \(blockedRootPaths.joined(separator: ", "))")
                success = false
            }

            DispatchQueue.main.async {
                self.scan()
                completion(success)
            }
        }
    }
}
