import Foundation
import XCTest
@testable import GestaltX

/// W4 Apple Wiki key table tests: the generated 943-key table, its
/// merge into the field editor search, and the hand-reviewed Chinese
/// names. No key here is guessed — the table is generated from The
/// Apple Wiki page by scripts/generate_apple_wiki_key_table.py and
/// cross-checked against the upstream worstgestalt data file.
final class W4AppleWikiKeyTableTests: XCTestCase {
    func testWikiTableCounts() {
        XCTAssertEqual(AppleWikiKeyTable.count, 943)
        XCTAssertEqual(AppleWikiKeyTable.names.count, 943)
        XCTAssertEqual(AppleWikiKeyTable.descriptions.count, 671)
    }

    func testEveryHashedKeyIs22Characters() {
        XCTAssertTrue(AppleWikiKeyTable.names.keys.allSatisfy { $0.count == 22 })
        XCTAssertTrue(AppleWikiKeyTable.descriptions.keys.allSatisfy { $0.count == 22 })
    }

    func testDescriptionsOnlyCoverKnownKeys() {
        for key in AppleWikiKeyTable.descriptions.keys {
            XCTAssertNotNil(AppleWikiKeyTable.names[key], "Description for unknown key \(key)")
        }
    }

    func testKnownKeysPresent() {
        XCTAssertEqual(
            AppleWikiKeyTable.plainName(forHashedKey: "YlEtTtHlNesRBMal1CqRaA"),
            "DeviceSupportsDynamicIsland")
        XCTAssertEqual(
            AppleWikiKeyTable.plainName(forHashedKey: "waGD2UTpntjbDXD1r3oALQ"),
            "DeviceSupportsSiriHub")
        XCTAssertEqual(
            AppleWikiKeyTable.plainName(forHashedKey: "h9jDsbgj7xIVeIQ8S3/X3Q"),
            "ProductType")
        XCTAssertEqual(
            AppleWikiKeyTable.description(forHashedKey: "QHxt+hGLaBPbQJbXiUJX3w"),
            "The device plays a chime when it turns on.")
        XCTAssertNil(AppleWikiKeyTable.plainName(forHashedKey: "definitely-not-a-real-key"))
        XCTAssertNil(AppleWikiKeyTable.description(forHashedKey: "YlEtTtHlNesRBMal1CqRaA"),
                     "Dynamic Island has no wiki description")
    }

