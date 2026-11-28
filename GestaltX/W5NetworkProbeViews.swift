// SPDX-License-Identifier: GPL-3.0-only
// W5 network probe card (LilaShift 5.0.0, Wave 1: ip-tools) —
// SwiftUI display for the probe engine in W5NetworkProbe.swift:
// ping with a live RTT chart, traceroute, and egress ASN / BGP
// information from RIPEstat.
//
// The card only shows measured values. Timeouts are shown as
// timeouts (a "×" slot in the chart, never a bar), statistics
// are dashes when no reply arrived, and the ASN section states
// its online/offline state up front: offline it shows only the
// local ping/traceroute results. No full BGP AS-path map is
// built here — that is ip-tools' BGPFeature scope and is out of
// scope for this card; the egress ASN and its announced prefix
// are the honest, checkable subset.
//
// Wiring note: this card is not referenced by ContentView or
// FeatureCatalog yet. `W5Registration.swift` carries the
// directory metadata; the coordinator wires it in.
import SwiftUI
import Combine
import Network

/// Reachability from `NWPathMonitor`: drives the online/offline
/// badge of the ASN section. It reports the path state only —
/// it never claims a measurement succeeded.
final class W5ReachabilityMonitor: ObservableObject {
    @Published private(set) var isOnline = false
    @Published private(set) var hasChecked = false

    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.lilashift.w5-reachability")

    /// Starts monitoring. Safe to call again after `stop()`: a
    /// cancelled `NWPathMonitor` cannot be restarted, so a fresh
    /// one is created when the previous one was stopped.
    func start() {
        if monitor == nil {
            let created = NWPathMonitor()
            created.pathUpdateHandler = { [weak self] path in
                let online = path.status == .satisfied
                DispatchQueue.main.async {
                    self?.isOnline = online
                    self?.hasChecked = true
                }
            }
            monitor = created
        }
        monitor?.start(queue: queue)
    }

    func stop() {
        monitor?.cancel()
        monitor = nil
    }
}

/// One traceroute hop as accumulated for display: the TTL and
/// the per-probe results keyed by probe index.
struct W5TraceHopRow: Identifiable {
    let ttl: Int
    var results: [Int: W5ProbeResult]

    var id: Int { ttl }

    /// The address of the first answering probe, or `nil` when
    /// every probe timed out.
    var address: W5IPAddress? {
        results.values.compactMap(\.address).first
    }

    var reachedDestination: Bool {
        results.values.contains { $0.reachedDestination }
    }
}

/// The network probe card: ping, traceroute and egress ASN/BGP.
struct NetworkProbeCard: View {
    @StateObject private var reachability = W5ReachabilityMonitor()

    @State private var pingTarget = "1.1.1.1"
    @State private var pingCount = 10
    @State private var pingSamples: [W5PingSample] = []
    @State private var pingError: String?
    @State private var pingRunning = false
    @State private var pingTask: Task<Void, Never>?

    @State private var traceTarget = "1.1.1.1"
    @State private var traceHops: [W5TraceHopRow] = []
    @State private var traceCompletion: W5TraceCompletion?
    @State private var traceError: String?
    @State private var traceRunning = false
    @State private var traceTask: Task<Void, Never>?

    @State private var egressInfo: W5EgressInfo?
    @State private var egressError: String?
    @State private var egressLoading = false
    @State private var egressTask: Task<Void, Never>?

    private var pingStatistics: W5PingStatistics { W5PingStatistics(samples: pingSamples) }

