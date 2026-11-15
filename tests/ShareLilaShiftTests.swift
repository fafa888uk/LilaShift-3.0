// SPDX-License-Identifier: GPL-3.0-only
// Tests for the About "Share LilaShift" row: the shared text must
// link the release page and the Telegram updates channel, name the
// shared version, and mark the build as a pre-release — never as a
// stable release. There are no referral codes, invite links or
// rewards to test for; the share only points at public links.
import XCTest
@testable import GestaltX

final class ShareLilaShiftTests: XCTestCase {
    func testShareTextContainsReleaseURLAndTelegramLink() {
        let text = ShareLilaShift.text()
        XCTAssertTrue(text.contains(ShareLilaShift.releaseURLString), "Share text must link the release page")
        XCTAssertTrue(text.contains(ShareLilaShift.telegramURLString), "Share text must link the Telegram updates channel")
    }

    func testShareTextNamesVersionAndMarksPreRelease() {
        let text = ShareLilaShift.text()
        XCTAssertTrue(text.contains(ShareLilaShift.versionLabel), "Share text must name the shared version")
        XCTAssertTrue(text.contains(ShareLilaShift.preReleaseLabel), "Share text must mark the build as a pre-release")
        XCTAssertTrue(text.contains(L("Telegram Updates Channel")), "Share text must label the Telegram link")
    }

    func testShareTextDoesNotClaimStableRelease() {
        let text = ShareLilaShift.text()
        XCTAssertFalse(text.localizedCaseInsensitiveContains("stable release"), "A pre-release must never be presented as stable")
        XCTAssertFalse(text.contains("正式版"), "A pre-release must never be presented as stable")
    }

    func testShareURLsAreValid() {
        XCTAssertEqual(ShareLilaShift.releaseURL.host, "github.com")
        XCTAssertEqual(ShareLilaShift.releaseURL.path, "/fafa920q-hue/LilaShift-2.0/releases/tag/v3.0.0-rc.1")
        XCTAssertEqual(ShareLilaShift.telegramURL.host, "t.me")
        XCTAssertEqual(ShareLilaShift.telegramURL.path, "/LilaShiftUpdates")
    }
}
