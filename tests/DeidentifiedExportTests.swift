// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

/// De-identified export (Stage 6, audit R-3): the identity keys are
/// stripped, everything else survives the round trip, and a
/// non-dictionary plist is refused.
final class DeidentifiedExportTests: XCTestCase {
    private func plistData(_ dict: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    private func decoded(_ data: Data) throws -> [String: Any] {
        guard let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            XCTFail("Expected a dictionary plist")
            return [:]
        }
        return dict
    }

    func testStripsObfuscatedIdentityKeys() throws {
        let input = try plistData([
            "re6Zb+zwFKJNlkQTUeT+/w": "00008150-000C0C5A14D2401C",
            "VasUgeSzVyHdB27g2XpN0g": "F17LXXXXXX",
            "TF31PAB6aO8KAbPyNKSxKA": "T8030",
            "h63QSdBCiT/z0WU6rdQv6Q": "LL",
            "someOtherKey": "kept",
        ])
        let stripped = try DeidentifiedExport.strip(input)
        XCTAssertEqual(Set(stripped.removed), [
            "re6Zb+zwFKJNlkQTUeT+/w", "VasUgeSzVyHdB27g2XpN0g", "TF31PAB6aO8KAbPyNKSxKA",
        ])
        let dict = try decoded(stripped.data)
        XCTAssertNil(dict["re6Zb+zwFKJNlkQTUeT+/w"])
        XCTAssertNil(dict["VasUgeSzVyHdB27g2XpN0g"])
        XCTAssertNil(dict["TF31PAB6aO8KAbPyNKSxKA"])
        XCTAssertEqual(dict["h63QSdBCiT/z0WU6rdQv6Q"] as? String, "LL")
        XCTAssertEqual(dict["someOtherKey"] as? String, "kept")
    }

    func testStripsReadableIdentityNames() throws {
        let input = try plistData([
            "UniqueDeviceID": "00008150-000C0C5A14D2401C",
            "SerialNumber": "F17LXXXXXX",
            "UniqueChipID": "T8030",
            "RegionCode": "LL",
        ])
        let stripped = try DeidentifiedExport.strip(input)
        XCTAssertEqual(Set(stripped.removed), ["UniqueDeviceID", "SerialNumber", "UniqueChipID"])
        let dict = try decoded(stripped.data)
        XCTAssertNil(dict["UniqueDeviceID"])
        XCTAssertNil(dict["SerialNumber"])
        XCTAssertNil(dict["UniqueChipID"])
        XCTAssertEqual(dict["RegionCode"] as? String, "LL")
    }

    func testNoIdentityKeysMeansNothingRemoved() throws {
        let input = try plistData(["h63QSdBCiT/z0WU6rdQv6Q": "LL"])
        let stripped = try DeidentifiedExport.strip(input)
        XCTAssertTrue(stripped.removed.isEmpty)
        let dict = try decoded(stripped.data)
        XCTAssertEqual(dict["h63QSdBCiT/z0WU6rdQv6Q"] as? String, "LL")
    }

    func testThrowsForNonDictionaryPlist() throws {
        let arrayPlist = try PropertyListSerialization.data(
            fromPropertyList: ["a", "b"], format: .binary, options: 0)
        XCTAssertThrowsError(try DeidentifiedExport.strip(arrayPlist)) { error in
            XCTAssertEqual(error as? DeidentifiedExportError, .notADictionaryPlist)
        }
    }

    func testDeidentifiedFileName() {
        XCTAssertTrue(DeidentifiedExport.fileName.hasSuffix("-deidentified.plist"))
        XCTAssertNotEqual(DeidentifiedExport.fileName, "MobileGestalt-LilaShift.plist")
    }
}
