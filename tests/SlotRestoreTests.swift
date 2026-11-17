// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

/// Stage 5 (ADR-2-02) slot-restore tests.
///
/// The offline profile has no AdvAI slot indices, so the slot
/// machinery is exercised with an explicit layout scanned from
/// fabricated descriptors (the `CacheLayoutGatingTests.table`
/// pattern): audioIntelligence #178 at index 4, personalTranslator
/// #266 at index 5, on a 6-slot layout. Production callers pass no
/// layout and resolve it from the device; tests pass the scanned
/// layout explicitly. No device or signing is needed.
final class SlotRestoreTests: XCTestCase {
    static let uuid = "A4A4A4A4-1111-2222-3333-123456789ABC"

    static func put<T: FixedWidthInteger>(_ value: T, into data: inout Data, at offset: Int) {
        var little = value.littleEndian
        withUnsafeBytes(of: &little) { data.replaceSubrange(offset..<(offset + $0.count), with: $0) }
    }

    /// Scans a 6-slot layout with the two AdvAI slots resolved
    /// (audio #178 = index 4, translator #266 = index 5).
    static func scannedLayout() throws -> MobileGestaltCacheLayout {
        let address: UInt64 = 0x180100000
        let keys = ["AAAAAAAAAAAAAAAAAAAAAA", DeviceCacheOptions.greenTeaKey,
                    DeviceCacheOptions.notGreenTeaKey, DeviceCacheOptions.wapiKey,
                    DeviceCacheOptions.audioIntelligenceKey, DeviceCacheOptions.personalTranslatorKey]
        var strings = Data()
        strings.append(contentsOf: (uuid + "\0").utf8)
        var pointers: [UInt64] = []
        for key in keys {
            pointers.append(address + UInt64(strings.count))
            strings.append(contentsOf: (key + "\0").utf8)
        }
        var descriptors = Data(repeating: 0, count: keys.count * 64)
        for i in keys.indices {
            put(pointers[i], into: &descriptors, at: i * 64)
            put(Int16(i), into: &descriptors, at: i * 64 + 0x3A)
            put(UInt32(11), into: &descriptors, at: i * 64 + 0x3C)
        }
        return try MobileGestaltCacheLayout.scan(strings: strings, stringAddress: address, constants: [descriptors])
    }

