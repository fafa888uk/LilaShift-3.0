// SPDX-License-Identifier: GPL-3.0-only
// Tests for the Stage 5 backup/diff/restore pipeline: SHA-256
// convergence, `.legacyNoDigest`, the SecurityEngine allowlist and
// pre-write backup rule, the pre-write orchestration (no double
// backup), the eight-step RestoreEngine pipeline, and the hashed
// device fingerprint (audit R-4). No device or signing is needed.
import Foundation
import XCTest
@testable import GestaltX

final class BackupRestorePipelineTests: XCTestCase {
    // MARK: - Helpers

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func store(in directory: URL) -> GestaltFileStore {
        let device = directory.appendingPathComponent("device.plist")
        let backups = directory.appendingPathComponent("backups")
        return GestaltFileStore(deviceURL: device, backupDirectory: backups,
                                deviceID: "install-1", acquire: { 1 }, release: { _ in })
    }

    private func backupFile(in directory: URL, document: GestaltDocument, digest: Bool) throws -> BackupRecord {
        let data = try document.encoded()
        let record = BackupRecord(id: UUID(), date: Date(), reason: "Test backup", source: .device,
                                  deviceID: "install-1", byteCount: data.count,
                                  sha256: digest ? BackupEngine.sha256Hex(of: data) : nil,
                                  provenance: .preModification)
        try data.write(to: directory.appendingPathComponent(record.filename))
        return record
    }

    // MARK: - SHA-256 convergence (ADR-2-08)

    func testSingleSHA256Implementation() {
        // The known SHA-256 of "abc".
        let expected = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        let data = Data("abc".utf8)
        XCTAssertEqual(BackupEngine.sha256Hex(of: data), expected)
        XCTAssertEqual(GestaltFileStore.sha256Hex(of: data), expected,
                       "GestaltFileStore delegates to BackupEngine")
        XCTAssertEqual(HistoryJournal.sha256Hex(of: data), expected,
                       "HistoryJournal delegates to BackupEngine")
        XCTAssertEqual(CustomizationFiles.digest(data), expected,
                       "CustomizationFiles delegates to BackupEngine")
    }

    // MARK: - Legacy backups are never "verified" (ADR-2-08 R-6)

