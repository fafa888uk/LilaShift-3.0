// SPDX-License-Identifier: GPL-3.0-only
// Tests for Post-Modification Auto-Acceptance (修改后自动验收):
// reverted-field listing (the known region case), accepted fields,
// file-vs-live distinction, unreadable fields, and no claims
// without a post-restart re-read.
import Foundation
import XCTest
@testable import GestaltX

final class PostModificationAcceptanceTests: XCTestCase {
    /// No post-restart document: every item is not re-read, nothing
    /// is claimed accepted, and no record is a restart-verified
    /// candidate.
    func testNoPostRestartDocumentMeansNotReRead() {
        let records = [regionRecord(), esimGreenTeaRecord()]
        let report = PostModificationAcceptance.accept(records: records, current: nil)
        XCTAssertEqual(report.notReReadCount, 2)
        XCTAssertEqual(report.acceptedCount, 0)
        XCTAssertTrue(report.restartVerifiedCandidateIDs.isEmpty)
        XCTAssertTrue(report.items.allSatisfy { $0.outcome == .notReRead })
    }

    /// Region staged CH → LL and still LL after the restart: accepted.
    func testAcceptedRegionChange() throws {
        let record = regionRecord()
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let report = PostModificationAcceptance.accept(
            records: [record], current: current, liveValues: [record.key: .string("LL")],
            restartEvidence: .verifiedBootChange)
        XCTAssertEqual(report.acceptedCount, 1)
        XCTAssertEqual(report.items.first?.outcome, .accepted)
        XCTAssertEqual(report.restartVerifiedCandidateIDs, [record.id])
    }

    /// The known region case: region staged CH → LL, but the
    /// post-restart file reads CH again — reverted, and the key is
    /// listed in `revertedKeys`.
    func testRevertedRegionChange() throws {
        let record = regionRecord()
        let current = try CoreModuleFixtures.document()
        let report = PostModificationAcceptance.accept(
            records: [record], current: current, restartEvidence: .verifiedBootChange)
        XCTAssertEqual(report.revertedCount, 1)
        XCTAssertEqual(report.items.first?.outcome, .reverted)
        XCTAssertEqual(report.revertedKeys, [GestaltKeys.regionCode])
        XCTAssertTrue(report.restartVerifiedCandidateIDs.isEmpty,
                      "A reverted record is never a restart-verified candidate")
    }

