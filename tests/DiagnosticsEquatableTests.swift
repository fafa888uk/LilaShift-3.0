// SPDX-License-Identifier: GPL-3.0-only
//
// DiagnosticsEquatableTests.swift — content-equality tests for the
// two types `HomeDiagnosticsCache` compares with `==` in its
// publish-only-on-change path (fix3).
//
// `LilaRecommendation` and `DeviceFingerprint` both carry creation
// metadata (`id` / `createdAt`, and `recordedAt`) that is fresh on
// every build/capture. Their synthesized `==` compared that metadata
// too, so two reports/fingerprints from identical inputs were never
// equal: an identical refresh always republished, and concurrent
// readers observed "torn" reports that matched neither snapshot's
// whole report. Both types now define `==` over content only
// (matching `DeviceFingerprint.digest`, which already excluded
// `recordedAt`). These tests pin that rule: identical content with
// different metadata is equal; different content is not.
import XCTest

@testable import GestaltX

final class DiagnosticsEquatableTests: XCTestCase {

    // MARK: - LilaRecommendation

    func testRecommendationEqualDespiteDifferentIDAndCreatedAt() {
        let first = LilaRecommendation(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            createdAt: Date(timeIntervalSince1970: 0),
            deviceID: "test-device",
            productType: "iPhone18,1",
            steps: [audioStep()],
            blockers: [],
            requiresRestart: false)
        let second = LilaRecommendation(
            id: UUID(uuidString: "99999999-8888-7777-6666-555555555555")!,
            createdAt: Date(timeIntervalSince1970: 1_000_000),
            deviceID: "test-device",
            productType: "iPhone18,1",
            steps: [audioStep()],
            blockers: [],
            requiresRestart: false)
        XCTAssertEqual(first, second,
                       "Recommendations with identical content must be equal regardless of id/createdAt")
    }

    func testRecommendationNotEqualWhenStepsDiffer() {
        let base = LilaRecommendation(
            id: UUID(), createdAt: Date(),
            deviceID: "test-device", productType: "iPhone18,1",
            steps: [audioStep()], blockers: [], requiresRestart: false)
        let differentSteps = LilaRecommendation(
            id: base.id, createdAt: base.createdAt,
            deviceID: "test-device", productType: "iPhone18,1",
            steps: [], blockers: [], requiresRestart: false)
        XCTAssertNotEqual(base, differentSteps,
                          "A recommendation with different steps must not be equal")
    }

    func testRecommendationNotEqualWhenBlockersDiffer() {
        let base = LilaRecommendation(
            id: UUID(), createdAt: Date(),
            deviceID: "test-device", productType: "iPhone18,1",
            steps: [audioStep()], blockers: [], requiresRestart: false)
        let blocked = LilaRecommendation(
            id: base.id, createdAt: base.createdAt,
            deviceID: "test-device", productType: "iPhone18,1",
            steps: [audioStep()],
            blockers: [PlanBlocker(featureID: "audioIntelligence",
                                   code: "unknown-model",
                                   reason: "test")],
            requiresRestart: false)
        XCTAssertNotEqual(base, blocked,
                          "A recommendation with different blockers must not be equal")
    }

    // MARK: - DeviceFingerprint

    func testFingerprintEqualDespiteDifferentRecordedAt() {
        let first = fingerprint(recordedAt: Date(timeIntervalSince1970: 0))
        let second = fingerprint(recordedAt: Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(first, second,
                       "Fingerprints with identical fields must be equal regardless of recordedAt")
        XCTAssertEqual(first.digest, second.digest,
                       "Equal fingerprints must have equal digests")
    }

    func testFingerprintNotEqualWhenRegionCodeDiffers() {
        let base = fingerprint(recordedAt: Date(timeIntervalSince1970: 0))
        let differentRegion = fingerprint(regionCode: "LL",
                                          recordedAt: Date(timeIntervalSince1970: 0))
        XCTAssertNotEqual(base, differentRegion,
                          "A fingerprint with a different region code must not be equal")
        XCTAssertNotEqual(base.digest, differentRegion.digest,
                          "Fingerprints that differ must have different digests")
    }

    // MARK: - Helpers

    private func audioStep() -> PlanStep {
        PlanStep(featureID: "audioIntelligence",
                 title: "Audio Intelligence",
                 kind: .cacheExtraKey,
                 key: DeviceCacheOptions.audioIntelligenceKey,
                 layer: .cacheExtra,
                 newValue: .bool(true),
                 slotIndex: nil,
                 verification: "test")
    }

    /// A fingerprint with test defaults and the given overrides
    /// (mirrors the helper in DeviceFingerprintTests).
    private func fingerprint(
        regionCode: String? = "CH",
        recordedAt: Date = Date(timeIntervalSince1970: 0)
    ) -> DeviceFingerprint {
        DeviceFingerprint(
            version: DeviceFingerprint.currentVersion,
            deviceID: "test-device",
            productType: "iPhone14,7",
            modelNumber: "A1234",
            osVersion: "27.0.1",
            osBuild: "23A344",
            regionCode: regionCode,
            salesRegionSuffix: "CH/A",
            cacheLayoutUUID: CoreModuleFixtures.uuid,
            cacheSlotCount: 720,
            cacheByteCount: 6480,
            esimGreenTea: true,
            esimNotGreenTea: false,
            wapiEnabled: true,
            audioIntelligenceSlot: nil,
            personalTranslatorSlot: nil,
            isNativeAppleIntelligence: false,
            appGroupAvailable: true,
            backupCount: 0,
            hasTrustedBackup: false,
            recordedAt: recordedAt)
    }
}
