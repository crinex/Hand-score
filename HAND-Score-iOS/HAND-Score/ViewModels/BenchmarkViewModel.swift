import SwiftUI

@MainActor
final class BenchmarkViewModel: ObservableObject {
    @Published var modelPath: URL?
    @Published var prompt: String = ""
    @Published var maxTokens: Int = 256
    @Published var temperature: Float = 0.0
    @Published var benchmarkMode: BenchmarkMode = .singleTurn

    // Multi-turn sample messages (populated from the selected ChatAlpaca multi-turn dialogue)
    @Published var multiTurnMessages: [[String: String]] = []

    // ChatAlpaca-20K extracted dataset (loaded from app bundle)
    @Published private(set) var dataset: ChatAlpacaDataset?

    // User-selected sample IDs. didSet auto-updates prompt / multiTurnMessages.
    @Published var selectedSingleTurnId: String? {
        didSet { applySelectedSingleTurn() }
    }
    @Published var selectedMultiTurnId: String? {
        didSet { applySelectedMultiTurn() }
    }

    @Published private(set) var isRunning = false
    @Published private(set) var statusText = ""
    @Published private(set) var generatedText = ""
    @Published private(set) var lastResult: BenchmarkResult?
    @Published private(set) var loadingProgress: Double = 0
    @Published private(set) var tokensGenerated: Int = 0
    @Published private(set) var currentTPS: Double = 0
    @Published private(set) var savedResults: [BenchmarkResult] = []

    // Batch execution (Exp A: 30 single-turn samples)
    struct BatchProgress: Sendable {
        let current: Int
        let total: Int
        let currentId: String
        let currentBin: String
        let phase: String      // "running" | "cooling Ns" | "done"
        let succeeded: Int
        let failed: Int

        static let idle = BatchProgress(current: 0, total: 0, currentId: "", currentBin: "", phase: "", succeeded: 0, failed: 0)
    }
    @Published private(set) var isBatchRunning: Bool = false
    @Published private(set) var batchProgress: BatchProgress = .idle
    @Published var batchCoolDownSec: Int = 10

    // Thermal stress (Exp C) parameters
    @Published var thermalStressRepeats: Int = 30

    // Models bundled with the app
    @Published private(set) var bundledModels: [URL] = []

    let hfService = HuggingFaceService()
    private let runner = BenchmarkRunner()

    init() {
        bundledModels = BenchmarkRunner.bundledModelPaths()
        if let first = bundledModels.first {
            modelPath = first
        }
        loadDataset()
        loadResults()
    }

    // MARK: - Dataset loading and sample application

    private func loadDataset() {
        do {
            let ds = try ChatAlpacaDataset.loadFromBundle()
            self.dataset = ds
            // Auto-select the first sample → didSet populates prompt/multiTurnMessages
            if let first = ds.singleTurn.first {
                selectedSingleTurnId = first.id
            }
            if let first = ds.multiTurn.first {
                selectedMultiTurnId = first.id
            }
            print("[HAND-Score] ChatAlpaca dataset loaded: single=\(ds.singleTurn.count), multi=\(ds.multiTurn.count)")
        } catch {
            print("[HAND-Score] ChatAlpaca dataset load failed: \(error.localizedDescription) — using fallback")
            // Fallback: hard-coded prompts when the bundle entry is missing
            prompt = "Explain what an NPU is in simple terms."
            multiTurnMessages = [
                ["role": "user", "content": "What is an NPU and how does it differ from a GPU?"],
                ["role": "assistant", "content": ""],
                ["role": "user", "content": "Can you give me specific examples of tasks that benefit from NPU acceleration?"],
                ["role": "assistant", "content": ""]
            ]
        }
    }

    private func applySelectedSingleTurn() {
        guard let id = selectedSingleTurnId,
              let sample = dataset?.singleTurn.first(where: { $0.id == id }) else { return }
        prompt = sample.prompt
    }

    private func applySelectedMultiTurn() {
        guard let id = selectedMultiTurnId,
              let sample = dataset?.multiTurn.first(where: { $0.id == id }) else { return }
        multiTurnMessages = sample.messages
    }

    // MARK: - Benchmark execution