    var body: some View {
        GlassCard(cornerRadius: GlassTokens.cardRadius, tint: GlassTokens.heroTint) {
            VStack(alignment: .leading, spacing: GlassTokens.cardSpacing) {
                HStack(spacing: GlassTokens.rowSpacing) {
                    GlassIconPedestal(systemImage: "network", tint: .gestaltAccent, size: GlassTokens.iconSize)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L("Network Probe"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text(L("Ping, traceroute and egress ASN — real measurements only."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                pingSection
                Divider()
                traceSection
                Divider()
                egressSection
                Divider()
                honestyNote
            }
        }
        .onAppear { reachability.start() }
        .onDisappear {
            stopPing()
            stopTrace()
            egressTask?.cancel()
            reachability.stop()
        }
    }

    // MARK: - Ping

    private var pingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Ping"))
                .font(.headline)
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                TextField(L("Host or IP address"), text: $pingTarget)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .disabled(pingRunning)
                if pingRunning {
                    Button(L("Stop")) { stopPing() }
                        .font(.subheadline)
                } else {
                    Button(L("Start")) { startPing() }
                        .font(.subheadline)
                        .disabled(pingTarget.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Picker(L("Count"), selection: $pingCount) {
                Text("4").tag(4)
                Text("10").tag(10)
                Text("20").tag(20)
            }
            .pickerStyle(.segmented)
            .disabled(pingRunning)
            if !pingSamples.isEmpty {
                W5RTTChartView(samples: pingSamples)
                pingStatisticsGrid
                ForEach(pingSamples.suffix(50)) { sample in
                    pingSampleRow(sample)
                }
            } else if pingRunning {
                Text(L("Waiting for replies…"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let pingError {
                Text(pingError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var pingStatisticsGrid: some View {
        let statistics = pingStatistics
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                pingStat(label: L("Min"), value: statistics.min)
                pingStat(label: L("Avg"), value: statistics.avg)
                pingStat(label: L("Max"), value: statistics.max)
            }
            HStack(spacing: 8) {
                pingStat(label: L("Jitter"), value: statistics.jitter)
                Text(L("Received") + ": \(statistics.received)/\(statistics.sent)")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Text(L("Loss") + ": \(Int((statistics.lossFraction * 100).rounded()))%")
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            }
            if statistics.received == 0, statistics.sent > 0 {
                Text(L("No replies received: no latency can be reported."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pingStat(label: String, value: TimeInterval?) -> some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value.map { W5NetworkProbeFormatting.milliseconds($0) } ?? "—")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    private func pingSampleRow(_ sample: W5PingSample) -> some View {
        HStack(spacing: 8) {
            Text("#\(sample.sequence + 1)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
            switch sample.outcome {
            case let .reply(rtt, bytes, ttl, from):
                Text(W5NetworkProbeFormatting.milliseconds(rtt))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(bytes) " + L("bytes"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let ttl {
                    Text("ttl=\(ttl)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(from.description)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            case .timeout:
                Text(L("Timeout"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case let .unreachable(code, from):
                Text(L("Unreachable") + " (\(code))")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Text(from.description)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            case let .error(error):
                Text(error.localizedDescription)
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
        }
    }

    private func startPing() {
        stopPing()
        pingSamples = []
        pingError = nil
        pingRunning = true
        let host = pingTarget
        let count = pingCount
        pingTask = Task {
            do {
                let target = try await Task.detached(priority: .userInitiated) {
                    try W5TargetResolver.resolveFirst(host: host)
                }.value
                let options = W5PingOptions(count: count, interval: 1.0, timeout: 2.0, payloadSize: 56)
                for try await sample in W5Pinger().ping(target, options: options) {
                    pingSamples.append(sample)
                }
                pingRunning = false
            } catch is CancellationError {
                pingRunning = false
            } catch let caught as W5NetError {
                pingError = caught.localizedDescription
                pingRunning = false
            } catch {
                pingError = error.localizedDescription
                pingRunning = false
            }
        }
    }

    private func stopPing() {
        pingTask?.cancel()
        pingTask = nil
        pingRunning = false
    }

    // MARK: - Traceroute

    private var traceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Traceroute"))
                .font(.headline)
                .foregroundStyle(.primary)
            HStack(spacing: 8) {
                TextField(L("Host or IP address"), text: $traceTarget)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .disabled(traceRunning)
                if traceRunning {
                    Button(L("Stop")) { stopTrace() }
                        .font(.subheadline)
                } else {
                    Button(L("Start")) { startTrace() }
                        .font(.subheadline)
                        .disabled(traceTarget.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            ForEach(traceHops) { hop in
                traceHopRow(hop)
            }
            if let traceCompletion {
                Text(traceCompletionSummary(traceCompletion))
                    .font(.subheadline)
                    .foregroundStyle(.primary)
            } else if traceRunning, traceHops.isEmpty {
                Text(L("Waiting for hops…"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let traceError {
                Text(traceError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func traceHopRow(_ hop: W5TraceHopRow) -> some View {
        HStack(spacing: 8) {
            Text("\(hop.ttl)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
            Text(hop.address?.description ?? "*")
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
            ForEach(0..<3, id: \.self) { index in
                if let result = hop.results[index] {
                    if let rtt = result.rtt {
                        Text(W5NetworkProbeFormatting.milliseconds(rtt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("*")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if hop.reachedDestination {
                Text(L("Destination"))
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
    }

    private func traceCompletionSummary(_ completion: W5TraceCompletion) -> String {
        switch completion {
        case .reachedDestination(let hops):
            return L("Reached the destination in") + " \(hops) " + L("hops.")
        case .unreachable(let hop, let code):
            return L("Destination unreachable at hop") + " \(hop)" + " (\(code))."
        case .maxHopsExceeded:
            return L("Maximum hops reached without arriving at the destination.")
        }
    }

    private func startTrace() {
        stopTrace()
        traceHops = []
        traceCompletion = nil
        traceError = nil
        traceRunning = true
        let host = traceTarget
        traceTask = Task {
            do {
                let target = try await Task.detached(priority: .userInitiated) {
                    try W5TargetResolver.resolveFirst(host: host)
                }.value
                let options = W5TraceOptions(maxHops: 30, probesPerHop: 3, timeout: 2.0)
                for try await event in W5Tracer().trace(target, options: options) {
                    switch event {
                    case let .probe(ttl, index, result):
                        if let rowIndex = traceHops.firstIndex(where: { $0.ttl == ttl }) {
                            traceHops[rowIndex].results[index] = result
                        } else {
                            traceHops.append(W5TraceHopRow(ttl: ttl, results: [index: result]))
                        }
                    case .hopFinished:
                        break
                    case let .finished(completion):
                        traceCompletion = completion
                    }
                }
                traceRunning = false
            } catch is CancellationError {
                traceRunning = false
            } catch let caught as W5NetError {
                traceError = caught.localizedDescription
                traceRunning = false
            } catch {
                traceError = error.localizedDescription
                traceRunning = false
            }
        }
    }

    private func stopTrace() {
        traceTask?.cancel()
        traceTask = nil
        traceRunning = false
    }

    // MARK: - Egress ASN / BGP

    private var egressSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(L("Egress ASN / BGP"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Text(egressOnlineLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(reachability.isOnline ? .green : .secondary)
            }
            Text(L("Your public IP and the network (ASN) that announces it, from RIPEstat. Online only."))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Button(egressLoading ? L("Loading…") : L("Look Up Egress Info")) {
                    fetchEgress()
                }
                .font(.subheadline)
                .disabled(egressLoading || (reachability.hasChecked && !reachability.isOnline))
                if let info = egressInfo {
                    Text(L("Updated") + ": " + info.fetchedAt.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if reachability.hasChecked, !reachability.isOnline {
                Text(L("Offline: only local ping and traceroute results are shown."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let info = egressInfo {
                egressRow(label: L("Public IP"), value: info.publicIP, monospaced: true)
                if let prefix = info.prefix {
                    egressRow(label: L("Announced Prefix"), value: prefix, monospaced: true)
                }
                if info.origins.isEmpty {
                    Text(L("No origin ASN reported for this IP."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(info.origins, id: \.asn) { origin in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text("AS\(origin.asn)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(origin.holder ?? L("Holder unknown"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            if let announced = origin.announced {
                                Text(announced ? L("Announced in BGP") : L("Not announced in BGP"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if !egressLoading, egressError == nil {
                Text(L("No egress information yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let egressError {
                Text(egressError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private var egressOnlineLabel: String {
        guard reachability.hasChecked else { return L("Checking…") }
        return reachability.isOnline ? L("Online") : L("Offline")
    }

    private func egressRow(label: String, value: String, monospaced: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label + ":")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .subheadline.monospaced() : .subheadline)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
        }
    }

    private func fetchEgress() {
        egressTask?.cancel()
        egressError = nil
        egressLoading = true
        egressTask = Task {
            do {
                let info = try await W5RIPEstatClient().egressInfo()
                egressInfo = info
                egressLoading = false
            } catch is CancellationError {
                egressLoading = false
            } catch let caught as W5NetError {
                egressError = caught.localizedDescription
                egressLoading = false
            } catch {
                egressError = error.localizedDescription
                egressLoading = false
            }
        }
    }

    // MARK: - Honesty note

    private var honestyNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L("Unprivileged ICMP needs no entitlement, but whether the iOS sandbox allows it on this iOS version must be verified on a real device. Timeouts and failures are shown as-is."))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(L("Pinging a LAN address may ask for local-network permission. A full BGP AS-path map is not part of this card."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - RTT chart

/// A bar chart of ping round-trip times. One bar per reply,
/// scaled to the largest reply in the run; a timeout is a "×"
/// slot with no bar, so a lost probe can never be mistaken for
/// a fast one. The chart shows at most the latest 50 samples.
struct W5RTTChartView: View {
    let samples: [W5PingSample]

    private var shown: [W5PingSample] { Array(samples.suffix(50)) }

    private var maxRTT: TimeInterval {
        shown.compactMap(\.rtt).max() ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(shown) { sample in
                    if let rtt = sample.rtt, maxRTT > 0 {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(rttColor(rtt))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(4, CGFloat(rtt / maxRTT) * 64))
                    } else {
                        Text("×")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .frame(height: 64, alignment: .bottom)
                    }
                }
            }
            .frame(height: 64)
            HStack(spacing: 8) {
                Text(L("RTT chart"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if maxRTT > 0 {
                    Text(L("Max") + ": " + W5NetworkProbeFormatting.milliseconds(maxRTT))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("× = " + L("timeout"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func rttColor(_ rtt: TimeInterval) -> Color {
        if rtt < 0.05 { return .green }
        if rtt < 0.15 { return .orange }
        return .red
    }
}

// MARK: - Formatting

/// Shared number formatting for the probe card. Kept in one
/// place so the statistics grid, sample rows and chart agree.
enum W5NetworkProbeFormatting {
    /// Seconds as milliseconds with one decimal, e.g. "12.3 ms".
    static func milliseconds(_ seconds: TimeInterval) -> String {
        String(format: "%.1f ms", seconds * 1000)
    }
}
