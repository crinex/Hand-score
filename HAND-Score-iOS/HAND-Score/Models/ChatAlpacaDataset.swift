import Foundation

// HAND-Score evaluation samples extracted from ChatAlpaca-20K.
// See scripts/extract_samples.py for the source JSON schema.

// Single-turn sample (Exp A — Baseline)
struct SingleTurnSample: Codable, Identifiable, Sendable, Hashable {
    let id: String              // e.g., "st-001"
    let bin: String             // "short" | "med_short" | "medium"
    let inputTokens: Int        // input token count of the first user message (cl100k_base)
    let prompt: String          // body of the first user message
    let reference: String?      // original ChatAlpaca assistant reply (kept for reference, not used for scoring)

    enum CodingKeys: String, CodingKey {
        case id, bin, prompt, reference
        case inputTokens = "input_tokens"
    }
}

// Multi-turn sample (Exp E — Multi-turn chatbot)
// `messages` matches the format expected by BenchmarkRunner.runMultiTurn: [{"role", "content"}]
// Assistant `content` fields are "" (the model fills them in); the original replies are kept in `references`.
struct MultiTurnSample: Codable, Identifiable, Sendable, Hashable {
    let id: String              // e.g., "mt-001"
    let turnCount: Int          // number of user-assistant pairs (4, 5, or 6)
    let totalTokens: Int        // total token count of the original dialogue
    let messages: [[String: String]]
    let references: [String]    // original assistant replies for each turn

    enum CodingKeys: String, CodingKey {
        case id, messages, references
        case turnCount = "turn_count"
        case totalTokens = "total_tokens"
    }
}

// Full ChatAlpaca dataset bundled with the app
struct ChatAlpacaDataset: Codable, Sendable {
    let version: String
    let dataset: String         // "robinsmits/ChatAlpaca-20K"
    let extractedAt: String     // YYYY-MM-DD
    let seed: Int
    let singleTurn: [SingleTurnSample]
    let multiTurn: [MultiTurnSample]

    enum CodingKeys: String, CodingKey {
        case version, dataset, seed
        case extractedAt = "extracted_at"
        case singleTurn = "single_turn"
        case multiTurn = "multi_turn"
    }

    enum LoadError: Error, LocalizedError {
        case resourceNotFound
        case decodingFailed(String)

        var errorDescription: String? {
            switch self {
            case .resourceNotFound:
                return "chatalpaca_handscore.json was not found in the app bundle."
            case .decodingFailed(let msg):
                return "Failed to decode the ChatAlpaca dataset: \(msg)"
            }
        }
    }

    static func loadFromBundle() throws -> ChatAlpacaDataset {
        guard let url = Bundle.main.url(forResource: "chatalpaca_handscore", withExtension: "json") else {
            throw LoadError.resourceNotFound
        }
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(ChatAlpacaDataset.self, from: data)
        } catch {
            throw LoadError.decodingFailed(String(describing: error))
        }
    }
}
