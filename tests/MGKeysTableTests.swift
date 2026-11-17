import Foundation
import XCTest
@testable import GestaltX

/// MG keys table tests (A22): the 56 Erosion-CN keys are all
/// present with their questions, the table is deduplicated by key,
/// every capability key appears, and search matches names, keys
/// and meanings. No key is guessed — the table is built from the
/// sources it cites.
final class MGKeysTableTests: XCTestCase {
    func testErosionCNKeyCount() {
        XCTAssertEqual(MGKeysTable.erosionCNKeys.count, 56)
        // Every Erosion-CN key is 22 characters, like every other
        // MobileGestalt key in the app.
        XCTAssertTrue(MGKeysTable.erosionCNKeys.allSatisfy { $0.key.count == 22 })
        // No duplicate keys in the source list.
        XCTAssertEqual(Set(MGKeysTable.erosionCNKeys.map(\.key)).count, 56)
    }

    func testTableIsDeduplicatedByKey() {
        let all = MGKeysTable.all
        XCTAssertEqual(Set(all.map(\.key)).count, all.count)
        XCTAssertFalse(all.isEmpty)
    }

    func testEveryCapabilityKeyAppears() {
        let keys = Set(MGKeysTable.all.map(\.key))
        for capability in Capability.all {
            for key in capability.keys {
                XCTAssertTrue(keys.contains(key), "Capability \(capability.id) key \(key) is missing from the table")
            }
        }
    }

    func testCapabilityRowsWinOverErosionCNRows() {
        // The spatial audio key is both an Erosion-CN row and a
        // capability row; the table must carry the capability's
        // meaning and source.
        let entry = MGKeysTable.all.first { $0.key == "X6NGcYcvHmbqlR8hLXASJA" }
        XCTAssertNotNil(entry)
        XCTAssertTrue(entry!.source.contains("spatialAudioRecording"))
    }

    func testIdentityKeysAppear() {
        let keys = Set(MGKeysTable.all.map(\.key))
        XCTAssertTrue(keys.contains(GestaltKeys.productType))
        XCTAssertTrue(keys.contains(GestaltKeys.regionCode))
        XCTAssertTrue(keys.contains(GestaltKeys.siriMode))
    }

    func testSearch() {
        XCTAssertEqual(MGKeysTable.matching("").count, MGKeysTable.all.count)
        let siri = MGKeysTable.matching("SiriHub")
        XCTAssertEqual(siri.count, 1)
        XCTAssertEqual(siri.first?.key, "waGD2UTpntjbDXD1r3oALQ")
        // Search by key fragment.
        XCTAssertFalse(MGKeysTable.matching("X6NGcYcvHmbqlR8hLXASJA").isEmpty)
        // Search by meaning.
        XCTAssertFalse(MGKeysTable.matching("DynamicIsland").isEmpty)
        // No match returns an empty list, never a guess.
        XCTAssertTrue(MGKeysTable.matching("definitely-not-a-real-key-xyz").isEmpty)
    }

    func testEveryEntryCitesASource() {
        for entry in MGKeysTable.all {
            XCTAssertFalse(entry.source.isEmpty, "Entry \(entry.key) has no source")
            XCTAssertFalse(entry.meaning.isEmpty, "Entry \(entry.key) has no meaning")
        }
    }

    func testAllIsStableAcrossAccesses() {
        // `all` is a cached static let (Stage 3): repeated access
        // returns the same rows in the same order. The cache also
        // guards against a future change making the order
        // nondeterministic (for example, a dictionary iteration).
        let first = MGKeysTable.all
        let second = MGKeysTable.all
        XCTAssertEqual(first.count, second.count)
        XCTAssertTrue(zip(first, second).allSatisfy { $0.key == $1.key && $0.name == $1.name },
                      "Repeated access returns the same rows in the same order")
    }
}
