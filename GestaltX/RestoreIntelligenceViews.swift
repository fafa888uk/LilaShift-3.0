// SPDX-License-Identifier: GPL-3.0-only
// Read-only change history and backup verification, with a separate
// confirmation for whole-backup restoration.
import SwiftUI

struct RestoreIntelligenceCard: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.colorScheme) private var colorScheme
    @State private var records: [RecordedChange] = []
    @State private var logCount = 0
    @State private var historyError: String?
    @State private var verifications: [BackupVerification] = []
    @State private var selectedEntry: RestoreTimelineEntry?
    @State private var selectedBackup: BackupRecord?
    @State private var showingAll = false

    private var heroTint: Color {
        colorScheme == .dark
            ? Color(red: 0.16, green: 0.13, blue: 0.28).opacity(0.65)
            : Color.lavenderGlass.opacity(0.65)
    }

    private var timeline: [RestoreTimelineEntry] {
        guard let document = model.working else { return [] }
        let layout = try? MobileGestaltCacheLayout.resolve(in: document)
        return RestoreIntelligence.timeline(
            records: records, snapshot: model.snapshot?.document,
            current: document, layout: layout)
    }

    private var visibleEntries: [RestoreTimelineEntry] {
        showingAll ? timeline : Array(timeline.prefix(5))
    }

    var body: some View {
        GlassCard(cornerRadius: 22, tint: heroTint) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GlassIconPedestal(systemImage: "clock.arrow.circlepath", tint: .gestaltAccent, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Restore Intelligence"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Modification timeline and precise restore, from trusted records only."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if model.working == nil {
                    Text(L("Read the device first to see the modification timeline."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                        Task { await model.connect() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .opacity(model.isBusy ? 0.5 : 1)
                } else {
                    if let historyError {
                        Text(historyError)
                            .font(.subheadline)
                            .foregroundStyle(.orange)
                    }
                    timelineSection
                    backupSection
                    if logCount > 0 {
                        Text(String(format: L("Restore log: %d entries"), logCount))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Text(L("The first-read value is the first-recorded value, never a factory original. Fields with no trusted original never offer a precise restore."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task { reloadHistory() }
        .onChange(of: model.snapshot?.data) { _, _ in reloadHistory() }
        .onChange(of: model.backups) { _, _ in refreshBackupVerification() }
        .sheet(item: $selectedEntry) { entry in
            RestoreEntryDetailView(entry: entry, records: records)
        }
    }

    private func reloadHistory() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else {
            historyError = L("History is unavailable: no installation ID has been recorded yet.")
            records = []
            return
        }
        let store = ChangeRecordStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        do {
            records = try store.load()
            historyError = nil
        } catch {
            records = []
            historyError = L("The change history could not be read. No system changes were made.")
        }
        let logStore = RestoreLogStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        logCount = (try? logStore.load().count) ?? 0
        refreshBackupVerification()
    }

    private func refreshBackupVerification() {
        verifications = RestoreIntelligence.verifyBackups(model.backups, against: model.snapshot?.document)
    }

    @ViewBuilder
    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Modification Timeline"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if timeline.isEmpty {
                Text(L("No modifications recorded and no differences detected."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleEntries) { entry in
                    Button { selectedEntry = entry } label: {
                        timelineRow(entry)
                    }
                    .buttonStyle(.plain)
                }
                if timeline.count > 5 {
                    Button(showingAll ? L("Show Less") : L("Show All")) {
                        showingAll.toggle()
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                }
            }
        }
    }

    @ViewBuilder
    private func timelineRow(_ entry: RestoreTimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(L(entry.title))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    if !entry.isRecordedOperation {
                        Text(L("Detected"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
                HStack(spacing: 4) {
                    Text(entry.original.displayText)
                    Text("→")
                    Text(entry.current?.displayText ?? L("Unknown"))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(entry.provenanceLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if entry.restartVerified {
                        Text(L("Restart verified"))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }
            Spacer()
            Text(statusLabel(entry.status))
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor(entry.status))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor(entry.status).opacity(0.12), in: Capsule())
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Backup Verification"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            if verifications.isEmpty {
                Text(L("No backups stored yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(verifications, id: \.record.id) { verification in
                    let integrityVerified = verification.status == .verified && verification.record.sha256 != nil
                    HStack(spacing: 8) {
                        Image(systemName: integrityVerified
                              ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(integrityVerified ? .green : .orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verification.record.filename)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(backupStatusText(verification))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.sourceIsDevice,
                           verification.permitsDeviceRestore(deviceID: RestoreIntelligence.installationDeviceID) {
                            Button(L("Restore")) {
                                selectedBackup = verification.record
                            }
                            .buttonStyle(GlassPrimaryButtonStyle())
                            .disabled(model.isBusy || model.changeCount > 0)
                        }
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .sheet(item: $selectedBackup) { record in
            FullBackupRestoreView(record: record) { reloadHistory() }
        }
    }

    private func statusLabel(_ status: RestoreTimelineStatus) -> String {
        switch status {
        case .restored: return L("Restored")
        case .pending: return L("In effect")
        case .changed: return L("Changed")
        case .unknown: return L("Unknown")
        }
    }

    private func statusColor(_ status: RestoreTimelineStatus) -> Color {
        switch status {
        case .restored: return .green
        case .pending: return .orange
        case .changed: return .red
        case .unknown: return .secondary
        }
    }

    private func backupStatusText(_ verification: BackupVerification) -> String {
        switch verification.status {
        case .verified:
            guard verification.record.sha256 != nil else {
                return L("Backup could not be verified")
            }
            if let layoutMatches = verification.layoutMatchesCurrent {
                return layoutMatches
                    ? L("Verified. Cache layout matches this device.")
                    : L("Verified, but the cache layout differs from this device.")
            }
            return L("Verified.")
        case .failed(let reason):
            return reason
        case .notFound:
            return L("Backup file not found.")
        }
    }
}

// MARK: - Entry detail + pre-restore preview

private struct RestoreEntryDetailView: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.dismiss) private var dismiss
    let entry: RestoreTimelineEntry
    let records: [RecordedChange]

    /// The recorded change behind this entry, or a synthesized
    /// unverified change for a detected difference (which the
    /// eligibility checker correctly refuses to auto-restore).
    private var change: RecordedChange {
        if let recorded = records.first(where: { $0.id == entry.id }) { return recorded }
        return RecordedChange(
            id: entry.id, date: entry.date,
            deviceID: RestoreIntelligence.installationDeviceID ?? "",
            osBuild: SystemDeviceIdentitySource().osBuild ?? "",
            featureID: entry.featureID, key: entry.key, layer: entry.layer,
            original: entry.original, new: entry.current ?? entry.target,
            backupProvenance: entry.provenance, verified: false,
            restartVerified: false)
    }

    private var preview: RestorePreview? {
        guard let document = model.snapshot?.document else { return nil }
        let layout = try? MobileGestaltCacheLayout.resolve(in: document)
        return RestorePreviewBuilder.build(
            changes: [change], records: [:], current: document, layout: layout)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L(entry.title))
                            .font(.headline)
                        Text(entry.provenanceLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 4) {
                        Text(L("Original") + ": " + entry.original.displayText)
                        Text("→")
                        Text(L("Current") + ": " + (entry.current?.displayText ?? L("Unknown")))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if let item = preview?.items.first {
                        previewSection(item)
                    }
                }
                .padding()
            }
            .navigationTitle(L("Restore Preview"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Close")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func previewSection(_ item: RestoreItemPreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Pre-Restore Diff"))
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 4) {
                Text(L("Current") + ": " + (item.currentValue?.displayText ?? L("Unknown")))
                Text("→")
                Text(L("Restore to") + ": " + item.targetValue.displayText)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(item.reason)
                .font(.subheadline)
                .foregroundStyle(item.risk == .blocked ? .red : .orange)
            if !item.conflicts.isEmpty {
                ForEach(Array(item.conflicts.enumerated()), id: \.offset) { _, conflict in
                    Text(conflict)
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }
            if case .previewOnly(let reason) = item.action {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text(L("Restore path not yet connected for this item."))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Full-backup restore

private struct FullBackupRestoreView: View {
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.dismiss) private var dismiss
    let record: BackupRecord
    let onRestored: () -> Void
    @State private var message: String?
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(record.filename)
                        .font(.headline)
                    Text(String(format: L("Restores the whole device file from this backup (%@)."), record.provenance.displayLabel))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(L("This restores every field in the backup, not just one change."))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(L("The current document is backed up first. Device restores are verified after writing."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(L(isRestoring ? "Restoring…" : "Apply to Device")) {
                        Task { await restore() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(isRestoring || model.isBusy || !model.sourceIsDevice || model.changeCount > 0)
                    if let message {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(L("Restore Backup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Close")) { dismiss() }
                        .disabled(isRestoring)
                }
            }
            .interactiveDismissDisabled(isRestoring)
        }
    }

    private func restore() async {
        guard !isRestoring, !model.isBusy, model.sourceIsDevice, model.changeCount == 0 else { return }
        isRestoring = true
        defer { isRestoring = false }
        message = nil
        if await model.restore(record) {
            onRestored()
            dismiss()
        } else {
            message = model.message
            model.message = nil
        }
    }
}
