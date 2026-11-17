import Foundation
import XCTest
@testable import GestaltX

/// Preset Lab tests (A24): only capability-backed entries are
/// stageable in the Lab — groups and virtual entries are excluded
/// because they have dedicated apply paths — and only the storage
/// preset needs an enable confirmation, mirroring
/// `Capability.requiresEnableConfirmation`.
final class PresetLabTests: XCTestCase {
    func testStageableEntriesAreCapabilityBackedOnly() {
        let stageable = PresetLab.stageableEntries()
        XCTAssertFalse(stageable.isEmpty)
        XCTAssertTrue(stageable.allSatisfy { $0.kind == .capability })
        // The catalog has groups and virtual entries; none of them
        // may appear in the Lab.
        XCTAssertTrue(PresetCatalog.all.contains { $0.kind == .group })
        XCTAssertTrue(PresetCatalog.all.contains { $0.kind == .virtual })
        XCTAssertFalse(stageable.contains { $0.kind == .group || $0.kind == .virtual })
    }

    func testStageableEntriesAreBackedByACapability() {
        let ids = Set(Capability.all.map(\.id))
        for entry in PresetLab.stageableEntries() {
            XCTAssertTrue(ids.contains(entry.featureID),
                          "Stageable entry \(entry.featureID) has no backing Capability")
        }
    }

    func testRequiresConfirmationOnlyForStorage() {
        XCTAssertTrue(PresetLab.requiresConfirmation(id: "storage"))
        XCTAssertFalse(PresetLab.requiresConfirmation(id: "dynamicIsland"))
        XCTAssertFalse(PresetLab.requiresConfirmation(id: "ai"))
        XCTAssertFalse(PresetLab.requiresConfirmation(id: "aod"))
    }

    func testStagedStateReadsModelChoices() {
        // A fresh manager stages nothing.
        let model = GestaltManager()
        XCTAssertFalse(PresetLab.isStaged(id: "dynamicIsland", in: model))
        XCTAssertEqual(PresetLab.stagedChoice(id: "dynamicIsland", in: model), .keep)
        model.choices["dynamicIsland"] = .enable
        XCTAssertTrue(PresetLab.isStaged(id: "dynamicIsland", in: model))
        XCTAssertEqual(PresetLab.stagedChoice(id: "dynamicIsland", in: model), .enable)
        model.choices["dynamicIsland"] = .keep
        XCTAssertFalse(PresetLab.isStaged(id: "dynamicIsland", in: model))
    }
}
