// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct DiskIconCacheMatch: Sendable, Equatable {
    let file: String
    let root: String
    let bytes: Int
    let inode: UInt64
    let filenameMatch: Bool
    let contentMatch: Bool
    /// SHA-256 of the probed prefix (at most the first 128 KB). Nil when
    /// the prefix could not be read even though the name matched.
    let prefixSHA256: String?
}

/// One directory entry's diagnostics, recorded for every entry even when
/// its content read was skipped or failed. `stage` names the failure
/// ("readdir", "iteratorOpen", "fstatat", "childOpen", "prefixOpen",
/// "prefixFstat", "prefixRead", "nonRegular"); `errno` is the errno for
/// that stage. `target` is a symlink's readlink target, never followed.
struct DiskIconCacheEntryDetail: Sendable, Equatable {
    let name: String
    let direntType: Int
    let mode: String?
    let size: Int?
    let uid: Int?
    let gid: Int?
    let inode: UInt64?
    let fileType: String?
    let stage: String?
    let errno: Int?
    let target: String?
    let statErrno: Int?
    let prefixSkipped: Bool
}

struct DiskIconCacheDirectoryStat: Sendable, Equatable {
    let mode: String
    let uid: Int
    let gid: Int
    let inode: UInt64
}

struct DiskIconCacheEvidence: Sendable {
    let bundleID: String
    let openedDirectories: Int
    let matches: Int
    /// Total unreadable entries, merged across roots. Its meaning is
    /// unchanged: only actual read failures count (non-regular entries
    /// do not). See `unreadableStages` for the per-stage breakdown.
    let unreadable: Int
    let report: String
    let matchesDetail: [DiskIconCacheMatch]
    let entriesDetail: [DiskIconCacheEntryDetail]
    let directoryStats: [DiskIconCacheDirectoryStat]
    /// Counts of entries that produced no content, by diagnosis stage,
    /// merged across roots. "nonRegular" entries are skipped by type,
    /// not failures, but are included so the breakdown accounts for
    /// every entry that produced no content.
    let unreadableStages: [String: Int]

    /// Counts of unreadable entries by diagnosis stage.
    var unreadableStageCounts: [String: Int] { unreadableStages }

    /// One-line breakdown, e.g. "fstatat ×1 · prefixOpen ×2".
    var unreadableSummary: String {
        guard !unreadableStages.isEmpty else { return appearanceDiagnosticText("No unreadable entries") }
        return unreadableStages.keys.sorted().map { "\($0) ×\(unreadableStages[$0] ?? 0)" }.joined(separator: " · ")
    }

    static func inspect(_ bundleID: String) -> Self {
        Self(fields: GXIconCacheProbe.inspect(bundleIdentifier: bundleID), bundleID: bundleID)
    }

    static func inspectDirectory(_ descriptor: Int32, bundleID: String) -> Self {
        let field = GXIconCacheProbe.inspectDirectory(descriptor, bundleIdentifier: bundleID)
        guard !field.isEmpty else { return Self(fields: [], bundleID: bundleID) }
        var opened = field
        opened["open"] = true
        return Self(fields: [opened], bundleID: bundleID)
    }

