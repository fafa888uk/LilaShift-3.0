// SPDX-License-Identifier: GPL-3.0-only
// Diagnostics Centre (Stage 6, ADR-2-09): the on-demand,
// authoritative view of the unified diagnostics report.
//
// The report is computed on demand from the manager's input
// builder (events and restore reports included) plus the home
// cache's fingerprint comparison, backup verifications and
// restart-pending set — the full input, not the cached copy.
// Computing is a pure function, so Refresh just recomputes.
// Suggestions never execute anything from here: each finding
// states what to do, and the user acts in the relevant view.
import SwiftUI

struct DiagnosticsCentreView: View {
    let share: (TemporaryExport) -> Void
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.homeDiagnosticsCache) private var diagnostics
    @State private var report: DiagnosticsReport?
    @State private var isComputing = false
    @State private var exportError: String?

    private var sortedFindings: [DiagnosticsFinding] {
        (report?.findings ?? []).sorted {
            if $0.severity != $1.severity { return $0.severity > $1.severity }
            return $0.code < $1.code
        }
    }

    var body: some View {
        List {
            if let report {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.summary).font(.headline)
                        Text(report.generatedAt, format: .dateTime.year().month().day().hour().minute().second())
                            .font(.caption).foregroundStyle(.secondary)
                        if let device = report.device {
                            Text(deviceSummary(device)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if report.findings.isEmpty {
                    Section {
                        Label(L("No issues found."), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.green)
                    }
                } else {
                    Section {
                        ForEach(sortedFindings) { finding in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: finding.severity.systemImage)
                                        .foregroundStyle(finding.severity.color)
                                    Text(finding.title).font(.subheadline).fontWeight(.medium)
                                    Spacer()
                                    Text(finding.category.label).font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(finding.evidence, id: \.self) { line in
                                    Text(line).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(finding.fix.kindLabel + ": " + finding.fix.actionText)
                                    .font(.caption)
                            }.padding(.vertical, 4)
                        }
                    } header: { Text(L("Findings")) }
                }
                Section {
                    Button { exportJSON() } label: { Label(L("Export Report (JSON)"), systemImage: "square.and.arrow.up") }
                    Button { exportText() } label: { Label(L("Export Report (Text)"), systemImage: "square.and.arrow.up") }
                } header: { Text(L("Export")) } footer: {
                    Text(L("Exports contain no UDID, serial number or chip ID: the report redacts device identity at construction."))
                }
                Section {
                    Text(L("This report covers the iOS version sentinel, the device read state, the Apple Intelligence chain, monitor differences, the slot baseline, backups, restore reports, the device fingerprint, operation events and monitor staleness. Operation events and restore reports come from this session; the fingerprint comparison needs a stored fingerprint."))
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text(L("What This Report Covers")) }
            } else if isComputing {
                ProgressView(L("Computing diagnostics…"))
            } else {
                ContentUnavailableView(L("Diagnostics Not Available"), systemImage: "stethoscope",
                                       description: Text(L("The report could not be computed.")))
            }
        }
        .navigationTitle(L("Diagnostics Centre"))
        .task { await compute() }
        .refreshable { await compute() }
        .alert(L("Export Failed"), isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button(L("OK"), role: .cancel) { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private func deviceSummary(_ device: DiagnosticsDevice) -> String {
        var parts: [String] = []
        if let model = device.model { parts.append(model) }
        if let build = device.build { parts.append(build) }
        if let region = device.regionCode { parts.append(L("Region") + " " + region) }
        return parts.joined(separator: " · ")
    }

    private func compute() async {
        isComputing = true
        defer { isComputing = false }
        report = await model.diagnosticsReport(
            fingerprintComparison: diagnostics?.fingerprintComparison,
            backupVerifications: diagnostics?.backupVerifications ?? [],
            pendingRestartFeatureIDs: diagnostics?.pendingRestartFeatureIDs ?? [])
    }

    private func exportJSON() {
        guard let report else { return }
        do {
            let data = try report.exportJSON()
            share(TemporaryExport(data: data, name: "LilaShift-Diagnostics.json"))
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func exportText() {
        guard let report else { return }
        do {
            let data = Data(report.exportText().utf8)
            share(TemporaryExport(data: data, name: "LilaShift-Diagnostics.txt"))
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private extension Severity {
    var systemImage: String {
        switch self {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        }
    }

    static func > (lhs: Severity, rhs: Severity) -> Bool {
        lhs.sortOrder > rhs.sortOrder
    }

    var sortOrder: Int {
        switch self {
        case .error: return 2
        case .warning: return 1
        case .info: return 0
        }
    }
}

private extension FindingCategory {
    var label: String {
        switch self {
        case .sentinel: return L("iOS Version")
        case .mgRead: return L("Read")
        case .mgWrite: return L("Write")
        case .compatibility: return L("Compatibility")
        case .conflict: return L("Conflict")
        case .backup: return L("Backup")
        case .restore: return L("Restore")
        case .device: return L("Device")
        }
    }
}
