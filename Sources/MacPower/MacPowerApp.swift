import AppKit
import SwiftUI

@main
struct MacPowerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var monitor = PowerMonitor()

    var body: some Scene {
        // `Window` (not `WindowGroup`) guarantees a single main window: opening it
        // again from the menu bar just brings the existing one forward.
        Window("MacPower", id: "main") {
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
                Picker("Smoothing (average window)", selection: $monitor.averagingSeconds) {
                    Text("Off").tag(0.0)
                    Text("5 s").tag(5.0)
                    Text("10 s").tag(10.0)
                    Text("30 s").tag(30.0)
                }
            }
            CommandGroup(replacing: .help) {
                HelpMenuCommands()
            }
        }

        MenuBarExtra {
            MenuBarView(monitor: monitor)
        } label: {
            // Isolated in its own view so per-tick reading updates don't
            // invalidate the scene body (which would close open menus).
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        // In-app help (opened from the Help menu). Single window.
        Window("MacPower Help", id: "help") {
            HelpView()
                .frame(width: 560, height: 640)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

/// SwiftPM executables launch as accessory apps; promote to a normal foreground
/// app so the window appears and takes focus.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Keep the app (and its menu-bar item) alive after the window is closed, so
    // MacPower behaves like a menu-bar utility. Quit via the popover's Quit
    // button or ⌘Q. Sampling continues because PowerMonitor owns its own Task,
    // independent of any window.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
