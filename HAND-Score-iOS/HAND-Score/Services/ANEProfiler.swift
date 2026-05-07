import Foundation
import CoreML

// ANE Compute Plan analyzer (iOS 17.4+).
// A Swift/iOS port of the Python ane_profiler.py utility.
struct ANEProfiler {

    // MARK: - Data model

    struct ProfileReport: Codable, Sendable {
        var components: [ComponentProfile] = []  // Per-component model profile
        var totalOps: Int = 0
        var aneOps: Int = 0
        var gpuOps: Int = 0
        var cpuOps: Int = 0
        var anePercentage: Double = 0.0
        var topCostOps: [OpCost] = []
        var aneBlockers: [String] = []
        var profilingTimeMs: Double = 0.0
    }

    struct ComponentProfile: Codable, Sendable {
        let name: String          // e.g., "gemma3_embeddings"
        let fileName: String      // e.g., "gemma3_embeddings.mlmodelc"
        var totalOps: Int = 0
        var aneOps: Int = 0
        var gpuOps: Int = 0
        var cpuOps: Int = 0
        var anePercentage: Double = 0.0
        var opsByDevice: [String: [String]] = [:]   // "ane" -> ["matmul:op1", ...]
        var opsByType: [String: Int] = [:]           // "conv" -> 5
    }

    struct OpCost: Codable, Sendable {
        let component: String
        let name: String
        let opType: String
        let weight: Double
    }

    // MARK: - Profiling entry point

    static func analyze(modelPath: URL) async -> ProfileReport? {
        let startTime = CFAbsoluteTimeGetCurrent()
        var report = ProfileReport()

        // Locate .mlmodelc files
        let fm = FileManager.default
        let mlmodelcFiles: [URL]

        // Files placed directly under the bundle root (flattened layout)
        if modelPath == Bundle.main.resourceURL {
            if let contents = try? fm.contentsOfDirectory(
                at: modelPath,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) {
                mlmodelcFiles = contents.filter { $0.pathExtension == "mlmodelc" }
            } else {
                mlmodelcFiles = []
            }
        } else {
            // Model living inside a subfolder
            if let contents = try? fm.contentsOfDirectory(
                at: modelPath,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) {
                mlmodelcFiles = contents.filter { $0.pathExtension == "mlmodelc" }
            } else {
                mlmodelcFiles = []
            }
        }

        guard !mlmodelcFiles.isEmpty else {
            print("[ANEProfiler] No .mlmodelc files found at: \(modelPath.path)")
            return nil
        }

        // Analyze each component
        for modelcURL in mlmodelcFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            if let componentProfile = await analyzeComponent(modelcURL) {
                report.components.append(componentProfile)
                report.totalOps += componentProfile.totalOps
                report.aneOps += componentProfile.aneOps
                report.gpuOps += componentProfile.gpuOps
                report.cpuOps += componentProfile.cpuOps
            }
        }

        // ANE percentage (over executable ops only)
        let executableOps = report.aneOps + report.gpuOps + report.cpuOps
        if executableOps > 0 {
            report.anePercentage = Double(report.aneOps) / Double(executableOps) * 100.0
        }

        // Identify ANE blockers
        report.aneBlockers = identifyBlockers(report)

        // Aggregate top-cost fallback operators (top 10)
        var allCosts: [OpCost] = []
        for component in report.components {
            // Treat GPU/CPU fallback operators as cost contributors
            for (device, ops) in component.opsByDevice {
                if device == "gpu" || device == "cpu" {
                    for op in ops {
                        let parts = op.components(separatedBy: ":")
                        let opType = parts.first ?? "unknown"
                        let opName = parts.count > 1 ? parts[1] : op
                        allCosts.append(OpCost(
                            component: component.name,
                            name: opName,
                            opType: opType,
                            weight: device == "cpu" ? 2.0 : 1.0  // CPU fallback weighted higher
                        ))
                    }
                }
            }
        }
        report.topCostOps = Array(allCosts.sorted { $0.weight > $1.weight }.prefix(10))

        report.profilingTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
        print("[ANEProfiler] Done: \(report.components.count) components, ANE \(String(format: "%.1f", report.anePercentage))%, \(String(format: "%.0f", report.profilingTimeMs))ms")

        return report
    }

    // MARK: - Component analysis

    private static func analyzeComponent(_ modelcURL: URL) async -> ComponentProfile? {
        let fileName = modelcURL.lastPathComponent
        let name = fileName.replacingOccurrences(of: ".mlmodelc", with: "")

        var profile = ComponentProfile(name: name, fileName: fileName)

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine

            let plan = try await MLComputePlan.load(
                contentsOf: modelcURL,
                configuration: config
            )

            let structure = plan.modelStructure

            // ML Program inspection (MLModelStructure is an enum)
            switch structure {
            case .program(let program):
                for function in program.functions.values {
                    analyzeBlock(function.block, plan: plan, profile: &profile)
                }
            default:
                break
            }

            // ANE percentage
            let executableOps = profile.aneOps + profile.gpuOps + profile.cpuOps
            if executableOps > 0 {
                profile.anePercentage = Double(profile.aneOps) / Double(executableOps) * 100.0
            }

            return profile
        } catch {
            print("[ANEProfiler] Component analysis failed (\(fileName)): \(error.localizedDescription)")
            return nil
        }
    }

    private static func analyzeBlock(
        _ block: MLModelStructure.Program.Block,
        plan: MLComputePlan,
        profile: inout ComponentProfile
    ) {
        for operation in block.operations {
            profile.totalOps += 1

            let opType = operation.operatorName
            profile.opsByType[opType, default: 0] += 1

            // Inspect device assignment
            if let deviceUsage = plan.deviceUsage(for: operation) {
                let device = deviceUsage.preferred
                let opName = outputName(for: operation) ?? opType

                switch device {
                case .cpu:
                    profile.cpuOps += 1
                    profile.opsByDevice["cpu", default: []].append("\(opType):\(opName)")
                case .gpu:
                    profile.gpuOps += 1
                    profile.opsByDevice["gpu", default: []].append("\(opType):\(opName)")
                case .neuralEngine:
                    profile.aneOps += 1
                    profile.opsByDevice["ane", default: []].append("\(opType):\(opName)")
                @unknown default:
                    break
                }
            }

            // Recurse into sub-blocks (control-flow operations)
            for subBlock in operation.blocks {
                analyzeBlock(subBlock, plan: plan, profile: &profile)
            }
        }
    }

    private static func outputName(for operation: MLModelStructure.Program.Operation) -> String? {
        let outputs = operation.outputs
        if let first = outputs.first {
            return first.name
        }
        return nil
    }

    // MARK: - ANE blocker classification

    private static func identifyBlockers(_ report: ProfileReport) -> [String] {
        var blockers: [String] = []

        let knownBlockers: [String: String] = [
            "while_loop": "dynamic control flow",
            "cond": "dynamic control flow",
            "select": "dynamic control flow",
            "cast": "data-type conversion",
            "gather": "dynamic indexing",
            "scatter": "dynamic indexing",
        ]

        for component in report.components {
            for (opType, count) in component.opsByType {
                if let reason = knownBlockers[opType] {
                    blockers.append("\(component.name): \(opType) (\(count)x) - \(reason)")
                }
            }

            // CPU fallback operators
            if let cpuOps = component.opsByDevice["cpu"], !cpuOps.isEmpty {
                blockers.append("\(component.name): CPU fallback in \(cpuOps.count) operators")
            }
        }

        return blockers
    }
}
