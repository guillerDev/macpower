import Foundation

/// One DVFS table from the IORegistry `pmgr` node: frequency and core voltage per
/// performance state, lowest state first.
struct DVFSTable: Equatable {
    let megahertz: [Double]
    let millivolts: [Double]

    var count: Int { megahertz.count }
    var maxMegahertz: Double { megahertz.max() ?? 0 }

    /// Decodes `voltage-statesN-sram` (frequency, voltage) pairs of little-endian
    /// UInt32s. Core voltages come from the matching non-SRAM `voltage-statesN`
    /// table when present (its second field); otherwise the SRAM voltages are used.
    /// Frequencies are Hz on M1-era chips; values that look like kHz are accepted too.
    static func parse(frequencies: Data, voltages: Data?) -> DVFSTable? {
        let freqPairs = pairs(frequencies)
        guard !freqPairs.isEmpty else { return nil }
        let mhz = freqPairs.map { Double($0.0) >= 10_000_000 ? Double($0.0) / 1e6 : Double($0.0) / 1e3 }
        // A CPU table rises monotonically and tops out well above 100 MHz.
        guard zip(mhz, mhz.dropFirst()).allSatisfy({ $0 <= $1 }), (mhz.last ?? 0) > 100 else { return nil }

        var mv = freqPairs.map { Double($0.1) }
        if let voltages {
            let core = pairs(voltages)
            if core.count == freqPairs.count { mv = core.map { Double($0.1) } }
        }
        return DVFSTable(megahertz: mhz, millivolts: mv)
    }

    private static func pairs(_ data: Data) -> [(UInt32, UInt32)] {
        let words = data.withUnsafeBytes { raw in
            (0..<raw.count / 4).map { raw.loadUnaligned(fromByteOffset: $0 * 4, as: UInt32.self) }
        }
        return stride(from: 0, to: words.count - 1, by: 2).map { (words[$0], words[$0 + 1]) }
    }
}

/// One core's DVFS activity over a sampling tick.
struct CoreActivity: Equatable {
    let label: String  // "E0", "P3"
    let cluster: CPUCluster
    /// Σ over performance states of seconds × GHz × V² — proportional to the
    /// dynamic energy the core used during the tick.
    let activity: Double
}

/// Per-core CPU power model for when macOS batches its energy counters (macOS 27
/// refreshes them only every several minutes, so per-tick deltas are zero).
///
/// Each core's dynamic power is modelled as `k × f × V²`, integrated over the time
/// it spent in each performance state. One constant per core type (E/P) plus a
/// cluster-overhead ratio are fitted against every batch macOS delivers, so the
/// estimate calibrates itself to this Mac; the fit persists across launches.
struct CorePowerModel {
    struct Calibration: Codable, Equatable {
        /// W per (GHz·V²) for efficiency and performance cores.
        var kE: Double
        var kP: Double
        /// Cluster energy outside the cores (the CPM rails), as a fraction of core energy.
        var overhead: Double
        /// Batches fitted so far; 0 means still on the built-in defaults.
        var batches: Int

        /// Starting point until this chip's first batch: fitted on an M1 Pro (macOS 27,
        /// a 31-minute batch; per-core error ±11%). Other chips calibrate from here.
        static let defaults = Calibration(kE: 0.08, kP: 0.58, overhead: 0.24, batches: 0)
    }

    /// Exact energy for one batch interval, as reported by macOS's counters.
    struct Batch {
        let interval: TimeInterval
        let eCoreJoules: Double
        let pCoreJoules: Double
        let cpuJoules: Double  // all CPU clusters, including overhead
    }

    private(set) var calibration: Calibration
    private var eActivity = 0.0
    private var pActivity = 0.0
    /// Seconds of ticks accumulated since the last batch.
    private var covered: TimeInterval = 0
    /// A tick gap (sleep, stall) makes the extrapolation below unreliable.
    private var hadGap = false

    /// Weight of each new batch fit once calibrated (smooths workload noise).
    static let blendWeight = 0.3
    /// Minimum share of a batch interval we must have sampled to fit it.
    static let minCoverage = 0.2
    /// A tick longer than this means the Mac slept or sampling stalled.
    static let maxTick: TimeInterval = 10

    init(calibration: Calibration = .defaults) {
        self.calibration = calibration
    }

    var isCalibrated: Bool { calibration.batches > 0 }

    /// Per-core watts for one tick, plus the CPU total (cores + cluster overhead).
    /// Also accumulates the tick toward the next calibration.
    mutating func estimate(_ cores: [CoreActivity], seconds: TimeInterval) -> (
        cores: [Double], cpuWatts: Double
    ) {
        guard seconds > 0 else { return (cores.map { _ in 0 }, 0) }
        if seconds > Self.maxTick { hadGap = true }
        covered += seconds
        var watts: [Double] = []
        for core in cores {
            let k = core.cluster == .efficiency ? calibration.kE : calibration.kP
            watts.append(k * core.activity / seconds)
            if core.cluster == .efficiency { eActivity += core.activity } else { pActivity += core.activity }
        }
        return (watts, watts.reduce(0, +) * (1 + calibration.overhead))
    }

