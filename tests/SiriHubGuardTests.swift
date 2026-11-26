import Foundation
import XCTest
@testable import GestaltX

/// SiriHub guard tests (A21, Erosion-CN `MGCacheLayout.siriHubKey`
/// / `MGInspectorView.isSiriHubConflictActive`): the key is the
/// verified DeviceSupportsSiriHub key, the status classifies the
/// live probe (unknown is never guessed), and the staging guard
/// blocks on a live SiriHub-on for native and non-native hardware
/// alike, while an unanswered probe does not gate.
final class SiriHubGuardTests: XCTestCase {
    func testKeyMatchesErosionCN() {
        XCTAssertEqual(SiriHubGuard.siriHubKey, "waGD2UTpntjbDXD1r3oALQ")
        XCTAssertEqual(MGKeysTable.erosionCNKeys.first { $0.key == SiriHubGuard.siriHubKey }?.question,
                       "DeviceSupportsSiriHub")
    }

    func testStatusClassification() {
        XCTAssertEqual(SiriHubGuard.status(liveValue: nil), .unknown)
        XCTAssertEqual(SiriHubGuard.status(liveValue: false), .clear)
        XCTAssertEqual(SiriHubGuard.status(liveValue: true), .conflict)
    }

    func testGuardBlocksOnSiriHubLiveForNativeHardware() {
        let decision = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", siriHubLive: true))
        XCTAssertEqual(decision.outcome, .block)
        XCTAssertTrue(decision.reason.contains("SiriHub"))
    }

    func testGuardBlocksOnSiriHubLiveForNonNativeHardware() {
        let decision = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone15,2", siriHubLive: true))
        XCTAssertEqual(decision.outcome, .block)
        XCTAssertTrue(decision.reason.contains("SiriHub"))
    }

    func testUnansweredProbeDoesNotGate() {
        // A nil probe leaves the guard's ordinary decision intact:
        // native hardware with a resolved, matching slot is allowed.
        let decision = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", personalTranslatorExtra: true,
            personalTranslatorSlot: true, siriHubLive: nil))
        XCTAssertEqual(decision.outcome, .allow)
    }

    func testGuardBlocksEvenWhenEverythingElseIsAllowed() {
        // SiriHub-on blocks even a combination the guard would
        // otherwise allow — the block is checked first.
        let decision = AIStagingGuard.decide(AIStagingRequest(
            productType: "iPhone16,2", personalTranslatorExtra: true,
            personalTranslatorSlot: true, siriHubLive: true))
        XCTAssertEqual(decision.outcome, .block)
        XCTAssertTrue(decision.reason.contains("SiriHub"))
    }
}
