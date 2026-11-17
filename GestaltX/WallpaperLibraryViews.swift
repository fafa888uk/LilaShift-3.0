// SPDX-License-Identifier: GPL-3.0-only
// Wallpaper Library views (Stage 8, TASKBOOK §7.1–§7.3): the user's
// own images — list, import, preview, crop suggestions, format
// conversion, favorites, categories, delete, export to Photos —
// and the in-app home background.
//
// Honest boundary, shown on screen: this app cannot set the system
// wallpaper directly (iOS offers no public API for it). "Save to
// Photos" saves the image; the user sets it from Photos (Use as
// Wallpaper) or with the Shortcuts Set Wallpaper action. "Use as
// Home Background" only changes the background inside LilaShift.
//
// The views never touch the file system directly: the model owns
// the store, and the store owns the files.
import SwiftUI
import Combine
import Photos
import PhotosUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Model

/// The wallpaper library model. Owns the store and the Photos
/// exporter (injectable, so tests record the export request instead
/// of claiming a real Photos write). All file work goes through
/// the store; the view only calls this model.
@MainActor
final class WallpaperLibraryModel: ObservableObject {
    @Published private(set) var entries: [WallpaperLibraryEntry] = []
    @Published private(set) var previews: [UUID: Data] = [:]
    @Published private(set) var busy = false
    @Published var message: String?
    @Published private(set) var homeBackgroundID: UUID?

    private let store: WallpaperLibraryStore
    private let exporter: WallpaperPhotoExporting

    init(store: WallpaperLibraryStore = WallpaperLibraryStore(storage: AppDirectories.wallpaperLibraryStorage),
         exporter: WallpaperPhotoExporting = PhotoLibraryWallpaperExporter()) {
        self.store = store
        self.exporter = exporter
    }

    private func run(_ operation: () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do { try await operation() } catch is CancellationError {} catch { message = error.localizedDescription }
    }

    private func loadPreviews() async {
        for entry in entries where previews[entry.id] == nil {
            previews[entry.id] = try? await store.thumbnailData(entry.id)
        }
    }

    func load() async {
        await run {
            entries = try await store.list()
            homeBackgroundID = PersonalizationCenter.loadHomeWallpaperID()
            await loadPreviews()
        }
    }

