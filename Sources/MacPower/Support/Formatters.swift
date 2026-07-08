import Foundation

enum Fmt {
    /// Power with adaptive precision: mW below 1 W, otherwise W.
    static func power(_ watts: Double) -> String {
        if watts < 0.0005 { return "0 mW" }
        if watts < 1 { return String(format: "%.0f mW", watts * 1000) }
        return String(format: "%.2f W", watts)
    }

    static func watts(_ watts: Double, decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f W", watts)
    }

    static func percent(_ fraction0to1: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", fraction0to1 * 100)
    }

    static func percentValue(_ value0to100: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f%%", value0to100)
    }

    static func minutes(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    static func mAh(_ value: Int) -> String {
        "\(value) mAh"
    }
}
