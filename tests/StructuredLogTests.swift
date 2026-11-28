// SPDX-License-Identifier: GPL-3.0-only
// Structured log tests (LilaShift 5.0.0, Wave 1 W2) — level
// mapping, entry construction and redaction, keyword / level /
// kind / source / date filtering, JSON and text export (including
// the honesty notes and the redaction of shared files), and the W2
// directory metadata. Everything here is synchronous and uses only
// invented identifiers, never a real device's.
import Foundation
import XCTest
@testable import GestaltX

final class StructuredLogTests: XCTestCase {
    /// Fixed whole-second dates, so JSON round trips are exact
    /// (ISO 8601 has second precision).
    private let dayOne = Date(timeIntervalSince1970: 1_800_000_000)
    private let dayTwo = Date(timeIntervalSince1970: 1_800_086_400)
    private let exportAt = Date(timeIntervalSince1970: 1_800_100_000)

    private func event(
        date: Date? = nil, kind: OperationEventKind,
        key: String? = nil, detail: String, featureID: String? = nil
    ) -> OperationEvent {
        OperationEvent(
            date: date ?? dayOne, kind: kind, key: key,
            detail: detail, featureID: featureID)
    }

    private func entries() -> [StructuredLogEntry] {
        [
            StructuredLogEntry(event: event(kind: .readSucceeded, detail: "read ok")),
            StructuredLogEntry(event: event(kind: .readFailed, detail: "read timed out")),
            StructuredLogEntry(event: event(kind: .guardLayoutUnresolved, detail: "layout unknown")),
            StructuredLogEntry(event: event(kind: .backupCreated, detail: "backup saved")),
            StructuredLogEntry(sessionLine: "session started"),
        ]
    }

    // MARK: - Level mapping

    func testLevelMappingForAllKinds() {
        let errors: [OperationEventKind] = [.readFailed, .writeFailed, .restoreFailed, .backupFailed]
        for kind in errors {
            XCTAssertEqual(StructuredLogLevel.level(for: kind), .error, "\(kind.rawValue) is an error")
        }
        let warnings: [OperationEventKind] = [
            .guardLayoutUnresolved, .guardHardwareIdentity, .guardNativeConflict,
            .slotUnresolvable, .regionReverted,
        ]
        for kind in warnings {
            XCTAssertEqual(StructuredLogLevel.level(for: kind), .warning, "\(kind.rawValue) is a warning")
        }
        let infos: [OperationEventKind] = [.readSucceeded, .writeVerified, .restoreSucceeded, .backupCreated]
        for kind in infos {
            XCTAssertEqual(StructuredLogLevel.level(for: kind), .info, "\(kind.rawValue) is info")
        }
        XCTAssertEqual(errors.count + warnings.count + infos.count, 13)
    }

    func testAllKindsListsEveryKindOnce() {
        XCTAssertEqual(StructuredLog.allKinds.count, 13)
        XCTAssertEqual(Set(StructuredLog.allKinds).count, 13)
        for kind in [OperationEventKind.readSucceeded, .readFailed,
                     .writeVerified, .writeFailed,
                     .restoreSucceeded, .restoreFailed,
                     .guardLayoutUnresolved, .guardHardwareIdentity,
                     .guardNativeConflict, .slotUnresolvable,
                     .backupCreated, .backupFailed, .regionReverted] {
            XCTAssertTrue(StructuredLog.allKinds.contains(kind), "\(kind.rawValue) must be listed")
        }
    }

    func testLevelTitlesArePresent() {
        XCTAssertEqual(StructuredLogLevel.info.title, "Info")
        XCTAssertEqual(StructuredLogLevel.warning.title, "Warning")
        XCTAssertEqual(StructuredLogLevel.error.title, "Error")
    }

    // MARK: - Entry construction

    func testEntryFromOperationEvent() {
        let entry = StructuredLogEntry(event: event(
            kind: .readFailed, key: "A62OafQ85EJAiiqKn4agtg",
            detail: "read timed out", featureID: "regionCode"))
        XCTAssertEqual(entry.level, .error)
        XCTAssertEqual(entry.source, .operationEvent)
        XCTAssertEqual(entry.kind, .readFailed)
        XCTAssertEqual(entry.date, dayOne)
        XCTAssertEqual(entry.key, "A62OafQ85EJAiiqKn4agtg")
        XCTAssertEqual(entry.featureID, "regionCode")
        XCTAssertEqual(entry.title, OperationEventKind.readFailed.title)
        XCTAssertEqual(entry.detail, "read timed out")
    }

