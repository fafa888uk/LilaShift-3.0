// SPDX-License-Identifier: GPL-3.0-only
// Cache analysis (Stage 7, DATA_MODELS §4.3, TASKBOOK §6.3).
//
// The ONE cache-measurement implementation in the app. It
// enumerates the app's OWN container directories (Application
// Support, Caches, tmp) into per-file entries with real sizes and
// real last-access times, and decides per file whether it is safe
// to delete. `AppContainerCacheMeasurer` (DiagnosticsExpansion)
// now delegates here; there is no second measurement loop.
//
// Protection: Application Support data is never cache, so its
// entries are never deletable. Inside Caches/tmp, files whose names
// look like chat libraries, login state, keychains, accounts or
// credentials are protected too — deletion is the destructive
// direction, so suspicion protects. Deletion only ever touches
// entries this module produced (tracked items), checks
// deletability first, and reports what it deleted, skipped and
// failed. `lastAccessed` is the system's content-access date when
// the system provides one, and `nil` otherwise — an unknown access
// time is shown as unknown, never invented.
import Foundation

/// Which of the app's own container directories a cache entry
/// lives in.
enum CacheCategory: String, Codable, CaseIterable, Sendable {
    case caches
    case tmp
    case other

    var title: String {
        switch self {
        case .caches: return L("Caches")
        case .tmp: return L("Temporary")
        case .other: return L("Application Support")
        }
    }
}

/// One file in a cache report (DATA_MODELS §4.3).
struct CacheEntry: Equatable, Hashable, Sendable {
    var relativePath: String
    var size: Int
    /// The system's content-access date, or `nil` when the system
    /// does not provide one. Never invented.
    var lastAccessed: Date?
    var category: CacheCategory
    var safeToDelete: Bool
    /// Required when `safeToDelete` is false.
    var protectionReason: String?
}

/// A cache report (DATA_MODELS §4.3).
struct CacheReport: Equatable, Sendable {
    var totalSize: Int
    var entries: [CacheEntry]
    var measuredAt: Date

    var totalFiles: Int { entries.count }
    var deletableBytes: Int { entries.filter { $0.safeToDelete }.reduce(0) { $0 + $1.size } }
    var deletableFiles: Int { entries.filter { $0.safeToDelete }.count }

    func entries(for category: CacheCategory) -> [CacheEntry] {
        entries.filter { $0.category == category }
    }
}

/// One file that could not be deleted, with the reason.
struct CacheDeletionFailure: Sendable {
    var path: String
    var reason: String
}

/// The result of deleting tracked cache entries. Deletion is never
/// reported as a bare success: deleted, skipped-protected and
/// failed items are all listed.
struct CacheDeletionReport: Sendable {
    var deleted: [String]
    var skippedProtected: [String]
    var failed: [CacheDeletionFailure]
    var freedBytes: Int
}

enum CacheAnalyzer {
    /// File-name fragments that mark a file as protected even inside
    /// Caches/tmp: chat libraries, messages, login state, keychains,
    /// accounts, credentials, tokens and passwords. The match is
    /// deliberately broad — a false positive only costs a missed
    /// deletion, while a false negative could destroy user data.
    static let protectedNameFragments = [
        "chat", "message", "login", "keychain", "account",
        "credential", "token", "password", "documents",
    ]

    /// Analyzes the app's own container directories. Read-only:
    /// nothing is created, moved or deleted. Missing directories
    /// measure as zero, never an error.
    static func analyzeContainer() -> CacheReport {
        analyze(
            applicationSupport: AppDirectories.applicationSupport,
            caches: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
            temporary: FileManager.default.temporaryDirectory)
    }

    /// Analyzes three injected directories. The URLs are injected
    /// so tests can analyze a temporary directory; the production
    /// caller passes the real container URLs (see
    /// `analyzeContainer`).
    static func analyze(applicationSupport: URL, caches: URL, temporary: URL) -> CacheReport {
        var entries: [CacheEntry] = []
        entries += scan(root: applicationSupport, category: .other)
        entries += scan(root: caches, category: .caches)
        entries += scan(root: temporary, category: .tmp)
        entries.sort { $0.size > $1.size }
        return CacheReport(
            totalSize: entries.reduce(0) { $0 + $1.size },
            entries: entries, measuredAt: Date())
    }

    /// The pure per-file mapping: size, access date and category in,
    /// protection decision out. Kept pure so the protection rules
    /// are unit-testable without touching the file system.
    static func makeEntry(relativePath: String, size: Int, lastAccessed: Date?,
                          category: CacheCategory) -> CacheEntry {
        switch category {
        case .other:
            // Application Support holds the app's real data (backup
            // vault, customization storage, launch images). It is
            // not cache, so nothing in it is ever deletable here.
            return CacheEntry(
                relativePath: relativePath, size: size, lastAccessed: lastAccessed,
                category: category, safeToDelete: false,
                protectionReason: L("Application Support data is not cache."))
        case .caches, .tmp:
            let lowercased = relativePath.lowercased()
            if protectedNameFragments.contains(where: { lowercased.contains($0) }) {
                return CacheEntry(
                    relativePath: relativePath, size: size, lastAccessed: lastAccessed,
                    category: category, safeToDelete: false,
                    protectionReason: L("Protected: looks like chat, login or account data."))
            }
            return CacheEntry(
                relativePath: relativePath, size: size, lastAccessed: lastAccessed,
                category: category, safeToDelete: true, protectionReason: nil)
        }
    }

