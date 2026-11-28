// SPDX-License-Identifier: GPL-3.0-only
// Screen brightness write / read-back / restore, using only the
// public UIScreen API. Extracted from the official-API target's
// SettingsScreen (Codex, lilashift-merged-offline-ci): the @main
// entry itself cannot be ported (the GestaltX target already has
// its own @main), so the brightness section lives here as a plain
// view hosted by the merged official-tools page. Every write goes
// through VerifiedChange: read back, compare with 1/255 tolerance,
// and restore the original when the app goes to the background.
import SwiftUI
import UIKit

@MainActor
struct BrightnessWriteView: View {
    @EnvironmentObject private var operationLog: UnifiedOperationLog
    @Environment(\.scenePhase) private var scenePhase
    @State private var transaction = VerifiedChange<Double>()
    @State private var selectedScreen: UIScreen?
    @State private var observed: Double?
    @State private var requested = 0.5
    @State private var result: VerifiedChange<Double>.Result?
    @State private var confirming = false

    private var isPhysicalDevice: Bool {
#if targetEnvironment(simulator)
        false
#else
        !ProcessInfo.processInfo.isiOSAppOnMac && !ProcessInfo.processInfo.isMacCatalystApp
#endif
    }

    private var activeScreen: UIScreen? {
        guard isPhysicalDevice else { return nil }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first {
            $0.session.role == .windowApplication &&
            $0.activationState == .foregroundActive &&
            $0.windows.contains(where: \.isKeyWindow)
        }?.screen
    }

    var body: some View {
        Form {
            Section {
                if let observed {
                    LabeledContent("screen.actual", value: observed.formatted(.percent.precision(.fractionLength(1))))
                } else {
                    Text(LocalizedStringKey(isPhysicalDevice ? "screen.unavailable" : "screen.physicalOnly"))
                        .foregroundStyle(.secondary)
                }

                if observed != nil && !transaction.canRestore {
                    LabeledContent("screen.target", value: requested.formatted(.percent))
                    Slider(value: $requested, in: 0.15...1, step: 0.01) {
                        Text("screen.target")
                    }
                    Button("screen.apply", systemImage: "sun.max") {
                        confirming = true
                    }
                }

                if transaction.canRestore {
                    Button("screen.restore", systemImage: "arrow.uturn.backward") { restore() }
                    if result == .externallyChanged || result == .restoreUnverified {
                        Button("screen.discard", systemImage: "xmark.circle") {
                            transaction.discard()
                            selectedScreen = nil
                            result = nil
                            refresh()
                        }
                    }
                }

                if let result {
                    Text(status(result)).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("screen.heading")
            } footer: {
                Text("screen.footer")
            }
        }
        .navigationTitle("screen.heading")
        .alert("screen.confirmTitle", isPresented: $confirming) {
            Button("screen.confirmWrite") { apply() }
            Button("common.cancel", role: .cancel) {}
        } message: {
            Text("screen.confirmBody")
        }
        .task { refresh() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background && transaction.canRestore {
                restore()
            } else if newPhase == .active {
                refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIScreen.brightnessDidChangeNotification)) { _ in
            // Do not synchronously reenter a UIKit setter/transaction.
            Task { @MainActor in refresh() }
        }
    }

    private func refresh() {
        let value = (selectedScreen ?? activeScreen).map { Double($0.brightness) }
        if observed == nil, let value {
            requested = min(1, max(0.15, value))
        }
        observed = value
    }

    private func matches(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) <= 1.0 / 255
    }

    private func apply() {
        guard let screen = activeScreen else {
            result = .unavailable
            refresh()
            return
        }
        let target = requested
        var change = transaction
        let outcome = change.apply(
            target, read: { Double(screen.brightness) },
            write: { screen.brightness = CGFloat($0) }, equals: matches
        )
        result = outcome
        switch outcome {
        case .applied:
            operationLog.record(.screen, .info, "屏幕亮度写入已读回核对")
        case .unchanged:
            operationLog.record(.screen, .info, "屏幕亮度已相同，没有写入")
        default:
            operationLog.record(.screen, .warning, "屏幕亮度写入未获确认")
        }
        transaction = change
        selectedScreen = change.canRestore ? screen : nil
        refresh()
    }

    private func restore() {
        guard let screen = selectedScreen else { return }
        var change = transaction
        let outcome = change.restore(
            read: { Double(screen.brightness) },
            write: { screen.brightness = CGFloat($0) }, equals: matches
        )
        result = outcome
        if outcome == .restored {
            operationLog.record(.screen, .info, "原始屏幕亮度已恢复并读回")
        } else {
            operationLog.record(.screen, .warning, "屏幕亮度恢复未获确认")
        }
        transaction = change
        if !change.canRestore { selectedScreen = nil }
        refresh()
    }

    private func status(_ result: VerifiedChange<Double>.Result) -> LocalizedStringKey {
        switch result {
        case .applied: "status.applied"
        case .restored: "status.restored"
        case .unchanged: "status.unchanged"
        case .busy: "status.busy"
        case .unavailable: "status.unavailable"
        case .writeRejectedAndOriginalRecovered: "status.rejected"
        case .restoreUnverified: "status.unverified"
        case .externallyChanged: "status.conflict"
        }
    }
}
