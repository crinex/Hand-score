import Foundation

struct DeviceInfo: Codable, Sendable {
    let model: String           // e.g. "iPhone16,1" (utsname machine)
    let name: String            // e.g. "iPhone 15 Pro"
    let chip: String            // chip name mapped from utsname machine
    let osVersion: String       // e.g. "18.0"
}

struct ModelInfo: Codable, Sendable {
    let name: String            // model folder name
    let path: String            // model file path
    let contextLength: Int
    let batchSize: Int
    let isMonolithic: Bool
}

// Benchmark mode
enum BenchmarkMode: String, Codable, CaseIterable, Sendable {
    case singleTurn = "single_turn"
    case multiTurn = "multi_turn"

    var displayName: String {
        switch self {
        case .singleTurn: return "Single-Turn"
        case .multiTurn: return "Multi-Turn (KV Cache)"
        }
    }
}

struct BenchmarkConfig: Codable, Sendable {
    let prompt: String
    let maxTokens: Int
    let temperature: Float
    let mode: BenchmarkMode

    init(prompt: String, maxTokens: Int, temperature: Float, mode: BenchmarkMode = .singleTurn) {
        self.prompt = prompt
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.mode = mode
    }
}

struct PerformanceMetrics: Codable, Sendable {
    let modelLoadTimeMs: Double
    let prefillTimeMs: Double
    let prefillTokens: Int
    let prefillTokensPerSec: Double
    let decodeTokens: Int
    let decodeTimeMs: Double
    let decodeTokensPerSec: Double
    let ttftMs: Double              // Time To First Token (latency until the first generated token)
    let totalTokens: Int
    let totalTimeMs: Double
}

// Per-turn result for multi-turn dialogues
struct TurnResult: Codable, Sendable {
    let turnIndex: Int
    let role: String                // "user" or "assistant"
    let inputText: String           // input text
    let inputTokens: Int            // input token count for this turn
    let outputTokens: Int           // generated token count
    let prefillTimeMs: Double       // prefill time (new tokens only)
    let prefillTokensPerSec: Double
    let decodeTimeMs: Double
    let decodeTokensPerSec: Double
    let ttftMs: Double
    let kvCachePosition: Int        // KV cache position at the start of this turn
    let generatedText: String
}

struct BenchmarkResult: Codable, Identifiable, Sendable {
    let id: UUID
    let timestamp: Date
    let device: DeviceInfo
    let model: ModelInfo
    let config: BenchmarkConfig
    let performance: PerformanceMetrics
    let system: SystemMetricsReport
    let generatedText: String
    let aneProfile: ANEProfiler.ProfileReport?
    let turnResults: [TurnResult]?  // per-turn results in multi-turn mode

    init(
        device: DeviceInfo,
        model: ModelInfo,
        config: BenchmarkConfig,
        performance: PerformanceMetrics,
        system: SystemMetricsReport,
        generatedText: String,
        aneProfile: ANEProfiler.ProfileReport? = nil,
        turnResults: [TurnResult]? = nil
    ) {
        self.id = UUID()
        self.timestamp = Date()
        self.device = device
        self.model = model
        self.config = config
        self.performance = performance
        self.system = system
        self.generatedText = generatedText
        self.aneProfile = aneProfile
        self.turnResults = turnResults
    }
}
