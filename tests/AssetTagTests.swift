import Foundation
import XCTest
@testable import GestaltX

/// Asset tag tests (A19, Erosion-CN `ConfigView`): the field is
/// set, read back, and removed on a temp plist standing in for
/// `SharedDeviceConfiguration.plist`. Other keys are preserved,
/// and removing the last key removes the file — exactly the
/// device behavior, without touching the real system file.
final class AssetTagTests: XCTestCase {
    private func tempPlist() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetTagTests_\(UUID().uuidString).plist")
    }

    func testApplyAndReadRoundTrip() {
        let url = tempPlist()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertNil(AssetTag.read(at: url))
        XCTAssertTrue(AssetTag.apply("IF FOUND CALL 555-1234", at: url))
        XCTAssertEqual(AssetTag.read(at: url), "IF FOUND CALL 555-1234")
    }

    func testApplyTrimsWhitespace() {
        let url = tempPlist()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(AssetTag.apply("  Lab iPhone  ", at: url))
        XCTAssertEqual(AssetTag.read(at: url), "Lab iPhone")
    }

    func testEmptyValueRemovesFieldAndFile() {
        let url = tempPlist()
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(AssetTag.apply("Some tag", at: url))
        XCTAssertTrue(AssetTag.apply("", at: url))
        XCTAssertNil(AssetTag.read(at: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testOtherKeysArePreserved() throws {
        let url = tempPlist()
        defer { try? FileManager.default.removeItem(at: url) }
        let seed: [String: Any] = ["LockScreenFootnote": "Keep this", "SomeOtherKey": 42]
        let data = try PropertyListSerialization.data(fromPropertyList: seed, format: .binary, options: 0)
        try data.write(to: url, options: .atomic)
        XCTAssertTrue(AssetTag.apply("My tag", at: url))
        let back = NSDictionary(contentsOf: url) as? [String: Any]
        XCTAssertEqual(back?["LockScreenFootnote"] as? String, "Keep this")
        XCTAssertEqual(back?["SomeOtherKey"] as? Int, 42)
        XCTAssertEqual(back?[AssetTag.key] as? String, "My tag")
        // Removing the tag leaves the other keys in place.
        XCTAssertTrue(AssetTag.apply("", at: url))
        let after = NSDictionary(contentsOf: url) as? [String: Any]
        XCTAssertNil(after?[AssetTag.key])
        XCTAssertEqual(after?["LockScreenFootnote"] as? String, "Keep this")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }
}
