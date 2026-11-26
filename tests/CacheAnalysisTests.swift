// SPDX-License-Identifier: GPL-3.0-only
// Tests for CacheAnalyzer (Stage 7, DATA_MODELS §4.3, TASKBOOK
// §6.3): per-file sizes, the protection list (Documents, chat,
// login state are never deletable), last-access honesty (nil stays
// nil), tracked-only deletion, and the convergence that the old
// AppContainerCacheMeasurer delegates to this one implementation.
import Foundation
import XCTest
@testable import GestaltX

final class CacheAnalysisTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CacheAnalysisTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func writeFile(_ url: URL, bytes: Int) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    private func fixture() throws -> (base: URL, appSupport: URL, caches: URL, tmp: URL) {
        let base = try tempDirectory()
        let appSupport = base.appendingPathComponent("Application Support")
        let caches = base.appendingPathComponent("Caches")
        let tmp = base.appendingPathComponent("tmp")
        return (base, appSupport, caches, tmp)
    }

    // MARK: - Analysis

    func testAnalyzeRealSizesAndCategories() throws {
        let fixture = try fixture()
        try writeFile(fixture.appSupport.appendingPathComponent("store.plist"), bytes: 100)
        try writeFile(fixture.caches.appendingPathComponent("sub/thumb.dat"), bytes: 200)
        try writeFile(fixture.tmp.appendingPathComponent("work.tmp"), bytes: 50)

        let report = CacheAnalyzer.analyze(
            applicationSupport: fixture.appSupport, caches: fixture.caches, temporary: fixture.tmp)
        XCTAssertEqual(report.totalSize, 350)
        XCTAssertEqual(report.totalFiles, 3)
        XCTAssertEqual(report.entries(for: .caches).count, 1)
        XCTAssertEqual(report.entries(for: .tmp).count, 1)
        XCTAssertEqual(report.entries(for: .other).count, 1)
        // Largest first.
        XCTAssertEqual(report.entries.map { $0.size }, [200, 100, 50])
        XCTAssertEqual(report.entries(for: .caches)[0].relativePath, "sub/thumb.dat")
    }

    func testAnalyzeMissingDirectoriesAreZero() throws {
        let fixture = try fixture()
        let report = CacheAnalyzer.analyze(
            applicationSupport: fixture.appSupport, caches: fixture.caches, temporary: fixture.tmp)
        XCTAssertEqual(report.totalSize, 0)
        XCTAssertEqual(report.totalFiles, 0)
        XCTAssertTrue(report.entries.isEmpty)
    }

    // MARK: - Protection

    func testApplicationSupportIsNeverDeletable() throws {
        let fixture = try fixture()
        try writeFile(fixture.appSupport.appendingPathComponent("GestaltX/vault.plist"), bytes: 100)
        let report = CacheAnalyzer.analyze(
            applicationSupport: fixture.appSupport, caches: fixture.caches, temporary: fixture.tmp)
        let entry = try XCTUnwrap(report.entries.first)
        XCTAssertEqual(entry.category, .other)
        XCTAssertFalse(entry.safeToDelete)
        XCTAssertNotNil(entry.protectionReason)
    }

    func testProtectedNamesInCachesAreNeverDeletable() throws {
        let fixture = try fixture()
        for name in ["chat.db", "login-state.json", "keychain.plist", "account.json",
                     "Messages.sqlite", "user-token.cache"] {
            try writeFile(fixture.caches.appendingPathComponent(name), bytes: 10)
        }
        try writeFile(fixture.caches.appendingPathComponent("thumb.dat"), bytes: 10)
        let report = CacheAnalyzer.analyze(
            applicationSupport: fixture.appSupport, caches: fixture.caches, temporary: fixture.tmp)
        XCTAssertEqual(report.entries.count, 7)
        for entry in report.entries where entry.relativePath != "thumb.dat" {
            XCTAssertFalse(entry.safeToDelete, entry.relativePath)
            XCTAssertNotNil(entry.protectionReason, entry.relativePath)
        }
        let ordinary = try XCTUnwrap(report.entries.first { $0.relativePath == "thumb.dat" })
        XCTAssertTrue(ordinary.safeToDelete)
        XCTAssertNil(ordinary.protectionReason)
    }

    /// The pure mapping: an unknown access time stays unknown, and
    /// a known one is carried through unchanged — never invented.
    func testLastAccessedNilStaysNil() {
        let unknown = CacheAnalyzer.makeEntry(
            relativePath: "a.dat", size: 10, lastAccessed: nil, category: .caches)
        XCTAssertNil(unknown.lastAccessed)
        let known = Date(timeIntervalSince1970: 1_000_000)
        let entry = CacheAnalyzer.makeEntry(
            relativePath: "a.dat", size: 10, lastAccessed: known, category: .caches)
        XCTAssertEqual(entry.lastAccessed, known)
    }

    func testSymlinkedDirectoryIsExcludedFromReport() throws {
        let fixture = try fixture()
        let outside = fixture.base.appendingPathComponent("outside")
        try writeFile(outside.appendingPathComponent("secret.dat"), bytes: 500)
        try writeFile(fixture.caches.appendingPathComponent("real.dat"), bytes: 10)
        try FileManager.default.createSymbolicLink(
            at: fixture.caches.appendingPathComponent("linkdir"),
            withDestinationURL: outside)
        let report = CacheAnalyzer.analyze(
            applicationSupport: fixture.appSupport, caches: fixture.caches, temporary: fixture.tmp)
        XCTAssertEqual(report.entries.map { $0.relativePath }, ["real.dat"])
        XCTAssertEqual(report.totalSize, 10)
    }

    // MARK: - Deletion

    func testDeleteTrackedDeletesOnlySelected() throws {
        let fixture = try fixture()
        try writeFile(fixture.caches.appendingPathComponent("drop.dat"), bytes: 200)
        try writeFile(fixture.caches.appendingPathComponent("keep.dat"), bytes: 100)
        let report = CacheAnalyzer.analyze(
            applicationSupport: fixture.appSupport, caches: fixture.caches, temporary: fixture.tmp)
        let drop = try XCTUnwrap(report.entries.first { $0.relativePath == "drop.dat" })

        let deletion = try CacheAnalyzer.deleteTracked(
            [drop], applicationSupport: fixture.appSupport, caches: fixture.caches, temporary: fixture.tmp)
        XCTAssertEqual(deletion.deleted, ["drop.dat"])
        XCTAssertEqual(deletion.freedBytes, 200)
        XCTAssertTrue(deletion.failed.isEmpty)
        XCTAssertTrue(deletion.skippedProtected.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: fixture.caches.appendingPathComponent("drop.dat").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.caches.appendingPathComponent("keep.dat").path))
    }

    func testDeleteTrackedRefusesProtectedEntries() throws {
        let fixture = try fixture()
        try writeFile(fixture.appSupport.appendingPathComponent("vault.plist"), bytes: 100)
        try writeFile(fixture.caches.appendingPathComponent("chat.db"), bytes: 50)
        let report = CacheAnalyzer.analyze(
            applicationSupport: fixture.appSupport, caches: fixture.caches, temporary: fixture.tmp)
        XCTAssertEqual(report.entries.count, 2)

        let deletion = try CacheAnalyzer.deleteTracked(
            report.entries, applicationSupport: fixture.appSupport,
            caches: fixture.caches, temporary: fixture.tmp)
        XCTAssertTrue(deletion.deleted.isEmpty)
        XCTAssertEqual(Set(deletion.skippedProtected), ["vault.plist", "chat.db"])
        XCTAssertTrue(deletion.failed.isEmpty)
        XCTAssertEqual(deletion.freedBytes, 0)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.appSupport.appendingPathComponent("vault.plist").path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.caches.appendingPathComponent("chat.db").path))
    }

    func testDeleteTrackedRefusesEscapingPaths() throws {
        let fixture = try fixture()
        let outside = fixture.base.appendingPathComponent("outside.txt")
        try writeFile(outside, bytes: 10)
        let escaping = CacheEntry(
            relativePath: "../outside.txt", size: 10, lastAccessed: nil,
            category: .caches, safeToDelete: true, protectionReason: nil)

        let deletion = try CacheAnalyzer.deleteTracked(
            [escaping], applicationSupport: fixture.appSupport,
            caches: fixture.caches, temporary: fixture.tmp)
        XCTAssertTrue(deletion.deleted.isEmpty)
        XCTAssertEqual(deletion.failed.map { $0.path }, ["../outside.txt"])
        // The file outside the roots is untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    // MARK: - Clear caches

    func testClearCachesFreesOwnCachesOnly() throws {
        let fixture = try fixture()
        try writeFile(fixture.appSupport.appendingPathComponent("keep.plist"), bytes: 100)
        try writeFile(fixture.caches.appendingPathComponent("sub/drop.dat"), bytes: 200)
        try writeFile(fixture.tmp.appendingPathComponent("keep.tmp"), bytes: 50)

        let freed = try CacheAnalyzer.clearCaches(at: fixture.caches)
        XCTAssertEqual(freed, 200)
        let after = CacheAnalyzer.analyze(
            applicationSupport: fixture.appSupport, caches: fixture.caches, temporary: fixture.tmp)
        XCTAssertEqual(after.entries(for: .caches).count, 0)
        XCTAssertEqual(after.entries(for: .other).count, 1)
        XCTAssertEqual(after.entries(for: .tmp).count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.caches.path))
    }

    func testClearCachesRefusesNonCachesDirectory() throws {
        let fixture = try fixture()
        try writeFile(fixture.appSupport.appendingPathComponent("keep.plist"), bytes: 100)
        XCTAssertThrowsError(try CacheAnalyzer.clearCaches(at: fixture.appSupport))
        XCTAssertThrowsError(try CacheAnalyzer.clearCaches(
            at: fixture.base.appendingPathComponent("NotCaches")))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.appSupport.appendingPathComponent("keep.plist").path))
    }

    // MARK: - Convergence

    /// The old measurer delegates to this analyzer: both must agree
    /// on the totals for the same fixture, or the convergence is a
    /// second implementation in disguise.
    func testOldMeasurerAgreesWithAnalyzer() throws {
        let fixture = try fixture()
        try writeFile(fixture.appSupport.appendingPathComponent("a.plist"), bytes: 100)
        try writeFile(fixture.caches.appendingPathComponent("sub/b.dat"), bytes: 200)
        try writeFile(fixture.tmp.appendingPathComponent("c.tmp"), bytes: 50)

        let legacy = AppContainerCacheMeasurer.measure(
            applicationSupport: fixture.appSupport, caches: fixture.caches, temporary: fixture.tmp)
        let report = CacheAnalyzer.analyze(
            applicationSupport: fixture.appSupport, caches: fixture.caches, temporary: fixture.tmp)
        XCTAssertEqual(legacy.totalBytes, Int64(report.totalSize))
        XCTAssertEqual(legacy.totalFiles, report.totalFiles)
        XCTAssertEqual(legacy.entry(for: .applicationSupport)?.byteCount, 100)
        XCTAssertEqual(legacy.entry(for: .caches)?.byteCount, 200)
        XCTAssertEqual(legacy.entry(for: .temporary)?.byteCount, 50)
    }
}
