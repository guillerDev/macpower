import Foundation
import Darwin

struct ProcessSample: Identifiable {
    let id: pid_t
    let name: String
    let cpuPercent: Double     // % of a single core (can exceed 100 when multithreaded)
    let energyImpact: Double   // approximate, Activity-Monitor-style score
    let idleWakeups: Double     // per second
}

/// Approximates per-process energy usage without root by tracking the delta of
/// each process's CPU time and idle wake-ups between calls. This mirrors the
/// signals Activity Monitor blends into its "Energy Impact" column; it is an
/// estimate, not the exact figure `powermetrics` would report.
final class ProcessSampler {
    private struct Prev { var cpuNanos: UInt64; var wakeups: UInt64 }
    private var previous: [pid_t: Prev] = [:]
    private var lastTime: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    func sample(limit: Int = 200) -> [ProcessSample] {
        let now = clock.now
        defer { lastTime = now }

        let pids = currentPIDs()
        var seconds = 1.0
        if let last = lastTime { seconds = max(last.duration(to: now).inSeconds, 0.001) }

        var current: [pid_t: Prev] = [:]
        current.reserveCapacity(pids.count)
        var samples: [ProcessSample] = []

        for pid in pids where pid > 0 {
            guard let usage = rusage(for: pid) else { continue }
            let cpuNanos = usage.ri_user_time + usage.ri_system_time
            let wakeups = usage.ri_pkg_idle_wkups + usage.ri_interrupt_wkups
            current[pid] = Prev(cpuNanos: cpuNanos, wakeups: wakeups)

            guard let prev = previous[pid] else { continue }   // new process this tick
            let cpuDelta = Double(cpuNanos &- prev.cpuNanos) / 1e9        // CPU seconds
            let wakeDelta = Double(wakeups &- prev.wakeups)
            let cpuPercent = max(0, cpuDelta / seconds * 100)
            let wakesPerSec = max(0, wakeDelta / seconds)
            // Weight roughly like Activity Monitor: CPU dominates, wake-ups add a
            // small idle-power penalty.
            let impact = cpuPercent + wakesPerSec * 0.02
            guard impact > 0.01 else { continue }

            samples.append(ProcessSample(id: pid,
                                         name: name(for: pid),
                                         cpuPercent: cpuPercent,
                                         energyImpact: impact,
                                         idleWakeups: wakesPerSec))
        }

        previous = current
        return Array(samples.sorted { $0.energyImpact > $1.energyImpact }.prefix(limit))
    }

    // MARK: - libproc plumbing

    private func currentPIDs() -> [pid_t] {
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        let count = Int(needed) / MemoryLayout<pid_t>.stride
        var pids = [pid_t](repeating: 0, count: count)
        let written = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, needed)
        guard written > 0 else { return [] }
        let n = Int(written) / MemoryLayout<pid_t>.stride
        return Array(pids.prefix(n))
    }

    private func rusage(for pid: pid_t) -> rusage_info_v4? {
        var usage = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &usage) { ptr -> Int32 in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reb in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, reb)
            }
        }
        return rc == 0 ? usage : nil
    }

    private func name(for pid: pid_t) -> String {
        let pathMax = 4096   // PROC_PIDPATHINFO_MAXSIZE
        var pathBuf = [UInt8](repeating: 0, count: pathMax)
        let len = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        if len > 0 {
            let path = decode(pathBuf)
            if let last = path.split(separator: "/").last { return String(last) }
        }
        var nameBuf = [UInt8](repeating: 0, count: 33)   // 2*MAXCOMLEN+1
        if proc_name(pid, &nameBuf, UInt32(nameBuf.count)) > 0 {
            return decode(nameBuf)
        }
        return "PID \(pid)"
    }

    private func decode(_ buffer: [UInt8]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}
