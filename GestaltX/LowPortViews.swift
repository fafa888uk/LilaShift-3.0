// SPDX-License-Identifier: GPL-3.0-only
// LOW port views (A16/A17/A19/A20/A21/A22/A23): read-only diagnostics
// and reversible tooling, surfaced under Tools > Advanced &
// Diagnostics. Nothing here writes to the MobileGestalt cache or to
// any system database; the only writes are the asset-tag apply
// (one field in the device-configuration plist, reversible) and the
// dialer-skin apply (keypad PNGs in the Phone container, backed up
// beside themselves and restorable).
import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - A16 Voice memo export

struct VoiceMemoExportView: View {
    @State private var recordings: [VoiceMemoExport.Recording] = []
    @State private var selected: Set<String> = []
    @State private var isScanning = false
    @State private var export: TemporaryExport?
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Your own Voice Memos recordings, read-only. Only the recordings the app can legitimately reach through the Voice Memos container are listed; nothing is deleted or modified. Export writes a ZIP of the selected recordings so you can share or back them up."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isScanning {
                    ProgressView(L("Scanning recordings…"))
                } else if recordings.isEmpty {
                    Text(L("No Voice Memos recordings were found."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    GlassCard(cornerRadius: GlassTokens.cardRadius) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recordings) { recording in
                                Button {
                                    if selected.contains(recording.id) { selected.remove(recording.id) }
                                    else { selected.insert(recording.id) }
                                } label: {
                                    HStack {
                                        Image(systemName: selected.contains(recording.id) ? "checkmark.circle.fill" : "circle")
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(recording.displayTitle).font(.subheadline)
                                            Text("\(recording.durationSeconds.map { VoiceMemoExport.formatDuration($0) } ?? L("Unknown duration")) · \(ByteCountFormatter.string(fromByteCount: recording.fileSizeBytes, countStyle: .file))")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                    HStack {
                        Button(L("Export Selected")) { exportRecordings(selected) }
                            .buttonStyle(GlassPrimaryButtonStyle())
                            .disabled(selected.isEmpty)
                        Button(L("Export All")) { exportRecordings(Set(recordings.map(\.id))) }
                            .buttonStyle(GlassPrimaryButtonStyle())
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Button(L("Scan Again")) { scan() }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(isScanning)
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("Voice Memo Export"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(item: $export) { ShareSheet(export: $0) }
        .task { scan() }
    }

    private func scan() {
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let roots = VoiceMemoExport.discoverRoots()
            let list = VoiceMemoExport.recordings(in: roots)
            await MainActor.run {
                recordings = list
                selected = Set(list.map(\.id))
                isScanning = false
                if roots.isEmpty {
                    message = L("The Voice Memos container could not be opened on this device.")
                }
            }
        }
    }

    private func exportRecordings(_ ids: Set<String>) {
        let chosen = recordings.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        Task.detached(priority: .userInitiated) {
            do {
                let zipURL = try VoiceMemoExport.zipRecordings(chosen)
                let made = try TemporaryExport(copying: zipURL, name: zipURL.lastPathComponent)
                try? FileManager.default.removeItem(at: zipURL)
                await MainActor.run { export = made }
            } catch {
                await MainActor.run { message = error.localizedDescription }
            }
        }
    }
}

// MARK: - A20 Model cache probe

struct ModelCacheProbeView: View {
    @State private var items: [ModelCacheProbe.Item] = []
    @State private var isProbing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Which Apple Intelligence model caches are actually present on this device, read-only. The probe reports only what it finds — it never guesses a model is present."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isProbing {
                    ProgressView(L("Probing model caches…"))
                } else if !items.isEmpty {
                    let accessible = items.filter(\.accessible)
                    let totalFiles = accessible.reduce(0) { $0 + $1.fileCount }
                    let totalBytes = accessible.reduce(Int64(0)) { $0 + $1.totalBytes }
                    GlassCard(cornerRadius: GlassTokens.cardRadius) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Summary"))
                                .font(.headline)
                            LabeledContent(L("Containers with caches"), value: "\(accessible.count) / \(items.count)")
                            LabeledContent(L("Total files"), value: "\(totalFiles)")
                            LabeledContent(L("Total size"), value: ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                        }
                    }
                    ForEach(items) { item in
                        GlassCard(cornerRadius: GlassTokens.cardRadius) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.title).font(.headline)
                                if item.accessible {
                                    LabeledContent(L("Files"), value: "\(item.fileCount)")
                                    LabeledContent(L("Size"), value: ByteCountFormatter.string(fromByteCount: item.totalBytes, countStyle: .file))
                                    if item.fileCount == 0 {
                                        Text(L("No model caches found here."))
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text(item.statusNote)
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Text(L("Only the readable system translation, voice-memo transcription and visual-analysis container caches are counted. The Apple Intelligence core model weights live in the MobileAsset read-only volume managed by protected daemons, so this probe does not and cannot report them."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button(L("Probe Again")) { probe() }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(isProbing)
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("Model Cache Probe"))
        .navigationBarTitleDisplayMode(.large)
        .task { probe() }
    }

    private func probe() {
        isProbing = true
        Task.detached(priority: .userInitiated) {
            let found = ModelCacheProbe.probe()
            await MainActor.run { items = found; isProbing = false }
        }
    }
}

// MARK: - A19 Asset tag

struct AssetTagView: View {
    @State private var current: String?
    @State private var draft = ""
    @State private var isLoading = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("The asset tag is the text shown at the bottom of the Lock Screen (for example an owner or organization label). It is stored in the device-configuration plist and can be removed again at any time."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                GlassCard(cornerRadius: GlassTokens.cardRadius) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Current Asset Tag")).font(.headline)
                        Text(current ?? L("Not set"))
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                TextField(L("Asset tag"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                HStack {
                    Button(L("Apply")) { apply() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                    Button(L("Remove")) { remove() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(current == nil || isLoading)
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Button(L("Refresh")) { load() }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(isLoading)
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("Asset Tag"))
        .navigationBarTitleDisplayMode(.large)
        .task { load() }
    }

    private func load() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let value = AssetTag.read()
            await MainActor.run {
                current = value
                if draft.isEmpty { draft = value ?? "" }
                isLoading = false
            }
        }
    }

    private func apply() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let ok = AssetTag.apply(draft)
            let value = AssetTag.read()
            await MainActor.run {
                current = value
                message = ok
                    ? L("Asset tag applied. Restart the device to see it on the Lock Screen.")
                    : L("The asset tag could not be applied on this device.")
                isLoading = false
            }
        }
    }

    private func remove() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let ok = AssetTag.apply("")
            await MainActor.run {
                if ok {
                    current = nil
                    draft = ""
                    message = L("Asset tag removed. Restart the device to see the change.")
                } else {
                    message = L("The asset tag could not be removed on this device.")
                }
                isLoading = false
            }
        }
    }
}

// MARK: - A18 Dialer skin

/// One keypad button cell: the staged replacement image if there is
/// one, else the current artwork, else a numbered placeholder.
/// A separate view (rather than inline in `DialerSkinView.body`) so
/// the compiler type-checks the grid cell on its own — the combined
/// expression timed out in Release builds.
private struct DialerKeypadButton: View {
    let key: DialerSkin.KeypadID
    let data: Data?
    let circle: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                if let data, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .clipShape(circle ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 12)))
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.15))
                        Text(key.keyNumber).font(.title2)
                    }
                    .frame(width: 64, height: 64)
                }
                Text(key.keyNumber).font(.caption).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

