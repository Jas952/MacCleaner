import Foundation

enum SafeDeletionError: LocalizedError {
    case protectedApplicationData(URL)

    var errorDescription: String? {
        switch self {
        case .protectedApplicationData:
            return "MacCleaner protects its running app and working data from cleanup."
        }
    }
}

enum SafeDeletionService {
    struct ProtectionPolicy: Sendable {
        fileprivate let protectedRoots: [String]
        fileprivate let protectedBundleComponents: Set<String>

        func contains(_ url: URL) -> Bool {
            let normalized = url.standardizedFileURL.path.lowercased()
            if protectedRoots.contains(where: { root in
                normalized == root || normalized.hasPrefix(root + "/")
            }) {
                return true
            }
            return url.standardizedFileURL.pathComponents.contains { component in
                protectedBundleComponents.contains(component.lowercased())
            }
        }

        func intersects(_ url: URL) -> Bool {
            if contains(url) { return true }
            let normalized = url.standardizedFileURL.path.lowercased()
            if normalized == "/" { return true }
            return protectedRoots.contains { $0.hasPrefix(normalized + "/") }
        }
    }

    struct MoveResult {
        let originalURL: URL
        let trashedURL: URL?
    }

    /// Moves an item to the user's Trash. There is deliberately no permanent
    /// deletion fallback: a failed move must remain visible to the caller.
    static func moveToTrash(
        _ url: URL,
        policy: ProtectionPolicy = currentProtectionPolicy()
    ) throws -> MoveResult {
        let normalized = url.standardizedFileURL
        guard FileManager.default.fileExists(atPath: normalized.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard !isProtectedApplicationPath(normalized, policy: policy) else {
            throw SafeDeletionError.protectedApplicationData(normalized)
        }

        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: normalized, resultingItemURL: &resultingURL)
        return MoveResult(originalURL: normalized, trashedURL: resultingURL as URL?)
    }

    static func isPath(_ path: String, inside root: String) -> Bool {
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
        return normalizedPath == normalizedRoot || normalizedPath.hasPrefix(normalizedRoot + "/")
    }

    static func currentProtectionPolicy(
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        bundleURL: URL? = Bundle.main.bundleURL,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> ProtectionPolicy {
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let identifier = bundleIdentifier.flatMap { $0.isEmpty ? nil : $0 } ?? "com.maccleaner.app"
        var roots: [URL] = [
            library.appendingPathComponent("Application Support/MacCleaner", isDirectory: true),
            library.appendingPathComponent("Caches/MacCleaner", isDirectory: true),
            library.appendingPathComponent("Caches/\(identifier)", isDirectory: true),
            library.appendingPathComponent("HTTPStorages/\(identifier)", isDirectory: true),
            library.appendingPathComponent("WebKit/\(identifier)", isDirectory: true),
            library.appendingPathComponent("Logs/MacCleaner", isDirectory: true),
            library.appendingPathComponent("Logs/\(identifier)", isDirectory: true),
            library.appendingPathComponent("Preferences/\(identifier).plist"),
            library.appendingPathComponent("Saved Application State/\(identifier).savedState", isDirectory: true),
            library.appendingPathComponent("LaunchAgents/\(identifier).plist"),
            library.appendingPathComponent("Application Scripts/\(identifier)", isDirectory: true),
            library.appendingPathComponent("Containers/\(identifier)", isDirectory: true)
        ]
        if let bundleURL { roots.append(bundleURL.standardizedFileURL) }
        return ProtectionPolicy(
            protectedRoots: Array(Set(roots.map { $0.standardizedFileURL.path.lowercased() })),
            protectedBundleComponents: ["maccleaner.app"]
        )
    }

    static func isProtectedApplicationPath(
        _ url: URL,
        policy: ProtectionPolicy = currentProtectionPolicy()
    ) -> Bool {
        policy.intersects(url)
    }

    /// Excludes only MacCleaner's own subtree during measurement. Parent
    /// cache folders may still be scanned while the protected subtree is skipped.
    static func isApplicationOwnedPath(
        _ url: URL,
        policy: ProtectionPolicy = currentProtectionPolicy()
    ) -> Bool {
        policy.contains(url)
    }
}
