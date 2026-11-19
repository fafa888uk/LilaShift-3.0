// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
import SwiftUI

private enum IncomingShareOffer {
    case plist(PlistImportOffer)
    case wallpaper(SharedWallpaperOffer)
}

struct ContentView: View {
    @StateObject private var model = GestaltManager()
    @StateObject private var systemSettings = SystemSettingsModel()
    @StateObject private var customizations = CustomizationModel()
    @StateObject private var wallpaperLibrary = WallpaperLibraryModel()
    @StateObject private var launchCatalog = LaunchArtworkCatalogModel()
    /// The shared home-diagnostics cache (see HomeDiagnosticsCache):
    /// it computes the device report, backup verifications, SafePatch
    /// simulations, health score, fingerprint and live values once per
    /// input change on a background task, so the home cards read a
    /// cached value instead of recomputing on every body evaluation.
    @StateObject private var diagnostics = HomeDiagnosticsCache()
    @Environment(\.scenePhase) private var scenePhase
    @State private var importOffer: PlistImportOffer?
    @State private var showsImportConfirmation = false
    @State private var wallpaperOffer: SharedWallpaperOffer?
    @State private var showsWallpaperConfirmation = false
    @State private var showsSharedWallpapers = false
    @State private var isCheckingSharedImport = false
    @State private var pendingSharedImport = false
    @State private var capturingDirectImports = 0
    @State private var sharesFile: TemporaryExport?
    @State private var activeExport: TemporaryExport?
    @State private var showsChanges = false
    @State private var showsRestartHelp = false
    /// The export warning (Stage 6, audit R-3): shown before any
    /// full plist export, offering the de-identified export.
    @State private var showsExportWarning = false
    @State private var asksImportedRestore = false
    @State private var showsShareNotice = false
    @AppStorage("GestaltX.sharedImportNotice.v1") private var sharedImportNoticeShown = false
    @State private var selectedTab = 0
    @State private var didStart = false
    @State private var didAutoRead = false
    /// The persisted personalization settings (Tools page card
    /// visibility). Loaded on appear and reloaded whenever the
    /// Personalization Center saves, via
    /// `.personalizationSettingsDidChange`.
    @State private var personalizationSettings = PersonalizationSettings.defaults
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if targetEnvironment(simulator)
    @State private var previewCategory: CapabilityCategory?
    #endif
    @AppStorage("GestaltX.acceptedWelcome.v1") private var acceptedWelcome = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DashboardV3Home { section in
                    dashboardDestination(section)
                }
            }
                // fix2: enum-value navigation for the catalog.
                // FeatureCatalogView's page rows are
                // NavigationLink(value:) over DashboardV3Destination;
                // the destination view is resolved HERE, by the
                // NavigationStack, and never by a closure passed
                // into the catalog or into dashboardDestination
                // itself (that closure was the recursive opaque-type
                // cycle that failed the build on 33c690a).
                .navigationDestination(for: DashboardV3Destination.self) { section in
                    dashboardDestination(section)
                }
                .tabItem { Label(L("Tools"), systemImage: "square.grid.2x2") }.tag(0)
            NavigationStack { FieldsView() }
                .tabItem { Label(L("MG Control"), systemImage: "slider.horizontal.3") }.tag(1)
            NavigationStack { BackupsView(share: presentShare) }
                .tabItem { Label(L("Backups"), systemImage: "clock.arrow.circlepath") }.tag(2)
            NavigationStack { AboutView() }
                .tabItem { Label(L("About"), systemImage: "info.circle") }.tag(3)
        }
        .environmentObject(model)
        .environment(\.homeDiagnosticsCache, diagnostics)
        .tint(Color.gestaltAccent)
        #if targetEnvironment(simulator)
        .sheet(item: $previewCategory) { category in
            NavigationStack {
                ToolGroupView(group: ToolGroup(for: category), systemSettings: systemSettings, customizations: customizations, wallpaperLibrary: wallpaperLibrary, launchCatalog: launchCatalog, share: presentShare)
            }.environmentObject(model)
        }
        #endif
        .sheet(isPresented: Binding(get: { !acceptedWelcome && !isPreviewSession }, set: { _ in })) {
            WelcomeView { acceptedWelcome = true }
        }
        .sheet(item: $sharesFile, onDismiss: {
            activeExport?.cleanUp()
            activeExport = nil
        }) { ShareSheet(export: $0) }
        .sheet(isPresented: $showsChanges) { ChangeReviewView().environmentObject(model) }
        .sheet(isPresented: $showsSharedWallpapers) {
            NavigationStack {
                WallpapersView(model: customizations)
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(L("Done")) { showsSharedWallpapers = false } } }
            }
        }
        .alert(L("LilaShift"), isPresented: Binding(get: { model.message != nil && !showsChanges }, set: { if !$0 { model.message = nil } })) {
            Button(L("OK"), role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .alert(L("Restart Your Device"), isPresented: $showsRestartHelp) {
            Button(L("OK"), role: .cancel) {}
        } message: { Text(L("Some changes need a device restart to take effect. LilaShift cannot restart SpringBoard itself. Please restart your device manually: hold the side button and a volume button, then slide to power off, or use Settings → General → Shut Down.")) }
        // Export warning (Stage 6, audit R-3): the full file
        // contains this device's UDID and serial number. The
        // de-identified export removes them and cannot be restored.
        .alert(L("Export this plist?"), isPresented: $showsExportWarning) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Export De-identified")) { if let export = model.exportDocumentDeidentified() { presentShare(export) } }
            Button(L("Export Full")) { if let export = model.exportDocument() { presentShare(export) } }
        } message: { Text(L("The full file contains this device's UDID and serial number. Anyone with the file can identify this device. De-identified removes the UDID, serial number and chip ID; the de-identified file cannot be restored.")) }
        .alert(L("Import Plist"), isPresented: $showsImportConfirmation) {
            Button(L("Cancel"), role: .cancel) {
                if let offer = importOffer { model.discardImport(offer) }
                importOffer = nil
                pendingSharedImport = true
            }
            Button(L("Import")) {
                guard let offer = importOffer else { return }
                isCheckingSharedImport = true
                importOffer = nil
                pendingSharedImport = true
                Task {
                    await model.acceptImport(offer)
                    isCheckingSharedImport = false
                    await resumeSharedImports()
                }
            }
        } message: {
            Text(verbatim: (importOffer?.name ?? "") + "\n\n" + L("This plist has been verified for this device. Import it?"))
        }
        .alert(L("Import Wallpaper"), isPresented: $showsWallpaperConfirmation) {
            Button(L("Cancel"), role: .cancel) {
                if let offer = wallpaperOffer {
                    do { try offer.inbox.acknowledge(offer.entry) } catch { model.message = error.localizedDescription }
                    offer.cleanUp()
                }
                wallpaperOffer = nil
                pendingSharedImport = true
            }
            Button(L("Import")) {
                guard let offer = wallpaperOffer else { return }
                wallpaperOffer = nil
                isCheckingSharedImport = true
                Task {
                    let imported = await customizations.importWallpaper(offer.file, id: offer.id)
                    if imported {
                        do {
                            try offer.inbox.acknowledge(offer.entry)
                            showsSharedWallpapers = true
                        } catch { model.message = error.localizedDescription }
                    } else {
                        model.message = customizations.message
                        customizations.message = nil
                        offer.inbox.reject(offer.entry)
                    }
                    offer.cleanUp()
                    pendingSharedImport = true
                    isCheckingSharedImport = false
                    await resumeSharedImports()
                }
            }
        } message: {
            Text(verbatim: (wallpaperOffer?.name ?? "") + "\n\n" + L("Import this wallpaper pack? It will be added to Wallpaper Settings."))
        }
        .alert(L("Restore Imported Plist"), isPresented: $asksImportedRestore) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Restore"), role: .destructive) { Task { await model.restoreImportedPlist() } }
        } message: {
            Text(L("The current device file will be backed up before restoring. Restart the device afterward."))
        }
        .alert(L("Import Plist"), isPresented: $showsShareNotice) {
            Button(L("OK"), role: .cancel) {}
        } message: {
            Text(L("Share this device's plist to LilaShift to edit its keys and values or restore a verified backup. Export a copy from LilaShift first to keep a device-bound proof."))
        }
        .onOpenURL { url in
            if url.scheme?.lowercased() == SharedAppGroups.hostURLScheme.lowercased(), url.host == "share" {
                Task { await checkSharedImport() }
            } else if url.isFileURL {
                do {
                    // Own the bytes before deferring presentation. The same
                    // durable confirmation queue handles Files and share events.
                    let capture = SharedPlistInbox.isWallpaperName(url.lastPathComponent)
                        ? SharedWallpaperImports.capture(url, in: try SharedWallpaperImports.inbox())
                        : DirectFileImports.capture(url, in: try DirectFileImports.inbox())
                    capturingDirectImports += 1
                    pendingSharedImport = true
                    Task {
                        do {
                            _ = try await withTaskCancellationHandler {
                                try await capture.value
                            } onCancel: { capture.cancel() }
                            capturingDirectImports -= 1
                            guard !Task.isCancelled else { return }
                            await resumeSharedImports()
                        } catch {
                            capturingDirectImports -= 1
                            if !Task.isCancelled && !(error is CancellationError) { model.message = error.localizedDescription }
                        }
                    }
                } catch { model.message = error.localizedDescription }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !isPreviewSession {
                launchCatalog.refreshIfLoaded()
                Task { await checkSharedImport() }
            }
        }
        .onChange(of: canPresentSharedImport) { _, ready in
            if ready && pendingSharedImport && !isCheckingSharedImport {
                Task { await resumeSharedImports() }
            }
        }
        .onChange(of: acceptedWelcome) { _, accepted in
            if accepted && !isPreviewSession { Task { await autoRead(); showShareNoticeIfNeeded() } }
        }
        // Diagnostics cache invalidation: refresh the shared cache
        // whenever the inputs it derives from change. The snapshot
        // data changes on a read, the backup inventory on a backup
        // reload, the staged-change count on staging/clearing/apply,
        // and the working-document presence on load/unload. The cache
        // cancels an in-flight refresh and only publishes changed
        // values, so these triggers are cheap and never rebuild the
        // home spuriously.
        .onChange(of: model.snapshot?.data) { _, _ in refreshDiagnostics() }
        .onChange(of: model.backups) { _, _ in refreshDiagnostics() }
        .onChange(of: model.changeCount) { _, _ in refreshDiagnostics() }
        .onChange(of: model.working != nil) { _, _ in refreshDiagnostics() }
        .task {
            guard !didStart else { return }
            didStart = true
            await model.reloadBackups()
            refreshDiagnostics()
            #if targetEnvironment(simulator)
            let arguments = ProcessInfo.processInfo.arguments
            if let flag = arguments.firstIndex(of: "--preview-document"), arguments.indices.contains(flag + 1) {
                await model.open(URL(fileURLWithPath: arguments[flag + 1]))
            }
            if let flag = arguments.firstIndex(of: "--preview-tab"), arguments.indices.contains(flag + 1), let tab = Int(arguments[flag + 1]) {
                selectedTab = tab
            }
            if arguments.contains("--preview-review") {
                if !arguments.contains("--preview-cache-option") { model.choices["pencil"] = .enable }
                showsChanges = true
            }
            if arguments.contains("--preview-cache-option") {
                model.stageCacheOption(.enable)
            }
            if let flag = arguments.firstIndex(of: "--preview-category"), arguments.indices.contains(flag + 1) {
                previewCategory = CapabilityCategory(rawValue: arguments[flag + 1])
            }
            if arguments.contains("--preview-document") || arguments.contains("--preview-tab") { return }
            #endif
            if acceptedWelcome { await autoRead(); showShareNoticeIfNeeded() }
        }
    }

    private var isPreviewSession: Bool {
        #if targetEnvironment(simulator)
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--preview-tab") || arguments.contains("--preview-document")
        #else
        return false
        #endif
    }

    private func autoRead() async {
        guard !didAutoRead else { return }
        didAutoRead = true
        if await checkSharedImport() || model.hasDocument { return }
        await model.connect(showErrorAlert: false)
    }

    /// Refreshes the shared home-diagnostics cache for the current
    /// inputs (snapshot, working document, backup inventory). The
    /// cache computes on a background task and publishes only changed
    /// values; calling this often is safe.
    private func refreshDiagnostics() {
        diagnostics.refresh(
            snapshot: model.snapshot, working: model.working,
            backups: model.backups,
            monitorRows: model.monitorRows, monitorSentinel: model.monitorSentinel,
            readAt: model.lastReadAt ?? model.monitorReadAt)
    }

    private var canPresentSharedImport: Bool {
        acceptedWelcome && !model.isBusy && model.changeCount == 0 && importOffer == nil
            && wallpaperOffer == nil && !showsWallpaperConfirmation && !showsSharedWallpapers
            && !customizations.busy && !customizations.isPresenting && customizations.message == nil
            && !showsImportConfirmation && !showsChanges
            && sharesFile == nil && !showsRestartHelp && !asksImportedRestore
            && !showsShareNotice && model.message == nil
    }

    private func resumeSharedImports() async {
        guard acceptedWelcome, !isPreviewSession else { return }
        if await checkSharedImport() { return }
        // Initial automatic reading may have yielded to an import that was
        // subsequently cancelled or rejected. Resume it when the queue empties.
        if didAutoRead && !model.hasDocument && !model.isBusy {
            await model.connect(showErrorAlert: false)
        }
    }

    @discardableResult
    private func checkSharedImport() async -> Bool {
        guard acceptedWelcome else { return false }
        guard !isCheckingSharedImport, importOffer == nil, wallpaperOffer == nil else { return true }
        do {
            let inboxes = [try DirectFileImports.inbox(), try SharedWallpaperImports.inbox()]
                + SharedAppGroups.inboxes + SharedAppGroups.wallpaperInboxes
            let entries = try SharedImportQueue.snapshot(in: inboxes)
            guard !entries.isEmpty else {
                pendingSharedImport = capturingDirectImports > 0
                return pendingSharedImport
            }
            guard canPresentSharedImport else {
                let firstNotice = !pendingSharedImport
                pendingSharedImport = true
                if model.changeCount > 0 && firstNotice && model.message == nil {
                    model.message = L("A shared file is waiting. Save or discard your current changes, then import it.")
                }
                return true
            }
            pendingSharedImport = false
            isCheckingSharedImport = true
            defer { isCheckingSharedImport = false }
            selectedTab = 0
            sharedImportNoticeShown = true
            let selection: SharedImportQueue.Selection<IncomingShareOffer> = await SharedImportQueue.next(in: entries) { inbox, entry in
                guard canPresentSharedImport else { return .deferred(nil) }
                if inbox.kind == .wallpaper {
                    do { return .ready(.wallpaper(try await SharedWallpaperImports.prepare(entry, from: inbox))) }
                    catch {
                        if SharedPlistError.canRetry(error) { return .deferred(error.localizedDescription) }
                        inbox.reject(entry)
                        return .rejected(error.localizedDescription)
                    }
                }
                switch await model.prepareSharedPlist(entry, from: inbox) {
                case .ready(let offer): return .ready(.plist(offer))
                case .deferred(let message): return .deferred(message)
                case .rejected(let message): return .rejected(message)
                }
            }
            switch selection {
            case .ready(let offer):
                // Verification may suspend while reading the device. Recheck
                // presentation after that await; the unacknowledged inbox file
                // remains available when the new modal/busy gate clears.
                guard canPresentSharedImport else {
                    if case .wallpaper(let wallpaper) = offer { wallpaper.cleanUp() }
                    pendingSharedImport = true
                    return true
                }
                pendingSharedImport = true
                switch offer {
                case .plist(let plist): importOffer = plist; showsImportConfirmation = true
                case .wallpaper(let wallpaper): wallpaperOffer = wallpaper; showsWallpaperConfirmation = true
                }
            case .deferred(let message):
                // A UI/busy gate can resume automatically. An unavailable device
                // identity waits for the next foreground/share event, avoiding
                // an isBusy -> retry -> isBusy loop on the same retained file.
                pendingSharedImport = message == nil
                if let message { model.message = message }
            case .empty(let lastRejection):
                pendingSharedImport = false
                if let lastRejection { model.message = lastRejection }
            }
            return selection.blocksAutomaticRead
        } catch {
            model.message = error.localizedDescription
            return true
        }
    }

    private func showShareNoticeIfNeeded() {
        guard !sharedImportNoticeShown, acceptedWelcome, !isPreviewSession,
              importOffer == nil, model.message == nil, !pendingSharedImport else { return }
        sharedImportNoticeShown = true
        showsShareNotice = true
    }

    private func presentShare(_ export: TemporaryExport) {
        guard sharesFile == nil, activeExport == nil else { export.cleanUp(); return }
        activeExport = export
        sharesFile = export
    }

    // Version 3 keeps legacy operations reachable while bringing costly
    // diagnostics onto separate, task-specific navigation destinations.
    // Internal (not private) on purpose: the Phase H snapshot tests
    // render each destination through this exact builder, so the
    // snapshots cover the real navigation targets instead of a copy.
    // Presentation only — no behaviour lives here.
    @ViewBuilder
    func dashboardDestination(_ section: DashboardV3Destination) -> some View {
        switch section {
        case .unlock:
            // Stage 14: the unlock page holds the one-tap card
            // only, plus the modified-values list as its restore
            // entry. The AI, Siri AI Mode and eSIM cards each have
            // their own page now — before Stage 14 all four home
            // tiles opened this same page.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ChinaUnlockCard { showsChanges = true }
                    ModifiedValuesCard()
                }
                .padding()
            }
            .background(GlassBackground())
            .navigationTitle(section.title)
        case .aiOnly:
            // Stage 14: the AI-only card plus the AI readiness
            // checkup as its status row.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ChinaAIOnlyCard { showsChanges = true }
                    AppleIntelligenceCheckupCard { showsChanges = true }
                }
                .padding()
            }
            .background(GlassBackground())
            .navigationTitle(section.title)
        case .siriAIMode:
            // Stage 14: the Siri AI Mode card only.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ChinaSiriAIModeCard { showsChanges = true }
                }
                .padding()
            }
            .background(GlassBackground())
            .navigationTitle(section.title)
        case .esimRegion:
            // Stage 14: the eSIM & region card only.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ChinaESIMRegionCard { showsChanges = true }
                }
                .padding()
            }
            .background(GlassBackground())
            .navigationTitle(section.title)
        case .diagnostics:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    LilaIntelligenceCard()
                    SmartFaultDiagnosisCard()
                    SystemHealthScoreCard()
                    DependencyAnalyzerCard()
                    DiagnosticsExpansionCard()
                }
                .padding()
            }
            .background(GlassBackground())
            .navigationTitle(section.title)
        case .restore:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    RestoreIntelligenceCard()
                    DeviceFingerprintCard()
                    PostModificationAcceptanceCard()
                }
                .padding()
            }
            .background(GlassBackground())
            .navigationTitle(section.title)
        case .presets:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    // The unified catalog browser (Phase E): search,
                    // filter, sort, favorites, recent use, hide and
                    // custom order over the same catalog the home
                    // sections and the card below are built from.
                    // fix2: the catalog navigates by enum value
                    // (NavigationLink(value:) + .navigationDestination
                    // on the NavigationStack below) — it takes NO
                    // destination closure. Passing one that called
                    // dashboardDestination() from inside
                    // dashboardDestination() made this function's
                    // `some View` return type refer to itself and
                    // the build failed (OpaqueTypeInference, :51
                    // and :384, Tests #147 / IPA #148 on 33c690a).
                    FeatureCatalogView()
                    PresetCatalogCard()
                    PersonalizationCenterCard()
                    SafePatchCard()
                }
                .padding()
            }
            .background(GlassBackground())
            .navigationTitle(section.title)
        case .advanced:
            tools
        }
    }

    private var tools: some View {
        ScrollView {
            // Lazy so off-screen cards are not built or laid out eagerly:
            // the tab holds ~16 glass cards and an eager VStack made
            // scrolling lag. Only visible cards are rendered now.
            LazyVStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 6) {
                    Text(model.hasDocument ? model.displayedName : UIDevice.current.model)
                        .font(.subheadline.weight(.semibold))
                    Text("•")
                        .foregroundStyle(.secondary)
                    Text(readStatusText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    if model.hasDocument {
                        Button { Task { await model.connect() } } label: {
                            Label(L("Read Again"), systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.gestaltAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.gestaltAccent.opacity(0.12), in: Capsule())
                        }
                        .disabled(model.isBusy || model.changeCount > 0)
                    }
                }

                // Stage 14: the unlock-family cards are NOT inlined
                // here any more — each has its own destination page
                // (unlock / AI-only / Siri AI Mode / eSIM & region)
                // and the home tiles already link to those pages.
                // The tools page keeps only the category grid, the
                // diagnostics summary and the actions below.
                // Diagnostics summary + one row per diagnostic area.
                // The full cards live on secondary pages behind a
                // NavigationLink (see HomeDiagnosticsSection): the
                // home used to inline all eleven full cards, which
                // made it long, duplicated the same summaries, and
                // forced every card to build at once.
                DiagnosticsSummaryCard()

                HomeDiagnosticsSection(order: HomeDiagnosticsSectionID.orderedVisibleSections(personalizationSettings))

                if model.isReading {
                    GlassReadProgressCard(title: L("Reading device data…"))
                }

                VStack(alignment: .leading, spacing: GlassTokens.rowSpacing) {
                    Text(L("Feature Categories"))
                        .font(.headline)
                    GlassEffectContainer(spacing: GlassTokens.gridSpacing) {
                        LazyVGrid(columns: gridColumns, spacing: GlassTokens.gridSpacing) {
                            ForEach(visibleToolGroups) { group in
                                NavigationLink {
                                    ToolGroupView(group: group, systemSettings: systemSettings, customizations: customizations, wallpaperLibrary: wallpaperLibrary, launchCatalog: launchCatalog, share: presentShare)
                                } label: {
                                    GlassCard(cornerRadius: GlassTokens.tileRadius) {
                                        GlassCategoryTile(
                                            title: group.title,
                                            detail: group.subtitle,
                                            symbol: group.symbol,
                                            tint: group.tint
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain)
                                .disabled(model.isBusy || (group.requiresDocument && !model.hasDocument))
                            }
                        }
                    }
                    if visibleToolGroups.isEmpty {
                        Text(L("All Tools cards are hidden. Re-enable them in the Personalization Center."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    NavigationLink {
                        ToolGroupView(group: .advancedDiagnostics, systemSettings: systemSettings, customizations: customizations, wallpaperLibrary: wallpaperLibrary, launchCatalog: launchCatalog, share: presentShare)
                    } label: {
                        GlassCard(cornerRadius: GlassTokens.tileRadius) {
                            GlassCategoryTile(
                                title: ToolGroup.advancedDiagnostics.title,
                                detail: ToolGroup.advancedDiagnostics.subtitle,
                                symbol: ToolGroup.advancedDiagnostics.symbol,
                                tint: ToolGroup.advancedDiagnostics.tint
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.hasDocument || model.isBusy)
                }

                VStack(alignment: .leading, spacing: GlassTokens.rowSpacing) {
                    Text(L("Actions"))
                        .font(.headline)
                    GlassCard(cornerRadius: GlassTokens.smallRadius) {
                        VStack(spacing: 0) {
                        if model.snapshot?.source == .local && model.snapshot?.ownershipVerified == true {
                            actionButton(label: L("Restore Imported Plist"), systemImage: "arrow.uturn.backward", enabled: model.canRestoreImportedPlist) { asksImportedRestore = true }
                            Divider()
                        }
                        actionButton(label: L("Apply Changes"), systemImage: "checkmark", badge: model.changeCount > 0 ? String(model.changeCount) : nil, accent: model.changeCount > 0 && !model.isBusy ? Color.gestaltAccent : nil, enabled: model.changeCount > 0 && !model.isBusy) { showsChanges = true }
                        Divider()
                        actionButton(label: L("Discard Changes"), systemImage: "xmark", accent: model.changeCount > 0 && !model.isBusy ? Color.red : nil, enabled: model.changeCount > 0 && !model.isBusy) { model.clearStaged() }
                        Divider()
                        actionButton(label: L("Create Backup"), systemImage: "externaldrive.badge.plus", enabled: model.hasDocument && !model.isBusy) { Task { await model.backup() } }
                        Divider()
                        actionButton(label: L("Export Plist"), systemImage: "square.and.arrow.up", enabled: model.hasDocument && !model.isBusy) {
                            showsExportWarning = true
                        }
                        Divider()
                        actionButton(label: L("Restart Device"), systemImage: "power", enabled: !model.isBusy) { showsRestartHelp = true }
                        Divider()
                        NavigationLink { SessionLogView() } label: {
                            actionLabel(label: L("Log"), systemImage: "text.alignleft")
                        }
                        .buttonStyle(.plain)
                        }
                    }
                }
                if model.needsRestart {
                    Label(L("Some changes require a device restart."), systemImage: "info.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("Tools LilaShift"))
        .navigationBarTitleDisplayMode(.large)
        .onAppear { loadPersonalizationSettings() }
        .onReceive(NotificationCenter.default.publisher(for: .personalizationSettingsDidChange)) { _ in
            loadPersonalizationSettings()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Label {
                        Text(L("Author @steam8871"))
                            .font(.caption.weight(.semibold))
                    } icon: {
                        Image(systemName: "person.fill")
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.gestaltAccent, in: Capsule())
                    if model.isBusy { ProgressView() }
                }
            }
        }
    }

    /// Two-column category grid; collapses to a single column at
    /// accessibility Dynamic Type sizes so text never overlaps or clips.
    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            [GridItem(.flexible(), spacing: GlassTokens.gridSpacing)]
        } else {
            [GridItem(.adaptive(minimum: 160), spacing: GlassTokens.gridSpacing)]
        }
    }

    /// The Tools page category cards the user's settings show, in
    /// grid order. The Personalization Center owns the toggles; this
    /// page only applies them. The Advanced & Diagnostics card is
    /// not part of this setting: it is always shown below the grid.
    private var visibleToolGroups: [ToolGroup] {
        let visibleIDs = PersonalizationCenter.visibleToolCardIDs(personalizationSettings)
        return ToolGroup.categories.filter { visibleIDs.contains($0.rawValue) }
    }

    /// Loads the persisted personalization settings for the Tools
    /// page grid. A missing history id means the defaults stay.
    private func loadPersonalizationSettings() {
        guard let deviceID = RestoreIntelligence.installationDeviceID else { return }
        let store = PersonalizationSettingsStore(
            directory: RestoreIntelligence.historyDirectory, deviceID: deviceID)
        personalizationSettings = store.load().settings
    }

    private var readStatusText: String {
        guard model.hasDocument else { return L("Not read yet") }
        return model.sourceIsDevice ? L("Data read from this device") : L("Local File")
    }

    private func actionLabel(label: String, systemImage: String) -> some View {
        HStack {
            Label(label, systemImage: systemImage)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
    }

    private func actionButton(label: String, systemImage: String, badge: String? = nil, accent: Color? = nil, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(label, systemImage: systemImage)
                Spacer(minLength: 8)
                if let badge {
                    Text(badge).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent ?? Color.primary)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

}

private struct ChinaUnlockCard: View {
    let onReviewChanges: () -> Void
    @EnvironmentObject private var model: GestaltManager

    var body: some View {
        let enabledAI = model.chinaUnlockEnabledAICapabilityIDs
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: GlassTokens.heroTint) {
            VStack(alignment: GlassTokens.cardAlignment, spacing: GlassTokens.cardSpacing) {
            HStack(spacing: GlassTokens.rowSpacing) {
                GlassIconPedestal(systemImage: "lock.open.fill", tint: .gestaltAccent, size: GlassTokens.iconSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("China Unlock"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(L("Set up eSIM, region code and Apple Intelligence in one tap."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Native Apple Intelligence hardware already enables the
            // seven AI presets: one-tap stages eSIM and region code
            // only, and the AI column below reads Native.
            if model.isNativeAppleIntelligence {
                Text(L("Apple Intelligence is already enabled natively — one-tap stages eSIM and region code only."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                statusColumn(title: "eSIM", value: esimStatus ?? L("Not read yet"))
                Divider().frame(height: 36).background(Color.primary.opacity(0.12))
                statusColumn(title: L("Region Code"), value: model.previewRegionCode ?? L("Not read yet"))
                Divider().frame(height: 36).background(Color.primary.opacity(0.12))
                statusColumn(title: L("Apple Intelligence"), value: aiStatusText)
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(ChinaUnlock.aiCapabilities) { capability in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(
                                L(capability.title),
                                systemImage: enabledAI.contains(capability.id) ? "checkmark.circle.fill" : "circle"
                            )
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(enabledAI.contains(capability.id) ? Color.green : .secondary)
                            Text(L(capability.detail))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                Text(L("Included AI Features"))
                    .font(.subheadline.weight(.medium))
            }

            if model.hasDocument {
                if model.isChinaUnlockStaged && model.changeCount > 0 {
                    Button(L("Review Changes")) { onReviewChanges() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                    Button(L("Restore pre-unlock state")) { stageChanges(restoring: true) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.gestaltAccent)
                        .frame(maxWidth: .infinity)
                        .disabled(model.isBusy)
                        .opacity(model.isBusy ? 0.5 : 1)
                } else {
                    let restoring = model.isChinaUnlockedInPreview
                    Button(L(restoring ? "Restore pre-unlock state" : "One-Tap Unlock")) { stageChanges(restoring: restoring) }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(model.isBusy || model.previewESIMFlags == nil)
                        .opacity(model.isBusy || model.previewESIMFlags == nil ? 0.5 : 1)
                }

                if model.previewESIMFlags == nil {
                    Text(model.cacheLayoutError ?? L("eSIM settings are unavailable. You can still configure region and AI under Intelligence."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L(model.sourceIsDevice
                           ? "Review the changes, apply them, then restart the device."
                           : "This edits the opened file in LilaShift. Export it to save a copy; the system file is not changed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                    Task { await model.connect() }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(model.isBusy)
                .opacity(model.isBusy ? 0.5 : 1)
                Text(L("Read the device before choosing a preset."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
            .padding(GlassTokens.cardPadding)
        }
    }

    private var esimStatus: String? {
        guard model.hasDocument else { return nil }
        guard let flags = model.previewESIMFlags else { return L("Unsupported") }
        return L(flags == .enabled ? "Configured" : "Not Configured")
    }

    /// The Apple Intelligence status: Native on hardware that
    /// natively supports it (the seven presets are skipped, not
    /// staged), otherwise the enabled count out of seven.
    private var aiStatusText: String {
        guard model.hasDocument else { return L("Not read yet") }
        if model.isNativeAppleIntelligence { return L("Native") }
        return "\(model.chinaUnlockAIEnabledCount)/\(ChinaUnlock.aiCapabilities.count)"
    }

    private func statusColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func stageChanges(restoring: Bool) {
        let staged = restoring ? model.restoreChinaUnlock() : model.stageChinaUnlock()
        if staged && model.changeCount > 0 { onReviewChanges() }
    }
}

/// Standalone AI-only preset: stages only the seven Apple Intelligence
/// presets (the AI part of the one-tap unlock), without eSIM or region.
/// Not blocked by the eSIM cache layout. Mirrors the one-tap card.
private struct ChinaAIOnlyCard: View {
    let onReviewChanges: () -> Void
    @EnvironmentObject private var model: GestaltManager

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: GlassTokens.heroTint) {
            VStack(alignment: GlassTokens.cardAlignment, spacing: GlassTokens.cardSpacing) {
            HStack(spacing: GlassTokens.rowSpacing) {
                GlassIconPedestal(systemImage: "sparkles", tint: .gestaltAccent, size: GlassTokens.iconSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("China AI"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(L("Enable the seven Apple Intelligence features on a China-model iPhone."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                statusColumn(title: L("Apple Intelligence"), value: aiStatusText)
            }

            if model.hasDocument {
                if model.isNativeAppleIntelligence {
                    // Native hardware already enables all seven presets:
                    // there is nothing to stage, so no Enable button.
                    // Restore stays available when anything reads as
                    // enabled, to undo a change applied earlier.
                    Text(L("Apple Intelligence is already enabled natively on this device — nothing to stage."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if model.chinaUnlockAIEnabledCount > 0 {
                        Button(L("Restore AI")) { stageChanges(restoring: true) }
                            .buttonStyle(GlassPrimaryButtonStyle())
                            .disabled(model.isBusy)
                            .opacity(model.isBusy ? 0.5 : 1)
                    }
                } else if model.isChinaAIOnlyStaged && model.changeCount > 0 {
                    Button(L("Review Changes")) { onReviewChanges() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                    Button(L("Restore AI")) { stageChanges(restoring: true) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.gestaltAccent)
                        .frame(maxWidth: .infinity)
                        .disabled(model.isBusy)
                        .opacity(model.isBusy ? 0.5 : 1)
                } else {
                    let restoring = model.isChinaAIOnlyApplied
                    Button(L(restoring ? "Restore AI" : "Enable China AI")) { stageChanges(restoring: restoring) }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(model.isBusy)
                        .opacity(model.isBusy ? 0.5 : 1)
                }

                Text(L(model.sourceIsDevice
                       ? "Review the changes, apply them, then restart the device."
                       : "This edits the opened file in LilaShift. Export it to save a copy; the system file is not changed."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                    Task { await model.connect() }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(model.isBusy)
                .opacity(model.isBusy ? 0.5 : 1)
                Text(L("Read the device before choosing a preset."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
            .padding(GlassTokens.cardPadding)
        }
    }

    /// The Apple Intelligence status: Native on hardware that
    /// natively supports it (there is nothing to stage), otherwise
    /// the enabled count out of seven.
    private var aiStatusText: String {
        guard model.hasDocument else { return L("Not read yet") }
        if model.isNativeAppleIntelligence { return L("Native") }
        return "\(model.chinaUnlockAIEnabledCount)/\(ChinaUnlock.aiCapabilities.count)"
    }

    private func statusColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func stageChanges(restoring: Bool) {
        let staged = restoring ? model.restoreChinaAIOnly() : model.stageChinaAIOnly()
        if staged && model.changeCount > 0 { onReviewChanges() }
    }
}

/// Standalone Siri AI Mode preset: stages only SiriMode=2 — the
/// single-item switch — without eSIM, region, or the other AI keys.
/// Unlike the AI-only preset this one is allowed on hardware that
/// natively supports Apple Intelligence: an explicit single-item
/// opt-in, with the experimental warning shown on the card.
/// Not blocked by the eSIM cache layout. Mirrors the AI-only card.
private struct ChinaSiriAIModeCard: View {
    let onReviewChanges: () -> Void
    @EnvironmentObject private var model: GestaltManager

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: GlassTokens.heroTint) {
            VStack(alignment: GlassTokens.cardAlignment, spacing: GlassTokens.cardSpacing) {
            HStack(spacing: GlassTokens.rowSpacing) {
                GlassIconPedestal(systemImage: "waveform", tint: .gestaltAccent, size: GlassTokens.iconSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Siri AI Mode"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(L("Switch Siri to AI mode alone — no eSIM, region, or other AI changes."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                statusColumn(title: L("Siri AI Mode"), value: siriAIModeStatusText)
            }

            if model.hasDocument {
                if model.isNativeAppleIntelligence {
                    // Native hardware already runs Siri AI: this
                    // switch is experimental and usually unnecessary
                    // here — but it stays available as an explicit
                    // single-item opt-in, unlike the AI-only preset.
                    Text(L("Apple Intelligence is already enabled natively on this device — Siri AI Mode is experimental and usually unnecessary here."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if model.isChinaSiriAIModeStaged && model.changeCount > 0 {
                    Button(L("Review Changes")) { onReviewChanges() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                    Button(L("Restore Siri AI Mode")) { stageChanges(restoring: true) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.gestaltAccent)
                        .frame(maxWidth: .infinity)
                        .disabled(model.isBusy)
                        .opacity(model.isBusy ? 0.5 : 1)
                } else {
                    let restoring = model.isChinaSiriAIModeApplied
                    Button(L(restoring ? "Restore Siri AI Mode" : "Enable Siri AI Mode")) { stageChanges(restoring: restoring) }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(model.isBusy)
                        .opacity(model.isBusy ? 0.5 : 1)
                }

                Text(L(model.sourceIsDevice
                       ? "Review the changes, apply them, then restart the device."
                       : "This edits the opened file in LilaShift. Export it to save a copy; the system file is not changed."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                    Task { await model.connect() }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(model.isBusy)
                .opacity(model.isBusy ? 0.5 : 1)
                Text(L("Read the device before choosing a preset."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
            .padding(GlassTokens.cardPadding)
        }
    }

    /// The SiriMode key state: On when the preview already shows
    /// SiriMode set to 2, Off otherwise. This reports the key, not
    /// whether Siri itself works — on native hardware Siri AI works
    /// with the key absent.
    private var siriAIModeStatusText: String {
        guard model.hasDocument else { return L("Not read yet") }
        return model.isChinaSiriAIModeApplied ? L("On") : L("Off")
    }

    private func statusColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func stageChanges(restoring: Bool) {
        let staged = restoring ? model.restoreChinaSiriAIMode() : model.stageChinaSiriAIMode()
        if staged && model.changeCount > 0 { onReviewChanges() }
    }
}

/// Standalone eSIM+region preset: stages only the eSIM cache flags and
/// the region code US (LL) — the eSIM+region part of the one-tap unlock,
/// without the seven AI presets. Blocked by the eSIM cache layout, exactly
/// like the one-tap. Mirrors the one-tap card.
private struct ChinaESIMRegionCard: View {
    let onReviewChanges: () -> Void
    @EnvironmentObject private var model: GestaltManager

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: GlassTokens.heroTint) {
            VStack(alignment: GlassTokens.cardAlignment, spacing: GlassTokens.cardSpacing) {
            HStack(spacing: GlassTokens.rowSpacing) {
                GlassIconPedestal(systemImage: "simcard.fill", tint: .gestaltAccent, size: GlassTokens.iconSize)
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("eSIM & Region"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(L("Enable eSIM and set the region code to US (LL)."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 0) {
                statusColumn(title: "eSIM", value: esimStatus ?? L("Not read yet"))
                Divider().frame(height: 36).background(Color.primary.opacity(0.12))
                statusColumn(title: L("Region Code"), value: model.previewRegionCode ?? L("Not read yet"))
            }

            if model.hasDocument {
                if model.isChinaESIMRegionStaged && model.changeCount > 0 {
                    Button(L("Review Changes")) { onReviewChanges() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                    Button(L("Restore eSIM & Region")) { stageChanges(restoring: true) }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.gestaltAccent)
                        .frame(maxWidth: .infinity)
                        .disabled(model.isBusy)
                        .opacity(model.isBusy ? 0.5 : 1)
                } else {
                    let restoring = model.isChinaESIMRegionApplied
                    Button(L(restoring ? "Restore eSIM & Region" : "Enable eSIM & Region")) { stageChanges(restoring: restoring) }
                        .buttonStyle(GlassPrimaryButtonStyle())
                        .disabled(model.isBusy || model.previewESIMFlags == nil)
                        .opacity(model.isBusy || model.previewESIMFlags == nil ? 0.5 : 1)
                }

                if model.previewESIMFlags == nil {
                    Text(model.cacheLayoutError ?? L("eSIM settings are unavailable. You can still configure region and AI under Intelligence."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text(L(model.sourceIsDevice
                           ? "Review the changes, apply them, then restart the device."
                           : "This edits the opened file in LilaShift. Export it to save a copy; the system file is not changed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                    Task { await model.connect() }
                }
                .buttonStyle(GlassPrimaryButtonStyle())
                .disabled(model.isBusy)
                .opacity(model.isBusy ? 0.5 : 1)
                Text(L("Read the device before choosing a preset."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
            .padding(GlassTokens.cardPadding)
        }
    }

    private var esimStatus: String? {
        guard model.hasDocument else { return nil }
        guard let flags = model.previewESIMFlags else { return L("Unsupported") }
        return L(flags == .enabled ? "Configured" : "Not Configured")
    }

    private func statusColumn(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func stageChanges(restoring: Bool) {
        let staged = restoring ? model.restoreChinaESIMRegion() : model.stageChinaESIMRegion()
        if staged && model.changeCount > 0 { onReviewChanges() }
    }
}

/// Apple Intelligence readiness checkup (item 4): four factors with live
/// on-device state when the probe can answer, and a one-tap Fix button.
/// Read-only until Fix is tapped: Fix only stages through the normal
/// review flow, and slot repairs go through review + backup + readback.
/// Uses the existing Liquid Glass card and tokens; no new colors.
private struct AppleIntelligenceCheckupCard: View {
    let onReviewChanges: () -> Void
    @EnvironmentObject private var model: GestaltManager

    var body: some View {
        Group {
            if let checkup = model.aiReadinessCheckup {
                GlassCard(cornerRadius: GlassTokens.cardRadius) {
                    VStack(alignment: .leading, spacing: GlassTokens.rowSpacing) {
                        HStack(spacing: GlassTokens.rowSpacing) {
                            GlassIconPedestal(systemImage: "sparkles", tint: .gestaltAccent, size: GlassTokens.iconSize)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(L("Apple Intelligence readiness"))
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(String(format: L("Ready %d/4"), checkup.readyCount))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(checkup.factors, id: \.title) { factor in
                            factorRow(factor)
                        }
                        if !model.aiConflicts.isEmpty {
                            ForEach(model.aiConflicts) { conflict in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text(conflict.detail)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                            }
                        }
                        if !checkup.isReady {
                            Button(L("Fix")) {
                                if model.fixAIReadiness() && model.changeCount > 0 { onReviewChanges() }
                            }
                            .buttonStyle(GlassPrimaryButtonStyle())
                            .disabled(model.isBusy)
                            .opacity(model.isBusy ? 0.5 : 1)
                        }
                    }
                    .padding(GlassTokens.cardPadding)
                }
                .task { await model.refreshLiveProbe() }
            }
        }
    }

    private func factorRow(_ factor: AIReadinessFactor) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: factor.isReady ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(factor.isReady ? Color.green : Color.orange)
                .font(.subheadline)
            VStack(alignment: .leading, spacing: 2) {
                Text(factor.title)
                    .font(.subheadline.weight(.medium))
                Text(factor.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(liveStatusText(for: factor))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The live line names the probe, not the feature: the AI factor's
    /// probe reads the CacheExtra `ai` key (see `refreshLiveProbe`), so
    /// "on" means the key reads on — it is not proof Apple Intelligence
    /// is actually working on the device.
    private func liveStatusText(for factor: AIReadinessFactor) -> String {
        switch factor.isLiveActive {
        case true: return L("Live probe: on")
        case false: return L("Live probe: off — restart to apply")
        case nil: return L("Live status unknown")
        }
    }
}

/// Read-only "Modified Values" card: lists every field in the
/// live-read document whose current value differs from its recorded
/// original, showing original → current. It stages nothing and writes
/// nothing. A field appears only when both its original and its
/// current value are known and verified; a field with no recorded
/// original is never shown with a made-up original. An empty list
/// after a comparison honestly means no modification was found,
/// because a baseline existed to compare against — but "no recorded
/// originals" is a different, honestly labeled state, never a claim
/// that nothing was modified.
private struct ModifiedValuesCard: View {
    @EnvironmentObject private var model: GestaltManager

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: GlassTokens.heroTint) {
            VStack(alignment: GlassTokens.cardAlignment, spacing: GlassTokens.cardSpacing) {
                HStack(spacing: GlassTokens.rowSpacing) {
                    GlassIconPedestal(systemImage: "list.bullet", tint: .gestaltAccent, size: GlassTokens.iconSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Modified Values"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Fields whose current value differs from the recorded original."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                switch model.modifiedValuesReport {
                case .noDocument:
                    Text(L("Read the device first to see modified values."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(L(model.isBusy ? "Reading…" : "Read Device")) {
                        Task { await model.connect() }
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(model.isBusy)
                    .opacity(model.isBusy ? 0.5 : 1)
                case .noRecordedOriginals:
                    Text(L("No recorded originals. Whether anything was modified cannot be determined."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(L("Only changes with a recorded original are listed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .compared(let rows):
                    if rows.isEmpty {
                        Text(L("No modifications found"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(String(format: L("Modified %d fields"), rows.count))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(rows) { row in
                                // One line per row: name on the left, the
                                // "original → current" value right-aligned,
                                // so all values line up in a column instead
                                // of stacking under each name.
                                HStack(spacing: 8) {
                                    Text(L(row.title))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    HStack(spacing: 4) {
                                        Text(row.originalText)
                                        Text("→")
                                        Text(row.currentText)
                                    }
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: true, vertical: false)
                                }
                            }
                        }
                    }
                    Text(L("Only changes with a recorded original are listed."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(GlassTokens.cardPadding)
            // Full width: this card has no full-width button, so without
            // this the .leading-aligned parent VStack sized it to its
            // widest text and it rendered noticeably narrower than every
            // other card on the Tools tab.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Presentation groups for the Tools home screen. They regroup the
/// existing presets by task (screen, network, intelligence, charging,
/// iPad, personalization, diagnostics) without changing any preset
/// behavior: each group only filters `Capability.all` and reuses the
/// same staging, restore and review flow.
/// The seven user-visible tool groups on the Tools page (Stage 14:
/// the single user-facing classification). Internal, not private:
/// the mapping tests assert the group routing, and
/// `FeatureCatalog.destination(for:)` must agree with it — see
/// `init(for: FeatureCatalogCategory)` below.
enum ToolGroup: String, CaseIterable, Identifiable {
    case screenLock, networkEsim, intelligenceRegion, chargingButtons, ipadMultitasking, personalization, advancedDiagnostics
    var id: String { rawValue }

    /// The six preset groups shown in the two-column grid on the Tools home.
    static let categories: [ToolGroup] = [.screenLock, .networkEsim, .intelligenceRegion, .chargingButtons, .ipadMultitasking, .personalization]

    /// Maps the upstream preset category used by the simulator preview
    /// launch argument to the matching presentation group.
    /// Stage 14 fix: `.device` used to map to `.networkEsim`, but
    /// that group only holds the two call-audio capabilities
    /// (audioMix, spatialFaceTimeAudio). Six of the eleven `.device`
    /// capabilities live in `.chargingButtons`, which is the
    /// majority group; the remaining three (spatialAudioRecording,
    /// responsiveShutter, hypertensionNotifications) have no group
    /// section at all and stage from the catalog / MG Control only.
    init(for category: CapabilityCategory) {
        switch category {
        case .display: self = .screenLock
        case .device: self = .chargingButtons
        case .intelligence: self = .intelligenceRegion
        case .ipad: self = .ipadMultitasking
        case .advanced: self = .advancedDiagnostics
        }
    }

    /// The Tools-page group that shows a feature-catalog category's
    /// presets, or `nil` when the category is staged on its own
    /// destination page instead of the Tools page. This is the
    /// single mapping the catalog routing must agree with:
    /// `FeatureCatalog.destination(for:)` returns `.advanced` for
    /// every category that has a tool group here (screenLock,
    /// personalization, launchArtwork, advancedTools); the
    /// categories without one stage on their own page — except
    /// `.systemSettings`, whose presets still stage on the tools
    /// page, across three groups. The `nil` cases:
    /// smartUnlock / appleIntelligence / esimRegion have their own
    /// unlock-family pages; deviceDiagnostics and backupRestore
    /// have the diagnostics / restore pages; modifiedRecords is
    /// shown on the unlock page; systemSettings spans three groups
    /// (chargingButtons, ipadMultitasking, advancedDiagnostics for
    /// the model number), so no single group contains it.
    init?(for category: FeatureCatalogCategory) {
        switch category {
        case .screenLock: self = .screenLock
        case .personalization: self = .personalization
        case .launchArtwork: self = .personalization
        case .advancedTools: self = .advancedDiagnostics
        case .smartUnlock, .appleIntelligence, .esimRegion,
             .systemSettings, .deviceDiagnostics, .modifiedRecords,
             .backupRestore:
            return nil
        }
    }

    var title: String {
        switch self {
        case .screenLock: L("Screen & Lock Screen")
        case .networkEsim: L("Network & eSIM")
        case .intelligenceRegion: L("Apple Intelligence & Region")
        case .chargingButtons: L("Charging & Buttons")
        case .ipadMultitasking: L("iPad & Multitasking")
        case .personalization: L("Personalization")
        case .advancedDiagnostics: L("Advanced & Diagnostics")
        }
    }

    var subtitle: String {
        switch self {
        case .screenLock: L("Dynamic Island, Always-On Display")
        case .networkEsim: L("Digital SIM, Wi-Fi options")
        case .intelligenceRegion: L("Region code, translation and Clean Up")
        case .chargingButtons: L("Charge limit, tap to wake")
        case .ipadMultitasking: L("Stage Manager, Apple Pencil")
        case .personalization: L("Wallpapers, Lock Screen text, launch images")
        case .advancedDiagnostics: L("Model, sales region, run log")
        }
    }

    var description: String {
        switch self {
        case .screenLock: L("Lock screen display, screen brightness and display effects.")
        case .networkEsim: L("eSIM options, WAPI and call audio.")
        case .intelligenceRegion: L("Region code and Apple Intelligence features.")
        case .chargingButtons: L("Charging limits, buttons and alerts.")
        case .ipadMultitasking: L("iPad features on iPhone.")
        case .personalization: L("Wallpapers, Lock Screen text and app launch images.")
        case .advancedDiagnostics: L("Device identity, internal features and diagnostics.")
        }
    }

    var symbol: String {
        switch self {
        case .screenLock: "display"
        case .networkEsim: "simcard"
        case .intelligenceRegion: "sparkles"
        case .chargingButtons: "bolt.fill"
        case .ipadMultitasking: "ipad.landscape"
        case .personalization: "paintpalette"
        case .advancedDiagnostics: "wrench.and.screwdriver"
        }
    }

    var tint: Color {
        switch self {
        case .screenLock: .indigo
        case .networkEsim: .lavenderBlue
        case .intelligenceRegion: .purple
        case .chargingButtons: .green
        case .ipadMultitasking: .teal
        case .personalization: .pink
        case .advancedDiagnostics: .orange
        }
    }

    /// Personalization links work without a document; every other group
    /// needs a document read first.
    var requiresDocument: Bool { self != .personalization }

    var sections: [ToolGroupSection] {
        switch self {
        case .screenLock:
            [ToolGroupSection(title: L("Lock Screen Display"), capabilityIDs: ["aod", "aodVibrancy", "aodHighLuminance", "aodFlipbook", "aodFlipbookCount"]),
             ToolGroupSection(title: L("Display Effects"), capabilityIDs: ["dynamicIsland", "parallax", "hdrPhotoDisplay", "liquidGlass", "pwm", "displayPort"])]
        case .networkEsim:
            [ToolGroupSection(title: L("Digital SIM"), capabilityIDs: []),
             ToolGroupSection(title: L("Wi-Fi & Calls"), capabilityIDs: ["audioMix", "spatialFaceTimeAudio"])]
        case .intelligenceRegion:
            [ToolGroupSection(title: L("Region"), capabilityIDs: []),
             ToolGroupSection(title: L("Apple Intelligence"), capabilityIDs: ["ai", "siriOnDevice", "audioIntelligence", "personalTranslator", "photosCleanUp", "handwritingSynthesis", "alwaysListeningSiri"])]
        case .chargingButtons:
            [ToolGroupSection(title: L("Charging & Buttons"), capabilityIDs: ["chargeLimit", "tapToWake", "cameraControl", "actionButton", "bootChime", "collisionSOS"])]
        case .ipadMultitasking:
            [ToolGroupSection(title: L("Multitasking"), capabilityIDs: ["stageManager", "ipadApps", "pencil"])]
        case .personalization:
            []
        case .advancedDiagnostics:
            [ToolGroupSection(title: L("Internal Features"), capabilityIDs: ["internal", "storage", "srd", "internalSettings"]),
             ToolGroupSection(title: L("Diagnostics"), capabilityIDs: [])]
        }
    }

    var showsDynamicIslandPicker: Bool { self == .screenLock }
    var showsAdditionalOptions: Bool { self == .networkEsim }
    var showsWAPI: Bool { self == .networkEsim }
    var showsRegionPicker: Bool { self == .intelligenceRegion }
    var showsCustomizationLinks: Bool { self == .personalization }
    var showsLogLink: Bool { self == .advancedDiagnostics }
    var showsExperimentalNote: Bool { self == .ipadMultitasking || self == .advancedDiagnostics }
}

struct ToolGroupSection: Identifiable {
    let title: String
    let capabilityIDs: [String]
    var id: String { title }
    var capabilities: [Capability] {
        capabilityIDs.compactMap { id in Capability.all.first { $0.id == id } }
    }
}

struct ToolGroupView: View {
    fileprivate let group: ToolGroup
    let systemSettings: SystemSettingsModel
    let customizations: CustomizationModel
    let wallpaperLibrary: WallpaperLibraryModel
    let launchCatalog: LaunchArtworkCatalogModel
    /// Shares an export sheet (Stage 6 fix, Stage 9 first commit):
    /// `presentShare` is a private method of `ContentView`, out of
    /// scope inside this struct, so the closure is threaded in from
    /// the instantiation site — the same shape as
    /// `BackupsView(share: presentShare)`.
    let share: (TemporaryExport) -> Void
    @EnvironmentObject private var model: GestaltManager
    @State private var asksInternalBuild = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(group.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if model.isReading {
                    GlassReadProgressCard(title: L("Reading related settings…"))
                }

                if group == .advancedDiagnostics {
                    sectionCard(title: L("Device Information")) {
                        modelNameRow
                        LabeledContent("iOS", value: "\(UIDevice.current.systemVersion) (\(VersionSupport.label))")
                        if let document = model.working {
                            LabeledContent("CacheExtra", value: String(document.extra.count))
                        }
                        Divider()
                        salesRegionPicker
                        Divider()
                        modelNumberPicker
                    }
                }

                ForEach(group.sections) { section in
                    sectionCard(title: section.title) {
                        if section.title == L("Display Effects") && group.showsDynamicIslandPicker {
                            dynamicIslandPicker
                            if !section.capabilities.isEmpty { Divider() }
                        }
                        if section.title == L("Region") && group.showsRegionPicker {
                            regionPicker
                        }
                        if section.title == L("Digital SIM") && group.showsAdditionalOptions {
                            AdditionalOptionsRow()
                        }
                        if section.title == L("Wi-Fi & Calls") && group.showsWAPI {
                            WAPIPresetRow()
                            if !section.capabilities.isEmpty { Divider() }
                        }
                        ForEach(section.capabilities) { capability in
                            PresetRow(capability: capability, onStageInternalBuild: { asksInternalBuild = true })
                            if capability.id != section.capabilities.last?.id { Divider() }
                        }
                        if section.title == L("Diagnostics") && group.showsLogLink {
                            NavigationLink { SessionLogView() } label: {
                                HStack {
                                    Label(L("Log"), systemImage: "text.alignleft")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { BatteryTelemetryView() } label: {
                                HStack {
                                    Label(L("Battery Telemetry"), systemImage: "battery.100.bolt")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { CrashDiagnosticsView() } label: {
                                HStack {
                                    Label(L("Crash Diagnostics"), systemImage: "exclamationmark.triangle")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { DiagnosticsCentreView(share: share) } label: {
                                HStack {
                                    Label(L("Diagnostics Centre"), systemImage: "stethoscope")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { AppArchiveView(share: share) } label: {
                                HStack {
                                    Label(L("App Archive & Cache"), systemImage: "archivebox")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { SupervisionAuditView() } label: {
                                HStack {
                                    Label(L("Supervision Audit"), systemImage: "shield.checkered")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { ProxyRulesView() } label: {
                                HStack {
                                    Label(L("Proxy Rules"), systemImage: "network")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { AppGroupBrowserView() } label: {
                                HStack {
                                    Label(L("AppGroup Browser"), systemImage: "folder.badge.gearshape")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { VoiceMemoExportView() } label: {
                                HStack {
                                    Label(L("Voice Memo Export"), systemImage: "mic")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { ModelCacheProbeView() } label: {
                                HStack {
                                    Label(L("Model Cache Probe"), systemImage: "cpu")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { AssetTagView() } label: {
                                HStack {
                                    Label(L("Asset Tag"), systemImage: "tag")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { DialerSkinView() } label: {
                                HStack {
                                    Label(L("Dialer Skin"), systemImage: "phone")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { SiriHubGuardView() } label: {
                                HStack {
                                    Label(L("SiriHub Guard"), systemImage: "shield.lefthalf.filled")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { MGKeysTableView() } label: {
                                HStack {
                                    Label(L("MobileGestalt Keys"), systemImage: "key")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { MGMonitorView() } label: {
                                HStack {
                                    Label(L("MG Monitor"), systemImage: "waveform.path.ecg")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { CompatibilityMatrixView() } label: {
                                HStack {
                                    Label(L("Compatibility"), systemImage: "checklist")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                            Divider()
                            NavigationLink { PresetLabView() } label: {
                                HStack {
                                    Label(L("Preset Lab"), systemImage: "flask")
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if group.showsCustomizationLinks {
                    sectionCard(title: group.title) {
                        NavigationLink { SystemSettingsView(model: systemSettings) } label: {
                            GlassCategoryTile(
                                title: L("System Settings"),
                                detail: L("Add your own text at the bottom of the Lock Screen."),
                                symbol: "gearshape",
                                tint: .indigo
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)
                        Divider()
                        NavigationLink { WallpapersView(model: customizations) } label: {
                            GlassCategoryTile(
                                title: L("Wallpaper Settings"),
                                detail: L("Import and apply wallpaper packs."),
                                symbol: "photo.on.rectangle.angled",
                                tint: .teal
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)
                        Divider()
                        NavigationLink { WallpaperLibraryView(model: wallpaperLibrary) } label: {
                            GlassCategoryTile(
                                title: L("Wallpaper Library"),
                                detail: L("Your own images: crop, convert, save to Photos."),
                                symbol: "photo",
                                tint: .purple
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy)
                        Divider()
                        NavigationLink { LaunchArtworkApplicationsView(customizations: customizations, catalog: launchCatalog) } label: {
                            GlassCategoryTile(
                                title: L("App Launch Images"),
                                detail: L("Change the image shown when an app opens."),
                                symbol: "app.badge",
                                tint: .pink
                            )
                        }
                        .buttonStyle(.plain)
                        Divider()
                        NavigationLink { AppSoundApplicationsView(customizations: customizations) } label: {
                            GlassCategoryTile(
                                title: L("App Audio Library"),
                                detail: L("Replace an app's notification sounds with your own audio."),
                                symbol: "bell.badge",
                                tint: .orange
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(model.isBusy || AppSoundAvailability.unavailableReason(forBuild: SystemDeviceIdentitySource().osBuild) != nil)
                        // Sound replacement goes through the worse_query lease,
                        // so it is blocked wherever the version sentinel says
                        // the mechanism is blocked. The tile stays visible
                        // with the reason instead of opening an empty list.
                        if let audioGuidance = AppSoundAvailability.unavailableReason(forBuild: SystemDeviceIdentitySource().osBuild) {
                            Text(audioGuidance)
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                if group.showsExperimentalNote {
                    Text(L("Experimental settings. Back up before applying."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.large)
        .disabled(model.isBusy)
        .safeAreaInset(edge: .bottom) {
            if model.changeCount > 0 {
                GlassBottomBar {
                    NavigationLink { ChangeReviewView(isSheet: false) } label: {
                        Text(String(format: L("View %lld pending changes"), model.changeCount))
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                }
            }
        }
        .alert(L("Enable Internal Build?"), isPresented: $asksInternalBuild) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Enable"), role: .destructive) {
                guard !model.isBusy, model.hasDocument else { return }
                model.choices["storage"] = .enable
            }
        } message: {
            Text(L("This stages the system-wide InternalBuild flag. It can affect system services beyond the storage screen. You can review the change before applying it."))
        }
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        GlassCard(cornerRadius: GlassTokens.smallRadius) {
            VStack(alignment: .leading, spacing: GlassTokens.rowSpacing) {
                Text(title).font(.headline)
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var dynamicIslandPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("Dynamic Island Layout"), selection: $model.subtype) {
                Text(L("Keep Current")).tag(0)
                Text("iPhone 14 Pro · 2556").tag(2556)
                Text("iPhone 14 Pro Max · 2796").tag(2796)
                Text("iPhone Air · 2736").tag(2736)
                Text("iPhone 16 Pro · 2622").tag(2622)
                Text("iPhone 16 Pro Max · 2868").tag(2868)
            }
            .pickerStyle(.menu)
            .onChange(of: model.subtype) { _, value in if value != 0 { model.choices["dynamicIsland"] = .keep } }
            Text(L("Choose the Dynamic Island layout size.")).font(.caption).foregroundStyle(.secondary)
            if let error = model.artworkEditingError {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(model.artworkEditingError != nil)
    }

    private var modelNameRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(L("Change Model Name"), isOn: $model.changesName)
            Text(L("Change the device model name shown by the system.")).font(.caption).foregroundStyle(.secondary)
            if model.changesName {
                TextField(L("Model Name"), text: $model.modelName).autocorrectionDisabled()
                Text(L("A device restart may be required.")).font(.caption).foregroundStyle(.secondary)
            }
            if let error = model.artworkEditingError {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
        }
        .disabled(model.artworkEditingError != nil)
    }

    private var regionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Set the device region code for region-locked features.")).font(.caption).foregroundStyle(.secondary)
            Picker(L("Region Code"), selection: $model.regionCodeID) {
                ForEach(RegionPreset.all) { Text(L($0.title)).tag($0.id) }
            }
            .pickerStyle(.menu)
            if model.regionCodeID != "keep" {
                Text(L("A device restart may be required.")).font(.caption).foregroundStyle(.secondary)
            }
            Text(L("Usually, changing the region code is enough. There is no need to change Sales Region."))
                .font(.caption).foregroundStyle(.secondary)
            Text(L("* If you previously changed Sales Region, restore your device's original sales region and apply it first."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var salesRegionPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Set the sales-region suffix of the device model.")).font(.caption).foregroundStyle(.secondary)
            Picker(L("Sales Region"), selection: $model.regionID) {
                ForEach(RegionPreset.all) { Text(L($0.title)).tag($0.id) }
            }
            .pickerStyle(.menu)
            if model.regionID != "keep" {
                Text(L("Restart the device after changing the region.")).font(.caption).foregroundStyle(.secondary)
            }
            Text(L("Changing the sales-region suffix may cause verification tools to report a mismatch with factory information."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var modelNumberPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Change the reported device model number.")).font(.caption).foregroundStyle(.secondary)
            Picker(L("Model Number"), selection: $model.modelID) {
                ForEach(ModelPreset.all) { Text(L($0.title)).tag($0.id) }
            }
            .pickerStyle(.menu)
            HStack(alignment: .firstTextBaseline) {
                if model.modelID != "keep" {
                    Text(L("A device restart may be required after changing the model number.")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button(L("Revert")) { Task { await model.restoreCapability(ModelPreset.restoration) } }
                    .font(.caption).buttonStyle(.borderless)
                    .disabled(!model.canRestore(ModelPreset.restoration))
            }
            Text(L("Listed values apply to iPhone Air, iPhone 18 Pro and iPhone 18 Pro Max only. Choosing a model number that does not match your hardware can make verification tools report a mismatch."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PresetRow: View {
    let capability: Capability
    let onStageInternalBuild: () -> Void
    @EnvironmentObject private var model: GestaltManager

    private var choice: PresetChoice { model.choices[capability.id] ?? .keep }
    private var canEnable: Bool { capability.availableChoices.contains(.enable) }

    private enum Status { case pending, configured, unconfigured, keep, notRead }
    private var status: Status {
        if !model.hasDocument { return .notRead }
        if choice != .keep { return .pending }
        if !canEnable { return .keep }
        return capability.isEnabled(in: model.preview) ? .configured : .unconfigured
    }

    var body: some View {
        GlassFeatureRow(
            symbol: symbol(for: capability),
            tint: tint(for: capability),
            title: L(capability.title),
            detail: L(capability.detail),
            caution: capability.caution,
            effectHint: choice != .keep ? L(capability.effectHint) : nil,
            statusText: statusText,
            statusTint: statusTint,
            actionTitle: status == .unconfigured ? L("Enable") : nil,
            actionEnabled: model.hasDocument,
            onAction: { stage(.enable, for: capability) },
            menu: optionsMenu
        )
    }

    private var statusText: String {
        switch status {
        case .pending: L("Pending")
        case .configured: L("Configured")
        case .unconfigured: L("Not Configured")
        case .keep: L("Keep Current")
        case .notRead: L("Not read yet")
        }
    }

    private var statusTint: Color {
        switch status {
        case .pending: .orange
        case .configured: .green
        case .unconfigured, .keep, .notRead: .secondary
        }
    }

    private var optionsMenu: some View {
        Menu {
            Text(L(capability.effectHint))
            ForEach(capability.availableChoices) { option in
                Button(L(optionTitle(option, for: capability))) { stage(option, for: capability) }
            }
            if model.canRestore(capability) {
                Button(L("Revert")) { Task { await model.restoreCapability(capability) } }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L("More options"))
        }
    }

    private func tint(for capability: Capability) -> Color {
        switch capability.category {
        case .display: .lavenderBlue
        case .device: .teal
        case .ipad: .purple
        case .intelligence: .indigo
        case .advanced: .orange
        }
    }

    private func stage(_ choice: PresetChoice, for capability: Capability) {
        if capability.requiresEnableConfirmation, choice == .enable,
           model.choices[capability.id] != .enable {
            onStageInternalBuild()
            return
        }
        model.choices[capability.id] = choice
        if capability.id == "dynamicIsland" && choice != .keep { model.subtype = 0 }
    }

    private func optionTitle(_ choice: PresetChoice, for capability: Capability) -> String {
        if capability.id == "siriOnDevice" && choice == .disable { return "Restore Original" }
        return choice.title
    }

    private func symbol(for capability: Capability) -> String {
        switch capability.id {
        case "dynamicIsland": "display"
        case "aod", "aodVibrancy", "aodHighLuminance": "moon.fill"
        case "aodFlipbook", "aodFlipbookCount": "rectangle.stack.fill"
        case "parallax": "move.3d"
        case "hdrPhotoDisplay": "sun.max.fill"
        case "pwm": "lightbulb"
        case "displayPort": "cable.connector"
        case "liquidGlass": "drop.fill"
        case "bootChime": "speaker.wave.2.fill"
        case "chargeLimit": "battery.100.bolt"
        case "tapToWake": "hand.tap.fill"
        case "cameraControl": "camera.fill"
        case "actionButton": "button.programmable"
        case "collisionSOS": "sos"
        case "audioMix": "waveform"
        case "spatialFaceTimeAudio": "person.wave.2.fill"
        case "pencil": "pencil"
        case "stageManager": "rectangle.3.offgrid"
        case "ipadApps": "apps.ipad"
        case "ai", "siriOnDevice": "sparkles"
        case "audioIntelligence": "waveform"
        case "personalTranslator": "translate"
        case "photosCleanUp": "wand.and.stars"
        case "handwritingSynthesis": "pencil.and.scribble"
        case "alwaysListeningSiri": "ear.fill"
        case "internal": "wrench.and.screwdriver"
        case "storage": "internaldrive.fill"
        case "srd": "shield.fill"
        case "internalSettings": "gearshape.fill"
        default: "gearshape"
        }
    }
}

struct AdditionalOptionsRow: View {
    @EnvironmentObject private var model: GestaltManager

    private var support: Result<CachedOptionFlags, Error> {
        Result {
            guard let document = model.preview else { throw GestaltFailure("Load a document first.") }
            return try DeviceCacheOptions.flags(in: document)
        }
    }

    var body: some View {
        switch support {
        case .success:
            VStack(alignment: .leading, spacing: 8) {
                Picker(L("Additional Options"), selection: Binding(
                    get: { model.cacheOptionChoice },
                    set: { _ = model.stageCacheOption($0) }
                )) {
                    ForEach(CacheOptionChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("cache-option-choice")
                Text(L("Enable or disable the eSIM-related system options."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L("Some changes require a device restart."))
                    .font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Spacer(minLength: 8)
                    Button(L("Revert")) { Task { await model.restoreCacheOption() } }
                        .font(.caption).buttonStyle(.borderless)
                        .disabled(!model.canRestoreCacheOption)
                        .accessibilityIdentifier("cache-option-revert")
                }
            }
        case .failure(let error):
            VStack(alignment: .leading, spacing: 4) {
                LabeledContent(L("Additional Options")) { Text(L("Unsupported")).foregroundStyle(.secondary) }
                Text(error.localizedDescription).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct WAPIPresetRow: View {
    @EnvironmentObject private var model: GestaltManager
    private var supported: Bool {
        guard let document = model.preview else { return false }
        return (try? DeviceCacheOptions.wapi(in: document)) != nil
    }
    var body: some View {
        if supported {
            VStack(alignment: .leading, spacing: 8) {
                Picker("WAPI", selection: Binding(get: { model.wapiChoice }, set: { model.stageWAPI($0) })) {
                    ForEach(WAPIChoice.allCases) { choice in Text(choice.title).tag(choice) }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("wapi-choice")
                Text(L("Use the WAPI wireless security standard."))
                    .font(.caption).foregroundStyle(.secondary)
                Text(L("Disabling may show Wi-Fi and change some network options. Restart to apply."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        } else {
            LabeledContent("WAPI") { Text(L("Unsupported")).foregroundStyle(.secondary) }
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 44
    var body: some View {
        Image("AppMark").resizable().frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)).accessibilityHidden(true)
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let export: TemporaryExport
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [export.url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in export.cleanUp() }
        return controller
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