    func importPhoto(_ item: PhotosPickerItem, category: WallpaperCategory) async {
        await run {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                throw CustomizationFailure("This image could not be used. Choose another image.")
            }
            let entry = try await store.importImage(data, name: L("Wallpaper"), category: category)
            entries = try await store.list()
            previews[entry.id] = try? await store.thumbnailData(entry.id)
        }
    }

    func importFile(_ url: URL, category: WallpaperCategory) async {
        defer { CustomizationFiles.discardStagedDirectory(containing: url) }
        await run {
            let entry = try await store.importImageFile(url, name: nil, category: category)
            entries = try await store.list()
            previews[entry.id] = try? await store.thumbnailData(entry.id)
        }
    }

    func setFavorite(_ entry: WallpaperLibraryEntry, isFavorite: Bool) async {
        await run {
            _ = try await store.setFavorite(entry.id, isFavorite: isFavorite)
            entries = try await store.list()
        }
    }

    func setCategory(_ entry: WallpaperLibraryEntry, category: WallpaperCategory) async {
        await run {
            _ = try await store.setCategory(entry.id, category: category)
            entries = try await store.list()
        }
    }

    func rename(_ entry: WallpaperLibraryEntry, name: String) async {
        await run {
            _ = try await store.rename(entry.id, name: name)
            entries = try await store.list()
        }
    }

    func deleteEntry(_ entry: WallpaperLibraryEntry) async {
        await run {
            // Check the stored setting directly, not only the cached
            // id from load(): a delete must never leave a dangling
            // home-background setting behind if load() was skipped.
            if homeBackgroundID == entry.id || PersonalizationCenter.loadHomeWallpaperID() == entry.id {
                homeBackgroundID = nil
                if let error = PersonalizationCenter.setHomeWallpaperID(nil) { message = error }
            }
            try await store.delete(entry.id)
            entries.removeAll { $0.id == entry.id }
            previews.removeValue(forKey: entry.id)
        }
    }

    /// Saves the entry's original image to Photos. This does not
    /// set the system wallpaper: the user sets it from Photos.
    func saveToPhotos(_ entry: WallpaperLibraryEntry) async {
        await run {
            let data = try await store.imageData(entry.id)
            let fileExtension: String
            switch entry.format {
            case .png: fileExtension = "png"
            case .jpeg: fileExtension = "jpg"
            case .heic: fileExtension = "heic"
            case .unsupported: throw CustomizationFailure("This image format is not supported. Use PNG, JPEG, or HEIC.")
            }
            let name = entry.name.replacingOccurrences(of: "/", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try await exporter.saveToPhotos(data, filename: "\(name.isEmpty ? "wallpaper" : name)-wallpaper.\(fileExtension)")
            message = L("Wallpaper saved to Photos. Set it from Photos (Use as Wallpaper) or with the Shortcuts Set Wallpaper action.")
        }
    }

    /// Converts the entry to PNG or JPEG and saves the result as a
    /// new library entry. The original is kept.
    func convertAndSaveCopy(_ entry: WallpaperLibraryEntry, to format: AppAppearanceImageFormat) async {
        await run {
            guard format == .png || format == .jpeg else {
                throw CustomizationFailure("This image format is not supported. Use PNG, JPEG, or HEIC.")
            }
            let data = try await store.imageData(entry.id)
            guard let converted = WallpaperImageConversion.convert(data, to: format) else {
                throw CustomizationFailure("This image could not be converted. Choose another image.")
            }
            let copy = try await store.importImage(
                converted, name: "\(entry.name) (\(format.displayName))", category: entry.category)
            entries = try await store.list()
            previews[copy.id] = try? await store.thumbnailData(copy.id)
        }
    }

    /// Renders the suggested crop at the target size and saves it
    /// as a new library entry. The original is kept.
    func saveCroppedCopy(_ entry: WallpaperLibraryEntry, suggestion: WallpaperCropSuggestion, format: AppAppearanceImageFormat) async {
        await run {
            guard format == .png || format == .jpeg else {
                throw CustomizationFailure("This image format is not supported. Use PNG, JPEG, or HEIC.")
            }
            let data = try await store.imageData(entry.id)
            guard let rendered = WallpaperImageConversion.renderCrop(
                data, crop: suggestion.crop,
                targetSize: CGSize(width: suggestion.targetWidth, height: suggestion.targetHeight),
                format: format) else {
                throw CustomizationFailure("This image could not be cropped. Choose another image.")
            }
            let copy = try await store.importImage(
                rendered, name: "\(entry.name) · \(suggestion.label)", category: entry.category)
            entries = try await store.list()
            previews[copy.id] = try? await store.thumbnailData(copy.id)
        }
    }

    /// Uses the entry as the in-app home background only. This
    /// never changes the system wallpaper.
    func useAsHomeBackground(_ entry: WallpaperLibraryEntry) async {
        await run {
            if let error = PersonalizationCenter.setHomeWallpaperID(entry.id) {
                message = error
                return
            }
            homeBackgroundID = entry.id
            message = L("Home background set. This only changes the background inside LilaShift.")
        }
    }

    func useDefaultHomeBackground() async {
        await run {
            if let error = PersonalizationCenter.setHomeWallpaperID(nil) {
                message = error
                return
            }
            homeBackgroundID = nil
        }
    }
}

// MARK: - Home background

/// Loads the in-app home background image: the library thumbnail
/// of the wallpaper the user chose, downsampled to the screen's
/// longest side. `nil` means the default lavender gradient (or
/// the chosen entry is gone, which also falls back silently).
@MainActor
final class HomeBackgroundModel: ObservableObject {
    @Published private(set) var image: UIImage?

    private let store: WallpaperLibraryStore

    init(store: WallpaperLibraryStore = WallpaperLibraryStore(storage: AppDirectories.wallpaperLibraryStorage)) {
        self.store = store
    }

    func reload() async {
        guard let id = PersonalizationCenter.loadHomeWallpaperID() else {
            image = nil
            return
        }
        guard let data = try? await store.imageData(id),
              let png = AppAppearanceValidatedImage.croppedThumbnailPNG(
                from: data, crop: AppAppearanceCrop(), maxPixelSize: 2736),
              let rendered = UIImage(data: png) else {
            image = nil
            return
        }
        image = rendered
    }
}

/// The Tools home background: the chosen library wallpaper with a
/// lavender scrim so text stays readable, or the default lavender
/// gradient when nothing is chosen. In-app only — this never
/// touches the system wallpaper.
struct HomeBackgroundView: View {
    let image: UIImage?

