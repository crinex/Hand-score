import Foundation
#if canImport(UIKit)
import UIKit
#endif

// System-metric collector (1-second Timer)
final class MetricsCollector: @unchecked Sendable {
    private var timer: Timer?
    private var samples: [MetricsSample] = []
    private var startTime: CFAbsoluteTime = 0

    func start() {
        samples.removeAll()
        startTime = CFAbsoluteTimeGetCurrent()

        // Take the first sample immediately
        collectSample()

        // 1-second periodic timer
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.collectSample()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() -> [MetricsSample] {
        timer?.invalidate()
        timer = nil
        // Take the final sample
        collectSample()
        return samples
    }

    private func collectSample() {
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let sample = MetricsSample(
            timestamp: elapsed,
            memoryUsageMB: Self.currentMemoryUsageMB(),
            availableMemoryMB: Self.availableMemoryMB(),
            cpuUsagePercent: Self.cpuUsagePercent(),
            thermalState: Self.currentThermalState()
        )
        samples.append(sample)
    }

    // MARK: - System snapshot

    static func takeSnapshot() -> SystemSnapshot {
        #if canImport(UIKit) && !targetEnvironment(simulator)
        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true
        let batteryLevel = device.batteryLevel
        let batteryState = batteryStateString(device.batteryState)
        #else
        let batteryLevel: Float = -1.0
        let batteryState = "simulator"
        #endif

        return SystemSnapshot(
            batteryLevel: batteryLevel,
            batteryState: batteryState,
            memoryUsageMB: currentMemoryUsageMB(),
            availableMemoryMB: availableMemoryMB(),
            thermalState: currentThermalState()
        )
    }

    // MARK: - Memory measurement

    static func currentMemoryUsageMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / (1024 * 1024)
    }

    static func availableMemoryMB() -> Double {
        return Double(os_proc_available_memory()) / (1024 * 1024)
    }

    // MARK: - CPU measurement

    static func cpuUsagePercent() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0

        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else {
            return 0
        }

        var totalUsage: Double = 0
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info_data_t()
            var infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &infoCount)
                }
            }
            if result == KERN_SUCCESS && info.flags & TH_FLAGS_IDLE == 0 {
                totalUsage += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }

        let size = vm_size_t(Int(threadCount) * MemoryLayout<thread_t>.size)
        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: threads), size)

        return totalUsage
    }

    // MARK: - Thermal State

    static func currentThermalState() -> Int {
        return ProcessInfo.processInfo.thermalState.rawValue
    }

    // MARK: - Battery state

    #if canImport(UIKit)
    static func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .unknown: return "unknown"
        case .unplugged: return "unplugged"
        case .charging: return "charging"
        case .full: return "full"
        @unknown default: return "unknown"
        }
    }
    #endif
}