    func testEntryRedactsDeviceIdentifiers() {
        let entry = StructuredLogEntry(event: event(
            kind: .readFailed,
            detail: "UniqueDeviceID=00008150-000C0C5A14D2401C and serial ab12cd34ef56"))
        XCTAssertFalse(entry.detail.contains("00008150-000C0C5A14D2401C"))
        XCTAssertFalse(entry.detail.contains("ab12cd34ef56"))
        XCTAssertTrue(entry.detail.contains("[redacted]"))
    }

    func testEntryFromSessionLineHasNoDateAndIsInfo() {
        let entry = StructuredLogEntry(sessionLine: "session started")
        XCTAssertNil(entry.date, "A session line has no recorded time; none is invented")
        XCTAssertNil(entry.kind)
        XCTAssertEqual(entry.level, .info)
        XCTAssertEqual(entry.source, .sessionLine)
        XCTAssertEqual(entry.detail, "session started")
    }

    // MARK: - Keyword search

    func testKeywordMatchesTitleDetailKeyAndFeatureID() {
        let byDetail = StructuredLogEntry(event: event(kind: .backupCreated, detail: "backup saved"))
        XCTAssertTrue(byDetail.matches(keyword: "backup"))
        XCTAssertTrue(byDetail.matches(keyword: "BACKUP"), "Search is case-insensitive")
        let byKey = StructuredLogEntry(event: event(
            kind: .readSucceeded, key: "A62OafQ85EJAiiqKn4agtg", detail: "read ok"))
        XCTAssertTrue(byKey.matches(keyword: "A62OafQ85EJAiiqKn4agtg"))
        let byFeature = StructuredLogEntry(event: event(
            kind: .readSucceeded, detail: "read ok", featureID: "regionCode"))
        XCTAssertTrue(byFeature.matches(keyword: "regionCode"))
        XCTAssertFalse(byDetail.matches(keyword: "regionCode"))
    }

    func testEmptyKeywordMatchesEverything() {
        let entry = StructuredLogEntry(event: event(kind: .readFailed, detail: "read timed out"))
        XCTAssertTrue(entry.matches(keyword: ""))
        XCTAssertTrue(entry.matches(keyword: "   "))
    }

    // MARK: - Filters

    func testLevelFilter() {
        let all = entries()
        var filter = StructuredLogFilter()
        filter.levels = [.error]
        let errors = filter.applying(to: all)
        XCTAssertEqual(errors.count, 1)
        XCTAssertEqual(errors.first?.kind, .readFailed)
        filter.levels = [.info, .warning]
        XCTAssertEqual(filter.applying(to: all).count, 4)
    }

