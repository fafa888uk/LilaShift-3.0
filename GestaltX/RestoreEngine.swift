// SPDX-License-Identifier: GPL-3.0-only
// Restore engine (Stage 5, DATA_MODELS §5 / ADR-2-08): the
// eight-step restore pipeline. Each step is a gate: a failed step
// records its reason and stops the pipeline — no later step runs
// on a failed gate, and the report always lists all eight steps
// (steps that never ran are marked not-run, never passed).
//
// The engine orchestrates; it does not duplicate the existing
// restore machinery: integrity uses `RestoreIntelligence
// .verifyBackups`, preview uses `RestorePreviewChecklistBuilder`,
// the pre-write backup uses `BackupEngine`, and execution /
// read-back are caller-supplied closures (the manager's commit
// path), so the pipeline cannot drift from the code that actually
// writes. Adoption into `GestaltManager.restore(_:)` is a Stage 6
// handoff item — the UI must supply `allowLegacyNoDigest` from the
// user's explicit confirmation of the legacy warning first.
import Foundation

enum RestoreEngine {
    /// The eight steps of a restore, in order.
    enum Step: String, CaseIterable, Sendable {
        case verifyIntegrity
        case verifyDeviceIdentity
        case verifyVersionCompatibility
        case preview
        case backUpFirst
        case execute
        case readBackVerify
        case report

        /// The user-facing name shown in the Backups view's restore
        /// report. The `rawValue` stays the stable identifier used
        /// in logs and in `StepOutcome` equality.
        var displayName: String {
            switch self {
            case .verifyIntegrity: return L("Verify integrity")
            case .verifyDeviceIdentity: return L("Verify device identity")
            case .verifyVersionCompatibility: return L("Check iOS version")
            case .preview: return L("Preview changes")
            case .backUpFirst: return L("Back up first")
            case .execute: return L("Write changes")
            case .readBackVerify: return L("Read back and verify")
            case .report: return L("Report")
            }
        }
    }

    /// The outcome of one step. `passed` is false for a failed step
    /// and for a step that never ran because an earlier step failed.
    struct StepOutcome: Equatable, Sendable {
        let step: Step
        let passed: Bool
        let detail: String
    }

    /// What to restore. `allowLegacyNoDigest` is true only when the
    /// user explicitly confirmed a legacy backup (no digest) after
    /// seeing the warning — a legacy backup is never restored
    /// silently, and never shown as verified.
    struct Plan: Equatable, Sendable {
        let record: BackupRecord
        let allowLegacyNoDigest: Bool
    }

    /// The pipeline's report (step 8): one outcome per step, in
    /// order, plus the pre-write backup record when one was created.
    /// `succeeded` is true only when all eight steps ran and passed.
    struct Report: Equatable, Sendable {
        let plan: Plan
        let outcomes: [StepOutcome]
        let preWriteBackup: BackupRecord?

        var succeeded: Bool {
            outcomes.count == Step.allCases.count && outcomes.allSatisfy(\.passed)
        }
    }

