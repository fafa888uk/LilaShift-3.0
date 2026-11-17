// SPDX-License-Identifier: GPL-3.0-only
// MEDIUM port views (A6/A7/A8/A9/A11): read-only diagnostics and
// reversible proxy-rule tooling, surfaced under Tools > Advanced &
// Diagnostics. Nothing here writes to the MobileGestalt cache or
// to any system database; the only writes are the supervision
// cleanup (deletes only a fake-supervision residue file, never a
// genuine MDM profile), the crash-log cleanup (deletes only the
// app-readable diagnostic reports), and the proxy-module injection
// (writes one .sgmodule file into a detected proxy client's own
// AppGroup container).
import SwiftUI

// MARK: - A7 Battery telemetry

struct BatteryTelemetryView: View {
    @State private var result: PowerTelemetry.ReadResult?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Battery health, cycle count and temperature are read from the system powerlog (read-only). They are not available through public iOS APIs. When the firmware does not grant the powerlog, the values are shown as unavailable — never guessed."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isLoading {
                    ProgressView(L("Reading powerlog…"))
                } else if let result {
                    if !result.accessible {
                        Label(result.message ?? L("The powerlog container could not be opened on this firmware."), systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        if let latest = result.batterySamples.first {
                            GlassCard(cornerRadius: GlassTokens.cardRadius) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L("Latest Sample"))
                                        .font(.headline)
                                    if let health = latest.trueHealthPercent {
                                        LabeledContent(L("True Health"), value: String(format: "%.1f%%", health))
                                    } else {
                                        LabeledContent(L("True Health"), value: L("Unavailable"))
                                    }
                                    if let cycles = latest.cycleCount {
                                        LabeledContent(L("Cycle Count"), value: String(cycles))
                                    }
                                    if let level = latest.levelPercent {
                                        LabeledContent(L("Level"), value: String(format: "%.0f%%", level))
                                    }
                                    if let capacity = latest.rawMaxCapacitymAh {
                                        LabeledContent(L("Max Capacity"), value: "\(capacity) mAh")
                                    }
                                    if let design = latest.designCapacitymAh {
                                        LabeledContent(L("Design Capacity"), value: "\(design) mAh")
                                    }
                                    if let temp = latest.temperatureCelsius {
                                        LabeledContent(L("Temperature"), value: String(format: "%.1f °C", temp))
                                    }
                                    if let power = latest.computedPowerWatts {
                                        LabeledContent(L("Power"), value: String(format: "%.2f W", power))
                                    }
                                    LabeledContent(L("Charging"), value: latest.isCharging == nil ? L("Unknown") : (latest.isCharging! ? L("Yes") : L("No")))
                                    LabeledContent(L("Sampled"), value: latest.timestamp.formatted(date: .abbreviated, time: .shortened))
                                }
                            }
                        }
                        if !result.thermalEvents.isEmpty {
                            GlassCard(cornerRadius: GlassTokens.cardRadius) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(L("Thermal Events"))
                                        .font(.headline)
                                    ForEach(result.thermalEvents) { event in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(event.summary).font(.subheadline)
                                            Text(event.timestamp.formatted(date: .abbreviated, time: .shortened))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Divider()
                                    }
                                }
                            }
                        }
                        if result.batterySamples.isEmpty && result.thermalEvents.isEmpty {
                            Text(L("No powerlog samples were found."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Button(L("Refresh")) { load() }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    .disabled(isLoading)
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("Battery Telemetry"))
        .navigationBarTitleDisplayMode(.large)
        .task { load() }
    }

    private func load() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let read = PowerTelemetry.read()
            await MainActor.run {
                result = read
                isLoading = false
            }
        }
    }
}

// MARK: - A8 Crash diagnostics

struct CrashDiagnosticsView: View {
    @State private var report: CrashDiagnostics.ScanResult?
    @State private var message: String?
    @State private var isLoading = false
    @State private var asksClean = false

