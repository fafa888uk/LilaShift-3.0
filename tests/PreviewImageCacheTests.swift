// SPDX-License-Identifier: GPL-3.0-only
// PreviewImageCache tests (Stage 9, TASKBOOK §8.2).
//
// These pin the cache contract the views rely on: a stored image is
// returned for its key (so the body never re-decodes), a miss
// returns nil, storing replaces, and removals drop exactly what
// they claim. The decode itself is not tested here —
// `UIImage(data:)` is Apple's API; the cache's job is to hold the
// decoded result once.
import UIKit
import XCTest
@testable import GestaltX

final class PreviewImageCacheTests: XCTestCase {
    /// A 1×1 transparent PNG, decoded once per test file run.
    private func testImage() throws -> UIImage {
        let base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let data = try XCTUnwrap(Data(base64Encoded: base64), "Test PNG must decode from base64")
        return try XCTUnwrap(UIImage(data: data), "Test PNG must decode to an image")
    }

    @MainActor
    func testStoreAndLookupReturnsSameImage() throws {
        let cache = PreviewImageCache()
        let image = try testImage()
        cache.store(image, for: UUID())
        // A fresh UUID key misses; the stored key hits with the
        // identical image instance (no second decode).
        XCTAssertNil(cache.image(for: UUID()), "An unknown key misses")
        let key = UUID()
        cache.store(image, for: key)
        XCTAssertTrue(cache.image(for: key) === image, "Lookup returns the stored image instance")
    }

    @MainActor
    func testLookupMissReturnsNil() {
        let cache = PreviewImageCache()
        XCTAssertNil(cache.image(for: "never-stored"), "A miss returns nil, never a placeholder")
        XCTAssertEqual(cache.count, 0, "A miss stores nothing")
    }

    @MainActor
    func testStoreReplacesPreviousImage() throws {
        let cache = PreviewImageCache()
        let first = try testImage()
        let second = try testImage()
        let key = "pack"
        cache.store(first, for: key)
        cache.store(second, for: key)
        XCTAssertTrue(cache.image(for: key) === second, "Storing replaces the previous image for the key")
        XCTAssertEqual(cache.count, 1, "Replacing does not add a second entry")
    }

    @MainActor
    func testRemoveDropsOneKey() throws {
        let cache = PreviewImageCache()
        let image = try testImage()
        cache.store(image, for: "a")
        cache.store(image, for: "b")
        cache.remove(for: "a")
        XCTAssertNil(cache.image(for: "a"), "The removed key misses")
        XCTAssertNotNil(cache.image(for: "b"), "Other keys are untouched")
        XCTAssertEqual(cache.count, 1)
    }

    @MainActor
    func testRemoveAllDropsEverything() throws {
        let cache = PreviewImageCache()
        let image = try testImage()
        cache.store(image, for: "a")
        cache.store(image, for: "b")
        cache.removeAll()
        XCTAssertNil(cache.image(for: "a"))
        XCTAssertNil(cache.image(for: "b"))
        XCTAssertEqual(cache.count, 0)
    }

    @MainActor
    func testCountTracksStoredImages() throws {
        let cache = PreviewImageCache()
        let image = try testImage()
        XCTAssertEqual(cache.count, 0)
        cache.store(image, for: UUID())
        cache.store(image, for: UUID())
        XCTAssertEqual(cache.count, 2, "Two distinct keys store two images")
    }
}
