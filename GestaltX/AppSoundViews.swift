// SPDX-License-Identifier: GPL-3.0-only
// App Audio Library views (Stage 13): ported 1:1 from upstream
// GestaltX v1.1.1 (GPL-3.0), with attribution in THIRD_PARTY_NOTICES.md,
// adapted for LilaShift Phase 1 only:
// - The capture guide (CapturedSoundStore, NotificationCaptureView,
//   AppSoundCapturedEditor, the "Captured Apps" section, and the
//   capture toolbar button) is NOT in this stage — it needs Pairing
//   & Device Connection, which is deferred (see the Stage 13 record).
//   The store-level named-override API (`createNamed`,
//   `prepareNamed`) IS ported and tested; the UI that feeds it
//   filenames arrives with capture.
// - The catalog therefore lists only apps whose Sound/Sounds
//   directories already hold audio (`existing`); the `observed`
//   (captured) signal is re-added with capture.
// - List styling follows the launch-image pages (the pattern twin);
//   the Glass entry point is the Tools-page tile in ContentView.
// - User-visible "GestaltX" strings are "LilaShift" here.
import SwiftUI
import Combine
import AVFAudio

/// Whether the audio library can replace sounds on this iOS build.
/// Replacement goes through the `worse_query` lease, so it is
/// blocked wherever the version sentinel says the mechanism is
/// blocked. Returns the sentinel guidance for blocked/unknown
/// builds, `nil` when replacement is available. The Tools-page tile
/// uses this to show disabled-with-guidance instead of an empty
/// list or a silent failure.
enum AppSoundAvailability {
    static func unavailableReason(forBuild build: String?) -> String? {
        VersionSentinel.guidance(for: VersionSentinel.state(forBuild: build))
    }
}

@MainActor
final class AppSoundCatalogModel: ObservableObject {
    @Published private(set) var applications: [LaunchArtworkApp] = []
    @Published private(set) var scanning = false

    private let catalog: LaunchArtworkCatalogStore
    private let sounds = AppSoundStore(storage: AppDirectories.audioStorage,
                                       device: DeviceConsolePaths.deviceIdentifier)

    // Metadata and the availability signal are kept separate, per the plan:
    //   installed  — the shared app roster (name + bundle id, cache-first)
    //   existing    — bundle ids whose Sound/Sounds directories already hold audio
    //   visible     = installed ∩ existing
    // (Upstream also has an `observed` signal from capture; it returns
    // with the capture guide in a later stage.)
    private var installed: [String: LaunchArtworkApp] = [:]
    private var existing: Set<String> = []
    private var scannedExisting: Set<String> = []
    private let defaults = UserDefaults.standard
    private var existingCacheKey: String { "GestaltX.audioLibrary.existing.\(DeviceConsolePaths.deviceIdentifier)" }
    private var scannedCacheKey: String { "GestaltX.audioLibrary.scanned.\(DeviceConsolePaths.deviceIdentifier)" }

    private var catalogTask: Task<Void, Never>?

    init() {
        let backend = LaunchArtworkCatalogStore.Backend(inventory: LaunchArtworkCatalogStore.Backend.device.inventory, verify: { candidate in
            #if os(iOS) && !targetEnvironment(simulator)
            guard let path = GXCustomizationAccess.applicationContainer(for: candidate.app.id, hint: candidate.container) else {
                return LaunchArtworkAvailability(available: false, retryable: true)
            }
            return LaunchArtworkAvailability(available: !path.isEmpty)
            #else
            return LaunchArtworkAvailability(available: false)
            #endif
        })
        catalog = LaunchArtworkCatalogStore(storage: AppDirectories.audioCatalogStorage,
                                           device: DeviceConsolePaths.deviceIdentifier, backend: backend)
        existing = Set(defaults.stringArray(forKey: existingCacheKey) ?? [])
        scannedExisting = Set(defaults.stringArray(forKey: scannedCacheKey) ?? [])
    }

