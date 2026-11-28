// SPDX-License-Identifier: GPL-3.0-only
// IPA Audit — firmware CVE exposure radar (W3).
//
// The 13-entry radar from Kianuni/WQGuard v1.3.6
// (`Sources/WQGuardCore/Engine/FirmwarePostureEngine.swift`,
// MIT, Copyright (c) 2026 WQGuard Contributors) — see
// W3NOTICES.md — re-checked entry by entry against the NVD API
// 2.0 and Apple security advisories on 2026-11-28. The upstream
// README's CVSS scores and fix versions were WRONG for most
// entries (see `records/w3-wqguard.md` for the full table): this
// file stores the NVD-verified score and fixed versions, keeps
// the upstream claim beside it for auditability, and marks every
// entry with a verification status. Anything that could not be
// verified is stored as `nil` / `.unverified` and shown as
// "未核实" — never as the README's number.
//
// Exposure evaluation is conservative: a branch (iOS 26.x /
// 27.x) without a verified fixed version evaluates to `.unknown`,
// never to "patched". A device is only called patched for a CVE
// when NVD or an Apple advisory names the fixed version for that
// branch.
import Foundation

/// How far official sources confirm an entry.
enum IPAAuditVerification: String, Equatable, Codable, Sendable {
    /// CVE number, CVSS score, fixed versions and impact all
    /// match NVD and/or an Apple advisory.
    case verified
    /// The CVE exists in NVD, but at least one upstream claim
    /// (score, fix version, component label or an ID in a range)
    /// does not match the official record. See `verificationNote`.
    case partiallyVerified
    /// No NVD record exists for the ID (or no CVE number exists
    /// at all). Nothing about this entry is treated as verified.
    case unverified

    var title: String {
        switch self {
        case .verified: return L("Verified")
        case .partiallyVerified: return L("Partially verified")
        case .unverified: return L("Unverified")
        }
    }
}

/// Exposure of one device OS version to one CVE entry.
enum IPAAuditExposure: String, Equatable, Codable, Sendable {
    /// The device version is below a verified fixed version.
    case exposed
    /// The device version is at or above a verified fixed version.
    case patched
    /// No verified fixed version exists for this device branch
    /// (or the entry itself is unverified): the radar cannot say.
    case unknown

    var title: String {
        switch self {
        case .exposed: return L("Exposed")
        case .patched: return L("Patched")
        case .unknown: return L("Unknown")
        }
    }
}

/// A simple major.minor.patch OS version with an optional beta
/// ordinal (for the worse_query 27.3 beta 2 boundary). Parsed
/// from strings such as "27.0.1" or "27.3 beta 2"; unparseable
/// input yields `nil` rather than a guessed version.
struct IPAAuditOSVersion: Equatable, Comparable, Codable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int
    /// Beta number for pre-release builds (`nil` for GA/RC).
    let beta: Int?

    init(major: Int, minor: Int, patch: Int = 0, beta: Int? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.beta = beta
    }

    init?(string: String) {
        let text = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.utf8.count <= 64 else { return nil }
        var beta: Int?
        let lower = text.lowercased()
        if let betaRange = lower.range(of: "beta") {
            let after = lower[betaRange.upperBound...].trimmingCharacters(in: .whitespaces)
            let digits = after.prefix(while: { $0.isNumber })
            beta = Int(digits)
        }
        // The numeric core starts at the first digit ("iOS 27.2"
        // and "27.3 beta 2" both parse); it ends at the first
        // character that is neither a digit nor a dot.
        guard let firstDigit = lower.firstIndex(where: { $0.isNumber }) else { return nil }
        var coreEnd = firstDigit
        while coreEnd < lower.endIndex, lower[coreEnd].isNumber || lower[coreEnd] == "." {
            coreEnd = lower.index(after: coreEnd)
        }
        let core = String(lower[firstDigit..<coreEnd])
        let parts = core.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 2, parts.count <= 3,
              parts.allSatisfy({ $0 >= 0 }) else { return nil }
        self.major = parts[0]
        self.minor = parts[1]
        self.patch = parts.count == 3 ? parts[2] : 0
        self.beta = beta
    }

    static func < (lhs: IPAAuditOSVersion, rhs: IPAAuditOSVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    var displayString: String {
        var text = "\(major).\(minor).\(patch)"
        if let beta { text += " beta \(beta)" }
        return text
    }
}

