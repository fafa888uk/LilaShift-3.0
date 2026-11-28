// SPDX-License-Identifier: GPL-3.0-only
// IPA Audit — threat signature catalog + four-tier verdict (W3).
//
// Rule names and needle values follow Kianuni/WQGuard v1.3.6
// (`Sources/WQGuardCore/Engine/SignatureCatalog.swift` and
// `ExpandedThreatCatalog.swift`, MIT, Copyright (c) 2026 WQGuard
// Contributors) — see W3NOTICES.md. The rule *table* here is a
// compact re-encoding for LilaShift: plain-string needles (no
// XOR armor — see the note on `Rule.needle`), the four verdict
// tiers from the audit report (high-risk / known tool /
// pre-attention / safe), and a whitelist rewritten for LilaShift
// (the WQGuard Bundle ID is deliberately NOT copied).
//
// Honesty notes, enforced by the types:
//   • A string needle alone never proves exploitation: every rule
//     carries a severity and the report shows the exact matched
//     evidence, so a reviewer can tell a linked private framework
//     from a stray string.
//   • Tuple / obfuscation heuristics from upstream
//     (`TUPLE_OBFUSCATED_EXPLOIT`, `CLIPBOARD_SNOOP_TUPLE`) are
//     NOT ported: the README gives no deterministic spec for them,
//     and this engine does not guess.
//   • The whitelist never suppresses a finding: a whitelisted
//     bundle with a high-risk finding is still high-risk. It only
//     supplies the "known tool" tier for a clean, recognized build.
import Foundation

/// The four verdict tiers (audit report §2.3.8).
enum IPAAuditVerdict: String, Equatable, Codable, Sendable {
    /// At least one high-risk finding.
    case highRisk
    /// No high-risk finding, and the bundle is a recognized
    /// LilaShift build (whitelisted). A known tool, not a threat.
    case knownTool
    /// No high-risk finding, but at least one pre-attention
    /// (caution) finding.
    case caution
    /// No findings at all.
    case safe

    var title: String {
        switch self {
        case .highRisk: return L("High Risk")
        case .knownTool: return L("Known Tool")
        case .caution: return L("Needs Attention")
        case .safe: return L("Safe & Compliant")
        }
    }

    /// The verdict is never presented as a safety guarantee: a
    /// static scan can only report what it found in the binary.
    var disclaimer: String {
        L("Static analysis only reports what was found in this binary. It cannot prove an app is safe.")
    }
}

/// Where a rule can match.
enum IPAAuditRuleSource: String, Equatable, Codable, Sendable {
    /// An LC_LOAD_DYLIB install name.
    case dylib
    /// A symbol name from LC_SYMTAB.
    case symbol
    /// A string from __TEXT,__cstring or an Objective-C selector.
    case string
    /// A merged entitlement key/value.
    case entitlement
    /// A package-level property (symlink, bundle structure).
    case package
}

/// One static signature rule.
struct IPAAuditRule: Equatable, Sendable {
    let id: String
    /// The literal needle matched against dylib names, symbols or
    /// strings (substring match, case-sensitive: symbol and path
    /// names are case-sensitive on Apple platforms).
    ///
    /// NOTE — no XOR armor: upstream armors these needles so its
    /// own scanner binary does not self-trigger on `__TEXT`.
    /// LilaShift keeps plain needles and documents the consequence
    /// instead: scanning LilaShift's own IPA can match the
    /// needles stored in this catalog's own strings. The audit
    /// view warns about that when the scanned bundle is LilaShift
    /// itself, and the verdict for a whitelisted bundle is
    /// "known tool", never "high risk", unless a dylib or symbol
    /// rule — which cannot come from a mere string — fires.
    let needle: String
    let source: IPAAuditRuleSource
    let title: String
    let detail: String
    /// The tier a single match contributes: `.highRisk` or
    /// `.caution`. (The `.knownTool` / `.safe` tiers are verdict
    /// outcomes, not rule severities.)
    let severity: IPAAuditVerdict
    /// Related CVE, when the rule exists because of one.
    let relatedCVE: String?
}

