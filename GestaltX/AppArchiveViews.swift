// SPDX-License-Identifier: GPL-3.0-only
// App archive & cache view (Stage 7, ADR-2-10, TASKBOOK §6).
//
// Archives and cache analysis for THIS app's own data only: the
// app's own Documents, its own cache, files the user picks, data
// shared into the app, and authorized App Group data. The view
// says so on screen — it never presents itself as able to read or
// delete another app's private data (e.g. WeChat). Long work runs
// in a detached task with real progress and a cancel button;
// restoring an archive first verifies it, backs up the current
// state, and then reports restored, skipped and failed items.
import SwiftUI
import UniformTypeIdentifiers

struct AppArchiveView: View {
    let share: (TemporaryExport) -> Void

    @State private var scan: ArchiveScan?
    @State private var selectedRoot: ArchiveRootKind = .ownDocuments
    @State private var isWorking = false
    @State private var workProgress = 0.0
    @State private var workLabel = ""
    @State private var activeTask: Task<Void, Never>?
    /// The in-flight archive scan / cache measurement tasks, if any.
    /// Scanning reads every archive's manifest and measuring
    /// enumerates the whole container (TASKBOOK §8.2), so both run
    /// in detached tasks; starting a new one cancels the previous.
    @State private var scanTask: Task<Void, Never>?
    @State private var cacheTask: Task<Void, Never>?
    @State private var creationReport: ArchiveCreationReport?
    @State private var restoreReport: ArchiveRestoreReport?
    @State private var restoreCandidate: AppArchiveInfo?
    @State private var deleteCandidate: AppArchiveInfo?
    @State private var workError: String?
    @State private var cacheReport: CacheReport?
    @State private var selectedDeletable: Set<String> = []
    @State private var deletionReport: CacheDeletionReport?
    @State private var confirmsDeleteCache = false
    @State private var showingFileImporter = false
    @State private var pendingUserFileRestore: AppArchiveInfo?
    @State private var exportError: String?