    /// A field that holds a third value — neither the target nor the
    /// original — is reported as changed, not accepted or reverted.
    func testChangedToSomethingElse() throws {
        let record = regionRecord()
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "JP"])
        let report = PostModificationAcceptance.accept(records: [record], current: current)
        XCTAssertEqual(report.changedCount, 1)
        XCTAssertEqual(report.items.first?.outcome, .changed)
    }

    /// The eSIM pair staged and still staged after the restart:
    /// both slots accepted.
    func testESIMPairAccepted() throws {
        let greenTea = esimGreenTeaRecord()
        let notGreenTea = RecordedChange(
            id: UUID(), date: Date(timeIntervalSince1970: 0), deviceID: "test",
            osBuild: "23A344", featureID: "esim", key: DeviceCacheOptions.notGreenTeaKey,
            layer: .cacheData, original: .bool(false), new: .bool(true),
            backupProvenance: .preModification, verified: true)
        let current = try CoreModuleFixtures.document(greenTea: false, notGreenTea: true)
        let report = PostModificationAcceptance.accept(
            records: [greenTea, notGreenTea], current: current, restartEvidence: .verifiedBootChange)
        XCTAssertEqual(report.acceptedCount, 2)
        XCTAssertEqual(report.filePersistedCount, 2)
        XCTAssertTrue(report.restartVerifiedCandidateIDs.isEmpty)
    }

    /// A post-restart document whose layout cannot resolve leaves
    /// CacheData items unreadable, while CacheExtra items are still
    /// read — the report never guesses a slot value.
    func testUnreadableCacheDataWithoutLayout() throws {
        let records = [regionRecord(), esimGreenTeaRecord()]
        let current = try documentWithUnknownLayout()
        let report = PostModificationAcceptance.accept(records: records, current: current)
        let region = report.items.first { $0.key == GestaltKeys.regionCode }
        let greenTea = report.items.first { $0.key == DeviceCacheOptions.greenTeaKey }
        XCTAssertEqual(region?.outcome, .reverted,
                       "The region key still reads from CacheExtra")
        XCTAssertEqual(greenTea?.outcome, .unreadable,
                       "The eSIM slot cannot be read without a layout")
        XCTAssertEqual(report.unreadableCount, 1)
    }

    /// File vs live: the file holds the staged LL, but the live
    /// probe reports CH — the item is file-accepted and the live
    /// disagreement is reported, never hidden.
    func testFileVsLiveDistinction() throws {
        let record = regionRecord()
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let disagreeing = PostModificationAcceptance.accept(
            records: [record], current: current,
            liveValues: [GestaltKeys.regionCode: .string("CH")])
        XCTAssertEqual(disagreeing.items.first?.outcome, .accepted,
                       "The file holds the staged value")
        XCTAssertEqual(disagreeing.items.first?.liveAgrees, false,
                       "The live probe disagrees with the staged value")
        let agreeing = PostModificationAcceptance.accept(
            records: [record], current: current,
            liveValues: [GestaltKeys.regionCode: .string("LL")])
        XCTAssertEqual(agreeing.items.first?.liveAgrees, true)
    }

    /// The summary says plainly when the device was not confirmed
    /// restarted: file values alone say nothing about whether the
    /// system took the change.
    func testRestartConfirmedAffectsSummary() throws {
        let record = regionRecord()
        let current = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let unconfirmed = PostModificationAcceptance.accept(
            records: [record], current: current, restartEvidence: .sameBoot)
        let confirmed = PostModificationAcceptance.accept(
            records: [record], current: current, restartEvidence: .verifiedBootChange)
        XCTAssertEqual(unconfirmed.restartEvidence, .sameBoot)
        XCTAssertEqual(confirmed.restartEvidence, .verifiedBootChange)
        XCTAssertEqual(unconfirmed.filePersistedCount, 0)
        XCTAssertEqual(confirmed.filePersistedCount, 1)
        XCTAssertEqual(confirmed.systemConfirmedCount, 0)
        XCTAssertTrue(confirmed.restartVerifiedCandidateIDs.isEmpty)
    }

    // MARK: - Live values from the probe

    /// A fake live-answers source: answers only what the test says,
    /// nothing else.
    private struct FakeLiveAnswers: LiveAnswersSource {
        let bools: [String: Bool]
        let strings: [String: String]
        func boolAnswer(for key: String) -> Bool? { bools[key] }
        func stringAnswer(for key: String) -> String? { strings[key] }
    }

    /// Bool targets ask for a bool answer, string targets for a
    /// string answer, and both are mapped to the matching
    /// `ChangeValue`.
    func testLiveValuesMapsBoolAndStringTargets() throws {
        let aiKey = try XCTUnwrap(Capability.all.first(where: { $0.id == "ai" })?.keys.first)
        let aiRecord = RecordedChange(
            id: UUID(), date: Date(timeIntervalSince1970: 0), deviceID: "test",
            osBuild: "23A344", featureID: "ai", key: aiKey,
            layer: .cacheExtra, original: .absent, new: .bool(true),
            backupProvenance: .preModification, verified: true)
        let fake = FakeLiveAnswers(
            bools: [aiKey: true],
            strings: [GestaltKeys.regionCode: "LL"])
        let values = PostModificationAcceptance.liveValues(
            for: [regionRecord(), aiRecord], using: fake)
        XCTAssertEqual(values[GestaltKeys.regionCode], .string("LL"))
        XCTAssertEqual(values[aiKey], .bool(true))
    }

    /// CacheData keys get no live value: the slots have no live
    /// probe, so the file value is the only evidence for them.
    func testLiveValuesSkipsCacheDataKeys() {
        let fake = FakeLiveAnswers(
            bools: [DeviceCacheOptions.greenTeaKey: false], strings: [:])
        let values = PostModificationAcceptance.liveValues(
            for: [esimGreenTeaRecord()], using: fake)
        XCTAssertTrue(values.isEmpty, "A CacheData key must never get a live-probe value")
    }

    /// A key the probe cannot answer gets no entry — never a guessed
    /// value.
    func testLiveValuesSkipsUnansweredKeys() {
        let values = PostModificationAcceptance.liveValues(
            for: [regionRecord()], using: FakeLiveAnswers(bools: [:], strings: [:]))
        XCTAssertTrue(values.isEmpty)
    }

    /// An integer target is not probed at all: asking a bool question
    /// about an integer key would misread it.
    func testLiveValuesSkipsIntTargets() {
        let intRecord = RecordedChange(
            id: UUID(), date: Date(timeIntervalSince1970: 0), deviceID: "test",
            osBuild: "23A344", featureID: "test", key: "test-int-key",
            layer: .cacheExtra, original: .int(1), new: .int(2),
            backupProvenance: .preModification, verified: true)
        let fake = FakeLiveAnswers(bools: ["test-int-key": true], strings: [:])
        let values = PostModificationAcceptance.liveValues(for: [intRecord], using: fake)
        XCTAssertTrue(values.isEmpty, "An integer-valued key must not be read as a bool")
    }

    func testSixAIKeysAreProbedAndAcceptedIndependently() throws {
        let keys = ChinaUnlock.aiCapabilities.flatMap(\.keys)
        XCTAssertEqual(Set(keys).count, 6)
        let records = keys.map(aiRecord)
        let cache = try CoreModuleFixtures.document(extra: Dictionary(uniqueKeysWithValues: keys.map {
            ($0, NSNumber(value: true))
        }))
        var queried = Set<String>()
        let raw = LiveGestaltProbe.answers(for: Set(keys)) { key in
            queried.insert(key)
            if key == keys[0] { return PlistObservation(NSNumber(value: true)) }
            if key == keys[1] { return PlistObservation(NSNumber(value: false)) }
            if key == keys[2] { return PlistObservation(NSNumber(value: 1)) }
            return nil
        }
        XCTAssertEqual(queried, Set(keys))
        let values = raw.compactMapValues { $0.value.flatMap(ChangeValue.fromPlistValue) }
        let report = PostModificationAcceptance.accept(records: records, current: cache,
                                                       liveValues: values, restartEvidence: .verifiedBootChange)
        XCTAssertEqual(report.items.map(\.status), [
            .systemConfirmed, .systemDisagrees, .systemConfirmed, .filePersisted, .filePersisted, .filePersisted
        ])
        XCTAssertEqual(report.filePersistedCount, 6)
        XCTAssertEqual(report.systemConfirmedCount, 2)
        XCTAssertEqual(report.systemDisagreesCount, 1)
        XCTAssertEqual(report.restartVerifiedCandidateIDs, [records[0].id, records[2].id])
    }

    func testErrorStateAndManualRestartCannotConfirmSystem() throws {
        let record = aiRecord(ChinaUnlock.appleIntelligenceKey)
        let current = try CoreModuleFixtures.document(extra: [record.key: NSNumber(value: true)])
        let answer = [record.key: ChangeValue.bool(true)]
        let failed = PostModificationAcceptance.accept(records: [record], current: nil, liveValues: answer,
                                                       restartEvidence: .verifiedBootChange)
        let manual = PostModificationAcceptance.accept(records: [record], current: current, liveValues: answer,
                                                       restartEvidence: .manualWithFreshRead)
        let otherBuild = PostModificationAcceptance.accept(records: [record], current: current, liveValues: answer,
                                                           restartEvidence: .verifiedBootChange, sameBuild: false)
        XCTAssertEqual(failed.items.first?.status, .unknown)
        XCTAssertEqual(manual.items.first?.status, .filePersisted)
        XCTAssertEqual(otherBuild.items.first?.status, .unknown)
        XCTAssertTrue([failed, manual, otherBuild].allSatisfy { $0.restartVerifiedCandidateIDs.isEmpty })
    }

    func testBootSessionRequiresFreshReadAndBootAfterWrite() {
        let before = BootSession(seconds: 100, microseconds: 0)
        let after = BootSession(seconds: 200, microseconds: 0)
        let write = Date(timeIntervalSince1970: 150)
        let read = Date(timeIntervalSince1970: 210)
        XCTAssertEqual(RestartEvidence.compare(before: before, after: after, referenceDate: write,
                                               readAt: read, manual: false), .verifiedBootChange)
        XCTAssertEqual(RestartEvidence.compare(before: before, after: before, referenceDate: write,
                                               readAt: read, manual: true), .sameBoot)
        XCTAssertEqual(RestartEvidence.compare(before: before, after: after, referenceDate: write,
                                               readAt: write, manual: true), .noFreshRead)
        XCTAssertEqual(RestartEvidence.compare(before: nil, after: after, referenceDate: write,
                                               readAt: read, manual: true), .manualWithFreshRead)
    }

    func testCacheUUIDChangeAloneDoesNotProveRebuild() throws {
        let before = try StandalonePresetsTests.fixture()
        let after = try StandalonePresetsTests.fixture(cacheUUID: UUID().uuidString)
        func fingerprint(_ document: GestaltDocument, inode: UInt64) throws -> CacheFingerprint {
            CacheFingerprint(snapshot: DocumentSnapshot(data: try document.encoded(), document: document,
                source: .local, name: "fixture", cacheFileIdentity: CacheFileIdentity(inode: inode,
                    birthSeconds: Int64(inode), birthMicroseconds: 0)), osBuild: "test")
        }
        let original = try fingerprint(before, inode: 1)
        let uuidOnly = try original.compare(to: fingerprint(after, inode: 1))
        let replaced = try original.compare(to: fingerprint(after, inode: 2))
        XCTAssertTrue(uuidOnly.uuidChanged)
        XCTAssertTrue(uuidOnly.layoutResolutionChanged)
        XCTAssertFalse(uuidOnly.layoutChanged)
        XCTAssertFalse(uuidOnly.rebuildEvidence)
        XCTAssertTrue(replaced.rebuildEvidence)
    }

    func testSiriBetaRegionAndLanguagesAreIndependentOfMG() {
        var settings = SiriSettingsObservation()
        settings.appleAccountRegion = "CN"
        settings.siriLanguage = "en-US"
        settings.appleIntelligenceEnabled = true
        settings.betaEntry = true
        settings.betaEnabled = true
        settings.voiceConfigured = true
        settings.modelDownloaded = true
        func status(_ settings: SiriSettingsObservation) -> SiriBetaStatus.Outcome {
            SiriBetaStatus(nativeHardware: true, osVersion: "27.0", deviceLanguage: "en-US", settings: settings).outcome
        }
        XCTAssertEqual(status(settings), .unsupportedRegion)
        settings.appleAccountRegion = ""
        XCTAssertEqual(status(settings), .pendingConfirmation)
        settings.appleAccountRegion = "US"
        settings.siriLanguage = "zh-CN"
        XCTAssertEqual(status(settings), .unsupportedLanguage)
        settings.siriLanguage = "en-US"
        XCTAssertEqual(status(settings), .readyInSettings)
    }

    private func aiRecord(_ key: String) -> RecordedChange {
        RecordedChange(id: UUID(), date: .distantPast, deviceID: "test", osBuild: "test",
                       featureID: "ai", key: key, layer: .cacheExtra, original: .absent, new: .bool(true),
                       backupProvenance: .preModification, verified: true)
    }

    // MARK: - Helpers

    /// Region staged CH → LL.
    private func regionRecord() -> RecordedChange {
        RecordedChange(
            id: UUID(), date: Date(timeIntervalSince1970: 0), deviceID: "test",
            osBuild: "23A344", featureID: "regionCode", key: GestaltKeys.regionCode,
            layer: .cacheExtra, original: .string("CH"), new: .string("LL"),
            backupProvenance: .preModification, verified: true)
    }

    /// eSIM green-tea staged true → false.
    private func esimGreenTeaRecord() -> RecordedChange {
        RecordedChange(
            id: UUID(), date: Date(timeIntervalSince1970: 0), deviceID: "test",
            osBuild: "23A344", featureID: "esim", key: DeviceCacheOptions.greenTeaKey,
            layer: .cacheData, original: .bool(true), new: .bool(false),
            backupProvenance: .preModification, verified: true)
    }

    /// A document with a CacheUUID no known layout matches, so the
    /// layout cannot resolve.
    private func documentWithUnknownLayout() throws -> GestaltDocument {
        try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheUUID": "00000000-0000-0000-0000-000000000000",
            "CacheData": CoreModuleFixtures.cacheData(greenTea: true, notGreenTea: false, wapi: true),
            "CacheExtra": [GestaltKeys.regionCode: "CH"],
        ], format: .binary, options: 0))
    }
}
