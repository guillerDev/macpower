import SwiftUI
import Charts

struct CPUView: View {
    var monitor: PowerMonitor

    private var snapshot: PowerSnapshot { monitor.snapshot }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                summary
                if !snapshot.eCores.isEmpty {
                    clusterCard("Efficiency cores", cores: snapshot.eCores,
                                total: snapshot.eClusterWatts, color: Theme.eCore)
                }
                if !snapshot.pCores.isEmpty {
                    clusterCard("Performance cores", cores: snapshot.pCores,
                                total: snapshot.pClusterWatts, color: Theme.pCore)
                }
                Card(title: "Power per core", systemImage: "chart.bar.fill") {
                    perCorePowerChart
                        .frame(height: max(120, CGFloat(snapshot.cores.count) * 26))
                }
            }
            .padding(16)
        }
        .navigationTitle("CPU")
    }

    private var summary: some View {
        HStack(spacing: 12) {
            Card {
                HStack {
                    RingGauge(fraction: snapshot.cpuOverall,
                              color: Theme.cpu,
                              label: Fmt.percent(snapshot.cpuOverall),
                              caption: "utilisation")
                        .frame(width: 110, height: 110)
                    VStack(alignment: .leading, spacing: 8) {
                        StatTile(title: "CPU power",
                                 value: Fmt.power(snapshot.energy.cpuWatts),
                                 color: Theme.cpu)
                        StatTile(title: "Cores",
                                 value: "\(snapshot.cores.count)",
                                 caption: "\(snapshot.eCores.count)E · \(snapshot.pCores.count)P")
                    }
                }
            }
            Card {
                StatTile(title: "E-cluster",
                         value: Fmt.power(snapshot.eClusterWatts),
                         caption: "efficiency",
                         color: Theme.eCore)
            }
            Card {
                StatTile(title: "P-cluster",
                         value: Fmt.power(snapshot.pClusterWatts),
                         caption: "performance",
                         color: Theme.pCore)
            }
        }
    }

    private func clusterCard(_ title: String, cores: [CoreStat], total: Double, color: Color) -> some View {
        Card(title: title, systemImage: "cpu") {
            ForEach(cores) { core in
                MeterRow(label: core.label,
                         fraction: core.usage,
                         trailing: Fmt.percent(core.usage),
                         color: color)
            }
            Divider().padding(.vertical, 2)
            HStack {
                Text("Cluster power").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(Fmt.power(total)).font(.system(.caption, design: .monospaced))
                    .foregroundStyle(color)
            }
        }
    }

    private var perCorePowerChart: some View {
        Chart(snapshot.cores) { core in
            BarMark(
                x: .value("Power", core.watts),
                y: .value("Core", core.label)
            )
            .foregroundStyle(Theme.cluster(core.cluster))
            .annotation(position: .trailing, alignment: .leading) {
                Text(Fmt.power(core.watts))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXAxisLabel("Watts")
        .chartYAxis {
            AxisMarks(preset: .aligned, position: .leading)
        }
    }
}
