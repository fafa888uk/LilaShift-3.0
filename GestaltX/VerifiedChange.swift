// SPDX-License-Identifier: GPL-3.0-only
/// A single reversible, verified change. The caller provides the real read/write
/// implementation and must serialize every call on the device API's actor.
struct VerifiedChange<Value> {
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
