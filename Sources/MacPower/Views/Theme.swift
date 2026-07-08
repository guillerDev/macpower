import SwiftUI

/// Central colour vocabulary so every chart, legend and card reads as one system.
enum Theme {
    static let cpu  = Color(red: 0.30, green: 0.56, blue: 0.98)   // blue
    static let gpu  = Color(red: 0.66, green: 0.42, blue: 0.98)   // violet
    static let ane  = Color(red: 0.18, green: 0.74, blue: 0.72)   // teal
    static let dram = Color(red: 0.96, green: 0.62, blue: 0.26)   // amber

    static let eCore = Color(red: 0.29, green: 0.74, blue: 0.47)  // green
    static let pCore = cpu

    static let system = Color(red: 0.55, green: 0.58, blue: 0.64)  // neutral steel
    static let soc    = Color(red: 0.42, green: 0.47, blue: 0.86)  // indigo
    static let other  = Color(red: 0.60, green: 0.62, blue: 0.66).opacity(0.7)

    static func rail(_ rail: PowerRail) -> Color {
        switch rail {
        case .cpu: cpu
        case .gpu: gpu
        case .ane: ane
        case .dram: dram
        }
    }

    static func cluster(_ cluster: CPUCluster) -> Color {
        cluster == .efficiency ? eCore : pCore
    }
}

enum PowerRail: String, CaseIterable, Identifiable {
    case cpu = "CPU", gpu = "GPU", ane = "ANE", dram = "DRAM"
    var id: String { rawValue }
}

extension EnergyReading {
    func watts(for rail: PowerRail) -> Double {
        switch rail {
        case .cpu: cpuWatts
        case .gpu: gpuWatts
        case .ane: aneWatts
        case .dram: dramWatts
        }
    }
}