/// One radar entry. `verifiedCVSS` is the NVD CVSS 3.1 base
/// score; `nil` means no single verified score exists for the
/// entry (multi-ID entries disagree, or the entry is unverified).
struct IPAAuditCVEEntry: Equatable, Codable, Sendable {
    /// Display ID: a CVE number, a range, or "0day:…" / "PoC:…"
    /// when no CVE number exists.
    let id: String
    let title: String
    let subsystem: String
    let verifiedCVSS: Double?
    /// The score WQGuard's README / catalog claimed, kept for
    /// auditability. Never shown as the verified score.
    let upstreamClaimedCVSS: Double?
    /// Per-ID verified scores, for entries covering several CVE
    /// IDs (113960/1, 113964–70). Empty for single-ID entries.
    let verifiedCVSSByID: [String: Double]
    /// IDs in a claimed range with no NVD record at all
    /// (113966, 113967 as of 2026-11-28).
    let unverifiedIDs: [String]
    let verification: IPAAuditVerification
    /// What was checked, what matched, and what did not — in
    /// plain language, with the official source named.
    let verificationNote: String
    /// Fixed iOS versions, as verified ("iOS 26.7.2 / 27.2") or
    /// "未核实" when no official source names one.
    let fixedVersionNote: String
    /// Verified fixed version for the iOS 26 branch, if any.
    let patch26: IPAAuditOSVersion?
    /// Verified fixed version for the iOS 27 branch, if any.
    let patch27: IPAAuditOSVersion?
    /// Impact in the official source's own words (short).
    let impact: String
    /// Official sources (NVD API record, Apple advisory).
    let sources: [String]
}

/// The 13-entry radar. Verification date: 2026-11-28 (NVD API
/// 2.0 + Apple support advisories; full per-entry table in
/// `records/w3-wqguard.md`).
enum IPAAuditCVERadar {
    static let verificationDate = "2026-11-28"

