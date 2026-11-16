// SPDX-License-Identifier: GPL-3.0-only
// LilaShift 3.0: share the current pre-release with others.
// There are no referral codes, invite links or rewards — the share
// only points at the public release page and the Telegram updates
// channel. The shared build is 3.0.0-rc.1, a pre-release, never a
// stable release.
import Foundation

/// Content for the "Share LilaShift" row in About.
enum ShareLilaShift {
    /// Public release page for 3.0.0-rc.1.
    static let releaseURLString = "https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v3.0.0-rc.1"
    /// Telegram updates channel.
    static let telegramURLString = "https://t.me/LilaShiftUpdates"
    /// Version label of the shared build.
    static let versionLabel = "3.0.0-rc.1"

    static var releaseURL: URL { URL(string: releaseURLString)! }
    static var telegramURL: URL { URL(string: telegramURLString)! }

    /// Localized label stating the shared build is a pre-release.
    static var preReleaseLabel: String { L("Pre-release") }

    /// The full share text: app name, version, pre-release label and
    /// both links. The URLs are constants and are never translated.
    static func text() -> String {
        "LilaShift \(versionLabel) (\(preReleaseLabel))\n\(releaseURLString)\n\(L("Telegram Updates Channel")): \(telegramURLString)"
    }
}
