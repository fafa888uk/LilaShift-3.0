// SPDX-License-Identifier: GPL-3.0-only
// Tests for AppArchiveEngine (Stage 7, ADR-2-10, DATA_MODELS §4):
// manifest digest verification, relative-path rejection, restore
// reports, pre-restore backup, symlink skipping, and the allowlist
// rule that only this app's own data is ever archived. Nothing
// here reads or writes another app's container.
import Foundation
import XCTest
@testable import GestaltX

final class AppArchiveEngineTests: XCTestCase {
    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppArchiveEngineTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func writeFile(_ url: URL, contents: String) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func readString(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func makeSource(root: URL, kind: ArchiveRootKind = .ownDocuments) -> ArchiveSource {
        ArchiveSource(rootURL: root, kind: kind, sourceApp: "com.huami.gestultx")
    }

    // MARK: - Create and verify

    func testCreateArchiveRoundTrip() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("root")
        try writeFile(root.appendingPathComponent("a.txt"), contents: "hello")
        try writeFile(root.appendingPathComponent("sub/b.txt"), contents: "world!")
        let archives = base.appendingPathComponent("archives")

        let report = try await AppArchiveEngine.createArchive(
            from: makeSource(root: root), deviceID: "test-install-id", to: archives)
        XCTAssertEqual(report.entries.count, 2)
        XCTAssertEqual(report.totalBytes, 11)
        XCTAssertTrue(report.skippedSymlinks.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.fileURL.path))

