// SPDX-License-Identifier: GPL-3.0-only
// MG Control (FieldsView + FieldEditorView), split out of ContentView.swift in Stage 3.
import SwiftUI

struct FieldsView: View {
    @EnvironmentObject private var model: GestaltManager
    @State private var search = ""
    @State private var draft: FieldDraft?
    @State private var deletesKey: String?
    /// Debounced search text: the key list filters on the published
    /// value, so fast typing rebuilds the filtered list once per
    /// pause instead of once per keystroke.
    @StateObject private var searchDebouncer = SearchDebouncer()
    /// Keys matching the search, from one preview snapshot. Takes
    /// the snapshot as a parameter so the body can build the preview
    /// once per evaluation and share it between the list and every
    /// row, instead of rebuilding the complete document per row.
    private func keys(in extra: [String: Any]) -> [String] {
        // Preview applies staged presets. Reuse one snapshot while filtering so each value
        // lookup does not rebuild the complete document on the main actor.
        let query = searchDebouncer.debounced
        return extra.keys.sorted().filter { key in
            query.isEmpty || key.localizedCaseInsensitiveContains(query) || valueText(key, in: extra).localizedCaseInsensitiveContains(query)
        }
    }
    private func valueText(_ key: String, in extra: [String: Any] = [:]) -> String {
        // Uses only the passed snapshot: the old fallback rebuilt
        // the preview here when the snapshot was empty, which put
        // a document build back into every row.
        guard let value = extra[key] else { return "" }
        let type = PlistValueKind.detect(value)
        if type == .data { return String(format: L("%lld bytes"), Int64((value as? Data)?.count ?? 0)) }
        return type.text(for: value)
    }
    var body: some View {
        // One preview build per body evaluation: the key list, the
        // row buttons and the row value texts all read this one
        // snapshot instead of rebuilding the document per row.
        let extra = model.preview?.extra ?? [:]
        let visibleKeys = keys(in: extra)
        return List {
            if !model.hasDocument {
                ContentUnavailableView(L("No Document Open"), systemImage: "doc.text.magnifyingglass", description: Text(L("Read MobileGestalt in Tools, or share this device's plist to LilaShift.")))
            } else {
                Section {
                    ForEach(visibleKeys, id: \.self) { key in
                        Button {
                            guard let value = extra[key] else { return }
                            let kind = PlistValueKind.detect(value)
                            draft = FieldDraft(originalKey: key, key: key, kind: kind, text: kind.text(for: value), originalValue: value)
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(key).font(.system(.subheadline, design: .monospaced)).foregroundStyle(.primary).lineLimit(2)
                                    Spacer(minLength: 4)
                                    if let value = extra[key] {
                                        Text(L(PlistValueKind.detect(value).rawValue)).font(.caption2).foregroundStyle(Color.gestaltAccent)
                                    }
                                }
                                Text(valueText(key, in: extra)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }.padding(.vertical, 5)
                        }
                        .swipeActions(allowsFullSwipe: false) { Button(L("Delete")) { deletesKey = key }.tint(.red) }
                    }
                } header: { Text("CacheExtra") }
                if visibleKeys.isEmpty { ContentUnavailableView.search(text: search) }
            }
        }
        .navigationTitle(L("MG Control"))
        .searchable(text: $search, prompt: L("Search keys and values"))
        .onChange(of: search) { _, newValue in searchDebouncer.submit(newValue) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { draft = FieldDraft() } label: { Image(systemName: "plus").accessibilityLabel(L("Add Field")) }
                    .disabled(!model.hasDocument || model.isBusy)
            }
        }
        .sheet(item: $draft) { FieldEditorView(draft: $0).environmentObject(model) }.disabled(model.isBusy)
        .alert(L("Delete this field?"), isPresented: Binding(get: { deletesKey != nil }, set: { if !$0 { deletesKey = nil } })) {
            Button(L("Cancel"), role: .cancel) { deletesKey = nil }
            Button(L("Delete"), role: .destructive) { if let key = deletesKey { model.removeField(key) }; deletesKey = nil }
        } message: { Text(L("The deletion is staged. The device file changes only after you apply.")) }
    }
}

struct FieldEditorView: View {
    @State var draft: FieldDraft
    @State private var error: String?
    @EnvironmentObject private var model: GestaltManager
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section(L("Key")) {
                    TextField(L("Field Key"), text: $draft.key).font(.system(.subheadline, design: .monospaced))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                Section(L("Value")) {
                    Picker(L("Type"), selection: $draft.kind) { ForEach(PlistValueKind.allCases) { Text(L($0.rawValue)).tag($0) } }
                    TextEditor(text: $draft.text).font(.system(.subheadline, design: .monospaced))
                        .frame(minHeight: 150).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if draft.kind == .array || draft.kind == .dictionary {
                    Section { Text(L("Use an XML plist fragment, including the array or dict tags. Nested data and numeric types are preserved.")).font(.footnote).foregroundStyle(.secondary) }
                } else if draft.kind == .data {
                    Section { Text(L("Data values use Base64 encoding.")).font(.footnote).foregroundStyle(.secondary) }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.footnote) } }
            }
            .navigationTitle(L(draft.originalKey == nil ? "Add Field" : "Edit Field"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(L("Cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Stage")) {
                        do { try model.stage(draft); dismiss() } catch { self.error = error.localizedDescription }
                    }.fontWeight(.semibold)
                }
            }
        }
    }
}
