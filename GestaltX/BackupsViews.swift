// SPDX-License-Identifier: GPL-3.0-only
// Backups view, split out of ContentView.swift in Stage 3.
import SwiftUI

struct BackupsView: View {
    let share: (TemporaryExport) -> Void
    @EnvironmentObject private var model: GestaltManager
    @State private var restores: BackupRecord?
    @State private var deletes: BackupRecord?
    @State private var hardwareRestores: BackupRecord?
    @State private var confirmsRebuild = false
    var body: some View {
        List {
            Section {
                Button { Task { await model.backup() } } label: { Label(L("Create Backup"), systemImage: "plus.circle.fill") }
                    .disabled(!model.hasDocument || model.isBusy)
            } footer: {
                if model.changeCount > 0 {
                    Text(L("Save or discard your current changes before opening another plist."))
                }
            }
            Section {
                Button(L("Clear & Rebuild Cache"), role: .destructive) { confirmsRebuild = true }
                    .disabled(!model.hasDocument || !model.sourceIsDevice || model.isBusy || model.changeCount > 0)
            } footer: {
                Text(L("Deletes the system cache so iOS rebuilds it from the hardware on restart. A backup is taken first."))
            }
            if model.backups.isEmpty {
                ContentUnavailableView(L("No Backups"), systemImage: "externaldrive.badge.timemachine", description: Text(L("A backup is created before each write.")))
            }
            ForEach(model.backups) { record in
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: record.source == .device ? "iphone" : "doc.text").foregroundStyle(Color.gestaltAccent)
                            Text(L(record.reason)).fontWeight(.medium)
                            Spacer()
                        }
                        Text(record.date, format: .dateTime.year().month().day().hour().minute().second()).font(.subheadline)
                        Text(record.provenanceLabel).font(.caption).foregroundStyle(.secondary)
                        Text(L(record.source == .device ? "Device Backup" : "Local File Backup") + " · " + ByteCountFormatter.string(fromByteCount: Int64(record.byteCount), countStyle: .file))
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(L("Open")) { Task { await model.openBackup(record) } }
                                .disabled(model.changeCount > 0)
                            Spacer()
                            Button(L("Export")) { Task { if let url = await model.exportBackup(record) { share(url) } } }
                            Spacer()
                            Button(L("Restore")) { restores = record }
                                .disabled(model.changeCount > 0 || !model.hasDocument || (model.sourceIsDevice && record.source != .device))
                        }.font(.subheadline).buttonStyle(.borderless).padding(.top, 6)
                        // Face ID recovery: restore only the four
                        // hardware-identity fields from a verified
                        // same-device backup, keeping AI and region.
                        // Only a device backup with a recorded digest
                        // can prove it belongs to this device.
                        if record.source == .device && record.sha256 != nil {
                            Button(L("Restore Hardware Identity")) { hardwareRestores = record }
                                .disabled(model.changeCount > 0 || !model.hasDocument)
                                .font(.subheadline).buttonStyle(.borderless).padding(.top, 2)
                        }
                    }.padding(.vertical, 6)
                }.swipeActions(allowsFullSwipe: false) { Button(L("Delete")) { deletes = record }.tint(.red) }
            }
        }
        .navigationTitle(L("Backups")).disabled(model.isBusy)
        .task { await model.reloadBackups() }
        .refreshable { await model.reloadBackups() }
        .alert(L("Restore this backup?"), isPresented: Binding(get: { restores != nil }, set: { if !$0 { restores = nil } })) {
            Button(L("Cancel"), role: .cancel) { restores = nil }
            Button(L("Restore")) { if let record = restores { Task { await model.restore(record) } }; restores = nil }
                .disabled(model.isBusy || model.changeCount > 0)
        } message: {
            if let record = restores {
                Text(record.provenanceLabel + "\n" + L("The current document is backed up first. Device restores are verified after writing."))
            } else {
                Text(L("The current document is backed up first. Device restores are verified after writing."))
            }
        }
        .alert(L("Delete this backup?"), isPresented: Binding(get: { deletes != nil }, set: { if !$0 { deletes = nil } })) {
            Button(L("Cancel"), role: .cancel) { deletes = nil }
            Button(L("Delete"), role: .destructive) { if let record = deletes { Task { await model.deleteBackup(record) } }; deletes = nil }
        } message: { Text(L("This removes the local backup permanently. It does not change the device file.")) }
        .alert(L("Restore Hardware Identity"), isPresented: Binding(get: { hardwareRestores != nil }, set: { if !$0 { hardwareRestores = nil } })) {
            Button(L("Cancel"), role: .cancel) { hardwareRestores = nil }
            Button(L("Restore"), role: .destructive) { if let record = hardwareRestores { Task { await model.restoreHardwareIdentity(from: record) } }; hardwareRestores = nil }
                .disabled(model.isBusy || model.changeCount > 0)
        } message: {
            Text(L("Restore only the original product, board, CPU and model number from this backup. AI and region settings are kept. Restart and test Face ID and dictation afterward."))
        }
        .alert(L("Clear & Rebuild Cache"), isPresented: $confirmsRebuild) {
            Button(L("Cancel"), role: .cancel) { }
            Button(L("Clear & Rebuild Cache"), role: .destructive) { Task { await model.rebuildCache() } }
                .disabled(model.isBusy || model.changeCount > 0)
        } message: {
            Text(L("Deletes the system cache so iOS rebuilds it from the hardware on restart. A backup is taken first."))
        }
    }
}
