// SPDX-License-Identifier: GPL-3.0-only
// Backup engine (Stage 5, ADR-2-08): the single owner of backup
// creation and of SHA-256 in the app.
//
// - SHA-256: `sha256Hex(of:)` is the ONE implementation. Every other
//   digest call in the app delegates to it (`GestaltFileStore`,
//   `HistoryJournal`, `CustomizationFiles`, `SystemSettingsStore`),
//   so a digest can never silently disagree between two call sites.
// - Pre-write backup: `createPreWriteBackup` is the AppCore
//   orchestration entry point for the §3.4 rule — never write
//   without a fresh backup first. The caller passes the record to
//   `GestaltFileStore.commit(preWriteBackup:)`; commit verifies the
//   record covers the pre-write bytes and skips its internal backup
//   (no double backup). When no record is supplied, commit still
//   creates the backup itself, so the rule holds on every path.
import CryptoKit
import Foundation

enum BackupEngine {
    /// The canonical SHA-256 hex digest. The only implementation in
    /// the app; all other digest helpers delegate here.
    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Creates a fresh pre-write backup of the snapshot's current
    /// state through the store and returns its record. `reason` is
    /// the device-write reason ("Before applying" /
    /// "Before restoring"); a locally opened file always records
    /// "Before editing" with `.importedHistory` provenance, matching
    /// what `commit` used to do internally. The store verifies the
    /// backup by read-back before returning, so a returned record
    /// always covers bytes that are on disk.
    static func createPreWriteBackup(store: GestaltFileStore,
                                     snapshot: DocumentSnapshot,
                                     reason: String) async throws -> BackupRecord {
        try await store.createPreWriteBackup(snapshot, reason: reason)
    }
}