    /// A document on the scanned layout. The slot bytes carry the
    /// given values; validity bytes are set for both slots unless
    /// disabled (an unset validity byte makes the slot unparseable).
    /// Defaults are the interesting case for ADR-2-02: the originals
    /// differ from the native baselines (#266 = 0, #178 = 1).
    static func document(audio: Bool = true, translator: Bool = false,
                         audioValid: Bool = true, translatorValid: Bool = true,
                         productType: String = "iPhone18,1") throws -> GestaltDocument {
        let layout = try scannedLayout()
        var cache = Data(count: layout.byteCount)
        cache[layout.greenTeaOffset] = 1
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        cache[layout.validityOffset(for: 4)] = audioValid ? 1 : 0
        cache[layout.validityOffset(for: 5)] = translatorValid ? 1 : 0
        cache[4 * 8] = audio ? 1 : 0
        cache[5 * 8] = translator ? 1 : 0
        return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": uuid,
            "CacheData": cache,
            "CacheExtra": [GestaltKeys.productType: productType, GestaltKeys.regionCode: "CH"],
        ], format: .binary, options: 0))
    }

    /// A document on the offline profile (no AdvAI slot indices),
    /// mirroring the AIBaselineFixTests fixture: eSIM restricted,
    /// region CH, Air model number.
    static func offlineDocument(productType: String = "iPhone18,1") throws -> GestaltDocument {
        let layout = MobileGestaltCacheLayout.originalProfile
        var cache = Data(count: layout.byteCount)
        cache[layout.greenTeaOffset] = 1
        cache[layout.notGreenTeaOffset] = 0
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": layout.uuid,
            "CacheData": cache, "CacheExtra": [
                GestaltKeys.productType: productType,
                GestaltKeys.regionCode: "CH",
                GestaltKeys.regionInfo: "CH/A",
                GestaltKeys.legacyRegionInfo: "CH/A",
                GestaltKeys.modelNumber: "A3518",
            ],
        ], format: .binary, options: 0))
    }

    @MainActor
    func manager(for document: GestaltDocument) throws -> GestaltManager {
        let snapshot = DocumentSnapshot(data: try document.encoded(), document: document,
                                        source: .local, name: "fixture")
        let manager = GestaltManager()
        manager.loadSnapshotForTests(snapshot)
        return manager
    }

    /// A manager loaded with the given document as its snapshot and
    /// working document (mirrors the AIBaselineFixTests fixture).
    @MainActor
    func manager(for document: GestaltDocument) throws -> GestaltManager {
        let snapshot = DocumentSnapshot(data: try document.encoded(), document: document,
                                        source: .local, name: "fixture")
        let manager = GestaltManager()
        manager.loadSnapshotForTests(snapshot)
        return manager
    }

    // MARK: - U-2-3: snapshot.document retains the original CacheData bytes

    func testSnapshotDocumentRetainsOriginalSlotBytes() throws {
        let layout = try Self.scannedLayout()
        // Native hardware whose slot originals differ from the baselines.
        let snapshot = try Self.document(audio: true, translator: false)
        XCTAssertEqual(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.audioIntelligenceKey, in: snapshot, using: layout), true,
                       "U-2-3: the snapshot document's #178 byte reads as the recorded original (true)")
        XCTAssertEqual(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.personalTranslatorKey, in: snapshot, using: layout), false,
                       "U-2-3: the snapshot document's #266 byte reads as the recorded original (false)")
    }

    // MARK: - OriginalValues.advAISlots recording

    func testSlotOriginalsRecordedWhenChanged() throws {
        let layout = try Self.scannedLayout()
        let before = try Self.document(audio: true, translator: false)
        let after = try Self.document(audio: false, translator: true)
        let recorded = DocumentSnapshot.slotOriginals(before: before, after: after, using: layout)
        XCTAssertEqual(recorded[DeviceCacheOptions.audioIntelligenceKey], true,
                       "Changed #178 records its original value (true)")
        XCTAssertEqual(recorded[DeviceCacheOptions.personalTranslatorKey], false,
                       "Changed #266 records its original value (false)")
    }

    func testSlotOriginalsNotRecordedWhenEqual() throws {
        let layout = try Self.scannedLayout()
        let before = try Self.document(audio: true, translator: false)
        let after = try Self.document(audio: true, translator: false)
        XCTAssert(DocumentSnapshot.slotOriginals(before: before, after: after, using: layout).isEmpty,
                  "Equal slots are not a change: nothing is recorded")
    }

    func testSlotOriginalsNotRecordedWhenUnresolvable() throws {
        // The offline profile has no AdvAI slot indices: both sides
        // are unreadable even when the raw bytes differ, so nothing
        // is recorded — never guessed.
        let layout = MobileGestaltCacheLayout.originalProfile
        func offlineDocument(slotByte: UInt8) throws -> GestaltDocument {
            var cache = Data(count: layout.byteCount)
            cache[layout.greenTeaOffset] = 1
            cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
            cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
            cache[4 * 8] = slotByte
            cache[5 * 8] = slotByte == 0 ? 1 : 0
            return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
                "CacheVersion": "24C5037i", "CacheUUID": layout.uuid,
                "CacheData": cache,
                "CacheExtra": [GestaltKeys.productType: "iPhone18,1"],
            ], format: .binary, options: 0))
        }
        let before = try offlineDocument(slotByte: 1)
        let after = try offlineDocument(slotByte: 0)
        XCTAssertNil(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.audioIntelligenceKey, in: before, using: layout),
                     "The offline layout cannot resolve #178")
        XCTAssert(DocumentSnapshot.slotOriginals(before: before, after: after, using: layout).isEmpty,
                  "Unresolvable slots record nothing, even when the raw bytes differ")
    }

    func testSlotOriginalsFirstRecordingWins() throws {
        let layout = try Self.scannedLayout()
        let before = try Self.document(audio: true, translator: false)
        let after = try Self.document(audio: false, translator: true)
        let previously: [String: Bool] = [DeviceCacheOptions.audioIntelligenceKey: false]
        let recorded = DocumentSnapshot.slotOriginals(before: before, after: after,
                                                      previouslyRecorded: previously, using: layout)
        XCTAssertEqual(recorded[DeviceCacheOptions.audioIntelligenceKey], false,
                       "A previously recorded original is kept: the first recording wins")
        XCTAssertEqual(recorded[DeviceCacheOptions.personalTranslatorKey], false,
                       "The other slot is still recorded from this comparison")
    }

    func testRecordingOriginalsSkipsUnresolvableSlots() throws {
        let layout = try Self.scannedLayout()
        let before = try Self.document(audio: true, translator: false)
        let after = try Self.document(audio: false, translator: true)
        let snapshot = DocumentSnapshot(data: try before.encoded(), document: before,
                                        source: .local, name: "fixture")
        let originals = snapshot.recordingOriginals(to: after)
        // recordingOriginals resolves without an explicit layout, so
        // the offline profile cannot resolve the slots; assert the
        // merge path instead with the explicit-layout helper.
        XCTAssert(originals.advAISlots.isEmpty,
                  "Without a resolvable layout, recordingOriginals records no slot originals (never guessed)")
        let direct = DocumentSnapshot.slotOriginals(before: before, after: after, using: layout)
        XCTAssertEqual(direct.count, 2, "With a resolvable layout both slot originals are recorded")
    }

    // MARK: - Persistence codec validation

    func testDecodeAdvAISlots() throws {
        let valid: [String: Bool] = [DeviceCacheOptions.audioIntelligenceKey: true,
                                     DeviceCacheOptions.personalTranslatorKey: false]
        XCTAssertEqual(try OriginalValues.decodeAdvAISlots(valid), valid, "A valid slot-originals dict decodes")
        XCTAssertEqual(try OriginalValues.decodeAdvAISlots(nil), [:], "A missing entry decodes as empty")
        XCTAssertThrowsError(try OriginalValues.decodeAdvAISlots(["unknown-key": true]),
                             "An unknown slot key is corruption, never a future slot")
        XCTAssertThrowsError(try OriginalValues.decodeAdvAISlots([DeviceCacheOptions.audioIntelligenceKey: "yes"]),
                             "A non-Bool slot value is corruption")
    }

    // MARK: - MGDatabase restorable flip (ADR-2-02 gap closed)

    func testSlotRecordsAreRestorable() {
        for key in [DeviceCacheOptions.audioIntelligenceKey, DeviceCacheOptions.personalTranslatorKey] {
            let record = MGDatabase.record(forKey: key)
            XCTAssertNotNil(record, "Slot key \(key) is in the database")
            XCTAssertEqual(record?.restorable, true,
                           "Slot \(key) is restorable now that Stage 5 records its original")
        }
    }

    // MARK: - AdvAISlotRestore helper (ADR-2-02 exact behavior)

    func testSlotRestoreWritesOriginalsBack() throws {
        let layout = try Self.scannedLayout()
        let snapshot = try Self.document(audio: true, translator: false)
        var working = try Self.document(audio: false, translator: true)
        let outcomes = AdvAISlotRestore.restore(in: &working, from: snapshot, using: layout)
        XCTAssertEqual(outcomes, [
            .restored(key: DeviceCacheOptions.personalTranslatorKey, original: false),
            .restored(key: DeviceCacheOptions.audioIntelligenceKey, original: true),
        ], "Both slots are written back to their snapshot originals")
        XCTAssertEqual(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.audioIntelligenceKey, in: working, using: layout), true,
                       "#178 is back to its original (true)")
        XCTAssertEqual(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.personalTranslatorKey, in: working, using: layout), false,
                       "#266 is back to its original (false)")
    }

    func testSlotRestoreSkipsUnchanged() throws {
        let layout = try Self.scannedLayout()
        let snapshot = try Self.document(audio: true, translator: false)
        var working = try Self.document(audio: true, translator: false)
        let outcomes = AdvAISlotRestore.restore(in: &working, from: snapshot, using: layout)
        XCTAssert(outcomes.allSatisfy { if case .skippedUnchanged = $0 { return true }; return false },
                  "Equal slots are skipped, not rewritten")
    }

    func testSlotRestoreSkipsUnparseableOriginal() throws {
        let layout = try Self.scannedLayout()
        // The snapshot's #178 has no validity byte: its original
        // cannot be parsed, so it is skipped, never guessed. #266
        // still restores.
        let snapshot = try Self.document(audio: true, translator: false, audioValid: false)
        var working = try Self.document(audio: false, translator: true)
        let outcomes = AdvAISlotRestore.restore(in: &working, from: snapshot, using: layout)
        XCTAssert(outcomes.contains(.skippedUnresolvable(key: DeviceCacheOptions.audioIntelligenceKey)),
                  "An unparseable original is skipped")
        XCTAssert(outcomes.contains(.restored(key: DeviceCacheOptions.personalTranslatorKey, original: false)),
                  "The other slot still restores when one is unparseable")
        XCTAssertEqual(DeviceCacheOptions.advAISlotValue(DeviceCacheOptions.personalTranslatorKey, in: working, using: layout), false,
                       "#266 was restored despite #178 being unparseable")
    }

    func testSlotRestoreSkipsUnresolvableLayout() throws {
        let layout = MobileGestaltCacheLayout.originalProfile
        let snapshot = try Self.offlineDocument()
        var working = try Self.offlineDocument()
        let outcomes = AdvAISlotRestore.restore(in: &working, from: snapshot, using: layout)
        XCTAssert(outcomes.allSatisfy { if case .skippedUnresolvable = $0 { return true }; return false },
                  "An unresolvable layout skips both slots without crashing")
    }

    // MARK: - Manager wiring (offline: slots cannot resolve, so the
    // restore must be a safe no-op for slots and still restore the
    // CacheExtra parts; the slot logic itself is covered above and
    // on device in Stage 11)

    @MainActor
    func testRestoreChinaUnlockSkipsSlotsOffline() throws {
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let manager = try manager(for: Self.offlineDocument())
        let before = try XCTUnwrap(manager.working, "A working document is loaded")
        XCTAssert(manager.restoreChinaUnlock(), "One-tap restore stages on native hardware offline")
        let after = try XCTUnwrap(manager.working, "A working document is loaded")
        XCTAssert(after.matches(before), "Offline: the working document is unchanged (no slot resolves)")
        XCTAssert(ChinaUnlock.aiCapabilityIDs.allSatisfy { manager.choices[$0] == .disable },
                  "All AI choices are set to restore (.disable)")
        XCTAssert(!manager.logs.contains(where: { $0.contains("[restore] slot") }),
                  "No slot failure is logged when both slots are skipped as unresolvable")
    }

    @MainActor
    func testRestoreChinaAIOnlySkipsSlotsOffline() throws {
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let manager = try manager(for: Self.offlineDocument())
        let before = try XCTUnwrap(manager.working, "A working document is loaded")
        XCTAssert(manager.restoreChinaAIOnly(), "AI-only restore stages on native hardware offline")
        let after = try XCTUnwrap(manager.working, "A working document is loaded")
        XCTAssert(after.matches(before), "Offline: the working document is unchanged (no slot resolves)")
        XCTAssert(ChinaUnlock.aiCapabilityIDs.allSatisfy { manager.choices[$0] == .disable },
                  "All AI choices are set to restore (.disable)")
    }

    // MARK: - RestoreAction mapping for slots

    func testSlotRestoreActionFollowsStagingGroup() {
        func change(featureID: String) -> RecordedChange {
            RecordedChange(id: UUID(), date: Date(), deviceID: "test", osBuild: "",
                           featureID: featureID, key: DeviceCacheOptions.audioIntelligenceKey,
                           layer: .cacheData, original: .bool(true), new: .bool(false),
                           backupProvenance: .preModification, verified: true)
        }
        XCTAssertEqual(RestoreAction.forChange(change(featureID: "preset.oneTap")), .chinaUnlock,
                       "A one-tap slot change restores through the one-tap path")
        XCTAssertEqual(RestoreAction.forChange(change(featureID: "preset.aiOnly")), .aiOnly,
                       "An AI-only slot change restores through the AI-only path")
        if case .previewOnly = RestoreAction.forChange(change(featureID: "something-else")) {
            // Expected: no known group, preview only.
        } else {
            XCTFail("A slot change with no known staging group must stay preview-only")
        }
    }

    // MARK: - ModifiedValues slot rows

    func testModifiedValuesShowsSlotRows() throws {
        let layout = try Self.scannedLayout()
        let current = try Self.document(audio: false, translator: true)
        var snapshot = DocumentSnapshot(data: try current.encoded(), document: current,
                                        source: .local, name: "fixture",
                                        advAISlotOriginals: [
                                            DeviceCacheOptions.audioIntelligenceKey: true,
                                            DeviceCacheOptions.personalTranslatorKey: false,
                                        ])
        let report = ModifiedValues.report(for: snapshot, using: layout)
        guard case .compared(let rows) = report else {
            return XCTFail("A snapshot with recorded slot originals compares, it does not report no-originals")
        }
        XCTAssertEqual(rows.count, 2, "Both changed slots appear as rows")
        XCTAssert(rows.contains { $0.key == DeviceCacheOptions.audioIntelligenceKey && $0.originalText == "true" && $0.currentText == "false" },
                  "#178 row shows original true → current false")
        XCTAssert(rows.contains { $0.key == DeviceCacheOptions.personalTranslatorKey && $0.originalText == "false" && $0.currentText == "true" },
                  "#266 row shows original false → current true")

        // Equal slots produce no rows, and the report still compares
        // (the originals exist, so "no modification found" is honest).
        snapshot = DocumentSnapshot(data: try current.encoded(), document: current,
                                    source: .local, name: "fixture",
                                    advAISlotOriginals: [
                                        DeviceCacheOptions.audioIntelligenceKey: false,
                                        DeviceCacheOptions.personalTranslatorKey: true,
                                    ])
        guard case .compared(let equalRows) = ModifiedValues.report(for: snapshot, using: layout) else {
            return XCTFail("Equal slots still compare")
        }
        XCTAssert(equalRows.isEmpty, "Equal slots produce no rows")
    }
}
