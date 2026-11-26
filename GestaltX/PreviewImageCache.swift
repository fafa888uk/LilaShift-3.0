// SPDX-License-Identifier: GPL-3.0-only
// Preview image cache (Stage 9, TASKBOOK §8.2).
//
// A view body must never re-decode the same preview bytes on every
// render: `UIImage(data:)` in a body decodes again each time the
// view re-evaluates. This cache holds the decoded image once per
// key — the decode itself runs in a detached task at the call site
// (see `CustomizationModel.loadPreviews`), and the view reads the
// decoded image back from here instead of decoding in its body.
//
// Main-actor isolated: owners (models) and readers (views) are all
// main-actor, so no locking is needed. The stored images are
// thumbnails; the cache holds at most one image per preview key and
// drops entries when the underlying preview is deleted.
import UIKit

/// Decoded preview images, keyed once and read back by views.
@MainActor
final class PreviewImageCache {
    private var images: [AnyHashable: UIImage] = [:]

    /// The decoded image for a key, or `nil` when it has not been
    /// decoded (or was removed).
    func image<Key: Hashable>(for key: Key) -> UIImage? {
        images[AnyHashable(key)]
    }

    /// Stores a decoded image for a key, replacing any previous
    /// image for that key.
    func store<Key: Hashable>(_ image: UIImage, for key: Key) {
        images[AnyHashable(key)] = image
    }

    /// Drops the image for one key.
    func remove<Key: Hashable>(for key: Key) {
        images.removeValue(forKey: AnyHashable(key))
    }

    /// Drops all stored images.
    func removeAll() {
        images.removeAll()
    }

    /// The number of stored images (tests and diagnostics only).
    var count: Int { images.count }
}
