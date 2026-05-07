import Foundation

// HuggingFace model download service
@MainActor
final class HuggingFaceService: ObservableObject {

    enum DownloadState: Sendable {
        case idle
        case fetching        // listing files
        case downloading(progress: Double, fileName: String)
        case completed(URL)
        case failed(String)
    }

    @Published private(set) var downloadStates: [String: DownloadState] = [:] // repoId -> state

    private var activeTasks: [String: Task<Void, Never>] = [:]

    // Local path where downloaded models are stored
    static var modelsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // Check whether the model has already been downloaded
    func isModelDownloaded(_ repoId: String) -> Bool {
        let modelDir = Self.modelsDirectory.appendingPathComponent(Self.sanitizedName(repoId))
        let metaPath = modelDir.appendingPathComponent("meta.yaml")
        return FileManager.default.fileExists(atPath: metaPath.path)
    }

    // Resolved path of a downloaded model
    func downloadedModelPath(_ repoId: String) -> URL? {
        let modelDir = Self.modelsDirectory.appendingPathComponent(Self.sanitizedName(repoId))
        let metaPath = modelDir.appendingPathComponent("meta.yaml")
        if FileManager.default.fileExists(atPath: metaPath.path) {
            return modelDir
        }
        return nil
    }

    // List the paths of all downloaded models
    func allDownloadedModels() -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: Self.modelsDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        return contents.filter { url in
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            guard isDir.boolValue else { return false }
            return fm.fileExists(atPath: url.appendingPathComponent("meta.yaml").path)
        }
    }

    // Start a model download
    func downloadModel(_ repoId: String) {
        guard activeTasks[repoId] == nil else { return }

        downloadStates[repoId] = .fetching

        let task = Task { @MainActor in
            do {
                // 1. List files in the repo
                let files = try await fetchFileList(repoId: repoId)

                // Keep only the files we need (skip .mlpackage, chat.py, README, ...)
                let neededFiles = files.filter { file in
                    let name = file.path
                    // Skip files we do not need
                    if name.hasSuffix(".md") || name.hasSuffix(".py") || name == ".gitattributes" || name == ".DS_Store" {
                        return false
                    }
                    if name.contains(".mlpackage/") || name.contains(".mlpackage") && !name.contains(".mlmodelc") {
                        return false
                    }
                    // Skip progress / metadata files
                    if name == "meta_progress.yaml" {
                        return false
                    }
                    return true
                }

                let totalSize = neededFiles.reduce(0) { $0 + $1.size }
                var downloadedSize: Int64 = 0

                // 2. Create the destination folder
                let modelDir = Self.modelsDirectory.appendingPathComponent(Self.sanitizedName(repoId))
                try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

                // 3. Download files
                for file in neededFiles {
                    let fileName = file.path
                    downloadStates[repoId] = .downloading(
                        progress: totalSize > 0 ? Double(downloadedSize) / Double(totalSize) : 0,
                        fileName: fileName.components(separatedBy: "/").last ?? fileName
                    )

                    let destPath = modelDir.appendingPathComponent(fileName)
                    // Create the subdirectory
                    let parentDir = destPath.deletingLastPathComponent()
                    try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

                    try await downloadFile(repoId: repoId, remotePath: fileName, localPath: destPath)
                    downloadedSize += file.size
                }

                downloadStates[repoId] = .completed(modelDir)
            } catch is CancellationError {
                downloadStates[repoId] = .idle
            } catch {
                downloadStates[repoId] = .failed(error.localizedDescription)
            }

            activeTasks[repoId] = nil
        }

        activeTasks[repoId] = task
    }

    // Cancel an in-flight download
    func cancelDownload(_ repoId: String) {
        activeTasks[repoId]?.cancel()
        activeTasks[repoId] = nil
        downloadStates[repoId] = .idle
    }

    // Delete a downloaded model
    func deleteModel(_ repoId: String) {
        let modelDir = Self.modelsDirectory.appendingPathComponent(Self.sanitizedName(repoId))
        try? FileManager.default.removeItem(at: modelDir)
        downloadStates[repoId] = .idle
    }

    // MARK: - Private

    private struct HFFile: Codable {
        let type: String     // "file" or "directory"
        let path: String
        let size: Int64

        enum CodingKeys: String, CodingKey {
            case type, path, size
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            path = try container.decode(String.self, forKey: .path)
            size = (try? container.decode(Int64.self, forKey: .size)) ?? 0
        }
    }

    private func fetchFileList(repoId: String, path: String = "") async throws -> [HFFile] {
        try Task.checkCancellation()

        let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let urlString = "https://huggingface.co/api/models/\(repoId)/tree/main\(encodedPath.isEmpty ? "" : "/\(encodedPath)")"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let items = try JSONDecoder().decode([HFFile].self, from: data)
        var allFiles: [HFFile] = []

        for item in items {
            if item.type == "file" {
                allFiles.append(item)
            } else if item.type == "directory" {
                // Walk the directory tree recursively
                let subFiles = try await fetchFileList(repoId: repoId, path: item.path)
                allFiles.append(contentsOf: subFiles)
            }
        }

        return allFiles
    }

    private func downloadFile(repoId: String, remotePath: String, localPath: URL) async throws {
        try Task.checkCancellation()

        let encodedPath = remotePath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? remotePath
        let urlString = "https://huggingface.co/\(repoId)/resolve/main/\(encodedPath)"
        guard let url = URL(string: urlString) else {
            throw URLError(.badURL)
        }

        let (tempURL, response) = try await URLSession.shared.download(from: url)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Remove the existing file if any
        if FileManager.default.fileExists(atPath: localPath.path) {
            try FileManager.default.removeItem(at: localPath)
        }
        try FileManager.default.moveItem(at: tempURL, to: localPath)
    }

    static func sanitizedName(_ repoId: String) -> String {
        // Take the last segment, e.g. "anemll/anemll-...-0.3.5" -> "anemll-...-0.3.5"
        repoId.components(separatedBy: "/").last ?? repoId
    }

    static func formattedSize(_ mb: Int) -> String {
        if mb >= 1000 {
            return String(format: "%.1f GB", Double(mb) / 1000.0)
        }
        return "\(mb) MB"
    }
}