    private var crashCount: Int { report?.reports.filter { $0.kind == .crash }.count ?? 0 }
    private var jetsamCount: Int { report?.reports.filter { $0.kind == .jetsam }.count ?? 0 }
    private var systemCount: Int { report?.reports.filter { $0.kind == .system }.count ?? 0 }
    private var totalBytes: Int64 { report?.reports.reduce(0) { $0 + $1.fileSize } ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Crash, jetsam and panic reports already on this device, read-only. Cleaning deletes only the reports listed here; it never touches system logs."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isLoading {
                    ProgressView(L("Scanning diagnostic reports…"))
                } else if let report {
                    if !report.readable {
                        Label(report.message ?? L("The diagnostic reports container could not be opened on this system version."), systemImage: "exclamationmark.triangle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        GlassCard(cornerRadius: GlassTokens.cardRadius) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(L("Summary"))
                                    .font(.headline)
                                LabeledContent(L("Reports"), value: String(report.reports.count))
                                LabeledContent(L("Crashes"), value: String(crashCount))
                                LabeledContent(L("Jetsam"), value: String(jetsamCount))
                                LabeledContent(L("System"), value: String(systemCount))
                                LabeledContent(L("Total Size"), value: ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file))
                            }
                        }
                        if report.reports.isEmpty {
                            Text(L("No crash reports were found."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            GlassCard(cornerRadius: GlassTokens.cardRadius) {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(report.reports) { item in
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.processName).font(.subheadline)
                                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary)
                                            Text("\(item.fileName) · \(item.modifiedDate.formatted(date: .abbreviated, time: .shortened))")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Divider()
                                    }
                                }
                            }
                            Button(L("Delete All Reports"), role: .destructive) { asksClean = true }
                                .buttonStyle(.plain)
                                .disabled(!report.writable)
                        }
                    }
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
        .navigationTitle(L("Crash Diagnostics"))
        .navigationBarTitleDisplayMode(.large)
        .task { load() }
        .alert(L("Delete all diagnostic reports?"), isPresented: $asksClean) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Delete"), role: .destructive) {
                Task.detached(priority: .userInitiated) {
                    let deleted = CrashDiagnostics.cleanAllReports(report?.reports ?? [])
                    await MainActor.run {
                        message = deleted > 0 ? String(format: L("Deleted %lld report(s)."), deleted) : L("No reports were deleted.")
                        load()
                    }
                }
            }
        } message: {
            Text(L("This deletes the crash, jetsam and panic reports listed above. It does not affect system logs or any app data."))
        }
    }

    private func load() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let scanned = CrashDiagnostics.scan()
            await MainActor.run {
                report = scanned
                isLoading = false
            }
        }
    }
}

// MARK: - A6 Supervision audit

struct SupervisionAuditView: View {
    @State private var audit: SupervisionAuditState?
    @State private var message: String?
    @State private var isLoading = false
    @State private var asksClean = false

    private var summary: String {
        switch audit {
        case .clean:
            return L("No CloudConfigurationDetails.plist exists. The device carries no supervision residue.")
        case .genuineMDM(let organization):
            return organization.isEmpty
                ? L("This device has a genuine MDM supervision profile. It will never be deleted by this feature.")
                : String(format: L("This device has a genuine MDM supervision profile (%@). It will never be deleted by this feature."), organization)
        case .fakeResidue(let organization):
            return organization.isEmpty
                ? L("Only a fake-supervision residue file was found (IsSupervised with no MDM certificate chain). Cleaning it is safe.")
                : String(format: L("Only a fake-supervision residue file was found (%@, IsSupervised with no MDM certificate chain). Cleaning it is safe."), organization)
        case nil:
            return ""
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Checks whether this device carries a genuine MDM supervision profile or only a leftover fake-supervision residue file. Genuine MDM is never touched. Cleanup deletes only the residue file."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isLoading {
                    ProgressView(L("Auditing supervision state…"))
                } else if let audit {
                    GlassCard(cornerRadius: GlassTokens.cardRadius) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Result"))
                                .font(.headline)
                            switch audit {
                            case .clean:
                                LabeledContent(L("State"), value: L("Clean"))
                            case .genuineMDM(let organization):
                                LabeledContent(L("State"), value: L("Genuine MDM"))
                                if !organization.isEmpty {
                                    LabeledContent(L("Organization"), value: organization)
                                }
                            case .fakeResidue(let organization):
                                LabeledContent(L("State"), value: L("Fake Residue"))
                                if !organization.isEmpty {
                                    LabeledContent(L("Organization"), value: organization)
                                }
                            }
                            Text(summary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if case .fakeResidue = audit {
                        Button(L("Clean Fake Supervision Residue"), role: .destructive) { asksClean = true }
                            .buttonStyle(.plain)
                    }
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
        .navigationTitle(L("Supervision Audit"))
        .navigationBarTitleDisplayMode(.large)
        .task { load() }
        .alert(L("Clean fake supervision residue?"), isPresented: $asksClean) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Clean"), role: .destructive) {
                Task.detached(priority: .userInitiated) {
                    let cleaned = SupervisionAudit.cleanFakeResidue()
                    await MainActor.run {
                        message = cleaned ? L("Fake supervision residue removed. A genuine MDM profile was not touched.") : L("Nothing was removed. The residue may already be gone, or access was denied.")
                        load()
                    }
                }
            }
        } message: {
            Text(L("This deletes only the leftover CloudConfigurationDetails.plist that contains nothing but IsSupervised and OrganizationName. A genuine MDM enrollment is never deleted, and the lock-screen footnote is untouched."))
        }
    }

