import Foundation

enum LLMFitSort: String, CaseIterable, Identifiable {
    case score
    case tps
    case params
    case mem
    case ctx
    case date
    case use
    case provider

    var id: String { rawValue }

    var title: String {
        switch self {
        case .score: return "Best match"
        case .tps: return "Fastest"
        case .params: return "Model size"
        case .mem: return "Lowest RAM"
        case .ctx: return "Longest context"
        case .date: return "Newest"
        case .use: return "Use case"
        case .provider: return "Publisher"
        }
    }

    var hint: String {
        switch self {
        case .score: return "llmfit overall score: quality, speed, memory fit, and context"
        case .tps: return "Estimated tokens per second on this Mac/runtime"
        case .params: return "Number of model parameters, usually larger means heavier"
        case .mem: return "Estimated memory required to run the model"
        case .ctx: return "Maximum context window"
        case .date: return "Release date when llmfit knows it"
        case .use: return "llmfit use-case grouping"
        case .provider: return "Organization or repository owner publishing the model"
        }
    }
}

enum LLMFitMode: String, CaseIterable, Identifiable {
    case compatible = "Compatible"
    case all = "All Models"

    var id: String { rawValue }
}

enum LLMFitParamFilter: String, CaseIterable, Identifiable {
    case any = "Any Params"
    case tiny = "< 3B"
    case small = "3B-8B"
    case medium = "8B-30B"
    case large = "30B-70B"
    case xlarge = "70B+"

    var id: String { rawValue }

    func contains(_ params: Double?) -> Bool {
        guard let params else { return self == .any }
        switch self {
        case .any: return true
        case .tiny: return params < 3
        case .small: return params >= 3 && params < 8
        case .medium: return params >= 8 && params < 30
        case .large: return params >= 30 && params < 70
        case .xlarge: return params >= 70
        }
    }
}

struct LLMFitSystem: Codable {
    let availableRAMGB: Double?
    let backend: String?
    let cpuCores: Int?
    let cpuName: String?
    let gpuName: String?
    let gpuVRAMGB: Double?
    let totalRAMGB: Double?
    let unifiedMemory: Bool?

    enum CodingKeys: String, CodingKey {
        case availableRAMGB = "available_ram_gb"
        case backend
        case cpuCores = "cpu_cores"
        case cpuName = "cpu_name"
        case gpuName = "gpu_name"
        case gpuVRAMGB = "gpu_vram_gb"
        case totalRAMGB = "total_ram_gb"
        case unifiedMemory = "unified_memory"
    }
}

struct LLMFitModel: Codable, Identifiable {
    let name: String
    let provider: String?
    let parameterCount: String?
    let parametersRaw: UInt64?
    let minRAMGB: Double?
    let recommendedRAMGB: Double?
    let minVRAMGB: Double?
    let quantization: String?
    let contextLength: Int?
    let effectiveContextLength: Int?
    let useCase: String?
    let capabilities: [String]?
    let format: String?
    let runtime: String?
    let runtimeLabel: String?
    let runMode: String?
    let fitLevel: String?
    let score: Double?
    let estimatedTPS: Double?
    let memoryRequiredGB: Double?
    let memoryAvailableGB: Double?
    let totalMemoryGB: Double?
    let utilizationPct: Double?
    let bestQuant: String?
    let diskSizeGB: Double?
    let releaseDate: String?
    let installed: Bool?
    let isMoE: Bool?
    let category: String?
    let license: String?
    let notes: [String]?
    let paramsB: Double?
    let scoreComponents: LLMFitScoreComponents?
    let moeOffloadedGB: Double?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case provider
        case parameterCount = "parameter_count"
        case parametersRaw = "parameters_raw"
        case minRAMGB = "min_ram_gb"
        case recommendedRAMGB = "recommended_ram_gb"
        case minVRAMGB = "min_vram_gb"
        case quantization
        case contextLength = "context_length"
        case effectiveContextLength = "effective_context_length"
        case useCase = "use_case"
        case capabilities
        case format
        case runtime
        case runtimeLabel = "runtime_label"
        case runMode = "run_mode"
        case fitLevel = "fit_level"
        case score
        case estimatedTPS = "estimated_tps"
        case memoryRequiredGB = "memory_required_gb"
        case memoryAvailableGB = "memory_available_gb"
        case totalMemoryGB = "total_memory_gb"
        case utilizationPct = "utilization_pct"
        case bestQuant = "best_quant"
        case diskSizeGB = "disk_size_gb"
        case releaseDate = "release_date"
        case installed
        case isMoE = "is_moe"
        case category
        case license
        case notes
        case paramsB = "params_b"
        case scoreComponents = "score_components"
        case moeOffloadedGB = "moe_offloaded_gb"
    }
}

struct LLMFitScoreComponents: Codable {
    let context: Double?
    let fit: Double?
    let quality: Double?
    let speed: Double?
}

struct LLMFitSnapshot {
    let date: Date
    let mode: LLMFitMode
    let sort: LLMFitSort
    let system: LLMFitSystem?
    let models: [LLMFitModel]
    let totalKnownModels: Int?
    let command: String
}

struct LLMFitFitResponse: Codable {
    let models: [LLMFitModel]
    let system: LLMFitSystem?
}
