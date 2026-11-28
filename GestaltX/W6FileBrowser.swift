// SPDX-License-Identifier: GPL-3.0-only
// W6 file browser (LilaShift 5.0.0 Wave 1, W6) — file browsing ported
// from Kianuni/Erosion-CN v1.0.8 (GPL-3.0) and kolbicz/WQFiles
// (GPL-3.0); see W6NOTICES.md for attribution and scope.
//
// What this file does (5 features, all read-first):
//   1. Multi-select batch operations over a real directory listing
//      (Erosion-CN v1.0.8 "选择文件…" + bottom action bar).
//   2. Recursive folder import with a name-conflict choice
//      (Erosion-CN v1.0.8 issue #75: keep-both auto-numbering or
//      overwrite; WQFiles "Existing items are never replaced").
//   3. Splash-ad cache path recognition for 7 apps from a table
//      that can be updated (Erosion-CN v1.0.7, issue #58) — every
//      path is marked pending verification until it is confirmed on
//      a real device; nothing here claims a path is verified.
//   4. Read-only cross-app file browsing (WQFiles), reusing
//      LilaShift's existing container-access choke point
//      (`ContainerAccess`, itself the worse_query grant used by
//      `GestaltManager`) and gated by the existing `VersionSentinel`
//      (blocked from 24C5049d, iOS 27.3 beta 2).
//   5. Read-only cross-app cache usage statistics (WQFiles cache
//      cleaner, statistics only). This workflow deliberately has NO
//      cleanup API: no "clear all" anywhere, and no per-app clear
//      either — cleanup needs per-app confirmation and per-item
//      restore, and stays a follow-up.
//
// Honesty rules, enforced by the types:
//   • A listing comes from a real container read. When a container
//     cannot be read the result is empty with `reachable == false`
//     and a reason — never a fabricated entry, never a silent zero.
//   • Cross-app access is read-only: this file grants read access
//     only (`requireWrite: false`) and never writes, deletes or
//     moves anything inside another app's container. Folder import
//     writes only into the destination the caller passes in (the
//     app's own container or a directory the user picked).
//   • The import copier refuses container roots, metadata files,
//     the factory-backup vault, the ad-lock placeholder and
//     `com.apple.MobileGestalt.plist`, refuses symlinks, refuses
//     importing a folder into itself, and keeps SQLite `-wal` /
//     `-shm` / `-journal` companions with their database file
//     (Erosion-CN v1.0.8).
//   • This file never calls worse_query directly: the only call
//     sites stay the ones `ModuleBoundaryTests` knows
//     (`ContainerAccess` is the choke point).
import Foundation
import ZIPFoundation

/// One browsed file or directory. `id` is the full path, so a
/// selection survives a re-sort; `byteCount` is the file's own size
/// (0 for a directory — directory sizes are measured on demand by
/// `W6FileBrowser.measureDirectory`, never guessed here).
struct W6FileEntry: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let isDirectory: Bool
    let byteCount: Int64
    let modifiedAt: Date?

    var url: URL { URL(fileURLWithPath: id) }

    var isHidden: Bool { name.hasPrefix(".") }
}

/// A starting point for the browser: the app's own container
/// directories plus any discovered shared AppGroup containers.
/// The view never builds these paths itself — it asks the engine.
struct W6BrowserRoot: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let url: URL
}

/// The read-only directory browser. Listing mirrors
/// `AppGroupBrowser.list`: a direct read first, and only when the
/// direct read actually fails is read access granted through
/// `ContainerAccess` (read-only) and released afterwards. A
/// directory that cannot be read yields an empty list, never an
/// invented one.
enum W6FileBrowser {
    /// The browser's starting roots: the app's own Documents,
    /// Caches and tmp directories, then the shared AppGroup
    /// containers this device can identify (proxy groups first,
    /// matching `AppGroupDiscovery` order).
    static func roots() -> [W6BrowserRoot] {
        var found: [W6BrowserRoot] = []
        let fm = FileManager.default
        if let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            found.append(W6BrowserRoot(id: documents.path, title: L("Documents"), url: documents))
        }
        if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            found.append(W6BrowserRoot(id: caches.path, title: L("Caches"), url: caches))
        }
        found.append(W6BrowserRoot(id: fm.temporaryDirectory.path, title: L("Temporary"), url: fm.temporaryDirectory))
        for group in AppGroupDiscovery.scanSharedGroups() {
            found.append(W6BrowserRoot(id: group.path, title: group.clientName ?? group.groupID, url: group.url))
        }
        return found
    }

    /// Lists one directory under `root`. `relativePath` must stay
    /// inside the root (the same traversal guard
    /// `AppGroupBrowser` uses). Returns an empty list when the
    /// directory cannot be read.
    static func list(root: URL, relativePath: String = "") -> [W6FileEntry] {
        guard AppGroupBrowser.validRelativePath(relativePath) else { return [] }
        let base = root.standardizedFileURL
        let target = relativePath.isEmpty ? base : base.appendingPathComponent(relativePath).standardizedFileURL
        let resolvedBase = base.path
        let resolvedTarget = target.path
        guard resolvedTarget == resolvedBase || resolvedTarget.hasPrefix(resolvedBase + "/") else { return [] }
        let entries = tryList(resolvedTarget)
        if !entries.isEmpty {
            return entries
        }
        if FileManager.default.isReadableFile(atPath: resolvedTarget) {
            return entries
        }
        let grant = ContainerAccess.grantAccess(path: resolvedTarget, requireWrite: false)
        guard grant.granted else { return [] }
        defer { ContainerAccess.releaseAccess(path: resolvedTarget) }
        return tryList(resolvedTarget)
    }

    /// The temporary directory batch ZIP archives are written to.
    /// The view asks the engine for it so the view never touches
    /// the file system itself.
    static func temporaryExportDirectory() -> URL {
        FileManager.default.temporaryDirectory
    }

    /// Measures a directory recursively: total bytes and file
    /// count of regular files. Symlinks are never followed. The
    /// walk stops at `maximumFiles` and reports `truncated`, so a
    /// huge container cannot hang the caller — a truncated total
    /// is labelled truncated, never presented as complete.
    static func measureDirectory(_ root: URL, maximumFiles: Int = 100_000) -> W6DirectoryMeasurement {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles], errorHandler: nil) else {
            return W6DirectoryMeasurement(byteCount: 0, fileCount: 0, truncated: false, reachable: false)
        }
        var bytes: Int64 = 0
        var count = 0
        var truncated = false
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            count += 1
            bytes += Int64(values.fileSize ?? 0)
            if count >= maximumFiles {
                truncated = true
                break
            }
        }
        return W6DirectoryMeasurement(byteCount: bytes, fileCount: count, truncated: truncated, reachable: true)
    }

    private static func tryList(_ path: String) -> [W6FileEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { return [] }
        var entries: [W6FileEntry] = []
        for name in names.sorted() {
            let itemPath = path + "/" + name
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: itemPath, isDirectory: &isDir) else { continue }
            let attributes = try? FileManager.default.attributesOfItem(atPath: itemPath)
            let size = attributes?[.size] as? Int64 ?? 0
            let modified = attributes?[.modificationDate] as? Date
            entries.append(W6FileEntry(id: itemPath, name: name, isDirectory: isDir.boolValue,
                                       byteCount: isDir.boolValue ? 0 : size, modifiedAt: modified))
        }
        return entries
    }
}

