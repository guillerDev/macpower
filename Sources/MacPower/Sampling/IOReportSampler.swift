import CIOReport
import Foundation

/// One interval's worth of energy readings, already converted to watts.
struct EnergyReading {
    /// Aggregate rails.
    var cpuWatts: Double = 0
    var gpuWatts: Double = 0
    var aneWatts: Double = 0
    var dramWatts: Double = 0
    /// Per physical CPU core, in the natural cluster order (E cores first).
    var coreWatts: [CorePower] = []
    /// Where `cpuWatts` and `coreWatts` come from.
    var cpuSource: CPUPowerSource = .measured
    /// macOS is batching the CPU/ANE/DRAM energy counters (macOS 27+), so ANE and
    /// DRAM show the average over the latest batch rather than live values.
    var batched = false
    /// Batched, and no batch has landed since launch: ANE/DRAM have no data yet.
    var awaitingBatch = false

    var socWatts: Double { cpuWatts + gpuWatts + aneWatts + dramWatts }
}

enum CPUPowerSource: Equatable {
    /// Straight from the SoC energy counters (they update every tick).
    case measured
    /// Modelled from per-core frequency/voltage residency (`CorePowerModel`);
    /// `calibrated` once fitted against a batch of real counter data on this chip.
    case estimated(calibrated: Bool)
    /// Batched counters and no model available: the average over the latest batch.
    case batchAverage
}

struct CorePower: Identifiable {
    let id: Int  // logical index within `coreWatts`
    let label: String  // e.g. "E0", "P3"
    let cluster: CPUCluster
    let watts: Double
}

enum CPUCluster: String { case efficiency = "E", performance = "P" }

/// Reads Apple Silicon SoC energy counters via the private IOReport API.
/// Requires no elevated privileges. Not thread-safe; call `sample()` from one
/// queue.
///
/// Power is each counter's energy delta over the time between *its own* updates,
/// from the element timestamps — not over our sampling tick. Through macOS 26 the
/// counters update continuously, so the two match. macOS 27 batches the CPU, ANE
/// and DRAM counters minutes apart: per tick they read 0 W, and one batch divided
/// by a single tick would read as thousands of watts.
final class IOReportSampler {
    struct Sample {
        var reading: EnergyReading
        /// Exact per-core-type energy for a batch that landed this tick (batched
        /// counters only), for calibrating `CorePowerModel`.
        var batch: CorePowerModel.Batch?
    }

    private struct Counter {
        var value: Int64
        var timestamp: UInt64  // mach_absolute_time of the counter's last update
    }

    /// Counters updating less often than this are batched (macOS 27 batches are
    /// minutes apart) rather than live. Well above the longest sampling interval.
    static let liveUpdateLimit: TimeInterval = 30

    private let subscription: OpaquePointer
    private let subscribedChannels: CFMutableDictionary
    private var counters: [String: Counter] = [:]
    /// Latest watts per channel, over that channel's most recent update interval.
    private var watts: [String: Double] = [:]
    /// Seconds between the last two "CPU Energy" updates; nil until one is seen.
    private var cpuUpdateInterval: TimeInterval?
    /// Per-core channel names that carried non-zero cumulative energy at launch.
    /// Binned chips expose slots for fused-off cores that read zero forever;
    /// tracking the live set filters them out.
    private var activeCoreNames: Set<String> = []

    init?() {
        // The "Energy Model" group carries every SoC energy rail we need.
        guard let raw = IOReportCopyChannelsInGroup("Energy Model" as CFString, nil, 0, 0, 0),
            let channels = CFDictionaryCreateMutableCopy(nil, 0, raw)
        else { return nil }

        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = IOReportCreateSubscription(nil, channels, &subbed, 0, nil), let subbed else {
            return nil
        }
        subscription = sub
        subscribedChannels = subbed.takeRetainedValue()

        // Prime the counters and learn which cores are physically present.
        guard let initial = IOReportCreateSamples(sub, subscribedChannels, nil) else { return }
        let now = mach_absolute_time()
        IOReportIterate(initial) { channel in
            guard let channel, let name = IOReportChannelGetChannelName(channel) as String? else { return 0 }
            let value = IOReportSimpleGetIntegerValue(channel, nil)
            self.counters[name] = Counter(value: value, timestamp: Self.timestamp(of: channel) ?? now)
            switch Self.classify(name) {
            case .eCore, .pCore: if value > 0 { self.activeCoreNames.insert(name) }
            default: break
            }
            return 0
        }
    }

