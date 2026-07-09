import CSMC
import Foundation

/// Reads temperatures, fan speeds and total system power from the SMC. Relevant
/// sensor keys are discovered once at init (they are model-specific) and only
/// those are re-read each tick.
final class SMCReader {
    private let available: Bool
    private var cpuKeys: [String] = []
    private var gpuKeys: [String] = []
    private var batteryKeys: [String] = []
    private var enclosureKeys: [String] = []
    private var fanCount = 0

    init() {
        available = smc_open()
        guard available else { return }
        discoverKeys()
        fanCount = Int(readValue("FNum") ?? 0)
    }

    deinit { if available { smc_close() } }

    func read() -> ThermalInfo? {
        guard available else { return ThermalInfo(thermalState: ProcessInfo.processInfo.thermalState) }
        var info = ThermalInfo()
        info.thermalState = ProcessInfo.processInfo.thermalState
        info.cpuTemp = average(cpuKeys)
        info.gpuTemp = average(gpuKeys)
        info.batteryTemp = average(batteryKeys)
        info.enclosureTemp = average(enclosureKeys)
        info.systemPower = readValue("PSTR")
        info.adapterPower = readValue("PDTR")

        var fans: [FanInfo] = []
        for i in 0..<fanCount {
            let rpm = readValue("F\(i)Ac") ?? 0
            let minRPM = readValue("F\(i)Mn") ?? 0
            let maxRPM = readValue("F\(i)Mx") ?? 0
            fans.append(FanInfo(id: i, rpm: rpm, minRPM: minRPM, maxRPM: maxRPM))
        }
        info.fans = fans
        return info
    }

    // MARK: - Key discovery

    private func discoverKeys() {
        let count = Int(smc_key_count())
        guard count > 0, count < 10_000 else { return }
        var keyBuf = [CChar](repeating: 0, count: 5)
        var typeBuf = [CChar](repeating: 0, count: 5)
        var value = 0.0

        for i in 0..<count {
            guard smc_key_at_index(Int32(i), &keyBuf) else { continue }
            let key = String(cString: keyBuf)
            guard key.hasPrefix("T") else { continue }
            // Only keep float temperature sensors with a plausible reading.
            guard smc_read(key, &typeBuf, &value),
                String(cString: typeBuf) == "flt ",
                value > 0, value < 150
            else { continue }

            switch key.prefix(2) {
            case "Tp": cpuKeys.append(key)
            case "Tg": gpuKeys.append(key)
            case "TB": batteryKeys.append(key)
            case "Ts": enclosureKeys.append(key)
            default: break
            }
        }
    }

    // MARK: - Reads

    private func readValue(_ key: String) -> Double? {
        var typeBuf = [CChar](repeating: 0, count: 5)
        var value = 0.0
        return smc_read(key, &typeBuf, &value) ? value : nil
    }

    private func average(_ keys: [String]) -> Double? {
        let values = keys.compactMap { readValue($0) }.filter { $0 > 0 && $0 < 150 }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }
}
