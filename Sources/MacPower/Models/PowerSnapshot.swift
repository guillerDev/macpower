import Foundation

/// One combined per-core reading: utilisation (from host_processor_info) and
/// power (from IOReport), aligned by logical index.
struct CoreStat: Identifiable {
    let id: Int
    let label: String  // "E0", "P3"
    let cluster: CPUCluster
    let usage: Double  // 0...1
    let watts: Double
}

/// A single moment's worth of everything the app displays.
struct PowerSnapshot {
    let time: Date
    let energy: EnergyReading
    let cores: [CoreStat]
    let cpuOverall: Double  // 0...1
    let processes: [ProcessSample]
    let battery: BatteryInfo?
    let gpu: GPUInfo?
    let thermal: ThermalInfo?

    static let empty = PowerSnapshot(
        time: .now,
        energy: EnergyReading(),
        cores: [],
        cpuOverall: 0,
        processes: [],
        battery: nil,
        gpu: nil,
        thermal: nil)

    var eCores: [CoreStat] { cores.filter { $0.cluster == .efficiency } }
    var pCores: [CoreStat] { cores.filter { $0.cluster == .performance } }
    var eClusterWatts: Double { eCores.reduce(0) { $0 + $1.watts } }
    var pClusterWatts: Double { pCores.reduce(0) { $0 + $1.watts } }
}

extension PowerSnapshot {
    /// Element-wise mean of the numeric readings across `snaps` (a trailing time
    /// window). Non-numeric fields (labels, clusters, thermal state, battery)
    /// come from the most recent snapshot. Used to smooth per-second jitter.
    static func averaged(_ snaps: [PowerSnapshot]) -> PowerSnapshot {
        guard let latest = snaps.last else { return .empty }
        guard snaps.count > 1 else { return latest }
        let n = Double(snaps.count)
        func mean(_ f: (PowerSnapshot) -> Double) -> Double { snaps.reduce(0) { $0 + f($1) } / n }
        func meanOpt(_ values: [Double?]) -> Double? {
            let present = values.compactMap { $0 }
            return present.isEmpty ? nil : present.reduce(0, +) / Double(present.count)
        }

        // Aggregate rails + per-core power (cores are stable in count and order).
        var energy = EnergyReading()
        energy.cpuWatts = mean { $0.energy.cpuWatts }
        energy.gpuWatts = mean { $0.energy.gpuWatts }
        energy.aneWatts = mean { $0.energy.aneWatts }
        energy.dramWatts = mean { $0.energy.dramWatts }
        energy.coreWatts = latest.energy.coreWatts.enumerated().map { i, ref in
            let w =
                snaps.reduce(0.0) {
                    $0 + ($1.energy.coreWatts.indices.contains(i) ? $1.energy.coreWatts[i].watts : 0)
                } / n
            return CorePower(id: ref.id, label: ref.label, cluster: ref.cluster, watts: w)
        }

        // Combined per-core (usage + power).
        let cores = latest.cores.enumerated().map { i, ref -> CoreStat in
            let usage = snaps.reduce(0.0) { $0 + ($1.cores.indices.contains(i) ? $1.cores[i].usage : 0) } / n
            let watts = snaps.reduce(0.0) { $0 + ($1.cores.indices.contains(i) ? $1.cores[i].watts : 0) } / n
            return CoreStat(id: ref.id, label: ref.label, cluster: ref.cluster, usage: usage, watts: watts)
        }

        // GPU.
        var gpu = latest.gpu
        let gpuSnaps = snaps.compactMap(\.gpu)
        if !gpuSnaps.isEmpty {
            let gn = Double(gpuSnaps.count)
            var g = GPUInfo()
            g.utilization = gpuSnaps.reduce(0) { $0 + $1.utilization } / gn
            g.rendererUtil = gpuSnaps.reduce(0) { $0 + $1.rendererUtil } / gn
            g.tilerUtil = gpuSnaps.reduce(0) { $0 + $1.tilerUtil } / gn
            g.inUseMemory = Int(gpuSnaps.reduce(0.0) { $0 + Double($1.inUseMemory) } / gn)
            g.allocatedMemory = Int(gpuSnaps.reduce(0.0) { $0 + Double($1.allocatedMemory) } / gn)
            gpu = g
        }

        // Thermal (keep state + fan structure from latest, average the numbers).
        var thermal = latest.thermal
        let thSnaps = snaps.compactMap(\.thermal)
        if var t = latest.thermal, !thSnaps.isEmpty {
            t.cpuTemp = meanOpt(thSnaps.map(\.cpuTemp))
            t.gpuTemp = meanOpt(thSnaps.map(\.gpuTemp))
            t.batteryTemp = meanOpt(thSnaps.map(\.batteryTemp))
            t.enclosureTemp = meanOpt(thSnaps.map(\.enclosureTemp))
            t.systemPower = meanOpt(thSnaps.map(\.systemPower))
            t.adapterPower = meanOpt(thSnaps.map(\.adapterPower))
            t.fans = t.fans.map { fan in
                let rpms = thSnaps.compactMap { $0.fans.first { $0.id == fan.id }?.rpm }
                let avg = rpms.isEmpty ? fan.rpm : rpms.reduce(0, +) / Double(rpms.count)
                return FanInfo(id: fan.id, rpm: avg, minRPM: fan.minRPM, maxRPM: fan.maxRPM)
            }
            thermal = t
        }

        // Processes: average each still-present PID's metrics across the window.
        let processes = latest.processes.map { p -> ProcessSample in
            let matches = snaps.compactMap { s in s.processes.first { $0.id == p.id } }
            let c = Double(matches.count)
            return ProcessSample(
                id: p.id, name: p.name,
                cpuPercent: matches.reduce(0) { $0 + $1.cpuPercent } / c,
                energyImpact: matches.reduce(0) { $0 + $1.energyImpact } / c,
                idleWakeups: matches.reduce(0) { $0 + $1.idleWakeups } / c)
        }

        return PowerSnapshot(
            time: latest.time, energy: energy, cores: cores,
            cpuOverall: mean { $0.cpuOverall },
            processes: processes, battery: latest.battery,
            gpu: gpu, thermal: thermal)
    }
}

/// A compact point kept in the rolling history for time-series charts.
struct PowerHistoryPoint: Identifiable {
    let id: Date
    let cpu: Double
    let gpu: Double
    let ane: Double
    let dram: Double
}
