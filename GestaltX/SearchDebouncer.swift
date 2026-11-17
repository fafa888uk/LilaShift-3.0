// SPDX-License-Identifier: GPL-3.0-only
// Search debounce (Stage 3, PERFORMANCE_AUDIT P0).
//
// Typing in a catalog search used to run the full filter + sort
// pipeline on every keystroke. The debouncer holds the raw text
// and only publishes it after the user pauses, so a fast typist
// triggers one pipeline run instead of one per character.
//
// The delay is a chosen default (200ms, inside the audit's
// 150-300ms range), not a measured optimum: the optimal value is
// a Stage 9 measurement (input-to-result latency on device).
import Combine
import Foundation

/// Publishes search text after a pause in typing. Main-actor
/// isolated: submissions come from the UI thread and the published
/// value is read on the UI thread. Cancelling drops the stale
/// value — only the latest query is ever applied.
@MainActor
final class SearchDebouncer: ObservableObject {
    /// The default pause before a query is applied (200ms).
    static let defaultDelayNanoseconds: UInt64 = 200_000_000

    @Published private(set) var debounced: String = ""
    private var task: Task<Void, Never>?

    /// Submits new raw text. Any pending submission is cancelled,
    /// so only the latest text is published after the delay.
    func submit(_ text: String, delayNanoseconds: UInt64 = defaultDelayNanoseconds) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            debounced = text
        }
    }

    /// Drops any pending submission. The published value is
    /// unchanged: cancelling never applies a stale query.
    func cancel() {
        task?.cancel()
        task = nil
    }
}
