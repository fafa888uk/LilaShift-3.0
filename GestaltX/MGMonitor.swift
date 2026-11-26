// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The iOS version sentinel (ADR-2-09): the iOS 27.3 beta 2 build
/// (24C5049d) is the first build where Apple blocked worse_query.
/// On blocked builds every monitor read reports "not granted on this
/// iOS version" with stay/downgrade guidance — never an empty list,
/// never a silent failure.
enum VersionSentinelState: Equatable, Sendable {
    /// This build grants the mechanism.
    case supported
    /// This build blocks the mechanism.
    case blocked(build: String)
    /// The build could not be classified (unparsable, or unreadable).
    /// Unknown is never assumed supported.
    case unknownBuild(build: String)
}

enum VersionSentinel {
    /// The first build where Apple blocked worse_query (iOS 27.3
    /// beta 2). The structured twin `blockedFrom` must match it.
    static let blockedFromBuild = "24C5049d"

    /// Classifies a build string such as "24C5049d". `nil` (no build
    /// readable) is `.unknownBuild` — never assumed supported. Other
    /// trains fall through the same total order: an older train is
    /// supported, a newer train is blocked fail-closed until the
    /// threshold is reviewed (Stage 6 combines this with the
    /// version-based support ranges).
    static func state(forBuild build: String?) -> VersionSentinelState {
        guard let build, !build.isEmpty else { return .unknownBuild(build: "") }
        guard let parsed = parse(build) else { return .unknownBuild(build: build) }
        return parsed >= blockedFrom ? .blocked(build: build) : .supported
    }

    /// Stay/downgrade guidance for a blocked or unknown build:
    /// stay on iOS 27.2.1 or below, or downgrade to 27.2.1 while
    /// Apple still signs it; never upgrade past 27.3 beta 1. `nil`
    /// for supported builds.
    static func guidance(for state: VersionSentinelState) -> String? {
        switch state {
        case .supported: return nil
        case .blocked:
            return L("This iOS version blocks the mechanism. Stay on iOS 27.2.1 or below, or downgrade to 27.2.1 while Apple still signs it. Do not upgrade.")
        case .unknownBuild:
            return L("The iOS build could not be confirmed, so the monitor cannot tell whether the mechanism is granted on this version.")
        }
    }

    /// The highest iOS version the mechanism is known to work on:
    /// 27.3 beta 1 — the build just before `blockedFromBuild`.
    static let supportedThroughLabel = "iOS 27.3 beta 1"

    /// Why a build is blocked: at or past the known threshold, or
    /// from a newer train whose threshold has not been reviewed
    /// (blocked fail-closed, not known-blocked).
    enum BlockReason: Equatable, Sendable {
        case atOrPastThreshold
        case newerTrainUnreviewed
    }

    /// The block reason for a build, or `nil` when the build is not
    /// blocked (supported or unknown). A newer train (a major number
    /// above the threshold's) is blocked fail-closed until the
    /// threshold is reviewed — it is not claimed to be a known block.
    static func blockReason(forBuild build: String?) -> BlockReason? {
        guard let build, let parsed = parse(build), parsed >= blockedFrom else { return nil }
        return parsed.major > blockedFrom.major ? .newerTrainUnreviewed : .atOrPastThreshold
    }

    /// The honest supported range, as named in diagnostics reports.
    /// The range is build-based, not version-based: every build older
    /// than `blockedFromBuild` (through 27.3 beta 1) is supported;
    /// builds from 24C5049d on are blocked; newer trains are blocked
    /// fail-closed until the threshold is reviewed. Older trains
    /// (for example 23x, iOS 26 and earlier) classify supported by
    /// the same total order — the range statement says so, rather
    /// than naming a lower bound that was never verified.
    static func supportedRangeDescription(for state: VersionSentinelState) -> String {
        let range = L("Supported: iOS 27.3 beta 1 and earlier (builds before 24C5049d).")
        switch state {
        case .supported:
            return range + " " + L("Builds from 24C5049d on are blocked; newer trains are blocked until the threshold is reviewed.")
        case .blocked(let build):
            switch blockReason(forBuild: build) {
            case .newerTrainUnreviewed:
                return String(format: L("Build %@: blocked fail-closed — it is from a newer train than the reviewed threshold (24C5049d, iOS 27.3 beta 2), and support for this train has not been reviewed. %@"), build, range)
            case .atOrPastThreshold, nil:
                return String(format: L("Build %@: blocked — it is at or past 24C5049d (iOS 27.3 beta 2), where Apple blocked the mechanism. %@"), build, range)
            }
        case .unknownBuild:
            return L("The supported range could not be confirmed for this build.") + " " + range
        }
    }

    /// The structured twin of `blockedFromBuild`.
    private static let blockedFrom = Build(major: 24, letter: "C", number: 5049, suffix: "d")

    /// Parses "24C5049d" into its parts, or `nil` when the string is
    /// not an Apple build number.
    static func parse(_ build: String) -> Build? {
        var major = ""
        var letter: Character?
        var number = ""
        var suffix = ""
        var stage = 0 // 0 major digits, 1 letter, 2 number digits, 3 seed letter
        for character in build {
            switch stage {
            case 0:
                if character.isNumber { major.append(character) }
                else if character.isUppercase && character.isASCII { letter = character; stage = 1 }
                else { return nil }
            case 1:
                if character.isNumber { number.append(character); stage = 2 }
                else { return nil }
            case 2:
                if character.isNumber { number.append(character) }
                else if character.isLowercase && character.isASCII { suffix.append(character); stage = 3 }
                else { return nil }
            default: return nil
            }
        }
        guard stage == 2 || stage == 3, let letter, !major.isEmpty, !number.isEmpty,
              let majorValue = Int(major), let numberValue = Int(number) else { return nil }
        return Build(major: majorValue, letter: letter, number: numberValue, suffix: suffix)
    }

