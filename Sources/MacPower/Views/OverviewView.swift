import SwiftUI
import Charts

struct OverviewView: View {
    var monitor: PowerMonitor

    private var energy: EnergyReading { monitor.snapshot.energy }

    /// Total wall power from the SMC (PSTR), if it meaningfully exceeds the SoC
    /// figure. When present, the diagram gains a System root that splits into the
    /// SoC and the non-SoC remainder.
    private var systemWatts: Double? {
        guard let p = monitor.snapshot.thermal?.systemPower, p > energy.socWatts + 0.05 else { return nil }
        return p
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                totals
                Card(title: "Power flow", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                    SankeyView(nodes: sankeyNodes, links: sankeyLinks)
                        .frame(height: 300)
                        .padding(.vertical, 4)
                    legend
                }
                if !sourceNodes.isEmpty {
                    Card(title: "Power source", systemImage: "powerplug") {
                        SankeyView(nodes: sourceNodes, links: sourceLinks)
                            .frame(height: 120)
                            .padding(.vertical, 4)
                        Text(sourceCaption)
                            .font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Card(title: "Power over time", systemImage: "waveform.path.ecg") {
                    historyChart
                        .frame(height: 200)
                }
            }
            .padding(16)
        }
        .navigationTitle("Overview")
    }

    // MARK: - Totals row