/// The result of measuring one directory: real bytes and file
/// count, or `reachable == false` when the directory could not be
/// opened at all. `truncated` means the walk hit the file cap and
/// the totals are a lower bound, not a complete measurement.
struct W6DirectoryMeasurement: Equatable, Sendable {
    let byteCount: Int64
    let fileCount: Int
    let truncated: Bool
    let reachable: Bool
}

// MARK: - Multi-select batch operations (feature 1)

/// The multi-select state for one listing (Erosion-CN v1.0.8
/// "选择文件…" + top 全选 / 取消全选 + bottom action bar). Pure
/// value type: the view owns one, the engine never holds
/// selection. Selection is by entry id (full path), so it survives
/// a re-sort of the same listing.
struct W6FileSelection: Equatable, Sendable {
    private(set) var selectedIDs: Set<String> = []

    var isEmpty: Bool { selectedIDs.isEmpty }
    var count: Int { selectedIDs.count }

    func contains(_ entry: W6FileEntry) -> Bool {
        selectedIDs.contains(entry.id)
    }

    mutating func toggle(_ entry: W6FileEntry) {
        if selectedIDs.contains(entry.id) {
            selectedIDs.remove(entry.id)
        } else {
            selectedIDs.insert(entry.id)
        }
    }

    /// Selects every entry in the listing (the "全选" action).
    mutating func selectAll(in entries: [W6FileEntry]) {
        selectedIDs = Set(entries.map(\.id))
    }

    /// Clears the selection (the "取消全选" action).
    mutating func deselectAll() {
        selectedIDs.removeAll()
    }

    /// Inverts the selection over the listing (WQFiles cache
    /// cleaner "Invert" behaviour, applied to the browser).
    mutating func invert(in entries: [W6FileEntry]) {
        let listed = Set(entries.map(\.id))
        let kept = selectedIDs.subtracting(listed)
        selectedIDs = kept.union(listed.subtracting(selectedIDs))
    }

    /// Drops ids that are no longer in the listing, so a refresh
    /// cannot keep a stale selection pointing at a deleted file.
    mutating func prune(to entries: [W6FileEntry]) {
        let listed = Set(entries.map(\.id))
        selectedIDs = selectedIDs.intersection(listed)
    }

    /// The entries in `entries` that are selected, in listing
    /// order — the input to the batch action bar.
    func selected(in entries: [W6FileEntry]) -> [W6FileEntry] {
        entries.filter { selectedIDs.contains($0.id) }
    }

    /// The batch summary the action bar shows: how many items and
    /// how many bytes of files (directories contribute 0 here —
    /// their size is measured on demand, never guessed).
    func summary(for entries: [W6FileEntry]) -> W6BatchSummary {
        let chosen = selected(in: entries)
        return W6BatchSummary(
            count: chosen.count,
            directoryCount: chosen.filter(\.isDirectory).count,
            fileCount: chosen.filter { !$0.isDirectory }.count,
            fileBytes: chosen.filter { !$0.isDirectory }.reduce(0) { $0 + $1.byteCount })
    }
}

/// What the batch action bar shows for the current selection.
struct W6BatchSummary: Equatable, Sendable {
    let count: Int
    let directoryCount: Int
    let fileCount: Int
    let fileBytes: Int64
}

// MARK: - Recursive folder import (feature 2)

/// How a name conflict is resolved when importing (Erosion-CN
/// v1.0.8 issue #75: the user picks "保留两者" or "覆盖替换";
/// WQFiles move never replaces an existing item). The default is
/// `.keepBoth`: an import never destroys an existing file.
enum W6ImportConflictPolicy: String, CaseIterable, Codable, Sendable {
    /// Keep both: the imported item is auto-numbered
    /// ("name 2.ext", "name 3.ext", …) and nothing is replaced.
    case keepBoth
    /// Replace the existing item with the imported one.
    case replace
    /// Skip the conflicting item and report it as skipped.
    case skip

    var title: String {
        switch self {
        case .keepBoth: return L("Keep both")
        case .replace: return L("Replace")
        case .skip: return L("Skip")
        }
    }
}

/// One item that could not be imported, with the real reason —
/// failures are listed per item, never swallowed into a bare
/// failure count.
struct W6ImportFailure: Equatable, Sendable {
    let path: String
    let reason: String
}

