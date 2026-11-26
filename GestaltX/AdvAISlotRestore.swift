// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Restores the two AdvAI CacheData slots (#178/#266) in a working
/// document to the values recorded in a snapshot (Stage 5, ADR-2-02).
///
/// The guards mirror `fixAIBaseline`: an original that cannot be
/// parsed is skipped, never guessed; an original equal to the current
/// value is skipped (no false diff); a write error is reported as a
/// failed outcome and does not stop the other slot. This helper is
/// the single place that writes slots back — both one-tap restore
/// paths (`restoreChinaUnlock`, `restoreChinaAIOnly`) call it, so the
/// two paths cannot drift apart.
///
/// `layout` is the explicit layout for tests; production passes `nil`
/// and each slot read resolves the layout from the documents.
enum AdvAISlotRestore {
    enum Outcome: Equatable, Sendable {
        /// The slot was written back to its recorded original.
        case restored(key: String, original: Bool)
        /// The original equals the current value: nothing to do.
        case skippedUnchanged(key: String)
        /// The original or the current value could not be parsed
        /// (unresolvable layout or invalid bytes): left alone.
        case skippedUnresolvable(key: String)
        /// The write threw: the reason is logged by the caller and
        /// the other slot is still attempted.
        case failed(key: String, reason: String)

        var isRestored: Bool {
            if case .restored = self { return true }
            return false
        }
    }

    static func restore(in document: inout GestaltDocument, from snapshot: GestaltDocument,
                        using layout: MobileGestaltCacheLayout? = nil) -> [Outcome] {
        var outcomes: [Outcome] = []
        for key in [DeviceCacheOptions.personalTranslatorKey, DeviceCacheOptions.audioIntelligenceKey] {
            guard let original = DeviceCacheOptions.advAISlotValue(key, in: snapshot, using: layout) else {
                outcomes.append(.skippedUnresolvable(key: key))
                continue
            }
            guard let current = DeviceCacheOptions.advAISlotValue(key, in: document, using: layout) else {
                outcomes.append(.skippedUnresolvable(key: key))
                continue
            }
            guard original != current else {
                outcomes.append(.skippedUnchanged(key: key))
                continue
            }
            do {
                try document.setAdvAISlot(key, value: original, using: layout)
                outcomes.append(.restored(key: key, original: original))
            } catch {
                outcomes.append(.failed(key: key, reason: error.localizedDescription))
            }
        }
        return outcomes
    }
}