    private var totals: some View {
        HStack(spacing: 12) {
            if let sys = systemWatts {
                Card {
                    StatTile(title: "Total system",
                             value: Fmt.power(sys),
                             caption: "wall power (SMC)",
                             color: Theme.system)
                }
            }
            Card {
                StatTile(title: "SoC power",
                         value: Fmt.power(energy.socWatts),
                         caption: "CPU + GPU + ANE + DRAM",
                         color: Theme.soc)
            }
            ForEach(PowerRail.allCases) { rail in
                Card {
                    StatTile(title: rail.rawValue,
                             value: Fmt.power(energy.watts(for: rail)),
                             color: Theme.rail(rail))
                }
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(PowerRail.allCases) { rail in
                HStack(spacing: 5) {
                    Circle().fill(Theme.rail(rail)).frame(width: 8, height: 8)
                    Text(rail.rawValue).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Sankey graph

    private func w(_ value: Double) -> Double { max(value, 0.0001) }

    private var sankeyNodes: [SankeyNode] {
        // SoC sits at column 0, or column 1 when a System root is present.
        let socColumn = systemWatts == nil ? 0 : 1
        var nodes: [SankeyNode] = []

        if let sys = systemWatts {
            nodes.append(SankeyNode(id: "system", label: "System", column: 0,
                                    value: w(sys), color: Theme.system))
            let other = sys - energy.socWatts
            nodes.append(SankeyNode(id: "other", label: "Other", column: 1,
                                    value: w(other), color: Theme.other))
        }

        nodes.append(SankeyNode(id: "soc", label: "SoC", column: socColumn,
                                value: w(energy.socWatts), color: Theme.soc))

        for rail in PowerRail.allCases {
            nodes.append(SankeyNode(id: rail.rawValue, label: rail.rawValue, column: socColumn + 1,
                                    value: w(energy.watts(for: rail)), color: Theme.rail(rail)))
        }
        if energy.cpuWatts > 0.0005 {
            nodes.append(SankeyNode(id: "ecluster", label: "E-cores", column: socColumn + 2,
                                    value: w(monitor.snapshot.eClusterWatts), color: Theme.eCore))
            nodes.append(SankeyNode(id: "pcluster", label: "P-cores", column: socColumn + 2,
                                    value: w(monitor.snapshot.pClusterWatts), color: Theme.pCore))
        }
        return nodes
    }

    private var sankeyLinks: [SankeyLink] {
        var links: [SankeyLink] = []

        if let sys = systemWatts {
            links.append(SankeyLink(source: "system", target: "soc", value: w(energy.socWatts)))
            links.append(SankeyLink(source: "system", target: "other", value: w(sys - energy.socWatts)))
        }
        for rail in PowerRail.allCases {
            links.append(SankeyLink(source: "soc", target: rail.rawValue,
                                    value: w(energy.watts(for: rail))))
        }
        if energy.cpuWatts > 0.0005 {
            links.append(SankeyLink(source: "CPU", target: "ecluster",
                                    value: w(monitor.snapshot.eClusterWatts)))
            links.append(SankeyLink(source: "CPU", target: "pcluster",
                                    value: w(monitor.snapshot.pClusterWatts)))
        }
        return links
    }

    // MARK: - Power source flow (adapter / battery)

    private var adapterWatts: Double? { monitor.snapshot.thermal?.adapterPower }
    private var systemWattsRaw: Double? { monitor.snapshot.thermal?.systemPower }

    private var onAC: Bool {
        (monitor.snapshot.battery?.externalConnected ?? false) && (adapterWatts ?? 0) > 0.1
    }

    private var sourceNodes: [SankeyNode] {
        guard let sys = systemWattsRaw, sys > 0.05 else { return [] }
        var nodes: [SankeyNode] = []
        if onAC, let adapter = adapterWatts {
            nodes.append(SankeyNode(id: "adapter", label: "Adapter", column: 0,
                                    value: w(adapter), color: Theme.eCore))
            nodes.append(SankeyNode(id: "sys", label: "System", column: 1,
                                    value: w(min(sys, adapter)), color: Theme.system))
            let toBattery = adapter - sys
            if toBattery > 0.1 {
                nodes.append(SankeyNode(id: "batt", label: "Battery", column: 1,
                                        value: w(toBattery), color: Theme.ane))
            }
        } else {
            // Running on the battery: it is the source powering the system.
            nodes.append(SankeyNode(id: "batt", label: "Battery", column: 0,
                                    value: w(sys), color: Theme.dram))
            nodes.append(SankeyNode(id: "sys", label: "System", column: 1,
                                    value: w(sys), color: Theme.system))
        }
        return nodes
    }

    private var sourceLinks: [SankeyLink] {
        guard let sys = systemWattsRaw, sys > 0.05 else { return [] }
        if onAC, let adapter = adapterWatts {
            var links = [SankeyLink(source: "adapter", target: "sys", value: w(min(sys, adapter)))]
            let toBattery = adapter - sys
            if toBattery > 0.1 {
                links.append(SankeyLink(source: "adapter", target: "batt", value: w(toBattery)))
            }
            return links
        } else {
            return [SankeyLink(source: "batt", target: "sys", value: w(sys))]
        }
    }

    private var sourceCaption: String {
        guard let sys = systemWattsRaw else { return "" }
        if onAC, let adapter = adapterWatts {
            let toBattery = max(0, adapter - sys)
            if toBattery > 0.1 {
                return "Adapter delivers \(Fmt.watts(adapter, decimals: 1)); "
                    + "\(Fmt.watts(sys, decimals: 1)) runs the system, "
                    + "\(Fmt.watts(toBattery, decimals: 1)) charges the battery (incl. losses)."
            }
            return "On adapter power (\(Fmt.watts(adapter, decimals: 1))); battery not charging."
        }
        return "Running on battery — \(Fmt.watts(sys, decimals: 1)) drawn from the pack."
    }

    // MARK: - History chart

    private struct Series: Identifiable {
        let id: String
        let date: Date
        let rail: String
        let watts: Double
    }

    private var seriesData: [Series] {
        monitor.history.flatMap { point in
            [
                Series(id: "cpu\(point.id)", date: point.id, rail: "CPU", watts: point.cpu),
                Series(id: "gpu\(point.id)", date: point.id, rail: "GPU", watts: point.gpu),
                Series(id: "ane\(point.id)", date: point.id, rail: "ANE", watts: point.ane),
                Series(id: "dram\(point.id)", date: point.id, rail: "DRAM", watts: point.dram)
            ]
        }
    }

    private var historyChart: some View {
        Chart(seriesData) { item in
            AreaMark(
                x: .value("Time", item.date),
                y: .value("Watts", item.watts)
            )
            .foregroundStyle(by: .value("Rail", item.rail))
            .interpolationMethod(.monotone)
        }
        .chartForegroundStyleScale([
            "CPU": Theme.cpu, "GPU": Theme.gpu, "ANE": Theme.ane, "DRAM": Theme.dram
        ])
        .chartYAxisLabel("Watts")
        .chartLegend(.hidden)
        .overlay {
            if monitor.history.count < 2 {
                ContentUnavailableView("Collecting samples…",
                                       systemImage: "clock",
                                       description: Text("Power history will appear after a few seconds."))
            }
        }
    }
}