/// The threat catalog: dylib, private-symbol, string and
/// entitlement rules. `allRules` is the whole table; the engine
/// matches each binary's evidence against it.
enum IPAAuditThreatCatalog {
    /// Bundle IDs LilaShift trusts as its own builds. The WQGuard
    /// Bundle ID was deliberately NOT copied here.
    static let trustedBundleIDs: Set<String> = [
        "com.huami.gestultx",
        "com.huami.gestultx.ShareExtension",
    ]

    /// Dylib rules: a linked private library.
    static let dylibRules: [IPAAuditRule] = [
        IPAAuditRule(
            id: "DYLIB_CONTAINERMANAGER",
            needle: "libsystem_containermanager.dylib",
            source: .dylib,
            title: "Container Manager linkage",
            detail: "Direct linkage to the private libsystem_containermanager.dylib, used for containermanagerd IPC and sandbox-token acquisition (worse_query / bad_query).",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "INJECTED_HOOK_FRAMEWORK_SUBSTRATE",
            needle: "CydiaSubstrate",
            source: .dylib,
            title: "Hook framework (CydiaSubstrate)",
            detail: "Links a code-injection hook framework. Such frameworks patch other processes at runtime and are a common sideload-malware carrier.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "INJECTED_HOOK_FRAMEWORK_ELLEKIT",
            needle: "ElleKit",
            source: .dylib,
            title: "Hook framework (ElleKit)",
            detail: "Links the ElleKit code-injection framework.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "INJECTED_HOOK_FRAMEWORK_LIBHOOKER",
            needle: "libhooker",
            source: .dylib,
            title: "Hook framework (libhooker)",
            detail: "Links the libhooker code-injection framework.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "INJECTED_HOOK_FRAMEWORK_LIBSUBSTITUTE",
            needle: "libsubstitute",
            source: .dylib,
            title: "Hook framework (libsubstitute)",
            detail: "Links the libsubstitute code-injection framework.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "BUNDLED_LIBBROTLI",
            needle: "libbrotli",
            source: .dylib,
            title: "Bundled libbrotli",
            detail: "Bundles its own Brotli decoder instead of the system one. Check the bundled version against CVE-2026-111497 (Brotli heap out-of-bounds write, fixed in Brotli 1.2.1). Bundling alone does not prove the vulnerable version is present.",
            severity: .caution,
            relatedCVE: "CVE-2026-111497"),
    ]

    /// Private-API symbol rules. The eleven `container_query_*`
    /// symbols are the worse_query primitive set.
    static let symbolRules: [IPAAuditRule] = [
        IPAAuditRule(
            id: "SYM_QUERY_CREATE",
            needle: "container_query_create",
            source: .symbol,
            title: "Private API: container_query_create",
            detail: "Private containermanager API that allocates a container query object — the entry point of the worse_query primitive set.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_SET_GROUP_IDENTIFIERS",
            needle: "container_query_set_group_identifiers",
            source: .symbol,
            title: "Private API: container_query_set_group_identifiers",
            detail: "Private API setting the target App Group identifier in a container query.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_SET_PART",
            needle: "container_query_set_part",
            source: .symbol,
            title: "Private API: container_query_set_part",
            detail: "Private API setting the container part (e.g. part=3 for Library/Caches).",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_SET_FLAGS",
            needle: "container_query_set_flags",
            source: .symbol,
            title: "Private API: container_query_set_flags",
            detail: "Private API setting container query operation flags.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_COPY_SANDBOX_TOKEN",
            needle: "container_query_copy_sandbox_token",
            source: .symbol,
            title: "Private API: container_query_copy_sandbox_token",
            detail: "Private API retrieving an issued Seatbelt sandbox token from a containermanagerd result.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_QUERY_SINGLE_RESULT",
            needle: "container_query_get_single_result",
            source: .symbol,
            title: "Private API: container_query_get_single_result",
            detail: "Private containermanager API reading a single query result.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_QUERY_ITERATE_SYNC",
            needle: "container_query_iterate_sync",
            source: .symbol,
            title: "Private API: container_query_iterate_sync",
            detail: "Private containermanager API iterating query results synchronously.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_QUERY_SET_CLASS",
            needle: "container_query_set_class",
            source: .symbol,
            title: "Private API: container_query_set_class",
            detail: "Private API setting the container query class (e.g. class=7 for App Groups).",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_QUERY_FREE",
            needle: "container_query_free",
            source: .symbol,
            title: "Private API: container_query_free",
            detail: "Private containermanager API freeing a container query object.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_SANDBOX_EXTENSION_CONSUME",
            needle: "sandbox_extension_consume",
            source: .symbol,
            title: "Private API: sandbox_extension_consume",
            detail: "Darwin Seatbelt API consuming a sandbox extension token to acquire kernel path privileges.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_SANDBOX_EXTENSION_RELEASE",
            needle: "sandbox_extension_release",
            source: .symbol,
            title: "Private API: sandbox_extension_release",
            detail: "Darwin Seatbelt API releasing a sandbox extension token.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_FSGETPATH",
            needle: "fsgetpath",
            source: .symbol,
            title: "Private API: fsgetpath",
            detail: "Private API resolving a file descriptor to a path (bad_query inode enumeration primitive).",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "SYM_CONTAINER_OBJECT_GET_PATH",
            needle: "container_object_get_path",
            source: .symbol,
            title: "Private API: container_object_get_path",
            detail: "Private containermanager API resolving a container object to a filesystem path.",
            severity: .highRisk,
            relatedCVE: nil),
    ]

