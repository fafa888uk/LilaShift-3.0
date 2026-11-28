// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import SettingsCore

final class LocalPlistWorkspaceTests: XCTestCase {
    func testEditDiffReadbackAndByteExactRestore() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let work = LocalPlistWorkspace(root: root)
        let original = try plist(["name": "one", "enabled": true], .binary)
        let record = try work.importCopy(original, name: "source.plist")
        let candidate = try plist(["name": "two", "count": 42, "enabled": 1], .xml)
        let change = try work.stage(xml: String(decoding: candidate, as: UTF8.self), for: record)
        XCTAssertEqual(change.changedKeys, ["count", "enabled", "name"])
        let applied = try work.apply(change)
        XCTAssertEqual(applied.working, candidate)
        XCTAssertEqual(applied.original, original)
        XCTAssertEqual(try work.records(), [applied])
        let restored = try work.restoreOriginal(id: applied.id, expectedSHA: applied.workingSHA)
        XCTAssertEqual(restored.working, original)
        XCTAssertEqual(restored.workingSHA, record.originalSHA)
    }

    func testSecondWriteCanRestoreToPreviousWorkingCopy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let work = LocalPlistWorkspace(root: root)
        let original = try plist(["name": "first"], .binary)
        let starting = try work.importCopy(original, name: "source.plist")
        let middle = try plist(["name": "middle"], .xml)
        let applied = try work.apply(work.stage(xml: String(decoding: middle, as: UTF8.self), for: starting))
        let last = try plist(["name": "last"], .xml)
        let final = try work.apply(work.stage(xml: String(decoding: last, as: UTF8.self), for: applied))
        XCTAssertEqual(final.previous, middle)
        let undone = try work.restorePrevious(id: final.id, expectedSHA: final.workingSHA)
        XCTAssertEqual(undone.working, middle)
        XCTAssertEqual(undone.original, original)
    }

    func testOldProposalCannotOverwriteNewerRevision() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let work = LocalPlistWorkspace(root: root)
        let record = try work.importCopy(plist(["name": "one"], .binary), name: "source.plist")
        let bytes = try plist(["name": "two"], .xml)
        let proposal = try work.stage(xml: String(decoding: bytes, as: UTF8.self), for: record)
        let applied = try work.apply(proposal)
        XCTAssertThrowsError(try work.apply(proposal)) {
            XCTAssertEqual($0 as? LocalPlistWorkspace.Failure, .staleRevision)
        }
        XCTAssertThrowsError(try work.restoreOriginal(id: applied.id, expectedSHA: record.workingSHA)) {
            XCTAssertEqual($0 as? LocalPlistWorkspace.Failure, .staleRevision)
        }
        XCTAssertEqual(try work.records(), [applied])
    }

    func testSameDataDoesNotCreateChanges() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let work = LocalPlistWorkspace(root: root)
        let record = try work.importCopy(plist(["name": "one"], .binary), name: "source.plist")
        XCTAssertThrowsError(try work.stage(xml: LocalPlistWorkspace.editableXML(record.working), for: record)) {
            XCTAssertEqual($0 as? LocalPlistWorkspace.Failure, .noChange)
        }
    }

    private func plist(_ value: [String: Any], _ format: PropertyListSerialization.PropertyListFormat) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0)
    }
}
