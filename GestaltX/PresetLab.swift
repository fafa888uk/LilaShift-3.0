// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Preset Lab (A24): the lab area where presets can be tried.
///
/// The Lab is a VIEW over the existing catalog, not a new staging
/// mechanism. Only capability-backed entries are stageable here:
/// groups (one-tap, AI-only, Siri AI Mode, eSIM+region) and virtual
/// entries (eSIM, region) have dedicated apply paths and are
/// excluded, so the Lab can never double-apply a group or stage a
/// virtual entry. Staging is exactly ContentView's `stage(_:for:)`
/// — `model.choices[id] = choice` — and applying is exactly
/// `model.apply()`, the existing SafePatch flow (review + backup +
/// readback). The Lab adds no write path of its own.
enum PresetLab {
    /// The entries the Lab can stage: capability-backed presets
    /// only (no groups, no virtual entries).
    static func stageableEntries(in entries: [PresetEntry] = PresetCatalog.all) -> [PresetEntry] {
        entries.filter { $0.kind == .capability }
    }

    /// Whether staging this entry needs an enable confirmation,
    /// mirroring `Capability.requiresEnableConfirmation` (only the
    /// storage preset asks, because enabling it can hide apps).
    static func requiresConfirmation(id: String) -> Bool {
        id == "storage"
    }

    /// Whether an entry is staged in the model right now (any
    /// choice other than `.keep`).
    static func isStaged(id: String, in model: GestaltManager) -> Bool {
        guard let choice = model.choices[id] else { return false }
        return choice != .keep
    }

    /// The staged choice for an entry, or `.keep` when unstaged.
    static func stagedChoice(id: String, in model: GestaltManager) -> PresetChoice {
        model.choices[id] ?? .keep
    }
}