    private var byteFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }

    private func formatBytes(_ bytes: Int) -> String {
        byteFormatter.string(fromByteCount: Int64(bytes))
    }

    /// The one-line deletion summary. Built from separate statements:
    /// the single `+` chain of localized fragments and interpolations
    /// it replaced timed out the type checker (CI #372).
    private func deletionSummary(for report: CacheDeletionReport) -> String {
        let deleted = L("Deleted") + ": \(report.deleted.count)"
        let freed = L("Freed") + ": " + formatBytes(report.freedBytes)
        let skipped = L("Skipped (protected)") + ": \(report.skippedProtected.count)"
        let failed = L("Failed") + ": \(report.failed.count)"
        return [deleted, freed, skipped, failed].joined(separator: " · ")
    }

    private var selectedEntries: [CacheEntry] {
        (cacheReport?.entries ?? []).filter { selectedDeletable.contains($0.relativePath) }
    }

    private var selectedBytes: Int {
        selectedEntries.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        List {
            Section {
                Text(L("App Archive only archives this app's own data: its Documents, its cache, files you pick, data you share into the app, and authorized App Group data. It cannot read or delete another app's private data."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } header: { Text(L("Scope")) }

            Section {
                Picker(L("Archive Source"), selection: $selectedRoot) {
                    ForEach(ArchiveRootKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .disabled(isWorking)
                Button { startCreate() } label: {
                    Label(L("Create Archive"), systemImage: "archivebox.fill")
                }
                .disabled(isWorking)
                if isWorking {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: workProgress) {
                            Text(workLabel)
                        }
                        Button(L("Cancel"), role: .destructive) { activeTask?.cancel() }
                    }
                }
                if let creationReport {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Archive created."))
                            .font(.subheadline).fontWeight(.medium)
                        Text(L("Files") + ": \(creationReport.entries.count) · " + formatBytes(creationReport.totalBytes))
                            .font(.caption).foregroundStyle(.secondary)
                        if !creationReport.skippedSymlinks.isEmpty {
                            Text(L("Skipped symbolic links:") + " \(creationReport.skippedSymlinks.count)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let workError {
                    Text(workError).font(.caption).foregroundStyle(.red)
                }
            } header: { Text(L("Create Archive")) }

            Section {
                if let scan, !scan.valid.isEmpty {
                    ForEach(scan.valid, id: \.manifest.id) { info in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(info.manifest.root.title).font(.subheadline).fontWeight(.medium)
                                Spacer()
                                Text(formatBytes(info.byteCount)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(info.manifest.createdAt, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                            Text(L("Files") + ": \(info.manifest.entries.count)")
                                .font(.caption).foregroundStyle(.secondary)
                            HStack(spacing: 16) {
                                Button(L("Restore")) { restoreCandidate = info }
                                    .disabled(isWorking)
                                Button(L("Export Manifest")) { exportManifest(of: info) }
                                Button(L("Delete"), role: .destructive) { deleteCandidate = info }
                                    .disabled(isWorking)
                            }
                            .font(.subheadline)
                        }.padding(.vertical, 4)
                    }
                } else {
                    Text(L("No archives yet.")).font(.subheadline).foregroundStyle(.secondary)
                }
                if let scan, !scan.corrupt.isEmpty {
                    ForEach(scan.corrupt, id: \.self) { name in
                        Label(L("Corrupt archive (manifest unreadable):") + " \(name)",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
                if let restoreReport {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Restore finished."))
                            .font(.subheadline).fontWeight(.medium)
                        Text(L("Restored") + ": \(restoreReport.restored.count) · "
                             + L("Skipped") + ": \(restoreReport.skipped.count) · "
                             + L("Failed") + ": \(restoreReport.failed.count)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(L("Pre-restore backup:") + " \(restoreReport.preRestoreArchiveID.uuidString)")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(restoreReport.failed, id: \.path) { failure in
                            Text(failure.path + ": " + failure.reason)
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            } header: { Text(L("Archives")) } footer: {
                Text(L("Restoring first verifies the archive, then backs up the current state, so a failed restore can go back."))
            }

            Section {
                Button { measureCache() } label: {
                    Label(L("Measure Cache"), systemImage: "internaldrive")
                }
                if let cacheReport {
                    Text(L("Files") + ": \(cacheReport.totalFiles) · "
                         + L("Total") + ": " + formatBytes(cacheReport.totalSize) + " · "
                         + L("Safe to delete") + ": " + formatBytes(cacheReport.deletableBytes))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(cacheReport.entries.prefix(25), id: \.self) { entry in
                        cacheRow(entry)
                    }
                    if cacheReport.entries.count > 25 {
                        Text(L("Showing the 25 largest files."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !selectedDeletable.isEmpty {
                        Button(L("Delete Selected") + " (\(selectedDeletable.count) · \(formatBytes(selectedBytes)))",
                               role: .destructive) { confirmsDeleteCache = true }
                        .disabled(isWorking)
                    }
                    Button(L("Clear App Caches"), role: .destructive) { clearCaches() }
                        .disabled(isWorking)
                }
                if let deletionReport {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(deletionSummary(for: deletionReport))
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(deletionReport.failed, id: \.path) { failure in
                            Text(failure.path + ": " + failure.reason)
                                .font(.caption).foregroundStyle(.red)
                        }
                    }
                }
            } header: { Text(L("Cache Analysis")) } footer: {
                Text(L("Only files this analysis lists as safe to delete can be selected. Documents, chat libraries and login state are never listed as deletable."))
            }
        }
        .navigationTitle(L("App Archive & Cache"))
        .task { refreshScan() }
        .onDisappear { scanTask?.cancel(); cacheTask?.cancel() }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [UTType.item],
                      allowsMultipleSelection: false) { result in
            handlePickedFile(result)
        }
        .alert(L("Restore This Archive?"), isPresented: Binding(
            get: { restoreCandidate != nil },
            set: { if !$0 { restoreCandidate = nil } })) {
                Button(L("Restore"), role: .destructive) {
                    if let info = restoreCandidate { startRestore(info) }
                    restoreCandidate = nil
                }
                Button(L("Cancel"), role: .cancel) { restoreCandidate = nil }
            } message: {
                if let info = restoreCandidate {
                    Text(L("The archive will be verified first, then the current state is backed up before anything is written. Files:") + " \(info.manifest.entries.count)")
                }
            }
        .alert(L("Delete This Archive?"), isPresented: Binding(
            get: { deleteCandidate != nil },
            set: { if !$0 { deleteCandidate = nil } })) {
                Button(L("Delete"), role: .destructive) {
                    if let info = deleteCandidate { deleteArchive(info) }
                    deleteCandidate = nil
                }
                Button(L("Cancel"), role: .cancel) { deleteCandidate = nil }
            } message: {
                Text(L("The archive file will be deleted. This cannot be undone."))
            }
        .alert(L("Delete Selected Cache Files?"), isPresented: $confirmsDeleteCache) {
            Button(L("Delete"), role: .destructive) { deleteSelectedCache() }
            Button(L("Cancel"), role: .cancel) { }
        } message: {
            Text(L("Files") + ": \(selectedDeletable.count) · " + formatBytes(selectedBytes))
        }
        .alert(L("Export Failed"), isPresented: Binding(
            get: { exportError != nil },
            set: { if !$0 { exportError = nil } })) {
                Button(L("OK"), role: .cancel) { exportError = nil }
            } message: { Text(exportError ?? "") }
    }

    private func cacheRow(_ entry: CacheEntry) -> some View {
        HStack(spacing: 8) {
            if entry.safeToDelete {
                Toggle("", isOn: Binding(
                    get: { selectedDeletable.contains(entry.relativePath) },
                    set: { on in
                        if on { selectedDeletable.insert(entry.relativePath) }
                        else { selectedDeletable.remove(entry.relativePath) }
                    }))
                .labelsHidden()
            } else {
                Image(systemName: "lock.fill").foregroundStyle(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.relativePath).font(.caption).lineLimit(2)
                HStack(spacing: 6) {
                    Text(formatBytes(entry.size)).font(.caption).foregroundStyle(.secondary)
                    Text(entry.category.title).font(.caption).foregroundStyle(.secondary)
                    if let lastAccessed = entry.lastAccessed {
                        Text(lastAccessed, format: .dateTime.year().month().day())
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text(L("Last access unknown")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let reason = entry.protectionReason {
                    Text(reason).font(.caption).foregroundStyle(.orange)
                }
            }
            Spacer()
        }.padding(.vertical, 2)
    }

    // MARK: - Archives

    /// Scans the archives directory off the main thread (TASKBOOK
    /// §8.2): `scanArchives` opens every archive's manifest, so it
    /// never runs synchronously in `.task` (main actor) or after a
    /// create/restore. Only the result is published.
    private func refreshScan() {
        scanTask?.cancel()
        scanTask = Task.detached(priority: .userInitiated) {
            let result = AppArchiveEngine.scanArchives(in: AppArchiveEngine.archivesDirectory())
            guard !Task.isCancelled else { return }
            await MainActor.run { scan = result }
        }
    }

    private func startCreate() {
        if selectedRoot == .userFile {
            showingFileImporter = true
            return
        }
        guard let source = AppArchiveEngine.resolveSource(for: selectedRoot) else {
            workError = L("The archive source could not be resolved.")
            return
        }
        create(source: source)
    }

    private func handlePickedFile(_ result: Result<[URL], Error>) {
        // A pending user-file restore: the picked URL is the file to
        // restore onto (the archive stores no absolute path).
        if let info = pendingUserFileRestore {
            pendingUserFileRestore = nil
            switch result {
            case .success(let urls):
                guard let picked = urls.first else { return }
                let source = ArchiveSource(
                    rootURL: picked, kind: .userFile, sourceApp: info.manifest.sourceApp)
                let scoped = picked.startAccessingSecurityScopedResource()
                restore(info: info, source: source, scopedURL: scoped ? picked : nil)
            case .failure(let error):
                workError = error.localizedDescription
            }
            return
        }
        switch result {
        case .success(let urls):
            guard let picked = urls.first else { return }
            isWorking = true
            workLabel = L("Staging picked file…")
            workError = nil
            activeTask = Task.detached(priority: .userInitiated) {
                let staged: URL
                do {
                    staged = try CustomizationFiles.stagePickedFile(picked)
                } catch {
                    await MainActor.run {
                        isWorking = false
                        workProgress = 0
                        workError = error.localizedDescription
                    }
                    return
                }
                // The staged copy is discarded on every path out.
                defer { CustomizationFiles.discardStagedDirectory(containing: staged) }
                do {
                    let source = ArchiveSource(rootURL: staged, kind: .userFile,
                                               sourceApp: Bundle.main.bundleIdentifier ?? "com.huami.gestultx")
                    await MainActor.run { workLabel = L("Creating archive…") }
                    let report = try await AppArchiveEngine.createArchive(from: source) { fraction in
                        Task { @MainActor in workProgress = fraction }
                    }
                    await MainActor.run { finishCreate(report: report) }
                } catch is CancellationError {
                    await MainActor.run { resetWork() }
                } catch {
                    await MainActor.run {
                        isWorking = false
                        workProgress = 0
                        workError = error.localizedDescription
                    }
                }
            }
        case .failure(let error):
            workError = error.localizedDescription
        }
    }

    private func create(source: ArchiveSource) {
        isWorking = true
        workProgress = 0
        workLabel = L("Creating archive…")
        workError = nil
        creationReport = nil
        activeTask = Task.detached(priority: .userInitiated) {
            do {
                let report = try await AppArchiveEngine.createArchive(from: source) { fraction in
                    Task { @MainActor in workProgress = fraction }
                }
                await MainActor.run { finishCreate(report: report) }
            } catch is CancellationError {
                await MainActor.run { resetWork() }
            } catch {
                await MainActor.run {
                    isWorking = false
                    workProgress = 0
                    workError = error.localizedDescription
                }
            }
        }
    }

    private func finishCreate(report: ArchiveCreationReport) {
        creationReport = report
        isWorking = false
        workProgress = 1
        refreshScan()
    }

    private func resetWork() {
        isWorking = false
        workProgress = 0
        workLabel = ""
    }

    private func startRestore(_ info: AppArchiveInfo) {
        if info.manifest.root == .userFile {
            // A picked-file archive restores onto the file itself:
            // the user picks the target file to restore onto.
            pendingUserFileRestore = info
            showingFileImporter = true
            return
        }
        guard let source = AppArchiveEngine.resolveSource(for: info.manifest.root) else {
            workError = L("The archive source could not be resolved.")
            return
        }
        restore(info: info, source: source)
    }

    private func restore(info: AppArchiveInfo, source: ArchiveSource, scopedURL: URL? = nil) {
        isWorking = true
        workProgress = 0
        workLabel = L("Restoring archive…")
        workError = nil
        restoreReport = nil
        activeTask = Task.detached(priority: .userInitiated) {
            defer { if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() } }
            do {
                let report = try await AppArchiveEngine.restoreArchive(at: info.fileURL, to: source) { fraction in
                    Task { @MainActor in workProgress = fraction }
                }
                await MainActor.run {
                    restoreReport = report
                    isWorking = false
                    workProgress = 1
                    refreshScan()
                }
            } catch is CancellationError {
                await MainActor.run { resetWork() }
            } catch {
                await MainActor.run {
                    isWorking = false
                    workProgress = 0
                    workError = error.localizedDescription
                }
            }
        }
    }

    private func deleteArchive(_ info: AppArchiveInfo) {
        do {
            try AppArchiveEngine.deleteArchive(at: info.fileURL)
            refreshScan()
        } catch {
            workError = error.localizedDescription
        }
    }

    private func exportManifest(of info: AppArchiveInfo) {
        do {
            let data = try AppArchiveEngine.canonicalManifestData(for: info.manifest)
            let export = try TemporaryExport(
                data: data, name: "archive-\(info.manifest.id.uuidString)-manifest.json")
            share(export)
        } catch {
            exportError = error.localizedDescription
        }
    }

    // MARK: - Cache

    /// Measures the container off the main thread (TASKBOOK §8.2):
    /// `analyzeContainer` enumerates Application Support, Caches
    /// and tmp with a per-file stat, so it never runs synchronously
    /// from the Measure button, after a delete, or after clearing
    /// caches. A fresh measurement clears a stale deletion report,
    /// unless the caller passes the report it just produced —
    /// previously `measureCache()` unconditionally cleared
    /// `deletionReport`, so the report set by a delete/clear was
    /// swallowed before it could display.
    private func measureCache(keeping report: CacheDeletionReport? = nil) {
        cacheTask?.cancel()
        cacheTask = Task.detached(priority: .userInitiated) {
            let result = CacheAnalyzer.analyzeContainer()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                cacheReport = result
                selectedDeletable.removeAll()
                deletionReport = report
            }
        }
    }

    private func deleteSelectedCache() {
        isWorking = true
        workError = nil
        let entries = selectedEntries
        activeTask = Task.detached(priority: .userInitiated) {
            do {
                let report = try CacheAnalyzer.deleteTracked(entries)
                await MainActor.run {
                    isWorking = false
                    measureCache(keeping: report)
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    workError = error.localizedDescription
                }
            }
        }
    }

    /// Clears the app's Caches directories off the main thread
    /// (TASKBOOK §8.2): deleting files and re-enumerating the
    /// container never run on the main actor.
    private func clearCaches() {
        isWorking = true
        workError = nil
        activeTask = Task.detached(priority: .userInitiated) {
            do {
                let freed = try CacheAnalyzer.clearContainerCaches()
                let report = CacheDeletionReport(
                    deleted: [], skippedProtected: [], failed: [], freedBytes: Int(freed))
                await MainActor.run {
                    isWorking = false
                    measureCache(keeping: report)
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    workError = error.localizedDescription
                }
            }
        }
    }
}
