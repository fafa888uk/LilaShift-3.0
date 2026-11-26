// SPDX-License-Identifier: GPL-3.0-only
// SearchDebouncer tests (Stage 3).
//
// The delays here are short on purpose: the tests pin the mechanism
// (publish after a pause, latest value wins, cancel drops), not the
// 200ms production default, which is a chosen value, not a measured
// optimum (Stage 9).
import Foundation
import XCTest
@testable import GestaltX

final class SearchDebouncerTests: XCTestCase {
    @MainActor
    func testSubmitPublishesAfterDelay() async throws {
        let debouncer = SearchDebouncer()
        debouncer.submit("siri", delayNanoseconds: 50_000_000)
        XCTAssertEqual(debouncer.debounced, "", "Nothing is published before the delay")
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(debouncer.debounced, "siri", "The submitted text is published after the delay")
    }

    @MainActor
    func testLatestValueWins() async throws {
        let debouncer = SearchDebouncer()
        debouncer.submit("sir", delayNanoseconds: 100_000_000)
        try await Task.sleep(nanoseconds: 30_000_000)
        debouncer.submit("siri", delayNanoseconds: 100_000_000)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(debouncer.debounced, "siri", "Only the latest submission is published")
    }

    @MainActor
    func testCancelDropsPendingSubmission() async throws {
        let debouncer = SearchDebouncer()
        debouncer.submit("siri", delayNanoseconds: 100_000_000)
        debouncer.cancel()
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertEqual(debouncer.debounced, "", "A cancelled submission is never published")
    }

    @MainActor
    func testDefaultDelayPublishes() async throws {
        let debouncer = SearchDebouncer()
        debouncer.submit("siri")
        XCTAssertEqual(debouncer.debounced, "", "Nothing is published before the default delay")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(debouncer.debounced, "", "The default delay is longer than 100ms")
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(debouncer.debounced, "siri", "The submitted text is published after the default delay")
    }
}
