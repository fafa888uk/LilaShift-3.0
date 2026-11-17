// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Safari bookmarks export (A17, read-only source).
///
/// The bookmarks themselves are read by `SafariBookmarks.read`
/// (MEDIUM A11, APFS snapshot, read-only). This file only renders
/// them into the interoperable Netscape bookmark HTML format that
/// browsers import (`bookmarks.html`), so the user's own bookmarks
/// can be carried to another browser. Nothing is written back to
/// Safari, and the source database is never modified.
enum SafariBookmarksExport {
    static let fileName = "Safari-Bookmarks.html"

    /// Renders bookmarks as Netscape bookmark HTML. Titles and URLs
    /// are HTML-escaped; entries with an empty URL are skipped.
    static func html(_ bookmarks: [SafariBookmarkRecord]) -> String {
        var lines: [String] = [
            "<!DOCTYPE NETSCAPE-Bookmark-file-1>",
            "<!-- This is an automatically generated file.",
            "     It will be read and overwritten.",
            "     DO NOT EDIT! -->",
            "<META HTTP-EQUIV=\"Content-Type\" CONTENT=\"text/html; charset=UTF-8\">",
            "<TITLE>Bookmarks</TITLE>",
            "<H1>Bookmarks</H1>",
            "<DL><p>",
        ]
        for record in bookmarks where !record.url.isEmpty {
            let title = escape(record.title.isEmpty ? record.url : record.title)
            lines.append("    <DT><A HREF=\"\(escape(record.url))\">\(title)</A>")
        }
        lines.append("</DL><p>")
        return lines.joined(separator: "\n") + "\n"
    }

    /// Minimal HTML escaping for attribute values and text content.
    static func escape(_ raw: String) -> String {
        var out = raw
        out = out.replacingOccurrences(of: "&", with: "&amp;")
        out = out.replacingOccurrences(of: "<", with: "&lt;")
        out = out.replacingOccurrences(of: ">", with: "&gt;")
        out = out.replacingOccurrences(of: "\"", with: "&quot;")
        return out
    }
}
