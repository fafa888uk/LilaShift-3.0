// SPDX-License-Identifier: GPL-3.0-only
// The merged official-API tools page (LilaShift 5.0.0 merge).
// One destination hosting every feature that uses only public
// Apple APIs: screen brightness write, the intelligence report,
// the resource monitor, the network egress check, the wallpaper
// studio, the local plist workspace, the session log, and the
// app appearance mode. Nothing on this page writes MobileGestalt,
// eSIM, Apple Intelligence eligibility, the system appearance,
// wallet cards, or another app's container. The full 4.2.0
// feature set (including the sandbox-escape-backed writes) stays
// reachable from the rest of the app; this page adds to it, it
// does not replace it.
import SwiftUI

struct OfficialToolsPage: View {
    var body: some View {
        List {
            Section {
                NavigationLink {
                    BrightnessWriteView()
                } label: {
                    Label("屏幕亮度写入", systemImage: "sun.max")
                }
                NavigationLink {
                    W7IntelligenceReportView()
                } label: {
                    Label(W7IntelligenceReportView.title, systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink {
                    W8ResourceMonitorView()
                } label: {
                    Label(W8ResourceMonitorView.title, systemImage: "waveform.path")
                }
                NavigationLink {
                    NetworkCheckView()
                } label: {
                    Label("network.title", systemImage: "network")
                }
                NavigationLink {
                    W9WallpaperStudioView()
                } label: {
                    Label(W9WallpaperStudioView.title, systemImage: "photo.stack")
                }
                NavigationLink {
                    LocalPlistWorkspaceView()
                } label: {
                    Label("本地 plist 工作区", systemImage: "doc.badge.gearshape")
                }
                NavigationLink {
                    UnifiedOperationLogView()
                } label: {
                    Label("会话日志", systemImage: "list.bullet.rectangle")
                }
            }

            Section {
                W11AppearanceSettingsRow()
            } header: {
                Text("appearance.heading")
            } footer: {
                Text(String(localized: "Changes only LilaShift, not the iOS appearance setting.", table: "W11Appearance"))
            }
        }
        .navigationTitle(L("Official API Tools"))
    }
}
