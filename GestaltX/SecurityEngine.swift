// SPDX-License-Identifier: GPL-3.0-only
// Write security engine (Stage 5, §3.4 / ADR-2-05): the gate every
// device write passes through, inside `GestaltFileStore.commit`
// (the write choke point). Two rules, both fail-closed:
//
// 1. Allowlist — the apply path may only change keys a feature
//    stages. The list is computed from the capability catalog plus
//    the named special keys (region, model number, model-name
//    display keys, artwork), so a new capability extends it and a
//    key no feature stages never writes. Device-identity keys are
//    deliberately NOT on the allowlist: they are checked separately
//    by `commit` itself and are only writable by the hardware-
//    identity restore path, which does not go through this gate.
// 2. Pre-write backup — a write never proceeds without a fresh
//    backup covering the pre-write bytes. When AppCore supplies a
//    pre-write record, `requirePreWriteBackup` verifies it covers
//    the current bytes (byte count and SHA-256; a record with no
//    digest cannot prove coverage and is rejected). When none is
//    supplied, `commit` creates the backup itself — the rule holds
//    by construction on that path too.
//
// No plaintext UDID/serial storage: this engine stores no device
// identifiers at all. Backup records carry the random installation
// ID (`BackupRecord.deviceID`), never the UDID; the device
// fingerprint stores only the SHA-256 of the UDID (Stage 5, R-4).
// The backup plist files themselves are verbatim copies of the
// device's own MobileGestalt file — they contain its UDID/serial
// because a restore writes the whole file back — and live only in
// the app sandbox; that is a deliberate, documented exception, not
// a second identifier store.
//
// System Settings writes do NOT pass through this engine
// (Stage 13): they touch no `GestaltDocument` and no CacheExtra
// key — the lock-screen text is a plain `String` (`LockScreenFootnote`)
// in a configuration-profiles plist. Their equivalent gate lives
// in `SystemSettingsStore.apply` (stale-snapshot check, single-line
// ≤ 256 validation, verified pre-write backup, verified journal,
// read-back verification, rollback). Do not "fix" the bypass by
// adding `LockScreenFootnote` to the CacheExtra allowlist: the
// allowlist is defined as every CacheExtra key the app may write,
// and this key is not one. The same applies to file writes that
// go through `GXCustomizationAccess.acquirePath` (launch images,
// wallpapers, notification sounds): their gate is the per-app
// writer lock plus sibling-`.bak` backup and pinning, documented
// where those stores live.
import Foundation

enum SecurityEngine {
    /// The two model-name display keys the preview writes directly
    /// (Settings > General > About shows the model name from
    /// these); they belong to no Capability, so they are named here
    /// rather than silently dropped from the allowlist.
    static let modelNameKey1 = "Z/dqyWS6OZTRy10UcmUAhw"
    static let modelNameKey2 = "bbtR9jQx50Fv5Af/affNtA"

    /// The nested artwork keys the preview writes (via `setArtwork`).
    static let artworkKeys: Set<String> = ["ArtworkDeviceProductDescription", "ArtworkDeviceSubType"]

    /// Every CacheExtra key the app may write, plus the artwork
    /// container key itself. Computed from the capability catalog
    /// plus the named special keys.
    static var writeAllowlist: Set<String> {
        var keys = Set(Capability.all.flatMap(\.keys))
        keys.formUnion([GestaltKeys.regionCode, GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo,
                        GestaltKeys.modelNumber, GestaltKeys.artwork,
                        modelNameKey1, modelNameKey2])
        return keys
    }

    /// The apply-path gate: throws unless every CacheExtra key that
    /// changed between `expected` and `edited` is allowlisted, every
    /// changed nested artwork key is allowlisted, and every changed
    /// CacheData slot/flag is one the app stages (the byte-level
    /// CacheData check itself lives in
    /// `DeviceCacheOptions.validateEdit`, which `commit` calls just
    /// before this gate — this gate only names the slots so a
    /// changed slot is never an unlisted surprise). Restore paths
    /// (whole-file replacement) do not go through this gate: their
    /// checks are device identity, layout validation and integrity,
    /// enforced by `commit` and `RestoreEngine`.
    static func authorizeWrite(from expected: GestaltDocument, to edited: GestaltDocument) throws {
        let changedExtra = changedKeys(from: expected.extra, to: edited.extra)
        let disallowed = changedExtra.subtracting(writeAllowlist)
        guard disallowed.isEmpty else {
            throw GestaltFailure("This change writes keys the app does not stage: \(disallowed.sorted().joined(separator: ", ")). No system changes were made.")
        }
        let changedArtwork = changedKeys(from: expected.artwork, to: edited.artwork)
        let disallowedArtwork = changedArtwork.subtracting(artworkKeys)
        guard disallowedArtwork.isEmpty else {
            throw GestaltFailure("This change writes artwork keys the app does not stage: \(disallowedArtwork.sorted().joined(separator: ", ")). No system changes were made.")
        }
        // CacheData slots/flags: the byte-level allowlist is
        // validateEdit's job, but a slot that changed here without
        // resolving on both sides is a layout surprise, not a
        // staged edit — fail closed rather than writing blind.
        for key in [DeviceCacheOptions.audioIntelligenceKey, DeviceCacheOptions.personalTranslatorKey] {
            let before = DeviceCacheOptions.advAISlotValue(key, in: expected)
            let after = DeviceCacheOptions.advAISlotValue(key, in: edited)
            if (before == nil) != (after == nil) {
                throw GestaltFailure("The cache layout changed under this edit. No system changes were made.")
            }
        }
    }

    /// The pre-write backup rule for a supplied record: throws
    /// unless the record covers `current` exactly (byte count and
    /// SHA-256). A record with no digest cannot prove coverage and
    /// is rejected — a legacy backup is never silently treated as
    /// the pre-write proof. A `nil` record is not an error here:
    /// `commit` creates the backup itself in that case.
    static func requirePreWriteBackup(_ record: BackupRecord?, covering current: Data) throws {
        guard let record else { return }
        guard let digest = record.sha256, !digest.isEmpty else {
            throw GestaltFailure("The pre-write backup has no recorded digest, so it cannot prove it covers the current device state. No system changes were made.")
        }
        guard record.byteCount == current.count,
              digest == BackupEngine.sha256Hex(of: current) else {
            throw GestaltFailure("The pre-write backup does not match the current device state. No system changes were made.")
        }
    }

    /// The keys whose values differ between two plist dictionaries
    /// (added, removed, or changed). Values are compared with
    /// `NSObject.isEqual`, which is how plist values compare.
    static func changedKeys(from before: [String: Any], to after: [String: Any]) -> Set<String> {
        var changed = Set<String>()
        for key in Set(before.keys).union(after.keys) {
            let old = before[key]
            let new = after[key]
            switch (old, new) {
            case (nil, nil):
                break
            case (nil, _), (_, nil):
                changed.insert(key)
            case let (x as NSObject, y as NSObject):
                if !x.isEqual(y) { changed.insert(key) }
            case let (x?, y?):
                if String(describing: x) != String(describing: y) { changed.insert(key) }
            }
        }
        return changed
    }
}
