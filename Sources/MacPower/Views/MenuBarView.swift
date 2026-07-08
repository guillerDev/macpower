import SwiftUI

/// Compact popover shown from the menu-bar item.
struct MenuBarView: View {
    var monitor: PowerMonitor
    @Environment(\.openWindow) private var openWindow

    private var energy: EnergyReading { monitor.snapshot.energy }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("MacPower", systemImage: "bolt.fill").font(.headline)
                Spacer()
                Text(Fmt.power(energy.socWatts))
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .contentTransition(.numericText())
            }

            Divider()

            ForEach(PowerRail.allCases) { rail in
                HStack {
                    Circle().fill(Theme.rail(rail)).frame(width: 8, height: 8)
                    Text(rail.rawValue).font(.callout)
                    Spacer()
                    Text(Fmt.power(energy.watts(for: rail)))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if let power = monitor.snapshot.thermal?.systemPower {
                Divider()
                HStack {
                    Text("Total system").font(.callout)
                    Spacer()
                    Text(Fmt.watts(power, decimals: 1))
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
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
}
