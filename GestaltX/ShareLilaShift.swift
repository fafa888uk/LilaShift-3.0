// SPDX-License-Identifier: GPL-3.0-only
// LilaShift 4.0: share the current release with others.
// There are no referral codes, invite links or rewards — the share
// only points at the public release page and the Telegram updates
// channel. The shared build is 4.1.0.
import Foundation

/// Content for the "Share LilaShift" row in About.
enum ShareLilaShift {
    /// Public release page for 4.1.0.
    static let releaseURLString = "https://github.com/fafa888uk/LilaShift-3.0/releases/tag/v4.1.0"
    /// Telegram updates channel.
    static let telegramURLString = "https://t.me/LilaShiftUpdates"
    /// Version label of the shared build.
    static let versionLabel = "4.1.0"

    static var releaseURL: URL { URL(string: releaseURLString)! }
    static var telegramURL: URL { URL(string: telegramURLString)! }

    /// The full share text: app name, version and both links. The
    /// URLs are constants and are never translated. 4.1.0 is a formal
    /// release, so no pre-release label is attached.
    static func text() -> String {
        "LilaShift \(versionLabel)\n\(releaseURLString)\n\(L("Telegram Updates Channel")): \(telegramURLString)"
    }
}