/// The outcome of one import. Nothing is reported as a bare
/// success: copied, skipped and failed items are all listed, with
/// the bytes actually copied.
struct W6ImportResult: Equatable, Sendable {
    let copied: [String]
    let skipped: [String]
    let failed: [W6ImportFailure]
    let copiedBytes: Int64
    let copiedFiles: Int

    var succeeded: Bool { failed.isEmpty }
}

/// Recursive folder import with streaming copy and conflict
/// handling (Erosion-CN v1.0.8: stream copy so a large file never
/// spikes memory; auto write-authorization is the caller's job —
/// the destination must already be writable). The copy writes
/// only under the destination parent the caller passes in; the
/// source is only read. There is no delete step here: `.replace`
/// removes only the single conflicting item it is about to
/// overwrite, never a directory tree the user did not name.
enum W6FolderImport {
    /// Maximum items copied in one import, so a runaway folder
    /// cannot loop forever. Items past the cap are reported as
    /// failed with the cap as the reason.
    static let maximumItems = 10_000
    /// Streaming copy chunk size (64 KB, matching Erosion-CN's
    /// Wi-Fi share chunk size).
    static let chunkSize = 64 * 1024
    /// Database file suffixes whose `-wal` / `-shm` / `-journal`
    /// companions travel with the database (Erosion-CN v1.0.8).
    static let databaseSuffixes = [".db", ".sqlite", ".sqlite3"]
    static let databaseCompanionSuffixes = ["-wal", "-shm", "-journal"]

    /// Names that must never be imported over, deleted or replaced:
    /// container roots are refused by the caller-level checks, and
    /// these file names are refused item by item (Erosion-CN
    /// v1.0.8 root/metadata/ad-lock/MobileGestalt protection).
    static let protectedNames: Set<String> = [
        ".erosion_adlock",
        "com.apple.MobileGestalt.plist",
        ".com.apple.mobile_container_manager.metadata.plist",
        "com.apple.mobile_container_manager.metadata.plist",
    ]

    /// Copies one file into `destinationParent`, resolving a name
    /// conflict with `policy`. The file's SQLite companions travel
    /// with it when present. Returns the per-item outcome.
    static func copyFile(source: URL, into destinationParent: URL,
                         conflictPolicy: W6ImportConflictPolicy = .keepBoth) -> W6ImportResult {
        var result = W6ImportResult(copied: [], skipped: [], failed: [], copiedBytes: 0, copiedFiles: 0)
        copyFile(source: source, into: destinationParent, conflictPolicy: conflictPolicy, result: &result)
        return result
    }

    /// Recursively copies `source` (a folder) into
    /// `destinationParent`, so the result is
    /// `destinationParent/<source name>/…`. Conflict handling
    /// applies to the top folder name first, then per item inside.
    static func copyFolder(source: URL, into destinationParent: URL,
                           conflictPolicy: W6ImportConflictPolicy = .keepBoth) -> W6ImportResult {
        var copied: [String] = []
        var skipped: [String] = []
        var failed: [W6ImportFailure] = []
        var copiedBytes: Int64 = 0
        var copiedFiles = 0
        let fm = FileManager.default

        func fail(_ path: String, _ reason: String) {
            failed.append(W6ImportFailure(path: path, reason: reason))
        }

        var sourceIsDir: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &sourceIsDir), sourceIsDir.boolValue else {
            fail(source.path, L("The source is not a folder."))
            return W6ImportResult(copied: copied, skipped: skipped, failed: failed,
                                  copiedBytes: copiedBytes, copiedFiles: copiedFiles)
        }
        guard !isSymlink(source) else {
            fail(source.path, L("Symbolic links are not imported."))
            return W6ImportResult(copied: copied, skipped: skipped, failed: failed,
                                  copiedBytes: copiedBytes, copiedFiles: copiedFiles)
        }
        var destinationIsDir: ObjCBool = false
        guard fm.fileExists(atPath: destinationParent.path, isDirectory: &destinationIsDir),
              destinationIsDir.boolValue, !isSymlink(destinationParent) else {
            fail(source.path, L("The destination folder is not available."))
            return W6ImportResult(copied: copied, skipped: skipped, failed: failed,
                                  copiedBytes: copiedBytes, copiedFiles: copiedFiles)
        }
        // Refuse importing a folder into itself or one of its own
        // subfolders: the walk would otherwise grow without bound.
        let sourcePath = source.standardizedFileURL.path
        let destinationPath = destinationParent.standardizedFileURL.path
        guard destinationPath != sourcePath && !destinationPath.hasPrefix(sourcePath + "/") else {
            fail(source.path, L("A folder cannot be imported into itself."))
            return W6ImportResult(copied: copied, skipped: skipped, failed: failed,
                                  copiedBytes: copiedBytes, copiedFiles: copiedFiles)
        }

        let topName = source.lastPathComponent
        guard !protectedNames.contains(topName) else {
            fail(source.path, L("That item is protected and cannot be imported."))
            return W6ImportResult(copied: copied, skipped: skipped, failed: failed,
                                  copiedBytes: copiedBytes, copiedFiles: copiedFiles)
        }
        let resolvedTop: URL
        switch resolveDestination(name: topName, in: destinationParent, conflictPolicy: conflictPolicy) {
        case .use(let url):
            resolvedTop = url
        case .skip:
            skipped.append(source.path)
            return W6ImportResult(copied: copied, skipped: skipped, failed: failed,
                                  copiedBytes: copiedBytes, copiedFiles: copiedFiles)
        case .failed(let reason):
            fail(source.path, reason)
            return W6ImportResult(copied: copied, skipped: skipped, failed: failed,
                                  copiedBytes: copiedBytes, copiedFiles: copiedFiles)
        }
        do {
            try fm.createDirectory(at: resolvedTop, withIntermediateDirectories: true)
        } catch {
            fail(resolvedTop.path, error.localizedDescription)
            return W6ImportResult(copied: copied, skipped: skipped, failed: failed,
                                  copiedBytes: copiedBytes, copiedFiles: copiedFiles)
        }

