// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
// LilaShift enhancement: open-source contributor center (About page).
// Maintainer: @steam8871. Upstream GestaltX code remains huamidev's.
// See THIRD_PARTY_NOTICES.md and docs/OPEN_SOURCE_REFERENCES.md.
import SwiftUI

/// One open-source project LilaShift uses or references.
/// `relationshipKey` is a localization key (e.g. "Bundled code").
/// `tech` is a short English technical tag (proper nouns / technical terms).
/// `license` is nil when the project states no open-source license.
/// `licenseFile` is the bundled license text (without ".txt"), nil when
/// the text is not shipped in the app (research references and tools).
struct OpenSourceProject: Identifiable {
    let name: String
    let author: String
    let relationshipKey: String
    let tech: String
    let license: String?
    let licenseFile: String?
    let url: String
    let shippedInIPA: Bool
    var id: String { name }
}

let openSourceProjects: [OpenSourceProject] = [
    OpenSourceProject(name: "GestaltX", author: "huamidev", relationshipKey: "Original code base", tech: "Application baseline", license: "GPL-3.0", licenseFile: "GestaltX-GPL-3.0", url: "https://github.com/huamidev/GestaltX", shippedInIPA: true),
    OpenSourceProject(name: "worse_query", author: "Taj C (forcequitOS)", relationshipKey: "Bundled code", tech: "Sandbox escape", license: "GPL-3.0-or-later", licenseFile: "GestaltX-GPL-3.0", url: "https://github.com/forcequitOS/worse_query", shippedInIPA: true),
    OpenSourceProject(name: "Ketamine", author: "Nouvborne", relationshipKey: "Suspended", tech: "Respring", license: "GPL-3.0", licenseFile: "GestaltX-GPL-3.0", url: "https://github.com/Nouvborne/Ketamine", shippedInIPA: false),
    OpenSourceProject(name: "NeoSpring", author: "rooootdev", relationshipKey: "Suspended", tech: "Respring", license: nil, licenseFile: nil, url: "https://github.com/rooootdev/neospring", shippedInIPA: false),
    OpenSourceProject(name: "LCSign", author: "huamidev", relationshipKey: "Design reference", tech: "Entitlement reading", license: nil, licenseFile: nil, url: "https://sign.lc", shippedInIPA: false),
    OpenSourceProject(name: "Erosion-CN", author: "Kianuni", relationshipKey: "Reused data", tech: "AI checkup · Safe write · Device data", license: "GPL-3.0", licenseFile: "Erosion-GPL-3.0", url: "https://github.com/Kianuni/Erosion-CN", shippedInIPA: true),
    OpenSourceProject(name: "Erosion", author: "lunginspector · jailbreak.party", relationshipKey: "Design reference", tech: "Wallpaper descriptors", license: "GPL-3.0", licenseFile: "Erosion-GPL-3.0", url: "https://github.com/jailbreakdotparty/Erosion", shippedInIPA: false),
    OpenSourceProject(name: "Gester", author: "sasobhabha · KAMUI contributors", relationshipKey: "Design reference", tech: "PosterBoard descriptors", license: "MIT", licenseFile: "Gester-MIT", url: "https://github.com/sasobhabha/Gester", shippedInIPA: false),
    OpenSourceProject(name: "ZIPFoundation", author: "Thomas Zoechling", relationshipKey: "Bundled code", tech: "ZIP archives", license: "MIT", licenseFile: "ZIPFoundation-MIT", url: "https://github.com/weichsel/ZIPFoundation", shippedInIPA: true),
    OpenSourceProject(name: "Primer Octicons", author: "GitHub Inc.", relationshipKey: "Bundled code", tech: "GitHub icon", license: "MIT", licenseFile: "Primer-Octicons-MIT", url: "https://github.com/primer/octicons", shippedInIPA: true),
    OpenSourceProject(name: "MGKeys", author: "PoomSmart", relationshipKey: "Research reference", tech: "Key mappings", license: "MIT", licenseFile: nil, url: "https://github.com/PoomSmart/MGKeys", shippedInIPA: false),
    OpenSourceProject(name: "Nugget", author: "leminlimez", relationshipKey: "Research reference", tech: "Key mappings · Feature grouping", license: "AGPL-3.0", licenseFile: nil, url: "https://github.com/leminlimez/Nugget", shippedInIPA: false),
    OpenSourceProject(name: "mond", author: "rooootdev", relationshipKey: "Research reference", tech: "Key mappings", license: "AGPL-3.0", licenseFile: nil, url: "https://github.com/rooootdev/mond", shippedInIPA: false),
    OpenSourceProject(name: "GestaltEdit", author: "frs0n", relationshipKey: "Research reference", tech: "Workflow reference", license: "GPL-3.0-or-later", licenseFile: nil, url: "https://github.com/frs0n/GestaltEdit", shippedInIPA: false),
    OpenSourceProject(name: "WQFiles", author: "kolbicz", relationshipKey: "Research reference", tech: "LaunchServices discovery", license: "GPL-3.0", licenseFile: "GestaltX-GPL-3.0", url: "https://github.com/kolbicz/WQFiles", shippedInIPA: false),
    OpenSourceProject(name: "SnapshotTesting", author: "Point-Free, Inc.", relationshipKey: "Test tool", tech: "Snapshot tests", license: "MIT", licenseFile: nil, url: "https://github.com/pointfreeco/swift-snapshot-testing", shippedInIPA: false),
    OpenSourceProject(name: "SwiftLint", author: "Realm Inc.", relationshipKey: "Build tool", tech: "Code style checks", license: "MIT", licenseFile: nil, url: "https://github.com/realm/SwiftLint", shippedInIPA: false),
]

