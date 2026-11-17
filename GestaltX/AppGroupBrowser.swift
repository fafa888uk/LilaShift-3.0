// SPDX-License-Identifier: GPL-3.0-only
import Foundation
import SQLite3

/// A shared AppGroup container detected on the device (A11).
struct AppGroupContainer: Identifiable, Equatable, Codable {
    let id: String
    let groupID: String
    let path: String
    let clientName: String?

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

/// Read-only cross-container AppGroup discovery and browsing (A11).
/// The mechanism follows Erosion-CN's `AppGroupHubView` (Kianuni,
/// GPL-3.0), reimplemented for LilaShift's access helper: shared
/// AppGroup containers are enumerated under
/// `/var/mobile/Containers/Shared/AppGroup`, and each container's
/// group ID is read from its `com.apple.containermanager.identifier`
/// xattr (falling back to the container metadata plist's
/// `MCMMetadataIdentifier`). A group is only reported when its
/// identity could be read — a container whose owner cannot be
/// verified is never listed as belonging to an app. For a single
/// app, `groups(for:)` prefers the LaunchServices-cache validated
/// map (`GXCustomizationAccess.applicationGroupContainers(for:)`),
/// which never infers ownership from group names. Browsing is
/// read-only: it lists names and sizes inside a granted container
/// and never writes, deletes, or modifies anything there.
enum AppGroupDiscovery {
    static let sharedAppGroupDirectory = "/var/mobile/Containers/Shared/AppGroup"

    /// Known proxy clients and their AppGroup IDs (Erosion-CN's map).
    static let knownProxyGroups: [String: String] = [
        "group.com.nssurge.inc.surge-ios": "Surge",
        "group.com.nssurge.inc.surge-ios-tf": "Surge (TestFlight)",
        "group.com.liguangming.Shadowrocket": "Shadowrocket",
        "group.com.luo.quantumult-x": "Quantumult X",
        "group.com.loon.loon": "Loon",
        "group.com.loon0x00.loon": "Loon",
        "group.ws.stash.app": "Stash",
    ]

    /// Verified AppGroup containers for one app, from the
    /// LaunchServices cache (ownership validated, never inferred).
    static func groups(for bundleID: String) -> [AppGroupContainer] {
        #if os(iOS) && !targetEnvironment(simulator)
        let verified = GXCustomizationAccess.applicationGroupContainers(for: bundleID)
        return verified.map { groupID, path in
            AppGroupContainer(id: path, groupID: groupID, path: path,
                              clientName: knownProxyGroups[groupID])
        }.sorted { $0.groupID < $1.groupID }
        #else
        return []
        #endif
    }

    /// All shared AppGroup containers whose group ID could be read
    /// from the container xattr or metadata plist. Containers with
    /// an unreadable identity are skipped, never guessed.
    static func scanSharedGroups() -> [AppGroupContainer] {
        let fm = FileManager.default
        let wasActive = ContainerAccess.hasActiveAccess(path: sharedAppGroupDirectory)
        let grant = ContainerAccess.grantAccess(path: sharedAppGroupDirectory, requireWrite: false)
        guard grant.granted else { return [] }
        defer {
            if !wasActive {
                ContainerAccess.releaseAccess(path: sharedAppGroupDirectory)
            }
        }
        guard let entries = try? fm.contentsOfDirectory(atPath: sharedAppGroupDirectory) else { return [] }
        var found: [AppGroupContainer] = []
        for entry in entries {
            let path = sharedAppGroupDirectory + "/" + entry
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
            let url = URL(fileURLWithPath: path, isDirectory: true)
            guard let groupID = groupID(for: url), !groupID.isEmpty else { continue }
            found.append(AppGroupContainer(id: path, groupID: groupID, path: path,
                                           clientName: knownProxyGroups[groupID]))
        }
        return found.sorted { ($0.clientName ?? $0.groupID) < ($1.clientName ?? $1.groupID) }
    }

    /// Proxy-client groups only, sorted by client name.
    static func scanProxyGroups() -> [AppGroupContainer] {
        scanSharedGroups().filter { $0.clientName != nil }
    }

