// SPDX-License-Identifier: GPL-3.0-only
// IPA Audit — audit report model + export renderers (W3).
//
// The report is the only thing that leaves the scanner: it is a
// plain `Codable` value built from real parse results, never from
// guesses. Every field that could not be determined is `nil` or
// an explicit "unknown" — the renderers never fill a gap with a
// plausible-looking value. Export formats: RFC 8259 JSON,
// Markdown, and plain text, shared through the system share
// sheet (the same `TemporaryExport` + `ShareSheet` the app
// already uses for other exports).
import Foundation

/// One matched rule, with its evidence.
struct IPAAuditFinding: Equatable, Codable, Sendable {
    let ruleID: String
    let title: String
    let detail: String
    let severity: IPAAuditVerdict
    /// Where it was found, e.g. "Payload/App.app/App · LC_SYMTAB".
    let location: String
    /// The matched evidence, truncated to 128 characters by the
    /// engine so a hostile binary cannot smuggle long strings
    /// into the report.
    let evidence: String
    let relatedCVE: String?
}

/// The signature facts for one audited binary.
struct IPAAuditBinaryReport: Equatable, Codable, Sendable {
    /// Path inside the IPA, e.g. "Payload/App.app/App".
    let relativePath: String
    let architectures: [String]
    let isFat: Bool
    /// `cryptid != 0` on every slice.
    let isFairPlayEncrypted: Bool
    /// True when FairPlay encryption made static analysis
    /// impossible for this binary (no rule matching ran on it).
    let wasSkipped: Bool
    let hasDirectSyscall: Bool
    let directSyscallCount: Int
    /// Linked dylibs, capped at 200 by the engine.
    let linkedDylibs: [String]
    let signature: IPAAuditCodeSignature
}

/// One radar row for the device version the audit ran against.
struct IPAAuditCVEExposure: Equatable, Codable, Sendable {
    let entryID: String
    let verifiedCVSS: Double?
    let verification: IPAAuditVerification
    let exposure: IPAAuditExposure
    let fixedVersionNote: String
}

/// The complete audit report for one IPA file.
struct IPAAuditReport: Equatable, Codable, Sendable {
    let id: String
    let auditedAt: Date
    let scannerVersion: String
    let fileName: String
    let fileSize: Int
    let fileSHA256: String
    let bundleID: String?
    let appName: String?
    let appVersion: String?
    let verdict: IPAAuditVerdict
    let findings: [IPAAuditFinding]
    let binaries: [IPAAuditBinaryReport]
    let cveExposure: [IPAAuditCVEExposure]
    let skippedFairPlayCount: Int
    let strippedSymlinkCount: Int
    let coverageNote: String

    var highRiskFindings: [IPAAuditFinding] {
        findings.filter { $0.severity == .highRisk }
    }

    var cautionFindings: [IPAAuditFinding] {
        findings.filter { $0.severity == .caution }
    }

    // MARK: - JSON

    func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    // MARK: - Markdown