    func refresh(force: Bool = false) {
        guard catalogTask == nil else { return }
        if force { scannedExisting.removeAll() }
        scanning = true
        catalogTask = Task {
            for await event in catalog.events(force: force) {
                switch event {
                case .snapshot(let apps): installed = Dictionary(apps.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                case .upsert(let app): installed[app.id] = app
                case .remove(let id): installed[id] = nil; existing.remove(id); scannedExisting.remove(id)
                }
                recompute()
            }
            await scanExisting()
            saveScanCache()
            scanning = false
            catalogTask = nil
        }
    }

    /// Directed, ascending-by-size background scan of the four Sound/Sounds
    /// directories (and verified App Groups, inside AppSoundStore.scan). A
    /// temporary read failure leaves an app unscanned so its prior state is kept;
    /// only a confirmed empty scan rules an app out of `existing`.
    private func scanExisting() async {
        let candidates = installed.values
            .filter { !scannedExisting.contains($0.id) }
            .sorted(by: LaunchArtworkAppOrder.before)
        for app in candidates {
            if Task.isCancelled { return }
            do {
                let result = try await sounds.scan(app)
                if result.files.isEmpty { existing.remove(app.id) }
                else { existing.insert(app.id) }
                if !result.partial { scannedExisting.insert(app.id) }
                recompute()
            } catch is CancellationError {
                return
            } catch {
                // leave unscanned; keep whatever we already knew
            }
        }
    }

    private func recompute() {
        let visible = installed.keys.filter { existing.contains($0) }
        applications = visible.compactMap { installed[$0] }.sorted(by: LaunchArtworkAppOrder.before)
    }

    private func saveScanCache() {
        defaults.set(Array(existing), forKey: existingCacheKey)
        defaults.set(Array(scannedExisting), forKey: scannedCacheKey)
    }

    var existingApps: [LaunchArtworkApp] {
        applications.filter { existing.contains($0.id) }
    }
}

@MainActor
final class AppSoundModel: ObservableObject {
    @Published private(set) var files: [AppSoundEntry] = []
    @Published private(set) var partial = false
    @Published private(set) var busy = false
    @Published private(set) var selection: AppSoundSelection?
    @Published private(set) var draft: Data?
    @Published var message: String?
    private var player: AVAudioPlayer?
    private let store = AppSoundStore(storage: AppDirectories.audioStorage,
                                      device: DeviceConsolePaths.deviceIdentifier)

    func scan(_ app: LaunchArtworkApp) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do { let result = try await store.scan(app); files = result.files; partial = result.partial }
        catch { NSLog("LilaShift Audio scan failed for \(app.id): \(error)"); message = error.localizedDescription }
    }

    func select(_ entry: AppSoundEntry, app: LaunchArtworkApp) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        stop(); draft = nil; selection = nil
        do { selection = try await store.select(entry, app: app) }
        catch { NSLog("LilaShift Audio select failed for \(app.id)/\(entry.path): \(error)"); message = error.localizedDescription }
    }
    func choose(_ url: URL) async {
        guard !busy, let selection else { return }
        busy = true; defer { busy = false }
        stop()
        do { draft = try await store.prepare(url, selection: selection) }
        catch { message = error.localizedDescription }
    }
    func play(replacement: Bool) {
        let data: Data?
        if replacement { data = draft } else { data = selection?.current.data }
        guard let data else { return }
        do {
            stop()
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            player = try AVAudioPlayer(data: data)
            guard player?.play() == true else { throw CustomizationFailure("This audio format is not supported.") }
        } catch { message = error.localizedDescription }
    }
    func stop() {
        player?.stop(); player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func discard() { stop(); draft = nil }
    func apply(_ app: LaunchArtworkApp, restore: Bool = false) async {
        guard !busy, let selection else { return }
        busy = true; defer { busy = false }
        stop()
        do {
            if restore { try await store.restore(selection, app: app) }
            else if let draft { try await store.apply(draft, selection: selection, app: app) }
            else { return }
            draft = nil
            let result = try await store.scan(app)
            files = result.files; partial = result.partial
            if let entry = files.first(where: { $0.id == selection.entry.id }) {
                self.selection = try await store.select(entry, app: app)
            } else { self.selection = nil }
            message = L(restore ? "Original audio restored." : "Audio replaced.")
        } catch {
            NSLog("LilaShift Audio \(restore ? "restore" : "apply") failed for \(app.id)/\(selection.entry.path): \(error)")
            message = error.localizedDescription
        }
    }
}

