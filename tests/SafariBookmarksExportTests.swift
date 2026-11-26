import Foundation
import XCTest
@testable import GestaltX

/// Safari bookmarks export tests (A17): the Netscape HTML
/// structure browsers import, HTML escaping of titles and URLs,
/// and skipping entries with an empty URL. The source database is
/// never touched here — only rendering is tested.
final class SafariBookmarksExportTests: XCTestCase {
    func testHTMLStructure() {
        let html = SafariBookmarksExport.html([
            SafariBookmarkRecord(id: 1, title: "Example", url: "https://example.com"),
            SafariBookmarkRecord(id: 2, title: "", url: "https://example.org"),
        ])
        XCTAssertTrue(html.hasPrefix("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
        XCTAssertTrue(html.contains("<TITLE>Bookmarks</TITLE>"))
        XCTAssertTrue(html.contains("<DT><A HREF=\"https://example.com\">Example</A>"))
        // An empty title falls back to the URL.
        XCTAssertTrue(html.contains("<DT><A HREF=\"https://example.org\">https://example.org</A>"))
        XCTAssertTrue(html.hasSuffix("</DL><p>\n"))
    }

    func testHTMLEscaping() {
        let html = SafariBookmarksExport.html([
            SafariBookmarkRecord(id: 1, title: "A & B <C> \"D\"", url: "https://example.com/?a=1&b=2"),
        ])
        XCTAssertTrue(html.contains("A &amp; B &lt;C&gt; &quot;D&quot;"))
        XCTAssertTrue(html.contains("https://example.com/?a=1&amp;b=2"))
        XCTAssertFalse(html.contains("A & B"))
    }

    func testEmptyURLIsSkipped() {
        let html = SafariBookmarksExport.html([
            SafariBookmarkRecord(id: 1, title: "No URL", url: ""),
            SafariBookmarkRecord(id: 2, title: "Has URL", url: "https://example.com"),
        ])
        XCTAssertFalse(html.contains("No URL"))
        XCTAssertTrue(html.contains("Has URL"))
    }

    func testEmptyBookmarks() {
        let html = SafariBookmarksExport.html([])
        XCTAssertTrue(html.contains("<DL><p>"))
        XCTAssertTrue(html.contains("</DL><p>"))
        XCTAssertFalse(html.contains("<DT>"))
    }
}