    private init(fields: [[String: Any]], bundleID: String) {
        self.bundleID = bundleID
        openedDirectories = fields.filter { $0["open"] as? Bool == true }.count
        matches = fields.reduce(0) { count, field in
            count + ((field["matches"] as? [[String: Any]])?.count ?? 0)
        }
        unreadable = fields.reduce(0) { count, field in
            count + ((field["unreadable"] as? NSNumber)?.intValue ?? 0)
        }
        matchesDetail = fields.flatMap { field in
            ((field["matches"] as? [[String: Any]]) ?? []).compactMap { match -> DiskIconCacheMatch? in
                guard let file = match["file"] as? String else { return nil }
                return DiskIconCacheMatch(
                    file: file,
                    root: match["root"] as? String ?? "",
                    bytes: (match["bytes"] as? NSNumber)?.intValue ?? 0,
                    inode: (match["inode"] as? NSNumber)?.uint64Value ?? 0,
                    filenameMatch: match["filenameMatch"] as? Bool ?? false,
                    contentMatch: match["contentMatch"] as? Bool ?? false,
                    prefixSHA256: match["prefixSHA256"] as? String)
            }
        }
        entriesDetail = fields.flatMap { field in
            ((field["entriesDetail"] as? [[String: Any]]) ?? []).compactMap { entry -> DiskIconCacheEntryDetail? in
                guard let name = entry["name"] as? String else { return nil }
                return DiskIconCacheEntryDetail(
                    name: name,
                    direntType: (entry["direntType"] as? NSNumber)?.intValue ?? 0,
                    mode: entry["mode"] as? String,
                    size: (entry["size"] as? NSNumber)?.intValue,
                    uid: (entry["uid"] as? NSNumber)?.intValue,
                    gid: (entry["gid"] as? NSNumber)?.intValue,
                    inode: (entry["inode"] as? NSNumber)?.uint64Value,
                    fileType: entry["fileType"] as? String,
                    stage: entry["stage"] as? String,
                    errno: (entry["errno"] as? NSNumber)?.intValue,
                    target: entry["target"] as? String,
                    statErrno: (entry["statErrno"] as? NSNumber)?.intValue,
                    prefixSkipped: entry["prefixSkipped"] as? Bool ?? false)
            }
        }
        directoryStats = fields.compactMap { field in
            guard let stat = field["directoryStat"] as? [String: Any],
                  let mode = stat["mode"] as? String else { return nil }
            return DiskIconCacheDirectoryStat(
                mode: mode,
                uid: (stat["uid"] as? NSNumber)?.intValue ?? 0,
                gid: (stat["gid"] as? NSNumber)?.intValue ?? 0,
                inode: (stat["inode"] as? NSNumber)?.uint64Value ?? 0)
        }
        var stages: [String: Int] = [:]
        for field in fields {
            for (stage, count) in field["unreadableStages"] as? [String: Any] ?? [:] {
                stages[stage, default: 0] += (count as? NSNumber)?.intValue ?? 0
            }
        }
        unreadableStages = stages
        let serialized = try? JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys])
        report = serialized.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
}

func appearanceDiagnosticText(_ key: String) -> String {
    NSLocalizedString(key, tableName: "AppAppearanceDiagnostics", comment: "")
}

/// This result describes one fresh lookup. Missing fields stay absent.
private struct AppearanceNameEvidence: Sendable {
    let displayName: String?
    let bundleName: String?
    let size: Int?
    let sha256: String?

    static func inspect(_ bundleID: String) -> Self {
        #if targetEnvironment(simulator)
        let fields: [String: Any] = [:]
        #else
        let fields = GXLaunchServicesDatabase.inspectDisplayName(for: bundleID)
        #endif
        return Self(displayName: fields["displayName"] as? String, bundleName: fields["bundleName"] as? String,
                    size: (fields["size"] as? NSNumber)?.intValue, sha256: fields["sha256"] as? String)
    }
}

struct AppAppearanceApplicationsView: View {
    @State private var apps: [LaunchArtworkApp] = []
    @State private var isReading = false
    @State private var query = ""

