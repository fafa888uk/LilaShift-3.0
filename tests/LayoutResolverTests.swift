// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import XCTest
@testable import GestaltX

/// LayoutResolver pure-function tests (ADR-2-11, Stage 4).
///
/// Every assertion builds its input from raw bytes only — the
/// CacheUUID string and the CacheData bytes — never from a
/// `GestaltDocument` passed to the resolver. Fixtures reuse
/// `CoreModuleFixtures` (the offline `originalProfile` layout:
/// uuid 7F1DF278-..., 720 slots, 6480 bytes).
final class LayoutResolverTests: XCTestCase {
    private var matchingUUID: String { CoreModuleFixtures.uuid }
    private var matchingData: Data {
        CoreModuleFixtures.cacheData(greenTea: true, notGreenTea: false, wapi: true)
    }

    func testResolveAcceptsMatchingRawBytes() throws {
        let layout = try LayoutResolver.resolve(cacheUUID: matchingUUID, cacheData: matchingData)
        XCTAssertEqual(layout, MobileGestaltCacheLayout.originalProfile)
    }

    func testResolveRejectsUnknownUUID() {
        XCTAssertThrowsError(
            try LayoutResolver.resolve(cacheUUID: "00000000-0000-0000-0000-000000000000", cacheData: matchingData),
            "A UUID the layout does not know fails to resolve")
    }

    func testResolveRejectsWrongLength() {
        let truncated = matchingData.prefix(100)
        XCTAssertThrowsError(
            try LayoutResolver.resolve(cacheUUID: matchingUUID, cacheData: Data(truncated)),
            "CacheData of the wrong length fails to resolve")
    }

    func testResolveRejectsNilInputs() {
        XCTAssertThrowsError(try LayoutResolver.resolve(cacheUUID: nil, cacheData: matchingData),
                             "A missing CacheUUID fails to resolve")
        XCTAssertThrowsError(try LayoutResolver.resolve(cacheUUID: matchingUUID, cacheData: nil),
                             "Missing CacheData fails to resolve")
        XCTAssertThrowsError(try LayoutResolver.resolve(cacheUUID: nil, cacheData: nil),
                             "Missing UUID and CacheData fail to resolve")
    }

    func testMatchesIsCaseInsensitiveForUUID() {
        XCTAssertTrue(LayoutResolver.matches(MobileGestaltCacheLayout.originalProfile,
                                            cacheUUID: matchingUUID.lowercased(), cacheData: matchingData),
                      "The resolver must accept the equivalent UUID spelling")
        XCTAssertFalse(LayoutResolver.matches(MobileGestaltCacheLayout.originalProfile,
                                             cacheUUID: "00000000-0000-0000-0000-000000000000", cacheData: matchingData))
        XCTAssertFalse(LayoutResolver.matches(MobileGestaltCacheLayout.originalProfile,
                                             cacheUUID: matchingUUID, cacheData: nil))
    }

    func testLockReasonIsNilForMatchingBytesAndSetOtherwise() {
        XCTAssertNil(LayoutResolver.lockReason(cacheUUID: matchingUUID, cacheData: matchingData))
        XCTAssertNotNil(LayoutResolver.lockReason(cacheUUID: "00000000-0000-0000-0000-000000000000", cacheData: matchingData))
        XCTAssertNotNil(LayoutResolver.lockReason(cacheUUID: matchingUUID, cacheData: nil))
    }

    /// The resolver reads raw parts only: two documents with the same
    /// UUID and CacheData but different CacheExtra resolve identically,
    /// so no CacheExtra content can change the layout decision.
    func testResolveUsesOnlyRawParts() throws {
        let first = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "CH"])
        let second = try CoreModuleFixtures.document(extra: [GestaltKeys.regionCode: "LL"])
        let fromFirst = try LayoutResolver.resolve(cacheUUID: first.cacheUUID, cacheData: first.cacheData)
        let fromSecond = try LayoutResolver.resolve(cacheUUID: second.cacheUUID, cacheData: second.cacheData)
        XCTAssertEqual(fromFirst, fromSecond)
        XCTAssertEqual(fromFirst, MobileGestaltCacheLayout.originalProfile)
    }

    /// The document's own cache setters still work through the new
    /// path: `setCacheOptions` resolves via `LayoutResolver` from the
    /// document's raw parts, with the same result as before.
    func testDocumentSettersResolveThroughLayoutResolver() throws {
        var document = try CoreModuleFixtures.document(greenTea: true, notGreenTea: false)
        try document.setCacheOptions(.enabled)
        XCTAssertEqual(try DeviceCacheOptions.flags(in: document), .enabled)
        try document.setWAPI(false)
        XCTAssertEqual(try DeviceCacheOptions.wapi(in: document), false)
    }
}