    /// Fits the constants against a batch's exact energy. Our activity only covers
    /// the part of the interval we sampled, so it's scaled up to the whole interval.
    /// Returns true if the calibration changed.
    @discardableResult
    mutating func calibrate(with batch: Batch) -> Bool {
        defer {
            eActivity = 0
            pActivity = 0
            covered = 0
            hadGap = false
        }
        let coverage = batch.interval > 0 ? min(1, covered / batch.interval) : 0
        guard !hadGap, coverage >= Self.minCoverage, eActivity > 0, pActivity > 0 else { return false }

        let kE = batch.eCoreJoules / (eActivity / coverage)
        let kP = batch.pCoreJoules / (pActivity / coverage)
        let cores = batch.eCoreJoules + batch.pCoreJoules
        let overhead = cores > 0 ? batch.cpuJoules / cores - 1 : calibration.overhead
        // Reject physically implausible fits (e.g. counters reset) rather than learn them.
        let sane = (0.001...50)
        guard sane.contains(kE), sane.contains(kP), (0...5).contains(overhead) else { return false }

        let w = isCalibrated ? Self.blendWeight : 1
        calibration.kE += w * (kE - calibration.kE)
        calibration.kP += w * (kP - calibration.kP)
        calibration.overhead += w * (overhead - calibration.overhead)
        calibration.batches += 1
        return true
    }

    // MARK: - IOReport "CPU Core Performance States" parsing

    /// Index into the DVFS table for a state named "V<n>P<m>"; nil for IDLE/OFF/DOWN.
    static func stateIndex(_ name: String) -> Int? {
        guard name.hasPrefix("V"), let p = name.firstIndex(of: "P") else { return nil }
        return Int(name[name.index(after: name.startIndex)..<p])
    }

    /// Parses a per-core channel name like "ECPU010" / "PCPU120":
    /// type, cluster index, core index (the trailing digit is ignored).
    static func parseCoreChannel(_ name: String) -> (cluster: CPUCluster, clusterIndex: Int, core: Int)? {
        let chars = Array(name)
        guard chars.count >= 6, name.dropFirst().hasPrefix("CPU"),
            let clusterIndex = chars[4].wholeNumberValue, let core = chars[5].wholeNumberValue
        else { return nil }
        switch chars[0] {
        case "E": return (.efficiency, clusterIndex, core)
        case "P": return (.performance, clusterIndex, core)
        default: return nil
        }
    }

    /// Which `voltage-statesN` table drives a cluster. M1-family layout first (E → 1,
    /// P0 → 5, P1 → 13, verified on an M1 Pro); otherwise the fastest table with the
    /// same number of states as the cluster reports.
    static func tableNumber(cluster: CPUCluster, clusterIndex: Int, states: Int, tables: [Int: DVFSTable])
        -> Int?
    {
        let preferred = cluster == .efficiency ? [1] : (clusterIndex == 0 ? [5] : [13, 5])
        if let n = preferred.first(where: { tables[$0]?.count == states }) { return n }
        return tables.filter { $0.value.count == states }
            .max { ($0.value.maxMegahertz, $1.key) < ($1.value.maxMegahertz, $0.key) }?.key
    }

    /// Residency tick rate from a unit label like "24Mticks"; defaults to 24 MHz.
    static func tickRate(unitLabel: String) -> Double {
        if unitLabel.hasSuffix("Mticks"), let m = Double(unitLabel.dropLast("Mticks".count)) {
            return m * 1e6
        }
        return 24e6
    }

    /// seconds × GHz × V² summed over states, from per-state residency tick deltas.
    static func activity(residencyDeltas: [(state: String, ticks: Int64)], table: DVFSTable, tickRate: Double)
        -> Double
    {
        residencyDeltas.reduce(0) { sum, entry in
            guard let i = stateIndex(entry.state), table.megahertz.indices.contains(i), entry.ticks > 0 else {
                return sum
            }
            let volts = table.millivolts[i] / 1000
            return sum + Double(entry.ticks) / tickRate * table.megahertz[i] / 1000 * volts * volts
        }
    }
}

// MARK: - Persistence

extension CorePowerModel.Calibration {
    /// Per chip, so a fit from one SoC is never applied to another.
    private static var defaultsKey: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let chip = String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init), as: UTF8.self)
        return "CorePowerCalibration.\(chip.isEmpty ? "unknown" : chip)"
    }

    /// The fit saved by a previous launch on this chip, if any.
    static func load() -> Self? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
