// SPDX-License-Identifier: GPL-3.0-only
import Darwin
import Dispatch
import Foundation

enum W8ResourceMetrics {
    /// Mach resident size of this process, not whole-device RAM or physical footprint.
    static func residentBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<integer_t>.stride)
        let requiredCount = count
        let result = withUnsafeMutablePointer(to: &info) { infoPointer in
            infoPointer.withMemoryRebound(to: integer_t.self, capacity: Int(requiredCount)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS, count >= requiredCount else { return nil }
        return info.resident_size
    }

    static func pressureEvents() -> AsyncStream<W8PressureLevel> {
        AsyncStream(bufferingPolicy: .bufferingNewest(12)) { continuation in
            let source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical])
            source.setEventHandler {
                if let level = W8PressureLevel(event: source.data) {
                    continuation.yield(level)
                }
            }
            continuation.onTermination = { _ in source.cancel() }
            source.activate()
        }
    }
}

enum W8PressureLevel: Equatable, Sendable {
    case normal, warning, critical

    init?(event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) { self = .critical }
        else if event.contains(.warning) { self = .warning }
        else if event.contains(.normal) { self = .normal }
        else { return nil }
    }
}

struct W8NetworkTotals: Equatable, Sendable {
    private(set) var sent: UInt64?
    private(set) var received: UInt64?

    /// Only on-network transactions count; URLSession can return cached or unknown results.
    mutating func include(isNetwork: Bool, sent: [Int64], received: [Int64]) {
        guard isNetwork else { return }
        self.sent = Self.add(sent, to: self.sent)
        self.received = Self.add(received, to: self.received)
    }

    private static func add(_ components: [Int64], to current: UInt64?) -> UInt64? {
        components.reduce(current) { total, component in
            guard component >= 0 else { return total }
            let (value, overflow) = (total ?? 0).addingReportingOverflow(UInt64(component))
            return overflow ? UInt64.max : value
        }
    }
}

/// Owned by the app scene. The lock guards the only mutable state; callbacks
/// store counts, never URLs, headers, addresses, payloads or user identifiers.
final class W8NetworkCounter: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var totals = W8NetworkTotals()

    func snapshot() -> W8NetworkTotals {
        lock.lock()
        defer { lock.unlock() }
        return totals
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        lock.lock()
        defer { lock.unlock() }
        for transaction in metrics.transactionMetrics where transaction.resourceFetchType == .networkLoad {
            totals.include(
                isNetwork: true,
                sent: [transaction.countOfRequestHeaderBytesSent, transaction.countOfRequestBodyBytesSent],
                received: [transaction.countOfResponseHeaderBytesReceived, transaction.countOfResponseBodyBytesReceived]
            )
        }
    }
}
