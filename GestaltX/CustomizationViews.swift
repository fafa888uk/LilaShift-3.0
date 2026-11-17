// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import Combine
import Photos
import UniformTypeIdentifiers

@MainActor
final class CustomizationModel: ObservableObject {
    @Published private(set) var packs: [WallpaperPack] = []
    @Published private(set) var previews: [UUID: Data] = [:]
    /// Decoded preview images, one per pack (Stage 9, TASKBOOK
    /// §8.2). The view reads from here and never calls
    /// `UIImage(data:)` in its body; the decode runs once per pack
    /// in `loadPreviews`, off the main thread.
    private(set) var previewCache = PreviewImageCache()
    @Published private(set) var busy = false
    @Published private(set) var isPresenting = false
    private var presentationOwners = Set<UUID>()
    func setPresenting(_ presenting: Bool, owner: UUID) {
        if presenting { presentationOwners.insert(owner) } else { presentationOwners.remove(owner) }
        isPresenting = !presentationOwners.isEmpty
    }
    @Published var message: String?
    private let store: CustomizationStore
    init() {
        store = CustomizationStore(storage: AppDirectories.customizationStorage, device: UIDevice.current.identifierForVendor?.uuidString ?? "local")
    }
    private func run(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { try await operation() } catch is CancellationError {} catch { message = error.localizedDescription }
    }
    private func loadPreviews() async {
        for pack in packs where previews[pack.id] == nil {
            guard let data = try? await store.wallpaperPreview(pack.id) else { continue }
            // Decode off the main thread (TASKBOOK §8.2) and store
            // the decoded image; the view reads `previewCache` and
            // never re-decodes on every render. The data is published
            // after the image is stored, so the render that follows
            // the publish always finds the image.
            if let image = await Task.detached(priority: .userInitiated) { UIImage(data: data) }.value {
                previewCache.store(image, for: pack.id)
            }
            previews[pack.id] = data
        }
    }
    func loadWallpapers() async {
        await run { packs = try await store.listWallpapers(); await loadPreviews() }
    }
    @discardableResult
    func importWallpaper(_ url: URL, id: UUID = UUID()) async -> Bool {
        defer { CustomizationFiles.discardStagedDirectory(containing: url) }
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do { packs = try await store.importWallpaper(url, id: id); await loadPreviews(); return true }
        catch { message = error.localizedDescription; return false }
    }
    func applyWallpaper(_ pack: WallpaperPack) async {
        await run {
            packs = try await store.applyWallpaper(pack.id)
            message = L("Wallpaper added. Open the wallpaper gallery to select it. If it does not appear, restart the device.")
        }
    }
    /// Saves the pack's wallpaper image to Photos (public Photos API). This
    /// does not set the system wallpaper: the user sets it from Photos
    /// (Use as Wallpaper) or with the Shortcuts Set Wallpaper action.
    func saveWallpaperToPhotos(_ pack: WallpaperPack) async {
        await run {
            let data = try await store.wallpaperImageData(pack.id)
            var authorization = PHPhotoLibrary.authorizationStatus(for: .addOnly)
            if authorization == .notDetermined { authorization = await PHPhotoLibrary.requestAuthorization(for: .addOnly) }
            guard authorization == .authorized || authorization == .limited else {
                throw CustomizationFailure("Allow LilaShift to add photos in Settings, then try again.")
            }
            let kind = CustomizationImages.kind(of: data) ?? "png"
            let name = pack.name.replacingOccurrences(of: "/", with: "-").trimmingCharacters(in: .whitespacesAndNewlines)
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                let options = PHAssetResourceCreationOptions()
                options.originalFilename = "\(name.isEmpty ? "wallpaper" : name)-wallpaper.\(kind)"
                request.addResource(with: .photo, data: data, options: options)
            }
            message = L("Wallpaper saved to Photos. Set it from Photos (Use as Wallpaper) or with the Shortcuts Set Wallpaper action.")
        }
    }
    func removeWallpaper(_ pack: WallpaperPack) async {
        await run { packs = try await store.removeWallpaper(pack.id); previews.removeValue(forKey: pack.id); previewCache.remove(for: pack.id) }
    }
    func deleteImportedWallpaper(_ pack: WallpaperPack) async {
        await run {
            try await store.deleteImportedWallpaper(pack.id)
            packs.removeAll { $0.id == pack.id }
            previews.removeValue(forKey: pack.id)
            previewCache.remove(for: pack.id)
        }
    }
    func open(_ identifier: String) {
        guard GXCustomizationAccess.openApplication(identifier) else {
            message = L("The app could not be opened. Open it manually."); return
        }
    }
}