    func runBenchmark() async {
        guard let modelPath else {
            statusText = "Select a model folder"
            return
        }

        isRunning = true
        statusText = "Starting benchmark..."
        generatedText = ""
        lastResult = nil
        tokensGenerated = 0
        currentTPS = 0

        // Observe runner state
        let observation = Task { @MainActor in
            for await _ in runner.$state.values {
                switch runner.state {
                case .idle:
                    break
                case .loadingModel(let progress, let stage):
                    self.loadingProgress = progress
                    self.statusText = stage
                case .running(let tokens, let tps):
                    self.tokensGenerated = tokens
                    self.currentTPS = tps
                    self.generatedText = runner.generatedText
                    self.statusText = "Generating... \(tokens) tokens"
                case .completed(let result):
                    self.lastResult = result
                    self.generatedText = runner.generatedText
                    self.statusText = "Done"
                case .failed(let error):
                    self.statusText = "Error: \(error)"
                }
            }
        }

        // For multi-turn we only forward messages whose assistant content is empty (model fills them).
        let messages: [[String: String]]? = benchmarkMode == .multiTurn ? multiTurnMessages : nil

        await runner.run(
            modelPath: modelPath,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            mode: benchmarkMode,
            multiTurnMessages: messages
        )

        observation.cancel()

        // Sync final state
        switch runner.state {
        case .completed(let result):
            lastResult = result
            generatedText = runner.generatedText
            let modeLabel = benchmarkMode == .multiTurn ? "Multi-Turn" : "Single-Turn"
            statusText = String(format: "Done [\(modeLabel)] | %.1f tok/s | %d tokens", result.performance.decodeTokensPerSec, result.performance.totalTokens)
        case .failed(let error):
            statusText = "Error: \(error)"
        default:
            break
        }

        isRunning = false
        loadResults()
    }

    // MARK: - Batch execution (Exp A)

