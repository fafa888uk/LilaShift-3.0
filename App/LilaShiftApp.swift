import SwiftUI
import UIKit
import Combine
import Foundation

@main
struct LilaShiftApp: App {
    @AppStorage("appearance") private var appearance = "system"

    var body: some Scene {
        WindowGroup {
            SettingsScreen(appearance: $appearance)
                .preferredColorScheme(
                    appearance == "dark" ? .dark : appearance == "light" ? .light : nil
                )
                .tint(Color(red: 0.49, green: 0.30, blue: 0.78))
        }
    }
}

@MainActor
private struct SettingsScreen: View {
    @Binding var appearance: String
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
        NavigationStack {
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

                Section("device.heading") {
                    LabeledContent("device.system", value: "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
                    LabeledContent("device.family", value: UIDevice.current.localizedModel)
                    LabeledContent("device.memory", value: ByteCountFormatter.string(
                        fromByteCount: Int64(ProcessInfo.processInfo.physicalMemory), countStyle: .memory
                    ))
                    LabeledContent("device.cpu", value: ProcessInfo.processInfo.processorCount.formatted())
                }

                Section("appearance.heading") {
                    Picker("appearance.mode", selection: $appearance) {
                        Text("appearance.system").tag("system")
                        Text("appearance.light").tag("light")
                        Text("appearance.dark").tag("dark")
                    }
                }

                Section("limits.heading") {
                    Text("limits.body")
                    Text("limits.test").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("app.title")
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
        result = change.apply(
            target, read: { Double(screen.brightness) },
            write: { screen.brightness = CGFloat($0) }, equals: matches
        )
        transaction = change
        selectedScreen = change.canRestore ? screen : nil
        refresh()
    }

    private func restore() {
        guard let screen = selectedScreen else { return }
        var change = transaction
        result = change.restore(
            read: { Double(screen.brightness) },
            write: { screen.brightness = CGFloat($0) }, equals: matches
        )
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
