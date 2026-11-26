import Foundation
import XCTest
@testable import GestaltX

/// Offline tests for the crash diagnostics parser (A8, Erosion-CN
/// CrashDiagnosticsView): the `.ips` first-line JSON header format
/// (`bug_type` as a string, `app_name`/`name`), bug-type mapping
/// (298 jetsam, 309/109 crash, 210 panic), app-name fallback, and
/// the `cleanAllReports` path guard that refuses files outside the
/// diagnostic reports directory. No device is needed: parsing is
/// pure, and cleaning is tested with constructed items.
final class CrashDiagnosticsTests: XCTestCase {
    private func ipsData(bugType: String, appName: String? = nil, body: [String: Any] = [:]) throws -> Data {
        var header: [String: Any] = ["bug_type": bugType, "timestamp": "2026-11-17T08:00:00Z"]
        if let appName { header["app_name"] = appName }
        let headerJSON = String(data: try JSONSerialization.data(withJSONObject: header), encoding: .utf8)!
        let bodyJSON = String(data: try JSONSerialization.data(withJSONObject: body), encoding: .utf8)!
        return Data((headerJSON + "\n" + bodyJSON).utf8)
    }

    private func parse(_ data: Data, fileName: String = "test.ips") -> DiagnosticReportItem? {
        CrashDiagnostics.parseIPSData(data, fileName: fileName, modifiedDate: Date(timeIntervalSince1970: 0),
                                      fileSize: Int64(data.count), fileURL: URL(fileURLWithPath: "/tmp/" + fileName))
    }

    func testJetsamBugType() throws {
        let item = parse(try ipsData(bugType: "298", appName: "TestApp"))
        XCTAssertEqual(item?.kind, .jetsam)
        XCTAssertEqual(item?.bugType, "298")
    }

    func testCrashBugTypes() throws {
        for bugType in ["309", "109"] {
            let item = parse(try ipsData(bugType: bugType, appName: "TestApp"))
            XCTAssertEqual(item?.kind, .crash, "bug_type \(bugType) should map to crash")
        }
    }

    func testPanicBugType() throws {
        let item = parse(try ipsData(bugType: "210"))
        XCTAssertEqual(item?.kind, .system)
        XCTAssertEqual(item?.processName, "Kernel panic / watchdog restart")
    }

    func testUnknownBugTypeMapsToSystem() throws {
        let item = parse(try ipsData(bugType: "999"))
        XCTAssertEqual(item?.kind, .system)
    }

    func testAppNameFromHeader() throws {
        let item = parse(try ipsData(bugType: "309", appName: "TestApp", body: ["procName": "TestApp"]))
        XCTAssertEqual(item?.processName, "TestApp")
    }

    func testMissingAppNameFallsBackToFilename() throws {
        let item = parse(try ipsData(bugType: "309"), fileName: "MyApp-2026-11-17.ips")
        // Without a body procName the process name stays the file name.
        XCTAssertEqual(item?.processName, "MyApp-2026-11-17.ips")
    }

    func testJetsamFilenameDetectsJetsam() throws {
        let item = parse(try ipsData(bugType: "Unknown"), fileName: "JetsamEvent-2026-11-17.ips")
        XCTAssertEqual(item?.kind, .jetsam)
    }

    func testPanicFilenameDetectsSystem() throws {
        let item = parse(try ipsData(bugType: "Unknown"), fileName: "panic-full-2026-11-17.ips")
        XCTAssertEqual(item?.kind, .system)
    }

    func testInvalidJSONStillReturnsItemWithUnknownType() {
        // The parser never crashes on malformed input; it reports an
        // unknown system event instead of inventing a kind.
        let item = parse(Data("not json at all".utf8))
        XCTAssertNotNil(item)
        XCTAssertEqual(item?.kind, .system)
        XCTAssertEqual(item?.bugType, "Unknown")
    }

    func testCleanRefusesFilesOutsideReportsDirectory() {
        let outside = DiagnosticReportItem(id: "/tmp/evil.ips", fileURL: URL(fileURLWithPath: "/tmp/evil.ips"),
                                           fileName: "evil.ips", kind: .crash, bugType: "309",
                                           processName: "evil", subtitle: "evil",
                                           modifiedDate: Date(), fileSize: 10)
        XCTAssertEqual(CrashDiagnostics.cleanAllReports([outside]), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/evil.ips"))
    }

    func testCleanRefusesNonRegularFiles() {
        // A directory inside the reports path must never be removed.
        let dir = DiagnosticReportItem(id: CrashDiagnostics.diagnosticReportsDirectory,
                                       fileURL: URL(fileURLWithPath: CrashDiagnostics.diagnosticReportsDirectory),
                                       fileName: "DiagnosticReports", kind: .system, bugType: "210",
                                       processName: "dir", subtitle: "dir",
                                       modifiedDate: Date(), fileSize: 0)
        XCTAssertEqual(CrashDiagnostics.cleanAllReports([dir]), 0)
    }
}