    func runBatchSingleTurn() async {
        guard let modelPath else {
            statusText = "Select a model"
            return
        }
        guard let dataset, !dataset.singleTurn.isEmpty else {
            statusText = "ChatAlpaca dataset is missing"
            return
        }

        let samples = dataset.singleTurn
        let total = samples.count
        var succeeded = 0
        var failed = 0

        isBatchRunning = true
        // Force single-turn mode (ignore multi-turn toggle)
        benchmarkMode = .singleTurn

        for (idx, sample) in samples.enumerated() {
            // Update progress
            batchProgress = BatchProgress(
                current: idx + 1,
                total: total,
                currentId: sample.id,
                currentBin: sample.bin,
                phase: "running",
                succeeded: succeeded,
                failed: failed
            )
            statusText = "Batch \(idx+1)/\(total): \(sample.id) [\(sample.bin), \(sample.inputTokens) tok]"
            generatedText = ""

            // Sync the sample picker (UI consistency)
            selectedSingleTurnId = sample.id

            // Single execution (model load → inference → unload)
            await runner.run(
                modelPath: modelPath,
                prompt: sample.prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                mode: .singleTurn,
                multiTurnMessages: nil
            )

            // Determine success/failure from runner.state
            if case .completed(let result) = runner.state {
                lastResult = result
                generatedText = runner.generatedText
                succeeded += 1
            } else if case .failed(let msg) = runner.state {
                statusText = "Batch \(idx+1)/\(total) failed: \(msg)"
                failed += 1
            }

            // Skip cool-down after the last sample
            guard idx < total - 1 else { break }

            // Cool-down (count down by 1s)
            for sec in stride(from: batchCoolDownSec, through: 1, by: -1) {
                batchProgress = BatchProgress(
                    current: idx + 1,
                    total: total,
                    currentId: sample.id,
                    currentBin: sample.bin,
                    phase: "cooling \(sec)s",
                    succeeded: succeeded,
                    failed: failed
                )
                statusText = "Cool-down \(sec)s — next: \(idx+2 <= total ? samples[idx+1].id : "")"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        batchProgress = BatchProgress(
            current: total,
            total: total,
            currentId: "",
            currentBin: "",
            phase: "done",
            succeeded: succeeded,
            failed: failed
        )
        statusText = "Batch done — \(succeeded) succeeded · \(failed) failed · \(total) total"
        isBatchRunning = false
        loadResults()
    }

    // MARK: - Batch execution (Exp E — multi-turn cumulative-context)

    func runBatchMultiTurn() async {
        guard let modelPath else {
            statusText = "Select a model"
            return
        }
        guard let dataset, !dataset.multiTurn.isEmpty else {
            statusText = "ChatAlpaca dataset is missing"
            return
        }

        let samples = dataset.multiTurn
        let total = samples.count
        var succeeded = 0
        var failed = 0

        isBatchRunning = true
        // Force multi-turn mode
        benchmarkMode = .multiTurn

        for (idx, sample) in samples.enumerated() {
            let label = "\(sample.turnCount) turns · \(sample.totalTokens) tok"
            batchProgress = BatchProgress(
                current: idx + 1,
                total: total,
                currentId: sample.id,
                currentBin: label,
                phase: "running",
                succeeded: succeeded,
                failed: failed
            )
            statusText = "Batch \(idx+1)/\(total): \(sample.id) [\(label)]"
            generatedText = ""

            // Sync the sample picker (UI consistency)
            selectedMultiTurnId = sample.id
            multiTurnMessages = sample.messages

            await runner.run(
                modelPath: modelPath,
                prompt: sample.messages.first?["content"] ?? "",
                maxTokens: maxTokens,
                temperature: temperature,
                mode: .multiTurn,
                multiTurnMessages: sample.messages
            )

            if case .completed(let result) = runner.state {
                lastResult = result
                generatedText = runner.generatedText
                succeeded += 1
            } else if case .failed(let msg) = runner.state {
                statusText = "Batch \(idx+1)/\(total) failed: \(msg)"
                failed += 1
            }

            guard idx < total - 1 else { break }

            // Cool-down
            for sec in stride(from: batchCoolDownSec, through: 1, by: -1) {
                batchProgress = BatchProgress(
                    current: idx + 1,
                    total: total,
                    currentId: sample.id,
                    currentBin: label,
                    phase: "cooling \(sec)s",
                    succeeded: succeeded,
                    failed: failed
                )
                statusText = "Cool-down \(sec)s — next: \(idx+2 <= total ? samples[idx+1].id : "")"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }

        batchProgress = BatchProgress(
            current: total,
            total: total,
            currentId: "",
            currentBin: "",
            phase: "done",
            succeeded: succeeded,
            failed: failed
        )
        statusText = "Batch done (multi-turn) — \(succeeded) succeeded · \(failed) failed · \(total) total"
        isBatchRunning = false
        loadResults()
    }

    // MARK: - Thermal Stress (Exp C — same sample, N rounds, no cool-down)

    func runThermalStress() async {
        guard let modelPath else {
            statusText = "Select a model"
            return
        }
        guard let dataset, !dataset.singleTurn.isEmpty else {
            statusText = "ChatAlpaca dataset is missing"
            return
        }

        // Use the single-turn sample currently selected via the picker (else the first one)
        let targetSampleId = selectedSingleTurnId ?? dataset.singleTurn.first?.id
        guard let sampleId = targetSampleId,
              let sample = dataset.singleTurn.first(where: { $0.id == sampleId }) else {
            statusText = "Could not find a sample for thermal stress"
            return
        }

        let total = max(1, thermalStressRepeats)
        var succeeded = 0
        var failed = 0

        isBatchRunning = true
        // Force single-turn mode (ignore multi-turn toggle)
        benchmarkMode = .singleTurn
        prompt = sample.prompt

        for round in 1...total {
            batchProgress = BatchProgress(
                current: round,
                total: total,
                currentId: sample.id,
                currentBin: "round \(round)/\(total)",
                phase: "stress",
                succeeded: succeeded,
                failed: failed
            )
            statusText = "Thermal stress \(round)/\(total): \(sample.id) [\(sample.bin), \(sample.inputTokens) tok]"
            generatedText = ""

            await runner.run(
                modelPath: modelPath,
                prompt: sample.prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                mode: .singleTurn,
                multiTurnMessages: nil
            )

            if case .completed(let result) = runner.state {
                lastResult = result
                generatedText = runner.generatedText
                succeeded += 1
            } else if case .failed(let msg) = runner.state {
                statusText = "Thermal stress round \(round)/\(total) failed: \(msg)"
                failed += 1
            }
            // Cool-down deliberately skipped: thermal/battery accumulation across rounds is the measurement target.
        }

        batchProgress = BatchProgress(
            current: total,
            total: total,
            currentId: "",
            currentBin: "",
            phase: "done",
            succeeded: succeeded,
            failed: failed
        )
        statusText = "Thermal Stress done — rounds \(succeeded) succeeded · \(failed) failed · \(total) total"
        isBatchRunning = false
        loadResults()
    }

    func loadResults() {
        savedResults = ResultStore.loadAll()
    }

    func deleteResult(_ result: BenchmarkResult) {
        ResultStore.delete(result)
        loadResults()
    }

    func validateModelPath(_ url: URL) -> Bool {
        let metaPath = url.appendingPathComponent("meta.yaml").path
        return FileManager.default.fileExists(atPath: metaPath)
    }
}
