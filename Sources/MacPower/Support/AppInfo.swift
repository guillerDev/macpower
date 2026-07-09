import Foundation

enum AppInfo {
    /// Marketing version (CFBundleShortVersionString). Works both for the .app
    /// bundle and the bare executable (via the embedded __info_plist section).
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
    }
}
