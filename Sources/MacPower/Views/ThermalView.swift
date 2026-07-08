import SwiftUI

struct ThermalView: View {
    var monitor: PowerMonitor

    private var thermal: ThermalInfo? { monitor.snapshot.thermal }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let thermal {
                    summary(thermal)
                    if !temps(thermal).isEmpty {
                        Card(title: "Temperatures", systemImage: "thermometer.medium") {
                            HStack(spacing: 12) {
                                ForEach(temps(thermal), id: \.0) { name, value in
                                    StatTile(title: name,
                                             value: String(format: "%.1f°C", value),
                                             color: tempColor(value))
                                }
                            }
                        }
                    }
                    if !thermal.fans.isEmpty {
                        Card(title: "Fans", systemImage: "fanblades") {
                            ForEach(thermal.fans) { fan in
                                MeterRow(label: "F\(fan.id)",
                                         fraction: fan.fraction,
                                         trailing: "\(Int(fan.rpm)) rpm",
                                         color: Theme.cpu)
                            }
                            Text("Range \(Int(thermal.fans[0].minRPM))–\(Int(thermal.fans[0].maxRPM)) rpm")
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    ContentUnavailableView("Sensor data unavailable",
                                           systemImage: "thermometer.slash")
                        .padding(.top, 60)
                }
            }
            .padding(16)
        }
        .navigationTitle("Thermal")
    }

    private func summary(_ t: ThermalInfo) -> some View {
        HStack(spacing: 12) {
            Card {
                StatTile(title: "Thermal state",
                         value: t.thermalStateLabel,
                         caption: "system pressure",
                         color: stateColor(t.thermalState))
            }
            if let power = t.systemPower {
                Card {
                    StatTile(title: "Total system power",
                             value: Fmt.watts(power, decimals: 1),
                             caption: "measured at SMC (PSTR)",
                             color: .primary)
                }
            }
            if let fan = t.fans.first {
                Card {
                    StatTile(title: "Fan",
                             value: fan.rpm < 1 ? "Off" : "\(Int(fan.rpm)) rpm",
                             caption: "\(t.fans.count) fan\(t.fans.count == 1 ? "" : "s")",
                             color: Theme.cpu)
                }
            }
        }
    }

    private func temps(_ t: ThermalInfo) -> [(String, Double)] {
        var out: [(String, Double)] = []
        if let v = t.cpuTemp { out.append(("CPU", v)) }
        if let v = t.gpuTemp { out.append(("GPU", v)) }
        if let v = t.batteryTemp { out.append(("Battery", v)) }
        if let v = t.enclosureTemp { out.append(("Enclosure", v)) }
        return out
    }

    private func tempColor(_ c: Double) -> Color {
        if c >= 90 { return .red }
        if c >= 75 { return Theme.dram }
        return .primary
    }

    private func stateColor(_ s: ProcessInfo.ThermalState) -> Color {
        switch s {
        case .nominal: Theme.eCore
        case .fair: Theme.dram
        case .serious, .critical: .red
        @unknown default: .secondary
        }
    }
}
