import Foundation

final class AIIndexStoreService {
    private static let cacheTTL: TimeInterval = 10
    private static let packageCacheTTL: TimeInterval = 120
    private static var cache: (date: Date, value: [AIIndexStore])?
    private static var packageCache: (date: Date, value: [AIAgentComponent])?

    static func stores(from processes: [ProcessNode], force: Bool = false) -> [AIIndexStore] {
        let now = Date()
        if !force, let cache, now.timeIntervalSince(cache.date) < cacheTTL {
            return cache.value
        }

        let value = [lanceDBStore(from: processes)]
        cache = (now, value)
        return value
    }

    private static func lanceDBStore(from processes: [ProcessNode]) -> AIIndexStore {
        let rows = processes
            .map(AIWorkloadService.classify)
            .filter { process in
                let text = "\(process.name) \(process.commandLine)".lowercased()
                return text.contains("lancedb") ||
                    text.contains(" lance ") ||
                    text.contains("/lance") ||
                    text.contains(".lance")
            }
            .sorted {
                if $0.memoryBytes == $1.memoryBytes { return $0.cpuUsage > $1.cpuUsage }
                return $0.memoryBytes > $1.memoryBytes
            }

        let components = lanceDBComponents()
        let dependencies = lanceDBDependencies()
        let packageInstalls = lanceDBPackageInstalls()
        let allComponents = components + packageInstalls
        let existingComponents = allComponents.filter(\.exists)
        let rootPath = existingComponents.first?.path ?? defaultLanceDBPath()
        let diskBytes = existingComponents.reduce(UInt64(0)) { total, component in
            total + directorySize(at: component.path, maxItems: 2_000)
        }

        let status: AIIndexStoreStatus
        if rows.contains(where: { $0.cpuUsage >= 1.0 }) {
            status = .active
        } else if !rows.isEmpty {
            status = .idle
        } else if !existingComponents.isEmpty || !dependencies.isEmpty {
            status = .installed
        } else {
            status = .missing
        }

        return AIIndexStore(
            id: "lancedb",
            name: "LanceDB",
            kind: "Vector / Index",
            status: status,
            rootPath: rootPath,
            diskBytes: diskBytes,
            processes: rows,
            components: allComponents,
            dependencies: dependencies
        )
    }

    private static func lanceDBComponents() -> [AIAgentComponent] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let workspace = workspacePath()
        var candidates: [(String, String, String)] = [
            ("MacCleaner LanceDB index", defaultLanceDBPath(), "app index"),
            ("Home LanceDB", "\(home)/.lancedb", "user index"),
            ("Home Lance data", "\(home)/.lance", "user data"),
            ("Application Support LanceDB", "\(home)/Library/Application Support/LanceDB", "app support")
        ]
        if let workspace {
            candidates.insert(contentsOf: [
                ("Workspace LanceDB", "\(workspace)/.lancedb", "workspace index"),
                ("Workspace Lance data", "\(workspace)/.lance", "workspace data"),
                ("Workspace data/lancedb", "\(workspace)/data/lancedb", "workspace index")
            ], at: 1)
        }

        return candidates.map {
            let path = normalizedPath($0.1)
            return AIAgentComponent(
                title: $0.0,
                path: path,
                kind: $0.2,
                exists: FileManager.default.fileExists(atPath: path)
            )
        }
    }

    private static func lanceDBDependencies() -> [AIAgentComponent] {
        let candidates = workspaceCandidates().flatMap { cwd in
            [
                "\(cwd)/package.json",
                "\(cwd)/pnpm-lock.yaml",
                "\(cwd)/package-lock.json",
                "\(cwd)/requirements.txt",
                "\(cwd)/pyproject.toml",
                "\(cwd)/uv.lock",
                "\(cwd)/Cargo.toml"
            ]
        }

        return candidates.compactMap { path in
            guard let text = try? String(contentsOfFile: path),
                  text.range(of: "lancedb", options: .caseInsensitive) != nil ||
                    text.range(of: "lance", options: .caseInsensitive) != nil else {
                return nil
            }

            return AIAgentComponent(
                title: URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                kind: "dependency",
                exists: true
            )
        }
    }

    private static func lanceDBPackageInstalls() -> [AIAgentComponent] {
        let now = Date()
        if let packageCache, now.timeIntervalSince(packageCache.date) < packageCacheTTL {
            return packageCache.value
        }

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = [
            "\(home)/.local",
            "\(home)/.pyenv",
            "\(home)/Library/Python",
            "\(home)/.npm",
            "\(home)/.nvm",
            "\(home)/node_modules",
            "/opt/homebrew/lib",
            "/usr/local/lib"
        ]

        var found: [AIAgentComponent] = []
        var seen = Set<String>()
        for root in roots where FileManager.default.fileExists(atPath: root) {
            for path in findNamedEntries(under: root, names: ["lancedb", "@lancedb"], maxDepth: 6, maxMatches: 12) {
                let normalized = normalizedPath(path)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                found.append(AIAgentComponent(
                    title: packageTitle(for: normalized),
                    path: normalized,
                    kind: "installed package",
                    exists: true
                ))
            }
        }
        let value = found.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
        packageCache = (now, value)
        return value
    }

    private static func defaultLanceDBPath() -> String {
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/MacCleaner/AI/Indexes/lancedb"
    }

    private static func workspacePath() -> String? {
        let cwd = normalizedPath(FileManager.default.currentDirectoryPath)
        guard cwd != "/" else { return nil }
        return cwd
    }

    private static func workspaceCandidates() -> [String] {
        var paths: [String] = []
        if let workspace = workspacePath() {
            paths.append(workspace)
        }

        let repoPath = "/Users/dmitriy/Docs/project/new"
        if FileManager.default.fileExists(atPath: repoPath), !paths.contains(repoPath) {
            paths.append(repoPath)
        }
        return paths
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func findNamedEntries(under root: String, names: Set<String>, maxDepth: Int, maxMatches: Int) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        let rootDepth = URL(fileURLWithPath: root).pathComponents.count
        var matches: [String] = []

        for case let url as URL in enumerator {
            let depth = url.pathComponents.count - rootDepth
            if depth > maxDepth {
                enumerator.skipDescendants()
                continue
            }

            if names.contains(url.lastPathComponent.lowercased()) {
                matches.append(url.path)
                if matches.count >= maxMatches { break }
                enumerator.skipDescendants()
            }
        }

        return matches
    }

    private static func packageTitle(for path: String) -> String {
        if path.contains("/site-packages/") { return "Python package" }
        if path.contains("/node_modules/") { return "Node package" }
        return "Installed package"
    }

    private static func directorySize(at path: String, maxItems: Int) -> UInt64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return fileSize(at: path)
        }

        guard let enumerator = FileManager.default.enumerator(atPath: path) else { return 0 }
        var total: UInt64 = 0
        var count = 0
        while let relative = enumerator.nextObject() as? String {
            count += 1
            if count > maxItems { break }
            total += fileSize(at: "\(path)/\(relative)")
        }
        return total
    }

    private static func fileSize(at path: String) -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else {
            return 0
        }
        return size.uint64Value
    }
}
