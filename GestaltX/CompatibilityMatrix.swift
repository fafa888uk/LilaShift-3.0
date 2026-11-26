// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// In-app compatibility matrix (A23).
///
/// Built from `docs/COMPATIBILITY_ZH-CN.md` and the code it
/// cites. Every cell carries its source, and the doc's own
/// verification disclaimer is the matrix's header: **this build
/// was not verified device-by-device on real hardware** — the
/// matrix states the designed support range, not a per-device
/// test result. Cells marked `.unverified` are exactly that:
/// never upgraded to supported or unsupported without evidence.
enum CompatibilityMatrix {
    enum Status: Equatable {
        case supported
        case unsupported
        case unverified
        case conditional
    }

    struct Cell: Equatable {
        let status: Status
        let note: String
    }

    struct SystemRow: Identifiable {
        var id: String { feature }
        let feature: String
        /// One cell per iOS column, in `iosColumns` order.
        let cells: [Cell]
        let source: String
    }

    struct DeviceRow: Identifiable {
        var id: String { device + feature }
        let device: String
        let feature: String
        let status: Status
        let note: String
        let source: String
    }

    struct InstallRow: Identifiable {
        var id: String { method }
        let method: String
        let requirement: String
        let note: String
        let source: String
    }

    static let iosColumns = ["iOS 27.x", "iOS 26.x", "iOS 25.x and earlier"]

    /// The doc's verification disclaimer, shown above the matrix.
    static let verificationDisclaimer = L("This build was not verified device-by-device on real hardware. The matrix below states the designed support range from the repository source and documentation, not a per-device test result. Anything marked “unverified” has not been confirmed on a real device with this build.")

    /// Feature × iOS version. Sources cite `docs/COMPATIBILITY_ZH-CN.md`
    /// sections unless noted.
    static let systemRows: [SystemRow] = [
        SystemRow(
            feature: "On-device MobileGestalt access",
            cells: [
                Cell(status: .supported, note: "Full functionality; SystemGroup access needs iOS 27."),
                Cell(status: .unsupported, note: "Installable, but on-device access reports unsupported."),
                Cell(status: .unsupported, note: "Out of support range."),
            ],
            source: "docs/COMPATIBILITY_ZH-CN.md §1"),
        SystemRow(
            feature: "Local plist editing",
            cells: [
                Cell(status: .supported, note: "Supported."),
                Cell(status: .supported, note: "Supported."),
                Cell(status: .unverified, note: "Not verified on this build."),
            ],
            source: "docs/COMPATIBILITY_ZH-CN.md §1"),
        SystemRow(
            feature: "One-tap unlock (eSIM + region)",
            cells: [
                Cell(status: .conditional, note: "eSIM needs eUICC hardware; see the device table."),
                Cell(status: .unsupported, note: "Needs on-device access, which is unsupported on iOS 26.x."),
                Cell(status: .unsupported, note: "Out of support range."),
            ],
            source: "docs/COMPATIBILITY_ZH-CN.md §1, §2.1"),
        SystemRow(
            feature: "Apple Intelligence staging",
            cells: [
                Cell(status: .conditional, note: "All four conditions must hold (hardware, system, region, Apple services); not verified on a real device with this build."),
                Cell(status: .unsupported, note: "Needs on-device access, which is unsupported on iOS 26.x."),
                Cell(status: .unsupported, note: "Out of support range."),
            ],
            source: "docs/COMPATIBILITY_ZH-CN.md §2.2"),
        SystemRow(
            feature: "Launch-image apply",
            cells: [
                Cell(status: .supported, note: "Writes into the target app container through the sandbox escape."),
                Cell(status: .unverified, note: "Container access through the escape is verified only on iOS 27.x."),
                Cell(status: .unverified, note: "Container access through the escape is verified only on iOS 27.x."),
            ],
            source: "docs/COMPATIBILITY_ZH-CN.md §1; LaunchArtworkDirectory"),
        SystemRow(
            feature: "Dialer skin",
            cells: [
                Cell(status: .supported, note: "Same container mechanism as launch images."),
                Cell(status: .unverified, note: "Container access through the escape is verified only on iOS 27.x."),
                Cell(status: .unverified, note: "Container access through the escape is verified only on iOS 27.x."),
            ],
            source: "docs/COMPATIBILITY_ZH-CN.md §1; DialerSkin"),
        SystemRow(
            feature: "Voice memo export (read-only)",
            cells: [
                Cell(status: .supported, note: "Reads the Voice Memos container through the app group."),
                Cell(status: .unverified, note: "Container access through the escape is verified only on iOS 27.x."),
                Cell(status: .unverified, note: "Container access through the escape is verified only on iOS 27.x."),
            ],
            source: "docs/COMPATIBILITY_ZH-CN.md §1; VoiceMemoExport"),
        SystemRow(
            feature: "Safari bookmarks export (read-only)",
            cells: [
                Cell(status: .supported, note: "Reads Safari bookmarks through the app group."),
                Cell(status: .unverified, note: "Container access through the escape is verified only on iOS 27.x."),
                Cell(status: .unverified, note: "Container access through the escape is verified only on iOS 27.x."),
            ],
            source: "docs/COMPATIBILITY_ZH-CN.md §1; SafariBookmarksExport"),
        SystemRow(
            feature: "Model cache probe (read-only)",
            cells: [
                Cell(status: .supported, note: "Reports only the model caches it actually finds."),
                Cell(status: .unverified, note: "Container access through the escape is verified only on iOS 27.x."),
                Cell(status: .unverified, note: "Container access through the escape is verified only on iOS 27.x."),
            ],
            source: "docs/COMPATIBILITY_ZH-CN.md §1; ModelCacheProbe"),
        SystemRow(
            feature: "SiriHub guard (live probe)",
            cells: [
                Cell(status: .supported, note: "Reads the live DeviceSupportsSiriHub answer."),
                Cell(status: .unverified, note: "Live probe verified only on iOS 27.x."),
                Cell(status: .unverified, note: "Live probe verified only on iOS 27.x."),
            ],
            source: "docs/COMPATIBILITY_ZH-CN.md §1; SiriHubGuard"),
    ]

