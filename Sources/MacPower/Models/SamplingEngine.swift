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
    private let cpuStates = CPUStateSampler()
    private let cpuUsage = CPUUsageSampler()
    private let processes = ProcessSampler()
    private let smc = SMCReader()

    private var lastEnergy = EnergyReading()
    private var coreModel = CorePowerModel(calibration: CorePowerModel.Calibration.load() ?? .defaults)

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
        let sample = ioReport?.sample()
        var energy = sample?.reading ?? lastEnergy
        let states = cpuStates?.sample()
        if energy.batched { applyCoreModel(to: &energy, states: states, batch: sample?.batch) }
        lastEnergy = energy

        let usage = cpuUsage.sample()
        let perCoreUsage = usage?.perCore ?? []
        let overall = usage?.overall ?? 0

        // Align per-core power (IOReport) with per-core usage (host_processor_info)
        // by logical index. Both enumerate E cores first, then P cores.
        var cores: [CoreStat] = []
        for (index, power) in energy.coreWatts.enumerated() {
            let use = index < perCoreUsage.count ? perCoreUsage[index] : 0
            cores.append(
                CoreStat(
                    id: index,
                    label: power.label,
                    cluster: power.cluster,
                    usage: use,
                    watts: power.watts))
        }
        // If IOReport gave no cores but usage did, still surface utilisation.
        if cores.isEmpty && !perCoreUsage.isEmpty {
            for (index, use) in perCoreUsage.enumerated() {
                cores.append(
                    CoreStat(
                        id: index, label: "\(index)",
                        cluster: .performance, usage: use, watts: 0))
            }
        }

        let procs = processes.sample()
        let gpu = GPUReader.read()
        let thermal = smc.read()
        var battery = BatteryReader.read()
        if battery?.temperature == nil { battery?.temperature = thermal?.batteryTemp }

        return PowerSnapshot(
            time: Date(),
            energy: energy,
            cores: cores,
            cpuOverall: overall,
            processes: procs,
            battery: battery,
            gpu: gpu,
            thermal: thermal)
    }

    /// With batched counters (macOS 27), model CPU and per-core power from DVFS
    /// residency, and fit the model to every batch as it lands. Without the model
    /// (no residency data or DVFS tables) the latest batch averages stay.
    private func applyCoreModel(
        to energy: inout EnergyReading, states: CPUStateSampler.Tick?, batch: CorePowerModel.Batch?
    ) {
        // Accumulate this tick first: most of it falls inside the batch interval.
        let estimate = states.map { coreModel.estimate($0.cores, seconds: $0.seconds) }
        if let batch, coreModel.calibrate(with: batch) { coreModel.calibration.save() }

        guard let states, let estimate else { return }
        energy.coreWatts = zip(states.cores, estimate.cores).enumerated().map { i, pair in
            CorePower(id: i, label: pair.0.label, cluster: pair.0.cluster, watts: pair.1)
        }
        energy.cpuWatts = estimate.cpuWatts
        energy.cpuSource = .estimated(calibrated: coreModel.isCalibrated)
    }
}