    static let entries: [IPAAuditCVEEntry] = [
        IPAAuditCVEEntry(
            id: "0day:worse_query",
            title: "containermanagerd cross-sandbox token escape (worse_query / bad_query)",
            subsystem: "Darwin Sandbox / containermanagerd",
            verifiedCVSS: nil,
            upstreamClaimedCVSS: 8.8,
            verifiedCVSSByID: [:],
            unverifiedIDs: [],
            verification: .unverified,
            verificationNote: "No CVE number exists, so there is no NVD record to check. The 8.8 score and the iOS 27.3 fix version are upstream claims, not verified against NVD or an Apple advisory. The 27.3 beta 2 boundary used for exposure comes from LilaShift's own worse_query version sentinel, not from a CVE record.",
            fixedVersionNote: "未核实（CVE 记录不存在）；按 LilaShift 自身哨兵：iOS 27.3 beta 2+",
            patch26: nil,
            patch27: IPAAuditOSVersion(major: 27, minor: 3, patch: 0, beta: 2),
            impact: "An app may be able to escape its sandbox via containermanagerd (upstream description; not an NVD impact statement).",
            sources: []),
        IPAAuditCVEEntry(
            id: "CVE-2026-112676",
            title: "Photos private TCC prompt and access bypass",
            subsystem: "Photos / TCC Privacy",
            verifiedCVSS: 7.5,
            upstreamClaimedCVSS: 7.5,
            verifiedCVSSByID: [:],
            unverifiedIDs: [],
            verification: .verified,
            verificationNote: "NVD (Analyzed, CVSS 3.1 7.5 HIGH) and Apple advisory for iOS 26.7.2 / 27.2 both confirm the ID, score, impact (an app may access the Photos Library) and fixed versions. This is the only entry where the upstream score matches NVD exactly, together with CVE-2026-20700.",
            fixedVersionNote: "iOS 26.7.2 / 27.2",
            patch26: IPAAuditOSVersion(major: 26, minor: 7, patch: 2),
            patch27: IPAAuditOSVersion(major: 27, minor: 2, patch: 0),
            impact: "An app may be able to access a user's Photos Library.",
            sources: [
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-112676",
                "https://support.apple.com/en-us/149227",
            ]),
        IPAAuditCVEEntry(
            id: "CVE-2026-111497",
            title: "Brotli decoder heap out-of-bounds write",
            subsystem: "Brotli decoder library",
            verifiedCVSS: 9.8,
            upstreamClaimedCVSS: 9.2,
            verifiedCVSSByID: [:],
            unverifiedIDs: [],
            verification: .partiallyVerified,
            verificationNote: "NVD (Analyzed, CVSS 3.1 9.8 CRITICAL) confirms the ID and the Brotli decoder component, but the upstream score 9.2 is wrong and the upstream 'HTTP2Shell' name does not appear in the NVD record. Fixed in Brotli 1.0.10 / 1.1.1 / 1.2.1 per NVD; no iOS fixed version is named in the NVD record, so iOS exposure cannot be evaluated from the OS version.",
            fixedVersionNote: "未核实（iOS 修复版本）；Brotli 库修复于 1.2.1",
            patch26: nil,
            patch27: nil,
            impact: "A remote unauthenticated attacker may corrupt decoder memory, disclose memory contents, or execute arbitrary code with a crafted Brotli stream.",
            sources: [
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-111497",
            ]),
        IPAAuditCVEEntry(
            id: "CVE-2026-112611",
            title: "Malicious PDF memory corruption",
            subsystem: "PDF processing",
            verifiedCVSS: 6.1,
            upstreamClaimedCVSS: 8.8,
            verifiedCVSSByID: [:],
            unverifiedIDs: [],
            verification: .partiallyVerified,
            verificationNote: "NVD (Analyzed, CVSS 3.1 6.1 MEDIUM) and Apple advisory for iOS 26.7.2 confirm the ID, the PDF impact and the fixed versions, but the upstream score 8.8 is wrong. The 'CoreGraphics' component label is not named in the NVD description text retrieved, so the subsystem is stated as PDF processing only.",
            fixedVersionNote: "iOS 26.7.2 / 27.2",
            patch26: IPAAuditOSVersion(major: 26, minor: 7, patch: 2),
            patch27: IPAAuditOSVersion(major: 27, minor: 2, patch: 0),
            impact: "Processing a maliciously crafted PDF file may lead to memory corruption.",
            sources: [
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-112611",
                "https://support.apple.com/en-us/149227",
            ]),
        IPAAuditCVEEntry(
            id: "CVE-2026-86950",
            title: "Malicious file out-of-bounds write",
            subsystem: "File parsing",
            verifiedCVSS: 8.8,
            upstreamClaimedCVSS: 8.6,
            verifiedCVSSByID: [:],
            unverifiedIDs: [],
            verification: .partiallyVerified,
            verificationNote: "NVD (Analyzed, CVSS 3.1 8.8 HIGH) confirms the ID and the fixed versions iOS 18.7.11 / 26.7.1, but the upstream score 8.6 is wrong and no 'CoreGraphics' component is named in the NVD description. NVD notes Apple is aware of a report that this issue may have been exploited against targeted individuals on iOS before iOS 27.",
            fixedVersionNote: "iOS 18.7.11 / 26.7.1",
            patch26: IPAAuditOSVersion(major: 26, minor: 7, patch: 1),
            patch27: nil,
            impact: "Processing a maliciously crafted file may lead to arbitrary code execution.",
            sources: [
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-86950",
            ]),
        IPAAuditCVEEntry(
            id: "CVE-2026-113963",
            title: "App authorization bypass (sensitive user data)",
            subsystem: "App authorization",
            verifiedCVSS: 5.5,
            upstreamClaimedCVSS: 7.8,
            verifiedCVSSByID: [:],
            unverifiedIDs: [],
            verification: .partiallyVerified,
            verificationNote: "NVD (Awaiting Analysis, CVSS 3.1 5.5 MEDIUM) confirms the ID and the iOS 27.2.1 fix, but the upstream score 7.8 is wrong, the upstream 'App Intents' component label is not named in the NVD description, and the upstream iOS 26.7.3 grouping is not in the NVD record (no iOS 26 fix is listed).",
            fixedVersionNote: "iOS 27.2.1（iOS 26 修复版本未核实）",
            patch26: nil,
            patch27: IPAAuditOSVersion(major: 27, minor: 2, patch: 1),
            impact: "An app may be able to access sensitive user data.",
            sources: [
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-113963",
            ]),
        IPAAuditCVEEntry(
            id: "CVE-2026-113960/1",
            title: "iMessage group unauthorized join and history leak",
            subsystem: "iMessage",
            verifiedCVSS: nil,
            upstreamClaimedCVSS: 8.1,
            verifiedCVSSByID: ["CVE-2026-113960": 6.5, "CVE-2026-113961": 7.5],
            unverifiedIDs: [],
            verification: .partiallyVerified,
            verificationNote: "NVD confirms both IDs (113960: Analyzed, CVSS 3.1 6.5 MEDIUM; 113961: Awaiting Analysis, CVSS 3.1 7.5 HIGH) and the fixed versions iOS 26.7.3 / 27.2.1, with impacts matching unauthorized group join and pre-join history access. The upstream single score 8.1 matches neither ID, and the 'Blastdoor' label is not in the NVD descriptions, so no single verified score is stored for the entry.",
            fixedVersionNote: "iOS 26.7.3 / 27.2.1",
            patch26: IPAAuditOSVersion(major: 26, minor: 7, patch: 3),
            patch27: IPAAuditOSVersion(major: 27, minor: 2, patch: 1),
            impact: "A remote attacker may be able to join an iMessage group chat and receive its messages; a user added to a group may access messages sent before they joined.",
            sources: [
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-113960",
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-113961",
            ]),
        IPAAuditCVEEntry(
            id: "CVE-2026-113964–70",
            title: "Bluetooth pairing and AirPlay use-after-free",
            subsystem: "Bluetooth / AirPlay",
            verifiedCVSS: nil,
            upstreamClaimedCVSS: 8.8,
            verifiedCVSSByID: [
                "CVE-2026-113964": 5.4,
                "CVE-2026-113965": 5.4,
                "CVE-2026-113968": 5.4,
                "CVE-2026-113969": 7.5,
                "CVE-2026-113970": 8.8,
            ],
            unverifiedIDs: ["CVE-2026-113966", "CVE-2026-113967"],
            verification: .partiallyVerified,
            verificationNote: "NVD confirms five of the seven IDs in the claimed range (113964: 5.4, 113965: 5.4, 113968: 5.4, 113969: 7.5, 113970: 8.8; all Awaiting Analysis) and the fixed versions iOS 18.7.12 / 26.7.3 / 27.2.1. CVE-2026-113966 and CVE-2026-113967 return no NVD record at all (totalResults=0 as of 2026-11-28). The upstream single score 8.8 matches only 113970.",
            fixedVersionNote: "iOS 18.7.12 / 26.7.3 / 27.2.1",
            patch26: IPAAuditOSVersion(major: 26, minor: 7, patch: 3),
            patch27: IPAAuditOSVersion(major: 27, minor: 2, patch: 1),
            impact: "An attacker in Bluetooth range may bypass pairing-code rate limits or pair without user interaction; 113970 is a use-after-free that may corrupt memory.",
            sources: [
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-113964",
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-113970",
            ]),
        IPAAuditCVEEntry(
            id: "CVE-2026-65339",
            title: "Sensitive user information leak",
            subsystem: "Audio / media services",
            verifiedCVSS: 5.0,
            upstreamClaimedCVSS: 7.8,
            verifiedCVSSByID: [:],
            unverifiedIDs: [],
            verification: .partiallyVerified,
            verificationNote: "NVD (Modified, CVSS 3.1 5.0 MEDIUM) confirms the ID and the fixed versions iOS 18.7.11 / 26.6.1, but the upstream score 7.8 is wrong and the 'audiomxd microphone TCC bypass' component label is not named in the NVD description. No iOS 27 fix is listed, so the iOS 27 branch evaluates as unknown rather than patched.",
            fixedVersionNote: "iOS 18.7.11 / 26.6.1",
            patch26: IPAAuditOSVersion(major: 26, minor: 6, patch: 1),
            patch27: nil,
            impact: "An app may be able to leak sensitive user information.",
            sources: [
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-65339",
            ]),
        IPAAuditCVEEntry(
            id: "CVE-2026-20700",
            title: "Memory corruption with memory-write capability",
            subsystem: "System services",
            verifiedCVSS: 7.8,
            upstreamClaimedCVSS: 7.8,
            verifiedCVSSByID: [:],
            unverifiedIDs: [],
            verification: .partiallyVerified,
            verificationNote: "NVD (Analyzed, CVSS 3.1 7.8 HIGH) and Apple advisory for iOS 26.3 confirm the ID, the score, the iOS 26.3 fix and the exploited-in-the-wild note (Google Threat Analysis Group; also CVE-2025-14174 / CVE-2025-43529). The upstream 'dyld' component label is not named in the NVD description or in the Apple advisory text retrieved, so the subsystem is stated generically.",
            fixedVersionNote: "iOS 26.3（iOS 27 分支未核实）",
            patch26: IPAAuditOSVersion(major: 26, minor: 3, patch: 0),
            patch27: nil,
            impact: "An attacker with memory write capability may be able to execute arbitrary code. Apple is aware of a report of exploitation against targeted individuals on iOS before iOS 26.",
            sources: [
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-20700",
                "https://support.apple.com/en-us/126346",
            ]),
        IPAAuditCVEEntry(
            id: "CVE-2026-113897",
            title: "Web Content sandbox escape",
            subsystem: "Web content",
            verifiedCVSS: 10.0,
            upstreamClaimedCVSS: 8.8,
            verifiedCVSSByID: [:],
            unverifiedIDs: [],
            verification: .partiallyVerified,
            verificationNote: "NVD (Modified, CVSS 3.1 10.0 CRITICAL) confirms the ID, the Web Content sandbox-escape impact and the fix in Safari 27.2 / iOS 27.2, but the upstream score 8.8 is wrong, the 'GPU' qualifier is not in the NVD description, and the upstream iOS 26.7.2 grouping is not in the NVD record (no iOS 26 fix is listed).",
            fixedVersionNote: "iOS 27.2（iOS 26 修复版本未核实）",
            patch26: nil,
            patch27: IPAAuditOSVersion(major: 27, minor: 2, patch: 0),
            impact: "A remote attacker may be able to break out of the Web Content sandbox.",
            sources: [
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-113897",
            ]),
        IPAAuditCVEEntry(
            id: "CVE-2026-84493",
            title: "Bluetooth access without user consent",
            subsystem: "Bluetooth authorization",
            verifiedCVSS: 4.4,
            upstreamClaimedCVSS: 6.5,
            verifiedCVSSByID: [:],
            unverifiedIDs: [],
            verification: .partiallyVerified,
            verificationNote: "NVD (Modified, CVSS 3.1 4.4 MEDIUM) and Apple advisory for iOS 26.7.2 confirm the ID, the Bluetooth-without-consent impact and the fixed versions iOS 26.7.2 / 27.2, but the upstream score 6.5 is wrong and the 'AccessorySetupKit' component label is not named in the NVD description text retrieved.",
            fixedVersionNote: "iOS 26.7.2 / 27.2",
            patch26: IPAAuditOSVersion(major: 26, minor: 7, patch: 2),
            patch27: IPAAuditOSVersion(major: 27, minor: 2, patch: 0),
            impact: "A malicious app may be able to access Bluetooth without user consent.",
            sources: [
                "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2026-84493",
                "https://support.apple.com/en-us/149227",
            ]),
        IPAAuditCVEEntry(
            id: "PoC:BookRestore",
            title: "BookRestore MobileGestalt overwrite proof of concept",
            subsystem: "Book assets / MobileGestalt",
            verifiedCVSS: nil,
            upstreamClaimedCVSS: 7.8,
            verifiedCVSSByID: [:],
            unverifiedIDs: [],
            verification: .unverified,
            verificationNote: "No CVE number exists, so there is no NVD record to check. The 7.8 score and the iOS 27.0 / 26.2 fix versions are upstream claims, not verified against NVD or an Apple advisory.",
            fixedVersionNote: "未核实",
            patch26: nil,
            patch27: nil,
            impact: "Proof-of-concept overwrite of MobileGestalt values via bookassetd (upstream description; not an NVD impact statement).",
            sources: []),
    ]