/// Copy mode owns the document inside this app; it does not depend on retained Files bookmarks.
struct CustomizationFilePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let complete: (Result<URL, Error>) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(complete, cancel: { dismiss() }) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data, .zip], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let complete: (Result<URL, Error>) -> Void
        let cancel: () -> Void
        init(_ complete: @escaping (Result<URL, Error>) -> Void, cancel: @escaping () -> Void) { self.complete = complete; self.cancel = cancel }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { cancel() }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let source = urls.first else { return }
            Task {
                let result: Result<URL, Error> = await Task.detached(priority: .userInitiated) {
                    Result { try CustomizationFiles.stagePickedFile(source) }
                }.value
                complete(result)
            }
        }
    }
}

struct WallpapersView: View {
    @ObservedObject var model: CustomizationModel
    @State private var showsImport = false
    @State private var pendingApply: WallpaperPack?
    @State private var pendingDelete: WallpaperPack?
    @State private var presentationOwner = UUID()
    var body: some View {
        List {
            Section {
                Button { showsImport = true } label: { Label(L("Import Wallpaper"), systemImage: "square.and.arrow.down") }
            } footer: { Text(L("Import a .tendies or .zip wallpaper pack. You can also share it to LilaShift.")) }
            if model.packs.isEmpty {
                Section { ContentUnavailableView(L("No Wallpapers"), systemImage: "photo.on.rectangle.angled") }
            } else {
                Section {
                    ForEach(model.packs) { pack in
                        HStack(spacing: 14) {
                            preview(pack).frame(width: 70, height: 110).clipShape(RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 8) {
                                Text(pack.name).font(.headline).lineLimit(2)
                                Label(String(pack.descriptors.count), systemImage: "square.stack").font(.caption).foregroundStyle(.secondary)
                                if pack.isApplied { Label(L("Applied"), systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green) }
                                HStack {
                                    Button(L("Apply")) { pendingApply = pack }.disabled(pack.isApplied)
                                    Button { Task { await model.saveWallpaperToPhotos(pack) } } label: {
                                        Label(L("Save to Photos"), systemImage: "square.and.arrow.down")
                                    }
                                    Spacer()
                                    Button(role: .destructive) { pendingDelete = pack } label: { Image(systemName: "trash") }
                                        .accessibilityLabel(L("Delete"))
                                }.buttonStyle(.borderless)
                            }
                        }.padding(.vertical, 5)
                    }
                }
            }
            Section {
                Button { model.open("com.apple.PosterBoard") } label: { Label(L("Open Wallpaper Gallery"), systemImage: "photo.on.rectangle") }
            }
        }
        .navigationTitle(L("Wallpaper Settings"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.busy)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { if model.busy { ProgressView() } } }
        .task { await model.loadWallpapers() }
        .onChange(of: showsImport || pendingApply != nil || pendingDelete != nil || model.message != nil, initial: true) { _, presenting in
            model.setPresenting(presenting, owner: presentationOwner)
        }
        .onDisappear { if !showsImport { model.setPresenting(false, owner: presentationOwner) } }
        .sheet(isPresented: $showsImport) {
            CustomizationFilePicker { result in
                showsImport = false
                switch result {
                case .success(let url): Task { await model.importWallpaper(url) }
                case .failure(let error): model.message = error.localizedDescription
                }
            }.ignoresSafeArea()
        }
        .alert(L("Apply these changes?"), isPresented: Binding(get: { pendingApply != nil }, set: { if !$0 { pendingApply = nil } })) {
            Button(L("Cancel"), role: .cancel) { pendingApply = nil }
            Button(L("Apply")) { if let pack = pendingApply { Task { await model.applyWallpaper(pack) } }; pendingApply = nil }
        } message: { Text(L("This adds new wallpapers without replacing your existing ones.")) }
        .alert(L("Delete the imported wallpaper pack?"), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(L("Cancel"), role: .cancel) { pendingDelete = nil }
            Button(L("Delete"), role: .destructive) { if let pack = pendingDelete { Task { await model.deleteImportedWallpaper(pack) } }; pendingDelete = nil }
        } message: { Text(L("This only deletes the imported pack from LilaShift. Applied wallpapers will be kept.")) }
        .alert(L("LilaShift"), isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button(L("OK"), role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
    @ViewBuilder private func preview(_ pack: WallpaperPack) -> some View {
        // The decoded image comes from the cache (Stage 9): decoding
        // `UIImage(data:)` here would re-decode on every render.
        if let image = model.previewCache.image(for: pack.id) {
            Image(uiImage: image).resizable().scaledToFill().clipped()
        } else {
            RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .tertiarySystemFill))
                .overlay { Image(systemName: "photo.on.rectangle.angled").foregroundStyle(.secondary) }
        }
    }
}
