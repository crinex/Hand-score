import Foundation

// System-metric snapshot taken once per second
struct MetricsSample: Codable, Sendable {
    let timestamp: TimeInterval      // seconds elapsed since the start of the benchmark
    let memoryUsageMB: Double        // task_vm_info phys_footprint
    let availableMemoryMB: Double    // os_proc_available_memory()
    let cpuUsagePercent: Double      // sum of thread_basic_info usage
    let thermalState: Int            // ProcessInfo.thermalState rawValue
}

// Snapshot used for pre/post-inference comparison
struct SystemSnapshot: Codable, Sendable {
    let batteryLevel: Float          // 0.0 ~ 1.0
    let batteryState: String         // unknown, unplugged, charging, full
    let memoryUsageMB: Double
    let availableMemoryMB: Double
    let thermalState: Int
}

// Time series + pre/post snapshots combined
struct SystemMetricsReport: Codable, Sendable {
    let before: SystemSnapshot
    let after: SystemSnapshot
    let timeline: [MetricsSample]
}
