import Foundation
import SQLite3
import XCTest
@testable import GestaltX

/// Voice memo export tests (A16, Erosion-CN `VoiceMemosAIView`):
/// the pure helpers (filename sanitizing, duration formatting,
/// label normalization), the CloudRecordings.db parse against a
/// fixture database, the recording listing over a temp root, and
/// the ZIP export (original bytes unchanged). No device is needed.
final class VoiceMemoExportTests: XCTestCase {
    func testSanitizeFileName() {
        XCTAssertEqual(VoiceMemoExport.sanitizeFileName("My memo"), "My memo")
        XCTAssertEqual(VoiceMemoExport.sanitizeFileName("a/b:c?d*e\"f<g>h|i"), "a_b_c_d_e_f_g_h_i")
        XCTAssertEqual(VoiceMemoExport.sanitizeFileName(""), "Recording")
        XCTAssertEqual(VoiceMemoExport.sanitizeFileName("   "), "Recording")
    }

    func testFormatDuration() {
        XCTAssertEqual(VoiceMemoExport.formatDuration(0), "00:00")
        XCTAssertEqual(VoiceMemoExport.formatDuration(65), "01:05")
        XCTAssertEqual(VoiceMemoExport.formatDuration(3661), "1:01:01")
        XCTAssertEqual(VoiceMemoExport.formatDuration(-5), "00:00")
    }

    func testNormalizeRecordingLabel() {
        // A custom label wins over a timestamp sorting label.
        XCTAssertEqual(VoiceMemoExport.normalizeRecordingLabel(
            sortingLabel: "2026-11-17T10:00:00Z", customLabel: "Interview"), "Interview")
        // A bare timestamp becomes "Recording <date>" (the clock
        // part depends on the runner's timezone, so only the date
        // and the prefix are asserted).
        let stamped = VoiceMemoExport.normalizeRecordingLabel(
            sortingLabel: "2026-11-17T10:00:00Z", customLabel: "")
        XCTAssertTrue(stamped.hasPrefix("Recording 2026-11-17"), "Got: \(stamped)")
        // A non-timestamp sorting label is used as-is.
        XCTAssertEqual(VoiceMemoExport.normalizeRecordingLabel(
            sortingLabel: "Morning notes", customLabel: ""), "Morning notes")
        XCTAssertEqual(VoiceMemoExport.normalizeRecordingLabel(sortingLabel: "", customLabel: ""), "")
    }

    func testParseCloudRecordingsDB() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("CloudRecordings.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbPath, &db), SQLITE_OK)
        defer { if let db { sqlite3_close(db) } }
        let schema = """
        CREATE TABLE ZCLOUDRECORDING (ZPATH TEXT, ZCUSTOMLABELFORSORTING TEXT, ZCUSTOMLABEL TEXT, ZDURATION REAL);
        INSERT INTO ZCLOUDRECORDING VALUES ('/Recordings/20261117-100000.m4a', '2026-11-17T10:00:00Z', 'Interview', 125.5);
        INSERT INTO ZCLOUDRECORDING VALUES ('/Recordings/20261117-110000.m4a', '2026-11-17T11:00:00Z', '', 60.0);
        INSERT INTO ZCLOUDRECORDING VALUES (NULL, '', '', NULL);
        """
        var error: UnsafeMutablePointer<CChar>?
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, &error), SQLITE_OK)
        let map = VoiceMemoExport.parseCloudRecordingsDB(at: dbPath)
        XCTAssertEqual(map["20261117-100000.m4a"]?.title, "Interview")
        XCTAssertEqual(map["20261117-100000.m4a"]?.duration, 125.5)
        XCTAssertEqual(map["20261117-100000"]?.title, "Interview")
        XCTAssertTrue(map["20261117-110000.m4a"]?.title.hasPrefix("Recording 2026-11-17") == true)
        XCTAssertEqual(map["20261117-110000.m4a"]?.duration, 60.0)
    }

    func testParseMissingDatabaseReturnsEmpty() {
        XCTAssertTrue(VoiceMemoExport.parseCloudRecordingsDB(at: "/tmp/definitely-not-a-database.db").isEmpty)
    }

    func testRecordingsListingOverTempRoot() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("VoiceMemoExportTests_\(UUID().uuidString)", isDirectory: true)
        let recDir = root.appendingPathComponent("Recordings", isDirectory: true)
        try fm.createDirectory(at: recDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let audio = Data("fake-audio-bytes".utf8)
        try audio.write(to: recDir.appendingPathComponent("20261117-100000.m4a"), options: .atomic)
        try "not audio".write(to: recDir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        // An empty audio file is skipped.
        try Data().write(to: recDir.appendingPathComponent("empty.m4a"), options: .atomic)
        let list = VoiceMemoExport.recordings(in: [root])
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].originalFileName, "20261117-100000.m4a")
        XCTAssertEqual(list[0].displayTitle, "20261117-100000")
        XCTAssertEqual(list[0].fileSizeBytes, Int64(audio.count))
    }

    func testZipRecordingsKeepsOriginalBytes() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("VoiceMemoZipTests_\(UUID().uuidString)", isDirectory: true)
        let recDir = root.appendingPathComponent("Recordings", isDirectory: true)
        try fm.createDirectory(at: recDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let audio = Data("fake-audio-bytes-1234".utf8)
        try audio.write(to: recDir.appendingPathComponent("memo.m4a"), options: .atomic)
        let list = VoiceMemoExport.recordings(in: [root])
        XCTAssertEqual(list.count, 1)
        let zipURL = try VoiceMemoExport.zipRecordings(list)
        defer { try? fm.removeItem(at: zipURL) }
        XCTAssertTrue(fm.fileExists(atPath: zipURL.path))
        XCTAssertTrue((try fm.attributesOfItem(atPath: zipURL.path)[.size] as? Int64 ?? 0) > 0)
        // The ZIP unzips to a file with the original bytes.
        let outDir = fm.temporaryDirectory.appendingPathComponent("VoiceMemoUnzip_\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: outDir) }
        try fm.unzipItem(at: zipURL, to: outDir)
        let unzipped = try fm.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil)
        XCTAssertEqual(unzipped.count, 1)
        XCTAssertEqual(try Data(contentsOf: unzipped[0]), audio)
    }
}
