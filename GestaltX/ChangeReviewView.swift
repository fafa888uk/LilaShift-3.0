// SPDX-License-Identifier: GPL-3.0-only
// Change review sheet, split out of ContentView.swift in Stage 3.
import SwiftUI

struct ChangeReviewView: View {
    var isSheet = true
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.dismiss) private var dismiss
    @State private var asksApply = false
    /// True from the moment the user confirms Apply until `apply()`
    /// returns. While true, the bottom bar shows the apply-progress card
    /// instead of the Apply button.
    @State private var applying = false
    var body: some View {
        Group {
            if isSheet { NavigationStack { contents } } else { contents }
        }
    }
    private var contents: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Check which settings this will update."))
                    .font(.subheadline).foregroundStyle(.secondary)
                GlassCard(cornerRadius: GlassTokens.smallRadius) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(L(model.sourceIsDevice ? "Write to this device" : "Save local document"), systemImage: model.sourceIsDevice ? "iphone" : "doc.text")
                            .font(.headline)
                        Text(L(model.sourceIsDevice ? "Backed up before writing, verified after writing." : "This edits the opened file in LilaShift. Export it to save a copy; the system file is not changed."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let message = model.message {
                    GlassCard(cornerRadius: GlassTokens.smallRadius, tint: Color.red.opacity(0.18)) {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let validationError = model.previewValidationError {
                    GlassCard(cornerRadius: GlassTokens.smallRadius, tint: Color.red.opacity(0.18)) {
                        Text(validationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if model.isChinaUnlockStaged { chinaUnlockSummary }
                fieldChanges
                cacheChanges
                GlassCard(cornerRadius: GlassTokens.smallRadius) {
                    VStack(alignment: .leading, spacing: 4) {
                        Button(L("Back to adjust")) { dismiss() }.disabled(model.isBusy)
                        Divider()
                        Button(L("Discard Changes"), role: .destructive) { model.clearStaged(); dismiss() }.disabled(model.isBusy)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(L("After applying, restart, then check the related entries in system Settings."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("Confirm Changes")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet { ToolbarItem(placement: .cancellationAction) { Button(L("Done")) { dismiss() }.disabled(model.isBusy) } }
            ToolbarItem(placement: .topBarTrailing) { if model.isBusy { ProgressView() } }
        }
        .safeAreaInset(edge: .bottom) { reviewBottomBar }
        .onChange(of: model.isBusy) { _, busy in if applying && !busy { applying = false } }
        .alert(L("Apply these changes?"), isPresented: $asksApply) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Apply")) { applying = true; Task { await model.apply(); applying = false; if model.changeCount == 0 { dismiss() } } }
        } message: { Text(L(model.sourceIsDevice ? "Incorrect system values can affect device behavior. A verified backup will be kept. No restart is triggered automatically." : "The current local document will be backed up before saving your edits.")) }
    }

    /// Fixed glass action bar: change count, data source and backup status
    /// above the apply button. The button label follows the data source
    /// (device vs local file); the official backup / confirm / write /
    /// verify flow behind it is unchanged, and a failed write reports its
    /// error through `model.message` instead of claiming success.
    /// While a write is in progress, the button is replaced by the
    /// apply-progress card (backup → write → verify → done), driven by
    /// the real write flow (see `applyProgressSteps`).
    private var reviewBottomBar: some View {
        GlassBottomBar {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(String(format: L("%lld fields changed"), model.changeCount))
                    Text("•").foregroundStyle(.secondary)
                    Text(L(model.sourceIsDevice ? "On Device" : "Local Document"))
                    Text("•").foregroundStyle(.secondary)
                    backupStatusText
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if applying {
                    GlassApplyProgressCard(
                        title: applyProgressTitle,
                        progress: applyProgressFraction,
                        steps: applyProgressSteps
                    )
                } else {
                    Button(L(model.sourceIsDevice ? "Apply to Device" : "Save Local Changes")) { asksApply = true }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(model.changeCount == 0 || model.isBusy || model.previewValidationError != nil)
                }
            }
        }
    }

    /// Apply progress derived from the real write flow, observed through
    /// the session log. `apply()` logs "[apply]" first; the commit then
    /// emits, in order, "Backup: … saved and verified", "Write: …",
    /// "Readback: comparing …" and "Readback: verified". No step is
    /// shown as done before its marker appears, and a failed step is
    /// shown as failed. Local files have no device write/readback, so
    /// their write and verify steps complete together when the save
    /// returns; nothing here invents a percentage.
    private var applyLogLines: [String] {
        guard let anchor = model.logs.lastIndex(where: { $0.contains("[apply]") }) else { return [] }
        return Array(model.logs[anchor...])
    }
    private var applyBackupDone: Bool {
        applyLogLines.contains { $0.contains("Backup: ") && $0.contains("saved and verified") }
    }
    private var applyVerifyStarted: Bool { applyLogLines.contains { $0.contains("Readback: comparing") } }
    private var applyVerifyDone: Bool { applyLogLines.contains { $0.contains("Readback: verified") } }
    private var applyFailed: Bool {
        applyLogLines.contains { $0.contains("Write/readback failed") || $0.contains("Recovery: restoring") }
    }
    private var applyFinishedOK: Bool { !model.isBusy && model.changeCount == 0 && applying }

    private var applyProgressSteps: [GlassApplyStep] {
        let backupDone = applyBackupDone
        let writeDone = applyVerifyStarted || applyVerifyDone || (applyFinishedOK && !model.sourceIsDevice)
        let verifyDone = applyVerifyDone || (applyFinishedOK && !model.sourceIsDevice)
        let allDone = applyFinishedOK
        func state(done: Bool, isCurrent: Bool) -> ApplyStepState {
            if applyFailed && isCurrent { return .failed }
            if done { return .done }
            return isCurrent ? .current : .pending
        }
        return [
            GlassApplyStep(title: L("Back Up"), state: state(done: backupDone, isCurrent: !backupDone)),
            GlassApplyStep(title: L("Write"), state: state(done: writeDone, isCurrent: backupDone && !writeDone)),
            GlassApplyStep(title: L("Verify"), state: state(done: verifyDone, isCurrent: writeDone && !verifyDone)),
            GlassApplyStep(title: L("Done"), state: state(done: allDone, isCurrent: verifyDone && !allDone)),
        ]
    }

    private var applyProgressFraction: Double {
        Double(applyProgressSteps.filter { $0.state == .done }.count) / 4.0
    }

    private var applyProgressTitle: String {
        let steps = applyProgressSteps
        if steps.allSatisfy({ $0.state == .done }) {
            return String(format: L("Apply Progress (Done %lld/4)"), 4)
        }
        let current = (steps.firstIndex { $0.state != .done } ?? 0) + 1
        return String(format: L("Apply Progress (Writing %lld/4)"), current)
    }

    private var backupStatusText: some View {
        Group {
            if let latest = model.backups.max(by: { $0.date < $1.date }) {
                Text(L("Latest backup")) + Text(" ") + Text(latest.date, style: .date)
            } else {
                Text(L("A backup is created before writing."))
            }
        }
    }

    /// The field keys written by the China Unlock group: the region code
    /// plus the seven AI capability keys.
    private var chinaUnlockFieldKeys: Set<String> {
        var keys = Set(ChinaUnlock.aiCapabilities.flatMap(\.keys))
        keys.insert(GestaltKeys.regionCode)
        return keys
    }

    private var chinaUnlockSummary: some View {
        GlassCard(cornerRadius: GlassTokens.smallRadius) {
            VStack(alignment: .leading, spacing: GlassTokens.rowSpacing) {
                Text(L("China Unlock")).font(.headline)
                summaryRow(
                icon: "simcard", tint: .teal,
                title: "eSIM",
                before: esimBeforeText,
                after: L("Will configure"),
                detail: L("Add a digital SIM in Settings.")
            )
            Divider()
            summaryRow(
                icon: "globe", tint: .lavenderBlue,
                title: L("Region Code"),
                before: regionDisplay(code: model.snapshot?.document.extra[GestaltKeys.regionCode] as? String),
                after: regionAfterText,
                detail: L("Set the device region code for region-locked features.")
            )
            Divider()
            summaryRow(
                icon: "sparkles", tint: .purple,
                title: L("Apple Intelligence"),
                before: "\(aiBeforeCount)/\(ChinaUnlock.aiCapabilities.count)",
                after: L("Configure 7 items"),
                detail: L("Enable seven Apple Intelligence features, including translation, Clean Up and always-listening Hey Siri.")
            )
            DisclosureGroup(L("Technical Details")) {
                ForEach(chinaUnlockFieldKeys.sorted(), id: \.self) { key in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: key).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        valueRow("Before", value: model.snapshot?.document.extra[key])
                        valueRow("After", value: model.preview?.extra[key])
                    }
                    .padding(.vertical, 6)
                }
                ForEach(model.cacheDataChanges.filter { $0.name != "wapi" }) { change in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: change.name).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Text(verbatim: change.keyPathText).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        valueRow("Before", value: NSNumber(value: change.before))
                        valueRow("After", value: NSNumber(value: change.after))
                    }
                    .padding(.vertical, 6)
                }
                unexplainedCacheBytesRow
                Text(L("eSIM requires eSIM hardware.")).font(.caption).foregroundStyle(.secondary)
            }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summaryRow(icon: String, tint: Color, title: String, before: String, after: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: GlassTokens.rowSpacing) {
                GlassIconPedestal(systemImage: icon, tint: tint, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(before).foregroundStyle(.secondary)
                        Text("→").foregroundStyle(.secondary)
                        newValuePill(after)
                    }
                    .font(.subheadline)
                }
            }
            if let detail {
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func newValuePill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.gestaltAccent.opacity(0.12), in: Capsule())
            .foregroundStyle(Color.gestaltAccent)
    }

    private var esimBeforeText: String {
        guard let snapshot = model.snapshot else { return L("Not present") }
        guard let flags = try? DeviceCacheOptions.flags(in: snapshot.document) else { return L("Unsupported") }
        return L(flags == .enabled ? "Configured" : "Not Configured")
    }

    private var aiBeforeCount: Int {
        guard let fields = model.snapshot?.document.extra else { return 0 }
        // Same staged-value rule as `chinaUnlockEnabledAICapabilityIDs`:
        // siriAIMode reads as enabled at SiriMode=2, not 1.
        return ChinaUnlock.aiCapabilities.filter { capability in
            capability.keys.allSatisfy { key in
                guard let field = fields[key] else { return false }
                return GestaltDocument.valuesEqual(field, capability.values[key] ?? capability.enabled)
            }
        }.count
    }

    private func regionDisplay(code: String?) -> String {
        guard let code, !code.isEmpty else { return L("Not present") }
        if let preset = RegionPreset.all.first(where: { $0.code == code }) {
            return "\(L(preset.title))（\(code)）"
        }
        return code
    }

    /// Region row's after-value: the one-tap unlock stages the region
    /// code only, so the after-value is just the LL display string.
    private var regionAfterText: String {
        regionDisplay(code: "LL")
    }

    private var fieldChanges: some View {
        let keys = model.changeKeys.filter { !(model.isChinaUnlockStaged && chinaUnlockFieldKeys.contains($0)) }
        let fieldGroups = Dictionary(grouping: keys, by: reviewTitle)
        let before = model.snapshot?.document.extra
        let after = model.preview?.extra
        return ForEach(fieldGroups.keys.sorted { L($0).localizedStandardCompare(L($1)) == .orderedAscending }, id: \.self) { title in
            let keys = fieldGroups[title, default: []]
            GlassCard(cornerRadius: GlassTokens.smallRadius) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L(title)).font(.headline)
                    if let capability = Capability.all.first(where: { $0.title == title }) {
                    if let choice = model.choices[capability.id], choice != .keep {
                        Text(L(choice.title)).fontWeight(.medium)
                    }
                    Text(L(capability.detail)).font(.subheadline).foregroundStyle(.secondary)
                }
                if title == "Region Code" {
                    LabeledContent(L("Before"), value: before?[GestaltKeys.regionCode] as? String ?? L("Not present"))
                    LabeledContent(L("After"), value: after?[GestaltKeys.regionCode] as? String ?? L("Not present"))
                }
                DisclosureGroup(L("Technical Details")) {
                    ForEach(keys, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: key).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            valueRow("Before", value: before?[key])
                            valueRow("After", value: after?[key])
                        }
                        .padding(.vertical, 6)
                    }
                }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var cacheChanges: some View {
        let changes = model.cacheDataChanges.filter { !(model.isChinaUnlockStaged && $0.name != "wapi") }
        let cacheGroups = Dictionary(grouping: changes) { $0.name == "wapi" ? "WAPI" : "eSIM" }
        return ForEach(cacheGroups.keys.sorted(), id: \.self) { title in
            GlassCard(cornerRadius: GlassTokens.smallRadius) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(verbatim: title).font(.headline)
                    if title == "eSIM" {
                    Text(L(model.isESIMUnlockedInPreview ? "Configured" : "Not Configured")).fontWeight(.medium)
                    Text(L("Add a digital SIM in Settings."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if title == "WAPI" {
                    Text(L("Use the WAPI wireless security standard."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                DisclosureGroup(L("Technical Details")) {
                    ForEach(cacheGroups[title, default: []]) { change in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(verbatim: change.name).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text(verbatim: change.keyPathText).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                            valueRow("Before", value: NSNumber(value: change.before))
                            valueRow("After", value: NSNumber(value: change.after))
                        }
                        .padding(.vertical, 6)
                    }
                    unexplainedCacheBytesRow
                    if title == "eSIM" {
                        Text(L("eSIM requires eSIM hardware.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func reviewTitle(for key: String) -> String {
        switch key {
        case GestaltKeys.regionCode: "Region Code"
        case GestaltKeys.regionInfo, GestaltKeys.legacyRegionInfo: "Sales Region"
        case GestaltKeys.modelNumber: "Model Number"
        default: Capability.all.first { $0.keys.contains(key) }?.title ?? "Other Fields"
        }
    }

    /// Red "other bytes" row for the review sheet: changed CacheData bytes
    /// outside the known slots, with their hex offsets. Visible even
    /// though the write will be refused — that is the point (diagnosis
    /// before Apply). The existing commit auto-rollback is unchanged and
    /// is not duplicated here.
    private var unexplainedCacheBytesRow: some View {
        Group {
            if let diff = model.cacheDataDiff, diff.hasUnexplained {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("Other CacheData bytes changed"))
                        .font(.caption.weight(.semibold)).foregroundStyle(.red)
                    Text(verbatim: diff.unexplainedOffsets.map { String(format: "0x%X", $0) }.joined(separator: ", "))
                        .font(.system(.caption, design: .monospaced)).foregroundStyle(.red)
                    Text(L("Unrelated cache bytes changed — apply will be refused."))
                        .font(.caption).foregroundStyle(.red)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func valueRow(_ title: String, value: Any?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(title)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Text(value.map { PlistValueKind.detect($0).text(for: $0) } ?? L("Not present"))
                .font(.system(.caption, design: .monospaced)).lineLimit(6).textSelection(.enabled)
        }
    }
}
