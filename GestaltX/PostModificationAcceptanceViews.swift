// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct PostModificationAcceptanceCard: View {
    @EnvironmentObject private var model: GestaltManager
    @State private var manualRestart = false
    @State private var showingSiriSettings = false

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius) {
            VStack(alignment: .leading, spacing: 14) {
                Text(L("Post-Modification Acceptance")).font(.headline)
                Button(L("Reconnect and read the device")) {
                    Task { await model.connect() }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(model.isBusy || model.changeCount > 0)
                if let error = model.persistenceError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if let baseline = model.deviceBaseline, let read = model.devicePersistenceRead {
                    evidence(baseline: baseline, read: read)
                } else {
                    if model.matchingPersistenceWrite != nil {
                        Text(L("Device file write verified")).font(.subheadline)
                    }
                    Text(L("A fresh device read is required for persistence diagnostics."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(GlassTokens.cardPadding)
        }
        .onChange(of: model.persistenceWrite?.writtenAt) { _, _ in manualRestart = false }
        .sheet(isPresented: $showingSiriSettings) {
            SiriObservationForm(settings: model.siriSettings) { model.saveSiriSettings($0) }
        }
    }

    @ViewBuilder
    private func evidence(baseline: DeviceBaseline, read: DevicePersistenceRead) -> some View {
        let report = model.persistenceAcceptance(manual: manualRestart)
        let restart = model.restartEvidence(manual: manualRestart)
        Text(report.summary).font(.subheadline)
        if restart == .unknown || restart == .manualWithFreshRead {
            Toggle(L("I restarted before this device read"), isOn: $manualRestart).font(.subheadline)
        }
        if !report.items.isEmpty {
            Text(String(format: L("File persisted %d · System confirmed %d · System disagrees %d"),
                        report.filePersistedCount, report.systemConfirmedCount, report.systemDisagreesCount))
                .font(.caption)
            DisclosureGroup(L("Written fields")) {
                ForEach(report.items) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title).font(.subheadline.weight(.medium))
                        Text(item.status.title)
                        if item.restartEvidence.hasPostRestartRead && item.outcome == .changed {
                            Text(L("The target file value was replaced by a different value."))
                        }
                        Text(String(format: L("Target %@ · File %@ · Live %@"),
                                    item.target.displayText, item.current?.displayText ?? L("Unknown"),
                                    item.liveValue?.displayText ?? L("Unknown")))
                    }
                    .font(.caption)
                    .padding(.vertical, 3)
                }
            }
        }
        DisclosureGroup(L("Cache fingerprints")) {
            fingerprint(baseline.fingerprint, title: L("First read"))
            if let write = model.matchingPersistenceWrite {
                fingerprint(write.fingerprint, title: L("After verified write"))
                comparison(write.fingerprint.compare(to: read.fingerprint))
            } else {
                comparison(baseline.fingerprint.compare(to: read.fingerprint))
            }
            fingerprint(read.fingerprint, title: L("Current device read"))
        }
        DisclosureGroup(L("Apple Intelligence key diagnostics")) {
            ForEach(model.aiKeyDiagnostics(manual: manualRestart)) { item in
                AIKeyDiagnosticRow(item: item)
            }
        }
        siriReport(baseline: baseline, read: read)
        Text(AcceptanceReport.disclaimer).font(.caption).foregroundStyle(.secondary)
    }

    private func fingerprint(_ fingerprint: CacheFingerprint, title: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.medium))
            Text(fingerprint.observedScope)
            Text("UUID \(fingerprint.cacheUUID ?? L("Unknown"))")
            Text("SHA-256 \(fingerprint.fileSHA256)").textSelection(.enabled)
            Text(String(format: L("File bytes %d · CacheData bytes %@"), fingerprint.fileSize,
                        fingerprint.cacheDataLength.map(String.init) ?? L("Unknown")))
            if let layout = fingerprint.layout {
                Text(String(format: L("Slots %d · eSIM %d/%d · WAPI %@ · Audio %@ · Translator %@"),
                            layout.slotCount, layout.greenTeaIndex, layout.notGreenTeaIndex,
                            layout.wapiIndex.map(String.init) ?? L("Unknown"),
                            layout.audioIntellIndex.map(String.init) ?? L("Unknown"),
                            layout.personalTranslatorIndex.map(String.init) ?? L("Unknown")))
            } else {
                Text(L("Dynamic layout unknown"))
            }
        }
        .font(.caption)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func comparison(_ result: CacheFingerprintComparison) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if result.rebuildEvidence { Text(L("File replacement and cache generation evidence are consistent with a rebuild.")) }
            if result.fileReplaced == true { Text(L("File identity changed.")) }
            if result.uuidChanged { Text(L("CacheUUID changed.")) }
            if result.bytesChanged { Text(L("Cache file bytes changed.")) }
            if result.layoutChanged { Text(L("Cache layout or CacheData length changed.")) }
            if result.layoutResolutionChanged { Text(L("Dynamic layout resolution changed.")) }
        }
        .font(.caption)
    }

    private func siriReport(baseline: DeviceBaseline, read: DevicePersistenceRead) -> some View {
        let settings = model.siriSettings
        let siri = SiriBetaStatus(nativeHardware: DeviceAIEligibility.isNativeAppleIntelligence(productType: baseline.productType),
                                  osVersion: SystemDeviceIdentitySource().osVersion,
                                  deviceLanguage: Locale.preferredLanguages.first, settings: settings)
        return DisclosureGroup(L("Siri and Apple Intelligence status")) {
            VStack(alignment: .leading, spacing: 6) {
                field(L("Traditional Siri in Settings"), manual(settings.traditionalSiriEnabled))
                field(L("On-Device Siri CacheExtra"),
                      PlistObservation(read.snapshot.document.extra[ChinaUnlock.onDeviceSiriKey]).display)
                field(L("On-Device Siri live answer"), read.liveProbeResults[ChinaUnlock.onDeviceSiriKey]?.display)
                Text(L("The one-tap preset preserves the On-Device Siri value."))
                field(L("Apple Intelligence in Settings"), manual(settings.appleIntelligenceEnabled))
                field(L("Siri AI Beta"), siri.outcome.title)
                field(L("Hardware"), siri.nativeHardware ? L("Native Apple Intelligence hardware") : L("Unsupported hardware"))
                field("iOS", siri.osVersion)
                field(L("Device language"), siri.deviceLanguage)
                field(L("Siri language"), settings.confirmedSiriLanguage.map { "\($0) (\(L("User provided")))" })
                field(L("Apple Account region"), settings.confirmedRegion.map { "\($0) (\(L("User provided")))" })
                field(L("Beta entry"), manual(settings.betaEntry))
                field(L("Beta enabled"), manual(settings.betaEnabled))
                field(L("Waitlist joined"), manual(settings.joinedWaitlist))
                field(L("Voice configured"), manual(settings.voiceConfigured))
                field(L("Model downloaded"), manual(settings.modelDownloaded))
                Button(L("Record Settings observations")) { showingSiriSettings = true }
            }
            .font(.caption)
        }
    }

    private func manual(_ value: Bool?) -> String? {
        value.map { "\($0 ? L("Yes") : L("No")) (\(L("User provided")))" }
    }

    private func field(_ label: String, _ value: String?) -> some View {
        LabeledContent(label, value: value ?? L("Pending user confirmation"))
    }
}