    func testAppleWikiEntriesAreTheNonCuratedKeys() {
        XCTAssertEqual(MGKeysTable.appleWikiEntries.count, 878)
        XCTAssertEqual(MGKeysTable.searchableCount, 955)
        let curatedKeys = Set(MGKeysTable.all.map(\.key))
        let wikiKeys = Set(MGKeysTable.appleWikiEntries.map(\.key))
        XCTAssertTrue(curatedKeys.isDisjoint(with: wikiKeys))
        // 77 curated + 878 non-curated wiki entries = 955. (943 is
        // the wiki total including the 65 curated keys, which are
        // excluded from `appleWikiEntries` by construction.)
        XCTAssertEqual(curatedKeys.union(wikiKeys).count, 955)
        // Sorted by name, like `all`.
        let names = MGKeysTable.appleWikiEntries.map(\.name)
        XCTAssertEqual(names, names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    func testAppleWikiEntriesCiteTheWiki() {
        for entry in MGKeysTable.appleWikiEntries {
            XCTAssertFalse(entry.meaning.isEmpty, "Entry \(entry.key) has no meaning")
            XCTAssertTrue(entry.source.contains("The Apple Wiki"), "Entry \(entry.key) cites \(entry.source)")
            XCTAssertTrue(entry.source.contains("CC BY-SA 4.0"), "Entry \(entry.key) carries the data license")
        }
    }

    func testCuratedRowsKeepPriority() {
        // The spatial audio key is both curated and in the wiki; the
        // searchable index must carry the capability row only.
        let spatial = MGKeysTable.matching("X6NGcYcvHmbqlR8hLXASJA")
        XCTAssertEqual(spatial.count, 1)
        XCTAssertTrue(spatial.first!.source.contains("spatialAudioRecording"))
        XCTAssertEqual(MGKeysTable.matching("SiriHub").count, 1)
        XCTAssertEqual(MGKeysTable.matching("SiriHub").first?.key, "waGD2UTpntjbDXD1r3oALQ")
    }

    func testEmptyQueryStillReturnsTheCuratedTableOnly() {
        // The browse list is the 77 curated rows: MGDatabaseSeed
        // mirrors `all` exactly, so the wiki rows stay search-only.
        XCTAssertEqual(MGKeysTable.matching("").count, MGKeysTable.all.count)
        XCTAssertEqual(MGKeysTable.all.count, 77)
    }

    func testSearchFindsWikiOnlyKeys() {
        // By wiki plain name.
        let liquid = MGKeysTable.matching("DeviceSupportsLiquidDetection")
        XCTAssertEqual(liquid.count, 1)
        XCTAssertEqual(liquid.first?.key, "XxnEk9uiIk5vCdbWEGt7lA")
        // By wiki description words.
        XCTAssertFalse(MGKeysTable.matching("accelerometer hardware").isEmpty)
        // By obfuscated key.
        XCTAssertFalse(MGKeysTable.matching("XxnEk9uiIk5vCdbWEGt7lA").isEmpty)
        // No match returns an empty list, never a guess.
        XCTAssertTrue(MGKeysTable.matching("definitely-not-a-real-key-xyz").isEmpty)
    }

    func testSearchFindsChineseNames() {
        let island = MGKeysTable.matching("灵动岛")
        XCTAssertEqual(island.count, 1)
        XCTAssertEqual(island.first?.key, "YlEtTtHlNesRBMal1CqRaA")
        XCTAssertFalse(MGKeysTable.matching("常亮显示").isEmpty)
        XCTAssertFalse(MGKeysTable.matching("销售地区代码").isEmpty)
        // The "no Chinese name yet" label is a status, not a name.
        XCTAssertTrue(MGKeysTable.matching("暂无中文名").isEmpty)
    }

    func testChineseCoverage() {
        XCTAssertEqual(MGKeyChineseNames.translatedKeyCount, 122)
        XCTAssertEqual(Set(MGKeyChineseNames.names.keys), Set(MGKeyChineseNames.descriptions.keys))
        // Every curated key has a reviewed Chinese name.
        for entry in MGKeysTable.all {
            XCTAssertNotNil(entry.chineseName, "Curated key \(entry.key) has no Chinese name")
            XCTAssertNotNil(entry.chineseDescription, "Curated key \(entry.key) has no Chinese description")
        }
        // Every translated key is a real key: in the wiki table or the
        // curated table (identity keys such as the Siri AI mode key are
        // curated-only).
        let wikiKeys = Set(AppleWikiKeyTable.names.keys)
        let curatedKeys = Set(MGKeysTable.all.map(\.key))
        for key in MGKeyChineseNames.names.keys {
            XCTAssertTrue(wikiKeys.contains(key) || curatedKeys.contains(key),
                          "Translated key \(key) is in neither table")
        }
        // 821 wiki keys are still untranslated: they must report nil,
        // never a fabricated name.
        let untranslated = MGKeysTable.appleWikiEntries.filter { $0.chineseName == nil }
        XCTAssertEqual(untranslated.count, 878 - 45)
        XCTAssertEqual(MGKeyChineseNames.missingChineseNameLabel, "暂无中文名")
    }
}

/// W4 registration tests: the two features' directory metadata.
final class W4RegistrationTests: XCTestCase {
    func testTwoFeatures() {
        XCTAssertEqual(W4Registration.features.count, 2)
        XCTAssertEqual(Set(W4Registration.features.map(\.id)).count, 2)
    }

    func testKeyTableFeature() {
        let feature = W4Registration.features.first { $0.id == "w4.appleWikiKeyTable" }
        XCTAssertNotNil(feature)
        XCTAssertEqual(feature!.chineseTitle, "Apple Wiki 键值表")
        XCTAssertEqual(feature!.category, .deviceDiagnostics)
        XCTAssertEqual(feature!.viewKind, .keyTableSearch)
        XCTAssertFalse(feature!.summary.isEmpty)
    }

    func testChineseNamesFeature() {
        let feature = W4Registration.features.first { $0.id == "w4.chineseKeyNames" }
        XCTAssertNotNil(feature)
        XCTAssertEqual(feature!.chineseTitle, "键名中文翻译")
        XCTAssertEqual(feature!.category, .deviceDiagnostics)
        XCTAssertEqual(feature!.viewKind, .keyRowDisplay)
        XCTAssertFalse(feature!.summary.isEmpty)
    }
}
