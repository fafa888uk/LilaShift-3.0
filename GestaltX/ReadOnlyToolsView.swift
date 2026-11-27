// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

struct ReadOnlyToolsView: View {
    @State private var query = ""

    private enum Tool: CaseIterable, Identifiable {
        case live, ipa, pairing, gestalt, themes

        var id: Self { self }

        var title: String {
            switch self {
            case .live: return L("Live Diagnostics")
            case .ipa: return L("IPA Archive Inspection")
            case .pairing: return L("Pairing Record Inspection")
            case .gestalt: return L("MobileGestalt Reference")
            case .themes: return L("Theme Preview")
            }
        }

        var symbol: String {
            switch self {
            case .live: return "waveform.path.ecg"
            case .ipa: return "checkmark.shield"
            case .pairing: return "iphone.gen3"
            case .gestalt: return "books.vertical"
            case .themes: return "swatchpalette"
            }
        }

        var category: String {
            switch self {
            case .live, .ipa, .pairing: return L("Diagnostics")
            case .gestalt: return L("Reference")
            case .themes: return L("Customization")
            }
        }

        @ViewBuilder var destination: some View {
            switch self {
            case .live: LiveDiagnosticsView()
            case .ipa: IPAAuditView()
            case .pairing: PairingRecordInspectionView()
            case .gestalt: MGReferenceView()
            case .themes: ThemePreviewView()
            }
        }
    }

    var body: some View {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = Tool.allCases.filter {
            text.isEmpty || $0.title.localizedStandardContains(text) || $0.category.localizedStandardContains(text)
        }
        List {
            if filtered.isEmpty {
                ContentUnavailableView.search(text: text)
            }
            ForEach([L("Diagnostics"), L("Reference"), L("Customization")], id: \.self) { category in
                let tools = filtered.filter { $0.category == category }
                if !tools.isEmpty {
                    Section(category) {
                        ForEach(tools) { tool in
                            NavigationLink {
                                tool.destination
                            } label: {
                                Label(tool.title, systemImage: tool.symbol)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(L("Read-Only Tools"))
        .searchable(text: $query, prompt: L("Search tools"))
        .tint(.gestaltAccent)
    }
}