    var body: some View {
        if let image {
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                LinearGradient(
                    colors: [Color.lavenderGlass.opacity(0.55), Color.lavenderGlass.opacity(0.35)],
                    startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        } else {
            GlassBackground()
        }
    }
}

// MARK: - File picker

/// Picks a single image file (PNG, JPEG, HEIC) as a copy. Same
/// staging pattern as `CustomizationFilePicker`: the picked file is
/// copied into a private temp directory and the caller owns it.
struct WallpaperImageFilePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let complete: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(complete, cancel: { dismiss() }) }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.png, .jpeg, .heic], asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let complete: (Result<URL, Error>) -> Void
        let cancel: () -> Void

        init(_ complete: @escaping (Result<URL, Error>) -> Void, cancel: @escaping () -> Void) {
            self.complete = complete
            self.cancel = cancel
        }

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

// MARK: - Library view

/// The personal wallpaper library. The user's own images only:
/// import one image at a time from Photos or Files, crop it for
/// this device or another iPhone, convert it, save it to Photos,
/// or use it as the in-app home background.
struct WallpaperLibraryView: View {
    @ObservedObject var model: WallpaperLibraryModel
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showsFilePicker = false
    @State private var importCategory: WallpaperCategory = .other
    @State private var filterCategory: WallpaperCategory?
    @State private var favoritesOnly = false
    @State private var selectedEntryID: UUID?

    /// The actual screen size in pixels (points × scale), so "This
    /// Device" suggestions are computed from the real device, not
    /// from a table.
    static var currentDevicePixelSize: CGSize {
        let bounds = UIScreen.main.bounds.size
        let scale = UIScreen.main.scale
        return CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
    }

    private var visibleEntries: [WallpaperLibraryEntry] {
        model.entries.filter { entry in
            if favoritesOnly, !entry.isFavorite { return false }
            if let filterCategory, entry.category != filterCategory { return false }
            return true
        }
    }

