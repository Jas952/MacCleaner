import Foundation

enum LLMFitServiceError: LocalizedError {
    case commandFailed(String)
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .commandFailed(let message): return message
        case .invalidOutput: return "llmfit returned output MacCleaner could not decode."
        }
    }
}

final class LLMFitService {
    private static var listCache: (date: Date, sort: LLMFitSort, value: [LLMFitModel])?
    private static var fitCache: (date: Date, sort: LLMFitSort, perfect: Bool, toolUse: Bool, limit: Int, value: LLMFitFitResponse)?
    private static let cacheTTL: TimeInterval = 60
    private static let commandTimeout: TimeInterval = 30

    static func load(mode: LLMFitMode, sort: LLMFitSort, perfect: Bool, toolUse: Bool, limit: Int) throws -> LLMFitSnapshot {
        switch mode {
        case .compatible:
            let response = try fit(sort: sort, perfect: perfect, toolUse: toolUse, limit: limit)
            return LLMFitSnapshot(
                date: Date(),
                mode: mode,
                sort: sort,
                system: response.system,
                models: response.models,
                totalKnownModels: nil,
                command: fitCommand(sort: sort, perfect: perfect, toolUse: toolUse, limit: limit)
            )
        case .all:
            let allModels = try list(sort: sort)
            return LLMFitSnapshot(
                date: Date(),
                mode: mode,
                sort: sort,
                system: nil,
                models: allModels,
                totalKnownModels: allModels.count,
                command: "llmfit list --json --sort \(sort.rawValue)"
            )
        }
    }

    static func info(modelName: String) throws -> LLMFitFitResponse {
        let data = try run(["info", modelName, "--json"])
        return try JSONDecoder().decode(LLMFitFitResponse.self, from: data)
    }

    private static func list(sort: LLMFitSort) throws -> [LLMFitModel] {
        let now = Date()
        if let cache = listCache, cache.sort == sort, now.timeIntervalSince(cache.date) < cacheTTL {
            return cache.value
        }

        let data = try run(["list", "--json", "--sort", sort.rawValue])
        let models = try JSONDecoder().decode([LLMFitModel].self, from: data)
        listCache = (now, sort, models)
        return models
    }

    private static func fit(sort: LLMFitSort, perfect: Bool, toolUse: Bool, limit: Int) throws -> LLMFitFitResponse {
        let now = Date()
        if let cache = fitCache,
           cache.sort == sort,
           cache.perfect == perfect,
           cache.toolUse == toolUse,
           cache.limit == limit,
           now.timeIntervalSince(cache.date) < cacheTTL {
            return cache.value
        }

        var args = ["fit", "--json", "--sort", sort.rawValue, "-n", "\(limit)"]
        if perfect { args.append("--perfect") }
        if toolUse { args.append("--tool-use") }

        let data = try run(args)
        let response = try JSONDecoder().decode(LLMFitFitResponse.self, from: data)
        fitCache = (now, sort, perfect, toolUse, limit, response)
        return response
    }

    private static func fitCommand(sort: LLMFitSort, perfect: Bool, toolUse: Bool, limit: Int) -> String {
        var parts = ["llmfit", "fit", "--json", "--sort", sort.rawValue, "-n", "\(limit)"]
        if perfect { parts.append("--perfect") }
        if toolUse { parts.append("--tool-use") }
        return parts.joined(separator: " ")
    }

    private static func run(_ args: [String]) throws -> Data {
        guard let executable = llmfitExecutable() else {
            throw LLMFitServiceError.commandFailed("llmfit is not installed in /opt/homebrew/bin or /usr/local/bin.")
        }
        let task = Process()
        task.executableURL = executable
        task.arguments = args
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        environment["LC_ALL"] = "C"
        task.environment = environment

        let token = UUID().uuidString
        let tempDirectory = FileManager.default.temporaryDirectory
        let outputURL = tempDirectory.appendingPathComponent("MacCleaner-llmfit-\(token).json")
        let errorURL = tempDirectory.appendingPathComponent("MacCleaner-llmfit-\(token).err")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        FileManager.default.createFile(atPath: errorURL.path, contents: nil)

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        defer {
            try? outputHandle.close()
            try? errorHandle.close()
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        task.standardOutput = outputHandle
        task.standardError = errorHandle

        let semaphore = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in semaphore.signal() }
        do {
            try task.run()
        } catch {
            throw LLMFitServiceError.commandFailed("Unable to run llmfit: \(error.localizedDescription)")
        }

        if semaphore.wait(timeout: .now() + commandTimeout) == .timedOut {
            task.terminate()
            throw LLMFitServiceError.commandFailed("llmfit timed out after \(Int(commandTimeout))s")
        }

        try? outputHandle.synchronize()
        try? errorHandle.synchronize()
        let data = try Data(contentsOf: outputURL)
        let errorData = try Data(contentsOf: errorURL)

        guard task.terminationStatus == 0 else {
            let message = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw LLMFitServiceError.commandFailed(message?.isEmpty == false ? message! : "llmfit exited with status \(task.terminationStatus)")
        }

        guard !data.isEmpty else { throw LLMFitServiceError.invalidOutput }
        return data
    }

    private static func llmfitExecutable() -> URL? {
        let candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/llmfit"),
            URL(fileURLWithPath: "/usr/local/bin/llmfit")
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
