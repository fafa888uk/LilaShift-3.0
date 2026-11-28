// SPDX-License-Identifier: GPL-3.0-only
import Dispatch
import XCTest
@testable import GestaltX

final class W8ResourceMetricsTests: XCTestCase {
    func testUnobservedIsNotZeroAndCachedTransactionsAreIgnored() {
        var totals = W8NetworkTotals()
        XCTAssertNil(totals.sent)
        XCTAssertNil(totals.received)
        totals.include(isNetwork: false, sent: [20], received: [200])
        XCTAssertNil(totals.sent)
        XCTAssertNil(totals.received)
    }

    func testTotalsAddRealComponentsAndIgnoreNegativeValues() {
        var totals = W8NetworkTotals()
        totals.include(isNetwork: true, sent: [-1], received: [0])
        XCTAssertNil(totals.sent)
        XCTAssertEqual(totals.received, 0)
        totals.include(isNetwork: true, sent: [10, 20], received: [30, -1])
        totals.include(isNetwork: true, sent: [40], received: [5, 6])
        XCTAssertEqual(totals.sent, 70)
        XCTAssertEqual(totals.received, 41)
    }

    func testTotalsSaturateWithoutWrapping() {
        var totals = W8NetworkTotals()
        totals.include(isNetwork: true, sent: [Int64.max, Int64.max, 10], received: [])
        XCTAssertEqual(totals.sent, UInt64.max)
        XCTAssertNil(totals.received)
    }

    func testPressurePriorityAndUnknown() {
        XCTAssertNil(W8PressureLevel(event: []))
        XCTAssertEqual(W8PressureLevel(event: .normal), .normal)
        XCTAssertEqual(W8PressureLevel(event: [.warning, .normal]), .warning)
        XCTAssertEqual(W8PressureLevel(event: [.critical, .warning]), .critical)
    }
}
