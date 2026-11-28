// SPDX-License-Identifier: GPL-3.0-only
// W6 file browser views (LilaShift 5.0.0 Wave 1, W6) — SwiftUI for
// the W6 engine (`W6FileBrowser.swift`). Views never touch the
// file system: every path, listing, measurement and copy comes
// from the engine. Cross-app pages are read-only, and no page
// offers any cleanup: the batch bar shares and packs only, and
// the cache page only measures. Batch delete and any cross-app
// cleanup are deliberately not in this workflow.
import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - Entry page

/// The W6 entry page: one row per feature, each opening its own
/// page. The coordinator wires this page into the app; the
/// registration metadata lives in `W6Registration`.
struct W6FileBrowserHomeView: View {
    let osBuild: String?

    var body: some View {
        List {
            Section {
                NavigationLink {
                    W6FileBrowserView()
                } label: {
                    W6HomeRow(
                        title: L("File Browser"),
                        detail: L("Browse, multi-select and import folders."))
                }
                NavigationLink {
                    W6CrossAppBrowserView(osBuild: osBuild)
                } label: {
                    W6HomeRow(
                        title: L("Cross-App File Browser"),
                        detail: L("Read-only browsing of other apps' containers."))
                }
                NavigationLink {
                    W6SplashAdPathsView(osBuild: osBuild)
                } label: {
                    W6HomeRow(
                        title: L("Splash Ad Cache Paths"),
                        detail: L("Known splash-ad paths for 7 apps, pending verification."))
                }
                NavigationLink {
                    W6CrossAppCacheView(osBuild: osBuild)
                } label: {
                    W6HomeRow(
                        title: L("Cross-App Cache Usage"),
                        detail: L("Read-only cache statistics per app. No cleanup here."))
                }
            } header: {
                Text(L("File Browser"))
            } footer: {
                Text(L("Cross-app access works through iOS 27.3 beta 1. It is blocked from iOS 27.3 beta 2 on."))
            }
        }
        .navigationTitle(L("File Browser"))
    }
}

private struct W6HomeRow: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - File browser (features 1 + 2)

/// The file browser: directory listing, multi-select with a
/// bottom batch bar (share, pack as ZIP), and file/folder import.
/// Import writes only into the directory currently shown, which
/// is always the app's own container or a directory the user
/// picked — never into another app's container.
struct W6FileBrowserView: View {
    @State private var roots: [W6BrowserRoot] = []
    @State private var selectedRootID: String?
    @State private var pathComponents: [String] = []
    @State private var entries: [W6FileEntry] = []
    @State private var selection = W6FileSelection()
    @State private var selecting = false
    @State private var showFileImport = false
    @State private var showFolderImport = false
    @State private var importResult: W6ImportResult?
    @State private var shareURLs: [URL] = []
    @State private var archiveError: String?
    @State private var isWorking = false

    private var selectedRoot: W6BrowserRoot? {
        roots.first { $0.id == selectedRootID } ?? roots.first
    }

    private var relativePath: String {
        pathComponents.joined(separator: "/")
    }

    private var currentDirectory: URL? {
        guard let root = selectedRoot else { return nil }
        return relativePath.isEmpty
            ? root.url
            : root.url.appendingPathComponent(relativePath)
    }

    private var summary: W6BatchSummary {
        selection.summary(for: entries)
    }

