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

    /// Trailing window (seconds) over which readings are averaged for display.
    /// 0 disables smoothing (show the raw per-tick values).
    var averagingSeconds: TimeInterval = 10

    /// Number of points retained for the history chart (~2 minutes at 1s).
    let historyLimit = 120

    var energyAvailable: Bool { engine.energyAvailable }

    @ObservationIgnored private let engine = SamplingEngine()
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Raw snapshots inside the current averaging window (trimmed by time).
    @ObservationIgnored private var window: [PowerSnapshot] = []

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
        // Maintain the trailing window and publish its average (smoothing jitter).
        window.append(snap)
        let cutoff = snap.time.addingTimeInterval(-averagingSeconds)
        window.removeAll { $0.time < cutoff }  // always keeps the just-added snap
        snapshot = PowerSnapshot.averaged(window)

        // History chart tracks the RAW signal so real variation stays visible.
        let point = PowerHistoryPoint(
            id: snap.time,
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
