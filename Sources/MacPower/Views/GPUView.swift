import SwiftUI

struct GPUView: View {
    var monitor: PowerMonitor

    private var gpu: GPUInfo? { monitor.snapshot.gpu }
    private var gpuWatts: Double { monitor.snapshot.energy.gpuWatts }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let gpu {
                    HStack(spacing: 12) {
                        Card {
                            HStack(spacing: 16) {
                                RingGauge(fraction: gpu.utilization,
                                          color: Theme.gpu,
                                          label: Fmt.percent(gpu.utilization),
                                          caption: "utilisation")
                                    .frame(width: 120, height: 120)
                                VStack(alignment: .leading, spacing: 10) {
                                    StatTile(title: "GPU power",
                                             value: Fmt.power(gpuWatts),
                                             color: Theme.gpu)
                                    StatTile(title: "In-use memory",
                                             value: bytes(gpu.inUseMemory))
                                }
                            }
                        }
                    }

                    Card(title: "Utilisation breakdown", systemImage: "cpu") {
                        MeterRow(label: "Dev", fraction: gpu.utilization,
                                 trailing: Fmt.percent(gpu.utilization), color: Theme.gpu)
                        MeterRow(label: "Rend", fraction: gpu.rendererUtil,
                                 trailing: Fmt.percent(gpu.rendererUtil), color: Theme.gpu)
                        MeterRow(label: "Tile", fraction: gpu.tilerUtil,
                                 trailing: Fmt.percent(gpu.tilerUtil), color: Theme.gpu)
                    }

                    Card(title: "Memory", systemImage: "memorychip") {
                        HStack(spacing: 12) {
                            StatTile(title: "In use", value: bytes(gpu.inUseMemory))
                            StatTile(title: "Allocated", value: bytes(gpu.allocatedMemory))
                        }
                    }
                } else {
                    ContentUnavailableView("GPU statistics unavailable",
                                           systemImage: "display.trianglebadge.exclamationmark")
                        .padding(.top, 60)
                }
            }
            .padding(16)
        }
        .navigationTitle("GPU")
    }

    private func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}