    private func load() {
        isLoading = true
        Task.detached(priority: .userInitiated) {
            let result = SupervisionAudit.audit()
            await MainActor.run {
                audit = result
                isLoading = false
            }
        }
    }
}

// MARK: - A9 Proxy rules

struct ProxyRulesView: View {
    @State private var format: ProxyRuleFormat = .surgeModule
    @State private var policy = "PROXY"
    @State private var proxyGroups: [AppGroupContainer] = []
    @State private var message: String?
    @State private var isScanning = false
    @State private var isInjecting = false
    @State private var export: TemporaryExport?
    @State private var asksInject: AppGroupContainer?

    private var content: String { ProxyRuleGenerator.content(for: format, policy: policy) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Generates routing rules that keep China Siri and Mandarin call screening on a real-IP direct connection, while routing Apple Intelligence private cloud compute, region checks and visual intelligence to your overseas policy group. Generating writes nothing; injection writes one .sgmodule file into the detected proxy client's own shared container."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                GlassCard(cornerRadius: GlassTokens.cardRadius) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Format"))
                            .font(.headline)
                        Picker(L("Format"), selection: $format) {
                            ForEach(ProxyRuleFormat.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        LabeledContent(L("Policy Group")) {
                            TextField("PROXY", text: $policy)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                        }
                    }
                }
                GlassCard(cornerRadius: GlassTokens.cardRadius) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L("Generated Rules"))
                            .font(.headline)
                        Text(content)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
                HStack(spacing: 12) {
                    Button(L("Copy")) {
                        UIPasteboard.general.string = content
                        message = L("Copied to the clipboard.")
                    }
                    .buttonStyle(GlassPrimaryButtonStyle())
                    Button(L("Share")) { share() }
                        .buttonStyle(GlassPrimaryButtonStyle())
                }
                GlassCard(cornerRadius: GlassTokens.cardRadius) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Inject into Proxy Client"))
                            .font(.headline)
                        if isScanning {
                            ProgressView(L("Scanning shared containers…"))
                        } else if proxyGroups.isEmpty {
                            Text(L("No proxy client was detected. Install Surge, Shadowrocket, Quantumult X, Loon or Stash first."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(proxyGroups) { group in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(group.clientName ?? group.groupID).font(.subheadline)
                                        Text(group.groupID).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button(L("Inject")) { asksInject = group }
                                        .buttonStyle(GlassPrimaryButtonStyle())
                                        .disabled(isInjecting || format != .surgeModule)
                                }
                                Divider()
                            }
                            if format != .surgeModule {
                                Text(L("Injection is only available for the Surge (.sgmodule) format."))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button(L("Scan Again")) { scan() }
                            .buttonStyle(.plain)
                            .disabled(isScanning)
                    }
                }
                if let message {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(GlassBackground())
        .navigationTitle(L("Proxy Rules"))
        .navigationBarTitleDisplayMode(.large)
        .task { scan() }
        .alert(L("Inject module into this proxy client?"), isPresented: Binding(get: { asksInject != nil }, set: { if !$0 { asksInject = nil } })) {
            Button(L("Cancel"), role: .cancel) {}
            Button(L("Inject")) {
                if let group = asksInject { inject(into: group) }
                asksInject = nil
            }
        } message: {
            Text(L("This writes one file (LilaShift-AppleIntelligence-CN.sgmodule) into the proxy client's own shared container. You still need to enable the module inside the proxy app. Removing the file fully reverses it."))
        }
        .sheet(item: $export) { ShareSheet(export: $0) }
    }

    private func scan() {
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let found = AppGroupDiscovery.scanProxyGroups()
            await MainActor.run {
                proxyGroups = found
                isScanning = false
            }
        }
    }