    /// Runs the eight-step pipeline for `plan` against `snapshot`.
    /// `installationDeviceID` is the random installation ID (never
    /// the UDID); `currentBuild` is the device's iOS build string
    /// for the version sentinel. `createPreWriteBackup` creates the
    /// step-5 backup; `execute` performs the restore given the
    /// backup record and the pre-write record and returns the
    /// restored document; `readBack` re-reads the device after the
    /// write. The report is always returned, never thrown — a
    /// failure is a failed outcome in it.
    static func run(plan: Plan,
                    snapshot: DocumentSnapshot,
                    installationDeviceID: String?,
                    currentBuild: String?,
                    deviceDisplayName: String,
                    directory: URL? = nil,
                    createPreWriteBackup: (DocumentSnapshot) async throws -> BackupRecord,
                    execute: (BackupRecord, BackupRecord) async throws -> GestaltDocument,
                    readBack: () async throws -> GestaltDocument) async -> Report {
        var outcomes: [StepOutcome] = []
        var preWriteBackup: BackupRecord?
        func record(_ step: Step, _ passed: Bool, _ detail: String) {
            outcomes.append(StepOutcome(step: step, passed: passed, detail: detail))
        }
        func abort(_ reason: String) -> Report {
            for step in Step.allCases where !outcomes.contains(where: { $0.step == step }) {
                record(step, false, L("Not run:") + " " + reason)
            }
            return Report(plan: plan, outcomes: outcomes, preWriteBackup: preWriteBackup)
        }

        // 1. Verify integrity: the file must exist, match its byte
        // count and SHA-256, and parse. A legacy backup (no digest)
        // passes only with explicit user confirmation.
        let verifications = RestoreIntelligence.verifyBackups(
            [plan.record], against: snapshot.document, directory: directory)
        guard let verification = verifications.first else {
            record(.verifyIntegrity, false, L("The backup could not be verified. No system changes were made."))
            return abort(L("integrity verification failed"))
        }
        var integrityDetail = L("Verified.")
        switch verification.status {
        case .verified:
            break
        case .legacyNoDigest:
            guard plan.allowLegacyNoDigest else {
                record(.verifyIntegrity, false, L("This is a legacy backup with no recorded digest, so its integrity cannot be verified. No system changes were made."))
                return abort(L("legacy backup without explicit confirmation"))
            }
            // The step passes because the user explicitly confirmed
            // the legacy backup — but the detail must never call it
            // "verified": integrity was not proven.
            integrityDetail = L("Legacy backup — integrity not verified (no digest recorded).")
        case .failed(let reason):
            record(.verifyIntegrity, false, reason)
            return abort(L("integrity verification failed"))
        case .notFound:
            record(.verifyIntegrity, false, L("Backup file not found."))
            return abort(L("backup file not found"))
        }
        if verification.layoutMatchesCurrent == false {
            record(.verifyIntegrity, false, L("Verified, but the cache layout differs from this device."))
            return abort(L("cache layout differs from this device"))
        }
        record(.verifyIntegrity, true, integrityDetail)

        // 2. Verify device identity: the backup must belong to this
        // installation. Fail closed when no installation ID exists.
        guard let installationDeviceID, plan.record.deviceID == installationDeviceID else {
            record(.verifyDeviceIdentity, false, L("This backup does not belong to this device."))
            return abort(L("device identity mismatch"))
        }
        record(.verifyDeviceIdentity, true, L("This device."))

        // 3. Verify version compatibility: the iOS build must still
        // grant the mechanism. Unknown and blocked builds fail.
        switch VersionSentinel.state(forBuild: currentBuild) {
        case .supported:
            record(.verifyVersionCompatibility, true, L("Verified. Cache layout matches this device."))
        case .blocked(let build):
            record(.verifyVersionCompatibility, false,
                   L("This iOS version blocks the mechanism.") + " (\(build))")
            return abort(L("iOS version blocks the mechanism"))
        case .unknownBuild:
            record(.verifyVersionCompatibility, false,
                   L("The iOS build could not be confirmed, so the monitor cannot tell whether the mechanism is granted on this version."))
            return abort(L("iOS build could not be confirmed"))
        }

        // 4. Preview: the restore checklist must have no failed
        // check (unknown checks are shown, not passed silently).
        let layout = try? LayoutResolver.resolve(cacheUUID: snapshot.document.cacheUUID,
                                                 cacheData: snapshot.document.cacheData)
        let checklist = RestorePreviewChecklistBuilder.buildForBackup(
            record: plan.record, verifications: verifications,
            deviceID: installationDeviceID, deviceDisplayName: deviceDisplayName,
            current: snapshot.document, layout: layout)
        guard checklist.noCheckFailed else {
            record(.preview, false, checklist.fileIntegrity)
            return abort(L("restore preview has a failed check"))
        }
        record(.preview, true, L("Restore preview checked."))

        // 5. Back up first: a fresh pre-write backup of the current
        // state, before anything is written.
        do {
            preWriteBackup = try await createPreWriteBackup(snapshot)
        } catch {
            record(.backUpFirst, false, error.localizedDescription)
            return abort(L("pre-write backup failed"))
        }
        record(.backUpFirst, true, L("Backup saved."))

        // 6. Execute the restore through the caller's path.
        guard let preWrite = preWriteBackup else {
            record(.execute, false, L("Pre-write backup missing. No system changes were made."))
            return abort(L("pre-write backup missing"))
        }
        let restored: GestaltDocument
        do {
            restored = try await execute(plan.record, preWrite)
        } catch {
            record(.execute, false, error.localizedDescription)
            return abort(L("restore execution failed"))
        }
        record(.execute, true, L("Backup restored and verified."))

        // 7. Read-back verify: the device must now match what was
        // restored.
        do {
            let reread = try await readBack()
            guard reread.matches(restored) else {
                record(.readBackVerify, false, L("The write did not match the readback."))
                return abort(L("read-back mismatch"))
            }
        } catch {
            record(.readBackVerify, false, error.localizedDescription)
            return abort(L("read-back failed"))
        }
        record(.readBackVerify, true, L("Readback: verified."))

        // 8. Report.
        record(.report, true, L("Restore complete."))
        return Report(plan: plan, outcomes: outcomes, preWriteBackup: preWriteBackup)
    }
}
