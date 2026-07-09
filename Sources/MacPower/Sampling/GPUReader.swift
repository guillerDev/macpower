import Foundation
import IOKit

/// Reads GPU utilisation and memory from the IOAccelerator's
/// `PerformanceStatistics` dictionary. No privileges required.
enum GPUReader {
    static func read() -> GPUInfo? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOAccelerator"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
            let props = unmanaged?.takeRetainedValue() as? [String: Any],
            let stats = props["PerformanceStatistics"] as? [String: Any]
        else {
            return nil
        }

        var info = GPUInfo()
        func pct(_ key: String) -> Double { Double(stats[key] as? Int ?? 0) / 100 }
        info.utilization = pct("Device Utilization %")
        info.rendererUtil = pct("Renderer Utilization %")
        info.tilerUtil = pct("Tiler Utilization %")
        info.inUseMemory = stats["In use system memory"] as? Int ?? 0
        info.allocatedMemory = stats["Alloc system memory"] as? Int ?? 0
        return info
    }
}
