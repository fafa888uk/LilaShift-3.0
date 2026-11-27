// SPDX-License-Identifier: GPL-3.0-only
import Charts
import Darwin
import FoundationModels
import Network
import SwiftUI
import UIKit

struct LiveDiagnosticsView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var cpu: [Reading] = []
    @State private var memory: [Reading] = []
    @State private var receive: [Reading] = []
    @State private var transmit: [Reading] = []
    @State private var disk: DiskSpace?
    @State private var languageModelReady: Bool?
    @State private var path: NetworkPath?

    private struct Reading: Identifiable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    private struct InterfaceCounters {
        let received: UInt64
        let sent: UInt64

        static func read() -> [String: Self] {
            var first: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&first) == 0, let first else { return [:] }
            defer { freeifaddrs(first) }

            var results: [String: Self] = [:]
            var next: UnsafeMutablePointer<ifaddrs>? = first
            while let row = next {
                let interface = row.pointee
                next = interface.ifa_next
                guard let address = interface.ifa_addr, Int32(address.pointee.sa_family) == AF_LINK,
                      let name = interface.ifa_name, let data = interface.ifa_data else { continue }
                let identifier = String(cString: name)
                guard identifier.hasPrefix("en") || identifier.hasPrefix("pdp_ip") else { continue }
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                results[identifier] = Self(received: UInt64(counters.ifi_ibytes), sent: UInt64(counters.ifi_obytes))
            }
            return results
        }
    }

    private struct DiskSpace {
        let total: Int64
        let free: Int64

        init?() {
            guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
                  let total = attributes[.systemSize] as? NSNumber,
                  let free = attributes[.systemFreeSize] as? NSNumber else { return nil }
            self.total = total.int64Value
            self.free = free.int64Value
        }
    }

    private struct NetworkPath: Sendable {
        let status: String
        let interfaces: [String]
        let expensive: Bool
        let constrained: Bool

        init(_ path: NWPath) {
            switch path.status {
            case .satisfied: status = "Available"
            case .requiresConnection: status = "Requires Connection"
            case .unsatisfied: status = "Unavailable"
            @unknown default: status = "Unknown"
            }
            let names: [(NWInterface.InterfaceType, String)] = [
                (.wifi, "Wi-Fi"), (.cellular, "Cellular"), (.wiredEthernet, "Ethernet"),
                (.loopback, "Loopback"), (.other, "Other Interface")
            ]
            interfaces = names.filter { path.usesInterfaceType($0.0) }.map { $0.1 }
            expensive = path.isExpensive
            constrained = path.isConstrained
        }
    }

    var body: some View {
        List {
            Section(L("Device Overview")) {
                if let model = DeviceModelReference.name {
                    LabeledContent(L("Device Model"), value: model)
                }
                if !DeviceModelReference.identifier.isEmpty {
                    LabeledContent(L("Model Identifier"), value: DeviceModelReference.identifier)
                }
                LabeledContent(L("iOS Version"), value: UIDevice.current.systemVersion)
                LabeledContent(L("Logical CPU Cores"), value: ProcessInfo.processInfo.processorCount.formatted())
                LabeledContent(L("Physical Memory"), value: bytes(Int64(ProcessInfo.processInfo.physicalMemory)))
            }
            Section {
                if let languageModelReady {
                    LabeledContent(L("On-Device Model"), value: L(languageModelReady ? "Available" : "Unavailable"))
                } else {
                    ProgressView()
                }
            } footer: {
                Text(L("Checks whether the system language model is available to apps on this device."))
            }
            Section {
                chart("App CPU", readings: cpu, units: "%")
                chart("App Resident Memory", readings: memory, units: "MiB")
            } header: {
                Text(L("Live Performance"))
            } footer: {
                Text(L("Charts sample LilaShift while this screen is active. CPU is expressed as a percentage of one logical core."))
            }
            Section(L("Local Storage")) {
                if let disk {
                    LabeledContent(L("Capacity"), value: bytes(disk.total))
                    LabeledContent(L("Free Space"), value: bytes(disk.free))
                } else {
                    Text(L("Unavailable"))
                }
            }
            Section {
                if let path {
                    LabeledContent(L("Path Status"), value: L(path.status))
                    if !path.interfaces.isEmpty {
                        LabeledContent(L("Interface"), value: path.interfaces.map(L).joined(separator: ", "))
                    }
                    LabeledContent(L("Expensive Path"), value: L(path.expensive ? "Yes" : "No"))
                    LabeledContent(L("Low Data Mode"), value: L(path.constrained ? "Yes" : "No"))
                } else {
                    ProgressView()
                }
            } header: {
                Text(L("Network Path"))
            } footer: {
                Text(L("Reports the local network path without sending traffic to a server."))
            }
            Section {
                chart("Interface Download Rate", readings: receive, units: "KiB/s")
                chart("Interface Upload Rate", readings: transmit, units: "KiB/s")
            } header: {
                Text(L("Interface Traffic"))
            } footer: {
                Text(L("Rates come from the device’s Wi-Fi, Ethernet and cellular interface counters. They may include traffic from other apps."))
            }
        }
        .navigationTitle(L("Live Diagnostics"))
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            languageModelReady = SystemLanguageModel.default.isAvailable
            await sampleMetrics()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            path = nil
            for await snapshot in Self.networkUpdates() {
                guard !Task.isCancelled else { return }
                path = snapshot
            }
        }
    }

    private func chart(_ title: String, readings: [Reading], units: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let latest = readings.last {
                LabeledContent(L(title), value: latest.value.formatted(.number.precision(.fractionLength(1))) + " " + units)
                Chart(readings) { reading in
                    LineMark(x: .value(L("Time"), reading.date), y: .value(L(title), reading.value))
                        .foregroundStyle(Color.gestaltAccent)
                    PointMark(x: .value(L("Time"), reading.date), y: .value(L(title), reading.value))
                        .foregroundStyle(Color.gestaltAccent)
                        .symbolSize(10)
                }
                .frame(height: 84)
                .chartXAxis(.hidden)
            } else {
                LabeledContent(L(title), value: L("Waiting for a sample"))
            }
        }
    }

    @MainActor
    private func sampleMetrics() async {
        cpu.removeAll(keepingCapacity: true)
        memory.removeAll(keepingCapacity: true)
        receive.removeAll(keepingCapacity: true)
        transmit.removeAll(keepingCapacity: true)
        disk = DiskSpace()
        var previousCPU = Self.cpuTime()
        var previousCounters = InterfaceCounters.read()
        let clock = ContinuousClock()
        var previousTime = clock.now
        var sampleCount = 0
        while !Task.isCancelled {
            let now = Date()
            let time = clock.now
            let currentCPU = Self.cpuTime()
            let interval = previousTime.duration(to: time).components
            let elapsed = Double(interval.seconds) + Double(interval.attoseconds) / 1e18
            if let currentCPU, let previousCPU, elapsed >= 0.5, currentCPU >= previousCPU {
                cpu.append(Reading(date: now, value: 100 * (currentCPU - previousCPU) / elapsed))
                if cpu.count > 30 { cpu.removeFirst() }
            }
            let counters = InterfaceCounters.read()
            if elapsed >= 0.5 {
                recordTraffic(current: counters, previous: previousCounters, elapsed: elapsed, date: now)
            }
            previousCounters = counters
            previousTime = time
            previousCPU = currentCPU
            if let resident = Self.residentMemory() {
                memory.append(Reading(date: now, value: Double(resident) / 1_048_576))
                if memory.count > 30 { memory.removeFirst() }
            }
            sampleCount += 1
            if sampleCount.isMultiple(of: 5) { disk = DiskSpace() }
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
        }
    }

    private func recordTraffic(
        current: [String: InterfaceCounters], previous: [String: InterfaceCounters], elapsed: Double, date: Date
    ) {
        var received: UInt64 = 0
        var sent: UInt64 = 0
        var count = 0
        for (interface, latest) in current {
            guard let earlier = previous[interface],
                  latest.received >= earlier.received, latest.sent >= earlier.sent else { continue }
            received += latest.received - earlier.received
            sent += latest.sent - earlier.sent
            count += 1
        }
        guard count > 0 else { return }
        receive.append(Reading(date: date, value: Double(received) / elapsed / 1024))
        transmit.append(Reading(date: date, value: Double(sent) / elapsed / 1024))
        if receive.count > 30 { receive.removeFirst() }
        if transmit.count > 30 { transmit.removeFirst() }
    }

    private static func cpuTime() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }

    private static func residentMemory() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.stride)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? info.resident_size : nil
    }

    private static func networkUpdates() -> AsyncStream<NetworkPath> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield(NetworkPath($0)) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "LilaShift.NetworkPath"))
        }
    }

    private func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}
