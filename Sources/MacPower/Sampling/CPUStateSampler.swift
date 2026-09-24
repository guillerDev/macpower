import CIOReport
import Foundation
import IOKit

/// Per-core DVFS activity: residency in each frequency/voltage state from IOReport's
/// "CPU Core Performance States" (unlike the energy counters on macOS 27, these
/// still update every tick, without root), weighted by the chip's own DVFS tables
/// from the IORegistry `pmgr` node. Feeds `CorePowerModel`. Not thread-safe; call
/// `sample()` from one queue.
final class CPUStateSampler {
    struct Tick {
        let cores: [CoreActivity]  // E cores first, then P cores by cluster
        let seconds: TimeInterval
    }

    private struct Core {
        let label: String
        let cluster: CPUCluster
        let table: DVFSTable
    }

    private let subscription: OpaquePointer
    private let subscribedChannels: CFMutableDictionary
    private let cores: [String: Core]  // keyed by channel name ("ECPU000")
    private let order: [String]
    private var previous: [String: [String: Int64]] = [:]  // channel -> state -> residency
    /// Doesn't advance during sleep — same basis as the energy counters' timestamps.
    private let clock = SuspendingClock()
    private var lastSample: SuspendingClock.Instant?

    init?() {
        guard
            let raw = IOReportCopyChannelsInGroup(
                "CPU Stats" as CFString, "CPU Core Performance States" as CFString, 0, 0, 0),
            let channels = CFDictionaryCreateMutableCopy(nil, 0, raw)
        else { return nil }
        var subbed: Unmanaged<CFMutableDictionary>?
        guard let sub = IOReportCreateSubscription(nil, channels, &subbed, 0, nil), let subbed else {
            return nil
        }
        subscription = sub
        subscribedChannels = subbed.takeRetainedValue()

        guard let first = IOReportCreateSamples(sub, subscribedChannels, nil) else { return nil }
        let found = Self.discoverCores(in: first)
        let tables = Self.loadDVFSTables()

        // E cores first, then P cores, each by cluster then core — the order
        // host_processor_info and the energy counters use.
        let sorted = found.sorted {
            ($0.id.cluster == .efficiency ? 0 : 1, $0.id.clusterIndex, $0.id.core)
                < ($1.id.cluster == .efficiency ? 0 : 1, $1.id.clusterIndex, $1.id.core)
        }
        var byName: [String: Core] = [:]
        var names: [String] = []
        var counts: [CPUCluster: Int] = [:]
        for entry in sorted {
            guard
                let n = CorePowerModel.tableNumber(
                    cluster: entry.id.cluster, clusterIndex: entry.id.clusterIndex,
                    states: entry.states, tables: tables),
                let table = tables[n]
            else { continue }
            let index = counts[entry.id.cluster, default: 0]
            counts[entry.id.cluster] = index + 1
            byName[entry.channel] = Core(
                label: "\(entry.id.cluster.rawValue)\(index)", cluster: entry.id.cluster, table: table)
            names.append(entry.channel)
        }
        // Nothing to model if no core could be matched to a DVFS table.
        guard !names.isEmpty else { return nil }
        cores = byName
        order = names
    }

    /// Per-core activity since the previous call; nil on the priming call.
    func sample() -> Tick? {
        let now = clock.now
        defer { lastSample = now }
        guard let samples = IOReportCreateSamples(subscription, subscribedChannels, nil) else { return nil }

        var current: [String: [String: Int64]] = [:]
        var activity: [String: Double] = [:]
        IOReportIterate(samples) { channel in
            guard let channel, let name = IOReportChannelGetChannelName(channel) as String?,
                let core = self.cores[name]
            else { return 0 }
            let rate = CorePowerModel.tickRate(
                unitLabel: IOReportChannelGetUnitLabel(channel) as String? ?? "")
            var states: [String: Int64] = [:]
            var deltas: [(state: String, ticks: Int64)] = []
            for i in 0..<IOReportStateGetCount(channel) {
                guard let state = IOReportStateGetNameForIndex(channel, i) as String? else { continue }
                let residency = IOReportStateGetResidency(channel, i)
                states[state] = residency
                if let before = self.previous[name]?[state] { deltas.append((state, residency - before)) }
            }
            current[name] = states
            activity[name] = CorePowerModel.activity(
                residencyDeltas: deltas, table: core.table, tickRate: rate)
            return 0
        }
        let primed = !previous.isEmpty
        previous = current
        guard primed, let last = lastSample else { return nil }
        let seconds = last.duration(to: now).inSeconds
        guard seconds > 0 else { return nil }
        let ticks = order.compactMap { name in
            cores[name].map {
                CoreActivity(label: $0.label, cluster: $0.cluster, activity: activity[name] ?? 0)
            }
        }
        return Tick(cores: ticks, seconds: seconds)
    }

    // MARK: - Discovery

    private typealias Found = (
        channel: String, id: (cluster: CPUCluster, clusterIndex: Int, core: Int), states: Int
    )

    /// Per-core channels and how many DVFS states each one reports.
    private static func discoverCores(in samples: CFDictionary) -> [Found] {
        var found: [Found] = []
        IOReportIterate(samples) { channel in
            guard let channel, let name = IOReportChannelGetChannelName(channel) as String?,
                let id = CorePowerModel.parseCoreChannel(name)
            else { return 0 }
            var states = 0
            for i in 0..<IOReportStateGetCount(channel) {
                if let state = IOReportStateGetNameForIndex(channel, i) as String?,
                    let v = CorePowerModel.stateIndex(state)
                {
                    states = max(states, v + 1)
                }
            }
            found.append((name, id, states))
            return 0
        }
        return found
    }

    /// Every `voltage-statesN` DVFS table on the `pmgr` node, keyed by N.
    private static func loadDVFSTables() -> [Int: DVFSTable] {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceNameMatching("pmgr"))
        guard service != 0 else { return [:] }
        defer { IOObjectRelease(service) }
        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let props = unmanaged?.takeRetainedValue() as? [String: Any]
        else { return [:] }

        var tables: [Int: DVFSTable] = [:]
        for key in props.keys where key.hasPrefix("voltage-states") && !key.hasSuffix("-sram") {
            guard let n = Int(key.dropFirst("voltage-states".count)) else { continue }
            let plain = props[key] as? Data
            // M1-era chips keep frequencies in the -sram twin and core voltages here.
            let table =
                (props["\(key)-sram"] as? Data).flatMap { DVFSTable.parse(frequencies: $0, voltages: plain) }
                ?? plain.flatMap { DVFSTable.parse(frequencies: $0, voltages: nil) }
            if let table { tables[n] = table }
        }
        return tables
    }
}