struct AboutView: View {
    @EnvironmentObject private var model: GestaltManager
    var body: some View {
        List {
            Section {
                HStack(spacing: GlassTokens.rowSpacing) {
                    BrandMark(size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("LilaShift")).font(.headline)
                        Text("LilaShift \(GestaltBrand.version) (\(GestaltBrand.build))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 6)
                Link(destination: GestaltBrand.lilashift) {
                    Label { Text(L("GitHub Repository")) } icon: {
                        Image("GitHubMark").renderingMode(.template).resizable().scaledToFit()
                            .frame(width: 22, height: 22).foregroundStyle(Color(uiColor: .label))
                    }
                }
                Link(destination: URL(string: "https://t.me/LilaShiftUpdates")!) {
                    Label(L("Telegram Updates Channel"), systemImage: "paperplane.fill")
                }
                ShareLink(item: ShareLilaShift.text()) {
                    Label(L("Share LilaShift"), systemImage: "square.and.arrow.up")
                }
            }
            Section {
                LabeledContent(L("Supported OS"), value: VersionSupport.range)
                NavigationLink { CompatibilityView() } label: { Label(L("Compatibility"), systemImage: "iphone.badge.checkmark") }
            }
            Section(L("Open Source & Acknowledgements")) {
                LabeledContent(L("Original Project"), value: "GestaltX")
                LabeledContent(L("Original Author"), value: "huamidev")
                LabeledContent(L("Enhanced Version Maintainer"), value: "@steam8871")
                NavigationLink { LicenseTextView(name: "GestaltX-GPL-3.0", title: "GNU GPL v3") } label: {
                    LabeledContent(L("Open Source License"), value: "GNU GPL v3.0")
                }
                Text(L("The enhanced version is distributed under the GNU GPL v3.0. Its complete corresponding source is distributed with the release."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
                Text("Based on GestaltX by huamidev")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
            Section {
                ForEach(openSourceProjects) { project in
                    NavigationLink { OpenSourceProjectDetailView(project: project) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(project.name)
                                Text(project.author).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(L(project.relationshipKey)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(L("Technical Sources"))
            } footer: {
                Text(L("Tap a project for its author, relationship, key technology, license and source link."))
                    .font(.footnote)
            }
            Section {
                licenseRow("Third-Party Notices", file: "ThirdPartyNotices")
                licenseRow("GNU GPL v3", file: "GestaltX-GPL-3.0")
                licenseRow("Erosion · GPL v3", file: "Erosion-GPL-3.0")
                licenseRow("Gester · MIT", file: "Gester-MIT")
                licenseRow("ZIPFoundation · MIT", file: "ZIPFoundation-MIT")
                licenseRow("Primer Octicons · MIT", file: "Primer-Octicons-MIT")
            } header: {
                Text(L("Third-Party Licenses"))
            } footer: {
                Text(L("License texts shown here are bundled with the app. Research references and development tools are MIT- or GPL-licensed at their upstream repositories; their texts are not bundled because their code is not shipped in the app."))
                    .font(.footnote)
            }
            Section(L("Full Source Code")) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Original Project URL")).font(.caption).foregroundStyle(.secondary)
                    Link("https://github.com/huamidev/GestaltX", destination: GestaltBrand.projects)
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(L("Enhanced Source URL")).font(.caption).foregroundStyle(.secondary)
                    Link("https://github.com/fafa888uk/LilaShift-3.0", destination: GestaltBrand.lilashift)
                        .font(.subheadline)
                }
                .padding(.vertical, 4)
            }
            Section(L("Disclaimer")) {
                Text(L("LilaShift is an unofficial enhancement project. It is not affiliated with Apple or any upstream project."))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(L("Modifying device features carries compatibility and data risks. Back up your device before applying changes."))
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(L("The complete source code is provided under the applicable open-source licenses."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Section {
            } footer: {
                aboutFooter.padding(.top, 8)
            }
        }
        .listSectionSpacing(20)
        .safeAreaPadding(.bottom, 20)
        .navigationTitle(L("About"))
    }

    private func licenseRow(_ title: String, file: String) -> some View {
        NavigationLink { LicenseTextView(name: file, title: title) } label: {
            Text(title)
        }
    }

    private var aboutFooter: some View {
        let year = Calendar.current.component(.year, from: .now)
        return VStack(spacing: 8) {
            Text("\(L("LilaShift")) \(GestaltBrand.version) (\(GestaltBrand.build))")
                .foregroundStyle(.secondary)
            Text("Based on GestaltX by huamidev · Enhanced by @steam8871")
                .foregroundStyle(.secondary.opacity(0.7))
            Text("© \(String(year)) huamidev. Licensed under the GNU GPL v3.")
                .foregroundStyle(.secondary.opacity(0.5))
        }
        .font(.caption)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }
}

struct OpenSourceProjectDetailView: View {
    let project: OpenSourceProject
    var body: some View {
        List {
            Section {
                LabeledContent(L("Author"), value: project.author)
                LabeledContent(L("Relationship"), value: L(project.relationshipKey))
                LabeledContent(L("Key Technology"), value: project.tech)
                if let file = project.licenseFile, let license = project.license {
                    NavigationLink { LicenseTextView(name: file, title: project.name + " · " + license) } label: {
                        LabeledContent(L("License"), value: license)
                    }
                } else if let license = project.license {
                    LabeledContent(L("License"), value: license)
                } else {
                    LabeledContent(L("License"), value: L("No license stated"))
                }
                LabeledContent(L("Shipped in IPA"), value: project.shippedInIPA ? L("Yes") : L("No"))
            }
            Section(L("GitHub Repository")) {
                Link(project.url, destination: URL(string: project.url)!)
                    .font(.subheadline)
            }
        }
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
struct CompatibilityView: View {
    var body: some View {
        List {
            Section(L("worse_query")) {
                Text(VersionSupport.range).font(.headline)
                LabeledContent("iOS 26.x", value: L("Unsupported"))
                Text(L("Available paths and MobileGestalt presets vary by device and OS build."))
                    .font(.subheadline).foregroundStyle(.secondary)
                Link(L("Read Upstream Compatibility"), destination: URL(string: "https://github.com/forcequitOS/worse_query")!)
            }
            Section(L("Manual Restart")) {
                Text(L("LilaShift does not restart SpringBoard itself. After applying changes, restart your device manually if a feature does not appear."))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }.navigationTitle(L("Compatibility"))
    }
}
struct LicenseTextView: View {
    let name: String
    let title: String
    var source: URL? = nil
    /// The license paragraphs, loaded once in `.task`. The old
    /// computed property re-read the bundle file on every body
    /// evaluation; the file is small and local, but there is no
    /// reason to read it more than once.
    @State private var paragraphs: [String] = []
    /// Reads and reflows a bundled license text for a phone screen.
    /// GPL's source text is wrapped at fixed columns, so paragraphs
    /// are rejoined on whitespace. Returns a fallback paragraph when
    /// the file cannot be loaded.
    private static func loadParagraphs(name: String) -> [String] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [L("License text could not be loaded.")] }
        return text.components(separatedBy: "\n\n").map { paragraph in
            paragraph.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }.filter { !$0.isEmpty }
    }
    private func isHeading(_ text: String) -> Bool {
        (text.count < 90 && text == text.uppercased()) || text == "Preamble"
            || text.range(of: #"^\d+\. [A-Z]"#, options: .regularExpression) != nil
            || text == "How to Apply These Terms to Your New Programs"
    }
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(isHeading(paragraph) ? .headline : .body)
                        .lineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .textSelection(.enabled)
            .environment(\.layoutDirection, .leftToRight)
            .padding(20).frame(maxWidth: 720).frame(maxWidth: .infinity)
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
        .task { paragraphs = Self.loadParagraphs(name: name) }
        .toolbar {
            if let source {
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: source) {
                        Image("GitHubMark").renderingMode(.template).resizable().scaledToFit().frame(width: 22, height: 22)
                    }.accessibilityLabel(L("GitHub Repository"))
                }
            }
        }
    }
}
