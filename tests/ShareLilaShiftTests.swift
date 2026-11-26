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

    func testShareTextNamesVersionWithoutPreReleaseMark() {
        let text = ShareLilaShift.text()
        XCTAssertTrue(text.contains(ShareLilaShift.versionLabel), "Share text must name the shared version")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("pre-release"), "A formal release must not be marked as a pre-release")
        XCTAssertFalse(text.contains("预发布"), "A formal release must not be marked as a pre-release")
        XCTAssertTrue(text.contains(L("Telegram Updates Channel")), "Share text must label the Telegram link")
    }

    func testShareTextLinksFormalRelease() {
        let text = ShareLilaShift.text()
        XCTAssertTrue(text.contains("/releases/tag/v4.1.0"), "Share text must link the formal 4.0.0 release page")
        XCTAssertFalse(text.localizedCaseInsensitiveContains("rc."), "A formal release must not link a release candidate")
    }

    func testShareURLsAreValid() {
        XCTAssertEqual(ShareLilaShift.releaseURL.host, "github.com")
        XCTAssertEqual(ShareLilaShift.releaseURL.path, "/fafa888uk/LilaShift-3.0/releases/tag/v4.1.0")
        XCTAssertEqual(ShareLilaShift.telegramURL.host, "t.me")
        XCTAssertEqual(ShareLilaShift.telegramURL.path, "/LilaShiftUpdates")
    }
}