struct DialerSkinView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var container: URL?
    @State private var current: [DialerSkin.KeypadID: Data] = [:]
    @State private var replacements: [DialerSkin.KeypadID: Data] = [:]
    @State private var circle = false
    @State private var pickingKey: DialerSkin.KeypadID?
    @State private var pickerItem: PhotosPickerItem?
    @State private var importingTheme = false
    @State private var isBusy = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Custom images for the Phone app keypad buttons, staged the same way as launch images: every replaced file is backed up beside itself and can be restored. This is not a system-wide dialer theme — iOS has no public API for that — it replaces the cached button artwork the Phone app reads. After applying, toggle the appearance or restart the device; never force-quit the Phone app."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if container == nil {
                    Text(L("The Phone app container could not be opened on this device."))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Toggle(L("Circular buttons"), isOn: $circle)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 12)], spacing: 12) {
                        ForEach(DialerSkin.KeypadID.allCases, id: \.self) { key in
                            DialerKeypadButton(
                                key: key,
                                data: replacements[key] ?? current[key],
                                circle: circle
                            ) { pickingKey = key }
                        }
                    }
                    HStack {
                        Button(L("Apply")) { apply() }
                            .buttonStyle(GlassPrimaryButtonStyle())
                            .disabled(replacements.isEmpty || isBusy)
                        Button(L("Restore Originals")) { restore() }
                            .buttonStyle(GlassPrimaryButtonStyle())
                            .disabled(isBusy)
                        Button(L("Import Theme")) { importingTheme = true }
                            .buttonStyle(GlassPrimaryButtonStyle())
                            .disabled(isBusy)
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
                Button(L("Refresh")) { load() }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(isBusy)
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("Dialer Skin"))
        .navigationBarTitleDisplayMode(.large)
        .photosPicker(item: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item, let key = pickingKey else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty {
                    replacements[key] = DialerSkin.resize(data, to: CGSize(width: 250, height: 250), circle: circle)
                }
                pickerItem = nil
            }
        }
        .fileImporter(isPresented: $importingTheme, allowedContentTypes: [.zip], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let matched = try DialerSkin.importTheme(from: url, dark: colorScheme == .dark)
                replacements.merge(matched) { _, new in new }
                message = L("Theme imported. Review the images, then tap Apply.")
            } catch {
                message = error.localizedDescription
            }
        }
        .task { load() }
    }

    private func load() {
        isBusy = true
        let dark = colorScheme == .dark
        Task.detached(priority: .userInitiated) {
            let found = DialerSkin.phoneContainer()
            let keys: [DialerSkin.KeypadID: Data]? = found.flatMap { try? DialerSkin.currentKeypads(container: $0, dark: dark) }
            await MainActor.run {
                container = found
                current = keys ?? [:]
                isBusy = false
                if found == nil {
                    message = L("The Phone app container could not be opened on this device.")
                }
            }
        }
    }

    private func apply() {
        guard let container else { return }
        isBusy = true
        let dark = colorScheme == .dark
        Task.detached(priority: .userInitiated) {
            do {
                let result = try DialerSkin.apply(images: replacements, container: container)
                let keys = try? DialerSkin.currentKeypads(container: container, dark: dark)
                await MainActor.run {
                    current = keys ?? [:]
                    replacements = [:]
                    message = result.failed == 0
                        ? L("Dialer skin applied. Toggle the appearance or restart the device to see it.")
                        : L("Dialer skin applied with some invalid images skipped.")
                    isBusy = false
                }
            } catch {
                await MainActor.run { message = error.localizedDescription; isBusy = false }
            }
        }
    }

    private func restore() {
        guard let container else { return }
        isBusy = true
        let dark = colorScheme == .dark
        Task.detached(priority: .userInitiated) {
            do {
                let count = try DialerSkin.restore(container: container)
                let keys = try? DialerSkin.currentKeypads(container: container, dark: dark)
                await MainActor.run {
                    current = keys ?? [:]
                    replacements = [:]
                    message = count == 0
                        ? L("No backed-up keypad originals were found.")
                        : L("Original keypad images restored. Toggle the appearance or restart the device to see them.")
                    isBusy = false
                }
            } catch {
                await MainActor.run { message = error.localizedDescription; isBusy = false }
            }
        }
    }
}