    /// Device class × feature. Sources cite the doc or the code
    /// that establishes the device condition.
    static let deviceRows: [DeviceRow] = [
        DeviceRow(
            device: "iPhone Air, iPhone 18 series (eUICC)",
            feature: "Add eSIM",
            status: .conditional,
            note: "Can be attempted; activation still follows carrier and Apple rules.",
            source: "docs/COMPATIBILITY_ZH-CN.md §2.1"),
        DeviceRow(
            device: "Early dual physical SIM, no eUICC",
            feature: "Add eSIM",
            status: .unsupported,
            note: "Software cannot add an eSIM chip. The switch only unlocks FaceTime audio and AI region access.",
            source: "docs/COMPATIBILITY_ZH-CN.md §2.1"),
        DeviceRow(
            device: "iPhone 18 Pro / Pro Max (dual physical + eSIM)",
            feature: "Add eSIM",
            status: .conditional,
            note: "With both SIM trays occupied the baseband may hide “Add eSIM”. Remove the tray, apply the unlock, cold-restart, add the eSIM, then reinsert the cards.",
            source: "docs/COMPATIBILITY_ZH-CN.md §2.1"),
        DeviceRow(
            device: "Native Apple Intelligence hardware",
            feature: "Apple Intelligence",
            status: .conditional,
            note: "Native baseline: Personal Translator slot #266 = true, Audio Intelligence slot #178 = false. Forcing the Audio Intelligence slot can break photo cleanup / expand / reframe. All four conditions (§2.2) must hold.",
            source: "docs/COMPATIBILITY_ZH-CN.md §2.2; DeviceAIEligibility"),
        DeviceRow(
            device: "Four-microphone models (iPhone 17,1–5, iPhone 18,1/2/3/5)",
            feature: "Spatial audio recording",
            status: .supported,
            note: "Verified model list from Erosion-CN.",
            source: "Erosion-CN GestaltHelpers.fourMicPhones; LilaIntelligence.spatialAudioScope"),
        DeviceRow(
            device: "Three-microphone models (incl. iPhone Air, iPhone18,4)",
            feature: "Spatial audio recording",
            status: .conditional,
            note: "Not in the verified four-mic list. Enabling it can break the Voice Memos Studio recording mode. Reversible: turn it off, apply, restart.",
            source: "Erosion-CN GestaltHelpers.fourMicPhones; LilaIntelligence.spatialAudioScope"),
        DeviceRow(
            device: "iPad",
            feature: "iPad presets (Stage Manager, app compatibility)",
            status: .supported,
            note: "iPad presets only make sense on iPad.",
            source: "docs/COMPATIBILITY_ZH-CN.md §2.3"),
        DeviceRow(
            device: "iPhone",
            feature: "iPad presets (Stage Manager, app compatibility)",
            status: .unsupported,
            note: "“Unsupported” on iPhone is normal.",
            source: "docs/COMPATIBILITY_ZH-CN.md §2.3"),
        DeviceRow(
            device: "Any model",
            feature: "Change ProductType",
            status: .unsupported,
            note: "Never change the model identifier. Forcing a China board (e.g. iPhone19,7) to a US model breaks baseband checks and the eSIM menu disappears entirely.",
            source: "docs/COMPATIBILITY_ZH-CN.md §5"),
    ]

    /// Install methods and their requirements.
    static let installRows: [InstallRow] = [
        InstallRow(
            method: "LiveContainer",
            requirement: "iOS 27.x device (on-device access)",
            note: "No re-signing; installing the container itself may need one sideload.",
            source: "docs/COMPATIBILITY_ZH-CN.md §3"),
        InstallRow(
            method: "AltStore / SideStore / Sideloadly",
            requirement: "Personal Apple ID",
            note: "Free-account certificates last 7 days and need refreshing; re-signing must keep the share extension and shared App Group.",
            source: "docs/COMPATIBILITY_ZH-CN.md §3"),
        InstallRow(
            method: "Paid developer certificate / Xcode",
            requirement: "Apple Developer Program account",
            note: "The provisioning profile must include the App Group.",
            source: "docs/COMPATIBILITY_ZH-CN.md §3"),
    ]
}