    /// One Apple build number, comparable in the order Apple ships
    /// them: major train, then letter, then number, then seed letter.
    struct Build: Comparable, Equatable, Sendable {
        let major: Int
        let letter: Character
        let number: Int
        let suffix: String

        static func < (lhs: Build, rhs: Build) -> Bool {
            if lhs.major != rhs.major { return lhs.major < rhs.major }
            if lhs.letter != rhs.letter { return lhs.letter < rhs.letter }
            if lhs.number != rhs.number { return lhs.number < rhs.number }
            return lhs.suffixRank < rhs.suffixRank
        }

        /// A bare build number (no seed letter) ranks after all its
        /// seeds: it is the finalized build of that number, and a
        /// finalized build of a blocked beta stays blocked.
        var suffixRank: Int {
            guard let scalar = suffix.unicodeScalars.first else { return 26 }
            return Int(scalar.value) - 97 // "a" == 97
        }
    }
}

/// A CacheData slot probe for one key: the layout-resolved slot
/// number (a per-device observation, never a layout constant) and
/// the slot byte at each source. `nil` bytes mean "the slot did not
/// resolve on that document", never a guessed value.
struct MGSlotProbe: Equatable, Sendable {
    let slotNumber: Int
    /// The slot byte in the first-read document.
    let originalByte: Bool?
    /// The slot byte in the staged document.
    let stagedByte: Bool?
    /// The live MGCopyAnswer answer for the key.
    let liveAnswer: Bool?
    /// The record's native baseline, when known (`nil` = unknown,
    /// and callers must fail closed on it).
    let nativeBaseline: Bool?

    /// Whether the live answer disagrees with the native baseline.
    /// `nil` when either is unknown — unknown is not a disagreement.
    var disagreesWithNativeBaseline: Bool? {
        guard let liveAnswer, let nativeBaseline else { return nil }
        return liveAnswer != nativeBaseline
    }
}

/// One monitored key: the three sources side by side, as in
/// Erosion-CN's MGInspectorView (GPL-3.0 reference only — the
/// three-source layout is the model, the code is LilaShift's own).
/// The three sources are the first-read (original) value, the
/// staged (working-document) value, and the live MGCopyAnswer value.
struct MGMonitorRow: Equatable, Sendable {
    let record: MGKeyRecord
    /// First-read (backup) value. `nil` = the key was absent at first read.
    let original: MGValue?
    /// Working-document (staged) value. `nil` = absent from the staged document.
    let staged: MGValue?
    /// Live MGCopyAnswer value. `nil` = the live probe returned nothing.
    let live: MGValue?
    /// When the live value was read.
    let liveReadAt: Date?
    /// The slot probe for CacheData keys (`nil` for CacheExtra-only keys).
    let slot: MGSlotProbe?
    let compatibility: CompatibilityStatus
    let compatibilityReason: String
    /// Whether `liveReadAt` is older than `MGMonitor.staleAfter`.
    let isStale: Bool

    /// Whether the sources disagree: a staged change, a staged
    /// deletion, or the live answer differing from the staged value.
    /// An absent live value is "unreadable", not a difference, and an
    /// absent original is "not recorded", not a difference.
    var hasDifference: Bool {
        if let original, let staged, original != staged { return true }
        if original != nil, staged == nil { return true }
        if let staged, let live, staged != live { return true }
        if let slot, let liveAnswer = slot.liveAnswer, let stagedByte = slot.stagedByte,
           liveAnswer != stagedByte { return true }
        return false
    }
}

/// Inputs to one monitor row. Pure data: the engine never reads the
/// device, the file system or the live probe itself — the caller
/// (GestaltManager) supplies the three sources.
struct MGMonitorInput: Sendable {
    let record: MGKeyRecord
    let original: MGValue?
    let staged: MGValue?
    let live: MGValue?
    let liveReadAt: Date?
    let slot: MGSlotProbe?
    let productType: String?
    let iosVersion: String
    let sentinel: VersionSentinelState
}

/// The monitor engine: pure three-source comparison plus the
/// per-key compatibility badge. No I/O, no timers — the monitor
/// refreshes on demand only (no timer polls the device).
enum MGMonitor {
    /// Live values older than this are shown as stale. A chosen UX
    /// value, not a measured threshold.
    static let staleAfter: TimeInterval = 300

    static func row(for input: MGMonitorInput, now: Date = Date()) -> MGMonitorRow {
        let (status, reason) = MGKeyCompatibility.evaluate(
            record: input.record, productType: input.productType,
            iosVersion: input.iosVersion, live: input.live, sentinel: input.sentinel)
        let isStale: Bool = {
            guard let liveReadAt = input.liveReadAt else { return false }
            return now.timeIntervalSince(liveReadAt) > staleAfter
        }()
        return MGMonitorRow(record: input.record, original: input.original, staged: input.staged,
                            live: input.live, liveReadAt: input.liveReadAt, slot: input.slot,
                            compatibility: status, compatibilityReason: reason, isStale: isStale)
    }

    static func rows(for inputs: [MGMonitorInput], now: Date = Date()) -> [MGMonitorRow] {
        inputs.map { row(for: $0, now: now) }
    }
}
