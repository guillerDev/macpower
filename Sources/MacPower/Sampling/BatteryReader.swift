import Foundation
import IOKit

struct BatteryInfo {
    var isInstalled: Bool = false
    var charge: Double = 0            // %
    var health: Double = 0            // % of design capacity
    var cycleCount: Int = 0
    var designCapacity: Int = 0       // mAh
    var maxCapacity: Int = 0          // mAh (current full-charge capacity)
    var currentCapacity: Int = 0      // mAh
    var voltage: Double = 0           // V
    var amperage: Double = 0          // A (positive = charging)
    var temperature: Double = 0       // °C
    var isCharging: Bool = false
    var externalConnected: Bool = false
    var fullyCharged: Bool = false
    var timeToFull: Int?              // minutes
    var timeToEmpty: Int?             // minutes
    var condition: String = "Normal"
    var serial: String?

    /// Signed power flowing in/out of the pack, in watts.
    var powerWatts: Double { voltage * amperage }
}

/// Reads battery details from the IOKit `AppleSmartBattery` service. No
/// privileges required.
enum BatteryReader {
    static func read() -> BatteryInfo? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                  IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = unmanaged?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        var info = BatteryInfo()
        info.isInstalled = (props["BatteryInstalled"] as? Bool) ?? false

        let design = props["DesignCapacity"] as? Int ?? 0
        // On Apple Silicon the true mAh figures live under the Apple-prefixed keys.
        let rawMax = props["AppleRawMaxCapacity"] as? Int ?? props["MaxCapacity"] as? Int ?? 0
        let rawCur = props["AppleRawCurrentCapacity"] as? Int ?? props["CurrentCapacity"] as? Int ?? 0

        info.designCapacity = design
        info.maxCapacity = rawMax
        info.currentCapacity = rawCur

        if let pct = props["CurrentCapacity"] as? Int, (props["MaxCapacity"] as? Int) == 100 {
            info.charge = Double(pct)                          // already a percentage
        } else if rawMax > 0 {
            info.charge = Double(rawCur) / Double(rawMax) * 100
        }
        if design > 0 { info.health = Double(rawMax) / Double(design) * 100 }

        info.cycleCount = props["CycleCount"] as? Int ?? 0
        info.voltage = Double(props["Voltage"] as? Int ?? 0) / 1000.0
        info.amperage = Double(props["Amperage"] as? Int ?? 0) / 1000.0
        if let temp = props["Temperature"] as? Int { info.temperature = Double(temp) / 100.0 }
        info.isCharging = (props["IsCharging"] as? Bool) ?? false
        info.externalConnected = (props["ExternalConnected"] as? Bool) ?? false
        info.fullyCharged = (props["FullyCharged"] as? Bool) ?? false
        info.serial = props["Serial"] as? String

        if let t = props["AvgTimeToFull"] as? Int, t > 0, t != 65535 { info.timeToFull = t }
        if let t = props["AvgTimeToEmpty"] as? Int, t > 0, t != 65535 { info.timeToEmpty = t }

        if let cond = props["BatteryHealthCondition"] as? String, !cond.isEmpty {
            info.condition = cond
        } else if let perm = props["PermanentFailureStatus"] as? Int, perm != 0 {
            info.condition = "Service Recommended"
        }

        return info
    }
}
