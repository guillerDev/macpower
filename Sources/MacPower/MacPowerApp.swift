import SwiftUI
import AppKit

@main
struct MacPowerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor = PowerMonitor()

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView(monitor: monitor)
                .frame(minWidth: 820, minHeight: 560)
                .task { monitor.start() }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(after: .toolbar) {
                Picker("Sampling interval", selection: $monitor.interval) {
                    Text("0.5 s").tag(0.5)
                    Text("1 s").tag(1.0)
                    Text("2 s").tag(2.0)
                    Text("5 s").tag(5.0)
                }
            }
        }

        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            // Live total-system wattage in the menu bar (falls back to SoC power
            // when the SMC total isn't available).
            let total = monitor.snapshot.thermal?.systemPower ?? monitor.snapshot.energy.socWatts
            Image(systemName: "bolt.fill")
            Text(Fmt.power(total))
        }
        .menuBarExtraStyle(.window)
    }
}

/// SwiftPM executables launch as accessory apps; promote to a normal foreground
/// app so the window appears and takes focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
