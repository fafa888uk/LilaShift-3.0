// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

enum W11AppearanceMode: String, CaseIterable, Identifiable {
    case light, dark, system

    static let storageKey = "LilaShift.appearanceMode.v1"
    static let defaultMode: Self = .light

    var id: Self { self }

    static func stored(_ rawValue: String) -> Self {
        Self(rawValue: rawValue) ?? defaultMode
    }

    var preferredScheme: ColorScheme? {
        switch self {
        case .light: .light
        case .dark: .dark
        case .system: nil
        }
    }

    var title: String {
        switch self {
        case .light: String(localized: "Light", table: "W11Appearance")
        case .dark: String(localized: "Dark", table: "W11Appearance")
        case .system: String(localized: "Follow System", table: "W11Appearance")
        }
    }
}

struct W11AppearanceSettingsRow: View {
    @AppStorage(W11AppearanceMode.storageKey) private var storedMode = W11AppearanceMode.defaultMode.rawValue

    private var selection: Binding<W11AppearanceMode> {
        Binding(
            get: { W11AppearanceMode.stored(storedMode) },
            set: { storedMode = $0.rawValue }
        )
    }

    var body: some View {
        Picker(selection: selection) {
            ForEach(W11AppearanceMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        } label: {
            Label {
                Text("App Appearance", tableName: "W11Appearance")
            } icon: {
                Image(systemName: "circle.lefthalf.filled")
            }
        }
        .pickerStyle(.menu)
        .accessibilityIdentifier("lilashift.appearance.mode")
    }
}