    /// Latest power per rail. Counters that didn't update since the previous call
    /// keep their last value (between macOS 27 batches: the latest batch average).
    func sample() -> Sample? {
        guard let current = IOReportCreateSamples(subscription, subscribedChannels, nil) else { return nil }
        let now = mach_absolute_time()
        var joules: [String: Double] = [:]  // channels that updated this tick
        var cpuAge: TimeInterval = 0

        IOReportIterate(current) { channel in
            guard let channel, let name = IOReportChannelGetChannelName(channel) as String? else { return 0 }
            let value = IOReportSimpleGetIntegerValue(channel, nil)
            // Without a readable timestamp, fall back to treating every read as an update.
            let stamp = Self.timestamp(of: channel) ?? now
            let previous = self.counters[name]
            self.counters[name] = Counter(value: value, timestamp: stamp)
            if name == "CPU Energy", now > stamp { cpuAge = Self.seconds(now - stamp) }

            guard let previous, stamp > previous.timestamp else { return 0 }
            let seconds = Self.seconds(stamp - previous.timestamp)
            let unit = IOReportChannelGetUnitLabel(channel) as String? ?? "mJ"
            let energy = Self.nanojoules(Double(value - previous.value), unit: unit) / 1e9
            joules[name] = energy
            self.watts[name] = energy / seconds
            if name == "CPU Energy" { self.cpuUpdateInterval = seconds }
            return 0
        }

        let batched = Self.isBatched(lastUpdateInterval: cpuUpdateInterval, age: cpuAge)
        var batch: CorePowerModel.Batch?
        if batched, let interval = cpuUpdateInterval, let cpuJoules = joules["CPU Energy"] {
            var e = 0.0
            var p = 0.0
            for (name, energy) in joules where activeCoreNames.contains(name) {
                if case .eCore = Self.classify(name) { e += energy } else { p += energy }
            }
            batch = CorePowerModel.Batch(
                interval: interval, eCoreJoules: e, pCoreJoules: p, cpuJoules: cpuJoules)
        }
        return Sample(reading: reading(batched: batched), batch: batch)
    }

    /// Batched when the last CPU update interval was long, or — before any update
    /// has been seen — when the current value is already stale.
    static func isBatched(lastUpdateInterval: TimeInterval?, age: TimeInterval) -> Bool {
        (lastUpdateInterval ?? age) > liveUpdateLimit
    }

    // MARK: - Assembly

    private func reading(batched: Bool) -> EnergyReading {
        var result = EnergyReading()
        result.batched = batched
        result.awaitingBatch = batched && !watts.keys.contains { Self.classify($0) == .dram }
        result.cpuSource = batched ? .batchAverage : .measured
        var eCores: [(Int, Double)] = []  // (core index, watts)
        var pCores: [(cluster: Int, core: Int, watts: Double)] = []

        for (name, w) in watts {
            switch Self.classify(name) {
            case .cpuTotal: result.cpuWatts = w
            case .gpuTotal: result.gpuWatts = w
            case .ane: result.aneWatts += w
            case .dram: result.dramWatts += w
            case .eCore(let i): if activeCoreNames.contains(name) { eCores.append((i, w)) }
            case .pCore(let c, let i): if activeCoreNames.contains(name) { pCores.append((c, i, w)) }
            case .ignore: break
            }
        }

        // Assemble cores in a stable order: E cores, then P cores by cluster.
        var cores: [CorePower] = []
        for (i, w) in eCores.sorted(by: { $0.0 < $1.0 }) {
            cores.append(CorePower(id: cores.count, label: "E\(i)", cluster: .efficiency, watts: w))
        }
        for entry in pCores.sorted(by: { ($0.cluster, $0.core) < ($1.cluster, $1.core) }) {
            cores.append(
                CorePower(
                    id: cores.count, label: "P\(cores.count - eCores.count)",
                    cluster: .performance, watts: entry.watts))
        }
        result.coreWatts = cores
        return result
    }

    // MARK: - Element timestamps

    /// mach_absolute_time of the channel's last update, read from its raw element
    /// (IOKit's IOReportTypes.h: a packed 64-byte IOReportElement with the
    /// timestamp at byte offset 24).
    private static func timestamp(of channel: CFDictionary) -> UInt64? {
        guard let raw = (channel as NSDictionary)["RawElements"] as? Data, raw.count >= 32 else { return nil }
        return raw.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 24, as: UInt64.self) }
    }

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func seconds(_ ticks: UInt64) -> TimeInterval {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }

    // MARK: - Channel classification

    // Internal (not private) so the pure-logic unit tests can exercise it.
    enum Kind: Equatable {
        case cpuTotal, gpuTotal, ane, dram
        case eCore(Int)
        case pCore(cluster: Int, core: Int)
        case ignore
    }

    static func classify(_ name: String) -> Kind {
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
        return Int(suffix)  // nil for cluster sums (empty / non-numeric suffix)
    }

    static func nanojoules(_ value: Double, unit: String) -> Double {
        switch unit {
        case "mJ": return value * 1_000_000
        case "uJ", "µJ": return value * 1_000
        case "nJ": return value
        case "J": return value * 1_000_000_000
        default: return value * 1_000_000  // assume mJ
        }
    }
}
