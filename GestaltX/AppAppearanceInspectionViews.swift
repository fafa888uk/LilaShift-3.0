// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

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
    @State private var isReading = false

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
                    ShareLink(item: evidenceText(names))
                }
            } header: {
                Text(appearanceDiagnosticText("Read-only cache evidence"))
            } footer: {
                Text(appearanceDiagnosticText("The system icon lookup is separate from the on-disk icon cache. Cache writes are unverified."))
            }
            AppAppearancePreviewView(app: app)
        }
        .navigationTitle(app.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await inspect() }
    }

    private func inspect() async {
        guard !isReading else { return }
        isReading = true
        names = nil
        iconPNG = nil
        defer { isReading = false }
        let bundleID = app.id
        let result = await Task.detached(priority: .userInitiated) {
            AppearanceNameEvidence.inspect(bundleID)
        }.value
        guard !Task.isCancelled else { return }
        iconPNG = GXCustomizationAccess.homeScreenIcon(for: bundleID)
        names = result
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
            "System icon PNG SHA-256 = \(iconPNG.map(GestaltFileStore.sha256Hex(of:)) ?? unknown)"
        ].joined(separator: "\n")
    }
}
