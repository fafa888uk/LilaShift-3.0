// SPDX-License-Identifier: GPL-3.0-only
// PerformanceMonitor tests (Stage 3, ADR-2-12).
//
// These pin the mechanism (real durations are recorded, failed work
// is not, reset clears), never a performance claim: no test asserts
// a duration is "fast", only that what was recorded is a real,
// non-negative measurement of the work that ran.
import Foundation
import XCTest
@testable import GestaltX

final class PerformanceMonitorTests: XCTestCase {
    func testSyncMeasureRecordsDuration() async {
        let monitor = PerformanceMonitor()
        let result = await monitor.measure(label: "work") { 42 }
        XCTAssertEqual(result, 42, "measure returns the work's result")
        let samples = await monitor.samples(for: "work")
        XCTAssertEqual(samples.count, 1, "One run records one sample")
        XCTAssertGreaterThanOrEqual(samples[0], 0, "A recorded duration is never negative")
    }

    func testAsyncMeasureRecordsDuration() async throws {
        let monitor = PerformanceMonitor()
        let result = await monitor.measure(label: "work") {
            try await Task.sleep(nanoseconds: 10_000_000)
            return "done"
        }
        XCTAssertEqual(result, "done", "async measure returns the work's result")
        let samples = await monitor.samples(for: "work")
        XCTAssertEqual(samples.count, 1, "One async run records one sample")
        XCTAssertGreaterThanOrEqual(samples[0], 0.005, "The sample covers at least the 10ms sleep")
    }

    func testRecordAndReset() async {
        let monitor = PerformanceMonitor()
        await monitor.record(label: "a", duration: 0.1)
        await monitor.record(label: "a", duration: 0.2)
        await monitor.record(label: "b", duration: 0.3)
        var samplesA = await monitor.samples(for: "a")
        XCTAssertEqual(samplesA, [0.1, 0.2], "Samples keep recording order")
        await monitor.reset(label: "a")
        samplesA = await monitor.samples(for: "a")
        XCTAssertEqual(samplesA, [], "Resetting one label clears only that label")
        let samplesB = await monitor.samples(for: "b")
        XCTAssertEqual(samplesB, [0.3], "Other labels are untouched")
        await monitor.reset()
        let samplesBCleared = await monitor.samples(for: "b")
        XCTAssertEqual(samplesBCleared, [], "Resetting with no label clears everything")
    }

    func testThrowingWorkIsNotRecorded() async {
        struct Boom: Error {}
        let monitor = PerformanceMonitor()
        do {
            let _: Int = try await monitor.measure(label: "work") { throw Boom() }
            XCTFail("measure must rethrow the work's error")
        } catch is Boom {
            // Expected: the error propagates.
        } catch {
            XCTFail("measure must rethrow Boom, got \(error)")
        }
        let samples = await monitor.samples(for: "work")
        XCTAssertEqual(samples, [], "Failed work is not recorded as a sample")
    }

    func testLabelsListsRecordedLabels() async {
        let monitor = PerformanceMonitor()
        let labelsBeforeRecording = await monitor.labels()
        XCTAssertEqual(labelsBeforeRecording, [], "No samples means no labels")
        await monitor.record(label: "backup", duration: 0.1)
        await monitor.record(label: "apply", duration: 0.2)
        await monitor.record(label: "backup", duration: 0.3)
        let labelsAfterRecording = await monitor.labels()
        XCTAssertEqual(labelsAfterRecording, ["apply", "backup"], "Labels are the recorded labels, sorted")
        await monitor.reset(label: "apply")
        let labelsAfterResetOne = await monitor.labels()
        XCTAssertEqual(labelsAfterResetOne, ["backup"], "Resetting a label removes it")
        await monitor.reset()
        let labelsAfterResetAll = await monitor.labels()
        XCTAssertEqual(labelsAfterResetAll, [], "Resetting everything clears the labels")
    }
}
