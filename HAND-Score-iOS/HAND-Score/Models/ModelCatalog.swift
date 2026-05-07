import Foundation

// Catalog of models downloadable from HuggingFace
struct ModelCatalogEntry: Identifiable, Codable, Sendable {
    let id: String           // HuggingFace repo ID (e.g., "optai-inc/Gemma3-1b-it-ANE")
    let url: String          // HuggingFace URL
    let displayName: String  // user-facing display name
    let family: String       // model family (Gemma, Qwen, Llama, ...)
    let parameterSize: String // parameter size (e.g., 270M, 1B)
    let contextLength: Int
    let estimatedSizeMB: Int // approximate download size
    let description: String
    let iconName: String     // SF Symbol name

    // Auto-derive the repo ID from the URL
    init(url: String, displayName: String, family: String, parameterSize: String,
         contextLength: Int, estimatedSizeMB: Int, description: String, iconName: String) {
        self.id = Self.extractRepoId(from: url)
        self.url = url
        self.displayName = displayName
        self.family = family
        self.parameterSize = parameterSize
        self.contextLength = contextLength
        self.estimatedSizeMB = estimatedSizeMB
        self.description = description
        self.iconName = iconName
    }

    // "https://huggingface.co/optai-inc/Gemma3-1b-it-ANE" → "optai-inc/Gemma3-1b-it-ANE"
    static func extractRepoId(from url: String) -> String {
        let cleaned = url
            .replacingOccurrences(of: "https://huggingface.co/", with: "")
            .replacingOccurrences(of: "http://huggingface.co/", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return cleaned
    }
}

struct ModelCatalog {
    static let availableModels: [ModelCatalogEntry] = [
        ModelCatalogEntry(
            url: "https://huggingface.co/optai-inc/Gemma3-270m-4096-ANE",
            displayName: "Gemma 3 270M",
            family: "Gemma",
            parameterSize: "270M",
            contextLength: 4096,
            estimatedSizeMB: 510,
            description: "Google Gemma 3 270M, ANE-optimized (lut4/lut6), ctx 4096",
            iconName: "sparkle"
        ),
        ModelCatalogEntry(
            url: "https://huggingface.co/optai-inc/Gemma3-1b-4096-ANE",
            displayName: "Gemma 3 1B",
            family: "Gemma",
            parameterSize: "1B",
            contextLength: 4096,
            estimatedSizeMB: 1150,
            description: "Google Gemma 3 1B Instruct, ANE-optimized (lut4/lut6), ctx 4096",
            iconName: "sparkle"
        ),
        ModelCatalogEntry(
            url: "https://huggingface.co/optai-inc/Llama-3.2-1B-4096-ANE",
            displayName: "Llama 3.2 1B",
            family: "Llama",
            parameterSize: "1B",
            contextLength: 4096,
            estimatedSizeMB: 1160,
            description: "Meta Llama 3.2 1B Instruct, ANE-optimized (lut4/lut6), ctx 4096",
            iconName: "flame.fill"
        ),
        ModelCatalogEntry(
            url: "https://huggingface.co/optai-inc/Llama-3.2-3B-4096-ANE",
            displayName: "Llama 3.2 3B",
            family: "Llama",
            parameterSize: "3B",
            contextLength: 4096,
            estimatedSizeMB: 2400,
            description: "Meta Llama 3.2 3B Instruct, ANE-optimized (lut4/lut6, 2 chunks), ctx 4096",
            iconName: "flame.fill"
        ),
        ModelCatalogEntry(
            url: "https://huggingface.co/optai-inc/Qwen3-4B-4096-ANE",
            displayName: "Qwen 3 4B",
            family: "Qwen",
            parameterSize: "4B",
            contextLength: 4096,
            estimatedSizeMB: 2800,
            description: "Alibaba Qwen 3 4B, ANE-optimized (lut4/lut6, 2 chunks), ctx 4096",
            iconName: "bolt.fill"
        ),
    ]

    static func entry(for repoId: String) -> ModelCatalogEntry? {
        availableModels.first { $0.id == repoId }
    }
}