// MARK: - A21 SiriHub guard

struct SiriHubGuardView: View {
    @State private var status: SiriHubGuard.Status = .unknown

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("DeviceSupportsSiriHub is the on-device Siri Hub intent-routing slot. When SiriHub routing is on, enabling Siri AI can hang at “Adding Siri support”, so the staging guard blocks AI staging until it is off. The status below is the live system answer, read-only."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                GlassCard(cornerRadius: GlassTokens.cardRadius) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("SiriHub Routing")).font(.headline)
                        switch status {
                        case .conflict:
                            Label(SiriHubGuard.conflictReason, systemImage: "exclamationmark.triangle")
                                .font(.subheadline).foregroundStyle(.orange)
                        case .clear:
                            Label(L("SiriHub routing is off. Siri AI staging is not blocked by this guard."), systemImage: "checkmark.circle")
                                .font(.subheadline).foregroundStyle(.green)
                        case .unknown:
                            Label(SiriHubGuard.unknownNote, systemImage: "questionmark.circle")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                Text(L("Key: waGD2UTpntjbDXD1r3oALQ (Erosion-CN MGCacheLayout). Not present in upstream GestaltX 1.1.1."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button(L("Refresh")) { refresh() }
                    .buttonStyle(GlassPrimaryButtonStyle())
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("SiriHub Guard"))
        .navigationBarTitleDisplayMode(.large)
        .task { refresh() }
    }

    private func refresh() {
        Task.detached(priority: .userInitiated) {
            let found = SiriHubGuard.liveStatus()
            await MainActor.run { status = found }
        }
    }
}

// MARK: - A22 MG keys table

struct MGKeysTableView: View {
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("Every MobileGestalt key the app knows about, with its meaning and the open-source source it was verified against. Nothing here is guessed."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            TextField(L("Search keys"), text: $query)
                .textFieldStyle(.roundedBorder)
                .autocapitalization(.none)
                .disableAutocorrection(true)
            List(MGKeysTable.matching(query)) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.name).font(.subheadline)
                    Text(entry.key).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(entry.meaning).font(.caption).foregroundStyle(.secondary)
                    Text(entry.source).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .listStyle(.plain)
        }
        .padding()
        .background(GlassBackground())
        .navigationTitle(L("MobileGestalt Keys"))
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - A23 Compatibility matrix

struct CompatibilityMatrixView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(CompatibilityMatrix.verificationDisclaimer)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(L("System Version"))
                    .font(.headline)
                ForEach(CompatibilityMatrix.systemRows) { row in
                    GlassCard(cornerRadius: GlassTokens.cardRadius) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.feature).font(.subheadline)
                            ForEach(Array(zip(CompatibilityMatrix.iosColumns, row.cells)), id: \.0) { column, cell in
                                HStack(alignment: .top, spacing: 8) {
                                    compatibilityBadge(cell.status)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(column).font(.caption).foregroundStyle(.secondary)
                                        Text(cell.note).font(.caption)
                                    }
                                }
                            }
                            Text(row.source).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                Text(L("Device"))
                    .font(.headline)
                ForEach(CompatibilityMatrix.deviceRows) { row in
                    GlassCard(cornerRadius: GlassTokens.cardRadius) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 8) {
                                compatibilityBadge(row.status)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.device).font(.subheadline)
                                    Text(row.feature).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(row.note).font(.caption)
                            Text(row.source).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                Text(L("Installation"))
                    .font(.headline)
                ForEach(CompatibilityMatrix.installRows) { row in
                    GlassCard(cornerRadius: GlassTokens.cardRadius) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(row.method).font(.subheadline)
                            Text(row.requirement).font(.caption)
                            Text(row.note).font(.caption).foregroundStyle(.secondary)
                            Text(row.source).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("Compatibility"))
        .navigationBarTitleDisplayMode(.large)
    }

    private func compatibilityBadge(_ status: CompatibilityMatrix.Status) -> some View {
        let (text, symbol, color): (String, String, Color) = {
            switch status {
            case .supported: return (L("Supported"), "checkmark.circle.fill", .green)
            case .unsupported: return (L("Unsupported"), "xmark.circle.fill", .red)
            case .unverified: return (L("Unverified"), "questionmark.circle.fill", .secondary)
            case .conditional: return (L("Conditional"), "exclamationmark.circle.fill", .orange)
            }
        }()
        return Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(color)
    }
}
