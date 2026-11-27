// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// The unified MobileGestalt key database (Stage 4, ADR-2-07).
///
/// Base table: MGKeys (PoomSmart, MIT, master `db9cf77f`, iOS 27.2
/// baseline) — the used-keys subset only (77 records in
/// `MGDatabaseSeed`). The separate read-only reference does not feed this editor database.
/// Every record carries the 14 task-book fields (§3.2) plus the two
/// Stage 1 additions (`readableViaMGCopyAnswer`, `slot`).
/// Verification is evidence-gated: only the two AdvAI slot keys
/// carry `verifiedByUpstreamProbe` (Erosion-CN live probe); every
/// other record is `unverified` until real evidence exists.
enum MGDatabase {
    /// DB version: the MGKeys baseline iOS version plus the
    /// LilaShift revision of this table. A new iOS key table must
    /// go through the offline `discover-version.sh` flow and bump
    /// `lilashiftRevision` — the 27.2 table must never be presented
    /// as a 27.3 table.
    static let version = MGDatabaseVersion(mgkeysBaseline: "27.2", lilashiftRevision: 1)

    /// All records, sorted by readable name. Built once: the seed
    /// is static data, so the result never changes.
    static let all: [MGKeyRecord] = MGDatabaseSeed.records.sorted {
        $0.readableName.localizedCaseInsensitiveCompare($1.readableName) == .orderedAscending
    }

    /// The record for an obfuscated key, or `nil` when the key is
    /// not in the used-keys subset. A missing record is "not in the
    /// database", never a guessed record. The lookup also accepts a
    /// readable name: the parallax key is staged by its readable
    /// name (`UIParallaxCapability`), not its MG hash.
    static func record(forKey key: String) -> MGKeyRecord? {
        all.first { $0.obfuscatedName == key } ?? all.first { $0.readableName == key }
    }

    /// The record for a readable key name, or `nil` when unknown.
    static func record(forReadableName readableName: String) -> MGKeyRecord? {
        all.first { $0.readableName == readableName }
    }

    /// Records in one category, in database order.
    static func records(in category: MGKeyCategory) -> [MGKeyRecord] {
        all.filter { $0.category == category }
    }

    /// Records whose iOS range covers `version` (e.g. "27.0.1").
    static func keysAvailable(onIOS version: String) -> [MGKeyRecord] {
        all.filter { $0.iosScope.contains(version) }
    }

    /// Records matching a search string (readable name, key ID or
    /// obfuscated key). Whitespace is ignored on both sides, so
    /// typing a camelCase feature name such as "DynamicIsland"
    /// finds the "DeviceSupportsDynamicIsland" row.
    static func search(_ query: String) -> [MGKeyRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        let squashed = trimmed.lowercased().filter { !$0.isWhitespace }
        return all.filter {
            let name = $0.readableName.lowercased().filter { !$0.isWhitespace }
            let key = $0.obfuscatedName.lowercased().filter { !$0.isWhitespace }
            return name.contains(squashed) || key.contains(squashed)
        }
    }
}

/// The database version: the MGKeys baseline plus our revision.
struct MGDatabaseVersion: Equatable, Sendable {
    /// The MGKeys baseline iOS version this table was built from.
    let mgkeysBaseline: String
    /// LilaShift revision of the table (bumps on any seed change).
    let lilashiftRevision: Int
}

/// One MobileGestalt value. `nil` at the call site means "absent";
/// there is no `.absent` case — absence is the Optional, never a
/// guessed default.
enum MGValue: Equatable, Sendable {
    case bool(Bool)
    case string(String)
    case int(Int)
    case data(Data)
    indirect case array([MGValue])
    indirect case dictionary([String: MGValue])

    /// Converts a plist value, or `nil` when the value has no
    /// `MGValue` representation (real, date). Integer conversion
    /// uses `intValue`, matching the flag values (0/1) this layer
    /// classifies; it is not a general 64-bit integer transport.
    static func fromPlistValue(_ value: Any?) -> MGValue? {
        guard let value else { return nil }
        switch PlistValueKind.detect(value) {
        case .boolean: return .bool((value as? NSNumber)?.boolValue ?? false)
        case .integer: return .int((value as? NSNumber)?.intValue ?? 0)
        case .string: return .string(value as? String ?? String(describing: value))
        case .data: return (value as? Data).map(MGValue.data)
        case .array:
            guard let array = value as? [Any] else { return nil }
            return .array(array.compactMap(MGValue.fromPlistValue))
        case .dictionary:
            guard let dict = value as? [String: Any] else { return nil }
            var result: [String: MGValue] = [:]
            for (key, element) in dict {
                guard let converted = MGValue.fromPlistValue(element) else { return nil }
                result[key] = converted
            }
            return .dictionary(result)
        case .real, .date: return nil
        }
    }

    /// Display text for a value, in the app's standard plist style.
    var displayText: String {
        switch self {
        case .bool(let value): return value ? "true" : "false"
        case .int(let value): return String(value)
        case .string(let value): return value
        case .data(let value): return value.base64EncodedString()
        case .array(let values): return "[" + values.map(\.displayText).joined(separator: ", ") + "]"
        case .dictionary(let values):
            return "{" + values.keys.sorted().map { "\($0): \(values[$0]?.displayText ?? "")" }.joined(separator: ", ") + "}"
        }
    }
}

/// The data type of a MobileGestalt key's value.
enum MGValueType: String, Equatable, Sendable {
    case bool, string, int, data, array, dictionary
}

