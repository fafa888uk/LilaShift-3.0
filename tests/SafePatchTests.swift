// SPDX-License-Identifier: GPL-3.0-only
// Tests for SafePatch (修改模拟器): simulation diffs, the
// hardware-identity guard, unknown-model fail-closed, and the
// changed-snapshot refusal.
//
// The happy-path fixture is a known non-native model (iPhone14,7)
// with a document matching the offline `originalProfile` layout, so
// `resolve(in:)` succeeds on the test host and the profile is
// injected (the test host itself is an unknown model, which is
// exactly what the fail-closed test exercises).
import Foundation
import XCTest
@testable import GestaltX

final class SafePatchTests: XCTestCase {
    /// The 10-item one-tap unlock on a known non-native CH device:
    /// the simulation proceeds, the diff is exactly the 10 fields
    /// (region + 7 AI keys + the eSIM pair), the serialization
    /// round-trips, and the effect states show only "staged" as
    /// projected — the other three are confirmed only by real events.
    func testOneTapSimulationHappyPath() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(
            document: document,
            cachedOptions: try CachedOptionsOriginal(document: document),
            wapi: try WAPIOriginal(document: document))
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal.oneTap(), snapshot: snapshot, profile: profile)
        XCTAssertTrue(simulation.canProceed, "One-tap must proceed on a known non-native CH device; blockers: \(simulation.blockers)")
        XCTAssertTrue(simulation.serializationOK, "The simulated document must encode and decode back to itself")
        XCTAssertNotNil(simulation.simulatedByteCount)
        XCTAssertTrue(simulation.hardwareIdentityTouches.isEmpty,
                      "One-tap must not touch any hardware-identity field")
        XCTAssertEqual(simulation.diffs.count, 10,
                       "One-tap changes exactly 10 fields, got: \(simulation.diffs.map(\.key))")
        let regionDiff = simulation.diffs.first { $0.key == GestaltKeys.regionCode }
        XCTAssertEqual(regionDiff?.original, .string("CH"))
        XCTAssertEqual(regionDiff?.target, .string("LL"))
        XCTAssertEqual(regionDiff?.originalSource, .firstRecordedValue)
        for key in ChinaUnlock.aiCapabilityIDs.compactMap({ id in Capability.all.first { $0.id == id }?.keys.first }) {
            let diff = simulation.diffs.first { $0.key == key }
            XCTAssertEqual(diff?.original, .absent, "AI key \(key) was absent before staging")
            XCTAssertEqual(diff?.target, .bool(true))
        }
        let greenTea = simulation.diffs.first { $0.key == DeviceCacheOptions.greenTeaKey }
        XCTAssertEqual(greenTea?.original, .bool(true))
        XCTAssertEqual(greenTea?.target, .bool(false))
        XCTAssertEqual(greenTea?.originalSource, .recordedOriginal)
        let notGreenTea = simulation.diffs.first { $0.key == DeviceCacheOptions.notGreenTeaKey }
        XCTAssertEqual(notGreenTea?.original, .bool(false))
        XCTAssertEqual(notGreenTea?.target, .bool(true))
        let staged = simulation.effectStates.first { $0.effect == .staged }
        XCTAssertEqual(staged?.status, .notReached,
                       "A simulation only projects 'staged'; it never claims the write or the function is verified")
        XCTAssertTrue(simulation.effectStates.filter { $0.effect != .staged }
            .allSatisfy { $0.status == .notReached },
            "File-write, restart and function verification are confirmed only by real events")
    }

    /// Region-only proposal: the diff is exactly the region code,
    /// model-independent, and it proceeds without an injected profile.
    func testRegionOnlyProposalDiff() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(
            document: document,
            originals: [GestaltKeys.regionCode: OriginalField(value: "CH")])
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal(featureIDs: [FeatureEligibilityEvaluator.regionCodeFeatureID]),
            snapshot: snapshot)
        XCTAssertTrue(simulation.canProceed, "Region staging is model-independent; blockers: \(simulation.blockers)")
        XCTAssertEqual(simulation.diffs.count, 1)
        XCTAssertEqual(simulation.diffs.first?.key, GestaltKeys.regionCode)
        XCTAssertEqual(simulation.diffs.first?.original, .string("CH"))
        XCTAssertEqual(simulation.diffs.first?.target, .string("LL"))
        XCTAssertEqual(simulation.diffs.first?.originalSource, .recordedOriginal)
    }

    /// Unknown model (the test host itself): the simulation blocks —
    /// fail-closed — because the model-dependent AI features cannot
    /// be judged. Nothing is staged, and the blockers name the model.
    func testUnknownModelBlocksSimulation() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let simulation = SafePatch.simulate(proposal: SafePatchProposal.oneTap(), snapshot: snapshot)
        XCTAssertFalse(simulation.canProceed,
                       "An unknown model must block the one-tap simulation")
        XCTAssertFalse(simulation.blockers.isEmpty, "The blockers must name why the simulation refused")
    }

    /// A current document that differs from the snapshot: the
    /// unchanged-since-snapshot check fails as a blocker and the
    /// simulation refuses, even though the proposal itself is fine.
    func testSimulationRefusesChangedSnapshot() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        var changed = document
        changed.set("LL", for: GestaltKeys.regionCode)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal(featureIDs: [FeatureEligibilityEvaluator.regionCodeFeatureID]),
            snapshot: snapshot, currentDocument: changed, profile: profile)
        XCTAssertFalse(simulation.canProceed,
                       "A changed snapshot must block the simulation")
        let check = simulation.check(.unchangedSinceSnapshot)
        XCTAssertEqual(check?.passed, false)
        XCTAssertEqual(check?.isBlocker, true)
    }

    /// No snapshot at all: the trusted-original check fails as a
    /// blocker and the simulation refuses.
    func testSimulationWithoutSnapshotBlocks() {
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal.oneTap(), snapshot: nil)
        XCTAssertFalse(simulation.canProceed, "No snapshot must block the simulation")
        XCTAssertEqual(simulation.check(.trustedOriginal)?.passed, false)
        XCTAssertEqual(simulation.check(.trustedOriginal)?.isBlocker, true)
    }

    /// Hardware-identity guard (defense-in-depth): the one-tap
    /// proposal touches no identity field, and the guard's key set
    /// contains the product type, the model number, and the three
    /// obfuscated device-identity keys. The underlying invariant is
    /// that changing an identity key fails `preservesDeviceIdentity`.
    func testHardwareIdentityGuard() throws {
        let document = try CoreModuleFixtures.document()
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let profile = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal.oneTap(), snapshot: snapshot, profile: profile)
        XCTAssertEqual(simulation.check(.hardwareIdentity)?.passed, true)
        XCTAssertTrue(simulation.hardwareIdentityTouches.isEmpty)
        XCTAssertTrue(SafePatch.hardwareIdentityKeys.contains(GestaltKeys.productType))
        XCTAssertTrue(SafePatch.hardwareIdentityKeys.contains(GestaltKeys.modelNumber))
        XCTAssertTrue(SafePatch.hardwareIdentityKeys.contains("re6Zb+zwFKJNlkQTUeT+/w"))
        XCTAssertTrue(SafePatch.hardwareIdentityKeys.contains("VasUgeSzVyHdB27g2XpN0g"))
        XCTAssertTrue(SafePatch.hardwareIdentityKeys.contains("TF31PAB6aO8KAbPyNKSxKA"))
        var changed = document
        changed.set("iPhone99,9", for: GestaltKeys.productType)
        XCTAssertFalse(changed.preservesDeviceIdentity(of: document),
                       "Changing the product type must fail the device-identity check")
    }

    /// A proposal that would change nothing (region already LL):
    /// the diff check warns, the diff is empty, and the simulation
    /// still proceeds (nothing to do is not a blocker).
    func testNoOpProposalWarns() throws {
        let document = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let snapshot = CoreModuleFixtures.snapshot(document: document)
        let simulation = SafePatch.simulate(
            proposal: SafePatchProposal(featureIDs: [FeatureEligibilityEvaluator.regionCodeFeatureID]),
            snapshot: snapshot)
        XCTAssertTrue(simulation.diffs.isEmpty, "Region already LL means nothing would change")
        XCTAssertEqual(simulation.check(.diff)?.passed, false)
        XCTAssertEqual(simulation.check(.diff)?.isBlocker, false,
                       "Changing nothing is a warning, not a blocker")
    }

    /// The native one-tap (iPhone Air, iPhone18,4): the proposal
    /// stages exactly the 3 non-AI fields (region + the eSIM pair),
    /// the seven AI keys are absent from the diff and recorded as
    /// skipped, and the simulation proceeds.
    func testOneTapSimulationNativeSkipsAI() throws {
        let document = try CoreModuleFixtures.document(extra: [GestaltKeys.productType: "iPhone18,4"])
        let snapshot = CoreModuleFixtures.snapshot(
            document: document,
            cachedOptions: try CachedOptionsOriginal(document: document),
            wapi: try WAPIOriginal(document: document))
        let profile = CoreModuleFixtures.profile(productType: "iPhone18,4", isNativeAI: true)
        let proposal = SafePatchProposal.oneTap(nativeAppleIntelligence: true)
        XCTAssertEqual(proposal.featureIDs,
                       [FeatureEligibilityEvaluator.esimFeatureID,
                        FeatureEligibilityEvaluator.regionCodeFeatureID],
                       "Native one-tap stages only eSIM and region code")
        XCTAssertEqual(proposal.skippedFeatureIDs, ChinaUnlock.aiCapabilityIDs,
                       "Native one-tap records all seven AI capabilities as skipped")
        let simulation = SafePatch.simulate(proposal: proposal, snapshot: snapshot, profile: profile)
        XCTAssertTrue(simulation.canProceed, "Native one-tap must proceed; blockers: \(simulation.blockers)")
        XCTAssertTrue(simulation.serializationOK, "The simulated document must encode and decode back to itself")
        XCTAssertEqual(simulation.diffs.count, 3,
                       "Native one-tap changes exactly 3 fields, got: \(simulation.diffs.map(\.key))")
        XCTAssertEqual(simulation.skippedFeatureIDs, ChinaUnlock.aiCapabilityIDs,
                       "Native one-tap simulation records all seven AI capabilities as skipped")
        let aiKeys = ChinaUnlock.aiCapabilityIDs.flatMap { id in
            Capability.all.first { $0.id == id }?.keys ?? []
        }
        for key in aiKeys {
            XCTAssertNil(simulation.diffs.first { $0.key == key },
                         "AI key \(key) must not be staged on native hardware")
        }
        let regionDiff = simulation.diffs.first { $0.key == GestaltKeys.regionCode }
        XCTAssertEqual(regionDiff?.original, .string("CH"))
        XCTAssertEqual(regionDiff?.target, .string("LL"))
        let greenTea = simulation.diffs.first { $0.key == DeviceCacheOptions.greenTeaKey }
        XCTAssertEqual(greenTea?.original, .bool(true))
        XCTAssertEqual(greenTea?.target, .bool(false))
        let notGreenTea = simulation.diffs.first { $0.key == DeviceCacheOptions.notGreenTeaKey }
        XCTAssertEqual(notGreenTea?.original, .bool(false))
        XCTAssertEqual(notGreenTea?.target, .bool(true))
    }

    /// The AI-only preset on native hardware: the proposal comes back
    /// empty with all seven recorded as skipped, the simulation changes
    /// nothing (a warning, not a blocker) and still proceeds.
    func testAIOnlyNativeSkipsAllSeven() throws {
        let document = try CoreModuleFixtures.document(extra: [GestaltKeys.productType: "iPhone18,4"])
        let snapshot = CoreModuleFixtures.snapshot(
            document: document,
            cachedOptions: try CachedOptionsOriginal(document: document),
            wapi: try WAPIOriginal(document: document))
        let profile = CoreModuleFixtures.profile(productType: "iPhone18,4", isNativeAI: true)
        let proposal = SafePatchProposal.aiOnly(nativeAppleIntelligence: true)
        XCTAssertTrue(proposal.featureIDs.isEmpty,
                      "Native AI-only stages nothing")
        XCTAssertEqual(proposal.skippedFeatureIDs, ChinaUnlock.aiCapabilityIDs,
                       "Native AI-only records all seven AI capabilities as skipped")
        let simulation = SafePatch.simulate(proposal: proposal, snapshot: snapshot, profile: profile)
        XCTAssertTrue(simulation.diffs.isEmpty, "Native AI-only changes nothing")
        XCTAssertEqual(simulation.skippedFeatureIDs, ChinaUnlock.aiCapabilityIDs,
                       "Native AI-only simulation records all seven AI capabilities as skipped")
        XCTAssertEqual(simulation.check(.diff)?.passed, false)
        XCTAssertEqual(simulation.check(.diff)?.isBlocker, false,
                       "Changing nothing is a warning, not a blocker")
        XCTAssertTrue(simulation.canProceed, "An empty AI-only proposal must not block")
    }

    /// The native flag resolves from a known profile value first,
    /// and falls back to the product-type list when the profile value
    /// is unknown.
    func testNativeFlagResolution() {
        let native = CoreModuleFixtures.profile(productType: "iPhone18,4", isNativeAI: true)
        XCTAssertTrue(SafePatchProposal.isNativeAppleIntelligence(profile: native))
        let nonNative = CoreModuleFixtures.profile(productType: "iPhone14,7", isNativeAI: false)
        XCTAssertFalse(SafePatchProposal.isNativeAppleIntelligence(profile: nonNative))
        let fallbackNative = profileWithUnknownNative(productType: "iPhone18,4")
        XCTAssertTrue(SafePatchProposal.isNativeAppleIntelligence(profile: fallbackNative),
                      "Unknown native flag falls back to the product-type list")
        let fallbackUnknown = profileWithUnknownNative(productType: "iPhone99,9")
        XCTAssertFalse(SafePatchProposal.isNativeAppleIntelligence(profile: fallbackUnknown),
                       "Unknown native flag and unknown product type fail closed")
    }

    /// Unknown native status fails closed: the helper reads
    /// non-native, and the one-tap proposal still carries all 9
    /// items with nothing skipped. (At the simulation level an
    /// unknown model blocks — see `testUnknownModelBlocksSimulation`;
    /// at the manager level the unknown device stages all 9 — see
    /// `RegionModeTests`.)
    func testUnknownNativeStatusFailsClosed() {
        XCTAssertFalse(SafePatchProposal.isNativeAppleIntelligence(profile: nil),
                       "No profile reads as non-native")
        let unknownProfile = profileWithUnknownNative(productType: "iPhone99,9")
        XCTAssertFalse(SafePatchProposal.isNativeAppleIntelligence(profile: unknownProfile),
                       "Unknown product type reads as non-native")
        let proposal = SafePatchProposal.oneTap(nativeAppleIntelligence: false)
        // 9 feature IDs, not 10: the fail-closed one-tap stages 10
        // FIELDS (2 eSIM keys + region + 7 AI keys), but eSIM is a
        // single feature ID covering both keys, so featureIDs has 9.
        XCTAssertEqual(proposal.featureIDs.count, 9,
                       "Fail-closed one-tap still carries all 9 feature IDs (10 staged fields)")
        XCTAssertTrue(proposal.skippedFeatureIDs.isEmpty,
                      "Fail-closed one-tap skips nothing")
    }

    /// A profile whose native flag is `.unknown`, so the helper must
    /// fall back to the product-type list (or fail closed when the
    /// product type is unknown too).
    private func profileWithUnknownNative(productType: String) -> DeviceProfile {
        DeviceProfile(
            productType: .known(productType),
            modelNumber: .known("A1234"),
            osVersion: .known("27.0.1"),
            osBuild: .known("23A344"),
            regionCode: .known("CH"),
            salesRegionSuffix: .known("CH/A"),
            isNativeAppleIntelligence: .unknown(reason: "test"),
            modelDecision: DeviceModelSupport.decision(for: productType, originalRegModel: nil),
            cacheLayout: .known(MobileGestaltCacheLayout.originalProfile),
            cacheReadState: .read(cacheUUID: CoreModuleFixtures.uuid, byteCount: CoreModuleFixtures.layout.byteCount),
            liveAIEnabled: .unknown(reason: "test"),
            liveRegionCode: .known("CH"),
            appGroupAvailable: .known(true),
            shareExtensionPresent: .known(false),
            backupCount: 0,
            hasTrustedBackup: false,
            changeRecordCount: 0)
    }
}