    /// Evaluates one entry against a device OS version. A branch
    /// without a verified patch version is `.unknown`, never
    /// "patched". The worse_query entry is the exception: it has
    /// no CVE record, and its boundary is LilaShift's own 27.3
    /// beta 2 sentinel (see the entry's verification note).
    static func exposure(of entry: IPAAuditCVEEntry, for version: IPAAuditOSVersion) -> IPAAuditExposure {
        if entry.id == "0day:worse_query" {
            if version.major < 26 { return .patched }
            if version.major == 26 { return .exposed }
            if version.major == 27 {
                if version < IPAAuditOSVersion(major: 27, minor: 3, patch: 0) { return .exposed }
                if version.minor == 3, version.patch == 0 {
                    if let beta = version.beta, beta < 2 { return .exposed }
                    if version.beta == nil { return .patched }
                    return .patched
                }
                return .patched
            }
            return .patched
        }
        let patch: IPAAuditOSVersion?
        switch version.major {
        case 26: patch = entry.patch26
        case 27: patch = entry.patch27
        default: patch = nil
        }
        guard let patch else { return .unknown }
        return version < patch ? .exposed : .patched
    }

    /// The whole radar evaluated for one device version.
    static func evaluate(for version: IPAAuditOSVersion) -> [(entry: IPAAuditCVEEntry, exposure: IPAAuditExposure)] {
        entries.map { ($0, exposure(of: $0, for: version)) }
    }
}