/// Which devices a key applies to.
enum DeviceScope: Equatable, Sendable {
    case all
    case iphoneOnly
    case ipadOnly
    case specific([String])

    /// Whether `productType` (e.g. "iPhone18,4") is in scope.
    func contains(productType: String) -> Bool {
        switch self {
        case .all: return true
        case .iphoneOnly: return productType.hasPrefix("iPhone")
        case .ipadOnly: return productType.hasPrefix("iPad")
        case .specific(let types): return types.contains(productType)
        }
    }
}

/// The iOS versions a key exists in, from MGKeys `keys_versions.py`.
/// `introduced` is the version the key first appeared in; `removed`
/// the version it was removed in (`nil` = never recorded removed);
/// `reintroduced` the versions it came back in. A `nil` introduced
/// means the key is not in the MGKeys 27.2 baseline at all.
struct IOSVersionRange: Equatable, Sendable {
    let introduced: String?
    let removed: String?
    let reintroduced: [String]

    /// Whether `version` (e.g. "27.0.1") is covered: at or after the
    /// introduction, and not inside a removed gap. A key with no
    /// recorded introduction covers nothing — an unrecorded key is
    /// never assumed present.
    func contains(_ version: String) -> Bool {
        guard let introduced, IOSVersionRange.compare(version, introduced) != .orderedAscending else { return false }
        if let removed, IOSVersionRange.compare(version, removed) != .orderedAscending,
           !reintroduced.contains(where: { IOSVersionRange.compare(version, $0) != .orderedAscending }) {
            return false
        }
        return true
    }

    /// Numeric dotted-version comparison ("27.0.1" < "27.2").
    /// Non-numeric segments compare as 0; this is a display/version
    /// helper, not a build-number comparison (builds go through
    /// `VersionSentinel`, ADR-2-09).
    static func compare(_ left: String, _ right: String) -> ComparisonResult {
        let leftParts = left.split(separator: ".").map { Int($0) ?? 0 }
        let rightParts = right.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(leftParts.count, rightParts.count) {
            let leftValue = index < leftParts.count ? leftParts[index] : 0
            let rightValue = index < rightParts.count ? rightParts[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }
}

/// Capability category, aligned with `CapabilityCategory`.
enum MGKeyCategory: String, CaseIterable, Equatable, Sendable {
    case display, device, ipad, intelligence, advanced
}

/// Risk of writing the key wrong: `high` = may break Face ID or a
/// system function, `medium` = needs a warning, `low` = reversible
/// capability flag.
enum RiskLevel: String, Equatable, Sendable {
    case low, medium, high
}

/// Verification status. Only the two evidence-carrying cases count
/// as verified; `unverified` is the default and must be shown as
/// such in the UI, never as a pass.
enum VerificationStatus: Equatable, Sendable {
    /// Verified by a live-device probe in this app (needs device +
    /// system version + date recorded with the evidence).
    case verifiedOnDevice
    /// Verified by an upstream live-device probe (the citation is
    /// recorded with the record, e.g. in `slot.baselineEvidence`).
    case verifiedByUpstreamProbe
    /// Not verified — shown as unverified, never as a pass.
    case unverified
    /// The key has no verification concept (a purely informational
    /// record). Not used by the seed today.
    case notApplicable
}

/// A CacheData slot: the slot number is a per-device observation
/// from a probe, never a layout constant. `nativeBaseline` is the
/// probed native value (`nil` = unknown, and callers must fail
/// closed on it); `baselineEvidence` is the citation.
struct CacheDataSlotInfo: Equatable, Sendable {
    let slotNumber: Int
    let nativeBaseline: Bool?
    let baselineEvidence: String?
}

/// One key in the unified database: the 14 task-book fields (§3.2)
/// plus the two Stage 1 additions (`readableViaMGCopyAnswer`,
/// `slot`). "Original key name" and "readable key name" are the same
/// field in MGKeys terms (the de-obfuscated name), so the record
/// carries `readableName` + `obfuscatedName` and no ambiguous
/// `originalName`.
struct MGKeyRecord: Equatable, Sendable {
    /// Stable ID: the readable key name (e.g.
    /// "DeviceSupportsAppleIntelligence").
    let keyID: String
    /// Readable key name (same as `keyID`, unless an alias exists).
    let readableName: String
    /// Obfuscated MobileGestalt key string (the MG hash).
    let obfuscatedName: String
    let dataType: MGValueType
    /// Native default value — filled only with probe evidence,
    /// otherwise `nil` (never a guess).
    let defaultValue: MGValue?
    let deviceScope: DeviceScope
    let iosScope: IOSVersionRange
    let category: MGKeyCategory
    let riskLevel: RiskLevel
    /// E.g. "MGKeys mapping-gestalt.h (MIT)" /
    /// "Erosion-CN MGCacheLayout.swift:41 (GPL-3.0-only)".
    let upstreamSource: String
    /// SPDX identifier, e.g. "MIT" / "GPL-3.0-only".
    let license: String
    /// Whether the key may be written (CacheExtra keys: true).
    let writable: Bool
    /// Whether the key can be restored (true only when an original
    /// value is recorded for it).
    let restorable: Bool
    let verificationStatus: VerificationStatus
    /// `false` for `// non-gestalt-key` entries (IODeviceTree query
    /// keys, not readable via `MGCopyAnswer`).
    let readableViaMGCopyAnswer: Bool
    /// Set only when the key is a CacheData slot.
    let slot: CacheDataSlotInfo?
}
