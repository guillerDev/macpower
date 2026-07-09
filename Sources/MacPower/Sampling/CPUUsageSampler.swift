import Darwin
import Foundation

/// Per-logical-core CPU utilisation via `host_processor_info`. No privileges
/// required. Utilisation is computed from the delta of cumulative CPU ticks
/// between successive calls.
final class CPUUsageSampler {
    private var previousTicks: [[UInt32]] = []

    struct Usage {
        let perCore: [Double]  // 0...1 per logical core
        var overall: Double { perCore.isEmpty ? 0 : perCore.reduce(0, +) / Double(perCore.count) }
    }

    /// Returns per-core busy ratios, or `nil` on the priming call / on error.
    func sample() -> Usage? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &count, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return nil }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let cpuCount = Int(count)
        var current: [[UInt32]] = []
        current.reserveCapacity(cpuCount)

        info.withMemoryRebound(to: UInt32.self, capacity: cpuCount * Int(CPU_STATE_MAX)) { ptr in
            for cpu in 0..<cpuCount {
                let base = cpu * Int(CPU_STATE_MAX)
                current.append([
                    ptr[base + Int(CPU_STATE_USER)],
                    ptr[base + Int(CPU_STATE_SYSTEM)],
                    ptr[base + Int(CPU_STATE_IDLE)],
                    ptr[base + Int(CPU_STATE_NICE)],
                ])
            }
        }

        defer { previousTicks = current }
        guard previousTicks.count == cpuCount else { return nil }

        var perCore: [Double] = []
        perCore.reserveCapacity(cpuCount)
        for cpu in 0..<cpuCount {
            let prev = previousTicks[cpu]
            let cur = current[cpu]
            let user = Double(cur[0] &- prev[0])
            let system = Double(cur[1] &- prev[1])
            let idle = Double(cur[2] &- prev[2])
            let nice = Double(cur[3] &- prev[3])
            let busy = user + system + nice
            let total = busy + idle
            perCore.append(total > 0 ? busy / total : 0)
        }
        return Usage(perCore: perCore)
    }
}
