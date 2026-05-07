import SwiftUI

struct BenchmarkView: View {
    @StateObject private var viewModel = BenchmarkViewModel()
    @State private var showResults = false
    @State private var showResultDetail = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Model card gallery
                    ModelCardGalleryView(
                        viewModel: viewModel,
                        hfService: viewModel.hfService
                    )

                    configSection
                    runButton

                    // Batch runner shown for both single-turn and multi-turn modes (Exp A / E)
                    batchSection

                    // Thermal-stress runner shown only in single-turn mode (Exp C)
                    if viewModel.benchmarkMode == .singleTurn {
                        thermalStressSection
                    }

                    if viewModel.isRunning {
                        progressSection
                    }

                    if viewModel.isBatchRunning {
                        batchProgressSection
                    }

                    if !viewModel.generatedText.isEmpty {
                        generatedTextSection
                    }

                    if let result = viewModel.lastResult {
                        resultSummarySection(result)
                    }
                }
                .padding()
            }
            .navigationTitle("HAND-Score")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Results") {
                        showResults = true
                    }
                    .disabled(viewModel.savedResults.isEmpty)
                }
            }
            .sheet(isPresented: $showResults) {
                ResultsListView(viewModel: viewModel)
            }
        }
    }

    // MARK: - Configuration

    private var configSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)

            // Benchmark mode selector
            VStack(alignment: .leading, spacing: 4) {
                Text("Benchmark Mode")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Mode", selection: $viewModel.benchmarkMode) {
                    ForEach(BenchmarkMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            if viewModel.benchmarkMode == .singleTurn {
                // Single-turn: ChatAlpaca sample selector + prompt editor
                if let dataset = viewModel.dataset {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ChatAlpaca Sample (Exp A)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Sample", selection: $viewModel.selectedSingleTurnId) {
                            ForEach(dataset.singleTurn) { sample in
                                Text("\(sample.id) · \(sample.bin) · \(sample.inputTokens) tok")
                                    .tag(Optional(sample.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Prompt")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $viewModel.prompt)
                        .frame(minHeight: 60, maxHeight: 120)
                        .padding(4)
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(.separator), lineWidth: 1))
                }
            } else {
                // Multi-turn: ChatAlpaca dialogue selector + preview
                if let dataset = viewModel.dataset {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ChatAlpaca Dialogue (Exp E)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Picker("Dialogue", selection: $viewModel.selectedMultiTurnId) {
                            ForEach(dataset.multiTurn) { sample in
                                Text("\(sample.id) · \(sample.turnCount) turns · \(sample.totalTokens) tok")
                                    .tag(Optional(sample.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Multi-turn Conversation (\(viewModel.multiTurnMessages.count) turns)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(viewModel.multiTurnMessages.enumerated()), id: \.offset) { _, msg in
                            let role = msg["role"] ?? "?"
                            let content = msg["content"] ?? ""
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: role == "user" ? "person.fill" : "cpu")
                                    .foregroundStyle(role == "user" ? .blue : .green)
                                    .frame(width: 20)
                                if content.isEmpty {
                                    Text("(generated by model)")
                                        .font(.caption)
                                        .italic()
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text(content)
                                        .font(.caption)
                                        .lineLimit(2)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Max Tokens")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("256", value: $viewModel.maxTokens, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }

                VStack(alignment: .leading) {
                    Text("Temperature")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField("0.0", value: $viewModel.temperature, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.decimalPad)
                }
            }
        }
    }

    // MARK: - Run button

    private var runButton: some View {
        Button {
            Task {
                await viewModel.runBenchmark()
            }
        } label: {
            HStack {
                if viewModel.isRunning {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "play.fill")
                }
                Text(viewModel.isRunning ? "Running..." : "Run Benchmark")
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(viewModel.isRunning ? Color.gray : Color.blue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(viewModel.isRunning || viewModel.modelPath == nil)
    }

    // MARK: - Batch runner (Exp A / E)

    private var batchSection: some View {
        let isSingleTurn = viewModel.benchmarkMode == .singleTurn
        let title = isSingleTurn ? "Exp A — Single-turn Batch" : "Exp E — Multi-turn Batch"
        let count = isSingleTurn ? (viewModel.dataset?.singleTurn.count ?? 0) : (viewModel.dataset?.multiTurn.count ?? 0)

        return VStack(alignment: .leading, spacing: 10) {
            Divider()
            Text(title)
                .font(.headline)
            if let dataset = viewModel.dataset {
                Group {
                    if isSingleTurn {
                        let s = dataset.singleTurn.filter { $0.bin == "short" }.count
                        let ms = dataset.singleTurn.filter { $0.bin == "med_short" }.count
                        let m = dataset.singleTurn.filter { $0.bin == "medium" }.count
                        Text("ChatAlpaca \(dataset.singleTurn.count) single-turn samples (Short \(s) · Med-Short \(ms) · Medium \(m))")
                    } else {
                        let by4 = dataset.multiTurn.filter { $0.turnCount == 4 }.count
                        let by5 = dataset.multiTurn.filter { $0.turnCount == 5 }.count
                        let by6 = dataset.multiTurn.filter { $0.turnCount == 6 }.count
                        Text("ChatAlpaca \(dataset.multiTurn.count) multi-turn dialogues (4-turn \(by4) · 5-turn \(by5) · 6-turn \(by6))")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cool-down (sec)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("10", value: $viewModel.batchCoolDownSec, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                }
                Spacer()
            }
            Button {
                Task {
                    if isSingleTurn {
                        await viewModel.runBatchSingleTurn()
                    } else {
                        await viewModel.runBatchMultiTurn()
                    }
                }
            } label: {
                HStack {
                    if viewModel.isBatchRunning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "play.rectangle.on.rectangle")
                    }
                    Text(viewModel.isBatchRunning ? "Batch running..." : "Run ChatAlpaca \(count) samples")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background((viewModel.isRunning || viewModel.isBatchRunning) ? Color.gray : (isSingleTurn ? Color.purple : Color.indigo))
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.isRunning || viewModel.isBatchRunning || viewModel.modelPath == nil || viewModel.dataset == nil)
        }
    }

    // MARK: - Thermal Stress section (Exp C)

    private var thermalStressSection: some View {
        let selectedSample: SingleTurnSample? = {
            guard let dataset = viewModel.dataset, let id = viewModel.selectedSingleTurnId else { return nil }
            return dataset.singleTurn.first(where: { $0.id == id })
        }()

        return VStack(alignment: .leading, spacing: 10) {
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Exp C — Thermal Stress")
                    .font(.headline)
            }
            Text("Repeats the same sample for N rounds without cool-down to measure the thermal-throttling curve.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let sample = selectedSample {
                Text("Target sample: \(sample.id) · \(sample.bin) · \(sample.inputTokens) tok")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Change the sample using the 'ChatAlpaca Sample' picker above.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("No sample selected — pick a single-turn sample from the picker above.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rounds")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("30", value: $viewModel.thermalStressRepeats, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                        .frame(width: 80)
                }
                Spacer()
            }
            Button {
                Task { await viewModel.runThermalStress() }
            } label: {
                HStack {
                    if viewModel.isBatchRunning {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "flame.fill")
                    }
                    Text(viewModel.isBatchRunning ? "Thermal stress running..." : "Run thermal stress for \(viewModel.thermalStressRepeats) rounds")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background((viewModel.isRunning || viewModel.isBatchRunning) ? Color.gray : Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.isRunning || viewModel.isBatchRunning || viewModel.modelPath == nil || selectedSample == nil)
        }
    }

    private var batchProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Batch \(viewModel.batchProgress.current)/\(viewModel.batchProgress.total)")
                    .font(.headline)
                Spacer()
                Text("Succeeded \(viewModel.batchProgress.succeeded) · Failed \(viewModel.batchProgress.failed)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if viewModel.batchProgress.total > 0 {
                ProgressView(value: Double(viewModel.batchProgress.current), total: Double(viewModel.batchProgress.total))
            }
            if !viewModel.batchProgress.currentId.isEmpty {
                HStack {
                    Text(viewModel.batchProgress.currentId)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("[\(viewModel.batchProgress.currentBin)]")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(viewModel.batchProgress.phase)
                        .font(.caption)
                        .foregroundStyle(viewModel.batchProgress.phase.contains("cooling") ? .blue : .green)
                }
            }
            Text(viewModel.statusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: - Progress

    private var progressSection: some View {
        VStack(spacing: 8) {
            if viewModel.loadingProgress > 0 && viewModel.loadingProgress < 1.0 {
                ProgressView(value: viewModel.loadingProgress)
            }

            Text(viewModel.statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if viewModel.tokensGenerated > 0 {
                HStack {
                    Label("\(viewModel.tokensGenerated) tokens", systemImage: "text.word.spacing")
                    Spacer()
                    Label(String(format: "%.1f tok/s", viewModel.currentTPS), systemImage: "speedometer")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(10)
    }

    // MARK: - Generated text

    private var generatedTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Generated Output")
                .font(.headline)

            Text(viewModel.generatedText)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
        }
    }

    // MARK: - Result summary

    private func resultSummarySection(_ result: BenchmarkResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Benchmark Result")
                    .font(.headline)
                if result.config.mode == .multiTurn {
                    Text("Multi-Turn")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(4)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                metricCard("Model Load", String(format: "%.0f ms", result.performance.modelLoadTimeMs))
                metricCard("Prefill", String(format: "%.0f ms", result.performance.prefillTimeMs))
                metricCard("Prefill TPS", String(format: "%.1f tok/s", result.performance.prefillTokensPerSec))
                metricCard("Decode TPS", String(format: "%.1f tok/s", result.performance.decodeTokensPerSec))
                metricCard("TTFT", String(format: "%.0f ms", result.performance.ttftMs))
                metricCard("Total Tokens", "\(result.performance.totalTokens)")
                metricCard("Thermal", thermalStateText(result.system.after.thermalState))
                metricCard("Memory", String(format: "%.0f MB", result.system.after.memoryUsageMB))
                if let profile = result.aneProfile {
                    metricCard("ANE %", String(format: "%.1f%%", profile.anePercentage))
                    metricCard("ANE Ops", "\(profile.aneOps)/\(profile.totalOps)")
                }
            }

            // Per-turn results for multi-turn mode
            if let turns = result.turnResults, !turns.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Per-Turn Detail")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    ForEach(Array(turns.enumerated()), id: \.offset) { _, turn in
                        HStack {
                            Image(systemName: turn.role == "user" ? "person.fill" : "cpu")
                                .foregroundStyle(turn.role == "user" ? .blue : .green)
                                .frame(width: 20)

                            VStack(alignment: .leading, spacing: 2) {
                                if turn.role == "user" {
                                    Text("Prefill: \(turn.inputTokens) tok | \(String(format: "%.1f", turn.prefillTokensPerSec)) tok/s")
                                        .font(.caption)
                                } else {
                                    Text("Generated: \(turn.outputTokens) tok | \(String(format: "%.1f", turn.decodeTokensPerSec)) tok/s | TTFT: \(String(format: "%.0f", turn.ttftMs))ms")
                                        .font(.caption)
                                }
                                Text("KV pos: \(turn.kvCachePosition)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()
                        }
                    }
                }
                .padding(8)
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
            }

            Button("Show Detail") {
                showResultDetail = true
            }
            .sheet(isPresented: $showResultDetail) {
                ResultDetailView(result: result)
            }
        }
    }

    private func metricCard(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }

    private func thermalStateText(_ state: Int) -> String {
        switch state {
        case 0: return "Normal"
        case 1: return "Fair"
        case 2: return "Serious"
        case 3: return "Critical"
        default: return "Unknown"
        }
    }
}
