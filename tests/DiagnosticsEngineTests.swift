// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

/// DiagnosticsEngine + VersionSentinel ranges + RestoreEngine step
/// names (Stage 6, ADR-2-09). All inputs are value snapshots built
/// in the test — no device, no file I/O. Assertions are structural
/// (finding code, category, severity, fix kind) so they do not
/// depend on localized strings.
final class DiagnosticsEngineTests: XCTestCase {
    // MARK: - Fixtures

    private var regionRecord: MGKeyRecord {
        MGDatabase.record(forKey: GestaltKeys.regionCode)!
    }

    private func row(record: MGKeyRecord, original: MGValue? = nil, staged: MGValue? = nil,
                     live: MGValue? = nil, liveReadAt: Date? = Date(),
                     slot: MGSlotProbe? = nil,
                     sentinel: VersionSentinelState = .supported) -> MGMonitorRow {
        MGMonitor.row(for: MGMonitorInput(
            record: record, original: original, staged: staged, live: live,
            liveReadAt: liveReadAt, slot: slot, productType: "iPhone18,4",
            iosVersion: "27.0.1", sentinel: sentinel))
    }

    private func device(build: String? = "23A344", region: String? = "LL",
                        native: Bool = false) -> DiagnosticsDevice {
        DiagnosticsDevice(productType: "iPhone18,4", osBuild: build, regionCode: region,
                          isNativeAppleIntelligence: native)
    }

    private func input(device deviceValue: DiagnosticsDevice? = nil,
                       mgReadState: MGReadState = .live(values: [:], readAt: Date()),
                       snapshotValues: [String: MGValue] = [:],
                       workingValues: [String: MGValue] = [:],
                       monitorRows: [MGMonitorRow] = [],
                       monitorSentinel: VersionSentinelState = .supported,
                       backups: [BackupRecord] = [],
                       backupVerifications: [BackupVerification] = [],
                       restoreReports: [RestoreEngine.Report] = [],
                       fingerprintComparison: FingerprintComparison? = nil,
                       events: [OperationEvent] = [],
                       pendingRestartFeatureIDs: Set<String> = []) -> DiagnosticsInput {
        // The engine derives the sentinel from device.osBuild
        // (DiagnosticsInput has no monitorSentinel field), so the
        // parameter only selects the build the device reports. When
        // the caller gives no device, or a device with no build, the
        // sentinel's build becomes the reported build; a device that
        // already reports a build is left alone.
        let sentinelBuild: String? = {
            switch monitorSentinel {
            case .blocked(let build), .unknownBuild(let build): return build
            case .supported: return nil
            }
        }()
        let device: DiagnosticsDevice? = {
            guard let sentinelBuild else { return deviceValue }
            if let deviceValue, deviceValue.osBuild != nil { return deviceValue }
            return DiagnosticsDevice(
                productType: deviceValue?.productType,
                modelNumber: deviceValue?.modelNumber,
                osVersion: deviceValue?.osVersion,
                osBuild: sentinelBuild,
                regionCode: deviceValue?.regionCode,
                isNativeAppleIntelligence: deviceValue?.isNativeAppleIntelligence)
        }()
        return DiagnosticsInput(
            device: device, mgReadState: mgReadState,
            snapshotValues: snapshotValues, workingValues: workingValues,
            monitorRows: monitorRows,
            backups: backups, backupVerifications: backupVerifications,
            restoreReports: restoreReports, fingerprintComparison: fingerprintComparison,
            events: events, pendingRestartFeatureIDs: pendingRestartFeatureIDs)
    }

    private func finding(_ report: DiagnosticsReport, _ code: String) -> DiagnosticsFinding? {
        report.findings.first { $0.code == code }
    }

    private func backupRecord(sha256: String? = "deadbeef") -> BackupRecord {
        BackupRecord(id: UUID(), date: Date(), reason: "Test", source: .device,
                     deviceID: "install-1", byteCount: 100, sha256: sha256, provenance: .unknown)
    }

    private var aiKeys: [(id: String, key: String, onValue: MGValue)] {
        ChinaUnlock.aiCapabilities.compactMap { capability in
            guard let key = capability.keys.first,
                  let onValue = capability.values[key].flatMap(MGValue.fromPlistValue) else { return nil }
            return (capability.id, key, onValue)
        }
    }