    /// Reads a container's group/bundle ID from its
    /// `com.apple.containermanager.identifier` xattr, falling back to
    /// the container metadata plist. Returns `nil` when neither
    /// yields an identity.
    static func groupID(for url: URL) -> String? {
        var buf = [CChar](repeating: 0, count: 512)
        let len = getxattr(url.path, "com.apple.containermanager.identifier", &buf, 511, 0, XATTR_NOFOLLOW)
        if len >= 0 {
            let id = String(cString: buf)
            if !id.isEmpty { return id }
        }
        for metaName in [".com.apple.mobile_container_manager.metadata.plist",
                         "com.apple.mobile_container_manager.metadata.plist"] {
            let metaURL = url.appendingPathComponent(metaName)
            guard let data = try? Data(contentsOf: metaURL),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let id = plist["MCMMetadataIdentifier"] as? String, !id.isEmpty else { continue }
            return id
        }
        return nil
    }
}

/// A single Safari bookmark row, read-only (A11 / A17 groundwork).
struct SafariBookmarkRecord: Identifiable, Equatable, Codable {
    let id: Int64
    let title: String
    let url: String
}

enum SafariBookmarks {
    /// Reads Safari bookmarks from a `Bookmarks.db` through an APFS
    /// clonefile snapshot (read-only; the live database is never
    /// locked). Returns an empty list when the table is absent.
    static func read(at dbPath: String, limit: Int = 5000) -> [SafariBookmarkRecord] {
        do {
            return try SQLiteSnapshotHelper.withClonedDatabase(at: dbPath) { db in
                let cols = SQLiteSnapshotHelper.columnNames(in: "bookmarks", db: db)
                guard cols.contains("url") else { return [] }
                let titleCol = cols.contains("title") ? "\"title\"" : "''"
                let sql = "SELECT rowid, \(titleCol), url FROM bookmarks WHERE url IS NOT NULL AND url != '' ORDER BY rowid ASC LIMIT \(max(1, limit));"
                var stmt: OpaquePointer?
                guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let validStmt = stmt else {
                    return []
                }
                defer { sqlite3_finalize(validStmt) }
                var records: [SafariBookmarkRecord] = []
                while sqlite3_step(validStmt) == SQLITE_ROW {
                    guard let rowid = SQLiteSnapshotHelper.int64Col(validStmt, 0),
                          let url = SQLiteSnapshotHelper.stringCol(validStmt, 2) else { continue }
                    records.append(SafariBookmarkRecord(id: rowid,
                                                        title: SQLiteSnapshotHelper.stringCol(validStmt, 1) ?? "",
                                                        url: url))
                }
                return records
            }
        } catch {
            return []
        }
    }
}

/// Read-only listing inside a granted AppGroup container (A11).
/// Only names, sizes and directory flags are returned; file contents
/// are never read here, and nothing is ever written.
enum AppGroupBrowser {
    struct Entry: Identifiable, Equatable {
        let id: String
        let name: String
        let isDirectory: Bool
        let byteCount: Int64
    }

    /// Lists one directory inside a container the app has access to.
    /// `relativePath` must stay inside the container (no `..`, no
    /// leading slash, no empty components). Returns an empty list
    /// when the directory cannot be read. On a device the directory
    /// is opened through `ContainerAccess`; when the directory is
    /// already directly readable (tests, or a container the app owns)
    /// the direct read is used and no grant is attempted.
    static func list(container: AppGroupContainer, relativePath: String = "") -> [Entry] {
        guard Self.validRelativePath(relativePath) else { return [] }
        let base = container.url
        let target = relativePath.isEmpty ? base : base.appendingPathComponent(relativePath)
        // Resolve symlinks and require the target to stay inside the container.
        let resolvedBase = base.standardizedFileURL.path
        let resolvedTarget = target.standardizedFileURL.path
        guard resolvedTarget == resolvedBase || resolvedTarget.hasPrefix(resolvedBase + "/") else { return [] }
        let entries = tryList(resolvedTarget)
        if !entries.isEmpty {
            return entries
        }
        // An empty result is ambiguous: the directory may be directly
        // readable but empty, or unreadable. Only attempt the grant
        // when the direct read actually failed — a directly readable
        // directory never needs a grant, even when it is empty.
        if FileManager.default.isReadableFile(atPath: resolvedTarget) {
            return entries
        }
        let grant = ContainerAccess.grantAccess(path: resolvedTarget, requireWrite: false)
        guard grant.granted else { return [] }
        defer { ContainerAccess.releaseAccess(path: resolvedTarget) }
        return tryList(resolvedTarget)
    }

    private static func tryList(_ path: String) -> [Entry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        var entries: [Entry] = []
        for name in names.sorted() where !name.hasPrefix(".") {
            let itemPath = path + "/" + name
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDir) else { continue }
            let size = (try? FileManager.default.attributesOfItem(atPath: itemPath)[.size] as? Int64) ?? 0
            entries.append(Entry(id: itemPath, name: name, isDirectory: isDir.boolValue, byteCount: size))
        }
        return entries
    }

    static func validRelativePath(_ path: String) -> Bool {
        if path.isEmpty { return true }
        if path.hasPrefix("/") || path.contains("\\") || path.contains("\0") { return false }
        // omittingEmptySubsequences: false so "a//b" splits into
        // ["a", "", "b"] and the empty component is rejected below.
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }
}