    func testLegacyBackupReportsLegacyNoDigest() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try CoreModuleFixtures.document()
        let legacy = try backupFile(in: directory, document: document, digest: false)
        let verified = try backupFile(in: directory, document: document, digest: true)
        let results = RestoreIntelligence.verifyBackups([legacy, verified], against: document, directory: directory)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first { $0.record.id == legacy.id }?.status, .legacyNoDigest,
                       "A backup with no digest is never shown as verified")
        XCTAssertEqual(results.first { $0.record.id == verified.id }?.status, .verified)
        XCTAssertEqual(results.first { $0.record.id == verified.id }?.layoutMatchesCurrent, true)
    }

    func testTamperedBackupFailsEvenWithDigest() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // "alpha" -> "omega" keeps the encoded size identical, so
        // only the digest can catch the replacement (mirrors
        // BackupIntegrityTests).
        let document = try CoreModuleFixtures.document(extra: ["setting": "alpha"])
        let record = try backupFile(in: directory, document: document, digest: true)
        var tampered = try CoreModuleFixtures.document(extra: ["setting": "alpha"])
        tampered.set("omega", for: "setting")
        let tamperedData = try tampered.encoded()
        XCTAssertEqual(tamperedData.count, record.byteCount,
                       "The fixture replacement must be the same size so only the digest can catch it")
        try tamperedData.write(to: directory.appendingPathComponent(record.filename))
        let results = RestoreIntelligence.verifyBackups([record], against: document, directory: directory)
        if case .failed = results.first?.status { /* Expected. */ }
        else { XCTFail("A tampered backup with a recorded digest must fail verification") }
    }

    func testMissingBackupReportsNotFound() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try CoreModuleFixtures.document()
        let record = BackupRecord(id: UUID(), date: Date(), reason: "Gone", source: .device,
                                  deviceID: "install-1", byteCount: 1, sha256: "00", provenance: .unknown)
        let results = RestoreIntelligence.verifyBackups([record], against: document, directory: directory)
        XCTAssertEqual(results.first?.status, .notFound)
    }

    func testLegacyChecklistIsUnknownNotFailed() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = try CoreModuleFixtures.document()
        let legacy = try backupFile(in: directory, document: document, digest: false)
        let verifications = RestoreIntelligence.verifyBackups([legacy], against: document, directory: directory)
        let checklist = RestorePreviewChecklistBuilder.buildForBackup(
            record: legacy, verifications: verifications, deviceID: "install-1",
            deviceDisplayName: "Test iPhone", current: document, layout: nil)
        XCTAssertNil(checklist.fileIntegrityOK,
                     "A legacy backup's integrity is unknown, not failed — the two-step confirmation is its gate")
        XCTAssertTrue(checklist.noCheckFailed,
                      "Unknown integrity does not block the way a failed check does")
        XCTAssert(checklist.fileIntegrity.contains("Legacy"),
                  "The checklist says plainly that integrity was not verified")
    }

    // MARK: - SecurityEngine allowlist (§3.4)

    func testAllowlistCoversStagedKeysOnly() {
        let allowlist = SecurityEngine.writeAllowlist
        XCTAssertTrue(Capability.all.flatMap(\.keys).allSatisfy { allowlist.contains($0) },
                      "Every capability key is allowlisted")
        for key in [GestaltKeys.regionCode, GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo,
                    GestaltKeys.modelNumber, GestaltKeys.artwork,
                    SecurityEngine.modelNameKey1, SecurityEngine.modelNameKey2] {
            XCTAssertTrue(allowlist.contains(key), "Special key \(key) is allowlisted")
        }
        for key in GestaltKeys.hardwareIdentity where key != GestaltKeys.modelNumber {
            XCTAssertFalse(allowlist.contains(key),
                           "Hardware-identity key \(key) is never allowlisted for the apply path")
        }
        XCTAssertFalse(allowlist.contains("UniqueDeviceID"), "The UDID is never writable through the apply path")
        XCTAssertFalse(allowlist.contains("SerialNumber"), "The serial number is never writable through the apply path")
    }

    func testAuthorizeWriteAllowsStagedKeys() throws {
        let key = try XCTUnwrap(Capability.all.flatMap(\.keys).first, "At least one capability key exists")
        let before = try CoreModuleFixtures.document()
        var after = before
        after.set(NSNumber(value: true), for: key)
        XCTAssertNoThrow(try SecurityEngine.authorizeWrite(from: before, to: after),
                         "Changing an allowlisted capability key is authorized")
    }

    func testAuthorizeWriteRejectsUnstagedKeys() throws {
        let before = try CoreModuleFixtures.document()
        var after = before
        after.set("ATTACKER", for: "SomeUnstagedKey")
        XCTAssertThrowsError(try SecurityEngine.authorizeWrite(from: before, to: after),
                             "Changing a key no feature stages is refused")
        var identity = before
        identity.set("00008150-000C0C5A14D2401C", for: "UniqueDeviceID")
        XCTAssertThrowsError(try SecurityEngine.authorizeWrite(from: before, to: identity),
                             "Writing a UDID through the apply path is refused")
    }

    func testAuthorizeWriteRejectsUnknownArtworkKeys() throws {
        let before = try CoreModuleFixtures.document()
        var after = before
        XCTAssertTrue(after.setArtwork("X", for: "ArtworkDeviceProductDescription"),
                      "The artwork container is editable in the fixture")
        XCTAssertNoThrow(try SecurityEngine.authorizeWrite(from: before, to: after),
                         "The known artwork key is authorized")
        var bad = before
        XCTAssertTrue(bad.setArtwork("X", for: "UnknownArtworkKey"))
        XCTAssertThrowsError(try SecurityEngine.authorizeWrite(from: before, to: bad),
                             "An unknown nested artwork key is refused")
    }

    // MARK: - Pre-write backup rule (§3.4)

    func testRequirePreWriteBackup() throws {
        let data = Data("device-bytes".utf8)
        let digest = BackupEngine.sha256Hex(of: data)
        let record = BackupRecord(id: UUID(), date: Date(), reason: "Before applying", source: .device,
                                  deviceID: "install-1", byteCount: data.count, sha256: digest,
                                  provenance: .preModification)
        XCTAssertNoThrow(try SecurityEngine.requirePreWriteBackup(nil, covering: data),
                         "No record means commit creates the backup itself")
        XCTAssertNoThrow(try SecurityEngine.requirePreWriteBackup(record, covering: data),
                         "A record covering the current bytes is accepted")
        let stale = BackupRecord(id: UUID(), date: Date(), reason: "Before applying", source: .device,
                                 deviceID: "install-1", byteCount: 1, sha256: digest,
                                 provenance: .preModification)
        XCTAssertThrowsError(try SecurityEngine.requirePreWriteBackup(stale, covering: data),
                             "A record with the wrong byte count cannot prove coverage")
        let noDigest = BackupRecord(id: UUID(), date: Date(), reason: "Before applying", source: .device,
                                    deviceID: "install-1", byteCount: data.count, sha256: nil,
                                    provenance: .preModification)
        XCTAssertThrowsError(try SecurityEngine.requirePreWriteBackup(noDigest, covering: data),
                             "A record with no digest cannot prove coverage")
        let wrongDigest = BackupRecord(id: UUID(), date: Date(), reason: "Before applying", source: .device,
                                       deviceID: "install-1", byteCount: data.count,
                                       sha256: String(repeating: "0", count: 64),
                                       provenance: .preModification)
        XCTAssertThrowsError(try SecurityEngine.requirePreWriteBackup(wrongDigest, covering: data),
                             "A record with the wrong digest cannot prove coverage")
    }

    // MARK: - Pre-write orchestration: no double backup

    func testCommitWithPreWriteBackupWritesOneBackup() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store(in: directory)
        let document = try CoreModuleFixtures.document()
        let snapshot = DocumentSnapshot(data: try document.encoded(), document: document,
                                        source: .local, name: "test")
        var edited = document
        edited.set("LL", for: GestaltKeys.regionCode)
        let preWrite = try await BackupEngine.createPreWriteBackup(store: store, snapshot: snapshot, reason: "Before applying")
        XCTAssertEqual(preWrite.reason, "Before editing",
                       "A locally opened file always records 'Before editing'")
        XCTAssertEqual(preWrite.provenance, .importedHistory)
        _ = try await store.commit(edited, expected: snapshot, preWriteBackup: preWrite)
        XCTAssertEqual(try await store.backups().count, 1,
                       "One pre-write backup exists — commit did not write a second one")

        // The same edit without an orchestrated record still gets
        // exactly one backup, created inside commit.
        let snapshot2 = DocumentSnapshot(data: try edited.encoded(), document: edited,
                                         source: .local, name: "test")
        var edited2 = edited
        edited2.set("US", for: GestaltKeys.regionCode)
        _ = try await store.commit(edited2, expected: snapshot2)
        XCTAssertEqual(try await store.backups().count, 2,
                       "Commit without a supplied record creates the backup itself")
    }

    func testCommitRejectsStalePreWriteBackup() async throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store(in: directory)
        let document = try CoreModuleFixtures.document()
        let snapshot = DocumentSnapshot(data: try document.encoded(), document: document,
                                        source: .local, name: "test")
        let preWrite = try await BackupEngine.createPreWriteBackup(store: store, snapshot: snapshot, reason: "Before applying")
        // The pre-write state moved on after the backup was taken.
        let movedOn = try CoreModuleFixtures.document(extra: ["MovedOn": "yes"])
        let snapshot2 = DocumentSnapshot(data: try movedOn.encoded(), document: movedOn,
                                         source: .local, name: "test")
        var edited = movedOn
        edited.set("LL", for: GestaltKeys.regionCode)
        do {
            _ = try await store.commit(edited, expected: snapshot2, preWriteBackup: preWrite)
            XCTFail("A stale pre-write backup must refuse the write")
        } catch {
            XCTAssertTrue(error is GestaltFailure)
        }
    }

    // MARK: - RestoreEngine eight-step pipeline (DATA_MODELS §5)

    private func engineFixture() throws -> (directory: URL, document: GestaltDocument, snapshot: DocumentSnapshot) {
        let directory = try tempDirectory()
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        return (directory, document, snapshot)
    }

    private func engineReport(for record: BackupRecord, snapshot: DocumentSnapshot,
                              directory: URL, allowLegacy: Bool = false,
                              installationDeviceID: String? = "install-1",
                              currentBuild: String? = "24C5037i",
                              execute: ((BackupRecord, BackupRecord) async throws -> GestaltDocument)? = nil,
                              readBack: (() async throws -> GestaltDocument)? = nil) async -> RestoreEngine.Report {
        let restored = snapshot.document
        return await RestoreEngine.run(
            plan: RestoreEngine.Plan(record: record, allowLegacyNoDigest: allowLegacy),
            snapshot: snapshot, installationDeviceID: installationDeviceID,
            currentBuild: currentBuild, deviceDisplayName: "Test iPhone", directory: directory,
            createPreWriteBackup: { _ in
                BackupRecord(id: UUID(), date: Date(), reason: "Before restoring", source: .device,
                             deviceID: "install-1", byteCount: 0, sha256: "", provenance: .preModification)
            },
            execute: execute ?? { _, _ in restored },
            readBack: readBack ?? { restored })
    }

    func testRestoreEngineHappyPath() async throws {
        let (directory, document, snapshot) = try engineFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try backupFile(in: directory, document: document, digest: true)
        let report = await engineReport(for: record, snapshot: snapshot, directory: directory)
        XCTAssertTrue(report.succeeded, "All eight steps pass on a verified same-device backup")
        XCTAssertEqual(report.outcomes.count, RestoreEngine.Step.allCases.count)
        XCTAssertTrue(report.outcomes.allSatisfy(\.passed))
        XCTAssertNotNil(report.preWriteBackup, "Step 5 created a pre-write backup")
    }

    func testRestoreEngineLegacyNeedsExplicitConfirmation() async throws {
        let (directory, document, snapshot) = try engineFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = try backupFile(in: directory, document: document, digest: false)
        let refused = await engineReport(for: legacy, snapshot: snapshot, directory: directory)
        XCTAssertFalse(refused.succeeded, "A legacy backup without explicit confirmation stops at step 1")
        XCTAssertFalse(refused.outcomes[0].passed)
        XCTAssertEqual(refused.outcomes[0].step, .verifyIntegrity)
        XCTAssert(refused.outcomes.dropFirst().allSatisfy { !$0.passed && $0.detail.hasPrefix("Not run") },
                  "No later step runs after a failed gate")

        let allowed = await engineReport(for: legacy, snapshot: snapshot, directory: directory, allowLegacy: true)
        XCTAssertTrue(allowed.succeeded, "With explicit confirmation the legacy backup restores")
    }

    func testRestoreEngineFailsClosed() async throws {
        let (directory, document, snapshot) = try engineFixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let record = try backupFile(in: directory, document: document, digest: true)

        let wrongDevice = await engineReport(for: record, snapshot: snapshot, directory: directory,
                                             installationDeviceID: "another-install")
        XCTAssertFalse(wrongDevice.succeeded)
        XCTAssertEqual(wrongDevice.outcomes[1].step, .verifyDeviceIdentity)
        XCTAssertFalse(wrongDevice.outcomes[1].passed)

        let noDevice = await engineReport(for: record, snapshot: snapshot, directory: directory,
                                          installationDeviceID: nil)
        XCTAssertFalse(noDevice.succeeded, "No installation ID at all fails the identity gate")

        let blocked = await engineReport(for: record, snapshot: snapshot, directory: directory,
                                         currentBuild: "24C5049d")
        XCTAssertFalse(blocked.succeeded)
        XCTAssertEqual(blocked.outcomes[2].step, .verifyVersionCompatibility)
        XCTAssertFalse(blocked.outcomes[2].passed)

        let unknownBuild = await engineReport(for: record, snapshot: snapshot, directory: directory,
                                              currentBuild: "not-a-build")
        XCTAssertFalse(unknownBuild.succeeded, "An unparseable build fails the version gate")

        let executeFailed = await engineReport(for: record, snapshot: snapshot, directory: directory,
                                               execute: { _, _ in throw GestaltFailure("write failed") })
        XCTAssertFalse(executeFailed.succeeded)
        XCTAssertEqual(executeFailed.outcomes[5].step, .execute)
        XCTAssertFalse(executeFailed.outcomes[5].passed)
        XCTAssertFalse(executeFailed.outcomes[6].passed, "Read-back never runs after a failed execute")

        let changed = try CoreModuleFixtures.document(extra: ["Changed": "yes"])
        let mismatch = await engineReport(for: record, snapshot: snapshot, directory: directory,
                                          readBack: { changed })
        XCTAssertFalse(mismatch.succeeded)
        XCTAssertEqual(mismatch.outcomes[6].step, .readBackVerify)
        XCTAssertFalse(mismatch.outcomes[6].passed)
    }

    // MARK: - Hashed device fingerprint (audit R-4)

    func testFingerprintStoresHashNeverPlaintextUDID() throws {
        let udid = "TEST-UDID-1234567890"
        let document = try CoreModuleFixtures.document(extra: ["UniqueDeviceID": udid])
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let fingerprint = try XCTUnwrap(DeviceFingerprintCapture.capture(profile: profile, snapshot: snapshot))
        XCTAssertEqual(fingerprint.deviceID, BackupEngine.sha256Hex(of: Data(udid.utf8)),
                       "The fingerprint carries the SHA-256 of the UDID, never the UDID")
        XCTAssertNotEqual(fingerprint.deviceID, udid)
        XCTAssertEqual(fingerprint.version, 2, "Version 2 is the first hashed version")

        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeviceFingerprintStore(directory: directory, deviceID: "install-1")
        try store.save(fingerprint)
        let raw = try Data(contentsOf: directory.appendingPathComponent(DeviceFingerprintStore.fileName))
        XCTAssertNil(raw.range(of: Data(udid.utf8)),
                     "The stored fingerprint file contains no plaintext UDID")
        XCTAssertNotNil(raw.range(of: Data(fingerprint.deviceID.utf8)),
                        "The stored file does contain the hash (ownership is proven by hash comparison)")
        XCTAssertEqual(try store.load(), fingerprint, "The hashed fingerprint round-trips")
    }

    func testStaleVersionOneFingerprintIsNotTrusted() throws {
        let directory = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DeviceFingerprintStore(directory: directory, deviceID: "install-1")
        let stale = DeviceFingerprint(version: 1, deviceID: "plaintext-udid",
                                      productType: nil, modelNumber: nil, osVersion: nil, osBuild: nil,
                                      regionCode: nil, salesRegionSuffix: nil, cacheLayoutUUID: nil,
                                      cacheSlotCount: nil, cacheByteCount: nil, esimGreenTea: nil,
                                      esimNotGreenTea: nil, wapiEnabled: nil, audioIntelligenceSlot: nil,
                                      personalTranslatorSlot: nil, isNativeAppleIntelligence: nil,
                                      appGroupAvailable: nil, backupCount: nil, hasTrustedBackup: nil,
                                      recordedAt: Date())
        try store.save(stale)
        XCTAssertNil(try store.load(),
                     "A version-1 fingerprint (plaintext UDID) loads as nothing — it is re-captured, never trusted")
    }
}
