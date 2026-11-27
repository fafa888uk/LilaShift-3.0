// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UniformTypeIdentifiers

struct IPAAuditView: View {
    @State private var picking = false
    @State private var working = false
    @State private var report: IPAAudit?
    @State private var failure: String?
    @State private var selectedFile: URL?

    var body: some View {
        List {
            Section {
                Button {
                    picking = true
                } label: {
                    Label(L("Choose IPA"), systemImage: "doc.badge.magnifyingglass")
                }
                .disabled(working)
                if working { ProgressView() }
                if let failure { Text(failure).foregroundStyle(.secondary) }
            } footer: {
                Text(L("Inspects the selected IPA locally. Signature files and permission descriptions are metadata only. This does not verify trust, entitlements, or whether the app is safe to install."))
            }
            if let report {
                Section(L("Package Metadata")) {
                    LabeledContent(L("Bundle Identifier"), value: report.bundleID ?? L("Unknown"))
                    LabeledContent(L("Version"), value: report.version ?? L("Unknown"))
                    LabeledContent(L("Minimum iOS"), value: report.minimumOS ?? L("Unknown"))
                    metadataRow("App Executable", present: report.executablePresent)
                    metadataRow("Signature Resources", present: report.signatureResourcesPresent)
                    metadataRow("Embedded Provisioning Profile", present: report.provisioningPresent)
                }
                Section(L("Embedded Libraries")) {
                    if report.codePaths.isEmpty { Text(L("None Found")) }
                    ForEach(report.codePaths, id: \.self) { Text($0).font(.caption.monospaced()) }
                }
                Section(L("Permission Descriptions")) {
                    if report.usageDescriptionKeys.isEmpty { Text(L("None Found")) }
                    ForEach(report.usageDescriptionKeys, id: \.self) { Text($0).font(.caption.monospaced()) }
                }
            }
        }
        .navigationTitle(L("IPA Archive Inspection"))
        .fileImporter(isPresented: $picking, allowedContentTypes: [.init(filenameExtension: "ipa") ?? .zip]) { result in
            switch result {
            case .success(let url): selectedFile = url
            case .failure(let error): failure = error.localizedDescription
            }
        }
        .task(id: selectedFile) {
            guard let url = selectedFile else { return }
            report = nil
            failure = nil
            working = true
            let worker = Task.detached(priority: .userInitiated) { try IPAAudit.inspect(url) }
            defer {
                working = false
                selectedFile = nil
            }
            do {
                let inspected = try await withTaskCancellationHandler {
                    try await worker.value
                } onCancel: {
                    worker.cancel()
                }
                try Task.checkCancellation()
                report = inspected
            } catch is CancellationError {
                return
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func metadataRow(_ label: String, present: Bool) -> some View {
        LabeledContent(L(label), value: L(present ? "Present" : "Absent"))
    }
}