    var body: some View {
        List {
            Section {
                if let homeID = model.homeBackgroundID,
                   let home = model.entries.first(where: { $0.id == homeID }) {
                    HStack(spacing: GlassTokens.rowSpacing) {
                        Label(L("Home background"), systemImage: "house")
                            .font(.subheadline.weight(.semibold))
                        Text(home.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        Spacer()
                        Button(L("Use Default")) { Task { await model.useDefaultHomeBackground() } }
                            .font(.subheadline)
                    }
                } else {
                    Label(L("Home background: Default lavender"), systemImage: "house")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(L("In-App Home Background"))
            } footer: {
                Text(L("The home background only changes LilaShift itself. It never changes the system wallpaper."))
            }

            Section {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(L("Import from Photos"), systemImage: "photo.badge.plus")
                }
                Button { showsFilePicker = true } label: {
                    Label(L("Import an Image File"), systemImage: "folder.badge.plus")
                }
                Picker(L("Category for new imports"), selection: $importCategory) {
                    ForEach(WallpaperCategory.allCases, id: \.self) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.menu)
            } footer: {
                Text(L("PNG, JPEG, or HEIC, up to 5 MB and 4096 pixels on the longest side."))
            }

            Section {
                Picker(L("Category"), selection: $filterCategory) {
                    Text(L("All")).tag(nil as WallpaperCategory?)
                    ForEach(WallpaperCategory.allCases, id: \.self) { category in
                        Text(category.title).tag(category as WallpaperCategory?)
                    }
                }
                .pickerStyle(.menu)
                Toggle(L("Favorites only"), isOn: $favoritesOnly)
            }

            if visibleEntries.isEmpty {
                Section {
                    ContentUnavailableView(
                        L("No Wallpapers"),
                        systemImage: "photo.on.rectangle.angled",
                        description: Text(L("Import an image to start your library.")))
                }
            } else {
                Section {
                    ForEach(visibleEntries) { entry in
                        Button { selectedEntryID = entry.id } label: {
                            HStack(spacing: GlassTokens.rowSpacing) {
                                thumbnail(entry)
                                    .frame(width: 70, height: 110)
                                    .clipShape(RoundedRectangle(cornerRadius: GlassTokens.smallRadius))
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(spacing: 6) {
                                        Text(entry.name).font(.headline).lineLimit(2)
                                        if entry.isFavorite {
                                            Image(systemName: "star.fill")
                                                .font(.caption)
                                                .foregroundStyle(Color.gestaltAccent)
                                        }
                                    }
                                    Text("\(entry.resolutionText) · \(entry.format.displayName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(entry.category.title)
                                        .font(.caption).foregroundStyle(.secondary)
                                    if model.homeBackgroundID == entry.id {
                                        Label(L("Home background"), systemImage: "house")
                                            .font(.caption).foregroundStyle(Color.gestaltAccent)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 5)
                    }
                }
            }

            Section {
                Text(L("LilaShift cannot set the system wallpaper directly. Save an image to Photos, then set it from Photos (Use as Wallpaper) or with the Shortcuts Set Wallpaper action."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L("Wallpaper Library"))
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.busy)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { if model.busy { ProgressView() } } }
        .task { await model.load() }
        .sheet(item: Binding(
            get: { selectedEntryID.flatMap { id in model.entries.first(where: { $0.id == id }) } },
            set: { selectedEntryID = $0?.id }
        )) { entry in
            NavigationStack {
                WallpaperEntryDetailView(entryID: entry.id, model: model)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("Done")) { selectedEntryID = nil } } }
            }
        }
        .sheet(isPresented: $showsFilePicker) {
            WallpaperImageFilePicker { result in
                showsFilePicker = false
                switch result {
                case .success(let url): Task { await model.importFile(url, category: importCategory) }
                case .failure(let error): model.message = error.localizedDescription
                }
            }.ignoresSafeArea()
        }
        .onChange(of: selectedPhoto) { _, item in
            guard let item else { return }
            selectedPhoto = nil
            Task { await model.importPhoto(item, category: importCategory) }
        }
        .alert(L("LilaShift"), isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button(L("OK"), role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }

    @ViewBuilder private func thumbnail(_ entry: WallpaperLibraryEntry) -> some View {
        if let data = model.previews[entry.id], let image = UIImage(data: data) {
            Image(uiImage: image).resizable().scaledToFill().clipped()
        } else {
            RoundedRectangle(cornerRadius: GlassTokens.smallRadius)
                .fill(Color(uiColor: .tertiarySystemFill))
                .overlay { Image(systemName: "photo.on.rectangle.angled").foregroundStyle(.secondary) }
        }
    }
}

// MARK: - Entry detail

/// One library entry: large preview, real resolution and size,
/// category and favorite, crop suggestions for this device or
/// another iPhone, format conversion, save to Photos, use as the
/// in-app home background, delete. The entry is looked up from the
/// model on every render, so edits never show a stale copy.
struct WallpaperEntryDetailView: View {
    let entryID: UUID
    @ObservedObject var model: WallpaperLibraryModel
    @Environment(\.dismiss) private var dismiss

    @State private var nameDraft = ""
    @State private var targetDevice: WallpaperDevice?
    @State private var orientation: WallpaperCropSuggestion.Orientation = .portrait
    @State private var pendingDelete = false

    private var entry: WallpaperLibraryEntry? {
        model.entries.first(where: { $0.id == entryID })
    }

    private var devicePixelSize: CGSize {
        if let targetDevice { return targetDevice.pixelSize }
        return WallpaperLibraryView.currentDevicePixelSize
    }

    private var deviceName: String {
        targetDevice?.name ?? L("This Device")
    }

    private var suggestions: [WallpaperCropSuggestion] {
        guard let entry else { return [] }
        return WallpaperCropSuggestions.suggestions(
            for: entry.pixelSize, targetPixelSize: devicePixelSize, deviceName: deviceName)
    }

    private var selectedSuggestion: WallpaperCropSuggestion? {
        suggestions.first(where: { $0.orientation == orientation })
    }

    var body: some View {
        if let entry {
            detailList(entry)
        } else {
            ContentUnavailableView(L("Wallpaper not found"), systemImage: "photo.on.rectangle.angled")
                .navigationTitle(L("Wallpaper"))
                .navigationBarTitleDisplayMode(.inline)
                .task { dismiss() }
        }
    }

    @ViewBuilder
    private func detailList(_ entry: WallpaperLibraryEntry) -> some View {
        List {
            Section {
                preview(entry)
                Text(String(format: L("Image: %@ · %d × %d · %d KB"),
                            entry.format.displayName, entry.width, entry.height, entry.byteCount / 1024))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextField(L("Name"), text: $nameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await model.rename(entry, name: nameDraft) } }
                Picker(L("Category"), selection: Binding(
                    get: { entry.category },
                    set: { category in Task { await model.setCategory(entry, category: category) } }
                )) {
                    ForEach(WallpaperCategory.allCases, id: \.self) { category in
                        Text(category.title).tag(category)
                    }
                }
                .pickerStyle(.menu)
                Toggle(L("Favorite"), isOn: Binding(
                    get: { entry.isFavorite },
                    set: { isFavorite in Task { await model.setFavorite(entry, isFavorite: isFavorite) } }
                ))
            } header: {
                Text(L("Details"))
            }

            Section {
                Picker(L("Device"), selection: $targetDevice) {
                    Text(L("This Device")).tag(nil as WallpaperDevice?)
                    ForEach(WallpaperDevice.knownDevices, id: \.name) { device in
                        Text("\(device.name) · \(device.width) × \(device.height)").tag(device as WallpaperDevice?)
                    }
                }
                .pickerStyle(.menu)
                Picker(L("Orientation"), selection: $orientation) {
                    Text(L("Portrait")).tag(WallpaperCropSuggestion.Orientation.portrait)
                    Text(L("Landscape")).tag(WallpaperCropSuggestion.Orientation.landscape)
                    Text(L("Square")).tag(WallpaperCropSuggestion.Orientation.square)
                }
                .pickerStyle(.segmented)
                if let suggestion = selectedSuggestion {
                    Text(String(format: L("Crop: %d × %d from %d × %d"),
                                Int(suggestion.crop.width), Int(suggestion.crop.height),
                                entry.width, entry.height))
                        .font(.caption).foregroundStyle(.secondary)
                    if suggestion.needsUpscale {
                        Label(L("This image is smaller than the device screen. The cropped copy will be upscaled and may look soft."),
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(Color.gestaltAccent)
                    }
                    HStack {
                        Button(L("Save Cropped Copy (PNG)")) {
                            Task { await model.saveCroppedCopy(entry, suggestion: suggestion, format: .png) }
                        }
                        Button(L("Save Cropped Copy (JPEG)")) {
                            Task { await model.saveCroppedCopy(entry, suggestion: suggestion, format: .jpeg) }
                        }
                    }
                    .font(.subheadline)
                }
            } header: {
                Text(L("Crop for a Device"))
            } footer: {
                Text(L("The crop fills the screen without stretching. The original is kept."))
            }

            Section {
                HStack {
                    Button(L("Convert to PNG")) { Task { await model.convertAndSaveCopy(entry, to: .png) } }
                    Button(L("Convert to JPEG")) { Task { await model.convertAndSaveCopy(entry, to: .jpeg) } }
                }
                .font(.subheadline)
                Button { Task { await model.saveToPhotos(entry) } } label: {
                    Label(L("Save to Photos"), systemImage: "square.and.arrow.down")
                }
                Button { Task { await model.useAsHomeBackground(entry) } } label: {
                    Label(L("Use as Home Background"), systemImage: "house")
                }
                .disabled(model.homeBackgroundID == entry.id)
            } footer: {
                Text(L("Save to Photos does not set the system wallpaper. Set it from Photos (Use as Wallpaper) or with the Shortcuts Set Wallpaper action. Home Background only changes LilaShift itself."))
            }

            Section {
                Button(L("Delete Wallpaper"), role: .destructive) { pendingDelete = true }
            } footer: {
                Text(L("This only deletes the image from the LilaShift library."))
            }
        }
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
        .disabled(model.busy)
        .onAppear { nameDraft = entry.name }
        .onChange(of: entry.name) { _, name in nameDraft = name }
        .alert(L("Delete this wallpaper?"), isPresented: $pendingDelete) {
            Button(L("Cancel"), role: .cancel) { pendingDelete = false }
            Button(L("Delete"), role: .destructive) {
                pendingDelete = false
                Task { await model.deleteEntry(entry); dismiss() }
            }
        } message: {
            Text(L("This only deletes the image from the LilaShift library."))
        }
        .alert(L("LilaShift"), isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button(L("OK"), role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }

    @ViewBuilder private func preview(_ entry: WallpaperLibraryEntry) -> some View {
        if let data = model.previews[entry.id], let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: GlassTokens.smallRadius))
        } else {
            RoundedRectangle(cornerRadius: GlassTokens.smallRadius)
                .fill(Color(uiColor: .tertiarySystemFill))
                .frame(height: 180)
                .overlay { Image(systemName: "photo.on.rectangle.angled").foregroundStyle(.secondary) }
        }
    }
}
