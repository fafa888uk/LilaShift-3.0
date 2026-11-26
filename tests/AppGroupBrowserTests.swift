import Foundation
import SQLite3
import XCTest
@testable import GestaltX

/// Offline tests for the AppGroup browser (A11, Erosion-CN
/// AppGroupHubView): relative-path validation (the traversal guard
/// that keeps browsing inside the container), the known proxy-group
/// map, and the Safari bookmark reader against a fixture database.
/// No device is needed.
final class AppGroupBrowserTests: XCTestCase {
    func testValidRelativePaths() {
        XCTAssertTrue(AppGroupBrowser.validRelativePath(""))
        XCTAssertTrue(AppGroupBrowser.validRelativePath("Documents"))
        XCTAssertTrue(AppGroupBrowser.validRelativePath("Library/Safari"))
        XCTAssertTrue(AppGroupBrowser.validRelativePath("a/b/c"))
    }

    func testTraversalPathsAreRejected() {
        XCTAssertFalse(AppGroupBrowser.validRelativePath(".."))
        XCTAssertFalse(AppGroupBrowser.validRelativePath("../.."))
        XCTAssertFalse(AppGroupBrowser.validRelativePath("Documents/../.."))
        XCTAssertFalse(AppGroupBrowser.validRelativePath("/absolute"))
        XCTAssertFalse(AppGroupBrowser.validRelativePath("a//b"))
        XCTAssertFalse(AppGroupBrowser.validRelativePath("a/./b"))
        XCTAssertFalse(AppGroupBrowser.validRelativePath("a\\b"))
        XCTAssertFalse(AppGroupBrowser.validRelativePath("a\0b"))
    }

    func testKnownProxyGroups() {
        XCTAssertEqual(AppGroupDiscovery.knownProxyGroups["group.com.nssurge.inc.surge-ios"], "Surge")
        XCTAssertEqual(AppGroupDiscovery.knownProxyGroups["group.com.nssurge.inc.surge-ios-tf"], "Surge (TestFlight)")
        XCTAssertEqual(AppGroupDiscovery.knownProxyGroups["group.com.liguangming.Shadowrocket"], "Shadowrocket")
        XCTAssertEqual(AppGroupDiscovery.knownProxyGroups["group.com.luo.quantumult-x"], "Quantumult X")
        XCTAssertEqual(AppGroupDiscovery.knownProxyGroups["group.com.loon.loon"], "Loon")
        XCTAssertEqual(AppGroupDiscovery.knownProxyGroups["group.ws.stash.app"], "Stash")
        XCTAssertNil(AppGroupDiscovery.knownProxyGroups["group.com.apple.mobilesafari"])
    }

    func testListRefusesTraversal() {
        let group = AppGroupContainer(id: "/tmp", groupID: "group.test", path: "/tmp", clientName: nil)
        XCTAssertTrue(AppGroupBrowser.list(container: group, relativePath: "..").isEmpty)
        XCTAssertTrue(AppGroupBrowser.list(container: group, relativePath: "/etc").isEmpty)
    }

    func testListReadsRealDirectory() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        try Data("hello".utf8).write(to: dir.appendingPathComponent("note.txt"))
        try fm.createDirectory(at: dir.appendingPathComponent("Sub"), withIntermediateDirectories: false)
        let group = AppGroupContainer(id: dir.path, groupID: "group.test", path: dir.path, clientName: nil)
        let entries = AppGroupBrowser.list(container: group)
        XCTAssertEqual(entries.map(\.name), ["Sub", "note.txt"])
        XCTAssertTrue(entries[0].isDirectory)
        XCTAssertFalse(entries[1].isDirectory)
        XCTAssertEqual(entries[1].byteCount, 5)
    }

    func testSafariBookmarksFromFixture() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }
        let dbPath = dir.appendingPathComponent("Bookmarks.db").path
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dbPath, &db), SQLITE_OK)
        defer { if let db { sqlite3_close(db) } }
        let schema = """
        CREATE TABLE bookmarks (title TEXT, url TEXT);
        INSERT INTO bookmarks VALUES ('Example', 'https://example.com');
        INSERT INTO bookmarks VALUES ('', 'https://empty-title.example');
        INSERT INTO bookmarks VALUES (NULL, NULL);
        INSERT INTO bookmarks VALUES ('No URL', '');
        """
        var error: UnsafeMutablePointer<CChar>?
        XCTAssertEqual(sqlite3_exec(db, schema, nil, nil, &error), SQLITE_OK)
        let records = SafariBookmarks.read(at: dbPath)
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records[0].title, "Example")
        XCTAssertEqual(records[0].url, "https://example.com")
        XCTAssertEqual(records[1].title, "")
        XCTAssertEqual(records[1].url, "https://empty-title.example")
    }

    func testSafariBookmarksMissingFileReturnsEmpty() {
        XCTAssertTrue(SafariBookmarks.read(at: "/tmp/definitely-not-a-database.db").isEmpty)
    }
}
