// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Pure-function layout resolution (ADR-2-11, Stage 4).
///
/// This breaks the `GestaltDocument` <-> `MobileGestaltCacheLayout`
/// cycle: resolution takes raw cache bytes — the CacheUUID string and
/// the CacheData bytes — never a `GestaltDocument`, and performs no
/// file I/O. The only runtime input is the cached scan of this
/// launch's loaded `libMobileGestalt.dylib` (in-memory only, read
/// once per launch). Callers pass a document's raw parts
/// (`document.cacheUUID`, `document.cacheData`).
///
/// Signature note: the ADR sketch named the inputs
/// `(cacheData: Data, cacheExtra: [String: Any])`, but layout
/// matching never reads CacheExtra — it needs the root-level
/// CacheUUID and the CacheData bytes. The signature takes exactly
/// those two inputs; nothing else is consulted, so a test fixture
/// built from bytes alone fully determines the result.
enum LayoutResolver {
    /// The layout scanned from this launch's loaded library, if the
    /// scan succeeded. Exposed only so diagnostics can name which
    /// profile matched; resolution itself goes through `resolve`.
    static let runtimeProfile: MobileGestaltCacheLayout? = {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let image = GXCopyMobileGestaltImage() else { return nil }
        return try? MobileGestaltCacheLayout.scan(image: image)
        #else
        return nil
        #endif
    }()

    /// The runtime layout resolved from this launch's loaded library, if
    /// the scan succeeded.
    static func runtimeLayout() -> MobileGestaltCacheLayout? { runtimeProfile }

    /// Whether `layout` matches these raw cache bytes: the slot
    /// indices are in range and distinct, the CacheUUID matches
    /// (case-insensitive), and the CacheData length matches the
    /// layout's byte count. A `nil` UUID or `nil` CacheData never
    /// matches — an unknown layout is reported, never borrowed.
    static func matches(_ layout: MobileGestaltCacheLayout, cacheUUID: String?, cacheData: Data?) -> Bool {
        guard (1...16384).contains(layout.slotCount), (0..<layout.slotCount).contains(layout.greenTeaIndex),
              (0..<layout.slotCount).contains(layout.notGreenTeaIndex), layout.greenTeaIndex != layout.notGreenTeaIndex,
              let uuid = cacheUUID,
              let data = cacheData else { return false }
        if let wapiIndex = layout.wapiIndex, (!(0..<layout.slotCount).contains(wapiIndex) || wapiIndex == layout.greenTeaIndex || wapiIndex == layout.notGreenTeaIndex) { return false }
        for index in [layout.audioIntellIndex, layout.personalTranslatorIndex].compactMap({ $0 }) {
            guard (0..<layout.slotCount).contains(index), index != layout.greenTeaIndex, index != layout.notGreenTeaIndex,
                  index != layout.wapiIndex else { return false }
        }
        return layout.uuid.caseInsensitiveCompare(uuid) == .orderedSame && data.count == layout.byteCount
    }

    /// The reason the cache layout cannot be resolved for these raw
    /// cache bytes, or `nil` when it resolves. This is the lock reason
    /// for the eSIM / WAPI switches: when it is non-nil the switches
    /// stay locked and this string is shown, rather than falling back
    /// to any layout. On a device build a failed runtime scan lands
    /// here; the hardcoded offline profile is never substituted.
    static func lockReason(cacheUUID: String?, cacheData: Data?) -> String? {
        do {
            _ = try resolve(cacheUUID: cacheUUID, cacheData: cacheData)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Resolves the cache layout for these raw cache bytes.
    /// On device the hardcoded layout is never silently used. If the
    /// runtime scan failed, the eSIM switches lock and the reason is
    /// shown instead of guessing a layout that may not match this iOS
    /// build. The offline profile below exists only for the simulator
    /// and the offline test fixtures, where no library can be scanned.
    static func resolve(cacheUUID: String?, cacheData: Data?) throws -> MobileGestaltCacheLayout {
        #if os(iOS) && !targetEnvironment(simulator)
        guard let runtime = runtimeProfile else {
            throw GestaltFailure("Unable to resolve this device's MobileGestalt cache layout.")
        }
        guard matches(runtime, cacheUUID: cacheUUID, cacheData: cacheData) else {
            throw GestaltFailure("Unable to resolve this device's MobileGestalt cache layout.")
        }
        return runtime
        #else
        for layout in [runtimeProfile, MobileGestaltCacheLayout.originalProfile].compactMap({ $0 }) {
            if matches(layout, cacheUUID: cacheUUID, cacheData: cacheData) { return layout }
        }
        throw GestaltFailure("Unable to resolve this device's MobileGestalt cache layout.")
        #endif
    }
}
