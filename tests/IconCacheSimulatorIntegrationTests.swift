// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Foundation
import XCTest
@testable import GestaltX

/// Simulator integration tests: probe v2 + the gated write state machine
/// run against REAL paths inside the iOS Simulator sandbox — never a
/// hard-coded device path and never a pure fixture directory.
///
/// What this file does and does not prove
/// - It proves the mechanism works inside the range the OS actually
///   allows on the simulator: container paths resolve, the probe runs
///   on a real directory descriptor, per-entry diagnostics name the
///   failure stage, the gate opens for a real-path match and blocks
///   without one, and the write state machine walks backup -> write ->
///   read-back -> restart-wait -> restore inside the app's own container.
/// - It does NOT prove anything about the device. On a real iPhone the
///   sandbox paths and permissions are stricter: the system icon-cache
///   roots live outside the app container and the whole-bundle inspect
///   is the only path that ever opens them. A green run here means the
///   plumbing is sound where the OS lets it run; device results may
///   differ and must be verified on device.
/// - The one honest simulator stop point is pinned, not skipped: the
///   whole-bundle inspect (`DiskIconCacheEvidence.inspect`) is compiled
///   to an empty result on the simulator, so the gate refuses it.
///   That refusal is the expected result, not a failure.
///
/// No test here skips, and no assertion is relaxed for the simulator:
// every expected value follows from the code under test or from an
// errno the test records at the moment the open fails.
final class IconCacheSimulatorIntegrationTests: XCTestCase {
    private let target = "com.yueyou.cyreader"

