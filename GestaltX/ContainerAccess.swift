// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// Grants this app access to a system-group container path via the
/// bundled `worse_query` sandbox escape (forcequitOS, GPL-3.0-or-later),
/// following the same pattern `GestaltManager` uses for the MobileGestalt
/// cache: try each signed App Group until one yields a usable handle.
/// The mechanism is Erosion-CN's `WorseQuery.grantAccess` (Kianuni,
/// GPL-3.0), reimplemented for LilaShift's entitlement reader and
/// bridging header. Handles are cached per canonical path and released
/// explicitly; a granted path is verified readable (and writable when
/// requested) before it is reported as granted, so callers never trust
/// a handle that did not actually open the path.
enum ContainerAccess {
    private static let handleLock = NSLock()
    private static var activeHandles: [String: Int64] = [:]

    /// A failed access grant. `handle` is the raw `worse_query` result
    /// (negative codes match the C function's error convention).
    struct GrantResult {
        let granted: Bool
        let handle: Int64
        let error: String?
    }

    static func grantAccess(path: String, requireWrite: Bool = false) -> GrantResult {
        let canonical = (path as NSString).standardizingPath
        guard !canonical.isEmpty else {
            return GrantResult(granted: false, handle: 0, error: L("Target path is empty."))
        }
        let fm = FileManager.default
        handleLock.lock()
        if let existing = activeHandles[canonical],
           fm.isReadableFile(atPath: canonical) && (!requireWrite || fm.isWritableFile(atPath: canonical)) {
            handleLock.unlock()
            return GrantResult(granted: true, handle: existing, error: nil)
        }
        handleLock.unlock()

        let signedGroups = GXEntitlementsReader.usableAppGroups()
        guard !signedGroups.isEmpty else {
            return GrantResult(granted: false, handle: -1, error: L("The signed app has no usable App Group. Enable its App Group capability and sign it again."))
        }
        var rejection: Int64 = -1
        var handle: Int64 = -1
        for group in signedGroups {
            var attempt = worse_query(canonical, group, false, false)
            if attempt == -4, let root = fm.containerURL(forSecurityApplicationGroupIdentifier: group) {
                // The exploit swaps Library/Caches for a symlink, so a
                // container without Library fails until the directory exists.
                try? fm.createDirectory(at: root.appendingPathComponent("Library/Caches"),
                                        withIntermediateDirectories: true)
                attempt = worse_query(canonical, group, false, false)
            }
            if attempt >= 0 {
                handle = attempt
                break
            }
            rejection = attempt
        }
        if handle < 0 {
            return GrantResult(granted: false, handle: rejection, error: errorMessage(for: rejection))
        }
        let readable = fm.isReadableFile(atPath: canonical)
        let writable = fm.isWritableFile(atPath: canonical)
        guard readable, !requireWrite || writable else {
            worse_query_release(handle)
            return GrantResult(granted: false, handle: handle,
                               error: requireWrite
                               ? L("That path still cannot be read and written by this app.")
                               : L("That path still cannot be read by this app."))
        }
        handleLock.lock()
        if let old = activeHandles[canonical], old >= 0, old != handle {
            worse_query_release(old)
        }
        activeHandles[canonical] = handle
        handleLock.unlock()
        return GrantResult(granted: true, handle: handle, error: nil)
    }

    static func hasActiveAccess(path: String) -> Bool {
        let canonical = (path as NSString).standardizingPath
        handleLock.lock()
        defer { handleLock.unlock() }
        return activeHandles[canonical] != nil
    }

    static func releaseAccess(path: String) {
        let canonical = (path as NSString).standardizingPath
        handleLock.lock()
        let handle = activeHandles.removeValue(forKey: canonical)
        handleLock.unlock()
        if let handle, handle >= 0 {
            worse_query_release(handle)
        }
    }

    private static func errorMessage(for code: Int64) -> String {
        switch code {
        case -1: return L("Could not access the App Group.")
        case -2: return L("Could not resolve the system functions.")
        case -3: return L("Could not create the query handle.")
        case -4: return L("Could not create the symbolic link.")
        case -5: return L("The sandbox query was denied.")
        case -6: return L("The kernel refused the sandbox extension token for this path.")
        case -255: return L("The target path does not exist.")
        default: return L("Access was denied.")
        }
    }
}
