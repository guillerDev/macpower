import Foundation

/// Owns the stateful samplers and runs them on a private serial queue so a tick
/// never touches the main thread. Produces a unified `PowerSnapshot`.
///
/// `@unchecked Sendable`: the samplers are non-Sendable but are only ever touched
/// inside `sampleNow()` on the serial `queue`, and `tick()` is awaited
/// sequentially, so there is no concurrent access.
final class SamplingEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.macpower.sampling", qos: .utility)
    private let ioReport = IOReportSampler()
    private let cpuUsage = CPUUsageSampler()
    private let processes = ProcessSampler()
    private let smc = SMCReader()

    private var lastEnergy = EnergyReading()

    /// Whether the SoC energy source initialised. If false the app still runs
    /// but power figures are unavailable.
    var energyAvailable: Bool { ioReport != nil }

    func tick() async -> PowerSnapshot {
        await withCheckedContinuation { continuation in
            queue.async {
                continuation.resume(returning: self.sampleNow())
            }
        }
    }

    private func sampleNow() -> PowerSnapshot {
        let energy = ioReport?.sample() ?? lastEnergy
        lastEnergy = energy

        let usage = cpuUsage.sample()
        let perCoreUsage = usage?.perCore ?? []
        let overall = usage?.overall ?? 0

        // Align per-core power (IOReport) with per-core usage (host_processor_info)
        // by logical index. Both enumerate E cores first, then P cores.
        var cores: [CoreStat] = []
        for (index, power) in energy.coreWatts.enumerated() {
            let use = index < perCoreUsage.count ? perCoreUsage[index] : 0
            cores.append(CoreStat(id: index,
                                  label: power.label,
                                  cluster: power.cluster,
                                  usage: use,
                                  watts: power.watts))
        }
        // If IOReport gave no cores but usage did, still surface utilisation.
        if cores.isEmpty && !perCoreUsage.isEmpty {
            for (index, use) in perCoreUsage.enumerated() {
                cores.append(CoreStat(id: index, label: "\(index)",
                                      cluster: .performance, usage: use, watts: 0))
            }
        }

        let procs = processes.sample()
        let battery = BatteryReader.read()
        let gpu = GPUReader.read()
        let thermal = smc.read()

        return PowerSnapshot(time: Date(),
                             energy: energy,
                             cores: cores,
                             cpuOverall: overall,
                             processes: procs,
                             battery: battery,
                             gpu: gpu,
                             thermal: thermal)
    }
}