    func testSimulatorContainerPathsResolveInsideAppSandbox() throws {
        let files = FileManager.default
        let home = NSHomeDirectory()
        XCTAssertFalse(home.isEmpty, "The app sandbox home must resolve")
        let caches = try XCTUnwrap(files.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let library = try XCTUnwrap(files.urls(for: .libraryDirectory, in: .userDomainMask).first)
        let support = try XCTUnwrap(files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        for directory in [caches, library, support] {
            // iOS creates container directories lazily: on a fresh
            // simulator container Library/Application Support does not
            // exist yet. Creating it is the OS's deferred step, not a
            // relaxed assertion — the existence, is-a-directory and
            // in-sandbox checks below still run on the real path.
            try files.createDirectory(at: directory, withIntermediateDirectories: true)
            XCTAssertTrue(directory.isFileURL)
            XCTAssertTrue(directory.path.hasPrefix(home),
                          "\(directory.path) is outside the app sandbox home \(home)")
            var isDirectory: ObjCBool = false
            XCTAssertTrue(files.fileExists(atPath: directory.path, isDirectory: &isDirectory),
                          "\(directory.path) must exist in the simulator container")
            XCTAssertTrue(isDirectory.boolValue, "\(directory.path) must be a directory")
        }
        XCTAssertNotEqual(caches, library)
        XCTAssertNotEqual(caches, support)
        // The app's own caches directory is really enumerable here, and
        // open() on it succeeds: this is the real descriptor the probe
        // tests below run on.
        let names = try files.contentsOfDirectory(atPath: caches.path)
        XCTAssertTrue(names.allSatisfy { !$0.isEmpty })
        let descriptor = open(caches.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0, "open() on the real caches directory must succeed")
        close(descriptor)
    }

    func testRealDeviceIconCacheRootsAreRecordedNotSkipped() {
        // The two candidate roots from GXIconCacheProbe.inspectBundleIdentifier.
        // They are device paths; on the simulator they are expected to be
        // unreachable, and the test records exactly how each open fails
        // instead of skipping the check.
        let group = IconCacheWriteGate.iconCacheGroupPath
        XCTAssertTrue(group.hasPrefix("/private/var/containers/Shared/SystemGroup/"))
        let roots = [
            group + "/Library/Caches/com.apple.IconsCache",
            "/private/var/mobile/Library/Caches/com.apple.IconsCache",
        ]
        for root in roots {
            let descriptor = open(root, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
            if descriptor >= 0 {
                // Unexpected on the simulator, but handled honestly: probe
                // what actually opened and assert only what the probe
                // guarantees about it.
                defer { close(descriptor) }
                let evidence = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: target)
                XCTAssertEqual(evidence.openedDirectories, 1)
                XCTAssertEqual(evidence.bundleID, target)
                XCTAssertFalse(evidence.report.isEmpty)
            } else {
                let failure = errno
                XCTAssertTrue([ENOENT, EACCES, EPERM, ENOTDIR].contains(failure),
                              "Opening \(root) failed with unexpected errno \(failure)")
                XCTAssertNotEqual(failure, 0)
                if failure == ENOENT {
                    // errno 2 is the evidence: the path does not exist
                    // in this sandbox at all.
                    XCTAssertFalse(FileManager.default.fileExists(atPath: root),
                                   "\(root) reported errno 2 yet fileExists says it is present")
                }
            }
        }
    }

    func testProbeOnRealSimulatorPathReportsMatchAndSymlinkDiagnostics() throws {
        let seed = try makeRealPathSeed()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        // A symlink inside the real root, pointing at a file outside it:
        // the probe must record it as a non-regular diagnostic and never
        // follow it.
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".isdata")
        try Data(target.utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: seed.root.appendingPathComponent("aliased.isdata"), withDestinationURL: outside)

        let descriptor = open(seed.root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }

        let evidence = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: target)
        XCTAssertEqual(evidence.bundleID, target)
        XCTAssertEqual(evidence.openedDirectories, 1)
        XCTAssertEqual(evidence.matches, 1)
        XCTAssertEqual(evidence.unreadable, 0)
        XCTAssertFalse(evidence.report.isEmpty)
        let match = try XCTUnwrap(evidence.matchesDetail.first)
        XCTAssertEqual(match.file, seed.relativeFile)
        XCTAssertTrue(match.contentMatch)
        let prefixSHA = try XCTUnwrap(match.prefixSHA256)
        XCTAssertEqual(prefixSHA.count, 64)
        XCTAssertEqual(evidence.directoryStats.count, 1)
        XCTAssertTrue(evidence.directoryStats[0].mode.hasPrefix("40"))
        let aliased = try XCTUnwrap(evidence.entriesDetail.first { $0.name == "aliased.isdata" })
        XCTAssertEqual(aliased.stage, "nonRegular")
        XCTAssertEqual(aliased.fileType, "symlink")
        XCTAssertEqual(aliased.target, outside.path)
        XCTAssertEqual(evidence.unreadableStageCounts["nonRegular"], 1)

        // The gate opens for this real-path match...
        guard case .ready(let record) = IconCacheWriteGate.evaluate(evidence, bundleID: target) else {
            return XCTFail("Gate should be ready for the real-path match")
        }
        XCTAssertEqual(record, seed.record)
        XCTAssertEqual(record.bundleID, target)
        XCTAssertEqual(record.relativePath, seed.relativeFile)
        XCTAssertEqual(record.sha256AtProbe.count, 64)

        // ...and blocks when the same real directory is probed for
        // another bundle ID with no match.
        let noMatch = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: "com.example.other")
        XCTAssertEqual(noMatch.matches, 0)
        guard case .blocked(let reason) = IconCacheWriteGate.evaluate(noMatch, bundleID: target) else {
            return XCTFail("Gate should block evidence without a match")
        }
        XCTAssertEqual(reason, appearanceDiagnosticText("No candidate record matches this app."))
    }

    func testWholeBundleInspectIsEmptyOnSimulatorAndGateBlocks() {
        // GXIconCacheProbe.inspectBundleIdentifier returns an empty array
        // under TARGET_OS_SIMULATOR, so the whole-bundle inspect opens
        // zero directories. That is the exact point where the simulator
        // sandbox stops the device flow: no system cache root is ever
        // opened, there is no verified record, and the gate refuses.
        // The refusal is the expected honest result, not a failure.
        let evidence = DiskIconCacheEvidence.inspect(target)
        XCTAssertEqual(evidence.bundleID, target)
        XCTAssertEqual(evidence.openedDirectories, 0)
        XCTAssertEqual(evidence.matches, 0)
        XCTAssertTrue(evidence.matchesDetail.isEmpty)
        guard case .blocked(let reason) = IconCacheWriteGate.evaluate(evidence, bundleID: target) else {
            return XCTFail("Gate should block empty simulator evidence")
        }
        XCTAssertEqual(reason, appearanceDiagnosticText("No candidate record matches this app."))
        guard case .blocked(let scopeReason) = IconCacheWriteGate.evaluate(evidence, bundleID: "com.tencent.xin") else {
            return XCTFail("Gate should block a non-七猫小说 bundle ID")
        }
        XCTAssertEqual(scopeReason, appearanceDiagnosticText("Only 七猫小说 is in scope for the first write target."))
        guard case .blocked(let iconReason) = IconCacheWriteGate.evaluateIconReplacement() else {
            return XCTFail("Icon replacement must be refused")
        }
        XCTAssertEqual(iconReason, appearanceDiagnosticText("Icon record format not confirmed"))
    }

    func testWritePlanRunsOnRealContainerPathsAndRestores() throws {
        let seed = try makeRealPathSeed()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        // The production backup location: Application Support inside the
        // app's own container, which the simulator sandbox allows.
        let backupDirectory = IconCacheWritePlan.backupDirectory(for: target)
        defer { try? FileManager.default.removeItem(at: backupDirectory) }
        let original = try Data(contentsOf: seed.file)
        var plan = IconCacheWritePlan()
        XCTAssertEqual(plan.state, .idle)
        try plan.backup(cacheRoot: seed.root, backupDirectory: backupDirectory, record: seed.record)
        XCTAssertEqual(plan.state, .backedUp)
        XCTAssertEqual(try Data(contentsOf: IconCacheWritePlan.backupFileURL(in: backupDirectory)), original)
        try plan.write(cacheRoot: seed.root, backupDirectory: backupDirectory, evidence: seed.evidence,
                       currentName: "七猫小说", newName: "七猫小説",
                       bootBefore: BootSession(seconds: 1000, microseconds: 0))
        XCTAssertEqual(plan.state, .written)
        let written = try Data(contentsOf: seed.file)
        XCTAssertNotNil(written.range(of: Data("七猫小説".utf8)))
        XCTAssertNil(written.range(of: Data("七猫小说".utf8)))
        XCTAssertEqual(written.count, seed.record.size)
        try plan.readBack(cacheRoot: seed.root, backupDirectory: backupDirectory)
        XCTAssertEqual(plan.state, .readBackVerified)
        try plan.beginRestartWait()
        XCTAssertEqual(plan.state, .awaitingRestartVerification)
        // No reboot yet: the state must not advance.
        XCTAssertFalse(plan.verifyAfterRestart(newEvidence: seed.evidence, bootChanged: false))
        XCTAssertEqual(plan.state, .awaitingRestartVerification)
        // A reboot alone is not enough: stale evidence (pre-write prefix
        // hash) must not verify.
        XCTAssertFalse(plan.verifyAfterRestart(newEvidence: seed.evidence, bootChanged: true))
        XCTAssertEqual(plan.state, .awaitingRestartVerification)
        // A fresh probe after the write still shows the mutation.
        let descriptor = open(seed.root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }
        let fresh = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: target)
        XCTAssertEqual(fresh.matches, 1)
        XCTAssertTrue(plan.verifyAfterRestart(newEvidence: fresh, bootChanged: true))
        XCTAssertEqual(plan.state, .verifiedAfterRestart)
        // The restore path works from the backup in the app's container,
        // and the backup file is kept afterwards.
        try plan.restore(cacheRoot: seed.root, backupDirectory: backupDirectory)
        XCTAssertEqual(plan.state, .restored)
        XCTAssertEqual(try Data(contentsOf: seed.file), original)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: IconCacheWritePlan.backupFileURL(in: backupDirectory).path))
    }

    func testWriteAndRestoreRefuseWithoutBackup() throws {
        let seed = try makeRealPathSeed()
        defer { try? FileManager.default.removeItem(at: seed.root) }
        let backupDirectory = seed.root.appendingPathComponent("backup")
        var plan = IconCacheWritePlan()
        do {
            try plan.write(cacheRoot: seed.root, backupDirectory: backupDirectory, evidence: seed.evidence,
                           currentName: "七猫小说", newName: "七猫小説", bootBefore: nil)
            XCTFail("Write should refuse a plan with no backup")
        } catch let error as IconCacheWriteError {
            XCTAssertEqual(error, .notBackedUp)
        }
        XCTAssertEqual(plan.state, .idle)
        do {
            try plan.restore(cacheRoot: seed.root, backupDirectory: backupDirectory)
            XCTFail("Restore should refuse a plan that never backed up")
        } catch let error as IconCacheWriteError {
            XCTAssertEqual(error, .invalidState)
        }
        XCTAssertEqual(plan.state, .idle)
    }

    /// Seeds one matched cache file under the app's REAL caches
    /// directory: <caches>/IconCacheSimulatorProbe-<uuid>/<uuid>/record.isdata.
    /// The inner directory name is a UUID so probe v2 recurses into it,
    /// exactly as it does for a cache generation directory. The file
    /// content uses "/" separators: the probe only reports scoped
    /// literals, and "-" is an identifier byte, so a dash-joined token
    /// such as "header-com.yueyou.cyreader-..." would not match.
    private func makeRealPathSeed() throws -> (root: URL, file: URL, relativeFile: String,
                                              record: VerifiedIconCacheRecord,
                                              evidence: DiskIconCacheEvidence) {
        let files = FileManager.default
        let caches = try XCTUnwrap(files.urls(for: .cachesDirectory, in: .userDomainMask).first)
        let root = caches.appendingPathComponent("IconCacheSimulatorProbe-" + UUID().uuidString, isDirectory: true)
        let childName = UUID().uuidString
        let child = root.appendingPathComponent(childName, isDirectory: true)
        try files.createDirectory(at: child, withIntermediateDirectories: true)
        var content = Data()
        content.append(Data("header/".utf8))
        content.append(Data(target.utf8))
        content.append(Data("/".utf8))
        content.append(Data("七猫小说".utf8))
        content.append(Data("/tail".utf8))
        let file = child.appendingPathComponent("record.isdata")
        try content.write(to: file)
        let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw POSIXError(.EACCES) }
        defer { close(descriptor) }
        let evidence = DiskIconCacheEvidence.inspectDirectory(descriptor, bundleID: target)
        XCTAssertEqual(evidence.matches, 1)
        let record = try XCTUnwrap(VerifiedIconCacheRecord.fromEvidence(evidence, bundleID: target))
        return (root, file, childName + "/record.isdata", record, evidence)
    }
}