    var body: some View {
        VStack(spacing: 0) {
            if roots.isEmpty {
                ContentUnavailableView(
                    L("No browsable folders"),
                    systemImage: "folder",
                    description: Text(L("The app container could not be opened.")))
            } else {
                Picker(L("Location"), selection: $selectedRootID) {
                    ForEach(roots) { root in
                        Text(root.title).tag(Optional(root.id))
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, GlassTokens.pageMargin)
                .onChange(of: selectedRootID) { _, _ in
                    pathComponents = []
                    selection.deselectAll()
                    refresh()
                }
                List {
                    if entries.isEmpty {
                        ContentUnavailableView(
                            L("This folder is empty."),
                            systemImage: "folder",
                            description: Text(L("Nothing was found here, or the folder could not be read.")))
                    }
                    ForEach(entries) { entry in
                        W6EntryRow(
                            entry: entry, selecting: selecting,
                            selected: selection.contains(entry),
                            onToggle: { selection.toggle(entry) },
                            onOpen: {
                                if entry.isDirectory {
                                    pathComponents.append(entry.name)
                                    selection.deselectAll()
                                    refresh()
                                }
                            })
                    }
                }
                .refreshable { refresh() }
            }
            if selecting {
                W6BatchBar(
                    summary: summary,
                    onSelectAll: { selection.selectAll(in: entries) },
                    onDeselectAll: { selection.deselectAll() },
                    onInvert: { selection.invert(in: entries) },
                    onShare: { shareURLs = selection.selected(in: entries).map(\.url) },
                    onPack: packSelection)
            }
        }
        .navigationTitle(pathComponents.last ?? selectedRoot?.title ?? L("File Browser"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button(selecting ? L("Done") : L("Select…")) { selecting.toggle() }
                    Button(L("Import Files…")) { showFileImport = true }
                    Button(L("Import Folder…")) { showFolderImport = true }
                    if !pathComponents.isEmpty {
                        Button(L("Up One Level")) {
                            pathComponents.removeLast()
                            selection.deselectAll()
                            refresh()
                        }
                    }
                } label: {
                    Label(L("Actions"), systemImage: "ellipsis.circle")
                }
            }
        }
        .task { loadRoots() }
        .fileImporter(
            isPresented: $showFileImport,
            allowedContentTypes: [UTType.item],
            allowsMultipleSelection: true
        ) { result in importPickedFiles(result) }
        .fileImporter(
            isPresented: $showFolderImport,
            allowedContentTypes: [UTType.folder],
            allowsMultipleSelection: false
        ) { result in importPickedFolder(result) }
        .sheet(isPresented: Binding(
            get: { !shareURLs.isEmpty },
            set: { if !$0 { shareURLs = [] } }
        )) {
            W6ShareSheet(urls: shareURLs)
        }
        .alert(
            L("Import finished"),
            isPresented: Binding(
                get: { importResult != nil },
                set: { if !$0 { importResult = nil } }
            ),
            presenting: importResult
        ) { _ in
            Button(L("OK"), role: .cancel) {}
        } message: { result in
            Text(W6ImportReportText.text(for: result))
        }
        .alert(
            L("Could not pack the selection"),
            isPresented: Binding(
                get: { archiveError != nil },
                set: { if !$0 { archiveError = nil } }
            ),
            presenting: archiveError
        ) { _ in
            Button(L("OK"), role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .overlay {
            if isWorking {
                ProgressView().padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: GlassTokens.smallRadius))
            }
        }
    }

    private func loadRoots() {
        let loaded = W6FileBrowser.roots()
        roots = loaded
        selectedRootID = loaded.first?.id
        refresh()
    }

    private func refresh() {
        guard let root = selectedRoot else {
            entries = []
            return
        }
        entries = W6FileBrowser.list(root: root.url, relativePath: relativePath)
        selection.prune(to: entries)
    }

    private func packSelection() {
        let chosen = selection.selected(in: entries)
        guard !chosen.isEmpty else { return }
        isWorking = true
        Task.detached {
            do {
                let url = try W6BatchArchive.archive(
                    entries: chosen, to: W6FileBrowser.temporaryExportDirectory())
                await MainActor.run {
                    isWorking = false
                    shareURLs = [url]
                }
            } catch {
                await MainActor.run {
                    isWorking = false
                    archiveError = error.localizedDescription
                }
            }
        }
    }

    private func importPickedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let destination = currentDirectory, !urls.isEmpty else { return }
        isWorking = true
        Task.detached {
            var combined = W6ImportResult(copied: [], skipped: [], failed: [],
                                          copiedBytes: 0, copiedFiles: 0)
            for url in urls {
                let opened = url.startAccessingSecurityScopedResource()
                defer { if opened { url.stopAccessingSecurityScopedResource() } }
                let single = W6FolderImport.copyFile(source: url, into: destination)
                combined = W6ImportResult(
                    copied: combined.copied + single.copied,
                    skipped: combined.skipped + single.skipped,
                    failed: combined.failed + single.failed,
                    copiedBytes: combined.copiedBytes + single.copiedBytes,
                    copiedFiles: combined.copiedFiles + single.copiedFiles)
            }
            let finalResult = combined
            await MainActor.run {
                isWorking = false
                importResult = finalResult
                refresh()
            }
        }
    }

    private func importPickedFolder(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result,
              let url = urls.first,
              let destination = currentDirectory else { return }
        isWorking = true
        Task.detached {
            let opened = url.startAccessingSecurityScopedResource()
            defer { if opened { url.stopAccessingSecurityScopedResource() } }
            let outcome = W6FolderImport.copyFolder(source: url, into: destination)
            await MainActor.run {
                isWorking = false
                importResult = outcome
                refresh()
            }
        }
    }
}

