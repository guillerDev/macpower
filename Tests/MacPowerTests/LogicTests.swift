import XCTest

@testable import MacPower

/// Pure-logic tests: channel classification, unit conversion, and formatting.
/// These need no SMC/IOReport hardware, so they run on any CI runner.
final class LogicTests: XCTestCase {

    // MARK: IOReport channel classification

    func testAggregateChannels() {
        XCTAssertEqual(IOReportSampler.classify("CPU Energy"), .cpuTotal)
        XCTAssertEqual(IOReportSampler.classify("GPU Energy"), .gpuTotal)
        XCTAssertEqual(IOReportSampler.classify("ANE0"), .ane)
        XCTAssertEqual(IOReportSampler.classify("DRAM0"), .dram)
    }

    func testPerCoreChannels() {
        XCTAssertEqual(IOReportSampler.classify("EACC_CPU0"), .eCore(0))
        XCTAssertEqual(IOReportSampler.classify("EACC_CPU1"), .eCore(1))
        XCTAssertEqual(IOReportSampler.classify("PACC0_CPU2"), .pCore(cluster: 0, core: 2))
        XCTAssertEqual(IOReportSampler.classify("PACC1_CPU0"), .pCore(cluster: 1, core: 0))
    }

    func testClusterSumsAreIgnored() {
        // Cluster totals have no trailing core digit — must not be counted as cores.
        XCTAssertEqual(IOReportSampler.classify("EACC_CPU"), .ignore)
        XCTAssertEqual(IOReportSampler.classify("PACC0_CPU"), .ignore)
        XCTAssertEqual(IOReportSampler.classify("EACC_CPM"), .ignore)
        XCTAssertEqual(IOReportSampler.classify("Nonsense"), .ignore)
    }

    // MARK: Energy unit conversion (to nanojoules)

    func testUnitConversion() {
        XCTAssertEqual(IOReportSampler.nanojoules(1, unit: "mJ"), 1_000_000)
        XCTAssertEqual(IOReportSampler.nanojoules(1, unit: "uJ"), 1_000)
        XCTAssertEqual(IOReportSampler.nanojoules(1, unit: "nJ"), 1)
        XCTAssertEqual(IOReportSampler.nanojoules(1, unit: "J"), 1_000_000_000)
        // Unknown unit falls back to mJ.
        XCTAssertEqual(IOReportSampler.nanojoules(1, unit: "??"), 1_000_000)
    }

    // MARK: Formatting

    func testPowerFormatting() {
        XCTAssertEqual(Fmt.power(0), "0 mW")
        XCTAssertEqual(Fmt.power(0.5), "500 mW")
        XCTAssertEqual(Fmt.power(2.5), "2.50 W")
    }

    func testPercentAndMinutes() {
        XCTAssertEqual(Fmt.percent(0.5), "50%")
        XCTAssertEqual(Fmt.minutes(90), "1h 30m")
        XCTAssertEqual(Fmt.minutes(45), "45m")
    }

    // MARK: Battery registry layouts

    func testBatteryMacOS26Layout() {
        let info = BatteryReader.parse([
            "BatteryInstalled": true, "DesignCapacity": 6075, "AppleRawMaxCapacity": 5103,
            "AppleRawCurrentCapacity": 4000, "MaxCapacity": 100, "CurrentCapacity": 78, "Temperature": 3150,
        ])
        XCTAssertEqual(info.health, 5103.0 / 6075 * 100, accuracy: 1e-9)
        XCTAssertEqual(info.currentCapacity, 4000)
        XCTAssertEqual(info.charge, 78)
        XCTAssertEqual(info.temperature, 31.5)
    }

    func testBatteryMacOS27Layout() {
        // macOS 27 drops the top-level mAh keys and Temperature; BatteryData keeps them.
        let info = BatteryReader.parse([
            "BatteryInstalled": true, "MaxCapacity": 100, "CurrentCapacity": 80,
            "BatteryData": [
                "DesignCapacity": 6075, "NominalChargeCapacity": 4993, "FullChargeCapacity": 4843,
                "RemainingCapacity": 3809, "MaxCapacity": 100,
            ] as [String: Any],
        ])
        XCTAssertEqual(info.designCapacity, 6075)
        XCTAssertEqual(info.maxCapacity, 4993)
        XCTAssertEqual(info.health, 4993.0 / 6075 * 100, accuracy: 1e-9)  // not 0, not 100/6075
        XCTAssertEqual(info.currentCapacity, 3809)
        XCTAssertEqual(info.charge, 80)
        XCTAssertNil(info.temperature)  // filled from the SMC by SamplingEngine
    }

    // MARK: powermetrics sudoers rule

    func testSudoersRuleAllowsOnlyExactCommandLines() {
        let rule = PowerMetricsService.sudoersRule(user: "alice", intervalsMs: [500, 1000])
        XCTAssertEqual(
            rule,
            "alice ALL=(root) NOPASSWD: "
                + "/usr/bin/powermetrics --samplers tasks -f plist -i 500, "
                + "/usr/bin/powermetrics --samplers tasks -f plist -i 1000")
        // A wildcard (or a bare command) would also match `-o <file>` — a root file write.
        XCTAssertFalse(rule.contains("*"))
    }

    func testSudoersRuleCoversEverySelectableInterval() {
        let intervalsMs = PowerMonitor.intervalChoices.map { Int($0 * 1000) }
        let rule = PowerMetricsService.sudoersRule(user: "alice", intervalsMs: intervalsMs)
        for ms in intervalsMs {
            // The exact argv `start(intervalMs:)` runs must appear in the rule.
            let command = (["/usr/bin/powermetrics"] + PowerMetricsService.arguments(intervalMs: ms))
                .joined(separator: " ")
            XCTAssertTrue(rule.contains(command + ",") || rule.hasSuffix(command), command)
        }
    }

    func testInstallScriptIsValidShell() throws {
        let script = PowerMetricsService.installScript(
            rule: PowerMetricsService.sudoersRule(user: "alice", intervalsMs: [1000]),
            path: "/etc/sudoers.d/test", legacyPath: "/etc/sudoers.d/legacy")
        XCTAssertFalse(script.contains("/tmp/macpower.sudoers"), "must not use a predictable temp path")

        let sh = Process()
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-n", "-c", script]  // parse only, never execute
        try sh.run()
        sh.waitUntilExit()
        XCTAssertEqual(sh.terminationStatus, 0)
    }

    func testAdminAppleScriptEscaping() {
        XCTAssertEqual(
            PowerMetricsService.adminAppleScript(running: #"printf '%s\n' "$t""#),
            #"do shell script "printf '%s\\n' \"$t\"" with administrator privileges"#)
    }
}
