// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

/// MGDatabase tests (Stage 4, ADR-2-07).
///
/// The seed is checked against the sources it was built from:
/// `MGKeysTable.all` (the same 77 keys, deduplicated the same way),
/// MGKeys version data, and the Erosion-CN probe evidence for the
/// two slot keys. No test invents a key, a version or a baseline.
final class MGDatabaseTests: XCTestCase {
    func testSeedHas77Records() {
        XCTAssertEqual(MGDatabase.all.count, 77,
                       "The used-keys subset is 77 records: 56 Erosion-CN + 9 identity + 12 capability-only")
        XCTAssertEqual(Set(MGDatabase.all.map(\.obfuscatedName)).count, 77,
                       "Seed keys are unique by obfuscated key")
        XCTAssertEqual(Set(MGDatabase.all.map(\.keyID)).count, 77,
                       "Seed key IDs are unique")
    }

    /// The seed is exactly `MGKeysTable.all`: same keys, no more,
    /// no fewer. (The Stage 0 audit said 76; the true count is 77 —
    /// 56 + 9 + 12 capability-only keys.) One key differs in form:
    /// the table stages the parallax key by its readable name
    /// (`UIParallaxCapability`); the DB stores its MG hash
    /// (`mmu76v66k1dAtghToInT8g`, mapping.h) as the obfuscated name.
    func testSeedMatchesMGKeysTable() {
        let tableKeys = Set(MGKeysTable.all.map(\.key))
        let dbKeys = Set(MGDatabase.all.map(\.obfuscatedName))
        let expectedDbKeys = tableKeys.subtracting(["UIParallaxCapability"])
            .union(["mmu76v66k1dAtghToInT8g"])
        XCTAssertEqual(dbKeys, expectedDbKeys,
                       "MGDatabase must contain exactly the MGKeysTable keys")
        XCTAssertEqual(MGDatabase.all.count, MGKeysTable.all.count)
        for entry in MGKeysTable.all {
            XCTAssertNotNil(MGDatabase.record(forKey: entry.key),
                            "Missing DB record for MGKeysTable key \(entry.key)")
        }
        XCTAssertEqual(MGDatabase.record(forKey: "UIParallaxCapability")?.obfuscatedName,
                       "mmu76v66k1dAtghToInT8g",
                       "The parallax key is looked up by its readable name")
    }

    func testSlotKeysCarryProbeEvidence() {
        let audio = MGDatabase.record(forKey: DeviceCacheOptions.audioIntelligenceKey)
        XCTAssertEqual(audio?.slot?.slotNumber, 178)
        XCTAssertEqual(audio?.slot?.nativeBaseline, false)
        XCTAssertEqual(audio?.defaultValue, .bool(false))
        XCTAssertEqual(audio?.verificationStatus, .verifiedByUpstreamProbe)
        XCTAssertEqual(audio?.restorable, false,
                       "Slot values are not in OriginalValues yet (ADR-2-02 gap, Stage 5)")
        XCTAssertTrue(audio?.slot?.baselineEvidence?.contains("GestaltHelpers.swift:1027-1044") == true)

        let translator = MGDatabase.record(forKey: DeviceCacheOptions.personalTranslatorKey)
        XCTAssertEqual(translator?.slot?.slotNumber, 266)
        XCTAssertEqual(translator?.slot?.nativeBaseline, true)
        XCTAssertEqual(translator?.defaultValue, .bool(true))
        XCTAssertEqual(translator?.verificationStatus, .verifiedByUpstreamProbe)
        XCTAssertEqual(translator?.restorable, false)
    }

    /// Nothing else claims verification, and nothing else carries a
    /// default value: defaults need probe evidence, and only the two
    /// slot keys have it.
    func testNothingElseClaimsVerification() {
        let slotKeys: Set<String> = [DeviceCacheOptions.audioIntelligenceKey,
                                     DeviceCacheOptions.personalTranslatorKey]
        for record in MGDatabase.all where !slotKeys.contains(record.obfuscatedName) {
            XCTAssertEqual(record.verificationStatus, .unverified,
                           "\(record.keyID) must not claim verification without evidence")
            XCTAssertNil(record.defaultValue,
                         "\(record.keyID) must not carry a guessed default value")
            XCTAssertNil(record.slot, "\(record.keyID) is not a CacheData slot")
        }
    }

    func testAllRecordsReadableViaMGCopyAnswer() {
        XCTAssertTrue(MGDatabase.all.allSatisfy(\.readableViaMGCopyAnswer),
                      "No used key is a // non-gestalt-key (IODeviceTree) key")
    }

