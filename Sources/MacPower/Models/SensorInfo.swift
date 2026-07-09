import Foundation

struct FanInfo: Identifiable {
    let id: Int
    let rpm: Double
    let minRPM: Double
    let maxRPM: Double
    /// 0...1 position between min and max.
    var fraction: Double {
        guard maxRPM > minRPM else { return 0 }
        return min(1, max(0, (rpm - minRPM) / (maxRPM - minRPM)))
    }
}

struct ThermalInfo {
    var thermalState: ProcessInfo.ThermalState = .nominal
    var cpuTemp: Double?
    var gpuTemp: Double?
    var batteryTemp: Double?
    var enclosureTemp: Double?
    var fans: [FanInfo] = []
    var systemPower: Double?  // PSTR — true total system draw, in watts
    var adapterPower: Double?  // PDTR — DC-in (wall adapter) input power, in watts

    var thermalStateLabel: String {
        switch thermalState {
        case .nominal: "Nominal"
        case .fair: "Fair"
        case .serious: "Serious"
        case .critical: "Critical"
        @unknown default: "Unknown"
        }
    }
}

struct GPUInfo {
    var utilization: Double = 0  // 0...1 (Device Utilization %)
    var rendererUtil: Double = 0
    var tilerUtil: Double = 0
    var inUseMemory: Int = 0  // bytes
    var allocatedMemory: Int = 0  // bytes
}
