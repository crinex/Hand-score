import SwiftUI

struct ResultDetailView: View {
    let result: BenchmarkResult
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Device info
                Section("Device") {
                    row("Model", result.device.name)
                    row("Chipset", result.device.chip)
                    row("iOS", result.device.osVersion)
                    row("Identifier", result.device.model)
                }

                // Model info
                Section("Model") {
                    row("Name", result.model.name)
                    row("Context Length", "\(result.model.contextLength)")
                    row("Batch Size", "\(result.model.batchSize)")
                    row("Monolithic", result.model.isMonolithic ? "Yes" : "No")
                }

                // Benchmark configuration
                Section("Configuration") {
                    row("Prompt", result.config.prompt)
                    row("Max Tokens", "\(result.config.maxTokens)")
                    row("Temperature", String(format: "%.1f", result.config.temperature))
                }

                // Inference performance
                Section("Inference Performance") {
                    row("Model Load Time", String(format: "%.0f ms", result.performance.modelLoadTimeMs))
                    row("Prefill Time", String(format: "%.0f ms", result.performance.prefillTimeMs))
                    row("Prefill Tokens", "\(result.performance.prefillTokens)")
                    row("Prefill TPS", String(format: "%.1f tok/s", result.performance.prefillTokensPerSec))
                    row("Decode Tokens", "\(result.performance.decodeTokens)")
                    row("Decode Time", String(format: "%.0f ms", result.performance.decodeTimeMs))
                    row("Decode TPS", String(format: "%.1f tok/s", result.performance.decodeTokensPerSec))
                    row("TTFT", String(format: "%.0f ms", result.performance.ttftMs))
                    row("Total Tokens", "\(result.performance.totalTokens)")
                    row("Total Time", String(format: "%.1f s", result.performance.totalTimeMs / 1000.0))
                }

                // System metrics (Before)
                Section("System (Before)") {
                    row("Battery", String(format: "%.0f%%", result.system.before.batteryLevel * 100))
                    row("Battery State", result.system.before.batteryState)
                    row("Memory Used", String(format: "%.0f MB", result.system.before.memoryUsageMB))
                    row("Memory Available", String(format: "%.0f MB", result.system.before.availableMemoryMB))
                    row("Thermal", thermalText(result.system.before.thermalState))
                }

                // System metrics (After)
                Section("System (After)") {
                    row("Battery", String(format: "%.0f%%", result.system.after.batteryLevel * 100))
                    row("Battery State", result.system.after.batteryState)
                    row("Memory Used", String(format: "%.0f MB", result.system.after.memoryUsageMB))
                    row("Memory Available", String(format: "%.0f MB", result.system.after.availableMemoryMB))
                    row("Thermal", thermalText(result.system.after.thermalState))
                }

                // Timeline summary
                if !result.system.timeline.isEmpty {
                    Section("Timeline (\(result.system.timeline.count) samples)") {
                        let maxMem = result.system.timeline.map(\.memoryUsageMB).max() ?? 0
                        let maxCPU = result.system.timeline.map(\.cpuUsagePercent).max() ?? 0
                        let maxThermal = result.system.timeline.map(\.thermalState).max() ?? 0

                        row("Peak Memory", String(format: "%.0f MB", maxMem))
                        row("Peak CPU", String(format: "%.1f%%", maxCPU))
                        row("Max Thermal", thermalText(maxThermal))
                    }
                }

                // ANE profile
                if let profile = result.aneProfile {
                    Section("ANE Profile") {
                        aneRatioBar(ane: profile.aneOps, gpu: profile.gpuOps, cpu: profile.cpuOps)
                        row("ANE Ratio", String(format: "%.1f%%", profile.anePercentage))
                        row("Total Ops", "\(profile.totalOps)")
                        row("ANE", "\(profile.aneOps)")
                        row("GPU", "\(profile.gpuOps)")
                        row("CPU", "\(profile.cpuOps)")
                        row("Components", "\(profile.components.count)")
                        row("Profiling Time", String(format: "%.0f ms", profile.profilingTimeMs))
                    }

                    // Per-component detail
                    if profile.components.count > 1 {
                        Section("Per-Component ANE Ratio") {
                            ForEach(profile.components, id: \.name) { comp in
                                HStack {
                                    Text(comp.name)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(String(format: "%.0f%%", comp.anePercentage))
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundStyle(comp.anePercentage >= 80 ? .green : comp.anePercentage >= 50 ? .orange : .red)
                                }
                            }
                        }
                    }

                    // ANE blockers
                    if !profile.aneBlockers.isEmpty {
                        Section("ANE Blockers") {
                            ForEach(profile.aneBlockers, id: \.self) { blocker in
                                Text(blocker)
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    // Top-cost fallback ops
                    if !profile.topCostOps.isEmpty {
                        Section("Fallback Operators (by cost)") {
                            ForEach(Array(profile.topCostOps.enumerated()), id: \.offset) { _, op in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(op.name)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                        Text("\(op.component) / \(op.opType)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(String(format: "%.1f", op.weight))
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                    }
                }

                // Generated output
                Section("Generated Output") {
                    Text(result.generatedText)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            .navigationTitle("Result Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    ShareLink(item: jsonString) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func aneRatioBar(ane: Int, gpu: Int, cpu: Int) -> some View {
        let total = max(ane + gpu + cpu, 1)
        let aneFrac = CGFloat(ane) / CGFloat(total)
        let gpuFrac = CGFloat(gpu) / CGFloat(total)
        let cpuFrac = CGFloat(cpu) / CGFloat(total)

        return VStack(spacing: 4) {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geo.size.width * aneFrac)
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: geo.size.width * gpuFrac)
                    Rectangle()
                        .fill(Color.red)
                        .frame(width: geo.size.width * cpuFrac)
                }
                .cornerRadius(4)
            }
            .frame(height: 12)

            HStack(spacing: 12) {
                Label("ANE \(ane)", systemImage: "circle.fill").foregroundStyle(.green)
                Label("GPU \(gpu)", systemImage: "circle.fill").foregroundStyle(.blue)
                Label("CPU \(cpu)", systemImage: "circle.fill").foregroundStyle(.red)
            }
            .font(.caption2)
        }
        .padding(.vertical, 4)
    }

    private func thermalText(_ state: Int) -> String {
        switch state {
        case 0: return "Normal"
        case 1: return "Fair"
        case 2: return "Serious"
        case 3: return "Critical"
        default: return "Unknown"
        }
    }

    private var jsonString: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(result) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
