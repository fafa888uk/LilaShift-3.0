// SPDX-License-Identifier: GPL-3.0-only
// Preset Lab view (A24): try presets in one place. Staging is
// exactly ContentView's stage — `model.choices[id] = choice` —
// and applying is exactly `model.apply()`, the existing SafePatch
// flow (review + backup + readback). The Lab adds no write path
// of its own. Groups and virtual entries are excluded: they have
// dedicated apply paths and must not be double-applied here.
import SwiftUI

struct PresetLabView: View {
    @EnvironmentObject private var model: GestaltManager
    @State private var query = ""
    @State private var confirmingStorage = false
    @State private var pendingStorageChoice: PresetChoice = .enable
    @State private var isApplying = false

    private var entries: [PresetEntry] {
        let stageable = PresetLab.stageableEntries()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return stageable }
        return PresetCatalog.search(query, in: stageable)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GlassTokens.rowSpacing) {
            Text(L("Try presets here before applying them. Staging a preset only marks it for the next apply; nothing is written until you tap Apply, which runs the same review, backup and readback as the main preset page. Groups and virtual entries are not listed here — they have their own apply paths."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(L("Search presets"), text: $query)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            if model.changeCount > 0 {
                HStack {
                    Text("\(L("Staged changes")): \(model.changeCount)")
                        .font(.subheadline)
                    Spacer()
                    Button(L("Apply")) { apply() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(model.isBusy || isApplying)
                }
            }
            List(entries) { entry in
                let capability = Capability.all.first { $0.id == entry.featureID }
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(entry.englishTitle).font(.subheadline)
                        Spacer()
                        if PresetLab.isStaged(id: entry.featureID, in: model) {
                            Text(L("Staged")).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    Text(entry.chineseDescription).font(.caption).foregroundStyle(.secondary)
                    if let capability {
                        Picker(L("Choice"), selection: Binding(
                            get: { PresetLab.stagedChoice(id: entry.featureID, in: model) },
                            set: { stage($0, for: capability) }
                        )) {
                            ForEach(capability.availableChoices, id: \.self) { choice in
                                Text(choice.title).tag(choice)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .listStyle(.plain)
        }
        .padding()
        .background(GlassBackground())
        .navigationTitle(L("Preset Lab"))
        .navigationBarTitleDisplayMode(.large)
        .alert(L("Enable storage preset?"), isPresented: $confirmingStorage) {
            Button(L("Enable"), role: .destructive) { model.choices["storage"] = pendingStorageChoice }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Enabling the storage preset can hide apps from the Home Screen. Only continue if you understand this."))
        }
    }

    private func stage(_ choice: PresetChoice, for capability: Capability) {
        // Mirrors ContentView.stage(_:for:): the storage preset asks
        // first; everything else stages directly.
        if PresetLab.requiresConfirmation(id: capability.id), choice == .enable,
           model.choices[capability.id] != .enable {
            pendingStorageChoice = choice
            confirmingStorage = true
            return
        }
        model.choices[capability.id] = choice
        if capability.id == "dynamicIsland" && choice != .keep { model.subtype = 0 }
    }

    private func apply() {
        isApplying = true
        Task {
            await model.apply()
            isApplying = false
        }
    }
}
