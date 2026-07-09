import SwiftUI

enum HelpLinks {
    // Update these to your repository once published.
    static let repo = URL(string: "https://github.com/guillerdev/macpower")!
    static let issues = URL(string: "https://github.com/guillerdev/macpower/issues")!
}

/// Contents of the Help menu (replaces the default "AppName Help" item).
struct HelpMenuCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("MacPower Help") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "help")
        }
        .keyboardShortcut("?", modifiers: .command)

        Divider()
        Link("MacPower on GitHub", destination: HelpLinks.repo)
        Link("Report an Issue…", destination: HelpLinks.issues)
    }
}

/// An in-app help window explaining the app and its concepts.
struct HelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                topic("What MacPower shows", "bolt.fill") {
                    Text("MacPower reads live power, temperature and utilisation "
                         + "from your Mac and visualises where energy is going. "
                         + "Everything runs with **no special privileges** — the "
                         + "only exception is the optional exact per-process mode.")
                }

                topic("Sections", "sidebar.left") {
                    bullet("Overview", "The power-flow Sankey and a stacked power-over-time chart. Click any metric card to focus its flow.")
                    bullet("CPU", "Per-core utilisation and power, grouped into efficiency (E) and performance (P) clusters.")
                    bullet("GPU", "Utilisation (device / renderer / tiler), power, and memory.")
                    bullet("Processes", "Processes ranked by energy impact. Approximate by default; toggle Exact energy for powermetrics figures.")
                    bullet("Battery", "Charge, health, cycle count, condition, capacity, and live power flow.")
                    bullet("Thermal", "Thermal-pressure state, temperatures, fan RPM, and total system power.")
                }

                topic("Reading the power flow", "point.topleft.down.to.point.bottomright.curvepath") {
                    bullet("System", "Total power drawn by the whole Mac (measured at the SMC).")
                    bullet("SoC", "The chip itself — the sum of CPU + GPU + ANE + DRAM.")
                    bullet("Other", "Everything outside the chip: display, storage, Wi-Fi/Bluetooth, peripherals, and power-conversion losses. These can't be measured individually.")
                    bullet("ANE", "Apple Neural Engine — the ML accelerator. Near 0 W unless a model is running (Face ID, photo analysis, Core ML apps).")
                    bullet("E / P cores", "Efficiency cores handle light background work; performance cores handle demanding tasks.")
                }

                topic("Per-process energy", "list.bullet.rectangle") {
                    Text("**Approximate (default)** is estimated from each process's "
                         + "CPU time and idle wake-ups — no root, instant.")
                    Text("**Exact** uses Apple's `powermetrics` (requires root). The "
                         + "first time you enable it, MacPower installs a one-time "
                         + "passwordless rule via a single admin prompt.")
                        .padding(.top, 2)
                }

                topic("Smoothing", "waveform.path.ecg") {
                    Text("Headline numbers show a trailing average (default 10 s) so "
                         + "they don't flicker each second. Change it under "
                         + "**View → Smoothing**. The power-over-time chart always "
                         + "shows the raw per-sample signal.")
                }

                topic("Menu bar", "menubar.arrow.up.rectangle") {
                    Text("The menu-bar item shows live total system power; its popover "
                         + "breaks it down. Closing the window keeps MacPower running "
                         + "in the menu bar — quit from the popover's Quit button or ⌘Q.")
                }

                topic("Privacy", "lock.shield") {
                    Text("All readings stay on your Mac. MacPower makes no network "
                         + "connections and collects no data.")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.cpu)
            VStack(alignment: .leading, spacing: 2) {
                Text("MacPower").font(.title.weight(.semibold))
                Text("Live macOS power-consumption visualiser · v\(AppInfo.version)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func topic<Content: View>(_ title: String, _ icon: String,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.headline)
            content()
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bullet(_ term: String, _ desc: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("•")
            (Text(term).fontWeight(.semibold).foregroundStyle(.primary)
             + Text(" — \(desc)"))
        }
    }
}
