import Foundation
import XCTest
@testable import GestaltX

/// Media/health capability tests (A13/A14/A15, Erosion-CN
/// `MGCacheLayout`): the three keys are the verified 22-character
/// MobileGestalt keys, they are toggleable presets (not part of the
/// fixed one-tap unlock), their catalog rows are present with the
/// right risk levels and both layers named, and the spatial audio
/// scope is exactly the verified four-microphone model list.
final class MediaHealthCapabilitiesTests: XCTestCase {
    private let ids = ["spatialAudioRecording", "responsiveShutter", "hypertensionNotifications"]
    private let keys = [
        "spatialAudioRecording": "X6NGcYcvHmbqlR8hLXASJA",
        "responsiveShutter": "gQDt76Te0SPw7N8oTLrBFw",
        "hypertensionNotifications": "4fh9efw4o1yaFqkXNCXoeA",
    ]

    func testKeysAreVerified22CharKeys() {
        for id in ids {
            let capability = Capability.all.first { $0.id == id }
            XCTAssertNotNil(capability, "Capability \(id) is missing")
            XCTAssertEqual(capability!.keys, [keys[id]!])
            XCTAssertEqual(keys[id]!.count, 22)
        }
        // The keys are the ones Erosion-CN's MGCacheLayout documents.
        XCTAssertEqual(MGKeysTable.erosionCNKeys.first { $0.key == keys["spatialAudioRecording"] }?.question,
                       "spatial-audio-recording")
        XCTAssertEqual(MGKeysTable.erosionCNKeys.first { $0.key == keys["responsiveShutter"] }?.question,
                       "ResponsiveShutter")
        XCTAssertEqual(MGKeysTable.erosionCNKeys.first { $0.key == keys["hypertensionNotifications"] }?.question,
                       "HypertensionNotifications")
    }

    func testNotInOneTapUnlock() {
        // The 10-item one-tap unlock is fixed by the 2026-11-15 #178
        // decision; these three toggles must not join it.
        for id in ids {
            XCTAssertFalse(ChinaUnlock.aiCapabilityIDs.contains(id),
                           "\(id) must not be part of the one-tap AI unlock")
        }
    }

    func testCatalogRowsPresent() {
        for id in ids {
            XCTAssertTrue(PresetCatalog.all.contains { $0.featureID == id },
                          "PresetCatalog is missing a row for \(id)")
        }
    }

    func testSpatialScopeIsTheVerifiedFourMicList() {
        guard case .verifiedModels(let models) = FeatureEligibilityEvaluator.spatialAudioScope else {
            return XCTFail("spatialAudioScope must be .verifiedModels")
        }
        XCTAssertEqual(models.count, 9)
        XCTAssertTrue(models.contains("iPhone17,1"))
        XCTAssertTrue(models.contains("iPhone18,5"))
        // iPhone Air (iPhone18,4) has three microphones and is NOT
        // in Erosion-CN's four-mic list.
        XCTAssertFalse(models.contains("iPhone18,4"))
        let entry = PresetCatalog.all.first { $0.featureID == "spatialAudioRecording" }
        XCTAssertNotNil(entry)
        guard case .verifiedModels(let entryModels) = entry!.scope else {
            return XCTFail("spatialAudioRecording scope must be .verifiedModels")
        }
        XCTAssertEqual(entryModels, models)
    }

    func testRiskLevels() {
        XCTAssertEqual(LilaIntelligence.entry(for: "spatialAudioRecording")?.riskLevel, .high)
        XCTAssertEqual(LilaIntelligence.entry(for: "responsiveShutter")?.riskLevel, .high)
        XCTAssertEqual(LilaIntelligence.entry(for: "hypertensionNotifications")?.riskLevel, .low)
    }

    func testBothLayersNamed() {
        for id in ids {
            let entry = LilaIntelligence.entry(for: id)
            XCTAssertNotNil(entry)
            XCTAssertTrue(entry!.underlyingKeyOrSlot.contains("CacheExtra key"),
                          "\(id) must name the CacheExtra key layer")
            XCTAssertTrue(entry!.underlyingKeyOrSlot.contains("CacheData slot"),
                          "\(id) must name the CacheData slot layer")
        }
    }

    func testErosionCNCitedAsSource() {
        for id in ids {
            let entry = LilaIntelligence.entry(for: id)
            XCTAssertNotNil(entry)
            XCTAssertTrue(entry!.sources.contains { $0.contains("Erosion-CN") },
                          "\(id) must cite Erosion-CN as its key source")
        }
    }
}
