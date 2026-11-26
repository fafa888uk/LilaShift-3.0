// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

/// Lock-screen-text catalog pointer entry (Stage 13): the feature
/// is discoverable from the catalog, search, and combinations, but
/// it is never stageable through the MobileGestalt pipeline — it
/// is a `.virtual` pointer to the System Settings page, where the
/// text is typed and applied. The page itself was ported 1:1 from
/// upstream GestaltX v1.0.6 (see `SystemSettingsStore.swift`).
final class LockScreenTextPresetTests: XCTestCase {
    private func lockScreenTextEntry() throws -> PresetEntry {
        guard let entry = PresetCatalog.all.first(where: { $0.featureID == "lockScreenText" }) else {
            throw Failure(message: "Catalog is missing the lockScreenText entry")
        }
        return entry
    }

    struct Failure: Error { let message: String }

    func testLockScreenTextCatalogEntry() throws {
        let entry = try lockScreenTextEntry()
        XCTAssertEqual(entry.kind, .virtual, "Lock screen text must be a virtual pointer, not a capability")
        XCTAssertEqual(entry.category, .display)
        XCTAssertTrue(entry.memberIDs.isEmpty, "A pointer entry has no members to stage")
        XCTAssertEqual(entry.keys, ["LockScreenFootnote"])
        XCTAssertFalse(entry.evidence.isEmpty, "Evidence must cite the ported store")
        XCTAssertTrue(entry.evidence.contains { $0.text.contains("SystemSettingsStore.swift") },
                      "Evidence must cite SystemSettingsStore.swift")
        XCTAssertFalse(entry.chineseDescription.isEmpty)
        XCTAssertFalse(entry.restoreMethod.isEmpty, "Restore must name the System Settings Revert path")
    }

    func testLockScreenTextCatalogMapping() throws {
        let entry = try lockScreenTextEntry()
        XCTAssertEqual(FeatureCatalog.category(for: entry), .screenLock,
                       "A .display entry maps to the Screen & Lock Screen category")
        XCTAssertEqual(FeatureCatalog.destination(for: entry), .advanced,
                       "The entry lives on the Tools page, which hosts the System Settings tile")
        XCTAssertTrue(FeatureCatalog.presetItems.contains { $0.presetFeatureID == "lockScreenText" },
                      "The catalog browser must list the entry")
    }

    func testLockScreenTextIsNeverStageable() {
        XCTAssertFalse(PresetLab.stageableEntries().contains { $0.featureID == "lockScreenText" },
                       "A virtual pointer entry must never be offered for MG staging")
    }
}
