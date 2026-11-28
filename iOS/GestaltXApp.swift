// SPDX-License-Identifier: GPL-3.0-only
//
//  GestaltXApp.swift
//  GestaltX
//

import SwiftUI

@main
struct GestaltXApp: App {
    @AppStorage(W11AppearanceMode.storageKey) private var storedMode = W11AppearanceMode.defaultMode.rawValue
    @State private var w8NetworkCounter = W8NetworkCounter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.w8NetworkCounter, w8NetworkCounter)
                .preferredColorScheme(W11AppearanceMode.stored(storedMode).preferredScheme)
                .environment(\.layoutDirection, Bundle.main.preferredLocalizations.first?.hasPrefix("fa") == true ? .rightToLeft : .leftToRight)
        }
    }
}
