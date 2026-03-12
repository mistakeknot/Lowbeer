import XCTest
@testable import Lowbeer

final class PowerSamplerTests: XCTestCase {

    // MARK: - PowerSample

    func testPowerSampleZero() {
        let sample = PowerSample.zero
        XCTAssertEqual(sample.totalWatts, 0)
        XCTAssertEqual(sample.cpuWatts, 0)
        XCTAssertEqual(sample.gpuWatts, 0)
        XCTAssertEqual(sample.aneWatts, 0)
        XCTAssertEqual(sample.dramWatts, 0)
        XCTAssertEqual(sample.packageWatts, 0)
    }

    func testPowerSampleTotalWatts() {
        let sample = PowerSample(
            timestamp: 1, cpuWatts: 3.0, gpuWatts: 1.5, aneWatts: 0.5,
            dramWatts: 0.3, packageWatts: 5.3, pCoreWatts: 2.5, eCoreWatts: 0.5
        )
        XCTAssertEqual(sample.totalWatts, 5.3, accuracy: 0.001)
        XCTAssertEqual(sample.cpuWatts, 3.0)
        XCTAssertEqual(sample.pCoreWatts, 2.5)
        XCTAssertEqual(sample.eCoreWatts, 0.5)
    }

    // MARK: - PowerSampler Initialization

    func testPowerSamplerInitializes() {
        let sampler = PowerSampler()
        // IOReport may or may not be available depending on the system.
        // On Apple Silicon macOS 14+, it should be available.
        // On CI or Intel, it won't be.
        // We just verify initialization doesn't crash.
        _ = sampler.isIOReportAvailable
    }

    func testInitialSampleIsZero() {
        let sampler = PowerSampler()
        let initial = sampler.latestSample
        XCTAssertEqual(initial.totalWatts, 0)
    }

    // MARK: - Sampling (integration — only meaningful on Apple Silicon)

    func testSampleReturnsNonNegativeValues() {
        let sampler = PowerSampler()
        guard sampler.isIOReportAvailable else {
            // Skip on systems without IOReport (Intel, CI)
            return
        }

        // Need a small delay between init (baseline) and first sample
        Thread.sleep(forTimeInterval: 0.5)
        let sample = sampler.sample()

        XCTAssertGreaterThanOrEqual(sample.cpuWatts, 0)
        XCTAssertGreaterThanOrEqual(sample.gpuWatts, 0)
        XCTAssertGreaterThanOrEqual(sample.aneWatts, 0)
        XCTAssertGreaterThanOrEqual(sample.dramWatts, 0)
        XCTAssertGreaterThanOrEqual(sample.totalWatts, 0)
    }

    func testSampleOnAppleSiliconReturnsReasonableValues() {
        let sampler = PowerSampler()
        guard sampler.isIOReportAvailable else { return }

        Thread.sleep(forTimeInterval: 1.0)
        let sample = sampler.sample()

        // A Mac doing basically nothing should draw 1-15W total CPU+GPU+ANE+DRAM.
        // During tests it might spike higher. Just verify it's in a sane range.
        XCTAssertLessThan(sample.totalWatts, 100,
            "Total watts \(sample.totalWatts)W seems unreasonably high")

        // If we got any reading at all, CPU should be non-zero
        // (the test runner itself uses CPU)
        if sample.totalWatts > 0 {
            XCTAssertGreaterThan(sample.cpuWatts, 0,
                "CPU watts should be non-zero while running tests")
        }
    }

    // MARK: - Fallback behavior

    func testSampleWithoutIOReportReturnsZero() {
        let sampler = PowerSampler()
        if !sampler.isIOReportAvailable {
            let sample = sampler.sample()
            XCTAssertEqual(sample.totalWatts, 0,
                "Without IOReport, sample should return zero")
        }
    }
}
