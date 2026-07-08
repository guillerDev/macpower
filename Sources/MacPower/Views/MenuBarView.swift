import SwiftUI

/// Compact popover shown from the menu-bar item.
struct MenuBarView: View {
    var monitor: PowerMonitor
    @Environment(\.openWindow) private var openWindow

    private var energy: EnergyReading { monitor.snapshot.energy }
    private var systemWatts: Double? { monitor.snapshot.thermal?.systemPower }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Headline: total system power (the same number shown in the menu bar).
            HStack(alignment: .firstTextBaseline) {
                Label("Total system", systemImage: "bolt.fill").font(.headline)
                Spacer()
                Text(Fmt.power(systemWatts ?? energy.socWatts))
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                    .contentTransition(.numericText())
            }

            Divider()

            // SoC subtotal, then the per-rail breakdown beneath it.
            row(label: "SoC", value: energy.socWatts, color: Theme.soc, bold: true)
            ForEach(PowerRail.allCases) { rail in
                row(label: rail.rawValue, value: energy.watts(for: rail),
                    color: Theme.rail(rail), indented: true)
            }
            if let sys = systemWatts {
                row(label: "Other", value: max(0, sys - energy.socWatts), color: Theme.other,
                    help: "Display, storage, Wi-Fi/Bluetooth, peripherals & power-conversion "
                        + "losses. These can't be measured individually.")
            }

            if let top = monitor.snapshot.processes.first {
                Divider()
                HStack {
                    Text("Top: \(top.name)").font(.caption).lineLimit(1)
                    Spacer()
                    Text(Fmt.percentValue(top.cpuPercent, decimals: 0))
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack {
                Button("Open MacPower") { openWindow(id: "main") }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .font(.callout)
        }
        .padding(14)
        .frame(width: 260)
    }

    private func row(label: String, value: Double, color: Color,
                     bold: Bool = false, indented: Bool = false,
                     help: String? = nil) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(bold ? .callout.weight(.semibold) : .callout)
            if help != nil {
                Image(systemName: "info.circle")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text(Fmt.power(value))
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, indented ? 12 : 0)
        .help(help ?? "")
    }
}
