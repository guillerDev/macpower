import Foundation
import Observation

/// Observable view-model that samples on an interval and publishes the latest
/// snapshot plus a rolling history for time-series charts.
@MainActor
@Observable
final class PowerMonitor {
    private(set) var snapshot: PowerSnapshot = .empty
    private(set) var history: [PowerHistoryPoint] = []
    private(set) var isRunning = false

    /// Optional exact per-process energy (powermetrics, requires root).
    let powerMetrics = PowerMetricsService()

    /// Sampling interval in seconds.
    var interval: TimeInterval = 1.0 {
        didSet { if isRunning { restart() } }
    }

    /// Number of points retained for the history chart (~2 minutes at 1s).
    let historyLimit = 120

    var energyAvailable: Bool { engine.energyAvailable }

    @ObservationIgnored private let engine = SamplingEngine()
    @ObservationIgnored private var task: Task<Void, Never>?

    func start() {
        guard !isRunning else { return }
        isRunning = true
        task = Task { [weak self] in
            guard let self else { return }
            // Prime once so the first published snapshot already has deltas.
            _ = await self.engine.tick()
            while !Task.isCancelled {
                let snap = await self.engine.tick()
                self.apply(snap)
                try? await Task.sleep(for: .seconds(self.interval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func restart() {
        stop()
        start()
        if powerMetrics.isActive {
            powerMetrics.start(intervalMs: Int(interval * 1000))
        }
    }

    /// Enable/disable the exact powermetrics energy source.
    func setPowerMetrics(_ enabled: Bool) {
        if enabled {
            powerMetrics.start(intervalMs: Int(interval * 1000))
        } else {
            powerMetrics.stop()
        }
    }

    private func apply(_ snap: PowerSnapshot) {
        snapshot = snap
        let point = PowerHistoryPoint(id: snap.time,
                                      cpu: snap.energy.cpuWatts,
                                      gpu: snap.energy.gpuWatts,
                                      ane: snap.energy.aneWatts,
                                      dram: snap.energy.dramWatts)
        history.append(point)
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }
}
