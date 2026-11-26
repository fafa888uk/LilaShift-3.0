// SPDX-License-Identifier: GPL-3.0-only
//
//  GestaltXApp.swift
//  GestaltX
//

import SwiftUI

@main
struct GestaltXApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.light)
                .environment(\.layoutDirection, Bundle.main.preferredLocalizations.first?.hasPrefix("fa") == true ? .rightToLeft : .leftToRight)
        }
    }
}
