// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation
import XCTest
@testable import GestaltX

final class IconCacheProbeTests: XCTestCase {
    func testOnlyScopedLiteralMatchesAreReportedAndSymlinksAreSkipped() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = root.appendingPathComponent("cache")
        let generation = cache.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: generation, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }

        let target = "com.yueyou.cyreader"
        try Data([0]).write(to: cache.appendingPathComponent(target + ".isdata"))
        let encoded = try XCTUnwrap(target.data(using: .utf16LittleEndian))
        try (Data([0, 0]) + encoded + Data([0, 0])).write(to: generation.appendingPathComponent("identifier.isindex"))
        try Data((target + ".other").utf8).write(to: cache.appendingPathComponent("longer.isdata"))

        let outside = root.appendingPathComponent("outside.isdata")
        try Data(target.utf8).write(to: outside)
        try files.createSymbolicLink(at: cache.appendingPathComponent("aliased.isdata"), withDestinationURL: outside)

        let descriptor = open(cache.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }

        let evidence = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: target)
        XCTAssertEqual(evidence.openedDirectories, 1)
        XCTAssertEqual(evidence.matches, 2)
        XCTAssertTrue(evidence.report.contains(target + ".isdata"))
        XCTAssertTrue(evidence.report.contains("identifier.isindex"))
        XCTAssertFalse(evidence.report.contains("longer.isdata"))
        XCTAssertFalse(evidence.report.contains("aliased.isdata"))
        XCTAssertEqual(DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: "../unsupported").matches, 0)
    }
}
