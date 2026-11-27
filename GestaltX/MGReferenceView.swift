// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

private struct MGReferenceEntry: Decodable, Identifiable, Sendable {
    let key: String
    let name: String
    let introduced: String
    let removed: [String]
    let reintroduced: [String]
    var id: String { key }

    var category: MGReferenceCategory {
        let normalized = name.lowercased()
        return MGReferenceCategory.allCases.first { group in
            group.tokens.contains { normalized.contains($0) }
        } ?? .other
    }

    static func load() throws -> [Self] {
        guard let url = Bundle.main.url(forResource: "MGReference", withExtension: "json") else {
            throw CustomizationFailure("MobileGestalt reference data is unavailable.")
        }
        return try JSONDecoder().decode([Self].self, from: Data(contentsOf: url)).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

private enum MGReferenceCategory: String, CaseIterable, Identifiable {
    case connectivity = "Connectivity"
    case display = "Display & Input"
    case media = "Camera & Media"
    case security = "Identity & Security"
    case hardware = "Hardware & Power"
    case system = "System & Localization"
    case other = "Other Keys"

    var id: Self { self }

    var tokens: [String] {
        switch self {
        case .connectivity:
            return ["wifi", "wi-fi", "network", "radio", "lte", "cellular", "simcard", "esim",
                    "telephony", "baseband", "bluetooth", "carrier", "nfc", "wireless", "airdrop"]
        case .display:
            return ["display", "screen", "brightness", "keyboard", "touch", "pencil", "parallax", "pointer"]
        case .media:
            return ["camera", "microphone", "audio", "video", "speaker", "photo", "hevc", "h264", "music", "codec"]
        case .security:
            return ["passcode", "secure", "security", "serial", "attestation", "identifier", "activation", "biometric"]
        case .hardware:
            return ["battery", "power", "processor", "chip", "gpu", "cpu", "hardware", "sensor", "charger", "memory"]
        case .system:
            return ["region", "language", "locale", "siri", "osversion", "build", "deviceclass", "product", "boot"]
        case .other:
            return []
        }
    }
}

struct MGReferenceView: View {
    @State private var entries: [MGReferenceEntry]?
    @State private var error: String?
    @State private var query = ""
    @State private var category: MGReferenceCategory?

    private var matches: [MGReferenceEntry] {
        let terms = query.split(whereSeparator: \.isWhitespace)
        return (entries ?? []).filter { entry in
            let group = entry.category
            guard category == nil || category == group else { return false }
            return terms.allSatisfy { term in
                [entry.name, entry.key, L(group.rawValue)].contains {
                    $0.localizedCaseInsensitiveContains(String(term))
                }
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker(L("Category"), selection: $category) {
                    Text(L("All Categories")).tag(nil as MGReferenceCategory?)
                    ForEach(MGReferenceCategory.allCases) { group in
                        Text(L(group.rawValue)).tag(Optional(group))
                    }
                }
            } footer: {
                Text(L("Version history comes from MGKeys. Categories are approximate. Entries describe known keys and do not confirm support on your device."))
            }
            if let error {
                Text(error).foregroundStyle(.secondary)
            } else if entries == nil {
                ProgressView()
            } else {
                let results = matches
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(results) { entry in
                        NavigationLink {
                            detail(entry)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(entry.name).font(.body)
                                Text(L(entry.category.rawValue)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("MobileGestalt Reference"))
        .searchable(text: $query, prompt: L("Search names, hashes, or categories"))
        .task {
            guard entries == nil else { return }
            do {
                entries = try await Task.detached { try MGReferenceEntry.load() }.value
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func detail(_ entry: MGReferenceEntry) -> some View {
        List {
            LabeledContent(L("Category"), value: L(entry.category.rawValue))
            LabeledContent(L("Key Hash"), value: entry.key)
            LabeledContent(L("First Observed"), value: versionLabel(entry.introduced))
            if !entry.removed.isEmpty {
                LabeledContent(L("Removed In"), value: entry.removed.joined(separator: ", "))
            }
            if !entry.reintroduced.isEmpty {
                LabeledContent(L("Returned In"), value: entry.reintroduced.joined(separator: ", "))
            }
        }
        .textSelection(.enabled)
        .navigationTitle(entry.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func versionLabel(_ version: String) -> String {
        switch version {
        case "sim": return L("Simulator Only")
        case "unknown": return L("Unknown")
        default: return version
        }
    }
}
