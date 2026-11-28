// SPDX-License-Identifier: GPL-3.0-only
// IPA Audit — secure IPA package scanner + audit engine (W3).
//
// Design ported from Kianuni/WQGuard v1.3.6
// (`Sources/WQGuardCore/Engine/IPAPackageScanner.swift`, MIT,
// Copyright (c) 2026 WQGuard Contributors) — see W3NOTICES.md:
// ZIP / ZIP64 central-directory validation, on-demand extraction
// of only the binaries and signatures into an isolated
// `tmp/IPAAudit-<UUID>/` sandbox destroyed by `defer`, Zip-Slip
// interception, symlink stripping, and 64 KB streaming chunks
// against decompression bombs.
//
// This file is a fresh implementation for LilaShift. It does NOT
// call `CustomizationArchive.extract` or any other existing
// LilaShift unpack path: those paths are built for trusted
// wallpaper/backup archives, and an untrusted IPA must never go
// through them. Only the numeric size limits are shared with
// `CustomizationFiles` (256 MB per file, 768 MB total), and the
// ZIP reading itself uses the already-linked ZIPFoundation 0.9.21
// (MIT) in read mode — the same library the audit report
// (§2.3.3) records LilaShift as already using.
//
// Read-only with respect to the device: the scanner never writes
// outside its own tmp sandbox, never executes the IPA, and never
// touches another app's container.
import Foundation
import ZIPFoundation

/// The secure IPA scanner: validates, extracts on demand, parses
/// every Mach-O image found, matches the threat catalog, and
/// assembles the audit report.
enum IPAAuditScanner {
    static let scannerVersion = "LilaShift 5.0.0 (W3)"
    /// Per-file cap, shared with `CustomizationFiles.maximumFile`.
    static let maxEntrySize = CustomizationFiles.maximumFile
    /// Total extracted cap, shared with
    /// `CustomizationFiles.maximumTotal`.
    static let maxTotalExtracted = CustomizationFiles.maximumTotal
    static let maxEntries = 20_000
    /// Entries whose uncompressed size exceeds the compressed size
    /// by more than this factor (and exceed 1 MB) are rejected as
    /// suspected decompression bombs.
    static let maxCompressionRatio: UInt64 = 100
    static let chunkSize = 64 * 1024

