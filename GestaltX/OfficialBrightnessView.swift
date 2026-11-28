// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UIKit
import Combine
import Foundation

@MainActor
struct OfficialBrightnessView: View {
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @State private var transaction = OfficialBrightnessTransaction<Double>()
    @State private var selectedScreen: UIScreen?
    @State private var observed: Double?
    @State private var requested = 0.5
    @State private var result: OfficialBrightnessTransaction<Double>.Result?
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
                        LabeledContent(label("screen.actual"), value: observed.formatted(.percent.precision(.fractionLength(1))))
                    } else {
                        Text(verbatim: label(isPhysicalDevice ? "screen.unavailable" : "screen.physicalOnly"))
                            .foregroundStyle(.secondary)
                    }

                    if observed != nil && !transaction.canRestore {
                        LabeledContent(label("screen.target"), value: requested.formatted(.percent))
                        Slider(value: $requested, in: 0.15...1, step: 0.01) {
                            Text(verbatim: label("screen.target"))
                        }
                        Button(label("screen.apply"), systemImage: "sun.max") {
                            confirming = true
                        }
                    }

                    if transaction.canRestore {
                        Button(label("screen.restore"), systemImage: "arrow.uturn.backward") { restore() }
                        if result == .externallyChanged || result == .restoreUnverified {
                            Button(label("screen.discard"), systemImage: "xmark.circle") {
                                transaction.discard()
                                selectedScreen = nil
                                result = nil
                                refresh()
                            }
                        }
                    }

                    if let result {
                        Text(verbatim: status(result)).font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text(verbatim: label("screen.heading"))
                } footer: {
                    Text(verbatim: label("screen.footer"))
                    Text(verbatim: label("limits.test"))
                }

            }
            .navigationTitle(label("screen.heading"))
            .alert(label("screen.confirmTitle"), isPresented: $confirming) {
                Button(label("screen.confirmWrite")) { apply() }
                Button(label("common.cancel"), role: .cancel) {}
            } message: {
                Text(verbatim: label("screen.confirmBody"))
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
            .onDisappear {
                if transaction.canRestore { restore() }
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

    private func status(_ result: OfficialBrightnessTransaction<Double>.Result) -> String {
        switch result {
        case .applied: label("status.applied")
        case .restored: label("status.restored")
        case .unchanged: label("status.unchanged")
        case .busy: label("status.busy")
        case .unavailable: label("status.unavailable")
        case .writeRejectedAndOriginalRecovered: label("status.rejected")
        case .restoreUnverified: label("status.unverified")
        case .externallyChanged: label("status.conflict")
        }
    }
    private func label(_ key: String) -> String {
        let id = locale.identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        let isSimplifiedChinese = id == "zh" || id.hasPrefix("zh-hans") || id.hasPrefix("zh-cn") || id.hasPrefix("zh-sg")
        return (isSimplifiedChinese ? Self.zh[key] : Self.en[key]) ?? key
    }

    private static let en = [
        "screen.actual": "Current UIKit reading",
        "screen.unavailable": "No active built-in display is available.",
        "screen.physicalOnly": "Brightness writes are unavailable on simulators and Mac.",
        "screen.target": "Target brightness",
        "screen.apply": "Apply to screen",
        "screen.restore": "Restore original brightness",
        "screen.discard": "Clear recovery record without changing brightness",
        "screen.heading": "Display brightness",
        "screen.footer": "Applies to the built-in display, not a permanent Settings value. The app saves the original in memory and attempts recovery when backgrounded. A lock or app termination can end the session. Use Control Center if recovery cannot be verified.",
        "limits.test": "Prerelease · Real-device validation pending.",
        "screen.confirmTitle": "Change display brightness?",
        "screen.confirmWrite": "Write and verify",
        "common.cancel": "Cancel",
        "screen.confirmBody": "The app will read the current value, save it for recovery, write the requested value, then read it back from UIKit.",
        "status.applied": "UIKit readback matched the target.",
        "status.restored": "UIKit readback matched the saved original.",
        "status.unchanged": "The read value already matched the target; nothing was written.",
        "status.busy": "Restore the previous change first.",
        "status.unavailable": "Readback is unavailable; no success was recorded.",
        "status.rejected": "Target was not confirmed; the original value was read back.",
        "status.unverified": "The expected value could not be verified; the recovery record is still available.",
        "status.conflict": "Readback diverged; the app did not overwrite the unexpected value.",
    ]
    private static let zh = [
        "screen.actual": "UIKit 当前读数",
        "screen.unavailable": "当前未找到可用的内置屏幕。",
        "screen.physicalOnly": "模拟器和 Mac 不支持本功能的亮度写入。",
        "screen.target": "目标亮度",
        "screen.apply": "应用到屏幕",
        "screen.restore": "恢复原亮度",
        "screen.discard": "清除恢复记录（不改亮度）",
        "screen.heading": "屏幕亮度",
        "screen.footer": "这会改变内置屏幕实际亮度，不会永久更改系统设置。原值在本次会话中保留，进入后台时尝试恢复。锁屏或强退可能中断会话。若无法确认恢复，请使用控制中心调整。",
        "limits.test": "预发布 · 尚未完成真机验证。",
        "screen.confirmTitle": "更改屏幕亮度？",
        "screen.confirmWrite": "写入并读回",
        "common.cancel": "取消",
        "screen.confirmBody": "应用将先读取并保存原值，再写入目标值并从 UIKit 读回。",
        "status.applied": "UIKit 读回值与目标一致。",
        "status.restored": "UIKit 读回值与保存的原值一致。",
        "status.unchanged": "当前读数与目标一致，没有写入。",
        "status.busy": "请先恢复上一次修改。",
        "status.unavailable": "无法获取读数，未记录成功。",
        "status.rejected": "未确认目标值；读回值仍是原值。",
        "status.unverified": "未能确认预期值，仍保留恢复记录。",
        "status.conflict": "读回值不一致；应用没有覆盖意外值。",
    ]
}

/// A single reversible, verified change. The caller provides the real read/write
/// implementation and must serialize every call on the device API's actor.
private struct OfficialBrightnessTransaction<Value> {
    enum Result: Equatable {
        case applied
        case restored
        case unchanged
        case busy
        case unavailable
        case writeRejectedAndOriginalRecovered
        case restoreUnverified
        case externallyChanged
    }

    private struct Snapshot {
        let original: Value
        let lastObserved: Value
    }

    private var pending: Snapshot?
    var canRestore: Bool { pending != nil }

    init() {}

    mutating func apply(
        _ target: Value,
        read: () -> Value?,
        write: (Value) -> Void,
        equals: (Value, Value) -> Bool
    ) -> Result {
        guard pending == nil else { return .busy }
        guard let original = read() else { return .unavailable }
        guard !equals(original, target) else { return .unchanged }
        // Save before the application of the requested value.
        pending = Snapshot(original: original, lastObserved: target)
        write(target)
        let observed = read()
        if let observed, equals(observed, target) {
            pending = Snapshot(original: original, lastObserved: observed)
            return .applied
        }
        if let observed, equals(observed, original) {
            pending = nil
            return .writeRejectedAndOriginalRecovered
        }
        // An unverified intermediate value is never blindly overwritten.
        return observed == nil ? .restoreUnverified : .externallyChanged
    }

    mutating func restore(
        read: () -> Value?,
        write: (Value) -> Void,
        equals: (Value, Value) -> Bool
    ) -> Result {
        guard let snapshot = pending else { return .unchanged }
        guard let current = read() else { return .unavailable }
        if equals(current, snapshot.original) {
            pending = nil
            return .restored
        }
        guard equals(current, snapshot.lastObserved) else { return .externallyChanged }
        write(snapshot.original)
        guard let actual = read(), equals(actual, snapshot.original) else {
            return .restoreUnverified
        }
        pending = nil
        return .restored
    }

    /// Stops tracking the transaction without writing to the device.
    mutating func discard() {
        pending = nil
    }
}
