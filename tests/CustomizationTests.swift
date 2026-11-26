// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

/// Tiny ZIP_STORED archives generated independently with Python zipfile.
/// Embedding the fixtures makes archive safety checks runnable in every CI job.
final class CustomizationTests: XCTestCase {
    private let fileManager = FileManager.default

    func testValidArchiveExtractsExpectedBytes() throws {
        try withArchive(Self.validArchive) { source, destination, _ in
            try CustomizationArchive.extract(source, into: destination)
            let output = destination.appendingPathComponent("safe/file.txt")
            XCTAssertEqual(try Data(contentsOf: output), Data("LilaShift archive check\n".utf8))
        }
    }

    func testTraversalArchiveCannotModifySiblingFile() throws {
        try withArchive(Self.traversalArchive) { source, destination, parent in
            let outside = parent.appendingPathComponent("outside.txt")
            let original = Data("keep outside contents".utf8)
            try original.write(to: outside)
            XCTAssertThrowsError(try CustomizationArchive.extract(source, into: destination))
            XCTAssertEqual(try Data(contentsOf: outside), original)
            XCTAssertFalse(fileManager.fileExists(atPath: destination.path))
        }
    }

    func testSymbolicLinkArchiveIsRejectedBeforeExtraction() throws {
        try withArchive(Self.symlinkArchive) { source, destination, parent in
            let outside = parent.appendingPathComponent("outside.txt")
            let original = Data("keep symlink target".utf8)
            try original.write(to: outside)
            XCTAssertThrowsError(try CustomizationArchive.extract(source, into: destination))
            XCTAssertEqual(try Data(contentsOf: outside), original)
            XCTAssertFalse(fileManager.fileExists(atPath: destination.path))
        }
    }

    func testCaseCollidingArchiveNamesAreRejected() throws {
        try withArchive(Self.duplicateArchive) { source, destination, _ in
            XCTAssertThrowsError(try CustomizationArchive.extract(source, into: destination))
            XCTAssertFalse(fileManager.fileExists(atPath: destination.path))
        }
    }

    func testCorruptArchiveCRCRemovesPartialExtraction() throws {
        try withArchive(Self.corruptCRCArchive) { source, destination, _ in
            let sourceBefore = try Data(contentsOf: source)
            XCTAssertThrowsError(try CustomizationArchive.extract(source, into: destination))
            XCTAssertFalse(fileManager.fileExists(atPath: destination.path))
            XCTAssertEqual(try Data(contentsOf: source), sourceBefore)
        }
    }

    private func withArchive(
        _ fixture: String,
        check: (URL, URL, URL) throws -> Void
    ) throws {
        let parent = fileManager.temporaryDirectory
            .appendingPathComponent("LilaShift-ArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: parent) }
        let source = parent.appendingPathComponent("input.zip")
        let destination = parent.appendingPathComponent("output", isDirectory: true)
        try XCTUnwrap(Data(base64Encoded: fixture)).write(to: source)
        try check(source, destination, parent)
    }

    private static let validArchive = "UEsDBBQAAAAAAAAAe12X9ckpGAAAABgAAAANAAAAc2FmZS9maWxlLnR4dExpbGFTaGlmdCBhcmNoaXZlIGNoZWNrClBLAQIUAxQAAAAAAAAAe12X9ckpGAAAABgAAAANAAAAAAAAAAAAAACkgQAAAABzYWZlL2ZpbGUudHh0UEsFBgAAAAABAAEAOwAAAEMAAAAAAA=="
    private static let traversalArchive = "UEsDBBQAAAAAAAAAe10fKKpnAgAAAAIAAAAOAAAALi4vb3V0c2lkZS50eHRub1BLAQIUAxQAAAAAAAAAe10fKKpnAgAAAAIAAAAOAAAAAAAAAAAAAACkgQAAAAAuLi9vdXRzaWRlLnR4dFBLBQYAAAAAAQABADwAAAAuAAAAAAA="
    private static let symlinkArchive = "UEsDBBQAAAAAAAAAe13GnafXDgAAAA4AAAAEAAAAbGluay4uL291dHNpZGUudHh0UEsBAhQDFAAAAAAAAAB7Xcadp9cOAAAADgAAAAQAAAAAAAAAAAAAAP+hAAAAAGxpbmtQSwUGAAAAAAEAAQAyAAAAMAAAAAAA"
    private static let duplicateArchive = "UEsDBBQAAAAAAAAAe13xhmx6AwAAAAMAAAAJAAAAcGhvdG8udHh0b25lUEsDBBQAAAAAAAAAe11misoRAwAAAAMAAAAJAAAAUEhPVE8uVFhUdHdvUEsBAhQDFAAAAAAAAAB7XfGGbHoDAAAAAwAAAAkAAAAAAAAAAAAAAKSBAAAAAHBob3RvLnR4dFBLAQIUAxQAAAAAAAAAe11misoRAwAAAAMAAAAJAAAAAAAAAAAAAACkgSoAAABQSE9UTy5UWFRQSwUGAAAAAAIAAgBuAAAAVAAAAAAA"
    private static let corruptCRCArchive = "UEsDBBQAAAAAAAAAe12X9ckpGAAAABgAAAANAAAAc2FmZS9maWxlLnR4dFhpbGFTaGlmdCBhcmNoaXZlIGNoZWNrClBLAQIUAxQAAAAAAAAAe12X9ckpGAAAABgAAAANAAAAAAAAAAAAAACkgQAAAABzYWZlL2ZpbGUudHh0UEsFBgAAAAABAAEAOwAAAEMAAAAAAA=="
}
