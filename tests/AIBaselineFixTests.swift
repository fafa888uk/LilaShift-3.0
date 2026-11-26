import Foundation
import XCTest
@testable import GestaltX

/// Offline tests for the one-click AI baseline fix (A3): the
/// `fixAIBaseline()` step in the one-tap flow. The CacheData slot
/// repair (Personal Translator #266 = 1, Audio Intelligence #178 = 0)
/// needs a real device's runtime-scanned layout to resolve the slots,
/// so it cannot be exercised offline — the slot machinery itself
/// (`setAdvAISlot` / `advAISlotValue` with an explicit layout) is
/// covered by `AIReadinessTests`, and the manager wiring is
/// device-verified. What IS verified here, offline: the CacheExtra
/// key fill (absent AI keys filled with their staged values on
/// non-native hardware; present values untouched; native hardware
/// skipped per the #178 decision), and that the step is a safe no-op
/// where nothing resolves. No device or signing is needed.
final class AIBaselineFixTests: XCTestCase {
    static let siriKey = "K/R1GfGfCkXvEhaPS2Vrng"

    /// China-mainland fixture on the offline layout: eSIM restricted,
    /// region CH, a device-specific Siri value and an Air model
    /// number. Pass a non-native product type (for example iPhone15,4)
    /// for the full AI staging path; the default is native iPhone18,1.
    /// Pass `aiKeys` to pre-set AI CacheExtra keys (a value of `true`
    /// is the staged value for the boolean keys; pass `false` for a
    /// present-but-wrong value).
    static func fixture(productType: String = "iPhone18,1",
                        aiKeys: [String: Any] = [:]) throws -> GestaltDocument {
        let layout = MobileGestaltCacheLayout.originalProfile
        var cache = Data(count: layout.byteCount)
        cache[layout.greenTeaOffset] = 1
        cache[layout.notGreenTeaOffset] = 0
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        var extra: [String: Any] = [
            GestaltKeys.productType: productType,
            GestaltKeys.regionCode: "CH",
            GestaltKeys.regionInfo: "CH/A",
            GestaltKeys.legacyRegionInfo: "CH/A",
            GestaltKeys.modelNumber: "A3518",
            siriKey: NSNumber(value: 2),
        ]
        for (key, value) in aiKeys { extra[key] = value }
        return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": layout.uuid,
            "CacheData": cache, "CacheExtra": extra,
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

    /// The staged value for an AI capability key (its explicit value,
    /// or the plain boolean enable value).
    static func stagedValue(for capability: Capability, key: String) -> Any {
        capability.values[key] ?? capability.enabled
    }

    @MainActor
    func testKeyFillOnNonNative() throws {
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let manager = try manager(for: Self.fixture(productType: "iPhone15,4"))
        XCTAssert(manager.stageChinaAIOnly(), "AI-only staging succeeds on non-native hardware")
        // The fill runs in the working document itself, not only in
        // the preview: every absent AI key is now present with its
        // staged value.
        let working = try XCTUnwrap(manager.working, "A working document is loaded")
        for capability in ChinaUnlock.aiCapabilities {
            for key in capability.keys {
                let value = working.extra[key]
                XCTAssert(value != nil, "Absent AI key \(key) is filled in the working document")
                XCTAssert(GestaltDocument.valuesEqual(value!, Self.stagedValue(for: capability, key: key)),
                           "Filled AI key \(key) holds its staged value")
            }
        }
        // The preview agrees: all seven AI presets are staged.
        XCTAssert(manager.isChinaAIOnlyStaged, "All seven AI presets read as staged after the fill")
    }

    @MainActor
    func testFixAIBaselineReturnValue() throws {
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let manager = try manager(for: Self.fixture(productType: "iPhone15,4"))
        // Nothing staged yet: no AI choices, so the fill has nothing
        // to fill and the slots do not resolve offline.
        XCTAssert(!manager.fixAIBaseline(), "fixAIBaseline stages nothing when AI is not staged")
        for id in ChinaUnlock.aiCapabilityIDs { manager.choices[id] = .enable }
        XCTAssert(manager.fixAIBaseline(), "fixAIBaseline stages the absent AI keys once AI staging is active")
        XCTAssert(!manager.fixAIBaseline(), "A second fixAIBaseline stages nothing: the keys are already filled")
    }

    @MainActor
    func testPresentValuesUntouched() throws {
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        // One AI key present but wrong (ai = false), the rest absent.
        // The fill must not overwrite the present value; the choices
        // correct it in the preview instead.
        let manager = try manager(for: Self.fixture(productType: "iPhone15,4",
                                                    aiKeys: ["A62OafQ85EJAiiqKn4agtg": false]))
        XCTAssert(manager.stageChinaAIOnly(), "AI-only staging succeeds on non-native hardware")
        let working = try XCTUnwrap(manager.working, "A working document is loaded")
        XCTAssert(working.extra["A62OafQ85EJAiiqKn4agtg"] as? Bool == false,
                   "A present AI key is left untouched by the fill, even when wrong")
        let preview = try XCTUnwrap(manager.preview, "A preview is available")
        XCTAssert(preview.extra["A62OafQ85EJAiiqKn4agtg"] as? Bool == true,
                   "The staged choice still corrects the present key in the preview")
        // The absent keys were still filled.
        for capability in ChinaUnlock.aiCapabilities where capability.id != "ai" {
            for key in capability.keys {
                XCTAssert(working.extra[key] != nil, "Absent AI key \(key) is still filled")
            }
        }
    }

    @MainActor
    func testNativeSkipsKeyFill() throws {
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        // Native hardware (iPhone18,1): the one-tap skips the seven AI
        // presets per the #178 decision, and the baseline fix must not
        // fill them either — only the slot repair applies there, and
        // it is a no-op offline (slots do not resolve).
        let manager = try manager(for: Self.fixture(productType: "iPhone18,1"))
        XCTAssert(manager.stageChinaUnlock(), "One-tap staging succeeds on native hardware")
        XCTAssert(manager.isChinaUnlockStaged, "The one-tap reads as staged on native hardware (AI skipped, not missing)")
        let working = try XCTUnwrap(manager.working, "A working document is loaded")
        for capability in ChinaUnlock.aiCapabilities {
            for key in capability.keys {
                XCTAssert(working.extra[key] == nil,
                           "Native hardware: AI key \(key) is not filled in the working document")
            }
        }
        XCTAssert(!manager.fixAIBaseline(), "fixAIBaseline stages nothing further on native hardware offline")
    }

    @MainActor
    func testSlotRepairIsNoopOffline() throws {
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        // The offline layout has no AdvAI slot indices, so the slot
        // repair cannot resolve anything: it must leave the document
        // alone rather than guess. (On a device the runtime-scanned
        // layout resolves the slots and the repair applies.)
        let manager = try manager(for: Self.fixture(productType: "iPhone18,1"))
        let before = try XCTUnwrap(manager.working, "A working document is loaded")
        XCTAssert(!manager.fixAIBaseline(), "No slot resolves offline, so nothing is staged")
        let after = try XCTUnwrap(manager.working, "A working document is loaded")
        XCTAssert(after.matches(before), "The document is untouched when no slot resolves")
    }
}