    /// Audits one IPA file. `deviceOSVersion` is the version the
    /// CVE radar is evaluated against (the view passes the real
    /// device version; tests pass fixed versions). `nil` means the
    /// device version could not be determined: every radar row
    /// then evaluates to `.unknown` instead of a guessed verdict.
    /// `progress` receives 0.0–1.0 and a short label; `isCancelled` is polled
    /// between entries so the view's cancel button stops the scan
    /// promptly. The tmp sandbox is destroyed before this returns,
    /// on success and on failure alike.
    static func audit(
        ipaURL: URL,
        deviceOSVersion: IPAAuditOSVersion?,
        progress: (Double, String) -> Void = { _, _ in },
        isCancelled: () -> Bool = { false }
    ) throws -> IPAAuditReport {
        let fileSize = try validatedIPAFileSize(ipaURL)
        let fileData = try Data(contentsOf: ipaURL, options: .mappedIfSafe)
        let fileSHA256 = BackupEngine.sha256Hex(of: fileData)
        let fileName = ipaURL.lastPathComponent

        let sandbox = FileManager.default.temporaryDirectory
            .appendingPathComponent("IPAAudit-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: sandbox) }

        progress(0.05, L("Opening the IPA…"))
        let archive: Archive
        do {
            archive = try Archive(url: ipaURL, accessMode: .read)
        } catch {
            throw IPAAuditError(L("The file is not a valid ZIP/IPA archive."))
        }

        let entries = try validatedEntries(of: archive, isCancelled: isCancelled)
        progress(0.15, L("Locating the app bundle…"))
        guard let appDirectory = entries.appDirectory else {
            throw IPAAuditError(L("No Payload/*.app bundle was found in the IPA."))
        }

        let mainInfo = try extractMainInfoPlist(archive: archive, entries: entries, appDirectory: appDirectory, sandbox: sandbox)
        progress(0.25, L("Scanning binaries…"))

        var findings: [IPAAuditFinding] = []
        var binaryReports: [IPAAuditBinaryReport] = []
        var skippedFairPlayCount = 0
        let strippedSymlinkCount = entries.strippedSymlinkCount
        if !entries.escapingSymlinks.isEmpty {
            for target in entries.escapingSymlinks {
                findings.append(IPAAuditFinding(
                    ruleID: "ESCAPING_SYMLINK",
                    title: "Escaping symlink in the IPA",
                    detail: "A symlink entry points outside the package. It was stripped, never followed.",
                    severity: .highRisk,
                    location: "IPA entries",
                    evidence: String(target.prefix(128)),
                    relatedCVE: nil))
            }
        }

        let candidates = binaryCandidates(entries: entries, appDirectory: appDirectory, mainExecutable: mainInfo.executableName)
        var extractedTotal: UInt64 = 0
        for (index, candidate) in candidates.enumerated() {
            if isCancelled() { throw IPAAuditError(L("The scan was cancelled.")) }
            progress(0.25 + 0.65 * Double(index) / Double(max(candidates.count, 1)), L("Scanning") + " \(candidate.entry.path)…")
            let extracted = try extractEntry(
                archive: archive, entry: candidate.entry, into: sandbox,
                alreadyExtracted: extractedTotal)
            extractedTotal += extracted.byteCount
            let binaryReport = try auditBinary(
                at: extracted.url, relativePath: candidate.entry.path,
                findings: &findings, skippedFairPlayCount: &skippedFairPlayCount)
            binaryReports.append(binaryReport)
        }

        if binaryReports.isEmpty {
            throw IPAAuditError(L("No Mach-O binary was found in the app bundle."))
        }

        let bundleID = mainInfo.bundleID
        let verdict = IPAAuditThreatCatalog.verdict(findings: findings, bundleID: bundleID)
        let cveExposure = IPAAuditCVERadar.entries.map { entry in
            IPAAuditCVEExposure(
                entryID: entry.id,
                verifiedCVSS: entry.verifiedCVSS,
                verification: entry.verification,
                exposure: deviceOSVersion.map { IPAAuditCVERadar.exposure(of: entry, for: $0) } ?? .unknown,
                fixedVersionNote: entry.fixedVersionNote)
        }
        progress(1.0, L("Done"))
        return IPAAuditReport(
            id: UUID().uuidString,
            auditedAt: Date(),
            scannerVersion: scannerVersion,
            fileName: fileName,
            fileSize: fileSize,
            fileSHA256: fileSHA256,
            bundleID: bundleID,
            appName: mainInfo.appName,
            appVersion: mainInfo.appVersion,
            verdict: verdict,
            findings: findings,
            binaries: binaryReports,
            cveExposure: cveExposure,
            skippedFairPlayCount: skippedFairPlayCount,
            strippedSymlinkCount: strippedSymlinkCount,
            coverageNote: coverageNote(
                skippedFairPlayCount: skippedFairPlayCount,
                bundleID: bundleID))
    }

    // MARK: - IPA validation

    private static func validatedIPAFileSize(_ url: URL) throws -> Int {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true,
              let size = values.fileSize, size > 0, size <= maxEntrySize else {
            throw IPAAuditError(L("The IPA is invalid or exceeds the size limit."))
        }
        return size
    }

    /// The validated entry list: safe relative paths, no
    /// duplicates, per-entry and total size caps, compression-ratio
    /// bomb check. Symlink entries are stripped (never followed):
    /// escaping targets become findings, the rest are counted.
    private struct ValidatedEntries {
        let appDirectory: String?
        let all: [Archive.Entry]
        let strippedSymlinkCount: Int
        let escapingSymlinks: [String]
    }

    private static func validatedEntries(of archive: Archive, isCancelled: () -> Bool) throws -> ValidatedEntries {
        var all: [Archive.Entry] = []
        var seen = Set<String>()
        var appDirectory: String?
        var strippedSymlinks = 0
        var escapingSymlinks: [String] = []
        var expectedTotal: UInt64 = 0
        var count = 0
        for entry in archive {
            if isCancelled() { throw IPAAuditError(L("The scan was cancelled.")) }
            count += 1
            guard count <= maxEntries else {
                throw IPAAuditError(L("The IPA contains too many entries."))
            }
            guard entry.type != .directory else { continue }
            let path = entry.path
            _ = try safeRelativePath(path)
            let normalized = path.precomposedStringWithCanonicalMapping.lowercased()
            guard seen.insert(normalized).inserted else {
                throw IPAAuditError(L("The IPA contains duplicate entries."))
            }
            guard entry.uncompressedSize <= UInt64(maxEntrySize) else {
                throw IPAAuditError(L("An entry in the IPA exceeds the size limit."))
            }
            if entry.uncompressedSize > 1_048_576, entry.compressedSize > 0,
               entry.uncompressedSize / entry.compressedSize > maxCompressionRatio {
                throw IPAAuditError(L("An entry in the IPA looks like a decompression bomb."))
            }
            expectedTotal += entry.uncompressedSize
            guard expectedTotal <= UInt64(maxTotalExtracted) else {
                throw IPAAuditError(L("The IPA would extract to more than the size limit."))
            }
            if entry.type == .symlink {
                strippedSymlinks += 1
                if let target = try? readSymlinkTarget(archive: archive, entry: entry),
                   isEscapingSymlinkTarget(target) {
                    escapingSymlinks.append(target)
                }
                continue
            }
            all.append(entry)
            if appDirectory == nil {
                let parts = path.split(separator: "/")
                if parts.count >= 2, parts[0] == "Payload", parts[1].hasSuffix(".app") {
                    appDirectory = "Payload/\(parts[1])"
                }
            }
        }
        guard count > 0 else {
            throw IPAAuditError(L("The IPA contains no entries."))
        }
        return ValidatedEntries(
            appDirectory: appDirectory, all: all,
            strippedSymlinkCount: strippedSymlinks, escapingSymlinks: escapingSymlinks)
    }

    /// A relative path inside the package: no leading slash, no
    /// backslash, no NUL, no empty / "." / ".." components.
    static func safeRelativePath(_ path: String) throws -> String {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              path.utf8.count < 1_024 else {
            throw IPAAuditError(L("The IPA contains an unsafe entry path."))
        }
        return path
    }

    /// Resolves a safe relative path under `root`, refusing to
    /// escape it even through a pre-existing symlink on disk.
    private static func checkedTarget(_ relativePath: String, in root: URL) throws -> URL {
        let path = try safeRelativePath(relativePath)
        var next = root
        for part in path.split(separator: "/") {
            next.appendPathComponent(String(part))
            let values = try? next.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                throw IPAAuditError(L("The IPA contains an unsafe entry path."))
            }
        }
        guard next.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path) else {
            throw IPAAuditError(L("The IPA contains an unsafe entry path."))
        }
        return next
    }

    private static func readSymlinkTarget(archive: Archive, entry: Archive.Entry) throws -> String {
        var bytes = Data()
        _ = try archive.extract(entry, bufferSize: 1_024) { chunk in
            bytes.append(chunk)
            guard bytes.count <= 1_024 else {
                throw IPAAuditError(L("The IPA contains an unsafe entry path."))
            }
        }
        return String(bytes: bytes, encoding: .utf8) ?? ""
    }

    private static func isEscapingSymlinkTarget(_ target: String) -> Bool {
        target.hasPrefix("/") || target.split(separator: "/").contains("..")
    }

    // MARK: - Info.plist

    private struct MainInfo {
        let bundleID: String?
        let appName: String?
        let appVersion: String?
        let executableName: String?
    }

    private static func extractMainInfoPlist(
        archive: Archive, entries: ValidatedEntries, appDirectory: String, sandbox: URL
    ) throws -> MainInfo {
        let plistPath = "\(appDirectory)/Info.plist"
        guard let entry = entries.all.first(where: { $0.path == plistPath }) else {
            return MainInfo(bundleID: nil, appName: nil, appVersion: nil, executableName: nil)
        }
        let extractedPlist = try extractEntry(archive: archive, entry: entry, into: sandbox, alreadyExtracted: 0)
        let url = extractedPlist.url
        let data = try Data(contentsOf: url)
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = plist as? [String: Any] else {
            return MainInfo(bundleID: nil, appName: nil, appVersion: nil, executableName: nil)
        }
        let bundleID = dict["CFBundleIdentifier"] as? String
        let appName = (dict["CFBundleDisplayName"] as? String) ?? (dict["CFBundleName"] as? String)
        let appVersion = dict["CFBundleShortVersionString"] as? String
        let executableName = dict["CFBundleExecutable"] as? String
        return MainInfo(bundleID: bundleID, appName: appName, appVersion: appVersion, executableName: executableName)
    }

    // MARK: - Binary candidates

    private struct BinaryCandidate {
        let entry: Archive.Entry
    }

    /// On-demand candidate list: the main executable, every
    /// `.framework` binary, every `.appex` binary, and every
    /// `.dylib` under the app bundle. Nothing else is extracted:
    /// assets, storyboards and strings files are never read.
    private static func binaryCandidates(
        entries: ValidatedEntries, appDirectory: String, mainExecutable: String?
    ) -> [BinaryCandidate] {
        var candidates: [Archive.Entry] = []
        var seen = Set<String>()
        func add(_ entry: Archive.Entry) {
            if seen.insert(entry.path).inserted { candidates.append(entry) }
        }
        let prefix = appDirectory + "/"
        for entry in entries.all where entry.path.hasPrefix(prefix) {
            let relative = String(entry.path.dropFirst(prefix.count))
            let parts = relative.split(separator: "/").map(String.init)
            guard let first = parts.first else { continue }
            if first == "Frameworks", parts.count == 3, parts[1].hasSuffix(".framework"),
               parts[2] == parts[1].dropSuffix(".framework") {
                add(entry)
            } else if first == "PlugIns", parts.count == 3, parts[1].hasSuffix(".appex"),
                      parts[2] == parts[1].dropSuffix(".appex") {
                add(entry)
            } else if relative.hasSuffix(".dylib") {
                add(entry)
            } else if let mainExecutable, parts.count == 1, first == mainExecutable {
                add(entry)
            } else if parts.count == 1, first == (appDirectory as NSString).lastPathComponent.dropSuffix(".app") {
                // Fallback when Info.plist is missing: the file at
                // the app root named after the bundle.
                add(entry)
            }
        }
        return candidates.map { BinaryCandidate(entry: $0) }
    }

    // MARK: - Streaming extraction

    /// Extracts one entry into the sandbox with 64 KB streaming
    /// chunks, verifying the CRC-32 and the extracted byte count.
    /// `alreadyExtracted` is the byte total of earlier entries, so
    /// the cap is enforced across entries, not just per entry.
    /// Returns the extracted file and its byte count.
    private static func extractEntry(
        archive: Archive, entry: Archive.Entry, into sandbox: URL, alreadyExtracted: UInt64
    ) throws -> (url: URL, byteCount: UInt64) {
        let target = try checkedTarget(entry.path, in: sandbox)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: target.path, contents: nil) else {
            throw IPAAuditError(L("The IPA could not be extracted."))
        }
        let handle = try FileHandle(forWritingTo: target)
        var extracted: UInt64 = 0
        do {
            let crc = try archive.extract(entry, bufferSize: chunkSize) { chunk in
                extracted += UInt64(chunk.count)
                guard extracted <= UInt64(maxEntrySize),
                      extracted + alreadyExtracted <= UInt64(maxTotalExtracted) else {
                    throw IPAAuditError(L("The IPA would extract to more than the size limit."))
                }
                try handle.write(contentsOf: chunk)
            }
            try handle.close()
            guard crc == entry.checksum, extracted == entry.uncompressedSize else {
                throw IPAAuditError(L("An entry in the IPA failed its checksum."))
            }
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: target)
            throw error
        }
        return (target, extracted)
    }

    // MARK: - Per-binary audit

    private static func auditBinary(
        at url: URL, relativePath: String,
        findings: inout [IPAAuditFinding], skippedFairPlayCount: inout Int
    ) throws -> IPAAuditBinaryReport {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let slices = try IPAAuditMachOParser.parse(data)

        var linkedDylibs: [String] = []
        var symbols: [String] = []
        var strings: [String] = []
        var architectures: [String] = []
        var hasDirectSyscall = false
        var directSyscallCount = 0
        var allFairPlayEncrypted = true
        var mergedEntitlements: [String: Any] = [:]
        var xmlKeys = Set<String>()
        var derKeys = Set<String>()
        var isAdHoc = false
        var hasCMSSignature = false
        var codeDirectoryIdent: String?
        var hasXMLEntitlements = false
        var hasDEREntitlements = false

        for slice in slices {
            architectures.append(slice.architecture)
            linkedDylibs.append(contentsOf: slice.linkedDylibs.filter { !linkedDylibs.contains($0) })
            symbols.append(contentsOf: slice.symbols.filter { !symbols.contains($0) })
            strings.append(contentsOf: slice.cstrings.filter { !strings.contains($0) })
            strings.append(contentsOf: slice.objcSelectors.filter { !strings.contains($0) })
            hasDirectSyscall = hasDirectSyscall || slice.hasDirectSyscall
            directSyscallCount += slice.directSyscallCount
            if !slice.isFairPlayEncrypted { allFairPlayEncrypted = false }
            guard let signatureData = slice.codeSignature else { continue }
            do {
                let slots = try IPAAuditCSBlobParser.parseDictionaries(signatureData)
                hasXMLEntitlements = hasXMLEntitlements || slots.xml != nil
                hasDEREntitlements = hasDEREntitlements || slots.der != nil
                isAdHoc = isAdHoc || slots.isAdHoc
                hasCMSSignature = hasCMSSignature || slots.hasCMSSignature
                codeDirectoryIdent = codeDirectoryIdent ?? slots.codeDirectoryIdent
                // Merge this slice's XML+DER dictionaries (DER
                // wins within the slice) into the binary-wide
                // merge with the anti-shadowing rules, so a second
                // fat slice cannot hide a privilege.
                let sliceMerged = IPAAuditCSBlobParser.mergeEntitlementDictionaries(
                    slots.xml ?? [:], slots.der ?? [:])
                mergedEntitlements = IPAAuditCSBlobParser.mergeEntitlementDictionaries(
                    mergedEntitlements, sliceMerged)
                xmlKeys.formUnion(slots.xml?.keys ?? [])
                derKeys.formUnion(slots.der?.keys ?? [])
            } catch {
                // A malformed signature blob is evidence, not a
                // reason to stop the whole scan: record it and
                // keep auditing the binary's code.
                findings.append(IPAAuditFinding(
                    ruleID: "SIGNATURE_MALFORMED",
                    title: "Malformed code signature",
                    detail: "The LC_CODE_SIGNATURE blob could not be parsed: \(error.localizedDescription)",
                    severity: .caution,
                    location: relativePath,
                    evidence: "LC_CODE_SIGNATURE",
                    relatedCVE: nil))
            }
        }

        let renderedEntitlements = IPAAuditCSBlobParser.renderEntitlements(
            mergedEntitlements, xmlKeys: xmlKeys, derKeys: derKeys)
        let signature = IPAAuditCodeSignature(
            hasXMLEntitlements: hasXMLEntitlements,
            hasDEREntitlements: hasDEREntitlements,
            mergedEntitlements: renderedEntitlements,
            appGroups: (mergedEntitlements[IPAAuditCSBlobParser.appGroupsKey] as? [String]) ?? [],
            codeDirectoryIdent: codeDirectoryIdent,
            isAdHoc: isAdHoc,
            hasCMSSignature: hasCMSSignature)

        let wasSkipped = allFairPlayEncrypted && !slices.isEmpty
        if wasSkipped {
            skippedFairPlayCount += 1
            findings.append(IPAAuditFinding(
                ruleID: "FAIRPLAY_ENCRYPTED_SKIPPED",
                title: "FairPlay-encrypted binary skipped",
                detail: "The __TEXT segment is FairPlay-encrypted (cryptid != 0), so static analysis of this binary was skipped. The verdict does not cover it.",
                severity: .caution,
                location: relativePath,
                evidence: "LC_ENCRYPTION_INFO cryptid != 0",
                relatedCVE: nil))
        } else {
            let matched = IPAAuditThreatCatalog.match(
                dylibs: linkedDylibs, symbols: symbols, strings: strings,
                entitlements: renderedEntitlements)
            for finding in matched {
                findings.append(IPAAuditFinding(
                    ruleID: finding.ruleID, title: finding.title, detail: finding.detail,
                    severity: finding.severity, location: "\(relativePath) · \(finding.location)",
                    evidence: finding.evidence, relatedCVE: finding.relatedCVE))
            }
        }

        return IPAAuditBinaryReport(
            relativePath: relativePath,
            architectures: architectures,
            isFat: slices.first?.isFat ?? false,
            isFairPlayEncrypted: allFairPlayEncrypted,
            wasSkipped: wasSkipped,
            hasDirectSyscall: hasDirectSyscall,
            directSyscallCount: directSyscallCount,
            linkedDylibs: Array(linkedDylibs.prefix(200)),
            signature: signature)
    }

    private static func coverageNote(
        skippedFairPlayCount: Int, bundleID: String?
    ) -> String {
        var parts: [String] = []
        if skippedFairPlayCount > 0 {
            parts.append(L("FairPlay-encrypted binaries were skipped, so the verdict does not cover them."))
        }
        if let bundleID, IPAAuditThreatCatalog.trustedBundleIDs.contains(bundleID) {
            parts.append(L("This is a LilaShift build. Rule needles are stored as plain strings in this app, so scanning LilaShift's own IPA can match string rules from the catalog itself; dylib and symbol rules cannot match that way."))
        }
        parts.append(L("Static analysis only reports what was found in this binary. It cannot prove an app is safe."))
        return parts.joined(separator: " ")
    }
}

private extension String {
    /// Drops `suffix` when present, e.g. "Foo.framework" → "Foo".
    func dropSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
