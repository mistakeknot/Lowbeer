import XCTest
@testable import Lowbeer

final class ProcessHistoryTests: XCTestCase {

    func testEmptyDefaults() {
        let history = ProcessHistory(capacity: 10)
        XCTAssertEqual(history.count, 0)
        XCTAssertEqual(history.latest, 0)
        XCTAssertEqual(history.peak, 0)
        XCTAssertEqual(history.average, 0)
        XCTAssertTrue(history.samples.isEmpty)
    }

    func testAppendSingle() {
        var history = ProcessHistory(capacity: 10)
        history.append(42.5)
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.latest, 42.5)
        XCTAssertEqual(history.samples, [42.5])
    }

    func testAppendMultiple() {
        var history = ProcessHistory(capacity: 10)
        history.append(10)
        history.append(20)
        history.append(30)
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.latest, 30)
        XCTAssertEqual(history.samples, [10, 20, 30])
    }

    func testAppendFillCapacity() {
        var history = ProcessHistory(capacity: 5)
        for i in 1...5 {
            history.append(Double(i))
        }
        XCTAssertEqual(history.count, 5)
        XCTAssertEqual(history.samples, [1, 2, 3, 4, 5])
    }

    func testAppendWrapAround() {
        var history = ProcessHistory(capacity: 3)
        history.append(1)
        history.append(2)
        history.append(3)
        history.append(4) // overwrites 1
        XCTAssertEqual(history.count, 3)
        XCTAssertEqual(history.samples, [2, 3, 4])
        XCTAssertEqual(history.latest, 4)
    }

    func testSamplesChronological() {
        var history = ProcessHistory(capacity: 4)
        for i in 1...6 {
            history.append(Double(i))
        }
        // Buffer: [5, 6, 3, 4] with index=2, should return [3, 4, 5, 6]
        XCTAssertEqual(history.samples, [3, 4, 5, 6])
    }

    func testPeakReturnsMax() {
        var history = ProcessHistory(capacity: 10)
        history.append(10)
        history.append(90)
        history.append(50)
        XCTAssertEqual(history.peak, 90)
    }

    func testAverageCalculation() {
        var history = ProcessHistory(capacity: 10)
        history.append(10)
        history.append(20)
        history.append(30)
        XCTAssertEqual(history.average, 20, accuracy: 0.001)
    }
}
