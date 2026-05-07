import Foundation

// JSON result store / loader
struct ResultStore {
    private static let directoryName = "HAND-Score"

    private static var directory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(directoryName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Save

    static func save(_ result: BenchmarkResult) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(result)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: result.timestamp)
        let modelName = result.model.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")

        let filename = "bench_\(modelName)_\(timestamp).json"
        let fileURL = directory.appendingPathComponent(filename)

        try data.write(to: fileURL)
        return fileURL
    }

    // MARK: - Load list

    static func loadAll() -> [BenchmarkResult] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(BenchmarkResult.self, from: data)
            }
    }

    // MARK: - Delete individual entry

    static func delete(_ result: BenchmarkResult) {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }

        // Locate the file by ID and delete it
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for url in files where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let stored = try? decoder.decode(BenchmarkResult.self, from: data),
               stored.id == result.id {
                try? FileManager.default.removeItem(at: url)
                return
            }
        }
    }
}
