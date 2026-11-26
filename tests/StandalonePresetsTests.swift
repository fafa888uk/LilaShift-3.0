import Foundation
import XCTest
@testable import GestaltX

/// Offline tests for the two standalone presets: the AI-only preset (seven
/// Apple Intelligence keys, no eSIM or region) and the eSIM+region preset
/// (two eSIM CacheData slots + RegionCode LL, no AI keys). Both are pure
/// subsets of the 10-item one-tap unlock; the full one-tap is unchanged.
/// No device or signing is needed.
final class StandalonePresetsTests: XCTestCase {
    struct Failure: Error { let message: String }

    /// The seven Apple Intelligence keys, in the same order as
    /// `ChinaUnlock.aiCapabilityIDs`: ai, siriAIMode, audioIntelligence,
    /// personalTranslator, photosCleanUp, handwritingSynthesis,
    /// alwaysListeningSiri.
    static let aiKeys = [
        "A62OafQ85EJAiiqKn4agtg",
        "a3n5T9sFtlyQ74NEp9ESxg",
        "rb2tKZxlj0Gm2tBmUQSLqQ",
        "M1n2sAqf33NAOgZRGxQYBA",
        "XNCjqOupLM/S8fNyxRNQTA",
        "YgYIIViDt1kgzyIsIV61vA",
        "TusANsf9Lfe3P/9fIXXSrQ",
    ]
    static let siriKey = "K/R1GfGfCkXvEhaPS2Vrng"