    func testKindFilterExcludesSessionLines() {
        var filter = StructuredLogFilter()
        filter.kinds = [.backupCreated]
        let found = filter.applying(to: entries())
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.kind, .backupCreated)
    }

    func testSourceFilter() {
        var filter = StructuredLogFilter()
        filter.source = .sessionLine
        let lines = filter.applying(to: entries())
        XCTAssertEqual(lines.count, 1)
        XCTAssertEqual(lines.first?.source, .sessionLine)
        filter.source = .operationEvent
        XCTAssertEqual(filter.applying(to: entries()).count, 4)
    }

    func testDateRangeFilter() {
        let first = StructuredLogEntry(event: event(date: dayOne, kind: .readSucceeded, detail: "day one"))
        let second = StructuredLogEntry(event: event(date: dayTwo, kind: .readSucceeded, detail: "day two"))
        let line = StructuredLogEntry(sessionLine: "undated line")
        var filter = StructuredLogFilter()
        filter.fromDate = dayOne
        filter.toDate = dayOne.addingTimeInterval(3_600)
        let found = filter.applying(to: [first, second, line])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.detail, "day one")
        // With no date range the undated line is included.
        XCTAssertEqual(StructuredLogFilter.unfiltered.applying(to: [first, second, line]).count, 3)
    }

    func testDayRangeCoversOneCalendarDay() {
        let range = StructuredLogFilter.dayRange(
            for: dayOne, calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(range.to.timeIntervalSince(range.from), 86_399, accuracy: 0.001)
        XCTAssertTrue(range.from <= dayOne && dayOne <= range.to)
    }

    func testCombinedFilters() {
        var filter = StructuredLogFilter()
        filter.keyword = "read"
        filter.levels = [.error]
        let found = filter.applying(to: entries())
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found.first?.kind, .readFailed)
    }

    func testUnfilteredFilterIsNotActive() {
        XCTAssertFalse(StructuredLogFilter.unfiltered.isActive)
        var filter = StructuredLogFilter()
        filter.keyword = "read"
        XCTAssertTrue(filter.isActive)
    }

    // MARK: - Assembly and counts

    func testEntriesFromSnapshotOrder() {
        let snapshot = OperationLogSnapshot(
            events: [
                event(kind: .readSucceeded, detail: "first"),
                event(kind: .backupCreated, detail: "second"),
            ],
            freeTextLines: ["line one", "line two"])
        let built = StructuredLog.entries(from: snapshot)
        XCTAssertEqual(built.count, 4)
        XCTAssertEqual(built[0].detail, "first")
        XCTAssertEqual(built[1].detail, "second")
        // Session lines have no timestamp, so they follow the
        // events, newest first.
        XCTAssertEqual(built[2].detail, "line two")
        XCTAssertEqual(built[3].detail, "line one")
        XCTAssertNil(built[2].date)
    }

    func testCountsByLevel() {
        let counts = StructuredLog.countsByLevel(entries())
        XCTAssertEqual(counts[.info], 3)
        XCTAssertEqual(counts[.warning], 1)
        XCTAssertEqual(counts[.error], 1)
        XCTAssertEqual(StructuredLog.countsByLevel([])[.error], 0)
    }

    // MARK: - Export

    func testJsonExportRoundTrip() throws {
        let all = entries()
        let data = try StructuredLogExporter.jsonData(for: all, exportedAt: exportAt)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(StructuredLogExportDocument.self, from: data)
        XCTAssertEqual(decoded.formatVersion, StructuredLogExporter.formatVersion)
        XCTAssertEqual(decoded.exportedAt, exportAt)
        XCTAssertEqual(decoded.entryCount, all.count)
        XCTAssertEqual(decoded.entries, all)
        XCTAssertEqual(
            decoded.writeAndRestoreEventsConnected,
            OperationLogSnapshot.writeAndRestoreEventsConnected)
    }

    func testJsonExportRedactsIdentifiers() throws {
        let entry = StructuredLogEntry(event: event(
            kind: .readFailed,
            detail: "UniqueDeviceID=00008150-000C0C5A14D2401C failed"))
        let data = try StructuredLogExporter.jsonData(for: [entry], exportedAt: exportAt)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("00008150-000C0C5A14D2401C"))
        XCTAssertTrue(text.contains("[redacted]"))
    }

    func testTextExportContainsHonestyNotesAndLevels() {
        let text = StructuredLogExporter.text(for: entries(), exportedAt: exportAt)
        XCTAssertTrue(text.contains(OperationLogSnapshot.writeAndRestoreNote))
        XCTAssertTrue(text.contains("no network request records"))
        XCTAssertTrue(text.contains("[ERROR]"))
        XCTAssertTrue(text.contains("[WARNING]"))
        XCTAssertTrue(text.contains("[INFO]"))
        XCTAssertTrue(text.contains("unknown time"), "Undated session lines say so")
        XCTAssertTrue(text.contains("read timed out"))
    }

    func testExportFileNames() {
        XCTAssertEqual(
            StructuredLogExportFormat.json.fileName(exportedAt: exportAt),
            "LilaShift-operation-log-1800100000.json")
        XCTAssertEqual(
            StructuredLogExportFormat.text.fileName(exportedAt: exportAt),
            "LilaShift-operation-log-1800100000.log")
    }

    func testTemporaryExportWritesShareableFile() throws {
        let export = try StructuredLogExporter.temporaryExport(
            for: entries(), format: .json, exportedAt: exportAt)
        addTeardownBlock { export.cleanUp() }
        XCTAssertTrue(FileManager.default.fileExists(atPath: export.url.path))
        XCTAssertEqual(export.url.lastPathComponent, "LilaShift-operation-log-1800100000.json")
        let data = try Data(contentsOf: export.url)
        XCTAssertFalse(data.isEmpty)
        export.cleanUp()
        XCTAssertFalse(FileManager.default.fileExists(atPath: export.url.path))
    }

    // MARK: - Registration

    func testRegistrationListsBothFeatures() {
        XCTAssertEqual(W2Registration.features.count, 2)
        let viewer = W2Registration.feature(id: "w2.structured-log-viewer")
        XCTAssertEqual(viewer?.title, "结构化日志查看")
        XCTAssertEqual(viewer?.category, .deviceDiagnostics)
        XCTAssertEqual(viewer?.viewType, "StructuredLogView")
        let export = W2Registration.feature(id: "w2.log-export-share")
        XCTAssertEqual(export?.title, "日志导出分享")
        XCTAssertEqual(export?.category, .deviceDiagnostics)
        XCTAssertEqual(export?.viewType, "StructuredLogView")
        XCTAssertNil(W2Registration.feature(id: "w2.no-such-feature"))
    }
}