private struct W6EntryRow: View {
    let entry: W6FileEntry
    let selecting: Bool
    let selected: Bool
    let onToggle: () -> Void
    let onOpen: () -> Void

    var body: some View {
        Button {
            if selecting { onToggle() } else { onOpen() }
        } label: {
            HStack {
                if selecting {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? .accent : .secondary)
                }
                Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name).lineLimit(1)
                    if !entry.isDirectory {
                        Text(W6Format.bytes(entry.byteCount))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if entry.isDirectory {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct W6BatchBar: View {
    let summary: W6BatchSummary
    let onSelectAll: () -> Void
    let onDeselectAll: () -> Void
    let onInvert: () -> Void
    let onShare: () -> Void
    let onPack: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(W6BatchBarText.summary(summary))
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Button(L("Select All"), action: onSelectAll)
                Button(L("Deselect All"), action: onDeselectAll)
                Button(L("Invert"), action: onInvert)
            }
            .font(.subheadline)
            HStack(spacing: 12) {
                Button(L("Share"), action: onShare)
                    .buttonStyle(.bordered)
                    .disabled(summary.count == 0)
                Button(L("Pack as ZIP"), action: onPack)
                    .buttonStyle(.borderedProminent)
                    .disabled(summary.count == 0)
            }
            Text(L("Batch delete is not in this workflow."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, GlassTokens.pageMargin)
        .background(.thinMaterial)
    }
}

private enum W6BatchBarText {
    static func summary(_ summary: W6BatchSummary) -> String {
        if summary.count == 0 {
            return L("Nothing selected.")
        }
        return String(format: L("%d selected (%d files, %@)"),
                      summary.count, summary.fileCount, W6Format.bytes(summary.fileBytes))
    }
}

private enum W6ImportReportText {
    static func text(for result: W6ImportResult) -> String {
        var parts: [String] = []
        parts.append(String(format: L("Copied %d files (%@)."),
                            result.copiedFiles, W6Format.bytes(result.copiedBytes)))
        if !result.skipped.isEmpty {
            parts.append(String(format: L("Skipped %d items."), result.skipped.count))
        }
        if !result.failed.isEmpty {
            parts.append(String(format: L("Failed: %d items."), result.failed.count))
            for failure in result.failed.prefix(3) {
                parts.append(failure.path + ": " + failure.reason)
            }
        }
        return parts.joined(separator: "\n")
    }
}

private struct W6ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Cross-app browser (feature 4)

/// Read-only cross-app browsing. The sentinel banner is shown
/// first: on a blocked or unknown build the list is replaced by
/// the version guidance, never by an empty list that looks like
/// "this app has no files".
struct W6CrossAppBrowserView: View {
    let osBuild: String?

    @State private var apps: [W6CrossAppTarget] = []
    @State private var loaded = false

    private var sentinel: VersionSentinelState {
        W6CrossAppBrowser.sentinelState(osBuild: osBuild)
    }

    var body: some View {
        List {
            W6SentinelBanner(state: sentinel)
            if apps.isEmpty {
                ContentUnavailableView(
                    L("No apps found"),
                    systemImage: "app.dashed",
                    description: Text(L("No installed apps could be listed on this device.")))
            }
            ForEach(apps) { app in
                NavigationLink {
                    W6CrossAppFolderView(app: app, osBuild: osBuild)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.name).font(.headline)
                        Text(app.bundleID).font(.caption).foregroundStyle(.secondary)
                        Text(app.containerPath ?? L("Container not located"))
                            .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }
                .disabled(sentinel != .supported)
            }
        }
        .navigationTitle(L("Cross-App File Browser"))
        .task {
            if !loaded {
                apps = W6CrossAppBrowser.installedApps()
                loaded = true
            }
        }
    }
}

private struct W6CrossAppFolderView: View {
    let app: W6CrossAppTarget
    let osBuild: String?

    @State private var pathComponents: [String] = []
    @State private var listing: W6CrossAppListing?

    private var relativePath: String {
        pathComponents.joined(separator: "/")
    }

    var body: some View {
        List {
            if let listing {
                if !listing.reachable {
                    ContentUnavailableView(
                        L("Cannot open this container"),
                        systemImage: "exclamationmark.triangle",
                        description: Text(listing.note))
                } else if listing.entries.isEmpty {
                    ContentUnavailableView(
                        L("This folder is empty."),
                        systemImage: "folder",
                        description: Text(L("Nothing was found here.")))
                }
                ForEach(listing.entries) { entry in
                    Button {
                        if entry.isDirectory {
                            pathComponents.append(entry.name)
                            refresh()
                        }
                    } label: {
                        HStack {
                            Image(systemName: entry.isDirectory ? "folder.fill" : "doc")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).lineLimit(1)
                                if !entry.isDirectory {
                                    Text(W6Format.bytes(entry.byteCount))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if entry.isDirectory {
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!entry.isDirectory)
                }
            }
        }
        .navigationTitle(pathComponents.last ?? app.name)
        .toolbar {
            if !pathComponents.isEmpty {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L("Up One Level")) {
                        pathComponents.removeLast()
                        refresh()
                    }
                }
            }
        }
        .task { refresh() }
        .refreshable { refresh() }
    }

    private func refresh() {
        listing = W6CrossAppBrowser.list(app: app, relativePath: relativePath, osBuild: osBuild)
    }
}

private struct W6SentinelBanner: View {
    let state: VersionSentinelState

    var body: some View {
        Section {
            switch state {
            case .supported:
                Label(
                    String(format: L("Supported through %@."), VersionSentinel.supportedThroughLabel),
                    systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
            case .blocked, .unknownBuild:
                VStack(alignment: .leading, spacing: 6) {
                    Label(L("Cross-app access is unavailable on this iOS version."), systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(VersionSentinel.supportedRangeDescription(for: state))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if let guidance = VersionSentinel.guidance(for: state) {
                        Text(guidance).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Splash-ad paths (feature 3)

/// The splash-ad path table, grouped by app, with each path's
/// verification state. A "核对" section checks the table against
/// a real installed app container when one is available — but
/// every path stays "待核实" until a maintainer confirms it on
/// a real device. This page never locks, clears or edits
/// anything: recognition only.
struct W6SplashAdPathsView: View {
    let osBuild: String?

    @State private var checkedAppID: String?
    @State private var matches: [W6SplashAdMatch] = []
    @State private var genericMatches: [W6SplashAdMatch] = []
    @State private var checkedContainerReachable = false

    private var tableApps: [(bundleID: String, appName: String)] {
        W6SplashAdPathTable.apps
    }

    private var installedTableApps: [W6CrossAppTarget] {
        let wanted = Set(tableApps.map(\.bundleID))
        return W6CrossAppBrowser.installedApps().filter { wanted.contains($0.bundleID) }
    }

    var body: some View {
        List {
            Section {
                Text(W6SplashAdPathTable.tableVersion)
                    .font(.caption).foregroundStyle(.secondary)
                Text(L("Paths change with app versions. Every path below is pending verification until it is confirmed on a real device. This page only recognises paths; it never locks or clears anything."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } header: {
                Text(L("About this table"))
            }
            ForEach(tableApps, id: \.bundleID) { app in
                Section(app.appName) {
                    ForEach(W6SplashAdPathTable.entries(for: app.bundleID), id: \.relativePath) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.relativePath).font(.subheadline).lineLimit(2)
                            HStack {
                                Text(entry.verification.title)
                                    .font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 2)
                                    .background(.quaternary, in: Capsule())
                                Text(entry.source).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Section {
                if installedTableApps.isEmpty {
                    Text(L("None of the 7 table apps are installed, or their containers could not be listed on this device."))
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Picker(L("Check against app"), selection: $checkedAppID) {
                        Text(L("Choose an app")).tag(String?(nil))
                        ForEach(installedTableApps) { app in
                            Text(app.name).tag(Optional(app.bundleID))
                        }
                    }
                    .pickerStyle(.menu)
                    Button(L("Check paths in this app's container")) {
                        checkSelectedApp()
                    }
                    .disabled(checkedAppID == nil)
                    if checkedAppID != nil {
                        if !checkedContainerReachable {
                            Text(L("The app container could not be opened on this device."))
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else if matches.isEmpty && genericMatches.isEmpty {
                            Text(L("No table paths were found in this container. The app may have moved them in a newer version."))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        ForEach(matches, id: \.entry.relativePath) { match in
                            W6SplashMatchRow(match: match)
                        }
                        if !genericMatches.isEmpty {
                            Text(L("Generic ad SDK hints in this container:"))
                                .font(.subheadline).foregroundStyle(.secondary)
                            ForEach(genericMatches, id: \.entry.relativePath) { match in
                                W6SplashMatchRow(match: match)
                            }
                        }
                    }
                }
            } header: {
                Text(L("Check against a real container"))
            } footer: {
                Text(L("A found path is still pending verification until a maintainer confirms the app version on a real device."))
            }
        }
        .navigationTitle(L("Splash Ad Cache Paths"))
    }

    private func checkSelectedApp() {
        guard let bundleID = checkedAppID,
              let app = installedTableApps.first(where: { $0.bundleID == bundleID }),
              let container = app.containerURL else {
            matches = []
            genericMatches = []
            checkedContainerReachable = false
            return
        }
        let sentinel = W6CrossAppBrowser.sentinelState(osBuild: osBuild)
        guard sentinel == .supported else {
            matches = []
            genericMatches = []
            checkedContainerReachable = false
            return
        }
        let check = W6SplashAdPathTable.check(in: container, bundleID: bundleID)
        matches = check.matches
        genericMatches = check.genericMatches
        checkedContainerReachable = check.containerReachable
    }
}

private struct W6SplashMatchRow: View {
    let match: W6SplashAdMatch

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(match.entry.relativePath).font(.subheadline).lineLimit(2)
            HStack {
                Text(match.exists ? L("Found") : L("Not found"))
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                if match.exists {
                    Text(W6Format.bytes(match.byteCount))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(match.entry.verification.title)
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Cross-app cache statistics (feature 5)

/// Read-only per-app cache statistics. The page measures on
/// demand and shows what was actually measured; an unreachable
/// container is shown as unreachable, never as zero cache. There
/// is no clear button on this page, by design: cleanup needs
/// per-app confirmation and per-item restore, and stays a
/// follow-up.
struct W6CrossAppCacheView: View {
    let osBuild: String?

    @State private var stats: [W6AppCacheStat] = []
    @State private var measuredAt: Date?
    @State private var isMeasuring = false

    private var sentinel: VersionSentinelState {
        W6CrossAppBrowser.sentinelState(osBuild: osBuild)
    }

    private var measuredTotal: Int64 {
        stats.filter(\.reachable).reduce(0) { $0 + $1.totalBytes }
    }

    var body: some View {
        List {
            W6SentinelBanner(state: sentinel)
            Section {
                Button {
                    measure()
                } label: {
                    if isMeasuring {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(L("Measure now")).frame(maxWidth: .infinity)
                    }
                }
                .disabled(isMeasuring || sentinel != .supported)
                if let measuredAt {
                    Text(String(format: L("Measured at %@."), measuredAt.formatted(date: .abbreviated, time: .shortened)))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(String(format: L("Measured total: %@."), W6Format.bytes(measuredTotal)))
                        .font(.subheadline)
                }
                Text(L("Statistics only. This page never deletes anything."))
                    .font(.subheadline).foregroundStyle(.secondary)
            } header: {
                Text(L("Cache usage by app"))
            }
            if !stats.isEmpty {
                Section {
                    ForEach(stats, id: \.bundleID) { stat in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(stat.appName).font(.headline)
                                Spacer()
                                Text(W6Format.bytes(stat.totalBytes)).font(.headline)
                            }
                            Text(stat.bundleID).font(.caption).foregroundStyle(.secondary)
                            if stat.reachable {
                                Text(String(format: L("Caches %@ (%d files) · Temporary %@ (%d files)."),
                                            W6Format.bytes(stat.cachesBytes), stat.cachesFiles,
                                            W6Format.bytes(stat.tmpBytes), stat.tmpFiles))
                                .font(.caption).foregroundStyle(.secondary)
                                if stat.splashAdPathsChecked > 0 {
                                    Text(String(format: L("Splash-ad paths found: %d of %d (%@)."),
                                                stat.splashAdPathsFound, stat.splashAdPathsChecked,
                                                W6Format.bytes(stat.splashAdBytes)))
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                            } else {
                                Text(L("Container could not be opened — not measured."))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle(L("Cross-App Cache Usage"))
    }

    private func measure() {
        isMeasuring = true
        Task.detached {
            let apps = W6CrossAppBrowser.installedApps()
            let measured = W6CrossAppCacheStats.measureAll(apps: apps, osBuild: osBuild)
            await MainActor.run {
                stats = measured
                measuredAt = Date()
                isMeasuring = false
            }
        }
    }
}