    /// China-mainland fixture: eSIM restricted (green-tea on), region CH
    /// with CH/A sales suffixes, no AI keys, a device-specific Siri
    /// value (2) and an Air model number. Pass a bogus cacheUUID for an
    /// unsupported layout (the eSIM cache layout cannot be verified).
    /// The default product type is the native iPhone18,1; pass a
    /// non-native product type (for example iPhone14,7) for the full
    /// AI-only preset. Pass an unknown product type (for example
    /// iPhone99,9) with an unknown model number (for example A9999)
    /// for the fail-closed unknown-model path.
    static func fixture(cacheUUID: String? = nil, productType: String = "iPhone18,1",
                        modelNumber: String = "A3518") throws -> GestaltDocument {
        let layout = MobileGestaltCacheLayout.originalProfile
        var cache = Data(count: layout.byteCount)
        cache[layout.greenTeaOffset] = 1
        cache[layout.notGreenTeaOffset] = 0
        cache[layout.validityOffset(for: layout.greenTeaIndex)] = 1
        cache[layout.validityOffset(for: layout.notGreenTeaIndex)] = 1
        let extra: [String: Any] = [
            GestaltKeys.productType: productType,
            GestaltKeys.regionCode: "CH",
            GestaltKeys.regionInfo: "CH/A",
            GestaltKeys.legacyRegionInfo: "CH/A",
            GestaltKeys.modelNumber: modelNumber,
            siriKey: NSNumber(value: 2),
        ]
        return try GestaltDocument(data: PropertyListSerialization.data(fromPropertyList: [
            "CacheVersion": "24C5037i", "CacheUUID": cacheUUID ?? layout.uuid,
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

    @MainActor
    func testAIOnlyPreset() throws {
        // The region mode is a persisted user setting; pin the default
        // here so this test never inherits another run's opt-in Full US mode.
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        // The fixture is native Apple Intelligence hardware
        // (iPhone18,1): the AI-only preset is refused — the seven
        // presets are already on — and nothing is staged.
        let original = try Self.fixture()
        let manager = try manager(for: original)
        XCTAssert(manager.chinaUnlockESIMLayoutError == nil,
                   "Supported layout: no eSIM layout error")
        XCTAssert(!manager.isChinaAIOnlyStaged && !manager.isChinaAIOnlyApplied,
                   "Fixture starts with AI absent")
        XCTAssert(!manager.stageChinaAIOnly(),
                   "AI-only staging is refused on native hardware")
        XCTAssert(manager.message?.isEmpty == false,
                   "AI-only refusal shows the reason")
        XCTAssert(!manager.isChinaAIOnlyStaged && !manager.isChinaAIOnlyApplied,
                   "A refused AI-only staging stages nothing")
        XCTAssert(manager.changeCount == 0,
                   "A refused AI-only staging changes nothing, got \(manager.changeCount)")
        XCTAssert(manager.restoreChinaAIOnly(),
                   "AI-only restore is a no-op when nothing was staged")
        XCTAssert(manager.changeCount == 0, "Restore of nothing staged changes nothing")
        XCTAssert(!manager.isChinaAIOnlyStaged && !manager.isChinaAIOnlyApplied,
                   "Restore leaves the AI-only staged and applied state clear")

        // Staging again is refused the same way.
        XCTAssert(!manager.stageChinaAIOnly(),
                   "AI-only staging stays refused on native hardware")
        XCTAssert(manager.changeCount == 0, "A refused AI-only staging still changes nothing")
    }

    @MainActor
    func testAIOnlyPresetNonNative() throws {
        // The region mode is a persisted user setting; pin the default
        // here so this test never inherits another run's opt-in Full US mode.
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try Self.fixture(productType: "iPhone14,7")
        let manager = try manager(for: original)
        XCTAssert(manager.chinaUnlockESIMLayoutError == nil,
                   "Supported layout: no eSIM layout error")
        XCTAssert(!manager.isChinaAIOnlyStaged && !manager.isChinaAIOnlyApplied,
                   "Fixture starts with AI absent")

        // Staging the AI-only preset changes exactly the seven AI keys.
        XCTAssert(manager.stageChinaAIOnly(), "AI-only staging succeeds")
        XCTAssert(manager.isChinaAIOnlyStaged, "AI-only staged flag is set")
        XCTAssert(manager.isChinaAIOnlyApplied, "Preview shows all seven AI presets enabled")
        XCTAssert(!manager.isChinaUnlockStaged,
                   "AI-only staging is not the full one-tap: eSIM and region are not staged")
        XCTAssert(manager.changeCount == 7, "AI-only staging changes exactly 7 items, got \(manager.changeCount)")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after AI-only staging") }
        for key in Self.aiKeys {
            // Each AI key stages its capability's own value: boolean
            // true for six keys, SiriMode=2 for the siriAIMode key.
            let expected = ChinaUnlock.aiCapabilities
                .first { $0.keys.contains(key) }?.values[key] as? NSNumber
            XCTAssert((preview.extra[key] as? NSNumber)?.intValue == (expected?.intValue ?? 1),
                       "Preview enables AI key \(key) to its staged value")
        }
        XCTAssert(preview.extra[GestaltKeys.regionCode] as? String == "CH",
                   "AI-only staging leaves RegionCode at CH")
        XCTAssert(preview.extra[GestaltKeys.regionInfo] as? String == "CH/A"
                   && preview.extra[GestaltKeys.legacyRegionInfo] as? String == "CH/A",
                   "AI-only staging leaves the sales-region suffixes alone")
        XCTAssert(try DeviceCacheOptions.flags(in: preview) == .restricted,
                   "AI-only staging leaves the eSIM flags restricted")
        XCTAssert((preview.extra[Self.siriKey] as? NSNumber)?.intValue == 2,
                   "AI-only staging keeps the device-specific Siri value")
        XCTAssert(manager.chinaUnlockAIEnabledCount == 7, "All seven AI presets read as enabled")
        XCTAssert(!manager.isChinaESIMRegionStaged && !manager.isChinaESIMRegionApplied,
                   "AI-only staging does not stage the eSIM+region preset")

        // Staging twice is idempotent.
        manager.stageChinaAIOnly()
        XCTAssert(manager.changeCount == 7, "Staging AI-only twice does not duplicate changes")

        // Restoring the AI-only preset returns the AI keys to their originals.
        XCTAssert(manager.restoreChinaAIOnly(), "AI-only restore succeeds")
        XCTAssert(!manager.isChinaAIOnlyStaged && !manager.isChinaAIOnlyApplied,
                   "Restore clears the AI-only staged and applied state")
        XCTAssert(manager.changeCount == 0, "Restore unstages every AI change")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after AI-only restore") }
        XCTAssert(restored.matches(original), "Restored preview matches the original document")
        for key in Self.aiKeys {
            XCTAssert(restored.extra[key] == nil, "Restore removes AI key \(key)")
        }
        XCTAssert(restored.extra[GestaltKeys.regionCode] as? String == "CH",
                   "Restore leaves RegionCode at CH")
        XCTAssert(try DeviceCacheOptions.flags(in: restored) == .restricted,
                   "Restore leaves the eSIM flags restricted")

        // The AI-only preset can be staged again after a restore.
        manager.stageChinaAIOnly()
        XCTAssert(manager.isChinaAIOnlyStaged && manager.changeCount == 7,
                   "AI-only stages again after a restore")
    }

    @MainActor
    func testESIMRegionPreset() throws {
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        // Non-native fixture: the "eSIM+region is not the full
        // one-tap" assertion only holds there — on native hardware
        // eSIM+region IS the full one-tap (the AI keys are skipped).
        let original = try Self.fixture(productType: "iPhone14,7")
        let manager = try manager(for: original)
        XCTAssert(manager.chinaUnlockESIMLayoutError == nil,
                   "Supported layout: no eSIM layout error")
        XCTAssert(!manager.isChinaESIMRegionStaged && !manager.isChinaESIMRegionApplied,
                   "Fixture starts locked: eSIM restricted, region CH")

        // Staging the eSIM+region preset changes exactly 3 items.
        XCTAssert(manager.stageChinaESIMRegion(), "eSIM+region staging succeeds")
        XCTAssert(manager.isChinaESIMRegionStaged, "eSIM+region staged flag is set")
        XCTAssert(manager.isChinaESIMRegionApplied, "Preview shows eSIM enabled and region LL")
        XCTAssert(!manager.isChinaUnlockStaged,
                   "eSIM+region staging is not the full one-tap: AI is not staged")
        XCTAssert(manager.changeCount == 3, "eSIM+region staging changes exactly 3 items, got \(manager.changeCount)")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after eSIM+region staging") }
        XCTAssert(try DeviceCacheOptions.flags(in: preview) == .enabled,
                   "Preview enables eSIM: green-tea false, not-green-tea true")
        let before = original.root["CacheData"] as! Data
        let after = preview.root["CacheData"] as! Data
        let layout = MobileGestaltCacheLayout.originalProfile
        XCTAssert(before.indices.filter { before[$0] != after[$0] } == [layout.greenTeaOffset, layout.notGreenTeaOffset].sorted(),
                   "Only the two eSIM bytes change in CacheData")
        XCTAssert(preview.extra[GestaltKeys.regionCode] as? String == "LL",
                   "Preview sets RegionCode to LL")
        XCTAssert(preview.extra[GestaltKeys.regionInfo] as? String == "CH/A"
                   && preview.extra[GestaltKeys.legacyRegionInfo] as? String == "CH/A",
                   "Sales-region suffixes stay CH/A")
        for key in Self.aiKeys {
            XCTAssert(preview.extra[key] == nil, "eSIM+region staging leaves AI key \(key) absent")
        }
        XCTAssert(manager.chinaUnlockAIEnabledCount == 0, "No AI preset reads as enabled")
        XCTAssert((preview.extra[Self.siriKey] as? NSNumber)?.intValue == 2,
                   "eSIM+region staging keeps the device-specific Siri value")
        XCTAssert(preview.extra[GestaltKeys.modelNumber] as? String == "A3518",
                   "Model number is untouched")
        XCTAssert(!manager.isChinaAIOnlyStaged && !manager.isChinaAIOnlyApplied,
                   "eSIM+region staging does not stage the AI-only preset")

        // Staging twice is idempotent.
        manager.stageChinaESIMRegion()
        XCTAssert(manager.changeCount == 3, "Staging eSIM+region twice does not duplicate changes")

        // Restoring the eSIM+region preset returns eSIM and region to their originals.
        XCTAssert(manager.restoreChinaESIMRegion(), "eSIM+region restore succeeds")
        XCTAssert(!manager.isChinaESIMRegionStaged && !manager.isChinaESIMRegionApplied,
                   "Restore clears the eSIM+region staged and applied state")
        XCTAssert(manager.changeCount == 0, "Restore unstages every eSIM+region change")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after eSIM+region restore") }
        XCTAssert(restored.matches(original), "Restored preview matches the original document")
        XCTAssert(try DeviceCacheOptions.flags(in: restored) == .restricted,
                   "Restore returns the eSIM flags to restricted")
        XCTAssert(restored.extra[GestaltKeys.regionCode] as? String == "CH",
                   "Restore returns RegionCode to CH")
        for key in Self.aiKeys {
            XCTAssert(restored.extra[key] == nil, "Restore leaves AI key \(key) absent")
        }

        // The eSIM+region preset can be staged again after a restore.
        manager.stageChinaESIMRegion()
        XCTAssert(manager.isChinaESIMRegionStaged && manager.changeCount == 3,
                   "eSIM+region stages again after a restore")
    }

    @MainActor
    func testStandalonePresetsLayoutGating() throws {
        // Unsupported cache layout: the eSIM layout cannot be verified.
        // Non-native fixture: the AI-only preset's layout independence
        // is verified here — on native hardware AI-only is refused
        // regardless of the layout (see `testAIOnlyPreset`).
        let unsupported = try Self.fixture(cacheUUID: "unsupported-layout", productType: "iPhone14,7")
        let manager = try manager(for: unsupported)
        XCTAssert(manager.chinaUnlockESIMLayoutError != nil,
                   "Unsupported layout: the eSIM layout error names the reason")
        XCTAssert(manager.previewESIMFlags == nil, "Unknown cache layout has no reliable eSIM status")

        // The AI-only preset is NOT blocked by the eSIM layout: the seven AI
        // keys are CacheExtra values and do not need the layout to resolve.
        XCTAssert(manager.stageChinaAIOnly(),
                   "AI-only staging succeeds even when the eSIM layout cannot be verified")
        XCTAssert(manager.changeCount == 7,
                   "AI-only staging on an unsupported layout changes exactly the 7 AI keys, got \(manager.changeCount)")
        XCTAssert(manager.isChinaAIOnlyStaged, "AI-only staged flag is set on an unsupported layout")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after AI-only staging") }
        for key in Self.aiKeys {
            // Each AI key stages its capability's own value: boolean
            // true for six keys, SiriMode=2 for the siriAIMode key.
            let expected = ChinaUnlock.aiCapabilities
                .first { $0.keys.contains(key) }?.values[key] as? NSNumber
            XCTAssert((preview.extra[key] as? NSNumber)?.intValue == (expected?.intValue ?? 1),
                       "Preview enables AI key \(key) on an unsupported layout to its staged value")
        }
        XCTAssert(preview.extra[GestaltKeys.regionCode] as? String == "CH",
                   "AI-only staging leaves RegionCode at CH on an unsupported layout")
        manager.restoreChinaAIOnly()
        XCTAssert(manager.changeCount == 0, "AI-only restore clears the staging on an unsupported layout")

        // The eSIM+region preset IS blocked by the eSIM layout, exactly
        // like the full one-tap unlock.
        XCTAssert(!manager.stageChinaESIMRegion(),
                   "eSIM+region staging stops when the eSIM layout cannot be verified")
        XCTAssert(manager.message?.isEmpty == false,
                   "eSIM+region staging shows the reason")
        XCTAssert(manager.changeCount == 0 && !manager.isChinaESIMRegionStaged,
                   "A blocked eSIM+region staging leaves nothing staged")
        XCTAssert(!manager.restoreChinaESIMRegion(),
                   "eSIM+region restore stops when the eSIM layout cannot be verified")
    }

    @MainActor
    func testStandalonePresetsComposeIntoOneTap() throws {
        // The two subsets compose into the full 10-item one-tap: staging
        // AI-only and then eSIM+region stages exactly the 10 items, and
        // the one-tap staged flag reads true. Non-native fixture: on
        // native hardware the AI-only preset is refused, so the two
        // subsets compose into the 3-item one-tap instead (see
        // `testStandalonePresetsComposeIntoOneTapNative`).
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try Self.fixture(productType: "iPhone14,7")
        let manager = try manager(for: original)
        manager.stageChinaAIOnly()
        manager.stageChinaESIMRegion()
        XCTAssert(manager.changeCount == 10,
                   "Both subsets staged together change exactly 10 items, got \(manager.changeCount)")
        XCTAssert(manager.isChinaUnlockStaged,
                   "Both subsets staged together read as the full one-tap staged")
        XCTAssert(manager.isChinaUnlockedInPreview,
                   "Both subsets staged together read as unlocked in preview")
        // Restoring the full one-tap clears both subsets.
        manager.restoreChinaUnlock()
        XCTAssert(manager.changeCount == 0, "One-tap restore clears both subsets")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after one-tap restore") }
        XCTAssert(restored.matches(original), "One-tap restore returns the original document")
    }

    @MainActor
    func testStandalonePresetsComposeIntoOneTapNative() throws {
        // On native hardware the AI-only preset is refused, so the
        // two subsets compose into the 3-item one-tap: eSIM+region
        // alone is the full unlock there.
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try Self.fixture()
        let manager = try manager(for: original)
        XCTAssert(!manager.stageChinaAIOnly(), "AI-only staging is refused on native hardware")
        manager.stageChinaESIMRegion()
        XCTAssert(manager.changeCount == 3,
                   "Native compose changes exactly 3 items, got \(manager.changeCount)")
        XCTAssert(manager.isChinaUnlockStaged,
                   "eSIM+region staged reads as the full one-tap on native hardware")
        XCTAssert(manager.isChinaUnlockedInPreview,
                   "eSIM+region staged reads as unlocked in preview on native hardware")
        // Restoring the full one-tap clears the native staging.
        manager.restoreChinaUnlock()
        XCTAssert(manager.changeCount == 0, "One-tap restore clears the native staging")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after one-tap restore") }
        XCTAssert(restored.matches(original), "One-tap restore returns the original document")
    }

    // MARK: - Standalone Siri AI Mode preset

    /// The SiriMode key, for asserting the single-item staging.
    static let siriModeKey = "a3n5T9sFtlyQ74NEp9ESxg"

    @MainActor
    func testSiriAIModePreset() throws {
        // Non-native fixture: staging the Siri AI Mode preset
        // changes exactly one item — the SiriMode key to 2 — and
        // nothing else.
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try Self.fixture(productType: "iPhone14,7")
        let manager = try manager(for: original)
        XCTAssert(manager.chinaUnlockESIMLayoutError == nil,
                   "Supported layout: no eSIM layout error")
        XCTAssert(!manager.isChinaSiriAIModeStaged && !manager.isChinaSiriAIModeApplied,
                   "Fixture starts with SiriMode absent")

        XCTAssert(manager.stageChinaSiriAIMode(), "Siri AI Mode staging succeeds")
        XCTAssert(manager.isChinaSiriAIModeStaged, "Siri AI Mode staged flag is set")
        XCTAssert(manager.isChinaSiriAIModeApplied, "Preview shows SiriMode set to 2")
        XCTAssert(!manager.isChinaUnlockStaged,
                   "Siri AI Mode staging is not the full one-tap: eSIM, region and the other AI keys are not staged")
        XCTAssert(!manager.isChinaAIOnlyStaged && !manager.isChinaAIOnlyApplied,
                   "Siri AI Mode staging is not the AI-only preset")
        XCTAssert(!manager.isChinaESIMRegionStaged && !manager.isChinaESIMRegionApplied,
                   "Siri AI Mode staging is not the eSIM+region preset")
        XCTAssert(manager.changeCount == 1, "Siri AI Mode staging changes exactly 1 item, got \(manager.changeCount)")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after Siri AI Mode staging") }
        XCTAssert((preview.extra[Self.siriModeKey] as? NSNumber)?.intValue == 2,
                   "Preview sets SiriMode to 2")
        for key in Self.aiKeys where key != Self.siriModeKey {
            XCTAssert(preview.extra[key] == nil, "Siri AI Mode staging leaves AI key \(key) absent")
        }
        XCTAssert(preview.extra[GestaltKeys.regionCode] as? String == "CH",
                   "Siri AI Mode staging leaves RegionCode at CH")
        XCTAssert(preview.extra[GestaltKeys.regionInfo] as? String == "CH/A"
                   && preview.extra[GestaltKeys.legacyRegionInfo] as? String == "CH/A",
                   "Siri AI Mode staging leaves the sales-region suffixes alone")
        XCTAssert(try DeviceCacheOptions.flags(in: preview) == .restricted,
                   "Siri AI Mode staging leaves the eSIM flags restricted")
        XCTAssert((preview.extra[Self.siriKey] as? NSNumber)?.intValue == 2,
                   "Siri AI Mode staging keeps the device-specific Siri value")

        // Staging twice is idempotent.
        manager.stageChinaSiriAIMode()
        XCTAssert(manager.changeCount == 1, "Staging Siri AI Mode twice does not duplicate changes")

        // Restoring the Siri AI Mode preset removes the SiriMode key.
        XCTAssert(manager.restoreChinaSiriAIMode(), "Siri AI Mode restore succeeds")
        XCTAssert(!manager.isChinaSiriAIModeStaged && !manager.isChinaSiriAIModeApplied,
                   "Restore clears the Siri AI Mode staged and applied state")
        XCTAssert(manager.changeCount == 0, "Restore unstages the SiriMode change")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after Siri AI Mode restore") }
        XCTAssert(restored.matches(original), "Restored preview matches the original document")
        XCTAssert(restored.extra[Self.siriModeKey] == nil, "Restore removes the SiriMode key")

        // The Siri AI Mode preset can be staged again after a restore.
        manager.stageChinaSiriAIMode()
        XCTAssert(manager.isChinaSiriAIModeStaged && manager.changeCount == 1,
                   "Siri AI Mode stages again after a restore")
    }

    @MainActor
    func testSiriAIModePresetNative() throws {
        // Native hardware is the whole point of this preset: unlike
        // the AI-only preset, Siri AI Mode staging is ALLOWED on
        // native Apple Intelligence hardware — an explicit
        // single-item opt-in — and stages exactly the SiriMode key.
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try Self.fixture()
        let manager = try manager(for: original)
        XCTAssert(manager.chinaUnlockESIMLayoutError == nil,
                   "Supported layout: no eSIM layout error")
        XCTAssert(!manager.isChinaSiriAIModeStaged && !manager.isChinaSiriAIModeApplied,
                   "Fixture starts with SiriMode absent")

        XCTAssert(manager.stageChinaSiriAIMode(), "Siri AI Mode staging succeeds on native hardware")
        XCTAssert(manager.isChinaSiriAIModeStaged, "Siri AI Mode staged flag is set on native hardware")
        XCTAssert(manager.isChinaSiriAIModeApplied, "Preview shows SiriMode set to 2 on native hardware")
        XCTAssert(manager.changeCount == 1, "Siri AI Mode staging on native hardware changes exactly 1 item, got \(manager.changeCount)")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after Siri AI Mode staging") }
        XCTAssert((preview.extra[Self.siriModeKey] as? NSNumber)?.intValue == 2,
                   "Preview sets SiriMode to 2 on native hardware")
        XCTAssert(preview.extra[GestaltKeys.regionCode] as? String == "CH",
                   "Siri AI Mode staging leaves RegionCode at CH on native hardware")
        XCTAssert(try DeviceCacheOptions.flags(in: preview) == .restricted,
                   "Siri AI Mode staging leaves the eSIM flags restricted on native hardware")

        // Restoring works on native hardware too.
        XCTAssert(manager.restoreChinaSiriAIMode(), "Siri AI Mode restore succeeds on native hardware")
        XCTAssert(!manager.isChinaSiriAIModeStaged && !manager.isChinaSiriAIModeApplied,
                   "Restore clears the Siri AI Mode staged and applied state on native hardware")
        XCTAssert(manager.changeCount == 0, "Restore unstages the SiriMode change on native hardware")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after Siri AI Mode restore") }
        XCTAssert(restored.matches(original), "Restored preview matches the original document")
    }

    @MainActor
    func testSiriAIModePresetUnknownModel() throws {
        // Unknown model: fail-closed. The SiriMode key is never
        // staged for a device with no verified mapping entry, and
        // the reason is shown.
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try Self.fixture(productType: "iPhone99,9", modelNumber: "A9999")
        let manager = try manager(for: original)
        XCTAssert(!manager.isChinaSiriAIModeStaged && !manager.isChinaSiriAIModeApplied,
                   "Fixture starts with SiriMode absent")
        XCTAssert(!manager.stageChinaSiriAIMode(),
                   "Siri AI Mode staging is refused on an unknown model")
        XCTAssert(manager.message?.isEmpty == false,
                   "Siri AI Mode refusal shows the reason")
        XCTAssert(!manager.isChinaSiriAIModeStaged && !manager.isChinaSiriAIModeApplied,
                   "A refused Siri AI Mode staging stages nothing")
        XCTAssert(manager.changeCount == 0,
                   "A refused Siri AI Mode staging changes nothing, got \(manager.changeCount)")
        XCTAssert(manager.restoreChinaSiriAIMode(),
                   "Siri AI Mode restore is a no-op when nothing was staged")
        XCTAssert(manager.changeCount == 0, "Restore of nothing staged changes nothing")
    }

    @MainActor
    func testSiriAIModePresetLayoutIndependent() throws {
        // Unsupported cache layout: the SiriMode key is a CacheExtra
        // value and does not need the layout to resolve, so staging
        // succeeds exactly like the AI-only preset — unlike
        // eSIM+region, which is blocked by the layout.
        let unsupported = try Self.fixture(cacheUUID: "unsupported-layout", productType: "iPhone14,7")
        let manager = try manager(for: unsupported)
        XCTAssert(manager.chinaUnlockESIMLayoutError != nil,
                   "Unsupported layout: the eSIM layout error names the reason")
        XCTAssert(manager.stageChinaSiriAIMode(),
                   "Siri AI Mode staging succeeds even when the eSIM layout cannot be verified")
        XCTAssert(manager.changeCount == 1,
                   "Siri AI Mode staging on an unsupported layout changes exactly 1 item, got \(manager.changeCount)")
        XCTAssert(manager.isChinaSiriAIModeStaged, "Siri AI Mode staged flag is set on an unsupported layout")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after Siri AI Mode staging") }
        XCTAssert((preview.extra[Self.siriModeKey] as? NSNumber)?.intValue == 2,
                   "Preview sets SiriMode to 2 on an unsupported layout")
        manager.restoreChinaSiriAIMode()
        XCTAssert(manager.changeCount == 0, "Siri AI Mode restore clears the staging on an unsupported layout")
    }

    @MainActor
    func testSiriAIModeComposesWithOthers() throws {
        // Siri AI Mode composes with the other standalone presets
        // without duplicating changes. Non-native fixture.
        ChinaUnlockRegionMode.stored = .regionCodeOnly
        let original = try Self.fixture(productType: "iPhone14,7")
        let manager = try manager(for: original)

        // Siri AI Mode + eSIM+region = 4 items, but not the full
        // one-tap (the other six AI keys are missing).
        manager.stageChinaSiriAIMode()
        manager.stageChinaESIMRegion()
        XCTAssert(manager.changeCount == 4,
                   "Siri AI Mode + eSIM+region change exactly 4 items, got \(manager.changeCount)")
        XCTAssert(!manager.isChinaUnlockStaged,
                   "Siri AI Mode + eSIM+region is not the full one-tap")
        XCTAssert(manager.isChinaSiriAIModeStaged && manager.isChinaESIMRegionStaged,
                   "Both subsets read as staged")
        manager.restoreChinaUnlock()
        XCTAssert(manager.changeCount == 0, "One-tap restore clears both subsets")
        guard let restored = manager.preview else { throw Failure(message: "Preview exists after one-tap restore") }
        XCTAssert(restored.matches(original), "One-tap restore returns the original document")

        // Siri AI Mode is subsumed by the AI-only preset: staging
        // it first and then AI-only changes exactly the 7 AI keys,
        // with no duplicate change for the SiriMode key.
        manager.stageChinaSiriAIMode()
        XCTAssert(manager.changeCount == 1, "Siri AI Mode alone changes exactly 1 item")
        manager.stageChinaAIOnly()
        XCTAssert(manager.changeCount == 7,
                   "Siri AI Mode + AI-only change exactly the 7 AI keys, got \(manager.changeCount)")
        XCTAssert(manager.isChinaAIOnlyStaged, "AI-only staged flag is set")
        guard let preview = manager.preview else { throw Failure(message: "Preview exists after AI-only staging") }
        for key in Self.aiKeys {
            let expected = key == Self.siriModeKey ? 2 : 1
            XCTAssert((preview.extra[key] as? NSNumber)?.intValue == expected,
                       "Preview enables AI key \(key) with value \(expected)")
        }
        XCTAssert(!manager.isChinaUnlockStaged,
                   "AI keys alone are not the full one-tap: eSIM and region are not staged")
    }
}
