// SPDX-License-Identifier: GPL-3.0-only
// Real performance measurement (Stage 3, ADR-2-12).
//
// Records real durations, nothing else: no estimated FPS, no
// improvement percentages, no invented numbers. Stage 3 is only the
// stake — the monitor and its tests — wiring it into views is Stage 9,
// where the numbers it reports are the evidence for the audit's
// TO-MEASURE items. There is no shared singleton (ADR-2-04 allows
// only SharedApplicationInventory.shared); callers own an instance.
import Foundation

actor PerformanceMonitor {
    private var recorded: [String: [TimeInterval]] = [:]

    /// Runs the work and records how long it took, in seconds.
    func measure<T>(label: String, work: () throws -> T) rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = try work()
        record(label: label, duration: durationSince(start))
        return result
    }

    /// Async variant of `measure(label:work:)`.
    func measure<T>(label: String, work: () async throws -> T) async rethrows -> T {
        let start = DispatchTime.now().uptimeNanoseconds
        let result = try await work()
        record(label: label, duration: durationSince(start))
        return result
    }

    /// Records one observed duration, in seconds.
    func record(label: String, duration: TimeInterval) {
        recorded[label, default: []].append(duration)
    }

    /// The recorded durations for a label, in recording order.
    func samples(for label: String) -> [TimeInterval] {
        recorded[label] ?? []
    }

    /// Drops the samples for one label, or all labels when nil.
    func reset(label: String? = nil) {
        if let label { recorded[label] = nil } else { recorded.removeAll() }
    }

    private func durationSince(_ start: UInt64) -> TimeInterval {
        TimeInterval(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000
    }
}