    /// The production container roots, for callers (views) that
    /// must not resolve file-system paths themselves — see
    /// ModuleBoundaryTests.testViewsDoNotReadFilesDirectly.
    static func containerRoots() -> (applicationSupport: URL, caches: URL, temporary: URL) {
        (AppDirectories.applicationSupport,
         FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0],
         FileManager.default.temporaryDirectory)
    }

    /// Deletes tracked entries from the production container roots.
    static func deleteTracked(_ entries: [CacheEntry]) throws -> CacheDeletionReport {
        let roots = containerRoots()
        return try deleteTracked(
            entries, applicationSupport: roots.applicationSupport,
            caches: roots.caches, temporary: roots.temporary)
    }

    /// Clears the app's OWN Caches directory (production path).
    static func clearContainerCaches() throws -> Int64 {
        try clearCaches(at: containerRoots().caches)
    }

    /// Deletes ONLY the entries given (tracked items from a report
    /// this module produced). Protected entries are refused and
    /// listed as skipped; each file's deletability is checked before
    /// removal; a resolved path that escapes its root is refused.
    /// Returns what was deleted, skipped and failed, plus the bytes
    /// freed.
    static func deleteTracked(_ entries: [CacheEntry],
                              applicationSupport: URL, caches: URL, temporary: URL) throws -> CacheDeletionReport {
        var deleted: [String] = []
        var skippedProtected: [String] = []
        var failed: [CacheDeletionFailure] = []
        var freedBytes = 0
        for entry in entries {
            if !entry.safeToDelete {
                skippedProtected.append(entry.relativePath)
                continue
            }
            do {
                let root = rootURL(for: entry.category, applicationSupport: applicationSupport,
                                   caches: caches, temporary: temporary)
                let target = try CustomizationFiles.checked(entry.relativePath, in: root)
                guard FileManager.default.isDeletableFile(atPath: target.path) else {
                    throw GestaltFailure("The file cannot be deleted.")
                }
                let size = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? entry.size
                try FileManager.default.removeItem(at: target)
                deleted.append(entry.relativePath)
                freedBytes += size
            } catch {
                failed.append(CacheDeletionFailure(path: entry.relativePath, reason: error.localizedDescription))
            }
        }
        return CacheDeletionReport(
            deleted: deleted, skippedProtected: skippedProtected,
            failed: failed, freedBytes: freedBytes)
    }

    /// Clears the app's OWN Caches directory: removes its contents,
    /// never the directory itself, and returns the bytes freed.
    /// Refuses any URL whose last component is not "Caches", so a
    /// wrong URL can never delete another directory. System caches
    /// are never touched.
    static func clearCaches(at cachesURL: URL) throws -> Int64 {
        guard cachesURL.lastPathComponent == "Caches" else {
            throw GestaltFailure("Refusing to clear a directory that is not the app's Caches directory.")
        }
        let before = analyze(caches: cachesURL)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: cachesURL, includingPropertiesForKeys: nil)) ?? []
        for item in contents {
            try FileManager.default.removeItem(at: item)
        }
        let after = analyze(caches: cachesURL)
        guard after.totalFiles == 0 else {
            throw GestaltFailure("The app cache could not be cleared.")
        }
        return Int64(before.totalSize - after.totalSize)
    }

    // MARK: - Private helpers

    private static func rootURL(for category: CacheCategory, applicationSupport: URL,
                                caches: URL, temporary: URL) -> URL {
        switch category {
        case .caches: return caches
        case .tmp: return temporary
        case .other: return applicationSupport
        }
    }

    private static func scan(root: URL, category: CacheCategory) -> [CacheEntry] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentAccessDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles], errorHandler: nil) else {
            return []
        }
        var entries: [CacheEntry] = []
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let relativePath = relativePath(of: fileURL, under: root)
            // Refuse any path that passes through a symlink
            // component, so a symlinked directory inside a cache
            // root can never pull outside files into the report.
            guard (try? CustomizationFiles.checked(relativePath, in: root)) != nil else { continue }
            entries.append(makeEntry(
                relativePath: relativePath, size: values.fileSize ?? 0,
                lastAccessed: values.contentAccessDate, category: category))
        }
        return entries
    }

    /// Single-root analysis used by `clearCaches` for its
    /// before/after totals.
    private static func analyze(caches: URL) -> CacheReport {
        let entries = scan(root: caches, category: .caches)
        return CacheReport(
            totalSize: entries.reduce(0) { $0 + $1.size },
            entries: entries, measuredAt: Date())
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let childPath = url.standardizedFileURL.path
        guard childPath.hasPrefix(rootPath + "/") else { return url.lastPathComponent }
        return String(childPath.dropFirst(rootPath.count + 1))
    }
}
