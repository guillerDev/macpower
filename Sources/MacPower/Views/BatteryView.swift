import SwiftUI

struct BatteryView: View {
    var monitor: PowerMonitor

    var body: some View {
        ScrollView {
            if let b = monitor.snapshot.battery, b.isInstalled {
                content(b)
                    .padding(16)
            } else {
                ContentUnavailableView(
                    "No battery detected",
                    systemImage: "bolt.slash",
                    description: Text("This Mac has no internal battery, or details are unavailable.")
                )
                .padding(.top, 80)
            }
        }
        .navigationTitle("Battery")
    }

    private func content(_ b: BatteryInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Card {
                    HStack(spacing: 16) {
                        RingGauge(
                            fraction: b.charge / 100,
                            color: chargeColor(b),
                            label: Fmt.percentValue(b.charge),
                            caption: b.isCharging
                                ? "charging" : (b.externalConnected ? "on AC" : "on battery")
                        )
                        .frame(width: 120, height: 120)
                        VStack(alignment: .leading, spacing: 10) {
                            StatTile(
                                title: "Power flow",
                                value: Fmt.watts(abs(b.powerWatts), decimals: 1),
                                caption: powerCaption(b),
                                color: b.powerWatts >= 0 ? Theme.eCore : Theme.dram)
                            if let mins = timeRemaining(b) {
                                StatTile(
                                    title: b.isCharging ? "Time to full" : "Time to empty",
                                    value: Fmt.minutes(mins))
                            }
                        }
                    }
                }
            }

            Card(title: "Health", systemImage: "heart.text.square") {
                HStack(spacing: 12) {
                    StatTile(
                        title: "Health", value: Fmt.percentValue(b.health),
                        caption: "of design capacity",
                        color: healthColor(b.health))
                    StatTile(title: "Cycle count", value: "\(b.cycleCount)")
                    StatTile(
                        title: "Condition", value: b.condition,
                        color: b.condition == "Normal" ? .primary : Theme.dram)
                    StatTile(
                        title: "Temperature",
                        value: String(format: "%.1f°C", b.temperature))
                }
            }

            Card(title: "Capacity", systemImage: "battery.100") {
                HStack(spacing: 12) {
                    StatTile(title: "Current", value: Fmt.mAh(b.currentCapacity))
                    StatTile(title: "Full charge", value: Fmt.mAh(b.maxCapacity))
                    StatTile(title: "Design", value: Fmt.mAh(b.designCapacity))
                }
            }

            Card(title: "Electrical", systemImage: "bolt") {
                HStack(spacing: 12) {
                    StatTile(title: "Voltage", value: String(format: "%.2f V", b.voltage))
                    StatTile(
                        title: "Amperage",
                        value: String(format: "%+.2f A", b.amperage),
                        caption: b.amperage >= 0 ? "into battery" : "from battery")
                    StatTile(
                        title: "AC power",
                        value: b.externalConnected ? "Connected" : "Not connected",
                        color: b.externalConnected ? Theme.eCore : .secondary)
                }
            }
        }
    }

    private func chargeColor(_ b: BatteryInfo) -> Color {
        if b.isCharging || b.externalConnected { return Theme.eCore }
        if b.charge < 20 { return Theme.dram }
        return Theme.cpu
    }

    private func healthColor(_ health: Double) -> Color {
        if health >= 80 { return Theme.eCore }
        if health >= 60 { return Theme.dram }
        return .red
    }

    private func powerCaption(_ b: BatteryInfo) -> String {
        if b.powerWatts > 0.05 { return "charging" }
        if b.powerWatts < -0.05 { return "discharging" }
        return "idle"
    }

    private func timeRemaining(_ b: BatteryInfo) -> Int? {
        b.isCharging ? b.timeToFull : b.timeToEmpty
    }
}
