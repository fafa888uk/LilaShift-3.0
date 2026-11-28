// SPDX-License-Identifier: GPL-3.0-only
// IPA Audit — SwiftUI audit page (W3).
//
// The user picks an IPA with the document picker; the scan runs
// in a detached task with real progress and a cancel button, and
// the report exports as JSON / Markdown / plain text through the
// system share sheet. FairPlay-encrypted binaries are skipped
// with an explicit note (never silently treated as clean), and
// the page states what this audit does NOT do: it never lists
// installed apps, never talks lockdownd, and never reads another
// app's container — iOS sandbox rules, not a missing feature.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct IPAAuditView: View {
    @State private var showingFileImporter = false
    @State private var isScanning = false
    @State private var progress = 0.0
    @State private var progressLabel = ""
    @State private var report: IPAAuditReport?
    @State private var errorMessage: String?
    @State private var shareExport: TemporaryExport?
    @State private var showingShare = false
    @State private var scanTask: Task<Void, Never>?

    private var ipaContentTypes: [UTType] {
        [UTType(filenameExtension: "ipa"), UTType.zip].compactMap { $0 }
    }

    var body: some View {
        List {
            Section {
                Text(L("Pick an IPA file to audit it on this device. The audit is read-only: the IPA is never installed, never executed, and the extracted files are deleted when the scan finishes."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button(L("Choose IPA…")) { showingFileImporter = true }
                    .disabled(isScanning)
            } header: {
                Text(L("IPA Security Audit"))
            }

            if isScanning {
                Section {
                    ProgressView(value: progress) {
                        Text(progressLabel.isEmpty ? L("Scanning…") : progressLabel)
                    }
                    Button(L("Cancel"), role: .destructive) {
                        scanTask?.cancel()
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                } header: {
                    Text(L("Scan Failed"))
                }
            }

            if let report {
                verdictSection(report)
                findingsSection(report)
                binariesSection(report)
                cveSection(report)
                exportSection(report)
            }

            Section {
                Text(L("Not part of this audit: listing installed apps, lockdownd pairing, container forensics, and proxy shields. Those need a paired Mac, an exported snapshot, or a proxy client, and are not iOS-app capabilities."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L("Scope"))
            }
        }
        .navigationTitle(L("IPA Security Audit"))
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: ipaContentTypes,
            allowsMultipleSelection: false
        ) { result in
            handlePickedFile(result)
        }
        .sheet(isPresented: $showingShare) {
            if let shareExport {
                ShareSheet(export: shareExport)
            }
        }
        .onDisappear { scanTask?.cancel() }
    }

    // MARK: - Sections

    private func verdictSection(_ report: IPAAuditReport) -> some View {
        Section {
            LabeledContent(L("Verdict")) {
                Text(report.verdict.title)
                    .bold()
                    .foregroundStyle(report.verdict == .highRisk ? .red : .primary)
            }
            LabeledContent(L("Bundle ID")) { Text(report.bundleID ?? L("Unknown")) }
            if let appName = report.appName {
                LabeledContent(L("App")) { Text(appName + (report.appVersion.map { " \($0)" } ?? "")) }
            }
            LabeledContent(L("SHA-256")) { Text(report.fileSHA256).font(.caption2).lineLimit(2) }
            LabeledContent(L("Findings")) {
                Text("\(report.highRiskFindings.count) high risk · \(report.cautionFindings.count) needs attention")
            }
            Text(report.coverageNote)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(report.verdict.disclaimer)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text(L("Result"))
        }
    }

    private func findingsSection(_ report: IPAAuditReport) -> some View {
        Section {
            if report.findings.isEmpty {
                Text(L("No findings."))
            } else {
                ForEach(Array(report.findings.enumerated()), id: \.offset) { _, finding in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(finding.ruleID).font(.caption).bold()
                            Spacer()
                            Text(finding.severity.title)
                                .font(.caption)
                                .foregroundStyle(finding.severity == .highRisk ? .red : .orange)
                        }
                        Text(finding.title).font(.subheadline)
                        Text(finding.detail).font(.caption).foregroundStyle(.secondary)
                        Text(finding.location).font(.caption2).foregroundStyle(.secondary)
                        if !finding.evidence.isEmpty {
                            Text(finding.evidence).font(.caption2).monospaced()
                        }
                        if let cve = finding.relatedCVE {
                            Text(cve).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        } header: {
            Text(L("Findings"))
        }
    }

    private func binariesSection(_ report: IPAAuditReport) -> some View {
        Section {
            ForEach(report.binaries, id: \.relativePath) { binary in
                VStack(alignment: .leading, spacing: 4) {
                    Text(binary.relativePath).font(.subheadline).bold()
                    Text(binary.architectures.joined(separator: ", ")
                        + (binary.isFat ? " " + L("(fat)") : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if binary.wasSkipped {
                        Text(L("FairPlay-encrypted — static analysis skipped."))
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else {
                        if binary.hasDirectSyscall {
                            Text(L("Direct syscalls (svc #0x80):") + " \(binary.directSyscallCount)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        if binary.signature.isAdHoc {
                            Text(L("Ad-hoc signature."))
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if !binary.signature.hasCMSSignature {
                            Text(L("No CMS signature blob. The chain is not verified by this scanner."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !binary.signature.appGroups.isEmpty {
                            Text(L("App Groups:") + " " + binary.signature.appGroups.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(binary.signature.mergedEntitlements, id: \.key) { entitlement in
                            Text("[\(entitlement.source)] \(entitlement.key)=\(entitlement.value)")
                                .font(.caption2)
                                .monospaced()
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(L("Binaries"))
        }
    }

    private func cveSection(_ report: IPAAuditReport) -> some View {
        Section {
            Text(L("Scores are the NVD-verified CVSS 3.1 values as of") + " \(IPAAuditCVERadar.verificationDate). " + L("Entries that could not be verified carry no score."))
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(report.cveExposure, id: \.entryID) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.entryID).font(.subheadline).bold()
                        Spacer()
                        Text(row.exposure.title)
                            .font(.caption)
                            .foregroundStyle(row.exposure == .exposed ? .red : .primary)
                    }
                    Text("CVSS \(row.verifiedCVSS.map { String($0) } ?? L("Unverified")) · \(row.verification.title) · \(L("Fixed:")) \(row.fixedVersionNote)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text(L("CVE Radar"))
        }
    }

    private func exportSection(_ report: IPAAuditReport) -> some View {
        Section {
            Button(L("Share as JSON")) { share(data: try? report.jsonData(), name: "ipa-audit-\(report.id).json") }
            Button(L("Share as Markdown")) { share(data: report.markdown().data(using: .utf8), name: "ipa-audit-\(report.id).md") }
            Button(L("Share as Plain Text")) { share(data: report.plainText().data(using: .utf8), name: "ipa-audit-\(report.id).txt") }
        } header: {
            Text(L("Export Report"))
        } footer: {
            Text(L("The exported file contains only this audit's findings. No data leaves the device except through the share destination you choose."))
        }
    }

    // MARK: - Actions

    private func handlePickedFile(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            startScan(url: url)
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func startScan(url: URL) {
        errorMessage = nil
        report = nil
        isScanning = true
        progress = 0
        progressLabel = ""
        let deviceVersion = IPAAuditOSVersion(string: UIDevice.current.systemVersion)
        scanTask?.cancel()
        scanTask = Task {
            let staged: URL
            do {
                staged = try CustomizationFiles.stagePickedFile(url)
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isScanning = false
                }
                return
            }
            defer { CustomizationFiles.discardStagedDirectory(containing: staged) }
            do {
                let scanned = try IPAAuditScanner.audit(
                    ipaURL: staged,
                    deviceOSVersion: deviceVersion,
                    progress: { value, label in
                        Task { @MainActor in
                            progress = value
                            progressLabel = label
                        }
                    },
                    isCancelled: { Task.isCancelled })
                await MainActor.run {
                    report = scanned
                    isScanning = false
                }
            } catch {
                await MainActor.run {
                    if Task.isCancelled {
                        errorMessage = L("The scan was cancelled.")
                    } else {
                        errorMessage = error.localizedDescription
                    }
                    isScanning = false
                }
            }
        }
    }

    private func share(data: Data?, name: String) {
        guard let data else {
            errorMessage = L("The report could not be generated.")
            return
        }
        do {
            shareExport = try TemporaryExport(data: data, name: name)
            showingShare = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
