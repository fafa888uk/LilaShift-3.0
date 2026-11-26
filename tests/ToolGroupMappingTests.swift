// SPDX-License-Identifier: GPL-3.0-only
// Tests for the Stage 14 navigation recategorization: the four
// one-tap family groups open four different pages, the
// FeatureCatalog destination mapping agrees with the ToolGroup
// mapping, and the ToolGroup sections cover the capabilities they
// claim (with the three known ungrouped device capabilities
// documented, not silently dropped).
import XCTest
@testable import GestaltX

final class ToolGroupMappingTests: XCTestCase {
    private func destination(of featureID: String) -> DashboardV3Destination? {
        guard let entry = PresetCatalog.entry(for: featureID) else {
            XCTFail("Missing catalog entry \(featureID)")
            return nil
        }
        return FeatureCatalog.destination(for: entry)
    }

    // MARK: - The four one-tap family groups

    func testFourPresetGroupsHaveDistinctDestinations() {
        XCTAssertEqual(destination(of: "preset.oneTap"), .unlock)
        XCTAssertEqual(destination(of: "preset.aiOnly"), .aiOnly)
        XCTAssertEqual(destination(of: "preset.siriAIMode"), .siriAIMode)
        XCTAssertEqual(destination(of: "preset.esimRegion"), .esimRegion)
        let destinations: Set<DashboardV3Destination> = [.unlock, .aiOnly, .siriAIMode, .esimRegion]
        XCTAssertEqual(destinations.count, 4, "The four group pages must be four different destinations")
    }

    // MARK: - Destination for every preset entry

    func testDestinationForEveryPresetEntry() {
        for entry in PresetCatalog.all {
            let destination = FeatureCatalog.destination(for: entry)
            switch entry.featureID {
            case "preset.oneTap":
                XCTAssertEqual(destination, .unlock, "One-tap stages on the unlock page")
            case "preset.aiOnly":
                XCTAssertEqual(destination, .aiOnly, "AI-only stages on the AI page")
            case "preset.siriAIMode":
                XCTAssertEqual(destination, .siriAIMode, "Siri AI Mode stages on its own page")
            case "preset.esimRegion":
                XCTAssertEqual(destination, .esimRegion, "eSIM & region stages on the eSIM page")
            case "siriAIMode":
                XCTAssertEqual(destination, .siriAIMode, "The Siri AI Mode capability stages on its own page")
            default:
                switch FeatureCatalog.category(for: entry) {
                case .smartUnlock:
                    XCTAssertEqual(destination, .unlock, "Entry \(entry.featureID)")
                case .appleIntelligence:
                    XCTAssertEqual(destination, .aiOnly, "Entry \(entry.featureID)")
                case .esimRegion:
                    XCTAssertEqual(destination, .esimRegion, "Entry \(entry.featureID)")
                case .screenLock, .systemSettings, .personalization,
                     .launchArtwork, .advancedTools:
                    XCTAssertEqual(destination, .advanced, "Entry \(entry.featureID)")
                case .deviceDiagnostics:
                    XCTAssertEqual(destination, .diagnostics, "Entry \(entry.featureID)")
                case .modifiedRecords:
                    XCTAssertEqual(destination, .unlock, "Entry \(entry.featureID)")
                case .backupRestore:
                    XCTAssertEqual(destination, .restore, "Entry \(entry.featureID)")
                }
            }
        }
    }

    // MARK: - ToolGroup mapping (CapabilityCategory)

    func testToolGroupForCapabilityCategory() {
        XCTAssertEqual(ToolGroup(for: .display), .screenLock)
        XCTAssertEqual(ToolGroup(for: .device), .chargingButtons)
        XCTAssertEqual(ToolGroup(for: .intelligence), .intelligenceRegion)
        XCTAssertEqual(ToolGroup(for: .ipad), .ipadMultitasking)
        XCTAssertEqual(ToolGroup(for: .advanced), .advancedDiagnostics)
    }

    func testChargingButtonsHoldsTheDeviceCapabilities() {
        let ids = Set(ToolGroup.chargingButtons.sections.flatMap(\.capabilityIDs))
        for id in ["chargeLimit", "tapToWake", "cameraControl",
                   "actionButton", "bootChime", "collisionSOS"] {
            XCTAssertTrue(ids.contains(id), "chargingButtons must list \(id)")
        }
    }

    // MARK: - ToolGroup mapping (FeatureCatalogCategory)

    func testToolGroupForFeatureCatalogCategory() {
        XCTAssertEqual(ToolGroup(for: .screenLock), .screenLock)
        XCTAssertEqual(ToolGroup(for: .personalization), .personalization)
        XCTAssertEqual(ToolGroup(for: .launchArtwork), .personalization)
        XCTAssertEqual(ToolGroup(for: .advancedTools), .advancedDiagnostics)
        for category in [FeatureCatalogCategory.smartUnlock, .appleIntelligence,
                         .esimRegion, .systemSettings, .deviceDiagnostics,
                         .modifiedRecords, .backupRestore] {
            XCTAssertNil(
                ToolGroup(for: category),
                "Category \(category) must have no single tool group — it stages on its own page or spans several groups")
        }
    }

    // MARK: - The two mappings agree

    func testToolGroupAndDestinationAgree() {
        for entry in PresetCatalog.all {
            let destination = FeatureCatalog.destination(for: entry)
            if let group = ToolGroup(for: FeatureCatalog.category(for: entry)) {
                XCTAssertEqual(
                    destination, .advanced,
                    "Entry \(entry.featureID) has tool group \(group), so it must stage on the tools page")
            }
        }
    }

    // MARK: - Section coverage

    func testGroupedCapabilityIDsCoverAllButThreeDocumentedCapabilities() {
        let grouped = Set(ToolGroup.allCases.flatMap { $0.sections.flatMap(\.capabilityIDs) })
        let all = Set(Capability.all.map(\.id))
        XCTAssertTrue(grouped.isSubset(of: all), "ToolGroup sections must only list real capabilities")
        XCTAssertEqual(grouped.count, 33)
        XCTAssertEqual(
            all.subtracting(grouped),
            ["spatialAudioRecording", "responsiveShutter", "hypertensionNotifications"],
            "Only these three device capabilities have no ToolGroup section — they stage from the catalog / MG Control")
    }
}