struct AppSoundApplicationsView: View {
    @ObservedObject var customizations: CustomizationModel
    @StateObject private var catalog = AppSoundCatalogModel()
    @State private var search = ""
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        List {
            Section {
                Label(L("Apps that already have notification sounds or audio files"), systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if catalog.scanning { HStack { ProgressView(); Text(L("Reading…")) }.foregroundStyle(.secondary) }
            if !filteredExisting.isEmpty {
                Section(L("Existing Audio")) {
                    ForEach(filteredExisting) { app in appRow(app) }
                }
            }
            if !catalog.scanning && catalog.applications.isEmpty { ContentUnavailableView(L("No Notification Sounds"), systemImage: "bell") }
        }
        .navigationTitle(L("App Audio Library"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { catalog.refresh(force: true) } label: { Image(systemName: "arrow.clockwise") }.disabled(catalog.scanning)
                    .accessibilityLabel(L("Read Again"))
            }
        }
        .task { catalog.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { catalog.refresh() } }
        .transaction { $0.animation = nil }
    }

    private var filteredExisting: [LaunchArtworkApp] { filtered(catalog.existingApps) }

    private func filtered(_ apps: [LaunchArtworkApp]) -> [LaunchArtworkApp] {
        guard !search.isEmpty else { return apps }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search)
        }
    }

    private func appRow(_ app: LaunchArtworkApp) -> some View {
        NavigationLink { AppSoundFilesView(app: app, customizations: customizations) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).lineLimit(1)
                Text(app.id).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

private struct AppSoundFilesView: View {
    let app: LaunchArtworkApp
    @ObservedObject var customizations: CustomizationModel
    @StateObject private var model = AppSoundModel()
    @State private var search = ""
    var body: some View {
        List {
            if model.busy { HStack { ProgressView(); Text(L("Reading…")) }.foregroundStyle(.secondary) }
            ForEach(model.files.filter { search.isEmpty || $0.path.localizedCaseInsensitiveContains(search) }) { entry in
                NavigationLink { AppSoundEditor(app: app, entry: entry, customizations: customizations) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text((entry.path as NSString).lastPathComponent).lineLimit(1)
                        Text(entry.group.map { $0 + "/" + entry.path } ?? entry.path).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            if !model.busy && model.files.isEmpty {
                ContentUnavailableView(L("No Notification Sounds"), systemImage: "bell")
            }
            if model.partial { Section { Text(L("Some folders could not be read or the scan limit was reached.")).foregroundStyle(.secondary) } }
            if !model.files.isEmpty {
                Section {} footer: { Text(L("Not every sound listed is the current notification sound. Preview the sounds before replacing one.")) }
            }
        }
        .navigationTitle(app.name).navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search)
        .toolbar { ToolbarItem(placement: .topBarTrailing) {
            Button { Task { await model.scan(app) } } label: { Image(systemName: "arrow.clockwise") }.disabled(model.busy)
                .accessibilityLabel(L("Read Again"))
        } }
        .task { await model.scan(app) }
        // Returning from an editor must show a newly replaced sound
        // and the refreshed restore state immediately.
        .onAppear { Task { await model.scan(app) } }
        .alert(L("LilaShift"), isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button(L("OK"), role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}

private struct AppSoundEditor: View {
    let app: LaunchArtworkApp
    let entry: AppSoundEntry
    @ObservedObject var customizations: CustomizationModel
    @StateObject private var model = AppSoundModel()
    @State private var importsAudio = false
    @State private var confirmsApply = false
    @State private var confirmsRestore = false
    @State private var presentationOwner = UUID()
    private var presenting: Bool { model.busy || model.draft != nil || importsAudio || confirmsApply || confirmsRestore || model.message != nil }
    var body: some View {
        List {
            Section {
                Text(entry.group.map { $0 + "/" + entry.path } ?? entry.path).font(.footnote).textSelection(.enabled)
                Button { model.play(replacement: false) } label: { Label(L("Play Current Audio"), systemImage: "play.fill") }
                    .disabled(model.selection == nil)
                Button { importsAudio = true } label: { Label(L("Choose Audio"), systemImage: "square.and.arrow.down") }
                    .disabled(model.selection == nil)
                if model.draft != nil {
                    Button { model.play(replacement: true) } label: { Label(L("Play Replacement"), systemImage: "play.fill") }
                    Button { model.discard() } label: { Label(L("Discard Changes"), systemImage: "xmark") }.tint(.red)
                }
            }
            Section {
                Button { confirmsApply = true } label: { Label(L("Apply Changes"), systemImage: "checkmark") }.disabled(model.draft == nil)
                Button { confirmsRestore = true } label: { Label(L("Restore Original Audio"), systemImage: "arrow.uturn.backward") }
                    .disabled(model.selection?.canRestore != true)
            }
        }
        .disabled(model.busy)
        .navigationTitle((entry.path as NSString).lastPathComponent).navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { if model.busy { ProgressView() } } }
        .task { await model.select(entry, app: app) }
        .onChange(of: presenting, initial: true) { _, value in customizations.setPresenting(value, owner: presentationOwner) }
        .onDisappear { model.stop(); if !importsAudio { customizations.setPresenting(false, owner: presentationOwner) } }
        .sheet(isPresented: $importsAudio) {
            CustomizationFilePicker { result in
                importsAudio = false
                switch result {
                case .success(let url): Task { await model.choose(url) }
                case .failure(let error):
                    if (error as NSError).code != CocoaError.userCancelled.rawValue {
                        model.message = error.localizedDescription
                    }
                }
            }
            .ignoresSafeArea()
        }
        .alert(L("Apply these changes?"), isPresented: $confirmsApply) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Apply")) { Task { await model.apply(app) } }
        }
        .alert(L("Restore Original Audio"), isPresented: $confirmsRestore) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Restore Audio")) { Task { await model.apply(app, restore: true) } }
        }
        .alert(L("LilaShift"), isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button(L("OK"), role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
    }
}
