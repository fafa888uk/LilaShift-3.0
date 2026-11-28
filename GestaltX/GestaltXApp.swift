// SPDX-License-Identifier: GPL-3.0-only
//
//  GestaltXApp.swift
//  GestaltX
//

import SwiftUI

@main
struct GestaltXApp: App {
    // Merge (LilaShift 5.0.0): the official-API tools need two
    // app-level objects — the W8 network counter (RIPEstat traffic
    // totals, observed by W8ResourceMonitorView / NetworkCheckView)
    // and the unified session operation log (written by the
    // brightness, network and plist tools). Both are created here
    // so every hosted view sees the same instance.
    @State private var w8Counter = W8NetworkCounter()
    @StateObject private var operationLog = UnifiedOperationLog()
    // Merge: the app appearance mode (W11). Default is light, so
    // the 4.2.0 forced-light behaviour is unchanged until the user
    // picks dark / follow-system in the official-tools page. This
    // only changes this app's scheme, never the iOS setting.
    @AppStorage(W11AppearanceMode.storageKey) private var appearance = W11AppearanceMode.defaultMode.rawValue

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(W11AppearanceMode.stored(appearance).preferredScheme)
                .environment(\.w8NetworkCounter, w8Counter)
                .environmentObject(operationLog)
                .environment(\.layoutDirection, Bundle.main.preferredLocalizations.first?.hasPrefix("fa") == true ? .rightToLeft : .leftToRight)
        }
    }
}
