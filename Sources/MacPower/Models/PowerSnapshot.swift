import Foundation

/// One combined per-core reading: utilisation (from host_processor_info) and
/// power (from IOReport), aligned by logical index.
struct CoreStat: Identifiable {
    let id: Int
    let label: String       // "E0", "P3"
    let cluster: CPUCluster
    let usage: Double        // 0...1
    let watts: Double
}

/// A single moment's worth of everything the app displays.
struct PowerSnapshot {
    let time: Date
    let energy: EnergyReading
    let cores: [CoreStat]
    let cpuOverall: Double            // 0...1
    let processes: [ProcessSample]
    let battery: BatteryInfo?
    let gpu: GPUInfo?
    let thermal: ThermalInfo?

    static let empty = PowerSnapshot(time: .now,
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

/// A compact point kept in the rolling history for time-series charts.
struct PowerHistoryPoint: Identifiable {
    let id: Date
    let cpu: Double
    let gpu: Double
    let ane: Double
    let dram: Double
    var total: Double { cpu + gpu + ane + dram }
}