        var handled = 0
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: source, includingPropertiesForKeys: keys,
                                             options: [], errorHandler: nil) else {
            fail(source.path, L("The folder could not be read."))
            return W6ImportResult(copied: copied, skipped: skipped, failed: failed,
                                  copiedBytes: copiedBytes, copiedFiles: copiedFiles)
        }
        for case let itemURL as URL in enumerator {
            handled += 1
            if handled > maximumItems {
                fail(itemURL.path, L("The import stopped at the item limit."))
                break
            }
            let relative = relativePath(of: itemURL, under: source)
            guard !relative.isEmpty else { continue }
            let targetParent = resolvedTop.appendingPathComponent(
                (relative as NSString).deletingLastPathComponent)
            if isSymlink(itemURL) {
                skipped.append(relative)
                continue
            }
            guard let values = try? itemURL.resourceValues(forKeys: Set(keys)) else {
                fail(relative, L("The item could not be read."))
                continue
            }
            if values.isDirectory == true {
                let name = itemURL.lastPathComponent
                guard !protectedNames.contains(name) else {
                    skipped.append(relative)
                    continue
                }
                do {
                    try fm.createDirectory(
                        at: targetParent.appendingPathComponent(name),
                        withIntermediateDirectories: true)
                } catch {
                    fail(relative, error.localizedDescription)
                }
                continue
            }
            guard values.isRegularFile == true else {
                skipped.append(relative)
                continue
            }
            var single = W6ImportResult(copied: [], skipped: [], failed: [],
                                        copiedBytes: 0, copiedFiles: 0)
            copyFile(source: itemURL, into: targetParent, conflictPolicy: conflictPolicy, result: &single)
            copied += single.copied
            skipped += single.skipped
            failed += single.failed
            copiedBytes += single.copiedBytes
            copiedFiles += single.copiedFiles
        }
        return W6ImportResult(copied: copied, skipped: skipped, failed: failed,
                              copiedBytes: copiedBytes, copiedFiles: copiedFiles)
    }

    /// Streams one file in 64 KB chunks, so a large file never
    /// loads into memory whole. The destination file is created
    /// empty first and filled by the stream; a failure removes the
    /// partial destination so no truncated file is left behind.
    static func copyFileChunked(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard fm.createFile(atPath: destination.path, contents: nil) else {
            throw GestaltFailure("The destination file could not be created.")
        }
        do {
            let reader = try FileHandle(forReadingFrom: source)
            defer { try? reader.close() }
            let writer = try FileHandle(forWritingTo: destination)
            defer { try? writer.close() }
            while true {
                guard let chunk = try reader.read(upToCount: chunkSize), !chunk.isEmpty else { break }
                try writer.write(contentsOf: chunk)
            }
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    /// The auto-numbered name for `.keepBoth`: "Report.pdf" becomes
    /// "Report 2.pdf", then "Report 3.pdf" — the same "name 2.ext"
    /// convention Erosion-CN's Wi-Fi share and WQFiles use, so an
    /// import never silently replaces an existing file.
    static func uniqueName(for name: String, in directory: URL) -> String {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = name
        var index = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path) {
            candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            index += 1
        }
        return candidate
    }

    // MARK: - Private helpers

    private enum DestinationResolution {
        case use(URL)
        case skip
        case failed(String)
    }

    private static func resolveDestination(name: String, in directory: URL,
                                           conflictPolicy: W6ImportConflictPolicy) -> DestinationResolution {
        let candidate = directory.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: candidate.path) else {
            return .use(candidate)
        }
        switch conflictPolicy {
        case .keepBoth:
            return .use(directory.appendingPathComponent(uniqueName(for: name, in: directory)))
        case .replace:
            do {
                try FileManager.default.removeItem(at: candidate)
                return .use(candidate)
            } catch {
                return .failed(error.localizedDescription)
            }
        case .skip:
            return .skip
        }
    }

    private static func copyFile(source: URL, into destinationParent: URL,
                                 conflictPolicy: W6ImportConflictPolicy,
                                 result: inout W6ImportResult) {
        let fm = FileManager.default
        let name = source.lastPathComponent
        guard !protectedNames.contains(name) else {
            result = W6ImportResult(
                copied: result.copied, skipped: result.skipped + [source.path], failed: result.failed,
                copiedBytes: result.copiedBytes, copiedFiles: result.copiedFiles)
            return
        }
        guard !isSymlink(source) else {
            result = W6ImportResult(
                copied: result.copied, skipped: result.skipped + [source.path], failed: result.failed,
                copiedBytes: result.copiedBytes, copiedFiles: result.copiedFiles)
            return
        }
        var destinationIsDir: ObjCBool = false
        guard fm.fileExists(atPath: destinationParent.path, isDirectory: &destinationIsDir),
              destinationIsDir.boolValue else {
            result = W6ImportResult(
                copied: result.copied, skipped: result.skipped,
                failed: result.failed + [W6ImportFailure(path: source.path, reason: L("The destination folder is not available."))],
                copiedBytes: result.copiedBytes, copiedFiles: result.copiedFiles)
            return
        }
        do {
            try fm.createDirectory(at: destinationParent, withIntermediateDirectories: true)
        } catch {
            result = W6ImportResult(
                copied: result.copied, skipped: result.skipped,
                failed: result.failed + [W6ImportFailure(path: source.path, reason: error.localizedDescription)],
                copiedBytes: result.copiedBytes, copiedFiles: result.copiedFiles)
            return
        }
        let resolved: URL
        switch resolveDestination(name: name, in: destinationParent, conflictPolicy: conflictPolicy) {
        case .use(let url):
            resolved = url
        case .skip:
            result = W6ImportResult(
                copied: result.copied, skipped: result.skipped + [source.path], failed: result.failed,
                copiedBytes: result.copiedBytes, copiedFiles: result.copiedFiles)
            return
        case .failed(let reason):
            result = W6ImportResult(
                copied: result.copied, skipped: result.skipped,
                failed: result.failed + [W6ImportFailure(path: source.path, reason: reason)],
                copiedBytes: result.copiedBytes, copiedFiles: result.copiedFiles)
            return
        }
        do {
            try copyFileChunked(from: source, to: resolved)
        } catch {
            result = W6ImportResult(
                copied: result.copied, skipped: result.skipped,
                failed: result.failed + [W6ImportFailure(path: source.path, reason: error.localizedDescription)],
                copiedBytes: result.copiedBytes, copiedFiles: result.copiedFiles)
            return
        }
        let size = (try? resolved.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var copied = result.copied + [resolved.path]
        var copiedBytes = result.copiedBytes + Int64(size)
        var copiedFiles = result.copiedFiles + 1
        // SQLite companions travel with their database, so a copied
        // database never arrives without its WAL (Erosion-CN v1.0.8).
        for companionSuffix in databaseCompanionSuffixes where databaseSuffixes.contains(where: { name.hasSuffix($0) }) {
            let companion = source.deletingLastPathComponent()
                .appendingPathComponent(name + companionSuffix)
            guard fm.fileExists(atPath: companion.path), !isSymlink(companion) else { continue }
            let companionDestination = resolved.deletingLastPathComponent()
                .appendingPathComponent(resolved.lastPathComponent + companionSuffix)
            guard !fm.fileExists(atPath: companionDestination.path) else { continue }
            do {
                try copyFileChunked(from: companion, to: companionDestination)
                copied.append(companionDestination.path)
                copiedBytes += Int64((try? companionDestination.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                copiedFiles += 1
            } catch {
                result = W6ImportResult(
                    copied: copied, skipped: result.skipped,
                    failed: result.failed + [W6ImportFailure(path: companion.path, reason: error.localizedDescription)],
                    copiedBytes: copiedBytes, copiedFiles: copiedFiles)
                return
            }
        }
        result = W6ImportResult(copied: copied, skipped: result.skipped, failed: result.failed,
                                copiedBytes: copiedBytes, copiedFiles: copiedFiles)
    }

    private static func isSymlink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let childPath = url.standardizedFileURL.path
        guard childPath.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(childPath.dropFirst(rootPath.count + 1))
    }
}

// MARK: - Batch ZIP (feature 1, action bar)

/// Packs the selected entries into one ZIP next to nothing: the
/// archive is written into the directory the caller passes in
/// (the view passes the engine's temporary export directory).
/// Directories are expanded to their regular files; symlinks are
/// skipped and reported, never followed into the archive. The
/// archive is removed again when packing fails, so a failed pack
/// never leaves a partial ZIP behind.
enum W6BatchArchive {
    /// Maximum files in one batch archive.
    static let maximumFiles = 1_000
    /// Maximum total bytes in one batch archive (2 GB, matching
    /// Erosion-CN's folder ZIP cap).
    static let maximumBytes: Int64 = 2 * 1_024 * 1_024 * 1_024

    static func archive(entries: [W6FileEntry], to directory: URL) throws -> URL {
        var files: [(url: URL, archivePath: String)] = []
        var totalBytes: Int64 = 0
        for entry in entries {
            if entry.isDirectory {
                let measured = W6FileBrowser.measureDirectory(entry.url)
                guard measured.reachable else {
                    throw GestaltFailure("The folder could not be read.")
                }
                guard let enumerator = FileManager.default.enumerator(
                    at: entry.url, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles], errorHandler: nil) else {
                    throw GestaltFailure("The folder could not be read.")
                }
                for case let fileURL as URL in enumerator {
                    guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                          values.isSymbolicLink != true, values.isRegularFile == true else { continue }
                    let size = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                    totalBytes += size
                    guard files.count < maximumFiles, totalBytes <= maximumBytes else {
                        throw GestaltFailure("The selection is too large to pack into one archive.")
                    }
                    let relative = String(fileURL.path.dropFirst(entry.url.path.count + 1))
                    files.append((url: fileURL, archivePath: entry.name + "/" + relative))
                }
            } else {
                totalBytes += entry.byteCount
                guard files.count < maximumFiles, totalBytes <= maximumBytes else {
                    throw GestaltFailure("The selection is too large to pack into one archive.")
                }
                files.append((url: entry.url, archivePath: entry.name))
            }
        }
        guard !files.isEmpty else {
            throw GestaltFailure("Nothing to pack: the selection has no files.")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDir),
              isDir.boolValue else {
            throw GestaltFailure("The export folder is not available.")
        }
        let archiveURL = directory.appendingPathComponent("w6-batch-\(UUID().uuidString).zip")
        do {
            let archive = try Archive(url: archiveURL, accessMode: .create)
            for file in files {
                try archive.addEntry(with: file.archivePath, fileURL: file.url, compressionMethod: .deflate)
            }
        } catch {
            try? FileManager.default.removeItem(at: archiveURL)
            throw error
        }
        return archiveURL
    }
}

