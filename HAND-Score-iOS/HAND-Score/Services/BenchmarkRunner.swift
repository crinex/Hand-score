import Foundation
import CoreML
@preconcurrency import HandScoreCore
#if canImport(UIKit)
import UIKit
#endif

// Benchmark execution orchestrator
@MainActor
final class BenchmarkRunner: ObservableObject {

    enum State: Sendable {
        case idle
        case loadingModel(progress: Double, stage: String)
        case running(tokensGenerated: Int, currentTPS: Double)
        case completed(BenchmarkResult)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var generatedText: String = ""

    private var inferenceManager: InferenceManager?
    private var loadedModels: LoadedModels?

    // MARK: - Single-turn benchmark entry point

    func run(modelPath: URL, prompt: String, maxTokens: Int, temperature: Float) async {
        await run(modelPath: modelPath, prompt: prompt, maxTokens: maxTokens, temperature: temperature, mode: .singleTurn, multiTurnMessages: nil)
    }

    // MARK: - Unified benchmark execution (single-turn / multi-turn)

    func run(
        modelPath: URL,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        mode: BenchmarkMode,
        multiTurnMessages: [[String: String]]?  // [{"role": "user"/"assistant", "content": "..."}]
    ) async {
        state = .idle
        generatedText = ""

        let metricsCollector = MetricsCollector()

        do {
            // 1. Pre-run metrics snapshot
            let snapshotBefore = MetricsCollector.takeSnapshot()

            // 2. Start MetricsCollector
            metricsCollector.start()

            // 3. Load model
            state = .loadingModel(progress: 0, stage: "Loading config")
            let metaYamlPath = modelPath.appendingPathComponent("meta.yaml").path

            guard FileManager.default.fileExists(atPath: metaYamlPath) else {
                state = .failed("meta.yaml not found: \(metaYamlPath)")
                return
            }

            let config = try YAMLConfig.load(from: metaYamlPath)

            state = .loadingModel(progress: 0.1, stage: "Loading tokenizer")
            let template = detectTemplate(from: config)
            let tokenizer = try await Tokenizer(modelPath: modelPath.path, template: template)

            state = .loadingModel(progress: 0.2, stage: "Loading CoreML model")
            let loadStartTime = CFAbsoluteTimeGetCurrent()

            let progressDelegate = LoadingProgressAdapter { [weak self] pct, stage, _ in
                Task { @MainActor in
                    self?.state = .loadingModel(progress: 0.2 + pct * 0.7, stage: stage)
                }
            }

            let modelLoader = ModelLoader(progressDelegate: progressDelegate)
            let models = try await modelLoader.loadModel(from: config)
            self.loadedModels = models

            let modelLoadTimeMs = (CFAbsoluteTimeGetCurrent() - loadStartTime) * 1000.0

            state = .loadingModel(progress: 0.95, stage: "Initializing inference engine")
            let infManager = try InferenceManager(
                models: models,
                contextLength: config.contextLength,
                batchSize: config.batchSize,
                splitLMHead: config.splitLMHead,
                argmaxInModel: config.argmaxInModel,
                slidingWindow: config.slidingWindow,
                updateMaskPrefill: config.updateMaskPrefill,
                prefillDynamicSlice: config.prefillDynamicSlice,
                modelPrefix: config.modelPrefix,
                vocabSize: config.vocabSize,
                lmHeadChunkSizes: config.lmHeadChunkSizes
            )
            self.inferenceManager = infManager

            // 4. Mode-specific execution branch
            let result: BenchmarkResult
            if mode == .multiTurn, let messages = multiTurnMessages {
                result = try await runMultiTurn(
                    infManager: infManager,
                    tokenizer: tokenizer,
                    config: config,
                    modelPath: modelPath,
                    modelLoadTimeMs: modelLoadTimeMs,
                    messages: messages,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    metricsCollector: metricsCollector,
                    snapshotBefore: snapshotBefore
                )
            } else {
                result = try await runSingleTurn(
                    infManager: infManager,
                    tokenizer: tokenizer,
                    config: config,
                    modelPath: modelPath,
                    modelLoadTimeMs: modelLoadTimeMs,
                    prompt: prompt,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    metricsCollector: metricsCollector,
                    snapshotBefore: snapshotBefore
                )
            }

            // 8. ANE profiling (before unloading the model)
            state = .loadingModel(progress: 0.98, stage: "Analyzing ANE profile...")
            let aneProfile = await ANEProfiler.analyze(modelPath: modelPath)

            let finalResult: BenchmarkResult
            if aneProfile != nil {
                finalResult = BenchmarkResult(
                    device: result.device,
                    model: result.model,
                    config: result.config,
                    performance: result.performance,
                    system: result.system,
                    generatedText: result.generatedText,
                    aneProfile: aneProfile,
                    turnResults: result.turnResults
                )
            } else {
                finalResult = result
            }

            // 9. Save JSON
            let savedURL = try ResultStore.save(finalResult)
            print("[HAND-Score] Saved result: \(savedURL.lastPathComponent)")

            state = .completed(finalResult)

            // Unload model
            infManager.unload()
            self.inferenceManager = nil
            self.loadedModels = nil

        } catch {
            _ = metricsCollector.stop()
            inferenceManager?.unload()
            self.inferenceManager = nil
            self.loadedModels = nil
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Single-turn execution

    private func runSingleTurn(
        infManager: InferenceManager,
        tokenizer: Tokenizer,
        config: YAMLConfig,
        modelPath: URL,
        modelLoadTimeMs: Double,
        prompt: String,
        maxTokens: Int,
        temperature: Float,
        metricsCollector: MetricsCollector,
        snapshotBefore: SystemSnapshot
    ) async throws -> BenchmarkResult {
        state = .running(tokensGenerated: 0, currentTPS: 0)

        let chatMessages: [HandScoreCore.Tokenizer.ChatMessage] = [.user(prompt)]
        let inputTokens = tokenizer.applyChatTemplate(input: chatMessages, addGenerationPrompt: true)
        let prefillTokenCount = inputTokens.count

        var tokenCount = 0
        var ttftMs: Double = 0
        let inferenceStartTime = CFAbsoluteTimeGetCurrent()
        var firstTokenTime: CFAbsoluteTime = 0
        var allTokenIds: [Int] = []
        var prevDecodedText: String = ""

        let capturedInfManager = infManager
        let capturedTokenizer = tokenizer

        let (_, prefillTime, _) = try await Task.detached(priority: .userInitiated) {
            () async throws -> ([Int], TimeInterval, String) in
            try await capturedInfManager.generateResponse(
                initialTokens: inputTokens,
                temperature: temperature,
                maxTokens: maxTokens,
                eosTokens: capturedTokenizer.eosTokenIds,
                tokenizer: capturedTokenizer,
                onToken: { [weak self] token in
                    tokenCount += 1

                    if firstTokenTime == 0 {
                        firstTokenTime = CFAbsoluteTimeGetCurrent()
                        ttftMs = (firstTokenTime - inferenceStartTime) * 1000.0
                    }

                    allTokenIds.append(token)
                    let fullText = capturedTokenizer.decode(tokens: allTokenIds)
                    let newText: String
                    if fullText.count > prevDecodedText.count {
                        newText = String(fullText[fullText.index(fullText.startIndex, offsetBy: prevDecodedText.count)...])
                    } else {
                        newText = capturedTokenizer.decode(tokens: [token])
                    }
                    prevDecodedText = fullText

                    let elapsed = CFAbsoluteTimeGetCurrent() - inferenceStartTime
                    let currentTPS = elapsed > 0 ? Double(tokenCount) / elapsed : 0

                    Task { @MainActor in
                        self?.generatedText += newText
                        self?.state = .running(tokensGenerated: tokenCount, currentTPS: currentTPS)
                    }
                }
            )
        }.value

        let endTime = CFAbsoluteTimeGetCurrent()
        let totalInferenceTime = endTime - inferenceStartTime

        let timeline = metricsCollector.stop()
        let snapshotAfter = MetricsCollector.takeSnapshot()

        let prefillTimeMs = prefillTime * 1000.0   // compute-only (kept for reference)
        // Standard definition: Prefill TPS = N_prompt / TTFT (Genie / llama.cpp / vLLM convention)
        let prefillTPS = ttftMs > 0 ? Double(prefillTokenCount) / (ttftMs / 1000.0) : 0

        let decodeTokenCount = max(tokenCount - 1, 0)
        let decodeTimeSec: Double
        if firstTokenTime > 0 && decodeTokenCount > 0 {
            decodeTimeSec = endTime - firstTokenTime
        } else {
            decodeTimeSec = max(totalInferenceTime - prefillTime, 0.001)
        }
        let decodeTimeMs = decodeTimeSec * 1000.0
        let decodeTPS = decodeTimeSec > 0 ? Double(decodeTokenCount) / decodeTimeSec : 0

        print("[HAND-Score] === Timing detail (Single-Turn) ===")
        print("[HAND-Score] prefillTokens: \(prefillTokenCount), prefillTime: \(String(format: "%.3f", prefillTime))s, prefillTPS: \(String(format: "%.1f", prefillTPS))")
        print("[HAND-Score] decodeTokens: \(decodeTokenCount), decodeTime: \(String(format: "%.3f", decodeTimeSec))s, decodeTPS: \(String(format: "%.1f", decodeTPS))")
        print("[HAND-Score] TTFT: \(String(format: "%.1f", ttftMs))ms, totalTime: \(String(format: "%.3f", totalInferenceTime))s")

        return BenchmarkResult(
            device: Self.currentDeviceInfo(),
            model: ModelInfo(
                name: modelPath.lastPathComponent,
                path: modelPath.path,
                contextLength: config.contextLength,
                batchSize: config.batchSize,
                isMonolithic: config.isMonolithic
            ),
            config: BenchmarkConfig(
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                mode: .singleTurn
            ),
            performance: PerformanceMetrics(
                modelLoadTimeMs: modelLoadTimeMs,
                prefillTimeMs: prefillTimeMs,
                prefillTokens: prefillTokenCount,
                prefillTokensPerSec: prefillTPS,
                decodeTokens: decodeTokenCount,
                decodeTimeMs: decodeTimeMs,
                decodeTokensPerSec: decodeTPS,
                ttftMs: ttftMs,
                totalTokens: tokenCount,
                totalTimeMs: totalInferenceTime * 1000.0
            ),
            system: SystemMetricsReport(
                before: snapshotBefore,
                after: snapshotAfter,
                timeline: timeline
            ),
            generatedText: generatedText
        )
    }

    // MARK: - Multi-turn execution (Cumulative Context)
    //
    // Because the non-monolithic HandScoreCore runPrefill does not correctly accumulate the KV
    // cache when positionOffset > 0, we measure multi-turn dialogues by re-prefilling the
    // accumulated chat history from scratch at every assistant turn instead of relying on
    // KV-cache reuse.
    //
    // Measurement objective: the effect of cumulative context on response latency and memory.
    // (Measuring KV-cache reuse efficiency is left to a separate ablation.)

    private func runMultiTurn(
        infManager: InferenceManager,
        tokenizer: Tokenizer,
        config: YAMLConfig,
        modelPath: URL,
        modelLoadTimeMs: Double,
        messages: [[String: String]],
        maxTokens: Int,
        temperature: Float,
        metricsCollector: MetricsCollector,
        snapshotBefore: SystemSnapshot
    ) async throws -> BenchmarkResult {
        state = .running(tokensGenerated: 0, currentTPS: 0)

        var turnResults: [TurnResult] = []
        var totalGeneratedTokens = 0
        var totalPrefillTokens = 0
        var totalPrefillTimeMs: Double = 0
        var totalDecodeTimeMs: Double = 0
        var totalDecodeTokens = 0
        var firstTurnTTFT: Double = 0
        var totalTTFTMs: Double = 0   // For standard prefill-TPS aggregation (N / TTFT)
        let overallStartTime = CFAbsoluteTimeGetCurrent()
        var allGeneratedText = ""

        let capturedInfManager = infManager
        let capturedTokenizer = tokenizer

        // Cumulative chat history (user messages + generated assistant replies)
        var chatHistory: [HandScoreCore.Tokenizer.ChatMessage] = []

        for (turnIdx, message) in messages.enumerated() {
            let role = message["role"] ?? "user"
            let content = message["content"] ?? ""

            if role == "user" {
                // User messages are appended to the history only; actual prefill occurs at the next assistant turn (cumulative).
                chatHistory.append(.user(content))

                let userInputTokens = capturedTokenizer.tokenize(content).count
                turnResults.append(TurnResult(
                    turnIndex: turnIdx,
                    role: "user",
                    inputText: content,
                    inputTokens: userInputTokens,
                    outputTokens: 0,
                    prefillTimeMs: 0,
                    prefillTokensPerSec: 0,
                    decodeTimeMs: 0,
                    decodeTokensPerSec: 0,
                    ttftMs: 0,
                    kvCachePosition: 0,
                    generatedText: ""
                ))

                print("[HAND-Score] Turn \(turnIdx) (user): +\(userInputTokens) tok appended to history (deferred prefill)")

                Task { @MainActor in
                    self.state = .running(tokensGenerated: totalGeneratedTokens, currentTPS: 0)
                }

            } else if role == "assistant" {
                // Tokenize the entire accumulated history and prefill from scratch (no KV-cache reuse)
                let inputTokens = capturedTokenizer.applyChatTemplate(input: chatHistory, addGenerationPrompt: true)
                let prefillTokenCount = inputTokens.count

                var turnTokenCount = 0
                var turnFirstTokenTime: CFAbsoluteTime = 0
                var turnAllTokenIds: [Int] = []
                var turnPrevDecoded = ""
                let turnInferStart = CFAbsoluteTimeGetCurrent()

                let (_, prefillTime, _) = try await Task.detached(priority: .userInitiated) {
                    () async throws -> ([Int], TimeInterval, String) in
                    try await capturedInfManager.generateResponse(
                        initialTokens: inputTokens,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        eosTokens: capturedTokenizer.eosTokenIds,
                        tokenizer: capturedTokenizer,
                        onToken: { [weak self] token in
                            turnTokenCount += 1
                            totalGeneratedTokens += 1

                            if turnFirstTokenTime == 0 {
                                turnFirstTokenTime = CFAbsoluteTimeGetCurrent()
                            }

                            turnAllTokenIds.append(token)
                            let fullText = capturedTokenizer.decode(tokens: turnAllTokenIds)
                            let newText: String
                            if fullText.count > turnPrevDecoded.count {
                                newText = String(fullText[fullText.index(fullText.startIndex, offsetBy: turnPrevDecoded.count)...])
                            } else {
                                newText = capturedTokenizer.decode(tokens: [token])
                            }
                            turnPrevDecoded = fullText

                            let elapsed = CFAbsoluteTimeGetCurrent() - overallStartTime
                            let currentTPS = elapsed > 0 ? Double(totalGeneratedTokens) / elapsed : 0

                            Task { @MainActor in
                                self?.generatedText += newText
                                self?.state = .running(tokensGenerated: totalGeneratedTokens, currentTPS: currentTPS)
                            }
                        }
                        // preserveKVCache argument omitted (defaults to false): KV cache is reset every turn
                    )
                }.value

                let turnEndTime = CFAbsoluteTimeGetCurrent()
                let turnTTFT = turnFirstTokenTime > 0 ? (turnFirstTokenTime - turnInferStart) * 1000.0 : 0
                let turnPrefillMs = prefillTime * 1000.0
                let turnDecodeTokens = max(turnTokenCount - 1, 0)
                let turnDecodeSec = turnFirstTokenTime > 0 ? turnEndTime - turnFirstTokenTime : max((turnEndTime - turnInferStart) - prefillTime, 0.001)
                let turnDecodeMs = turnDecodeSec * 1000.0
                let turnDecodeTPS = turnDecodeSec > 0 ? Double(turnDecodeTokens) / turnDecodeSec : 0
                // Standard definition: Prefill TPS = N_prompt / TTFT
                let turnPrefillTPS = turnTTFT > 0 ? Double(prefillTokenCount) / (turnTTFT / 1000.0) : 0

                if firstTurnTTFT == 0 {
                    firstTurnTTFT = turnTTFT
                }

                totalPrefillTokens += prefillTokenCount
                totalPrefillTimeMs += turnPrefillMs
                totalTTFTMs += turnTTFT   // For aggregating the average prefill TPS
                totalDecodeTokens += turnDecodeTokens
                totalDecodeTimeMs += turnDecodeMs

                let turnGenText = capturedTokenizer.decode(tokens: turnAllTokenIds)

                // Append the generated reply to the history (consumed by the next turn's cumulative prefill)
                chatHistory.append(.assistant(turnGenText))

                allGeneratedText += "[Turn \(turnIdx)] \(turnGenText)\n"

                turnResults.append(TurnResult(
                    turnIndex: turnIdx,
                    role: "assistant",
                    inputText: "(generated)",
                    inputTokens: prefillTokenCount,
                    outputTokens: turnTokenCount,
                    prefillTimeMs: turnPrefillMs,
                    prefillTokensPerSec: turnPrefillTPS,
                    decodeTimeMs: turnDecodeMs,
                    decodeTokensPerSec: turnDecodeTPS,
                    ttftMs: turnTTFT,
                    kvCachePosition: 0,  // KV cache reuse disabled
                    generatedText: turnGenText
                ))

                print("[HAND-Score] Turn \(turnIdx) (assistant): cumulative prefill \(prefillTokenCount) tok, generated \(turnTokenCount) tok, TTFT: \(String(format: "%.1f", turnTTFT))ms, decode TPS: \(String(format: "%.1f", turnDecodeTPS))")
            }
        }

        let overallEndTime = CFAbsoluteTimeGetCurrent()
        let totalTime = overallEndTime - overallStartTime

        let timeline = metricsCollector.stop()
        let snapshotAfter = MetricsCollector.takeSnapshot()

        // Standard definition: average Prefill TPS = Σ N_prompt / Σ TTFT
        let avgPrefillTPS = totalTTFTMs > 0 ? Double(totalPrefillTokens) / (totalTTFTMs / 1000.0) : 0
        let avgDecodeTPS = totalDecodeTimeMs > 0 ? Double(totalDecodeTokens) / (totalDecodeTimeMs / 1000.0) : 0

        print("[HAND-Score] === Timing detail (Multi-Turn, Cumulative Context) ===")
        print("[HAND-Score] total turns: \(messages.count), total prefill: \(totalPrefillTokens) tok, total decode: \(totalDecodeTokens) tok")
        print("[HAND-Score] avg prefill TPS: \(String(format: "%.1f", avgPrefillTPS)), avg decode TPS: \(String(format: "%.1f", avgDecodeTPS))")
        print("[HAND-Score] first-turn TTFT: \(String(format: "%.1f", firstTurnTTFT))ms, total time: \(String(format: "%.3f", totalTime))s")

        return BenchmarkResult(
            device: Self.currentDeviceInfo(),
            model: ModelInfo(
                name: modelPath.lastPathComponent,
                path: modelPath.path,
                contextLength: config.contextLength,
                batchSize: config.batchSize,
                isMonolithic: config.isMonolithic
            ),
            config: BenchmarkConfig(
                prompt: messages.first?["content"] ?? "",
                maxTokens: maxTokens,
                temperature: temperature,
                mode: .multiTurn
            ),
            performance: PerformanceMetrics(
                modelLoadTimeMs: modelLoadTimeMs,
                prefillTimeMs: totalPrefillTimeMs,
                prefillTokens: totalPrefillTokens,
                prefillTokensPerSec: avgPrefillTPS,
                decodeTokens: totalDecodeTokens,
                decodeTimeMs: totalDecodeTimeMs,
                decodeTokensPerSec: avgDecodeTPS,
                ttftMs: firstTurnTTFT,
                totalTokens: totalGeneratedTokens,
                totalTimeMs: totalTime * 1000.0
            ),
            system: SystemMetricsReport(
                before: snapshotBefore,
                after: snapshotAfter,
                timeline: timeline
            ),
            generatedText: allGeneratedText,
            turnResults: turnResults
        )
    }

    // MARK: - Bundled-model discovery

    static func bundledModelPaths() -> [URL] {
        guard let resourceURL = Bundle.main.resourceURL else { return [] }
        let fm = FileManager.default

        // 1) Subfolder containing meta.yaml (folder-style bundle)
        if let contents = try? fm.contentsOfDirectory(
            at: resourceURL,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) {
            let subfolderModels = contents.filter { url in
                var isDir: ObjCBool = false
                fm.fileExists(atPath: url.path, isDirectory: &isDir)
                guard isDir.boolValue else { return false }
                return fm.fileExists(atPath: url.appendingPathComponent("meta.yaml").path)
            }
            if !subfolderModels.isEmpty {
                return subfolderModels
            }
        }

        // 2) meta.yaml directly at bundle root (flattened layout)
        if fm.fileExists(atPath: resourceURL.appendingPathComponent("meta.yaml").path) {
            return [resourceURL]
        }

        return []
    }

    // MARK: - Device info

    static func currentDeviceInfo() -> DeviceInfo {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }

        return DeviceInfo(
            model: machine,
            name: mapDeviceName(machine),
            chip: mapChipName(machine),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    private static func mapDeviceName(_ machine: String) -> String {
        let mapping: [String: String] = [
            "iPhone15,4": "iPhone 15",
            "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro",
            "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,1": "iPhone 16 Pro",
            "iPhone17,2": "iPhone 16 Pro Max",
            "iPhone17,3": "iPhone 16",
            "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,5": "iPhone 16e",
            "iPad16,3": "iPad Pro M4 11\"",
            "iPad16,4": "iPad Pro M4 11\"",
            "iPad16,5": "iPad Pro M4 13\"",
            "iPad16,6": "iPad Pro M4 13\"",
        ]
        return mapping[machine] ?? machine
    }

    private static func mapChipName(_ machine: String) -> String {
        if machine.hasPrefix("iPhone17") { return "A18 / A18 Pro" }
        if machine.hasPrefix("iPhone16") { return "A17 Pro" }
        if machine.hasPrefix("iPhone15") { return "A16 Bionic" }
        if machine.contains("iPad16") { return "M4" }
        return "Unknown"
    }

    private func detectTemplate(from config: YAMLConfig) -> String {
        let path = config.modelPath.lowercased()
        if path.contains("gemma3") { return "gemma3" }
        if path.contains("gemma") { return "gemma" }
        if path.contains("qwen") { return "qwen" }
        if path.contains("deepseek") { return "deepseek" }
        if path.contains("deephermes") { return "deephermes" }
        if path.contains("llama") { return "llama3" }
        return "default"
    }
}

// MARK: - Loading-progress adapter

private final class LoadingProgressAdapter: ModelLoadingProgressDelegate, @unchecked Sendable {
    private let onProgress: (Double, String, String?) -> Void

    init(onProgress: @escaping (Double, String, String?) -> Void) {
        self.onProgress = onProgress
    }

    func loadingProgress(percentage: Double, stage: String, detail: String?) {
        onProgress(percentage, stage, detail)
    }

    func loadingCompleted(models: LoadedModels) {
        onProgress(1.0, "Done", nil)
    }

    func loadingCancelled() {
        onProgress(0, "Cancelled", nil)
    }

    func loadingFailed(error: Error) {
        onProgress(0, "Failed", error.localizedDescription)
    }
}
