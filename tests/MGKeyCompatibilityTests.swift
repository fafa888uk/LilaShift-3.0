// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

/// MGKeyCompatibility tests (Stage 4). The precedence is the
/// contract: sentinel first, then scope, then readability, then the
/// live value. Reasons are display text — the tests assert the
/// status, which is the contract, and that a reason is always given.
final class MGKeyCompatibilityTests: XCTestCase {
    private func makeRecord(obfuscatedName: String = "test-key", readableName: String = "TestKey",
                            dataType: MGValueType = .bool, defaultValue: MGValue? = nil,
                            deviceScope: DeviceScope = .all,
                            iosScope: IOSVersionRange = IOSVersionRange(introduced: "7.0", removed: nil, reintroduced: []),
                            writable: Bool = true, readableViaMGCopyAnswer: Bool = true) -> MGKeyRecord {
        MGKeyRecord(keyID: readableName, readableName: readableName, obfuscatedName: obfuscatedName,
                    dataType: dataType, defaultValue: defaultValue, deviceScope: deviceScope,
                    iosScope: iosScope, category: .device, riskLevel: .low,
                    upstreamSource: "test", license: "MIT", writable: writable, restorable: true,
                    verificationStatus: .unverified, readableViaMGCopyAnswer: readableViaMGCopyAnswer,
                    slot: nil)
    }

    private func evaluate(_ record: MGKeyRecord, productType: String? = "iPhone18,4",
                          iosVersion: String = "27.0.1", live: MGValue? = .bool(true),
                          sentinel: VersionSentinelState = .supported) -> (status: CompatibilityStatus, reason: String) {
        MGKeyCompatibility.evaluate(record: record, productType: productType,
                                    iosVersion: iosVersion, live: live, sentinel: sentinel)
    }

    func testBlockedSentinelWinsOverEverything() {
        let (status, reason) = evaluate(makeRecord(), live: .bool(true),
                                        sentinel: .blocked(build: "24C5049d"))
        XCTAssertEqual(status, .readFailed)
        XCTAssertFalse(reason.isEmpty)
    }

    func testUnknownSentinelIsUnverified() {
        let (status, _) = evaluate(makeRecord(), sentinel: .unknownBuild(build: "abc"))
        XCTAssertEqual(status, .unverified)
    }

    func testUnknownProductTypeIsUnverified() {
        let (status, _) = evaluate(makeRecord(), productType: nil)
        XCTAssertEqual(status, .unverified)
    }

    func testDeviceScope() {
        let pencil = MGDatabase.record(forKey: "yhHcB0iH0d1XzPO/CFd3ow")!
        XCTAssertEqual(evaluate(pencil, productType: "iPhone18,4").status, .unsupported)
        XCTAssertEqual(evaluate(pencil, productType: "iPad13,4").status, .enabled)
        XCTAssertEqual(evaluate(pencil, productType: "iPad13,4", live: .bool(false)).status, .modifiable)
    }

    func testIOSScope() {
        let siriMode = MGDatabase.record(forKey: GestaltKeys.siriMode)!
        XCTAssertEqual(evaluate(siriMode, iosVersion: "26.0").status, .unsupported)
        XCTAssertEqual(evaluate(siriMode, iosVersion: "27.0.1").status, .enabled)
    }

    func testUnreadableKeyIsUnverified() {
        let record = makeRecord(readableViaMGCopyAnswer: false)
        XCTAssertEqual(evaluate(record).status, .unverified)
    }

    func testNoLiveValueIsUnverified() {
        XCTAssertEqual(evaluate(makeRecord(), live: nil).status, .unverified)
    }

    func testBoolLiveValues() {
        XCTAssertEqual(evaluate(makeRecord(), live: .bool(true)).status, .enabled)
        XCTAssertEqual(evaluate(makeRecord(), live: .bool(false)).status, .modifiable)
        XCTAssertEqual(evaluate(makeRecord(writable: false), live: .bool(false)).status, .unsupported)
    }

    func testNonBoolLiveValueAgainstDefault() {
        let record = makeRecord(dataType: .string, defaultValue: .string("LL"))
        XCTAssertEqual(evaluate(record, live: .string("LL")).status, .nativeSupported)
        XCTAssertEqual(evaluate(record, live: .string("CH")).status, .unverified)
        let noDefault = makeRecord(dataType: .string)
        XCTAssertEqual(evaluate(noDefault, live: .string("LL")).status, .unverified)
    }

    func testRegionCodeIsInformational() {
        let region = MGDatabase.record(forKey: GestaltKeys.regionCode)!
        XCTAssertEqual(evaluate(region, live: .string("LL")).status, .unverified)
    }

    func testSlotKeyNativeBaselineDoesNotChangeTheBadge() {
        // The slot baseline comparison lives on the row (MGSlotProbe),
        // not in the status: #178 live false on native hardware is
        // modifiable (it may be staged), even though it matches the
        // native baseline.
        let audio = MGDatabase.record(forKey: DeviceCacheOptions.audioIntelligenceKey)!
        XCTAssertEqual(evaluate(audio, live: .bool(false)).status, .modifiable)
        XCTAssertEqual(evaluate(audio, live: .bool(true)).status, .enabled)
    }
}