struct AIKeyDiagnosticRow: View {
    let item: AIKeyDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L(item.title)).font(.subheadline.weight(.medium))
            Text(item.key).font(.caption.monospaced()).textSelection(.enabled)
            LabeledContent(L("Observed model and build"), value: item.observedScope)
            if item.nativeHardware { Text(L("Native Apple Intelligence hardware")) }
            LabeledContent(L("Original value and type"), value: item.original.display)
            LabeledContent(L("Current file value"), value: item.file.display)
            LabeledContent(L("Current MG answer"), value: item.live?.display ?? L("Unknown"))
            LabeledContent(L("Target"), value: item.target?.displayText ?? L("No target written"))
            LabeledContent(L("File after restart"), value: item.postRestartFile?.display ?? L("Unknown"))
            LabeledContent(L("Live after restart"), value: item.postRestartLive?.display ?? L("Unknown"))
            if item.target != nil { Text(item.status.title) }
            if item.key == DeviceCacheOptions.audioIntelligenceKey || item.key == DeviceCacheOptions.personalTranslatorKey {
                LabeledContent(L("CacheData slot"), value: item.cacheDataSlot.map(String.init) ?? L("Unknown"))
                LabeledContent(L("First-read CacheData slot"), value: item.originalCacheDataSlot.map(String.init) ?? L("Unknown"))
                if let slot = item.cacheDataSlot, item.live?.capabilityBoolean == slot, item.file.capabilityBoolean != slot {
                    Text(L("The system answer agrees with the resolved CacheData slot. The effective configuration layer remains unverified."))
                }
            }
            if item.key == DeviceCacheOptions.audioIntelligenceKey,
               item.observedScope.hasPrefix(DeviceAIEligibility.persistenceProductType + " /") {
                Text(AIStagingGuard.targetAudioWarning).foregroundStyle(.orange)
            }
        }
        .font(.caption)
        .padding(.vertical, 5)
    }
}

private struct SiriObservationForm: View {
    @Environment(\.dismiss) private var dismiss
    @State var settings: SiriSettingsObservation
    let save: (SiriSettingsObservation) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Text(L("Check Apple Intelligence & Siri and your Apple Account country or region in Settings. Enter the observed values."))
                TextField(L("Apple Account region (ISO code, e.g. CN or US)"), text: $settings.appleAccountRegion)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                TextField(L("Siri language (e.g. en-US or zh-CN)"), text: $settings.siriLanguage)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                answer(L("Traditional Siri enabled"), $settings.traditionalSiriEnabled)
                answer(L("Apple Intelligence enabled"), $settings.appleIntelligenceEnabled)
                answer(L("Beta entry"), $settings.betaEntry)
                answer(L("Beta enabled"), $settings.betaEnabled)
                answer(L("Waitlist joined"), $settings.joinedWaitlist)
                answer(L("Voice configured"), $settings.voiceConfigured)
                answer(L("Model downloaded"), $settings.modelDownloaded)
            }
            .navigationTitle(L("Settings observations"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save")) { save(settings); dismiss() }
                        .disabled(!settings.appleAccountRegion.isEmpty && settings.confirmedRegion == nil)
                }
            }
        }
    }

    private func answer(_ title: String, _ value: Binding<Bool?>) -> some View {
        Picker(title, selection: value) {
            Text(L("Unknown")).tag(nil as Bool?)
            Text(L("Yes")).tag(true as Bool?)
            Text(L("No")).tag(false as Bool?)
        }
    }
}
