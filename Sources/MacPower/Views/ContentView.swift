import SwiftUI

enum Section: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case cpu = "CPU"
    case gpu = "GPU"
    case processes = "Processes"
    case battery = "Battery"
    case thermal = "Thermal"

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .overview: "bolt.fill"
        case .cpu: "cpu.fill"
        case .gpu: "display"
        case .processes: "list.bullet.rectangle"
        case .battery: "battery.75percent"
        case .thermal: "thermometer.medium"
        }
    }
}

struct ContentView: View {
    var monitor: PowerMonitor
    @State private var selection: Section? = .overview

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
            .safeAreaInset(edge: .bottom) { statusFooter }
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .overview {
        case .overview: OverviewView(monitor: monitor)
        case .cpu: CPUView(monitor: monitor)
        case .gpu: GPUView(monitor: monitor)
        case .processes: ProcessesView(monitor: monitor)
        case .battery: BatteryView(monitor: monitor)
        case .thermal: ThermalView(monitor: monitor)
        }
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 6) {
                if monitor.energyAvailable {
                    // Healthy: just a subtle green dot.
                    Circle().fill(Theme.eCore).frame(width: 7, height: 7)
                        .help("Sampling live")
                } else {
                    // Something's wrong: surface it.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Energy source unavailable")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("v\(AppInfo.version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }
}