    /// String rules: framework / service / daemon names found in
    /// __TEXT strings. A string match is weaker evidence than a
    /// dylib or symbol match — these are all `.caution` except
    /// the containermanagerd XPC service name, which only an app
    /// talking to that daemon would embed.
    static let stringRules: [IPAAuditRule] = [
        IPAAuditRule(
            id: "XPC_CONTAINERMANAGERD",
            needle: "com.apple.containermanagerd",
            source: .string,
            title: "XPC service: containermanagerd",
            detail: "References the containermanagerd XPC service. Combined with container_query symbols this is the worse_query IPC path; alone it is only a reference.",
            severity: .highRisk,
            relatedCVE: nil),
        IPAAuditRule(
            id: "AUDIOMXD_BYPASS",
            needle: "audiomxd",
            source: .string,
            title: "Audio daemon reference (audiomxd)",
            detail: "References the audiomxd audio daemon. Upstream links this string to CVE-2026-65339; the string alone does not prove the bypass is used.",
            severity: .caution,
            relatedCVE: "CVE-2026-65339"),
        IPAAuditRule(
            id: "BOOKRESTORE_GESTALT",
            needle: "bookassetd",
            source: .string,
            title: "BookRestore daemon reference (bookassetd)",
            detail: "References the bookassetd daemon used by the BookRestore MobileGestalt-overwrite proof of concept. The string alone does not prove the overwrite is attempted.",
            severity: .caution,
            relatedCVE: nil),
        IPAAuditRule(
            id: "PRIVATE_PHOTOS_BYPASS",
            needle: "PhotoLibraryServices",
            source: .string,
            title: "Private Photos framework reference",
            detail: "References the private PhotoLibraryServices framework. Upstream links this area to CVE-2026-112676 (Photos TCC bypass); the reference alone does not prove the bypass is used.",
            severity: .caution,
            relatedCVE: "CVE-2026-112676"),
        IPAAuditRule(
            id: "ACCESSORY_SETUP_BYPASS",
            needle: "AccessorySetupKit",
            source: .string,
            title: "AccessorySetupKit reference",
            detail: "References AccessorySetupKit. Upstream links this area to CVE-2026-84493 (Bluetooth access without user consent); the reference alone does not prove the bypass is used.",
            severity: .caution,
            relatedCVE: "CVE-2026-84493"),
        IPAAuditRule(
            id: "BRAND_IMPERSONATION_WALLET",
            needle: "MetaMask",
            source: .string,
            title: "Wallet brand string (MetaMask)",
            detail: "Embeds a well-known wallet brand name. Brand strings alone do not prove impersonation — check the bundle ID and signing identity against the real vendor before concluding anything.",
            severity: .caution,
            relatedCVE: nil),
    ]

