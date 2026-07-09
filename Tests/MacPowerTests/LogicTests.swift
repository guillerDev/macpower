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
}
