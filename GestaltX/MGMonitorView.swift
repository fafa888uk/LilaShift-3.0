// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// The realtime MobileGestalt monitor (Stage 4): every database key
/// with its three sources side by side — first-read (original),
/// staged (working document), and live MGCopyAnswer — plus the
/// CacheData slot probe for slot keys and the per-key compatibility
/// badge. The monitor refreshes on demand only (no timer polls the
/// device). On a sentinel-blocked build it shows the "not granted on
/// this iOS version" banner with stay/downgrade guidance, never an
/// empty list.
struct MGMonitorView: View {
    @EnvironmentObject private var model: GestaltManager
    @State private var query = ""
    @State private var showDifferencesOnly = false

    private var filteredRows: [MGMonitorRow] {
        let rows = model.monitorRows
        let matching = query.isEmpty ? rows : rows.filter { row in
            MGDatabase.search(query).contains(row.record)
        }
        return showDifferencesOnly ? matching.filter(\.hasDifference) : matching
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GlassTokens.rowSpacing) {
            Text(L("Every database key, live: the first-read value, the staged value, and the live system answer side by side. A difference means a change is staged, or the live answer disagrees with it."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            sentinelBanner
            HStack {
                TextField(L("Search keys"), text: $query)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                Button(L("Refresh")) {
                    Task { await model.refreshMonitor() }
                }
            }
            Toggle(L("Differences only"), isOn: $showDifferencesOnly)
            if let readAt = model.monitorReadAt {
                Text(L("Live values read at") + " " + readAt.formatted(date: .omitted, time: .shortened)
                     + (model.monitorRows.contains(where: \.isStale) ? " · " + L("stale") : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.monitorRows.isEmpty {
                Text(L("No monitor data yet — tap Refresh."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if filteredRows.isEmpty {
                Text(L("No keys match this filter."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                List(filteredRows, id: \.record.obfuscatedName) { row in
                    MGMonitorRowView(row: row)
                }
                .listStyle(.plain)
            }
        }
        .padding()
        .background(GlassBackground())
        .navigationTitle(L("MG Monitor"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear {
            Task { await model.refreshMonitor() }
        }
    }

    @ViewBuilder
    private var sentinelBanner: some View {
        switch model.monitorSentinel {
        case .supported:
            EmptyView()
        case .blocked(let build):
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Not granted on this iOS version.") + " (\(L("build")) \(build)).")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let guidance = VersionSentinel.guidance(for: model.monitorSentinel) {
                    Text(guidance).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(GlassBackground())
        case .unknownBuild:
            VStack(alignment: .leading, spacing: 4) {
                Text(L("The iOS build could not be confirmed."))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                if let guidance = VersionSentinel.guidance(for: model.monitorSentinel) {
                    Text(guidance).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
            .background(GlassBackground())
        }
    }
}

private struct MGMonitorRowView: View {
    let row: MGMonitorRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.record.readableName).font(.subheadline)
                if row.hasDifference {
                    Text(L("Changed")).font(.caption2).fontWeight(.semibold)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(GlassTokens.heroTint.opacity(0.15))
                        .clipShape(Capsule())
                }
                Spacer(minLength: 8)
                Text(row.compatibility.title).font(.caption).foregroundStyle(.secondary)
            }
            Text(row.record.obfuscatedName).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            Text(row.compatibilityReason).font(.caption).foregroundStyle(.secondary)
            sourceRow(label: L("Original"), value: row.original, absentText: L("Absent"))
            sourceRow(label: L("Staged"), value: row.staged, absentText: L("Absent"))
            sourceRow(label: L("Live"), value: row.live, absentText: L("Unreadable"))
            if let slot = row.slot {
                slotSection(slot: slot)
            }
        }
    }

    private func sourceRow(label: String, value: MGValue?, absentText: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .leading)
            Text(value?.displayText ?? absentText)
                .font(.caption).foregroundStyle(value == nil ? .tertiary : .primary)
                .textSelection(.enabled)
        }
    }

    @ViewBuilder
    private func slotSection(slot: MGSlotProbe) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(L("Slot")) \(slot.slotNumber)").font(.caption).fontWeight(.semibold)
            slotByteRow(label: L("Original"), value: slot.originalByte)
            slotByteRow(label: L("Staged"), value: slot.stagedByte)
            slotByteRow(label: L("Live"), value: slot.liveAnswer)
            if let nativeBaseline = slot.nativeBaseline {
                Text("\(L("Native baseline")): \(nativeBaseline ? "true" : "false")")
                    .font(.caption).foregroundStyle(.secondary)
                if slot.disagreesWithNativeBaseline == true {
                    Text(L("The live answer disagrees with the native baseline."))
                        .font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    private func slotByteRow(label: String, value: Bool?) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.tertiary)
                .frame(width: 64, alignment: .leading)
            Text(value.map { $0 ? "true" : "false" } ?? L("Unknown"))
                .font(.caption).foregroundStyle(value == nil ? .tertiary : .primary)
        }
    }
}