    private func offValue(for onValue: MGValue) -> MGValue {
        switch onValue {
        case .bool: return .bool(false)
        case .int: return .int(0)
        case .string: return .string("")
        case .data: return .data(Data())
        case .array: return .array([])
        case .dictionary: return .dictionary([:])
        }
    }

    private func aiRecord(id: String, key: String, onValue: MGValue) -> MGKeyRecord {
        let type: MGValueType
        switch onValue {
        case .bool: type = .bool
        case .int: type = .int
        case .string: type = .string
        case .data: type = .data
        case .array: type = .array
        case .dictionary: type = .dictionary
        }
        return MGKeyRecord(keyID: id, readableName: id, obfuscatedName: key,
                           dataType: type, defaultValue: nil, deviceScope: .all)
    }

    // MARK: - Sentinel

    func testSentinelBlockedBuildProducesErrorFinding() {
        let report = DiagnosticsEngine.report(input(
            device: device(build: "24C5049d"),
            monitorSentinel: .blocked(build: "24C5049d")))
        let found = finding(report, "sentinel-blocked")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .error)
        XCTAssertEqual(found?.category, .device)
        if case .unsupported = found?.fix { } else {
            XCTFail("A blocked build must suggest the unsupported fix, got \(String(describing: found?.fix))")
        }
    }

    func testSentinelSupportedBuildProducesNoFinding() {
        let report = DiagnosticsEngine.report(input(
            device: device(build: "23A344"), monitorSentinel: .supported))
        XCTAssertNil(finding(report, "sentinel-blocked"))
        XCTAssertNil(finding(report, "sentinel-unknown-build"))
    }

    func testSentinelUnknownBuildProducesWarningFinding() {
        let report = DiagnosticsEngine.report(input(
            device: device(build: nil), monitorSentinel: .unknownBuild(build: "abc")))
        let found = finding(report, "sentinel-unknown-build")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .warning)
    }

    func testSentinelBlockReasons() {
        XCTAssertEqual(VersionSentinel.blockReason(forBuild: "24C5049d"), .atOrPastThreshold)
        XCTAssertEqual(VersionSentinel.blockReason(forBuild: "25A100a"), .newerTrainUnreviewed)
        XCTAssertEqual(VersionSentinel.blockReason(forBuild: "24D1000a"), .newerTrainUnreviewed)
        XCTAssertNil(VersionSentinel.blockReason(forBuild: "23A344"))
        XCTAssertNil(VersionSentinel.blockReason(forBuild: nil))
    }

    func testSupportedRangeDescriptionNamesThreshold() {
        let blocked = VersionSentinel.supportedRangeDescription(for: .blocked(build: "24C5049d"))
        XCTAssertTrue(blocked.contains("24C5049d"))
        XCTAssertTrue(blocked.contains("27.3 beta 1"))
        let newer = VersionSentinel.supportedRangeDescription(for: .blocked(build: "25A100a"))
        XCTAssertTrue(newer.contains("newer train"))
        let supported = VersionSentinel.supportedRangeDescription(for: .supported)
        XCTAssertTrue(supported.contains("27.3 beta 1"))
    }

    // MARK: - Read state

    func testNotReadYetProducesInfoFinding() {
        let report = DiagnosticsEngine.report(input(mgReadState: .notReadYet))
        let found = finding(report, "device-never-read")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .info)
        XCTAssertEqual(found?.category, .device)
        if case .autoFixable = found?.fix { } else {
            XCTFail("Not-read-yet must be auto-fixable, got \(String(describing: found?.fix))")
        }
    }

    func testLiveReadProducesNoDeviceFinding() {
        let report = DiagnosticsEngine.report(input())
        XCTAssertNil(finding(report, "device-never-read"))
    }

    // MARK: - AI chain (§5.2)

    func testAINotStagedWhenLiveShowsOff() {
        XCTAssertFalse(aiKeys.isEmpty, "The AI capability list must not be empty")
        let rows = aiKeys.map { key in
            row(record: aiRecord(id: key.id, key: key.key, onValue: key.onValue),
                live: offValue(for: key.onValue))
        }
        let report = DiagnosticsEngine.report(input(
            device: device(region: "LL"), workingValues: [:], monitorRows: rows))
        let found = finding(report, "ai-not-staged")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .warning)
    }

    func testAILiveMismatchNeedsColdRestart() {
        guard let first = aiKeys.first else {
            XCTFail("The AI capability list must not be empty"); return
        }
        let rows = [row(record: aiRecord(id: first.id, key: first.key, onValue: first.onValue),
                        live: offValue(for: first.onValue))]
        let report = DiagnosticsEngine.report(input(
            device: device(region: "LL"), workingValues: [first.key: first.onValue], monitorRows: rows))
        let found = finding(report, "ai-live-mismatch")
        XCTAssertNotNil(found)
        if case .needsColdRestart = found?.fix { } else {
            XCTFail("A staged-but-not-live AI value must need a cold restart, got \(String(describing: found?.fix))")
        }
    }

    func testAIWriteFailedEvent() {
        guard let first = aiKeys.first else {
            XCTFail("The AI capability list must not be empty"); return
        }
        let event = OperationEvent(kind: .writeFailed, key: first.key, detail: "Write did not verify")
        let report = DiagnosticsEngine.report(input(device: device(region: "LL"), events: [event]))
        let found = finding(report, "ai-write-failed")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .error)
        XCTAssertEqual(found?.category, .mgWrite)
    }

    func testAIRestartPending() {
        let report = DiagnosticsEngine.report(input(
            device: device(region: "LL"),
            pendingRestartFeatureIDs: [ChinaUnlock.aiCapabilityIDs[0]]))
        XCTAssertNotNil(finding(report, "ai-restart-pending"))
    }

    func testAIRegionDependency() {
        guard let first = aiKeys.first else {
            XCTFail("The AI capability list must not be empty"); return
        }
        let report = DiagnosticsEngine.report(input(
            device: device(region: "CH"), workingValues: [first.key: first.onValue]))
        XCTAssertNotNil(finding(report, "ai-region-dependency"))
        // Native hardware does not depend on the region code.
        let native = DiagnosticsEngine.report(input(
            device: device(region: "CH", native: true),
            workingValues: [first.key: first.onValue]))
        XCTAssertNil(finding(native, "ai-region-dependency"))
    }

    // MARK: - Monitor differences and slots

    func testMonitorDifferences() {
        let differing = row(record: regionRecord, original: .string("CH"),
                            staged: .string("LL"), live: .string("CH"))
        let report = DiagnosticsEngine.report(input(monitorRows: [differing]))
        let found = finding(report, "monitor-differences")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .warning)
        XCTAssertFalse(found?.evidence.isEmpty ?? true)
    }

    func testNoMonitorDifferencesWhenAgree() {
        let agreeing = row(record: regionRecord, original: .string("LL"),
                           staged: .string("LL"), live: .string("LL"))
        let report = DiagnosticsEngine.report(input(monitorRows: [agreeing]))
        XCTAssertNil(finding(report, "monitor-differences"))
    }

    func testSlotBaselineDisagreement() {
        let slot = MGSlotProbe(slotNumber: 178, originalByte: false, stagedByte: false,
                               liveAnswer: true, nativeBaseline: false)
        let disagreeing = row(record: regionRecord, original: .bool(false),
                              staged: .bool(false), live: .bool(true), slot: slot)
        let report = DiagnosticsEngine.report(input(monitorRows: [disagreeing]))
        XCTAssertNotNil(finding(report, "slot-baseline-disagreement"))
        // An unknown baseline is not a disagreement.
        let unknown = MGSlotProbe(slotNumber: 178, originalByte: false, stagedByte: false,
                                  liveAnswer: true, nativeBaseline: nil)
        let unknownRow = row(record: regionRecord, original: .bool(false),
                             staged: .bool(false), live: .bool(true), slot: unknown)
        let unknownReport = DiagnosticsEngine.report(input(monitorRows: [unknownRow]))
        XCTAssertNil(finding(unknownReport, "slot-baseline-disagreement"))
    }

    // MARK: - Backups

    func testNoBackups() {
        let report = DiagnosticsEngine.report(input(backups: []))
        let found = finding(report, "backup-none")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .info)
        XCTAssertEqual(found?.category, .backup)
    }

    func testFailedBackupVerification() {
        let record = backupRecord()
        let verification = BackupVerification(record: record, status: .failed(reason: "Digest mismatch"),
                                              layoutMatchesCurrent: nil)
        let report = DiagnosticsEngine.report(input(
            backups: [record], backupVerifications: [verification]))
        let found = finding(report, "backup-failed")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .error)
        if case .needsRebackup = found?.fix { } else {
            XCTFail("A failed backup must need a rebackup, got \(String(describing: found?.fix))")
        }
    }

    func testLegacyOnlyBackups() {
        let record = backupRecord(sha256: nil)
        let verification = BackupVerification(record: record, status: .legacyNoDigest,
                                              layoutMatchesCurrent: nil)
        let report = DiagnosticsEngine.report(input(
            backups: [record], backupVerifications: [verification]))
        let found = finding(report, "backup-legacy-only")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .warning)
        if case .needsConfirmation = found?.fix { } else {
            XCTFail("Legacy-only backups must need confirmation, got \(String(describing: found?.fix))")
        }
    }

    func testUnverifiedBackups() {
        let report = DiagnosticsEngine.report(input(backups: [backupRecord()]))
        XCTAssertNotNil(finding(report, "backup-unverified"))
    }

    // MARK: - Restore reports

    private func restoreReport(failedStep: RestoreEngine.Step?) -> RestoreEngine.Report {
        let record = backupRecord()
        let outcomes = RestoreEngine.Step.allCases.map { step in
            RestoreEngine.StepOutcome(step: step, passed: step != failedStep,
                                      detail: step == failedStep ? "Step failed" : "Step passed")
        }
        return RestoreEngine.Report(
            plan: RestoreEngine.Plan(record: record, allowLegacyNoDigest: false),
            outcomes: outcomes, preWriteBackup: nil)
    }

    func testFailedRestoreReport() {
        let report = DiagnosticsEngine.report(input(restoreReports: [restoreReport(failedStep: .execute)]))
        let found = finding(report, "restore-failed")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .error)
        XCTAssertEqual(found?.category, .restore)
        if case .cannotConfirm = found?.fix { } else {
            XCTFail("A failed execute step must be unconfirmable, got \(String(describing: found?.fix))")
        }
    }

    func testFailedRestoreIntegrityStepNeedsRebackup() {
        let report = DiagnosticsEngine.report(input(restoreReports: [restoreReport(failedStep: .verifyIntegrity)]))
        let found = finding(report, "restore-failed")
        if case .needsRebackup = found?.fix { } else {
            XCTFail("A failed integrity step must need a rebackup, got \(String(describing: found?.fix))")
        }
    }

    func testSuccessfulRestoreReportProducesNoFinding() {
        let report = DiagnosticsEngine.report(input(restoreReports: [restoreReport(failedStep: nil)]))
        XCTAssertNil(finding(report, "restore-failed"))
    }

    // MARK: - Fingerprint

    func testFingerprintChanged() {
        let change = FingerprintChange(field: "osBuild", displayName: "OS Build",
                                       old: "23A344", new: "24C5049d",
                                       invalidatesSupportScope: false)
        let comparison = FingerprintComparison(changes: [change], differentDevice: false,
                                               invalidatesSupportScope: false)
        let report = DiagnosticsEngine.report(input(fingerprintComparison: comparison))
        let found = finding(report, "fingerprint-changed")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .warning)
    }

    func testFingerprintDifferentDevice() {
        let comparison = FingerprintComparison(changes: [], differentDevice: true,
                                               invalidatesSupportScope: true)
        let report = DiagnosticsEngine.report(input(fingerprintComparison: comparison))
        let found = finding(report, "fingerprint-different-device")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .error)
    }

    // MARK: - Events

    func testFailedEventsProduceFindings() {
        let events = [
            OperationEvent(kind: .writeFailed, detail: "Write did not verify"),
            OperationEvent(kind: .readFailed, detail: "Read failed"),
            OperationEvent(kind: .guardNativeConflict, detail: "Native slot must stay off"),
        ]
        let report = DiagnosticsEngine.report(input(events: events))
        XCTAssertEqual(report.findings.filter { $0.code.hasPrefix("event-") }.count, 3)
        XCTAssertNotNil(finding(report, "event-\(OperationEventKind.writeFailed.rawValue)"))
        XCTAssertNotNil(finding(report, "event-\(OperationEventKind.readFailed.rawValue)"))
    }

    func testSuccessEventsProduceNoFindings() {
        let events = [OperationEvent(kind: .backupCreated, detail: "Backup saved")]
        let report = DiagnosticsEngine.report(input(events: events))
        XCTAssertTrue(report.findings.filter { $0.code.hasPrefix("event-") }.isEmpty)
    }

    // MARK: - Staleness

    func testStaleMonitor() {
        let stale = row(record: regionRecord, original: .string("LL"), staged: .string("LL"),
                        live: .string("LL"), liveReadAt: Date(timeIntervalSinceNow: -600))
        let report = DiagnosticsEngine.report(input(monitorRows: [stale]))
        let found = finding(report, "monitor-stale")
        XCTAssertNotNil(found)
        XCTAssertEqual(found?.severity, .info)
    }

    // MARK: - Redaction and export

    func testEvidenceIsRedacted() {
        // The dashed UDID format the redactor masks
        // ("00008150-000C0C5A14D2401C": 8 hex, dash, 16 hex).
        let udid = "AAAAAAAA-1111111111111111"
        let event = OperationEvent(kind: .writeFailed,
                                   detail: "Write failed for device \(udid)")
        let report = DiagnosticsEngine.report(input(events: [event]))
        let found = finding(report, "event-\(OperationEventKind.writeFailed.rawValue)")
        XCTAssertNotNil(found)
        XCTAssertFalse(found?.evidence.joined(separator: " ").contains(udid) ?? true,
                       "Evidence must not contain the UDID")
    }

    func testExportJSONRoundTrips() throws {
        let report = DiagnosticsEngine.report(input(
            device: device(build: "24C5049d"), monitorSentinel: .blocked(build: "24C5049d")))
        let data = try report.exportJSON()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DiagnosticsReportExport.self, from: data)
        XCTAssertEqual(decoded.findings.count, report.findings.count)
        XCTAssertEqual(decoded.findings.map(\.code), report.findings.map(\.code))
        // The export carries no device identity: no identity hash
        // and no UDID-shaped token survives the JSON.
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("re6Zb+zwFKJNlkQTUeT+/w"))
        XCTAssertFalse(json.contains("VasUgeSzVyHdB27g2XpN0g"))
        XCTAssertFalse(json.contains("TF31PAB6aO8KAbPyNKSxKA"))
    }

    func testExportTextContainsTitles() {
        let report = DiagnosticsEngine.report(input(
            device: device(build: "24C5049d"), monitorSentinel: .blocked(build: "24C5049d")))
        let text = report.exportText()
        XCTAssertTrue(text.contains("Diagnostics Report"))
        XCTAssertTrue(text.contains("sentinel-blocked"))
    }

    func testSummaryCounts() {
        let report = DiagnosticsEngine.report(input(
            device: device(build: "24C5049d"), monitorSentinel: .blocked(build: "24C5049d"),
            backups: []))
        XCTAssertTrue(report.summary.contains("1 error"))
        XCTAssertTrue(report.summary.contains("1 note"))
        XCTAssertEqual(report.findings.count, 2)
    }

    // MARK: - Fix kinds and step names

    func testFixKindLabelsAreDistinctAndNonEmpty() {
        let kinds: [FixSuggestion] = [
            .autoFixable(action: "Do it"), .needsConfirmation(action: "Confirm it"), .needsRebackup(action: "Back up first"),
            .needsColdRestart(action: "Restart"), .unsupported(reason: "Not supported"), .cannotConfirm(reason: "Cannot confirm"),
        ]
        let labels = kinds.map(\.kindLabel)
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty })
        XCTAssertEqual(Set(labels).count, kinds.count, "Each fix kind needs its own label")
        XCTAssertTrue(kinds.allSatisfy { !$0.actionText.isEmpty })
    }

    func testRestoreStepDisplayNamesAreNonEmpty() {
        for step in RestoreEngine.Step.allCases {
            XCTAssertFalse(step.displayName.isEmpty, "\(step.rawValue) needs a display name")
        }
        XCTAssertEqual(Set(RestoreEngine.Step.allCases.map(\.displayName)).count,
                       RestoreEngine.Step.allCases.count, "Step display names must be distinct")
    }
}
