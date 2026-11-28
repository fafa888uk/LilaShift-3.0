// SPDX-License-Identifier: GPL-3.0-only
import Charts
import Foundation
import SwiftUI

private struct W8NetworkCounterKey: EnvironmentKey {
    static let defaultValue: W8NetworkCounter? = nil
}

extension EnvironmentValues {
    var w8NetworkCounter: W8NetworkCounter? {
        get { self[W8NetworkCounterKey.self] }
        set { self[W8NetworkCounterKey.self] = newValue }
    }
}

@MainActor
struct W8ResourceMonitorView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.w8NetworkCounter) private var counter
    @State private var started: ContinuousClock.Instant?
    @State private var elapsed: Int64 = 0
    @State private var resident: UInt64?
    @State private var memoryPoints: [MemoryPoint] = []
    @State private var pressurePoints: [PressurePoint] = []
    @State private var network = W8NetworkTotals()

    private struct MemoryPoint: Identifiable {
        let at: Double
        let bytes: UInt64
        var id: Double { at }
    }

    private struct PressurePoint: Identifiable {
        let id = UUID()
        let at: Int64
        let level: W8PressureLevel
    }

    static var title: String { String(localized: "Resource Monitor", table: "W8Monitoring") }

    var body: some View {
        List {
            Section {
                LabeledContent(text("Resident memory"), value: byteText(resident))
                if !memoryPoints.isEmpty {
                    Chart(memoryPoints) { point in
                        LineMark(
                            x: .value(text("Session seconds"), point.at),
                            y: .value(text("Memory in MiB"), Double(point.bytes) / 1_048_576)
                        )
                        .foregroundStyle(Color.accentColor)
                        PointMark(
                            x: .value(text("Session seconds"), point.at),
                            y: .value(text("Memory in MiB"), Double(point.bytes) / 1_048_576)
                        )
                        .foregroundStyle(Color.accentColor)
                    }
                    .frame(height: 146)
                }
            } header: {
                Text("App memory", tableName: "W8Monitoring")
            } footer: {
                Text("Current process only. Samples about every two seconds while this page is active.", tableName: "W8Monitoring")
            }

            Section {
                if pressurePoints.isEmpty {
                    Text("No memory pressure event observed yet.", tableName: "W8Monitoring")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pressurePoints.reversed()) { point in
                        LabeledContent(pressureText(point.level), value: secondsText(point.at))
                    }
                }
            } header: {
                Text("Memory pressure events", tableName: "W8Monitoring")
            } footer: {
                Text("The latest 12 observed changes during foreground monitoring; an empty list does not mean normal.", tableName: "W8Monitoring")
            }

            Section {
                LabeledContent(text("Sent"), value: byteText(network.sent))
                LabeledContent(text("Received"), value: byteText(network.received))
            } header: {
                Text("Measured network traffic", tableName: "W8Monitoring")
            } footer: {
                Text("Since app launch, for RIPEstat HTTPS diagnostics only. Includes measured HTTP headers and bodies. Does not include cache hits, ping, traceroute, or other apps.", tableName: "W8Monitoring")
            }

            Section {
                LabeledContent(text("Monitor session"), value: secondsText(elapsed))
            } footer: {
                Text("Elapsed time since opening this monitor. It is not system uptime.", tableName: "W8Monitoring")
            }
        }
        .navigationTitle(Self.title)
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            if started == nil { started = .now }
            memoryPoints.removeAll(keepingCapacity: true)
            await sample()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            for await level in W8ResourceMetrics.pressureEvents() {
                guard !Task.isCancelled else { return }
                pressurePoints.append(.init(at: secondsSinceStart().components.seconds, level: level))
                if pressurePoints.count > 12 { pressurePoints.removeFirst() }
            }
        }
    }

    private func sample() async {
        let clock = ContinuousClock()
        while !Task.isCancelled {
            let duration = secondsSinceStart()
            elapsed = duration.components.seconds
            network = counter?.snapshot() ?? W8NetworkTotals()
            let value = W8ResourceMetrics.residentBytes()
            resident = value
            if let value {
                let time = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
                memoryPoints.append(.init(at: time, bytes: value))
                if memoryPoints.count > 60 { memoryPoints.removeFirst() }
            } else {
                memoryPoints.removeAll(keepingCapacity: true)
            }
            do {
                try await clock.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
    }

    private func secondsSinceStart() -> Duration {
        guard let started else { return .zero }
        return started.duration(to: .now)
    }

    private func byteText(_ bytes: UInt64?) -> String {
        guard let bytes else { return text("Not measured") }
        return ByteCountFormatter.string(fromByteCount: Int64(clamping: bytes), countStyle: .binary)
    }

    private func secondsText(_ seconds: Int64) -> String {
        seconds.formatted(.number) + " " + text("sec")
    }

    private func pressureText(_ level: W8PressureLevel) -> String {
        switch level {
        case .normal: text("Normal")
        case .warning: text("Warning")
        case .critical: text("Critical")
        }
    }

    private func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "W8Monitoring")
    }
}