    func markdown() -> String {
        var lines: [String] = []
        lines.append("# IPA Security Audit Report")
        lines.append("")
        lines.append("- File: \(fileName) (\(fileSize) bytes)")
        lines.append("- SHA-256: \(fileSHA256)")
        lines.append("- Bundle ID: \(bundleID ?? "Unknown")")
        lines.append("- App: \(appName ?? "Unknown") \(appVersion ?? "")")
        lines.append("- Verdict: \(verdict.title)")
        lines.append("- Audited at: \(ISO8601DateFormatter().string(from: auditedAt))")
        lines.append("- Scanner: \(scannerVersion)")
        lines.append("")
        lines.append("## Findings (\(findings.count))")
        lines.append("")
        if findings.isEmpty {
            lines.append("No findings.")
        } else {
            for finding in findings {
                lines.append("- [\(finding.severity.rawValue)] \(finding.ruleID): \(finding.title) — \(finding.location) — evidence: `\(finding.evidence)`")
            }
        }
        lines.append("")
        lines.append("## Binaries (\(binaries.count))")
        lines.append("")
        for binary in binaries {
            lines.append("- \(binary.relativePath) (\(binary.architectures.joined(separator: ", ")))"
                + (binary.wasSkipped ? " — FairPlay-encrypted, skipped" : "")
                + (binary.hasDirectSyscall ? " — direct syscalls: \(binary.directSyscallCount)" : ""))
            if binary.signature.isAdHoc {
                lines.append("  - Ad-hoc signature (CS_ADHOC).")
            }
            if !binary.signature.hasCMSSignature {
                lines.append("  - No CMS signature blob present. The signature chain is not verified by this scanner.")
            }
            if !binary.signature.appGroups.isEmpty {
                lines.append("  - App Groups: \(binary.signature.appGroups.joined(separator: ", "))")
            }
            for entitlement in binary.signature.mergedEntitlements {
                lines.append("  - Entitlement [\(entitlement.source)] \(entitlement.key)=\(entitlement.value)")
            }
        }
        lines.append("")
        lines.append("## CVE Radar (device OS version at audit time)")
        lines.append("")
        lines.append("Verification date: \(IPAAuditCVERadar.verificationDate). Scores are the NVD-verified CVSS 3.1 values; entries that could not be verified are marked Unverified and carry no score.")
        lines.append("")
        for row in cveExposure {
            let score = row.verifiedCVSS.map { String($0) } ?? "Unverified"
            lines.append("- \(row.entryID): \(row.exposure.title) — CVSS \(score) — \(row.verification.title) — fixed: \(row.fixedVersionNote)")
        }
        lines.append("")
        lines.append("## Coverage")
        lines.append("")
        lines.append(coverageNote)
        if strippedSymlinkCount > 0 {
            lines.append("Stripped symlink entries: \(strippedSymlinkCount).")
        }
        lines.append("")
        lines.append("> \(verdict.disclaimer)")
        return lines.joined(separator: "\n")
    }

    // MARK: - Plain text

    func plainText() -> String {
        var lines: [String] = []
        lines.append("IPA Security Audit Report")
        lines.append("File: \(fileName) (\(fileSize) bytes)")
        lines.append("SHA-256: \(fileSHA256)")
        lines.append("Bundle ID: \(bundleID ?? "Unknown")")
        lines.append("App: \(appName ?? "Unknown") \(appVersion ?? "")")
        lines.append("Verdict: \(verdict.title)")
        lines.append("Audited at: \(ISO8601DateFormatter().string(from: auditedAt))")
        lines.append("Scanner: \(scannerVersion)")
        lines.append("")
        lines.append("Findings (\(findings.count)):")
        if findings.isEmpty {
            lines.append("  No findings.")
        } else {
            for finding in findings {
                lines.append("  [\(finding.severity.rawValue)] \(finding.ruleID): \(finding.title)")
                lines.append("    Location: \(finding.location)")
                lines.append("    Evidence: \(finding.evidence)")
            }
        }
        lines.append("")
        lines.append("Binaries (\(binaries.count)):")
        for binary in binaries {
            lines.append("  \(binary.relativePath) (\(binary.architectures.joined(separator: ", ")))"
                + (binary.wasSkipped ? " — FairPlay-encrypted, skipped" : ""))
        }
        lines.append("")
        lines.append("CVE Radar (verification date \(IPAAuditCVERadar.verificationDate)):")
        for row in cveExposure {
            let score = row.verifiedCVSS.map { String($0) } ?? "Unverified"
            lines.append("  \(row.entryID): \(row.exposure.title) — CVSS \(score) — \(row.verification.title) — fixed: \(row.fixedVersionNote)")
        }
        lines.append("")
        lines.append("Coverage: \(coverageNote)")
        if strippedSymlinkCount > 0 {
            lines.append("Stripped symlink entries: \(strippedSymlinkCount).")
        }
        lines.append("")
        lines.append(verdict.disclaimer)
        return lines.joined(separator: "\n")
    }
}