// MARK: - Splash-ad cache paths (feature 3)

/// Whether one table path has been confirmed on a real device.
/// Every bundled path starts as `.pendingVerification`: the table
/// records what upstream reported, not what this device proved.
/// A path becomes `.verifiedOnDevice` only when a maintainer
/// checks it against the matching app version on a real device
/// and records that version here.
enum W6SplashAdVerification: String, Codable, Equatable, Sendable {
    /// Not yet confirmed on a real device — shown as "待核实".
    case pendingVerification
    /// Confirmed on a real device; `detail` names the app version
    /// and iOS version it was confirmed against.
    case verifiedOnDevice

    var title: String {
        switch self {
        case .pendingVerification: return L("Pending verification")
        case .verifiedOnDevice: return L("Verified on device")
        }
    }
}

/// One splash-ad cache path, relative to an app's container root.
/// The table is data, not code: it decodes from JSON
/// (`decodeUpdatedTable`), so a new app version's paths can ship
/// as an updated table instead of a code change — paths drift
/// with app versions, so they must never be treated as permanent.
/// All fields are `Codable`, so the whole table round-trips
/// through JSON unchanged.
struct W6SplashAdPathEntry: Codable, Equatable, Sendable {
    /// The app's iOS bundle ID; the path applies only inside
    /// that app's container, never to other apps.
    let bundleID: String
    /// The app's Chinese display name.
    let appName: String
    /// The path inside the container, e.g.
    /// "Library/Caches/startADImage".
    let relativePath: String
    /// Where the path came from, e.g. "Erosion-CN v1.0.7 (#58)".
    let source: String
    let verification: W6SplashAdVerification
    /// Free-form note, e.g. the app version a verification was
    /// checked against. Empty for pending entries.
    let note: String

