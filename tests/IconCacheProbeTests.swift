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
        // "longer.isdata" and the symlink are enumerated as metadata-only
        // diagnostics but must never appear as matches.
        XCTAssertFalse(evidence.matchesDetail.contains { $0.file.contains("longer.isdata") })
        XCTAssertFalse(evidence.matchesDetail.contains { $0.file.contains("aliased.isdata") })
        XCTAssertEqual(DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: "../unsupported").matches, 0)
        // Every entry is enumerated: four in the root plus the one file
        // inside the UUID subdirectory.
        XCTAssertEqual(evidence.entriesDetail.count, 5)
        XCTAssertEqual(evidence.unreadableStageCounts, ["nonRegular": 1])
        XCTAssertEqual(evidence.unreadable, 0)
        let aliased = try XCTUnwrap(evidence.entriesDetail.first { $0.name == "aliased.isdata" })
        XCTAssertEqual(aliased.stage, "nonRegular")
        XCTAssertEqual(aliased.fileType, "symlink")
        XCTAssertEqual(aliased.target, outside.path)
    }

    func testProbeDiagnosticsRecordSymlinkTargetAndNonRegularEntries() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = root.appendingPathComponent("cache")
        try files.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }

        let target = "com.yueyou.cyreader"
        try Data([0]).write(to: cache.appendingPathComponent(target + ".isdata"))
        let outside = root.appendingPathComponent("outside.isdata")
        try Data(target.utf8).write(to: outside)
        try files.createSymbolicLink(at: cache.appendingPathComponent("aliased.isdata"), withDestinationURL: outside)
        let fifo = cache.appendingPathComponent("pipe.isdata")
        XCTAssertEqual(mkfifo(fifo.path, 0o644), 0)

        let descriptor = open(cache.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }

        let evidence = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: target)
        XCTAssertEqual(evidence.matches, 1)
        XCTAssertFalse(evidence.matchesDetail.contains { $0.file.contains("aliased.isdata") })
        XCTAssertFalse(evidence.matchesDetail.contains { $0.file.contains("pipe.isdata") })

        let aliased = try XCTUnwrap(evidence.entriesDetail.first { $0.name == "aliased.isdata" })
        XCTAssertEqual(aliased.stage, "nonRegular")
        XCTAssertEqual(aliased.fileType, "symlink")
        XCTAssertEqual(aliased.direntType, 10) // DT_LNK
        XCTAssertEqual(aliased.target, outside.path)

        let pipe = try XCTUnwrap(evidence.entriesDetail.first { $0.name == "pipe.isdata" })
        XCTAssertEqual(pipe.stage, "nonRegular")
        XCTAssertEqual(pipe.fileType, "fifo")
        XCTAssertEqual(pipe.direntType, 1) // DT_FIFO

        let regular = try XCTUnwrap(evidence.entriesDetail.first { $0.name == target + ".isdata" })
        XCTAssertNil(regular.stage)
        XCTAssertEqual(regular.fileType, "regular")
        XCTAssertEqual(regular.direntType, 8) // DT_REG
        XCTAssertTrue(regular.mode?.hasPrefix("100") ?? false)
        XCTAssertEqual(regular.size, 1)
        XCTAssertNotNil(regular.uid)
        XCTAssertNotNil(regular.gid)
        XCTAssertNotNil(regular.inode)

        XCTAssertEqual(evidence.directoryStats.count, 1)
        XCTAssertTrue(evidence.directoryStats[0].mode.hasPrefix("40"))
        XCTAssertEqual(evidence.unreadableStageCounts["nonRegular"], 2)
        XCTAssertEqual(evidence.unreadable, 0)
    }

    func testProbeDiagnosticsRecordUnreadableRegularFileWithStageAndErrno() throws {
        // chmod 000 only blocks the open for a non-root runner.
        guard geteuid() != 0 else { throw XCTSkip("Unreadable-file diagnostics need a non-root runner.") }
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = root.appendingPathComponent("cache")
        try files.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }

        let target = "com.yueyou.cyreader"
        let locked = cache.appendingPathComponent("locked.isdata")
        try Data(target.utf8).write(to: locked)
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        defer { try? files.setAttributes([.posixPermissions: 0o644], ofItemAtPath: locked.path) }

        let descriptor = open(cache.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }

        let evidence = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: target)
        XCTAssertEqual(evidence.matches, 0)
        XCTAssertEqual(evidence.unreadable, 1)
        XCTAssertEqual(evidence.unreadableStageCounts["prefixOpen"], 1)
        XCTAssertTrue(evidence.unreadableSummary.contains("prefixOpen"))
        let detail = try XCTUnwrap(evidence.entriesDetail.first { $0.name == "locked.isdata" })
        XCTAssertEqual(detail.stage, "prefixOpen")
        XCTAssertEqual(detail.errno, Int(EACCES))
        XCTAssertEqual(detail.size, target.utf8.count)
        XCTAssertEqual(detail.fileType, "regular")
    }

    func testProbeDiagnosticsRecordUnreadableSubdirectoryWithChildOpenStage() throws {
        guard geteuid() != 0 else { throw XCTSkip("Unreadable-directory diagnostics need a non-root runner.") }
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = root.appendingPathComponent("cache")
        let child = cache.appendingPathComponent(UUID().uuidString)
        try files.createDirectory(at: child, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        try files.setAttributes([.posixPermissions: 0o000], ofItemAtPath: child.path)
        defer { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: child.path) }

        let descriptor = open(cache.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }

        let evidence = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: "com.yueyou.cyreader")
        XCTAssertEqual(evidence.unreadable, 1)
        XCTAssertEqual(evidence.unreadableStageCounts["childOpen"], 1)
        let detail = try XCTUnwrap(evidence.entriesDetail.first { $0.name == child.lastPathComponent })
        XCTAssertEqual(detail.stage, "childOpen")
        XCTAssertEqual(detail.errno, Int(EACCES))
        XCTAssertEqual(detail.fileType, "directory")
    }

    func testGateRefusesWithoutMatchAndNonTargetBundleID() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = root.appendingPathComponent("cache")
        try files.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }

        let target = "com.yueyou.cyreader"
        try Data([0]).write(to: cache.appendingPathComponent(target + ".isdata"))

        let descriptor = open(cache.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }

        let matchEvidence = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: target)
        XCTAssertEqual(matchEvidence.matches, 1)

        // The same directory probed for another bundle ID has no matches.
        let noMatch = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: "com.example.other")
        XCTAssertEqual(noMatch.matches, 0)

        guard case .blocked(let noMatchReason) = IconCacheWriteGate.evaluate(noMatch, bundleID: target) else {
            return XCTFail("Gate should block evidence without a match")
        }
        XCTAssertEqual(noMatchReason, appearanceDiagnosticText("No candidate record matches this app."))

        guard case .blocked(let scopeReason) = IconCacheWriteGate.evaluate(matchEvidence, bundleID: "com.tencent.xin") else {
            return XCTFail("Gate should block a non-七猫小说 bundle ID")
        }
        XCTAssertEqual(scopeReason, appearanceDiagnosticText("Only 七猫小说 is in scope for the first write target."))

        guard case .ready(let record) = IconCacheWriteGate.evaluate(matchEvidence, bundleID: target) else {
            return XCTFail("Gate should be ready with a matching record")
        }
        XCTAssertEqual(record.bundleID, target)
        XCTAssertEqual(record.relativePath, target + ".isdata")
        XCTAssertEqual(record.sha256AtProbe.count, 64)

        guard case .blocked(let iconReason) = IconCacheWriteGate.evaluateIconReplacement() else {
            return XCTFail("Icon replacement must be refused")
        }
        XCTAssertEqual(iconReason, appearanceDiagnosticText("Icon record format not confirmed"))
    }

    func testMutationBuilderReplacesUTF8AndUTF16LENameBytes() throws {
        let current = "七猫小说"
        let replacement = "七猫小説"
        let currentUTF8 = try XCTUnwrap(current.data(using: .utf8))
        let currentUTF16 = try XCTUnwrap(current.data(using: .utf16LittleEndian))
        let replacementUTF8 = try XCTUnwrap(replacement.data(using: .utf8))
        let replacementUTF16 = try XCTUnwrap(replacement.data(using: .utf16LittleEndian))

        // UTF-8 form: only the name bytes change.
        let prefix = Data("ab".utf8) + currentUTF8 + Data("cd".utf8)
        let utf8Mutation = try WriteMutation.displayNameReplacement(prefix: prefix, currentName: current,
                                                                    newName: replacement).get()
        XCTAssertEqual(utf8Mutation.offset, 2)
        XCTAssertEqual(utf8Mutation.length, currentUTF8.count)
        XCTAssertEqual(utf8Mutation.replacement, replacementUTF8)
        XCTAssertEqual(try XCTUnwrap(utf8Mutation.applied(to: prefix)),
                       Data("ab".utf8) + replacementUTF8 + Data("cd".utf8))

        // UTF-16LE form.
        let widePrefix = Data("ab".utf8) + currentUTF16 + Data("cd".utf8)
        let wideMutation = try WriteMutation.displayNameReplacement(prefix: widePrefix, currentName: current,
                                                                    newName: replacement).get()
        XCTAssertEqual(wideMutation.offset, 2)
        XCTAssertEqual(wideMutation.length, currentUTF16.count)
        XCTAssertEqual(wideMutation.replacement, replacementUTF16)
        XCTAssertEqual(try XCTUnwrap(wideMutation.applied(to: widePrefix)),
                       Data("ab".utf8) + replacementUTF16 + Data("cd".utf8))

        // Out of range: the mutation cannot apply to a shorter buffer.
        XCTAssertNil(utf8Mutation.applied(to: Data("ab".utf8)))

        // Absent name.
        guard case .failure(let missing) = WriteMutation.displayNameReplacement(
            prefix: Data("nothing here".utf8), currentName: current, newName: replacement) else {
            return XCTFail("Builder should fail when the name is absent")
        }
        XCTAssertEqual(missing, .notFound)

        // Ambiguous: the name occurs twice.
        let doubled = currentUTF8 + Data("-".utf8) + currentUTF8
        guard case .failure(let ambiguous) = WriteMutation.displayNameReplacement(
            prefix: doubled, currentName: current, newName: replacement) else {
            return XCTFail("Builder should fail when the name occurs twice")
        }
        XCTAssertEqual(ambiguous, .ambiguous)

        // Different byte length: the new name cannot replace in place.
        guard case .failure(let length) = WriteMutation.displayNameReplacement(
            prefix: prefix, currentName: current, newName: "七猫") else {
            return XCTFail("Builder should fail when the new name has a different byte length")
        }
        XCTAssertEqual(length, .lengthMismatch)
    }

    func testBackupRestoreRoundTripRestoresExactBytes() throws {
        let fixture = try makeWriteFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backupDirectory = fixture.root.appendingPathComponent("backup")
        var plan = IconCacheWritePlan()
        try plan.backup(cacheRoot: fixture.cache, backupDirectory: backupDirectory, record: fixture.record)
        XCTAssertEqual(plan.state, .backedUp)
        let original = try Data(contentsOf: fixture.file)
        try Data("corrupted-contents".utf8).write(to: fixture.file, options: .atomic)
        XCTAssertNotEqual(try Data(contentsOf: fixture.file), original)
        try plan.restore(cacheRoot: fixture.cache, backupDirectory: backupDirectory)
        XCTAssertEqual(plan.state, .restored)
        XCTAssertEqual(try Data(contentsOf: fixture.file), original)
        // The backup is kept after a verified restore.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: backupDirectory.appendingPathComponent("backup.bin").path))
    }

    func testWriteRefusesOnSHAMismatch() throws {
        let fixture = try makeWriteFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backupDirectory = fixture.root.appendingPathComponent("backup")
        var plan = IconCacheWritePlan()
        try plan.backup(cacheRoot: fixture.cache, backupDirectory: backupDirectory, record: fixture.record)
        // Change the live bytes (same size) after the backup.
        var changed = try Data(contentsOf: fixture.file)
        changed[0] = changed[0] ^ 0xFF
        try changed.write(to: fixture.file, options: .atomic)
        do {
            try plan.write(cacheRoot: fixture.cache, backupDirectory: backupDirectory,
                           evidence: fixture.evidence, currentName: "七猫小说",
                           newName: "七猫小説", bootBefore: nil)
            XCTFail("Write should refuse a file that changed since the probe")
        } catch let error as IconCacheWriteError {
            XCTAssertEqual(error, .shaMismatch)
        }
        XCTAssertEqual(plan.state, .backedUp)
    }

    func testWriteRefusesWhenEvidenceHasMoreThanOneMatch() throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = root.appendingPathComponent("cache")
        try files.createDirectory(at: cache, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }

        let target = "com.yueyou.cyreader"
        try Data(target.utf8).write(to: cache.appendingPathComponent("first.isdata"))
        try Data(target.utf8).write(to: cache.appendingPathComponent("second.isdata"))
        let descriptor = open(cache.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }
        let evidence = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: target)
        XCTAssertEqual(evidence.matches, 2)
        let record = try XCTUnwrap(VerifiedIconCacheRecord.fromEvidence(evidence, bundleID: target))

        let backupDirectory = root.appendingPathComponent("backup")
        var plan = IconCacheWritePlan()
        try plan.backup(cacheRoot: cache, backupDirectory: backupDirectory, record: record)
        do {
            try plan.write(cacheRoot: cache, backupDirectory: backupDirectory, evidence: evidence,
                           currentName: "七猫小说", newName: "七猫小説", bootBefore: nil)
            XCTFail("Write should refuse evidence with more than one match")
        } catch let error as IconCacheWriteError {
            XCTAssertEqual(error, .unexpectedMatchCount(2))
        }
    }

    func testWriteReadBackAndRestartVerificationFlow() throws {
        let fixture = try makeWriteFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backupDirectory = fixture.root.appendingPathComponent("backup")
        var plan = IconCacheWritePlan()
        try plan.backup(cacheRoot: fixture.cache, backupDirectory: backupDirectory, record: fixture.record)
        XCTAssertEqual(plan.state, .backedUp)
        try plan.write(cacheRoot: fixture.cache, backupDirectory: backupDirectory,
                       evidence: fixture.evidence, currentName: "七猫小说", newName: "七猫小説",
                       bootBefore: BootSession(seconds: 1000, microseconds: 0))
        XCTAssertEqual(plan.state, .written)
        let written = try Data(contentsOf: fixture.file)
        XCTAssertNotNil(written.range(of: Data("七猫小説".utf8)))
        XCTAssertNil(written.range(of: Data("七猫小说".utf8)))
        XCTAssertEqual(written.count, fixture.record.size)
        try plan.readBack(cacheRoot: fixture.cache, backupDirectory: backupDirectory)
        XCTAssertEqual(plan.state, .readBackVerified)
        try plan.beginRestartWait()
        XCTAssertEqual(plan.state, .awaitingRestartVerification)
        // No reboot yet: the state must not advance.
        XCTAssertFalse(plan.verifyAfterRestart(newEvidence: fixture.evidence, bootChanged: false))
        XCTAssertEqual(plan.state, .awaitingRestartVerification)
        // A reboot alone is not enough: stale evidence (pre-write prefix
        // hash) must not verify.
        XCTAssertFalse(plan.verifyAfterRestart(newEvidence: fixture.evidence, bootChanged: true))
        XCTAssertEqual(plan.state, .awaitingRestartVerification)
        // A fresh probe after the reboot still shows the mutation.
        let descriptor = open(fixture.cache.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }
        let fresh = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: "com.yueyou.cyreader")
        XCTAssertEqual(fresh.matches, 1)
        XCTAssertTrue(plan.verifyAfterRestart(newEvidence: fresh, bootChanged: true))
        XCTAssertEqual(plan.state, .verifiedAfterRestart)
    }

    func testReadBackMismatchRestoresBackupImmediately() throws {
        let fixture = try makeWriteFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let backupDirectory = fixture.root.appendingPathComponent("backup")
        let original = try Data(contentsOf: fixture.file)
        var plan = IconCacheWritePlan()
        try plan.backup(cacheRoot: fixture.cache, backupDirectory: backupDirectory, record: fixture.record)
        try plan.write(cacheRoot: fixture.cache, backupDirectory: backupDirectory,
                       evidence: fixture.evidence, currentName: "七猫小说", newName: "七猫小説",
                       bootBefore: nil)
        XCTAssertEqual(plan.state, .written)
        // Corrupt the live file after the write (same size, different bytes).
        var corrupted = try Data(contentsOf: fixture.file)
        corrupted[0] = corrupted[0] ^ 0xFF
        try corrupted.write(to: fixture.file, options: .atomic)
        do {
            try plan.readBack(cacheRoot: fixture.cache, backupDirectory: backupDirectory)
            XCTFail("Read-back should refuse corrupted bytes")
        } catch let error as IconCacheWriteError {
            XCTAssertEqual(error, .readBackMismatch)
        }
        XCTAssertEqual(plan.state, .restored)
        XCTAssertEqual(try Data(contentsOf: fixture.file), original)
    }

    /// A synthetic cache file whose prefix contains the bundle ID and the
    /// current display name in UTF-8, plus the record the probe builds
    /// for it. Exactly one file matches, so the record is deterministic.
    /// The separators are "/" on purpose: the probe only reports scoped
    /// literals, and "-" is an identifier byte, so a dash-joined token
    /// such as "header-com.yueyou.cyreader-..." would not match.
    private func makeWriteFixture() throws -> (root: URL, cache: URL, file: URL,
                                              record: VerifiedIconCacheRecord,
                                              evidence: DiskIconCacheEvidence) {
        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = root.appendingPathComponent("cache")
        try files.createDirectory(at: cache, withIntermediateDirectories: true)
        let target = "com.yueyou.cyreader"
        var content = Data()
        content.append(Data("header/".utf8))
        content.append(Data(target.utf8))
        content.append(Data("/".utf8))
        content.append(Data("七猫小说".utf8))
        content.append(Data("/tail".utf8))
        let file = cache.appendingPathComponent("record.isdata")
        try content.write(to: file)
        let descriptor = open(cache.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }
        let evidence = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: target)
        XCTAssertEqual(evidence.matches, 1)
        let record = try XCTUnwrap(VerifiedIconCacheRecord.fromEvidence(evidence, bundleID: target))
        return (root, cache, file, record, evidence)
    }
}