        let manifest = try AppArchiveEngine.verifyArchive(at: report.fileURL)
        XCTAssertEqual(manifest.id, report.archiveID)
        XCTAssertEqual(manifest.deviceID, "test-install-id")
        XCTAssertEqual(manifest.formatVersion, AppArchiveEngine.currentFormatVersion)
        XCTAssertEqual(manifest.entries.count, 2)
        for entry in manifest.entries {
            let data = try Data(contentsOf: root.appendingPathComponent(entry.relativePath))
            XCTAssertEqual(entry.size, data.count)
            XCTAssertEqual(entry.sha256, BackupEngine.sha256Hex(of: data))
        }
    }

    func testEmptyDirectoryArchiveVerifies() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("root")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archives = base.appendingPathComponent("archives")

        let report = try await AppArchiveEngine.createArchive(from: makeSource(root: root), to: archives)
        XCTAssertEqual(report.entries.count, 0)
        XCTAssertEqual(report.totalBytes, 0)
        let manifest = try AppArchiveEngine.verifyArchive(at: report.fileURL)
        XCTAssertEqual(manifest.entries.count, 0)
    }

    func testSingleFileSourceArchivesOneEntry() async throws {
        let base = try tempDirectory()
        let file = base.appendingPathComponent("picked.plist")
        try writeFile(file, contents: "picked")
        let archives = base.appendingPathComponent("archives")

        let source = ArchiveSource(rootURL: file, kind: .userFile, sourceApp: "com.huami.gestultx")
        let report = try await AppArchiveEngine.createArchive(from: source, to: archives)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(report.entries[0].relativePath, "picked.plist")
        XCTAssertEqual(report.entries[0].size, 6)
        let manifest = try AppArchiveEngine.verifyArchive(at: report.fileURL)
        XCTAssertEqual(manifest.root, .userFile)
    }

    func testSymlinksAreSkippedNotArchived() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("root")
        try writeFile(root.appendingPathComponent("real.txt"), contents: "real")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link.txt"),
            withDestinationURL: root.appendingPathComponent("real.txt"))
        let archives = base.appendingPathComponent("archives")

        let report = try await AppArchiveEngine.createArchive(from: makeSource(root: root), to: archives)
        XCTAssertEqual(report.entries.count, 1)
        XCTAssertEqual(report.entries[0].relativePath, "real.txt")
        XCTAssertEqual(report.skippedSymlinks, ["link.txt"])
        let manifest = try AppArchiveEngine.verifyArchive(at: report.fileURL)
        XCTAssertEqual(manifest.entries.count, 1)
    }

    func testMissingDirectoryRootArchivesNothing() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("does-not-exist")
        let archives = base.appendingPathComponent("archives")
        let report = try await AppArchiveEngine.createArchive(from: makeSource(root: root), to: archives)
        XCTAssertEqual(report.entries.count, 0)
        let manifest = try AppArchiveEngine.verifyArchive(at: report.fileURL)
        XCTAssertEqual(manifest.entries.count, 0)
    }

    // MARK: - Manifest digest

    func testManifestDigestMismatchIsRejected() throws {
        var manifest = AppArchiveManifest(
            id: UUID(), deviceID: "test-install-id", createdAt: Date(),
            root: .ownDocuments, sourceApp: "com.huami.gestultx", entries: [],
            manifestSha256: "", formatVersion: AppArchiveEngine.currentFormatVersion)
        let data = try AppArchiveEngine.canonicalManifestData(for: manifest)
        // The digest of the empty-digest manifest is the valid one.
        manifest.manifestSha256 = BackupEngine.sha256Hex(of: data)
        XCTAssertNoThrow(try AppArchiveEngine.verifyManifestDigest(manifest))
        // Altering any byte invalidates it.
        manifest.deviceID = "someone-else"
        XCTAssertThrowsError(try AppArchiveEngine.verifyManifestDigest(manifest))
    }

    func testEntryDigestMismatchIsRejected() throws {
        let entry = ArchiveEntry(
            id: UUID(), sourceApp: "com.huami.gestultx", relativePath: "a.txt",
            size: 5, sha256: BackupEngine.sha256Hex(of: Data("hello".utf8)), capturedAt: Date())
        XCTAssertNoThrow(try AppArchiveEngine.verifyEntry(entry, data: Data("hello".utf8)))
        XCTAssertThrowsError(try AppArchiveEngine.verifyEntry(entry, data: Data("hellx".utf8)))
        XCTAssertThrowsError(try AppArchiveEngine.verifyEntry(entry, data: Data("hello!".utf8)))
    }

    func testTamperedArchiveBytesAreRejected() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("root")
        try writeFile(root.appendingPathComponent("a.txt"), contents: "hello hello hello")
        let archives = base.appendingPathComponent("archives")
        let report = try await AppArchiveEngine.createArchive(from: makeSource(root: root), to: archives)
        XCTAssertNoThrow(try AppArchiveEngine.verifyArchive(at: report.fileURL))

        // Flip bytes inside the ZIP: whatever it corrupts (compressed
        // data, CRC or central directory), verification must fail.
        var bytes = try Data(contentsOf: report.fileURL)
        for index in [bytes.count / 2, bytes.count - 10] where index < bytes.count {
            bytes[index] ^= 0xFF
        }
        try bytes.write(to: report.fileURL)
        XCTAssertThrowsError(try AppArchiveEngine.verifyArchive(at: report.fileURL))
        XCTAssertThrowsError(try AppArchiveEngine.readManifest(from: report.fileURL))
    }

    func testUnknownFormatVersionIsRejected() throws {
        let manifest = AppArchiveManifest(
            id: UUID(), deviceID: "test-install-id", createdAt: Date(),
            root: .ownDocuments, sourceApp: "com.huami.gestultx", entries: [],
            manifestSha256: "x", formatVersion: 99)
        let data = try AppArchiveEngine.canonicalManifestData(for: manifest)
        XCTAssertThrowsError(try AppArchiveEngine.migrateManifest(data))
    }

    // MARK: - Relative paths

    func testUnsafeRelativePathsAreRejected() {
        for path in ["../escape.txt", "/absolute.txt", "a//b.txt", "", "a/./b.txt",
                     "a/../b.txt", "a\\b.txt", "..", "."] {
            XCTAssertThrowsError(try AppArchiveEngine.validateRelativePath(path), path)
        }
    }

    func testSafeRelativePathsAreAccepted() throws {
        for path in ["a.txt", "sub/dir/file.plist", "a-b_c.d/e.txt"] {
            XCTAssertEqual(try AppArchiveEngine.validateRelativePath(path), path)
        }
    }

    // MARK: - Restore

    func testRestoreRoundTripAndPreRestoreBackup() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("root")
        try writeFile(root.appendingPathComponent("a.txt"), contents: "original")
        let archives = base.appendingPathComponent("archives")
        let report = try await AppArchiveEngine.createArchive(
            from: makeSource(root: root), to: archives)

        // Change the live file, then restore.
        try writeFile(root.appendingPathComponent("a.txt"), contents: "modified!!")
        let restore = try await AppArchiveEngine.restoreArchive(
            at: report.fileURL, to: makeSource(root: root), archivesDirectory: archives)
        XCTAssertEqual(restore.restored, ["a.txt"])
        // Diagnostic (fix7): print the failure reason so the next CI
        // log shows why the restore loop recorded a failure even
        // though the file content was written correctly.
        XCTAssertTrue(restore.failed.isEmpty, "\(restore.failed)")
        XCTAssertEqual(try readString(root.appendingPathComponent("a.txt")), "original")
        // The pre-restore backup is a real archive holding the
        // modified bytes, and it is listed by the scan.
        let scan = AppArchiveEngine.scanArchives(in: archives)
        XCTAssertTrue(scan.valid.contains { $0.manifest.id == restore.preRestoreArchiveID })
        let preRestore = try AppArchiveEngine.verifyArchive(
            at: archives.appendingPathComponent("archive-\(restore.preRestoreArchiveID.uuidString).zip"))
        XCTAssertEqual(preRestore.entries.count, 1)
    }

    func testRestorePickedFileThatIsGone() async throws {
        // Archive a picked file, delete the original, restore: the
        // pre-restore backup is empty, and the file comes back.
        let base = try tempDirectory()
        let file = base.appendingPathComponent("picked.plist")
        try writeFile(file, contents: "picked")
        let archives = base.appendingPathComponent("archives")
        let source = ArchiveSource(rootURL: file, kind: .userFile, sourceApp: "com.huami.gestultx")
        let report = try await AppArchiveEngine.createArchive(from: source, to: archives)
        try FileManager.default.removeItem(at: file)

        let restore = try await AppArchiveEngine.restoreArchive(
            at: report.fileURL, to: source, archivesDirectory: archives)
        XCTAssertEqual(restore.restored, ["picked.plist"])
        XCTAssertTrue(restore.failed.isEmpty)
        XCTAssertEqual(try readString(file), "picked")
    }

    func testSymlinkedDirectoryCannotPullInOutsideFiles() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("root")
        let outside = base.appendingPathComponent("outside")
        try writeFile(outside.appendingPathComponent("secret.txt"), contents: "secret")
        try writeFile(root.appendingPathComponent("real.txt"), contents: "real")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linkdir"),
            withDestinationURL: outside)
        let archives = base.appendingPathComponent("archives")

        let report = try await AppArchiveEngine.createArchive(from: makeSource(root: root), to: archives)
        XCTAssertEqual(report.entries.map { $0.relativePath }, ["real.txt"])
        XCTAssertTrue(report.skippedSymlinks.contains { $0.hasPrefix("linkdir") })
        // The outside file's bytes are nowhere in the archive.
        let manifest = try AppArchiveEngine.verifyArchive(at: report.fileURL)
        XCTAssertFalse(manifest.entries.contains { $0.relativePath.contains("secret") })
    }

    func testRestoreSkipsFilesAlreadyIdentical() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("root")
        try writeFile(root.appendingPathComponent("a.txt"), contents: "same")
        let archives = base.appendingPathComponent("archives")
        let report = try await AppArchiveEngine.createArchive(from: makeSource(root: root), to: archives)

        // Change the live file so the first restore genuinely writes;
        // the second restore then finds identical bytes and skips.
        try writeFile(root.appendingPathComponent("a.txt"), contents: "changed")
        let first = try await AppArchiveEngine.restoreArchive(
            at: report.fileURL, to: makeSource(root: root), archivesDirectory: archives)
        XCTAssertEqual(first.restored, ["a.txt"])
        let second = try await AppArchiveEngine.restoreArchive(
            at: report.fileURL, to: makeSource(root: root), archivesDirectory: archives)
        XCTAssertTrue(second.restored.isEmpty)
        XCTAssertEqual(second.skipped, ["a.txt"])
        XCTAssertTrue(second.failed.isEmpty)
    }

    func testRestoreNeverRunsOnCorruptArchive() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("root")
        try writeFile(root.appendingPathComponent("a.txt"), contents: "original")
        let archives = base.appendingPathComponent("archives")
        let report = try await AppArchiveEngine.createArchive(from: makeSource(root: root), to: archives)

        // Corrupt the archive, then change the live file.
        var bytes = try Data(contentsOf: report.fileURL)
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: report.fileURL)
        try writeFile(root.appendingPathComponent("a.txt"), contents: "modified!!")
        let beforeCount = AppArchiveEngine.scanArchives(in: archives).valid.count

        do {
            _ = try await AppArchiveEngine.restoreArchive(
                at: report.fileURL, to: makeSource(root: root), archivesDirectory: archives)
            XCTFail("Restore of a corrupt archive must throw")
        } catch {
            // expected: verification fails before any write
        }
        // The live file is untouched and no pre-restore backup was made.
        XCTAssertEqual(try readString(root.appendingPathComponent("a.txt")), "modified!!")
        XCTAssertEqual(AppArchiveEngine.scanArchives(in: archives).valid.count, beforeCount)
    }

    func testRestoreReportListsFailedItems() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("root")
        try writeFile(root.appendingPathComponent("a.txt"), contents: "aaa")
        try writeFile(root.appendingPathComponent("b.txt"), contents: "bbb")
        let archives = base.appendingPathComponent("archives")
        let report = try await AppArchiveEngine.createArchive(from: makeSource(root: root), to: archives)

        // Block one target: a directory where the file should go.
        try FileManager.default.removeItem(at: root.appendingPathComponent("b.txt"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("b.txt"), withIntermediateDirectories: false)
        let restore = try await AppArchiveEngine.restoreArchive(
            at: report.fileURL, to: makeSource(root: root), archivesDirectory: archives)
        // a.txt is byte-identical on disk, so it is skipped, not
        // restored; only the blocked b.txt fails.
        XCTAssertEqual(restore.restored, [])
        XCTAssertEqual(restore.skipped, ["a.txt"])
        XCTAssertEqual(restore.failed.map { $0.path }, ["b.txt"])
        XCTAssertFalse(restore.failed[0].reason.isEmpty)
        XCTAssertEqual(try readString(root.appendingPathComponent("a.txt")), "aaa")
    }

    // MARK: - Scan and delete

    func testScanListsValidAndCorruptArchives() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("root")
        try writeFile(root.appendingPathComponent("a.txt"), contents: "x")
        let archives = base.appendingPathComponent("archives")
        let report = try await AppArchiveEngine.createArchive(from: makeSource(root: root), to: archives)
        try Data("not a zip".utf8).write(
            to: archives.appendingPathComponent("broken.zip"))

        let scan = AppArchiveEngine.scanArchives(in: archives)
        XCTAssertEqual(scan.valid.map { $0.manifest.id }, [report.archiveID])
        XCTAssertEqual(scan.corrupt, ["broken.zip"])
    }

    func testDeleteArchiveRefusesOutsideFiles() async throws {
        let base = try tempDirectory()
        let root = base.appendingPathComponent("root")
        try writeFile(root.appendingPathComponent("a.txt"), contents: "x")
        let archives = base.appendingPathComponent("archives")
        let report = try await AppArchiveEngine.createArchive(from: makeSource(root: root), to: archives)

        // A zip elsewhere is refused, even with the right extension.
        let elsewhere = base.appendingPathComponent("elsewhere.zip")
        try FileManager.default.copyItem(at: report.fileURL, to: elsewhere)
        XCTAssertThrowsError(try AppArchiveEngine.deleteArchive(at: elsewhere, in: archives))
        XCTAssertTrue(FileManager.default.fileExists(atPath: elsewhere.path))

        try AppArchiveEngine.deleteArchive(at: report.fileURL, in: archives)
        XCTAssertFalse(FileManager.default.fileExists(atPath: report.fileURL.path))
    }
}