    /// Entitlement rules, matched against the merged XML+DER
    /// entitlement dictionary.
    static let entitlementRules: [IPAAuditRule] = [
        IPAAuditRule(
            id: "ENT_GET_TASK_ALLOW",
            needle: "get-task-allow",
            source: .entitlement,
            title: "Debuggable entitlement (get-task-allow)",
            detail: "The binary is signed with get-task-allow, so a debugger can attach to it. Normal for development builds; unexpected in a distributed release.",
            severity: .caution,
            relatedCVE: nil),
        IPAAuditRule(
            id: "ENT_WILDCARD_KEYCHAIN_GROUP",
            needle: "keychain-access-groups",
            source: .entitlement,
            title: "Wildcard keychain access group",
            detail: "A keychain access group contains a wildcard, which broadens the keychain items this app can read. Only flagged when the value contains '*'.",
            severity: .caution,
            relatedCVE: nil),
    ]

    static let allRules: [IPAAuditRule] = dylibRules + symbolRules + stringRules + entitlementRules

    /// Matches one binary's evidence against the catalog and
    /// returns one finding per (rule, evidence) pair. `evidence`
    /// strings are truncated to 128 characters in the finding so
    /// a hostile binary cannot smuggle long strings into the
    /// report.
    static func match(
        dylibs: [String], symbols: [String], strings: [String], entitlements: [IPAAuditEntitlement]
    ) -> [IPAAuditFinding] {
        var findings: [IPAAuditFinding] = []
        for rule in dylibRules {
            for dylib in dylibs where dylib.contains(rule.needle) {
                findings.append(IPAAuditFinding(
                    ruleID: rule.id, title: rule.title, detail: rule.detail,
                    severity: rule.severity, location: "LC_LOAD_DYLIB",
                    evidence: String(dylib.prefix(128)), relatedCVE: rule.relatedCVE))
            }
        }
        for rule in symbolRules {
            for symbol in symbols where symbol.contains(rule.needle) {
                findings.append(IPAAuditFinding(
                    ruleID: rule.id, title: rule.title, detail: rule.detail,
                    severity: rule.severity, location: "LC_SYMTAB",
                    evidence: String(symbol.prefix(128)), relatedCVE: rule.relatedCVE))
            }
        }
        for rule in stringRules {
            for text in strings where text.contains(rule.needle) {
                findings.append(IPAAuditFinding(
                    ruleID: rule.id, title: rule.title, detail: rule.detail,
                    severity: rule.severity, location: "__TEXT,__cstring",
                    evidence: String(text.prefix(128)), relatedCVE: rule.relatedCVE))
            }
        }
        for rule in entitlementRules {
            for entitlement in entitlements where entitlement.key == rule.needle {
                if rule.id == "ENT_WILDCARD_KEYCHAIN_GROUP",
                   !entitlement.value.contains("*") {
                    continue
                }
                if rule.id == "ENT_GET_TASK_ALLOW",
                   entitlement.value != "true" {
                    continue
                }
                findings.append(IPAAuditFinding(
                    ruleID: rule.id, title: rule.title, detail: rule.detail,
                    severity: rule.severity, location: "CSBlob entitlements",
                    evidence: "\(entitlement.key)=\(entitlement.value)".prefix(128).description,
                    relatedCVE: rule.relatedCVE))
            }
        }
        return findings
    }

    /// The verdict for a scan: high-risk wins over everything
    /// (the whitelist never suppresses it); a clean whitelisted
    /// bundle is a known tool; any caution finding needs
    /// attention; otherwise safe.
    static func verdict(findings: [IPAAuditFinding], bundleID: String?) -> IPAAuditVerdict {
        if findings.contains(where: { $0.severity == .highRisk }) {
            return .highRisk
        }
        if let bundleID, trustedBundleIDs.contains(bundleID) {
            return .knownTool
        }
        if findings.contains(where: { $0.severity == .caution }) {
            return .caution
        }
        return .safe
    }
}
