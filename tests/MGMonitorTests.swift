// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

/// MGMonitor + VersionSentinel tests (Stage 4, ADR-2-09).
///
/// The sentinel boundary is the fact that matters: iOS 27.3 beta 2
/// (build 24C5049d) is the first build where Apple blocked
/// worse_query. The three-source comparison is tested with real
/// database records and synthetic values — no device needed.
final class MGMonitorTests: XCTestCase {
    private var regionRecord: MGKeyRecord {
        MGDatabase.record(forKey: GestaltKeys.regionCode)!
    }

    private func input(record: MGKeyRecord = MGDatabase.record(forKey: GestaltKeys.regionCode)!,
                       original: MGValue? = .string("LL"), staged: MGValue? = .string("LL"),
                       live: MGValue? = .string("LL"), liveReadAt: Date? = Date(),
                       slot: MGSlotProbe? = nil, productType: String? = "iPhone18,4",
                       iosVersion: String = "27.0.1",
                       sentinel: VersionSentinelState = .supported) -> MGMonitorInput {
        MGMonitorInput(record: record, original: original, staged: staged, live: live,
                       liveReadAt: liveReadAt, slot: slot, productType: productType,
                       iosVersion: iosVersion, sentinel: sentinel)
    }

    // MARK: - Version sentinel

    func testSentinelBoundaryIs24C5049d() {
        XCTAssertEqual(VersionSentinel.state(forBuild: "24C5049d"), .blocked(build: "24C5049d"))
        XCTAssertEqual(VersionSentinel.state(forBuild: "24C5049c"), .supported)
        XCTAssertEqual(VersionSentinel.state(forBuild: "24C5049e"), .blocked(build: "24C5049e"))
        XCTAssertEqual(VersionSentinel.state(forBuild: "24C5035a"), .supported)
        XCTAssertEqual(VersionSentinel.state(forBuild: "23A344"), .supported)
    }

    func testSentinelBareBuildOfBlockedBetaStaysBlocked() {
        // A bare build number is the finalized build of that number;
        // a finalized build of a blocked beta stays blocked.
        XCTAssertEqual(VersionSentinel.state(forBuild: "24C5049"), .blocked(build: "24C5049"))
    }

    func testSentinelNewerTrainIsBlockedFailClosed() {
        XCTAssertEqual(VersionSentinel.state(forBuild: "25A100a"), .blocked(build: "25A100a"))
        XCTAssertEqual(VersionSentinel.state(forBuild: "24D1000a"), .blocked(build: "24D1000a"))
    }

    func testSentinelUnknownBuilds() {
        XCTAssertEqual(VersionSentinel.state(forBuild: "abc"), .unknownBuild(build: "abc"))
        XCTAssertEqual(VersionSentinel.state(forBuild: ""), .unknownBuild(build: ""))
        XCTAssertEqual(VersionSentinel.state(forBuild: nil), .unknownBuild(build: ""))
    }

    func testSentinelGuidance() {
        XCTAssertNil(VersionSentinel.guidance(for: .supported))
        XCTAssertNotNil(VersionSentinel.guidance(for: .blocked(build: "24C5049d")))
        XCTAssertNotNil(VersionSentinel.guidance(for: .unknownBuild(build: "abc")))
    }

    func testSentinelBlockedNeverProducesAnEmptyList() {
        let rows = MGMonitor.rows(for: MGDatabase.all.map { record in
            input(record: record, original: nil, staged: nil, live: nil,
                  sentinel: .blocked(build: "24C5049d"))
        })
        XCTAssertEqual(rows.count, 77, "A blocked build still lists every key")
        XCTAssertTrue(rows.allSatisfy { $0.compatibility == .readFailed })
    }

    // MARK: - Three-source comparison

    func testNoDifferenceWhenAllSourcesAgree() {
        XCTAssertFalse(MGMonitor.row(for: input()).hasDifference)
    }

    func testStagedChangeIsADifference() {
        XCTAssertTrue(MGMonitor.row(for: input(staged: .string("CH"))).hasDifference)
    }

    func testStagedDeletionIsADifference() {
        XCTAssertTrue(MGMonitor.row(for: input(staged: nil)).hasDifference)
    }

    func testLiveDisagreementIsADifference() {
        XCTAssertTrue(MGMonitor.row(for: input(live: .string("CH"))).hasDifference)
    }

    func testAbsentSourcesAreNotDifferences() {
        // Nothing recorded anywhere: no staged change, no live answer.
        XCTAssertFalse(MGMonitor.row(for: input(original: nil, staged: nil, live: nil)).hasDifference)
        // A live answer with nothing staged is not a staged change.
        XCTAssertFalse(MGMonitor.row(for: input(original: nil, staged: nil, live: .string("LL"))).hasDifference)
        // An unreadable live value is not a difference.
        XCTAssertFalse(MGMonitor.row(for: input(live: nil)).hasDifference)
    }

    func testSlotLiveDisagreementIsADifference() {
        let slot = MGSlotProbe(slotNumber: 178, originalByte: false, stagedByte: false,
                               liveAnswer: true, nativeBaseline: false)
        XCTAssertTrue(MGMonitor.row(for: input(slot: slot)).hasDifference)
        let agreeing = MGSlotProbe(slotNumber: 178, originalByte: false, stagedByte: false,
                                   liveAnswer: false, nativeBaseline: false)
        XCTAssertFalse(MGMonitor.row(for: input(slot: agreeing)).hasDifference)
    }

    func testSlotDisagreesWithNativeBaseline() {
        XCTAssertEqual(MGSlotProbe(slotNumber: 178, originalByte: false, stagedByte: false,
                                   liveAnswer: true, nativeBaseline: false).disagreesWithNativeBaseline, true)
        XCTAssertEqual(MGSlotProbe(slotNumber: 178, originalByte: false, stagedByte: false,
                                   liveAnswer: false, nativeBaseline: false).disagreesWithNativeBaseline, false)
        XCTAssertNil(MGSlotProbe(slotNumber: 178, originalByte: false, stagedByte: false,
                                 liveAnswer: nil, nativeBaseline: false).disagreesWithNativeBaseline,
                      "Unknown is not a disagreement")
        XCTAssertNil(MGSlotProbe(slotNumber: 178, originalByte: false, stagedByte: false,
                                 liveAnswer: true, nativeBaseline: nil).disagreesWithNativeBaseline)
    }

    // MARK: - Staleness

    func testStaleness() {
        let now = Date()
        XCTAssertTrue(MGMonitor.row(for: input(liveReadAt: now.addingTimeInterval(-301)), now: now).isStale)
        XCTAssertFalse(MGMonitor.row(for: input(liveReadAt: now.addingTimeInterval(-60)), now: now).isStale)
        XCTAssertFalse(MGMonitor.row(for: input(liveReadAt: nil), now: now).isStale)
        XCTAssertEqual(MGMonitor.staleAfter, 300)
    }
}
