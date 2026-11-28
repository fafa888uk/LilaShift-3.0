// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct W7IntelligenceReportView: View {
    @State private var choosing = false
    @State private var request: OpenRequest?
    @State private var summary: W7IntelligenceReport?
    @State private var issue: String?

    private struct OpenRequest: Identifiable, Sendable {
        let id = UUID()
        let url: URL
    }

    static var title: String { String(localized: "Apple Intelligence Report", table: "W7Report") }

    var body: some View {
        List {
            Section {
                Button {
                    choosing = true
                } label: {
                    Label(String(localized: "Choose report JSON", table: "W7Report"), systemImage: "doc.text")
                }
                if request != nil { ProgressView() }
                if let issue { Text(issue).foregroundStyle(.secondary) }
            } footer: {
                Text("Export from Settings → Privacy & Security → Apple Intelligence Report. This app only reads the file you choose and does not upload or retain it.", tableName: "W7Report")
            }

            if let summary {
                Section {
                    LabeledContent(label("Private Cloud Compute records"), value: displayCount(summary.privateCloudComputeRequests))
                    LabeledContent(label("Model request records"), value: displayCount(summary.modelRequests))
                } header: {
                    Text("Records found in this file", tableName: "W7Report")
                } footer: {
                    Text("A zero count describes this file only. The app does not verify the report's origin, server attestation, or device eligibility.", tableName: "W7Report")
                }
            }
        }
        .navigationTitle(Self.title)
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.json]) { result in
            summary = nil
            switch result {
            case .success(let url):
                issue = nil
                request = OpenRequest(url: url)
            case .failure:
                request = nil
                issue = label("Could not open this file.")
            }
        }
        .task(id: request?.id) {
            guard let opened = request else { return }
            let result = await Task.detached(priority: .userInitiated) {
                Result { try W7IntelligenceReport.read(opened.url) }
            }.value
            guard !Task.isCancelled, request?.id == opened.id else { return }
            request = nil
            switch result {
            case .success(let value):
                summary = value
            case .failure(let error):
                issue = failureMessage(error as? W7IntelligenceReport.Failure)
            }
        }
    }

    private func displayCount(_ count: Int?) -> String {
        count?.formatted() ?? label("Not in this file")
    }

    private func failureMessage(_ error: W7IntelligenceReport.Failure?) -> String {
        switch error {
        case .tooLarge: label("This file is larger than 4 MiB.")
        case .malformedJSON: label("This file is not valid JSON.")
        case .unrecognized: label("Recognized report sections were not found.")
        case .invalidRequestList: label("A report section had an unsupported format.")
        case .unreadable, nil: label("Could not open this file.")
        }
    }

    private func label(_ value: String.LocalizationValue) -> String {
        String(localized: value, table: "W7Report")
    }
}