    func testVersionRanges() {
        let modelNumber = MGDatabase.record(forKey: GestaltKeys.modelNumber)
        XCTAssertEqual(modelNumber?.iosScope.introduced, "7.0")
        XCTAssertEqual(modelNumber?.iosScope.reintroduced, ["17.0", "26.0"])
        XCTAssertNil(modelNumber?.iosScope.removed)

        let siriMode = MGDatabase.record(forKey: GestaltKeys.siriMode)
        XCTAssertEqual(siriMode?.iosScope.introduced, "27.0")
        XCTAssertTrue(siriMode?.iosScope.contains("27.0.1") == true)
        XCTAssertFalse(siriMode?.iosScope.contains("26.0") == true)

        let legacyBattery = MGDatabase.record(forKey: "Rq0MF/w+gXM66Ii4fkWOzg")
        XCTAssertEqual(legacyBattery?.iosScope.introduced, "27.2")
        XCTAssertTrue(legacyBattery?.iosScope.contains("27.2") == true)
        XCTAssertFalse(legacyBattery?.iosScope.contains("27.0.1") == true)

        let regionCode = MGDatabase.record(forKey: GestaltKeys.regionCode)
        XCTAssertTrue(regionCode?.iosScope.contains("7.0") == true)
        XCTAssertTrue(regionCode?.iosScope.contains("27.2") == true)
        XCTAssertEqual(MGDatabase.keysAvailable(onIOS: "27.0.1").count,
                       MGDatabase.all.filter { $0.iosScope.contains("27.0.1") }.count)
    }

    func testIOSVersionCompare() {
        XCTAssertEqual(IOSVersionRange.compare("27.0.1", "27.2"), .orderedAscending)
        XCTAssertEqual(IOSVersionRange.compare("27.2", "27.2"), .orderedSame)
        XCTAssertEqual(IOSVersionRange.compare("26.0", "27.0"), .orderedAscending)
        XCTAssertEqual(IOSVersionRange.compare("27.2.1", "27.2"), .orderedDescending)
    }

    func testDeviceScope() {
        XCTAssertTrue(DeviceScope.all.contains(productType: "iPhone18,4"))
        XCTAssertTrue(DeviceScope.all.contains(productType: "iPad13,4"))
        XCTAssertTrue(DeviceScope.ipadOnly.contains(productType: "iPad13,4"))
        XCTAssertFalse(DeviceScope.ipadOnly.contains(productType: "iPhone18,4"))
        XCTAssertTrue(DeviceScope.iphoneOnly.contains(productType: "iPhone18,4"))
        XCTAssertFalse(DeviceScope.iphoneOnly.contains(productType: "iPad13,4"))
        let pencil = MGDatabase.record(forKey: "yhHcB0iH0d1XzPO/CFd3ow")
        XCTAssertEqual(pencil?.deviceScope, .ipadOnly)
        XCTAssertEqual(MGDatabase.records(in: .ipad).count, 3)
    }

    func testRecordsByCategory() {
        XCTAssertEqual(MGDatabase.records(in: .display).count, 23)
        XCTAssertEqual(MGDatabase.records(in: .device).count, 36)
        XCTAssertEqual(MGDatabase.records(in: .ipad).count, 3)
        XCTAssertEqual(MGDatabase.records(in: .intelligence).count, 11)
        XCTAssertEqual(MGDatabase.records(in: .advanced).count, 4)
    }

    func testHighRiskKeysAreExactlySix() {
        let high = MGDatabase.all.filter { $0.riskLevel == .high }.map(\.obfuscatedName)
        XCTAssertEqual(Set(high), [
            DeviceCacheOptions.audioIntelligenceKey,
            DeviceCacheOptions.personalTranslatorKey,
            GestaltKeys.productType, GestaltKeys.hardwareModel,
            GestaltKeys.cpu, GestaltKeys.modelNumber,
        ])
    }

    func testSearch() {
        XCTAssertEqual(MGDatabase.search("").count, 77)
        let island = MGDatabase.search("DynamicIsland")
        XCTAssertEqual(island.map(\.keyID), ["DeviceSupportsDynamicIsland"])
        let siri = MGDatabase.search("SiriMode")
        XCTAssertEqual(siri.map(\.keyID), ["SiriMode"])
        XCTAssertTrue(MGDatabase.search("rb2tKZxlj0Gm2tBmUQSLqQ").map(\.keyID)
            .contains("DeviceSupportsAudioIntelligence"))
    }

    func testMGValueFromPlist() {
        XCTAssertEqual(MGValue.fromPlistValue(NSNumber(value: true)), .bool(true))
        XCTAssertEqual(MGValue.fromPlistValue(NSNumber(value: 3)), .int(3))
        XCTAssertEqual(MGValue.fromPlistValue("LL"), .string("LL"))
        XCTAssertEqual(MGValue.fromPlistValue(Data([1, 2])), .data(Data([1, 2])))
        XCTAssertEqual(MGValue.fromPlistValue([NSNumber(value: 1), NSNumber(value: 2)]),
                       .array([.int(1), .int(2)]))
        XCTAssertEqual(MGValue.fromPlistValue(["a": NSNumber(value: true)]),
                       .dictionary(["a": .bool(true)]))
        XCTAssertNil(MGValue.fromPlistValue(1.5), "A real has no MGValue representation")
        XCTAssertNil(MGValue.fromPlistValue(Date()), "A date has no MGValue representation")
        XCTAssertNil(MGValue.fromPlistValue(nil))
        XCTAssertEqual(MGValue.bool(true).displayText, "true")
        XCTAssertEqual(MGValue.string("LL").displayText, "LL")
    }

    func testDatabaseVersion() {
        XCTAssertEqual(MGDatabase.version.mgkeysBaseline, "27.2")
        XCTAssertEqual(MGDatabase.version.lilashiftRevision, 1)
    }
}
