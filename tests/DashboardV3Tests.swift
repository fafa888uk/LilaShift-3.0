// SPDX-License-Identifier: GPL-3.0-only
// LilaShift landing page ordering and compatibility migration tests.
import XCTest
@testable import GestaltX

final class DashboardV3Tests: XCTestCase {
    func testDefaultOrderingIncludesAllSections() {
        XCTAssertEqual(DashboardV3Destination.resolvedOrder(""), DashboardV3Destination.allCases)
    }

    func testCustomOrderingSurvivesReload() {
        // Stage 14: eight destinations now — the stored order must
        // cover all of them for the round-trip to be exact.
        let desired: [DashboardV3Destination] = [
            .esimRegion, .unlock, .aiOnly, .advanced,
            .siriAIMode, .diagnostics, .restore, .presets,
        ]
        XCTAssertEqual(desired.count, DashboardV3Destination.allCases.count)
        let stored = desired.map(\.rawValue).joined(separator: ",")
        XCTAssertEqual(DashboardV3Destination.resolvedOrder(stored), desired)
    }

    func testUnknownAndDuplicateIdentifiersAreIgnored() {
        let order = DashboardV3Destination.resolvedOrder("restore,invalid,restore,unlock")
        XCTAssertEqual(order.count, DashboardV3Destination.allCases.count)
        XCTAssertEqual(Array(order.prefix(2)), [.restore, .unlock])
        XCTAssertEqual(Set(order).count, order.count)
    }

    func testOlderOrderAutomaticallyReceivesNewSections() {
        let order = DashboardV3Destination.resolvedOrder("unlock,diagnostics")
        XCTAssertEqual(order.count, DashboardV3Destination.allCases.count)
        XCTAssertEqual(Array(order.prefix(2)), [.unlock, .diagnostics])
    }
}
