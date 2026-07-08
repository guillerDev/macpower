import Foundation
import CIOReport

/// One interval's worth of energy readings, already converted to watts.
struct EnergyReading {
    /// Aggregate rails.
    var cpuWatts: Double = 0
    var gpuWatts: Double = 0
    var aneWatts: Double = 0
    var dramWatts: Double = 0
    /// Per physical CPU core, in the natural cluster order (E cores first).
    var coreWatts: [CorePower] = []

    var socWatts: Double { cpuWatts + gpuWatts + aneWatts + dramWatts }
}

struct CorePower: Identifiable {
    let id: Int          // logical index within `coreWatts`
    let label: String    // e.g. "E0", "P3"
    let cluster: CPUCluster
    let watts: Double
}

enum CPUCluster: String { case efficiency = "E", performance = "P" }

/// Reads Apple Silicon SoC energy counters via the private IOReport API.
/// Requires no elevated privileges. Not thread-safe; call `sample()` from one
/// queue.
final class IOReportSampler {
    private let subscription: OpaquePointer?
    private let subscribedChannels: CFMutableDictionary?
    private var previousSample: CFDictionary?
    private var lastSampleTime: ContinuousClock.Instant?
    private let clock = ContinuousClock()
    /// Per-core channel names that carried non-zero cumulative energy at launch.
    /// Binned chips expose slots for fused-off cores that read zero forever;
    /// tracking the live set filters them out.
    private var activeCoreNames: Set<String> = []

    /// Cumulative energy in nanojoules keyed by channel name, harvested from the
    /// most recent delta pass.
    init?() {
        // The "Energy Model" group carries every SoC energy rail we need.
        guard let raw = IOReportCopyChannelsInGroup("Energy Model" as CFString,
                                                    nil, 0, 0, 0) else {
            return nil
        }
        guard let channels = CFDictionaryCreateMutableCopy(nil, 0, raw) else {
            return nil
        }

        var subbed: Unmanaged<CFMutableDictionary>?
        let sub = IOReportCreateSubscription(nil, channels, &subbed, 0, nil)
        guard let sub, let subbed else { return nil }

        self.subscription = sub
        let subbedChannels = subbed.takeRetainedValue()
        self.subscribedChannels = subbedChannels

        // Prime the counters and learn which cores are physically present.
        if let initial = IOReportCreateSamples(sub, subbedChannels, nil) {
            IOReportIterate(initial) { channel in
                guard let channel,
                      let name = IOReportChannelGetChannelName(channel) as String? else { return 0 }
                if case .eCore = Self.classify(name), IOReportSimpleGetIntegerValue(channel, nil) > 0 {
                    self.activeCoreNames.insert(name)
                } else if case .pCore = Self.classify(name), IOReportSimpleGetIntegerValue(channel, nil) > 0 {
                    self.activeCoreNames.insert(name)
                }
                return 0
            }
            previousSample = initial
            lastSampleTime = clock.now
        }
    }

    /// Take a new sample and return the power drawn since the previous call.
    /// The first call primes the counters and returns `nil`.
    func sample() -> EnergyReading? {
        let now = clock.now
        guard let current = IOReportCreateSamples(subscription, subscribedChannels, nil) else {
            return nil
        }

        defer {
            previousSample = current
            lastSampleTime = now
        }

        guard let previous = previousSample,
              let last = lastSampleTime,
              let delta = IOReportCreateSamplesDelta(previous, current, nil) else {
            return nil
        }

        let seconds = last.duration(to: now).inSeconds
        guard seconds > 0 else { return nil }

        return reading(from: delta, seconds: seconds)
    }

    // MARK: - Delta decoding

    private func reading(from delta: CFDictionary, seconds: Double) -> EnergyReading {
        var result = EnergyReading()
        var eCores: [(Int, Double)] = []      // (core index, watts)
        var pCores: [(cluster: Int, core: Int, watts: Double)] = []

        IOReportIterate(delta) { channel in
            guard let channel,
                  let name = IOReportChannelGetChannelName(channel) as String? else {
                return 0
            }
            let unit = IOReportChannelGetUnitLabel(channel) as String? ?? "mJ"
            let rawValue = IOReportSimpleGetIntegerValue(channel, nil)
            let watts = Self.nanojoules(Double(rawValue), unit: unit) / seconds / 1e9

            switch Self.classify(name) {
            case .cpuTotal:  result.cpuWatts = watts
            case .gpuTotal:  result.gpuWatts = watts
            case .ane:       result.aneWatts += watts
            case .dram:      result.dramWatts += watts
            case .eCore(let i): if self.activeCoreNames.contains(name) { eCores.append((i, watts)) }
            case .pCore(let c, let i): if self.activeCoreNames.contains(name) { pCores.append((c, i, watts)) }
            case .ignore:    break
            }
            return 0
        }

        // Assemble cores in a stable order: E cores, then P cores by cluster.
        var cores: [CorePower] = []
        for (i, w) in eCores.sorted(by: { $0.0 < $1.0 }) {
            cores.append(CorePower(id: cores.count, label: "E\(i)", cluster: .efficiency, watts: w))
        }
        for entry in pCores.sorted(by: { ($0.cluster, $0.core) < ($1.cluster, $1.core) }) {
            cores.append(CorePower(id: cores.count, label: "P\(cores.count - eCores.count)",
                                   cluster: .performance, watts: entry.watts))
        }
        result.coreWatts = cores
        return result
    }

    // MARK: - Channel classification

    private enum Kind {
        case cpuTotal, gpuTotal, ane, dram
        case eCore(Int)
        case pCore(cluster: Int, core: Int)
        case ignore
    }

    private static func classify(_ name: String) -> Kind {
        switch name {
        case "CPU Energy": return .cpuTotal
        case "GPU Energy": return .gpuTotal
        default: break
        }
        if name.hasPrefix("ANE") { return .ane }
        if name.hasPrefix("DRAM") { return .dram }

        // Per-core: EACC_CPU<n> (efficiency) or PACC<c>_CPU<n> (performance).
        // Cluster sums like "EACC_CPU", "EACC_CPM", "PACC0_CPU" have no trailing
        // core digit and must be ignored to avoid double counting.
        if let core = parseCore(name, prefix: "EACC_CPU") {
            return .eCore(core)
        }
        if name.hasPrefix("PACC"), let underscore = name.range(of: "_CPU") {
            let clusterPart = name[name.index(name.startIndex, offsetBy: 4)..<underscore.lowerBound]
            let corePart = name[underscore.upperBound...]
            if let cluster = Int(clusterPart), let core = Int(corePart) {
                return .pCore(cluster: cluster, core: core)
            }
        }
        return .ignore
    }

    private static func parseCore(_ name: String, prefix: String) -> Int? {
        guard name.hasPrefix(prefix) else { return nil }
        let suffix = name.dropFirst(prefix.count)
        return Int(suffix)   // nil for cluster sums (empty / non-numeric suffix)
    }

    private static func nanojoules(_ value: Double, unit: String) -> Double {
        switch unit {
        case "mJ": return value * 1_000_000
        case "uJ", "µJ": return value * 1_000
        case "nJ": return value
        case "J":  return value * 1_000_000_000
        default:   return value * 1_000_000   // assume mJ
        }
    }
}

