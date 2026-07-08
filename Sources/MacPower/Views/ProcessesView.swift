import SwiftUI

struct ProcessesView: View {
    var monitor: PowerMonitor

    @State private var sortOrder = [KeyPathComparator(\Row.approxImpact, order: .reverse)]
    @State private var query = ""
    @State private var exactEnabled = false
    @State private var showSetup = false
    @State private var setupError: String?

    struct Row: Identifiable {
        let id: Int32
        let name: String
        let cpuPercent: Double
        let idleWakeups: Double
        let approxImpact: Double
        let exactImpact: Double?
        var exactSort: Double { exactImpact ?? -1 }
    }

    private var exactActive: Bool {
        monitor.powerMetrics.status == .running && !monitor.powerMetrics.energyByPID.isEmpty
    }

    private var rows: [Row] {
        let exact = monitor.powerMetrics.energyByPID
        var list = monitor.snapshot.processes.map {
            Row(id: $0.id, name: $0.name, cpuPercent: $0.cpuPercent,
                idleWakeups: $0.idleWakeups, approxImpact: $0.energyImpact,
                exactImpact: exact[$0.id])
        }
        if !query.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(query) }
        }
        return list.sorted(using: sortOrder)
    }

    var body: some View {
        Table(rows, sortOrder: $sortOrder) {
            TableColumn("Process", value: \.name) { Text($0.name).lineLimit(1) }
                .width(min: 150, ideal: 230)

            TableColumn("PID", value: \.id) {
                Text("\($0.id)").monospacedDigit().foregroundStyle(.secondary)
            }
            .width(56)

            TableColumn("Impact (approx)", value: \.approxImpact) { r in
                ImpactCell(value: r.approxImpact, maxValue: maxApprox, color: Theme.cpu)
            }
            .width(min: 110, ideal: 150)

            TableColumn("Energy (exact)", value: \.exactSort) { r in
                if let e = r.exactImpact {
                    ImpactCell(value: e, maxValue: maxExact, color: Theme.gpu)
                } else {
                    Text(exactActive ? "—" : "off").foregroundStyle(.tertiary)
                }
            }
            .width(min: 110, ideal: 150)

            TableColumn("CPU", value: \.cpuPercent) { r in
                Text(Fmt.percentValue(r.cpuPercent, decimals: 1)).monospacedDigit()
            }
            .width(66)

            TableColumn("Wake-ups/s", value: \.idleWakeups) { r in
                Text(String(format: "%.0f", r.idleWakeups)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .width(88)
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Filter processes")
        .toolbar {
            ToolbarItem {
                Toggle(isOn: $exactEnabled) {
                    Label("Exact energy", systemImage: "bolt.badge.clock")
                }
                .toggleStyle(.switch)
                .help("Use powermetrics for exact per-process energy (requires root, one-time setup)")
            }
        }
        .navigationTitle("Processes")
        .navigationSubtitle(subtitle)
        .onChange(of: exactEnabled) { _, on in handleToggle(on) }
        .onChange(of: monitor.powerMetrics.status) { _, new in
            if new == .needsSetup { exactEnabled = false; showSetup = true }
            if case .failed = new { exactEnabled = false }
            if new == .running { sortOrder = [KeyPathComparator(\Row.exactSort, order: .reverse)] }
        }
        .sheet(isPresented: $showSetup) { setupSheet }
    }

    private var subtitle: String {
        switch monitor.powerMetrics.status {
        case .running: "Exact per-process energy from powermetrics"
        case .starting: "Starting powermetrics…"
        default: "Energy impact approximated from CPU time and wake-ups"
        }
    }

    private var maxApprox: Double { rows.map(\.approxImpact).max() ?? 1 }
    private var maxExact: Double { rows.compactMap(\.exactImpact).max() ?? 1 }

    private func handleToggle(_ on: Bool) {
        if on {
            if monitor.powerMetrics.isSetUp {
                monitor.setPowerMetrics(true)
            } else {
                exactEnabled = false
                showSetup = true
            }
        } else {
            monitor.setPowerMetrics(false)
            sortOrder = [KeyPathComparator(\Row.approxImpact, order: .reverse)]
        }
    }

    private var setupSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Enable exact energy", systemImage: "bolt.badge.clock")
                .font(.title2.weight(.semibold))
            Text("""
                Exact per-process energy comes from Apple's `powermetrics`, which \
                requires root. MacPower can install a one-time rule that lets it run \
                `powermetrics` without a password prompt each time.
                """)
                .foregroundStyle(.secondary)
            Text("You'll be asked for your administrator password once.")
                .font(.callout).foregroundStyle(.tertiary)
            if let setupError {
                Text(setupError).font(.callout).foregroundStyle(.red)
            }
            HStack {
                Button("Cancel") { showSetup = false }
                Spacer()
                Button("Install & Enable") { install() }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 440)
    }

    private func install() {
        setupError = nil
        if monitor.powerMetrics.installSudoersRule() {
            showSetup = false
            exactEnabled = true
            monitor.setPowerMetrics(true)
        } else {
            setupError = "Setup failed or was cancelled. Please try again."
        }
    }
}

/// A number with an inline bar for quick visual ranking.
private struct ImpactCell: View {
    let value: Double
    let maxValue: Double
    var color: Color = Theme.cpu

    var body: some View {
        HStack(spacing: 8) {
            Text(String(format: "%.1f", value))
                .monospacedDigit()
                .frame(width: 48, alignment: .trailing)
            GeometryReader { geo in
                Capsule()
                    .fill(color.opacity(0.8))
                    .frame(width: geo.size.width * CGFloat(min(1, value / max(maxValue, 0.001))))
            }
            .frame(height: 6)
        }
    }
}