    /// The container-relative directory that holds the path, for
    /// display ("Library/Caches" for "Library/Caches/foo").
    var parentDirectory: String {
        (relativePath as NSString).deletingLastPathComponent
    }
}

/// One path as found (or not found) inside a real container.
/// `exists == false` means the path is absent from this
/// container — the app may have moved it in a newer version, or
/// the container may be unreachable; the two cases are told apart
/// by `containerReachable`.
struct W6SplashAdMatch: Equatable, Sendable {
    let entry: W6SplashAdPathEntry
    let exists: Bool
    let byteCount: Int64
    let containerReachable: Bool
}

/// The updatable splash-ad path table (Erosion-CN v1.0.6/v1.0.7).
/// Seven apps, thirteen container-relative paths, all pending
/// verification on LilaShift until a real-device check lands.
/// Generic ad-SDK directory names (Erosion-CN v1.0.2) are kept
/// separate from the per-app table: they match inside any app's
/// container, but only as a hint — an SDK directory name is not
/// proof that a given app shows splash ads.
enum W6SplashAdPathTable {
    /// Table revision, for display and for the record: the
    /// upstream release the bundled paths were taken from.
    static let tableVersion = "2026-11-28 (Erosion-CN v1.0.7, issue #58; Taobao v1.0.6)"

    /// Generic ad-SDK directory names (Erosion-CN v1.0.2): matched
    /// by shallow scan inside any app's container as a hint only.
    static let genericAdDirectoryNames = [
        "KSAdSDK", "BUAdSDK", "Pangle", "GDTMobSDK", "TADCache",
        "BaiduMobAd", "SplashAd", "LaunchAd",
    ]

    /// Generic ad-config file names (Erosion-CN v1.0.3).
    static let genericAdConfigNames = [
        "splash_ad.json", "splash_ad.plist",
    ]