    private var visibleApps: [LaunchArtworkApp] {
        apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            if isReading {
                ProgressView(L("Reading…"))
            } else if visibleApps.isEmpty {
                ContentUnavailableView(appearanceDiagnosticText("No applications returned"), systemImage: "app.dashed")
            }
            ForEach(visibleApps) { app in
                NavigationLink {
                    AppAppearanceInspectionView(app: app)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name)
                        Text(app.id).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(appearanceDiagnosticText("App Icon & Name"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query)
        .task { if apps.isEmpty { await readApps() } }
        .toolbar {
            Button {
                Task { await readApps() }
            } label: {
                Label(L("Read Again"), systemImage: "arrow.clockwise")
            }
            .disabled(isReading)
        }
    }

    private func readApps() async {
        guard !isReading else { return }
        isReading = true
        defer { isReading = false }
        let inventory = await Task.detached(priority: .userInitiated) {
            LaunchArtworkCatalogStore.Backend.device.inventory(true)
        }.value
        guard !Task.isCancelled else { return }
        apps = inventory.candidates.filter(\.installed).map(\.app).sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }
}

private struct AppAppearanceInspectionView: View {
    let app: LaunchArtworkApp
    @State private var names: AppearanceNameEvidence?
    @State private var iconPNG: Data?
    @State private var diskIconCache: DiskIconCacheEvidence?
    @State private var isReading = false
    // Gated write path state. The plan is a candidate-only state machine:
    // it never claims the change is effective before the restart check.
    @State private var writePlan = IconCacheWritePlan()
    @State private var writeMessage: String?
    @State private var newDisplayName = ""
    @State private var writeBusy = false

    private let device = SystemDeviceIdentitySource()

    var body: some View {
        List {
            Section {
                LabeledContent(appearanceDiagnosticText("Installed application"), value: app.name)
                Text(app.id).font(.caption.monospaced()).textSelection(.enabled)
                LabeledContent("ProductType", value: device.productType ?? L("Unknown"))
                LabeledContent("iOS", value: device.osVersion ?? L("Unknown"))
                LabeledContent("Build", value: device.osBuild ?? L("Unknown"))
                Button {
                    Task { await inspect() }
                } label: {
                    Label(L("Read Again"), systemImage: "arrow.clockwise")
                }
                .disabled(isReading)
                if isReading { ProgressView(L("Reading…")) }
            }
            Section {
                if let names {
                    LabeledContent(appearanceDiagnosticText("LaunchServices display name"), value: names.displayName ?? L("Unknown"))
                    LabeledContent(appearanceDiagnosticText("LaunchServices bundle name"), value: names.bundleName ?? L("Unknown"))
                    LabeledContent(appearanceDiagnosticText("Cache bytes"), value: names.size.map(String.init) ?? L("Unknown"))
                    if let sha256 = names.sha256 {
                        LabeledContent("SHA-256") { Text(sha256).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                    LabeledContent(appearanceDiagnosticText("System icon lookup")) {
                        if let iconPNG, let icon = UIImage(data: iconPNG) {
                            Image(uiImage: icon).resizable().scaledToFit().frame(width: 52, height: 52)
                                .accessibilityLabel(appearanceDiagnosticText("System icon lookup"))
                        } else {
                            Text(L("Unknown"))
                        }
                    }
                    if let diskIconCache {
                        LabeledContent(appearanceDiagnosticText("Readable icon cache directories"),
                                       value: String(diskIconCache.openedDirectories))
                        LabeledContent(appearanceDiagnosticText("Candidate records matching Bundle ID"),
                                       value: String(diskIconCache.matches))
                        LabeledContent(appearanceDiagnosticText("Unreadable cache entries"),
                                       value: diskIconCache.unreadableSummary)
                        Text(appearanceDiagnosticText("Candidate records require confirmation on the Home Screen."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ShareLink(item: evidenceText(names))
                }
            } header: {
                Text(appearanceDiagnosticText("Read-only cache evidence"))
            } footer: {
                Text(appearanceDiagnosticText("The system icon lookup is separate from the on-disk icon cache. Cache writes are unverified."))
            }
            if app.id == IconCacheWriteGate.firstWriteTargetBundleID {
                Section {
                    LabeledContent(appearanceDiagnosticText("Icon-cache write (experimental)"), value: writeStatusText)
                    TextField(appearanceDiagnosticText("New display name (experimental)"), text: $newDisplayName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(writeBusy)
                    Button(appearanceDiagnosticText("Write (experimental)")) {
                        Task { await runExperimentalWrite() }
                    }
                    .disabled(!writeGateReady || writeBusy
                              || newDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || writePlan.state == .awaitingRestartVerification
                              || writePlan.state == .verifiedAfterRestart
                              || writePlan.state == .failed)
                    Button(appearanceDiagnosticText("Restore from backup"), role: .destructive) {
                        Task { await runRestore() }
                    }
                    .disabled(writeBusy || ![.backedUp, .written, .readBackVerified,
                                            .awaitingRestartVerification, .failed].contains(writePlan.state))
                    if let writeMessage {
                        Text(writeMessage).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(appearanceDiagnosticText("Icon-cache write (experimental)"))
                } footer: {
                    Text(appearanceDiagnosticText("Candidate records require confirmation on the Home Screen."))
                }
            }
            AppAppearancePreviewView(app: app)
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            writePlan = (try? IconCacheWritePlan.load(from: IconCacheWritePlan.backupDirectory(for: app.id)))
                ?? IconCacheWritePlan()
            await inspect()
        }
    }

    private func inspect() async {
        guard !isReading else { return }
        isReading = true
        names = nil
        iconPNG = nil
        diskIconCache = nil
        defer { isReading = false }
        let bundleID = app.id
        let result = await Task.detached(priority: .userInitiated) {
            (AppearanceNameEvidence.inspect(bundleID), DiskIconCacheEvidence.inspect(bundleID))
        }.value
        guard !Task.isCancelled else { return }
        iconPNG = GXCustomizationAccess.homeScreenIcon(for: bundleID)
        diskIconCache = result.1
        names = result.0
        checkRestartVerification()
    }

    /// After a fresh probe, check whether a pending write has become
    /// verified-effective: only a real reboot plus a fresh probe that
    /// still shows the mutation qualifies.
    private func checkRestartVerification() {
        guard writePlan.state == .awaitingRestartVerification,
              let writtenAt = writePlan.writtenAt,
              let evidence = diskIconCache else { return }
        let bootChanged = RestartEvidence.compare(before: writePlan.preWriteBootSession,
                                                  after: BootSession.current(),
                                                  referenceDate: writtenAt, readAt: Date(),
                                                  manual: false) == .verifiedBootChange
        if writePlan.verifyAfterRestart(newEvidence: evidence, bootChanged: bootChanged) {
            writeMessage = appearanceDiagnosticText("Verified-effective after restart")
            try? writePlan.save(to: IconCacheWritePlan.backupDirectory(for: app.id))
        }
    }

    private var writeStatusText: String {
        switch writePlan.state {
        case .idle:
            if let evidence = diskIconCache {
                switch IconCacheWriteGate.evaluate(evidence, bundleID: app.id, probedCacheSHA: names?.sha256) {
                case .ready:
                    return appearanceDiagnosticText("Ready — candidate record only")
                case .blocked(let reason):
                    return reason
                }
            }
            return L("Unknown")
        case .backedUp:
            return appearanceDiagnosticText("Backup saved")
        case .written:
            return appearanceDiagnosticText("Written — read-back pending")
        case .readBackVerified:
            return appearanceDiagnosticText("Read-back verified")
        case .awaitingRestartVerification:
            return appearanceDiagnosticText("Awaiting restart verification")
        case .verifiedAfterRestart:
            return appearanceDiagnosticText("Verified-effective after restart")
        case .restored:
            return appearanceDiagnosticText("Restored from backup")
        case .failed:
            let reason = writePlan.failureReason ?? ""
            return reason.isEmpty
                ? appearanceDiagnosticText("Write failed")
                : appearanceDiagnosticText("Write failed") + ": " + reason
        }
    }

    private var writeGateReady: Bool {
        guard let evidence = diskIconCache,
              case .ready(let record) = IconCacheWriteGate.evaluate(evidence, bundleID: app.id,
                                                                    probedCacheSHA: names?.sha256),
              !record.cacheRoot.isEmpty else { return false }
        return true
    }

    /// Runs backup -> write -> read-back, then stops in "awaiting restart
    /// verification". It does not auto-restore and does not claim the
    /// change is effective. The cache file is touched only while holding
    /// the icon-cache group lease, following the CustomizationStore
    /// acquire/release pattern.
    private func runExperimentalWrite() async {
        guard !writeBusy, let evidence = diskIconCache, let names else { return }
        guard case .ready(let record) = IconCacheWriteGate.evaluate(evidence, bundleID: app.id,
                                                                    probedCacheSHA: names.sha256) else {
            writeMessage = writeStatusText
            return
        }
        guard let currentName = names.displayName else {
            writeMessage = appearanceDiagnosticText("The current display name is unknown.")
            return
        }
        writeBusy = true
        defer { writeBusy = false }
        let startingPlan = writePlan
        let newName = newDisplayName
        let backupDirectory = IconCacheWritePlan.backupDirectory(for: app.id)
        let outcome = await Task.detached(priority: .userInitiated) { () -> (IconCacheWritePlan, String?) in
            var plan = startingPlan
            let cacheRoot = URL(fileURLWithPath: record.cacheRoot, isDirectory: true)
            #if os(iOS) && !targetEnvironment(simulator)
            var lease: Int64 = -1
            if record.cacheRoot.hasPrefix(IconCacheWriteGate.iconCacheGroupPath) {
                lease = GXCustomizationAccess.acquirePath(IconCacheWriteGate.iconCacheGroupPath)
                guard lease >= 0 else { return (plan, IconCacheWriteError.fileUnavailable.localizedDescription) }
            }
            defer { if lease >= 0 { worse_query_release(lease) } }
            #endif
            do {
                if plan.state == .idle || plan.state == .restored {
                    try plan.backup(cacheRoot: cacheRoot, backupDirectory: backupDirectory, record: record)
                }
                if plan.state == .backedUp {
                    try plan.write(cacheRoot: cacheRoot, backupDirectory: backupDirectory, evidence: evidence,
                                   currentName: currentName, newName: newName,
                                   bootBefore: BootSession.current())
                }
                if plan.state == .written {
                    try plan.readBack(cacheRoot: cacheRoot, backupDirectory: backupDirectory)
                }
                if plan.state == .readBackVerified {
                    try plan.beginRestartWait()
                }
                return (plan, nil)
            } catch {
                return (plan, error.localizedDescription)
            }
        }.value
        guard !Task.isCancelled else { return }
        writePlan = outcome.0
        try? writePlan.save(to: backupDirectory)
        if let message = outcome.1 {
            writeMessage = message
        } else if writePlan.state == .awaitingRestartVerification {
            writeMessage = appearanceDiagnosticText("Awaiting restart verification")
        }
    }

    /// Restores the backup bytes. Enabled only while a write is pending
    /// or awaiting restart verification (or failed and holding a backup).
    private func runRestore() async {
        guard !writeBusy, let record = writePlan.record, !record.cacheRoot.isEmpty else { return }
        writeBusy = true
        defer { writeBusy = false }
        let startingPlan = writePlan
        let backupDirectory = IconCacheWritePlan.backupDirectory(for: app.id)
        let outcome = await Task.detached(priority: .userInitiated) { () -> (IconCacheWritePlan, String?) in
            var plan = startingPlan
            let cacheRoot = URL(fileURLWithPath: record.cacheRoot, isDirectory: true)
            #if os(iOS) && !targetEnvironment(simulator)
            var lease: Int64 = -1
            if record.cacheRoot.hasPrefix(IconCacheWriteGate.iconCacheGroupPath) {
                lease = GXCustomizationAccess.acquirePath(IconCacheWriteGate.iconCacheGroupPath)
                guard lease >= 0 else { return (plan, IconCacheWriteError.fileUnavailable.localizedDescription) }
            }
            defer { if lease >= 0 { worse_query_release(lease) } }
            #endif
            do {
                try plan.restore(cacheRoot: cacheRoot, backupDirectory: backupDirectory)
                return (plan, nil)
            } catch {
                return (plan, error.localizedDescription)
            }
        }.value
        guard !Task.isCancelled else { return }
        writePlan = outcome.0
        try? writePlan.save(to: backupDirectory)
        if let message = outcome.1 {
            writeMessage = message
        } else if writePlan.state == .restored {
            writeMessage = appearanceDiagnosticText("Restored from backup")
        }
    }

    private func evidenceText(_ names: AppearanceNameEvidence) -> String {
        let unknown = L("Unknown")
        return [
            "Bundle ID = \(app.id)",
            "ProductType = \(device.productType ?? unknown)",
            "iOS = \(device.osVersion ?? unknown)",
            "Build = \(device.osBuild ?? unknown)",
            "LaunchServices CFBundleDisplayName candidate = \(names.displayName ?? unknown)",
            "LaunchServices bundle name = \(names.bundleName ?? unknown)",
            "LaunchServices cache bytes = \(names.size.map(String.init) ?? unknown)",
            "LaunchServices cache SHA-256 = \(names.sha256 ?? unknown)",
            "System icon PNG SHA-256 = \(iconPNG.map(GestaltFileStore.sha256Hex(of:)) ?? unknown)",
            "Disk icon cache candidates = \(diskIconCache?.report ?? unknown)"
        ].joined(separator: "\n")
    }
}