    private func share() {
        do {
            export = try TemporaryExport(data: Data(content.utf8), name: format.fileName)
        } catch {
            message = error.localizedDescription
        }
    }

    private func inject(into group: AppGroupContainer) {
        isInjecting = true
        Task.detached(priority: .userInitiated) {
            do {
                let file = try ProxyRuleInjector.inject(content: content, into: group)
                await MainActor.run {
                    message = String(format: L("Module written: %@. Open %@ and enable it in the module list."), file.lastPathComponent, group.clientName ?? group.groupID)
                    isInjecting = false
                }
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    isInjecting = false
                }
            }
        }
    }
}

// MARK: - A11 AppGroup browser

struct AppGroupBrowserView: View {
    @State private var groups: [AppGroupContainer] = []
    @State private var selected: AppGroupContainer?
    @State private var entries: [AppGroupBrowser.Entry] = []
    @State private var relativePath = ""
    @State private var bookmarks: [SafariBookmarkRecord] = []
    @State private var isScanning = false
    @State private var message: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Shared AppGroup containers on this device, read-only. A container is only listed when its group identity could be verified; browsing never writes or deletes anything."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if isScanning {
                    ProgressView(L("Scanning shared containers…"))
                } else if groups.isEmpty {
                    Text(L("No shared AppGroup containers were found."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    GlassCard(cornerRadius: GlassTokens.cardRadius) {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(groups) { group in
                                Button {
                                    selected = group
                                    relativePath = ""
                                    entries = AppGroupBrowser.list(container: group)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(group.clientName ?? group.groupID).font(.subheadline)
                                            Text(group.groupID).font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                    }
                }
                if let selected {
                    GlassCard(cornerRadius: GlassTokens.cardRadius) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(selected.clientName ?? selected.groupID)
                                .font(.headline)
                            Text(relativePath.isEmpty ? "/" : "/" + relativePath)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if !relativePath.isEmpty {
                                Button(L("Up")) {
                                    let parts = relativePath.split(separator: "/")
                                    relativePath = parts.dropLast().joined(separator: "/")
                                    entries = AppGroupBrowser.list(container: selected, relativePath: relativePath)
                                }
                                .buttonStyle(.plain)
                            }
                            if entries.isEmpty {
                                Text(L("This container is empty or cannot be read."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(entries) { entry in
                                    Button {
                                        guard entry.isDirectory else { return }
                                        relativePath = relativePath.isEmpty ? entry.name : relativePath + "/" + entry.name
                                        entries = AppGroupBrowser.list(container: selected, relativePath: relativePath)
                                    } label: {
                                        HStack {
                                            Image(systemName: entry.isDirectory ? "folder" : "doc")
                                            Text(entry.name).font(.subheadline)
                                            Spacer()
                                            if !entry.isDirectory {
                                                Text(ByteCountFormatter.string(fromByteCount: entry.byteCount, countStyle: .file))
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(!entry.isDirectory)
                                    Divider()
                                }
                            }
                        }
                    }
                }
                if !bookmarks.isEmpty {
                    GlassCard(cornerRadius: GlassTokens.cardRadius) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Safari Bookmarks"))
                                .font(.headline)
                            ForEach(bookmarks.prefix(50)) { bookmark in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(bookmark.title.isEmpty ? bookmark.url : bookmark.title).font(.subheadline)
                                    Text(bookmark.url).font(.caption).foregroundStyle(.secondary)
                                }
                                Divider()
                            }
                        }
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
        .navigationTitle(L("AppGroup Browser"))
        .navigationBarTitleDisplayMode(.large)
        .task { scan() }
    }

    private func scan() {
        isScanning = true
        Task.detached(priority: .userInitiated) {
            let found = AppGroupDiscovery.scanSharedGroups()
            let safari = found
                .first { $0.groupID.lowercased() == "group.com.apple.mobilesafari" || $0.groupID.lowercased() == "group.com.apple.safari" }
            var loadedBookmarks: [SafariBookmarkRecord] = []
            if let safari {
                let dbPath = safari.url.appendingPathComponent("Library/Safari/Bookmarks.db").path
                if FileManager.default.isReadableFile(atPath: dbPath) {
                    loadedBookmarks = SafariBookmarks.read(at: dbPath)
                }
            }
            await MainActor.run {
                groups = found
                bookmarks = loadedBookmarks
                isScanning = false
                if found.isEmpty {
                    message = L("No shared containers could be read on this device.")
                }
            }
        }
    }
}