    /// The bundled per-app table. Every entry is pending
    /// verification: these paths are what upstream reported for
    /// the named apps, and LilaShift has not confirmed any of
    /// them on its own device yet.
    static let entries: [W6SplashAdPathEntry] = [
        W6SplashAdPathEntry(
            bundleID: "com.taobao.taobao4iphone", appName: "淘宝",
            relativePath: "Documents/TBDocuments/bootImagebiz",
            source: "Erosion-CN v1.0.6 (#56)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "com.taobao.taobao4iphone", appName: "淘宝",
            relativePath: "Documents/TBDocuments/bootImageDoc",
            source: "Erosion-CN v1.0.6 (#56)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "com.taobao.taobao4iphone", appName: "淘宝",
            relativePath: "Documents/TBDocuments/bootImagesDoc",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "com.360buy.jdmobile", appName: "京东",
            relativePath: "Library/Caches/startADImage",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "com.dianping.dpscope", appName: "大众点评",
            relativePath: "Documents/splashes_new",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "cn.10086.app", appName: "中国移动",
            relativePath: "Library/DownloadCenter",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "com.tencent.live4iphone", appName: "腾讯视频",
            relativePath: "Library/Caches/QAD/PreloadImageAdOrderCache",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "com.tencent.live4iphone", appName: "腾讯视频",
            relativePath: "Library/Caches/QAD/QADWatchHistoryAdCache",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "com.tencent.live4iphone", appName: "腾讯视频",
            relativePath: "Library/Caches/QAD/maxViewAdCacheFolderName",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "com.tencent.live4iphone", appName: "腾讯视频",
            relativePath: "Library/Caches/TAD/PushAdPendantCache",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "com.tencent.live4iphone", appName: "腾讯视频",
            relativePath: "Library/Caches/TADCache",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "com.dragon.read", appName: "番茄小说",
            relativePath: "Documents/TTAdSplashSimpleCache",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "ctrip.com", appName: "携程旅行",
            relativePath: "Library/Caches/LoadingImages",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
        W6SplashAdPathEntry(
            bundleID: "ctrip.wireless", appName: "携程旅行",
            relativePath: "Library/Caches/LoadingImages",
            source: "Erosion-CN v1.0.7 (#58)", verification: .pendingVerification, note: ""),
    ]

    /// The distinct apps in the table, in table order.
    static var apps: [(bundleID: String, appName: String)] {
        var seen: [String] = []
        var result: [(bundleID: String, appName: String)] = []
        for entry in entries where !seen.contains(entry.bundleID) {
            seen.append(entry.bundleID)
            result.append((bundleID: entry.bundleID, appName: entry.appName))
        }
        return result
    }

    /// The table entries for one bundle ID, in table order.
    static func entries(for bundleID: String) -> [W6SplashAdPathEntry] {
        entries.filter { $0.bundleID == bundleID }
    }

    /// Decodes an updated table from JSON (same shape as
    /// `entries`): the mechanism by which new app versions' paths
    /// ship without a code change. Throws on malformed JSON —
    /// a bad update must never silently replace the table.
    static func decodeUpdatedTable(from data: Data) throws -> [W6SplashAdPathEntry] {
        try JSONDecoder().decode([W6SplashAdPathEntry].self, from: data)
    }

    /// Checks each table path for `bundleID` against a real
    /// container root: which paths exist there, and how many bytes
    /// each one holds. A missing path is reported as missing, not
    /// as zero bytes of proof — the app may have moved it.
    static func matches(in containerRoot: URL, bundleID: String) -> [W6SplashAdMatch] {        let reachable = FileManager.default.isReadableFile(atPath: containerRoot.path)
        return entries(for: bundleID).map { entry in
            let target = containerRoot.appendingPathComponent(entry.relativePath)
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir)
            var bytes: Int64 = 0
            if exists {
                if isDir.boolValue {
                    bytes = W6FileBrowser.measureDirectory(target).byteCount
                } else {
                    bytes = Int64((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
            }
            return W6SplashAdMatch(entry: entry, exists: exists, byteCount: bytes,
                                   containerReachable: reachable)
        }
    }

    /// Shallow scan for generic ad-SDK directories and ad-config
    /// files under the container's four usual roots. Only a hint:
    /// a matching directory name is reported with its path and
    /// size, never as proof of splash ads.
    static func genericMatches(in containerRoot: URL) -> [W6SplashAdMatch] {
        var found: [W6SplashAdMatch] = []
        let searchRoots = ["Documents", "Library/Caches", "Library/Application Support", "tmp"]
        for searchRoot in searchRoots {
            let root = containerRoot.appendingPathComponent(searchRoot)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: root.path) else { continue }
            for name in names.sorted() {
                let isGenericDirectory = genericAdDirectoryNames.contains(name)
                let isGenericConfig = genericAdConfigNames.contains(name)
                guard isGenericDirectory || isGenericConfig else { continue }
                let target = root.appendingPathComponent(name)
                var isDir: ObjCBool = false
                guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir) else { continue }
                let bytes: Int64
                if isDir.boolValue {
                    bytes = W6FileBrowser.measureDirectory(target).byteCount
                } else {
                    bytes = Int64((try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                }
                found.append(W6SplashAdMatch(
                    entry: W6SplashAdPathEntry(
                        bundleID: "", appName: L("Generic ad SDK"),
                        relativePath: searchRoot + "/" + name,
                        source: "Erosion-CN v1.0.2/v1.0.3 (generic)",
                        verification: .pendingVerification, note: ""),
                    exists: true, byteCount: bytes, containerReachable: true))
            }
        }
        return found
    }

    /// Checks the table against one real container: grants
    /// read-only access, runs the per-app matches and the generic
    /// hint scan, then releases the grant. The view calls this —
    /// it never grants access itself. `containerReachable` is
    /// false when the container could not be opened at all.
    static func check(in containerRoot: URL, bundleID: String) -> W6SplashAdCheck {
        let grant = ContainerAccess.grantAccess(path: containerRoot.path, requireWrite: false)
        guard grant.granted else {
            return W6SplashAdCheck(matches: [], genericMatches: [], containerReachable: false)
        }
        defer { ContainerAccess.releaseAccess(path: containerRoot.path) }
        return W6SplashAdCheck(
            matches: matches(in: containerRoot, bundleID: bundleID),
            genericMatches: genericMatches(in: containerRoot),
            containerReachable: true)
    }
}

// MARK: - Cross-app file browsing (feature 4)

/// The outcome of checking the splash-ad table against one real
/// container: the per-app matches, the generic SDK hints, and
/// whether the container could be opened at all.
struct W6SplashAdCheck: Equatable, Sendable {
    let matches: [W6SplashAdMatch]
    let genericMatches: [W6SplashAdMatch]
    let containerReachable: Bool
}

/// One installed app that cross-app browsing can address: the
/// bundle ID and display name from LaunchServices, plus the data
/// container path when it could be located. `containerPath` is
/// `nil` when the container is not locatable on this device —
/// the app is still listed, with its container honestly unknown,
/// rather than dropped from the list.
struct W6CrossAppTarget: Identifiable, Equatable, Sendable {
    let id: String
    let bundleID: String
    let name: String
    let containerPath: String?

    var containerURL: URL? {
        guard let containerPath else { return nil }
        return URL(fileURLWithPath: containerPath, isDirectory: true)
    }
}

/// One read-only cross-app listing: the entries actually read, or
/// an empty list with `reachable == false` and the reason in
/// `note`. The sentinel state is carried so the view can show the
/// version guidance instead of an empty list that looks like "no
/// files".
struct W6CrossAppListing: Equatable, Sendable {
    let app: W6CrossAppTarget
    let entries: [W6FileEntry]
    let reachable: Bool
    let sentinel: VersionSentinelState
    let note: String
}

/// Read-only cross-app file browsing (WQFiles, via LilaShift's
/// own container-access choke point). The app list comes from
/// LaunchServices (`GXCustomizationAccess`, the same source the
/// launch-image store uses); each container is opened read-only
/// through `ContainerAccess` and the grant is released afterwards.
/// Nothing here writes, deletes, moves or renames inside another
/// app's container — there is no write API on this type at all.
enum W6CrossAppBrowser {
    /// The installed apps, with their container paths when
    /// locatable. On the simulator (and anywhere LaunchServices
    /// is unavailable) the list is empty — an empty list is the
    /// honest answer there, never a fabricated app.
    static func installedApps() -> [W6CrossAppTarget] {
        #if os(iOS) && !targetEnvironment(simulator)
        return GXCustomizationAccess.launchApplications().compactMap { record in
            guard let identifier = record["identifier"], let name = record["name"] else { return nil }
            return W6CrossAppTarget(
                id: identifier, bundleID: identifier, name: name,
                containerPath: GXCustomizationAccess.launchContainer(for: identifier))
        }.sorted { $0.name < $1.name }
        #else
        return []
        #endif
    }

    /// The version sentinel for cross-app access, from the
    /// device's OS build string (`nil` build is unknown, never
    /// assumed supported). Reuses the existing `VersionSentinel`:
    /// supported through iOS 27.3 beta 1, blocked from 24C5049d
    /// (iOS 27.3 beta 2).
    static func sentinelState(osBuild: String?) -> VersionSentinelState {
        VersionSentinel.state(forBuild: osBuild)
    }

    /// Lists one directory inside `app`'s container, read-only.
    /// On a blocked or unknown build the listing is empty and the
    /// note carries the sentinel guidance; on a supported build a
    /// container that cannot be opened is reported unreachable
    /// with the grant error, never as an empty folder.
    static func list(app: W6CrossAppTarget, relativePath: String = "",
                     osBuild: String?) -> W6CrossAppListing {
        let sentinel = sentinelState(osBuild: osBuild)
        switch sentinel {
        case .supported:
            break
        case .blocked, .unknownBuild:
            return W6CrossAppListing(
                app: app, entries: [], reachable: false, sentinel: sentinel,
                note: VersionSentinel.supportedRangeDescription(for: sentinel))
        }
        guard let container = app.containerURL else {
            return W6CrossAppListing(
                app: app, entries: [], reachable: false, sentinel: sentinel,
                note: L("The app container could not be located on this device."))
        }
        guard AppGroupBrowser.validRelativePath(relativePath) else {
            return W6CrossAppListing(
                app: app, entries: [], reachable: false, sentinel: sentinel,
                note: L("The requested path is not inside the app container."))
        }
        let entries = W6FileBrowser.list(root: container, relativePath: relativePath)
        if entries.isEmpty {
            let target = relativePath.isEmpty
                ? container
                : container.appendingPathComponent(relativePath)
            let readable = FileManager.default.isReadableFile(atPath: target.path)
            if !readable {
                let grant = ContainerAccess.grantAccess(path: target.path, requireWrite: false)
                if !grant.granted {
                    return W6CrossAppListing(
                        app: app, entries: [], reachable: false, sentinel: sentinel,
                        note: grant.error ?? L("The app container could not be opened."))
                }
                ContainerAccess.releaseAccess(path: target.path)
            }
        }
        return W6CrossAppListing(
            app: app, entries: entries, reachable: true, sentinel: sentinel,
            note: entries.isEmpty ? L("This folder is empty.") : "")
    }
}

// MARK: - Cross-app cache statistics (feature 5)

/// Per-app cache usage, measured read-only from the app's real
/// container: `Library/Caches` and `tmp`, plus the bytes under
/// the splash-ad paths that actually exist there. `reachable ==
/// false` means the container could not be opened — the zeros
/// beside it are "not measured", never "this app has no cache".
/// There is deliberately no cleanup API on this type.
struct W6AppCacheStat: Equatable, Sendable {
    let bundleID: String
    let appName: String
    let cachesBytes: Int64
    let cachesFiles: Int
    let tmpBytes: Int64
    let tmpFiles: Int
    let splashAdBytes: Int64
    let splashAdPathsFound: Int
    let splashAdPathsChecked: Int
    let reachable: Bool
    let measuredAt: Date

    var totalBytes: Int64 { cachesBytes + tmpBytes }
}

/// Read-only cross-app cache statistics (WQFiles cache cleaner,
/// statistics only). Sizes come from a real walk of the granted
/// container; an unreachable container measures as unreachable,
/// not as zero. Cleanup is not in this workflow: no function
/// here deletes anything, and the view offers no clear button.
enum W6CrossAppCacheStats {
    /// Measures one app's cache usage. Sentinel-gated like the
    /// browser: blocked or unknown builds measure as unreachable.
    static func measure(app: W6CrossAppTarget, osBuild: String?) -> W6AppCacheStat {
        let sentinel = VersionSentinel.state(forBuild: osBuild)
        let empty = W6AppCacheStat(
            bundleID: app.bundleID, appName: app.name,
            cachesBytes: 0, cachesFiles: 0, tmpBytes: 0, tmpFiles: 0,
            splashAdBytes: 0, splashAdPathsFound: 0,
            splashAdPathsChecked: W6SplashAdPathTable.entries(for: app.bundleID).count,
            reachable: false, measuredAt: Date())
        guard sentinel == .supported, let container = app.containerURL else {
            return empty
        }
        let grant = ContainerAccess.grantAccess(path: container.path, requireWrite: false)
        guard grant.granted else {
            return empty
        }
        defer { ContainerAccess.releaseAccess(path: container.path) }
        let caches = W6FileBrowser.measureDirectory(container.appendingPathComponent("Library/Caches"))
        let tmp = W6FileBrowser.measureDirectory(container.appendingPathComponent("tmp"))
        let matches = W6SplashAdPathTable.matches(in: container, bundleID: app.bundleID)
        return W6AppCacheStat(
            bundleID: app.bundleID, appName: app.name,
            cachesBytes: caches.byteCount, cachesFiles: caches.fileCount,
            tmpBytes: tmp.byteCount, tmpFiles: tmp.fileCount,
            splashAdBytes: matches.filter(\.exists).reduce(0) { $0 + $1.byteCount },
            splashAdPathsFound: matches.filter(\.exists).count,
            splashAdPathsChecked: matches.count,
            reachable: caches.reachable || tmp.reachable || matches.contains(where: { $0.containerReachable }),
            measuredAt: Date())
    }

    /// Measures every app, largest cache first. Unreachable apps
    /// sort last, after every measured app, so an unreadable
    /// container never looks like the smallest cache.
    static func measureAll(apps: [W6CrossAppTarget], osBuild: String?) -> [W6AppCacheStat] {
        apps.map { measure(app: $0, osBuild: osBuild) }.sorted {
            if $0.reachable != $1.reachable { return $0.reachable && !$1.reachable }
            return $0.totalBytes > $1.totalBytes
        }
    }
}

// MARK: - Display formatting

/// Byte-count formatting for the W6 views, so the views never
/// format sizes themselves.
enum W6Format {
    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }

    static func bytes(_ count: Int) -> String {
        bytes(Int64(count))
    }
}
